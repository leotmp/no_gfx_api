package spirv

return_void :: proc(m: ^Module) {
	emit_fn_lit(m, .Return_)
	mark_terminated(m)
}

return_value :: proc(m: ^Module, v: Id) {
	emit_fn_lit(m, .ReturnValue, Word(v))
	mark_terminated(m)
}

unreachable :: proc(m: ^Module) {
	emit_fn_lit(m, .Unreachable)
	mark_terminated(m)
}

kill :: proc(m: ^Module) {
	emit_fn_lit(m, .Kill)
	mark_terminated(m)
}

branch :: proc(m: ^Module, target: Id) {
	emit_fn_lit(m, .Branch, Word(target))
	mark_terminated(m)
}

branch_cond :: proc(m: ^Module, cond, true_blk, false_blk: Id) {
	emit_fn_lit(m, .BranchConditional, Word(cond), Word(true_blk), Word(false_blk))
	mark_terminated(m)
}

selection_merge :: proc(m: ^Module, merge: Id, control := Selection_Control.None) {
	emit_fn_lit(m, .SelectionMerge, Word(merge), Word(control))
}

loop_merge :: proc(m: ^Module, merge, cont: Id, control := Loop_Control.None) {
	emit_fn_lit(m, .LoopMerge, Word(merge), Word(cont), Word(control))
}

Switch_Case :: struct {
	value: u32,
	label: Id,
}

switch_u32 :: proc(m: ^Module, selector, default_blk: Id, cases: []Switch_Case) {
	ops := make([]Word, 2 + 2 * len(cases), context.temp_allocator)
	ops[0] = Word(selector)
	ops[1] = Word(default_blk)
	for c, i in cases {
		ops[2 + 2 * i] = c.value
		ops[3 + 2 * i] = Word(c.label)
	}
	emit_fn(m, .Switch_, ops)
	mark_terminated(m)
}

load :: proc(m: ^Module, ty, ptr: Id, access: u32 = 0, extra: ..u32) -> Id {
	if access == 0 {
		return emit_typed_lit(m, .Load, ty, Word(ptr))
	}
	ops := make([]Word, 2 + len(extra), context.temp_allocator)
	ops[0] = Word(ptr)
	ops[1] = access
	copy(ops[2:], extra)
	return emit_typed(m, .Load, ty, ops)
}

store :: proc(m: ^Module, ptr, val: Id, access: u32 = 0, extra: ..u32) {
	if access == 0 {
		emit_fn_lit(m, .Store, Word(ptr), Word(val))
		return
	}
	ops := make([]Word, 3 + len(extra), context.temp_allocator)
	ops[0] = Word(ptr)
	ops[1] = Word(val)
	ops[2] = access
	copy(ops[3:], extra)
	emit_fn(m, .Store, ops)
}

load_aligned :: proc(m: ^Module, ty, ptr: Id, align: u32) -> Id {
	return load(m, ty, ptr, u32(Memory_Access.Aligned), align)
}

store_aligned :: proc(m: ^Module, ptr, val: Id, align: u32) {
	store(m, ptr, val, u32(Memory_Access.Aligned), align)
}

access_chain :: proc(m: ^Module, result_ptr_ty, base: Id, indexes: []Id) -> Id {
	ops := make([]Word, 1 + len(indexes), context.temp_allocator)
	ops[0] = Word(base)
	for idx, i in indexes {
		ops[1 + i] = Word(idx)
	}
	return emit_typed(m, .AccessChain, result_ptr_ty, ops)
}

in_bounds_access_chain :: proc(m: ^Module, result_ptr_ty, base: Id, indexes: []Id) -> Id {
	ops := make([]Word, 1 + len(indexes), context.temp_allocator)
	ops[0] = Word(base)
	for idx, i in indexes {
		ops[1 + i] = Word(idx)
	}
	return emit_typed(m, .InBoundsAccessChain, result_ptr_ty, ops)
}

ptr_access_chain :: proc(m: ^Module, result_ptr_ty, base, element: Id, indexes: []Id = nil) -> Id {
	ops := make([]Word, 2 + len(indexes), context.temp_allocator)
	ops[0] = Word(base)
	ops[1] = Word(element)
	for idx, i in indexes {
		ops[2 + i] = Word(idx)
	}
	return emit_typed(m, .PtrAccessChain, result_ptr_ty, ops)
}

