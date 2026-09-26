package misl

import "core:fmt"
import "core:strings"

Builtin_Proc :: enum {
	Invalid,

	// trig
	radians,
	degrees,
	sin,
	cos,
	tan,
	asin,
	acos,
	atan,
	atan2,
	sinh,
	cosh,
	tanh,
	asinh,
	acosh,
	atanh,

	// math
	pow,
	exp,
	log,
	exp2,
	log2,
	sqrt,
	isqrt, // inverse sqrt → GLSL inversesqrt
	abs,
	sign,
	floor,
	trunc,
	round,
	round_even,
	ceil,
	fract,
	mod,
	modf,
	min,
	max,
	clamp,
	lerp, // mix in glsl
	step,
	smoothstep,
	is_nan,
	is_inf,
	f32_from_u32_bits,
	u32_from_f32_bits,
	fma,
	frexp,
	ldexp,

	// Geom
	mag, // length
	dist,
	dot,
	cross,
	normalize,
	facefoward, // spelling kept; emits faceforward
	reflect,
	refract,

	// matrix
	matrix_comp_mult,
	outer_product,
	transpose,
	determinant,
	inverse,

	// textures
	sample,
	load,
	store,
	dim,

	// ray query
	rayquery_init,
	rayquery_proceed,
	rayquery_result,
	rayquery_candidate,
	rayquery_accept,

	// fragment derivatives
	dFdx,
	dFdy,
	fwidth,

	// bit_set
	card,

	// slice
	len,

	// debug (core:debug only — not ambient)
	printf,
	printfln,
	assert,
	panic,

	// FMAG interpreter (core:fmag only — not ambient)
	fmag_exec,

	// compute sync (snake_case MISL → camelCase GLSL)
	barrier,
	memory_barrier,
	memory_barrier_shared,
	memory_barrier_buffer,
	memory_barrier_image,
	group_memory_barrier,

	// wave / subgroup (core:wave only — not ambient)
	wave_is_first,
	wave_lane_count,
	wave_lane_id,
	wave_any,
	wave_all,
	wave_ballot,
	wave_broadcast_first,
	wave_read,
	wave_all_equal,
	wave_bit_count,
	wave_sum,
	wave_product,
	wave_min,
	wave_max,
	wave_bit_and,
	wave_bit_or,
	wave_bit_xor,
	wave_prefix_sum,
	wave_prefix_product,
	wave_prefix_bit_count,
	wave_quad_x,
	wave_quad_y,
	wave_quad_diag,
	wave_quad_read,
	wave_shuffle_xor,
	wave_shuffle_up,
	wave_shuffle_down,
	wave_clustered_sum,
	wave_clustered_product,
	wave_clustered_min,
	wave_clustered_max,
	wave_clustered_bit_and,
	wave_clustered_bit_or,
	wave_clustered_bit_xor,
	wave_rotate,
	wave_clustered_rotate,
}

@(rodata)
builtin_names := [Builtin_Proc]string {
	.Invalid          = "Invalid",
	.radians          = "radians",
	.degrees          = "degrees",
	.sin              = "sin",
	.cos              = "cos",
	.tan              = "tan",
	.asin             = "asin",
	.acos             = "acos",
	.atan             = "atan",
	.atan2            = "atan2",
	.sinh             = "sinh",
	.cosh             = "cosh",
	.tanh             = "tanh",
	.asinh            = "asinh",
	.acosh            = "acosh",
	.atanh            = "atanh",
	.pow              = "pow",
	.exp              = "exp",
	.log              = "log",
	.exp2             = "exp2",
	.log2             = "log2",
	.sqrt             = "sqrt",
	.isqrt            = "isqrt",
	.abs              = "abs",
	.sign             = "sign",
	.floor            = "floor",
	.trunc            = "trunc",
	.round            = "round",
	.round_even       = "round_even",
	.ceil             = "ceil",
	.fract            = "fract",
	.mod              = "mod",
	.modf             = "modf",
	.min              = "min",
	.max              = "max",
	.clamp            = "clamp",
	.lerp             = "lerp",
	.step             = "step",
	.smoothstep       = "smoothstep",
	.is_nan              = "is_nan",
	.is_inf              = "is_inf",
	.f32_from_u32_bits   = "f32_from_u32_bits",
	.u32_from_f32_bits   = "u32_from_f32_bits",
	.fma                 = "fma",
	.frexp            = "frexp",
	.ldexp            = "ldexp",
	.mag              = "mag",
	.dist             = "dist",
	.dot              = "dot",
	.cross            = "cross",
	.normalize        = "normalize",
	.facefoward       = "facefoward",
	.reflect          = "reflect",
	.refract          = "refract",
	.matrix_comp_mult = "matrix_comp_mult",
	.outer_product    = "outer_product",
	.transpose        = "transpose",
	.determinant      = "determinant",
	.inverse          = "inverse",
	.sample           = "sample",
	.load             = "load",
	.store            = "store",
	.rayquery_init      = "rayquery_init",
	.rayquery_proceed   = "rayquery_proceed",
	.rayquery_result    = "rayquery_result",
	.rayquery_candidate = "rayquery_candidate",
	.rayquery_accept    = "rayquery_accept",
	.dFdx             = "dFdx",
	.dFdy             = "dFdy",
	.fwidth           = "fwidth",
	.printf           = "printf",
	.printfln         = "printfln",
	.assert           = "assert",
	.panic            = "panic",
	.fmag_exec        = "exec",
	.dim              = "dim",
	.card             = "card",
	.len              = "len",
	.barrier                 = "barrier",
	.memory_barrier          = "memory_barrier",
	.memory_barrier_shared   = "memory_barrier_shared",
	.memory_barrier_buffer   = "memory_barrier_buffer",
	.memory_barrier_image    = "memory_barrier_image",
	.group_memory_barrier    = "group_memory_barrier",
	.wave_is_first           = "is_first",
	.wave_lane_count         = "lane_count",
	.wave_lane_id            = "lane_id",
	.wave_any                = "any",
	.wave_all                = "all",
	.wave_ballot             = "ballot",
	.wave_broadcast_first    = "broadcast_first",
	.wave_read               = "read",
	.wave_all_equal          = "all_equal",
	.wave_bit_count          = "bit_count",
	.wave_sum                = "sum",
	.wave_product            = "product",
	.wave_min                = "min",
	.wave_max                = "max",
	.wave_bit_and            = "bit_and",
	.wave_bit_or             = "bit_or",
	.wave_bit_xor            = "bit_xor",
	.wave_prefix_sum         = "prefix_sum",
	.wave_prefix_product     = "prefix_product",
	.wave_prefix_bit_count   = "prefix_bit_count",
	.wave_quad_x             = "quad_x",
	.wave_quad_y             = "quad_y",
	.wave_quad_diag          = "quad_diag",
	.wave_quad_read          = "quad_read",
	.wave_shuffle_xor        = "shuffle_xor",
	.wave_shuffle_up         = "shuffle_up",
	.wave_shuffle_down       = "shuffle_down",
	.wave_clustered_sum      = "clustered_sum",
	.wave_clustered_product  = "clustered_product",
	.wave_clustered_min      = "clustered_min",
	.wave_clustered_max      = "clustered_max",
	.wave_clustered_bit_and  = "clustered_bit_and",
	.wave_clustered_bit_or   = "clustered_bit_or",
	.wave_clustered_bit_xor  = "clustered_bit_xor",
	.wave_rotate             = "rotate",
	.wave_clustered_rotate   = "clustered_rotate",
}

