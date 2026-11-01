package misl

import "core:fmt"
import "core:path/filepath"
import "core:strings"

import spv "spirv"

SPV_DEBUG_STRING_MAX :: 65000

SPV_DBG_ENC_UNSPEC  :: u32(0)
SPV_DBG_ENC_BOOLEAN :: u32(2)
SPV_DBG_ENC_FLOAT   :: u32(3)
SPV_DBG_ENC_SIGNED  :: u32(4)
SPV_DBG_ENC_UNSIGNED :: u32(6)
SPV_DBG_COMPOSITE_STRUCT :: u32(1)
SPV_DBG_FLAG_NONE :: u32(0)
// FlagIsPublic | FlagIsDefinition
SPV_DBG_FLAG_PUBLIC_DEF :: u32(3 | 8)

spv_emit_debug_source :: proc(cg: ^Spv_CG) {
	if !cg.debug_info {
		return
	}
	mods := spv_gather_emit_modules(cg.module)
	seen := make(map[string]bool, context.temp_allocator)
	first_src := spv.NONE
	for m in mods {
		if m == nil || m.code == "" {
			continue
		}
		orig := m.fullpath
		if orig == "" || orig in seen {
			continue
		}
		seen[orig] = true
		path := orig
		if abs, err := filepath.abs(orig); err == nil {
			path = abs
		}
		file_id := spv.op_string(&cg.m, path)
		cg.file_str[orig] = file_id
		if path != orig {
			cg.file_str[path] = file_id
		}
		text := m.code
		if !cg.embed_source {
			text = ""
		}
		head := text
		rest := ""
		if len(text) > SPV_DEBUG_STRING_MAX {
			head = text[:SPV_DEBUG_STRING_MAX]
			rest = text[SPV_DEBUG_STRING_MAX:]
		}
		text_id := spv.op_string(&cg.m, head)
		// Do not emit OpSource. RenderDoc registers OpSource and DebugSource as
		// separate files; a stub OpSource (basename when source is long) is the
		// empty duplicate "Debug this vertex" opens.
		src := spv.shader_debug_types(&cg.m, .DebugSource, {file_id, text_id})
		for len(rest) > 0 {
			chunk := rest
			if len(chunk) > SPV_DEBUG_STRING_MAX {
				chunk = rest[:SPV_DEBUG_STRING_MAX]
				rest = rest[SPV_DEBUG_STRING_MAX:]
			} else {
				rest = ""
			}
			cid := spv.op_string(&cg.m, chunk)
			_ = spv.shader_debug_types(&cg.m, .DebugSourceContinued, {cid})
		}
		if first_src == spv.NONE {
			first_src = src
		}
		cg.dbg_src[orig] = src
		if path != orig {
			cg.dbg_src[path] = src
		}
	}
	if first_src == spv.NONE {
		file_id := spv.op_string(&cg.m, cg.module.fullpath if cg.module != nil else "misl")
		empty := spv.op_string(&cg.m, "")
		first_src = spv.shader_debug_types(&cg.m, .DebugSource, {file_id, empty})
	}
	cu_src := first_src
	if cg.module != nil && cg.module.fullpath != "" {
		if id, ok := cg.dbg_src[cg.module.fullpath]; ok {
			cu_src = id
		}
	}
	ver := spv.const_u32(&cg.m, 100)
	dwarf := spv.const_u32(&cg.m, 4)
	lang := spv.const_u32(&cg.m, u32(spv.Source_Language.Unknown))
	cg.dbg_cu = spv.shader_debug_types(&cg.m, .DebugCompilationUnit, {ver, dwarf, cu_src, lang})
	cg.dbg_void = cu_src
	cg.dbg_none = spv.shader_debug_types(&cg.m, .DebugInfoNone, {})
	cg.dbg_empty_expr = spv.shader_debug_types(&cg.m, .DebugExpression, {})
}

