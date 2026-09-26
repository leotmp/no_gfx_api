package misl

import spv "spirv"

Wave_Glsl_Ext :: enum {
	Basic,
	Vote,
	Arithmetic,
	Ballot,
	Shuffle,
	Shuffle_Relative,
	Clustered,
	Quad,
	Rotate,
}
Wave_Glsl_Exts :: bit_set[Wave_Glsl_Ext]

builtin_is_wave :: proc(id: Builtin_Proc) -> bool {
	return id >= .wave_is_first && id <= .wave_clustered_rotate
}

builtin_wave_glsl_exts :: proc(id: Builtin_Proc) -> Wave_Glsl_Exts {
	#partial switch id {
	case .wave_is_first, .wave_lane_count, .wave_lane_id, .wave_broadcast_first:
		return {.Basic}
	case .wave_any, .wave_all, .wave_all_equal:
		return {.Vote}
	case .wave_sum, .wave_product, .wave_min, .wave_max,
	     .wave_bit_and, .wave_bit_or, .wave_bit_xor,
	     .wave_prefix_sum, .wave_prefix_product:
		return {.Arithmetic}
	case .wave_ballot, .wave_bit_count, .wave_prefix_bit_count:
		return {.Ballot}
	case .wave_read, .wave_shuffle_xor:
		return {.Shuffle}
	case .wave_shuffle_up, .wave_shuffle_down:
		return {.Shuffle_Relative}
	case .wave_clustered_sum, .wave_clustered_product, .wave_clustered_min, .wave_clustered_max,
	     .wave_clustered_bit_and, .wave_clustered_bit_or, .wave_clustered_bit_xor:
		return {.Clustered, .Arithmetic}
	case .wave_quad_x, .wave_quad_y, .wave_quad_diag, .wave_quad_read:
		return {.Quad}
	case .wave_rotate:
		return {.Rotate}
	case .wave_clustered_rotate:
		return {.Rotate, .Clustered}
	}
	return {}
}

wave_payload_numeric :: proc(t: ^Type) -> bool {
	return type_is_gen(t, t_f32) || type_is_gen(t, t_i32) || type_is_gen(t, t_u32)
}

wave_payload_bits :: proc(t: ^Type) -> bool {
	return type_is_gen(t, t_i32) || type_is_gen(t, t_u32)
}

wave_payload_any :: proc(t: ^Type) -> bool {
	if wave_payload_numeric(t) do return true
	elem, _ := type_gen_break(t)
	return elem != nil && type_is_boolean(elem)
}

check_wave_cluster_size :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc, arg: ^Expr) -> Operand {
	op := check_expr(checker, arg, type_hint = t_u32)
	if type_is_untyped(op.type) {
		coerce_untyped(&op, t_u32)
	}
	if !type_eq(default_type(op.type), t_u32) && !type_is_implicit_castable(op.type, t_u32) {
		check_err(checker, arg.pos, "builtin '%s' cluster size must be u32, got '%s'", builtin_names[id], string_from_type(op.type))
		op.mode = .Invalid
		return op
	}
	if op.mode != .Constant {
		check_err(checker, arg.pos, "builtin '%s' cluster size must be a compile-time constant", builtin_names[id])
		op.mode = .Invalid
		return op
	}
	val := exact_value_to_i128(op.value)
	if val < 1 || val > 128 || (val & (val - 1)) != 0 {
		check_err(checker, arg.pos, "builtin '%s' cluster size must be a power of two in 1..=128, got %v", builtin_names[id], val)
		op.mode = .Invalid
		return op
	}
	return op
}

check_wave_u32_arg :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc, arg: ^Expr, what: string) -> Operand {
	op := check_expr(checker, arg, type_hint = t_u32)
	if type_is_untyped(op.type) {
		coerce_untyped(&op, t_u32)
	}
	if !type_eq(default_type(op.type), t_u32) && !type_is_implicit_castable(op.type, t_u32) {
		check_err(checker, arg.pos, "builtin '%s' %s must be u32, got '%s'", builtin_names[id], what, string_from_type(op.type))
		op.mode = .Invalid
	}
	return op
}

check_wave_pred :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc, arg: ^Expr) -> Operand {
	op := check_expr(checker, arg)
	if type_is_untyped(op.type) {
		if type_is_boolean(op.type) {
			coerce_untyped(&op, t_b32)
		} else {
			got := default_type(op.type)
			check_err(checker, arg.pos, "builtin '%s' expects b32, got '%s'", builtin_names[id], string_from_type(got if got != nil else op.type))
			op.mode = .Invalid
			return op
		}
	}
	if !type_is_boolean(op.type) {
		check_err(checker, arg.pos, "builtin '%s' expects b32, got '%s'", builtin_names[id], string_from_type(op.type))
		op.mode = .Invalid
	}
	return op
}