builtin_injected_by_compiler :: proc(id: Builtin_Proc) -> bool {
	#partial switch id {
	case .abs, .min, .max, .clamp, .lerp, .fma, .dot,
	     .radians, .degrees, .sin, .cos, .tan, .asin, .acos, .atan, .atan2,
	     .pow, .exp, .log, .exp2, .log2, .sqrt, .isqrt, .sign,
	     .floor, .trunc, .round, .round_even, .ceil, .fract,
	     .step, .smoothstep, .frexp, .mag,
	     .printf, .printfln, .assert, .panic, .fmag_exec,
	     .sample, .load, .store, .dim, .dFdx, .dFdy, .fwidth,
	     .rayquery_init, .rayquery_proceed, .rayquery_result,
	     .rayquery_candidate, .rayquery_accept,
	     .barrier, .memory_barrier, .memory_barrier_shared,
	     .memory_barrier_buffer, .memory_barrier_image, .group_memory_barrier:
		return false
	}
	if builtin_is_wave(id) {
		return false
	}
	return id != .Invalid
}

builtin_stage_flags :: proc(id: Builtin_Proc) -> Builtin_Stages {
	#partial switch id {
	case .dFdx, .dFdy, .fwidth:
		return {.Fragment}
	case .barrier, .memory_barrier, .memory_barrier_shared,
	     .memory_barrier_buffer, .memory_barrier_image, .group_memory_barrier:
		return {.Compute}
	case .wave_quad_x, .wave_quad_y, .wave_quad_diag, .wave_quad_read:
		return {.Fragment, .Compute}
	}
	return {}
}

// GPU resources, derivatives, compute sync, and matrix builtins are illegal in `proc "fmag"`.
builtin_ok_in_fmag :: proc(id: Builtin_Proc) -> bool {
	if builtin_is_wave(id) {
		return false
	}
	#partial switch id {
	case .sample, .load, .store, .dim, .dFdx, .dFdy, .fwidth,
	     .rayquery_init, .rayquery_proceed, .rayquery_result,
	     .rayquery_candidate, .rayquery_accept,
	     .barrier, .memory_barrier, .memory_barrier_shared,
	     .memory_barrier_buffer, .memory_barrier_image, .group_memory_barrier,
	     .matrix_comp_mult, .outer_product, .transpose, .determinant, .inverse,
	     .card, .printf, .printfln, .assert, .panic, .fmag_exec:
		return false
	}
	return true
}

// GLSL callee name for a builtin (ident emit / call lowering).
builtin_glsl_name :: proc(id: Builtin_Proc) -> string {
	#partial switch id {
	case .mag:              return "length"
	case .dist:             return "distance"
	case .lerp:             return "mix"
	case .isqrt:            return "inversesqrt"
	case .round_even:       return "roundEven"
	case .atan2:            return "atan"
	case .is_nan:              return "isnan"
	case .is_inf:              return "isinf"
	case .f32_from_u32_bits:   return "uintBitsToFloat"
	case .u32_from_f32_bits:   return "floatBitsToUint"
	case .facefoward:       return "faceforward"
	case .matrix_comp_mult: return "matrixCompMult"
	case .outer_product:    return "outerProduct"
	case .sample:           return "misl_sample_texture"
	case .dim:              return "misl_texture_size"
	case .dFdx:             return "dFdx"
	case .dFdy:             return "dFdy"
	case .fwidth:           return "fwidth"
	case .card:             return "bitCount"
	case .printf, .printfln: return "debugPrintfEXT"
	case .assert, .panic, .fmag_exec: return ""
	case .memory_barrier:        return "memoryBarrier"
	case .memory_barrier_shared: return "memoryBarrierShared"
	case .memory_barrier_buffer: return "memoryBarrierBuffer"
	case .memory_barrier_image:  return "memoryBarrierImage"
	case .group_memory_barrier:  return "groupMemoryBarrier"
	case .wave_sum: return "subgroupAdd"
	case .wave_product: return "subgroupMul"
	case .wave_min: return "subgroupMin"
	case .wave_max: return "subgroupMax"
	case .wave_bit_and: return "subgroupAnd"
	case .wave_bit_or: return "subgroupOr"
	case .wave_bit_xor: return "subgroupXor"
	case .wave_prefix_sum: return "subgroupExclusiveAdd"
	case .wave_prefix_product: return "subgroupExclusiveMul"
	case .wave_clustered_sum: return "subgroupClusteredAdd"
	case .wave_clustered_product: return "subgroupClusteredMul"
	case .wave_clustered_min: return "subgroupClusteredMin"
	case .wave_clustered_max: return "subgroupClusteredMax"
	case .wave_clustered_bit_and: return "subgroupClusteredAnd"
	case .wave_clustered_bit_or: return "subgroupClusteredOr"
	case .wave_clustered_bit_xor: return "subgroupClusteredXor"
	}
	return builtin_names[id]
}

// Stable compiler keys for `#intrinsic("…")`. The MISL decl name is independent.
intrinsic_key_to_builtin :: proc(key: string) -> (Builtin_Proc, bool) {
	switch key {
	case "spirv.abs":
		return .abs, true
	case "spirv.dFdx":
		return .dFdx, true
	case "spirv.dFdy":
		return .dFdy, true
	case "spirv.fwidth":
		return .fwidth, true
	case "builtin.sample":
		return .sample, true
	case "builtin.load":
		return .load, true
	case "builtin.store":
		return .store, true
	case "builtin.dim":
		return .dim, true
	case "builtin.rayquery_init":
		return .rayquery_init, true
	case "builtin.rayquery_proceed":
		return .rayquery_proceed, true
	case "builtin.rayquery_result":
		return .rayquery_result, true
	case "builtin.rayquery_candidate":
		return .rayquery_candidate, true
	case "builtin.rayquery_accept":
		return .rayquery_accept, true
	case "spirv.barrier":
		return .barrier, true
	case "spirv.memory_barrier":
		return .memory_barrier, true
	case "spirv.memory_barrier_shared":
		return .memory_barrier_shared, true
	case "spirv.memory_barrier_buffer":
		return .memory_barrier_buffer, true
	case "spirv.memory_barrier_image":
		return .memory_barrier_image, true
	case "spirv.group_memory_barrier":
		return .group_memory_barrier, true
	case "debug.printf":
		return .printf, true
	case "debug.printfln":
		return .printfln, true
	case "debug.assert":
		return .assert, true
	case "debug.panic":
		return .panic, true
	case "fmag.exec":
		return .fmag_exec, true
	}
	if strings.has_prefix(key, "wave.") {
		rest := key[len("wave."):]
		for id in Builtin_Proc {
			if builtin_is_wave(id) && builtin_names[id] == rest {
				return id, true
			}
		}
	}
	if strings.has_prefix(key, "spirv.") {
		rest := key[len("spirv."):]
		switch rest {
		case "mix":
			return .lerp, true
		case "inversesqrt":
			return .isqrt, true
		case "roundEven":
			return .round_even, true
		case "length":
			return .mag, true
		}
		for id in Builtin_Proc {
			if id != .Invalid && builtin_names[id] == rest {
				return id, true
			}
		}
	}
	return .Invalid, false
}