spv_debug_source_for_pos :: proc(cg: ^Spv_CG, pos: Token_Pos) -> spv.Id {
	if pos.file != "" {
		if id, ok := cg.dbg_src[pos.file]; ok {
			return id
		}
	}
	return cg.dbg_void
}

spv_debug_line :: proc(cg: ^Spv_CG, pos: Token_Pos) {
	if !cg.debug_info || pos.line <= 0 {
		return
	}
	file_id := spv.NONE
	if pos.file != "" {
		file_id = cg.file_str[pos.file]
	}
	if file_id == spv.NONE && cg.module != nil {
		file_id = cg.file_str[cg.module.fullpath]
	}
	if file_id != spv.NONE && !spv.is_terminated(&cg.m) {
		spv.line(&cg.m, file_id, u32(pos.line), u32(max(pos.column, 1)))
	}
	src := spv_debug_source_for_pos(cg, pos)
	if src != spv.NONE && !spv.is_terminated(&cg.m) {
		ls := spv.const_u32(&cg.m, u32(pos.line))
		cs := spv.const_u32(&cg.m, u32(max(pos.column, 1)))
		_ = spv.shader_debug(&cg.m, spv.type_void(&cg.m), .DebugLine, {src, ls, ls, cs, cs})
	}
}

spv_block :: proc(cg: ^Spv_CG, id: spv.Id) {
	spv.block_begin(&cg.m, id)
	spv_debug_scope(cg)
}

// First block of a function: DebugFunctionDefinition (and DebugEntryPoint) before DebugScope.
spv_fn_start :: proc(cg: ^Spv_CG, block, dbg_fn, fn_id: spv.Id, is_entry: bool) {
	spv.block_begin(&cg.m, block)
	spv_debug_function_body(cg, dbg_fn, fn_id, is_entry)
	spv_debug_scope(cg)
}

spv_debug_scope :: proc(cg: ^Spv_CG) {
	if !cg.debug_info || cg.dbg_cur_fn == spv.NONE {
		return
	}
	_ = spv.shader_debug(&cg.m, spv.type_void(&cg.m), .DebugScope, {cg.dbg_cur_fn})
}

spv_dbg_src_cu :: proc(cg: ^Spv_CG) -> (src, parent: spv.Id) {
	src = cg.dbg_void
	parent = cg.dbg_cu
	if src == spv.NONE {
		src = cg.dbg_none
	}
	if parent == spv.NONE {
		parent = cg.dbg_none
	}
	return
}

spv_dbg_line_col :: proc(cg: ^Spv_CG, pos: Token_Pos) -> (line, col: spv.Id) {
	l := u32(pos.line) if pos.line > 0 else 1
	c := u32(pos.column) if pos.column > 0 else 1
	return spv.const_u32(&cg.m, l), spv.const_u32(&cg.m, c)
}

spv_dbg_str :: proc(cg: ^Spv_CG, s: string) -> spv.Id {
	return spv.op_string(&cg.m, s if s != "" else "")
}

spv_dbg_type_name :: proc(type: ^Type) -> string {
	if type == nil {
		return "void"
	}
	if type.name != "" {
		return type.name
	}
	if type.ir_name != "" {
		return type.ir_name
	}
	return string_from_type(type)
}

spv_dbg_basic :: proc(cg: ^Spv_CG, name: string, bits, enc: u32) -> spv.Id {
	key := fmt.tprintf("b:%s:%d:%d", name, bits, enc)
	if id, ok := cg.dbg_aux[key]; ok {
		return id
	}
	id := spv.shader_debug_types(&cg.m, .DebugTypeBasic, {
		spv_dbg_str(cg, name),
		spv.const_u32(&cg.m, bits),
		spv.const_u32(&cg.m, enc),
		spv.const_u32(&cg.m, SPV_DBG_FLAG_NONE),
	})
	cg.dbg_aux[strings.clone(key, context.temp_allocator)] = id
	return id
}

