package misl_lsp

import "core:fmt"
import "core:strings"
import "oge:misl"
import "./lsp"

completion_item_kind :: proc(e: ^misl.Entity) -> lsp.Completion_Item_Kind {
	#partial switch e.kind {
	case .Procedure, .Entry, .Builtin, .Proc_Group:
		return .Function
	case .Type_Name:
		return .Class
	case .Constant:
		return .Constant
	case .Variable:
		return .Variable
	case .Import:
		return .Module
	}
	return .Text
}

// "(a: T, b: U)" / result description, from a checked Type_Proc. Used for
// non-builtin procs/entries — builtins use `completion_builtin_label_details`
// (templated genType/genNumeric params) instead.
completion_proc_label_details :: proc(pt: ^misl.Type_Proc) -> lsp.Completion_Item_Label_Details {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	if cc := misl.proc_cc_label(pt); cc != "" {
		fmt.sbprintf(&b, " \"%s\"(", cc)
	} else {
		strings.write_byte(&b, '(')
	}
	if pt.params != nil {
		for f, i in pt.params.variables {
			if f == nil do continue
			if i > 0 do strings.write_string(&b, ", ")
			strings.write_string(&b, misl.string_from_type(f.type))
		}
	}
	strings.write_byte(&b, ')')

	result := ""
	if pt.results != nil && len(pt.results.variables) > 0 {
		if len(pt.results.variables) == 1 {
			if f := pt.results.variables[0]; f != nil && f.type != nil {
				result = misl.string_from_type(f.type)
			}
		} else {
			rb: strings.Builder
			strings.builder_init(&rb, context.temp_allocator)
			for f, i in pt.results.variables {
				if f == nil do continue
				if i > 0 do strings.write_string(&rb, ", ")
				strings.write_string(&rb, misl.string_from_type(f.type))
			}
			result = strings.to_string(rb)
		}
	}
	return lsp.Completion_Item_Label_Details{detail = strings.to_string(b), description = result}
}

// Same shape as `completion_proc_label_details` but from `misl.builtin_sigs`
// (genType/genNumeric/any placeholders) rather than a resolved Type_Proc.
completion_builtin_label_details :: proc(id: misl.Builtin_Proc) -> lsp.Completion_Item_Label_Details {
	sig := misl.builtin_sigs[id]
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_byte(&b, '(')
	for p, i in sig.params {
		if i > 0 do strings.write_string(&b, ", ")
		strings.write_string(&b, misl.builtin_param_type_string(p))
	}
	if sig.kind == .Printf {
		if len(sig.params) > 0 do strings.write_string(&b, ", ")
		strings.write_string(&b, "..any")
	}
	strings.write_byte(&b, ')')
	result := misl.builtin_type_class_string(sig.result_class, sig.result_type_name)
	return lsp.Completion_Item_Label_Details{detail = strings.to_string(b), description = result}
}

// "struct" / "enum" / "bit_set[...]" / etc. — avoids echoing the type's own
// name back as its own detail (string_from_type(named struct) == its name).
completion_type_kind_detail :: proc(type: ^misl.Type) -> string {
	if type == nil do return "typeid"
	#partial switch _ in type.derived {
	case ^misl.Type_Struct:
		return "struct"
	case ^misl.Type_Enum:
		return "enum"
	case ^misl.Type_Proc:
		return "proc"
	}
	return misl.string_from_type(type)
}

// Builds a fully documented Completion_Item for a resolved scope entity:
// detail/labelDetails type hints, `name($0)` snippets for callables, and
// documentation from either `misl.builtin_sigs` (builtins) or the entity's
// leading doc comment (everything else).
completion_item_for_entity :: proc(name: string, e: ^misl.Entity) -> lsp.Completion_Item {
	item := lsp.Completion_Item{
		label = name,
		kind  = completion_item_kind(e),
	}
	if e == nil do return item

	#partial switch e.kind {
	case .Builtin:
		if id, ok := misl.entity_compiler_builtin(e); ok {
			item.insertText = fmt.tprintf("%s($0)", name)
			item.insertTextFormat = lsp.Insert_Text_Format.Snippet
			label_details := completion_builtin_label_details(id)
			item.labelDetails = label_details
			item.detail = misl.builtin_sig_label(id, name)
			item.documentation = lsp.Markup_Content{
				kind  = "markdown",
				value = misl.builtin_sig_docs_markdown(id, name),
			}
			return item
		}

	case .Procedure, .Entry:
		item.insertText = fmt.tprintf("%s($0)", name)
		item.insertTextFormat = lsp.Insert_Text_Format.Snippet
		if e.type != nil {
			item.detail = hover_proc_signature(e.type)
			if pt, is_proc := e.type.derived.(^misl.Type_Proc); is_proc {
				item.labelDetails = completion_proc_label_details(pt)
			}
		}

	case .Proc_Group:
		item.insertText = fmt.tprintf("%s($0)", name)
		item.insertTextFormat = lsp.Insert_Text_Format.Snippet
		item.detail = "proc {…}"
		if len(e.proc_group_members) > 0 {
			b: strings.Builder
			strings.builder_init(&b, context.temp_allocator)
			strings.write_string(&b, "proc {")
			for m, i in e.proc_group_members {
				if m == nil do continue
				if i > 0 do strings.write_string(&b, ", ")
				strings.write_string(&b, m.name)
			}
			strings.write_string(&b, "}")
			item.detail = strings.to_string(b)
		}

	case .Type_Name:
		item.detail = completion_type_kind_detail(e.type)

	case .Constant, .Variable, .Dummy:
		if e.type != nil {
			item.detail = misl.string_from_type(e.type)
		}

	case .Import:
		item.detail = "import"

	case .Pipeline:
		item.detail = "pipeline"
	}

	if docs := entity_leading_docs(e); docs != "" {
		item.documentation = lsp.Markup_Content{kind = "markdown", value = docs}
	}
	return item
}

completion_resolve :: proc(ws: ^Workspace, item: lsp.Completion_Item) -> lsp.Completion_Item {
	item := item
	if _, already_documented := item.documentation.?; already_documented do return item
	if entity := workspace_find_named_entity(ws, item.label); entity != nil {
		resolved := completion_item_for_entity(item.label, entity)
		item.documentation = resolved.documentation
		if item.detail == "" do item.detail = resolved.detail
		if _, has_details := item.labelDetails.?; !has_details {
			item.labelDetails = resolved.labelDetails
		}
		return item
	}
	for stage in proc_stage_completions {
		if stage.name == item.label {
			item.documentation = lsp.Markup_Content{
				kind = "markdown",
				value = markdown_fence_with_docs(
					fmt.tprintf("proc \"%s\"", stage.name),
					stage.docs,
				),
			}
			return item
		}
	}
	for info in misl.semantic_names {
		if info.name == item.label && info.docs != "" {
			item.documentation = lsp.Markup_Content{
				kind = "markdown",
				value = markdown_fence_with_docs(info.name, info.docs),
			}
			return item
		}
	}
	return item
}

// True when the cursor sits inside an (unterminated) string literal that
// immediately follows the `proc` keyword — i.e. `proc "<cursor>`, possibly
// with a partial stage word already typed (`proc "ver<cursor>`).
proc_stage_completion_at :: proc(text: string, offset: int) -> bool {
	if offset < 0 || offset > len(text) do return false

	quote_start := -1
	for j := offset - 1; j >= 0; j -= 1 {
		c := text[j]
		if c == '\n' do break
		if c == '"' {
			quote_start = j
			break
		}
	}
	if quote_start < 0 do return false

	k := quote_start
	for k > 0 && (text[k-1] == ' ' || text[k-1] == '\t') {
		k -= 1
	}
	if k < 4 || text[k-4:k] != "proc" do return false
	return k == 4 || !is_ident_byte(text[k-5])
}

