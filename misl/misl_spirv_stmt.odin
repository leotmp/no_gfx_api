package misl

import "core:fmt"
import "core:reflect"

import spv "spirv"

spv_stmt :: proc(cg: ^Spv_CG, stmt: ^Stmt) {
	if stmt == nil || spv.is_terminated(&cg.m) do return
	saved := cg.bounds_check
	cg.bounds_check = cg_bounds_from_flags(cg.bounds_check, stmt.state_flags)
	defer cg.bounds_check = saved
	spv_debug_line(cg, stmt.pos)
	#partial switch v in stmt.derived {
	case ^Value_Decl:
		spv_value_decl(cg, v)
	case ^Assign_Stmt:
		spv_assign(cg, v)
	case ^If_Stmt:
		spv_if(cg, v)
	case ^For_Stmt:
		spv_for(cg, v)
	case ^Range_Stmt:
		spv_range(cg, v)
	case ^Switch_Stmt:
		spv_switch(cg, v)
	case ^When_Stmt:
		spv_when(cg, v)
	case ^Which_Stmt:
		taken := which_taken_clause_from_tav(v)
		if taken != nil {
			for s in taken.body {
				spv_stmt(cg, s)
			}
		}
	case ^Return_Stmt:
		spv_return(cg, v)
	case ^Branch_Stmt:
		#partial switch v.tok.kind {
		case .Discard:
			spv.kill(&cg.m)
		case .Break:
			if len(cg.break_stk) == 0 {
				spv_err(cg, v.pos, "codegen_spirv: break outside loop/switch")
				return
			}
			spv.branch(&cg.m, cg.break_stk[len(cg.break_stk)-1])
		case .Continue:
			if len(cg.cont_stk) == 0 {
				spv_err(cg, v.pos, "codegen_spirv: continue outside loop")
				return
			}
			spv.branch(&cg.m, cg.cont_stk[len(cg.cont_stk)-1])
		}
	case ^Block_Stmt:
		for s in v.stmts {
			spv_stmt(cg, s)
		}
	case ^Expr_Stmt:
		if call, ok := v.expr.derived.(^Call_Expr); ok {
			if callee := entity_from_expr(call.expr); callee != nil && callee.kind == .Builtin {
				#partial switch callee.builtin_id {
				case .printf, .printfln:
					spv_printf(cg, call, callee.builtin_id == .printfln)
					return
				case .assert, .panic:
					spv_assert_or_panic(cg, call, callee.builtin_id)
					return
				case .fmag_exec:
					spv_fmag_exec_call(cg, call, nil, nil)
					return
				case .store:
					spv_image_store(cg, call)
					return
				case .rayquery_accept:
					rq := spv_ray_query_ptr(cg, call.args[0])
					spv.ray_query_confirm(&cg.m, rq)
					return
				case .barrier:
					spv.control_barrier(&cg.m, .Workgroup, .Workgroup, u32(spv.Memory_Semantics.AcquireRelease) | u32(spv.Memory_Semantics.WorkgroupMemory) | u32(spv.Memory_Semantics.UniformMemory) | u32(spv.Memory_Semantics.ImageMemory))
					return
				case .memory_barrier:
					spv.memory_barrier(&cg.m, .Device, u32(spv.Memory_Semantics.AcquireRelease) | u32(spv.Memory_Semantics.UniformMemory) | u32(spv.Memory_Semantics.WorkgroupMemory) | u32(spv.Memory_Semantics.ImageMemory))
					return
				case .memory_barrier_shared:
					spv.memory_barrier(&cg.m, .Workgroup, u32(spv.Memory_Semantics.AcquireRelease) | u32(spv.Memory_Semantics.WorkgroupMemory))
					return
				case .memory_barrier_buffer:
					spv.memory_barrier(&cg.m, .Device, u32(spv.Memory_Semantics.AcquireRelease) | u32(spv.Memory_Semantics.UniformMemory))
					return
				case .memory_barrier_image:
					spv.memory_barrier(&cg.m, .Device, u32(spv.Memory_Semantics.AcquireRelease) | u32(spv.Memory_Semantics.ImageMemory))
					return
				case .group_memory_barrier:
					spv.memory_barrier(&cg.m, .Workgroup, u32(spv.Memory_Semantics.AcquireRelease) | u32(spv.Memory_Semantics.WorkgroupMemory) | u32(spv.Memory_Semantics.UniformMemory) | u32(spv.Memory_Semantics.ImageMemory))
					return
				}
			}
			_ = spv_rvalue(cg, call)
		}
	case ^Using_Stmt:
	case:
		spv_err(cg, stmt.pos, "codegen_spirv: unsupported statement %v", reflect.union_variant_typeid(stmt.derived))
	}
}

spv_value_decl :: proc(cg: ^Spv_CG, v: ^Value_Decl) {
	if len(v.values) == 1 && len(v.names) > 1 {
		if call, ok := v.values[0].derived.(^Call_Expr); ok {
			dests := make([]^Entity, len(v.names), context.temp_allocator)
			for name, i in v.names {
				ident := name.derived.(^Ident)
				dests[i] = ident.entity
			}
			spv_call_into_ents(cg, dests, call)
			return
		}
	}
	for name, i in v.names {
		ident := name.derived.(^Ident)
		var := ident.entity
		if var == nil do continue
		if var.kind == .Dummy || var.name == "_" do continue
		if type_is_string_kind(var.type) do continue
		#partial switch var.kind {
		case .Constant, .Type_Name, .Procedure, .Entry, .Pipeline:
			continue
		}
		if .Shared in var.flags do continue
		ptr := spv_fn_var(cg, var.type, spv_debug_name(var) if var.name != "" else "_v", pos = var.pos)
		cg.entity_ptr[var] = ptr
		has_init := i < len(v.values)
		if type_is_ray_query(var.type) {
			if has_init {
				if id, call, ok := spv_expr_builtin(v.values[i]); ok && id == .rayquery_init {
					spv_ray_query_init(cg, ptr, call)
				}
			}
		} else if !has_init && .No_Init not_in var.flags {
			spv.store(&cg.m, ptr, spv_zero(cg, var.type))
		} else if has_init && .No_Init not_in var.flags {
			if call_is_fmag_exec(v.values[i]) {
				call := v.values[i].derived.(^Call_Expr)
				spv_fmag_exec_call(cg, call, {ptr}, {var.type})
			} else if id, call, ok := spv_expr_builtin(v.values[i]); ok && id == .rayquery_init {
				spv_ray_query_init(cg, ptr, call)
			} else {
				spv.store(&cg.m, ptr, spv_expr_to_owner(cg, v.values[i], nil))
			}
		}
	}
}