check_wave_payload :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc, arg: ^Expr, numeric: bool, bits: bool) -> Operand {
	op := check_expr(checker, arg)
	if type_is_untyped(op.type) {
		if type_is_boolean(op.type) {
			coerce_untyped(&op, t_b32)
		} else if bits {
			coerce_untyped(&op, t_i32)
			default_untyped_int(&op)
		} else {
			default_untyped_float(&op)
			if type_is_untyped(op.type) {
				default_untyped_int(&op)
			}
		}
	}
	t := default_type(op.type)
	ok: bool
	if bits {
		ok = wave_payload_bits(t)
	} else if numeric {
		ok = wave_payload_numeric(t)
	} else {
		ok = wave_payload_any(t)
	}
	if !ok {
		want := "i32, u32, f32, or b32 (or a vector of those)"
		if bits {
			want = "i32 or u32 (or a vector of those)"
		} else if numeric {
			want = "i32, u32, or f32 (or a vector of those)"
		}
		check_err(checker, arg.pos, "builtin '%s' expects %s, got '%s'", builtin_names[id], want, string_from_type(op.type))
		op.mode = .Invalid
	}
	return op
}

check_wave_builtin :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	#partial switch id {
	case .wave_is_first:
		if !expect_argc(checker, call, id, 0) do return builtin_fail(checker, call)
		return builtin_value(call, id, t_b32)
	case .wave_lane_count, .wave_lane_id:
		if !expect_argc(checker, call, id, 0) do return builtin_fail(checker, call)
		return builtin_value(call, id, t_u32)
	case .wave_any, .wave_all, .wave_bit_count, .wave_prefix_bit_count:
		if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
		p := check_wave_pred(checker, call, id, call.args[0])
		if p.mode == .Invalid do return builtin_fail(checker, call)
		if id == .wave_bit_count || id == .wave_prefix_bit_count {
			return builtin_value(call, id, t_u32)
		}
		return builtin_value(call, id, t_b32)
	case .wave_ballot:
		if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
		p := check_wave_pred(checker, call, id, call.args[0])
		if p.mode == .Invalid do return builtin_fail(checker, call)
		return builtin_value(call, id, vec_type(t_u32, 4))
	case .wave_all_equal:
		if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
		x := check_wave_payload(checker, call, id, call.args[0], numeric = false, bits = false)
		if x.mode == .Invalid do return builtin_fail(checker, call)
		return builtin_value(call, id, bool_gen_from(default_type(x.type)))
	case .wave_broadcast_first, .wave_sum, .wave_product, .wave_min, .wave_max,
	     .wave_bit_and, .wave_bit_or, .wave_bit_xor,
	     .wave_prefix_sum, .wave_prefix_product,
	     .wave_quad_x, .wave_quad_y, .wave_quad_diag:
		if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
		bits := id == .wave_bit_and || id == .wave_bit_or || id == .wave_bit_xor
		numeric := id != .wave_broadcast_first && id != .wave_quad_x && id != .wave_quad_y && id != .wave_quad_diag
		if bits {
			numeric = false
		}
		x := check_wave_payload(checker, call, id, call.args[0], numeric = numeric, bits = bits)
		if x.mode == .Invalid do return builtin_fail(checker, call)
		return builtin_value(call, id, default_type(x.type))
	case .wave_read, .wave_shuffle_xor, .wave_shuffle_up, .wave_shuffle_down, .wave_rotate, .wave_quad_read:
		if !expect_argc(checker, call, id, 2) do return builtin_fail(checker, call)
		x := check_wave_payload(checker, call, id, call.args[0], numeric = false, bits = false)
		what := "lane"
		#partial switch id {
		case .wave_shuffle_xor: what = "mask"
		case .wave_shuffle_up, .wave_shuffle_down, .wave_rotate: what = "delta"
		case .wave_quad_read: what = "lane"
		}
		lane := check_wave_u32_arg(checker, call, id, call.args[1], what)
		if x.mode == .Invalid || lane.mode == .Invalid do return builtin_fail(checker, call)
		return builtin_value(call, id, default_type(x.type))
	case .wave_clustered_sum, .wave_clustered_product, .wave_clustered_min, .wave_clustered_max,
	     .wave_clustered_bit_and, .wave_clustered_bit_or, .wave_clustered_bit_xor:
		if !expect_argc(checker, call, id, 2) do return builtin_fail(checker, call)
		bits := id == .wave_clustered_bit_and || id == .wave_clustered_bit_or || id == .wave_clustered_bit_xor
		x := check_wave_payload(checker, call, id, call.args[0], numeric = !bits, bits = bits)
		c := check_wave_cluster_size(checker, call, id, call.args[1])
		if x.mode == .Invalid || c.mode == .Invalid do return builtin_fail(checker, call)
		return builtin_value(call, id, default_type(x.type))
	case .wave_clustered_rotate:
		if !expect_argc(checker, call, id, 3) do return builtin_fail(checker, call)
		x := check_wave_payload(checker, call, id, call.args[0], numeric = false, bits = false)
		d := check_wave_u32_arg(checker, call, id, call.args[1], "delta")
		c := check_wave_cluster_size(checker, call, id, call.args[2])
		if x.mode == .Invalid || d.mode == .Invalid || c.mode == .Invalid do return builtin_fail(checker, call)
		return builtin_value(call, id, default_type(x.type))
	}
	check_err(checker, call.pos, "unhandled builtin '%s'", builtin_names[id])
	return builtin_fail(checker, call)
}