composite_extract :: proc(m: ^Module, ty, composite: Id, indexes: ..u32) -> Id {
	ops := make([]Word, 1 + len(indexes), context.temp_allocator)
	ops[0] = Word(composite)
	copy(ops[1:], indexes)
	return emit_typed(m, .CompositeExtract, ty, ops)
}

composite_insert :: proc(m: ^Module, ty, object, composite: Id, indexes: ..u32) -> Id {
	ops := make([]Word, 2 + len(indexes), context.temp_allocator)
	ops[0] = Word(object)
	ops[1] = Word(composite)
	copy(ops[2:], indexes)
	return emit_typed(m, .CompositeInsert, ty, ops)
}

composite_construct :: proc(m: ^Module, ty: Id, parts: []Id) -> Id {
	ops := make([]Word, len(parts), context.temp_allocator)
	for p, i in parts {
		ops[i] = Word(p)
	}
	return emit_typed(m, .CompositeConstruct, ty, ops)
}

vector_shuffle :: proc(m: ^Module, ty, a, b: Id, components: []u32) -> Id {
	ops := make([]Word, 2 + len(components), context.temp_allocator)
	ops[0] = Word(a)
	ops[1] = Word(b)
	copy(ops[2:], components)
	return emit_typed(m, .VectorShuffle, ty, ops)
}

bitcast :: proc(m: ^Module, ty, v: Id) -> Id {
	return emit_typed_lit(m, .Bitcast, ty, Word(v))
}

convert_u_to_ptr :: proc(m: ^Module, ptr_ty, v: Id) -> Id {
	return emit_typed_lit(m, .ConvertUToPtr, ptr_ty, Word(v))
}

convert_ptr_to_u :: proc(m: ^Module, int_ty, v: Id) -> Id {
	return emit_typed_lit(m, .ConvertPtrToU, int_ty, Word(v))
}

uconvert :: proc(m: ^Module, ty, v: Id) -> Id { return emit_typed_lit(m, .UConvert, ty, Word(v)) }
sconvert :: proc(m: ^Module, ty, v: Id) -> Id { return emit_typed_lit(m, .SConvert, ty, Word(v)) }
fconvert :: proc(m: ^Module, ty, v: Id) -> Id { return emit_typed_lit(m, .FConvert, ty, Word(v)) }
convert_s_to_f :: proc(m: ^Module, ty, v: Id) -> Id { return emit_typed_lit(m, .ConvertSToF, ty, Word(v)) }
convert_u_to_f :: proc(m: ^Module, ty, v: Id) -> Id { return emit_typed_lit(m, .ConvertUToF, ty, Word(v)) }
convert_f_to_s :: proc(m: ^Module, ty, v: Id) -> Id { return emit_typed_lit(m, .ConvertFToS, ty, Word(v)) }
convert_f_to_u :: proc(m: ^Module, ty, v: Id) -> Id { return emit_typed_lit(m, .ConvertFToU, ty, Word(v)) }

iadd :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .IAdd, ty, Word(a), Word(b)) }
isub :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .ISub, ty, Word(a), Word(b)) }
imul :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .IMul, ty, Word(a), Word(b)) }
sdiv :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .SDiv, ty, Word(a), Word(b)) }
udiv :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .UDiv, ty, Word(a), Word(b)) }
srem :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .SRem, ty, Word(a), Word(b)) }
umod :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .UMod, ty, Word(a), Word(b)) }
smod :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .SMod, ty, Word(a), Word(b)) }

fadd :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .FAdd, ty, Word(a), Word(b)) }
fsub :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .FSub, ty, Word(a), Word(b)) }
fmul :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .FMul, ty, Word(a), Word(b)) }
fdiv :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .FDiv, ty, Word(a), Word(b)) }
fmod :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .FMod, ty, Word(a), Word(b)) }
frem :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .FRem, ty, Word(a), Word(b)) }
fnegate :: proc(m: ^Module, ty, a: Id) -> Id { return emit_typed_lit(m, .FNegate, ty, Word(a)) }
snegate :: proc(m: ^Module, ty, a: Id) -> Id { return emit_typed_lit(m, .SNegate, ty, Word(a)) }