intrinsic_key_to_type :: proc(key: string) -> (^Type, bool) {
	prefix := "builtin."
	if !strings.has_prefix(key, prefix) {
		return nil, false
	}
	name := key[len(prefix):]
	switch name {
	case "ray_query":
		return t_ray_query, true
	case "t8_2d":
		return t_t8_2d, true
	case "t16_2d":
		return t_t16_2d, true
	case "t32_2d":
		return t_t32_2d, true
	case "rw8_2d":
		return t_rw8_2d, true
	case "rw16_2d":
		return t_rw16_2d, true
	case "rw32_2d":
		return t_rw32_2d, true
	}
	for kind in Scalar_Kind {
		t := scalar_types[kind]
		if t == nil do continue
		if !type_is_resource_id(t) do continue
		if t.derived.(^Type_Scalar).name == name {
			return t, true
		}
	}
	return nil, false
}

@(private)
vec_type :: proc(elem: ^Type, n: int) -> ^Type {
	if n <= 1 do return elem
	t := new_type(Type_Vector)
	t.elem = elem
	t.len = n
	return t
}

@(private)
bool_gen_from :: proc(t: ^Type) -> ^Type {
	_, n := type_gen_break(t)
	return vec_type(t_b32, n)
}

@(private)
int_gen_from :: proc(t: ^Type) -> ^Type {
	_, n := type_gen_break(t)
	return vec_type(t_i32, n)
}

@(private)
builtin_fail :: proc(checker: ^Checker, call: ^Call_Expr) -> Operand {
	return Operand{expr = call, type = t_invalid, mode = .Invalid, builtin_id = .Invalid}
}

@(private)
builtin_value :: proc(call: ^Call_Expr, id: Builtin_Proc, type: ^Type) -> Operand {
	return Operand{expr = call, type = type, mode = .Value, builtin_id = id, is_call = true}
}

@(private)
builtin_no_value :: proc(call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	return Operand{expr = call, type = t_invalid, mode = .No_Value, builtin_id = id, is_call = true}
}

@(private)
expect_argc :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc, n: int) -> bool {
	if len(call.args) == n do return true
	check_err(checker, call.pos, "builtin '%s' expects %d argument%s, got %d", builtin_names[id], n, "" if n == 1 else "s", len(call.args))
	return false
}

// Coerce untyped operand into `ctx` (vector or scalar) when allowed.
@(private)
coerce_untyped :: proc(op: ^Operand, ctx: ^Type) {
	if op == nil || ctx == nil do return
	if type_is_untyped(op.type) {
		resolve_operand_type(op, ctx)
	}
}

// Default remaining untyped to f32 / i32 scalar (or keep vector shape if somehow typed).
@(private)
default_untyped_float :: proc(op: ^Operand) {
	if type_is_untyped(op.type) {
		resolve_operand_type(op, t_f32)
		if type_is_untyped(op.type) {
			op.type = t_f32
			if op.expr != nil do op.expr.tav.type = t_f32
		}
	}
}

@(private)
default_untyped_int :: proc(op: ^Operand) {
	if type_is_untyped(op.type) {
		resolve_operand_type(op, t_i32)
		if type_is_untyped(op.type) {
			op.type = t_i32
			if op.expr != nil do op.expr.tav.type = t_i32
		}
	}
}

@(private)
is_gen_float :: proc(t: ^Type) -> bool {
	return type_is_gen(t, t_f32) || type_is_gen(t, t_f64)
}

@(private)
is_gen_numeric :: proc(t: ^Type) -> bool {
	elem, _ := type_gen_break(t)
	if elem == nil do return false
	return type_is_numeric(elem) || type_is_untyped(elem)
}

@(private)
gen_len :: proc(t: ^Type) -> int {
	_, n := type_gen_break(t)
	return n
}

// Pick the widest typed gen float among ops (prefer vectors over scalars).
@(private)
pick_gen_float_result :: proc(ops: []Operand) -> ^Type {
	best: ^Type
	best_n := 0
	for op in ops {
		if type_is_untyped(op.type) || !is_gen_float(op.type) do continue
		n := gen_len(op.type)
		if best == nil || n > best_n {
			best = op.type
			best_n = n
		}
	}
	return best
}

@(private)
pick_gen_numeric_result :: proc(ops: []Operand) -> ^Type {
	best: ^Type
	best_n := 0
	for op in ops {
		if type_is_untyped(op.type) || !is_gen_numeric(op.type) do continue
		n := gen_len(op.type)
		if best == nil || n > best_n {
			best = op.type
			best_n = n
		}
	}
	return best
}

// True if t is result, or (when allow_scalar) the scalar element of a vector result.
@(private)
matches_gen_or_scalar :: proc(t, result: ^Type, allow_scalar: bool) -> bool {
	if type_eq(t, result) do return true
	if !allow_scalar do return false
	elem, n := type_gen_break(result)
	return n > 1 && type_eq(t, elem)
}

// Unify args to a common gen float type.
// allow_scalar: GLSL broadcast — scalar elem may mix with a vector result type.
// untyped_as_scalar: when result is a vector, leave untyped args as the scalar elem (not splat).
@(private)
unify_gen_float :: proc(
	checker: ^Checker,
	call: ^Call_Expr,
	id: Builtin_Proc,
	ops: []Operand,
	allow_scalar := false,
	untyped_as_scalar := false,
) -> (result: ^Type, ok: bool) {
	for op in ops {
		if !type_is_untyped(op.type) && !is_gen_float(op.type) {
			check_err(checker, call.pos, "builtin '%s' expects floating genType arguments, got '%s'", builtin_names[id], string_from_type(op.type))
			return nil, false
		}
	}

	result = pick_gen_float_result(ops)
	if result == nil do result = t_f32

	elem, result_n := type_gen_break(result)
	for &op in ops {
		if type_is_untyped(op.type) {
			target := result
			if allow_scalar && untyped_as_scalar && result_n > 1 {
				target = elem
			}
			coerce_untyped(&op, target)
			default_untyped_float(&op)
			// If we preferred scalar but still mismatched somehow, fall back to result
			if !matches_gen_or_scalar(op.type, result, allow_scalar) {
				coerce_untyped(&op, result)
				default_untyped_float(&op)
			}
		}
		if !matches_gen_or_scalar(op.type, result, allow_scalar) {
			check_err(checker, call.pos, "builtin '%s' argument type mismatch (%s vs %s)", builtin_names[id], string_from_type(result), string_from_type(op.type))
			return nil, false
		}
	}
	return result, true
}

