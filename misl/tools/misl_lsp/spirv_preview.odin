package misl_lsp

import "core:encoding/json"
import "core:strings"
import "oge:misl"
import "./lsp"

SPIRV_Preview_Cache :: struct {
	uri:         string,
	entity_name: string,
	spirv:       string,
	line:        int,
	character:   int,
}

spirv_preview_cache: SPIRV_Preview_Cache

spirv_preview_cache_clear :: proc() {
	delete(spirv_preview_cache.uri)
	delete(spirv_preview_cache.entity_name)
	delete(spirv_preview_cache.spirv)
	spirv_preview_cache = {}
}

entity_is_gpu_entry :: proc(e: ^misl.Entity) -> bool {
	if e == nil || misl.entity_is_fmag(e) {
		return false
	}
	if e.type != nil {
		if pt, ok := e.type.derived.(^misl.Type_Proc); ok {
			if pt.is_fmag {
				return false
			}
			if _, has := pt.stage.?; has {
				return true
			}
		}
	}
	if e.proc_lit != nil && e.proc_lit.type != nil {
		_, ok := misl.entry_kind_from_calling_convention(e.proc_lit.type.calling_convention)
		return ok && !strings.has_prefix(e.proc_lit.type.calling_convention, "fmag")
	}
	return false
}

spirv_preview_request :: proc(ws: ^Workspace, params: json.Value, allocator := context.allocator) -> (result: json.Value, error: Maybe(lsp.Response_Error)) {
	uri: string
	entity_name: string
	uri_ok, name_ok: bool

	if obj, ok := params.(json.Object); ok {
		uri_v := obj["uri"] or_else nil
		name_v := obj["entity"] or_else nil
		uri, uri_ok = uri_v.(json.String)
		entity_name, name_ok = name_v.(json.String)
	} else if arr, is_arr := params.(json.Array); is_arr && len(arr) >= 2 {
		uri, uri_ok = arr[0].(json.String)
		entity_name, name_ok = arr[1].(json.String)
	}
	if !uri_ok || !name_ok || uri == "" || entity_name == "" {
		return nil, lsp.Response_Error{code = .Invalid_Params, message = "expected uri and entity"}
	}

	mod := workspace_module_for_uri(ws, uri)
	if mod == nil {
		return nil, lsp.Response_Error{code = .Unknown_Error_Code, message = "module not found"}
	}

	entity := preview_find_entity(mod, entity_name)
	if entity == nil {
		return nil, lsp.Response_Error{code = .Unknown_Error_Code, message = "entity not found"}
	}
	if misl.entity_is_fmag(entity) {
		return nil, lsp.Response_Error{code = .Unknown_Error_Code, message = "proc \"fmag\" has no SPIR-V preview"}
	}

	doc := ws.docs[uri] or_else nil
	parsed := ws.modules_by_path[doc.path] if doc != nil else misl.module_parsed_origin(mod)
	emit_mod := workspace_check_parsed(ws, parsed, ws.target)
	if emit_mod == nil {
		return nil, lsp.Response_Error{code = .Unknown_Error_Code, message = "failed to check entity"}
	}
	emit_entry := misl.find_entry_with_name(emit_mod, entity_name)
	if emit_entry == nil {
		return nil, lsp.Response_Error{code = .Unknown_Error_Code, message = "entry not found after check"}
	}

	text: string
	if spirv_preview_cache.uri == uri && spirv_preview_cache.entity_name == entity_name && spirv_preview_cache.spirv != "" {
		text = spirv_preview_cache.spirv
	} else {
		diags: [dynamic]misl.Diagnostic
		preview := workspace_target_spirv_preview(ws)
		r, ok := misl.compile_entry(emit_entry, preview, misl.Compile_Options{
			allocator = allocator,
			diags = &diags,
		})
		if !ok || r.spirv_asm == "" {
			msg := "SPIR-V emit failed"
			if len(diags) > 0 {
				msg = diags[0].message
			}
			return nil, lsp.Response_Error{code = .Unknown_Error_Code, message = msg}
		}
		emitted := strings.clone(r.spirv_asm, allocator)
		delete(spirv_preview_cache.uri)
		delete(spirv_preview_cache.entity_name)
		delete(spirv_preview_cache.spirv)
		spirv_preview_cache.uri = strings.clone(uri)
		spirv_preview_cache.entity_name = strings.clone(entity_name)
		spirv_preview_cache.spirv = strings.clone(emitted)
		text = spirv_preview_cache.spirv
	}

	search := emit_entry.name
	line, character := find_ident_line_col(text, search)

	delete(spirv_preview_cache.entity_name)
	spirv_preview_cache.entity_name = strings.clone(entity_name)
	spirv_preview_cache.line = line
	spirv_preview_cache.character = character

	out := make(json.Object, allocator)
	out["spirv"] = text
	out["line"] = i64(line)
	out["character"] = i64(character)
	out["entity"] = entity_name
	out["search"] = search
	return out, nil
}
