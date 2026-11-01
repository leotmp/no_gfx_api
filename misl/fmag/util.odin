// Copyright 2026 Dale Weiler
// SPDX-License-Identifier: MIT

package fmag

import "base:intrinsics"

Array_Header :: struct {
	len, cap: Length,
}

Arena_Block :: struct {
	next:       ^Arena_Block,
	used, size: Length,
}

Arena :: struct {
	allocator: Allocator,
	backing:   ^Allocator,
	block:     ^Arena_Block,
}

BLOCK_SIZE :: Length(1 << 20)

align16 :: proc "contextless" (n: Length) -> Length {
	return (n + 15) & ~Length(15)
}

array_header :: proc(array: rawptr) -> ^Array_Header {
	p := ([^]Array_Header)(array)
	return &p[-1]
}

array_length :: proc(array: rawptr) -> Length {
	if array == nil {
		return 0
	}
	return array_header(array).len
}

array_reserve :: proc(allocator: ^Allocator, array: ^rawptr, needed, type_size: Length) -> bool {
	info: ^Array_Header
	capacity: Length
	if array^ != nil {
		info = array_header(array^)
		capacity = info.cap
	}
	if needed <= capacity {
		return true
	}
	next := capacity * 2 if capacity != 0 else 16
	if next < needed {
		next = needed
	}
	bytes := size_of(Array_Header) + int(next * type_size)
	grown: ^Array_Header
	if info != nil {
		grown = (^Array_Header)(mem_realloc(
			allocator,
			info,
			Length(size_of(Array_Header)) + capacity * type_size,
			Length(bytes),
		))
	} else {
		grown = (^Array_Header)(mem_alloc(allocator, Length(bytes)))
	}
	if grown == nil {
		return false
	}
	if info == nil {
		grown.len = 0
	}
	grown.cap = next
	array^ = rawptr(([^]Array_Header)(grown)[1:])
	return true
}

array_resize :: proc(allocator: ^Allocator, array: ^rawptr, n, type_size: Length) {
	array_reserve(allocator, array, n, type_size)
	if array^ != nil {
		array_header(array^).len = n
	}
}

array_append :: proc(allocator: ^Allocator, array: ^rawptr, src: rawptr, n, type_size: Length) {
	at: Length
	if array^ != nil {
		at = array_header(array^).len
	}
	array_resize(allocator, array, at + n, type_size)
	if n != 0 && array^ != nil {
		intrinsics.mem_copy(([^]u8)(array^)[at * type_size:], src, int(n * type_size))
	}
}

array_delete :: proc(allocator: ^Allocator, array: ^rawptr) {
	if array^ != nil {
		mem_free(allocator, array_header(array^))
		array^ = nil
	}
}

array_push_raw :: proc(allocator: ^Allocator, array: ^rawptr, value: rawptr, type_size: Length) {
	array_reserve(allocator, array, array_length(array^) + 1, type_size)
	hdr := array_header(array^)
	dst := ([^]u8)(array^)
	intrinsics.mem_copy(&dst[hdr.len * type_size], value, int(type_size))
	hdr.len += 1
}

arena_allocate :: proc "contextless" (arena: ^Arena, size: Length) -> rawptr {
	size := align16(size)
	block := arena.block
	if block == nil || block.used + size > block.size {
		capacity := size if size > BLOCK_SIZE else BLOCK_SIZE
		block = (^Arena_Block)(arena.backing.allocate(
			arena.backing.udata,
			Length(size_of(Arena_Block)) + capacity,
		))
		if block == nil {
			return nil
		}
		data := ([^]u8)(rawptr(uintptr(block) + size_of(Arena_Block)))
		intrinsics.mem_zero(rawptr(data), int(capacity))
		block.next = arena.block
		block.used = 0
		block.size = capacity
		arena.block = block
	}
	data := ([^]u8)(rawptr(uintptr(block) + size_of(Arena_Block)))
	result := rawptr(&data[block.used])
	block.used += size
	return result
}

arena_reallocate :: proc "contextless" (arena: ^Arena, pointer: rawptr, old_size, new_size: Length) -> rawptr {
	block := arena.block
	used_old := align16(old_size)
	used_new := align16(new_size)
	if block != nil && pointer != nil &&
	   uintptr(pointer) + uintptr(used_old) == uintptr(block) + size_of(Arena_Block) + uintptr(block.used) {
		base := block.used - used_old
		if base + used_new <= block.size {
			block.used = base + used_new
			return pointer
		}
	}
	result := arena_allocate(arena, new_size)
	if result != nil && pointer != nil && old_size != 0 {
		n := old_size if old_size < new_size else new_size
		intrinsics.mem_copy(result, pointer, int(n))
	}
	return result
}

arena_cb_allocate :: proc "c" (udata: rawptr, size: Length) -> rawptr {
	return arena_allocate((^Arena)(udata), size)
}

arena_cb_reallocate :: proc "c" (udata: rawptr, pointer: rawptr, old_size, new_size: Length) -> rawptr {
	return arena_reallocate((^Arena)(udata), pointer, old_size, new_size)
}

arena_cb_deallocate :: proc "c" (udata: rawptr, pointer: rawptr) {
	_ = udata
	_ = pointer
}

arena_init :: proc(arena: ^Arena, backing: ^Allocator) {
	arena.allocator.allocate = arena_cb_allocate
	arena.allocator.reallocate = arena_cb_reallocate
	arena.allocator.deallocate = arena_cb_deallocate
	arena.allocator.udata = arena
	arena.backing = backing
	arena.block = nil
}

arena_destroy :: proc(arena: ^Arena) {
	block := arena.block
	for block != nil {
		next := block.next
		arena.backing.deallocate(arena.backing.udata, block)
		block = next
	}
	arena.block = nil
}

is_space :: proc(ch: u8) -> bool {
	return ch == ' ' || ch == '\t'
}

is_whitespace :: proc(ch: u8) -> bool {
	return is_space(ch) || ch == '\n' || ch == '\r'
}

is_digit :: proc(ch: u8) -> bool {
	return ch >= '0' && ch <= '9'
}

is_hex :: proc(ch: u8) -> bool {
	return is_digit(ch) || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
}

is_alpha :: proc(ch: u8) -> bool {
	return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

is_ident :: proc(ch: u8) -> bool {
	return is_alpha(ch) || is_digit(ch)
}
