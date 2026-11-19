// Copyright 2026 Dale Weiler
// SPDX-License-Identifier: MIT

package fmag

import "base:intrinsics"
import "base:runtime"
import "core:testing"

@(test)
test_cg_reg_is_qnan :: proc(t: ^testing.T) {
	w := cg_reg(0)
	testing.expect_value(t, w.u, u32(0x7FC00000))
	testing.expect(t, word_is_register(w))
	testing.expect_value(t, word_register(w), Register(0))

	w5 := cg_reg(5)
	testing.expect_value(t, w5.u, u32(0x7FC00005))
	testing.expect(t, word_is_register(w5))
	testing.expect_value(t, word_register(w5), Register(5))
}

@(test)
test_cg_imm_is_not_register :: proc(t: ^testing.T) {
	w := cg_imm(1)
	testing.expect(t, !word_is_register(w))
	w0 := cg_imm(0)
	testing.expect(t, !word_is_register(w0))
	wn := cg_imm(-2.5)
	testing.expect(t, !word_is_register(wn))
}

@(test)
test_vm_fused_multiply_add :: proc(t: ^testing.T) {
	ctx := context_create()
	defer context_delete(ctx)

	cg := cg_builder_create(context_allocator(ctx))
	// dst=0, a=1, b=imm 2, c=imm 3, guard=imm 1
	cg_fmag(cg, 0, 1, cg_imm(2), cg_imm(3), cg_imm(1))
	stream := cg_finalize(cg)
	cg_builder_delete(cg)
	defer {
		s := stream
		array_delete(context_allocator(ctx), &s.data)
	}

	regs := make([]f32, 2)
	defer delete(regs)
	regs[1] = 4
	vm_run_stream(stream, regs)
	testing.expect_value(t, regs[0], intrinsics.fused_mul_add(f32(4), f32(2), f32(3)))
}

@(test)
test_vm_false_guard_leaves_dst :: proc(t: ^testing.T) {
	ctx := context_create()
	defer context_delete(ctx)

	cg := cg_builder_create(context_allocator(ctx))
	cg_fmag(cg, 0, 1, cg_imm(2), cg_imm(3), cg_imm(0))
	stream := cg_finalize(cg)
	cg_builder_delete(cg)
	defer {
		s := stream
		array_delete(context_allocator(ctx), &s.data)
	}

	regs := make([]f32, 2)
	defer delete(regs)
	regs[0] = 99
	regs[1] = 4
	vm_run_stream(stream, regs)
	testing.expect_value(t, regs[0], f32(99))
}

@(test)
test_crc16_ccitt_false_vector :: proc(t: ^testing.T) {
	// CRC-16/CCITT-FALSE of "123456789" is 0x29B1.
	msg := "123456789"
	got := crc16(raw_data(msg), uint(len(msg)))
	testing.expect_value(t, got, u16(0x29B1))
}

@(test)
test_assemble_one_instruction :: proc(t: ^testing.T) {
	ctx := context_create()
	defer context_delete(ctx)
	src := `
.def main, 1, 1
%r0 = fmag %r0, $2, $3, $1
`
	prog := assemble(ctx, src)
	defer program_delete(ctx, &prog)
	testing.expect_value(t, prog.header.magic, MAGIC)
	testing.expect_value(t, prog.header.args, u16(1))
	testing.expect_value(t, prog.header.rets, u16(1))
	testing.expect(t, prog.stream.size == 16)

	regs := make([]f32, prog.header.regs)
	defer delete(regs)
	regs[0] = 4
	run(prog, regs)
	testing.expect_value(t, regs[0], intrinsics.fused_mul_add(f32(4), f32(2), f32(3)))
}

@(test)
test_assemble_roundtrip_stream :: proc(t: ^testing.T) {
	ctx := context_create()
	defer context_delete(ctx)
	src := `
.def main, 2, 1
; comment
%r1 = fmag %r0, $2, $0, $1
%r0 = fmag %r1, %r0, $0, $1
`
	a := assemble(ctx, src)
	defer program_delete(ctx, &a)
	testing.expect_value(t, a.header.magic, MAGIC)
	text := disassemble_text(a.header, a.stream, context.temp_allocator)
	b := assemble(ctx, text)
	defer program_delete(ctx, &b)
	testing.expect_value(t, b.header.magic, MAGIC)
	testing.expect_value(t, a.stream.size, b.stream.size)
	testing.expect(t, runtime.memory_compare(a.stream.data, b.stream.data, int(a.stream.size)) == 0)
}