spv_assign :: proc(cg: ^Spv_CG, v: ^Assign_Stmt) {
	if len(v.rhs) == 1 && len(v.lhs) > 1 {
		if call, ok := v.rhs[0].derived.(^Call_Expr); ok {
			spv_call_into_exprs(cg, v.lhs, call)
			return
		}
	}
	if len(v.lhs) != 1 || len(v.rhs) != 1 {
		spv_err(cg, v.pos, "codegen_spirv: unsupported multi-assign")
		return
	}
	if ident, ok := v.lhs[0].derived.(^Ident); ok && ident.name == "_" {
		_ = spv_rvalue(cg, v.rhs[0])
		return
	}
	if id, call, ok := spv_expr_builtin(v.rhs[0]); ok && id == .rayquery_init {
		l := spv_lval(cg, v.lhs[0])
		spv_ray_query_init(cg, l.ptr, call)
		return
	}
	if call_is_fmag_exec(v.rhs[0]) {
		l := spv_lval(cg, v.lhs[0])
		spv_fmag_exec_call(cg, v.rhs[0].derived.(^Call_Expr), {l.ptr}, {l.type})
		return
	}
	l := spv_lval(cg, v.lhs[0])
	rhs := spv_expr_to_owner(cg, v.rhs[0], nil)
	#partial switch v.op.kind {
	case .Eq:
		spv_store_ptr(cg, l, rhs)
	case .Add_Eq, .Sub_Eq, .Mul_Eq, .Quo_Eq, .Mod_Eq, .And_Eq, .Or_Eq, .Xor_Eq, .And_Not_Eq, .Shl_Eq, .Shr_Eq:
		cur := spv_load_ptr(cg, l)
		bin := spv_assign_op(cg, v.op.kind, cur, rhs, l.type, v.rhs[0].tav.type)
		spv_store_ptr(cg, l, bin)
	case .Cmp_And_Eq, .Cmp_Or_Eq:
		cur := spv_load_ptr(cg, l)
		lb := spv_as_bool(cg, cur, l.type)
		rb := spv_as_bool(cg, rhs, v.rhs[0].tav.type)
		b := spv.logical_and(&cg.m, lb, rb) if v.op.kind == .Cmp_And_Eq else spv.logical_or(&cg.m, lb, rb)
		spv_store_ptr(cg, l, spv_from_bool(cg, b, l.type))
	}
}

spv_assign_op :: proc(cg: ^Spv_CG, op: Token_Kind, l, r: spv.Id, lt, rt: ^Type) -> spv.Id {
	ty := spv_type(cg, lt)
	lf := type_is_float(type_base(lt))
	rhs := r
	rt := rt
	if type_is_vector(lt) && !type_is_vector(rt) && !type_is_matrix(rt) {
		rhs = spv_match_gen(cg, r, rt, lt)
		rt = lt
	}
	#partial switch op {
	case .Add_Eq: return spv.fadd(&cg.m, ty, l, rhs) if lf else spv.iadd(&cg.m, ty, l, rhs)
	case .Sub_Eq: return spv.fsub(&cg.m, ty, l, rhs) if lf else spv.isub(&cg.m, ty, l, rhs)
	case .Mul_Eq: return spv_mul(cg, l, rhs, lt, rt, lt)
	case .Quo_Eq:
		if lf do return spv.fdiv(&cg.m, ty, l, rhs)
		if spv_unsigned(lt) do return spv.udiv(&cg.m, ty, l, rhs)
		return spv.sdiv(&cg.m, ty, l, rhs)
	case .Mod_Eq:
		if lf do return spv.fmod(&cg.m, ty, l, rhs)
		if spv_unsigned(lt) do return spv.umod(&cg.m, ty, l, rhs)
		return spv.srem(&cg.m, ty, l, rhs)
	case .And_Eq: return spv.bitwise_and(&cg.m, ty, l, rhs)
	case .Or_Eq: return spv.bitwise_or(&cg.m, ty, l, rhs)
	case .Xor_Eq: return spv.bitwise_xor(&cg.m, ty, l, rhs)
	case .And_Not_Eq:
		n := spv.not_(&cg.m, ty, rhs)
		return spv.bitwise_and(&cg.m, ty, l, n)
	case .Shl_Eq: return spv.shift_left(&cg.m, ty, l, spv_u32(cg, rhs, rt))
	case .Shr_Eq:
		sh := spv_u32(cg, rhs, rt)
		if spv_unsigned(lt) do return spv.shift_right_logical(&cg.m, ty, l, sh)
		return spv.shift_right_arithmetic(&cg.m, ty, l, sh)
	}
	return l
}

spv_if :: proc(cg: ^Spv_CG, v: ^If_Stmt) {
	if v.init != nil {
		spv_stmt(cg, v.init)
	}
	cond := spv_as_bool(cg, spv_rvalue(cg, v.cond), v.cond.tav.type)
	then_b := spv.block_new(&cg.m)
	else_b := spv.block_new(&cg.m)
	merge := spv.block_new(&cg.m)
	has_else := v.else_stmt != nil
	spv.selection_merge(&cg.m, merge)
	spv.branch_cond(&cg.m, cond, then_b, else_b if has_else else merge)
	spv_block(cg, then_b)
	spv_stmt(cg, v.body)
	spv.branch_if_open(&cg.m, merge)
	if has_else {
		spv_block(cg, else_b)
		spv_stmt(cg, v.else_stmt)
		spv.branch_if_open(&cg.m, merge)
	}
	spv_block(cg, merge)
}

