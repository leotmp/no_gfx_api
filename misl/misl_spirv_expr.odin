package misl

import "core:fmt"
import "core:reflect"
import "core:strings"

import spv "spirv"

spv_rvalue :: proc(cg: ^Spv_CG, expr: ^Expr) -> spv.Id {
	if expr == nil {
		return spv.NONE
	}
	saved := cg.bounds_check
	cg.bounds_check = cg_bounds_from_flags(cg.bounds_check, expr.state_flags)
	defer cg.bounds_check = saved

	if expr.tav.mode == .Constant && expr.tav.value != nil {
		_, is_str := expr.tav.value.(string)
		if !is_str && !exact_value_is_compound(expr.tav.value) {
			#partial switch _ in expr.derived_expr {
			case ^Ident, ^Basic_Lit, ^Implicit_Selector_Expr, ^Binary_Expr, ^Unary_Expr, ^Paren_Expr, ^Auto_Cast, ^Type_Cast, ^Call_Expr, ^Comp_Lit, ^Ternary_If_Expr, ^Ternary_When_Expr:
				return spv_const_value(cg, expr.tav.type, expr.tav.value)
			}
		}
	}

	#partial switch v in expr.derived_expr {
	case ^Paren_Expr:
		return spv_rvalue(cg, v.expr)
	case ^Ident:
		return spv_ident_rvalue(cg, v)
	case ^Basic_Lit:
		return spv_const_value(cg, expr.tav.type, expr.tav.value)
	case ^Implicit_Selector_Expr:
		return spv_const_value(cg, v.field.tav.type, v.field.tav.value)
	case ^Unary_Expr:
		return spv_unary(cg, v)
	case ^Binary_Expr:
		return spv_binary(cg, v)
	case ^Selector_Expr:
		return spv_selector_rvalue(cg, v)
	case ^Index_Expr:
		if type_is_string_kind(v.expr.tav.type) {
			return spv_string_index(cg, v)
		}
		l := spv_index_lval(cg, v)
		return spv_load_ptr(cg, l)
	case ^Deref_Expr:
		return spv_deref_rvalue(cg, v)
	case ^Matrix_Index_Expr:
		l := spv_matrix_index_lval(cg, v)
		return spv_load_ptr(cg, l)
	case ^Type_Cast, ^Auto_Cast:
		inner: ^Expr
		if tc, ok := v.(^Type_Cast); ok {
			inner = tc.expr
		} else {
			inner = v.(^Auto_Cast).expr
		}
		src := spv_rvalue(cg, inner)
		return spv_convert(cg, src, inner.tav.type, expr.tav.type)
	case ^Call_Expr:
		return spv_call_rvalue(cg, v)
	case ^Comp_Lit:
		return spv_comp_lit_rvalue(cg, v)
	case ^Ternary_If_Expr:
		return spv_ternary(cg, v)
	case ^Ternary_When_Expr:
		if b, ok := v.cond.tav.value.(bool); ok {
			return spv_rvalue(cg, v.x if b else v.y)
		}
		spv_err(cg, v.pos, "codegen_spirv: 'when' expression condition was not a constant bool")
		return spv_zero(cg, expr.tav.type)
	case ^Slice_Expr:
		return spv_slice_expr(cg, v)
	case:
		spv_err(cg, expr.pos, "codegen_spirv: unsupported expression %v", reflect.union_variant_typeid(expr.derived_expr))
		return spv_zero(cg, expr.tav.type)
	}
}

spv_ident_rvalue :: proc(cg: ^Spv_CG, v: ^Ident) -> spv.Id {
	e := v.entity
	if e == nil {
		spv_err(cg, v.pos, "codegen_spirv: ident '%s' has no entity", v.name)
		return spv.NONE
	}
	if e.using_base != nil {
		base := spv_rvalue(cg, e.using_base)
		t := e.using_base.tav.type
		cur := base
		for field in e.using_chain {
			if field == nil do continue
			if type_is_pointer(t) {
				cur = spv_psb_index0(cg, cur, type_pointer_elem(t))
				t = type_pointer_elem(t)
			}
			st, sok := t.derived.(^Type_Struct)
			if !sok do continue
			idx := spv_field_index(st, field)
			cur = spv.composite_extract(&cg.m, spv_type(cg, field.type), cur, u32(idx))
			t = field.type
		}
		return cur
	}
	if e.kind == .Constant && type_is_string_kind(e.type) {
		return spv.const_u32(&cg.m, 0)
	}
	if entity_is_poly_const(e) && type_is_string_kind(e.type) {
		return spv.const_u32(&cg.m, 0)
	}
	if e.kind == .Constant && type_is_array(e.type) {
		spv_ensure_array_const(cg, e)
	}
	if e.kind == .Constant && e.value != nil && !type_is_array(e.type) && !type_is_string_kind(e.type) {
		return spv_const_value(cg, e.type, e.value)
	}
	if ptr, ok := cg.entity_ptr[e]; ok {
		load_t := e.type
		if e.semantic == .Indirect_Data {
			if elem := type_pointer_elem(e.type); elem != nil {
				load_t = elem
			}
		}
		sc := spv_entity_sc(cg, e)
		layout: Spv_Layout = .Stored if sc == .PhysicalStorageBuffer else .Func
		val_ty, has_ty := cg.entity_val_ty[e]
		if !has_ty {
			val_ty = spv_type(cg, load_t, layout)
		}
		if sc == .PhysicalStorageBuffer {
			loaded := spv.load_aligned(&cg.m, val_ty, ptr, spv_align_of(load_t))
			return spv_change_layout(cg, loaded, load_t, .Stored, .Func)
		}
		return spv.load(&cg.m, val_ty, ptr)
	}
	spv_err(cg, v.pos, "codegen_spirv: no value for '%s'", e.name)
	return spv_zero(cg, e.type)
}

spv_field_index :: proc(st: ^Type_Struct, field: ^Entity) -> int {
	if st == nil || st.fields == nil do return 0
	for f, i in st.fields.variables {
		if f == field || (f != nil && f.name == field.name) {
			return i
		}
	}
	return 0
}

spv_field_index_name :: proc(st: ^Type_Struct, name: string) -> int {
	if st == nil || st.fields == nil do return 0
	for f, i in st.fields.variables {
		if f != nil && f.name == name {
			return i
		}
	}
	return 0
}

spv_selector_rvalue :: proc(cg: ^Spv_CG, v: ^Selector_Expr) -> spv.Id {
	if lhs := entity_from_expr(v.expr); lhs != nil && lhs.kind == .Import {
		return spv_rvalue(cg, v.field)
	}
	base_t := v.expr.tav.type
	if spv_expr_is_indirect_data(v.expr) {
		if elem := type_pointer_elem(base_t); elem != nil {
			base_t = elem
		}
	}
	if type_is_vector(base_t) {
		vec := spv_rvalue(cg, v.expr)
		return spv_swizzle_extract(cg, vec, base_t, v.field.name, v.tav.type)
	}
	if type_is_pointer(base_t) && !spv_expr_is_indirect_data(v.expr) {
		loaded := spv_psb_index0(cg, spv_rvalue(cg, v.expr), type_pointer_elem(base_t))
		st := type_pointer_elem(base_t).derived.(^Type_Struct)
		idx := spv_field_index_name(st, v.field.name)
		ft := st.fields.variables[idx].type
		return spv.composite_extract(&cg.m, spv_type(cg, ft), loaded, u32(idx))
	}
	agg := spv_rvalue(cg, v.expr)
	if st, ok := base_t.derived.(^Type_Struct); ok {
		idx := spv_field_index_name(st, v.field.name)
		ft := st.fields.variables[idx].type
		return spv.composite_extract(&cg.m, spv_type(cg, ft), agg, u32(idx))
	}
	return agg
}

