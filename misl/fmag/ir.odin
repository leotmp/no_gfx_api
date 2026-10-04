// Copyright 2026 Dale Weiler
// SPDX-License-Identifier: MIT

package fmag

import "base:runtime"
import "core:fmt"
import "core:strings"

IR_Kind :: enum {
	Const,
	Param,
	Return,
	Op,
	Call,
	Phi,
	Result,
}

IR_Term :: enum {
	None,
	Br,
	Cond_Br,
	Ret,
}

IR_Edge :: struct {
	from:  ^IR_Block,
	value: ^IR_Value,
}

IR_Value :: struct {
	kind:         IR_Kind,
	id:           Length,
	value:        f32,
	index:        Length,
	operands:     [5]^IR_Value,
	callee:       ^IR_Function,
	args:         [^]^IR_Value,
	arg_count:    Length,
	edges:        [dynamic]IR_Edge,
	results:      [^]^IR_Value,
	result_count: Length,
	note:         string, // inlined-call comment; empty if none
}

IR_Block :: struct {
	function:     ^IR_Function,
	id:           Length,
	instructions: [dynamic]^IR_Value,
	term:         IR_Term,
	guard:        ^IR_Value,
	then_block:   ^IR_Block,
	else_block:   ^IR_Block,
	results:      [dynamic]^IR_Value,
}

IR_Function :: struct {
	name:         String,
	params:       [^]IR_Value,
	param_count:  Length,
	returns:      [^]IR_Value,
	return_count: Length,
	blocks:       [dynamic]^IR_Block,
}

IR_Builder :: struct {
	ctx:       ^Context,
	arena:     Arena,
	functions: [dynamic]^IR_Function,
	current:   ^IR_Block,
	next_id:   Length,
	fast_math: bool,
}

ir_alloc :: proc(b: ^IR_Builder) -> runtime.Allocator {
	return odin_allocator(&b.arena.allocator)
}

ir_builder_create :: proc(ctx: ^Context, fast_math: bool) -> ^IR_Builder {
	plain := context_allocator(ctx)
	builder := (^IR_Builder)(mem_alloc(plain, size_of(IR_Builder)))
	if builder == nil {
		return nil
	}
	builder.ctx = ctx
	arena_init(&builder.arena, plain)
	builder.functions = make([dynamic]^IR_Function, ir_alloc(builder))
	builder.current = nil
	builder.next_id = 0
	builder.fast_math = fast_math
	return builder
}

ir_builder_delete :: proc(builder: ^IR_Builder) {
	if builder == nil {
		return
	}
	plain := context_allocator(builder.ctx)
	arena_destroy(&builder.arena)
	mem_free(plain, builder)
}

ir_value_new :: proc(builder: ^IR_Builder, kind: IR_Kind) -> ^IR_Value {
	value := new(IR_Value, ir_alloc(builder))
	value.kind = kind
	if kind == .Op || kind == .Call || kind == .Phi || kind == .Result {
		value.id = builder.next_id
		builder.next_id += 1
	}
	if kind == .Phi {
		value.edges = make([dynamic]IR_Edge, ir_alloc(builder))
	}
	return value
}

ir_function :: proc(builder: ^IR_Builder, name: string, params, returns: Length) -> ^IR_Function {
	return ir_function_string(builder, string_from_odin(name), params, returns)
}

ir_function_string :: proc(builder: ^IR_Builder, name: String, params, returns: Length) -> ^IR_Function {
	a := &builder.arena.allocator
	function := new(IR_Function, ir_alloc(builder))
	function.name = string_copy(a, name)
	function.param_count = params
	if params != 0 {
		function.params = ([^]IR_Value)(mem_alloc(a, params * size_of(IR_Value)))
		for i in 0 ..< params {
			function.params[i].kind = .Param
			function.params[i].index = i
		}
	}
	function.return_count = returns
	if returns != 0 {
		function.returns = ([^]IR_Value)(mem_alloc(a, returns * size_of(IR_Value)))
		for i in 0 ..< returns {
			function.returns[i].kind = .Return
			function.returns[i].index = i
		}
	}
	function.blocks = make([dynamic]^IR_Block, ir_alloc(builder))
	append(&builder.functions, function)
	return function
}

ir_param :: proc(function: ^IR_Function, index: Length) -> ^IR_Value {
	if index < function.param_count {
		return &function.params[index]
	}
	return nil
}

ir_block :: proc(builder: ^IR_Builder, function: ^IR_Function) -> ^IR_Block {
	block := new(IR_Block, ir_alloc(builder))
	block.function = function
	block.id = Length(len(function.blocks))
	block.instructions = make([dynamic]^IR_Value, ir_alloc(builder))
	block.results = make([dynamic]^IR_Value, ir_alloc(builder))
	append(&function.blocks, block)
	builder.current = block
	return block
}

