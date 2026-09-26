// Copyright 2026 Dale Weiler
// SPDX-License-Identifier: MIT

package fmag

NAN_QUIET     :: u32(0x7FC00000)
REGISTER_MASK :: u32(0x003FFFFF)

Inst :: struct {
	word: [4]Word,
}

CG_Builder :: struct {
	allocator: ^Allocator,
	code:      rawptr,
}

cg_builder_create :: proc(allocator: ^Allocator) -> ^CG_Builder {
	builder := (^CG_Builder)(mem_alloc(allocator, size_of(CG_Builder)))
	if builder == nil {
		return nil
	}
	builder.allocator = allocator
	builder.code = nil
	return builder
}

cg_builder_delete :: proc(builder: ^CG_Builder) {
	if builder == nil {
		return
	}
	allocator := builder.allocator
	array_delete(allocator, &builder.code)
	mem_free(allocator, builder)
}

cg_reg :: proc(reg: Register) -> Word {
	w: Word
	w.u = NAN_QUIET | (u32(reg) & REGISTER_MASK)
	return w
}

cg_imm :: proc(value: f32) -> Word {
	w: Word
	w.r = value
	return w
}

word_is_register :: proc(word: Word) -> bool {
	return (word.u & 0x7F800000) == 0x7F800000 && (word.u & 0x007FFFFF) != 0
}

word_register :: proc(word: Word) -> Register {
	return Register(word.u & REGISTER_MASK)
}

cg_fmag :: proc(builder: ^CG_Builder, dst, a: Register, b, c, guard: Word) {
	inst: Inst
	inst.word[0] = b
	inst.word[1] = c
	inst.word[2] = guard
	inst.word[3].u = u32(dst) | (u32(a) << 16)
	array_push_raw(builder.allocator, &builder.code, &inst, size_of(Inst))
}

cg_finalize :: proc(builder: ^CG_Builder) -> Stream {
	stream: Stream
	stream.data = builder.code
	stream.size = array_length(builder.code) * size_of(Inst)
	builder.code = nil
	return stream
}