spv_for :: proc(cg: ^Spv_CG, v: ^For_Stmt) {
	if v.init != nil {
		spv_stmt(cg, v.init)
	}
	header := spv.block_new(&cg.m)
	body := spv.block_new(&cg.m)
	cont := spv.block_new(&cg.m)
	merge := spv.block_new(&cg.m)
	spv.branch_if_open(&cg.m, header)
	spv_block(cg, header)
	if v.cond != nil {
		c := spv_as_bool(cg, spv_rvalue(cg, v.cond), v.cond.tav.type)
		spv.loop_merge(&cg.m, merge, cont)
		spv.branch_cond(&cg.m, c, body, merge)
	} else {
		spv.loop_merge(&cg.m, merge, cont)
		spv.branch(&cg.m, body)
	}
	append(&cg.break_stk, merge)
	append(&cg.cont_stk, cont)
	spv_block(cg, body)
	spv_stmt(cg, v.body)
	spv.branch_if_open(&cg.m, cont)
	pop(&cg.break_stk)
	pop(&cg.cont_stk)
	spv_block(cg, cont)
	if v.post != nil {
		spv_stmt(cg, v.post)
	}
	spv.branch_if_open(&cg.m, header)
	spv_block(cg, merge)
}

spv_range :: proc(cg: ^Spv_CG, v: ^Range_Stmt) {
	if expr_is_range(v.expr) {
		binary := v.expr.derived.(^Binary_Expr)
		iter_t := default_type(v.expr.tav.type)
		iter_e := range_val_entity(v.vals[0]) if len(v.vals) > 0 else nil
		iter_ptr: spv.Id
		if iter_e != nil {
			iter_ptr = spv_fn_var(cg, iter_e.type, iter_e.name)
			cg.entity_ptr[iter_e] = iter_ptr
		} else {
			iter_ptr = spv_fn_var(cg, iter_t, "_i")
		}
		exclusive := binary.op.kind == .Range_Exclusive
		lo := spv_rvalue(cg, binary.left)
		hi := spv_rvalue(cg, binary.right)
		if v.reverse {
			start := hi
			if exclusive {
				one := spv_const_value(cg, iter_t, exact_int(1))
				start = spv.isub(&cg.m, spv_type(cg, iter_t), hi, one)
			}
			spv.store(&cg.m, iter_ptr, start)
		} else {
			spv.store(&cg.m, iter_ptr, lo)
		}
		header := spv.block_new(&cg.m)
		body := spv.block_new(&cg.m)
		cont := spv.block_new(&cg.m)
		merge := spv.block_new(&cg.m)
		spv.branch(&cg.m, header)
		spv_block(cg, header)
		iv := spv.load(&cg.m, spv_type(cg, iter_t), iter_ptr)
		cmp: spv.Id
		if v.reverse {
			cmp = spv_compare(cg, .Gt_Eq, iv, lo, iter_t)
		} else if exclusive {
			cmp = spv_compare(cg, .Lt, iv, hi, iter_t)
		} else {
			cmp = spv_compare(cg, .Lt_Eq, iv, hi, iter_t)
		}
		spv.loop_merge(&cg.m, merge, cont)
		spv.branch_cond(&cg.m, cmp, body, merge)
		append(&cg.break_stk, merge)
		append(&cg.cont_stk, cont)
		spv_block(cg, body)
		spv_stmt(cg, v.body)
		spv.branch_if_open(&cg.m, cont)
		pop(&cg.break_stk)
		pop(&cg.cont_stk)
		spv_block(cg, cont)
		cur := spv.load(&cg.m, spv_type(cg, iter_t), iter_ptr)
		one := spv_const_value(cg, iter_t, exact_int(1))
		nxt := spv.isub(&cg.m, spv_type(cg, iter_t), cur, one) if v.reverse else spv.iadd(&cg.m, spv_type(cg, iter_t), cur, one)
		spv.store(&cg.m, iter_ptr, nxt)
		spv.branch_if_open(&cg.m, header)
		spv_block(cg, merge)
		return
	}
	// array / slice range
	elem_t: ^Type
	is_slice := false
	array_len := 0
	#partial switch t in v.expr.tav.type.derived {
	case ^Type_Slice:
		elem_t = t.elem
		is_slice = true
	case ^Type_Array:
		elem_t = t.elem
		array_len = t.len
	case:
		spv_err(cg, v.expr.pos, "codegen_spirv: unsupported range type")
		return
	}
	idx_e: ^Entity
	val_e: ^Entity
	if len(v.vals) == 1 {
		val_e = range_val_entity(v.vals[0])
	} else if len(v.vals) >= 2 {
		val_e = range_val_entity(v.vals[0])
		idx_e = range_val_entity(v.vals[1])
	}
	idx_ptr: spv.Id
	if idx_e != nil {
		idx_ptr = spv_fn_var(cg, idx_e.type, idx_e.name)
		cg.entity_ptr[idx_e] = idx_ptr
	} else {
		idx_ptr = spv_fn_var(cg, t_i64, "_i")
	}
	is_ref := val_e != nil && .Range_Ref in val_e.flags
	val_ptr: spv.Id
	if val_e != nil && !is_ref {
		val_ptr = spv_fn_var(cg, val_e.type, val_e.name)
		cg.entity_ptr[val_e] = val_ptr
	}
	slice_val: spv.Id
	slice_rw := false
	if is_slice {
		slice_val = spv_rvalue(cg, v.expr)
		slice_rw = spv_expr_handle_rw(cg, v.expr)
	}
	if v.reverse {
		if is_slice {
			ln := spv.composite_extract(&cg.m, spv.type_i64(&cg.m), slice_val, 1)
			spv.store(&cg.m, idx_ptr, spv.isub(&cg.m, spv.type_i64(&cg.m), ln, spv.const_i64(&cg.m, 1)))
		} else {
			spv.store(&cg.m, idx_ptr, spv.const_i64(&cg.m, i64(array_len-1)))
		}
	} else {
		spv.store(&cg.m, idx_ptr, spv.const_i64(&cg.m, 0))
	}
	header := spv.block_new(&cg.m)
	body := spv.block_new(&cg.m)
	cont := spv.block_new(&cg.m)
	merge := spv.block_new(&cg.m)
	spv.branch(&cg.m, header)
	spv_block(cg, header)
	iv := spv.load(&cg.m, spv.type_i64(&cg.m), idx_ptr)
	cmp: spv.Id
	if v.reverse {
		cmp = spv.sgreater_equal(&cg.m, iv, spv.const_i64(&cg.m, 0))
	} else if is_slice {
		ln := spv.composite_extract(&cg.m, spv.type_i64(&cg.m), slice_val, 1)
		cmp = spv.sless_than(&cg.m, iv, ln)
	} else {
		cmp = spv.sless_than(&cg.m, iv, spv.const_i64(&cg.m, i64(array_len)))
	}
	spv.loop_merge(&cg.m, merge, cont)
	spv.branch_cond(&cg.m, cmp, body, merge)
	append(&cg.break_stk, merge)
	append(&cg.cont_stk, cont)
	spv_block(cg, body)
	if val_e != nil {
		idx_u := spv.sconvert(&cg.m, spv.type_u32(&cg.m), iv)
		if is_slice {
			st := v.expr.tav.type.derived.(^Type_Slice)
			data := spv.composite_extract(&cg.m, spv_psb_ptr(cg, st.elem, slice_rw).ptr_ty, slice_val, 0)
			if is_ref {
				chain := spv_psb_elem_ptr(cg, data, st.elem, idx_u)
				cg.entity_ptr[val_e] = chain
				cg.entity_sc[val_e] = .PhysicalStorageBuffer
				cg.entity_val_ty[val_e] = spv_type(cg, st.elem, .Stored)
				if val_e.name != "" {
					spv.name(&cg.m, chain, val_e.name)
				}
				cg.entity_alias[val_e] = true
			} else {
				spv.store(&cg.m, val_ptr, spv_psb_index(cg, data, st.elem, idx_u))
			}
		} else {
			base := spv_lval(cg, v.expr)
			layout: Spv_Layout = .Stored if base.aligned else .Func
			pty := spv.type_pointer(&cg.m, base.sc, spv_type(cg, elem_t, layout))
			ch := spv.access_chain(&cg.m, pty, base.ptr, {idx_u})
			if is_ref {
				cg.entity_ptr[val_e] = ch
				cg.entity_sc[val_e] = base.sc
				if base.aligned {
					cg.entity_val_ty[val_e] = spv_type(cg, elem_t, .Stored)
				}
				if val_e.name != "" {
					spv.name(&cg.m, ch, val_e.name)
				}
				cg.entity_alias[val_e] = true
			} else {
				loaded := spv.load(&cg.m, spv_type(cg, elem_t, layout), ch)
				if base.aligned {
					loaded = spv_change_layout(cg, loaded, elem_t, .Stored, .Func)
				}
				spv.store(&cg.m, val_ptr, loaded)
			}
		}
	}
	spv_stmt(cg, v.body)
	spv.branch_if_open(&cg.m, cont)
	pop(&cg.break_stk)
	pop(&cg.cont_stk)
	spv_block(cg, cont)
	cur := spv.load(&cg.m, spv.type_i64(&cg.m), idx_ptr)
	one := spv.const_i64(&cg.m, 1)
	nxt := spv.isub(&cg.m, spv.type_i64(&cg.m), cur, one) if v.reverse else spv.iadd(&cg.m, spv.type_i64(&cg.m), cur, one)
	spv.store(&cg.m, idx_ptr, nxt)
	spv.branch_if_open(&cg.m, header)
	spv_block(cg, merge)
}