Proc_Stage_Completion :: struct {
	name: string,
	docs: string,
}

proc_stage_completions := []Proc_Stage_Completion{
	{"vertex", "Vertex shader stage entry."},
	{"fragment", "Fragment shader stage entry."},
	{"compute", "Compute shader stage entry."},
	{"fmag", "FMAG bytecode entry (not a GPU pipeline stage). Host: `compile_fmag_entry`. GPU interpreter: `core:fmag` (16 registers). Bitcasts: `f32_from_u32_bits` / `u32_from_f32_bits`."},
}

append_proc_stage_completions :: proc(items: ^[dynamic]lsp.Completion_Item) {
	for s in proc_stage_completions {
		append(items, lsp.Completion_Item{
			label = s.name,
			kind = .Keyword,
			insertText = s.name,
			documentation = lsp.Markup_Content{
				kind  = "markdown",
				value = markdown_fence_with_docs(fmt.tprintf("proc \"%s\"", s.name), s.docs),
			},
		})
	}
}

Comp_Lit_Completion_Context :: struct {
	lit:           ^misl.Comp_Lit,
	type:          ^misl.Type,
	cursor_offset: int,
}

comp_lit_cursor_inside :: proc(lit: ^misl.Comp_Lit, offset: int) -> bool {
	if lit == nil do return false
	lo := lit.open.offset
	if lo <= 0 do lo = lit.pos.offset
	hi := lit.close.offset
	if hi <= lo do hi = lit.end.offset
	if hi <= lo do hi = lo + 1
	return offset >= lo && offset <= hi + 1
}

completion_call_param_type :: proc(call: ^misl.Call_Expr, index: int) -> ^misl.Type {
	if call == nil || index < 0 do return nil
	entity: ^misl.Entity
	#partial switch callee in call.expr.derived_expr {
	case ^misl.Ident:
		entity = callee.entity
	case ^misl.Selector_Expr:
		if callee.field != nil do entity = callee.field.entity
	}
	if entity == nil || entity.type == nil do return nil
	if proc_type, ok := entity.type.derived.(^misl.Type_Proc); ok {
		if proc_type.params != nil && index < len(proc_type.params.variables) {
			param := proc_type.params.variables[index]
			if param != nil do return param.type
		}
	}
	return nil
}

comp_lit_struct_field_type :: proc(st: ^misl.Type_Struct, name: string) -> ^misl.Type {
	if st == nil || st.fields == nil || name == "" do return nil
	for field in st.fields.variables {
		if field != nil && field.name == name do return field.type
	}
	return nil
}

compound_literal_context_at :: proc(mod: ^misl.Module, offset: int) -> Comp_Lit_Completion_Context {
	result: Comp_Lit_Completion_Context
	best_span := max(int)

	consider :: proc(lit: ^misl.Comp_Lit, hint: ^misl.Type, result: ^Comp_Lit_Completion_Context, best_span: ^int) -> ^misl.Type {
		if lit == nil do return nil
		type := lit.tav.type
		if lit.type != nil {
			if lit.type.tav.type != nil {
				type = lit.type.tav.type
			} else if explicit := type_from_expr_entity(lit.type); explicit != nil {
				type = explicit
			}
		}
		if type == nil do type = hint
		if comp_lit_cursor_inside(lit, result.cursor_offset) {
			lo := lit.open.offset if lit.open.offset > 0 else lit.pos.offset
			hi := lit.close.offset if lit.close.offset > lo else lit.end.offset
			span := max(hi - lo, 1)
			if span <= best_span^ {
				best_span^ = span
				result.lit = lit
				result.type = type
			}
		}
		return type
	}

	walk_expr :: proc(expr: ^misl.Expr, hint: ^misl.Type, result: ^Comp_Lit_Completion_Context, best_span: ^int) {
		if expr == nil do return
		#partial switch e in expr.derived_expr {
		case ^misl.Comp_Lit:
			lit_type := consider(e, hint, result, best_span)
			walk_expr(e.type, nil, result, best_span)
			struct_type: ^misl.Type_Struct
			bit_set_type: ^misl.Type_Bit_Set
			array_type: ^misl.Type_Array
			if lit_type != nil {
				struct_type, _ = lit_type.derived.(^misl.Type_Struct)
				bit_set_type, _ = lit_type.derived.(^misl.Type_Bit_Set)
				array_type, _ = lit_type.derived.(^misl.Type_Array)
			}
			for elem, i in e.elems {
				elem_hint: ^misl.Type
				if field_value, named := elem.derived_expr.(^misl.Field_Value); named {
					if field_ident, ok := field_value.field.derived_expr.(^misl.Ident); ok {
						elem_hint = comp_lit_struct_field_type(struct_type, field_ident.name)
					}
					walk_expr(field_value.field, nil, result, best_span)
					walk_expr(field_value.value, elem_hint, result, best_span)
					continue
				}
				if struct_type != nil && struct_type.fields != nil && i < len(struct_type.fields.variables) {
					field := struct_type.fields.variables[i]
					if field != nil do elem_hint = field.type
				} else if bit_set_type != nil {
					elem_hint = bit_set_type.elem
				} else if array_type != nil {
					elem_hint = array_type.elem
				}
				walk_expr(elem, elem_hint, result, best_span)
			}
		case ^misl.Call_Expr:
			walk_expr(e.expr, nil, result, best_span)
			for arg, i in e.args {
				walk_expr(arg, completion_call_param_type(e, i), result, best_span)
			}
		case ^misl.Field_Value:
			walk_expr(e.field, nil, result, best_span)
			walk_expr(e.value, hint, result, best_span)
		case ^misl.Proc_Lit:
			walk_expr(e.type, nil, result, best_span)
			walk_stmt(e.body, result, best_span)
		case ^misl.Unary_Expr:
			walk_expr(e.expr, hint, result, best_span)
		case ^misl.Binary_Expr:
			walk_expr(e.left, nil, result, best_span)
			walk_expr(e.right, nil, result, best_span)
		case ^misl.Paren_Expr:
			walk_expr(e.expr, hint, result, best_span)
		case ^misl.Selector_Expr:
			walk_expr(e.expr, nil, result, best_span)
		case ^misl.Selector_Call_Expr:
			walk_expr(e.expr, nil, result, best_span)
			walk_expr(e.call, nil, result, best_span)
		case ^misl.Index_Expr:
			walk_expr(e.expr, nil, result, best_span)
			walk_expr(e.index, nil, result, best_span)
		case ^misl.Deref_Expr:
			walk_expr(e.expr, nil, result, best_span)
		case ^misl.Slice_Expr:
			walk_expr(e.expr, nil, result, best_span)
			walk_expr(e.low, nil, result, best_span)
			walk_expr(e.high, nil, result, best_span)
		case ^misl.Matrix_Index_Expr:
			walk_expr(e.expr, nil, result, best_span)
			walk_expr(e.row_index, nil, result, best_span)
			walk_expr(e.column_index, nil, result, best_span)
		case ^misl.Ternary_If_Expr:
			walk_expr(e.x, hint, result, best_span)
			walk_expr(e.cond, nil, result, best_span)
			walk_expr(e.y, hint, result, best_span)
		case ^misl.Ternary_When_Expr:
			walk_expr(e.x, hint, result, best_span)
			walk_expr(e.cond, nil, result, best_span)
			walk_expr(e.y, hint, result, best_span)
		case ^misl.Type_Cast:
			walk_expr(e.type, nil, result, best_span)
			walk_expr(e.expr, e.type.tav.type if e.type != nil else hint, result, best_span)
		case ^misl.Auto_Cast:
			walk_expr(e.expr, hint, result, best_span)
		case ^misl.Ellipsis:
			walk_expr(e.expr, hint, result, best_span)
		}
	}

	walk_stmt :: proc(stmt: ^misl.Stmt, result: ^Comp_Lit_Completion_Context, best_span: ^int) {
		if stmt == nil do return
		#partial switch s in stmt.derived_stmt {
		case ^misl.Value_Decl:
			decl_type := s.type.tav.type if s.type != nil else nil
			if decl_type == nil && s.type != nil do decl_type = type_from_expr_entity(s.type)
			walk_expr(s.type, nil, result, best_span)
			for value in s.values { walk_expr(value, decl_type, result, best_span) }
		case ^misl.Assign_Stmt:
			for lhs in s.lhs { walk_expr(lhs, nil, result, best_span) }
			for rhs, i in s.rhs {
				hint: ^misl.Type
				if i < len(s.lhs) && s.lhs[i] != nil {
					hint = s.lhs[i].tav.type
					if hint == nil do hint = type_from_expr_entity(s.lhs[i])
				}
				walk_expr(rhs, hint, result, best_span)
			}
		case ^misl.Expr_Stmt:
			walk_expr(s.expr, nil, result, best_span)
		case ^misl.Block_Stmt:
			for child in s.stmts { walk_stmt(child, result, best_span) }
		case ^misl.If_Stmt:
			walk_stmt(s.init, result, best_span)
			walk_expr(s.cond, nil, result, best_span)
			walk_stmt(s.body, result, best_span)
			walk_stmt(s.else_stmt, result, best_span)
		case ^misl.When_Stmt:
			walk_expr(s.cond, nil, result, best_span)
			walk_stmt(s.body, result, best_span)
			walk_stmt(s.else_stmt, result, best_span)
		case ^misl.Which_Stmt:
			walk_expr(s.cond, nil, result, best_span)
			walk_stmt(s.body, result, best_span)
		case ^misl.For_Stmt:
			walk_stmt(s.init, result, best_span)
			walk_expr(s.cond, nil, result, best_span)
			walk_stmt(s.post, result, best_span)
			walk_stmt(s.body, result, best_span)
		case ^misl.Range_Stmt:
			walk_expr(s.expr, nil, result, best_span)
			walk_stmt(s.body, result, best_span)
		case ^misl.Switch_Stmt:
			walk_stmt(s.init, result, best_span)
			walk_expr(s.cond, nil, result, best_span)
			walk_stmt(s.body, result, best_span)
		case ^misl.Case_Clause:
			for value in s.list { walk_expr(value, nil, result, best_span) }
			for child in s.body { walk_stmt(child, result, best_span) }
		case ^misl.Return_Stmt:
			for value in s.results { walk_expr(value, nil, result, best_span) }
		case ^misl.Using_Stmt:
			for value in s.list { walk_expr(value, nil, result, best_span) }
		case ^misl.Tag_Stmt:
			walk_stmt(s.stmt, result, best_span)
		}
	}

	if mod != nil {
		result.cursor_offset = offset
		for decl in mod.decls {
			walk_stmt(decl, &result, &best_span)
		}
	}
	return result
}