@(test)
test_assemble_rejects_bad_def :: proc(t: ^testing.T) {
	ctx := context_create()
	defer context_delete(ctx)
	prog := assemble(ctx, ".def main, 0, 1\n%r0 = fmag %r1, $1, $0, $1\n")
	testing.expect_value(t, prog.header.magic, u32(0))
}

@(test)
test_load_rejects_bad_magic_and_crc :: proc(t: ^testing.T) {
	ok: bool
	_, _, ok = load_program([]u8{1, 2, 3})
	testing.expect(t, !ok)

	ctx := context_create()
	defer context_delete(ctx)
	prog := assemble(ctx, ".def main, 0, 1\n%r0 = fmag %r0, $0, $1, $1\n")
	defer program_delete(ctx, &prog)
	buf := make([]u8, size_of(HDR) + int(prog.stream.size))
	defer delete(buf)
	hdr := prog.header
	intrinsics.mem_copy(raw_data(buf), &hdr, size_of(HDR))
	intrinsics.mem_copy(raw_data(buf[size_of(HDR):]), prog.stream.data, int(prog.stream.size))
	_, _, ok = load_program(buf)
	testing.expect(t, ok)
	buf[size_of(HDR)] ~= 1
	_, _, ok = load_program(buf)
	testing.expect(t, !ok)
}

op_count :: proc(function: ^IR_Function) -> int {
	n := 0
	for block in function.blocks {
		n += len(block.instructions)
	}
	return n
}

@(test)
test_ir_sugar_is_fmag :: proc(t: ^testing.T) {
	ctx := context_create()
	defer context_delete(ctx)
	builder := ir_builder_create(ctx, false)
	defer ir_builder_delete(builder)
	fn := ir_function(builder, "main", 2, 1)
	ir_block(builder, fn)
	x := ir_param(fn, 0)
	y := ir_param(fn, 1)

	add := ir_add(builder, x, y)
	testing.expect_value(t, add.kind, IR_Kind.Op)
	testing.expect(t, add.operands[0] == x)
	testing.expect_value(t, add.operands[1].kind, IR_Kind.Const)
	testing.expect_value(t, add.operands[1].value, f32(1))
	testing.expect(t, add.operands[2] == y)
	testing.expect_value(t, add.operands[3].kind, IR_Kind.Const)
	testing.expect_value(t, add.operands[3].value, f32(0))
	testing.expect_value(t, add.operands[4].value, f32(1))

	mul := ir_mul(builder, x, y)
	testing.expect(t, mul.operands[0] == x)
	testing.expect(t, mul.operands[1] == y)
	testing.expect_value(t, mul.operands[2].value, f32(0))

	sel := ir_select(builder, x, y, mul)
	testing.expect(t, sel.operands[0] == x)
	testing.expect_value(t, sel.operands[1].value, f32(1))
	testing.expect_value(t, sel.operands[2].value, f32(0))
	testing.expect(t, sel.operands[3] == y)
	testing.expect(t, sel.operands[4] == mul)

	abs := ir_abs(builder, x)
	testing.expect(t, abs.operands[0] == x)
	testing.expect(t, abs.operands[3].kind == .Op)
	testing.expect(t, abs.operands[4] == x)
}

@(test)
test_ir_cond_br_phi_and_call :: proc(t: ^testing.T) {
	ctx := context_create()
	defer context_delete(ctx)
	builder := ir_builder_create(ctx, false)
	defer ir_builder_delete(builder)

	callee := ir_function(builder, "pair", 1, 2)
	ir_block(builder, callee)
	p := ir_param(callee, 0)
	one := ir_const(builder, 1)
	second := ir_add(builder, p, one)
	pair := [2]^IR_Value{p, second}
	ir_ret(builder, pair[:])

	fn := ir_function(builder, "main", 1, 1)
	entry := ir_block(builder, fn)
	then_b := ir_block(builder, fn)
	else_b := ir_block(builder, fn)
	merge := ir_block(builder, fn)
	x := ir_param(fn, 0)
	ir_position(builder, entry)
	ir_cond_br(builder, x, then_b, else_b)
	ir_position(builder, then_b)
	args := [1]^IR_Value{x}
	call := ir_call(builder, callee, args[:])
	got := ir_result(builder, call, 1)
	ir_br(builder, merge)
	ir_position(builder, else_b)
	ir_br(builder, merge)
	ir_position(builder, merge)
	phi := ir_phi(builder)
	ir_phi_edge(builder, phi, then_b, got)
	ir_phi_edge(builder, phi, else_b, x)
	rets := [1]^IR_Value{phi}
	ir_ret(builder, rets[:])

	testing.expect_value(t, entry.term, IR_Term.Cond_Br)
	testing.expect(t, entry.then_block == then_b)
	testing.expect(t, entry.else_block == else_b)
	testing.expect_value(t, phi.kind, IR_Kind.Phi)
	testing.expect_value(t, len(phi.edges), 2)
	testing.expect_value(t, call.kind, IR_Kind.Call)
	testing.expect(t, ir_result(builder, call, 0) == call)
	testing.expect_value(t, got.kind, IR_Kind.Result)
	testing.expect_value(t, got.index, Length(1))
}

