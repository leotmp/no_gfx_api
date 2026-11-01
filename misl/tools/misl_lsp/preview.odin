package misl_lsp

import "core:encoding/json"
import "core:strings"
import "oge:misl"
import "./lsp"

preview_find_entity :: proc(mod: ^misl.Module, entity_name: string) -> ^misl.Entity {
	if mod == nil do return nil
	for e in mod.definitions {
		if e != nil && e.name == entity_name {
			return e
		}
	}
	if e := misl.find_entry_with_name(mod, entity_name); e != nil && e.entity != nil {
		return e.entity
	}
	return misl.scope_lookup_current(mod.scope, entity_name)
}

code_lenses_at :: proc(ws: ^Workspace, params: lsp.Code_Lens_Params, allocator := context.temp_allocator) -> []lsp.Code_Lens {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil do return nil
	mod := workspace_module_for_uri(ws, params.text_document.uri)
	if mod == nil do return nil

	lenses := make([dynamic]lsp.Code_Lens, allocator)
	for e in mod.definitions {
		if e == nil do continue
		if e.kind != .Procedure && e.kind != .Entry do continue
		args := make([]json.Value, 2, allocator)
		args[0] = params.text_document.uri
		args[1] = e.name
		if misl.entity_is_fmag(e) {
			append(&lenses, lsp.Code_Lens{
				range = token_pos_to_range(e.pos, max(len(e.name), 1), doc.text),
				command = lsp.Command{
					title = "Show FMAG",
					command = "misl.showFmag",
					arguments = args,
				},
			})
			continue
		}
		if entity_is_gpu_entry(e) {
			append(&lenses, lsp.Code_Lens{
				range = token_pos_to_range(e.pos, max(len(e.name), 1), doc.text),
				command = lsp.Command{
					title = "Show SPIRV",
					command = "misl.showSpirv",
					arguments = args,
				},
			})
		}
	}
	return lenses[:]
}

find_ident_line_col :: proc(text: string, name: string) -> (line, character: int) {
	if name == "" do return 0, 0
	best := strings.index(text, name)
	if best < 0 do return 0, 0

	is_word := proc(c: u8) -> bool {
		return c == '_' ||
			(c >= 'a' && c <= 'z') ||
			(c >= 'A' && c <= 'Z') ||
			(c >= '0' && c <= '9')
	}

	start := 0
	for {
		idx := strings.index(text[start:], name)
		if idx < 0 do break
		abs := start + idx
		before_ok := abs == 0 || !is_word(text[abs - 1])
		after := abs + len(name)
		after_ok := after >= len(text) || !is_word(text[after])
		if before_ok && after_ok {
			best = abs
			break
		}
		start = abs + 1
		best = abs
	}

	line = 0
	character = 0
	for i in 0 ..< best {
		if text[i] == '\n' {
			line += 1
			character = 0
		} else {
			character += 1
		}
	}
	return line, character
}