spv_swizzle_extract :: proc(cg: ^Spv_CG, vec: spv.Id, vec_t: ^Type, swz: string, result_t: ^Type) -> spv.Id {
	comps := spv_swizzle_comps(swz)
	elem := type_base(vec_t)
	if len(comps) == 1 {
		return spv.composite_extract(&cg.m, spv_type(cg, elem), vec, comps[0])
	}
	return spv.vector_shuffle(&cg.m, spv_type(cg, result_t), vec, vec, comps)
}

spv_swizzle_comps :: proc(swz: string) -> []u32 {
	out := make([]u32, len(swz), context.temp_allocator)
	for c, i in swz {
		switch c {
		case 'x', 'r', 's': out[i] = 0
		case 'y', 'g', 't': out[i] = 1
		case 'z', 'b', 'p': out[i] = 2
		case 'w', 'a', 'q': out[i] = 3
		}
	}
	return out
}

spv_expr_is_indirect_data :: proc(expr: ^Expr) -> bool {
	e := entity_from_expr(expr)
	return e != nil && e.semantic == .Indirect_Data
}

spv_deref_rvalue :: proc(cg: ^Spv_CG, v: ^Deref_Expr) -> spv.Id {
	ptr := spv_rvalue(cg, v.expr)
	if spv_expr_is_indirect_data(v.expr) {
		return ptr
	}
	elem := type_pointer_elem(v.expr.tav.type)
	if elem == nil {
		if mp, ok := v.expr.tav.type.derived.(^Type_Multi_Pointer); ok {
			elem = mp.elem
		}
	}
	return spv_psb_index0(cg, ptr, elem)
}

spv_psb_elem_ptr :: proc(cg: ^Spv_CG, ptr: spv.Id, elem: ^Type, index: spv.Id) -> spv.Id {
	zero := spv.const_u32(&cg.m, 0)
	elem_ptr_ty := spv.type_pointer(&cg.m, .PhysicalStorageBuffer, spv_type(cg, elem, .Stored))
	return spv.access_chain(&cg.m, elem_ptr_ty, ptr, {zero, index})
}

spv_psb_index :: proc(cg: ^Spv_CG, ptr: spv.Id, elem: ^Type, index: spv.Id) -> spv.Id {
	chain := spv_psb_elem_ptr(cg, ptr, elem, index)
	loaded := spv.load_aligned(&cg.m, spv_type(cg, elem, .Stored), chain, spv_align_of(elem))
	return spv_change_layout(cg, loaded, elem, .Stored, .Func)
}

spv_psb_index0 :: proc(cg: ^Spv_CG, ptr: spv.Id, elem: ^Type) -> spv.Id {
	return spv_psb_index(cg, ptr, elem, spv.const_u32(&cg.m, 0))
}

spv_psb_store_index :: proc(cg: ^Spv_CG, ptr: spv.Id, elem: ^Type, index: spv.Id, val: spv.Id) {
	zero := spv.const_u32(&cg.m, 0)
	elem_ptr_ty := spv.type_pointer(&cg.m, .PhysicalStorageBuffer, spv_type(cg, elem, .Stored))
	chain := spv.access_chain(&cg.m, elem_ptr_ty, ptr, {zero, index})
	stored := spv_change_layout(cg, val, elem, .Func, .Stored)
	spv.store_aligned(&cg.m, chain, stored, spv_align_of(elem))
}

spv_index_as_u32 :: proc(cg: ^Spv_CG, index: ^Expr) -> spv.Id {
	v := spv_rvalue(cg, index)
	return spv_u32(cg, v, index.tav.type)
}

spv_lval :: proc(cg: ^Spv_CG, expr: ^Expr) -> Spv_Lval {
	expr := unparen_expr(expr)
	#partial switch v in expr.derived_expr {
	case ^Ident:
		e := v.entity
		if e == nil {
			spv_err(cg, v.pos, "codegen_spirv: lvalue ident has no entity")
			return {}
		}
		if e.kind == .Constant && type_is_array(e.type) {
			spv_ensure_array_const(cg, e)
		}
		if ptr, ok := cg.entity_ptr[e]; ok {
			lt := e.type
			if e.semantic == .Indirect_Data {
				if elem := type_pointer_elem(e.type); elem != nil {
					lt = elem
				}
			}
			sc := spv_entity_sc(cg, e)
			aligned := sc == .PhysicalStorageBuffer
			return Spv_Lval{
				ptr = ptr,
				type = lt,
				sc = sc,
				aligned = aligned,
				align = spv_align_of(lt) if aligned else 0,
				direct = sc == .Function && !cg.entity_alias[e],
			}
		}
		spv_err(cg, v.pos, "codegen_spirv: '%s' is not an lvalue", e.name)
		return {}
	case ^Unary_Expr:
		if v.op.kind == .And {
			return spv_lval(cg, v.expr)
		}
	case ^Index_Expr:
		return spv_index_lval(cg, v)
	case ^Selector_Expr:
		return spv_selector_lval(cg, v)
	case ^Deref_Expr:
		ptr := spv_rvalue(cg, v.expr)
		elem := type_pointer_elem(v.expr.tav.type)
		if elem == nil {
			if mp, ok := v.expr.tav.type.derived.(^Type_Multi_Pointer); ok {
				elem = mp.elem
			}
		}
		zero := spv.const_u32(&cg.m, 0)
		elem_ptr_ty := spv.type_pointer(&cg.m, .PhysicalStorageBuffer, spv_type(cg, elem, .Stored))
		chain := spv.access_chain(&cg.m, elem_ptr_ty, ptr, {zero, zero})
		return Spv_Lval{ptr = chain, type = elem, sc = .PhysicalStorageBuffer, aligned = true, align = spv_align_of(elem)}
	case ^Matrix_Index_Expr:
		return spv_matrix_index_lval(cg, v)
	}
	spv_err(cg, expr.pos, "codegen_spirv: expression is not an lvalue")
	return {}
}

