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
	current:     int,           // index into blocks; -1 = none
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
	fn_i:      int, // current function index; -1 = none

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
	m.generator = GENERATOR_MISL
	m.addressing = .Logical
	m.memory = .GLSL450
	m.fn_i = -1
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

inst_header :: proc(op: Op, word_count: u32) -> Word {
	return Word(u32(op) | (word_count << 16))
}

string_words :: proc(s: string, allocator := context.temp_allocator) -> []Word {
	n_bytes := len(s) + 1
	n_words := (n_bytes + 3) / 4
	out := make([]Word, n_words, allocator)
	bytes := slice.reinterpret([]u8, out)
	copy(bytes, transmute([]u8)s)
	return out
}

append_inst :: proc(dst: ^[dynamic]Word, op: Op, operands: []Word) {
	n := u32(1 + len(operands))
	append(dst, inst_header(op, n))
	append(dst, ..operands)
}

append_inst_lit :: proc(dst: ^[dynamic]Word, op: Op, operands: ..Word) {
	append_inst(dst, op, operands)
}

current_fn :: proc(m: ^Module) -> ^Function {
	if m.fn_i < 0 || m.fn_i >= len(m.functions) {
		return nil
	}
	return &m.functions[m.fn_i]
}

current_block :: proc(m: ^Module) -> ^Block {
	fn := current_fn(m)
	if fn == nil || fn.current < 0 || fn.current >= len(fn.blocks) {
		return nil
	}
	return &fn.blocks[fn.current]
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
	b := current_block(m)
	assert(b != nil, "spirv: emit outside a block")
	assert(!b.terminated || op == .Label, "spirv: emit into a terminated block")
	append_inst(&b.insts, op, operands)
}

emit_fn_lit :: proc(m: ^Module, op: Op, operands: ..Word) {
	emit_fn(m, op, operands)
}

emit_typed :: proc(m: ^Module, op: Op, result_type: Id, operands: []Word) -> Id {
	rid := alloc_id(m)
	ops := make([]Word, 2 + len(operands), context.temp_allocator)
	ops[0] = Word(result_type)
	ops[1] = Word(rid)
	copy(ops[2:], operands)
	emit_fn(m, op, ops)
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
	sw := string_words(n)
	ops := make([]Word, 1 + len(sw), context.temp_allocator)
	ops[0] = Word(target)
	copy(ops[1:], sw)
	append_inst(&m.debug, .Name, ops)
}

member_name :: proc(m: ^Module, struct_id: Id, member: u32, n: string) {
	if !m.emit_names || struct_id == NONE || n == "" {
		return
	}
	sw := string_words(n)
	ops := make([]Word, 2 + len(sw), context.temp_allocator)
	ops[0] = Word(struct_id)
	ops[1] = member
	copy(ops[2:], sw)
	append_inst(&m.debug, .MemberName, ops)
}

op_string :: proc(m: ^Module, s: string) -> Id {
	if id, ok := m.string_ids[s]; ok {
		return id
	}
	id := alloc_id(m)
	cloned := strings.clone(s, m.allocator)
	m.string_ids[cloned] = id
	sw := string_words(s)
	ops := make([]Word, 1 + len(sw), context.temp_allocator)
	ops[0] = Word(id)
	copy(ops[1:], sw)
	append_inst(&m.debug_src, .String_, ops)
	return id
}

decorate :: proc(m: ^Module, target: Id, dec: Decoration, extra: ..u32) {
	ops := make([]Word, 2 + len(extra), context.temp_allocator)
	ops[0] = Word(target)
	ops[1] = Word(dec)
	copy(ops[2:], extra)
	append_inst(&m.decorations, .Decorate, ops)
}

member_decorate :: proc(m: ^Module, struct_id: Id, member: u32, dec: Decoration, extra: ..u32) {
	ops := make([]Word, 3 + len(extra), context.temp_allocator)
	ops[0] = Word(struct_id)
	ops[1] = member
	ops[2] = Word(dec)
	copy(ops[3:], extra)
	append_inst(&m.decorations, .MemberDecorate, ops)
}

decorate_string :: proc(m: ^Module, target: Id, dec: Decoration, s: string) {
	sw := string_words(s)
	ops := make([]Word, 2 + len(sw), context.temp_allocator)
	ops[0] = Word(target)
	ops[1] = Word(dec)
	copy(ops[2:], sw)
	append_inst(&m.decorations, .Decorate, ops)
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
	b := current_block(m)
	return b != nil && b.terminated
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
	sw := string_words(text)
	ops := make([]Word, 3 + len(sw), context.temp_allocator)
	ops[0] = Word(lang)
	ops[1] = version
	ops[2] = Word(file)
	copy(ops[3:], sw)
	append_inst(&m.debug_src, .Source, ops)
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
	fn.current = -1
	fn.params = make([dynamic]Id, m.allocator)
	fn.param_types = make([dynamic]Id, m.allocator)
	fn.blocks = make([dynamic]Block, m.allocator)
	fn.variables = make([dynamic]Word, m.allocator)
	append(&m.functions, fn)
	m.fn_i = len(m.functions) - 1
	return fid
}

fn_param :: proc(m: ^Module, ty: Id) -> Id {
	fn := current_fn(m)
	assert(fn != nil)
	id := alloc_id(m)
	append(&fn.params, id)
	append(&fn.param_types, ty)
	return id
}