@(test)
test_ir_runtime_rcp_div_names :: proc(t: ^testing.T) {
	ctx := context_create()
	defer context_delete(ctx)
	builder := ir_builder_create(ctx, false)
	defer ir_builder_delete(builder)
	rcp := ir_runtime_rcp(builder)
	div := ir_runtime_div(builder)
	testing.expect(t, string_is(rcp.name, "__rcp"))
	testing.expect(t, string_is(div.name, "__div"))
	testing.expect_value(t, rcp.param_count, Length(1))
	testing.expect_value(t, div.param_count, Length(2))
}

@(test)
test_lower_rejects_recursion :: proc(t: ^testing.T) {
	ctx := context_create()
	defer context_delete(ctx)
	builder := ir_builder_create(ctx, false)
	defer ir_builder_delete(builder)
	a := ir_function(builder, "a", 1, 1)
	b := ir_function(builder, "b", 1, 1)
	ir_block(builder, a)
	xa := ir_param(a, 0)
	args_a := [1]^IR_Value{xa}
	ca := ir_call(builder, b, args_a[:])
	rets_a := [1]^IR_Value{ca}
	ir_ret(builder, rets_a[:])
	ir_block(builder, b)
	xb := ir_param(b, 0)
	args_b := [1]^IR_Value{xb}
	cb := ir_call(builder, a, args_b[:])
	rets_b := [1]^IR_Value{cb}
	ir_ret(builder, rets_b[:])

	prog := lower(builder, a)
	defer program_delete(ctx, &prog)
	testing.expect_value(t, prog.header.magic, u32(0))
}

@(test)
test_opt_fuse_mul_add :: proc(t: ^testing.T) {
	ctx := context_create()
	defer context_delete(ctx)
	builder := ir_builder_create(ctx, false)
	defer ir_builder_delete(builder)
	fn := ir_function(builder, "main", 2, 1)
	ir_block(builder, fn)
	x := ir_param(fn, 0)
	y := ir_param(fn, 1)
	prod := ir_mul(builder, x, ir_const(builder, 1))
	sum := ir_add(builder, prod, y)
	rets := [1]^IR_Value{sum}
	ir_ret(builder, rets[:])
	testing.expect_value(t, op_count(fn), 2)
	ir_optimize(builder)
	testing.expect_value(t, op_count(fn), 1)
	op := fn.blocks[0].instructions[0]
	testing.expect(t, op.operands[0] == x)
	testing.expect_value(t, op.operands[1].value, f32(1))
	testing.expect(t, op.operands[2] == y)
}

@(test)
test_opt_fold_mul_zero_and_equal_select :: proc(t: ^testing.T) {
	ctx := context_create()
	defer context_delete(ctx)

	fast := ir_builder_create(ctx, true)
	defer ir_builder_delete(fast)
	fn := ir_function(fast, "main", 1, 1)
	ir_block(fast, fn)
	x := ir_param(fn, 0)
	z := ir_mul(fast, x, ir_const(fast, 0))
	rets := [1]^IR_Value{z}
	ir_ret(fast, rets[:])
	ir_optimize(fast)
	testing.expect_value(t, op_count(fn), 0)
	testing.expect_value(t, fn.blocks[0].results[0].kind, IR_Kind.Const)
	testing.expect_value(t, fn.blocks[0].results[0].value, f32(0))

	builder := ir_builder_create(ctx, false)
	defer ir_builder_delete(builder)
	fn2 := ir_function(builder, "sel", 2, 1)
	ir_block(builder, fn2)
	a := ir_param(fn2, 0)
	g := ir_param(fn2, 1)
	sel := ir_select(builder, a, a, g)
	rets2 := [1]^IR_Value{sel}
	ir_ret(builder, rets2[:])
	ir_optimize(builder)
	testing.expect_value(t, op_count(fn2), 0)
	testing.expect(t, fn2.blocks[0].results[0] == a)
}

