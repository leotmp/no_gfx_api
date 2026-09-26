package misl_lsp

import "core:log"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "oge:misl"
import "./lsp"

Document :: struct {
	uri:     string,
	path:    string, // filesystem
	text:    string, // cloned
	version: int,
}

Workspace :: struct {
	docs:            map[string]^Document, // key uri
	collections:     map[string]string,
	session:         ^misl.Session,
	modules_by_path: map[string]^misl.Module, // after recheck
	root_path:       string,
	debounce_ms:     int, // default 200; coalesces didChange until next request
	dirty:           bool,
	recheck_after:   time.Tick,
	server:          ^lsp.Server,
	config:          Lsp_Config,
	features:        Lsp_Features,
	using_lsp_json:  bool, // true when misl.lsp.json is the active config source
	load_opts:       misl.Load_Options,
	target:          misl.Target,
	compile_opts:    misl.Compile_Options,
}

workspace: Workspace

workspace_init :: proc(ws: ^Workspace, server: ^lsp.Server) {
	ws^ = {}
	ws.docs = make(map[string]^Document)
	ws.collections = make(map[string]string)
	ws.modules_by_path = make(map[string]^misl.Module)
	ws.debounce_ms = 200
	ws.server = server
	ws.config = default_lsp_config()
	ws.features = ws.config.features
	ws.target = {
		formats = {.spirv},
		flags = {.Debug, .Named_Entry},
	}
	ws.load_opts = {
		soft_fail = true,
	}
	ws.compile_opts = {
		allocator = context.temp_allocator,
	}
}

workspace_destroy :: proc(ws: ^Workspace) {
	if ws.session != nil {
		misl.destroy_session(ws.session)
		ws.session = nil
	}
	for _, doc in ws.docs {
		delete(doc.uri)
		delete(doc.path)
		delete(doc.text)
		free(doc)
	}
	clear(&ws.docs)
	clear(&ws.modules_by_path)
	for k, v in ws.collections {
		delete(k)
		delete(v)
	}
	clear(&ws.collections)
	if ws.config.server_path != "" {
		delete(ws.config.server_path)
	}
	delete(ws.root_path)
}

// Mark documents dirty; recheck is deferred until the next LSP request (coalesces bursts).
workspace_mark_dirty :: proc(ws: ^Workspace) {
	ws.dirty = true
	delay := time.Duration(ws.debounce_ms) * time.Millisecond
	if ws.debounce_ms <= 0 {
		delay = 0
	}
	ws.recheck_after = time.tick_add(time.tick_now(), delay)
}

workspace_flush :: proc(ws: ^Workspace) {
	if !ws.dirty do return
	ws.dirty = false
	workspace_recheck(ws)
}

document_open :: proc(ws: ^Workspace, params: lsp.Did_Open_Text_Document_Params) {
	uri := params.text_document.uri
	path, path_ok := lsp.uri_to_filepath(uri)
	if !path_ok {
		log.errorf("didOpen: bad uri %s", uri)
		return
	}
	cleaned, _ := filepath.clean(path, context.allocator)
	delete(path)

	if existing, ok := ws.docs[uri]; ok {
		delete(existing.text)
		existing.text = strings.clone(params.text_document.text)
		existing.version = params.text_document.version
		if existing.path != cleaned {
			delete(existing.path)
			existing.path = cleaned
		} else {
			delete(cleaned)
		}
	} else {
		doc := new(Document)
		doc.uri = strings.clone(uri)
		doc.path = cleaned
		doc.text = strings.clone(params.text_document.text)
		doc.version = params.text_document.version
		ws.docs[doc.uri] = doc
	}
	ws.dirty = false
	workspace_recheck(ws)
}

document_change :: proc(ws: ^Workspace, params: lsp.Did_Change_Text_Document_Params) {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil {
		log.warnf("didChange for unknown document %s", params.text_document.uri)
		return
	}
	doc.version = params.text_document.version
	// Full sync: last change carries entire text
	if len(params.content_changes) > 0 {
		last := params.content_changes[len(params.content_changes) - 1]
		delete(doc.text)
		doc.text = strings.clone(last.text)
	}
	workspace_mark_dirty(ws)
}

document_close :: proc(ws: ^Workspace, params: lsp.Did_Close_Text_Document_Params) {
	uri := params.text_document.uri
	doc := ws.docs[uri] or_else nil
	if doc == nil do return
	publish_diagnostics_clear(ws, uri)
	delete_key(&ws.docs, uri)
	delete(doc.uri)
	delete(doc.path)
	delete(doc.text)
	free(doc)
	ws.dirty = false
	workspace_recheck(ws)
}

document_save :: proc(ws: ^Workspace, params: lsp.Did_Save_Text_Document_Params) {
	if text, has := params.text.?; has {
		if doc, ok := ws.docs[params.text_document.uri]; ok {
			delete(doc.text)
			doc.text = strings.clone(text)
			ws.dirty = false
			workspace_recheck(ws)
		}
	}
}