spv_index_lval :: proc(cg: ^Spv_CG, v: ^Index_Expr) -> Spv_Lval {
	base_t := v.expr.tav.type
	idx := spv_index_as_u32(cg, v.index)
	if type_is_slice(base_t) {
		s := spv_rvalue(cg, v.expr)
		st := base_t.derived.(^Type_Slice)
		data := spv.composite_extract(&cg.m, spv_psb_ptr(cg, st.elem, spv_expr_handle_rw(cg, v.expr)).ptr_ty, s, 0)
		if cg.bounds_check {
			ln := spv.composite_extract(&cg.m, spv.type_i64(&cg.m), s, 1)
			spv_emit_slice_bounds(cg, v.index, idx, ln)
		}
		zero := spv.const_u32(&cg.m, 0)
		elem_ptr_ty := spv.type_pointer(&cg.m, .PhysicalStorageBuffer, spv_type(cg, st.elem, .Stored))
		chain := spv.access_chain(&cg.m, elem_ptr_ty, data, {zero, idx})
		return Spv_Lval{ptr = chain, type = st.elem, sc = .PhysicalStorageBuffer, aligned = true, align = spv_align_of(st.elem)}
	}
	if type_is_multi_pointer(base_t) {
		p := spv_rvalue(cg, v.expr)
		elem := base_t.derived.(^Type_Multi_Pointer).elem
		zero := spv.const_u32(&cg.m, 0)
		elem_ptr_ty := spv.type_pointer(&cg.m, .PhysicalStorageBuffer, spv_type(cg, elem, .Stored))
		chain := spv.access_chain(&cg.m, elem_ptr_ty, p, {zero, idx})
		return Spv_Lval{ptr = chain, type = elem, sc = .PhysicalStorageBuffer, aligned = true, align = spv_align_of(elem)}
	}
	base := spv_lval(cg, v.expr)
	elem_t: ^Type
	#partial switch t in base_t.derived {
	case ^Type_Array:
		elem_t = t.elem
	case ^Type_Vector:
		elem_t = t.elem
	case:
		elem_t = v.tav.type
	}
	pty := spv.type_pointer(&cg.m, base.sc, spv_type(cg, elem_t, .Stored if base.aligned else .Func))
	chain := spv.access_chain(&cg.m, pty, base.ptr, {idx})
	return Spv_Lval{ptr = chain, type = elem_t, sc = base.sc, aligned = base.aligned, align = spv_align_of(elem_t)}
}

spv_selector_lval :: proc(cg: ^Spv_CG, v: ^Selector_Expr) -> Spv_Lval {
	base_t := v.expr.tav.type
	if spv_expr_is_indirect_data(v.expr) {
		if elem := type_pointer_elem(base_t); elem != nil {
			base_t = elem
		}
	}
	if type_is_vector(base_t) {
		base := spv_lval(cg, v.expr)
		comps := spv_swizzle_comps(v.field.name)
		if len(v.field.name) == 1 {
			idx := spv.const_u32(&cg.m, comps[0])
			elem := type_base(base_t)
			pty := spv.type_pointer(&cg.m, base.sc, spv_type(cg, elem))
			chain := spv.access_chain(&cg.m, pty, base.ptr, {idx})
			return Spv_Lval{ptr = chain, type = elem, sc = base.sc, aligned = base.aligned, align = spv_align_of(elem)}
		}
		return Spv_Lval{
			ptr = base.ptr,
			type = v.tav.type,
			sc = base.sc,
			aligned = base.aligned,
			align = base.align,
			vec = base_t,
			swizzle = comps,
		}
	}
	if type_is_pointer(base_t) && !spv_expr_is_indirect_data(v.expr) {
		ptr := spv_rvalue(cg, v.expr)
		elem := type_pointer_elem(base_t)
		st := elem.derived.(^Type_Struct)
		fi := spv_field_index_name(st, v.field.name)
		ft := st.fields.variables[fi].type
		zero := spv.const_u32(&cg.m, 0)
		member := spv.const_u32(&cg.m, u32(fi))
		elem_ptr_ty := spv.type_pointer(&cg.m, .PhysicalStorageBuffer, spv_type(cg, elem, .Stored))
		obj := spv.access_chain(&cg.m, elem_ptr_ty, ptr, {zero, zero})
		fty := spv.type_pointer(&cg.m, .PhysicalStorageBuffer, spv_type(cg, ft, .Stored))
		chain := spv.access_chain(&cg.m, fty, obj, {member})
		return Spv_Lval{ptr = chain, type = ft, sc = .PhysicalStorageBuffer, aligned = true, align = spv_align_of(ft)}
	}
	base := spv_lval(cg, v.expr)
	if st, ok := base_t.derived.(^Type_Struct); ok {
		fi := spv_field_index_name(st, v.field.name)
		ft := st.fields.variables[fi].type
		member := spv.const_u32(&cg.m, u32(fi))
		layout: Spv_Layout = .Stored if base.aligned else .Func
		pty := spv.type_pointer(&cg.m, base.sc, spv_type(cg, ft, layout))
		chain := spv.access_chain(&cg.m, pty, base.ptr, {member})
		return Spv_Lval{ptr = chain, type = ft, sc = base.sc, aligned = base.aligned, align = spv_align_of(ft)}
	}
	spv_err(cg, v.pos, "codegen_spirv: selector is not an lvalue")
	return {}
}

spv_matrix_index_lval :: proc(cg: ^Spv_CG, v: ^Matrix_Index_Expr) -> Spv_Lval {
	base := spv_lval(cg, v.expr)
	mt := v.expr.tav.type.derived.(^Type_Matrix)
	col := spv_index_as_u32(cg, v.column_index)
	row := spv_index_as_u32(cg, v.row_index)
	pty := spv.type_pointer(&cg.m, base.sc, spv_type(cg, mt.elem))
	chain := spv.access_chain(&cg.m, pty, base.ptr, {col, row})
	return Spv_Lval{ptr = chain, type = mt.elem, sc = base.sc, aligned = base.aligned, align = spv_align_of(mt.elem)}
}

spv_unary :: proc(cg: ^Spv_CG, v: ^Unary_Expr) -> spv.Id {
	if v.op.kind == .And {
		return spv_lval(cg, v.expr).ptr
	}
	x := spv_rvalue(cg, v.expr)
	ty := spv_type(cg, v.tav.type)
	src_t := v.expr.tav.type
	#partial switch v.op.kind {
	case .Sub:
		if type_is_float(type_base(src_t)) {
			return spv.fnegate(&cg.m, ty, x)
		}
		return spv.snegate(&cg.m, ty, x)
	case .Not:
		b := spv_as_bool(cg, x, src_t)
		nb := spv.logical_not(&cg.m, b)
		return spv_from_bool(cg, nb, v.tav.type)
	case .Xor:
		if type_is_bit_set(src_t) {
			bs := src_t.derived.(^Type_Bit_Set)
			bits := bs.upper - bs.lower + 1
			mask := (u64(1) << uint(bits)) - 1
			if bs.lower != 0 {
				mask <<= uint(bs.lower)
			}
			n := spv.not_(&cg.m, ty, x)
			m := spv.const_int(&cg.m, ty, mask, u32(type_sizeof(bs.underlying)*8))
			return spv.bitwise_and(&cg.m, ty, n, m)
		}
		return spv.not_(&cg.m, ty, x)
	}
	return x
}

