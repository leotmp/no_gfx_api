package misl

type_as_struct :: proc(t: ^Type) -> ^Type_Struct {
	if t == nil do return nil
	cur := t
	if p, is_ptr := cur.derived.(^Type_Pointer); is_ptr {
		cur = p.elem
		if cur == nil do return nil
	}
	st, ok := cur.derived.(^Type_Struct)
	return st if ok else nil
}

using_chain_append :: proc(prefix: []^Entity, field: ^Entity) -> []^Entity {
	out := make([]^Entity, len(prefix) + 1)
	copy(out, prefix)
	out[len(prefix)] = field
	return out
}

scope_define :: proc(c: ^Checker, scope: ^Scope, entity: ^Entity) -> bool {
	if entity == nil || entity.name == "" {
		return true
	}
	if existing := scope_lookup_current(scope, entity.name); existing != nil {
		check_err(c, entity.pos, "redeclaration of '%s' in this scope", entity.name)
		return false
	}
	scope_insert(scope, entity)
	return true
}

// Import `using foo`: bind the imported module's names here without stealing entity.scope.
scope_inject_existing :: proc(c: ^Checker, scope: ^Scope, e: ^Entity, pos: Token_Pos) -> bool {
	if e == nil || e.name == "" || e.name == "_" {
		return true
	}
	if existing := scope_lookup_current(scope, e.name); existing != nil {
		if existing == e {
			return true
		}
		check_err(c, pos, "redeclaration of '%s' in this scope", e.name)
		return false
	}
	scope.entities[e.name] = e
	return true
}

make_using_field_selector :: proc(lhs: ^Expr, field: ^Entity) -> ^Selector_Expr {
	sel := ast_new(Selector_Expr, lhs.pos, lhs.end)
	sel.expr = lhs
	id := ast_new(Ident, lhs.pos, lhs.end)
	id.name = field.name
	id.entity = field
	id.tav.type = field.type
	id.tav.mode = .Variable
	sel.field = id
	sel.tav.type = field.type
	mode := lhs.tav.mode
	if mode == .Variable || mode == .Swizzle_Variable {
		sel.tav.mode = .Variable
	} else {
		sel.tav.mode = .Value
	}
	return sel
}

rewrite_selector_using_chain :: proc(sel: ^Selector_Expr, chain: []^Entity) {
	if sel == nil || len(chain) == 0 {
		return
	}
	lhs := sel.expr
	mode := lhs.tav.mode if lhs != nil else Addressing_Mode.Value
	for i in 0 ..< len(chain) - 1 {
		inner := make_using_field_selector(lhs, chain[i])
		inner.tav.mode = mode
		lhs = inner
	}
	sel.expr = lhs
	last := chain[len(chain) - 1]
	if sel.field != nil {
		sel.field.entity = last
		sel.field.tav.type = last.type
		sel.field.tav.mode = mode
	}
	sel.tav.type = last.type
	if mode == .Variable || mode == .Swizzle_Variable {
		sel.tav.mode = .Variable
	} else {
		sel.tav.mode = .Value
	}
}

find_using_subtype_convert_field :: proc(from, to: ^Type) -> (field: ^Entity, ambiguous: bool, ok: bool) {
	st := type_as_struct(from)
	if st == nil || st.fields == nil || to == nil {
		return nil, false, false
	}
	found: ^Entity
	n := 0
	for f in st.fields.variables {
		if f == nil {
			continue
		}
		if .Using not_in f.flags && .Subtype not_in f.flags {
			continue
		}
		if !type_eq(f.type, to) {
			continue
		}
		n += 1
		found = f
	}
	if n == 0 {
		return nil, false, false
	}
	if n > 1 {
		return found, true, false
	}
	return found, false, true
}

// Rewrite `expr` to `expr.field` when a unique using/#subtype field matches `to`.
// Returns nil when no conversion applies (caller reports the type error).
try_using_convert :: proc(c: ^Checker, expr: ^Expr, from, to: ^Type) -> (converted: ^Expr, reported: bool) {
	if expr == nil || from == nil || to == nil {
		return nil, false
	}
	field, amb, ok := find_using_subtype_convert_field(from, to)
	if amb {
		check_err(c, expr.pos, "ambiguous conversion from '%s' to '%s' via using/#subtype fields", string_from_type(from), string_from_type(to))
		return nil, true
	}
	if !ok {
		return nil, false
	}
	return make_using_field_selector(expr, field), true
}