workspace_scope_entity :: proc(mod: ^misl.Module, name: string) -> ^misl.Entity {
	if mod == nil || mod.scope == nil || name == "" do return nil
	return mod.scope.entities[name] or_else nil
}

workspace_find_named_entity :: proc(ws: ^Workspace, name: string) -> ^misl.Entity {
	if ws == nil || name == "" do return nil
	workspace_flush(ws)
	if ws.session != nil {
		for _, inst in ws.session.check_cache {
			if inst == nil || inst.kind == .Builtin do continue
			if e := workspace_scope_entity(inst, name); e != nil {
				return e
			}
		}
	}
	for _, parsed in ws.modules_by_path {
		inst := workspace_check_parsed(ws, parsed, ws.target)
		if inst == nil || inst.kind == .Builtin do continue
		if e := workspace_scope_entity(inst, name); e != nil {
			return e
		}
	}
	if ws.session != nil {
		for _, inst in ws.session.check_cache {
			if e := workspace_scope_entity(inst, name); e != nil {
				return e
			}
		}
	}
	return nil
}

workspace_module_for_uri :: proc(ws: ^Workspace, uri: string, offset := -1) -> ^misl.Module {
	workspace_flush(ws)
	doc := ws.docs[uri] or_else nil
	if doc == nil do return nil
	parsed := ws.modules_by_path[doc.path]
	if parsed == nil do return nil
	target := ws.target
	if offset >= 0 {
		mode := misl.compile_mode_from_cursor(parsed, offset)
		target = misl.target_for_mode(ws.target, mode)
	}
	return workspace_check_parsed(ws, parsed, target)
}

workspace_check_parsed :: proc(ws: ^Workspace, parsed: ^misl.Module, target: misl.Target) -> ^misl.Module {
	if parsed == nil do return nil
	opts := ws.load_opts
	opts.soft_fail = true
	opts.err = collect_error_handler
	opts.warn = collect_warning_handler
	return misl.check(parsed, target, opts)
}

workspace_target_fmag :: proc(ws: ^Workspace) -> misl.Target {
	return misl.target_for_mode(ws.target, .FMAG)
}

workspace_target_spirv_preview :: proc(ws: ^Workspace) -> misl.Target {
	t := ws.target
	t.formats = {.spirv_asm}
	t.opt = .None
	t.flags += {.Debug, .No_Source, .Named_Entry}
	return t
}

workspace_checked_like :: proc(ws: ^Workspace, uri: string, like: ^misl.Module) -> ^misl.Module {
	workspace_flush(ws)
	doc := ws.docs[uri] or_else nil
	if doc == nil do return nil
	parsed := ws.modules_by_path[doc.path]
	if parsed == nil || like == nil do return nil
	return workspace_check_parsed(ws, parsed, misl.target_for_mode(ws.target, like.check_mode))
}

workspace_doc_for_path :: proc(ws: ^Workspace, path: string) -> ^Document {
	cleaned, _ := filepath.clean(path, context.temp_allocator)
	for _, doc in ws.docs {
		if strings.equal_fold(doc.path, cleaned) {
			return doc
		}
	}
	return nil
}

// Editor overlay: parent folder named `core` (repo `oge/misl/core`, or VSIX `server/core`).
lsp_path_in_core_folder :: proc(path: string) -> bool {
	if path == "" do return false
	cleaned, _ := filepath.clean(path, context.temp_allocator)
	parent := filepath.dir(cleaned)
	return strings.equal_fold(filepath.base(parent), "core")
}

workspace_recheck :: proc(ws: ^Workspace) {
	clear(&ws.modules_by_path)
	fmag_preview_cache_clear()
	spirv_preview_cache_clear()

	if ws.session != nil {
		misl.destroy_session(ws.session)
		ws.session = nil
	}
	cols := make([dynamic]misl.Collection, context.temp_allocator)
	for name, path in ws.collections {
		append(&cols, misl.Collection{name = name, path = path})
	}
	ws.session = misl.create_session({collections = cols[:]})

	diags: [dynamic]misl.Diagnostic
	diags.allocator = context.temp_allocator
	begin_diag_collection(&diags)
	defer end_diag_collection()

	opts := ws.load_opts
	opts.soft_fail = true
	opts.err = collect_error_handler
	opts.warn = collect_warning_handler

	// Load open documents (path key so imports resolve) — parse only.
	for _, doc in ws.docs {
		load_opts := opts
		load_opts.compiler_core = lsp_path_in_core_folder(doc.path)
		mod := misl.load_module_from_memory_opts(ws.session, doc.path, doc.text, from_file = true, opts = load_opts)
		if mod != nil {
			ws.modules_by_path[doc.path] = mod
		}
	}

	for _, mod in ws.session.modules {
		if mod == nil || mod.kind != .Normal || mod.fullpath == "" do continue
		ws.modules_by_path[mod.fullpath] = mod
	}

	for _, doc in ws.docs {
		parsed := ws.modules_by_path[doc.path]
		if parsed == nil do continue
		_ = misl.check_for_diagnostics(parsed, ws.target, opts)
	}

	publish_workspace_diagnostics(ws, diags[:])
}
