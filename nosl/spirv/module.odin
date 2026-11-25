package spirv

import "core:mem"
import "core:slice"
import "core:strings"

Word :: u32

Ext_Import :: struct {
	id:   Id,
	name: string,
}

Entry_Point :: struct {
	model: Execution_Model,
	fn:    Id,
	name:  string,
	iface: [dynamic]Id,
}

Exec_Mode :: struct {
	fn:     Id,
	mode:   Execution_Mode,
	use_id: bool, // OpExecutionModeId
	extra:  []u32,
}

Block :: struct {
	id:         Id,
	insts:      [dynamic]Word,
	terminated: bool,
}

Function :: struct {
	id:          Id,
	result_type: Id,
	type_id:     Id,
	control:     Function_Control,
	params:      [dynamic]Id,
	param_types: [dynamic]Id,
	blocks:      [dynamic]Block,
	variables:   [dynamic]Word, // OpVariable in the first block
}

Module :: struct {
	allocator:  mem.Allocator,
	version:    u32,
	generator:  u32,
	next_id:    u32, // last allocated id; bound is next_id+1

	caps:       [dynamic]Capability,
	cap_set:    map[Capability]bool,
	extensions: [dynamic]string,
	ext_set:    map[string]bool,
	ext_list:   [dynamic]Ext_Import,
	ext_inst:   map[string]Id,

	addressing: Addressing_Model,
	memory:     Memory_Model,

	entry_points: [dynamic]Entry_Point,
	exec_modes:   [dynamic]Exec_Mode,

	debug_src:   [dynamic]Word, // OpString / OpSource — must precede OpName
	debug:       [dynamic]Word,
	decorations: [dynamic]Word,
	types:       [dynamic]Word,

	functions: [dynamic]Function,
	cur_fn:    ^Function,
	cur_block: ^Block,

	type_map:   map[string]Id,
	const_map:  map[string]Id,
	string_ids: map[string]Id,

	ty_void:    Id,
	ty_bool:    Id,
	ty_sampler: Id,
	emit_names: bool, // OpName / OpMemberName
}

module_create :: proc(allocator := context.allocator) -> Module {
	m: Module
	m.allocator = allocator
	m.version = VERSION_1_5
	m.generator = GENERATOR_NOSL
	m.addressing = .Logical
	m.memory = .GLSL450
	m.emit_names = true
	context.allocator = allocator
	m.caps = make([dynamic]Capability, allocator)
	m.cap_set = make(map[Capability]bool, allocator)
	m.extensions = make([dynamic]string, allocator)
	m.ext_set = make(map[string]bool, allocator)
	m.ext_list = make([dynamic]Ext_Import, allocator)
	m.ext_inst = make(map[string]Id, allocator)
	m.entry_points = make([dynamic]Entry_Point, allocator)
	m.exec_modes = make([dynamic]Exec_Mode, allocator)
	m.debug_src = make([dynamic]Word, allocator)
	m.debug = make([dynamic]Word, allocator)
	m.decorations = make([dynamic]Word, allocator)
	m.types = make([dynamic]Word, allocator)
	m.functions = make([dynamic]Function, allocator)
	m.type_map = make(map[string]Id, allocator)
	m.const_map = make(map[string]Id, allocator)
	m.string_ids = make(map[string]Id, allocator)
	return m
}

alloc_id :: proc(m: ^Module) -> Id {
	m.next_id += 1
	return Id(m.next_id)
}

// Header, then prefix. tail is how many operand words the caller appends next.
append_inst_start :: proc(dst: ^[dynamic]Word, op: Op, tail: int, prefix: ..Word) {
	n := u32(1 + len(prefix) + tail)
	append(dst, Word(u32(op) | (n << 16)))
	append(dst, ..prefix)
}

string_word_count :: #force_inline proc(s: string) -> int {
	return (len(s) + 4) / 4 // NUL plus pad to a whole word
}

append_literal_string :: proc(dst: ^[dynamic]Word, s: string) {
	n := string_word_count(s)
	base := len(dst)
	reserve(dst, base + n)
	for _ in 0 ..< n {
		append(dst, 0)
	}
	bytes := slice.reinterpret([]u8, dst[base:])
	copy(bytes, transmute([]u8)s)
}

append_ids :: proc(dst: ^[dynamic]Word, ids: []Id) {
	reserve(dst, len(dst) + len(ids))
	for id in ids {
		append(dst, Word(id))
	}
}

append_inst :: proc(dst: ^[dynamic]Word, op: Op, operands: []Word) {
	append_inst_start(dst, op, len(operands))
	append(dst, ..operands)
}

append_inst_lit :: proc(dst: ^[dynamic]Word, op: Op, operands: ..Word) {
	append_inst(dst, op, operands)
}