comp_lit_member_has_dot :: proc(text: string, offset, lower_bound: int) -> bool {
	i := clamp(offset, 0, len(text))
	for i > lower_bound && is_ident_byte(text[i - 1]) {
		i -= 1
	}
	for i > lower_bound && (text[i - 1] == ' ' || text[i - 1] == '\t') {
		i -= 1
	}
	return i > lower_bound && text[i - 1] == '.'
}

append_comp_lit_enum_members :: proc(
	items: ^[dynamic]lsp.Completion_Item,
	type: ^misl.Type,
	text: string,
	offset, lower_bound: int,
) -> bool {
	type := type
	type = type_peel_single_pointers(type)
	if type != nil {
		if bs, is_bit_set := type.derived.(^misl.Type_Bit_Set); is_bit_set {
			type = type_as_enum_for_completion(bs.elem)
		}
	}
	enum_type: ^misl.Type_Enum
	ok: bool
	if type != nil {
		enum_type, ok = type.derived.(^misl.Type_Enum)
	}
	if !ok || enum_type == nil do return false
	has_dot := comp_lit_member_has_dot(text, offset, lower_bound)
	for field in enum_type.fields {
		if field == nil || field.name == "" do continue
		item := lsp.Completion_Item{
			label = field.name,
			kind = .Enum_Member,
			insertText = field.name if has_dot else fmt.tprintf(".%s", field.name),
		}
		if docs := entity_leading_docs(field); docs != "" {
			item.documentation = lsp.Markup_Content{kind = "markdown", value = docs}
		}
		append(items, item)
	}
	return true
}

comp_lit_active_field_type :: proc(
	lit: ^misl.Comp_Lit,
	st: ^misl.Type_Struct,
	text: string,
	offset: int,
) -> ^misl.Type {
	if lit == nil || st == nil do return nil
	best_sep := -1
	type: ^misl.Type
	for elem in lit.elems {
		field_value, ok := elem.derived_expr.(^misl.Field_Value)
		if !ok || field_value.sep.offset < 0 || field_value.sep.offset > offset do continue
		comma_after := false
		for i := field_value.sep.offset + 1; i < offset && i < len(text); i += 1 {
			if text[i] == ',' {
				comma_after = true
				break
			}
		}
		if comma_after || field_value.sep.offset < best_sep do continue
		if ident, ident_ok := field_value.field.derived_expr.(^misl.Ident); ident_ok {
			if field_type := comp_lit_struct_field_type(st, ident.name); field_type != nil {
				best_sep = field_value.sep.offset
				type = field_type
			}
		}
	}
	return type
}

append_comp_lit_completions :: proc(
	items: ^[dynamic]lsp.Completion_Item,
	mod: ^misl.Module,
	text: string,
	offset: int,
) -> bool {
	ctx := compound_literal_context_at(mod, offset)
	if ctx.lit == nil || ctx.type == nil do return false
	lower_bound := ctx.lit.open.offset if ctx.lit.open.offset >= 0 else ctx.lit.pos.offset
	type := type_peel_single_pointers(ctx.type)

	if append_comp_lit_enum_members(items, type, text, offset, lower_bound) {
		return true
	}

	st, is_struct := type.derived.(^misl.Type_Struct)
	if !is_struct || st == nil || st.fields == nil do return false

	if field_type := comp_lit_active_field_type(ctx.lit, st, text, offset); field_type != nil {
		if append_comp_lit_enum_members(items, field_type, text, offset, lower_bound) {
			return true
		}
		before := len(items^)
		append_type_fields(items, field_type)
		return len(items^) > before
	}

	used := make(map[string]bool, context.temp_allocator)
	for elem in ctx.lit.elems {
		if field_value, ok := elem.derived_expr.(^misl.Field_Value); ok {
			if ident, ident_ok := field_value.field.derived_expr.(^misl.Ident); ident_ok {
				used[ident.name] = true
			}
		}
	}
	for field in st.fields.variables {
		if field == nil || field.name == "" || field.name in used do continue
		append(items, lsp.Completion_Item{
			label = field.name,
			kind = .Field,
			detail = misl.string_from_type(field.type),
			insertText = fmt.tprintf("%s = $0", field.name),
			insertTextFormat = lsp.Insert_Text_Format.Snippet,
		})
	}
	return true
}

