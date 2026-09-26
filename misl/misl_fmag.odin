package misl

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

import fmag "fmag"

// Matches core:fmag.REGS. Do not raise this — shrink the kernel instead.
FMAG_REGS :: 16

Fmag_CG :: struct {
	b:         ^fmag.IR_Builder,
	fn:        ^fmag.IR_Function,
	module:    ^Module,
	slots:     map[^Entity][]^fmag.IR_Value,
	vec_expr:  map[^Entity]^Expr,
	vec_cache: map[^Entity][]^fmag.IR_Value,
	horiz:     map[^Call_Expr][]^fmag.IR_Value,
	helpers:   map[^Entity]^fmag.IR_Function,
	work_lane:   int, // -1 = all components; >=0 = one SIMD lane (keeps peak live down)
	ok:          bool,
	returned:    bool,
	div_ready:   bool,
	inline_dest: []^fmag.IR_Value, // non-nil while inlining a helper: return writes here, not ir_ret
}

fmag_flatten_count :: proc(tuple: ^Type_Tuple) -> int {
	if tuple == nil do return 0
	n := 0
	for v in tuple.variables {
		if v == nil || v.type == nil do continue
		if entity_is_poly_const(v) do continue
		w := fmag_width(v.type)
		n += w if w > 0 else 1
	}
	return n
}

fmag_width :: proc(type: ^Type) -> int {
	if type == nil do return 0
	type := default_type(type)
	if type_is_boolean(type) || type_is_float(type) do return 1
	if v, ok := type.derived.(^Type_Vector); ok {
		elem := default_type(v.elem)
		if type_is_boolean(elem) || type_is_float(elem) {
			return v.len
		}
	}
	return 0
}

fmag_err :: proc(cg: ^Fmag_CG, format: string, args: ..any) {
	cg.ok = false
	fmt.eprintf("compile_fmag_entry: ")
	fmt.eprintfln(format, ..args)
}

fmag_clone :: proc(vals: []^fmag.IR_Value) -> []^fmag.IR_Value {
	out := make([]^fmag.IR_Value, len(vals), context.temp_allocator)
	copy(out, vals)
	return out
}

// When work_lane is set, only one vector component is live. Naive three-wide
// lowering of shade() peaked at 19 registers; core:fmag.REGS is 16.
fmag_narrow :: proc(cg: ^Fmag_CG, vals: []^fmag.IR_Value) -> []^fmag.IR_Value {
	if !cg.ok || vals == nil do return vals
	if cg.work_lane < 0 || len(vals) <= 1 do return vals
	if cg.work_lane >= len(vals) {
		fmag_err(cg, "lane %d out of range for width %d", cg.work_lane, len(vals))
		return nil
	}
	return fmag_one(vals[cg.work_lane])
}

fmag_with_all_lanes :: proc(cg: ^Fmag_CG, expr: ^Expr) -> []^fmag.IR_Value {
	saved := cg.work_lane
	cg.work_lane = -1
	vals := fmag_expr(cg, expr)
	cg.work_lane = saved
	return vals
}

fmag_bind :: proc(cg: ^Fmag_CG, e: ^Entity, vals: []^fmag.IR_Value) {
	if e == nil || e.name == "_" do return
	cg.slots[e] = fmag_clone(vals)
}

fmag_bind_unpacked :: proc(cg: ^Fmag_CG, names: []^Expr, rhs: []^fmag.IR_Value) {
	off := 0
	for name in names {
		ident, iok := unparen_expr(name).derived.(^Ident)
		if !iok || ident.entity == nil {
			fmag_err(cg, "unpack target is not an identifier")
			return
		}
		n := fmag_width(ident.entity.type)
		if n <= 0 {
			fmag_err(cg, "local '%s' is not an FMAG value", ident.name)
			return
		}
		if off + n > len(rhs) {
			fmag_err(cg, "not enough values to unpack into '%s'", ident.name)
			return
		}
		fmag_bind(cg, ident.entity, rhs[off:off + n])
		off += n
	}
	if off != len(rhs) {
		fmag_err(cg, "unpack count mismatch (%d names / %d scalars)", off, len(rhs))
	}
}

fmag_one :: proc(v: ^fmag.IR_Value) -> []^fmag.IR_Value {
	out := make([]^fmag.IR_Value, 1, context.temp_allocator)
	out[0] = v
	return out
}

fmag_splat :: proc(v: ^fmag.IR_Value, n: int) -> []^fmag.IR_Value {
	out := make([]^fmag.IR_Value, n, context.temp_allocator)
	for i in 0 ..< n {
		out[i] = v
	}
	return out
}

fmag_fit :: proc(cg: ^Fmag_CG, vals: []^fmag.IR_Value, n: int, what: string) -> []^fmag.IR_Value {
	if !cg.ok do return nil
	if len(vals) == n do return vals
	if len(vals) == 1 && n > 1 do return fmag_splat(vals[0], n)
	fmag_err(cg, "%s: width %d cannot broadcast to %d", what, len(vals), n)
	return nil
}

fmag_exact_f32 :: proc(v: Exact_Value) -> (f32, bool) {
	#partial switch x in v {
	case f64:
		return f32(x), true
	case i128:
		return f32(x), true
	case bool:
		return 1 if x else 0, true
	}
	return 0, false
}

fmag_const_vals :: proc(cg: ^Fmag_CG, type: ^Type, value: Exact_Value) -> []^fmag.IR_Value {
	n := fmag_width(type)
	if n <= 0 {
		fmag_err(cg, "cannot lower constant of type '%s'", string_from_type(type))
		return nil
	}
	f, ok := fmag_exact_f32(value)
	if !ok {
		fmag_err(cg, "cannot lower constant value")
		return nil
	}
	return fmag_splat(fmag.ir_const(cg.b, f), n)
}

fmag_ensure_div :: proc(cg: ^Fmag_CG) {
	if cg.div_ready do return
	here := fmag.ir_current(cg.b)
	fmag.ir_runtime_rcp(cg.b)
	fmag.ir_runtime_div(cg.b)
	if here != nil {
		fmag.ir_position(cg.b, here)
	}
	cg.div_ready = true
}

fmag_lazy_component :: proc(cg: ^Fmag_CG, e: ^Entity) -> []^fmag.IR_Value {
	n := fmag_width(e.type)
	if n <= 0 {
		fmag_err(cg, "local '%s' is not an FMAG value", e.name)
		return nil
	}
	cache := cg.vec_cache[e]
	if len(cache) != n {
		cache = make([]^fmag.IR_Value, n, context.temp_allocator)
		cg.vec_cache[e] = cache
	}
	rhs, has_rhs := cg.vec_expr[e]
	if !has_rhs {
		fmag_err(cg, "unbound vector '%s'", e.name)
		return nil
	}
	fill_lane :: proc(cg: ^Fmag_CG, cache: []^fmag.IR_Value, rhs: ^Expr, i: int) {
		if cache[i] != nil do return
		saved := cg.work_lane
		cg.work_lane = i
		vs := fmag_expr(cg, rhs)
		cg.work_lane = saved
		if !cg.ok || len(vs) == 0 do return
		cache[i] = vs[0]
	}
	if cg.work_lane >= 0 {
		if cg.work_lane >= n {
			fmag_err(cg, "lane %d out of range for '%s'", cg.work_lane, e.name)
			return nil
		}
		fill_lane(cg, cache, rhs, cg.work_lane)
		if !cg.ok || cache[cg.work_lane] == nil do return nil
		return fmag_one(cache[cg.work_lane])
	}
	for i in 0 ..< n {
		fill_lane(cg, cache, rhs, i)
		if !cg.ok do return nil
	}
	return cache
}

fmag_lookup :: proc(cg: ^Fmag_CG, e: ^Entity) -> []^fmag.IR_Value {
	if e == nil do return nil
	if _, lazy := cg.vec_expr[e]; lazy {
		return fmag_lazy_component(cg, e)
	}
	if vals, ok := cg.slots[e]; ok {
		return fmag_narrow(cg, vals)
	}
	if e.kind == .Constant {
		return fmag_narrow(cg, fmag_const_vals(cg, e.type, e.value))
	}
	fmag_err(cg, "unbound name '%s'", e.name)
	return nil
}

