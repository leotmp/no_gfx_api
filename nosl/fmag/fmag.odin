// Copyright 2026 Dale Weiler
// SPDX-License-Identifier: MIT

package fmag

import "base:intrinsics"
import "base:runtime"
import "core:mem"

Length   :: uint
Register :: u16

Word :: struct #raw_union {
	u: u32,
	r: f32,
}

String :: struct {
	data:   [^]u8,
	length: Length,
}

Allocator :: struct {
	allocate:   proc "c" (udata: rawptr, size: Length) -> rawptr,
	reallocate: proc "c" (udata: rawptr, pointer: rawptr, old_size, new_size: Length) -> rawptr,
	deallocate: proc "c" (udata: rawptr, pointer: rawptr),
	udata:      rawptr,
}

Context :: struct {
	allocator: ^Allocator,
	owned:     Allocator,
	bridge:    Odin_Bridge,
}

HDR :: struct #packed {
	magic: u32,
	crc16: u16,
	regs:  u16,
	args:  u16,
	rets:  u16,
}

MAGIC :: u32('F') | (u32('M') << 8) | (u32('A') << 16) | (u32('G') << 24)

Stream :: struct {
	data: rawptr,
	size: Length,
}

Program :: struct {
	header: HDR,
	stream: Stream,
}

Odin_Bridge :: struct {
	allocator: runtime.Allocator,
}

#assert(size_of(HDR) == 12)
#assert(size_of(Word) == 4)
#assert(size_of(String) == 16)
#assert(size_of(Stream) == 16)
#assert(offset_of(Program, stream) == 16)
#assert(size_of(Program) == 32)
#assert(size_of(Allocator) == 32)
#assert(offset_of(Arena, allocator) == 0)
#assert(size_of(Arena) == 48)

string_from_odin :: proc(s: string) -> String {
	return String{data = raw_data(s), length = Length(len(s))}
}

string_to_odin :: proc(s: String) -> string {
	if s.data == nil || s.length == 0 {
		return ""
	}
	return string(s.data[:s.length])
}

mem_alloc :: proc(a: ^Allocator, size: Length) -> rawptr {
	return a.allocate(a.udata, size)
}

mem_realloc :: proc(a: ^Allocator, pointer: rawptr, old_size, new_size: Length) -> rawptr {
	return a.reallocate(a.udata, pointer, old_size, new_size)
}

mem_free :: proc(a: ^Allocator, pointer: rawptr) {
	a.deallocate(a.udata, pointer)
}

odin_allocate :: proc "c" (udata: rawptr, size: Length) -> rawptr {
	b := (^Odin_Bridge)(udata)
	context = runtime.default_context()
	context.allocator = b.allocator
	if size == 0 {
		return nil
	}
	p, err := mem.alloc_bytes(int(size), 16)
	if err != .None {
		return nil
	}
	return raw_data(p)
}

odin_reallocate :: proc "c" (udata: rawptr, pointer: rawptr, old_size, new_size: Length) -> rawptr {
	b := (^Odin_Bridge)(udata)
	context = runtime.default_context()
	context.allocator = b.allocator
	if pointer == nil {
		return odin_allocate(udata, new_size)
	}
	if new_size == 0 {
		odin_deallocate(udata, pointer)
		return nil
	}
	p, err := mem.resize_bytes(([^]u8)(pointer)[:old_size], int(new_size), 16)
	if err != .None {
		return nil
	}
	return raw_data(p)
}

odin_deallocate :: proc "c" (udata: rawptr, pointer: rawptr) {
	if pointer == nil {
		return
	}
	b := (^Odin_Bridge)(udata)
	context = runtime.default_context()
	context.allocator = b.allocator
	mem.free(pointer)
}