spv_binary :: proc(cg: ^Spv_CG, v: ^Binary_Expr) -> spv.Id {
	op := v.op.kind
	if op == .Cmp_And || op == .Cmp_Or {
		return spv_logical_bin(cg, v)
	}
	l := spv_rvalue(cg, v.left)
	r := spv_rvalue(cg, v.right)
	lt := default_type(v.left.tav.type)
	rt := default_type(v.right.tav.type)
	res_t := default_type(v.tav.type)
	ty := spv_type(cg, res_t)
	lf := type_is_float(type_base(lt)) || type_is_float(type_base(rt)) || type_is_float(type_base(res_t))
	if !type_is_matrix(lt) && !type_is_matrix(rt) && type_is_vector(res_t) {
		l = spv_match_gen(cg, l, lt, res_t)
		r = spv_match_gen(cg, r, rt, res_t)
		lt = res_t
		rt = res_t
	} else if type_is_vector(lt) && !type_is_vector(rt) && !type_is_matrix(rt) {
		r = spv_match_gen(cg, r, rt, lt)
		rt = lt
	} else if type_is_vector(rt) && !type_is_vector(lt) && !type_is_matrix(lt) {
		l = spv_match_gen(cg, l, lt, rt)
		lt = rt
	}
	#partial switch op {
	case .Add:
		return spv.fadd(&cg.m, ty, l, r) if lf else spv.iadd(&cg.m, ty, l, r)
	case .Sub:
		return spv.fsub(&cg.m, ty, l, r) if lf else spv.isub(&cg.m, ty, l, r)
	case .Mul:
		return spv_mul(cg, l, r, lt, rt, res_t)
	case .Quo:
		if lf {
			return spv.fdiv(&cg.m, ty, l, r)
		}
		if spv_unsigned(lt) {
			return spv.udiv(&cg.m, ty, l, r)
		}
		return spv.sdiv(&cg.m, ty, l, r)
	case .Mod:
		if lf {
			return spv.fmod(&cg.m, ty, l, r)
		}
		if spv_unsigned(lt) {
			return spv.umod(&cg.m, ty, l, r)
		}
		return spv.srem(&cg.m, ty, l, r)
	case .And:
		return spv.bitwise_and(&cg.m, ty, l, r)
	case .Or:
		return spv.bitwise_or(&cg.m, ty, l, r)
	case .Xor:
		return spv.bitwise_xor(&cg.m, ty, l, r)
	case .And_Not:
		n := spv.not_(&cg.m, spv_type(cg, rt), r)
		return spv.bitwise_and(&cg.m, ty, l, n)
	case .Shl:
		return spv.shift_left(&cg.m, ty, l, spv_u32(cg, r, rt))
	case .Shr:
		sh := spv_u32(cg, r, rt)
		if spv_unsigned(lt) {
			return spv.shift_right_logical(&cg.m, ty, l, sh)
		}
		return spv.shift_right_arithmetic(&cg.m, ty, l, sh)
	case .Cmp_Eq, .Not_Eq, .Lt, .Gt, .Lt_Eq, .Gt_Eq:
		b := spv_compare(cg, op, l, r, lt)
		return spv_from_bool(cg, b, res_t)
	}
	spv_err(cg, v.pos, "codegen_spirv: unsupported binary %v", op)
	return l
}

spv_mul :: proc(cg: ^Spv_CG, l, r: spv.Id, lt, rt, res: ^Type) -> spv.Id {
	ty := spv_type(cg, res)
	if type_is_matrix(lt) && type_is_matrix(rt) {
		return spv.matrix_times_matrix(&cg.m, ty, l, r)
	}
	if type_is_matrix(lt) && type_is_vector(rt) {
		return spv.matrix_times_vector(&cg.m, ty, l, r)
	}
	if type_is_vector(lt) && type_is_matrix(rt) {
		return spv.vector_times_matrix(&cg.m, ty, l, r)
	}
	if type_is_matrix(lt) && type_is_float(rt) {
		s := spv_convert(cg, r, rt, type_base(lt))
		return spv.matrix_times_scalar(&cg.m, ty, l, s)
	}
	if type_is_float(lt) && type_is_matrix(rt) {
		s := spv_convert(cg, l, lt, type_base(rt))
		return spv.matrix_times_scalar(&cg.m, ty, r, s)
	}
	if type_is_vector(lt) && !type_is_vector(rt) && !type_is_matrix(rt) {
		s := spv_convert(cg, r, rt, type_base(lt))
		return spv.vector_times_scalar(&cg.m, ty, l, s)
	}
	if type_is_vector(rt) && !type_is_vector(lt) && !type_is_matrix(lt) {
		s := spv_convert(cg, l, lt, type_base(rt))
		return spv.vector_times_scalar(&cg.m, ty, r, s)
	}
	if type_is_float(type_base(lt)) {
		return spv.fmul(&cg.m, ty, l, r)
	}
	return spv.imul(&cg.m, ty, l, r)
}

spv_compare :: proc(cg: ^Spv_CG, op: Token_Kind, l, r: spv.Id, lt: ^Type) -> spv.Id {
	base := type_base(lt)
	if type_is_float(base) {
		#partial switch op {
		case .Cmp_Eq: return spv.ford_equal(&cg.m, l, r)
		case .Not_Eq: return spv.ford_not_equal(&cg.m, l, r)
		case .Lt: return spv.ford_less(&cg.m, l, r)
		case .Gt: return spv.ford_greater(&cg.m, l, r)
		case .Lt_Eq: return spv.ford_less_equal(&cg.m, l, r)
		case .Gt_Eq: return spv.ford_greater_equal(&cg.m, l, r)
		}
	}
	if spv_unsigned(base) {
		#partial switch op {
		case .Cmp_Eq: return spv.iequal(&cg.m, l, r)
		case .Not_Eq: return spv.inot_equal(&cg.m, l, r)
		case .Lt: return spv.uless_than(&cg.m, l, r)
		case .Gt: return spv.ugreater_than(&cg.m, l, r)
		case .Lt_Eq: return spv.uless_equal(&cg.m, l, r)
		case .Gt_Eq: return spv.ugreater_equal(&cg.m, l, r)
		}
	}
	#partial switch op {
	case .Cmp_Eq: return spv.iequal(&cg.m, l, r)
	case .Not_Eq: return spv.inot_equal(&cg.m, l, r)
	case .Lt: return spv.sless_than(&cg.m, l, r)
	case .Gt: return spv.sgreater_than(&cg.m, l, r)
	case .Lt_Eq: return spv.sless_equal(&cg.m, l, r)
	case .Gt_Eq: return spv.sgreater_equal(&cg.m, l, r)
	}
	return spv.const_bool(&cg.m, false)
}

spv_logical_bin :: proc(cg: ^Spv_CG, v: ^Binary_Expr) -> spv.Id {
	// Short-circuit with selection.
	res_t := default_type(v.tav.type)
	tmp := spv_fn_var(cg, res_t, "_land")
	lb := spv_as_bool(cg, spv_rvalue(cg, v.left), v.left.tav.type)
	then_b := spv.block_new(&cg.m)
	else_b := spv.block_new(&cg.m)
	merge := spv.block_new(&cg.m)
	spv.selection_merge(&cg.m, merge)
	if v.op.kind == .Cmp_And {
		spv.branch_cond(&cg.m, lb, then_b, else_b)
		spv_block(cg, then_b)
		rb := spv_as_bool(cg, spv_rvalue(cg, v.right), v.right.tav.type)
		spv.store(&cg.m, tmp, spv_from_bool(cg, rb, res_t))
		spv.branch_if_open(&cg.m, merge)
		spv_block(cg, else_b)
		spv.store(&cg.m, tmp, spv_from_bool(cg, spv.const_bool(&cg.m, false), res_t))
		spv.branch_if_open(&cg.m, merge)
	} else {
		spv.branch_cond(&cg.m, lb, then_b, else_b)
		spv_block(cg, then_b)
		spv.store(&cg.m, tmp, spv_from_bool(cg, spv.const_bool(&cg.m, true), res_t))
		spv.branch_if_open(&cg.m, merge)
		spv_block(cg, else_b)
		rb := spv_as_bool(cg, spv_rvalue(cg, v.right), v.right.tav.type)
		spv.store(&cg.m, tmp, spv_from_bool(cg, rb, res_t))
		spv.branch_if_open(&cg.m, merge)
	}
	spv_block(cg, merge)
	return spv.load(&cg.m, spv_type(cg, res_t), tmp)
}