fmag_swizzle_indices :: proc(name: string, vec_len: int) -> (idx: []int, ok: bool) {
	idx = make([]int, len(name), context.temp_allocator)
	for char, i in name {
		index := -1
		switch char {
		case 'r', 'x': index = 0
		case 'g', 'y': index = 1
		case 'b', 'z': index = 2
		case 'a', 'w': index = 3
		}
		if index < 0 || index >= vec_len {
			return nil, false
		}
		idx[i] = index
	}
	return idx, true
}

fmag_expr :: proc(cg: ^Fmag_CG, expr: ^Expr) -> []^fmag.IR_Value {
	if !cg.ok || expr == nil do return nil
	expr := unparen_expr(expr)
	if expr == nil do return nil

	if expr.tav.mode == .Constant && expr.tav.value != nil {
		_, is_str := expr.tav.value.(string)
		if !is_str && !exact_value_is_compound(expr.tav.value) {
			#partial switch _ in expr.derived {
			case ^Ident, ^Basic_Lit, ^Implicit_Selector_Expr, ^Binary_Expr, ^Unary_Expr, ^Paren_Expr, ^Auto_Cast, ^Type_Cast, ^Call_Expr, ^Comp_Lit, ^Ternary_If_Expr, ^Ternary_When_Expr:
				return fmag_narrow(cg, fmag_const_vals(cg, expr.tav.type, expr.tav.value))
			}
		}
	}

	#partial switch v in expr.derived {
	case ^Ident:
		return fmag_lookup(cg, v.entity)
	case ^Basic_Lit:
		return fmag_const_vals(cg, v.tav.type, v.tav.value)
	case ^Unary_Expr:
		x := fmag_expr(cg, v.expr)
		if !cg.ok do return nil
		#partial switch v.op.kind {
		case .Add:
			return x
		case .Sub:
			out := make([]^fmag.IR_Value, len(x), context.temp_allocator)
			for e, i in x {
				out[i] = fmag.ir_neg(cg.b, e)
			}
			return out
		case .Not:
			out := make([]^fmag.IR_Value, len(x), context.temp_allocator)
			one := fmag.ir_const(cg.b, 1)
			for e, i in x {
				out[i] = fmag.ir_sub(cg.b, one, e)
			}
			return out
		}
		fmag_err(cg, "unary '%s' is not FMAG", v.op.text)
		return nil
	case ^Binary_Expr:
		return fmag_binary(cg, v)
	case ^Ternary_If_Expr:
		c := fmag_expr(cg, v.cond)
		x := fmag_expr(cg, v.x)
		y := fmag_expr(cg, v.y)
		if !cg.ok do return nil
		n := max(len(x), len(y))
		c = fmag_fit(cg, c, n if len(c) != 1 else len(c), "ternary cond")
		if len(c) == 1 && n > 1 {
			c = fmag_splat(c[0], n)
		}
		x = fmag_fit(cg, x, n, "ternary")
		y = fmag_fit(cg, y, n, "ternary")
		if !cg.ok do return nil
		out := make([]^fmag.IR_Value, n, context.temp_allocator)
		for i in 0 ..< n {
			g := c[i] if len(c) == n else c[0]
			out[i] = fmag.ir_select(cg.b, x[i], y[i], g)
		}
		return fmag_narrow(cg, out)
	case ^Ternary_When_Expr:
		b, ok := v.cond.tav.value.(bool)
		if !ok {
			fmag_err(cg, "'when' expression was not a constant bool")
			return nil
		}
		return fmag_expr(cg, v.x if b else v.y)
	case ^Selector_Expr:
		base := fmag_with_all_lanes(cg, v.expr)
		if !cg.ok do return nil
		name := v.field.name if v.field != nil else ""
		idx, sok := fmag_swizzle_indices(name, len(base))
		if !sok {
			fmag_err(cg, "cannot lower selector '.%s'", name)
			return nil
		}
		out := make([]^fmag.IR_Value, len(idx), context.temp_allocator)
		for id, i in idx {
			out[i] = base[id]
		}
		return fmag_narrow(cg, out)
	case ^Index_Expr:
		base := fmag_with_all_lanes(cg, v.expr)
		if !cg.ok do return nil
		if v.index == nil || v.index.tav.mode != .Constant {
			fmag_err(cg, "FMAG index must be a constant")
			return nil
		}
		iv, iok := v.index.tav.value.(i128)
		if !iok || iv < 0 || int(iv) >= len(base) {
			fmag_err(cg, "FMAG index out of range")
			return nil
		}
		return fmag_one(base[int(iv)])
	case ^Call_Expr:
		return fmag_call(cg, v)
	case ^Comp_Lit:
		return fmag_comp_lit(cg, v)
	case ^Type_Cast:
		src := fmag_expr(cg, v.expr)
		n := fmag_width(expr.tav.type)
		if n <= 0 {
			fmag_err(cg, "cannot cast to '%s' in proc \"fmag\"", string_from_type(expr.tav.type))
			return nil
		}
		return fmag_narrow(cg, fmag_fit(cg, src, n, "cast"))
	case ^Auto_Cast:
		src := fmag_expr(cg, v.expr)
		n := fmag_width(expr.tav.type)
		if n <= 0 {
			fmag_err(cg, "cannot cast to '%s' in proc \"fmag\"", string_from_type(expr.tav.type))
			return nil
		}
		return fmag_narrow(cg, fmag_fit(cg, src, n, "cast"))
	case ^Implicit_Selector_Expr:
		return fmag_narrow(cg, fmag_const_vals(cg, v.tav.type, v.tav.value))
	}
	fmag_err(cg, "cannot lower expression to FMAG")
	return nil
}

fmag_comp_lit :: proc(cg: ^Fmag_CG, lit: ^Comp_Lit) -> []^fmag.IR_Value {
	n := fmag_width(lit.tav.type)
	if n <= 0 {
		fmag_err(cg, "compound literal type '%s' is not FMAG", string_from_type(lit.tav.type))
		return nil
	}
	if len(lit.elems) == 0 {
		return fmag_narrow(cg, fmag_splat(fmag.ir_const(cg.b, 0), n))
	}
	acc := make([dynamic]^fmag.IR_Value, context.temp_allocator)
	for elem in lit.elems {
		e := elem
		if fv, is_fv := elem.derived.(^Field_Value); is_fv {
			e = fv.value
		}
		vs := fmag_expr(cg, e)
		if !cg.ok do return nil
		for v in vs {
			append(&acc, v)
		}
	}
	if len(acc) == 1 && n > 1 {
		return fmag_narrow(cg, fmag_splat(acc[0], n))
	}
	if len(acc) != n {
		fmag_err(cg, "compound literal has %d components, want %d", len(acc), n)
		return nil
	}
	return fmag_narrow(cg, acc[:])
}