spv_wave_scope :: proc(cg: ^Spv_CG) -> spv.Id {
	return spv.const_u32(&cg.m, u32(spv.Scope.Subgroup))
}

spv_wave_load_builtin :: proc(cg: ^Spv_CG, builtin: spv.Built_In, name: string) -> spv.Id {
	spv.require_cap(&cg.m, .GroupNonUniform)
	slot: ^spv.Id
	if builtin == .SubgroupSize {
		slot = &cg.subgroup_size
	} else {
		slot = &cg.subgroup_lane
	}
	if slot^ == 0 {
		slot^ = spv_builtin_var(cg, builtin, spv.type_u32(&cg.m), name)
	}
	return spv.load(&cg.m, spv.type_u32(&cg.m), slot^)
}

spv_wave_arith_op :: proc(id: Builtin_Proc, t: ^Type) -> spv.Op {
	flt := type_is_float(type_base(t))
	uns := spv_unsigned(t)
	#partial switch id {
	case .wave_sum, .wave_prefix_sum, .wave_clustered_sum:
		return .GroupNonUniformFAdd if flt else .GroupNonUniformIAdd
	case .wave_product, .wave_prefix_product, .wave_clustered_product:
		return .GroupNonUniformFMul if flt else .GroupNonUniformIMul
	case .wave_min, .wave_clustered_min:
		if flt do return .GroupNonUniformFMin
		return .GroupNonUniformUMin if uns else .GroupNonUniformSMin
	case .wave_max, .wave_clustered_max:
		if flt do return .GroupNonUniformFMax
		return .GroupNonUniformUMax if uns else .GroupNonUniformSMax
	case .wave_bit_and, .wave_clustered_bit_and:
		return .GroupNonUniformBitwiseAnd
	case .wave_bit_or, .wave_clustered_bit_or:
		return .GroupNonUniformBitwiseOr
	case .wave_bit_xor, .wave_clustered_bit_xor:
		return .GroupNonUniformBitwiseXor
	}
	return .GroupNonUniformIAdd
}

spv_wave_group_op :: proc(id: Builtin_Proc) -> spv.Group_Operation {
	#partial switch id {
	case .wave_prefix_sum, .wave_prefix_product, .wave_prefix_bit_count:
		return .ExclusiveScan
	case .wave_clustered_sum, .wave_clustered_product, .wave_clustered_min, .wave_clustered_max,
	     .wave_clustered_bit_and, .wave_clustered_bit_or, .wave_clustered_bit_xor:
		return .ClusteredReduce
	}
	return .Reduce
}