spv_ternary :: proc(cg: ^Spv_CG, v: ^Ternary_If_Expr) -> spv.Id {
	res_t := default_type(v.tav.type)
	tmp := spv_fn_var(cg, res_t, "_sel")
	cond := spv_as_bool(cg, spv_rvalue(cg, v.cond), v.cond.tav.type)
	then_b := spv.block_new(&cg.m)
	else_b := spv.block_new(&cg.m)
	merge := spv.block_new(&cg.m)
	spv.selection_merge(&cg.m, merge)
	spv.branch_cond(&cg.m, cond, then_b, else_b)
	spv_block(cg, then_b)
	spv.store(&cg.m, tmp, spv_rvalue(cg, v.x))
	spv.branch_if_open(&cg.m, merge)
	spv_block(cg, else_b)
	spv.store(&cg.m, tmp, spv_rvalue(cg, v.y))
	spv.branch_if_open(&cg.m, merge)
	spv_block(cg, merge)
	return spv.load(&cg.m, spv_type(cg, res_t), tmp)
}

spv_comp_lit_rvalue :: proc(cg: ^Spv_CG, v: ^Comp_Lit) -> spv.Id {
	t := default_type(v.tav.type)
	if type_is_bit_set(t) && v.tav.value != nil {
		return spv_const_value(cg, t, v.tav.value)
	}
	if type_is_vector(t) || type_is_matrix(t) {
		if len(v.elems) == 0 {
			return spv_zero(cg, t)
		}
		if mt, is_mat := t.derived.(^Type_Matrix); is_mat {
			n := len(v.elems)
			if n == int(mt.rows)*int(mt.columns) {
				cols := make([]spv.Id, mt.columns, context.temp_allocator)
				k := 0
				elem_ty := spv_type(cg, mt.elem)
				col_ty := spv.type_vector(&cg.m, elem_ty, u32(mt.rows))
				for c in 0 ..< int(mt.columns) {
					parts := make([]spv.Id, mt.rows, context.temp_allocator)
					for r in 0 ..< int(mt.rows) {
						value := v.elems[k]
						if fv, is_fv := value.derived.(^Field_Value); is_fv {
							value = fv.value
						}
						parts[r] = spv_convert(cg, spv_rvalue(cg, value), value.tav.type, mt.elem)
						k += 1
					}
					cols[c] = spv.composite_construct(&cg.m, col_ty, parts)
				}
				return spv.composite_construct(&cg.m, spv_type(cg, t), cols)
			}
		}
		parts := make([]spv.Id, len(v.elems), context.temp_allocator)
		for elem, i in v.elems {
			value := elem
			if fv, is_fv := elem.derived.(^Field_Value); is_fv {
				value = fv.value
			}
			parts[i] = spv_rvalue(cg, value)
		}
		return spv.composite_construct(&cg.m, spv_type(cg, t), parts)
	}
	if st, ok := t.derived.(^Type_Struct); ok {
		n := len(st.fields.variables) if st.fields != nil else 0
		parts := make([]spv.Id, n, context.temp_allocator)
		for field, i in st.fields.variables {
			parts[i] = spv_zero(cg, field.type)
		}
		for elem, i in v.elems {
			value := elem
			idx := i
			if fv, is_fv := elem.derived.(^Field_Value); is_fv {
				value = fv.value
				if ident, iok := fv.field.derived.(^Ident); iok {
					idx = spv_field_index_name(st, ident.name)
				}
			}
			if idx >= 0 && idx < n {
				parts[idx] = spv_rvalue(cg, value)
			}
		}
		return spv.composite_construct(&cg.m, spv_type(cg, t), parts)
	}
	if arr, ok := t.derived.(^Type_Array); ok {
		parts := make([]spv.Id, arr.len, context.temp_allocator)
		z := spv_zero(cg, arr.elem)
		for i in 0 ..< arr.len {
			parts[i] = z
		}
		for elem, i in v.elems {
			value := elem
			if fv, is_fv := elem.derived.(^Field_Value); is_fv {
				value = fv.value
			}
			if i < arr.len {
				parts[i] = spv_rvalue(cg, value)
			}
		}
		return spv.composite_construct(&cg.m, spv_type(cg, t), parts)
	}
	spv_err(cg, v.pos, "codegen_spirv: unsupported compound literal")
	return spv_zero(cg, t)
}

spv_slice_expr :: proc(cg: ^Spv_CG, v: ^Slice_Expr) -> spv.Id {
	base_t := v.expr.tav.type
	res_t := default_type(v.tav.type)
	elem: ^Type
	base_is_slice := false
	#partial switch bt in base_t.derived {
	case ^Type_Multi_Pointer:
		elem = bt.elem
	case ^Type_Slice:
		elem = bt.elem
		base_is_slice = true
	case:
		spv_err(cg, v.pos, "codegen_spirv: unsupported slice expression")
		return spv_zero(cg, res_t)
	}
	base := spv_rvalue(cg, v.expr)
	rw := spv_expr_handle_rw(cg, v.expr)
	ptr_ty := spv_psb_ptr(cg, elem, rw).ptr_ty
	data: spv.Id
	if base_is_slice {
		data = spv.composite_extract(&cg.m, ptr_ty, base, 0)
	} else {
		data = base
	}
	if type_is_multi_pointer(res_t) {
		// pointer advance: data + low * stride via ConvertPtrToU
		low := spv_rvalue(cg, v.low) if v.low != nil else spv.const_i64(&cg.m, 0)
		u := spv.convert_ptr_to_u(&cg.m, spv.type_u64(&cg.m), data)
		off := spv.imul(&cg.m, spv.type_u64(&cg.m), spv_convert(cg, low, v.low.tav.type if v.low != nil else t_i64, t_u64), spv.const_u64(&cg.m, u64(type_sizeof(elem))))
		sum := spv.iadd(&cg.m, spv.type_u64(&cg.m), u, off)
		return spv.convert_u_to_ptr(&cg.m, ptr_ty, sum)
	}
	low := spv_rvalue(cg, v.low) if v.low != nil else spv.const_i64(&cg.m, 0)
	high: spv.Id
	if v.high != nil {
		high = spv_rvalue(cg, v.high)
	} else if base_is_slice {
		high = spv.composite_extract(&cg.m, spv.type_i64(&cg.m), base, 1)
	} else {
		high = low
	}
	u := spv.convert_ptr_to_u(&cg.m, spv.type_u64(&cg.m), data)
	off := spv.imul(&cg.m, spv.type_u64(&cg.m), spv_convert(cg, low, v.low.tav.type if v.low != nil else t_i64, t_u64), spv.const_u64(&cg.m, u64(type_sizeof(elem))))
	ndata := spv.convert_u_to_ptr(&cg.m, ptr_ty, spv.iadd(&cg.m, spv.type_u64(&cg.m), u, off))
	ln := spv.isub(&cg.m, spv.type_i64(&cg.m), spv_convert(cg, high, v.high.tav.type if v.high != nil else t_i64, t_i64), spv_convert(cg, low, v.low.tav.type if v.low != nil else t_i64, t_i64))
	return spv.composite_construct(&cg.m, spv_slice_type(cg, elem, .Func, rw), {ndata, ln})
}