fmag_call :: proc(cg: ^Fmag_CG, call: ^Call_Expr) -> []^fmag.IR_Value {
	if call.expr != nil && call.expr.tav.mode == .Type {
		return fmag_ctor(cg, call.expr.tav.type, call.args)
	}
	callee := strip_entity_wrapping(entity_from_expr(call.expr))
	if callee != nil && callee.kind == .Type_Name {
		return fmag_ctor(cg, callee.type, call.args)
	}
	if callee == nil {
		fmag_err(cg, "calling a procedure is not allowed in proc \"fmag\"")
		return nil
	}
	if callee.kind == .Procedure {
		return fmag_inline_call(cg, call, callee)
	}
	if callee.kind != .Builtin {
		fmag_err(cg, "calling a procedure is not allowed in proc \"fmag\"")
		return nil
	}
	horizontal := callee.builtin_id == .dot || callee.builtin_id == .cross
	if horizontal {
		if hit, ok := cg.horiz[call]; ok {
			return fmag_narrow(cg, hit)
		}
	}
	saved_lane := cg.work_lane
	if horizontal {
		cg.work_lane = -1
	}
	args := make([dynamic][]^fmag.IR_Value, context.temp_allocator)
	n := 1
	for a in call.args {
		vs := fmag_expr(cg, a)
		if !cg.ok {
			cg.work_lane = saved_lane
			return nil
		}
		append(&args, vs)
		if len(vs) > n do n = len(vs)
	}
	fitn :: proc(cg: ^Fmag_CG, args: [][]^fmag.IR_Value, n: int) -> [][]^fmag.IR_Value {
		out := make([][]^fmag.IR_Value, len(args), context.temp_allocator)
		for a, i in args {
			out[i] = fmag_fit(cg, a, n, "builtin")
		}
		return out
	}
	result: []^fmag.IR_Value
	#partial switch callee.builtin_id {
	case .lerp:
		if len(args) != 3 {
			fmag_err(cg, "lerp expects 3 arguments")
			cg.work_lane = saved_lane
			return nil
		}
		aa := fitn(cg, args[:], n)
		if !cg.ok {
			cg.work_lane = saved_lane
			return nil
		}
		out := make([]^fmag.IR_Value, n, context.temp_allocator)
		for i in 0 ..< n {
			d := fmag.ir_sub(cg.b, aa[1][i], aa[0][i])
			out[i] = fmag.ir_fma(cg.b, d, aa[2][i], aa[0][i])
		}
		result = out
	case .fma:
		if len(args) != 3 {
			fmag_err(cg, "fma expects 3 arguments")
			cg.work_lane = saved_lane
			return nil
		}
		aa := fitn(cg, args[:], n)
		if !cg.ok {
			cg.work_lane = saved_lane
			return nil
		}
		out := make([]^fmag.IR_Value, n, context.temp_allocator)
		for i in 0 ..< n {
			out[i] = fmag.ir_fma(cg.b, aa[0][i], aa[1][i], aa[2][i])
		}
		result = out
	case .min, .max:
		if len(args) < 2 {
			fmag_err(cg, "min/max expects at least 2 arguments")
			cg.work_lane = saved_lane
			return nil
		}
		aa := fitn(cg, args[:], n)
		if !cg.ok {
			cg.work_lane = saved_lane
			return nil
		}
		out := fmag_clone(aa[0])
		for k in 1 ..< len(aa) {
			for i in 0 ..< n {
				if callee.builtin_id == .min {
					out[i] = fmag.ir_min(cg.b, out[i], aa[k][i])
				} else {
					out[i] = fmag.ir_max(cg.b, out[i], aa[k][i])
				}
			}
		}
		result = out
	case .clamp:
		if len(args) != 3 {
			fmag_err(cg, "clamp expects 3 arguments")
			cg.work_lane = saved_lane
			return nil
		}
		aa := fitn(cg, args[:], n)
		if !cg.ok {
			cg.work_lane = saved_lane
			return nil
		}
		out := make([]^fmag.IR_Value, n, context.temp_allocator)
		for i in 0 ..< n {
			out[i] = fmag.ir_clamp(cg.b, aa[0][i], aa[1][i], aa[2][i])
		}
		result = out
	case .abs:
		if len(args) != 1 {
			fmag_err(cg, "abs expects 1 argument")
			cg.work_lane = saved_lane
			return nil
		}
		out := make([]^fmag.IR_Value, n, context.temp_allocator)
		a0 := fmag_fit(cg, args[0], n, "abs")
		if !cg.ok {
			cg.work_lane = saved_lane
			return nil
		}
		for i in 0 ..< n {
			out[i] = fmag.ir_abs(cg.b, a0[i])
		}
		result = out
	case .dot:
		if len(args) != 2 {
			fmag_err(cg, "dot expects 2 arguments")
			cg.work_lane = saved_lane
			return nil
		}
		aa := fitn(cg, args[:], n)
		if !cg.ok {
			cg.work_lane = saved_lane
			return nil
		}
		acc := fmag.ir_mul(cg.b, aa[0][0], aa[1][0])
		for i in 1 ..< n {
			acc = fmag.ir_fma(cg.b, aa[0][i], aa[1][i], acc)
		}
		result = fmag_one(acc)
	case .cross:
		if len(args) != 2 || n != 3 {
			fmag_err(cg, "cross expects two [3]f32")
			cg.work_lane = saved_lane
			return nil
		}
		a, b := args[0], args[1]
		a = fmag_fit(cg, a, 3, "cross")
		b = fmag_fit(cg, b, 3, "cross")
		if !cg.ok {
			cg.work_lane = saved_lane
			return nil
		}
		out := make([]^fmag.IR_Value, 3, context.temp_allocator)
		out[0] = fmag.ir_sub(cg.b, fmag.ir_mul(cg.b, a[1], b[2]), fmag.ir_mul(cg.b, a[2], b[1]))
		out[1] = fmag.ir_sub(cg.b, fmag.ir_mul(cg.b, a[2], b[0]), fmag.ir_mul(cg.b, a[0], b[2]))
		out[2] = fmag.ir_sub(cg.b, fmag.ir_mul(cg.b, a[0], b[1]), fmag.ir_mul(cg.b, a[1], b[0]))
		result = out
	case:
		fmag_err(cg, "builtin '%s' has no FMAG opcode", builtin_names[callee.builtin_id])
		cg.work_lane = saved_lane
		return nil
	}
	if horizontal {
		cg.horiz[call] = result
	}
	cg.work_lane = saved_lane
	return fmag_narrow(cg, result)
}

fmag_clone_slots :: proc(src: map[^Entity][]^fmag.IR_Value) -> map[^Entity][]^fmag.IR_Value {
	dst := make(map[^Entity][]^fmag.IR_Value, context.temp_allocator)
	for e, v in src {
		dst[e] = fmag_clone(v)
	}
	return dst
}

fmag_clone_vec_expr :: proc(src: map[^Entity]^Expr) -> map[^Entity]^Expr {
	dst := make(map[^Entity]^Expr, context.temp_allocator)
	for e, x in src {
		dst[e] = x
	}
	return dst
}

fmag_clone_vec_cache :: proc(src: map[^Entity][]^fmag.IR_Value) -> map[^Entity][]^fmag.IR_Value {
	return fmag_clone_slots(src)
}

fmag_entity_before :: proc(a, b: ^Entity) -> bool {
	if a.pos.offset != b.pos.offset {
		return a.pos.offset < b.pos.offset
	}
	return a.id < b.id
}

fmag_sorted_entities :: proc(m: map[^Entity]$V) -> []^Entity {
	es: [dynamic]^Entity
	es.allocator = context.temp_allocator
	for e, _ in m {
		if e != nil {
			append(&es, e)
		}
	}
	slice.sort_by(es[:], fmag_entity_before)
	return es[:]
}

fmag_materialize_lazy :: proc(cg: ^Fmag_CG) {
	if !cg.ok do return
	saved := cg.work_lane
	cg.work_lane = -1
	for e in fmag_sorted_entities(cg.vec_expr) {
		vals := fmag_lazy_component(cg, e)
		if !cg.ok {
			cg.work_lane = saved
			return
		}
		delete_key(&cg.vec_expr, e)
		delete_key(&cg.vec_cache, e)
		fmag_bind(cg, e, vals)
	}
	cg.work_lane = saved
}

fmag_br_open :: proc(cg: ^Fmag_CG, target: ^fmag.IR_Block) {
	cur := fmag.ir_current(cg.b)
	if cur == nil || cur.term != .None do return
	fmag.ir_br(cg.b, target)
}

