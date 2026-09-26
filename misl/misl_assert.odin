package misl

check_assert :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	n := len(call.args)
	if n != 1 && n != 2 {
		check_err(checker, call.pos, "'assert' expects 1 or 2 arguments, got %d", n)
		return builtin_fail(checker, call)
	}

	cond := check_expr(checker, call.args[0], type_hint = t_b32)
	if cond.mode == .Invalid {
		return builtin_fail(checker, call)
	}
	if !type_is_boolean(cond.type) {
		check_err(checker, call.args[0].pos, "'assert' condition must be a bool, got '%s'", string_from_type(cond.type))
		return builtin_fail(checker, call)
	}

	if n == 2 {
		if !check_const_string_arg(checker, call.args[1], "assert") {
			return builtin_fail(checker, call)
		}
	}

	return builtin_no_value(call, id)
}

check_panic :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
	if !check_const_string_arg(checker, call.args[0], "panic") {
		return builtin_fail(checker, call)
	}
	return builtin_no_value(call, id)
}

check_const_string_arg :: proc(checker: ^Checker, arg: ^Expr, builtin_name: string) -> bool {
	op := check_expr(checker, arg)
	if op.mode != .Constant {
		check_err(checker, arg.pos, "'%s' message must be a constant string", builtin_name)
		return false
	}
	_, is_str := op.value.(string)
	if !is_str {
		check_err(checker, arg.pos, "'%s' message must be a constant string", builtin_name)
		return false
	}
	return true
}

call_const_string_arg :: proc(arg: ^Expr) -> (s: string, ok: bool) {
	if arg == nil || arg.tav.mode != .Constant do return "", false
	s, ok = arg.tav.value.(string)
	return
}
