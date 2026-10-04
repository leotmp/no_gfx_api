package misl

overload_arg_rank :: proc(from, to: ^Type) -> (rank: int, ok: bool) {
	if from == nil || to == nil {
		return 0, false
	}
	if type_is_untyped(from) {
		if !type_is_implicit_castable(from, to) {
			return 0, false
		}
		dt := default_type(from)
		if dt != from && !type_is_untyped(to) && type_eq(dt, to) {
			return 0, true
		}
		if type_is_integer(from) && type_is_integer(to) {
			return 1, true
		}
		if type_is_integer(from) && type_is_float(to) {
			return 2, true
		}
		if type_is_float(from) && type_is_float(to) {
			return 1, true
		}
		if type_is_boolean(from) && type_is_boolean(to) {
			return 0, true
		}
		return 2, true
	}
	if type_eq(from, to) {
		return 0, true
	}
	if type_is_implicit_castable(from, to) {
		return 3, true
	}
	return 0, false
}

proc_group_flatten_args :: proc(args: []Operand, allocator := context.temp_allocator) -> []Operand {
	flat := make([dynamic]Operand, allocator)
	for a in args {
		if tuple, is_tuple := a.type.derived.(^Type_Tuple); is_tuple {
			for var in tuple.variables {
				append(&flat, Operand{expr = a.expr, type = var.type, mode = .Value})
			}
		} else {
			append(&flat, a)
		}
	}
	return flat[:]
}

proc_group_member_rank :: proc(m: ^Entity, args: []Operand) -> (rank: int, ok: bool) {
	if m == nil || m.type == nil {
		return 0, false
	}
	pt, is_proc := m.type.derived.(^Type_Proc)
	if !is_proc || pt.params == nil {
		return 0, false
	}
	params := pt.params.variables
	flat := proc_group_flatten_args(args)
	if len(flat) != len(params) {
		return 0, false
	}
	total := 0
	for p, i in params {
		if p == nil {
			return 0, false
		}
		r, pok := overload_arg_rank(flat[i].type, p.type)
		if !pok {
			field, amb, uok := find_using_subtype_convert_field(flat[i].type, p.type)
			_ = field
			if uok && !amb {
				r = 4
			} else {
				return 0, false
			}
		}
		if .Ref in p.flags {
			if !flat[i].ref_syntax || (flat[i].mode != .Variable && flat[i].mode != .Swizzle_Variable) {
				return 0, false
			}
		} else if flat[i].ref_syntax {
			return 0, false
		}
		total += r
	}
	return total, true
}

check_proc_group_expr :: proc(checker: ^Checker, v: ^Proc_Group) -> (operand: Operand, members: []^Entity) {
	operand.expr = v
	if v == nil {
		operand.mode = .Invalid
		operand.type = t_invalid
		return
	}
	list := make([dynamic]^Entity, context.temp_allocator)
	for arg in v.args {
		if arg == nil {
			continue
		}
		if _, is_lit := unparen_expr(arg).derived.(^Proc_Lit); is_lit {
			check_err(checker, arg.pos, "proc group members must be named procedures, not literals")
			continue
		}
		op := check_expr(checker, arg)
		if op.mode != .Proc {
			if op.mode == .Shader {
				check_err(checker, arg.pos, "shader entry points cannot be proc group members")
			} else {
				check_err(checker, arg.pos, "expected a named procedure as proc group member")
			}
			continue
		}
		e := strip_entity_wrapping(entity_from_expr(arg))
		if e == nil || e.kind != .Procedure {
			check_err(checker, arg.pos, "proc group members must be named procedures")
			continue
		}
		dup := false
		for prev in list {
			if prev == e {
				check_err(checker, arg.pos, "duplicate proc group member '%s'", e.name)
				dup = true
				break
			}
			if prev.type != nil && e.type != nil && type_eq(prev.type, e.type) {
				check_err(checker, arg.pos, "proc group members '%s' and '%s' have the same signature", prev.name, e.name)
				dup = true
				break
			}
		}
		if dup {
			continue
		}
		append(&list, e)
	}
	if len(list) == 0 {
		operand.mode = .Invalid
		operand.type = t_invalid
		return
	}
	members = make([]^Entity, len(list))
	copy(members, list[:])
	operand.mode = .Proc_Group
	operand.type = t_invalid
	return
}

resolve_proc_group_overload :: proc(checker: ^Checker, call: ^Call_Expr, fn: Operand) -> ^Entity {
	group := strip_entity_wrapping(entity_from_expr(call.expr))
	if group == nil || group.kind != .Proc_Group {
		check_err(checker, call.pos, "invalid procedure group in call")
		return nil
	}
	args := make([]Operand, len(call.args), context.temp_allocator)
	for a, i in call.args {
		inner, has_and := peel_unary_and(a)
		if has_and {
			args[i] = check_expr(checker, inner, allow_multi_value = true)
			stamp_expr_operand(a, args[i])
			args[i].expr = a
			args[i].ref_syntax = true
		} else {
			args[i] = check_expr(checker, a, allow_multi_value = true)
		}
	}
	best_rank := max(int)
	best := make([dynamic]^Entity, context.temp_allocator)
	for m in group.proc_group_members {
		rank, ok := proc_group_member_rank(m, args)
		if !ok {
			continue
		}
		if rank < best_rank {
			clear(&best)
			best_rank = rank
			append(&best, m)
		} else if rank == best_rank {
			append(&best, m)
		}
	}
	switch len(best) {
	case 0:
		check_err(checker, call.pos, "no matching overload in procedure group '%s'", group.name)
		return nil
	case 1:
		return best[0]
	case:
		check_err(checker, call.pos, "ambiguous call to procedure group '%s'", group.name)
		return nil
	}
}
