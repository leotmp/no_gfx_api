package misl_lsp

import "oge:misl"

Ast_Hit :: struct {
	ident:           ^misl.Ident,
	expr:            ^misl.Expr,
	call:            ^misl.Call_Expr,
	entity:          ^misl.Entity, // import/package decls without an Ident node
	entity_pos:      misl.Token_Pos,
	entity_name_len: int,
}

offset_in_span :: proc(offset: int, pos, end: misl.Token_Pos) -> bool {
	if pos.offset < 0 do return false
	lo := pos.offset
	hi := end.offset if end.offset > pos.offset else pos.offset + 1
	return offset >= lo && offset < hi
}

ident_contains_offset :: proc(ident: ^misl.Ident, offset: int) -> bool {
	if ident == nil do return false
	lo := ident.pos.offset
	hi := ident.end.offset if ident.end.offset > lo else lo + len(ident.name)
	if hi <= lo {
		hi = lo + max(len(ident.name), 1)
	}
	return offset >= lo && offset < hi
}

// Prefer deepest (smallest span) Ident containing offset.
ast_find_at_offset :: proc(module: ^misl.Module, offset: int) -> Ast_Hit {
	hit: Ast_Hit
	best_span := max(int)
	best_call_span := max(int)

	consider_ident :: proc(ident: ^misl.Ident, offset: int, hit: ^Ast_Hit, best_span: ^int) {
		if ident == nil do return
		if !ident_contains_offset(ident, offset) do return
		lo := ident.pos.offset
		hi := ident.end.offset if ident.end.offset > lo else lo + len(ident.name)
		span := hi - lo
		if span < best_span^ {
			best_span^ = span
			hit.ident = ident
			hit.expr = ident
		}
	}

	consider_call :: proc(call: ^misl.Call_Expr, offset: int, hit: ^Ast_Hit, best_call_span: ^int) {
		if call == nil do return
		if !offset_in_span(offset, call.pos, call.end) do return
		span := call.end.offset - call.pos.offset
		if span < best_call_span^ {
			best_call_span^ = span
			hit.call = call
		}
	}

	walk_expr :: proc(expr: ^misl.Expr, offset: int, hit: ^Ast_Hit, best_span: ^int, best_call_span: ^int) {
		if expr == nil do return
		#partial switch e in expr.derived_expr {
		case ^misl.Ident:
			consider_ident(e, offset, hit, best_span)
		case ^misl.Basic_Lit:
		case ^misl.Basic_Directive:
		case ^misl.Implicit:
		case ^misl.Undef:
		case ^misl.Ellipsis:
			walk_expr(e.expr, offset, hit, best_span, best_call_span)
		case ^misl.Unary_Expr:
			walk_expr(e.expr, offset, hit, best_span, best_call_span)
		case ^misl.Binary_Expr:
			walk_expr(e.left, offset, hit, best_span, best_call_span)
			walk_expr(e.right, offset, hit, best_span, best_call_span)
		case ^misl.Paren_Expr:
			walk_expr(e.expr, offset, hit, best_span, best_call_span)
		case ^misl.Selector_Expr:
			walk_expr(e.expr, offset, hit, best_span, best_call_span)
			consider_ident(e.field, offset, hit, best_span)
		case ^misl.Implicit_Selector_Expr:
			consider_ident(e.field, offset, hit, best_span)
		case ^misl.Selector_Call_Expr:
			walk_expr(e.expr, offset, hit, best_span, best_call_span)
			walk_expr(e.call, offset, hit, best_span, best_call_span)
		case ^misl.Index_Expr:
			walk_expr(e.expr, offset, hit, best_span, best_call_span)
			walk_expr(e.index, offset, hit, best_span, best_call_span)
		case ^misl.Deref_Expr:
			walk_expr(e.expr, offset, hit, best_span, best_call_span)
		case ^misl.Slice_Expr:
			walk_expr(e.expr, offset, hit, best_span, best_call_span)
			walk_expr(e.low, offset, hit, best_span, best_call_span)
			walk_expr(e.high, offset, hit, best_span, best_call_span)
		case ^misl.Matrix_Index_Expr:
			walk_expr(e.expr, offset, hit, best_span, best_call_span)
			walk_expr(e.row_index, offset, hit, best_span, best_call_span)
			walk_expr(e.column_index, offset, hit, best_span, best_call_span)
		case ^misl.Call_Expr:
			consider_call(e, offset, hit, best_call_span)
			walk_expr(e.expr, offset, hit, best_span, best_call_span)
			for arg in e.args {
				walk_expr(arg, offset, hit, best_span, best_call_span)
			}
		case ^misl.Field_Value:
			walk_expr(e.field, offset, hit, best_span, best_call_span)
			walk_expr(e.value, offset, hit, best_span, best_call_span)
		case ^misl.Ternary_If_Expr:
			walk_expr(e.x, offset, hit, best_span, best_call_span)
			walk_expr(e.cond, offset, hit, best_span, best_call_span)
			walk_expr(e.y, offset, hit, best_span, best_call_span)
		case ^misl.Ternary_When_Expr:
			walk_expr(e.x, offset, hit, best_span, best_call_span)
			walk_expr(e.cond, offset, hit, best_span, best_call_span)
			walk_expr(e.y, offset, hit, best_span, best_call_span)
		case ^misl.Type_Cast:
			walk_expr(e.type, offset, hit, best_span, best_call_span)
			walk_expr(e.expr, offset, hit, best_span, best_call_span)
		case ^misl.Auto_Cast:
			walk_expr(e.expr, offset, hit, best_span, best_call_span)
		case ^misl.Comp_Lit:
			walk_expr(e.type, offset, hit, best_span, best_call_span)
			for elem in e.elems {
				walk_expr(elem, offset, hit, best_span, best_call_span)
			}
		case ^misl.Proc_Lit:
			walk_expr(e.type, offset, hit, best_span, best_call_span)
			walk_stmt(e.body, offset, hit, best_span, best_call_span)
		case ^misl.Tag_Expr:
			walk_expr(e.expr, offset, hit, best_span, best_call_span)
		case ^misl.Proc_Type:
			walk_field_list(e.params, offset, hit, best_span, best_call_span)
			walk_field_list(e.results, offset, hit, best_span, best_call_span)
		case ^misl.Pointer_Type:
			walk_expr(e.elem, offset, hit, best_span, best_call_span)
		case ^misl.Multi_Pointer_Type:
			walk_expr(e.elem, offset, hit, best_span, best_call_span)
		case ^misl.Array_Type:
			walk_expr(e.len, offset, hit, best_span, best_call_span)
			walk_expr(e.elem, offset, hit, best_span, best_call_span)
		case ^misl.Struct_Type:
			walk_field_list(e.fields, offset, hit, best_span, best_call_span)
		case ^misl.Enum_Type:
			for f in e.fields {
				walk_expr(f, offset, hit, best_span, best_call_span)
			}
		case ^misl.Bit_Set_Type:
			walk_expr(e.elem, offset, hit, best_span, best_call_span)
			walk_expr(e.underlying, offset, hit, best_span, best_call_span)
		case ^misl.Matrix_Type:
			walk_expr(e.row_count, offset, hit, best_span, best_call_span)
			walk_expr(e.column_count, offset, hit, best_span, best_call_span)
			walk_expr(e.elem, offset, hit, best_span, best_call_span)
		case ^misl.Distinct_Type:
			walk_expr(e.type, offset, hit, best_span, best_call_span)
		case ^misl.Helper_Type:
			walk_expr(e.type, offset, hit, best_span, best_call_span)
		case ^misl.Poly_Type:
			consider_ident(e.type, offset, hit, best_span)
			walk_expr(e.specialization, offset, hit, best_span, best_call_span)
		case ^misl.Typeid_Type:
			walk_expr(e.specialization, offset, hit, best_span, best_call_span)
		case ^misl.Proc_Group:
			for arg in e.args {
				walk_expr(arg, offset, hit, best_span, best_call_span)
			}
		case ^misl.Pipeline_Type:
		case ^misl.Bad_Expr:
		}
	}

	walk_field_list :: proc(fl: ^misl.Field_List, offset: int, hit: ^Ast_Hit, best_span: ^int, best_call_span: ^int) {
		if fl == nil do return
		for f in fl.list {
			if f == nil do continue
			for name in f.names {
				walk_expr(name, offset, hit, best_span, best_call_span)
			}
			walk_expr(f.type, offset, hit, best_span, best_call_span)
			walk_expr(f.default_value, offset, hit, best_span, best_call_span)
			consider_ident(f.semantics, offset, hit, best_span)
		}
	}

	walk_stmt :: proc(stmt: ^misl.Stmt, offset: int, hit: ^Ast_Hit, best_span: ^int, best_call_span: ^int) {
		if stmt == nil do return
		#partial switch s in stmt.derived_stmt {
		case ^misl.Empty_Stmt:
		case ^misl.Bad_Stmt:
		case ^misl.Expr_Stmt:
			walk_expr(s.expr, offset, hit, best_span, best_call_span)
		case ^misl.Tag_Stmt:
			walk_stmt(s.stmt, offset, hit, best_span, best_call_span)
		case ^misl.Assign_Stmt:
			for lhs in s.lhs {
				walk_expr(lhs, offset, hit, best_span, best_call_span)
			}
			for rhs in s.rhs {
				walk_expr(rhs, offset, hit, best_span, best_call_span)
			}
		case ^misl.Block_Stmt:
			for st in s.stmts {
				walk_stmt(st, offset, hit, best_span, best_call_span)
			}
		case ^misl.If_Stmt:
			walk_stmt(s.init, offset, hit, best_span, best_call_span)
			walk_expr(s.cond, offset, hit, best_span, best_call_span)
			walk_stmt(s.body, offset, hit, best_span, best_call_span)
			walk_stmt(s.else_stmt, offset, hit, best_span, best_call_span)
		case ^misl.When_Stmt:
			walk_expr(s.cond, offset, hit, best_span, best_call_span)
			walk_stmt(s.body, offset, hit, best_span, best_call_span)
			walk_stmt(s.else_stmt, offset, hit, best_span, best_call_span)
		case ^misl.Which_Stmt:
			walk_expr(s.cond, offset, hit, best_span, best_call_span)
			walk_stmt(s.body, offset, hit, best_span, best_call_span)
		case ^misl.Return_Stmt:
			for r in s.results {
				walk_expr(r, offset, hit, best_span, best_call_span)
			}
		case ^misl.For_Stmt:
			walk_stmt(s.init, offset, hit, best_span, best_call_span)
			walk_expr(s.cond, offset, hit, best_span, best_call_span)
			walk_stmt(s.post, offset, hit, best_span, best_call_span)
			walk_stmt(s.body, offset, hit, best_span, best_call_span)
		case ^misl.Range_Stmt:
			for val in s.vals {
				walk_expr(val, offset, hit, best_span, best_call_span)
			}
			walk_expr(s.expr, offset, hit, best_span, best_call_span)
			walk_stmt(s.body, offset, hit, best_span, best_call_span)
		case ^misl.Switch_Stmt:
			walk_stmt(s.init, offset, hit, best_span, best_call_span)
			walk_expr(s.cond, offset, hit, best_span, best_call_span)
			walk_stmt(s.body, offset, hit, best_span, best_call_span)
		case ^misl.Case_Clause:
			for list_expr in s.list {
				walk_expr(list_expr, offset, hit, best_span, best_call_span)
			}
			for st in s.body {
				walk_stmt(st, offset, hit, best_span, best_call_span)
			}
		case ^misl.Branch_Stmt:
			consider_ident(s.label, offset, hit, best_span)
		case ^misl.Using_Stmt:
			for list_expr in s.list {
				walk_expr(list_expr, offset, hit, best_span, best_call_span)
			}
		case ^misl.Value_Decl:
			for name in s.names {
				walk_expr(name, offset, hit, best_span, best_call_span)
			}
			walk_expr(s.type, offset, hit, best_span, best_call_span)
			for val in s.values {
				walk_expr(val, offset, hit, best_span, best_call_span)
			}
		case ^misl.Import_Decl:
		case ^misl.Package_Decl:
			// Handled after walk — nested procs cannot capture `module`.
		case ^misl.Bad_Decl:
		}
	}

	if module == nil do return hit
	for decl in module.decls {
		walk_stmt(decl, offset, &hit, &best_span, &best_call_span)
	}

	if hit.ident == nil && hit.entity == nil && hit.entity_name_len == 0 {
		for decl in module.decls {
			#partial switch s in decl.derived_stmt {
			case ^misl.Import_Decl:
				name_lo := s.name.pos.offset
				name_hi := name_lo + len(s.name.text)
				path_lo := s.relpath.pos.offset
				path_hi := path_lo + len(s.relpath.text)
				on_name := s.name.text != "" && offset >= name_lo && offset < name_hi
				on_path := len(s.relpath.text) > 0 && offset >= path_lo && offset < path_hi
				if !on_name && !on_path do continue
				lookup := s.name.text
				if lookup == "" {
					for _, ent in module.scope.entities {
						if ent != nil && ent.kind == .Import && ent.pos.offset == s.pos.offset {
							hit.entity = ent
							hit.entity_pos = s.relpath.pos if on_path else s.name.pos
							hit.entity_name_len = len(s.relpath.text) if on_path else 1
							break
						}
					}
				} else if e := misl.scope_lookup_current(module.scope, lookup); e != nil {
					hit.entity = e
					hit.entity_pos = s.name.pos if on_name else s.relpath.pos
					hit.entity_name_len = len(s.name.text) if on_name else len(s.relpath.text)
				}
			case ^misl.Package_Decl:
				lo := s.token.pos.offset
				hi := s.end.offset if s.end.offset > lo else lo + len(s.name) + 8
				if offset >= lo && offset < hi && s.name != "" {
					hit.entity_pos = s.token.pos
					hit.entity_name_len = max(len(s.name), 1)
				}
			}
		}
	}
	return hit
}