shift_left :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .ShiftLeftLogical, ty, Word(a), Word(b)) }
shift_right_logical :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .ShiftRightLogical, ty, Word(a), Word(b)) }
shift_right_arithmetic :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .ShiftRightArithmetic, ty, Word(a), Word(b)) }
bitwise_or :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .BitwiseOr, ty, Word(a), Word(b)) }
bitwise_and :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .BitwiseAnd, ty, Word(a), Word(b)) }
bitwise_xor :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .BitwiseXor, ty, Word(a), Word(b)) }
not_ :: proc(m: ^Module, ty, a: Id) -> Id { return emit_typed_lit(m, .Not, ty, Word(a)) }
bitcount :: proc(m: ^Module, ty, a: Id) -> Id { return emit_typed_lit(m, .BitCount, ty, Word(a)) }

logical_or :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .LogicalOr, type_bool(m), Word(a), Word(b)) }
logical_and :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .LogicalAnd, type_bool(m), Word(a), Word(b)) }
logical_not :: proc(m: ^Module, a: Id) -> Id { return emit_typed_lit(m, .LogicalNot, type_bool(m), Word(a)) }
logical_equal :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .LogicalEqual, type_bool(m), Word(a), Word(b)) }
select :: proc(m: ^Module, ty, cond, a, b: Id) -> Id { return emit_typed_lit(m, .Select, ty, Word(cond), Word(a), Word(b)) }

iequal :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .IEqual, type_bool(m), Word(a), Word(b)) }
inot_equal :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .INotEqual, type_bool(m), Word(a), Word(b)) }
inot_equal_ty :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .INotEqual, ty, Word(a), Word(b)) }

group_non_uniform_elect :: proc(m: ^Module, ty, scope: Id) -> Id {
	require_cap(m, .GroupNonUniform)
	return emit_typed_lit(m, .GroupNonUniformElect, ty, Word(scope))
}

group_non_uniform_any :: proc(m: ^Module, ty, scope, pred: Id) -> Id {
	require_cap(m, .GroupNonUniform)
	require_cap(m, .GroupNonUniformVote)
	return emit_typed_lit(m, .GroupNonUniformAny, ty, Word(scope), Word(pred))
}

group_non_uniform_all :: proc(m: ^Module, ty, scope, pred: Id) -> Id {
	require_cap(m, .GroupNonUniform)
	require_cap(m, .GroupNonUniformVote)
	return emit_typed_lit(m, .GroupNonUniformAll, ty, Word(scope), Word(pred))
}

group_non_uniform_all_equal :: proc(m: ^Module, ty, scope, value: Id) -> Id {
	require_cap(m, .GroupNonUniform)
	require_cap(m, .GroupNonUniformVote)
	return emit_typed_lit(m, .GroupNonUniformAllEqual, ty, Word(scope), Word(value))
}

group_non_uniform_broadcast_first :: proc(m: ^Module, ty, scope, value: Id) -> Id {
	require_cap(m, .GroupNonUniform)
	return emit_typed_lit(m, .GroupNonUniformBroadcastFirst, ty, Word(scope), Word(value))
}

group_non_uniform_ballot :: proc(m: ^Module, ty, scope, pred: Id) -> Id {
	require_cap(m, .GroupNonUniform)
	require_cap(m, .GroupNonUniformBallot)
	return emit_typed_lit(m, .GroupNonUniformBallot, ty, Word(scope), Word(pred))
}

group_non_uniform_ballot_bit_count :: proc(m: ^Module, ty, scope: Id, op: Group_Operation, value: Id) -> Id {
	require_cap(m, .GroupNonUniform)
	require_cap(m, .GroupNonUniformBallot)
	return emit_typed_lit(m, .GroupNonUniformBallotBitCount, ty, Word(scope), Word(u32(op)), Word(value))
}

group_non_uniform_shuffle :: proc(m: ^Module, ty, scope, value, id: Id) -> Id {
	require_cap(m, .GroupNonUniform)
	require_cap(m, .GroupNonUniformShuffle)
	return emit_typed_lit(m, .GroupNonUniformShuffle, ty, Word(scope), Word(value), Word(id))
}

group_non_uniform_shuffle_xor :: proc(m: ^Module, ty, scope, value, mask: Id) -> Id {
	require_cap(m, .GroupNonUniform)
	require_cap(m, .GroupNonUniformShuffle)
	return emit_typed_lit(m, .GroupNonUniformShuffleXor, ty, Word(scope), Word(value), Word(mask))
}