spv_call_rvalue :: proc(cg: ^Spv_CG, v: ^Call_Expr) -> spv.Id {
	if callee := entity_from_expr(v.expr); callee != nil && callee.kind == .Builtin {
		return spv_builtin_rvalue(cg, callee.builtin_id, v)
	}
	if callee := entity_from_expr(v.expr); callee != nil && callee.kind == .Type_Name {
		return spv_type_ctor(cg, v)
	}
	fn_e := entity_from_expr(v.expr)
	if fn_e != nil && entity_is_poly_const(fn_e) && fn_e.aliased_of != nil {
		fn_e = fn_e.aliased_of
	}
	if fn_e == nil {
		spv_err(cg, v.pos, "codegen_spirv: call has no callee")
		return spv_zero(cg, v.tav.type)
	}
	fn_id, fok := cg.fn_id[fn_e]
	if !fok {
		spv_err(cg, v.pos, "codegen_spirv: callee '%s' was not emitted", fn_e.name)
		return spv_zero(cg, v.tav.type)
	}
	pt := fn_e.type.derived.(^Type_Proc)
	args := make([dynamic]spv.Id, context.temp_allocator)
	copies := make([dynamic]Spv_Ref_Copy, context.temp_allocator)
	for param, i in pt.params.variables {
		if entity_is_poly_const(param) || type_is_string_kind(param.type) do continue
		if i >= len(v.args) do break
		arg := v.args[i]
		if .Ref in param.flags {
			append(&args, spv_ref_arg(cg, arg, &copies))
		} else {
			append(&args, spv_expr_to_owner(cg, arg, fn_e))
		}
	}
	results := pt.results.variables
	if len(results) > 1 {
		for i in 0 ..< len(results) - 1 {
			tmp := spv_fn_var(cg, results[i].type, results[i].name if results[i].name != "" else "_out")
			append(&args, tmp)
		}
	}
	ret_t := t_invalid
	if len(results) > 0 {
		ret_t = results[len(results)-1].type
	}
	ret: spv.Id
	if len(results) == 0 {
		_ = spv.call(&cg.m, spv.type_void(&cg.m), fn_id, args[:])
		ret = spv.NONE
	} else {
		ret = spv.call(&cg.m, spv_type_for_proc(cg, ret_t, fn_e), fn_id, args[:])
	}
	spv_ref_copyback(cg, copies[:])
	return ret
}

spv_live_dest :: proc(d: ^Entity) -> bool {
	return d != nil && d.kind != .Dummy && d.name != "_"
}

spv_ref_arg :: proc(cg: ^Spv_CG, expr: ^Expr, copies: ^[dynamic]Spv_Ref_Copy) -> spv.Id {
	l := spv_lval(cg, expr)
	if l.direct && l.sc == .Function && l.ptr != spv.NONE {
		return l.ptr
	}
	tmp := spv_fn_var(cg, l.type, "_ref")
	if l.ptr != spv.NONE {
		spv.store(&cg.m, tmp, spv_load_ptr(cg, l))
	}
	append(copies, Spv_Ref_Copy{tmp = tmp, dest = l})
	return tmp
}

spv_ref_copyback :: proc(cg: ^Spv_CG, copies: []Spv_Ref_Copy) {
	for cb in copies {
		loaded := spv.load(&cg.m, spv_type(cg, cb.dest.type, .Stored if cb.dest.aligned else .Func), cb.tmp)
		spv_store_ptr(cg, cb.dest, loaded)
	}
}

spv_type_ctor :: proc(cg: ^Spv_CG, v: ^Call_Expr) -> spv.Id {
	dest := v.tav.type
	if dest == nil {
		return spv.NONE
	}
	if type_is_vector(dest) {
		vt := dest.derived.(^Type_Vector)
		elems := make([dynamic]spv.Id, context.temp_allocator)
		for arg in v.args {
			if arg == nil do continue
			if type_is_vector(arg.tav.type) {
				av := arg.tav.type.derived.(^Type_Vector)
				src := spv_rvalue(cg, arg)
				elem_ty := spv_type(cg, av.elem)
				for i in 0 ..< int(av.len) {
					ex := spv.composite_extract(&cg.m, elem_ty, src, u32(i))
					append(&elems, spv_convert(cg, ex, av.elem, vt.elem))
				}
			} else {
				append(&elems, spv_convert(cg, spv_rvalue(cg, arg), arg.tav.type, vt.elem))
			}
		}
		if len(elems) == 1 && int(vt.len) > 1 {
			return spv_splat(cg, dest, elems[0])
		}
		return spv.composite_construct(&cg.m, spv_type(cg, dest), elems[:])
	}
	if type_is_matrix(dest) {
		mt := dest.derived.(^Type_Matrix)
		if len(v.args) == 1 {
			return spv_convert(cg, spv_rvalue(cg, v.args[0]), v.args[0].tav.type, dest)
		}
		cols := make([]spv.Id, mt.columns, context.temp_allocator)
		k := 0
		elem_ty := spv_type(cg, mt.elem)
		col_ty := spv.type_vector(&cg.m, elem_ty, u32(mt.rows))
		for c in 0 ..< int(mt.columns) {
			parts := make([]spv.Id, mt.rows, context.temp_allocator)
			for r in 0 ..< int(mt.rows) {
				parts[r] = spv_convert(cg, spv_rvalue(cg, v.args[k]), v.args[k].tav.type, mt.elem)
				k += 1
			}
			cols[c] = spv.composite_construct(&cg.m, col_ty, parts)
		}
		return spv.composite_construct(&cg.m, spv_type(cg, dest), cols)
	}
	if len(v.args) == 1 {
		return spv_convert(cg, spv_rvalue(cg, v.args[0]), v.args[0].tav.type, dest)
	}
	spv_err(cg, v.pos, "codegen_spirv: unsupported type constructor '%s'", string_from_type(dest))
	return spv_zero(cg, dest)
}