@(private)
unify_gen_numeric :: proc(
	checker: ^Checker,
	call: ^Call_Expr,
	id: Builtin_Proc,
	ops: []Operand,
	allow_scalar := false,
	untyped_as_scalar := false,
) -> (result: ^Type, ok: bool) {
	for op in ops {
		if !type_is_untyped(op.type) && !is_gen_numeric(op.type) {
			check_err(checker, call.pos, "builtin '%s' expects numeric arguments, got '%s'", builtin_names[id], string_from_type(op.type))
			return nil, false
		}
	}

	result = pick_gen_numeric_result(ops)
	if result == nil {
		want_float := false
		for op in ops {
			if s, sok := op.type.derived.(^Type_Scalar); sok && .Float in s.flags {
				want_float = true
				break
			}
		}
		result = t_f32 if want_float else t_i32
	}

	elem, result_n := type_gen_break(result)
	elem_is_float := type_is_float(type_base(result))
	for &op in ops {
		if type_is_untyped(op.type) {
			target := result
			if allow_scalar && untyped_as_scalar && result_n > 1 {
				target = elem
			}
			coerce_untyped(&op, target)
			if type_is_untyped(op.type) {
				if elem_is_float do default_untyped_float(&op)
				else do default_untyped_int(&op)
			}
			if !matches_gen_or_scalar(op.type, result, allow_scalar) {
				coerce_untyped(&op, result)
				if type_is_untyped(op.type) {
					if elem_is_float do default_untyped_float(&op)
					else do default_untyped_int(&op)
				}
			}
		}
		if !matches_gen_or_scalar(op.type, result, allow_scalar) {
			check_err(checker, call.pos, "builtin '%s' argument type mismatch (%s vs %s)", builtin_names[id], string_from_type(result), string_from_type(op.type))
			return nil, false
		}
	}
	return result, true
}

@(private)
check_args :: proc(checker: ^Checker, call: ^Call_Expr, hints: []^Type) -> []Operand {
	ops := make([]Operand, len(call.args), context.temp_allocator)
	for arg, i in call.args {
		// Soft gen hints (t_f32 / t_i32) must not freeze untyped args before
		// unify_gen_* — that would block vector splat coercion (e.g. pow(v, 2.2)).
		// Definitive contexts pass a real hint via check_expr directly.
		_ = hints
		_ = i
		ops[i] = check_expr(checker, arg)
	}
	return ops
}

@(private)
make_results_tuple :: proc(types: []^Type) -> ^Type {
	tuple := new_type(Type_Tuple)
	for t in types {
		e := new_entity(.Variable, nil, {}, "", t)
		append(&tuple.variables, e)
	}
	return tuple
}

// --- resource helpers (Phase 2) ---

check_resource_arg :: proc(checker: ^Checker, expr: ^Expr, hint: ^Type) -> Operand {
	o := check_expr(checker, expr, type_hint = hint)
	if type_is_untyped(o.type) && hint != nil && type_is_implicit_castable(o.type, hint) {
		o.type = hint
		expr.tav.type = hint
	}
	return o
}

@(private)
coord_type_f32 :: proc(n: int) -> ^Type {
	return vec_type(t_f32, n)
}

@(private)
coord_type_i32 :: proc(n: int) -> ^Type {
	return vec_type(t_i32, n)
}

@(private)
expect_coord :: proc(op: Operand, n: int, float: bool) -> bool {
	if n <= 1 {
		if float {
			return type_is_float(op.type) && !type_is_vector(op.type)
		}
		return type_is_integer(op.type) && !type_is_vector(op.type)
	}
	v, ok := op.type.derived.(^Type_Vector)
	if !ok || int(v.len) != n {
		return false
	}
	if float {
		return v.elem == t_f32 || type_is_float(v.elem)
	}
	return type_is_integer(v.elem)
}

@(private)
check_sample :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	n := len(call.args)
	if n < 3 || n > 5 {
		check_err(checker, call.pos, "builtin 'sample' expects 3 to 5 arguments, got %d", n)
		return builtin_fail(checker, call)
	}
	tex := check_resource_arg(checker, call.args[0], t_t32_2d)
	if !type_is_texture_id(tex.type) {
		check_err(checker, call.args[0].pos, "builtin 'sample' expects a texture handle, got '%s'", string_from_type(tex.type))
		return builtin_fail(checker, call)
	}
	view := resource_view_of(tex.type)
	if view == .Invalid {
		check_err(checker, call.args[0].pos, "builtin 'sample' cannot sample '%s'", string_from_type(tex.type))
		return builtin_fail(checker, call)
	}
	samp := check_resource_arg(checker, call.args[1], t_s32)
	if !type_is_sampler_id(samp.type) {
		check_err(checker, call.args[1].pos, "builtin 'sample' expects a sampler id, got '%s'", string_from_type(samp.type))
		return builtin_fail(checker, call)
	}
	is_cmp := type_is_compare_sampler_id(samp.type)
	if is_cmp && !resource_view_supports_compare(view) {
		check_err(checker, call.args[1].pos, "comparison sampling is not available for '%s'", string_from_type(tex.type))
		return builtin_fail(checker, call)
	}
	cn := resource_view_sample_coord_len(view)
	coord_hint := coord_type_f32(cn)
	coord := check_expr(checker, call.args[2], type_hint = coord_hint)
	coerce_untyped(&coord, coord_hint)
	if !expect_coord(coord, cn, true) {
		check_err(checker, call.args[2].pos, "builtin 'sample' expects %s coords for '%s', got '%s'", string_from_type(coord_hint), string_from_type(tex.type), string_from_type(coord.type))
		return builtin_fail(checker, call)
	}
	if is_cmp {
		if n < 4 {
			check_err(checker, call.pos, "comparison 'sample' expects a ref: f32 argument")
			return builtin_fail(checker, call)
		}
		ref := check_expr(checker, call.args[3], type_hint = t_f32)
		coerce_untyped(&ref, t_f32)
		if !type_is_float(ref.type) || type_is_vector(ref.type) {
			check_err(checker, call.args[3].pos, "comparison 'sample' ref must be f32, got '%s'", string_from_type(ref.type))
			return builtin_fail(checker, call)
		}
		if n == 5 {
			if !resource_view_compare_lod_ok(view) {
				check_err(checker, call.pos, "explicit lod is not available for comparison sampling of '%s'", string_from_type(tex.type))
				return builtin_fail(checker, call)
			}
			lod := check_expr(checker, call.args[4], type_hint = t_f32)
			coerce_untyped(&lod, t_f32)
			if !type_is_float(lod.type) || type_is_vector(lod.type) {
				check_err(checker, call.args[4].pos, "sample lod must be f32, got '%s'", string_from_type(lod.type))
				return builtin_fail(checker, call)
			}
		} else if n != 4 {
			check_err(checker, call.pos, "comparison 'sample' expects 4 or 5 arguments, got %d", n)
			return builtin_fail(checker, call)
		}
		return builtin_value(call, id, t_f32)
	}
	if n == 4 {
		lod := check_expr(checker, call.args[3], type_hint = t_f32)
		coerce_untyped(&lod, t_f32)
		if !type_is_float(lod.type) || type_is_vector(lod.type) {
			check_err(checker, call.args[3].pos, "sample lod must be f32, got '%s'", string_from_type(lod.type))
			return builtin_fail(checker, call)
		}
	} else if n != 3 {
		check_err(checker, call.pos, "color 'sample' expects 3 or 4 arguments, got %d", n)
		return builtin_fail(checker, call)
	}
	return builtin_value(call, id, vec_type(t_f32, 4))
}