spv_switch :: proc(cg: ^Spv_CG, v: ^Switch_Stmt) {
	if v.init != nil {
		spv_stmt(cg, v.init)
	}
	if v.cond == nil {
		spv_switch_bool(cg, v)
		return
	}
	tag := spv_rvalue(cg, v.cond)
	tag_t := default_type(v.cond.tav.type)
	sel_t := tag_t
	if et, is_enum := tag_t.derived.(^Type_Enum); is_enum {
		sel_t = et.base_type
	}
	sel := spv_u32(cg, tag, sel_t)
	body, ok := v.body.derived.(^Block_Stmt)
	if !ok do return
	clauses := make([dynamic]^Case_Clause, context.temp_allocator)
	for clause_stmt in body.stmts {
		clause, is_clause := clause_stmt.derived.(^Case_Clause)
		if is_clause {
			append(&clauses, clause)
		}
	}
	thens := make([]spv.Id, len(clauses), context.temp_allocator)
	for i in 0 ..< len(clauses) {
		thens[i] = spv.block_new(&cg.m)
	}
	default_blk := spv.NONE
	pairs := make([dynamic]spv.Switch_Case, context.temp_allocator)
	for clause, ci in clauses {
		if len(clause.list) == 0 {
			default_blk = thens[ci]
			continue
		}
		for expr in clause.list {
			n := exact_value_to_i128(expr.tav.value)
			append(&pairs, spv.Switch_Case{value = u32(i64(n)), label = thens[ci]})
		}
	}
	merge := spv.block_new(&cg.m)
	if default_blk == spv.NONE {
		default_blk = spv.block_new(&cg.m)
	}
	append(&cg.break_stk, merge)
	spv.selection_merge(&cg.m, merge)
	spv.switch_u32(&cg.m, sel, default_blk, pairs[:])
	for clause, ci in clauses {
		spv_block(cg, thens[ci])
		falls := false
		for s in clause.body {
			if stmt_is_fallthrough(s) {
				falls = true
				continue
			}
			spv_stmt(cg, s)
		}
		if falls && ci + 1 < len(clauses) {
			spv.branch_if_open(&cg.m, thens[ci + 1])
		} else {
			spv.branch_if_open(&cg.m, merge)
		}
	}
	if default_blk != spv.NONE {
		used := false
		for clause in clauses {
			if len(clause.list) == 0 {
				used = true
				break
			}
		}
		if !used {
			spv_block(cg, default_blk)
			spv.branch_if_open(&cg.m, merge)
		}
	}
	pop(&cg.break_stk)
	spv_block(cg, merge)
}