completion_at :: proc(ws: ^Workspace, params: lsp.Completion_Params, allocator := context.temp_allocator) -> lsp.Completion_List {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil do return {}

	items := make([dynamic]lsp.Completion_Item, allocator)
	seen := make(map[string]bool, allocator)

	has_trigger := false
	trigger := ""
	if ctx, has_ctx := params.ctx.?; has_ctx {
		if t, has_t := ctx.trigger_character.?; has_t {
			has_trigger = true
			trigger = t
		}
	}

	offset, ok := offset_from_position(doc.text, params.position)
	if !ok do return {}

	// `#+` file tags do not need a typechecked module (the line is often incomplete).
	if kind, _, tag_ok := file_tag_complete_at(doc.text, offset); tag_ok {
		append_file_tag_completions(&items, kind)
		// Incomplete so the client re-queries after Space rather than filtering
		// the `feature` list against an empty word.
		return {isIncomplete = true, items = items[:]}
	}

	// Import paths (`import "core:`, relative `.misl`) also work on a broken
	// buffer — the string is often still unclosed.
	if append_import_path_completions(&items, ws, doc, offset) {
		return {isIncomplete = true, items = items[:]}
	}

	// `proc "<cursor>` uses the same `"` trigger as import strings.
	if proc_stage_completion_at(doc.text, offset) {
		append_proc_stage_completions(&items)
		return {isIncomplete = false, items = items[:]}
	}

	// `:` `/` `"` are triggers for import strings; elsewhere they must not
	// dump every in-scope ident (`x: f32`, `a / b`, ordinary strings).
	if has_trigger && (trigger == ":" || trigger == "/" || trigger == "\"") {
		return {isIncomplete = false, items = items[:]}
	}

	// Space is a trigger only so `#+feature <cursor>` pops feature names. Anywhere
	// else it would dump every in-scope ident.
	if has_trigger && trigger == " " {
		return {isIncomplete = false, items = items[:]}
	}

	mod := workspace_module_for_uri(ws, params.text_document.uri, offset)
	if mod == nil do return {}

	// Directive completions after # (`#align`, `#config`, … — not `#+`).
	if (has_trigger && trigger == "#") || ends_with_hash(doc.text, params.position) {
		tags := []string{"align", "soa", "raw_union", "packed", "no_nil", "shared", "ref", "mut", "flat", "array", "config", "intrinsic"}
		for tag in tags {
			append(&items, lsp.Completion_Item{label = tag, kind = .Keyword})
		}
		return {isIncomplete = false, items = items[:]}
	}

	// Semantic (`| SV_…`) completions on struct fields / entry params & results.
	if pipe, prefix, pipe_ok := find_semantic_pipe(doc.text, offset); pipe_ok {
		if allowed, sem_ok := allowed_semantics_at(mod, doc.text, pipe); sem_ok {
			append_semantic_completions(&items, allowed, prefix)
			return {isIncomplete = false, items = items[:]}
		}
		// Bare `|` trigger outside a semantic slot — don't flood with idents.
		if has_trigger && trigger == "|" {
			return {isIncomplete = false, items = items[:]}
		}
	}

	// Compound literal fields and enum values are more specific than general
	// scope/member completion, including inferred `{...}` literals.
	if append_comp_lit_completions(&items, mod, doc.text, offset) {
		return {isIncomplete = false, items = items[:]}
	}

	// Field / member / enum completion after '.'
	if offset > 0 {
		i := offset - 1
		for i >= 0 && (doc.text[i] == ' ' || doc.text[i] == '\t') {
			i -= 1
		}
		if i >= 0 && doc.text[i] == '.' {
			dot_offset := i
			implicit := is_implicit_selector_dot(doc.text, dot_offset)

			if !implicit {
				// Import names are not types (`debug.printf`); their ident tav is
				// t_invalid, so type_before_dot / append_type_fields miss them.
				if imp := imported_module_before_dot(mod, doc.text, dot_offset); imp != nil {
					append_imported_scope_entities(&items, &seen, imp.scope)
					return {isIncomplete = false, items = items[:]}
				}
				if type := type_before_dot(mod, doc.text, dot_offset); type != nil {
					append_type_fields(&items, type)
					if len(items) > 0 {
						return {isIncomplete = false, items = items[:]}
					}
				}
			}

			// Bare `.` / incomplete implicit selector: prefer expected enum type, else all in-scope enum values.
			if hint := expected_enum_type_at(mod, dot_offset); hint != nil {
				append_type_fields(&items, hint)
				if len(items) > 0 {
					return {isIncomplete = false, items = items[:]}
				}
			}
			if implicit {
				scope := scope_at_offset(mod, offset)
				if scope == nil {
					scope = mod.scope
				}
				append_all_enum_members_in_scope(&items, &seen, scope)
				return {isIncomplete = false, items = items[:]}
			}
		}
	}

	// Innermost scope at cursor (locals/params), then outer → module → builtins.
	scope := scope_at_offset(mod, offset)
	if scope == nil {
		scope = mod.scope
	}
	append_scope_entities(&items, &seen, scope)

	return {isIncomplete = false, items = items[:]}
}

File_Tag_Complete :: enum {
	None,
	Directive,
	Feature,
}

is_file_tag_name_byte :: proc(c: u8) -> bool {
	return c == '_' ||
		c == '-' ||
		(c >= 'a' && c <= 'z') ||
		(c >= 'A' && c <= 'Z') ||
		(c >= '0' && c <= '9')
}

// Cursor is on a `#+…` line: either the directive name (`feature`) or a feature name.
file_tag_complete_at :: proc(text: string, offset: int) -> (kind: File_Tag_Complete, prefix: string, ok: bool) {
	if offset < 0 || offset > len(text) do return
	line_start := offset
	for line_start > 0 && text[line_start - 1] != '\n' {
		line_start -= 1
	}
	line := text[line_start:offset]
	i := 0
	for i < len(line) && (line[i] == ' ' || line[i] == '\t') {
		i += 1
	}
	if i >= len(line) || line[i] != '#' do return
	i += 1
	if i >= len(line) || line[i] != '+' do return
	i += 1
	for i < len(line) && (line[i] == ' ' || line[i] == '\t') {
		i += 1
	}
	ident_start := i
	for i < len(line) && is_file_tag_name_byte(line[i]) {
		i += 1
	}
	first := line[ident_start:i]
	if i >= len(line) {
		return .Directive, first, true
	}
	if first != "feature" {
		return .Directive, first, true
	}
	for i < len(line) && (line[i] == ' ' || line[i] == '\t') {
		i += 1
	}
	feat_start := i
	for i < len(line) && is_file_tag_name_byte(line[i]) {
		i += 1
	}
	return .Feature, line[feat_start:i], true
}

append_file_tag_completions :: proc(items: ^[dynamic]lsp.Completion_Item, kind: File_Tag_Complete) {
	switch kind {
	case .None:
		return
	case .Directive:
		for d in misl.FILE_TAG_DIRECTIVES {
			append(items, lsp.Completion_Item{
				label = d.name,
				kind = .Keyword,
				insertText = fmt.tprintf("%s ", d.name),
				command = lsp.Command{
					title = "Suggest",
					command = "editor.action.triggerSuggest",
				},
				documentation = lsp.Markup_Content{
					kind = "markdown",
					value = markdown_fence_with_docs(fmt.tprintf("#+%s", d.name), d.docs),
				},
			})
		}
	case .Feature:
		for f in misl.FILE_TAG_FEATURES {
			append(items, lsp.Completion_Item{
				label = f.name,
				kind = .Keyword,
				insertText = f.name,
				documentation = lsp.Markup_Content{
					kind = "markdown",
					value = markdown_fence_with_docs(fmt.tprintf("#+feature %s", f.name), f.docs),
				},
			})
		}
	}
}

ends_with_hash :: proc(text: string, pos: lsp.Position) -> bool {
	offset, ok := offset_from_position(text, pos)
	if !ok || offset <= 0 do return false
	return text[offset-1] == '#'
}