spv_builtin_rvalue :: proc(cg: ^Spv_CG, id: Builtin_Proc, call: ^Call_Expr) -> spv.Id {
	#partial switch id {
	case .len:
		if len(call.args) == 1 && type_is_slice(call.args[0].tav.type) {
			s := spv_rvalue(cg, call.args[0])
			return spv.composite_extract(&cg.m, spv.type_i64(&cg.m), s, 1)
		}
		if len(call.args) == 1 && type_is_string_kind(call.args[0].tav.type) {
			s, ok := spv_const_string(call.args[0])
			n := 0
			if ok {
				n = len(s)
			}
			return spv_const_value(cg, call.tav.type, exact_int(i128(n)))
		}
	case .card:
		a := spv_rvalue(cg, call.args[0])
		return spv.bitcount(&cg.m, spv_type(cg, call.tav.type), a)
	case .modf:
		return spv_modf_frexp_value(cg, call, .modf)
	case .frexp:
		return spv_modf_frexp_value(cg, call, .frexp)
	case .matrix_comp_mult:
		return spv_matrix_comp_mult(cg, call)
	case .sample:
		return spv_sample(cg, call)
	case .load:
		return spv_image_load(cg, call)
	case .dim:
		return spv_image_dim(cg, call)
	case .fmag_exec:
		return spv_fmag_exec_value(cg, call)
	case .rayquery_proceed:
		rq := spv_ray_query_ptr(cg, call.args[0])
		b := spv.ray_query_proceed(&cg.m, rq)
		return spv_from_bool(cg, b, call.tav.type)
	case .rayquery_result:
		return spv_ray_query_hit(cg, call, true)
	case .rayquery_candidate:
		return spv_ray_query_hit(cg, call, false)
	}
	if builtin_is_wave(id) {
		return spv_wave_rvalue(cg, id, call)
	}
	return spv_glsl450_or_core(cg, id, call)
}

spv_glsl450_or_core :: proc(cg: ^Spv_CG, id: Builtin_Proc, call: ^Call_Expr) -> spv.Id {
	res_t := default_type(call.tav.type)
	ty := spv_type(cg, res_t)
	arg :: proc(cg: ^Spv_CG, call: ^Call_Expr, i: int) -> spv.Id {
		return spv_rvalue(cg, call.args[i])
	}
	g := proc(cg: ^Spv_CG, ty: spv.Id, inst: spv.Glsl450, call: ^Call_Expr, n: int) -> spv.Id {
		as := make([]spv.Id, n, context.temp_allocator)
		for i in 0 ..< n {
			as[i] = spv_rvalue(cg, call.args[i])
		}
		return spv.glsl450(&cg.m, ty, inst, as)
	}
	#partial switch id {
	case .radians: return g(cg, ty, .Radians, call, 1)
	case .degrees: return g(cg, ty, .Degrees, call, 1)
	case .sin: return g(cg, ty, .Sin, call, 1)
	case .cos: return g(cg, ty, .Cos, call, 1)
	case .tan: return g(cg, ty, .Tan, call, 1)
	case .asin: return g(cg, ty, .Asin, call, 1)
	case .acos: return g(cg, ty, .Acos, call, 1)
	case .atan: return g(cg, ty, .Atan, call, 1)
	case .atan2: return g(cg, ty, .Atan2, call, 2)
	case .sinh: return g(cg, ty, .Sinh, call, 1)
	case .cosh: return g(cg, ty, .Cosh, call, 1)
	case .tanh: return g(cg, ty, .Tanh, call, 1)
	case .asinh: return g(cg, ty, .Asinh, call, 1)
	case .acosh: return g(cg, ty, .Acosh, call, 1)
	case .atanh: return g(cg, ty, .Atanh, call, 1)
	case .pow:
		a0 := spv_match_gen(cg, arg(cg, call, 0), call.args[0].tav.type, res_t)
		a1 := spv_match_gen(cg, arg(cg, call, 1), call.args[1].tav.type, res_t)
		return spv.glsl450(&cg.m, ty, .Pow, {a0, a1})
	case .fma:
		a0 := spv_match_gen(cg, arg(cg, call, 0), call.args[0].tav.type, res_t)
		a1 := spv_match_gen(cg, arg(cg, call, 1), call.args[1].tav.type, res_t)
		a2 := spv_match_gen(cg, arg(cg, call, 2), call.args[2].tav.type, res_t)
		return spv.glsl450(&cg.m, ty, .Fma, {a0, a1, a2})
	case .exp: return g(cg, ty, .Exp, call, 1)
	case .log: return g(cg, ty, .Log, call, 1)
	case .exp2: return g(cg, ty, .Exp2, call, 1)
	case .log2: return g(cg, ty, .Log2, call, 1)
	case .sqrt: return g(cg, ty, .Sqrt, call, 1)
	case .isqrt: return g(cg, ty, .InverseSqrt, call, 1)
	case .floor: return g(cg, ty, .Floor, call, 1)
	case .trunc: return g(cg, ty, .Trunc, call, 1)
	case .round: return g(cg, ty, .Round, call, 1)
	case .round_even: return g(cg, ty, .RoundEven, call, 1)
	case .ceil: return g(cg, ty, .Ceil, call, 1)
	case .fract: return g(cg, ty, .Fract, call, 1)
	case .ldexp: return g(cg, ty, .Ldexp, call, 2)
	case .step:
		edge := arg(cg, call, 0)
		x := arg(cg, call, 1)
		if type_is_vector(res_t) && !type_is_vector(call.args[0].tav.type) {
			edge = spv_splat(cg, res_t, edge)
		}
		return spv.glsl450(&cg.m, ty, .Step, {edge, x})
	case .smoothstep:
		a0 := arg(cg, call, 0)
		a1 := arg(cg, call, 1)
		a2 := arg(cg, call, 2)
		if type_is_vector(res_t) {
			if !type_is_vector(call.args[0].tav.type) {
				a0 = spv_splat(cg, res_t, a0)
			}
			if !type_is_vector(call.args[1].tav.type) {
				a1 = spv_splat(cg, res_t, a1)
			}
		}
		return spv.glsl450(&cg.m, ty, .SmoothStep, {a0, a1, a2})
	case .lerp:
		a := arg(cg, call, 0)
		b := arg(cg, call, 1)
		t := arg(cg, call, 2)
		if type_is_vector(res_t) && !type_is_vector(call.args[2].tav.type) {
			t = spv_splat(cg, res_t, t)
		}
		return spv.glsl450(&cg.m, ty, .FMix, {a, b, t})
	case .mag: return g(cg, ty, .Length, call, 1)
	case .dist: return g(cg, ty, .Distance, call, 2)
	case .normalize: return g(cg, ty, .Normalize, call, 1)
	case .facefoward: return g(cg, ty, .FaceForward, call, 3)
	case .reflect: return g(cg, ty, .Reflect, call, 2)
	case .refract: return g(cg, ty, .Refract, call, 3)
	case .cross: return g(cg, ty, .Cross, call, 2)
	case .determinant: return g(cg, ty, .Determinant, call, 1)
	case .inverse: return g(cg, ty, .MatrixInverse, call, 1)
	case .transpose:
		return spv.transpose(&cg.m, ty, arg(cg, call, 0))
	case .outer_product:
		return spv.outer_product(&cg.m, ty, arg(cg, call, 0), arg(cg, call, 1))
	case .dot:
		return spv.dot(&cg.m, ty, arg(cg, call, 0), arg(cg, call, 1))
	case .dFdx: return spv.dpdx(&cg.m, ty, arg(cg, call, 0))
	case .dFdy: return spv.dpdy(&cg.m, ty, arg(cg, call, 0))
	case .fwidth: return spv.fwidth(&cg.m, ty, arg(cg, call, 0))
	case .is_nan:
		return spv_from_bool(cg, spv.is_nan(&cg.m, arg(cg, call, 0)), res_t)
	case .is_inf:
		return spv_from_bool(cg, spv.is_inf(&cg.m, arg(cg, call, 0)), res_t)
	case .f32_from_u32_bits:
		return spv.bitcast(&cg.m, spv.type_f32(&cg.m), arg(cg, call, 0))
	case .u32_from_f32_bits:
		return spv.bitcast(&cg.m, spv.type_u32(&cg.m), arg(cg, call, 0))
	case .abs:
		a0 := arg(cg, call, 0)
		if type_is_float(type_base(res_t)) {
			return spv.glsl450(&cg.m, ty, .FAbs, {a0})
		}
		return spv.glsl450(&cg.m, ty, .SAbs, {a0})
	case .sign:
		a0 := arg(cg, call, 0)
		if type_is_float(type_base(res_t)) {
			return spv.glsl450(&cg.m, ty, .FSign, {a0})
		}
		return spv.glsl450(&cg.m, ty, .SSign, {a0})
	case .min, .max, .clamp:
		return spv_minmax(cg, id, call, ty, res_t)
	case .mod:
		a0 := spv_match_gen(cg, arg(cg, call, 0), call.args[0].tav.type, res_t)
		a1 := spv_match_gen(cg, arg(cg, call, 1), call.args[1].tav.type, res_t)
		return spv.fmod(&cg.m, ty, a0, a1)
	}
	spv_err(cg, call.pos, "codegen_spirv: unimplemented builtin %v", id)
	return spv_zero(cg, res_t)
}