spv_dbg_pointer :: proc(cg: ^Spv_CG, elem: ^Type, sc: spv.Storage_Class) -> spv.Id {
	key := fmt.tprintf("p:%p:%d", elem, u32(sc))
	if id, ok := cg.dbg_aux[key]; ok {
		return id
	}
	id := spv.shader_debug_types(&cg.m, .DebugTypePointer, {
		spv_dbg_type(cg, elem),
		spv.const_u32(&cg.m, u32(sc)),
		spv.const_u32(&cg.m, SPV_DBG_FLAG_NONE),
	})
	cg.dbg_aux[strings.clone(key, context.temp_allocator)] = id
	return id
}

spv_dbg_type :: proc(cg: ^Spv_CG, type: ^Type) -> spv.Id {
	if type == nil || cg.dbg_none == spv.NONE {
		return cg.dbg_none
	}
	type := default_type(type)
	if id, ok := cg.dbg_types[type]; ok {
		return id
	}
	#partial switch t in type.derived {
	case ^Type_Scalar:
		enc := SPV_DBG_ENC_UNSPEC
		if .Boolean in t.flags {
			enc = SPV_DBG_ENC_BOOLEAN
		} else if .Float in t.flags {
			enc = SPV_DBG_ENC_FLOAT
		} else if .Unsigned in t.flags {
			enc = SPV_DBG_ENC_UNSIGNED
		} else {
			enc = SPV_DBG_ENC_SIGNED
		}
		bits := u32(t.size * 8)
		if bits == 0 {
			bits = 32
		}
		id := spv_dbg_basic(cg, spv_dbg_type_name(type), bits, enc)
		cg.dbg_types[type] = id
		return id
	case ^Type_Enum:
		return spv_dbg_type(cg, t.base_type)
	case ^Type_Bit_Set:
		return spv_dbg_type(cg, t.underlying)
	case ^Type_Vector:
		id := spv.shader_debug_types(&cg.m, .DebugTypeVector, {
			spv_dbg_type(cg, t.elem),
			spv.const_u32(&cg.m, u32(t.len)),
		})
		cg.dbg_types[type] = id
		return id
	case ^Type_Matrix:
		col := spv.shader_debug_types(&cg.m, .DebugTypeVector, {
			spv_dbg_type(cg, t.elem),
			spv.const_u32(&cg.m, u32(t.rows)),
		})
		id := spv.shader_debug_types(&cg.m, .DebugTypeMatrix, {
			col,
			spv.const_u32(&cg.m, u32(t.columns)),
			spv.const_bool(&cg.m, true),
		})
		cg.dbg_types[type] = id
		return id
	case ^Type_Array:
		n := u32(t.len)
		id := spv.shader_debug_types(&cg.m, .DebugTypeArray, {
			spv_dbg_type(cg, t.elem),
			spv.const_u32(&cg.m, n),
		})
		cg.dbg_types[type] = id
		return id
	case ^Type_Pointer:
		id := spv_dbg_pointer(cg, t.elem, .PhysicalStorageBuffer)
		cg.dbg_types[type] = id
		return id
	case ^Type_Multi_Pointer:
		id := spv_dbg_pointer(cg, t.elem, .PhysicalStorageBuffer)
		cg.dbg_types[type] = id
		return id
	case ^Type_Slice:
		return spv_dbg_slice_type(cg, type, t)
	case ^Type_Struct:
		return spv_dbg_struct_type(cg, type, t)
	case ^Type_Atom:
		id := spv_dbg_basic(cg, spv_dbg_type_name(type), 32, SPV_DBG_ENC_UNSPEC)
		cg.dbg_types[type] = id
		return id
	}
	id := spv_dbg_basic(cg, spv_dbg_type_name(type), 32, SPV_DBG_ENC_UNSPEC)
	cg.dbg_types[type] = id
	return id
}