spv_switch_bool :: proc(cg: ^Spv_CG, v: ^Switch_Stmt) {
	body, ok := v.body.derived.(^Block_Stmt)
	if !ok do return
	matched_ptr := spv_fn_var(cg, t_b32, "_sw")
	fall_ptr := spv_fn_var(cg, t_b32, "_sw_fall")
	spv.store(&cg.m, matched_ptr, spv_zero(cg, t_b32))
	spv.store(&cg.m, fall_ptr, spv_zero(cg, t_b32))
	ran := spv_fn_var(cg, t_u32, "_sw_once")
	spv.store(&cg.m, ran, spv.const_u32(&cg.m, 1))
	loop_hdr := spv.block_new(&cg.m)
	inner := spv.block_new(&cg.m)
	cont := spv.block_new(&cg.m)
	merge := spv.block_new(&cg.m)
	spv.branch(&cg.m, loop_hdr)
	spv_block(cg, loop_hdr)
	flag := spv.load(&cg.m, spv.type_u32(&cg.m), ran)
	take_loop := spv.inot_equal(&cg.m, flag, spv.const_u32(&cg.m, 0))
	spv.loop_merge(&cg.m, merge, cont)
	spv.branch_cond(&cg.m, take_loop, inner, merge)
	spv_block(cg, inner)
	spv.store(&cg.m, ran, spv.const_u32(&cg.m, 0))
	append(&cg.break_stk, merge)
	for clause_stmt in body.stmts {
		clause, is_clause := clause_stmt.derived.(^Case_Clause)
		if !is_clause do continue
		then_b := spv.block_new(&cg.m)
		else_b := spv.block_new(&cg.m)
		already := spv_as_bool(cg, spv.load(&cg.m, spv_type(cg, t_b32), matched_ptr), t_b32)
		falling := spv_as_bool(cg, spv.load(&cg.m, spv_type(cg, t_b32), fall_ptr), t_b32)
		take: spv.Id
		if len(clause.list) == 0 {
			take = spv.logical_or(&cg.m, spv.logical_not(&cg.m, already), falling)
		} else {
			acc := spv.const_bool(&cg.m, false)
			for expr in clause.list {
				acc = spv.logical_or(&cg.m, acc, spv_as_bool(cg, spv_rvalue(cg, expr), expr.tav.type))
			}
			take = spv.logical_or(&cg.m, falling, spv.logical_and(&cg.m, spv.logical_not(&cg.m, already), acc))
		}
		spv.selection_merge(&cg.m, else_b)
		spv.branch_cond(&cg.m, take, then_b, else_b)
		spv_block(cg, then_b)
		spv.store(&cg.m, matched_ptr, spv_from_bool(cg, spv.const_bool(&cg.m, true), t_b32))
		spv.store(&cg.m, fall_ptr, spv_from_bool(cg, spv.const_bool(&cg.m, false), t_b32))
		for s in clause.body {
			if stmt_is_fallthrough(s) {
				spv.store(&cg.m, fall_ptr, spv_from_bool(cg, spv.const_bool(&cg.m, true), t_b32))
				continue
			}
			spv_stmt(cg, s)
		}
		spv.branch_if_open(&cg.m, else_b)
		spv_block(cg, else_b)
	}
	spv.branch_if_open(&cg.m, cont)
	pop(&cg.break_stk)
	spv_block(cg, cont)
	spv.branch(&cg.m, loop_hdr)
	spv_block(cg, merge)
}

spv_when :: proc(cg: ^Spv_CG, v: ^When_Stmt) {
	if b, ok := v.cond.tav.value.(bool); ok {
		if b {
			if block, is_block := v.body.derived.(^Block_Stmt); is_block {
				for s in block.stmts do spv_stmt(cg, s)
			} else {
				spv_stmt(cg, v.body)
			}
		} else if v.else_stmt != nil {
			if else_when, wok := v.else_stmt.derived.(^When_Stmt); wok {
				spv_when(cg, else_when)
			} else if block, is_block := v.else_stmt.derived.(^Block_Stmt); is_block {
				for s in block.stmts do spv_stmt(cg, s)
			} else {
				spv_stmt(cg, v.else_stmt)
			}
		}
	}
}

spv_return :: proc(cg: ^Spv_CG, v: ^Return_Stmt) {
	proc_t := cg.curr_proc
	if proc_t == nil {
		spv_err(cg, v.pos, "return outside procedure")
		return
	}
	stage, is_stage := proc_t.stage.?
	if is_stage {
		if stage == .Compute {
			spv.return_void(&cg.m)
			return
		}
		if len(v.results) == 0 {
			if proc_t.results != nil {
				for result in proc_t.results.variables {
					spv_unpack_stage_result(cg, result)
				}
			}
			spv.return_void(&cg.m)
			return
		}
		result_entity := proc_t.results.variables[0]
		result_expr := v.results[0]
		if ident, ok := result_expr.derived.(^Ident); ok && ident.entity == result_entity {
			spv_unpack_stage_result(cg, result_entity)
		} else {
			if ptr, pok := cg.entity_ptr[result_entity]; pok {
				spv.store(&cg.m, ptr, spv_rvalue(cg, result_expr))
			}
			spv_unpack_stage_result(cg, result_entity)
		}
		spv.return_void(&cg.m)
		return
	}
	results := proc_t.results.variables
	if len(results) == 0 {
		spv.return_void(&cg.m)
		return
	}
	if len(v.results) == 0 {
		// naked return
		if cg.return_ptr != spv.NONE {
			spv.return_value(&cg.m, spv.load(&cg.m, spv_type_for_proc(cg, results[len(results)-1].type, cg.curr_entity), cg.return_ptr))
			return
		}
		spv.return_void(&cg.m)
		return
	}
	if len(results) > 1 {
		for i in 0 ..< len(results) - 1 {
			if i < len(cg.out_ptrs) {
				spv.store(&cg.m, cg.out_ptrs[i], spv_rvalue(cg, v.results[i]))
			}
		}
		last := spv_expr_to_owner(cg, v.results[len(v.results)-1], cg.curr_entity)
		spv.return_value(&cg.m, last)
		return
	}
	spv.return_value(&cg.m, spv_expr_to_owner(cg, v.results[0], cg.curr_entity))
}

