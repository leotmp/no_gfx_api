package misl_lsp

import "core:encoding/json"
import "core:strings"
import "oge:misl"
import "./lsp"

Fmag_Preview_Cache :: struct {
	uri:         string,
	entity_name: string,
	fmag:        string,
	line:        int,
	character:   int,
}

fmag_preview_cache: Fmag_Preview_Cache

fmag_preview_cache_clear :: proc() {
	delete(fmag_preview_cache.uri)
	delete(fmag_preview_cache.entity_name)
	delete(fmag_preview_cache.fmag)
	fmag_preview_cache = {}
}

fmag_preview_request :: proc(ws: ^Workspace, params: json.Value, allocator := context.allocator) -> (result: json.Value, error: Maybe(lsp.Response_Error)) {
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

	doc := ws.docs[uri] or_else nil
	if doc == nil {
		return nil, lsp.Response_Error{code = .Unknown_Error_Code, message = "module not found"}
	}
	parsed := ws.modules_by_path[doc.path]
	mod := workspace_check_parsed(ws, parsed, workspace_target_fmag(ws))
	if mod == nil {
		return nil, lsp.Response_Error{code = .Unknown_Error_Code, message = "module not found"}
	}

	entry := misl.find_entry_with_name(mod, entity_name)
	if entry == nil || !misl.entry_is_fmag(entry) {
		return nil, lsp.Response_Error{code = .Invalid_Params, message = "entity is not proc \"fmag\""}
	}

	text: string
	if fmag_preview_cache.uri == uri && fmag_preview_cache.entity_name == entity_name && fmag_preview_cache.fmag != "" {
		text = fmag_preview_cache.fmag
	} else {
		emitted, emit_ok := misl.emit_fmag_asm(entry, allocator)
		if !emit_ok || emitted == "" {
			return nil, lsp.Response_Error{code = .Unknown_Error_Code, message = "FMAG emit failed"}
		}
		delete(fmag_preview_cache.uri)
		delete(fmag_preview_cache.entity_name)
		delete(fmag_preview_cache.fmag)
		fmag_preview_cache.uri = strings.clone(uri)
		fmag_preview_cache.entity_name = strings.clone(entity_name)
		fmag_preview_cache.fmag = strings.clone(emitted)
		text = fmag_preview_cache.fmag
	}

	search := entry.name
	line, character := find_ident_line_col(text, search)

	fmag_preview_cache.line = line
	fmag_preview_cache.character = character

	out := make(json.Object, allocator)
	out["fmag"] = text
	out["line"] = i64(line)
	out["character"] = i64(character)
	out["entity"] = entity_name
	out["search"] = search
	return out, nil
}