fmag_if :: proc(cg: ^Fmag_CG, d: ^If_Stmt) {
	if d.init != nil {
		fmag_stmt(cg, d.init)
		if !cg.ok || cg.returned do return
	}
	saved_lane := cg.work_lane
	cg.work_lane = -1
	fmag_materialize_lazy(cg)
	if !cg.ok {
		cg.work_lane = saved_lane
		return
	}
	cond := fmag_expr(cg, d.cond)
	if !cg.ok {
		cg.work_lane = saved_lane
		return
	}
	if len(cond) != 1 {
		fmag_err(cg, "if condition must be a scalar")
		cg.work_lane = saved_lane
		return
	}

	before_slots := fmag_clone_slots(cg.slots)
	before_expr := fmag_clone_vec_expr(cg.vec_expr)
	before_cache := fmag_clone_vec_cache(cg.vec_cache)

	entry := fmag.ir_current(cg.b)
	then_block := fmag.ir_block(cg.b, cg.fn)
	else_block := fmag.ir_block(cg.b, cg.fn)
	fmag.ir_position(cg.b, entry)
	fmag.ir_cond_br(cg.b, cond[0], then_block, else_block)

	fmag.ir_position(cg.b, then_block)
	cg.returned = false
	fmag_stmt(cg, d.body)
	then_ret := cg.returned
	if !then_ret {
		fmag_materialize_lazy(cg)
	}
	then_end := fmag.ir_current(cg.b)
	then_slots := fmag_clone_slots(cg.slots)
	if !cg.ok {
		cg.work_lane = saved_lane
		return
	}

	cg.slots = fmag_clone_slots(before_slots)
	cg.vec_expr = fmag_clone_vec_expr(before_expr)
	cg.vec_cache = fmag_clone_vec_cache(before_cache)
	fmag.ir_position(cg.b, else_block)
	cg.returned = false
	if d.else_stmt != nil {
		fmag_stmt(cg, d.else_stmt)
	}
	else_ret := cg.returned
	if !else_ret {
		fmag_materialize_lazy(cg)
	}
	else_end := fmag.ir_current(cg.b)
	else_slots := fmag_clone_slots(cg.slots)
	if !cg.ok {
		cg.work_lane = saved_lane
		return
	}

	if then_ret && else_ret {
		cg.returned = true
		cg.work_lane = saved_lane
		return
	}

	merge := fmag.ir_block(cg.b, cg.fn)
	if !then_ret {
		fmag.ir_position(cg.b, then_end)
		fmag_br_open(cg, merge)
	}
	if !else_ret {
		fmag.ir_position(cg.b, else_end)
		fmag_br_open(cg, merge)
	}
	fmag.ir_position(cg.b, merge)
	cg.returned = false
	cg.vec_expr = fmag_clone_vec_expr(before_expr)
	cg.vec_cache = fmag_clone_vec_cache(before_cache)
	cg.slots = fmag_clone_slots(before_slots)
	for e in fmag_sorted_entities(before_slots) {
		before_vals := before_slots[e]
		tvals := then_slots[e] if e in then_slots else before_vals
		evals := else_slots[e] if e in else_slots else before_vals
		if then_ret && !else_ret {
			fmag_bind(cg, e, evals)
			delete_key(&cg.vec_expr, e)
			delete_key(&cg.vec_cache, e)
			continue
		}
		if else_ret && !then_ret {
			fmag_bind(cg, e, tvals)
			delete_key(&cg.vec_expr, e)
			delete_key(&cg.vec_cache, e)
			continue
		}
		n := max(len(tvals), len(evals))
		if n == 0 {
			continue
		}
		tvals = fmag_fit(cg, tvals, n, "if")
		evals = fmag_fit(cg, evals, n, "if")
		if !cg.ok {
			cg.work_lane = saved_lane
			return
		}
		out := make([]^fmag.IR_Value, n, context.temp_allocator)
		for i in 0 ..< n {
			phi := fmag.ir_phi(cg.b)
			fmag.ir_phi_edge(cg.b, phi, then_end, tvals[i])
			fmag.ir_phi_edge(cg.b, phi, else_end, evals[i])
			out[i] = phi
		}
		fmag_bind(cg, e, out)
		delete_key(&cg.vec_expr, e)
		delete_key(&cg.vec_cache, e)
	}
	cg.work_lane = saved_lane
}

fmag_helper_fn :: proc(cg: ^Fmag_CG, callee: ^Entity) -> ^fmag.IR_Function {
	if fn, ok := cg.helpers[callee]; ok {
		return fn
	}
	if callee.type == nil {
		fmag_err(cg, "helper '%s' has no type", callee.name)
		return nil
	}
	pt, is_proc := callee.type.derived.(^Type_Proc)
	if !is_proc || callee.proc_lit == nil || callee.proc_lit.body == nil {
		fmag_err(cg, "helper '%s' has no body", callee.name)
		return nil
	}
	args := fmag_flatten_count(pt.params)
	rets := fmag_flatten_count(pt.results)
	here := fmag.ir_current(cg.b)
	saved_fn := cg.fn
	saved_slots := cg.slots
	saved_expr := cg.vec_expr
	saved_cache := cg.vec_cache
	saved_lane := cg.work_lane
	saved_ret := cg.returned
	saved_dest := cg.inline_dest

	fn := fmag.ir_function(cg.b, callee.name, fmag.Length(args), fmag.Length(rets))
	cg.helpers[callee] = fn
	fmag.ir_block(cg.b, fn)
	cg.fn = fn
	cg.slots = make(map[^Entity][]^fmag.IR_Value, context.temp_allocator)
	cg.vec_expr = make(map[^Entity]^Expr, context.temp_allocator)
	cg.vec_cache = make(map[^Entity][]^fmag.IR_Value, context.temp_allocator)
	cg.work_lane = -1
	cg.returned = false
	cg.inline_dest = nil
	pi: fmag.Length
	if pt.params != nil {
		for p in pt.params.variables {
			if p == nil || entity_is_poly_const(p) do continue
			w := fmag_width(p.type)
			if w <= 0 {
				fmag_err(cg, "helper '%s' parameter '%s' is not an FMAG value", callee.name, p.name)
				break
			}
			vals := make([]^fmag.IR_Value, w, context.temp_allocator)
			for i in 0 ..< w {
				vals[i] = fmag.ir_param(fn, pi)
				pi += 1
			}
			fmag_bind(cg, p, vals)
		}
	}
	if cg.ok {
		fmag_stmt(cg, callee.proc_lit.body)
	}
	if cg.ok && !cg.returned && rets > 0 {
		fmag_err(cg, "helper '%s' does not return", callee.name)
	}

	cg.fn = saved_fn
	cg.slots = saved_slots
	cg.vec_expr = saved_expr
	cg.vec_cache = saved_cache
	cg.work_lane = saved_lane
	cg.returned = saved_ret
	cg.inline_dest = saved_dest
	if here != nil {
		fmag.ir_position(cg.b, here)
	}
	if !cg.ok do return nil
	return fn
}

fmag_inline_call :: proc(cg: ^Fmag_CG, call: ^Call_Expr, callee: ^Entity) -> []^fmag.IR_Value {
	if hit, ok := cg.horiz[call]; ok {
		return fmag_narrow(cg, hit)
	}
	fn := fmag_helper_fn(cg, callee)
	if !cg.ok || fn == nil do return nil
	saved_lane := cg.work_lane
	cg.work_lane = -1
	arg_vals: [dynamic]^fmag.IR_Value
	arg_vals.allocator = context.temp_allocator
	for a in call.args {
		vs := fmag_expr(cg, a)
		if !cg.ok {
			cg.work_lane = saved_lane
			return nil
		}
		for v in vs {
			append(&arg_vals, v)
		}
	}
	ir_call := fmag.ir_call(cg.b, fn, arg_vals[:])
	if note := fmag_call_note(cg, call, callee); note != "" {
		ir_call.note = note
	}
	ret_n := int(fn.return_count)
	dest: []^fmag.IR_Value
	if ret_n > 0 {
		dest = make([]^fmag.IR_Value, ret_n, context.temp_allocator)
		for i in 0 ..< ret_n {
			dest[i] = fmag.ir_result(cg.b, ir_call, fmag.Length(i))
		}
		cg.horiz[call] = dest
	}
	cg.work_lane = saved_lane
	return fmag_narrow(cg, dest)
}