group_non_uniform_shuffle_up :: proc(m: ^Module, ty, scope, value, delta: Id) -> Id {
	require_cap(m, .GroupNonUniform)
	require_cap(m, .GroupNonUniformShuffleRelative)
	return emit_typed_lit(m, .GroupNonUniformShuffleUp, ty, Word(scope), Word(value), Word(delta))
}

group_non_uniform_shuffle_down :: proc(m: ^Module, ty, scope, value, delta: Id) -> Id {
	require_cap(m, .GroupNonUniform)
	require_cap(m, .GroupNonUniformShuffleRelative)
	return emit_typed_lit(m, .GroupNonUniformShuffleDown, ty, Word(scope), Word(value), Word(delta))
}

group_non_uniform_arith :: proc(m: ^Module, op: Op, ty, scope: Id, group_op: Group_Operation, value: Id, cluster: Id = NONE) -> Id {
	require_cap(m, .GroupNonUniform)
	require_cap(m, .GroupNonUniformArithmetic)
	if group_op == .ClusteredReduce {
		require_cap(m, .GroupNonUniformClustered)
		return emit_typed_lit(m, op, ty, Word(scope), Word(u32(group_op)), Word(value), Word(cluster))
	}
	return emit_typed_lit(m, op, ty, Word(scope), Word(u32(group_op)), Word(value))
}

group_non_uniform_quad_swap :: proc(m: ^Module, ty, scope, value, direction: Id) -> Id {
	require_cap(m, .GroupNonUniform)
	require_cap(m, .GroupNonUniformQuad)
	return emit_typed_lit(m, .GroupNonUniformQuadSwap, ty, Word(scope), Word(value), Word(direction))
}

group_non_uniform_quad_broadcast :: proc(m: ^Module, ty, scope, value, index: Id) -> Id {
	require_cap(m, .GroupNonUniform)
	require_cap(m, .GroupNonUniformQuad)
	return emit_typed_lit(m, .GroupNonUniformQuadBroadcast, ty, Word(scope), Word(value), Word(index))
}

group_non_uniform_rotate :: proc(m: ^Module, ty, scope, value, delta: Id, cluster: Id = NONE) -> Id {
	require_cap(m, .GroupNonUniform)
	require_cap(m, .GroupNonUniformRotateKHR)
	require_ext(m, EXT_SUBGROUP_ROTATE)
	if cluster != NONE {
		return emit_typed_lit(m, .GroupNonUniformRotateKHR, ty, Word(scope), Word(value), Word(delta), Word(cluster))
	}
	return emit_typed_lit(m, .GroupNonUniformRotateKHR, ty, Word(scope), Word(value), Word(delta))
}

sless_than :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .SLessThan, type_bool(m), Word(a), Word(b)) }
sless_equal :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .SLessThanEqual, type_bool(m), Word(a), Word(b)) }
sgreater_than :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .SGreaterThan, type_bool(m), Word(a), Word(b)) }
sgreater_equal :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .SGreaterThanEqual, type_bool(m), Word(a), Word(b)) }
uless_than :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .ULessThan, type_bool(m), Word(a), Word(b)) }
uless_equal :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .ULessThanEqual, type_bool(m), Word(a), Word(b)) }
ugreater_than :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .UGreaterThan, type_bool(m), Word(a), Word(b)) }
ugreater_equal :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .UGreaterThanEqual, type_bool(m), Word(a), Word(b)) }

ford_equal :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .FOrdEqual, type_bool(m), Word(a), Word(b)) }
ford_not_equal :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .FOrdNotEqual, type_bool(m), Word(a), Word(b)) }
ford_less :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .FOrdLessThan, type_bool(m), Word(a), Word(b)) }
ford_less_equal :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .FOrdLessThanEqual, type_bool(m), Word(a), Word(b)) }
ford_greater :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .FOrdGreaterThan, type_bool(m), Word(a), Word(b)) }
ford_greater_equal :: proc(m: ^Module, a, b: Id) -> Id { return emit_typed_lit(m, .FOrdGreaterThanEqual, type_bool(m), Word(a), Word(b)) }

dot :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .Dot, ty, Word(a), Word(b)) }
transpose :: proc(m: ^Module, ty, a: Id) -> Id { return emit_typed_lit(m, .Transpose, ty, Word(a)) }
outer_product :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .OuterProduct, ty, Word(a), Word(b)) }
matrix_times_vector :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .MatrixTimesVector, ty, Word(a), Word(b)) }
vector_times_matrix :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .VectorTimesMatrix, ty, Word(a), Word(b)) }
matrix_times_matrix :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .MatrixTimesMatrix, ty, Word(a), Word(b)) }
matrix_times_scalar :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .MatrixTimesScalar, ty, Word(a), Word(b)) }
vector_times_scalar :: proc(m: ^Module, ty, a, b: Id) -> Id { return emit_typed_lit(m, .VectorTimesScalar, ty, Word(a), Word(b)) }