entity_same_source :: proc(a, b: ^misl.Entity) -> bool {
	if a == nil || b == nil do return false
	if a == b do return true
	return a.name == b.name && a.pos.offset == b.pos.offset && a.pos.file == b.pos.file
}

// Collect all Idents in a module that reference the given entity (or share the name if entity nil).
ast_collect_idents_for_entity :: proc(module: ^misl.Module, entity: ^misl.Entity, out: ^[dynamic]^misl.Ident) {
	if module == nil || entity == nil do return

	visit_ident :: proc(ident: ^misl.Ident, entity: ^misl.Entity, out: ^[dynamic]^misl.Ident) {
		if ident == nil || ident.entity == nil do return
		if ident.entity == entity || entity_same_source(ident.entity, entity) {
			append(out, ident)
		}
	}

	walk_expr :: proc(expr: ^misl.Expr, entity: ^misl.Entity, out: ^[dynamic]^misl.Ident) {
		if expr == nil do return
		#partial switch e in expr.derived_expr {
		case ^misl.Ident:
			visit_ident(e, entity, out)
		case ^misl.Ellipsis:
			walk_expr(e.expr, entity, out)
		case ^misl.Unary_Expr:
			walk_expr(e.expr, entity, out)
		case ^misl.Binary_Expr:
			walk_expr(e.left, entity, out)
			walk_expr(e.right, entity, out)
		case ^misl.Paren_Expr:
			walk_expr(e.expr, entity, out)
		case ^misl.Selector_Expr:
			walk_expr(e.expr, entity, out)
			visit_ident(e.field, entity, out)
		case ^misl.Implicit_Selector_Expr:
			visit_ident(e.field, entity, out)
		case ^misl.Selector_Call_Expr:
			walk_expr(e.expr, entity, out)
			walk_expr(e.call, entity, out)
		case ^misl.Index_Expr:
			walk_expr(e.expr, entity, out)
			walk_expr(e.index, entity, out)
		case ^misl.Deref_Expr:
			walk_expr(e.expr, entity, out)
		case ^misl.Slice_Expr:
			walk_expr(e.expr, entity, out)
			walk_expr(e.low, entity, out)
			walk_expr(e.high, entity, out)
		case ^misl.Matrix_Index_Expr:
			walk_expr(e.expr, entity, out)
			walk_expr(e.row_index, entity, out)
			walk_expr(e.column_index, entity, out)
		case ^misl.Call_Expr:
			walk_expr(e.expr, entity, out)
			for arg in e.args {
				walk_expr(arg, entity, out)
			}
		case ^misl.Field_Value:
			walk_expr(e.field, entity, out)
			walk_expr(e.value, entity, out)
		case ^misl.Ternary_If_Expr:
			walk_expr(e.x, entity, out)
			walk_expr(e.cond, entity, out)
			walk_expr(e.y, entity, out)
		case ^misl.Ternary_When_Expr:
			walk_expr(e.x, entity, out)
			walk_expr(e.cond, entity, out)
			walk_expr(e.y, entity, out)
		case ^misl.Type_Cast:
			walk_expr(e.type, entity, out)
			walk_expr(e.expr, entity, out)
		case ^misl.Auto_Cast:
			walk_expr(e.expr, entity, out)
		case ^misl.Comp_Lit:
			walk_expr(e.type, entity, out)
			for elem in e.elems {
				walk_expr(elem, entity, out)
			}
		case ^misl.Proc_Lit:
			walk_expr(e.type, entity, out)
			walk_stmt(e.body, entity, out)
		case ^misl.Tag_Expr:
			walk_expr(e.expr, entity, out)
		case ^misl.Proc_Type:
			walk_field_list(e.params, entity, out)
			walk_field_list(e.results, entity, out)
		case ^misl.Pointer_Type:
			walk_expr(e.elem, entity, out)
		case ^misl.Multi_Pointer_Type:
			walk_expr(e.elem, entity, out)
		case ^misl.Array_Type:
			walk_expr(e.len, entity, out)
			walk_expr(e.elem, entity, out)
		case ^misl.Struct_Type:
			walk_field_list(e.fields, entity, out)
		case ^misl.Enum_Type:
			for f in e.fields {
				walk_expr(f, entity, out)
			}
		case ^misl.Bit_Set_Type:
			walk_expr(e.elem, entity, out)
			walk_expr(e.underlying, entity, out)
		case ^misl.Matrix_Type:
			walk_expr(e.row_count, entity, out)
			walk_expr(e.column_count, entity, out)
			walk_expr(e.elem, entity, out)
		case ^misl.Distinct_Type:
			walk_expr(e.type, entity, out)
		case ^misl.Helper_Type:
			walk_expr(e.type, entity, out)
		case ^misl.Poly_Type:
			visit_ident(e.type, entity, out)
			walk_expr(e.specialization, entity, out)
		case ^misl.Typeid_Type:
			walk_expr(e.specialization, entity, out)
		case ^misl.Proc_Group:
			for arg in e.args {
				walk_expr(arg, entity, out)
			}
		}
	}

	walk_field_list :: proc(fl: ^misl.Field_List, entity: ^misl.Entity, out: ^[dynamic]^misl.Ident) {
		if fl == nil do return
		for f in fl.list {
			if f == nil do continue
			for name in f.names {
				walk_expr(name, entity, out)
			}
			walk_expr(f.type, entity, out)
			walk_expr(f.default_value, entity, out)
			visit_ident(f.semantics, entity, out)
		}
	}

	walk_stmt :: proc(stmt: ^misl.Stmt, entity: ^misl.Entity, out: ^[dynamic]^misl.Ident) {
		if stmt == nil do return
		#partial switch s in stmt.derived_stmt {
		case ^misl.Expr_Stmt:
			walk_expr(s.expr, entity, out)
		case ^misl.Tag_Stmt:
			walk_stmt(s.stmt, entity, out)
		case ^misl.Assign_Stmt:
			for lhs in s.lhs { walk_expr(lhs, entity, out) }
			for rhs in s.rhs { walk_expr(rhs, entity, out) }
		case ^misl.Block_Stmt:
			for st in s.stmts { walk_stmt(st, entity, out) }
		case ^misl.If_Stmt:
			walk_stmt(s.init, entity, out)
			walk_expr(s.cond, entity, out)
			walk_stmt(s.body, entity, out)
			walk_stmt(s.else_stmt, entity, out)
		case ^misl.When_Stmt:
			walk_expr(s.cond, entity, out)
			walk_stmt(s.body, entity, out)
			walk_stmt(s.else_stmt, entity, out)
		case ^misl.Which_Stmt:
			walk_expr(s.cond, entity, out)
			walk_stmt(s.body, entity, out)
		case ^misl.Return_Stmt:
			for r in s.results { walk_expr(r, entity, out) }
		case ^misl.For_Stmt:
			walk_stmt(s.init, entity, out)
			walk_expr(s.cond, entity, out)
			walk_stmt(s.post, entity, out)
			walk_stmt(s.body, entity, out)
		case ^misl.Range_Stmt:
			for val in s.vals { walk_expr(val, entity, out) }
			walk_expr(s.expr, entity, out)
			walk_stmt(s.body, entity, out)
		case ^misl.Switch_Stmt:
			walk_stmt(s.init, entity, out)
			walk_expr(s.cond, entity, out)
			walk_stmt(s.body, entity, out)
		case ^misl.Case_Clause:
			for list_expr in s.list { walk_expr(list_expr, entity, out) }
			for st in s.body { walk_stmt(st, entity, out) }
		case ^misl.Branch_Stmt:
			visit_ident(s.label, entity, out)
		case ^misl.Using_Stmt:
			for list_expr in s.list { walk_expr(list_expr, entity, out) }
		case ^misl.Value_Decl:
			for name in s.names { walk_expr(name, entity, out) }
			walk_expr(s.type, entity, out)
			for val in s.values { walk_expr(val, entity, out) }
		}
	}

	for decl in module.decls {
		walk_stmt(decl, entity, out)
	}
}