emit_types :: proc(m: ^Module, op: Op, operands: ..Word) {
	append_inst_lit(&m.types, op, ..operands)
}

emit_debug :: proc(m: ^Module, op: Op, operands: ..Word) {
	append_inst_lit(&m.debug, op, ..operands)
}

emit_deco :: proc(m: ^Module, op: Op, operands: ..Word) {
	append_inst_lit(&m.decorations, op, ..operands)
}

emit_fn :: proc(m: ^Module, op: Op, operands: []Word) {
	b := m.cur_block
	assert(b != nil, "spirv: emit outside a block")
	assert(!b.terminated || op == .Label, "spirv: emit into a terminated block")
	append_inst(&b.insts, op, operands)
}

emit_fn_lit :: proc(m: ^Module, op: Op, operands: ..Word) {
	emit_fn(m, op, operands)
}

emit_typed :: proc(m: ^Module, op: Op, result_type: Id, operands: []Word) -> Id {
	rid := alloc_id(m)
	b := m.cur_block
	assert(b != nil, "spirv: emit outside a block")
	assert(!b.terminated || op == .Label, "spirv: emit into a terminated block")
	append_inst_start(&b.insts, op, len(operands), Word(result_type), Word(rid))
	append(&b.insts, ..operands)
	return rid
}

emit_typed_lit :: proc(m: ^Module, op: Op, result_type: Id, operands: ..Word) -> Id {
	return emit_typed(m, op, result_type, operands)
}

require_cap :: proc(m: ^Module, c: Capability) {
	if c in m.cap_set {
		return
	}
	m.cap_set[c] = true
	append(&m.caps, c)
}

require_ext :: proc(m: ^Module, name: string) {
	if name in m.ext_set {
		return
	}
	m.ext_set[name] = true
	append(&m.extensions, strings.clone(name, m.allocator))
}

ext_inst_import :: proc(m: ^Module, name: string) -> Id {
	if id, ok := m.ext_inst[name]; ok {
		return id
	}
	id := alloc_id(m)
	cloned := strings.clone(name, m.allocator)
	m.ext_inst[cloned] = id
	append(&m.ext_list, Ext_Import{id = id, name = cloned})
	return id
}

set_memory_model :: proc(m: ^Module, addressing: Addressing_Model, memory: Memory_Model) {
	m.addressing = addressing
	m.memory = memory
}

entry_point :: proc(m: ^Module, model: Execution_Model, fn: Id, name: string) -> ^Entry_Point {
	cloned := strings.clone(name, m.allocator)
	append(&m.entry_points, Entry_Point{
		model = model,
		fn = fn,
		name = cloned,
		iface = make([dynamic]Id, m.allocator),
	})
	return &m.entry_points[len(m.entry_points) - 1]
}

entry_iface :: proc(ep: ^Entry_Point, id: Id) {
	if id == NONE {
		return
	}
	for existing in ep.iface {
		if existing == id {
			return
		}
	}
	append(&ep.iface, id)
}

execution_mode :: proc(m: ^Module, fn: Id, mode: Execution_Mode, extra: ..u32) {
	cloned := slice.clone(extra, m.allocator)
	append(&m.exec_modes, Exec_Mode{fn = fn, mode = mode, use_id = false, extra = cloned})
}

execution_mode_id :: proc(m: ^Module, fn: Id, mode: Execution_Mode, extra: ..u32) {
	cloned := slice.clone(extra, m.allocator)
	append(&m.exec_modes, Exec_Mode{fn = fn, mode = mode, use_id = true, extra = cloned})
}

name :: proc(m: ^Module, target: Id, n: string) {
	if !m.emit_names || target == NONE || n == "" {
		return
	}
	append_inst_start(&m.debug, .Name, string_word_count(n), Word(target))
	append_literal_string(&m.debug, n)
}

member_name :: proc(m: ^Module, struct_id: Id, member: u32, n: string) {
	if !m.emit_names || struct_id == NONE || n == "" {
		return
	}
	append_inst_start(&m.debug, .MemberName, string_word_count(n), Word(struct_id), member)
	append_literal_string(&m.debug, n)
}

op_string :: proc(m: ^Module, s: string) -> Id {
	if id, ok := m.string_ids[s]; ok {
		return id
	}
	id := alloc_id(m)
	cloned := strings.clone(s, m.allocator)
	m.string_ids[cloned] = id
	append_inst_start(&m.debug_src, .String_, string_word_count(s), Word(id))
	append_literal_string(&m.debug_src, s)
	return id
}

decorate :: proc(m: ^Module, target: Id, dec: Decoration, extra: ..u32) {
	append_inst_start(&m.decorations, .Decorate, len(extra), Word(target), Word(dec))
	append(&m.decorations, ..extra)
}

