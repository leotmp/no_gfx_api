package misl

import "core:strings"

// Phase 4: unordered `::` declarations via collect → resolve → bodies.
// Mutable decls stay source-ordered and are checked when encountered.

guess_const_entity_kind :: proc(value: ^Expr) -> Entity_Kind {
	if value == nil do return .Constant
	#partial switch v in value.derived {
	case ^Proc_Lit:
		if v.type != nil && v.type.calling_convention != "" {
			return .Entry
		}
		return .Procedure
	case ^Proc_Group:
		return .Proc_Group
	case ^Struct_Type, ^Enum_Type, ^Matrix_Type, ^Array_Type, ^Multi_Pointer_Type,
	     ^Bit_Set_Type, ^Proc_Type, ^Pointer_Type, ^Helper_Type, ^Distinct_Type:
		return .Type_Name
	case ^Ident:
		// May be a type alias of another type name — refined during resolve
		return .Constant
	}
	return .Constant
}

collect_one_const_value_decl :: proc(c: ^Checker, s: ^Value_Decl, scope: ^Scope, out: ^[dynamic]^Entity) {
	if s.is_mutable do return
	for name, name_i in s.names {
		ident, is_ident := name.derived.(^Ident)
		if !is_ident {
			check_err(c, name.pos, "expected an identifier")
			continue
		}
		if is_blank_ident(ident.name) {
			ident.entity = new_entity_dummy(ident.pos)
			continue
		}
		if found := scope_lookup_current(scope, ident.name); found != nil {
			check_err(c, ident.pos, "redeclaration of '%s' in this scope", ident.name)
			continue
		}
		value: ^Expr
		if name_i < len(s.values) {
			value = s.values[name_i]
		}
		kind := guess_const_entity_kind(value)
		e := new_entity(kind, scope, ident.pos, ident.name, nil)
		e.decl = s
		e.decl_value_index = name_i
		e.module = c.module
		e.owner_proc = c.curr_proc_entity
		e.state = .Unresolved
		ident.entity = e
		e.ident = ident
		scope_insert(scope, e)
		append(out, e)
		append(&c.module.definitions, e)
	}
}

collect_const_decls :: proc(c: ^Checker, stmts: []^Stmt, scope: ^Scope, out: ^[dynamic]^Entity) {
	// Pass 1: stub all `::` at this level (not under `when`) so later `when FOO`
	// can resolve FOO even if FOO is textually below.
	for stmt in stmts {
		#partial switch s in stmt.derived {
		case ^Value_Decl:
			collect_one_const_value_decl(c, s, scope, out)
		case ^Import_Decl:
			// file-scope only; bound in check_module_imports
		}
	}
	// Pass 2: taken `when` / `which` branches only
	for stmt in stmts {
		#partial switch s in stmt.derived {
		case ^When_Stmt:
			taken, cond_ok := eval_when_condition(c, s)
			if !cond_ok do continue
			if taken {
				collect_when_body(c, s.body, scope, out)
			} else if s.else_stmt != nil {
				if _, is_when := s.else_stmt.derived.(^When_Stmt); is_when {
					collect_const_decls(c, {s.else_stmt}, scope, out)
				} else {
					collect_when_body(c, s.else_stmt, scope, out)
				}
			}
		case ^Which_Stmt:
			taken, cond_ok := eval_which_taken_clause(c, s, false)
			if !cond_ok do continue
			if taken != nil {
				collect_const_decls(c, taken.body, scope, out)
			}
		}
	}
}

collect_when_body :: proc(c: ^Checker, body: ^Stmt, scope: ^Scope, out: ^[dynamic]^Entity) {
	if body == nil do return
	if block, ok := body.derived.(^Block_Stmt); ok {
		collect_const_decls(c, block.stmts, scope, out)
	} else {
		collect_const_decls(c, {body}, scope, out)
	}
}

eval_when_condition :: proc(c: ^Checker, d: ^When_Stmt) -> (taken: bool, ok: bool) {
	cond := check_expr(c, d.cond)
	if cond.mode != .Constant {
		check_err(c, d.cond.pos, "'when' condition must be a constant")
		return false, false
	}
	if b, is_bool := cond.value.(bool); is_bool {
		return b, true
	}
	check_err(c, d.cond.pos, "'when' condition must be a boolean constant")
	return false, false
}

which_const_key :: proc(value: Exact_Value) -> (key: i128, ok: bool) {
	#partial switch v in value {
	case i128:
		return v, true
	case bool:
		return 1 if v else 0, true
	}
	return 0, false
}