ast_collect_all_idents :: proc(module: ^misl.Module, out: ^[dynamic]^misl.Ident, selectors: ^[dynamic]^misl.Selector_Expr = nil) {
	if module == nil do return

	visit :: proc(ident: ^misl.Ident, out: ^[dynamic]^misl.Ident) {
		if ident != nil do append(out, ident)
	}

	walk_expr :: proc(expr: ^misl.Expr, out: ^[dynamic]^misl.Ident, selectors: ^[dynamic]^misl.Selector_Expr) {
		if expr == nil do return
		#partial switch e in expr.derived_expr {
		case ^misl.Ident:
			visit(e, out)
		case ^misl.Ellipsis:
			walk_expr(e.expr, out, selectors)
		case ^misl.Unary_Expr:
			walk_expr(e.expr, out, selectors)
		case ^misl.Binary_Expr:
			walk_expr(e.left, out, selectors); walk_expr(e.right, out, selectors)
		case ^misl.Paren_Expr:
			walk_expr(e.expr, out, selectors)
		case ^misl.Selector_Expr:
			walk_expr(e.expr, out, selectors); visit(e.field, out)
			if selectors != nil do append(selectors, e)
		case ^misl.Implicit_Selector_Expr:
			visit(e.field, out)
		case ^misl.Call_Expr:
			walk_expr(e.expr, out, selectors)
			for arg in e.args { walk_expr(arg, out, selectors) }
		case ^misl.Index_Expr:
			walk_expr(e.expr, out, selectors); walk_expr(e.index, out, selectors)
		case ^misl.Deref_Expr:
			walk_expr(e.expr, out, selectors)
		case ^misl.Comp_Lit:
			walk_expr(e.type, out, selectors)
			for elem in e.elems { walk_expr(elem, out, selectors) }
		case ^misl.Field_Value:
			walk_expr(e.field, out, selectors); walk_expr(e.value, out, selectors)
		case ^misl.Proc_Lit:
			walk_expr(e.type, out, selectors); walk_stmt(e.body, out, selectors)
		case ^misl.Type_Cast, ^misl.Auto_Cast:
			#partial switch x in expr.derived_expr {
			case ^misl.Type_Cast:
				walk_expr(x.type, out, selectors); walk_expr(x.expr, out, selectors)
			case ^misl.Auto_Cast:
				walk_expr(x.expr, out, selectors)
			}
		case ^misl.Ternary_If_Expr:
			walk_expr(e.x, out, selectors); walk_expr(e.cond, out, selectors); walk_expr(e.y, out, selectors)
		case ^misl.Struct_Type:
			walk_field_list(e.fields, out, selectors)
		case ^misl.Proc_Type:
			walk_field_list(e.params, out, selectors); walk_field_list(e.results, out, selectors)
		case ^misl.Pointer_Type, ^misl.Multi_Pointer_Type:
			#partial switch x in expr.derived_expr {
			case ^misl.Pointer_Type: walk_expr(x.elem, out, selectors)
			case ^misl.Multi_Pointer_Type: walk_expr(x.elem, out, selectors)
			}
		case ^misl.Array_Type:
			walk_expr(e.len, out, selectors); walk_expr(e.elem, out, selectors)
		case ^misl.Enum_Type:
			for f in e.fields { walk_expr(f, out, selectors) }
		case ^misl.Bit_Set_Type:
			walk_expr(e.elem, out, selectors); walk_expr(e.underlying, out, selectors)
		case ^misl.Matrix_Type:
			walk_expr(e.row_count, out, selectors); walk_expr(e.column_count, out, selectors); walk_expr(e.elem, out, selectors)
		case ^misl.Distinct_Type, ^misl.Helper_Type:
			#partial switch x in expr.derived_expr {
			case ^misl.Distinct_Type: walk_expr(x.type, out, selectors)
			case ^misl.Helper_Type: walk_expr(x.type, out, selectors)
			}
		case ^misl.Proc_Group:
			for arg in e.args { walk_expr(arg, out, selectors) }
		case ^misl.Bad_Expr:
		}
	}

	walk_field_list :: proc(list: ^misl.Field_List, out: ^[dynamic]^misl.Ident, selectors: ^[dynamic]^misl.Selector_Expr) {
		if list == nil do return
		for field in list.list {
			if field == nil do continue
			for name in field.names { walk_expr(name, out, selectors) }
			walk_expr(field.type, out, selectors)
			walk_expr(field.default_value, out, selectors)
		}
	}

	walk_stmt :: proc(stmt: ^misl.Stmt, out: ^[dynamic]^misl.Ident, selectors: ^[dynamic]^misl.Selector_Expr) {
		if stmt == nil do return
		#partial switch s in stmt.derived_stmt {
		case ^misl.Expr_Stmt:
			walk_expr(s.expr, out, selectors)
		case ^misl.Block_Stmt:
			for st in s.stmts { walk_stmt(st, out, selectors) }
		case ^misl.If_Stmt:
			walk_stmt(s.init, out, selectors); walk_expr(s.cond, out, selectors); walk_stmt(s.body, out, selectors); walk_stmt(s.else_stmt, out, selectors)
		case ^misl.Return_Stmt:
			for r in s.results { walk_expr(r, out, selectors) }
		case ^misl.For_Stmt:
			walk_stmt(s.init, out, selectors); walk_expr(s.cond, out, selectors); walk_stmt(s.post, out, selectors); walk_stmt(s.body, out, selectors)
		case ^misl.Range_Stmt:
			for val in s.vals { walk_expr(val, out, selectors) }
			walk_expr(s.expr, out, selectors); walk_stmt(s.body, out, selectors)
		case ^misl.Switch_Stmt:
			walk_stmt(s.init, out, selectors); walk_expr(s.cond, out, selectors); walk_stmt(s.body, out, selectors)
		case ^misl.Which_Stmt:
			walk_expr(s.cond, out, selectors); walk_stmt(s.body, out, selectors)
		case ^misl.When_Stmt:
			walk_expr(s.cond, out, selectors); walk_stmt(s.body, out, selectors); walk_stmt(s.else_stmt, out, selectors)
		case ^misl.Case_Clause:
			for list_expr in s.list { walk_expr(list_expr, out, selectors) }
			for st in s.body { walk_stmt(st, out, selectors) }
		case ^misl.Assign_Stmt:
			for lhs in s.lhs { walk_expr(lhs, out, selectors) }
			for rhs in s.rhs { walk_expr(rhs, out, selectors) }
		case ^misl.Value_Decl:
			for name in s.names { walk_expr(name, out, selectors) }
			walk_expr(s.type, out, selectors)
			for val in s.values { walk_expr(val, out, selectors) }
		case ^misl.Tag_Stmt:
			walk_stmt(s.stmt, out, selectors)
		case ^misl.Import_Decl, ^misl.Package_Decl, ^misl.Bad_Decl:
		}
	}

	for decl in module.decls {
		walk_stmt(decl, out, selectors)
	}
}