fmag_ctor :: proc(cg: ^Fmag_CG, dest: ^Type, args: []^Expr) -> []^fmag.IR_Value {
	n := fmag_width(dest)
	if n <= 0 {
		fmag_err(cg, "cannot construct '%s' in proc \"fmag\"", string_from_type(dest))
		return nil
	}
	if cg.work_lane >= 0 && cg.work_lane < n {
		if len(args) == 1 {
			return fmag_expr(cg, args[0])
		}
		if len(args) == n {
			all_scalar := true
			for a in args {
				if a == nil || fmag_width(a.tav.type) != 1 {
					all_scalar = false
					break
				}
			}
			if all_scalar {
				return fmag_expr(cg, args[cg.work_lane])
			}
		}
	}
	acc := make([dynamic]^fmag.IR_Value, context.temp_allocator)
	for a in args {
		vs := fmag_expr(cg, a)
		if !cg.ok do return nil
		for v in vs {
			append(&acc, v)
		}
	}
	if len(acc) == 1 && n > 1 {
		return fmag_narrow(cg, fmag_splat(acc[0], n))
	}
	if len(acc) != n {
		fmag_err(cg, "constructor wants %d components, got %d", n, len(acc))
		return nil
	}
	return fmag_narrow(cg, acc[:])
}

fmag_binary :: proc(cg: ^Fmag_CG, bin: ^Binary_Expr) -> []^fmag.IR_Value {
	l := fmag_expr(cg, bin.left)
	r := fmag_expr(cg, bin.right)
	if !cg.ok do return nil
	n := max(len(l), len(r))
	l = fmag_fit(cg, l, n, "binary")
	r = fmag_fit(cg, r, n, "binary")
	if !cg.ok do return nil
	out := make([]^fmag.IR_Value, n, context.temp_allocator)
	#partial switch bin.op.kind {
	case .Add:
		for i in 0 ..< n do out[i] = fmag.ir_add(cg.b, l[i], r[i])
	case .Sub:
		for i in 0 ..< n do out[i] = fmag.ir_sub(cg.b, l[i], r[i])
	case .Mul:
		for i in 0 ..< n do out[i] = fmag.ir_mul(cg.b, l[i], r[i])
	case .Quo:
		fmag_ensure_div(cg)
		for i in 0 ..< n {
			q := fmag.ir_div(cg.b, l[i], r[i])
			if q == nil {
				fmag_err(cg, "failed to lower '/'")
				return nil
			}
			out[i] = q
		}
	case .Gt:
		for i in 0 ..< n do out[i] = fmag.ir_gt(cg.b, l[i], r[i])
	case .Lt:
		for i in 0 ..< n do out[i] = fmag.ir_lt(cg.b, l[i], r[i])
	case .Gt_Eq:
		for i in 0 ..< n do out[i] = fmag.ir_gte(cg.b, l[i], r[i])
	case .Lt_Eq:
		for i in 0 ..< n do out[i] = fmag.ir_lte(cg.b, l[i], r[i])
	case .Cmp_Eq:
		for i in 0 ..< n {
			out[i] = fmag.ir_mul(cg.b, fmag.ir_lte(cg.b, l[i], r[i]), fmag.ir_gte(cg.b, l[i], r[i]))
		}
	case .Not_Eq:
		one := fmag.ir_const(cg.b, 1)
		for i in 0 ..< n {
			eq := fmag.ir_mul(cg.b, fmag.ir_lte(cg.b, l[i], r[i]), fmag.ir_gte(cg.b, l[i], r[i]))
			out[i] = fmag.ir_sub(cg.b, one, eq)
		}
	case .Cmp_And:
		for i in 0 ..< n do out[i] = fmag.ir_mul(cg.b, l[i], r[i])
	case .Cmp_Or:
		for i in 0 ..< n do out[i] = fmag.ir_max(cg.b, l[i], r[i])
	case:
		fmag_err(cg, "operator '%s' is not FMAG", bin.op.text)
		return nil
	}
	return fmag_narrow(cg, out)
}

fmag_emit_from_expr :: proc(cg: ^Fmag_CG, expr: ^Expr, decls: map[^Entity]^Stmt, done: ^map[^Entity]bool) {
	if !cg.ok || expr == nil do return
	expr := unparen_expr(expr)
	if expr == nil do return
	#partial switch v in expr.derived {
	case ^Ident:
		fmag_emit_scalar_decl(cg, v.entity, decls, done)
	case ^Unary_Expr:
		fmag_emit_from_expr(cg, v.expr, decls, done)
	case ^Binary_Expr:
		fmag_emit_from_expr(cg, v.left, decls, done)
		fmag_emit_from_expr(cg, v.right, decls, done)
	case ^Ternary_If_Expr:
		fmag_emit_from_expr(cg, v.cond, decls, done)
		fmag_emit_from_expr(cg, v.x, decls, done)
		fmag_emit_from_expr(cg, v.y, decls, done)
	case ^Ternary_When_Expr:
		b, ok := v.cond.tav.value.(bool)
		if ok {
			fmag_emit_from_expr(cg, v.x if b else v.y, decls, done)
		}
	case ^Selector_Expr:
		fmag_emit_from_expr(cg, v.expr, decls, done)
	case ^Index_Expr:
		fmag_emit_from_expr(cg, v.expr, decls, done)
		fmag_emit_from_expr(cg, v.index, decls, done)
	case ^Call_Expr:
		for a in v.args {
			fmag_emit_from_expr(cg, a, decls, done)
		}
	case ^Comp_Lit:
		for e in v.elems {
			elem := e
			if fv, is_fv := e.derived.(^Field_Value); is_fv {
				elem = fv.value
			}
			fmag_emit_from_expr(cg, elem, decls, done)
		}
	case ^Type_Cast:
		fmag_emit_from_expr(cg, v.expr, decls, done)
	case ^Auto_Cast:
		fmag_emit_from_expr(cg, v.expr, decls, done)
	}
}

fmag_emit_scalar_decl :: proc(cg: ^Fmag_CG, e: ^Entity, decls: map[^Entity]^Stmt, done: ^map[^Entity]bool) {
	if !cg.ok || e == nil do return
	stmt, is_decl := decls[e]
	if !is_decl do return
	if done[e] do return
	done[e] = true
	vd := stmt.derived.(^Value_Decl)
	if len(vd.values) == 1 {
		fmag_emit_from_expr(cg, vd.values[0], decls, done)
	}
	fmag_stmt(cg, stmt)
}

fmag_is_scalar_decl :: proc(s: ^Stmt) -> (e: ^Entity, ok: bool) {
	vd, is_vd := s.derived.(^Value_Decl)
	if !is_vd || !vd.is_mutable || len(vd.names) != 1 || len(vd.values) != 1 {
		return
	}
	ident, iok := unparen_expr(vd.names[0]).derived.(^Ident)
	if !iok || ident.entity == nil do return
	if fmag_width(ident.entity.type) != 1 do return
	return ident.entity, true
}

fmag_block :: proc(cg: ^Fmag_CG, block: ^Block_Stmt) {
	has_order := false
	for s in block.stmts {
		if _, is_as := s.derived.(^Assign_Stmt); is_as {
			has_order = true
			break
		}
		if _, is_if := s.derived.(^If_Stmt); is_if {
			has_order = true
			break
		}
		if _, is_when := s.derived.(^When_Stmt); is_when {
			has_order = true
			break
		}
		if _, is_which := s.derived.(^Which_Stmt); is_which {
			has_order = true
			break
		}
	}
	if has_order {
		for s in block.stmts {
			fmag_stmt(cg, s)
			if cg.returned || !cg.ok do return
		}
		return
	}

	decls := make(map[^Entity]^Stmt, context.temp_allocator)
	decl_order: [dynamic]^Entity
	decl_order.allocator = context.temp_allocator
	rest: [dynamic]^Stmt
	rest.allocator = context.temp_allocator
	ret: ^Stmt
	for s in block.stmts {
		if _, is_ret := s.derived.(^Return_Stmt); is_ret {
			ret = s
			continue
		}
		if e, is_scalar := fmag_is_scalar_decl(s); is_scalar {
			decls[e] = s
			append(&decl_order, e)
			continue
		}
		append(&rest, s)
	}
	for s in rest {
		fmag_stmt(cg, s)
		if cg.returned || !cg.ok do return
	}

	done := make(map[^Entity]bool, context.temp_allocator)
	for e in fmag_sorted_entities(cg.vec_expr) {
		rhs := cg.vec_expr[e]
		fmag_emit_from_expr(cg, rhs, decls, &done)
		if !cg.ok do return
	}
	if ret != nil {
		rs := ret.derived.(^Return_Stmt)
		for r in rs.results {
			fmag_emit_from_expr(cg, r, decls, &done)
			if !cg.ok do return
		}
	}
	for e in decl_order {
		fmag_emit_scalar_decl(cg, e, decls, &done)
		if !cg.ok do return
	}
	if ret != nil {
		fmag_stmt(cg, ret)
	}
}