// Fold `which` to the taken `case`. Case labels are checked; bodies are not.
// `report_coverage` is the exhaustiveness / unmatched-case pass (skip during collect).
eval_which_taken_clause :: proc(c: ^Checker, d: ^Which_Stmt, report_coverage: bool) -> (taken: ^Case_Clause, ok: bool) {
	if d.body == nil {
		check_err(c, d.pos, "'which' body must be a block of case clauses")
		return nil, false
	}
	body, is_block := d.body.derived.(^Block_Stmt)
	if !is_block {
		check_err(c, d.pos, "'which' body must be a block of case clauses")
		return nil, false
	}

	is_bool := d.cond == nil
	tag_type: ^Type = t_invalid
	cond_key: i128
	cond_key_ok := false
	if d.cond != nil {
		tag := check_expr(c, d.cond)
		if tag.mode != .Constant {
			check_err(c, d.cond.pos, "'which' condition must be a constant")
			return nil, false
		}
		tag_type = default_type(tag.type)
		if tag_type == nil {
			tag_type = t_invalid
		}
		if !type_is_integer(tag_type) && !type_is_enum(tag_type) {
			check_err(c, d.cond.pos, "'which' condition must be an integer or enum, got '%s'", string_from_type(tag_type))
			return nil, false
		}
		cond_key, cond_key_ok = which_const_key(tag.value)
		if !cond_key_ok {
			check_err(c, d.cond.pos, "'which' condition must be a constant integer or enum")
			return nil, false
		}
	}

	has_default := false
	default_clause: ^Case_Clause
	seen: map[i128]bool
	defer delete(seen)

	for clause_stmt in body.stmts {
		clause, is_clause := clause_stmt.derived.(^Case_Clause)
		if !is_clause {
			check_err(c, clause_stmt.pos, "expected a 'case' clause in which")
			continue
		}
		if len(clause.list) == 0 {
			if has_default {
				check_err(c, clause.pos, "multiple default cases in which")
			}
			has_default = true
			if default_clause == nil {
				default_clause = clause
			}
			continue
		}
		matched := false
		if is_bool {
			for expr in clause.list {
				val := check_expr(c, expr)
				if val.mode != .Constant {
					check_err(c, expr.pos, "'which' case condition must be a constant")
					continue
				}
				if val.type == nil || val.type == t_invalid || !type_is_boolean(val.type) {
					check_err(c, expr.pos, "case condition must be boolean in a conditionless which, got '%s'", string_from_type(val.type))
					continue
				}
				b, is_b := val.value.(bool)
				if is_b && b {
					matched = true
				}
			}
		} else {
			for expr in clause.list {
				val := check_expr(c, expr, type_hint = tag_type if tag_type != t_invalid else nil)
				if val.mode != .Constant || val.value == nil {
					check_err(c, expr.pos, "case values must be constant")
					continue
				}
				if tag_type != t_invalid && !type_is_implicit_castable(val.type, tag_type) && !type_eq(val.type, tag_type) {
					check_err(c, expr.pos, "case value type '%s' is not compatible with which type '%s'", string_from_type(val.type), string_from_type(tag_type))
				}
				key, key_ok := which_const_key(val.value)
				if !key_ok {
					check_err(c, expr.pos, "unsupported case constant kind")
					continue
				}
				if key in seen {
					check_err(c, expr.pos, "duplicate case value")
				} else {
					seen[key] = true
				}
				if cond_key_ok && key == cond_key {
					matched = true
				}
			}
		}
		if matched && taken == nil {
			taken = clause
		}
	}

	if taken == nil {
		taken = default_clause
	}

	if report_coverage {
		if !is_bool && !d.partial && !has_default {
			if enum_t, is_enum := tag_type.derived.(^Type_Enum); is_enum {
				variant_count := 0
				for _ in enum_t.fields {
					variant_count += 1
				}
				if len(seen) < variant_count {
					check_err(c, d.pos, "which on enum '%s' is not exhaustive; use '#partial which' or add a default case", string_from_type(tag_type))
				}
			}
		}
		if taken == nil && !d.partial {
			check_err(c, d.pos, "'which' has no matching case; add a default 'case:' or use '#partial which'")
		}
	}

	return taken, true
}

which_taken_clause_from_tav :: proc(v: ^Which_Stmt) -> ^Case_Clause {
	if v == nil || v.body == nil do return nil
	body, ok := v.body.derived.(^Block_Stmt)
	if !ok do return nil

	if v.cond == nil {
		default_cl: ^Case_Clause
		for stmt in body.stmts {
			cl, cok := stmt.derived.(^Case_Clause)
			if !cok do continue
			if len(cl.list) == 0 {
				if default_cl == nil do default_cl = cl
				continue
			}
			for expr in cl.list {
				if b, bok := expr.tav.value.(bool); bok && b {
					return cl
				}
			}
		}
		return default_cl
	}

	cond_key, cok := which_const_key(v.cond.tav.value)
	if !cok do return nil
	default_cl: ^Case_Clause
	for stmt in body.stmts {
		cl, cl_ok := stmt.derived.(^Case_Clause)
		if !cl_ok do continue
		if len(cl.list) == 0 {
			if default_cl == nil do default_cl = cl
			continue
		}
		for expr in cl.list {
			key, key_ok := which_const_key(expr.tav.value)
			if key_ok && key == cond_key {
				return cl
			}
		}
	}
	return default_cl
}

ensure_entity_resolved :: proc(c: ^Checker, e: ^Entity) {
	if e == nil do return
	#partial switch e.kind {
	case .Constant, .Type_Name, .Procedure, .Entry, .Pipeline, .Proc_Group, .Builtin:
		if e.state != .Resolved && e.decl != nil {
			decl_resolve(c, e)
		}
	}
}

