// Copyright 2026 Dale Weiler
// SPDX-License-Identifier: MIT

package fmag

import "base:runtime"

// Opt-in C ABI. Default off: exporting these into mislc.exe mixes MSVC ucrt.lib
// with glslang's static CRT (/NODEFAULTLIB:libcmt). Enable with -define:FMAG_C_ABI=true.
when #config(FMAG_C_ABI, false) {

@(export, link_name = "fmag_context_create")
fmag_context_create :: proc "c" (allocator: ^Allocator) -> ^Context {
	context = runtime.default_context()
	return context_create_c(allocator)
}

@(export, link_name = "fmag_context_delete")
fmag_context_delete :: proc "c" (ctx: ^Context) {
	context = runtime.default_context()
	context_delete(ctx)
}

@(export, link_name = "fmag_context_allocator")
fmag_context_allocator :: proc "c" (ctx: ^Context) -> ^Allocator {
	context = runtime.default_context()
	return context_allocator(ctx)
}

@(export, link_name = "fmag_allocate")
fmag_allocate :: proc "c" (allocator: ^Allocator, size: Length) -> rawptr {
	context = runtime.default_context()
	return mem_alloc(allocator, size)
}

@(export, link_name = "fmag_reallocate")
fmag_reallocate :: proc "c" (allocator: ^Allocator, pointer: rawptr, old_size, new_size: Length) -> rawptr {
	context = runtime.default_context()
	return mem_realloc(allocator, pointer, old_size, new_size)
}

@(export, link_name = "fmag_deallocate")
fmag_deallocate :: proc "c" (allocator: ^Allocator, pointer: rawptr) {
	context = runtime.default_context()
	mem_free(allocator, pointer)
}

@(export, link_name = "fmag_string_is")
fmag_string_is :: proc "c" (a: String, literal: cstring) -> bool {
	context = runtime.default_context()
	return string_is(a, literal)
}

@(export, link_name = "fmag_string_same")
fmag_string_same :: proc "c" (a, b: String) -> bool {
	context = runtime.default_context()
	return string_same(a, b)
}

@(export, link_name = "fmag_string_starts")
fmag_string_starts :: proc "c" (a: String, prefix: cstring) -> bool {
	context = runtime.default_context()
	return string_starts(a, prefix)
}

@(export, link_name = "fmag_string_from")
fmag_string_from :: proc "c" (text: cstring) -> String {
	context = runtime.default_context()
	return string_from(text)
}

@(export, link_name = "fmag_string_copy")
fmag_string_copy :: proc "c" (allocator: ^Allocator, text: String) -> String {
	context = runtime.default_context()
	return string_copy(allocator, text)
}

@(export, link_name = "fmag_crc16")
fmag_crc16 :: proc "c" (data: rawptr, size: Length) -> u16 {
	context = runtime.default_context()
	return crc16(data, size)
}

@(export, link_name = "fmag_arena_init")
fmag_arena_init :: proc "c" (arena: ^Arena, backing: ^Allocator) {
	context = runtime.default_context()
	arena_init(arena, backing)
}

@(export, link_name = "fmag_arena_destroy")
fmag_arena_destroy :: proc "c" (arena: ^Arena) {
	context = runtime.default_context()
	arena_destroy(arena)
}

@(export, link_name = "fmag_array_reserve")
fmag_array_reserve :: proc "c" (allocator: ^Allocator, array: ^rawptr, needed, type_size: Length) -> bool {
	context = runtime.default_context()
	return array_reserve(allocator, array, needed, type_size)
}

@(export, link_name = "fmag_array_resize_untyped")
fmag_array_resize_untyped :: proc "c" (allocator: ^Allocator, array: ^rawptr, n, type_size: Length) {
	context = runtime.default_context()
	array_resize(allocator, array, n, type_size)
}

@(export, link_name = "fmag_array_append_untyped")
fmag_array_append_untyped :: proc "c" (allocator: ^Allocator, array: ^rawptr, src: rawptr, n, type_size: Length) {
	context = runtime.default_context()
	array_append(allocator, array, src, n, type_size)
}

@(export, link_name = "fmag_array_delete_untyped")
fmag_array_delete_untyped :: proc "c" (allocator: ^Allocator, array: ^rawptr) {
	context = runtime.default_context()
	array_delete(allocator, array)
}

@(export, link_name = "fmag_program_delete")
fmag_program_delete :: proc "c" (ctx: ^Context, program: ^Program) {
	context = runtime.default_context()
	program_delete(ctx, program)
}