@(test)
test_select_pass_collapses_diamond :: proc(t: ^testing.T) {
	ctx := context_create()
	defer context_delete(ctx)
	builder := ir_builder_create(ctx, false)
	defer ir_builder_delete(builder)
	fn := ir_function(builder, "main", 1, 1)
	entry := ir_block(builder, fn)
	then_b := ir_block(builder, fn)
	else_b := ir_block(builder, fn)
	merge := ir_block(builder, fn)
	x := ir_param(fn, 0)
	one := ir_const(builder, 1)
	ir_position(builder, entry)
	ir_cond_br(builder, x, then_b, else_b)
	ir_position(builder, then_b)
	tv := ir_add(builder, x, one)
	ir_br(builder, merge)
	ir_position(builder, else_b)
	ev := ir_sub(builder, x, one)
	ir_br(builder, merge)
	ir_position(builder, merge)
	phi := ir_phi(builder)
	ir_phi_edge(builder, phi, then_b, tv)
	ir_phi_edge(builder, phi, else_b, ev)
	rets := [1]^IR_Value{phi}
	ir_ret(builder, rets[:])
	testing.expect_value(t, len(fn.blocks), 4)
	ir_select_pass(builder)
	testing.expect_value(t, len(fn.blocks), 1)
	testing.expect_value(t, fn.blocks[0].term, IR_Term.Ret)
	has_phi := false
	has_select := false
	for op in fn.blocks[0].instructions {
		if op.kind == .Phi {
			has_phi = true
		}
		if op.kind == .Op && op.operands[1].kind == .Const && op.operands[1].value == 1 &&
		   op.operands[2].kind == .Const && op.operands[2].value == 0 &&
		   op.operands[4] == x {
			has_select = true
		}
	}
	testing.expect(t, !has_phi)
	testing.expect(t, has_select)
}

@(test)
test_lower_rejects_back_edge :: proc(t: ^testing.T) {
	ctx := context_create()
	defer context_delete(ctx)
	builder := ir_builder_create(ctx, false)
	defer ir_builder_delete(builder)
	fn := ir_function(builder, "loop", 1, 1)
	entry := ir_block(builder, fn)
	body := ir_block(builder, fn)
	exit := ir_block(builder, fn)
	x := ir_param(fn, 0)
	ir_position(builder, entry)
	ir_cond_br(builder, x, body, exit)
	ir_position(builder, body)
	ir_br(builder, entry)
	ir_position(builder, exit)
	rets := [1]^IR_Value{x}
	ir_ret(builder, rets[:])
	prog := lower(builder, fn)
	defer program_delete(ctx, &prog)
	testing.expect_value(t, prog.header.magic, u32(0))
}

@(test)
test_lower_abi_and_run :: proc(t: ^testing.T) {
	ctx := context_create()
	defer context_delete(ctx)
	builder := ir_builder_create(ctx, false)
	defer ir_builder_delete(builder)
	fn := ir_function(builder, "main", 2, 1)
	ir_block(builder, fn)
	x := ir_param(fn, 0)
	y := ir_param(fn, 1)
	sum := ir_add(builder, x, y)
	rets := [1]^IR_Value{sum}
	ir_ret(builder, rets[:])
	prog := lower(builder, fn)
	defer program_delete(ctx, &prog)
	testing.expect_value(t, prog.header.magic, MAGIC)
	testing.expect_value(t, prog.header.args, u16(2))
	testing.expect_value(t, prog.header.rets, u16(1))
	regs := make([]f32, prog.header.regs)
	defer delete(regs)
	regs[0] = 2
	regs[1] = 3
	run(prog, regs)
	testing.expect_value(t, regs[0], f32(5))
}

@(test)
test_fast_math_reassociates :: proc(t: ^testing.T) {
	build :: proc(ctx: ^Context, fast: bool) -> int {
		builder := ir_builder_create(ctx, fast)
		defer ir_builder_delete(builder)
		fn := ir_function(builder, "main", 1, 1)
		ir_block(builder, fn)
		x := ir_param(fn, 0)
		t1 := ir_mul(builder, x, ir_const(builder, 2))
		t2 := ir_mul(builder, t1, ir_const(builder, 3))
		rets := [1]^IR_Value{t2}
		ir_ret(builder, rets[:])
		ir_optimize(builder)
		return op_count(fn)
	}
	ctx := context_create()
	defer context_delete(ctx)
	testing.expect_value(t, build(ctx, false), 2)
	testing.expect_value(t, build(ctx, true), 1)
}