spv_match_gen :: proc(cg: ^Spv_CG, v: spv.Id, src_t, dest_t: ^Type) -> spv.Id {
	dest := default_type(dest_t)
	src := default_type(src_t)
	if dest == nil {
		return v
	}
	if type_is_vector(dest) && !type_is_vector(src) {
		elem := type_base(dest)
		s := v
		if src != nil && !type_eq(src, elem) {
			s = spv_convert(cg, v, src, elem)
		}
		return spv_splat(cg, dest, s)
	}
	if src != nil && dest != nil && !type_eq(src, dest) {
		return spv_convert(cg, v, src, dest)
	}
	return v
}

spv_minmax :: proc(cg: ^Spv_CG, id: Builtin_Proc, call: ^Call_Expr, ty: spv.Id, res_t: ^Type) -> spv.Id {
	flt := type_is_float(type_base(res_t))
	uns := spv_unsigned(res_t)
	inst_min: spv.Glsl450 = .FMin if flt else (.UMin if uns else .SMin)
	inst_max: spv.Glsl450 = .FMax if flt else (.UMax if uns else .SMax)
	inst_cl: spv.Glsl450 = .FClamp if flt else (.UClamp if uns else .SClamp)
	argn :: proc(cg: ^Spv_CG, call: ^Call_Expr, i: int, res_t: ^Type) -> spv.Id {
		return spv_match_gen(cg, spv_rvalue(cg, call.args[i]), call.args[i].tav.type, res_t)
	}
	if id == .clamp {
		return spv.glsl450(&cg.m, ty, inst_cl, {argn(cg, call, 0, res_t), argn(cg, call, 1, res_t), argn(cg, call, 2, res_t)})
	}
	inst := inst_min if id == .min else inst_max
	acc := argn(cg, call, 0, res_t)
	for i in 1 ..< len(call.args) {
		acc = spv.glsl450(&cg.m, ty, inst, {acc, argn(cg, call, i, res_t)})
	}
	return acc
}

spv_modf_frexp_parts :: proc(cg: ^Spv_CG, call: ^Call_Expr, id: Builtin_Proc) -> (last, first: spv.Id, first_t: ^Type) {
	x := spv_rvalue(cg, call.args[0])
	xt := default_type(call.args[0].tav.type)
	x_ty := spv_type(cg, xt)
	if id == .modf {
		st := spv.type_struct(&cg.m, {x_ty, x_ty}, fmt.tprintf("modf:%d", x_ty))
		s := spv.glsl450(&cg.m, st, .ModfStruct, {x})
		return spv.composite_extract(&cg.m, x_ty, s, 0), spv.composite_extract(&cg.m, x_ty, s, 1), xt
	}
	exp_t := t_i32
	if vt, ok := xt.derived.(^Type_Vector); ok {
		exp_t = vec_type(t_i32, int(vt.len))
	}
	e_ty := spv_type(cg, exp_t)
	st := spv.type_struct(&cg.m, {x_ty, e_ty}, fmt.tprintf("frexp:%d", x_ty))
	s := spv.glsl450(&cg.m, st, .FrexpStruct, {x})
	return spv.composite_extract(&cg.m, x_ty, s, 0), spv.composite_extract(&cg.m, e_ty, s, 1), exp_t
}

spv_modf_frexp_value :: proc(cg: ^Spv_CG, call: ^Call_Expr, id: Builtin_Proc) -> spv.Id {
	last, _, _ := spv_modf_frexp_parts(cg, call, id)
	return last
}

spv_modf_frexp_into :: proc(cg: ^Spv_CG, dests: []^Entity, call: ^Call_Expr, id: Builtin_Proc) {
	last, first, first_t := spv_modf_frexp_parts(cg, call, id)
	if len(dests) > 0 && spv_live_dest(dests[0]) {
		if _, ok := cg.entity_ptr[dests[0]]; !ok {
			cg.entity_ptr[dests[0]] = spv_fn_var(cg, dests[0].type, dests[0].name)
		}
		spv.store(&cg.m, cg.entity_ptr[dests[0]], spv_convert(cg, first, first_t, dests[0].type))
	}
	if len(dests) > 1 && spv_live_dest(dests[1]) {
		if _, ok := cg.entity_ptr[dests[1]]; !ok {
			cg.entity_ptr[dests[1]] = spv_fn_var(cg, dests[1].type, dests[1].name)
		}
		spv.store(&cg.m, cg.entity_ptr[dests[1]], last)
	} else if len(dests) == 1 && spv_live_dest(dests[0]) {
		_ = last
	}
	_ = first_t
}

spv_matrix_comp_mult :: proc(cg: ^Spv_CG, call: ^Call_Expr) -> spv.Id {
	res_t := default_type(call.tav.type)
	mt, ok := res_t.derived.(^Type_Matrix)
	if !ok || len(call.args) < 2 {
		return spv_zero(cg, res_t)
	}
	l := spv_rvalue(cg, call.args[0])
	r := spv_rvalue(cg, call.args[1])
	col_t := vec_type(mt.elem, int(mt.rows))
	col_ty := spv_type(cg, col_t)
	cols := make([]spv.Id, mt.columns, context.temp_allocator)
	for c in 0 ..< int(mt.columns) {
		lc := spv.composite_extract(&cg.m, col_ty, l, u32(c))
		rc := spv.composite_extract(&cg.m, col_ty, r, u32(c))
		cols[c] = spv.fmul(&cg.m, col_ty, lc, rc)
	}
	return spv.composite_construct(&cg.m, spv_type(cg, res_t), cols)
}

cg_bounds_from_flags :: proc(current: bool, flags: Node_State_Flags) -> bool {
	if .No_Bounds_Check in flags {
		return false
	} else if .Bounds_Check in flags {
		return true
	}
	return current
}
