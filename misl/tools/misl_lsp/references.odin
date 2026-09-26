package misl_lsp

import "oge:misl"
import "./lsp"

references_at :: proc(ws: ^Workspace, params: lsp.Reference_Params, allocator := context.temp_allocator) -> []lsp.Location {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil do return nil
	offset, ok := offset_from_position(doc.text, params.position)
	if !ok do return nil
	mod := workspace_module_for_uri(ws, params.text_document.uri, offset)
	if mod == nil do return nil

	hit := ast_find_at_offset(mod, offset)
	if hit.ident == nil || hit.ident.entity == nil do return nil
	entity := hit.ident.entity

	locs := make([dynamic]lsp.Location, allocator)
	for _, d in ws.docs {
		m := workspace_checked_like(ws, d.uri, mod)
		if m == nil do continue
		idents := make([dynamic]^misl.Ident, context.temp_allocator)
		ast_collect_idents_for_entity(m, entity, &idents)
		for ident in idents {
			append(&locs, lsp.Location{
				uri = d.uri,
				range = ident_range(ident, d.text),
			})
		}
	}
	return locs[:]
}

document_highlights_at :: proc(ws: ^Workspace, params: lsp.Document_Highlight_Params, allocator := context.temp_allocator) -> []lsp.Document_Highlight {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil do return nil
	offset, ok := offset_from_position(doc.text, params.position)
	if !ok do return nil
	mod := workspace_module_for_uri(ws, params.text_document.uri, offset)
	if mod == nil do return nil

	hit := ast_find_at_offset(mod, offset)
	if hit.ident == nil || hit.ident.entity == nil do return nil

	idents := make([dynamic]^misl.Ident, context.temp_allocator)
	ast_collect_idents_for_entity(mod, hit.ident.entity, &idents)

	out := make([]lsp.Document_Highlight, len(idents), allocator)
	for ident, i in idents {
		out[i] = {
			range = ident_range(ident, doc.text),
			kind = .Text,
		}
	}
	return out
}