fmag_stmt :: proc(cg: ^Fmag_CG, stmt: ^Stmt) {
	if !cg.ok || stmt == nil || cg.returned do return
	#partial switch v in stmt.derived {
	case ^Block_Stmt:
		fmag_block(cg, v)
		return
	case ^Empty_Stmt:
		return
	case ^Expr_Stmt:
		_ = fmag_expr(cg, v.expr)
	case ^Value_Decl:
		if !v.is_mutable do return
		if len(v.values) == 0 {
			for name in v.names {
				ident, iok := unparen_expr(name).derived.(^Ident)
				if !iok || ident.entity == nil do continue
				n := fmag_width(ident.entity.type)
				if n <= 0 {
					fmag_err(cg, "local '%s' is not an FMAG value", ident.name)
					return
				}
				fmag_bind(cg, ident.entity, fmag_splat(fmag.ir_const(cg.b, 0), n))
			}
			return
		}
		if len(v.names) == 1 && len(v.values) == 1 {
			ident, iok := unparen_expr(v.names[0]).derived.(^Ident)
			if !iok do return
			n := fmag_width(ident.tav.type if ident.entity == nil else ident.entity.type)
			if n > 1 && ident.entity != nil {
				cg.vec_expr[ident.entity] = v.values[0]
				cg.vec_cache[ident.entity] = make([]^fmag.IR_Value, n, context.temp_allocator)
				return
			}
			rhs := fmag_expr(cg, v.values[0])
			if n > 0 {
				rhs = fmag_fit(cg, rhs, n, "decl")
			}
			fmag_bind(cg, ident.entity, rhs)
			return
		}
		if len(v.names) == len(v.values) {
			for name, i in v.names {
				ident, iok := unparen_expr(name).derived.(^Ident)
				if !iok do continue
				fmag_bind(cg, ident.entity, fmag_expr(cg, v.values[i]))
			}
			return
		}
		if len(v.names) > 1 && len(v.values) == 1 {
			rhs := fmag_with_all_lanes(cg, v.values[0])
			if !cg.ok do return
			fmag_bind_unpacked(cg, v.names, rhs)
			return
		}
		fmag_err(cg, "unsupported declaration in proc \"fmag\"")
	case ^Assign_Stmt:
		fmag_assign(cg, v)
	case ^If_Stmt:
		fmag_if(cg, v)
	case ^Return_Stmt:
		vals: [dynamic]^fmag.IR_Value
		vals.allocator = context.temp_allocator
		if len(v.results) == 0 {
			if cg.inline_dest != nil {
				if len(cg.inline_dest) != 0 {
					fmag_err(cg, "return is missing values")
					return
				}
				cg.returned = true
				return
			}
			if cg.fn.return_count == 0 {
				fmag.ir_ret(cg.b, nil)
				cg.returned = true
				return
			}
			fmag_err(cg, "return is missing values")
			return
		}
		for r in v.results {
			n := fmag_width(r.tav.type)
			if n <= 1 {
				vs := fmag_expr(cg, r)
				if !cg.ok do return
				for x in vs {
					append(&vals, x)
				}
				continue
			}
			if cg.work_lane >= 0 {
				vs := fmag_expr(cg, r)
				if !cg.ok do return
				if len(vs) == 0 {
					fmag_err(cg, "return lane %d produced no value", cg.work_lane)
					return
				}
				append(&vals, vs[0])
				continue
			}
			saved := cg.work_lane
			for i in 0 ..< n {
				cg.work_lane = i
				vs := fmag_expr(cg, r)
				if !cg.ok {
					cg.work_lane = saved
					return
				}
				if len(vs) == 0 {
					fmag_err(cg, "return lane %d produced no value", i)
					cg.work_lane = saved
					return
				}
				append(&vals, vs[0])
			}
			cg.work_lane = saved
		}
		if cg.inline_dest != nil {
			if len(vals) != len(cg.inline_dest) {
				fmag_err(cg, "helper return has %d scalars, expected %d", len(vals), len(cg.inline_dest))
				return
			}
			for x, i in vals {
				cg.inline_dest[i] = x
			}
			cg.returned = true
			return
		}
		if fmag.Length(len(vals)) != cg.fn.return_count {
			fmag_err(cg, "return has %d scalars, entry wants %d", len(vals), cg.fn.return_count)
			return
		}
		fmag.ir_ret(cg.b, vals[:])
		cg.returned = true
	case ^When_Stmt:
		b, ok := v.cond.tav.value.(bool)
		if !ok {
			fmag_err(cg, "'when' condition was not a constant bool")
			return
		}
		if b {
			fmag_stmt(cg, v.body)
		} else if v.else_stmt != nil {
			fmag_stmt(cg, v.else_stmt)
		}
	case ^Which_Stmt:
		taken := which_taken_clause_from_tav(v)
		if taken == nil do return
		for s in taken.body {
			fmag_stmt(cg, s)
			if cg.returned || !cg.ok do return
		}
	case ^For_Stmt, ^Range_Stmt:
		fmag_err(cg, "'for' is not allowed in proc \"fmag\"")
	case ^Switch_Stmt:
		fmag_err(cg, "'switch' is not allowed in proc \"fmag\"")
	case:
		fmag_err(cg, "cannot lower statement to FMAG")
	}
}

fmag_assign :: proc(cg: ^Fmag_CG, as: ^Assign_Stmt) {
	if len(as.lhs) != 1 || len(as.rhs) != 1 {
		fmag_err(cg, "FMAG assignment must be 1:1")
		return
	}
	saved := cg.work_lane
	if as.op.kind != .Eq {
		cg.work_lane = -1
	}
	rhs := fmag_expr(cg, as.rhs[0])
	if !cg.ok {
		cg.work_lane = saved
		return
	}
	#partial switch as.op.kind {
	case .Eq:
		fmag_store(cg, as.lhs[0], rhs)
	case .Add_Eq, .Sub_Eq, .Mul_Eq, .Quo_Eq:
		lhs := fmag_expr(cg, as.lhs[0])
		if !cg.ok {
			cg.work_lane = saved
			return
		}
		n := max(len(lhs), len(rhs))
		lhs = fmag_fit(cg, lhs, n, "assign")
		rhs = fmag_fit(cg, rhs, n, "assign")
		if !cg.ok {
			cg.work_lane = saved
			return
		}
		out := make([]^fmag.IR_Value, n, context.temp_allocator)
		for i in 0 ..< n {
			#partial switch as.op.kind {
			case .Add_Eq: out[i] = fmag.ir_add(cg.b, lhs[i], rhs[i])
			case .Sub_Eq: out[i] = fmag.ir_sub(cg.b, lhs[i], rhs[i])
			case .Mul_Eq: out[i] = fmag.ir_mul(cg.b, lhs[i], rhs[i])
			case .Quo_Eq:
				fmag_ensure_div(cg)
				out[i] = fmag.ir_div(cg.b, lhs[i], rhs[i])
			}
		}
		fmag_store(cg, as.lhs[0], out)
	case:
		fmag_err(cg, "assignment '%s' is not FMAG", as.op.text)
	}
	cg.work_lane = saved
}

