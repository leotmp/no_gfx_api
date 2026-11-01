package misl_lsp

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import "oge:misl"
import "./lsp"

@(private)
_active_diags: ^[dynamic]misl.Diagnostic

collect_error_handler :: proc(pos: misl.Token_Pos, msg: string, args: ..any) {
	if _active_diags == nil do return
	append(_active_diags, misl.Diagnostic{
		pos = pos,
		severity = .Error,
		message = fmt.tprintf(msg, ..args),
	})
}

collect_warning_handler :: proc(pos: misl.Token_Pos, msg: string, args: ..any) {
	if _active_diags == nil do return
	append(_active_diags, misl.Diagnostic{
		pos = pos,
		severity = .Warning,
		message = fmt.tprintf(msg, ..args),
	})
}

begin_diag_collection :: proc(diags: ^[dynamic]misl.Diagnostic) {
	_active_diags = diags
}

end_diag_collection :: proc() {
	_active_diags = nil
}

publish_diagnostics_clear :: proc(ws: ^Workspace, uri: string) {
	if ws.server == nil do return
	params := lsp.Publish_Diagnostics_Params{
		uri = uri,
		diagnostics = {},
	}
	lsp.send_notification("textDocument/publishDiagnostics", params, ws.server.write)
}

misl_severity_to_lsp :: proc(sev: misl.Diagnostic_Severity) -> lsp.Diagnostic_Severity {
	switch sev {
	case .Error:   return .Error
	case .Warning: return .Warning
	}
	return .Error
}

diagnostic_file_matches_doc :: proc(diag_file: string, doc: ^Document) -> bool {
	if diag_file == "" do return true
	if diag_file == doc.path do return true
	cleaned, _ := filepath.clean(diag_file, context.temp_allocator)
	return strings.equal_fold(cleaned, doc.path)
}

ident_len_at :: proc(text: string, offset: int) -> int {
	if len(text) == 0 do return 1
	offset := offset
	offset = clamp(offset, 0, len(text) - 1)
	if !is_ident_byte(text[offset]) {
		if offset == 0 || !is_ident_byte(text[offset - 1]) do return 1
		offset -= 1
	}
	start := offset
	for start > 0 && is_ident_byte(text[start - 1]) {
		start -= 1
	}
	end := offset + 1
	for end < len(text) && is_ident_byte(text[end]) {
		end += 1
	}
	return max(end - start, 1)
}

publish_workspace_diagnostics :: proc(ws: ^Workspace, diags: []misl.Diagnostic) {
	if ws.server == nil do return

	for _, doc in ws.docs {
		out := make([dynamic]lsp.Diagnostic, context.temp_allocator)
		seen := make(map[string]bool, context.temp_allocator)
		for d in diags {
			if !diagnostic_file_matches_doc(d.pos.file, doc) do continue
			key := fmt.tprintf("%d:%d:%v:%s", d.pos.offset, d.pos.line, d.severity, d.message)
			if seen[key] do continue
			seen[key] = true
			msg_len := ident_len_at(doc.text, d.pos.offset)
			range := token_pos_to_range(d.pos, msg_len, doc.text)
			append(&out, lsp.Diagnostic{
				range = range,
				severity = misl_severity_to_lsp(d.severity),
				message = d.message,
			})
		}
		params := lsp.Publish_Diagnostics_Params{
			uri = doc.uri,
			version = doc.version,
			diagnostics = out[:],
		}
		lsp.send_notification("textDocument/publishDiagnostics", params, ws.server.write)
	}
}