// Imported module for `name.` when `name` is an Import entity.
imported_module_before_dot :: proc(mod: ^misl.Module, text: string, dot_offset: int) -> ^misl.Module {
	if sel := find_selector_at_dot(mod, dot_offset); sel != nil && sel.expr != nil {
		if e := misl.entity_from_expr(sel.expr); e != nil && e.kind == .Import {
			return e.imported_module
		}
	}

	end := dot_offset
	start := end
	for start > 0 {
		c := text[start - 1]
		if c == '_' ||
			(c >= 'a' && c <= 'z') ||
			(c >= 'A' && c <= 'Z') ||
			(c >= '0' && c <= '9') {
			start -= 1
			continue
		}
		break
	}
	if start >= end do return nil
	name := text[start:end]

	left_hit := ast_find_at_offset(mod, start)
	if left_hit.ident != nil && left_hit.ident.entity != nil && left_hit.ident.entity.kind == .Import {
		return left_hit.ident.entity.imported_module
	}

	scope := scope_at_offset(mod, start)
	if scope == nil {
		scope = mod.scope
	}
	if e := misl.scope_lookup(scope, name); e != nil && e.kind == .Import {
		return e.imported_module
	}
	return nil
}

// Current scope only — imported file modules parent to core:builtin.
append_imported_scope_entities :: proc(items: ^[dynamic]lsp.Completion_Item, seen: ^map[string]bool, scope: ^misl.Scope) {
	if scope == nil do return
	for name, e in scope.entities {
		if e == nil || name == "" || name == "_" do continue
		if name in seen^ do continue
		seen^[name] = true
		append(items, completion_item_for_entity(name, e))
	}
}

// `dot_offset` is the byte index of the '.' character.
type_before_dot :: proc(mod: ^misl.Module, text: string, dot_offset: int) -> ^misl.Type {
	// Prefer a Selector_Expr rooted at this '.' (including empty `foo.` / `mp[i].`).
	if sel := find_selector_at_dot(mod, dot_offset); sel != nil && sel.expr != nil {
		return type_for_field_completion(type_of_selector_lhs(sel.expr))
	}

	hit := ast_find_at_offset(mod, max(dot_offset - 1, 0))
	if hit.expr != nil {
		#partial switch e in hit.expr.derived_expr {
		case ^misl.Selector_Expr:
			if e.expr != nil {
				return type_for_field_completion(type_of_selector_lhs(e.expr))
			}
		case ^misl.Index_Expr:
			// `mp[i].` — indexing yields the element type.
			return type_for_field_completion(type_from_expr_entity(e))
		}
	}

	// Fallback: identifier text immediately left of '.' (bare `name.` only).
	// Does not handle `mp[i].` — that requires the selector/index paths above.
	end := dot_offset
	start := end
	for start > 0 {
		c := text[start - 1]
		if c == '_' ||
			(c >= 'a' && c <= 'z') ||
			(c >= 'A' && c <= 'Z') ||
			(c >= '0' && c <= '9') {
			start -= 1
			continue
		}
		break
	}
	if start >= end do return nil
	name := text[start:end]

	left_hit := ast_find_at_offset(mod, start)
	if left_hit.ident != nil {
		if left_hit.ident.tav.type != nil {
			return type_for_field_completion(left_hit.ident.tav.type)
		}
		if left_hit.ident.entity != nil && left_hit.ident.entity.type != nil {
			return type_for_field_completion(left_hit.ident.entity.type)
		}
	}

	scope := scope_at_offset(mod, start)
	if scope == nil {
		scope = mod.scope
	}
	if e := misl.scope_lookup(scope, name); e != nil {
		return type_for_field_completion(e.type)
	}
	return nil
}

// LHS type of `lhs.` — for Index_Expr prefer computed elem type over a stale tav.
type_of_selector_lhs :: proc(expr: ^misl.Expr) -> ^misl.Type {
	if expr == nil do return nil
	#partial switch e in expr.derived_expr {
	case ^misl.Index_Expr, ^misl.Deref_Expr:
		if t := type_from_expr_entity(expr); t != nil do return t
		return expr.tav.type
	}
	if expr.tav.type != nil do return expr.tav.type
	return type_from_expr_entity(expr)
}

// Multipointers/arrays/slices are not field-selectable; must index first (`mp[i].`).
type_for_field_completion :: proc(type: ^misl.Type) -> ^misl.Type {
	if type == nil do return nil
	t := type
	if tuple_t, is_tuple := t.derived.(^misl.Type_Tuple); is_tuple {
		if len(tuple_t.variables) != 1 do return nil
		t = tuple_t.variables[0].type
		if t == nil do return nil
	}
	#partial switch _ in t.derived {
	case ^misl.Type_Multi_Pointer, ^misl.Type_Array, ^misl.Type_Slice:
		return nil
	}
	return t
}

find_selector_at_dot :: proc(mod: ^misl.Module, dot_offset: int) -> ^misl.Selector_Expr {
	found: ^misl.Selector_Expr

	walk_expr :: proc(expr: ^misl.Expr, dot_offset: int, found: ^^misl.Selector_Expr) {
		if expr == nil do return
		#partial switch e in expr.derived_expr {
		case ^misl.Selector_Expr:
			if e.op.pos.offset == dot_offset {
				found^ = e
			}
			walk_expr(e.expr, dot_offset, found)
		case ^misl.Index_Expr:
			walk_expr(e.expr, dot_offset, found)
			walk_expr(e.index, dot_offset, found)
		case ^misl.Call_Expr:
			walk_expr(e.expr, dot_offset, found)
			for arg in e.args { walk_expr(arg, dot_offset, found) }
		case ^misl.Paren_Expr:
			walk_expr(e.expr, dot_offset, found)
		case ^misl.Unary_Expr:
			walk_expr(e.expr, dot_offset, found)
		case ^misl.Binary_Expr:
			walk_expr(e.left, dot_offset, found)
			walk_expr(e.right, dot_offset, found)
		case ^misl.Deref_Expr:
			walk_expr(e.expr, dot_offset, found)
		case ^misl.Comp_Lit:
			for elem in e.elems { walk_expr(elem, dot_offset, found) }
		case ^misl.Field_Value:
			walk_expr(e.value, dot_offset, found)
		case ^misl.Proc_Lit:
			walk_stmt(e.body, dot_offset, found)
		}
	}

	walk_stmt :: proc(stmt: ^misl.Stmt, dot_offset: int, found: ^^misl.Selector_Expr) {
		if stmt == nil do return
		#partial switch s in stmt.derived_stmt {
		case ^misl.Block_Stmt:
			for st in s.stmts { walk_stmt(st, dot_offset, found) }
		case ^misl.Expr_Stmt:
			walk_expr(s.expr, dot_offset, found)
		case ^misl.Assign_Stmt:
			for lhs in s.lhs { walk_expr(lhs, dot_offset, found) }
			for rhs in s.rhs { walk_expr(rhs, dot_offset, found) }
		case ^misl.Value_Decl:
			for val in s.values { walk_expr(val, dot_offset, found) }
			walk_expr(s.type, dot_offset, found)
		case ^misl.Return_Stmt:
			for r in s.results { walk_expr(r, dot_offset, found) }
		case ^misl.If_Stmt:
			walk_stmt(s.init, dot_offset, found)
			walk_expr(s.cond, dot_offset, found)
			walk_stmt(s.body, dot_offset, found)
			walk_stmt(s.else_stmt, dot_offset, found)
		case ^misl.For_Stmt:
			walk_stmt(s.init, dot_offset, found)
			walk_expr(s.cond, dot_offset, found)
			walk_stmt(s.post, dot_offset, found)
			walk_stmt(s.body, dot_offset, found)
		case ^misl.Range_Stmt:
			walk_expr(s.expr, dot_offset, found)
			walk_stmt(s.body, dot_offset, found)
		case ^misl.Switch_Stmt:
			walk_stmt(s.init, dot_offset, found)
			walk_expr(s.cond, dot_offset, found)
			walk_stmt(s.body, dot_offset, found)
		case ^misl.Which_Stmt:
			walk_expr(s.cond, dot_offset, found)
			walk_stmt(s.body, dot_offset, found)
		case ^misl.When_Stmt:
			walk_expr(s.cond, dot_offset, found)
			walk_stmt(s.body, dot_offset, found)
			walk_stmt(s.else_stmt, dot_offset, found)
		case ^misl.Case_Clause:
			for st in s.body { walk_stmt(st, dot_offset, found) }
		}
	}

	if mod == nil do return nil
	for decl in mod.decls {
		walk_stmt(decl, dot_offset, &found)
	}
	return found
}