@(private)
check_load :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if len(call.args) < 2 || len(call.args) > 3 {
		check_err(checker, call.pos, "builtin 'load' expects 2 or 3 arguments, got %d", len(call.args))
		return builtin_fail(checker, call)
	}
	handle := check_expr(checker, call.args[0])
	if type_is_untyped(handle.type) {
		check_err(checker, call.args[0].pos, "ambiguous resource id for 'load'; cast to t32_2d or rw32_2d")
		return builtin_fail(checker, call)
	}
	is_tex := type_is_texture_id(handle.type)
	is_rw := type_is_rw_texture_id(handle.type)
	if !is_tex && !is_rw {
		check_err(checker, call.args[0].pos, "builtin 'load' expects a texture or rw handle, got '%s'", string_from_type(handle.type))
		return builtin_fail(checker, call)
	}
	view := resource_view_of(handle.type)
	if is_tex && !resource_view_sampled_load_ok(view) {
		check_err(checker, call.args[0].pos, "builtin 'load' cannot fetch cube views; use 'sample'")
		return builtin_fail(checker, call)
	}
	if is_rw && len(call.args) != 2 {
		check_err(checker, call.pos, "builtin 'load' on rw texture expects 2 arguments, got %d", len(call.args))
		return builtin_fail(checker, call)
	}
	cn := resource_view_load_coord_len(view)
	coord_hint := coord_type_i32(cn)
	coord := check_expr(checker, call.args[1], type_hint = coord_hint)
	coerce_untyped(&coord, coord_hint)
	if !expect_coord(coord, cn, false) {
		check_err(checker, call.args[1].pos, "builtin 'load' expects %s coord, got '%s'", string_from_type(coord_hint), string_from_type(coord.type))
		return builtin_fail(checker, call)
	}
	if is_tex && len(call.args) == 3 {
		mip := check_expr(checker, call.args[2], type_hint = t_i32)
		coerce_untyped(&mip, t_i32)
		default_untyped_int(&mip)
		if !type_is_integer(mip.type) {
			check_err(checker, call.args[2].pos, "builtin 'load' mip must be an integer, got '%s'", string_from_type(mip.type))
			return builtin_fail(checker, call)
		}
	}
	return builtin_value(call, id, vec_type(t_f32, 4))
}

@(private)
check_store :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 3) do return builtin_fail(checker, call)
	handle := check_resource_arg(checker, call.args[0], t_rw32_2d)
	if !type_is_rw_texture_id(handle.type) {
		check_err(checker, call.args[0].pos, "builtin 'store' expects an rw handle, got '%s'", string_from_type(handle.type))
		return builtin_fail(checker, call)
	}
	view := resource_view_of(handle.type)
	cn := resource_view_load_coord_len(view)
	coord_hint := coord_type_i32(cn)
	coord := check_expr(checker, call.args[1], type_hint = coord_hint)
	coerce_untyped(&coord, coord_hint)
	if !expect_coord(coord, cn, false) {
		check_err(checker, call.args[1].pos, "builtin 'store' expects %s coord, got '%s'", string_from_type(coord_hint), string_from_type(coord.type))
		return builtin_fail(checker, call)
	}
	color_hint := vec_type(t_f32, 4)
	color := check_expr(checker, call.args[2], type_hint = color_hint)
	coerce_untyped(&color, color_hint)
	cv, is_vec := color.type.derived.(^Type_Vector)
	if !(is_vec && cv.len == 4 && type_is_float(cv.elem)) {
		check_err(checker, call.args[2].pos, "builtin 'store' expects [4]f32 color, got '%s'", string_from_type(color.type))
		return builtin_fail(checker, call)
	}
	return builtin_no_value(call, id)
}

@(private)
check_dim :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
	handle := check_expr(checker, call.args[0])
	if type_is_untyped(handle.type) {
		check_err(checker, call.args[0].pos, "ambiguous resource id for 'dim'; cast to t32_2d or rw32_2d")
		return builtin_fail(checker, call)
	}
	if !type_is_texture_id(handle.type) && !type_is_rw_texture_id(handle.type) {
		check_err(checker, call.args[0].pos, "builtin 'dim' expects t* or rw*, got '%s'", string_from_type(handle.type))
		return builtin_fail(checker, call)
	}
	n := resource_view_dim_len(resource_view_of(handle.type))
	return builtin_value(call, id, coord_type_i32(n))
}

@(private)
checker_named_type :: proc(checker: ^Checker, name: string) -> ^Type {
	e := scope_lookup(checker.curr_scope, name)
	if e == nil || e.type == nil do return nil
	return e.type
}

@(private)
check_ray_query_init :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 2) do return builtin_fail(checker, call)
	desc_t := checker_named_type(checker, "Ray_Desc")
	if desc_t == nil {
		check_err(checker, call.pos, "builtin 'rayquery_init' requires builtin type 'Ray_Desc'")
		return builtin_fail(checker, call)
	}
	desc := check_expr(checker, call.args[0], type_hint = desc_t)
	convert_to_typed(checker, &desc, desc_t)
	if !type_eq(desc.type, desc_t) {
		check_err(checker, call.args[0].pos, "builtin 'rayquery_init' expects 'Ray_Desc', got '%s'", string_from_type(desc.type))
		return builtin_fail(checker, call)
	}
	bvh := check_resource_arg(checker, call.args[1], t_bvh32)
	if !type_is_bvh_id(bvh.type) {
		check_err(checker, call.args[1].pos, "builtin 'rayquery_init' expects bvh32, got '%s'", string_from_type(bvh.type))
		return builtin_fail(checker, call)
	}
	return builtin_value(call, id, t_ray_query)
}

@(private)
check_ray_query_arg :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
	rq := check_expr(checker, call.args[0], type_hint = t_ray_query)
	if !type_is_ray_query(rq.type) {
		check_err(checker, call.args[0].pos, "builtin '%s' expects Ray_Query, got '%s'", builtin_names[id], string_from_type(rq.type))
		return builtin_fail(checker, call)
	}
	return rq
}

