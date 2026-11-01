package misl_lsp

import "core:slice"
import "oge:misl"
import "./lsp"

Semantic_Span :: struct {
	offset: int,
	length: int,
	type:   lsp.Semantic_Token_Type,
	mods:   lsp.Semantic_Token_Modifiers,
}

semantic_lex_ignore_err :: proc(pos: misl.Token_Pos, msg: string, args: ..any) {
	_ = pos
	_ = msg
	_ = args
}

semantic_ident_is_modification :: proc(ident: ^misl.Ident, text: string) -> bool {
	if ident == nil do return false
	i := ident.end.offset
	if i <= ident.pos.offset do i = ident.pos.offset + len(ident.name)
	i = clamp(i, 0, len(text))
	for i < len(text) && (text[i] == ' ' || text[i] == '\t') {
		i += 1
	}
	if i < len(text) && text[i] == '=' {
		return i + 1 >= len(text) || text[i + 1] != '='
	}
	if i < len(text) && (text[i] == '+' || text[i] == '-' || text[i] == '*' ||
		text[i] == '/' || text[i] == '%' || text[i] == '&' || text[i] == '|' ||
		text[i] == '^') {
		i += 1
		for i < len(text) && (text[i] == ' ' || text[i] == '\t') {
			i += 1
		}
		return i < len(text) && text[i] == '='
	}
	return false
}

semantic_lookup_ident :: proc(ident: ^misl.Ident, mod: ^misl.Module) -> ^misl.Entity {
	if ident == nil do return nil
	if ident.entity != nil do return ident.entity
	if mod != nil && mod.scope != nil && ident.name != "" {
		return misl.scope_lookup(mod.scope, ident.name)
	}
	return nil
}

// GPU entry bodies are not typechecked under helper locks, so selector fields
// have no entity. Resolve `import.member` from the imported module scope.
semantic_import_selector_field :: proc(sel: ^misl.Selector_Expr, mod: ^misl.Module) -> ^misl.Entity {
	if sel == nil || sel.field == nil do return nil
	if sel.field.entity != nil do return sel.field.entity
	lhs := misl.unparen_expr(sel.expr)
	if lhs == nil do return nil
	lhs_ident := lhs.derived.(^misl.Ident) or_else nil
	if lhs_ident == nil do return nil
	imp := semantic_lookup_ident(lhs_ident, mod)
	if imp == nil || imp.kind != .Import do return nil
	if imp.imported_module == nil || imp.imported_module.scope == nil do return nil
	if sel.field.name == "" do return nil
	return misl.scope_lookup_current(imp.imported_module.scope, sel.field.name)
}

append_ident_semantic_spans :: proc(spans: ^[dynamic]Semantic_Span, mod: ^misl.Module, text: string) {
	if mod == nil do return
	idents := make([dynamic]^misl.Ident, context.temp_allocator)
	selectors := make([dynamic]^misl.Selector_Expr, context.temp_allocator)
	ast_collect_all_idents(mod, &idents, &selectors)
	import_fields := make(map[^misl.Ident]^misl.Entity, context.temp_allocator)
	for sel in selectors {
		found := semantic_import_selector_field(sel, mod)
		if found != nil && sel.field != nil {
			import_fields[sel.field] = found
		}
	}
	proc_group_fns := make(map[^misl.Ident]bool, context.temp_allocator)
	proc_group_decls := make(map[^misl.Ident]bool, context.temp_allocator)
	ast_mark_proc_group_idents(mod, &proc_group_fns, &proc_group_decls)
	for ident in idents {
		if ident == nil do continue
		tt: lsp.Semantic_Token_Type = .Variable
		mods: lsp.Semantic_Token_Modifiers
		entity := ident.entity
		if entity == nil {
			entity = import_fields[ident] or_else nil
		}
		if entity == nil && mod.scope != nil {
			entity = misl.scope_lookup(mod.scope, ident.name)
		}
		if ident in proc_group_fns {
			tt = .Function
		} else if entity != nil {
			#partial switch entity.kind {
			case .Procedure, .Entry, .Builtin, .Proc_Group:
				tt = .Function
				if entity.kind == .Builtin {
					mods += {.Default_Library}
				}
			case .Type_Name:
				tt = .Class
			case .Constant:
				tt = .Variable
				mods += {.Readonly}
			case .Variable:
				if .Param in entity.flags {
					tt = .Parameter
				} else {
					tt = .Variable
				}
			case .Import:
				tt = .Namespace
			}
		}
		if ident in proc_group_decls {
			mods += {.Declaration}
		} else if entity != nil {
			same_file := entity.pos.file == "" || ident.pos.file == "" ||
				entity.pos.file == ident.pos.file
			if same_file && entity.pos.offset == ident.pos.offset {
				mods += {.Declaration}
			}
		}
		if semantic_ident_is_modification(ident, text) {
			mods += {.Modification}
		}
		length := len(ident.name)
		if ident.end.offset > ident.pos.offset {
			length = ident.end.offset - ident.pos.offset
		}
		append(spans, Semantic_Span{
			offset = ident.pos.offset,
			length = max(length, 1),
			type = tt,
			mods = mods,
		})
	}
}

