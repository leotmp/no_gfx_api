package misl_lsp

import "core:slice"
import "oge:misl"
import "./lsp"

rename_at :: proc(ws: ^Workspace, params: lsp.Rename_Params) -> Maybe(lsp.Workspace_Edit) {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil do return nil
	offset, ok := offset_from_position(doc.text, params.position)
	if !ok do return nil
	mod := workspace_module_for_uri(ws, params.text_document.uri, offset)
	if mod == nil do return nil

	hit := ast_find_at_offset(mod, offset)
	if hit.ident == nil || hit.ident.entity == nil do return nil
	entity := hit.ident.entity

	by_uri := make(map[string][dynamic]lsp.Text_Edit, context.temp_allocator)
	for _, d in ws.docs {
		m := workspace_checked_like(ws, d.uri, mod)
		if m == nil do continue
		idents := make([dynamic]^misl.Ident, context.temp_allocator)
		ast_collect_idents_for_entity(m, entity, &idents)
		for ident in idents {
			if d.uri not_in by_uri {
				by_uri[d.uri] = make([dynamic]lsp.Text_Edit, context.temp_allocator)
			}
			edits := &by_uri[d.uri]
			append(edits, lsp.Text_Edit{
				range = ident_range(ident, d.text),
				new_text = params.new_name,
			})
		}
	}

	doc_edits := make([dynamic]lsp.Text_Document_Edit, context.temp_allocator)
	for uri, edits in by_uri {
		append(&doc_edits, lsp.Text_Document_Edit{
			textDocument = {uri = uri, version = nil},
			edits = slice.clone(edits[:], context.temp_allocator),
		})
	}
	if len(doc_edits) == 0 do return nil
	return lsp.Workspace_Edit{documentChanges = doc_edits[:]}
}

prepare_rename_at :: proc(ws: ^Workspace, params: lsp.Prepare_Rename_Params) -> Maybe(lsp.Range) {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil do return nil
	offset, ok := offset_from_position(doc.text, params.position)
	if !ok do return nil
	mod := workspace_module_for_uri(ws, params.text_document.uri, offset)
	if mod == nil do return nil

	hit := ast_find_at_offset(mod, offset)
	if hit.ident == nil || hit.ident.entity == nil do return nil
	return ident_range(hit.ident, doc.text)
}