spv_wave_rvalue :: proc(cg: ^Spv_CG, id: Builtin_Proc, call: ^Call_Expr) -> spv.Id {
	res_t := default_type(call.tav.type)
	ty := spv_type(cg, res_t)
	scope := spv_wave_scope(cg)
	#partial switch id {
	case .wave_lane_count:
		return spv_wave_load_builtin(cg, .SubgroupSize, "gl_SubgroupSize")
	case .wave_lane_id:
		return spv_wave_load_builtin(cg, .SubgroupLocalInvocationId, "gl_SubgroupInvocationID")
	case .wave_is_first:
		b := spv.group_non_uniform_elect(&cg.m, spv.type_bool(&cg.m), scope)
		return spv_from_bool(cg, b, res_t)
	case .wave_any, .wave_all:
		pred := spv_as_bool(cg, spv_rvalue(cg, call.args[0]), call.args[0].tav.type)
		b: spv.Id
		if id == .wave_any {
			b = spv.group_non_uniform_any(&cg.m, spv.type_bool(&cg.m), scope, pred)
		} else {
			b = spv.group_non_uniform_all(&cg.m, spv.type_bool(&cg.m), scope, pred)
		}
		return spv_from_bool(cg, b, res_t)
	case .wave_ballot:
		pred := spv_as_bool(cg, spv_rvalue(cg, call.args[0]), call.args[0].tav.type)
		return spv.group_non_uniform_ballot(&cg.m, ty, scope, pred)
	case .wave_all_equal:
		v := spv_rvalue(cg, call.args[0])
		bty := spv_bool_type(cg, res_t)
		b := spv.group_non_uniform_all_equal(&cg.m, bty, scope, v)
		return spv_from_bool(cg, b, res_t)
	case .wave_bit_count, .wave_prefix_bit_count:
		pred := spv_as_bool(cg, spv_rvalue(cg, call.args[0]), call.args[0].tav.type)
		uvec4 := spv.type_vector(&cg.m, spv.type_u32(&cg.m), 4)
		bits := spv.group_non_uniform_ballot(&cg.m, uvec4, scope, pred)
		gop := spv_wave_group_op(id)
		return spv.group_non_uniform_ballot_bit_count(&cg.m, ty, scope, gop, bits)
	case .wave_broadcast_first:
		v := spv_rvalue(cg, call.args[0])
		return spv.group_non_uniform_broadcast_first(&cg.m, ty, scope, v)
	case .wave_read:
		v := spv_rvalue(cg, call.args[0])
		lane := spv_u32(cg, spv_rvalue(cg, call.args[1]), call.args[1].tav.type)
		return spv.group_non_uniform_shuffle(&cg.m, ty, scope, v, lane)
	case .wave_shuffle_xor:
		v := spv_rvalue(cg, call.args[0])
		mask := spv_u32(cg, spv_rvalue(cg, call.args[1]), call.args[1].tav.type)
		return spv.group_non_uniform_shuffle_xor(&cg.m, ty, scope, v, mask)
	case .wave_shuffle_up:
		v := spv_rvalue(cg, call.args[0])
		delta := spv_u32(cg, spv_rvalue(cg, call.args[1]), call.args[1].tav.type)
		return spv.group_non_uniform_shuffle_up(&cg.m, ty, scope, v, delta)
	case .wave_shuffle_down:
		v := spv_rvalue(cg, call.args[0])
		delta := spv_u32(cg, spv_rvalue(cg, call.args[1]), call.args[1].tav.type)
		return spv.group_non_uniform_shuffle_down(&cg.m, ty, scope, v, delta)
	case .wave_quad_x, .wave_quad_y, .wave_quad_diag:
		v := spv_rvalue(cg, call.args[0])
		dir: u32 = 0
		if id == .wave_quad_y do dir = 1
		if id == .wave_quad_diag do dir = 2
		return spv.group_non_uniform_quad_swap(&cg.m, ty, scope, v, spv.const_u32(&cg.m, dir))
	case .wave_quad_read:
		v := spv_rvalue(cg, call.args[0])
		lane := spv_u32(cg, spv_rvalue(cg, call.args[1]), call.args[1].tav.type)
		return spv.group_non_uniform_quad_broadcast(&cg.m, ty, scope, v, lane)
	case .wave_rotate:
		v := spv_rvalue(cg, call.args[0])
		delta := spv_u32(cg, spv_rvalue(cg, call.args[1]), call.args[1].tav.type)
		return spv.group_non_uniform_rotate(&cg.m, ty, scope, v, delta)
	case .wave_clustered_rotate:
		v := spv_rvalue(cg, call.args[0])
		delta := spv_u32(cg, spv_rvalue(cg, call.args[1]), call.args[1].tav.type)
		cluster := spv_u32(cg, spv_rvalue(cg, call.args[2]), call.args[2].tav.type)
		return spv.group_non_uniform_rotate(&cg.m, ty, scope, v, delta, cluster)
	case .wave_sum, .wave_product, .wave_min, .wave_max,
	     .wave_bit_and, .wave_bit_or, .wave_bit_xor,
	     .wave_prefix_sum, .wave_prefix_product,
	     .wave_clustered_sum, .wave_clustered_product, .wave_clustered_min, .wave_clustered_max,
	     .wave_clustered_bit_and, .wave_clustered_bit_or, .wave_clustered_bit_xor:
		v := spv_rvalue(cg, call.args[0])
		op := spv_wave_arith_op(id, default_type(call.args[0].tav.type))
		gop := spv_wave_group_op(id)
		cluster: spv.Id
		if gop == .ClusteredReduce {
			cluster = spv_u32(cg, spv_rvalue(cg, call.args[1]), call.args[1].tav.type)
		}
		return spv.group_non_uniform_arith(&cg.m, op, ty, scope, gop, v, cluster)
	}
	spv_err(cg, call.pos, "codegen_spirv: unimplemented wave builtin %v", id)
	return spv_zero(cg, res_t)
}