inject_nested_using_names :: proc(c: ^Checker, dest: ^Scope, nested: ^Type_Struct, prefix: []^Entity) {
	if dest == nil || nested == nil || nested.fields == nil {
		return
	}
	for f in nested.fields.variables {
		if f == nil || f.name == "" || f.name == "_" {
			continue
		}
		chain := using_chain_append(prefix, f)
		alias := new_entity(.Variable, dest, f.pos, f.name, f.type)
		alias.using_chain = chain
		alias.aliased_of = f
		alias.module = f.module
		alias.state = .Resolved
		if !scope_define(c, dest, alias) {
			continue
		}
		if .Using in f.flags {
			if inner := type_as_struct(f.type); inner != nil {
				inject_nested_using_names(c, dest, inner, chain)
			}
		}
	}
}

inject_struct_using_fields :: proc(c: ^Checker, st: ^Type_Struct) {
	if st == nil || st.fields == nil || st.scope == nil {
		return
	}
	for field in st.fields.variables {
		if field == nil || .Using not_in field.flags {
			continue
		}
		nested := type_as_struct(field.type)
		if nested == nil {
			check_err(c, field.pos, "'using' field '%s' requires a struct type, got '%s'", field.name, string_from_type(field.type))
			continue
		}
		inject_nested_using_names(c, st.scope, nested, []^Entity{field})
	}
}

inject_using_from_value :: proc(c: ^Checker, dest: ^Scope, base: ^Expr, type: ^Type, pos: Token_Pos) {
	st := type_as_struct(type)
	if st == nil {
		check_err(c, pos, "'using' requires a struct or import name, got '%s'", string_from_type(type))
		return
	}
	if st.scope == nil {
		return
	}
	for name, e in st.scope.entities {
		if e == nil || name == "" || name == "_" {
			continue
		}
		if existing := scope_lookup_current(dest, name); existing != nil {
			check_err(c, pos, "redeclaration of '%s' in this scope", name)
			continue
		}
		alias := new_entity(.Variable, dest, e.pos, name, e.type)
		alias.using_base = base
		alias.module = e.module
		alias.state = .Resolved
		alias.aliased_of = e.aliased_of if e.aliased_of != nil else e
		if len(e.using_chain) > 0 {
			alias.using_chain = e.using_chain
		} else {
			alias.using_chain = using_chain_append(nil, e)
		}
		scope_insert(dest, alias)
	}
}

inject_using_from_import :: proc(c: ^Checker, dest: ^Scope, imp: ^Entity, pos: Token_Pos) {
	if imp == nil || imp.imported_module == nil || imp.imported_module.scope == nil {
		check_err(c, pos, "invalid import in 'using'")
		return
	}
	for _, e in imp.imported_module.scope.entities {
		_ = scope_inject_existing(c, dest, e, pos)
	}
}

check_using_stmt :: proc(c: ^Checker, stmt: ^Using_Stmt) {
	if stmt == nil {
		return
	}
	for expr in stmt.list {
		if expr == nil {
			continue
		}
		op := check_expr_or_type(c, expr)
		if op.mode == .Invalid {
			continue
		}
		if op.mode == .Import {
			imp := entity_from_expr(expr)
			inject_using_from_import(c, c.curr_scope, imp, expr.pos)
			continue
		}
		if op.mode == .Type {
			check_err(c, expr.pos, "'using' of a type name is not supported")
			continue
		}
		if op.mode != .Variable && op.mode != .Value && op.mode != .Swizzle_Variable {
			check_err(c, expr.pos, "'using' requires a struct value or import name")
			continue
		}
		inject_using_from_value(c, c.curr_scope, expr, op.type, expr.pos)
	}
}

check_module_using_stmts :: proc(c: ^Checker) {
	for decl in c.module.decls {
		if us, ok := decl.derived.(^Using_Stmt); ok {
			check_using_stmt(c, us)
		}
	}
}

apply_using_flags_to_field :: proc(c: ^Checker, field: ^Field, var: ^Entity, allow_using: bool) {
	if field == nil || var == nil {
		return
	}
	has_using := .Using in field.flags
	has_subtype := .Subtype in field.flags
	if has_using && has_subtype {
		check_err(c, field.pos, "cannot apply both 'using' and '#subtype' to the same field")
		return
	}
	if has_using {
		if !allow_using {
			check_err(c, field.pos, "'using' is not allowed on this field")
		} else {
			var.flags += {.Using}
		}
	}
	if has_subtype {
		if !allow_using {
			check_err(c, field.pos, "'#subtype' is only allowed on struct fields")
		} else {
			var.flags += {.Subtype}
		}
	}
}

inject_param_using :: proc(c: ^Checker, params: ^Type_Tuple) {
	if params == nil {
		return
	}
	for p in params.variables {
		if p == nil || .Using not_in p.flags {
			continue
		}
		if p.ident != nil {
			p.ident.tav.type = p.type
			p.ident.tav.mode = .Variable
			inject_using_from_value(c, p.scope, p.ident, p.type, p.pos)
		}
	}
}