spv_call_into_ents :: proc(cg: ^Spv_CG, dests: []^Entity, call: ^Call_Expr) {
	if call_is_fmag_exec(call) {
		ptrs := make([]spv.Id, len(dests), context.temp_allocator)
		types := make([]^Type, len(dests), context.temp_allocator)
		for d, i in dests {
			if d == nil do continue
			if _, ok := cg.entity_ptr[d]; !ok {
				cg.entity_ptr[d] = spv_fn_var(cg, d.type, d.name)
			}
			ptrs[i] = cg.entity_ptr[d]
			types[i] = d.type
		}
		spv_fmag_exec_call(cg, call, ptrs, types)
		return
	}
	// Evaluate call; multi-return uses out-params.
	fn_e := entity_from_expr(call.expr)
	if fn_e != nil && entity_is_poly_const(fn_e) && fn_e.aliased_of != nil {
		fn_e = fn_e.aliased_of
	}
	if fn_e == nil || fn_e.kind == .Builtin {
		if fn_e != nil && (fn_e.builtin_id == .modf || fn_e.builtin_id == .frexp) {
			spv_modf_frexp_into(cg, dests, call, fn_e.builtin_id)
			return
		}
		if len(dests) > 0 && spv_live_dest(dests[0]) {
			if _, ok := cg.entity_ptr[dests[0]]; !ok {
				cg.entity_ptr[dests[0]] = spv_fn_var(cg, dests[0].type, dests[0].name)
			}
			spv.store(&cg.m, cg.entity_ptr[dests[0]], spv_rvalue(cg, call))
		}
		return
	}
	pt := fn_e.type.derived.(^Type_Proc)
	args := make([dynamic]spv.Id, context.temp_allocator)
	copies := make([dynamic]Spv_Ref_Copy, context.temp_allocator)
	for param, i in pt.params.variables {
		if entity_is_poly_const(param) || type_is_string_kind(param.type) do continue
		if i >= len(call.args) do break
		arg := call.args[i]
		if .Ref in param.flags {
			append(&args, spv_ref_arg(cg, arg, &copies))
		} else {
			append(&args, spv_rvalue(cg, arg))
		}
	}
	results := pt.results.variables
	if len(results) > 1 {
		for i in 0 ..< len(results) - 1 {
			d := dests[i] if i < len(dests) else nil
			if spv_live_dest(d) {
				if _, ok := cg.entity_ptr[d]; !ok {
					cg.entity_ptr[d] = spv_fn_var(cg, d.type, d.name)
				}
				append(&args, cg.entity_ptr[d])
			} else {
				append(&args, spv_fn_var(cg, results[i].type, "_out"))
			}
		}
	}
	last_i := len(results) - 1
	ret := spv.call(&cg.m, spv_type(cg, results[last_i].type), cg.fn_id[fn_e], args[:])
	spv_ref_copyback(cg, copies[:])
	if last_i < len(dests) && spv_live_dest(dests[last_i]) {
		if _, ok := cg.entity_ptr[dests[last_i]]; !ok {
			cg.entity_ptr[dests[last_i]] = spv_fn_var(cg, dests[last_i].type, dests[last_i].name)
		}
		spv.store(&cg.m, cg.entity_ptr[dests[last_i]], ret)
	}
}

spv_call_into_exprs :: proc(cg: ^Spv_CG, dests: []^Expr, call: ^Call_Expr) {
	ents := make([]^Entity, len(dests), context.temp_allocator)
	all_ident := true
	for d, i in dests {
		if ident, ok := unparen_expr(d).derived.(^Ident); ok && ident.entity != nil {
			ents[i] = ident.entity
		} else {
			all_ident = false
		}
	}
	if all_ident {
		spv_call_into_ents(cg, ents, call)
		return
	}
	val := spv_rvalue(cg, call)
	if len(dests) > 0 && !expr_is_blank_ident(dests[0]) {
		spv_store_ptr(cg, spv_lval(cg, dests[0]), val)
	}
}

range_val_entity :: proc(expr: ^Expr) -> ^Entity {
	expr := unparen_expr(expr)
	if u, ok := expr.derived.(^Unary_Expr); ok && u.op.kind == .And {
		expr = unparen_expr(u.expr)
	}
	ident, ok := expr.derived.(^Ident)
	if !ok || ident.entity == nil || ident.entity.kind == .Dummy {
		return nil
	}
	return ident.entity
}