member_decorate :: proc(m: ^Module, struct_id: Id, member: u32, dec: Decoration, extra: ..u32) {
	append_inst_start(&m.decorations, .MemberDecorate, len(extra), Word(struct_id), member, Word(dec))
	append(&m.decorations, ..extra)
}

decorate_string :: proc(m: ^Module, target: Id, dec: Decoration, s: string) {
	append_inst_start(&m.decorations, .Decorate, string_word_count(s), Word(target), Word(dec))
	append_literal_string(&m.decorations, s)
}

global_var :: proc(m: ^Module, ty_ptr: Id, sc: Storage_Class, init: Id = NONE) -> Id {
	id := alloc_id(m)
	if init != NONE {
		emit_types(m, .Variable, Word(ty_ptr), Word(id), Word(sc), Word(init))
	} else {
		emit_types(m, .Variable, Word(ty_ptr), Word(id), Word(sc))
	}
	return id
}

intern_key :: proc(m: ^Module, key: string, table: ^map[string]Id) -> (Id, bool) {
	if id, ok := table[key]; ok {
		return id, true
	}
	return NONE, false
}

put_key :: proc(m: ^Module, key: string, id: Id, table: ^map[string]Id) {
	table[strings.clone(key, m.allocator)] = id
}

is_terminated :: proc(m: ^Module) -> bool {
	return m.cur_block.terminated
}

branch_if_open :: proc(m: ^Module, target: Id) {
	if !is_terminated(m) {
		branch(m, target)
	}
}

source :: proc(m: ^Module, lang: Source_Language, version: u32, file: Id = NONE, text := "") {
	if file == NONE && text == "" {
		append_inst_lit(&m.debug_src, .Source, Word(lang), version)
		return
	}
	if text == "" {
		append_inst_lit(&m.debug_src, .Source, Word(lang), version, Word(file))
		return
	}
	append_inst_start(&m.debug_src, .Source, string_word_count(text), Word(lang), version, Word(file))
	append_literal_string(&m.debug_src, text)
}

line :: proc(m: ^Module, file: Id, line_no, column: u32) {
	if file == NONE {
		return
	}
	emit_fn_lit(m, .Line, Word(file), line_no, column)
}

fn_begin :: proc(m: ^Module, result_type, fn_type: Id, control := Function_Control.None, id: Id = NONE) -> Id {
	fid := id if id != NONE else alloc_id(m)
	fn: Function
	fn.id = fid
	fn.result_type = result_type
	fn.type_id = fn_type
	fn.control = control
	fn.params = make([dynamic]Id, m.allocator)
	fn.param_types = make([dynamic]Id, m.allocator)
	fn.blocks = make([dynamic]Block, m.allocator)
	fn.variables = make([dynamic]Word, m.allocator)
	append(&m.functions, fn)
	m.cur_fn = &m.functions[len(m.functions) - 1]
	m.cur_block = nil
	return fid
}

fn_param :: proc(m: ^Module, ty: Id) -> Id {
	assert(m.cur_fn != nil)
	id := alloc_id(m)
	append(&m.cur_fn.params, id)
	append(&m.cur_fn.param_types, ty)
	return id
}

fn_var :: proc(m: ^Module, ty_ptr: Id, sc := Storage_Class.Function, init: Id = NONE) -> Id {
	assert(m.cur_fn != nil)
	id := alloc_id(m)
	if init != NONE {
		append_inst_lit(&m.cur_fn.variables, .Variable, Word(ty_ptr), Word(id), Word(sc), Word(init))
	} else {
		append_inst_lit(&m.cur_fn.variables, .Variable, Word(ty_ptr), Word(id), Word(sc))
	}
	return id
}

block_new :: proc(m: ^Module) -> Id {
	return alloc_id(m)
}

block_begin :: proc(m: ^Module, id: Id) {
	assert(m.cur_fn != nil)
	b: Block
	b.id = id
	b.insts = make([dynamic]Word, m.allocator)
	append(&m.cur_fn.blocks, b)
	m.cur_block = &m.cur_fn.blocks[len(m.cur_fn.blocks) - 1]
	append_inst_lit(&m.cur_block.insts, .Label, Word(id))
}

fn_end :: proc(m: ^Module) {
	m.cur_fn = nil
	m.cur_block = nil
}