// Proc group names and members — even in untaken `which` arms (entity may be nil).
ast_mark_proc_group_idents :: proc(module: ^misl.Module, fns: ^map[^misl.Ident]bool, decls: ^map[^misl.Ident]bool) {
	if module == nil do return

	mark_ident :: proc(expr: ^misl.Expr, into: ^map[^misl.Ident]bool) {
		if expr == nil || into == nil do return
		if ident, ok := misl.unparen_expr(expr).derived.(^misl.Ident); ok {
			into[ident] = true
		}
	}

	walk_stmt :: proc(stmt: ^misl.Stmt, fns: ^map[^misl.Ident]bool, decls: ^map[^misl.Ident]bool) {
		if stmt == nil do return
		#partial switch s in stmt.derived_stmt {
		case ^misl.Block_Stmt:
			for st in s.stmts { walk_stmt(st, fns, decls) }
		case ^misl.If_Stmt:
			walk_stmt(s.body, fns, decls); walk_stmt(s.else_stmt, fns, decls)
		case ^misl.For_Stmt:
			walk_stmt(s.body, fns, decls)
		case ^misl.Range_Stmt:
			walk_stmt(s.body, fns, decls)
		case ^misl.Switch_Stmt:
			walk_stmt(s.body, fns, decls)
		case ^misl.Which_Stmt:
			walk_stmt(s.body, fns, decls)
		case ^misl.When_Stmt:
			walk_stmt(s.body, fns, decls); walk_stmt(s.else_stmt, fns, decls)
		case ^misl.Case_Clause:
			for st in s.body { walk_stmt(st, fns, decls) }
		case ^misl.Tag_Stmt:
			walk_stmt(s.stmt, fns, decls)
		case ^misl.Value_Decl:
			for val in s.values {
				pg, is_pg := misl.unparen_expr(val).derived.(^misl.Proc_Group)
				if !is_pg do continue
				for name in s.names {
					mark_ident(name, fns)
					mark_ident(name, decls)
				}
				for arg in pg.args {
					mark_ident(arg, fns)
				}
			}
		}
	}

	for decl in module.decls {
		walk_stmt(decl, fns, decls)
	}
}