ir_position :: proc(builder: ^IR_Builder, block: ^IR_Block) {
	builder.current = block
}

ir_current :: proc(builder: ^IR_Builder) -> ^IR_Block {
	return builder.current
}

ir_const :: proc(builder: ^IR_Builder, value: f32) -> ^IR_Value {
	result := ir_value_new(builder, .Const)
	result.value = value
	return result
}

ir_is_const :: proc(value: ^IR_Value, out: ^f32) -> bool {
	if value.kind != .Const {
		return false
	}
	if out != nil {
		out^ = value.value
	}
	return true
}

ir_fmag :: proc(builder: ^IR_Builder, a, b, c, d, e: ^IR_Value) -> ^IR_Value {
	result := ir_value_new(builder, .Op)
	result.operands = {a, b, c, d, e}
	append(&builder.current.instructions, result)
	return result
}

ir_call :: proc(builder: ^IR_Builder, callee: ^IR_Function, args: []^IR_Value) -> ^IR_Value {
	a := &builder.arena.allocator
	result := ir_value_new(builder, .Call)
	result.callee = callee
	result.arg_count = Length(len(args))
	if result.arg_count != 0 {
		result.args = ([^]^IR_Value)(mem_alloc(a, result.arg_count * size_of(^IR_Value)))
		for i in 0 ..< result.arg_count {
			result.args[i] = args[i]
		}
	}
	result.result_count = callee.return_count
	n := callee.return_count if callee.return_count != 0 else 1
	result.results = ([^]^IR_Value)(mem_alloc(a, n * size_of(^IR_Value)))
	result.results[0] = result
	append(&builder.current.instructions, result)
	return result
}

ir_result :: proc(builder: ^IR_Builder, call: ^IR_Value, index: Length) -> ^IR_Value {
	if index >= call.result_count {
		return nil
	}
	if call.results[index] == nil {
		projection := ir_value_new(builder, .Result)
		projection.operands[0] = call
		projection.index = index
		call.results[index] = projection
	}
	return call.results[index]
}

ir_phi :: proc(builder: ^IR_Builder) -> ^IR_Value {
	phi := ir_value_new(builder, .Phi)
	append(&builder.current.instructions, phi)
	return phi
}

ir_phi_edge :: proc(builder: ^IR_Builder, phi: ^IR_Value, from: ^IR_Block, value: ^IR_Value) {
	append(&phi.edges, IR_Edge{from = from, value = value})
}

ir_br :: proc(builder: ^IR_Builder, target: ^IR_Block) {
	builder.current.term = .Br
	builder.current.then_block = target
}

ir_cond_br :: proc(builder: ^IR_Builder, guard: ^IR_Value, then_block, else_block: ^IR_Block) {
	builder.current.term = .Cond_Br
	builder.current.guard = guard
	builder.current.then_block = then_block
	builder.current.else_block = else_block
}

ir_ret :: proc(builder: ^IR_Builder, values: []^IR_Value) {
	builder.current.term = .Ret
	for v in values {
		append(&builder.current.results, v)
	}
}

