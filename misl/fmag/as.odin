// Copyright 2026 Dale Weiler
// SPDX-License-Identifier: MIT

package fmag

import "base:intrinsics"
import "core:c/libc"
import "core:fmt"
import "core:strings"

AS :: struct {
	text:   String,
	cursor: Length,
	cg:     ^CG_Builder,
}

as_peek :: proc(as: ^AS, offset: Length) -> u8 {
	at := as.cursor + offset
	if at < as.text.length {
		return as.text.data[at]
	}
	return 0
}

as_rest :: proc(as: ^AS) -> String {
	if as.text.data == nil || as.cursor >= as.text.length {
		return {}
	}
	rest := as.text.data[as.cursor:as.text.length]
	return String{data = raw_data(rest), length = Length(len(rest))}
}

skip_seps :: proc(as: ^AS) {
	for is_space(as_peek(as, 0)) || as_peek(as, 0) == ',' {
		as.cursor += 1
	}
}

skip_blanks :: proc(as: ^AS) {
	for {
		for is_whitespace(as_peek(as, 0)) {
			as.cursor += 1
		}
		if as_peek(as, 0) != ';' {
			break
		}
		for as_peek(as, 0) != 0 && as_peek(as, 0) != '\n' {
			as.cursor += 1
		}
	}
}

skip_to_eol :: proc(as: ^AS) {
	for as_peek(as, 0) != 0 && as_peek(as, 0) != '\n' {
		as.cursor += 1
	}
}

parse_register :: proc(as: ^AS, out: ^Register) -> bool {
	skip_seps(as)
	if as_peek(as, 0) != '%' || as_peek(as, 1) != 'r' || !is_digit(as_peek(as, 2)) {
		return false
	}
	as.cursor += 2
	index: u32
	for is_digit(as_peek(as, 0)) {
		index = index * 10 + u32(as.text.data[as.cursor] - '0')
		as.cursor += 1
	}
	out^ = Register(index)
	return true
}

parse_float :: proc(as: ^AS, out: ^f32) -> bool {
	avail := as.text.length - as.cursor
	n := avail if avail < 63 else 63
	buf: [64]u8
	if n > 0 {
		intrinsics.mem_copy(&buf[0], &as.text.data[as.cursor], int(n))
	}
	buf[n] = 0
	endptr: [^]u8
	value := libc.strtof(cstring(&buf[0]), &endptr)
	if endptr == nil || endptr == &buf[0] {
		return false
	}
	as.cursor += Length(uintptr(endptr) - uintptr(&buf[0]))
	out^ = value
	return true
}

parse_operand :: proc(as: ^AS, out: ^Word) -> bool {
	skip_seps(as)
	if as_peek(as, 0) == '%' {
		reg: Register
		if !parse_register(as, &reg) {
			return false
		}
		out^ = cg_reg(reg)
		return true
	}
	if as_peek(as, 0) == '$' {
		as.cursor += 1
		value: f32
		if !parse_float(as, &value) {
			return false
		}
		out^ = cg_imm(value)
		return true
	}
	return false
}

parse_number :: proc(as: ^AS, out: ^Length) -> bool {
	skip_seps(as)
	if !is_digit(as_peek(as, 0)) {
		return false
	}
	n: Length
	for is_digit(as_peek(as, 0)) {
		n = n * 10 + Length(as.text.data[as.cursor] - '0')
		as.cursor += 1
	}
	out^ = n
	return true
}

parse_fmag_kw :: proc(as: ^AS) -> bool {
	skip_seps(as)
	if string_starts(as_rest(as), "fmag") && !is_alpha(as_peek(as, 4)) {
		as.cursor += 4
		return true
	}
	return false
}

parse_def :: proc(as: ^AS, args, rets: ^Length) -> bool {
	if !string_starts(as_rest(as), ".def") || is_ident(as_peek(as, 4)) {
		return false
	}
	as.cursor += 4
	skip_seps(as)
	if !is_alpha(as_peek(as, 0)) {
		return false
	}
	for is_ident(as_peek(as, 0)) {
		as.cursor += 1
	}
	if !parse_number(as, args) || !parse_number(as, rets) {
		return false
	}
	skip_to_eol(as)
	return true
}

analyze :: proc(scratch: ^Allocator, stream: Stream, out_regs, out_live_in: ^u16) {
	words := ([^]Word)(stream.data)
	count := stream.size / (4 * size_of(Word))
	regs: u32
	for i in 0 ..< count {
		inst := words[i * 4:]
		refs: [5]u32
		refs[0] = inst[3].u & 0xFFFF
		refs[1] = inst[3].u >> 16
		n: Length = 2
		for k in 0 ..< 3 {
			if word_is_register(inst[k]) {
				refs[n] = u32(word_register(inst[k]))
				n += 1
			}
		}
		for k in 0 ..< n {
			if refs[k] + 1 > regs {
				regs = refs[k] + 1
			}
		}
	}
	written_size := Length(regs) if regs != 0 else 1
	written := ([^]u8)(mem_alloc(scratch, written_size))
	live: u32
	for i in 0 ..< count {
		inst := words[i * 4:]
		a := inst[3].u >> 16
		a_used := word_is_register(inst[0]) || inst[0].r != 0
		if a_used && written[a] == 0 && a + 1 > live {
			live = a + 1
		}
		for k in 0 ..< 3 {
			if word_is_register(inst[k]) {
				r := u32(word_register(inst[k]))
				if written[r] == 0 && r + 1 > live {
					live = r + 1
				}
			}
		}
		written[inst[3].u & 0xFFFF] = 1
	}
	out_regs^ = u16(regs)
	out_live_in^ = u16(live)
}