dpdx :: proc(m: ^Module, ty, a: Id) -> Id { return emit_typed_lit(m, .DPdx, ty, Word(a)) }
dpdy :: proc(m: ^Module, ty, a: Id) -> Id { return emit_typed_lit(m, .DPdy, ty, Word(a)) }
fwidth :: proc(m: ^Module, ty, a: Id) -> Id { return emit_typed_lit(m, .Fwidth, ty, Word(a)) }
is_nan :: proc(m: ^Module, a: Id) -> Id { return emit_typed_lit(m, .IsNan, type_bool(m), Word(a)) }
is_inf :: proc(m: ^Module, a: Id) -> Id { return emit_typed_lit(m, .IsInf, type_bool(m), Word(a)) }

call :: proc(m: ^Module, result_ty, fn: Id, args: []Id) -> Id {
	ops := make([]Word, 1 + len(args), context.temp_allocator)
	ops[0] = Word(fn)
	for a, i in args {
		ops[1 + i] = Word(a)
	}
	return emit_typed(m, .FunctionCall, result_ty, ops)
}

copy_object :: proc(m: ^Module, ty, v: Id) -> Id {
	return emit_typed_lit(m, .CopyObject, ty, Word(v))
}

undef :: proc(m: ^Module, ty: Id) -> Id {
	return emit_typed_lit(m, .Undef, ty)
}

phi :: proc(m: ^Module, ty: Id, pairs: []struct{value, pred: Id}) -> Id {
	ops := make([]Word, 2 * len(pairs), context.temp_allocator)
	for p, i in pairs {
		ops[2 * i] = Word(p.value)
		ops[2 * i + 1] = Word(p.pred)
	}
	return emit_typed(m, .Phi, ty, ops)
}

control_barrier :: proc(m: ^Module, exec, mem: Scope, semantics: u32) {
	emit_fn_lit(m, .ControlBarrier, Word(const_u32(m, u32(exec))), Word(const_u32(m, u32(mem))), Word(const_u32(m, semantics)))
}

memory_barrier :: proc(m: ^Module, mem: Scope, semantics: u32) {
	emit_fn_lit(m, .MemoryBarrier, Word(const_u32(m, u32(mem))), Word(const_u32(m, semantics)))
}

sampled_image :: proc(m: ^Module, result_ty, image, sampler: Id) -> Id {
	return emit_typed_lit(m, .SampledImage, result_ty, Word(image), Word(sampler))
}

image_sample_implicit :: proc(m: ^Module, result_ty, sampled, coord: Id) -> Id {
	return emit_typed_lit(m, .ImageSampleImplicitLod, result_ty, Word(sampled), Word(coord))
}

image_sample_explicit_lod :: proc(m: ^Module, result_ty, sampled, coord, lod: Id) -> Id {
	return emit_typed_lit(m, .ImageSampleExplicitLod, result_ty, Word(sampled), Word(coord), u32(Image_Operands.Lod), Word(lod))
}

image_sample_dref_implicit :: proc(m: ^Module, result_ty, sampled, coord, dref: Id) -> Id {
	return emit_typed_lit(m, .ImageSampleDrefImplicitLod, result_ty, Word(sampled), Word(coord), Word(dref))
}

image_sample_dref_explicit_lod :: proc(m: ^Module, result_ty, sampled, coord, dref, lod: Id) -> Id {
	return emit_typed_lit(m, .ImageSampleDrefExplicitLod, result_ty, Word(sampled), Word(coord), Word(dref), u32(Image_Operands.Lod), Word(lod))
}

image_fetch :: proc(m: ^Module, result_ty, image, coord: Id, lod: Id = NONE) -> Id {
	if lod == NONE {
		return emit_typed_lit(m, .ImageFetch, result_ty, Word(image), Word(coord))
	}
	return emit_typed_lit(m, .ImageFetch, result_ty, Word(image), Word(coord), u32(Image_Operands.Lod), Word(lod))
}