decl_resolve :: proc(c: ^Checker, e: ^Entity) {
	if e == nil do return
	if e.state == .Resolved do return
	if e.state == .In_Progress {
		check_err(c, e.pos, "illegal dependency cycle involving '%s'", e.name)
		e.state = .Resolved
		e.type = t_invalid
		return
	}
	if e.decl == nil {
		e.state = .Resolved
		return
	}

	e.state = .In_Progress
	defer if e.state == .In_Progress {
		e.state = .Resolved
	}

	decl := e.decl
	idx := e.decl_value_index
	if idx < 0 || idx >= len(decl.values) {
		check_err(c, e.pos, "constant declaration '%s' is missing an initializer", e.name)
		e.type = t_invalid
		e.state = .Resolved
		return
	}

	init_type: ^Type
	if decl.type != nil {
		init_type = check_type(c, decl.type)
	}

	value_expr := decl.values[idx]

	// Procedures: signature first, mark resolved, then body (allows unordered mutual refs;
	// call-graph recursion is forbidden separately — GLSL cannot recurse)
	if lit, is_lit := value_expr.derived.(^Proc_Lit); is_lit {
		old_scope := c.curr_scope
		// Signature sees enclosing scope for nested procs
		type := check_proc_type(c, lit.type)
		lit.type.scope = type.scope
		e.proc_lit = lit
		e.type = type
		check_proc_attributes(c, decl, type, e)
		if type.stage != nil || type.is_fmag {
			if e.owner_proc != nil {
				check_err(c, lit.pos, "shader entry points cannot be nested; declare '%s' at module scope", e.name)
			}
			e.kind = .Entry
			bind_entry_entity(c.module, e)
		} else {
			e.kind = .Procedure
		}
		e.state = .Resolved

		if len(lit.where_clauses) > 0 {
			check_err(c, lit.pos, "'where' clauses are not supported")
		}

		// Check body with this entity as owner for nested decls
		proc_t := type
		if !proc_is_generic_template(proc_t) && should_check_proc_body_now(c, type) {
			ensure_proc_body_checked(c, e)
		}
		c.curr_scope = old_scope
		if e.ident != nil {
			e.ident.tav.type = type
			e.ident.tav.mode = .Proc if e.kind == .Procedure else .Shader
		}
		return
	}

	if pg, is_pg := value_expr.derived.(^Proc_Group); is_pg {
		op, members := check_proc_group_expr(c, pg)
		e.kind = .Proc_Group
		e.type = t_invalid
		e.proc_group_members = members
		if op.mode == .Invalid {
			e.type = t_invalid
		}
		if e.ident != nil {
			e.ident.tav.type = t_invalid
			e.ident.tav.mode = .Proc_Group
		}
		check_decl_attributes(c, decl, e, nil)
		e.state = .Resolved
		return
	}

	v := check_expr_internal(c, value_expr, init_type)
	if v.mode != .Builtin {
		if v.type == nil {
			v.type = t_invalid
			v.mode = .Invalid
		}
		// Constants keep the exact expression type (including untyped) unless a type
		// hint is present: `A :: 2` → untyped integer; `A : f32 : 2` → f32.
		if type_is_untyped(v.type) {
			if init_type != nil {
				convert_to_typed(c, &v, init_type)
			}
		} else if init_type != nil && type_is_implicit_castable(v.type, init_type) {
			v.type = init_type
		}
	}

	#partial switch v.mode {
	case .Builtin:
		e.kind = .Builtin
		e.builtin_id = v.builtin_id
		e.type = v.type
	case .Type:
		e.kind = .Type_Name
		e.type = v.type
		if v.type != nil && v.type.name == "" {
			v.type.name = e.name
		}
		alias_expr := unparen_expr(value_expr)
		if ident, is_ident := alias_expr.derived.(^Ident); is_ident && ident.entity != nil {
			e.aliased_of = ident.entity
		}
	case .Constant:
		if type_is_pipeline(v.type) {
			if e.owner_proc != nil {
				check_err(c, value_expr.pos, "pipeline declarations cannot be nested; declare '%s' at module scope", e.name)
			}
			e.kind = .Pipeline
			e.type = v.type
			e.checked_pipeline = v.checked_pipeline
			bind_pipeline_entity(c.module, e)
		} else {
			e.kind = .Constant
			e.type = v.type
			if v.value == nil {
				check_err(c, value_expr.pos, "constant declaration requires a constant expression")
			} else {
				e.value = v.value
			}
			if arr, is_arr := e.type.derived.(^Type_Array); is_arr {
				if !type_is_const_array_elem_ok(arr.elem) {
					check_err(c, value_expr.pos, "constant arrays must have scalar elements, got '%s'", string_from_type(arr.elem))
				}
			}
		}
	case .Proc, .Shader:
		// Should have been handled via Proc_Lit above
		e.kind = .Procedure if v.mode == .Proc else .Entry
		e.type = v.type
	case .Invalid:
		e.type = t_invalid
	case:
		check_err(c, value_expr.pos, "constant declaration expects a type, procedure, or constant value, got '%s'", v.mode)
		e.type = t_invalid
	}

	if e.ident != nil {
		e.ident.tav.type = e.type
		e.ident.tav.mode = v.mode
		e.ident.tav.value = e.value
	}
	check_decl_attributes(c, decl, e, nil)
	e.state = .Resolved
}

bind_entry_entity :: proc(m: ^Module, e: ^Entity) {
	if m == nil || e == nil do return
	for pe in m.entries {
		if pe != nil && pe.name == e.name {
			pe.entity = e
			if pe.module == nil {
				pe.module = m
			}
			return
		}
	}
	kind: Entry_Kind
	if e.type != nil {
		if pt, ok := e.type.derived.(^Type_Proc); ok {
			if pt.is_fmag {
				kind = .Fmag
			} else if stage, sok := pt.stage.?; sok {
				kind = entry_kind_from_stage(stage)
			}
		}
	}
	pe := new(Entry)
	pe.name = e.name
	pe.kind = kind
	pe.entity = e
	pe.module = m
	append(&m.entries, pe)
}

bind_pipeline_entity :: proc(m: ^Module, e: ^Entity) {
	if m == nil || e == nil do return
	for pp in m.pipelines {
		if pp != nil && pp.name == e.name {
			pp.entity = e
			if pp.module == nil {
				pp.module = m
			}
			return
		}
	}
	pp := new(Pipeline)
	pp.name = e.name
	pp.entity = e
	pp.module = m
	append(&m.pipelines, pp)
}