@(private)
check_ray_query_proceed :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if check_ray_query_arg(checker, call, id).mode == .Invalid do return builtin_fail(checker, call)
	return builtin_value(call, id, t_b32)
}

@(private)
check_ray_query_hit :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if check_ray_query_arg(checker, call, id).mode == .Invalid do return builtin_fail(checker, call)
	hit_t := checker_named_type(checker, "Ray_Result")
	if hit_t == nil {
		check_err(checker, call.pos, "builtin '%s' requires builtin type 'Ray_Result'", builtin_names[id])
		return builtin_fail(checker, call)
	}
	return builtin_value(call, id, hit_t)
}

@(private)
check_ray_query_confirm :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if check_ray_query_arg(checker, call, id).mode == .Invalid do return builtin_fail(checker, call)
	return builtin_no_value(call, id)
}

@(private)
check_derivative_builtin :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	return check_unary_gen_float(checker, call, id)
}

// --- math / geom patterns ---

@(private)
check_unary_gen_float :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
	ops := check_args(checker, call, {t_f32})
	t, ok := unify_gen_float(checker, call, id, ops)
	if !ok do return builtin_fail(checker, call)
	return builtin_value(call, id, t)
}

@(private)
check_unary_gen_float_to_bool :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
	ops := check_args(checker, call, {t_f32})
	t, ok := unify_gen_float(checker, call, id, ops)
	if !ok do return builtin_fail(checker, call)
	return builtin_value(call, id, bool_gen_from(t))
}

// IEEE bitcast: u32/uvecN ↔ f32/vecN (GLSL uintBitsToFloat / floatBitsToUint).
@(private)
check_bitcast_bits :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc, from_elem, to_elem: ^Type) -> Operand {
	if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
	x := check_expr(checker, call.args[0], type_hint = from_elem)
	if x.mode == .Invalid {
		return builtin_fail(checker, call)
	}
	if type_is_untyped(x.type) {
		coerce_untyped(&x, from_elem)
		if type_is_untyped(x.type) {
			x.type = from_elem
			if x.expr != nil do x.expr.tav.type = from_elem
		}
	}
	elem, n := type_gen_break(x.type)
	if elem == nil || !type_eq(elem, from_elem) {
		check_err(checker, call.pos, "builtin '%s' expects %s or a vector of it, got '%s'", builtin_names[id], string_from_type(from_elem), string_from_type(x.type))
		return builtin_fail(checker, call)
	}
	return builtin_value(call, id, vec_type(to_elem, n))
}

@(private)
check_binary_same_gen_float :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc, allow_scalar := false) -> Operand {
	if !expect_argc(checker, call, id, 2) do return builtin_fail(checker, call)
	ops := check_args(checker, call, {t_f32, t_f32})
	t, ok := unify_gen_float(checker, call, id, ops, allow_scalar = allow_scalar, untyped_as_scalar = allow_scalar)
	if !ok do return builtin_fail(checker, call)
	return builtin_value(call, id, t)
}

// Variadic min/max: 2+ args, scalar broadcast allowed; emit nests GLSL binary calls.
@(private)
check_min_max :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if len(call.args) < 2 {
		check_err(checker, call.pos, "builtin '%s' expects at least 2 arguments, got %d", builtin_names[id], len(call.args))
		return builtin_fail(checker, call)
	}
	ops := check_args(checker, call, nil)
	t, ok := unify_gen_numeric(checker, call, id, ops, allow_scalar = true, untyped_as_scalar = true)
	if !ok do return builtin_fail(checker, call)
	return builtin_value(call, id, t)
}

@(private)
check_ternary_same_gen_float :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc, allow_scalar := false) -> Operand {
	if !expect_argc(checker, call, id, 3) do return builtin_fail(checker, call)
	ops := check_args(checker, call, {t_f32, t_f32, t_f32})
	t, ok := unify_gen_float(checker, call, id, ops, allow_scalar = allow_scalar, untyped_as_scalar = allow_scalar)
	if !ok do return builtin_fail(checker, call)
	return builtin_value(call, id, t)
}

@(private)
check_ternary_same_gen_numeric :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc, allow_scalar := false) -> Operand {
	if !expect_argc(checker, call, id, 3) do return builtin_fail(checker, call)
	ops := check_args(checker, call, {nil, nil, nil})
	t, ok := unify_gen_numeric(checker, call, id, ops, allow_scalar = allow_scalar, untyped_as_scalar = allow_scalar)
	if !ok do return builtin_fail(checker, call)
	return builtin_value(call, id, t)
}

@(private)
check_dot :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 2) do return builtin_fail(checker, call)
	ops := check_args(checker, call, {t_f32, t_f32})
	t, ok := unify_gen_float(checker, call, id, ops)
	if !ok do return builtin_fail(checker, call)
	elem, _ := type_gen_break(t)
	return builtin_value(call, id, elem)
}

@(private)
check_mag_dist :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	n := 1 if id == .mag else 2
	if !expect_argc(checker, call, id, n) do return builtin_fail(checker, call)
	hints := make([]^Type, n, context.temp_allocator)
	for i in 0..<n do hints[i] = t_f32
	ops := check_args(checker, call, hints)
	t, ok := unify_gen_float(checker, call, id, ops)
	if !ok do return builtin_fail(checker, call)
	if !type_is_vector(t) {
		check_err(checker, call.pos, "builtin '%s' expects a vector, got '%s'", builtin_names[id], string_from_type(t))
		return builtin_fail(checker, call)
	}
	elem, _ := type_gen_break(t)
	return builtin_value(call, id, elem)
}

@(private)
check_cross :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 2) do return builtin_fail(checker, call)
	hint := vec_type(t_f32, 3)
	ops := check_args(checker, call, {hint, hint})
	t, ok := unify_gen_float(checker, call, id, ops)
	if !ok do return builtin_fail(checker, call)
	v, is_vec := t.derived.(^Type_Vector)
	if !is_vec || v.len != 3 {
		check_err(checker, call.pos, "builtin 'cross' expects [3]f32 vectors, got '%s'", string_from_type(t))
		return builtin_fail(checker, call)
	}
	return builtin_value(call, id, t)
}

@(private)
check_reflect_faceforward :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	n := 3 if id == .facefoward else 2
	if !expect_argc(checker, call, id, n) do return builtin_fail(checker, call)
	hints := make([]^Type, n, context.temp_allocator)
	for i in 0..<n do hints[i] = t_f32
	ops := check_args(checker, call, hints)
	t, ok := unify_gen_float(checker, call, id, ops[:min(2, n)])
	if !ok do return builtin_fail(checker, call)
	if n == 3 {
		coerce_untyped(&ops[2], t)
		default_untyped_float(&ops[2])
		if !type_eq(ops[2].type, t) {
			check_err(checker, call.pos, "builtin '%s' argument type mismatch", builtin_names[id])
			return builtin_fail(checker, call)
		}
	}
	if !type_is_vector(t) {
		check_err(checker, call.pos, "builtin '%s' expects vectors, got '%s'", builtin_names[id], string_from_type(t))
		return builtin_fail(checker, call)
	}
	return builtin_value(call, id, t)
}