image_read :: proc(m: ^Module, result_ty, image, coord: Id) -> Id {
	return emit_typed_lit(m, .ImageRead, result_ty, Word(image), Word(coord))
}

image_write :: proc(m: ^Module, image, coord, texel: Id) {
	emit_fn_lit(m, .ImageWrite, Word(image), Word(coord), Word(texel))
}

image_query_size :: proc(m: ^Module, result_ty, image: Id) -> Id {
	return emit_typed_lit(m, .ImageQuerySize, result_ty, Word(image))
}

image_query_size_lod :: proc(m: ^Module, result_ty, image, lod: Id) -> Id {
	return emit_typed_lit(m, .ImageQuerySizeLod, result_ty, Word(image), Word(lod))
}

atomic_compare_exchange :: proc(m: ^Module, ty, ptr, scope, eq, uneq, value, comparator: Id) -> Id {
	return emit_typed_lit(m, .AtomicCompareExchange, ty, Word(ptr), Word(scope), Word(eq), Word(uneq), Word(value), Word(comparator))
}

atomic_iadd :: proc(m: ^Module, ty, ptr, scope, semantics, value: Id) -> Id {
	return emit_typed_lit(m, .AtomicIAdd, ty, Word(ptr), Word(scope), Word(semantics), Word(value))
}

ray_query_initialize :: proc(m: ^Module, rq, accel, flags, cull, origin, tmin, dir, tmax: Id) {
	emit_fn_lit(m, .RayQueryInitializeKHR, Word(rq), Word(accel), Word(flags), Word(cull), Word(origin), Word(tmin), Word(dir), Word(tmax))
}

ray_query_proceed :: proc(m: ^Module, rq: Id) -> Id {
	return emit_typed_lit(m, .RayQueryProceedKHR, type_bool(m), Word(rq))
}

ray_query_confirm :: proc(m: ^Module, rq: Id) {
	emit_fn_lit(m, .RayQueryConfirmIntersectionKHR, Word(rq))
}

ray_query_get_intersection_type :: proc(m: ^Module, rq, committed: Id) -> Id {
	return emit_typed_lit(m, .RayQueryGetIntersectionTypeKHR, type_u32(m), Word(rq), Word(committed))
}

ray_query_get_intersection_t :: proc(m: ^Module, rq, committed: Id) -> Id {
	return emit_typed_lit(m, .RayQueryGetIntersectionTKHR, type_f32(m), Word(rq), Word(committed))
}

ray_query_get_intersection_instance_id :: proc(m: ^Module, rq, committed: Id) -> Id {
	return emit_typed_lit(m, .RayQueryGetIntersectionInstanceIdKHR, type_i32(m), Word(rq), Word(committed))
}

ray_query_get_intersection_primitive :: proc(m: ^Module, rq, committed: Id) -> Id {
	return emit_typed_lit(m, .RayQueryGetIntersectionPrimitiveIndexKHR, type_i32(m), Word(rq), Word(committed))
}

ray_query_get_intersection_front_face :: proc(m: ^Module, rq, committed: Id) -> Id {
	return emit_typed_lit(m, .RayQueryGetIntersectionFrontFaceKHR, type_bool(m), Word(rq), Word(committed))
}

ray_query_get_intersection_barycentrics :: proc(m: ^Module, rq, committed: Id) -> Id {
	return emit_typed_lit(m, .RayQueryGetIntersectionBarycentricsKHR, type_vector(m, type_f32(m), 2), Word(rq), Word(committed))
}

ray_query_get_object_to_world :: proc(m: ^Module, result_ty, rq, committed: Id) -> Id {
	return emit_typed_lit(m, .RayQueryGetIntersectionObjectToWorldKHR, result_ty, Word(rq), Word(committed))
}

ray_query_get_world_to_object :: proc(m: ^Module, result_ty, rq, committed: Id) -> Id {
	return emit_typed_lit(m, .RayQueryGetIntersectionWorldToObjectKHR, result_ty, Word(rq), Word(committed))
}

copy_memory :: proc(m: ^Module, dst, src: Id, access: u32 = 0, extra: ..u32) {
	if access == 0 {
		emit_fn_lit(m, .CopyMemory, Word(dst), Word(src))
		return
	}
	ops := make([]Word, 3 + len(extra), context.temp_allocator)
	ops[0] = Word(dst)
	ops[1] = Word(src)
	ops[2] = access
	copy(ops[3:], extra)
	emit_fn(m, .CopyMemory, ops)
}
