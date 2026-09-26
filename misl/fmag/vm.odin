// Copyright 2026 Dale Weiler
// SPDX-License-Identifier: MIT

package fmag

import "base:intrinsics"

load_op :: proc(registers: [^]f32, word: Word) -> f32 {
	if word_is_register(word) {
		return registers[word_register(word)]
	}
	return word.r
}

vm_run :: proc(code: [^]Word, count: Length, registers: [^]f32) {
	for i in 0 ..< count {
		inst := code[i * 4:]
		dst := Register(inst[3].u & 0xFFFF)
		a := Register(inst[3].u >> 16)
		b := load_op(registers, inst[0])
		c := load_op(registers, inst[1])
		guard := load_op(registers, inst[2])
		if guard > 0 {
			registers[dst] = intrinsics.fused_mul_add(registers[a], b, c)
		}
	}
}

vm_run_stream :: proc(stream: Stream, registers: []f32) {
	count := stream.size / (4 * size_of(Word))
	vm_run(([^]Word)(stream.data), count, raw_data(registers))
}