append_literal_semantic_spans :: proc(spans: ^[dynamic]Semantic_Span, text: string) {
	lex: misl.Lexer
	misl.lexer_init(&lex, text, "", semantic_lex_ignore_err)
	n := 0
	for {
		n += 1
		if n > len(text) + 8 {
			break
		}
		tok, _ := misl.lex_scan(&lex)
		if tok.kind == .EOF {
			break
		}
		tt: lsp.Semantic_Token_Type
		#partial switch tok.kind {
		case .Rune:
			tt = .String
		case .Integer, .Float, .Imaginary:
			tt = .Number
		case:
			continue
		}
		length := len(tok.text)
		if length <= 0 {
			continue
		}
		append(spans, Semantic_Span{
			offset = tok.pos.offset,
			length = length,
			type = tt,
		})
	}
}

semantic_tokens_full :: proc(ws: ^Workspace, params: lsp.Semantic_Tokens_Params, encoder: lsp.Token_Encoder, allocator := context.temp_allocator) -> lsp.Semantic_Tokens {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil do return {}
	mod := workspace_module_for_uri(ws, params.text_document.uri)

	spans := make([dynamic]Semantic_Span, allocator)
	append_ident_semantic_spans(&spans, mod, doc.text)
	append_literal_semantic_spans(&spans, doc.text)
	slice.sort_by(spans[:], proc(a, b: Semantic_Span) -> bool {
		return a.offset < b.offset
	})

	data := make([dynamic]u32, allocator)
	prev_line := 0
	prev_char := 0

	for span in spans {
		if span.type not_in encoder.token_set do continue
		pos := misl.Token_Pos{offset = span.offset}
		start := token_pos_to_lsp_position(pos, doc.text)
		end_off := min(span.offset + span.length, len(doc.text))
		end := position_from_offset(doc.text, end_off)
		tok_len := span.length
		if start.line == end.line {
			tok_len = max(end.character - start.character, 1)
		}
		delta_line := start.line - prev_line
		delta_char := start.character if delta_line != 0 else start.character - prev_char
		prev_line = start.line
		prev_char = start.character
		lsp.token_data_append(&data, {
			line = u32(delta_line),
			start_char = u32(max(delta_char, 0)),
			length = u32(max(tok_len, 1)),
			type = lsp.encode_token_type(encoder, span.type),
			modifiers = lsp.encode_token_modifiers(encoder, span.mods),
		})
	}

	return {data = data[:]}
}

semantic_tokens_range :: proc(ws: ^Workspace, params: lsp.Semantic_Tokens_Range_Params, encoder: lsp.Token_Encoder, allocator := context.temp_allocator) -> lsp.Semantic_Tokens {
	return semantic_tokens_full(ws, {text_document = params.text_document}, encoder, allocator)
}