spv_emit_proc :: proc(cg: ^Spv_CG, e: ^Entity) {
	if e == nil || e.proc_lit == nil || e.type == nil do return
	pt := e.type.derived.(^Type_Proc)
	if proc_is_generic_template(pt) do return
	saved_proc := cg.curr_proc
	saved_ent := cg.curr_entity
	cg.curr_proc = pt
	cg.curr_entity = e
	defer {
		cg.curr_proc = saved_proc
		cg.curr_entity = saved_ent
	}

	param_tys := make([dynamic]spv.Id, context.temp_allocator)
	param_ents := make([dynamic]^Entity, context.temp_allocator)
	for param in pt.params.variables {
		if entity_is_poly_const(param) || type_is_string_kind(param.type) do continue
		if .Ref in param.flags {
			append(&param_tys, spv_ptr_ty(cg, .Function, param.type))
		} else {
			append(&param_tys, spv_type_for_proc(cg, param.type, e))
		}
		append(&param_ents, param)
	}
	results := pt.results.variables
	if len(results) > 1 {
		for i in 0 ..< len(results) - 1 {
			append(&param_tys, spv.type_pointer(&cg.m, .Function, spv_type_for_proc(cg, results[i].type, e)))
		}
	}
	ret_ty := spv.type_void(&cg.m)
	if len(results) > 0 {
		ret_ty = spv_type_for_proc(cg, results[len(results)-1].type, e)
	}
	fn_ty := spv.type_function(&cg.m, ret_ty, param_tys[:])
	fn_id, has := cg.fn_id[e]
	if !has {
		fn_id = spv.NONE
	}
	id := spv.fn_begin(&cg.m, ret_ty, fn_ty, id = fn_id)
	cg.fn_id[e] = id
	spv.name(&cg.m, id, spv_debug_name(e))

	clear(&cg.out_ptrs)
	cg.return_ptr = spv.NONE
	for pent in param_ents {
		val_ty := spv_type_for_proc(cg, pent.type, e) if .Ref not_in pent.flags else spv_ptr_ty(cg, .Function, pent.type)
		pid := spv.fn_param(&cg.m, val_ty)
		spv.name(&cg.m, pid, pent.name)
		if .Ref in pent.flags {
			cg.entity_ptr[pent] = pid
		} else {
			cg.entity_ptr[pent] = pid
			cg.entity_val_ty[pent] = val_ty
		}
	}
	if len(results) > 1 {
		for i in 0 ..< len(results) - 1 {
			val_ty := spv_type_for_proc(cg, results[i].type, e)
			pid := spv.fn_param(&cg.m, spv.type_pointer(&cg.m, .Function, val_ty))
			append(&cg.out_ptrs, pid)
			if results[i].name != "" {
				cg.entity_ptr[results[i]] = pid
				cg.entity_val_ty[results[i]] = val_ty
			}
		}
	}

	ret_dbg: ^Type = nil
	if len(results) > 0 {
		ret_dbg = results[len(results)-1].type
	}
	dbg_fn := spv_debug_function(cg, e, param_ents[:], ret_dbg)
	saved_dbg := cg.dbg_cur_fn
	cg.dbg_cur_fn = dbg_fn
	defer cg.dbg_cur_fn = saved_dbg

	spv_fn_start(cg, spv.block_new(&cg.m), dbg_fn, id, false)
	spv_debug_line(cg, e.pos)
	arg_n: u32 = 0
	for pent in param_ents {
		if .Ref in pent.flags do continue
		src := cg.entity_ptr[pent]
		val_ty := cg.entity_val_ty[pent]
		loc := spv_fn_var_of(cg, val_ty, pent.name)
		spv.store(&cg.m, loc, src)
		cg.entity_ptr[pent] = loc
		arg_n += 1
		spv_debug_declare(cg, loc, pent.type, pent.name, pent.pos, arg_n)
	}
	if len(results) == 1 && results[0].name != "" {
		val_ty := spv_type_for_proc(cg, results[0].type, e)
		cg.return_ptr = spv_fn_var_of(cg, val_ty, results[0].name)
		cg.entity_ptr[results[0]] = cg.return_ptr
		cg.entity_val_ty[results[0]] = val_ty
		_, _, is_handle := spv_device_handle_elem(results[0].type)
		spv.store(&cg.m, cg.return_ptr, spv.const_null(&cg.m, val_ty) if is_handle else spv_zero(cg, results[0].type))
		spv_debug_declare(cg, cg.return_ptr, results[0].type, results[0].name, results[0].pos)
	} else if len(results) > 1 {
		last := results[len(results)-1]
		if last.name != "" {
			val_ty := spv_type_for_proc(cg, last.type, e)
			cg.return_ptr = spv_fn_var_of(cg, val_ty, last.name)
			cg.entity_ptr[last] = cg.return_ptr
			cg.entity_val_ty[last] = val_ty
			spv.store(&cg.m, cg.return_ptr, spv_zero(cg, last.type))
			spv_debug_declare(cg, cg.return_ptr, last.type, last.name, last.pos)
		}
	}

	body := e.proc_lit.body.derived.(^Block_Stmt).stmts
	if spv_stmts_use_fmag_exec(body) {
		arr_t := new_type(Type_Array)
		arr_t.elem = t_f32
		arr_t.len = FMAG_REGS
		cg.fmag_r = spv_fn_var(cg, arr_t, "_fmag_r")
	}
	for s in body {
		spv_stmt(cg, s)
	}
	if !spv.is_terminated(&cg.m) {
		if len(results) == 0 {
			spv.return_void(&cg.m)
		} else if cg.return_ptr != spv.NONE {
			spv.return_value(&cg.m, spv.load(&cg.m, ret_ty, cg.return_ptr))
		} else {
			spv.return_value(&cg.m, spv_zero(cg, results[len(results)-1].type))
		}
	}
	spv.fn_end(&cg.m)
}

spv_emit_entry :: proc(cg: ^Spv_CG, e: ^Entity) {
	pt := e.type.derived.(^Type_Proc)
	saved_proc := cg.curr_proc
	saved_ent := cg.curr_entity
	cg.curr_proc = pt
	cg.curr_entity = e
	defer {
		cg.curr_proc = saved_proc
		cg.curr_entity = saved_ent
	}
	void_t := spv.type_void(&cg.m)
	fn_ty := spv.type_function(&cg.m, void_t, {})
	fn := spv.fn_begin(&cg.m, void_t, fn_ty)
	ep_name := e.name if cg.named_entry else "main"
	spv.name(&cg.m, fn, e.name)
	model: spv.Execution_Model
	switch cg.stage {
	case .Vertex: model = .Vertex
	case .Fragment: model = .Fragment
	case .Compute: model = .GLCompute
	}
	cg.ep = spv.entry_point(&cg.m, model, fn, ep_name)
	if cg.stage == .Fragment {
		spv.execution_mode(&cg.m, fn, .OriginUpperLeft)
	}
	if cg.stage == .Compute {
		if cg.compat == .No_Gfx {
			x := spv.spec_const_int(&cg.m, spv.type_u32(&cg.m), u64(pt.local_size[0]), 32)
			y := spv.spec_const_int(&cg.m, spv.type_u32(&cg.m), u64(pt.local_size[1]), 32)
			z := spv.spec_const_int(&cg.m, spv.type_u32(&cg.m), u64(pt.local_size[2]), 32)
			spv.decorate(&cg.m, x, .SpecId, NO_GFX_LOCAL_SIZE_X_ID)
			spv.decorate(&cg.m, y, .SpecId, NO_GFX_LOCAL_SIZE_Y_ID)
			spv.decorate(&cg.m, z, .SpecId, NO_GFX_LOCAL_SIZE_Z_ID)
			spv.name(&cg.m, x, "local_size_x")
			spv.name(&cg.m, y, "local_size_y")
			spv.name(&cg.m, z, "local_size_z")
			spv.execution_mode_id(&cg.m, fn, .LocalSizeId, u32(x), u32(y), u32(z))
		} else {
			spv.execution_mode(&cg.m, fn, .LocalSize, pt.local_size[0], pt.local_size[1], pt.local_size[2])
		}
	}

	spv_emit_entry_io(cg, e, pt)
	spv_flush_iface(cg)
	dbg_fn := spv_debug_function(cg, e, {}, nil)
	saved_dbg := cg.dbg_cur_fn
	cg.dbg_cur_fn = dbg_fn
	defer cg.dbg_cur_fn = saved_dbg
	spv_fn_start(cg, spv.block_new(&cg.m), dbg_fn, fn, true)
	spv_debug_line(cg, e.pos)
	spv_emit_entry_prolog(cg, e, pt)
	body := e.proc_lit.body.derived.(^Block_Stmt).stmts
	if spv_stmts_use_fmag_exec(body) {
		arr_t := new_type(Type_Array)
		arr_t.elem = t_f32
		arr_t.len = FMAG_REGS
		cg.fmag_r = spv_fn_var(cg, arr_t, "_fmag_r")
	}
	for s in body {
		spv_stmt(cg, s)
	}
	if !spv.is_terminated(&cg.m) {
		if pt.results != nil && cg.stage != .Compute {
			for result in pt.results.variables {
				spv_unpack_stage_result(cg, result)
			}
		}
		spv.return_void(&cg.m)
	}
	spv.fn_end(&cg.m)
}