should_check_proc_body_now :: proc(c: ^Checker, type: ^Type_Proc) -> bool {
	if type == nil do return false
	if type.stage != nil {
		return c.compile_mode == .SPIRV
	}
	if type.is_fmag {
		return c.compile_mode == .FMAG
	}
	// Helpers: typecheck all bodies under SPIRV. FMAG typechecks helpers on-demand
	// so a GPU-only helper is not checked under `.FMAG`.
	if c.compile_mode == .FMAG {
		return false
	}
	return true
}

ensure_proc_body_checked :: proc(c: ^Checker, e: ^Entity) {
	if e == nil do return
	if .Body_Checked in e.flags do return
	if e.kind != .Procedure && e.kind != .Entry do return
	if e.proc_lit == nil || e.type == nil do return
	type, ok := e.type.derived.(^Type_Proc)
	if !ok do return
	if proc_is_generic_template(type) do return
	e.flags += {.Body_Checked}
	check_proc_lit_body(c, e.proc_lit, type, e)
}

check_proc_lit_body :: proc(c: ^Checker, lit: ^Proc_Lit, type: ^Type_Proc, owner: ^Entity) {
	block, ok := lit.body.derived.(^Block_Stmt)
	if !ok {
		check_err(c, lit.pos, "procedure body must be a block")
		return
	}
	block.scope = create_scope(type.scope, .Block)
	old_scope := c.curr_scope
	old_proc := c.curr_proc
	old_entity := c.curr_proc_entity
	c.curr_scope = block.scope
	c.curr_proc = type
	c.curr_proc_entity = owner
	check_block_stmts(c, block.stmts)
	c.curr_scope = old_scope
	c.curr_proc = old_proc
	c.curr_proc_entity = old_entity
}

// Collect + resolve `::` in a block, then check remaining stmts (mutable decls, etc.)
check_block_stmts :: proc(c: ^Checker, stmts: []^Stmt) {
	entities := make([dynamic]^Entity, context.temp_allocator)
	collect_const_decls(c, stmts, c.curr_scope, &entities)
	for e in entities {
		decl_resolve(c, e)
	}
	for stmt in stmts {
		check_stmt_after_const_collect(c, stmt)
	}
}

check_stmt_after_const_collect :: proc(c: ^Checker, stmt: ^Stmt) -> (diverging: bool) {
	#partial switch d in stmt.derived {
	case ^Bad_Decl, ^Bad_Stmt:
		return false
	case ^Value_Decl:
		if !d.is_mutable {
			// Already collected + resolved
			return false
		}
		check_value_decl(c, d)
		return false
	case ^When_Stmt:
		// Const decls in taken branch already collected; still need to check stmts in taken branch
		taken, ok := eval_when_condition(c, d)
		if !ok do return false
		if taken {
			check_when_body_stmts(c, d.body)
		} else if d.else_stmt != nil {
			if _, is_when := d.else_stmt.derived.(^When_Stmt); is_when {
				check_stmt_after_const_collect(c, d.else_stmt)
			} else {
				check_when_body_stmts(c, d.else_stmt)
			}
		}
		return false
	case ^Which_Stmt:
		check_which_stmt(c, d)
		return false
	case ^Using_Stmt:
		if c.curr_scope != nil && c.curr_scope.kind == .Module {
			return false
		}
		check_using_stmt(c, d)
		return false
	case ^Block_Stmt:
		old := c.curr_scope
		d.scope = create_scope(c.curr_scope, .Block)
		c.curr_scope = d.scope
		check_block_stmts(c, d.stmts)
		c.curr_scope = old
		return false
	}
	return check_stmt(c, stmt)
}

check_when_body_stmts :: proc(c: ^Checker, body: ^Stmt) {
	if body == nil do return
	if block, ok := body.derived.(^Block_Stmt); ok {
		// when does not introduce a scope — consts already in enclosing scope
		for stmt in block.stmts {
			check_stmt_after_const_collect(c, stmt)
		}
	} else {
		check_stmt_after_const_collect(c, body)
	}
}

entity_belongs_to_proc :: proc(e: ^Entity, proc_t: ^Type_Proc) -> bool {
	if e == nil || proc_t == nil || proc_t.scope == nil do return false
	s := e.scope
	for s != nil {
		if s == proc_t.scope do return true
		if s.kind == .Module do return false
		s = s.outer
	}
	return false
}

// Reject capturing outer params/locals from a nested (or any) procedure.
check_capture_rules :: proc(c: ^Checker, pos: Token_Pos, e: ^Entity) {
	if c.curr_proc == nil || e == nil do return
	if e.kind != .Variable do return
	if entity_belongs_to_proc(e, c.curr_proc) do return
	check_err(c, pos, "cannot capture '%s' from an enclosing procedure; only constant (`::`) bindings are visible — pass it as an argument", e.name)
}

rebind_call_callee :: proc(call: ^Call_Expr, spec: ^Entity) {
	if call == nil || spec == nil do return
	expr := unparen_expr(call.expr)
	if expr == nil do return
	#partial switch e in expr.derived {
	case ^Ident:
		e.entity = spec
		e.tav.type = spec.type
		e.tav.mode = .Proc
	case ^Selector_Expr:
		if e.field != nil {
			e.field.entity = spec
			e.field.tav.type = spec.type
			e.field.tav.mode = .Proc
		}
	}
}

