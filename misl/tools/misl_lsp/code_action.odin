package misl_lsp

import "core:fmt"
import "core:mem"
import "core:strings"
import "oge:misl"
import "./lsp"

Code_Action_Walk_Data :: struct {
	actions:       ^[dynamic]lsp.Code_Action,
	doc:           ^Document,
	uri:           string,
	request_start: int,
	request_end:   int,
	allocator:     mem.Allocator,
}

line_indentation_at :: proc(text: string, offset: int) -> string {
	offset := offset
	offset = clamp(offset, 0, len(text))
	start := offset
	for start > 0 && text[start - 1] != '\n' && text[start - 1] != '\r' {
		start -= 1
	}
	end := start
	for end < len(text) && (text[end] == ' ' || text[end] == '\t') {
		end += 1
	}
	return text[start:end]
}

stage_stub_kind :: proc(cc: string) -> string {
	switch cc {
	case "vertex", "vs":
		return "vertex"
	case "fragment", "fs":
		return "fragment"
	case "compute", "cs":
		return "compute"
	case "fmag":
		return "fmag"
	}
	return ""
}

offset_ranges_overlap :: proc(a_start, a_end, b_start, b_end: int) -> bool {
	a_end := max(a_end, a_start)
	b_end := max(b_end, b_start)
	return a_start <= b_end && b_start <= a_end
}

code_action_edit :: proc(
	uri: string,
	version: int,
	range: lsp.Range,
	new_text: string,
	allocator: mem.Allocator,
) -> lsp.Workspace_Edit {
	edits := make([]lsp.Text_Edit, 1, allocator)
	edits[0] = {range = range, new_text = new_text}
	doc_edits := make([]lsp.Text_Document_Edit, 1, allocator)
	doc_edits[0] = {
		textDocument = {uri = uri, version = version},
		edits = edits,
	}
	return {documentChanges = doc_edits}
}