type_from_expr_entity :: proc(expr: ^misl.Expr) -> ^misl.Type {
	if expr == nil do return nil
	#partial switch e in expr.derived_expr {
	case ^misl.Ident:
		if e.tav.type != nil do return e.tav.type
		if e.entity != nil do return e.entity.type
	case ^misl.Paren_Expr:
		return type_from_expr_entity(e.expr)
	case ^misl.Index_Expr:
		if e.tav.type != nil do return e.tav.type
		base := type_from_expr_entity(e.expr)
		if base == nil && e.expr != nil do base = e.expr.tav.type
		if base == nil do return nil
		#partial switch t in base.derived {
		case ^misl.Type_Multi_Pointer:
			return t.elem
		case ^misl.Type_Array:
			return t.elem
		case ^misl.Type_Slice:
			return t.elem
		case ^misl.Type_Vector:
			return t.elem
		}
	case ^misl.Deref_Expr:
		inner := type_from_expr_entity(e.expr)
		if inner == nil && e.expr != nil do inner = e.expr.tav.type
		if inner == nil do return nil
		if pt, ok := inner.derived.(^misl.Type_Pointer); ok {
			return pt.elem
		}
		return inner
	case ^misl.Selector_Expr:
		if e.field != nil {
			if e.field.tav.type != nil do return e.field.tav.type
			if e.field.entity != nil do return e.field.entity.type
		}
		if e.tav.type != nil do return e.tav.type
	}
	if expr.tav.type != nil do return expr.tav.type
	return nil
}

append_scope_entities :: proc(items: ^[dynamic]lsp.Completion_Item, seen: ^map[string]bool, scope: ^misl.Scope) {
	if scope == nil do return
	for name, e in scope.entities {
		if e == nil || name == "" || name == "_" do continue
		if name in seen^ do continue
		seen^[name] = true
		append(items, completion_item_for_entity(name, e))
	}
	append_scope_entities(items, seen, scope.outer)
}

append_type_fields :: proc(items: ^[dynamic]lsp.Completion_Item, type: ^misl.Type) {
	type := type_peel_single_pointers(type)
	if type == nil do return
	#partial switch t in type.derived {
	case ^misl.Type_Struct:
		if t.scope != nil {
			for name, e in t.scope.entities {
				if e == nil || name == "" || name == "_" do continue
				append(items, lsp.Completion_Item{label = name, kind = .Field})
			}
			return
		}
		if t.fields != nil {
			for f in t.fields.variables {
				if f == nil || f.name == "" do continue
				append(items, lsp.Completion_Item{label = f.name, kind = .Field})
			}
		}
	case ^misl.Type_Enum:
		if t.scope != nil {
			for name, e in t.scope.entities {
				if e == nil || name == "" do continue
				append(items, lsp.Completion_Item{label = name, kind = .Enum_Member})
			}
			return
		}
		for f in t.fields {
			if f == nil || f.name == "" do continue
			append(items, lsp.Completion_Item{label = f.name, kind = .Enum_Member})
		}
	case ^misl.Type_Vector:
		comps := "xyzw"
		n := min(t.len, 4)
		if n > 0 {
			for i in 0 ..< n {
				append(items, lsp.Completion_Item{label = comps[i:i+1], kind = .Property})
			}
		}
	}
}

// Implicit-deref for field completion: ^T / ^^T → T.
// Multipointers are NOT peeled — they index like arrays (`mp[i]` → T).
type_peel_single_pointers :: proc(type: ^misl.Type) -> ^misl.Type {
	type := type
	for type != nil {
		#partial switch t in type.derived {
		case ^misl.Type_Pointer:
			type = t.elem
		case:
			return type
		}
	}
	return nil
}

// True when '.' is an implicit selector (`.Val`), not `lhs.`.
is_implicit_selector_dot :: proc(text: string, dot_offset: int) -> bool {
	if dot_offset <= 0 do return true
	c := text[dot_offset - 1]
	if c == '_' ||
		(c >= 'a' && c <= 'z') ||
		(c >= 'A' && c <= 'Z') ||
		(c >= '0' && c <= '9') ||
		c == ')' || c == ']' {
		return false
	}
	return true
}

// Expected enum type near a '.' (assignment type, call arg, `==`/`!=`, `in`/`not_in` bit-set elem).
type_as_enum_for_completion :: proc(type: ^misl.Type) -> ^misl.Type {
	type := type_peel_single_pointers(type)
	if type == nil do return nil
	if _, ok := type.derived.(^misl.Type_Enum); ok do return type
	if bs, ok := type.derived.(^misl.Type_Bit_Set); ok {
		return type_as_enum_for_completion(bs.elem)
	}
	return nil
}