c_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]u8,
	runtime.Allocator_Error,
) {
	a := (^Allocator)(allocator_data)
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		p := a.allocate(a.udata, Length(size))
		if p == nil {
			return nil, .Out_Of_Memory
		}
		if mode == .Alloc {
			intrinsics.mem_zero(p, size)
		}
		return ([^]u8)(p)[:size], .None
	case .Free:
		a.deallocate(a.udata, old_memory)
		return nil, .None
	case .Resize, .Resize_Non_Zeroed:
		p := a.reallocate(a.udata, old_memory, Length(old_size), Length(size))
		if p == nil && size != 0 {
			return nil, .Out_Of_Memory
		}
		if mode == .Resize && p != nil && size > old_size {
			intrinsics.mem_zero(([^]u8)(p)[old_size:], size - old_size)
		}
		if p == nil {
			return nil, .None
		}
		return ([^]u8)(p)[:size], .None
	case .Query_Features:
		set := (^runtime.Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Resize, .Resize_Non_Zeroed, .Query_Features}
		}
		return nil, .None
	}
	return nil, .Mode_Not_Implemented
}

odin_allocator :: proc(a: ^Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = c_allocator_proc, data = a}
}

context_create :: proc(allocator := context.allocator) -> ^Context {
	bridge := Odin_Bridge{allocator = allocator}
	owned := Allocator{
		allocate   = odin_allocate,
		reallocate = odin_reallocate,
		deallocate = odin_deallocate,
		udata      = nil, // filled after Context is allocated
	}
	// Allocate Context with the caller's allocator so delete can free it.
	ctx, err := new(Context, allocator)
	if err != .None {
		return nil
	}
	ctx.bridge = bridge
	ctx.owned = owned
	ctx.owned.udata = &ctx.bridge
	ctx.allocator = &ctx.owned
	return ctx
}

context_create_c :: proc(allocator: ^Allocator) -> ^Context {
	p := allocator.allocate(allocator.udata, size_of(Context))
	if p == nil {
		return nil
	}
	intrinsics.mem_zero(p, size_of(Context))
	ctx := (^Context)(p)
	ctx.allocator = allocator
	return ctx
}

context_delete :: proc(ctx: ^Context) {
	if ctx == nil {
		return
	}
	a := ctx.allocator
	a.deallocate(a.udata, ctx)
}

context_allocator :: proc(ctx: ^Context) -> ^Allocator {
	return ctx.allocator
}

crc16 :: proc(data: rawptr, size: Length) -> u16 {
	bytes := ([^]u8)(data)
	crc: u16 = 0xFFFF
	for i in 0 ..< size {
		crc ~= u16(bytes[i]) << 8
		for _ in 0 ..< 8 {
			if crc & 0x8000 != 0 {
				crc = (crc << 1) ~ 0x1021
			} else {
				crc <<= 1
			}
		}
	}
	return crc
}

string_is :: proc(a: String, literal: cstring) -> bool {
	n := Length(len(string(literal)))
	return a.length == n && runtime.memory_compare(a.data, raw_data(string(literal)), int(n)) == 0
}

string_same :: proc(a, b: String) -> bool {
	return a.length == b.length && runtime.memory_compare(a.data, b.data, int(a.length)) == 0
}

string_starts :: proc(a: String, prefix: cstring) -> bool {
	n := Length(len(string(prefix)))
	return a.length >= n && runtime.memory_compare(a.data, raw_data(string(prefix)), int(n)) == 0
}

string_from :: proc(text: cstring) -> String {
	s := string(text)
	return String{data = raw_data(s), length = Length(len(s))}
}

string_copy :: proc(allocator: ^Allocator, text: String) -> String {
	data := mem_alloc(allocator, text.length)
	if data != nil && text.length > 0 {
		intrinsics.mem_copy(data, text.data, int(text.length))
	}
	return String{data = ([^]u8)(data), length = text.length}
}

program_delete :: proc(ctx: ^Context, program: ^Program) {
	a := context_allocator(ctx)
	array_delete(a, &program.stream.data)
	program.stream.data = nil
	program.stream.size = 0
}

stream_words :: proc(stream: Stream) -> []Word {
	n := int(stream.size / size_of(Word))
	if stream.data == nil || n == 0 {
		return nil
	}
	return ([^]Word)(stream.data)[:n]
}

run :: proc(program: Program, registers: []f32) {
	count := program.stream.size / (4 * size_of(Word))
	vm_run(([^]Word)(program.stream.data), count, raw_data(registers))
}