poly_spec_matches :: proc(spec: ^Entity, values: []Exact_Value) -> bool {
	if spec == nil || spec.type == nil do return false
	proc_t, ok := spec.type.derived.(^Type_Proc)
	if !ok do return false
	vi := 0
	for p in proc_t.params.variables {
		if .Poly_Const not_in p.flags do continue
		if vi >= len(values) || !exact_values_equal(p.value, values[vi]) {
			return false
		}
		vi += 1
	}
	return vi == len(values)
}

find_or_generate_poly_proc :: proc(c: ^Checker, generic: ^Entity, args: []Operand, call: ^Call_Expr) -> ^Entity {
	if generic == nil || generic.proc_lit == nil || generic.type == nil {
		return nil
	}
	proc_t, is_proc := generic.type.derived.(^Type_Proc)
	if !is_proc do return nil

	values := make([dynamic]Exact_Value, context.temp_allocator)
	ok := true
	for p, i in proc_t.params.variables {
		if .Poly_Const not_in p.flags do continue
		if i >= len(args) {
			ok = false
			break
		}
		op := args[i]
		if type_is_proc(p.type) {
			if op.mode != .Proc {
				pos := call.pos
				if op.expr != nil do pos = op.expr.pos
				check_err(c, pos, "constant parapoly argument must be a named procedure")
				ok = false
				continue
			}
			callee := strip_entity_wrapping(entity_from_expr(op.expr))
			if callee == nil || callee.kind != .Procedure {
				pos := call.pos
				if op.expr != nil do pos = op.expr.pos
				if callee != nil && callee.kind == .Entry {
					check_err(c, pos, "shader entry points cannot be passed as '$fn' procedure arguments")
				} else {
					check_err(c, pos, "constant parapoly argument must be a named procedure")
				}
				ok = false
				continue
			}
			if !type_eq(callee.type, p.type) {
				pos := call.pos
				if op.expr != nil do pos = op.expr.pos
				check_err(c, pos, "procedure type does not match '$' parameter: '%s' vs '%s'", string_from_type(callee.type), string_from_type(p.type))
				ok = false
				continue
			}
			append(&values, callee)
			continue
		}
		if op.mode != .Constant || op.value == nil {
			pos := call.pos
			if op.expr != nil do pos = op.expr.pos
			check_err(c, pos, "constant parapoly argument must be a compile-time constant")
			ok = false
			continue
		}
		convert_to_typed(c, &op, p.type)
		if op.mode == .Invalid {
			ok = false
			continue
		}
		args[i] = op
		append(&values, op.value)
	}
	if !ok do return nil

	for spec in generic.gen_procs {
		if poly_spec_matches(spec, values[:]) {
			return spec
		}
	}

	cloned := clone_proc_lit(generic.proc_lit)
	if cloned == nil || cloned.type == nil {
		check_err(c, call.pos, "internal: failed to clone polymorphic procedure")
		return nil
	}

	spec := new_entity(.Procedure, generic.scope, generic.pos, generic.name, nil)
	spec.module = generic.module
	spec.owner_proc = generic.owner_proc
	spec.proc_lit = cloned
	spec.state = .In_Progress

	old_module := c.module
	old_scope := c.curr_scope
	old_proc := c.curr_proc
	old_entity := c.curr_proc_entity
	c.module = generic.module
	c.curr_scope = generic.scope

	spec_type := check_proc_type(c, cloned.type, args)
	spec_type.poly_origin = generic
	spec_type.is_polymorphic = true
	spec_type.is_poly_specialized = true
	cloned.type.scope = spec_type.scope
	spec.type = spec_type
	spec.state = .Resolved
	check_proc_lit_body(c, cloned, spec_type, spec)
	spec.flags += {.Body_Checked}

	c.module = old_module
	c.curr_scope = old_scope
	c.curr_proc = old_proc
	c.curr_proc_entity = old_entity

	append(&generic.gen_procs, spec)
	append(&generic.module.definitions, spec)
	return spec
}

// Record a Procedure/Entry call edge for GLSL no-recursion enforcement.
// Edges are collected during body checking; cycles are reported in check_no_proc_recursion.
record_proc_call :: proc(c: ^Checker, callee: ^Entity, call_pos: Token_Pos) {
	caller := c.curr_proc_entity
	if caller == nil || callee == nil do return
	if caller.kind != .Procedure && caller.kind != .Entry do return
	if callee.kind != .Procedure && callee.kind != .Entry do return
	for existing in caller.callees {
		if existing == callee do return
	}
	append(&caller.callees, callee)
	_ = call_pos
}

Proc_Visit_Color :: enum u8 {
	White,
	Gray,
	Black,
}

// DFS over the call graph. Detects direct, mutual, and multi-hop cycles at any depth.
check_no_proc_recursion :: proc(c: ^Checker) {
	if c.module == nil do return
	colors := make(map[^Entity]Proc_Visit_Color, context.temp_allocator)
	path := make([dynamic]^Entity, context.temp_allocator)

	for e in c.module.definitions {
		if e.kind == .Procedure || e.kind == .Entry {
			check_proc_recursion_visit(c, e, &colors, &path)
		}
	}
}

check_proc_recursion_visit :: proc(
	c: ^Checker,
	e: ^Entity,
	colors: ^map[^Entity]Proc_Visit_Color,
	path: ^[dynamic]^Entity,
) {
	if e == nil do return
	if e.kind != .Procedure && e.kind != .Entry do return

	col := colors[e] or_else .White
	if col == .Black do return
	if col == .Gray {
		// Cycle: e appears earlier on the DFS path
		start := -1
		for node, i in path {
			if node == e {
				start = i
				break
			}
		}
		parts := make([dynamic]string, context.temp_allocator)
		if start >= 0 {
			for i in start ..< len(path) {
				append(&parts, path[i].name)
			}
		}
		append(&parts, e.name)
		cycle := strings.join(parts[:], " -> ", context.temp_allocator)
		check_err(c, e.pos, "recursive procedure call is not allowed (GLSL cannot recurse): %s", cycle)
		return
	}

	colors[e] = .Gray
	append(path, e)
	for callee in e.callees {
		check_proc_recursion_visit(c, callee, colors, path)
	}
	pop(path)
	colors[e] = .Black
}