@(export, link_name = "fmag_cg_builder_create")
fmag_cg_builder_create :: proc "c" (allocator: ^Allocator) -> ^CG_Builder {
	context = runtime.default_context()
	return cg_builder_create(allocator)
}

@(export, link_name = "fmag_cg_builder_delete")
fmag_cg_builder_delete :: proc "c" (builder: ^CG_Builder) {
	context = runtime.default_context()
	cg_builder_delete(builder)
}

@(export, link_name = "fmag_cg_reg")
fmag_cg_reg :: proc "c" (reg: Register) -> Word {
	context = runtime.default_context()
	return cg_reg(reg)
}

@(export, link_name = "fmag_cg_imm")
fmag_cg_imm :: proc "c" (value: f32) -> Word {
	context = runtime.default_context()
	return cg_imm(value)
}

@(export, link_name = "fmag_cg_word_is_register")
fmag_cg_word_is_register :: proc "c" (word: Word) -> bool {
	context = runtime.default_context()
	return word_is_register(word)
}

@(export, link_name = "fmag_cg_word_register")
fmag_cg_word_register :: proc "c" (word: Word) -> Register {
	context = runtime.default_context()
	return word_register(word)
}

@(export, link_name = "fmag_cg_fmag")
fmag_cg_fmag :: proc "c" (builder: ^CG_Builder, dst, a: Register, b, c, guard: Word) {
	context = runtime.default_context()
	cg_fmag(builder, dst, a, b, c, guard)
}

@(export, link_name = "fmag_cg_finalize")
fmag_cg_finalize :: proc "c" (builder: ^CG_Builder) -> Stream {
	context = runtime.default_context()
	return cg_finalize(builder)
}

@(export, link_name = "fmag_vm_run")
fmag_vm_run :: proc "c" (code: [^]Word, count: Length, registers: [^]f32) {
	context = runtime.default_context()
	vm_run(code, count, registers)
}

@(export, link_name = "fmag_assemble")
fmag_assemble :: proc "c" (ctx: ^Context, text: String) -> Program {
	context = runtime.default_context()
	return assemble_string(ctx, text)
}

@(export, link_name = "fmag_disassemble")
fmag_disassemble :: proc "c" (header: HDR, stream: Stream) {
	context = runtime.default_context()
	disassemble(header, stream)
}

@(export, link_name = "fmag_ir_builder_create")
fmag_ir_builder_create :: proc "c" (ctx: ^Context, fast_math: bool) -> ^IR_Builder {
	context = runtime.default_context()
	return ir_builder_create(ctx, fast_math)
}

@(export, link_name = "fmag_ir_builder_delete")
fmag_ir_builder_delete :: proc "c" (builder: ^IR_Builder) {
	context = runtime.default_context()
	ir_builder_delete(builder)
}

@(export, link_name = "fmag_ir_function")
fmag_ir_function :: proc "c" (builder: ^IR_Builder, name: String, params, returns: Length) -> ^IR_Function {
	context = runtime.default_context()
	return ir_function_string(builder, name, params, returns)
}

@(export, link_name = "fmag_ir_param")
fmag_ir_param :: proc "c" (function: ^IR_Function, index: Length) -> ^IR_Value {
	context = runtime.default_context()
	return ir_param(function, index)
}

@(export, link_name = "fmag_ir_block")
fmag_ir_block :: proc "c" (builder: ^IR_Builder, function: ^IR_Function) -> ^IR_Block {
	context = runtime.default_context()
	return ir_block(builder, function)
}

@(export, link_name = "fmag_ir_position")
fmag_ir_position :: proc "c" (builder: ^IR_Builder, block: ^IR_Block) {
	context = runtime.default_context()
	ir_position(builder, block)
}

@(export, link_name = "fmag_ir_current")
fmag_ir_current :: proc "c" (builder: ^IR_Builder) -> ^IR_Block {
	context = runtime.default_context()
	return ir_current(builder)
}

@(export, link_name = "fmag_ir_const")
fmag_ir_const :: proc "c" (builder: ^IR_Builder, value: f32) -> ^IR_Value {
	context = runtime.default_context()
	return ir_const(builder, value)
}

@(export, link_name = "fmag_ir_is_const")
fmag_ir_is_const :: proc "c" (value: ^IR_Value, out: ^f32) -> bool {
	context = runtime.default_context()
	return ir_is_const(value, out)
}