@(private)
check_refract :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 3) do return builtin_fail(checker, call)
	ops := check_args(checker, call, {t_f32, t_f32, t_f32})
	t, ok := unify_gen_float(checker, call, id, ops[:2])
	if !ok do return builtin_fail(checker, call)
	eta := ops[2]
	coerce_untyped(&eta, t_f32)
	default_untyped_float(&eta)
	if !type_is_float(eta.type) && !type_is_gen(eta.type, t_f32) {
		// eta must be scalar float
		elem, n := type_gen_break(eta.type)
		if n != 1 || !type_is_float(elem) {
			check_err(checker, call.args[2].pos, "builtin 'refract' eta must be a scalar float, got '%s'", string_from_type(eta.type))
			return builtin_fail(checker, call)
		}
	}
	if type_is_vector(eta.type) {
		check_err(checker, call.args[2].pos, "builtin 'refract' eta must be a scalar float, got '%s'", string_from_type(eta.type))
		return builtin_fail(checker, call)
	}
	if !type_is_vector(t) {
		check_err(checker, call.pos, "builtin 'refract' expects vectors, got '%s'", string_from_type(t))
		return builtin_fail(checker, call)
	}
	return builtin_value(call, id, t)
}

@(private)
check_ldexp :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 2) do return builtin_fail(checker, call)
	x := check_expr(checker, call.args[0], type_hint = t_f32)
	default_untyped_float(&x)
	if !is_gen_float(x.type) {
		check_err(checker, call.pos, "builtin 'ldexp' expects floating genType, got '%s'", string_from_type(x.type))
		return builtin_fail(checker, call)
	}
	exp_hint := int_gen_from(x.type)
	exp := check_expr(checker, call.args[1], type_hint = exp_hint)
	coerce_untyped(&exp, exp_hint)
	default_untyped_int(&exp)
	if !type_eq(exp.type, exp_hint) && !type_is_gen(exp.type, t_i32) {
		check_err(checker, call.args[1].pos, "builtin 'ldexp' exp must match integer genType, got '%s'", string_from_type(exp.type))
		return builtin_fail(checker, call)
	}
	return builtin_value(call, id, x.type)
}

// modf(x) -> (whole, fract); frexp(x) -> (exp, significand) — last is GLSL return.
@(private)
check_modf_frexp :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
	ops := check_args(checker, call, {t_f32})
	t, ok := unify_gen_float(checker, call, id, ops)
	if !ok do return builtin_fail(checker, call)
	if id == .modf {
		return builtin_value(call, id, make_results_tuple({t, t})) // (whole, fract)
	}
	// frexp
	return builtin_value(call, id, make_results_tuple({int_gen_from(t), t})) // (exp, significand)
}

@(private)
check_transpose :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
	m := check_expr(checker, call.args[0])
	mat, ok := m.type.derived.(^Type_Matrix)
	if !ok {
		check_err(checker, call.pos, "builtin 'transpose' expects a matrix, got '%s'", string_from_type(m.type))
		return builtin_fail(checker, call)
	}
	out := new_type(Type_Matrix)
	out.rows = mat.columns
	out.columns = mat.rows
	out.elem = mat.elem
	return builtin_value(call, id, out)
}

@(private)
check_determinant_inverse :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
	m := check_expr(checker, call.args[0])
	mat, ok := m.type.derived.(^Type_Matrix)
	if !ok || mat.rows != mat.columns {
		check_err(checker, call.pos, "builtin '%s' expects a square matrix, got '%s'", builtin_names[id], string_from_type(m.type))
		return builtin_fail(checker, call)
	}
	if id == .determinant do return builtin_value(call, id, mat.elem)
	return builtin_value(call, id, m.type)
}

@(private)
check_matrix_comp_mult :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 2) do return builtin_fail(checker, call)
	a := check_expr(checker, call.args[0])
	b := check_expr(checker, call.args[1], type_hint = a.type)
	if !type_is_matrix(a.type) || !type_eq(a.type, b.type) {
		check_err(checker, call.pos, "builtin 'matrix_comp_mult' expects two matrices of the same type")
		return builtin_fail(checker, call)
	}
	return builtin_value(call, id, a.type)
}

@(private)
check_outer_product :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 2) do return builtin_fail(checker, call)
	c := check_expr(checker, call.args[0])
	r := check_expr(checker, call.args[1])
	cv, c_ok := c.type.derived.(^Type_Vector)
	rv, r_ok := r.type.derived.(^Type_Vector)
	if !c_ok || !r_ok || !type_eq(cv.elem, rv.elem) || !type_is_float(cv.elem) {
		check_err(checker, call.pos, "builtin 'outer_product' expects two float vectors")
		return builtin_fail(checker, call)
	}
	out := new_type(Type_Matrix)
	out.rows = cv.len
	out.columns = rv.len
	out.elem = cv.elem
	return builtin_value(call, id, out)
}

check_builtin_stage :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> bool {
	stages := builtin_stage_flags(id)
	if stages == {} {
		return true
	}
	reason := builtin_names[id]
	if checker.curr_proc != nil {
		inherit_proc_stage_gate(checker.curr_proc, stages, reason)
		if stage, ok := checker.curr_proc.stage.?; ok {
			if builtin_stage_from_stage(stage) not_in stages {
				check_err(checker, call.pos, "builtin '%s' is only valid in %s shaders", reason, builtin_stages_adjective(stages))
				return false
			}
		}
	}
	return true
}

inherit_proc_stage_gate :: proc(proc_t: ^Type_Proc, stages: Builtin_Stages, reason: string) {
	if proc_t == nil || stages == {} {
		return
	}
	if !proc_t.has_stage_gate {
		proc_t.has_stage_gate = true
		proc_t.stage_gate = stages
		proc_t.gate_reason = reason
		return
	}
	proc_t.stage_gate &= stages
	if proc_t.stage_gate == {} {
		proc_t.stage_gate = stages
		proc_t.gate_reason = reason
	}
}

