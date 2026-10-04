package misl_lsp

import "core:fmt"
import "oge:misl"
import "./lsp"

inlay_position_in_range :: proc(pos: lsp.Position, range: lsp.Range) -> bool {
	if pos.line < range.start.line || pos.line > range.end.line do return false
	if pos.line == range.start.line && pos.character < range.start.character do return false
	if pos.line == range.end.line && pos.character > range.end.character do return false
	return true
}

inlay_call_entity :: proc(call: ^misl.Call_Expr) -> ^misl.Entity {
	if call == nil || call.expr == nil do return nil
	#partial switch callee in call.expr.derived_expr {
	case ^misl.Ident:
		return callee.entity
	case ^misl.Selector_Expr:
		if callee.field != nil do return callee.field.entity
	}
	return nil
}

inlay_hints :: proc(ws: ^Workspace, params: lsp.Inlay_Hint_Params, allocator := context.temp_allocator) -> []lsp.Inlay_Hint {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil do return nil
	workspace_flush(ws)
	parsed := ws.modules_by_path[doc.path]
	if parsed == nil do return nil

	hints := make([dynamic]lsp.Inlay_Hint, allocator)

	append_hint :: proc(hints: ^[dynamic]lsp.Inlay_Hint, pos: misl.Token_Pos, label: string, doc_text: string, requested: lsp.Range) {
		if label == "" do return
		lsp_pos := token_pos_to_lsp_position(pos, doc_text)
		if !inlay_position_in_range(lsp_pos, requested) do return
		append(hints, lsp.Inlay_Hint{
			position = lsp_pos,
			kind = .Parameter,
			label = label,
		})
	}

	add_call_hints :: proc(call: ^misl.Call_Expr, hints: ^[dynamic]lsp.Inlay_Hint, doc_text: string, requested: lsp.Range) {
		entity := inlay_call_entity(call)
		if entity == nil do return

		if id, ok := misl.entity_compiler_builtin(entity); ok {
			sig := misl.builtin_sigs[id]
			slots: []misl.Printf_Slot_Kind
			if sig.kind == .Printf && len(call.args) > 0 {
				arg0 := call.args[0]
				if arg0 != nil {
					if format, ok := arg0.tav.value.(string); ok {
						slots, _ = misl.printf_scan_slots(format, context.temp_allocator)
					}
				}
			}
			for arg, i in call.args {
				if arg == nil do continue
				if _, named := arg.derived_expr.(^misl.Field_Value); named do continue
				label := ""
				if i < len(sig.params) {
					label = fmt.tprintf("%s:", sig.params[i].name)
				} else if sig.kind == .Printf && i > 0 && i - 1 < len(slots) {
					spec := "%v" if slots[i - 1] == .Compact else "%#v"
					label = fmt.tprintf("%s:", spec)
				}
				if label != "" {
					append_hint(hints, arg.pos, label, doc_text, requested)
				}
			}
			return
		}

		proc_type, ok := proc_type_for_display(entity.type)
		if !ok || proc_type == nil || proc_type.params == nil do return
		for arg, i in call.args {
			if arg == nil || i >= len(proc_type.params.variables) do continue
			if _, named := arg.derived_expr.(^misl.Field_Value); named do continue
			param := proc_type.params.variables[i]
			if param == nil || param.name == "" do continue
			append_hint(hints, arg.pos, fmt.tprintf("%s:", hover_param_name(param)), doc_text, requested)
		}
	}

	add_comp_lit_hints :: proc(lit: ^misl.Comp_Lit, hints: ^[dynamic]lsp.Inlay_Hint, doc_text: string, requested: lsp.Range) {
		if lit == nil do return
		type := lit.tav.type
		if type == nil && lit.type != nil {
			type = lit.type.tav.type
			if type == nil {
				type = type_from_expr_entity(lit.type)
			}
		}
		type = type_peel_single_pointers(type)
		st: ^misl.Type_Struct
		ok: bool
		if type != nil {
			st, ok = type.derived.(^misl.Type_Struct)
		}
		if !ok || st == nil || st.fields == nil do return
		for elem, i in lit.elems {
			if elem == nil || i >= len(st.fields.variables) do continue
			if _, named := elem.derived_expr.(^misl.Field_Value); named do continue
			field := st.fields.variables[i]
			if field == nil || field.name == "" do continue
			append_hint(hints, elem.pos, fmt.tprintf("%s:", field.name), doc_text, requested)
		}
	}

	walk_expr :: proc(expr: ^misl.Expr, hints: ^[dynamic]lsp.Inlay_Hint, doc_text: string, requested: lsp.Range) {
		if expr == nil do return
		#partial switch e in expr.derived_expr {
		case ^misl.Call_Expr:
			add_call_hints(e, hints, doc_text, requested)
			walk_expr(e.expr, hints, doc_text, requested)
			for arg in e.args { walk_expr(arg, hints, doc_text, requested) }
		case ^misl.Comp_Lit:
			add_comp_lit_hints(e, hints, doc_text, requested)
			walk_expr(e.type, hints, doc_text, requested)
			for elem in e.elems { walk_expr(elem, hints, doc_text, requested) }
		case ^misl.Field_Value:
			walk_expr(e.field, hints, doc_text, requested)
			walk_expr(e.value, hints, doc_text, requested)
		case ^misl.Proc_Lit:
			walk_expr(e.type, hints, doc_text, requested)
			walk_stmt(e.body, hints, doc_text, requested)
		case ^misl.Selector_Call_Expr:
			walk_expr(e.expr, hints, doc_text, requested)
			walk_expr(e.call, hints, doc_text, requested)
		case ^misl.Unary_Expr:
			walk_expr(e.expr, hints, doc_text, requested)
		case ^misl.Binary_Expr:
			walk_expr(e.left, hints, doc_text, requested)
			walk_expr(e.right, hints, doc_text, requested)
		case ^misl.Paren_Expr:
			walk_expr(e.expr, hints, doc_text, requested)
		case ^misl.Selector_Expr:
			walk_expr(e.expr, hints, doc_text, requested)
		case ^misl.Index_Expr:
			walk_expr(e.expr, hints, doc_text, requested)
			walk_expr(e.index, hints, doc_text, requested)
		case ^misl.Deref_Expr:
			walk_expr(e.expr, hints, doc_text, requested)
		case ^misl.Slice_Expr:
			walk_expr(e.expr, hints, doc_text, requested)
			walk_expr(e.low, hints, doc_text, requested)
			walk_expr(e.high, hints, doc_text, requested)
		case ^misl.Matrix_Index_Expr:
			walk_expr(e.expr, hints, doc_text, requested)
			walk_expr(e.row_index, hints, doc_text, requested)
			walk_expr(e.column_index, hints, doc_text, requested)
		case ^misl.Ternary_If_Expr:
			walk_expr(e.x, hints, doc_text, requested)
			walk_expr(e.cond, hints, doc_text, requested)
			walk_expr(e.y, hints, doc_text, requested)
		case ^misl.Ternary_When_Expr:
			walk_expr(e.x, hints, doc_text, requested)
			walk_expr(e.cond, hints, doc_text, requested)
			walk_expr(e.y, hints, doc_text, requested)
		case ^misl.Type_Cast:
			walk_expr(e.type, hints, doc_text, requested)
			walk_expr(e.expr, hints, doc_text, requested)
		case ^misl.Auto_Cast:
			walk_expr(e.expr, hints, doc_text, requested)
		case ^misl.Ellipsis:
			walk_expr(e.expr, hints, doc_text, requested)
		case ^misl.Struct_Type:
			walk_field_list(e.fields, hints, doc_text, requested)
		case ^misl.Proc_Type:
			walk_field_list(e.params, hints, doc_text, requested)
			walk_field_list(e.results, hints, doc_text, requested)
		case ^misl.Pointer_Type:
			walk_expr(e.elem, hints, doc_text, requested)
		case ^misl.Multi_Pointer_Type:
			walk_expr(e.elem, hints, doc_text, requested)
		case ^misl.Array_Type:
			walk_expr(e.len, hints, doc_text, requested)
			walk_expr(e.elem, hints, doc_text, requested)
		case ^misl.Enum_Type:
			for field in e.fields { walk_expr(field, hints, doc_text, requested) }
		case ^misl.Bit_Set_Type:
			walk_expr(e.elem, hints, doc_text, requested)
			walk_expr(e.underlying, hints, doc_text, requested)
		case ^misl.Matrix_Type:
			walk_expr(e.row_count, hints, doc_text, requested)
			walk_expr(e.column_count, hints, doc_text, requested)
			walk_expr(e.elem, hints, doc_text, requested)
		case ^misl.Distinct_Type:
			walk_expr(e.type, hints, doc_text, requested)
		case ^misl.Helper_Type:
			walk_expr(e.type, hints, doc_text, requested)
		}
	}

	walk_field_list :: proc(list: ^misl.Field_List, hints: ^[dynamic]lsp.Inlay_Hint, doc_text: string, requested: lsp.Range) {
		if list == nil do return
		for field in list.list {
			if field == nil do continue
			walk_expr(field.type, hints, doc_text, requested)
			walk_expr(field.default_value, hints, doc_text, requested)
		}
	}

	walk_stmt :: proc(stmt: ^misl.Stmt, hints: ^[dynamic]lsp.Inlay_Hint, doc_text: string, requested: lsp.Range) {
		if stmt == nil do return
		#partial switch s in stmt.derived_stmt {
		case ^misl.Expr_Stmt:
			walk_expr(s.expr, hints, doc_text, requested)
		case ^misl.Tag_Stmt:
			walk_stmt(s.stmt, hints, doc_text, requested)
		case ^misl.Assign_Stmt:
			for lhs in s.lhs { walk_expr(lhs, hints, doc_text, requested) }
			for rhs in s.rhs { walk_expr(rhs, hints, doc_text, requested) }
		case ^misl.Block_Stmt:
			for st in s.stmts { walk_stmt(st, hints, doc_text, requested) }
		case ^misl.If_Stmt:
			walk_stmt(s.init, hints, doc_text, requested)
			walk_expr(s.cond, hints, doc_text, requested)
			walk_stmt(s.body, hints, doc_text, requested)
			walk_stmt(s.else_stmt, hints, doc_text, requested)
		case ^misl.When_Stmt:
			walk_expr(s.cond, hints, doc_text, requested)
			walk_stmt(s.body, hints, doc_text, requested)
			walk_stmt(s.else_stmt, hints, doc_text, requested)
		case ^misl.Which_Stmt:
			walk_expr(s.cond, hints, doc_text, requested)
			walk_stmt(s.body, hints, doc_text, requested)
		case ^misl.Return_Stmt:
			for result in s.results { walk_expr(result, hints, doc_text, requested) }
		case ^misl.For_Stmt:
			walk_stmt(s.init, hints, doc_text, requested)
			walk_expr(s.cond, hints, doc_text, requested)
			walk_stmt(s.post, hints, doc_text, requested)
			walk_stmt(s.body, hints, doc_text, requested)
		case ^misl.Range_Stmt:
			walk_expr(s.expr, hints, doc_text, requested)
			walk_stmt(s.body, hints, doc_text, requested)
		case ^misl.Switch_Stmt:
			walk_stmt(s.init, hints, doc_text, requested)
			walk_expr(s.cond, hints, doc_text, requested)
			walk_stmt(s.body, hints, doc_text, requested)
		case ^misl.Case_Clause:
			for value in s.list { walk_expr(value, hints, doc_text, requested) }
			for st in s.body { walk_stmt(st, hints, doc_text, requested) }
		case ^misl.Using_Stmt:
			for value in s.list { walk_expr(value, hints, doc_text, requested) }
		case ^misl.Value_Decl:
			walk_expr(s.type, hints, doc_text, requested)
			for value in s.values { walk_expr(value, hints, doc_text, requested) }
		}
	}

	mods := [2]^misl.Module{
		workspace_check_parsed(ws, parsed, ws.target),
		nil,
	}
	if misl.module_has_fmag_entry(parsed) {
		mods[1] = workspace_check_parsed(ws, parsed, workspace_target_fmag(ws))
	}
	for mod in mods {
		if mod == nil do continue
		for decl in mod.decls {
			walk_stmt(decl, &hints, doc.text, params.range)
		}
	}
	if len(hints) < 2 {
		return hints[:]
	}
	seen := make(map[string]bool, context.temp_allocator)
	uniq := make([dynamic]lsp.Inlay_Hint, allocator)
	for h in hints {
		key := fmt.tprintf("%d:%d:%s", h.position.line, h.position.character, h.label)
		if seen[key] do continue
		seen[key] = true
		append(&uniq, h)
	}
	return uniq[:]
}