spv_expr_uses_fmag_exec :: proc(expr: ^Expr) -> bool {
	if expr == nil do return false
	if call_is_fmag_exec(expr) do return true
	#partial switch v in expr.derived_expr {
	case ^Proc_Lit:
		return false
	case ^Ellipsis:
		return spv_expr_uses_fmag_exec(v.expr)
	case ^Comp_Lit:
		if spv_expr_uses_fmag_exec(v.type) do return true
		for e in v.elems {
			if spv_expr_uses_fmag_exec(e) do return true
		}
		return spv_expr_uses_fmag_exec(v.tag)
	case ^Tag_Expr:
		return spv_expr_uses_fmag_exec(v.expr)
	case ^Unary_Expr:
		return spv_expr_uses_fmag_exec(v.expr)
	case ^Paren_Expr:
		return spv_expr_uses_fmag_exec(v.expr)
	case ^Deref_Expr:
		return spv_expr_uses_fmag_exec(v.expr)
	case ^Auto_Cast:
		return spv_expr_uses_fmag_exec(v.expr)
	case ^Binary_Expr:
		return spv_expr_uses_fmag_exec(v.left) || spv_expr_uses_fmag_exec(v.right)
	case ^Selector_Expr:
		return spv_expr_uses_fmag_exec(v.expr)
	case ^Implicit_Selector_Expr:
		return false
	case ^Selector_Call_Expr:
		if spv_expr_uses_fmag_exec(v.expr) do return true
		if v.call == nil do return false
		if spv_expr_uses_fmag_exec(v.call.expr) do return true
		for a in v.call.args {
			if spv_expr_uses_fmag_exec(a) do return true
		}
		return false
	case ^Index_Expr:
		return spv_expr_uses_fmag_exec(v.expr) || spv_expr_uses_fmag_exec(v.index)
	case ^Slice_Expr:
		return spv_expr_uses_fmag_exec(v.expr) || spv_expr_uses_fmag_exec(v.low) || spv_expr_uses_fmag_exec(v.high)
	case ^Matrix_Index_Expr:
		return spv_expr_uses_fmag_exec(v.expr) || spv_expr_uses_fmag_exec(v.row_index) || spv_expr_uses_fmag_exec(v.column_index)
	case ^Call_Expr:
		if spv_expr_uses_fmag_exec(v.expr) do return true
		for a in v.args {
			if spv_expr_uses_fmag_exec(a) do return true
		}
	case ^Field_Value:
		return spv_expr_uses_fmag_exec(v.field) || spv_expr_uses_fmag_exec(v.value)
	case ^Ternary_If_Expr:
		return spv_expr_uses_fmag_exec(v.x) || spv_expr_uses_fmag_exec(v.cond) || spv_expr_uses_fmag_exec(v.y)
	case ^Ternary_When_Expr:
		return spv_expr_uses_fmag_exec(v.x) || spv_expr_uses_fmag_exec(v.cond) || spv_expr_uses_fmag_exec(v.y)
	case ^Type_Cast:
		return spv_expr_uses_fmag_exec(v.type) || spv_expr_uses_fmag_exec(v.expr)
	}
	return false
}

spv_stmt_uses_fmag_exec :: proc(stmt: ^Stmt) -> bool {
	if stmt == nil do return false
	#partial switch v in stmt.derived_stmt {
	case ^Expr_Stmt:
		return spv_expr_uses_fmag_exec(v.expr)
	case ^Tag_Stmt:
		return spv_stmt_uses_fmag_exec(v.stmt)
	case ^Assign_Stmt:
		for e in v.lhs {
			if spv_expr_uses_fmag_exec(e) do return true
		}
		for e in v.rhs {
			if spv_expr_uses_fmag_exec(e) do return true
		}
	case ^Block_Stmt:
		for s in v.stmts {
			if spv_stmt_uses_fmag_exec(s) do return true
		}
	case ^If_Stmt:
		return spv_stmt_uses_fmag_exec(v.init) || spv_expr_uses_fmag_exec(v.cond) || spv_stmt_uses_fmag_exec(v.body) || spv_stmt_uses_fmag_exec(v.else_stmt)
	case ^When_Stmt:
		return spv_expr_uses_fmag_exec(v.cond) || spv_stmt_uses_fmag_exec(v.body) || spv_stmt_uses_fmag_exec(v.else_stmt)
	case ^Which_Stmt:
		return spv_expr_uses_fmag_exec(v.cond) || spv_stmt_uses_fmag_exec(v.body)
	case ^Return_Stmt:
		for e in v.results {
			if spv_expr_uses_fmag_exec(e) do return true
		}
	case ^For_Stmt:
		return spv_stmt_uses_fmag_exec(v.init) || spv_expr_uses_fmag_exec(v.cond) || spv_stmt_uses_fmag_exec(v.post) || spv_stmt_uses_fmag_exec(v.body)
	case ^Range_Stmt:
		for e in v.vals {
			if spv_expr_uses_fmag_exec(e) do return true
		}
		return spv_expr_uses_fmag_exec(v.expr) || spv_stmt_uses_fmag_exec(v.body)
	case ^Case_Clause:
		for e in v.list {
			if spv_expr_uses_fmag_exec(e) do return true
		}
		for s in v.body {
			if spv_stmt_uses_fmag_exec(s) do return true
		}
	case ^Switch_Stmt:
		return spv_stmt_uses_fmag_exec(v.init) || spv_expr_uses_fmag_exec(v.cond) || spv_stmt_uses_fmag_exec(v.body)
	case ^Using_Stmt:
		for e in v.list {
			if spv_expr_uses_fmag_exec(e) do return true
		}
	case ^Value_Decl:
		if spv_expr_uses_fmag_exec(v.type) do return true
		for e in v.values {
			if spv_expr_uses_fmag_exec(e) do return true
		}
	}
	return false
}

spv_stmts_use_fmag_exec :: proc(stmts: []^Stmt) -> bool {
	for s in stmts {
		if spv_stmt_uses_fmag_exec(s) do return true
	}
	return false
}