@(export, link_name = "fmag_ir_fmag")
fmag_ir_fmag :: proc "c" (builder: ^IR_Builder, a, b, c, d, e: ^IR_Value) -> ^IR_Value {
	context = runtime.default_context()
	return ir_fmag(builder, a, b, c, d, e)
}

@(export, link_name = "fmag_ir_call")
fmag_ir_call :: proc "c" (builder: ^IR_Builder, callee: ^IR_Function, args: [^]^IR_Value, count: Length) -> ^IR_Value {
	context = runtime.default_context()
	slice: []^IR_Value
	if count != 0 && args != nil {
		slice = args[:count]
	}
	return ir_call(builder, callee, slice)
}

@(export, link_name = "fmag_ir_result")
fmag_ir_result :: proc "c" (builder: ^IR_Builder, call: ^IR_Value, index: Length) -> ^IR_Value {
	context = runtime.default_context()
	return ir_result(builder, call, index)
}

@(export, link_name = "fmag_ir_phi")
fmag_ir_phi :: proc "c" (builder: ^IR_Builder) -> ^IR_Value {
	context = runtime.default_context()
	return ir_phi(builder)
}

@(export, link_name = "fmag_ir_phi_edge")
fmag_ir_phi_edge :: proc "c" (builder: ^IR_Builder, phi: ^IR_Value, from: ^IR_Block, value: ^IR_Value) {
	context = runtime.default_context()
	ir_phi_edge(builder, phi, from, value)
}

@(export, link_name = "fmag_ir_rcp")
fmag_ir_rcp :: proc "c" (builder: ^IR_Builder, x: ^IR_Value) -> ^IR_Value {
	context = runtime.default_context()
	return ir_rcp(builder, x)
}

@(export, link_name = "fmag_ir_div")
fmag_ir_div :: proc "c" (builder: ^IR_Builder, a, b: ^IR_Value) -> ^IR_Value {
	context = runtime.default_context()
	return ir_div(builder, a, b)
}

@(export, link_name = "fmag_ir_runtime_rcp")
fmag_ir_runtime_rcp :: proc "c" (builder: ^IR_Builder) -> ^IR_Function {
	context = runtime.default_context()
	return ir_runtime_rcp(builder)
}

@(export, link_name = "fmag_ir_runtime_div")
fmag_ir_runtime_div :: proc "c" (builder: ^IR_Builder) -> ^IR_Function {
	context = runtime.default_context()
	return ir_runtime_div(builder)
}

@(export, link_name = "fmag_ir_br")
fmag_ir_br :: proc "c" (builder: ^IR_Builder, target: ^IR_Block) {
	context = runtime.default_context()
	ir_br(builder, target)
}

@(export, link_name = "fmag_ir_cond_br")
fmag_ir_cond_br :: proc "c" (builder: ^IR_Builder, guard: ^IR_Value, then_block, else_block: ^IR_Block) {
	context = runtime.default_context()
	ir_cond_br(builder, guard, then_block, else_block)
}

@(export, link_name = "fmag_ir_ret")
fmag_ir_ret :: proc "c" (builder: ^IR_Builder, values: [^]^IR_Value, count: Length) {
	context = runtime.default_context()
	slice: []^IR_Value
	if count != 0 && values != nil {
		slice = values[:count]
	}
	ir_ret(builder, slice)
}

@(export, link_name = "fmag_ir_dump")
fmag_ir_dump :: proc "c" (builder: ^IR_Builder) {
	context = runtime.default_context()
	ir_dump(builder)
}

@(export, link_name = "fmag_inline")
fmag_inline :: proc "c" (builder: ^IR_Builder) -> bool {
	context = runtime.default_context()
	return ir_inline(builder)
}

@(export, link_name = "fmag_select")
fmag_select :: proc "c" (builder: ^IR_Builder) {
	context = runtime.default_context()
	ir_select_pass(builder)
}

@(export, link_name = "fmag_flatten")
fmag_flatten :: proc "c" (builder: ^IR_Builder) -> bool {
	context = runtime.default_context()
	return ir_flatten(builder)
}

@(export, link_name = "fmag_optimize")
fmag_optimize :: proc "c" (builder: ^IR_Builder) {
	context = runtime.default_context()
	ir_optimize(builder)
}

@(export, link_name = "fmag_lower")
fmag_lower :: proc "c" (builder: ^IR_Builder, function: ^IR_Function) -> Program {
	context = runtime.default_context()
	return lower(builder, function)
}

}