check_graphics_device_store_effects :: proc(c: ^Checker) {
	for pe in c.module.entries {
		entry := pe.entity if pe != nil else nil
		if entry == nil || entry.type == nil do continue
		proc_t, ok := entry.type.derived.(^Type_Proc)
		if !ok do continue
		stage, has_stage := proc_t.stage.?
		if !has_stage do continue
		#partial switch stage {
		case .Vertex, .Fragment:
			if proc_reachable_device_store(entry) {
				check_err(c, entry.pos, "device pointee stores reachable from %s entry '%s' (direct or via helpers)", stage, entry.name)
			}
			if proc_reachable_compute_sync(entry) {
				check_err(c, entry.pos, "compute sync builtin reachable from %s entry '%s' (direct or via helpers)", stage, entry.name)
			}
		}
	}
}

proc_reachable_device_store :: proc(e: ^Entity) -> bool {
	visited := make(map[^Entity]bool, context.temp_allocator)
	return proc_reachable_device_store_visit(e, &visited)
}

proc_reachable_device_store_visit :: proc(e: ^Entity, visited: ^map[^Entity]bool) -> bool {
	if e == nil || e in visited^ do return false
	visited^[e] = true
	if e.type != nil {
		if proc_t, ok := e.type.derived.(^Type_Proc); ok {
			if len(proc_t.device_store_elems) > 0 {
				return true
			}
		}
	}
	for callee in e.callees {
		if proc_reachable_device_store_visit(callee, visited) {
			return true
		}
	}
	return false
}

proc_callgraph_stores_elem :: proc(e: ^Entity, elem: ^Type) -> bool {
	if e == nil || elem == nil do return false
	visited := make(map[^Entity]bool, context.temp_allocator)
	return proc_callgraph_stores_elem_visit(e, elem, &visited)
}

proc_callgraph_stores_elem_visit :: proc(e: ^Entity, elem: ^Type, visited: ^map[^Entity]bool) -> bool {
	if e == nil || e in visited^ do return false
	visited^[e] = true
	if e.type != nil {
		if proc_t, ok := e.type.derived.(^Type_Proc); ok {
			if proc_t.device_store_elems[elem] {
				return true
			}
		}
	}
	for callee in e.callees {
		if proc_callgraph_stores_elem_visit(callee, elem, visited) {
			return true
		}
	}
	return false
}

check_stage_gates :: proc(c: ^Checker) {
	if c.module == nil do return
	done := make(map[^Entity]bool, context.temp_allocator)
	visiting := make(map[^Entity]bool, context.temp_allocator)
	for e in c.module.definitions {
		if e == nil do continue
		if e.kind == .Procedure || e.kind == .Entry {
			propagate_stage_gate(e, &done, &visiting)
		}
	}
	for pe in c.module.entries {
		check_entry_stage_gates(c, pe.entity if pe != nil else nil)
		check_entry_fmag_gates(c, pe.entity if pe != nil else nil)
	}
}

propagate_stage_gate :: proc(e: ^Entity, done: ^map[^Entity]bool, visiting: ^map[^Entity]bool) {
	if e == nil || e in done^ do return
	if e in visiting^ do return
	visiting^[e] = true
	for callee in e.callees {
		propagate_stage_gate(callee, done, visiting)
		if e.kind == .Procedure {
			inherit_stage_gate_from_callee(e, callee)
			inherit_fmag_illegal_from_callee(e, callee)
		}
	}
	visiting^[e] = false
	done^[e] = true
}

inherit_stage_gate_from_callee :: proc(caller: ^Entity, callee: ^Entity) {
	if caller == nil || callee == nil || caller.type == nil || callee.type == nil do return
	caller_pt, caller_ok := caller.type.derived.(^Type_Proc)
	callee_pt, callee_ok := callee.type.derived.(^Type_Proc)
	if !caller_ok || !callee_ok do return
	if !callee_pt.has_stage_gate do return
	inherit_proc_stage_gate(caller_pt, callee_pt.stage_gate, callee_pt.gate_reason)
}

mark_fmag_illegal :: proc(pt: ^Type_Proc, reason: string) {
	if pt == nil || pt.is_fmag || pt.stage != nil do return
	if pt.fmag_illegal do return
	pt.fmag_illegal = true
	pt.fmag_illegal_reason = reason
}

inherit_fmag_illegal_from_callee :: proc(caller: ^Entity, callee: ^Entity) {
	if caller == nil || callee == nil || caller.type == nil || callee.type == nil do return
	caller_pt, caller_ok := caller.type.derived.(^Type_Proc)
	callee_pt, callee_ok := callee.type.derived.(^Type_Proc)
	if !caller_ok || !callee_ok do return
	if callee_pt.fmag_illegal {
		mark_fmag_illegal(caller_pt, callee_pt.fmag_illegal_reason)
	}
}

