package misl_lsp

import "oge:misl"
import "./lsp"

definition_at :: proc(ws: ^Workspace, params: lsp.Definition_Params, allocator := context.temp_allocator) -> []lsp.Location {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil do return nil
	offset, ok := offset_from_position(doc.text, params.position)
	if !ok do return nil
	mod := workspace_module_for_uri(ws, params.text_document.uri, offset)
	if mod == nil do return nil

	hit := ast_find_at_offset(mod, offset)

	e: ^misl.Entity
	uri := params.text_document.uri
	text := doc.text
	pos: misl.Token_Pos
	name_len := 1

	if hit.ident != nil && hit.ident.entity != nil {
		e = hit.ident.entity
	} else if hit.entity != nil {
		e = hit.entity
	} else if hit.entity_name_len > 0 {
		// Package decl (self location)
		locs := make([]lsp.Location, 1, allocator)
		locs[0] = {
			uri = uri,
			range = token_pos_to_range(hit.entity_pos, hit.entity_name_len, text),
		}
		return locs
	} else {
		return nil
	}

	for e.aliased_of != nil {
		e = e.aliased_of
	}

	pos = e.pos
	name_len = max(len(e.name), 1)

	// Import entity → jump into the imported module when available.
	if e.kind == .Import && e.imported_module != nil && e.imported_module.fullpath != "" {
		target := e.imported_module
		target_doc := workspace_doc_for_path(ws, target.fullpath)
		if target_doc != nil {
			uri = target_doc.uri
			text = target_doc.text
		} else {
			uri = lsp.filepath_to_uri(target.fullpath, allocator)
			text = target.code
		}
		pos = {offset = 0, line = 1, column = 1, file = target.fullpath}
		name_len = 1
	} else if e.module != nil && e.module.fullpath != "" {
		target_doc := workspace_doc_for_path(ws, e.module.fullpath)
		if target_doc != nil {
			uri = target_doc.uri
			text = target_doc.text
		} else {
			uri = lsp.filepath_to_uri(e.module.fullpath, allocator)
			text = e.module.code
		}
	}

	locs := make([]lsp.Location, 1, allocator)
	locs[0] = {
		uri = uri,
		range = token_pos_to_range(pos, name_len, text),
	}
	return locs
}