ir_fma :: proc(builder: ^IR_Builder, a, b, c: ^IR_Value) -> ^IR_Value {
	return ir_fmag(builder, a, b, c, ir_const(builder, 0), ir_const(builder, 1))
}
ir_add :: proc(builder: ^IR_Builder, a, b: ^IR_Value) -> ^IR_Value {
	return ir_fma(builder, a, ir_const(builder, 1), b)
}
ir_sub :: proc(builder: ^IR_Builder, a, b: ^IR_Value) -> ^IR_Value {
	return ir_fma(builder, b, ir_const(builder, -1), a)
}
ir_mul :: proc(builder: ^IR_Builder, a, b: ^IR_Value) -> ^IR_Value {
	return ir_fma(builder, a, b, ir_const(builder, 0))
}
ir_neg :: proc(builder: ^IR_Builder, a: ^IR_Value) -> ^IR_Value {
	return ir_fma(builder, a, ir_const(builder, -1), ir_const(builder, 0))
}
ir_select :: proc(builder: ^IR_Builder, t, f, g: ^IR_Value) -> ^IR_Value {
	return ir_fmag(builder, t, ir_const(builder, 1), ir_const(builder, 0), f, g)
}
ir_max :: proc(builder: ^IR_Builder, a, b: ^IR_Value) -> ^IR_Value {
	return ir_select(builder, a, b, ir_sub(builder, a, b))
}
ir_min :: proc(builder: ^IR_Builder, a, b: ^IR_Value) -> ^IR_Value {
	return ir_select(builder, b, a, ir_sub(builder, a, b))
}
ir_abs :: proc(builder: ^IR_Builder, a: ^IR_Value) -> ^IR_Value {
	return ir_select(builder, a, ir_neg(builder, a), a)
}
ir_clamp :: proc(builder: ^IR_Builder, x, lo, hi: ^IR_Value) -> ^IR_Value {
	return ir_min(builder, ir_max(builder, x, lo), hi)
}
ir_gt :: proc(builder: ^IR_Builder, a, b: ^IR_Value) -> ^IR_Value {
	return ir_select(builder, ir_const(builder, 1), ir_const(builder, 0), ir_sub(builder, a, b))
}
ir_lt :: proc(builder: ^IR_Builder, a, b: ^IR_Value) -> ^IR_Value {
	return ir_gt(builder, b, a)
}
ir_gte :: proc(builder: ^IR_Builder, a, b: ^IR_Value) -> ^IR_Value {
	return ir_sub(builder, ir_const(builder, 1), ir_lt(builder, a, b))
}
ir_lte :: proc(builder: ^IR_Builder, a, b: ^IR_Value) -> ^IR_Value {
	return ir_sub(builder, ir_const(builder, 1), ir_gt(builder, a, b))
}

ir_function_named :: proc(builder: ^IR_Builder, name: String, params: Length) -> ^IR_Function {
	for function in builder.functions {
		if function.param_count == params && string_same(function.name, name) {
			return function
		}
	}
	return nil
}

ir_rcp :: proc(builder: ^IR_Builder, x: ^IR_Value) -> ^IR_Value {
	rcp := ir_function_named(builder, string_from("__rcp"), 1)
	if rcp == nil {
		return nil
	}
	args := [1]^IR_Value{x}
	return ir_call(builder, rcp, args[:])
}

ir_div :: proc(builder: ^IR_Builder, a, b: ^IR_Value) -> ^IR_Value {
	div := ir_function_named(builder, string_from("__div"), 2)
	if div == nil {
		return nil
	}
	args := [2]^IR_Value{a, b}
	return ir_call(builder, div, args[:])
}

ir_pow2 :: proc(exponent: int) -> f32 {
	value: f32 = 1
	factor: f32 = 0.5 if exponent < 0 else 2
	steps := -exponent if exponent < 0 else exponent
	for _ in 0 ..< steps {
		value *= factor
	}
	return value
}

ir_rcp_rung :: proc(builder: ^IR_Builder, function: ^IR_Function, cond, factor: ^IR_Value, m, r: ^^IR_Value) {
	entry := ir_current(builder)
	scaled := ir_block(builder, function)
	merge := ir_block(builder, function)
	ir_position(builder, entry)
	ir_cond_br(builder, cond, scaled, merge)
	ir_position(builder, scaled)
	m_scaled := ir_mul(builder, m^, factor)
	r_scaled := ir_mul(builder, r^, factor)
	ir_br(builder, merge)
	ir_position(builder, merge)
	m_merged := ir_phi(builder)
	ir_phi_edge(builder, m_merged, entry, m^)
	ir_phi_edge(builder, m_merged, scaled, m_scaled)
	r_merged := ir_phi(builder)
	ir_phi_edge(builder, r_merged, entry, r^)
	ir_phi_edge(builder, r_merged, scaled, r_scaled)
	m^ = m_merged
	r^ = r_merged
}

ir_runtime_rcp :: proc(builder: ^IR_Builder) -> ^IR_Function {
	function := ir_function(builder, "__rcp", 1, 1)
	ir_block(builder, function)
	x := ir_param(function, 0)
	sign := ir_select(builder, ir_const(builder, -1), ir_const(builder, 1), ir_lt(builder, x, ir_const(builder, 0)))
	m := ir_abs(builder, x)
	r := ir_const(builder, 1)

	high := [7]int{64, 32, 16, 8, 4, 2, 1}
	for h in high {
		cond := ir_gte(builder, m, ir_const(builder, ir_pow2(h)))
		ir_rcp_rung(builder, function, cond, ir_const(builder, ir_pow2(-h)), &m, &r)
	}
	low := [8]int{-64, -32, -16, -8, -4, -2, -1, 0}
	for l in low {
		up := -l if l < 0 else 1
		cond := ir_lt(builder, m, ir_const(builder, ir_pow2(l)))
		ir_rcp_rung(builder, function, cond, ir_const(builder, ir_pow2(up)), &m, &r)
	}

	y := ir_sub(builder, ir_const(builder, 1.5), ir_mul(builder, ir_const(builder, 0.5), m))
	for _ in 0 ..< 3 {
		t := ir_sub(builder, ir_const(builder, 2), ir_mul(builder, m, y))
		y = ir_mul(builder, y, t)
	}
	result := ir_mul(builder, ir_mul(builder, sign, r), y)
	rets := [1]^IR_Value{result}
	ir_ret(builder, rets[:])
	return function
}