as_parse :: proc(as: ^AS, args, rets: ^Length, has_def: ^bool) -> bool {
	for {
		skip_blanks(as)
		if as.cursor >= as.text.length {
			return true
		}
		if as_peek(as, 0) == '.' {
			if !parse_def(as, args, rets) {
				return false
			}
			has_def^ = true
			continue
		}
		dst: Register
		if !parse_register(as, &dst) {
			return false
		}
		skip_seps(as)
		if as_peek(as, 0) != '=' {
			return false
		}
		as.cursor += 1
		a: Register
		b, c, guard: Word
		if !parse_fmag_kw(as) || !parse_register(as, &a) || !parse_operand(as, &b) || !parse_operand(as, &c) || !parse_operand(as, &guard) {
			return false
		}
		cg_fmag(as.cg, dst, a, b, c, guard)
		skip_to_eol(as)
	}
}

assemble :: proc(ctx: ^Context, text: string) -> Program {
	return assemble_string(ctx, string_from_odin(text))
}

assemble_string :: proc(ctx: ^Context, text: String) -> Program {
	allocator := context_allocator(ctx)
	cg := cg_builder_create(allocator)
	program: Program
	as := AS{text = text, cursor = 0, cg = cg}
	args: Length
	rets: Length
	has_def: bool
	if !as_parse(&as, &args, &rets, &has_def) {
		cg_builder_delete(cg)
		return program
	}
	stream := cg_finalize(cg)
	cg_builder_delete(cg)

	regs, live_in: u16
	{
		arena: Arena
		arena_init(&arena, allocator)
		analyze(&arena.allocator, stream, &regs, &live_in)
		arena_destroy(&arena)
	}

	if has_def && Length(live_in) > args {
		lie := Program{header = HDR{}, stream = stream}
		program_delete(ctx, &lie)
		return program
	}

	regs_needed := Length(regs)
	if args > regs_needed {
		regs_needed = args
	}
	if rets > regs_needed {
		regs_needed = rets
	}

	program.header.magic = MAGIC
	program.header.crc16 = crc16(stream.data, stream.size)
	program.header.regs = u16(regs_needed)
	program.header.args = u16(args)
	program.header.rets = u16(rets)
	program.stream = stream
	return program
}

operand_text :: proc(word: Word, allocator := context.allocator) -> string {
	if word_is_register(word) {
		return fmt.tprintf("%%r%v", word_register(word))
	}
	return fmt.tprintf("$%g", word.r)
}

disassemble_text :: proc(header: HDR, stream: Stream, allocator := context.allocator) -> string {
	return disassemble_named(header, stream, "main", nil, allocator)
}

disassemble_named :: proc(header: HDR, stream: Stream, name: string, notes: []string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	def_name := name if name != "" else "main"
	fmt.sbprintf(&b, ".def %s, %v, %v\n", def_name, header.args, header.rets)
	words := ([^]Word)(stream.data)
	count := stream.size / (4 * size_of(Word))
	last: string
	for i in 0 ..< count {
		if int(i) < len(notes) {
			note := notes[i]
			if note != "" && note != last {
				fmt.sbprintf(&b, "; %s\n", note)
				last = note
			}
		}
		inst := words[i * 4:]
		fmt.sbprintf(&b, "%%r%v = fmag %%r%v, ", inst[3].u & 0xFFFF, inst[3].u >> 16)
		fmt.sbprintf(&b, "%s, %s, %s\n", operand_text(inst[0]), operand_text(inst[1]), operand_text(inst[2]))
	}
	return strings.to_string(b)
}

disassemble :: proc(header: HDR, stream: Stream) {
	fmt.print(disassemble_text(header, stream))
}

load_program :: proc(bytes: []u8) -> (header: HDR, stream: Stream, ok: bool) {
	if len(bytes) < size_of(HDR) {
		return {}, {}, false
	}
	header = ([^]HDR)(raw_data(bytes))[0]
	payload := bytes[size_of(HDR):]
	if header.magic != MAGIC {
		return header, {}, false
	}
	if len(payload) % (4 * size_of(Word)) != 0 {
		return header, {}, false
	}
	if crc16(raw_data(payload), Length(len(payload))) != header.crc16 {
		return header, {}, false
	}
	return header, Stream{data = raw_data(payload), size = Length(len(payload))}, true
}