check_entry_fmag_gates :: proc(c: ^Checker, entry: ^Entity) {
	if entry == nil || entry.type == nil do return
	proc_t, ok := entry.type.derived.(^Type_Proc)
	if !ok || !proc_t.is_fmag do return
	for callee in entry.callees {
		if callee == nil || callee.kind != .Procedure || callee.type == nil do continue
		callee_pt, cok := callee.type.derived.(^Type_Proc)
		if !cok do continue
		if callee_pt.fmag_illegal {
			reason := callee_pt.fmag_illegal_reason if callee_pt.fmag_illegal_reason != "" else callee.name
			check_err(c, entry.pos, "proc %s called in proc \"fmag\" '%s', contains '%s', which is not allowed in proc \"fmag\"",
				callee.name, entry.name, reason)
		}
	}
	visited := make(map[^Entity]bool, context.temp_allocator)
	for callee in entry.callees {
		check_fmag_callee_abi(c, entry, callee, &visited)
	}
}

check_fmag_callee_abi :: proc(c: ^Checker, entry: ^Entity, callee: ^Entity, visited: ^map[^Entity]bool) {
	if callee == nil || callee in visited^ do return
	visited^[callee] = true
	if callee.kind == .Entry {
		check_err(c, entry.pos, "proc \"fmag\" '%s' cannot call shader entry '%s'", entry.name, callee.name)
		return
	}
	if callee.kind != .Procedure || callee.type == nil do return
	callee_pt, cok := callee.type.derived.(^Type_Proc)
	if !cok do return
	if callee_pt.params != nil {
		for param in callee_pt.params.variables {
			if param == nil || entity_is_poly_const(param) do continue
			if .Ref in param.flags {
				check_err(c, entry.pos, "proc %s called in proc \"fmag\" '%s', contains '#ref', which is not allowed in proc \"fmag\"", callee.name, entry.name)
			}
			if param.type != nil && param.type != t_invalid && !fmag_value_type_ok(param.type) {
				if v, vok := param.type.derived.(^Type_Vector); vok && (v.elem == nil || v.elem == t_invalid) {
					continue
				}
				check_err(c, entry.pos, "proc %s called in proc \"fmag\" '%s' has parameter '%s' of type '%s'; proc \"fmag\" values must be f32 or [2/3/4]f32",
					callee.name, entry.name, param.name, string_from_type(param.type))
			}
		}
	}
	if callee_pt.results != nil {
		for result in callee_pt.results.variables {
			if result == nil || result.type == nil || result.type == t_invalid do continue
			if v, vok := result.type.derived.(^Type_Vector); vok && (v.elem == nil || v.elem == t_invalid) {
				continue
			}
			if !fmag_value_type_ok(result.type) {
				name := result.name if result.name != "" else "result"
				check_err(c, entry.pos, "proc %s called in proc \"fmag\" '%s' has %s of type '%s'; proc \"fmag\" values must be f32 or [2/3/4]f32",
					callee.name, entry.name, name, string_from_type(result.type))
			}
		}
	}
	for sub in callee.callees {
		check_fmag_callee_abi(c, entry, sub, visited)
	}
}

check_entry_stage_gates :: proc(c: ^Checker, entry: ^Entity) {
	if entry == nil || entry.type == nil do return
	proc_t, ok := entry.type.derived.(^Type_Proc)
	if !ok do return
	stage, has_stage := proc_t.stage.?
	if !has_stage do return
	bstage := builtin_stage_from_stage(stage)
	for callee in entry.callees {
		if callee == nil || callee.kind != .Procedure || callee.type == nil do continue
		callee_pt, cok := callee.type.derived.(^Type_Proc)
		if !cok || !callee_pt.has_stage_gate do continue
		if bstage in callee_pt.stage_gate do continue
		reason := callee_pt.gate_reason if callee_pt.gate_reason != "" else callee.name
		check_err(c, entry.pos, "proc %s called in %s shader '%s', contains a call to '%s', which is a %s-only procedure",
			callee.name, stage_adjective(stage), entry.name, reason, builtin_stages_adjective(callee_pt.stage_gate))
	}
}

proc_reachable_compute_sync :: proc(e: ^Entity) -> bool {
	visited := make(map[^Entity]bool, context.temp_allocator)
	return proc_reachable_compute_sync_visit(e, &visited)
}

proc_reachable_compute_sync_visit :: proc(e: ^Entity, visited: ^map[^Entity]bool) -> bool {
	if e == nil || e in visited^ do return false
	visited^[e] = true
	if e.type != nil {
		if proc_t, ok := e.type.derived.(^Type_Proc); ok {
			if proc_t.uses_compute_sync {
				return true
			}
		}
	}
	for callee in e.callees {
		if proc_reachable_compute_sync_visit(callee, visited) {
			return true
		}
	}
	return false
}

check_proc_attributes :: proc(c: ^Checker, decl: ^Value_Decl, type: ^Type_Proc, e: ^Entity) {
	check_decl_attributes(c, decl, e, type)
}