fmag_store :: proc(cg: ^Fmag_CG, lhs: ^Expr, vals: []^fmag.IR_Value) {
	lhs := unparen_expr(lhs)
	if ident, ok := lhs.derived.(^Ident); ok {
		n := fmag_width(ident.entity.type) if ident.entity != nil else len(vals)
		if ident.entity != nil {
			delete_key(&cg.vec_expr, ident.entity)
			delete_key(&cg.vec_cache, ident.entity)
		}
		fmag_bind(cg, ident.entity, fmag_fit(cg, vals, n, "store"))
		return
	}
	if sel, ok := lhs.derived.(^Selector_Expr); ok {
		base_ident, is_ident := unparen_expr(sel.expr).derived.(^Ident)
		if !is_ident || base_ident.entity == nil {
			fmag_err(cg, "FMAG swizzle store needs a variable")
			return
		}
		cur := fmag_clone(fmag_lookup(cg, base_ident.entity))
		idx, sok := fmag_swizzle_indices(sel.field.name, len(cur))
		if !sok || len(idx) != len(vals) {
			fmag_err(cg, "swizzle store mismatch")
			return
		}
		for id, i in idx {
			cur[id] = vals[i]
		}
		delete_key(&cg.vec_expr, base_ident.entity)
		delete_key(&cg.vec_cache, base_ident.entity)
		fmag_bind(cg, base_ident.entity, cur)
		return
	}
	if ix, ok := lhs.derived.(^Index_Expr); ok {
		base_ident, is_ident := unparen_expr(ix.expr).derived.(^Ident)
		if !is_ident || ix.index == nil || ix.index.tav.mode != .Constant {
			fmag_err(cg, "FMAG index store needs a variable and constant index")
			return
		}
		iv, iok := ix.index.tav.value.(i128)
		cur := fmag_clone(fmag_lookup(cg, base_ident.entity))
		if !iok || iv < 0 || int(iv) >= len(cur) || len(vals) != 1 {
			fmag_err(cg, "FMAG index store out of range")
			return
		}
		cur[int(iv)] = vals[0]
		delete_key(&cg.vec_expr, base_ident.entity)
		delete_key(&cg.vec_cache, base_ident.entity)
		fmag_bind(cg, base_ident.entity, cur)
		return
	}
	fmag_err(cg, "cannot store to this lvalue in proc \"fmag\"")
}

fmag_copy_program :: proc(raw: fmag.Program, allocator := context.allocator) -> (prog: fmag.Program, ok: bool) {
	n := int(raw.stream.size)
	buf := make([]u8, n, allocator)
	if n > 0 && raw.stream.data != nil {
		intrinsics.mem_copy(raw_data(buf), raw.stream.data, n)
	}
	prog.header = raw.header
	prog.stream.data = raw_data(buf)
	prog.stream.size = raw.stream.size
	ok = true
	return
}

fmag_lower_proc :: proc(entry: ^Entity, ctx: ^fmag.Context, notes_allocator := context.allocator) -> (raw: fmag.Program, notes: []string, ok: bool) {
	pt := entry.type.derived.(^Type_Proc)
	if entry.proc_lit == nil || entry.proc_lit.body == nil {
		fmt.eprintfln("compile_fmag_entry: '%s' has no body", entry.name)
		return
	}
	args := fmag_flatten_count(pt.params)
	rets := fmag_flatten_count(pt.results)
	b := fmag.ir_builder_create(ctx, false)
	if b == nil {
		fmt.eprintfln("compile_fmag_entry: ir_builder_create failed")
		return
	}
	defer fmag.ir_builder_delete(b)
	fn := fmag.ir_function(b, entry.name, fmag.Length(args), fmag.Length(rets))
	fmag.ir_block(b, fn)

	cg := Fmag_CG{
		b = b,
		fn = fn,
		module = entry.module,
		slots = make(map[^Entity][]^fmag.IR_Value, context.temp_allocator),
		vec_expr = make(map[^Entity]^Expr, context.temp_allocator),
		vec_cache = make(map[^Entity][]^fmag.IR_Value, context.temp_allocator),
		horiz = make(map[^Call_Expr][]^fmag.IR_Value, context.temp_allocator),
		helpers = make(map[^Entity]^fmag.IR_Function, context.temp_allocator),
		work_lane = -1,
		ok = true,
	}
	pi: fmag.Length
	if pt.params != nil {
		for p in pt.params.variables {
			if p == nil || entity_is_poly_const(p) do continue
			w := fmag_width(p.type)
			if w <= 0 {
				fmag_err(&cg, "parameter '%s' is not an FMAG value", p.name)
				return
			}
			vals := make([]^fmag.IR_Value, w, context.temp_allocator)
			for i in 0 ..< w {
				vals[i] = fmag.ir_param(fn, pi)
				pi += 1
			}
			fmag_bind(&cg, p, vals)
		}
	}
	fmag_stmt(&cg, entry.proc_lit.body)
	if !cg.ok do return
	if !cg.returned {
		if rets == 0 {
			fmag.ir_ret(b, nil)
		} else {
			fmt.eprintfln("compile_fmag_entry: '%s' does not return", entry.name)
			return
		}
	}

	lowered_raw, arena_notes := fmag.lower_with_notes(b, fn)
	if lowered_raw.header.magic != fmag.MAGIC {
		fmt.eprintfln("compile_fmag_entry: '%s' failed to lower (unsupported control flow in FMAG IR?)", entry.name)
		return
	}
	notes = fmag_clone_notes(arena_notes, notes_allocator)
	raw = lowered_raw
	ok = true
	return
}

fmag_clone_notes :: proc(src: []string, allocator := context.allocator) -> []string {
	if len(src) == 0 do return nil
	out := make([]string, len(src), allocator)
	for n, i in src {
		if n != "" {
			out[i] = strings.clone(n, allocator)
		}
	}
	return out
}

fmag_free_notes :: proc(notes: []string, allocator := context.allocator) {
	for n in notes {
		if n != "" {
			delete(n, allocator)
		}
	}
	delete(notes, allocator)
}

fmag_squash_ws :: proc(s: string, allocator := context.allocator) -> string {
	if s == "" do return ""
	b: strings.Builder
	strings.builder_init(&b, allocator)
	space := false
	started := false
	for i in 0 ..< len(s) {
		c := s[i]
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
			if started {
				space = true
			}
			continue
		}
		if space {
			strings.write_byte(&b, ' ')
			space = false
		}
		strings.write_byte(&b, c)
		started = true
	}
	return strings.to_string(b)
}

fmag_call_note :: proc(cg: ^Fmag_CG, call: ^Call_Expr, callee: ^Entity) -> string {
	code := cg.module.code if cg.module != nil else ""
	start := call.pos.offset
	end := call.end.offset
	if start >= 0 && end <= len(code) && start < end {
		return fmag_squash_ws(code[start:end], fmag.ir_alloc(cg.b))
	}
	if callee != nil && callee.name != "" {
		return strings.clone(callee.name, fmag.ir_alloc(cg.b))
	}
	return ""
}

write_fmag_file :: proc(path: string, prog: fmag.Program) -> bool {
	n := size_of(fmag.HDR) + int(prog.stream.size)
	buf := make([]u8, n, context.temp_allocator)
	hdr := prog.header
	intrinsics.mem_copy(raw_data(buf), &hdr, size_of(fmag.HDR))
	if prog.stream.size > 0 && prog.stream.data != nil {
		intrinsics.mem_copy(raw_data(buf[size_of(fmag.HDR):]), prog.stream.data, int(prog.stream.size))
	}
	if write_err := os.write_entire_file(path, buf); write_err != nil {
		fmt.eprintfln("compile_fmag_entry: failed to write '%s'", path)
		return false
	}
	return true
}

emit_fmag_asm :: proc(entry: ^Entry, allocator := context.allocator) -> (text: string, ok: bool) {
	r, notes, cok := compile_fmag_entry_ex(entry, Target{formats = {.fmag_asm}}, Compile_Options{allocator = allocator})
	if !cok do return
	defer {
		if r.fmag.stream.data != nil {
			delete(([^]u8)(r.fmag.stream.data)[:int(r.fmag.stream.size)], allocator)
		}
		fmag_free_notes(notes, allocator)
	}
	text = strings.clone(r.fmag_asm, allocator)
	ok = true
	return
}

format_fmag_asm :: proc(name: string, prog: fmag.Program, notes: []string, allocator := context.allocator) -> string {
	return fmag.disassemble_named(prog.header, prog.stream, name, notes, allocator)
}