expected_enum_type_at :: proc(mod: ^misl.Module, dot_offset: int) -> ^misl.Type {
	found: ^misl.Type

	walk_expr :: proc(expr: ^misl.Expr, dot_offset: int, found: ^^misl.Type) {
		if expr == nil || found^ != nil do return
		#partial switch e in expr.derived_expr {
		case ^misl.Implicit_Selector_Expr:
			if e.pos.offset <= dot_offset && (e.end.offset == 0 || e.end.offset >= dot_offset) {
				if e.tav.type != nil {
					if t := type_as_enum_for_completion(e.tav.type); t != nil {
						found^ = t
						return
					}
				}
			}
		case ^misl.Selector_Expr:
			if e.op.pos.offset == dot_offset {
				if e.expr != nil && e.expr.tav.type != nil {
					if t := type_as_enum_for_completion(e.expr.tav.type); t != nil {
						found^ = t
						return
					}
				}
			}
			walk_expr(e.expr, dot_offset, found)
		case ^misl.Binary_Expr:
			walk_expr(e.left, dot_offset, found)
			walk_expr(e.right, dot_offset, found)
			if found^ != nil do return
			// `.A in s` — hint from bit-set elem on the right.
			if e.op.kind == .In || e.op.kind == .Not_In {
				if e.left != nil && offset_near_expr(e.left, dot_offset) {
					if t := type_as_enum_for_completion(e.right.tav.type if e.right != nil else nil); t != nil {
						found^ = t
					}
				}
				return
			}
			// `x == .` / `x != .` — hint from the left-hand type.
			if e.op.kind == .Cmp_Eq || e.op.kind == .Not_Eq {
				if e.right != nil && offset_near_expr(e.right, dot_offset) {
					if t := type_as_enum_for_completion(e.left.tav.type if e.left != nil else nil); t != nil {
						found^ = t
					}
				}
			}
		case ^misl.Call_Expr:
			walk_expr(e.expr, dot_offset, found)
			for arg in e.args { walk_expr(arg, dot_offset, found) }
		case ^misl.Paren_Expr:
			walk_expr(e.expr, dot_offset, found)
		case ^misl.Unary_Expr:
			walk_expr(e.expr, dot_offset, found)
		case ^misl.Index_Expr:
			walk_expr(e.expr, dot_offset, found)
			walk_expr(e.index, dot_offset, found)
		case ^misl.Comp_Lit:
			if t := type_as_enum_for_completion(e.type.tav.type if e.type != nil else nil); t != nil {
				for elem in e.elems {
					if offset_near_expr(elem, dot_offset) {
						found^ = t
						return
					}
					walk_expr(elem, dot_offset, found)
				}
			} else {
				for elem in e.elems { walk_expr(elem, dot_offset, found) }
			}
		case ^misl.Field_Value:
			walk_expr(e.value, dot_offset, found)
		case ^misl.Proc_Lit:
			walk_stmt(e.body, dot_offset, found)
		}
	}

	walk_stmt :: proc(stmt: ^misl.Stmt, dot_offset: int, found: ^^misl.Type) {
		if stmt == nil || found^ != nil do return
		#partial switch s in stmt.derived_stmt {
		case ^misl.Block_Stmt:
			for st in s.stmts { walk_stmt(st, dot_offset, found) }
		case ^misl.Expr_Stmt:
			walk_expr(s.expr, dot_offset, found)
		case ^misl.Assign_Stmt:
			for lhs in s.lhs { walk_expr(lhs, dot_offset, found) }
			for i in 0 ..< len(s.rhs) {
				walk_expr(s.rhs[i], dot_offset, found)
				if found^ != nil do return
				if offset_near_expr(s.rhs[i], dot_offset) && i < len(s.lhs) {
					if t := type_as_enum_for_completion(s.lhs[i].tav.type if s.lhs[i] != nil else nil); t != nil {
						found^ = t
					}
				}
			}
		case ^misl.Value_Decl:
			decl_type := type_as_enum_for_completion(s.type.tav.type if s.type != nil else nil)
			for val in s.values {
				walk_expr(val, dot_offset, found)
				if found^ != nil do return
				if decl_type != nil && offset_near_expr(val, dot_offset) {
					found^ = decl_type
				}
			}
			walk_expr(s.type, dot_offset, found)
		case ^misl.Return_Stmt:
			for r in s.results { walk_expr(r, dot_offset, found) }
		case ^misl.If_Stmt:
			walk_stmt(s.init, dot_offset, found)
			walk_expr(s.cond, dot_offset, found)
			walk_stmt(s.body, dot_offset, found)
			walk_stmt(s.else_stmt, dot_offset, found)
		case ^misl.For_Stmt:
			walk_stmt(s.init, dot_offset, found)
			walk_expr(s.cond, dot_offset, found)
			walk_stmt(s.post, dot_offset, found)
			walk_stmt(s.body, dot_offset, found)
		case ^misl.Range_Stmt:
			walk_expr(s.expr, dot_offset, found)
			walk_stmt(s.body, dot_offset, found)
		case ^misl.Switch_Stmt:
			walk_stmt(s.init, dot_offset, found)
			walk_expr(s.cond, dot_offset, found)
			walk_stmt(s.body, dot_offset, found)
		case ^misl.Which_Stmt:
			walk_expr(s.cond, dot_offset, found)
			walk_stmt(s.body, dot_offset, found)
		case ^misl.When_Stmt:
			walk_expr(s.cond, dot_offset, found)
			walk_stmt(s.body, dot_offset, found)
			walk_stmt(s.else_stmt, dot_offset, found)
		case ^misl.Case_Clause:
			for st in s.body { walk_stmt(st, dot_offset, found) }
		}
	}

	if mod == nil do return nil
	for decl in mod.decls {
		walk_stmt(decl, dot_offset, &found)
	}
	return found
}

offset_near_expr :: proc(expr: ^misl.Expr, offset: int) -> bool {
	if expr == nil do return false
	lo := expr.pos.offset
	hi := expr.end.offset if expr.end.offset > lo else lo + 1
	// Allow cursor just after incomplete `.`
	return offset >= lo && offset <= hi + 1
}

append_all_enum_members_in_scope :: proc(items: ^[dynamic]lsp.Completion_Item, seen: ^map[string]bool, scope: ^misl.Scope) {
	if scope == nil do return
	for _, e in scope.entities {
		if e == nil || e.kind != .Type_Name || e.type == nil do continue
		enum_t, ok := e.type.derived.(^misl.Type_Enum)
		if !ok do continue
		if enum_t.scope != nil {
			for name, mem in enum_t.scope.entities {
				if mem == nil || name == "" || name in seen^ do continue
				seen^[name] = true
				append(items, lsp.Completion_Item{label = name, kind = .Enum_Member})
			}
		} else {
			for f in enum_t.fields {
				if f == nil || f.name == "" || f.name in seen^ do continue
				seen^[f.name] = true
				append(items, lsp.Completion_Item{label = f.name, kind = .Enum_Member})
			}
		}
	}
	append_all_enum_members_in_scope(items, seen, scope.outer)
}

// --- Semantic (`| SV_*`) completion -----------------------------------------

Semantic_Slot :: enum {
	None,
	Struct_Field,
	Proc_Param,
	Proc_Result,
}

find_semantic_pipe :: proc(text: string, offset: int) -> (pipe: int, prefix: string, ok: bool) {
	if offset <= 0 || offset > len(text) do return
	i := offset
	for i > 0 && is_ident_byte(text[i - 1]) {
		i -= 1
	}
	prefix_start := i
	for i > 0 && (text[i - 1] == ' ' || text[i - 1] == '\t') {
		i -= 1
	}
	if i <= 0 || text[i - 1] != '|' do return
	pipe = i - 1
	// `||` is not a semantic introducer
	if pipe > 0 && text[pipe - 1] == '|' do return
	prefix = text[prefix_start:offset]
	ok = true
	return
}

is_ident_byte :: proc(c: u8) -> bool {
	return c == '_' ||
		(c >= 'a' && c <= 'z') ||
		(c >= 'A' && c <= 'Z') ||
		(c >= '0' && c <= '9')
}

append_semantic_completions :: proc(items: ^[dynamic]lsp.Completion_Item, allowed: misl.Semantics, prefix: string) {
	infos := misl.semantic_names
	for info, kind in infos {
		if kind == .None || kind == .Custom do continue
		if kind not_in allowed do continue
		if info.name == "" do continue
		if prefix != "" && !starts_with(info.name, prefix) do continue
		item := lsp.Completion_Item{label = info.name, kind = .Enum_Member}
		item.documentation = lsp.Markup_Content{
			kind  = "markdown",
			value = markdown_fence_with_docs(info.name, info.docs),
		}
		append(items, item)
	}
}

starts_with :: proc(s, prefix: string) -> bool {
	return len(prefix) <= len(s) && s[:len(prefix)] == prefix
}

stage_from_cc :: proc(cc: string) -> (stage: misl.Stage, ok: bool) {
	switch cc {
	case "vertex", "vert", "vs":
		return .Vertex, true
	case "fragment", "frag", "fs", "pixel", "ps":
		return .Fragment, true
	case "compute", "comp", "cs":
		return .Compute, true
	}
	return {}, false
}

allowed_semantics_for_slot :: proc(slot: Semantic_Slot, stage: misl.Stage, has_stage: bool) -> (allowed: misl.Semantics, ok: bool) {
	switch slot {
	case .None:
		return {}, false
	case .Struct_Field:
		return misl.Allowed_Semantics_Struct_Fields, true
	case .Proc_Param:
		if !has_stage do return {}, true // unstaged / proc "fmag": no SV_*; still a semantic slot
		switch stage {
		case .Compute:
			return misl.Allowed_Semantics_Compute_Params, true
		case .Vertex, .Fragment:
			return misl.Allowed_Semantics_Shader_Params, true
		}
	case .Proc_Result:
		if !has_stage do return {}, true
		switch stage {
		case .Vertex, .Fragment:
			return misl.Allowed_Semantics_Shader_Results, true
		case .Compute:
			return {}, true
		}
	}
	return {}, false
}