// Innermost checked scope containing `offset` (proc body, block, for, switch, …).
// Falls back to module.scope when nothing more specific is found.
scope_at_offset :: proc(module: ^misl.Module, offset: int) -> ^misl.Scope {
	if module == nil do return nil
	best: ^misl.Scope = module.scope
	best_span := max(int)

	consider :: proc(scope: ^misl.Scope, pos, end: misl.Token_Pos, offset: int, best: ^^misl.Scope, best_span: ^int) {
		if scope == nil do return
		if !offset_in_span(offset, pos, end) do return
		hi := end.offset if end.offset > pos.offset else pos.offset + 1
		span := hi - pos.offset
		if span < best_span^ {
			best_span^ = span
			best^ = scope
		}
	}

	walk_expr :: proc(expr: ^misl.Expr, offset: int, best: ^^misl.Scope, best_span: ^int) {
		if expr == nil do return
		#partial switch e in expr.derived_expr {
		case ^misl.Proc_Lit:
			walk_expr(e.type, offset, best, best_span)
			walk_stmt(e.body, offset, best, best_span)
			// Params live on the proc type scope (outer of the body block).
			if e.type != nil && e.type.scope != nil {
				consider(e.type.scope, e.pos, e.end, offset, best, best_span)
			}
		case ^misl.Proc_Type:
			if e.scope != nil {
				consider(e.scope, e.pos, e.end, offset, best, best_span)
			}
		case ^misl.Unary_Expr:
			walk_expr(e.expr, offset, best, best_span)
		case ^misl.Binary_Expr:
			walk_expr(e.left, offset, best, best_span)
			walk_expr(e.right, offset, best, best_span)
		case ^misl.Paren_Expr:
			walk_expr(e.expr, offset, best, best_span)
		case ^misl.Call_Expr:
			walk_expr(e.expr, offset, best, best_span)
			for arg in e.args { walk_expr(arg, offset, best, best_span) }
		case ^misl.Selector_Expr:
			walk_expr(e.expr, offset, best, best_span)
		case ^misl.Index_Expr:
			walk_expr(e.expr, offset, best, best_span)
			walk_expr(e.index, offset, best, best_span)
		case ^misl.Comp_Lit:
			walk_expr(e.type, offset, best, best_span)
			for elem in e.elems { walk_expr(elem, offset, best, best_span) }
		case ^misl.Type_Cast:
			walk_expr(e.type, offset, best, best_span)
			walk_expr(e.expr, offset, best, best_span)
		case ^misl.Auto_Cast:
			walk_expr(e.expr, offset, best, best_span)
		case ^misl.Ternary_If_Expr:
			walk_expr(e.x, offset, best, best_span)
			walk_expr(e.cond, offset, best, best_span)
			walk_expr(e.y, offset, best, best_span)
		case ^misl.Field_Value:
			walk_expr(e.field, offset, best, best_span)
			walk_expr(e.value, offset, best, best_span)
		}
	}

	walk_stmt :: proc(stmt: ^misl.Stmt, offset: int, best: ^^misl.Scope, best_span: ^int) {
		if stmt == nil do return
		#partial switch s in stmt.derived_stmt {
		case ^misl.Block_Stmt:
			consider(s.scope, s.pos, s.end, offset, best, best_span)
			for st in s.stmts { walk_stmt(st, offset, best, best_span) }
		case ^misl.If_Stmt:
			consider(s.scope, s.pos, s.end, offset, best, best_span)
			walk_stmt(s.init, offset, best, best_span)
			walk_expr(s.cond, offset, best, best_span)
			walk_stmt(s.body, offset, best, best_span)
			walk_stmt(s.else_stmt, offset, best, best_span)
		case ^misl.For_Stmt:
			consider(s.scope, s.pos, s.end, offset, best, best_span)
			walk_stmt(s.init, offset, best, best_span)
			walk_expr(s.cond, offset, best, best_span)
			walk_stmt(s.post, offset, best, best_span)
			walk_stmt(s.body, offset, best, best_span)
		case ^misl.Range_Stmt:
			consider(s.scope, s.pos, s.end, offset, best, best_span)
			for val in s.vals { walk_expr(val, offset, best, best_span) }
			walk_expr(s.expr, offset, best, best_span)
			walk_stmt(s.body, offset, best, best_span)
		case ^misl.Switch_Stmt:
			consider(s.scope, s.pos, s.end, offset, best, best_span)
			walk_stmt(s.init, offset, best, best_span)
			walk_expr(s.cond, offset, best, best_span)
			walk_stmt(s.body, offset, best, best_span)
		case ^misl.Case_Clause:
			consider(s.scope, s.pos, s.end, offset, best, best_span)
			for list_expr in s.list { walk_expr(list_expr, offset, best, best_span) }
			for st in s.body { walk_stmt(st, offset, best, best_span) }
		case ^misl.Expr_Stmt:
			walk_expr(s.expr, offset, best, best_span)
		case ^misl.Assign_Stmt:
			for lhs in s.lhs { walk_expr(lhs, offset, best, best_span) }
			for rhs in s.rhs { walk_expr(rhs, offset, best, best_span) }
		case ^misl.Return_Stmt:
			for r in s.results { walk_expr(r, offset, best, best_span) }
		case ^misl.Value_Decl:
			for name in s.names { walk_expr(name, offset, best, best_span) }
			walk_expr(s.type, offset, best, best_span)
			for val in s.values { walk_expr(val, offset, best, best_span) }
		case ^misl.When_Stmt:
			walk_expr(s.cond, offset, best, best_span)
			walk_stmt(s.body, offset, best, best_span)
			walk_stmt(s.else_stmt, offset, best, best_span)
		case ^misl.Which_Stmt:
			walk_expr(s.cond, offset, best, best_span)
			walk_stmt(s.body, offset, best, best_span)
		case ^misl.Tag_Stmt:
			walk_stmt(s.stmt, offset, best, best_span)
		}
	}

	for decl in module.decls {
		walk_stmt(decl, offset, &best, &best_span)
	}
	return best
}