check_decl_attributes :: proc(c: ^Checker, decl: ^Value_Decl, e: ^Entity, proc_type: ^Type_Proc) {
	if decl == nil || e == nil do return
	seen_size := false
	seen_builtin := false
	for attr in decl.attributes {
		for elem in attr.elems {
			if ident, is_ident := elem.derived.(^Ident); is_ident {
				switch ident.name {
				case "builtin":
					if seen_builtin {
						check_err(c, ident.pos, "duplicate 'builtin' attribute")
						continue
					}
					seen_builtin = true
					if !module_is_compiler_core(c.module) {
						check_err(c, ident.pos, "'@(builtin)' is only allowed in compiler-integrated core modules")
						continue
					}
					e.flags += {.Ambient_Builtin}
				case:
					check_err(c, ident.pos, "unknown attribute '%s'", ident.name)
				}
				continue
			}
			fv, is_fv := elem.derived.(^Field_Value)
			if !is_fv {
				check_err(c, elem.pos, "attributes must be of the form 'name = value'")
				continue
			}
			name_ident, is_ident := fv.field.derived.(^Ident)
			if !is_ident {
				check_err(c, fv.field.pos, "attribute name must be an identifier")
				continue
			}
			switch name_ident.name {
			case "size":
				if seen_size {
					check_err(c, fv.pos, "duplicate 'size' attribute")
					continue
				}
				seen_size = true
				if proc_type == nil {
					check_err(c, fv.pos, "'@(size=…)' is only allowed on compute entry procedures")
					continue
				}
				stage, ok := proc_type.stage.?
				if !ok || stage != .Compute {
					check_err(c, fv.pos, "'@(size=…)' is only allowed on compute entry procedures")
					continue
				}
				proc_type.local_size = check_compute_local_size(c, fv.value)
			case:
				check_err(c, name_ident.pos, "unknown attribute '%s'", name_ident.name)
			}
		}
	}
}

check_compute_local_size :: proc(c: ^Checker, expr: ^Expr) -> [3]u32 {
	result := [3]u32{1, 1, 1}
	if expr == nil do return result

	// Untyped compound {x}, {x,y}, {x,y,z}
	if lit, is_lit := expr.derived.(^Comp_Lit); is_lit && lit.type == nil {
		if len(lit.elems) < 1 || len(lit.elems) > 3 {
			check_err(c, expr.pos, "'@(size=…)' compound expects 1 to 3 components, got %d", len(lit.elems))
			return result
		}
		for elem, i in lit.elems {
			if _, is_fv := elem.derived.(^Field_Value); is_fv {
				check_err(c, elem.pos, "'@(size=…)' components must be positional constants")
				return result
			}
			op := check_expr(c, elem)
			if op.mode != .Constant || !type_is_integer(op.type) {
				check_err(c, elem.pos, "'@(size=…)' component must be an integer constant")
				return result
			}
			val := exact_value_to_i128(op.value)
			if val < 1 {
				check_err(c, elem.pos, "'@(size=…)' component must be >= 1, got %v", val)
				return result
			}
			result[i] = u32(val)
		}
		return validate_local_size(c, expr.pos, result)
	}

	op := check_expr(c, expr)
	if op.mode != .Constant {
		check_err(c, expr.pos, "'@(size=…)' value must be a compile-time constant")
		return result
	}

	// Scalar → (X,1,1)
	if type_is_integer(op.type) || (type_is_numeric(op.type) && type_is_implicit_castable(op.type, t_u32)) {
		if !type_is_implicit_castable(op.type, t_u32) && !type_is_castable(op.type, t_u32) {
			check_err(c, expr.pos, "'@(size=…)' scalar must convert to u32")
			return result
		}
		val := exact_value_to_i128(op.value)
		if val < 1 {
			check_err(c, expr.pos, "'@(size=…)' must be >= 1, got %v", val)
			return result
		}
		result[0] = u32(val)
		return validate_local_size(c, expr.pos, result)
	}

	if vec, is_vec := op.type.derived.(^Type_Vector); is_vec {
		if !type_eq(vec.elem, t_u32) && !type_is_implicit_castable(vec.elem, t_u32) && !type_is_castable(vec.elem, t_u32) {
			check_err(c, expr.pos, "'@(size=…)' vector elements must convert to u32")
			return result
		}
		if vec.len < 2 || vec.len > 3 {
			check_err(c, expr.pos, "'@(size=…)' vector must be [2]u32 or [3]u32, got '%s'", string_from_type(op.type))
			return result
		}
		// Vector constant values aren't structured in Exact_Value easily — re-check as compound if Comp_Lit typed
		if lit, is_lit := expr.derived.(^Comp_Lit); is_lit {
			for elem, i in lit.elems {
				if i >= int(vec.len) do break
				elem_op := check_expr(c, elem)
				if elem_op.mode != .Constant {
					check_err(c, elem.pos, "'@(size=…)' component must be constant")
					return result
				}
				val := exact_value_to_i128(elem_op.value)
				if val < 1 {
					check_err(c, elem.pos, "'@(size=…)' component must be >= 1")
					return result
				}
				result[i] = u32(val)
			}
			return validate_local_size(c, expr.pos, result)
		}
		check_err(c, expr.pos, "'@(size=…)' vector must be a compound literal")
		return result
	}

	check_err(c, expr.pos, "'@(size=…)' expects u32, [2]u32, or [3]u32, got '%s'", string_from_type(op.type))
	return result
}

validate_local_size :: proc(c: ^Checker, pos: Token_Pos, size: [3]u32) -> [3]u32 {
	x, y, z := size[0], size[1], size[2]
	if x < 1 || y < 1 || z < 1 {
		check_err(c, pos, "'@(size=…)' components must be >= 1")
		return {1, 1, 1}
	}
	if x > 128 || y > 128 || z > 64 {
		check_err(c, pos, "'@(size=…)' exceeds Vulkan minimum caps (x,y <= 128, z <= 64), got (%v,%v,%v)", x, y, z)
		return size
	}
	product := u64(x) * u64(y) * u64(z)
	if product > 128 {
		check_err(c, pos, "'@(size=…)' product x*y*z must be <= 128, got %v", product)
	}
	return size
}

exact_value_to_i128 :: proc(v: Exact_Value) -> i128 {
	#partial switch x in v {
	case i128: return x
	case f64: return i128(x)
	}
	return 0
}