field_list_contains_offset :: proc(fl: ^misl.Field_List, offset: int) -> bool {
	if fl == nil do return false
	lo := fl.pos.offset
	hi := fl.end.offset if fl.end.offset > lo else lo
	if fl.open.offset > 0 {
		lo = fl.open.offset
	}
	if fl.close.offset > lo {
		hi = fl.close.offset
	}
	if hi > lo {
		return offset >= lo && offset <= hi
	}
	for f in fl.list {
		if f == nil do continue
		flo := f.pos.offset
		fhi := f.end.offset if f.end.offset > flo else flo + 1
		if f.semantics != nil {
			fhi = max(fhi, f.semantics.end.offset if f.semantics.end.offset > 0 else f.semantics.pos.offset + len(f.semantics.name))
		}
		if offset >= flo && offset <= fhi + 1 {
			return true
		}
	}
	return false
}

// Resolve which semantic set applies at `pipe_offset` (byte index of `|`).
allowed_semantics_at :: proc(mod: ^misl.Module, text: string, pipe_offset: int) -> (allowed: misl.Semantics, ok: bool) {
	slot: Semantic_Slot
	stage: misl.Stage
	has_stage: bool
	found: bool

	consider_field_list :: proc(fl: ^misl.Field_List, pipe_offset: int, want: Semantic_Slot, slot: ^Semantic_Slot, found: ^bool) {
		if found^ || fl == nil do return
		if field_list_contains_offset(fl, pipe_offset) {
			slot^ = want
			found^ = true
		}
	}

	walk_expr :: proc(expr: ^misl.Expr, pipe_offset: int, slot: ^Semantic_Slot, stage: ^misl.Stage, has_stage: ^bool, found: ^bool) {
		if expr == nil || found^ do return
		#partial switch e in expr.derived_expr {
		case ^misl.Struct_Type:
			consider_field_list(e.fields, pipe_offset, .Struct_Field, slot, found)
		case ^misl.Proc_Type:
			st, st_ok := stage_from_cc(e.calling_convention)
			in_params := field_list_contains_offset(e.params, pipe_offset)
			in_results := field_list_contains_offset(e.results, pipe_offset)
			if in_params || in_results {
				slot^ = .Proc_Param if in_params else .Proc_Result
				stage^ = st
				has_stage^ = st_ok
				found^ = true
				return
			}
			consider_field_list(e.params, pipe_offset, .Proc_Param, slot, found)
			if found^ {
				stage^ = st
				has_stage^ = st_ok
				return
			}
			consider_field_list(e.results, pipe_offset, .Proc_Result, slot, found)
			if found^ {
				stage^ = st
				has_stage^ = st_ok
			}
		case ^misl.Proc_Lit:
			walk_expr(e.type, pipe_offset, slot, stage, has_stage, found)
			walk_stmt(e.body, pipe_offset, slot, stage, has_stage, found)
		case ^misl.Helper_Type, ^misl.Distinct_Type:
			#partial switch x in expr.derived_expr {
			case ^misl.Helper_Type: walk_expr(x.type, pipe_offset, slot, stage, has_stage, found)
			case ^misl.Distinct_Type: walk_expr(x.type, pipe_offset, slot, stage, has_stage, found)
			}
		case ^misl.Pointer_Type:
			walk_expr(e.elem, pipe_offset, slot, stage, has_stage, found)
		case ^misl.Array_Type:
			walk_expr(e.elem, pipe_offset, slot, stage, has_stage, found)
		case ^misl.Paren_Expr:
			walk_expr(e.expr, pipe_offset, slot, stage, has_stage, found)
		}
	}

	walk_stmt :: proc(stmt: ^misl.Stmt, pipe_offset: int, slot: ^Semantic_Slot, stage: ^misl.Stage, has_stage: ^bool, found: ^bool) {
		if stmt == nil || found^ do return
		#partial switch s in stmt.derived_stmt {
		case ^misl.Value_Decl:
			walk_expr(s.type, pipe_offset, slot, stage, has_stage, found)
			for v in s.values { walk_expr(v, pipe_offset, slot, stage, has_stage, found) }
		case ^misl.Block_Stmt:
			for st in s.stmts { walk_stmt(st, pipe_offset, slot, stage, has_stage, found) }
		case ^misl.Expr_Stmt:
			walk_expr(s.expr, pipe_offset, slot, stage, has_stage, found)
		}
	}

	if mod != nil {
		for decl in mod.decls {
			walk_stmt(decl, pipe_offset, &slot, &stage, &has_stage, &found)
			if found do break
		}
	}

	if found {
		return allowed_semantics_for_slot(slot, stage, has_stage)
	}
	return allowed_semantics_from_text(text, pipe_offset)
}

// Textual fallback when the AST did not capture an incomplete `|` slot.
allowed_semantics_from_text :: proc(text: string, pipe_offset: int) -> (allowed: misl.Semantics, ok: bool) {
	if pipe_offset <= 0 || pipe_offset >= len(text) do return {}, false

	// Must look like a field type slot: `name: <type> |`
	// Reject binary-or in expressions (`a | b`) — require a `:` earlier on the same
	// statement / field (after `,` / `;` / `{` / `(`).
	line_start := pipe_offset
	for line_start > 0 && text[line_start - 1] != '\n' {
		line_start -= 1
	}
	seg := text[line_start:pipe_offset]
	colon := -1
	for i := len(seg) - 1; i >= 0; i -= 1 {
		c := seg[i]
		if c == ':' {
			colon = i
			break
		}
		if c == ',' || c == ';' || c == '{' || c == '(' {
			break
		}
	}
	if colon < 0 do return {}, false

	// Enclosing proc stage / struct from preceding text (nearest wins).
	before := text[:pipe_offset]
	struct_at := last_index(before, "struct")
	proc_at := last_index(before, "proc")
	arrow_at := last_index(before, "->")

	if struct_at > proc_at {
		// Ensure a `{` opened after struct and wasn't closed before the pipe.
		open := index_from(before, "{", struct_at)
		if open >= 0 && brace_depth(before[open:pipe_offset]) > 0 {
			return misl.Allowed_Semantics_Struct_Fields, true
		}
	}

	if proc_at >= 0 {
		cc := calling_convention_after_proc(before, proc_at)
		stage, has_stage := stage_from_cc(cc)
		// Results if `->` appears after this proc and before the pipe.
		if arrow_at > proc_at {
			return allowed_semantics_for_slot(.Proc_Result, stage, has_stage)
		}
		return allowed_semantics_for_slot(.Proc_Param, stage, has_stage)
	}
	return {}, false
}

last_index :: proc(s, sub: string) -> int {
	if sub == "" do return len(s)
	last := -1
	for i := 0; i + len(sub) <= len(s); i += 1 {
		if s[i:i+len(sub)] == sub {
			// word-ish: not mid-ident
			left_ok := i == 0 || !is_ident_byte(s[i - 1])
			right_ok := i + len(sub) >= len(s) || !is_ident_byte(s[i + len(sub)])
			if left_ok && right_ok {
				last = i
			}
		}
	}
	return last
}

index_from :: proc(s, sub: string, start: int) -> int {
	i := start if start >= 0 else 0
	if i > len(s) do return -1
	for ; i + len(sub) <= len(s); i += 1 {
		if s[i:i+len(sub)] == sub do return i
	}
	return -1
}

brace_depth :: proc(s: string) -> int {
	depth := 0
	for i in 0 ..< len(s) {
		switch s[i] {
		case '{': depth += 1
		case '}': depth -= 1
		}
	}
	return depth
}

calling_convention_after_proc :: proc(text: string, proc_at: int) -> string {
	i := proc_at + len("proc")
	for i < len(text) && (text[i] == ' ' || text[i] == '\t' || text[i] == '\n' || text[i] == '\r') {
		i += 1
	}
	if i >= len(text) || text[i] != '"' do return ""
	i += 1
	start := i
	for i < len(text) && text[i] != '"' {
		i += 1
	}
	if i >= len(text) do return ""
	return text[start:i]
}