assemble :: proc(m: ^Module, allocator := context.allocator) -> []u32 {
	out := make([dynamic]Word, allocator)
	bound := m.next_id + 1
	append(&out, MAGIC, m.version, m.generator, bound, 0)

	for cap in m.caps {
		append_inst_lit(&out, .Capability, Word(cap))
	}
	for ext in m.extensions {
		append_inst_start(&out, .Extension, string_word_count(ext))
		append_literal_string(&out, ext)
	}
	for imp in m.ext_list {
		append_inst_start(&out, .ExtInstImport, string_word_count(imp.name), Word(imp.id))
		append_literal_string(&out, imp.name)
	}
	append_inst_lit(&out, .MemoryModel, Word(m.addressing), Word(m.memory))

	for ep in m.entry_points {
		append_inst_start(&out, .EntryPoint, string_word_count(ep.name) + len(ep.iface), Word(ep.model), Word(ep.fn))
		append_literal_string(&out, ep.name)
		append_ids(&out, ep.iface[:])
	}
	for em in m.exec_modes {
		op := Op.ExecutionModeId if em.use_id else Op.ExecutionMode
		append_inst_start(&out, op, len(em.extra), Word(em.fn), Word(em.mode))
		append(&out, ..em.extra)
	}

	append(&out, ..m.debug_src[:])
	append(&out, ..m.debug[:])
	append(&out, ..m.decorations[:])
	append(&out, ..m.types[:])

	for fn in m.functions {
		append_inst_lit(&out, .Function, Word(fn.result_type), Word(fn.id), Word(fn.control), Word(fn.type_id))
		for p, i in fn.params {
			append_inst_lit(&out, .FunctionParameter, Word(fn.param_types[i]), Word(p))
		}
		for b, bi in fn.blocks {
			if bi == 0 && len(fn.variables) > 0 {
				// Label is the first instruction in b.insts
				if len(b.insts) == 0 {
					continue
				}
				append(&out, b.insts[0]) // OpLabel header+id may be multiple words
				// OpLabel is 2 words: header, id. Find how many words the first inst has.
				n0 := int(b.insts[0] >> 16)
				append(&out, ..b.insts[1:n0])
				append(&out, ..fn.variables[:])
				append(&out, ..b.insts[n0:])
			} else {
				append(&out, ..b.insts[:])
			}
		}
		append_inst_lit(&out, .FunctionEnd)
	}
	return out[:]
}

bytes_from_words :: proc(words: []u32, allocator := context.allocator) -> []u8 {
	return slice.clone(slice.reinterpret([]u8, words), allocator)
}

ext_inst :: proc(m: ^Module, result_ty: Id, set: Id, inst: u32, args: []Id) -> Id {
	rid := alloc_id(m)
	b := m.cur_block
	assert(b != nil, "spirv: emit outside a block")
	assert(!b.terminated, "spirv: emit into a terminated block")
	append_inst_start(&b.insts, .ExtInst, len(args), Word(result_ty), Word(rid), Word(set), inst)
	append_ids(&b.insts, args)
	return rid
}

// OpExtInst in the types/constants section (DebugSource, DebugCompilationUnit).
ext_inst_types :: proc(m: ^Module, result_ty: Id, set: Id, inst: u32, args: []Id, id := NONE) -> Id {
	rid := id if id != NONE else alloc_id(m)
	append_inst_start(&m.types, .ExtInst, len(args), Word(result_ty), Word(rid), Word(set), inst)
	append_ids(&m.types, args)
	return rid
}

shader_debug_types :: proc(m: ^Module, inst: Shader_Debug, args: []Id, id := NONE) -> Id {
	require_ext(m, EXT_NON_SEMANTIC_INFO)
	set := ext_inst_import(m, EXT_SHADER_DEBUG_INFO)
	return ext_inst_types(m, type_void(m), set, u32(inst), args, id)
}

glsl450 :: proc(m: ^Module, result_ty: Id, inst: Glsl450, args: []Id) -> Id {
	set := ext_inst_import(m, EXT_GLSL_STD_450)
	return ext_inst(m, result_ty, set, u32(inst), args)
}

debug_printf :: proc(m: ^Module, fmt_id: Id, args: []Id) {
	require_ext(m, EXT_NON_SEMANTIC_INFO)
	set := ext_inst_import(m, EXT_DEBUG_PRINTF)
	rid := alloc_id(m)
	b := m.cur_block
	assert(b != nil, "spirv: emit outside a block")
	assert(!b.terminated, "spirv: emit into a terminated block")
	append_inst_start(&b.insts, .ExtInst, len(args), Word(type_void(m)), Word(rid), Word(set), u32(Debug_Printf.DebugPrintf), Word(fmt_id))
	append_ids(&b.insts, args)
}

shader_debug :: proc(m: ^Module, result_ty: Id, inst: Shader_Debug, args: []Id) -> Id {
	require_ext(m, EXT_NON_SEMANTIC_INFO)
	set := ext_inst_import(m, EXT_SHADER_DEBUG_INFO)
	return ext_inst(m, result_ty, set, u32(inst), args)
}