fn_var :: proc(m: ^Module, ty_ptr: Id, sc := Storage_Class.Function, init: Id = NONE) -> Id {
	fn := current_fn(m)
	assert(fn != nil)
	id := alloc_id(m)
	if init != NONE {
		append_inst_lit(&fn.variables, .Variable, Word(ty_ptr), Word(id), Word(sc), Word(init))
	} else {
		append_inst_lit(&fn.variables, .Variable, Word(ty_ptr), Word(id), Word(sc))
	}
	return id
}

block_new :: proc(m: ^Module) -> Id {
	return alloc_id(m)
}

block_begin :: proc(m: ^Module, id: Id) {
	fn := current_fn(m)
	assert(fn != nil)
	b: Block
	b.id = id
	b.insts = make([dynamic]Word, m.allocator)
	append(&fn.blocks, b)
	fn.current = len(fn.blocks) - 1
	append_inst_lit(&fn.blocks[fn.current].insts, .Label, Word(id))
}

block_ensure :: proc(m: ^Module) -> Id {
	fn := current_fn(m)
	assert(fn != nil)
	if fn.current >= 0 {
		return fn.blocks[fn.current].id
	}
	id := block_new(m)
	block_begin(m, id)
	return id
}

mark_terminated :: proc(m: ^Module) {
	b := current_block(m)
	if b != nil {
		b.terminated = true
	}
}

fn_end :: proc(m: ^Module) {
	m.fn_i = -1
}

assemble :: proc(m: ^Module, allocator := context.allocator) -> []u32 {
	out := make([dynamic]Word, allocator)
	bound := m.next_id + 1
	append(&out, MAGIC, m.version, m.generator, bound, 0)

	for cap in m.caps {
		append_inst_lit(&out, .Capability, Word(cap))
	}
	for ext in m.extensions {
		sw := string_words(ext)
		append_inst(&out, .Extension, sw)
	}
	for imp in m.ext_list {
		sw := string_words(imp.name)
		ops := make([]Word, 1 + len(sw), context.temp_allocator)
		ops[0] = Word(imp.id)
		copy(ops[1:], sw)
		append_inst(&out, .ExtInstImport, ops)
	}
	append_inst_lit(&out, .MemoryModel, Word(m.addressing), Word(m.memory))

	for ep in m.entry_points {
		sw := string_words(ep.name)
		ops := make([dynamic]Word, context.temp_allocator)
		append(&ops, Word(ep.model), Word(ep.fn))
		append(&ops, ..sw)
		for id in ep.iface {
			append(&ops, Word(id))
		}
		append_inst(&out, .EntryPoint, ops[:])
	}
	for em in m.exec_modes {
		ops := make([]Word, 2 + len(em.extra), context.temp_allocator)
		ops[0] = Word(em.fn)
		ops[1] = Word(em.mode)
		copy(ops[2:], em.extra)
		op := Op.ExecutionModeId if em.use_id else Op.ExecutionMode
		append_inst(&out, op, ops)
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

// Empty compute shader used by builder tests: LocalSize 1,1,1 and a void return.
build_empty_compute :: proc(entry_name := "empty", allocator := context.allocator) -> []u32 {
	m := module_create(allocator)
	require_cap(&m, .Shader)
	set_memory_model(&m, .Logical, .GLSL450)
	void_t := type_void(&m)
	fn_ty := type_function(&m, void_t, {})
	fn := fn_begin(&m, void_t, fn_ty)
	name(&m, fn, entry_name)
	ep := entry_point(&m, .GLCompute, fn, entry_name)
	_ = ep
	execution_mode(&m, fn, .LocalSize, 1, 1, 1)
	block_begin(&m, block_new(&m))
	return_void(&m)
	fn_end(&m)
	return assemble(&m, allocator)
}

ext_inst :: proc(m: ^Module, result_ty: Id, set: Id, inst: u32, args: []Id) -> Id {
	ops := make([]Word, 2 + len(args), context.temp_allocator)
	ops[0] = Word(set)
	ops[1] = inst
	for a, i in args {
		ops[2 + i] = Word(a)
	}
	return emit_typed(m, .ExtInst, result_ty, ops)
}

// OpExtInst in the types/constants section (DebugSource, DebugCompilationUnit).
ext_inst_types :: proc(m: ^Module, result_ty: Id, set: Id, inst: u32, args: []Id, id := NONE) -> Id {
	rid := id if id != NONE else alloc_id(m)
	ops := make([]Word, 4 + len(args), context.temp_allocator)
	ops[0] = Word(result_ty)
	ops[1] = Word(rid)
	ops[2] = Word(set)
	ops[3] = inst
	for a, i in args {
		ops[4 + i] = Word(a)
	}
	append_inst(&m.types, .ExtInst, ops)
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
	full := make([]Word, 3 + len(args), context.temp_allocator)
	full[0] = Word(set)
	full[1] = u32(Debug_Printf.DebugPrintf)
	full[2] = Word(fmt_id)
	for a, i in args {
		full[3 + i] = Word(a)
	}
	_ = emit_typed(m, .ExtInst, type_void(m), full)
}

shader_debug :: proc(m: ^Module, result_ty: Id, inst: Shader_Debug, args: []Id) -> Id {
	require_ext(m, EXT_NON_SEMANTIC_INFO)
	set := ext_inst_import(m, EXT_SHADER_DEBUG_INFO)
	return ext_inst(m, result_ty, set, u32(inst), args)
}