code_actions :: proc(ws: ^Workspace, params: lsp.Code_Action_Params, allocator := context.temp_allocator) -> []lsp.Code_Action {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil do return nil
	request_start, start_ok := offset_from_position(doc.text, params.range.start)
	request_end, end_ok := offset_from_position(doc.text, params.range.end)
	if !start_ok || !end_ok do return nil
	mod := workspace_module_for_uri(ws, params.text_document.uri, request_start)
	if mod == nil do return nil

	actions := make([dynamic]lsp.Code_Action, allocator)

	add_enum_case_fill_action :: proc(
		cond: ^misl.Expr,
		body_stmt: ^misl.Stmt,
		partial: bool,
		pos, end: misl.Token_Pos,
		title: string,
		actions: ^[dynamic]lsp.Code_Action,
		doc: ^Document,
		uri: string,
		request_start, request_end: int,
		allocator: mem.Allocator,
	) {
		if partial || cond == nil do return
		if !offset_ranges_overlap(
			pos.offset,
			end.offset,
			request_start,
			request_end,
		) {
			return
		}

		enum_type: ^misl.Type_Enum
		is_enum: bool
		if cond.tav.type != nil {
			enum_type, is_enum = cond.tav.type.derived.(^misl.Type_Enum)
		}
		if !is_enum || enum_type == nil do return
		body: ^misl.Block_Stmt
		body_ok: bool
		if body_stmt != nil {
			body, body_ok = body_stmt.derived_stmt.(^misl.Block_Stmt)
		}
		if !body_ok || body == nil do return

		seen := make(map[^misl.Entity]bool, allocator)
		seen_names := make(map[string]bool, allocator)
		for stmt in body.stmts {
			clause, ok := stmt.derived_stmt.(^misl.Case_Clause)
			if !ok do continue
			if len(clause.list) == 0 {
				return // A default clause already makes the switch exhaustive.
			}
			for value in clause.list {
				if value == nil do continue
				#partial switch v in value.derived_expr {
				case ^misl.Implicit_Selector_Expr:
					if v.field != nil {
						if v.field.entity != nil do seen[v.field.entity] = true
						seen_names[v.field.name] = true
					}
				case ^misl.Selector_Expr:
					if v.field != nil {
						if v.field.entity != nil do seen[v.field.entity] = true
						seen_names[v.field.name] = true
					}
				case ^misl.Ident:
					if v.entity != nil do seen[v.entity] = true
					seen_names[v.name] = true
				}
			}
		}

		missing := make([dynamic]^misl.Entity, allocator)
		for field in enum_type.fields {
			if field == nil || field.name == "" do continue
			if field in seen || field.name in seen_names do continue
			append(&missing, field)
		}
		if len(missing) == 0 do return

		insert_offset := body.close.offset
		if insert_offset <= body.open.offset || insert_offset > len(doc.text) {
			insert_offset = clamp(body.end.offset, 0, len(doc.text))
		}
		indent := line_indentation_at(doc.text, insert_offset)
		case_indent := fmt.tprintf("%s\t", indent)
		newline := "\r\n" if strings.contains(doc.text, "\r\n") else "\n"
		builder: strings.Builder
		strings.builder_init(&builder, allocator)
		if insert_offset > 0 && doc.text[insert_offset - 1] != '\n' && doc.text[insert_offset - 1] != '\r' {
			strings.write_string(&builder, newline)
		}
		for field in missing {
			fmt.sbprintf(&builder, "%scase .%s:%s", case_indent, field.name, newline)
		}
		edit_range := lsp.Range{
			start = position_from_offset(doc.text, insert_offset),
			end = position_from_offset(doc.text, insert_offset),
		}
		append(actions, lsp.Code_Action{
			title = title,
			kind = "quickfix",
			is_preferred = true,
			edit = code_action_edit(
				uri,
				doc.version,
				edit_range,
				strings.to_string(builder),
				allocator,
			),
		})
	}

	add_switch_action :: proc(
		switch_stmt: ^misl.Switch_Stmt,
		actions: ^[dynamic]lsp.Code_Action,
		doc: ^Document,
		uri: string,
		request_start, request_end: int,
		allocator: mem.Allocator,
	) {
		if switch_stmt == nil do return
		add_enum_case_fill_action(
			switch_stmt.cond,
			switch_stmt.body,
			switch_stmt.partial,
			switch_stmt.pos,
			switch_stmt.end,
			"Fill missing enum switch cases",
			actions,
			doc,
			uri,
			request_start,
			request_end,
			allocator,
		)
	}

	add_stage_stub_action :: proc(
		lit: ^misl.Proc_Lit,
		actions: ^[dynamic]lsp.Code_Action,
		doc: ^Document,
		uri: string,
		request_start, request_end: int,
		allocator: mem.Allocator,
	) {
		if lit == nil || lit.type == nil || lit.body == nil do return
		kind := stage_stub_kind(lit.type.calling_convention)
		if kind == "" do return
		body, ok := lit.body.derived_stmt.(^misl.Block_Stmt)
		if !ok || body == nil || len(body.stmts) != 0 do return
		if !offset_ranges_overlap(lit.pos.offset, lit.end.offset, request_start, request_end) do return

		indent := line_indentation_at(doc.text, lit.pos.offset)
		newline := "\r\n" if strings.contains(doc.text, "\r\n") else "\n"
		stub := ""
		title := ""
		switch kind {
		case "vertex":
			title = "Expand vertex shader stub"
			stub = fmt.tprintf(
				"proc \"vertex\"(vertex_id: u32 | SV_Vertex) -> (out: [4]f32 | SV_Position) {%s%s\tout = [4]f32{0, 0, 0, 1}%s%s\treturn out%s%s}",
				newline, indent, newline, indent, newline, indent,
			)
		case "fragment":
			title = "Expand fragment shader stub"
			stub = fmt.tprintf(
				"proc \"fragment\"() -> (out: [4]f32 | SV_Target) {%s%s\tout = [4]f32{1, 1, 1, 1}%s%s\treturn out%s%s}",
				newline, indent, newline, indent, newline, indent,
			)
		case "compute":
			title = "Expand compute shader stub"
			stub = fmt.tprintf(
				"proc \"compute\"(global_id: [3]u32 | SV_Global_Thread) {%s%s\t_ = global_id%s%s}",
				newline, indent, newline, indent,
			)
		case "fmag":
			title = "Expand fmag kernel stub"
			stub = fmt.tprintf(
				"proc \"fmag\"(%s%s\tndv: f32, ndl: f32, ldh: f32, vdh: f32,%s%s\talbedo: [3]f32,%s%s\tmetallic: f32, roughness: f32,%s%s\tD: f32, G: f32,%s%s\tlight: f32,%s%s) -> [3]f32 {%s%s\treturn albedo * light%s%s}",
				newline, indent, newline, indent, newline, indent, newline, indent, newline, indent, newline, indent, newline, indent, newline, indent,
			)
		}
		if stub == "" do return
		edit_range := node_range(lit.pos, lit.end, doc.text)
		append(actions, lsp.Code_Action{
			title = title,
			kind = "refactor.rewrite",
			is_preferred = false,
			edit = code_action_edit(uri, doc.version, edit_range, stub, allocator),
		})
	}

	walk_expr :: proc(expr: ^misl.Expr, data: ^Code_Action_Walk_Data) {
		if expr == nil do return
		#partial switch e in expr.derived_expr {
		case ^misl.Proc_Lit:
			add_stage_stub_action(
				e,
				data.actions,
				data.doc,
				data.uri,
				data.request_start,
				data.request_end,
				data.allocator,
			)
			walk_expr(e.type, data)
			walk_stmt(e.body, data)
		case ^misl.Call_Expr:
			walk_expr(e.expr, data)
			for arg in e.args { walk_expr(arg, data) }
		case ^misl.Comp_Lit:
			walk_expr(e.type, data)
			for elem in e.elems { walk_expr(elem, data) }
		case ^misl.Field_Value:
			walk_expr(e.field, data)
			walk_expr(e.value, data)
		case ^misl.Unary_Expr:
			walk_expr(e.expr, data)
		case ^misl.Binary_Expr:
			walk_expr(e.left, data)
			walk_expr(e.right, data)
		case ^misl.Paren_Expr:
			walk_expr(e.expr, data)
		case ^misl.Selector_Expr:
			walk_expr(e.expr, data)
		case ^misl.Index_Expr:
			walk_expr(e.expr, data)
			walk_expr(e.index, data)
		case ^misl.Type_Cast:
			walk_expr(e.type, data)
			walk_expr(e.expr, data)
		case ^misl.Auto_Cast:
			walk_expr(e.expr, data)
		}
	}

	walk_stmt :: proc(stmt: ^misl.Stmt, data: ^Code_Action_Walk_Data) {
		if stmt == nil do return
		#partial switch s in stmt.derived_stmt {
		case ^misl.Switch_Stmt:
			add_switch_action(
				s,
				data.actions,
				data.doc,
				data.uri,
				data.request_start,
				data.request_end,
				data.allocator,
			)
			walk_stmt(s.init, data)
			walk_expr(s.cond, data)
			walk_stmt(s.body, data)
		case ^misl.Block_Stmt:
			for st in s.stmts { walk_stmt(st, data) }
		case ^misl.Case_Clause:
			for value in s.list { walk_expr(value, data) }
			for st in s.body { walk_stmt(st, data) }
		case ^misl.Expr_Stmt:
			walk_expr(s.expr, data)
		case ^misl.Assign_Stmt:
			for lhs in s.lhs { walk_expr(lhs, data) }
			for rhs in s.rhs { walk_expr(rhs, data) }
		case ^misl.Value_Decl:
			walk_expr(s.type, data)
			for value in s.values { walk_expr(value, data) }
		case ^misl.If_Stmt:
			walk_stmt(s.init, data)
			walk_expr(s.cond, data)
			walk_stmt(s.body, data)
			walk_stmt(s.else_stmt, data)
		case ^misl.When_Stmt:
			walk_expr(s.cond, data)
			walk_stmt(s.body, data)
			walk_stmt(s.else_stmt, data)
		case ^misl.Which_Stmt:
			add_enum_case_fill_action(
				s.cond,
				s.body,
				s.partial,
				s.pos,
				s.end,
				"Fill missing enum which cases",
				data.actions,
				data.doc,
				data.uri,
				data.request_start,
				data.request_end,
				data.allocator,
			)
			walk_expr(s.cond, data)
			walk_stmt(s.body, data)
		case ^misl.For_Stmt:
			walk_stmt(s.init, data)
			walk_expr(s.cond, data)
			walk_stmt(s.post, data)
			walk_stmt(s.body, data)
		case ^misl.Range_Stmt:
			walk_expr(s.expr, data)
			walk_stmt(s.body, data)
		case ^misl.Return_Stmt:
			for value in s.results { walk_expr(value, data) }
		case ^misl.Tag_Stmt:
			walk_stmt(s.stmt, data)
		}
	}

	walk_data := Code_Action_Walk_Data{
		actions = &actions,
		doc = doc,
		uri = params.text_document.uri,
		request_start = request_start,
		request_end = request_end,
		allocator = allocator,
	}
	for decl in mod.decls {
		walk_stmt(decl, &walk_data)
	}
	return actions[:]
}