scan_wave_glsl_exts :: proc(modules: []^Module) -> Wave_Glsl_Exts {
	exts: Wave_Glsl_Exts
	for m in modules {
		if m == nil do continue
		for e in m.definitions {
			if e == nil || e.proc_lit == nil do continue
			#partial switch e.kind {
			case .Procedure, .Entry:
				scan_stmt_wave_exts(e.proc_lit.body, &exts)
			}
		}
	}
	return exts
}

scan_stmt_wave_exts :: proc(stmt: ^Stmt, exts: ^Wave_Glsl_Exts) {
	if stmt == nil do return
	#partial switch v in stmt.derived_stmt {
	case ^Expr_Stmt:
		scan_expr_wave_exts(v.expr, exts)
	case ^Assign_Stmt:
		for e in v.lhs do scan_expr_wave_exts(e, exts)
		for e in v.rhs do scan_expr_wave_exts(e, exts)
	case ^Value_Decl:
		for e in v.values do scan_expr_wave_exts(e, exts)
	case ^Block_Stmt:
		for s in v.stmts do scan_stmt_wave_exts(s, exts)
	case ^If_Stmt:
		scan_stmt_wave_exts(v.init, exts)
		scan_expr_wave_exts(v.cond, exts)
		scan_stmt_wave_exts(v.body, exts)
		scan_stmt_wave_exts(v.else_stmt, exts)
	case ^For_Stmt:
		scan_stmt_wave_exts(v.init, exts)
		scan_expr_wave_exts(v.cond, exts)
		scan_stmt_wave_exts(v.post, exts)
		scan_stmt_wave_exts(v.body, exts)
	case ^Range_Stmt:
		scan_expr_wave_exts(v.expr, exts)
		scan_stmt_wave_exts(v.body, exts)
	case ^Return_Stmt:
		for r in v.results do scan_expr_wave_exts(r, exts)
	case ^Switch_Stmt:
		scan_stmt_wave_exts(v.init, exts)
		scan_expr_wave_exts(v.cond, exts)
		scan_stmt_wave_exts(v.body, exts)
	case ^Case_Clause:
		for e in v.list do scan_expr_wave_exts(e, exts)
		for s in v.body do scan_stmt_wave_exts(s, exts)
	case ^When_Stmt:
		scan_stmt_wave_exts(v.body, exts)
		scan_stmt_wave_exts(v.else_stmt, exts)
	case ^Which_Stmt:
		scan_stmt_wave_exts(v.body, exts)
	}
}

scan_expr_wave_exts :: proc(expr: ^Expr, exts: ^Wave_Glsl_Exts) {
	if expr == nil do return
	#partial switch v in expr.derived_expr {
	case ^Call_Expr:
		if callee := entity_from_expr(v.expr); callee != nil && callee.kind == .Builtin {
			exts^ += builtin_wave_glsl_exts(callee.builtin_id)
		}
		scan_expr_wave_exts(v.expr, exts)
		for a in v.args do scan_expr_wave_exts(a, exts)
	case ^Selector_Expr:
		scan_expr_wave_exts(v.expr, exts)
		scan_expr_wave_exts(v.field, exts)
	case ^Selector_Call_Expr:
		scan_expr_wave_exts(v.expr, exts)
		if v.call != nil do scan_expr_wave_exts(v.call, exts)
	case ^Index_Expr:
		scan_expr_wave_exts(v.expr, exts)
		scan_expr_wave_exts(v.index, exts)
	case ^Deref_Expr:
		scan_expr_wave_exts(v.expr, exts)
	case ^Paren_Expr:
		scan_expr_wave_exts(v.expr, exts)
	case ^Unary_Expr:
		scan_expr_wave_exts(v.expr, exts)
	case ^Auto_Cast:
		scan_expr_wave_exts(v.expr, exts)
	case ^Tag_Expr:
		scan_expr_wave_exts(v.expr, exts)
	case ^Binary_Expr:
		scan_expr_wave_exts(v.left, exts)
		scan_expr_wave_exts(v.right, exts)
	case ^Ternary_If_Expr:
		scan_expr_wave_exts(v.cond, exts)
		scan_expr_wave_exts(v.x, exts)
		scan_expr_wave_exts(v.y, exts)
	}
}