fmag_check_and_entity :: proc(entry: ^Entry, target: Target, _opts: Compile_Options) -> (live: ^Entity, ok: bool) {
	target := target_apply_compat(target)
	if entry == nil {
		fmt.eprintfln("compile_fmag_entry: nil entry")
		return
	}
	if entry.kind != .Fmag {
		fmt.eprintfln("compile_fmag_entry: '%s' is not proc \"fmag\"", entry.name)
		return
	}
	fm := target.formats & FMAG_TARGET_FORMATS
	gpu := target.formats & GPU_TARGET_FORMATS
	if fm == {} || gpu != {} {
		fmt.eprintfln("compile_fmag_entry: Target.formats must be FMAG-only (got %v)", target.formats)
		return
	}
	parsed := module_parsed_origin(entry.module)
	checked := check(parsed, target, Load_Options{soft_fail = true})
	if checked == nil {
		fmt.eprintfln("compile_fmag_entry: failed to check '%s'", entry.name)
		return
	}
	if checked.type_error_count != 0 {
		fmt.eprintfln("compile_fmag_entry: type errors in '%s'", entry.name)
		return
	}
	found := find_entry_with_name(checked, entry.name)
	if found == nil || found.entity == nil {
		fmt.eprintfln("compile_fmag_entry: entry '%s' not present after check", entry.name)
		return
	}
	entry.entity = found.entity
	pt, is_proc := found.entity.type.derived.(^Type_Proc)
	if !is_proc || !pt.is_fmag {
		fmt.eprintfln("compile_fmag_entry: '%s' is not proc \"fmag\"", entry.name)
		return
	}
	return found.entity, true
}

fmag_lower_entity :: proc(entry: ^Entity, allocator: runtime.Allocator) -> (prog: fmag.Program, notes: []string, ok: bool) {
	if entry == nil {
		fmt.eprintfln("compile_fmag_entry: nil entry")
		return
	}
	ctx := fmag.context_create(allocator)
	if ctx == nil {
		fmt.eprintfln("compile_fmag_entry: fmag context_create failed")
		return
	}
	defer fmag.context_delete(ctx)

	raw, nts, lowered := fmag_lower_proc(entry, ctx, allocator)
	notes = nts
	defer if lowered {
		fmag.program_delete(ctx, &raw)
	}
	if !lowered {
		fmag_free_notes(notes, allocator)
		notes = nil
		return
	}
	if raw.header.regs > FMAG_REGS {
		fmt.eprintfln("compile_fmag_entry: '%s' uses %d registers; core:fmag.REGS is %d — shrink the kernel",
			entry.name, raw.header.regs, FMAG_REGS)
		fmag_free_notes(notes, allocator)
		notes = nil
		return
	}

	copied: bool
	prog, copied = fmag_copy_program(raw, allocator)
	if !copied {
		fmt.eprintfln("compile_fmag_entry: copy failed")
		fmag_free_notes(notes, allocator)
		notes = nil
		return
	}
	ok = true
	return
}

// compile_fmag_entry walks a checked `proc "fmag"` body and lowers it to FMAG bytecode.
compile_fmag_entry :: proc(entry: ^Entry, target: Target, opts := Compile_Options{}) -> (Compile_Result, bool) {
	r, notes, compiled := compile_fmag_entry_ex(entry, target, opts)
	fmag_free_notes(notes, compile_allocator(opts))
	return r, compiled
}

// compile_fmag_entry_ex is compile_fmag_entry plus per-instruction inline notes for disassembly.
compile_fmag_entry_ex :: proc(entry: ^Entry, target: Target, opts := Compile_Options{}) -> (result: Compile_Result, notes: []string, ok: bool) {
	ent, cok := fmag_check_and_entity(entry, target, opts)
	if !cok {
		return
	}
	allocator := compile_allocator(opts)
	prog, nts, lowered := fmag_lower_entity(ent, allocator)
	notes = nts
	if !lowered {
		return
	}
	if .fmag in target.formats || .fmag_asm in target.formats {
		result.fmag = prog
	}
	if .fmag_asm in target.formats {
		result.fmag_asm = format_fmag_asm(entry.name, prog, notes, allocator)
	}
	ok = true
	return
}

call_is_fmag_exec :: proc(expr: ^Expr) -> bool {
	if expr == nil do return false
	call, ok := unparen_expr(expr).derived.(^Call_Expr)
	if !ok do return false
	e := entity_from_expr(call.expr)
	return e != nil && e.kind == .Builtin && e.builtin_id == .fmag_exec
}

fmag_run_entity :: proc(exec_e: ^Entity) -> ^Entity {
	if exec_e == nil || exec_e.module == nil || exec_e.module.scope == nil {
		return nil
	}
	e := scope_lookup_current(exec_e.module.scope, "run")
	if e != nil && e.kind == .Procedure {
		return e
	}
	return nil
}

fmag_exec_width :: proc(type: ^Type) -> int {
	if type == nil do return 0
	type := default_type(type)
	if type_is_float(type) && !type_is_vector(type) do return 1
	if v, ok := type.derived.(^Type_Vector); ok {
		if type_is_float(v.elem) && v.len >= 2 && v.len <= 4 {
			return int(v.len)
		}
	}
	return 0
}

type_is_fmag_bytecode_slice :: proc(type: ^Type) -> bool {
	if type == nil do return false
	s, ok := type.derived.(^Type_Slice)
	if !ok do return false
	v, vok := s.elem.derived.(^Type_Vector)
	return vok && v.len == 4 && type_eq(v.elem, t_u32)
}

check_fmag_exec :: proc(checker: ^Checker, call: ^Call_Expr, type_hint: ^Type) -> Operand {
	if checker.compile_mode == .FMAG {
		check_err(checker, call.pos, "fmag.exec is only valid on the GPU interpreter")
		return builtin_fail(checker, call)
	}
	if len(call.args) < 1 {
		check_err(checker, call.pos, "fmag.exec expects bytecode followed by f32 arguments, got %d argument%s",
			len(call.args), "" if len(call.args) == 1 else "s")
		return builtin_fail(checker, call)
	}

	code := check_expr(checker, call.args[0])
	if !type_is_fmag_bytecode_slice(code.type) {
		check_err(checker, call.args[0].pos, "fmag.exec expects [][4]u32 bytecode, got '%s'", string_from_type(code.type))
		return builtin_fail(checker, call)
	}

	arg_slots := 0
	for i in 1 ..< len(call.args) {
		arg := check_expr(checker, call.args[i])
		if type_is_untyped(arg.type) {
			convert_to_typed(checker, &arg, t_f32)
		}
		w := fmag_exec_width(arg.type)
		if w == 0 {
			check_err(checker, call.args[i].pos, "fmag.exec argument must be f32 or [2/3/4]f32, got '%s'", string_from_type(arg.type))
			return builtin_fail(checker, call)
		}
		arg_slots += w
	}
	if arg_slots > FMAG_REGS {
		check_err(checker, call.pos, "fmag.exec flattened arguments use %d registers; core:fmag.REGS is %d", arg_slots, FMAG_REGS)
		return builtin_fail(checker, call)
	}

	run := fmag_run_entity(entity_from_expr(call.expr))
	if run == nil {
		check_err(checker, call.pos, "fmag.exec requires core:fmag.run")
		return builtin_fail(checker, call)
	}
	ensure_entity_resolved(checker, run)
	ensure_proc_body_checked(checker, run)
	record_proc_call(checker, run, call.pos)

	if type_hint == nil || type_is_untyped(type_hint) {
		return builtin_no_value(call, .fmag_exec)
	}

	slots := type_split_tuple(type_hint)
	ret_slots := 0
	for slot in slots {
		w := fmag_exec_width(slot)
		if w == 0 {
			check_err(checker, call.pos, "fmag.exec result must be f32 or [2/3/4]f32, got '%s'", string_from_type(slot))
			return builtin_fail(checker, call)
		}
		ret_slots += w
	}
	if ret_slots > FMAG_REGS {
		check_err(checker, call.pos, "fmag.exec flattened results use %d registers; core:fmag.REGS is %d", ret_slots, FMAG_REGS)
		return builtin_fail(checker, call)
	}

	if len(slots) == 0 {
		return builtin_no_value(call, .fmag_exec)
	}
	if len(slots) == 1 {
		return builtin_value(call, .fmag_exec, slots[0])
	}
	return builtin_value(call, .fmag_exec, type_hint)
}