check_builtin :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc, type_hint: ^Type = nil) -> (operand: Operand) {
	operand.builtin_id = id
	operand.expr = call

	if !check_builtin_stage(checker, call, id) {
		return builtin_fail(checker, call)
	}
	if checker.curr_proc != nil && !builtin_ok_in_fmag(id) {
		if checker.curr_proc.is_fmag {
			check_err(checker, call.pos, "builtin '%s' is not allowed in proc \"fmag\"", builtin_names[id])
			return builtin_fail(checker, call)
		}
		if checker.curr_proc.stage == nil {
			mark_fmag_illegal(checker.curr_proc, builtin_names[id])
		}
	}

	#partial switch id {
	case: check_err(checker, call.pos, "unhandled builtin '%s'", builtin_names[id]); return builtin_fail(checker, call)

	// textures
	case .sample: return check_sample(checker, call, id)
	case .load:   return check_load(checker, call, id)
	case .store:  return check_store(checker, call, id)
	case .dim:    return check_dim(checker, call, id)
	case .rayquery_init:      return check_ray_query_init(checker, call, id)
	case .rayquery_proceed:   return check_ray_query_proceed(checker, call, id)
	case .rayquery_result:    return check_ray_query_hit(checker, call, id)
	case .rayquery_candidate: return check_ray_query_hit(checker, call, id)
	case .rayquery_accept:    return check_ray_query_confirm(checker, call, id)
	case .dFdx, .dFdy, .fwidth:
		return check_derivative_builtin(checker, call, id)

	// unary gen float
	case .radians, .degrees, .sin, .cos, .tan, .asin, .acos, .atan,
	     .sinh, .cosh, .tanh, .asinh, .acosh, .atanh,
	     .exp, .log, .exp2, .log2, .sqrt, .isqrt, .abs, .sign,
	     .floor, .trunc, .round, .round_even, .ceil, .fract:
		return check_unary_gen_float(checker, call, id)

	case .normalize:
		if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
		ops := check_args(checker, call, {t_f32})
		t, ok := unify_gen_float(checker, call, id, ops)
		if !ok do return builtin_fail(checker, call)
		if !type_is_vector(t) {
			check_err(checker, call.pos, "builtin 'normalize' expects a vector, got '%s'", string_from_type(t))
			return builtin_fail(checker, call)
		}
		return builtin_value(call, id, t)

	case .is_nan, .is_inf:
		return check_unary_gen_float_to_bool(checker, call, id)
	case .f32_from_u32_bits:
		return check_bitcast_bits(checker, call, id, t_u32, t_f32)
	case .u32_from_f32_bits:
		return check_bitcast_bits(checker, call, id, t_f32, t_u32)

	// binary same gen float (step allows scalar edge)
	case .pow, .atan2, .mod:
		return check_binary_same_gen_float(checker, call, id)
	case .step:
		return check_binary_same_gen_float(checker, call, id, allow_scalar = true)

	case .min, .max:
		return check_min_max(checker, call, id)

	// ternary: clamp/lerp/smoothstep allow scalar broadcast; fma does not
	case .clamp:
		return check_ternary_same_gen_numeric(checker, call, id, allow_scalar = true)
	case .lerp, .smoothstep:
		return check_ternary_same_gen_float(checker, call, id, allow_scalar = true)
	case .fma:
		return check_ternary_same_gen_float(checker, call, id)

	case .dot: return check_dot(checker, call, id)
	case .mag, .dist: return check_mag_dist(checker, call, id)
	case .cross: return check_cross(checker, call, id)
	case .reflect: return check_reflect_faceforward(checker, call, id)
	case .facefoward: return check_reflect_faceforward(checker, call, id)
	case .refract: return check_refract(checker, call, id)
	case .ldexp: return check_ldexp(checker, call, id)
	case .modf, .frexp: return check_modf_frexp(checker, call, id)

	case .transpose: return check_transpose(checker, call, id)
	case .determinant, .inverse: return check_determinant_inverse(checker, call, id)
	case .matrix_comp_mult: return check_matrix_comp_mult(checker, call, id)
	case .outer_product: return check_outer_product(checker, call, id)

	case .card:
		if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
		x := check_expr(checker, call.args[0])
		if !type_is_bit_set(x.type) {
			check_err(checker, call.pos, "builtin 'card' expects a bit_set, got '%s'", string_from_type(x.type))
			return builtin_fail(checker, call)
		}
		operand = builtin_value(call, id, t_i32)
		if x.mode == .Constant {
			if mask, ok := x.value.(i128); ok {
				count: i128
				m := mask
				for m != 0 {
					count += 1
					m &= m - 1
				}
				operand.mode = .Constant
				operand.value = exact_int(count)
			}
		}
		return operand

	case .len:
		if !expect_argc(checker, call, id, 1) do return builtin_fail(checker, call)
		x := check_expr(checker, call.args[0])
		if type_is_string_kind(x.type) {
			operand = builtin_value(call, id, t_i64)
			if x.mode == .Constant {
				if s, ok := x.value.(string); ok {
					operand.mode = .Constant
					operand.value = exact_int(len(s))
				}
			}
			return operand
		}
		if !type_is_slice(x.type) && !type_is_array(x.type) {
			check_err(checker, call.pos, "builtin 'len' expects a slice, array, or string, got '%s'", string_from_type(x.type))
			return builtin_fail(checker, call)
		}
		operand = builtin_value(call, id, t_i64)
		if array_t, ok := x.type.derived.(^Type_Array); ok {
			operand.mode = .Constant
			operand.value = exact_int(array_t.len)
		}
		return operand

	case .printf, .printfln:
		return check_printf(checker, call, id)

	case .assert:
		return check_assert(checker, call, id)
	case .panic:
		return check_panic(checker, call, id)

	case .fmag_exec:
		return check_fmag_exec(checker, call, type_hint)

	case .barrier, .memory_barrier, .memory_barrier_shared,
	     .memory_barrier_buffer, .memory_barrier_image, .group_memory_barrier:
		return check_compute_sync_builtin(checker, call, id)

	case .wave_is_first, .wave_lane_count, .wave_lane_id,
	     .wave_any, .wave_all, .wave_ballot, .wave_broadcast_first, .wave_read, .wave_all_equal,
	     .wave_bit_count, .wave_sum, .wave_product, .wave_min, .wave_max,
	     .wave_bit_and, .wave_bit_or, .wave_bit_xor,
	     .wave_prefix_sum, .wave_prefix_product, .wave_prefix_bit_count,
	     .wave_quad_x, .wave_quad_y, .wave_quad_diag, .wave_quad_read,
	     .wave_shuffle_xor, .wave_shuffle_up, .wave_shuffle_down,
	     .wave_clustered_sum, .wave_clustered_product, .wave_clustered_min, .wave_clustered_max,
	     .wave_clustered_bit_and, .wave_clustered_bit_or, .wave_clustered_bit_xor,
	     .wave_rotate, .wave_clustered_rotate:
		return check_wave_builtin(checker, call, id)
	}

	return operand
}

check_compute_sync_builtin :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	if !expect_argc(checker, call, id, 0) do return builtin_fail(checker, call)
	if checker.curr_proc == nil {
		check_err(checker, call.pos, "builtin '%s' is only valid inside a procedure", builtin_names[id])
		return builtin_fail(checker, call)
	}
	if !check_builtin_stage(checker, call, id) {
		return builtin_fail(checker, call)
	}
	checker.curr_proc.uses_compute_sync = true
	return builtin_no_value(call, id)
}