ir_runtime_div :: proc(builder: ^IR_Builder) -> ^IR_Function {
	function := ir_function(builder, "__div", 2, 1)
	ir_block(builder, function)
	a := ir_param(function, 0)
	b := ir_param(function, 1)
	one := ir_const(builder, 1)
	neg_b := ir_neg(builder, b)
	y := ir_rcp(builder, b)
	y = ir_fma(builder, y, ir_fma(builder, neg_b, y, one), y)
	y = ir_fma(builder, y, ir_fma(builder, neg_b, y, one), y)
	q := ir_mul(builder, a, y)
	result := ir_fma(builder, y, ir_fma(builder, neg_b, q, a), q)
	rets := [1]^IR_Value{result}
	ir_ret(builder, rets[:])
	return function
}

value_print :: proc(b: ^strings.Builder, value: ^IR_Value) {
	switch value.kind {
	case .Const:
		fmt.sbprintf(b, "%g", value.value)
	case .Param:
		fmt.sbprintf(b, "p%v", value.index)
	case .Return:
		fmt.sbprintf(b, "%%r%v", value.index)
	case .Op, .Call, .Phi:
		fmt.sbprintf(b, "%%r%v", value.id)
	case .Result:
		fmt.sbprintf(b, "%%r%v.%v", value.operands[0].id, value.index)
	}
}

ir_dump_text :: proc(builder: ^IR_Builder, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	for function in builder.functions {
		fmt.sbprintf(&b, "fn %s(", string_to_odin(function.name))
		for i in 0 ..< function.param_count {
			if i != 0 {
				fmt.sbprint(&b, ", ")
			}
			fmt.sbprintf(&b, "p%v", function.params[i].index)
		}
		fmt.sbprint(&b, ") -> (")
		for i in 0 ..< function.return_count {
			if i != 0 {
				fmt.sbprint(&b, ", ")
			}
			fmt.sbprintf(&b, "r%v", function.returns[i].index)
		}
		fmt.sbprint(&b, "):\n")
		for block in function.blocks {
			fmt.sbprintf(&b, "  block %v:\n", block.id)
			for op in block.instructions {
				if op.kind == .Call {
					fmt.sbprintf(&b, "    %%r%v = call %s(", op.id, string_to_odin(op.callee.name))
					for k in 0 ..< op.arg_count {
						if k != 0 {
							fmt.sbprint(&b, ", ")
						}
						value_print(&b, op.args[k])
					}
					fmt.sbprint(&b, ")\n")
					continue
				}
				if op.kind == .Phi {
					fmt.sbprintf(&b, "    %%r%v = phi ", op.id)
					for k in 0 ..< len(op.edges) {
						if k != 0 {
							fmt.sbprint(&b, ", ")
						}
						fmt.sbprintf(&b, "[block %v: ", op.edges[k].from.id)
						value_print(&b, op.edges[k].value)
						fmt.sbprint(&b, "]")
					}
					fmt.sbprint(&b, "\n")
					continue
				}
				fmt.sbprintf(&b, "    %%r%v = fmag ", op.id)
				for k in 0 ..< 5 {
					if k != 0 {
						fmt.sbprint(&b, ", ")
					}
					value_print(&b, op.operands[k])
				}
				fmt.sbprint(&b, "\n")
			}
			switch block.term {
			case .Br:
				fmt.sbprintf(&b, "    br block %v\n", block.then_block.id)
			case .Cond_Br:
				fmt.sbprint(&b, "    cond_br ")
				value_print(&b, block.guard)
				fmt.sbprintf(&b, ", block %v, block %v\n", block.then_block.id, block.else_block.id)
			case .Ret:
				fmt.sbprint(&b, "    ret")
				for r in block.results {
					fmt.sbprint(&b, " ")
					value_print(&b, r)
				}
				fmt.sbprint(&b, "\n")
			case .None:
				fmt.sbprint(&b, "    <no terminator>\n")
			}
		}
	}
	return strings.to_string(b)
}

ir_dump :: proc(builder: ^IR_Builder) {
	fmt.print(ir_dump_text(builder, context.temp_allocator))
}
