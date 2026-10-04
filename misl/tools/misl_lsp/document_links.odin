package misl_lsp

import "core:path/filepath"
import "oge:misl"
import "./lsp"

// Document links for builtins were removed: VS Code underlines every
// `textDocument/documentLink` range, which made `sin`/`sample`/etc. look
// decorated in the editor. Docs stay available via hover (markdown link).
document_links :: proc(ws: ^Workspace, params: lsp.Document_Link_Params, allocator := context.temp_allocator) -> []lsp.Document_Link {
	_ = ws
	_ = params
	_ = allocator
	return nil
}

language_reference_uri :: proc(ws: ^Workspace, allocator := context.temp_allocator) -> string {
	if ws == nil || ws.root_path == "" do return ""
	docs_path, _ := filepath.join(
		{ws.root_path, "oge", "misl", "docs", "LANGUAGE.md"},
		allocator,
	)
	return lsp.filepath_to_uri(docs_path, allocator)
}