spv_dbg_member :: proc(cg: ^Spv_CG, name: string, field_t: ^Type, pos: Token_Pos, offset_bytes, size_bytes: int) -> spv.Id {
	src, parent := spv_dbg_src_cu(cg)
	line, col := spv_dbg_line_col(cg, pos)
	_ = parent
	return spv.shader_debug_types(&cg.m, .DebugTypeMember, {
		spv_dbg_str(cg, name),
		spv_dbg_type(cg, field_t),
		src,
		line,
		col,
		spv.const_u32(&cg.m, u32(max(offset_bytes, 0) * 8)),
		spv.const_u32(&cg.m, u32(max(size_bytes, 1) * 8)),
		spv.const_u32(&cg.m, SPV_DBG_FLAG_NONE),
	})
}

spv_dbg_struct_type :: proc(cg: ^Spv_CG, type: ^Type, st: ^Type_Struct) -> spv.Id {
	id := spv.alloc_id(&cg.m)
	cg.dbg_types[type] = id
	src, parent := spv_dbg_src_cu(cg)
	pos: Token_Pos
	members := make([dynamic]spv.Id, context.temp_allocator)
	if st.fields != nil {
		for field in st.fields.variables {
			if field == nil || field.type == nil do continue
			if pos.line == 0 {
				pos = field.pos
			}
			append(&members, spv_dbg_member(cg, field.name, field.type, field.pos, field.field_offset, type_sizeof(field.type)))
		}
	}
	line, col := spv_dbg_line_col(cg, pos)
	nm := spv_dbg_str(cg, spv_dbg_type_name(type))
	args := make([dynamic]spv.Id, context.temp_allocator)
	append(&args, nm)
	append(&args, spv.const_u32(&cg.m, SPV_DBG_COMPOSITE_STRUCT))
	append(&args, src, line, col, parent, nm)
	append(&args, spv.const_u32(&cg.m, u32(max(type_sizeof(type), 1) * 8)))
	append(&args, spv.const_u32(&cg.m, SPV_DBG_FLAG_NONE))
	append(&args, ..members[:])
	return spv.shader_debug_types(&cg.m, .DebugTypeComposite, args[:], id)
}

spv_dbg_slice_type :: proc(cg: ^Spv_CG, type: ^Type, st: ^Type_Slice) -> spv.Id {
	id := spv.alloc_id(&cg.m)
	cg.dbg_types[type] = id
	src, parent := spv_dbg_src_cu(cg)
	line := spv.const_u32(&cg.m, 1)
	col := spv.const_u32(&cg.m, 1)
	data := spv.shader_debug_types(&cg.m, .DebugTypeMember, {
		spv_dbg_str(cg, "data"),
		spv_dbg_pointer(cg, st.elem, .PhysicalStorageBuffer),
		src, line, col,
		spv.const_u32(&cg.m, 0),
		spv.const_u32(&cg.m, 64),
		spv.const_u32(&cg.m, SPV_DBG_FLAG_NONE),
	})
	ln := spv.shader_debug_types(&cg.m, .DebugTypeMember, {
		spv_dbg_str(cg, "len"),
		spv_dbg_basic(cg, "i64", 64, SPV_DBG_ENC_SIGNED),
		src, line, col,
		spv.const_u32(&cg.m, 64),
		spv.const_u32(&cg.m, 64),
		spv.const_u32(&cg.m, SPV_DBG_FLAG_NONE),
	})
	nm := spv_dbg_str(cg, spv_dbg_type_name(type))
	return spv.shader_debug_types(&cg.m, .DebugTypeComposite, {
		nm,
		spv.const_u32(&cg.m, SPV_DBG_COMPOSITE_STRUCT),
		src, line, col, parent, nm,
		spv.const_u32(&cg.m, 128),
		spv.const_u32(&cg.m, SPV_DBG_FLAG_NONE),
		data, ln,
	}, id)
}

spv_dbg_param_type :: proc(cg: ^Spv_CG, e: ^Entity) -> spv.Id {
	if e == nil || e.type == nil {
		return cg.dbg_none
	}
	if .Ref in e.flags {
		return spv_dbg_pointer(cg, e.type, .Function)
	}
	return spv_dbg_type(cg, e.type)
}

// DebugFunction in the types section; caller emits DebugFunctionDefinition in the first block.
spv_debug_function :: proc(cg: ^Spv_CG, e: ^Entity, params: []^Entity, ret_type: ^Type) -> spv.Id {
	if !cg.debug_info || e == nil || cg.dbg_cu == spv.NONE {
		return spv.NONE
	}
	fn_args := make([dynamic]spv.Id, context.temp_allocator)
	append(&fn_args, spv.const_u32(&cg.m, SPV_DBG_FLAG_NONE))
	if ret_type == nil {
		append(&fn_args, spv.type_void(&cg.m))
	} else {
		append(&fn_args, spv_dbg_type(cg, ret_type))
	}
	for p in params {
		append(&fn_args, spv_dbg_param_type(cg, p))
	}
	fn_ty := spv.shader_debug_types(&cg.m, .DebugTypeFunction, fn_args[:])
	src := spv_debug_source_for_pos(cg, e.pos)
	if src == spv.NONE {
		src = cg.dbg_void
	}
	line, col := spv_dbg_line_col(cg, e.pos)
	nm := spv_dbg_str(cg, e.name if e.name != "" else "fn")
	return spv.shader_debug_types(&cg.m, .DebugFunction, {
		nm,
		fn_ty,
		src,
		line,
		col,
		cg.dbg_cu,
		nm,
		spv.const_u32(&cg.m, SPV_DBG_FLAG_PUBLIC_DEF),
		line,
	})
}

spv_debug_function_body :: proc(cg: ^Spv_CG, dbg_fn, fn_id: spv.Id, is_entry: bool) {
	if dbg_fn == spv.NONE || fn_id == spv.NONE {
		return
	}
	_ = spv.shader_debug(&cg.m, spv.type_void(&cg.m), .DebugFunctionDefinition, {dbg_fn, fn_id})
	if is_entry && cg.dbg_cu != spv.NONE {
		// spirv-val: DebugEntryPoint is a module-scope debug inst (not in a function).
		sig := spv_dbg_str(cg, "misl")
		args := spv_dbg_str(cg, "")
		_ = spv.shader_debug_types(&cg.m, .DebugEntryPoint, {dbg_fn, cg.dbg_cu, sig, args})
	}
}

spv_debug_declare :: proc(cg: ^Spv_CG, var_id: spv.Id, type: ^Type, name: string, pos: Token_Pos, arg_number: u32 = 0) {
	if !cg.debug_info || cg.dbg_cur_fn == spv.NONE || var_id == spv.NONE || type == nil {
		return
	}
	if name == "" || name == "_" {
		return
	}
	src := spv_debug_source_for_pos(cg, pos)
	if src == spv.NONE {
		src = cg.dbg_void
	}
	line, col := spv_dbg_line_col(cg, pos)
	local_args := make([dynamic]spv.Id, context.temp_allocator)
	append(&local_args, spv_dbg_str(cg, name))
	append(&local_args, spv_dbg_type(cg, type))
	append(&local_args, src, line, col, cg.dbg_cur_fn)
	append(&local_args, spv.const_u32(&cg.m, SPV_DBG_FLAG_NONE))
	if arg_number > 0 {
		append(&local_args, spv.const_u32(&cg.m, arg_number))
	}
	local := spv.shader_debug_types(&cg.m, .DebugLocalVariable, local_args[:])
	_ = spv.shader_debug(&cg.m, spv.type_void(&cg.m), .DebugDeclare, {local, var_id, cg.dbg_empty_expr})
}
