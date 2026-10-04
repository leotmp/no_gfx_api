package misl

import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:time"

import spv "spirv"
import "spirv_tools"

Spirv_Emit :: struct {
	debug_info:            bool,
	embed_source:          bool,
	names:                 bool,
	named_entry:           bool,
	assert_buffer_spec_id: u32,
}

Spv_Layout :: enum {
	Func,   // Function / Private / Workgroup — no Offset
	Stored, // PhysicalStorageBuffer / PushConstant — Offset on structs
}

Spv_Lval :: struct {
	ptr:     spv.Id,
	type:    ^Type,
	sc:      spv.Storage_Class,
	aligned: bool,
	align:   u32,
	direct:  bool, // OpVariable / OpFunctionParameter — legal as a Function-pointer call arg
	vec:     ^Type, // parent vector type when swizzle is set
	swizzle: []u32, // vector component lvalue (empty = full object)
}

Spv_Ref_Copy :: struct {
	tmp:  spv.Id,
	dest: Spv_Lval,
}

Spv_Psb :: struct {
	ptr_ty:   spv.Id,
	block_ty: spv.Id,
	complete: bool,
}

Spv_Bindless :: struct {
	tex:      [Resource_View]spv.Id,
	rw:       [Resource_View]spv.Id,
	samp:     spv.Id,
	samp_cmp: spv.Id,
	bvh:      spv.Id,
}

Spv_CG :: struct {
	m:             spv.Module,
	module:        ^Module,
	entry:         ^Entity,
	curr_proc:     ^Type_Proc,
	curr_entity:   ^Entity,
	stage:         Stage,
	compat:        Misl_Compat,
	err:           Error_Handler,
	error_count:   int,
	rw_elems:      map[^Type]bool,
	bounds_check:  bool,
	disable_asserts: bool,
	needs_ray_query: bool,
	needs_assert:  bool,
	debug_info:    bool,
	embed_source:  bool,
	named_entry:   bool,
	assert_buffer_spec_id: u32,
	subgroup_size: spv.Id,
	subgroup_lane: spv.Id,

	type_fn:       map[^Type]spv.Id,
	type_stored:   map[^Type]spv.Id,
	psb_ro:        map[^Type]Spv_Psb,
	psb_rw:        map[^Type]Spv_Psb,
	psb_ro_id:     map[spv.Id]Spv_Psb,
	psb_rw_id:     map[spv.Id]Spv_Psb,
	slice_fn:      map[^Type]spv.Id, // elem → {ptr, len} Function struct
	slice_st:      map[^Type]spv.Id,
	voidptr:       spv.Id,
	entity_ptr:    map[^Entity]spv.Id,
	entity_sc:     map[^Entity]spv.Storage_Class,
	entity_val_ty: map[^Entity]spv.Id, // SPIR-V type loaded from entity_ptr
	entity_alias:  map[^Entity]bool, // range-ref AccessChain — not a legal Function call arg
	fn_id:         map[^Entity]spv.Id,
	bindless:      Spv_Bindless,
	pc_var:        spv.Id,
	pc_ty:         spv.Id,
	assert_spec:   spv.Id,
	assert_ptr_ty: spv.Id,
	assert_block:  spv.Id,
	ep:            ^spv.Entry_Point,
	iface_ids:     [dynamic]spv.Id,
	break_stk:     [dynamic]spv.Id,
	cont_stk:      [dynamic]spv.Id,
	return_blk:    spv.Id,
	return_ptr:    spv.Id,
	out_ptrs:      [dynamic]spv.Id,
	stage_outs:    [dynamic]spv.Id,
	stage_out_ents:[dynamic]^Entity,
	fmag_r:        spv.Id,
	dbg_cu:        spv.Id,
	dbg_void:      spv.Id, // DebugSource fallback
	dbg_none:      spv.Id,
	dbg_empty_expr: spv.Id,
	dbg_cur_fn:    spv.Id, // current DebugFunction (lexical scope)
	dbg_types:     map[^Type]spv.Id,
	dbg_aux:       map[string]spv.Id, // pointer / slice debug types
	file_str:      map[string]spv.Id,
	dbg_src:       map[string]spv.Id,
	string_vars:   map[string]spv.Id,
}

spv_err :: proc(cg: ^Spv_CG, pos: Token_Pos, msg: string, args: ..any) {
	cg.error_count += 1
	if cg.err != nil {
		cg.err(pos, msg, ..args)
	} else {
		default_error_handler(pos, msg, ..args)
	}
}

spv_gather_emit_modules :: proc(root: ^Module) -> []^Module {
	out := make([dynamic]^Module, context.temp_allocator)
	visited := make(map[^Module]bool, context.temp_allocator)
	walk :: proc(m: ^Module, visited: ^map[^Module]bool, out: ^[dynamic]^Module) {
		if m == nil || m.kind == .Builtin || m.kind == .Synthetic do return
		if m in visited^ do return
		visited^[m] = true
		for dep in m.imports_resolved {
			walk(dep, visited, out)
		}
		append(out, m)
	}
	walk(root, &visited, &out)
	return out[:]
}

spv_collect_rw_elems :: proc(root: ^Module) -> map[^Type]bool {
	rw := make(map[^Type]bool, context.temp_allocator)
	for m in spv_gather_emit_modules(root) {
		for e in m.definitions {
			if e == nil || e.type == nil do continue
			proc_t, ok := e.type.derived.(^Type_Proc)
			if !ok do continue
			for elem in proc_t.device_store_elems {
				rw[elem] = true
			}
		}
	}
	return rw
}

spv_expr_builtin :: proc(expr: ^Expr) -> (id: Builtin_Proc, call: ^Call_Expr, ok: bool) {
	if expr == nil do return .Invalid, nil, false
	call, ok = unparen_expr(expr).derived.(^Call_Expr)
	if !ok do return .Invalid, nil, false
	callee := entity_from_expr(call.expr)
	if callee == nil || callee.kind != .Builtin do return .Invalid, nil, false
	return callee.builtin_id, call, true
}

spv_debug_name :: proc(e: ^Entity) -> string {
	if e == nil do return ""
	if e.owner_proc != nil && e.owner_proc.name != "" {
		return fmt.tprintf("%s.%s", spv_debug_name(e.owner_proc), e.name)
	}
	return e.name
}

spv_unsigned :: proc(type: ^Type) -> bool {
	t := type_base(type)
	if t == nil do return false
	if bs, ok := t.derived.(^Type_Bit_Set); ok {
		t = bs.underlying
	}
	s, sok := t.derived.(^Type_Scalar)
	if !sok do return false
	return .Unsigned in s.flags || .Boolean in s.flags || .Rune in s.flags
}

spv_device_handle_elem :: proc(type: ^Type) -> (elem: ^Type, is_slice: bool, ok: bool) {
	if type == nil do return nil, false, false
	#partial switch t in type.derived {
	case ^Type_Pointer: return t.elem, false, true
	case ^Type_Multi_Pointer: return t.elem, false, true
	case ^Type_Slice: return t.elem, true, true
	}
	return nil, false, false
}

spv_elem_needs_rw :: proc(cg: ^Spv_CG, elem: ^Type, owner: ^Entity) -> bool {
	if elem == nil do return false
	if owner != nil {
		return proc_callgraph_stores_elem(owner, elem)
	}
	return elem in cg.rw_elems
}

spv_entity_is_param :: proc(cg: ^Spv_CG, e: ^Entity) -> bool {
	if cg.curr_proc == nil || e == nil || cg.curr_proc.params == nil {
		return false
	}
	for p in cg.curr_proc.params.variables {
		if p == e do return true
	}
	return false
}

// RO/RW of a handle *value*: params follow this proc; fields/locals use the module-wide set.
spv_expr_handle_rw :: proc(cg: ^Spv_CG, expr: ^Expr) -> bool {
	if expr == nil || expr.tav.type == nil {
		return false
	}
	elem, _, ok := spv_device_handle_elem(expr.tav.type)
	if !ok {
		return false
	}
	ident, is_ident := unparen_expr(expr).derived.(^Ident)
	if is_ident && ident.entity != nil && spv_entity_is_param(cg, ident.entity) {
		return proc_callgraph_stores_elem(cg.curr_entity, elem)
	}
	#partial switch d in unparen_expr(expr).derived {
	case ^Slice_Expr:
		return spv_expr_handle_rw(cg, d.expr)
	case ^Call_Expr:
		callee := entity_from_expr(d.expr)
		if callee != nil && entity_is_poly_const(callee) && callee.aliased_of != nil {
			callee = callee.aliased_of
		}
		if callee != nil && (callee.kind == .Procedure || callee.kind == .Entry) {
			return proc_callgraph_stores_elem(callee, elem)
		}
	}
	return elem in cg.rw_elems
}

spv_type_for_proc :: proc(cg: ^Spv_CG, type: ^Type, owner: ^Entity, layout: Spv_Layout = .Func) -> spv.Id {
	elem, is_slice, ok := spv_device_handle_elem(type)
	if !ok {
		return spv_type(cg, type, layout)
	}
	rw := proc_callgraph_stores_elem(owner, elem)
	if is_slice {
		return spv_slice_type(cg, elem, layout, rw)
	}
	return spv_psb_ptr(cg, elem, rw).ptr_ty
}

spv_coerce_handle :: proc(cg: ^Spv_CG, val: spv.Id, type: ^Type, src_rw, dst_rw: bool) -> spv.Id {
	elem, is_slice, ok := spv_device_handle_elem(type)
	if !ok || src_rw == dst_rw {
		return val
	}
	if is_slice {
		src_ptr_ty := spv_psb_ptr(cg, elem, src_rw).ptr_ty
		dst_ptr_ty := spv_psb_ptr(cg, elem, dst_rw).ptr_ty
		p := spv.composite_extract(&cg.m, src_ptr_ty, val, 0)
		n := spv.composite_extract(&cg.m, spv.type_i64(&cg.m), val, 1)
		u := spv.convert_ptr_to_u(&cg.m, spv.type_u64(&cg.m), p)
		p2 := spv.convert_u_to_ptr(&cg.m, dst_ptr_ty, u)
		return spv.composite_construct(&cg.m, spv_slice_type(cg, elem, .Func, dst_rw), {p2, n})
	}
	dst := spv_psb_ptr(cg, elem, dst_rw).ptr_ty
	u := spv.convert_ptr_to_u(&cg.m, spv.type_u64(&cg.m), val)
	return spv.convert_u_to_ptr(&cg.m, dst, u)
}

spv_expr_to_owner :: proc(cg: ^Spv_CG, expr: ^Expr, owner: ^Entity) -> spv.Id {
	v := spv_rvalue(cg, expr)
	if expr == nil || expr.tav.type == nil {
		return v
	}
	elem, _, ok := spv_device_handle_elem(expr.tav.type)
	if !ok {
		return v
	}
	return spv_coerce_handle(cg, v, expr.tav.type, spv_expr_handle_rw(cg, expr), spv_elem_needs_rw(cg, elem, owner))
}

spv_target_env :: proc(module: ^Module, needs_ray: bool) -> spirv_tools.Target_Env {
	if needs_ray || (module != nil && module.compat == .No_Gfx) {
		return .Vulkan_1_3
	}
	return .Vulkan_1_2
}

spirv_validate_words :: proc(words: []u32, env: spirv_tools.Target_Env, out_diags: ^[dynamic]Diagnostic = nil) -> bool {
	if len(words) == 0 {
		return false
	}
	ctx := spirv_tools.context_create(env)
	if ctx == nil {
		if out_diags != nil {
			append(out_diags, Diagnostic{
				pos = {file = "<spirv>", line = 1, column = 1},
				severity = .Error,
				message = "spirv-tools: failed to create context",
			})
		} else {
			fmt.eprintfln("SPIRV_VAL_ERR: failed to create context")
		}
		return false
	}
	defer spirv_tools.context_destroy(ctx)
	opts := spirv_tools.validator_options_create()
	defer spirv_tools.validator_options_destroy(opts)
	spirv_tools.validator_options_set_scalar_block_layout(opts, true)
	spirv_tools.validator_options_set_workgroup_scalar_block_layout(opts, true)
	bin := spirv_tools.Binary{
		code = raw_data(words),
		word_count = uint(len(words)),
	}
	diag: ^spirv_tools.Diagnostic
	result := spirv_tools.validate_with_options(ctx, opts, bin, &diag)
	if diag != nil {
		defer spirv_tools.diagnostic_destroy(diag)
		msg := string(diag.error) if diag.error != nil else "validate failed"
		if out_diags != nil {
			append(out_diags, Diagnostic{
				pos = {file = "<spirv>", line = 1, column = 1},
				severity = .Error,
				message = fmt.tprintf("spirv-val: %s", msg),
			})
		} else {
			fmt.eprintfln("SPIRV_VAL_ERR: %s", msg)
		}
		return false
	}
	if result != .Success {
		if out_diags != nil {
			append(out_diags, Diagnostic{
				pos = {file = "<spirv>", line = 1, column = 1},
				severity = .Error,
				message = fmt.tprintf("spirv-val: validate failed (%v)", result),
			})
		} else {
			fmt.eprintfln("SPIRV_VAL_ERR: validate failed (%v)", result)
		}
		return false
	}
	return true
}

spirv_builder_self_test :: proc(out_diags: ^[dynamic]Diagnostic = nil) -> bool {
	words := spv.build_empty_compute("empty", context.temp_allocator)
	return spirv_validate_words(words, .Vulkan_1_2, out_diags)
}

spv_helper_timing_name :: proc(e: ^Entity) -> string {
	if e == nil do return ""
	pt, ok := e.type.derived.(^Type_Proc)
	if ok && pt.is_poly_specialized {
		return fmt.tprintf("%s_%x", e.name, poly_const_key_hash(e))
	}
	return e.name
}

@(private = "package")
codegen_spirv :: proc(module: ^Module, entry: ^Entity, code_allocator: runtime.Allocator, emit := Spirv_Emit{}, et: ^Entry_Timing = nil) -> (code: []u32, ok: bool) {
	context.allocator = context.temp_allocator
	if module == nil || entry == nil {
		return nil, false
	}
	pt, pok := entry.type.derived.(^Type_Proc)
	if !pok || pt.stage == nil {
		fmt.eprintfln("codegen_spirv: '%s' is not a GPU entry", entry.name)
		return nil, false
	}
	stage := pt.stage.?
	setup_start := time.tick_now()

	cg: Spv_CG
	cg.m = spv.module_create(context.temp_allocator)
	cg.m.emit_names = emit.names
	cg.module = module
	cg.entry = entry
	cg.stage = stage
	cg.compat = module.compat
	cg.err = default_error_handler
	cg.rw_elems = spv_collect_rw_elems(module)
	cg.disable_asserts = module.disable_asserts
	cg.bounds_check = !module.no_bounds_check
	cg.debug_info = emit.debug_info
	cg.embed_source = emit.debug_info && emit.embed_source
	cg.named_entry = emit.named_entry
	cg.assert_buffer_spec_id = emit.assert_buffer_spec_id
	cg.type_fn = make(map[^Type]spv.Id, context.temp_allocator)
	cg.type_stored = make(map[^Type]spv.Id, context.temp_allocator)
	cg.psb_ro = make(map[^Type]Spv_Psb, context.temp_allocator)
	cg.psb_rw = make(map[^Type]Spv_Psb, context.temp_allocator)
	cg.psb_ro_id = make(map[spv.Id]Spv_Psb, context.temp_allocator)
	cg.psb_rw_id = make(map[spv.Id]Spv_Psb, context.temp_allocator)
	cg.slice_fn = make(map[^Type]spv.Id, context.temp_allocator)
	cg.slice_st = make(map[^Type]spv.Id, context.temp_allocator)
	cg.entity_ptr = make(map[^Entity]spv.Id, context.temp_allocator)
	cg.entity_sc = make(map[^Entity]spv.Storage_Class, context.temp_allocator)
	cg.entity_val_ty = make(map[^Entity]spv.Id, context.temp_allocator)
	cg.entity_alias = make(map[^Entity]bool, context.temp_allocator)
	cg.fn_id = make(map[^Entity]spv.Id, context.temp_allocator)
	cg.file_str = make(map[string]spv.Id, context.temp_allocator)
	cg.dbg_src = make(map[string]spv.Id, context.temp_allocator)
	cg.dbg_types = make(map[^Type]spv.Id, context.temp_allocator)
	cg.dbg_aux = make(map[string]spv.Id, context.temp_allocator)
	cg.string_vars = make(map[string]spv.Id, context.temp_allocator)
	cg.iface_ids = make([dynamic]spv.Id, context.temp_allocator)
	cg.break_stk = make([dynamic]spv.Id, context.temp_allocator)
	cg.cont_stk = make([dynamic]spv.Id, context.temp_allocator)
	cg.out_ptrs = make([dynamic]spv.Id, context.temp_allocator)
	cg.stage_outs = make([dynamic]spv.Id, context.temp_allocator)
	cg.stage_out_ents = make([dynamic]^Entity, context.temp_allocator)

	emit_mods := spv_gather_emit_modules(module)
	cg.needs_ray_query = spv_dag_needs_ray_query(emit_mods)
	cg.needs_assert = !cg.disable_asserts && spv_dag_needs_assert(emit_mods)

	spv.require_cap(&cg.m, .Shader)
	spv.require_cap(&cg.m, .PhysicalStorageBufferAddresses)
	spv.require_ext(&cg.m, spv.EXT_PHYSICAL_STORAGE_BUFFER)
	spv.require_cap(&cg.m, .RuntimeDescriptorArray)
	spv.require_cap(&cg.m, .ShaderNonUniform)
	spv.require_cap(&cg.m, .SampledImageArrayNonUniformIndexing)
	spv.require_cap(&cg.m, .StorageImageArrayNonUniformIndexing)
	spv.require_cap(&cg.m, .Sampled1D)
	spv.require_cap(&cg.m, .Image1D)
	spv.require_cap(&cg.m, .ImageCubeArray)
	spv.require_cap(&cg.m, .SampledCubeArray)
	spv.require_cap(&cg.m, .ImageQuery)
	spv.require_cap(&cg.m, .StorageImageReadWithoutFormat)
	spv.require_cap(&cg.m, .StorageImageWriteWithoutFormat)
	spv.set_memory_model(&cg.m, .PhysicalStorageBuffer64, .GLSL450)

	spv_emit_debug_source(&cg)
	spv_emit_bindless(&cg)
	spv_ensure_voidptr(&cg)
	if cg.needs_assert {
		spv_emit_assert_types(&cg)
	}

	helpers := spv_collect_reachable_helpers(entry, stage)
	for e in helpers {
		cg.fn_id[e] = spv.alloc_id(&cg.m)
	}
	if et != nil {
		et.setup = time.tick_diff(setup_start, time.tick_now())
		et.helper_count = len(helpers)
		et.helper_emits = make([]Helper_Timing, len(helpers), context.temp_allocator)
	}

	helpers_start := time.tick_now()
	for e, i in helpers {
		h_start := time.tick_now()
		spv_emit_proc(&cg, e)
		if et != nil {
			et.helper_emits[i] = Helper_Timing{
				name = spv_helper_timing_name(e),
				dur = time.tick_diff(h_start, time.tick_now()),
			}
		}
	}
	if et != nil {
		et.helpers = time.tick_diff(helpers_start, time.tick_now())
	}

	entry_start := time.tick_now()
	spv_emit_entry(&cg, entry)
	if et != nil {
		et.entry = time.tick_diff(entry_start, time.tick_now())
	}

	if cg.error_count != 0 {
		return nil, false
	}
	asm_start := time.tick_now()
	words := spv.assemble(&cg.m, code_allocator)
	if et != nil {
		et.assemble = time.tick_diff(asm_start, time.tick_now())
		et.words = len(words)
	}
	return words, true
}

spv_collect_reachable_helpers :: proc(entry: ^Entity, stage: Stage) -> []^Entity {
	out := make([dynamic]^Entity, context.temp_allocator)
	seen := make(map[^Entity]bool, context.temp_allocator)
	walk :: proc(e: ^Entity, stage: Stage, seen: ^map[^Entity]bool, out: ^[dynamic]^Entity) {
		if e == nil || e in seen^ do return
		seen^[e] = true
		for c in e.callees {
			walk(c, stage, seen, out)
		}
		if e.kind != .Procedure || e.type == nil do return
		hpt, hok := e.type.derived.(^Type_Proc)
		if !hok do return
		if proc_is_generic_template(hpt) do return
		if .Body_Checked not_in e.flags && e.proc_lit != nil do return
		if hpt.has_stage_gate && hpt.stage_gate != {} {
			if builtin_stage_from_stage(stage) not_in hpt.stage_gate do return
		}
		append(out, e)
	}
	walk(entry, stage, &seen, &out)
	return out[:]
}

spv_iface :: proc(cg: ^Spv_CG, id: spv.Id) {
	if id == spv.NONE {
		return
	}
	for existing in cg.iface_ids {
		if existing == id {
			return
		}
	}
	append(&cg.iface_ids, id)
	if cg.ep != nil {
		spv.entry_iface(cg.ep, id)
	}
}

spv_flush_iface :: proc(cg: ^Spv_CG) {
	if cg.ep == nil {
		return
	}
	for id in cg.iface_ids {
		spv.entry_iface(cg.ep, id)
	}
}

spv_align_of :: proc(type: ^Type) -> u32 {
	a := type_alignof(type)
	if a <= 0 do return 1
	return u32(a)
}

spv_size_of :: proc(type: ^Type) -> u32 {
	s := type_sizeof(type)
	if s <= 0 do return 1
	return u32(s)
}

spv_type :: proc(cg: ^Spv_CG, type: ^Type, layout: Spv_Layout = .Func) -> spv.Id {
	if type == nil {
		return spv.type_void(&cg.m)
	}
	type := default_type(type)
	cache := &cg.type_fn if layout == .Func else &cg.type_stored
	if id, ok := cache[type]; ok {
		return id
	}
	id := spv_type_uncached(cg, type, layout)
	cache[type] = id
	return id
}

spv_type_uncached :: proc(cg: ^Spv_CG, type: ^Type, layout: Spv_Layout) -> spv.Id {
	#partial switch t in type.derived {
	case ^Type_Scalar:
		return spv_scalar_type(cg, t)
	case ^Type_Enum:
		return spv_type(cg, t.base_type, layout)
	case ^Type_Bit_Set:
		return spv_type(cg, t.underlying, layout)
	case ^Type_Vector:
		elem := spv_type(cg, t.elem, layout)
		return spv.type_vector(&cg.m, elem, u32(t.len))
	case ^Type_Matrix:
		col := spv.type_vector(&cg.m, spv_type(cg, t.elem, layout), u32(t.rows))
		mat := spv.type_matrix(&cg.m, col, u32(t.columns))
		return mat
	case ^Type_Array:
		n := spv.const_u32(&cg.m, u32(t.len))
		stride: u32 = 0
		if layout == .Stored {
			stride = spv_size_of(t.elem)
		}
		return spv.type_array(&cg.m, spv_type(cg, t.elem, layout), n, stride)
	case ^Type_Struct:
		return spv_struct_type(cg, type, t, layout)
	case ^Type_Pointer:
		return spv_psb_ptr(cg, t.elem, spv_elem_needs_rw(cg, t.elem, nil)).ptr_ty
	case ^Type_Multi_Pointer:
		return spv_psb_ptr(cg, t.elem, spv_elem_needs_rw(cg, t.elem, nil)).ptr_ty
	case ^Type_Slice:
		return spv_slice_type(cg, t.elem, layout, spv_elem_needs_rw(cg, t.elem, nil))
	case ^Type_Atom:
		if type_is_ray_query(type) {
			return spv.type_ray_query(&cg.m)
		}
		if type_is_string_kind(type) {
			return spv.type_int(&cg.m, 8, false)
		}
		spv_err(cg, {}, "codegen_spirv: unsupported atom type '%s'", string_from_type(type))
		return spv.type_u32(&cg.m)
	}
	spv_err(cg, {}, "codegen_spirv: unsupported type '%s'", string_from_type(type))
	return spv.type_u32(&cg.m)
}

spv_scalar_type :: proc(cg: ^Spv_CG, s: ^Type_Scalar) -> spv.Id {
	if .Float in s.flags {
		if s.size == 8 {
			return spv.type_f64(&cg.m)
		}
		return spv.type_f32(&cg.m)
	}
	width := u32(s.size * 8)
	if width == 0 {
		width = 32
	}
	signed := !spv_unsigned(s)
	return spv.type_int(&cg.m, width, signed)
}

spv_type_debug_name :: proc(type: ^Type) -> string {
	if type == nil {
		return "struct"
	}
	if type.name != "" {
		return type.name
	}
	if type.ir_name != "" {
		return type.ir_name
	}
	return "struct"
}

// Trailing bytes from `#align` after the last field. Matches GLSL `_padding[N]`.
spv_struct_tail_pad :: proc(type: ^Type, st: ^Type_Struct) -> u32 {
	if st == nil || st.fields == nil || len(st.fields.variables) == 0 {
		return 0
	}
	end := 0
	for field in st.fields.variables {
		if field == nil || field.type == nil do continue
		e := field.field_offset + type_sizeof(field.type)
		if e > end {
			end = e
		}
	}
	sz := type_sizeof(type)
	if sz > end {
		return u32(sz - end)
	}
	return 0
}

spv_pad_array_type :: proc(cg: ^Spv_CG, nbytes: u32) -> spv.Id {
	spv.require_cap(&cg.m, .Int8)
	spv.require_cap(&cg.m, .StorageBuffer8BitAccess)
	u8 := spv.type_int(&cg.m, 8, false)
	n := spv.const_u32(&cg.m, nbytes)
	return spv.type_array(&cg.m, u8, n, 1)
}

spv_struct_type :: proc(cg: ^Spv_CG, type: ^Type, st: ^Type_Struct, layout: Spv_Layout) -> spv.Id {
	n := 0
	if st.fields != nil {
		n = len(st.fields.variables)
	}
	pad: u32 = 0
	if layout == .Stored && n > 0 {
		pad = spv_struct_tail_pad(type, st)
	}
	nm := n + (1 if pad > 0 else 0)
	members := make([]spv.Id, max(nm, 1), context.temp_allocator)
	if n == 0 {
		members[0] = spv.type_u32(&cg.m)
		id := spv.type_struct(&cg.m, members, fmt.tprintf("st:%p:%v", type, layout))
		spv.name(&cg.m, id, spv_type_debug_name(type) if type != nil && (type.name != "" || type.ir_name != "") else "empty")
		if layout == .Stored {
			spv.member_decorate(&cg.m, id, 0, .Offset, 0)
		}
		return id
	}
	for field, i in st.fields.variables {
		members[i] = spv_type(cg, field.type, layout)
	}
	if pad > 0 {
		members[n] = spv_pad_array_type(cg, pad)
	}
	id := spv.type_struct(&cg.m, members, fmt.tprintf("st:%p:%v", type, layout))
	spv.name(&cg.m, id, spv_type_debug_name(type))
	for field, i in st.fields.variables {
		if field == nil do continue
		spv.member_name(&cg.m, id, u32(i), field.name)
		if layout == .Stored {
			spv.member_decorate(&cg.m, id, u32(i), .Offset, u32(field.field_offset))
			if type_is_matrix(field.type) {
				mt := field.type.derived.(^Type_Matrix)
				spv.member_decorate(&cg.m, id, u32(i), .ColMajor)
				spv.member_decorate(&cg.m, id, u32(i), .MatrixStride, u32(mt.rows)*spv_size_of(mt.elem))
			}
		}
	}
	if pad > 0 {
		spv.member_name(&cg.m, id, u32(n), "_padding")
		if layout == .Stored {
			spv.member_decorate(&cg.m, id, u32(n), .Offset, spv_size_of(type) - pad)
		}
	}
	return id
}

spv_ensure_voidptr :: proc(cg: ^Spv_CG) {
	if cg.voidptr != spv.NONE {
		return
	}
	wrap := spv_psb_ptr(cg, t_u32, false)
	cg.voidptr = wrap.ptr_ty
	spv.name(&cg.m, cg.voidptr, "_voidptr_")
}

spv_psb_ptr :: proc(cg: ^Spv_CG, elem: ^Type, rw: bool) -> Spv_Psb {
	table := &cg.psb_rw if rw else &cg.psb_ro
	if w, ok := table[elem]; ok {
		return w
	}
	_, is_struct := elem.derived.(^Type_Struct)
	id_table := &cg.psb_rw_id if rw else &cg.psb_ro_id
	if !is_struct {
		stored_id := spv_type(cg, elem, .Stored)
		if w, ok := id_table[stored_id]; ok && w.complete {
			table[elem] = w
			return w
		}
	}
	w: Spv_Psb
	w.ptr_ty = spv.type_forward_pointer(&cg.m, .PhysicalStorageBuffer)
	table[elem] = w
	stored := spv_type(cg, elem, .Stored)
	if shared, ok := id_table[stored]; ok && shared.complete {
		table[elem] = shared
		return shared
	}
	ra := spv.type_runtime_array(&cg.m, stored, spv_size_of(elem))
	block := spv.type_struct(&cg.m, {ra}, fmt.tprintf("psb:%d:%v", stored, rw))
	spv.decorate(&cg.m, block, .Block)
	spv.member_decorate(&cg.m, block, 0, .Offset, 0)
	if !rw {
		spv.member_decorate(&cg.m, block, 0, .NonWritable)
	}
	spv.member_name(&cg.m, block, 0, "ptr")
	spv.name(&cg.m, block, fmt.tprintf("%s%s", spv_type_debug_name(elem), "_Ptr_RW" if rw else "_Ptr_RO"))
	spv.type_pointer_define(&cg.m, w.ptr_ty, .PhysicalStorageBuffer, block)
	w.block_ty = block
	w.complete = true
	table[elem] = w
	id_table[stored] = w
	return w
}

spv_slice_type :: proc(cg: ^Spv_CG, elem: ^Type, layout: Spv_Layout, rw: bool) -> spv.Id {
	ptr := spv_psb_ptr(cg, elem, rw).ptr_ty
	len_ty := spv.type_i64(&cg.m)
	id := spv.type_struct(&cg.m, {ptr, len_ty}, fmt.tprintf("slice:%d:%v:%v", ptr, layout, rw))
	if layout == .Func {
		spv.name(&cg.m, id, fmt.tprintf("%s%s", spv_type_debug_name(elem), "_Slice_RW" if rw else "_Slice_RO"))
	}
	spv.member_name(&cg.m, id, 0, "data")
	spv.member_name(&cg.m, id, 1, "len")
	if layout == .Stored {
		spv.member_decorate(&cg.m, id, 0, .Offset, 0)
		spv.member_decorate(&cg.m, id, 1, .Offset, 8)
	}
	if layout == .Func {
		cg.slice_fn[elem] = id
	} else {
		cg.slice_st[elem] = id
	}
	return id
}

spv_ptr_ty :: proc(cg: ^Spv_CG, sc: spv.Storage_Class, pointee: ^Type, layout: Spv_Layout = .Func) -> spv.Id {
	return spv.type_pointer(&cg.m, sc, spv_type(cg, pointee, layout))
}

spv_fn_var :: proc(cg: ^Spv_CG, type: ^Type, name: string, init: spv.Id = spv.NONE, pos: Token_Pos = {}) -> spv.Id {
	pty := spv_ptr_ty(cg, .Function, type)
	id := spv.fn_var(&cg.m, pty, .Function, init)
	if name != "" {
		spv.name(&cg.m, id, name)
	}
	spv_debug_declare(cg, id, type, name, pos)
	return id
}

spv_fn_var_of :: proc(cg: ^Spv_CG, val_ty: spv.Id, name: string) -> spv.Id {
	pty := spv.type_pointer(&cg.m, .Function, val_ty)
	id := spv.fn_var(&cg.m, pty, .Function)
	if name != "" {
		spv.name(&cg.m, id, name)
	}
	return id
}

spv_bind_entity :: proc(cg: ^Spv_CG, e: ^Entity, ptr: spv.Id, sc: spv.Storage_Class = .Function) {
	if e == nil do return
	cg.entity_ptr[e] = ptr
	cg.entity_sc[e] = sc
}

spv_entity_sc :: proc(cg: ^Spv_CG, e: ^Entity) -> spv.Storage_Class {
	if e != nil {
		if sc, ok := cg.entity_sc[e]; ok {
			return sc
		}
	}
	return .Function
}

spv_change_layout :: proc(cg: ^Spv_CG, v: spv.Id, type: ^Type, from, to: Spv_Layout) -> spv.Id {
	type := default_type(type)
	if from == to || type == nil {
		return v
	}
	#partial switch t in type.derived {
	case ^Type_Struct:
		n := 0
		if t.fields != nil {
			n = len(t.fields.variables)
		}
		if n == 0 {
			return spv_zero(cg, type)
		}
		pad: u32 = 0
		if to == .Stored {
			pad = spv_struct_tail_pad(type, t)
		}
		parts := make([]spv.Id, n + (1 if pad > 0 else 0), context.temp_allocator)
		for field, i in t.fields.variables {
			ex := spv.composite_extract(&cg.m, spv_type(cg, field.type, from), v, u32(i))
			parts[i] = spv_change_layout(cg, ex, field.type, from, to)
		}
		if pad > 0 {
			parts[n] = spv.const_null(&cg.m, spv_pad_array_type(cg, pad))
		}
		return spv.composite_construct(&cg.m, spv_type(cg, type, to), parts)
	case ^Type_Array:
		parts := make([]spv.Id, t.len, context.temp_allocator)
		elem_ty := spv_type(cg, t.elem, from)
		for i in 0 ..< t.len {
			ex := spv.composite_extract(&cg.m, elem_ty, v, u32(i))
			parts[i] = spv_change_layout(cg, ex, t.elem, from, to)
		}
		return spv.composite_construct(&cg.m, spv_type(cg, type, to), parts)
	case ^Type_Slice:
		rw := spv_elem_needs_rw(cg, t.elem, nil)
		ptr_ty := spv_psb_ptr(cg, t.elem, rw).ptr_ty
		p := spv.composite_extract(&cg.m, ptr_ty, v, 0)
		n := spv.composite_extract(&cg.m, spv.type_i64(&cg.m), v, 1)
		return spv.composite_construct(&cg.m, spv_slice_type(cg, t.elem, to, rw), {p, n})
	}
	return v
}

spv_zero :: proc(cg: ^Spv_CG, type: ^Type) -> spv.Id {
	type := default_type(type)
	ty := spv_type(cg, type)
	#partial switch t in type.derived {
	case ^Type_Scalar, ^Type_Enum, ^Type_Bit_Set:
		if type_is_float(type_base(type)) {
			if type_sizeof(type_base(type)) == 8 {
				return spv.const_f64(&cg.m, 0)
			}
			return spv.const_f32(&cg.m, 0)
		}
		return spv.const_int(&cg.m, ty, 0, u32(type_sizeof(type_base(type))*8))
	case ^Type_Vector:
		z := spv_zero(cg, t.elem)
		parts := make([]spv.Id, t.len, context.temp_allocator)
		for i in 0 ..< t.len {
			parts[i] = z
		}
		return spv.const_composite(&cg.m, ty, parts)
	case ^Type_Matrix:
		col_ty := spv.type_vector(&cg.m, spv_type(cg, t.elem), u32(t.rows))
		col_z := spv_zero(cg, vec_type(t.elem, int(t.rows)))
		parts := make([]spv.Id, t.columns, context.temp_allocator)
		for i in 0 ..< t.columns {
			parts[i] = col_z
		}
		_ = col_ty
		return spv.const_composite(&cg.m, ty, parts)
	case ^Type_Array:
		if t.len <= 0 {
			return spv.const_null(&cg.m, ty)
		}
		z := spv_zero(cg, t.elem)
		parts := make([]spv.Id, t.len, context.temp_allocator)
		for i in 0 ..< t.len {
			parts[i] = z
		}
		return spv.const_composite(&cg.m, ty, parts)
	case ^Type_Struct:
		if t.fields == nil || len(t.fields.variables) == 0 {
			return spv.const_null(&cg.m, ty)
		}
		parts := make([]spv.Id, len(t.fields.variables), context.temp_allocator)
		for field, i in t.fields.variables {
			parts[i] = spv_zero(cg, field.type)
		}
		return spv.const_composite(&cg.m, ty, parts)
	case ^Type_Pointer, ^Type_Multi_Pointer:
		return spv.const_null(&cg.m, ty)
	case ^Type_Slice:
		st, _ := type.derived.(^Type_Slice)
		rw := spv_elem_needs_rw(cg, st.elem, nil)
		ptr := spv.const_null(&cg.m, spv_psb_ptr(cg, st.elem, rw).ptr_ty)
		ln := spv.const_i64(&cg.m, 0)
		return spv.const_composite(&cg.m, ty, {ptr, ln})
	}
	return spv.const_null(&cg.m, ty)
}

spv_const_value :: proc(cg: ^Spv_CG, type: ^Type, value: Exact_Value) -> spv.Id {
	type := default_type(type)
	if type_is_string_kind(type) {
		return spv.const_u32(&cg.m, 0)
	}
	if value == nil {
		return spv_zero(cg, type)
	}
	ty := spv_type(cg, type)
	if type_is_vector(type) || type_is_matrix(type) {
		#partial switch v in value {
		case i128:
			elem := type_base(type)
			s := spv_const_value(cg, elem, v)
			return spv_splat(cg, type, s)
		case f64:
			elem := type_base(type)
			s := spv_const_value(cg, elem, v)
			return spv_splat(cg, type, s)
		case bool:
			elem := type_base(type)
			s := spv_const_value(cg, elem, v)
			return spv_splat(cg, type, s)
		}
	}
	#partial switch v in value {
	case bool:
		if type_is_boolean(type) && !type_is_untyped(type) {
			bits := u64(1 if v else 0)
			return spv.const_int(&cg.m, ty, bits, u32(type_sizeof(type)*8))
		}
		return spv.const_bool(&cg.m, v)
	case i128:
		if type_is_float(type_base(type)) {
			if type_sizeof(type_base(type)) == 8 {
				return spv.const_f64(&cg.m, f64(v))
			}
			return spv.const_f32(&cg.m, f32(v))
		}
		width := u32(type_sizeof(type_base(type)) * 8)
		if width == 0 do width = 32
		return spv.const_int(&cg.m, ty, u64(v), width)
	case f64:
		if type_sizeof(type_base(type)) == 8 {
			return spv.const_f64(&cg.m, v)
		}
		return spv.const_f32(&cg.m, f32(v))
	case string:
		if type_is_string_kind(type) {
			return spv.const_u32(&cg.m, 0)
		}
	}
	return spv_zero(cg, type)
}

spv_const_string :: proc(expr: ^Expr) -> (s: string, ok: bool) {
	if expr == nil {
		return "", false
	}
	if str, sok := expr.tav.value.(string); sok {
		return str, true
	}
	if ident, iok := expr.derived.(^Ident); iok && ident.entity != nil {
		if str, sok := ident.entity.value.(string); sok {
			return str, true
		}
	}
	return "", false
}

spv_intern_string :: proc(cg: ^Spv_CG, s: string) -> spv.Id {
	if len(s) == 0 {
		return spv.NONE
	}
	if id, ok := cg.string_vars[s]; ok {
		return id
	}
	u8ty := spv.type_int(&cg.m, 8, false)
	n := spv.const_u32(&cg.m, u32(len(s)))
	arr_ty := spv.type_array(&cg.m, u8ty, n)
	parts := make([]spv.Id, len(s), context.temp_allocator)
	for i in 0 ..< len(s) {
		parts[i] = spv.const_int(&cg.m, u8ty, u64(s[i]), 8)
	}
	init := spv.const_composite(&cg.m, arr_ty, parts)
	pty := spv.type_pointer(&cg.m, .Private, arr_ty)
	id := spv.global_var(&cg.m, pty, .Private, init)
	h := fnv32a_bytes(transmute([]u8)s)
	spv.name(&cg.m, id, fmt.tprintf("_str_%x", h))
	spv_iface(cg, id)
	key := strings.clone(s)
	cg.string_vars[key] = id
	return id
}

spv_string_index :: proc(cg: ^Spv_CG, v: ^Index_Expr) -> spv.Id {
	s, ok := spv_const_string(v.expr)
	if !ok || len(s) == 0 {
		return spv_zero(cg, v.tav.type)
	}
	arr := spv_intern_string(cg, s)
	idx := spv_index_as_u32(cg, v.index)
	u8ty := spv.type_int(&cg.m, 8, false)
	elem_ptr := spv.type_pointer(&cg.m, .Private, u8ty)
	ch := spv.access_chain(&cg.m, elem_ptr, arr, {idx})
	b := spv.load(&cg.m, u8ty, ch)
	return spv_convert(cg, b, t_u8, v.tav.type)
}

spv_splat :: proc(cg: ^Spv_CG, type: ^Type, scalar: spv.Id) -> spv.Id {
	ty := spv_type(cg, type)
	if v, ok := type.derived.(^Type_Vector); ok {
		parts := make([]spv.Id, v.len, context.temp_allocator)
		for i in 0 ..< v.len {
			parts[i] = scalar
		}
		return spv.composite_construct(&cg.m, ty, parts)
	}
	if m, ok := type.derived.(^Type_Matrix); ok {
		col_t := vec_type(m.elem, int(m.rows))
		col := spv_splat(cg, col_t, scalar)
		parts := make([]spv.Id, m.columns, context.temp_allocator)
		for i in 0 ..< m.columns {
			parts[i] = col
		}
		return spv.composite_construct(&cg.m, ty, parts)
	}
	return scalar
}

spv_load_ptr :: proc(cg: ^Spv_CG, l: Spv_Lval) -> spv.Id {
	if len(l.swizzle) > 0 && l.vec != nil {
		full := spv.load(&cg.m, spv_type(cg, l.vec), l.ptr)
		return spv_swizzle_extract(cg, full, l.vec, spv_swizzle_name(l.swizzle), l.type)
	}
	ty := spv_type(cg, l.type, .Stored if l.aligned else .Func)
	loaded: spv.Id
	if l.aligned {
		loaded = spv.load_aligned(&cg.m, ty, l.ptr, l.align if l.align != 0 else spv_align_of(l.type))
	} else {
		loaded = spv.load(&cg.m, ty, l.ptr)
	}
	if l.aligned && l.sc == .PhysicalStorageBuffer {
		return spv_change_layout(cg, loaded, l.type, .Stored, .Func)
	}
	return loaded
}

spv_store_ptr :: proc(cg: ^Spv_CG, l: Spv_Lval, val: spv.Id) {
	if len(l.swizzle) > 0 && l.vec != nil {
		full := spv.load(&cg.m, spv_type(cg, l.vec), l.ptr)
		vt := l.vec.derived.(^Type_Vector)
		cur := full
		if len(l.swizzle) == 1 {
			cur = spv.composite_insert(&cg.m, spv_type(cg, l.vec), val, full, l.swizzle[0])
		} else {
			elem_ty := spv_type(cg, vt.elem)
			for c, i in l.swizzle {
				part := spv.composite_extract(&cg.m, elem_ty, val, u32(i))
				cur = spv.composite_insert(&cg.m, spv_type(cg, l.vec), part, cur, c)
			}
		}
		if l.aligned {
			spv.store_aligned(&cg.m, l.ptr, cur, l.align if l.align != 0 else spv_align_of(l.vec))
		} else {
			spv.store(&cg.m, l.ptr, cur)
		}
		return
	}
	stored := val
	if l.aligned && l.sc == .PhysicalStorageBuffer {
		stored = spv_change_layout(cg, val, l.type, .Func, .Stored)
	}
	if l.aligned {
		spv.store_aligned(&cg.m, l.ptr, stored, l.align if l.align != 0 else spv_align_of(l.type))
		return
	}
	spv.store(&cg.m, l.ptr, stored)
}

spv_swizzle_name :: proc(comps: []u32) -> string {
	letters := "xyzw"
	buf := make([]u8, len(comps), context.temp_allocator)
	for c, i in comps {
		buf[i] = letters[c] if c < 4 else 'x'
	}
	return string(buf)
}

spv_bool_type :: proc(cg: ^Spv_CG, type: ^Type) -> spv.Id {
	_, n := type_gen_break(default_type(type))
	if n <= 1 {
		return spv.type_bool(&cg.m)
	}
	return spv.type_vector(&cg.m, spv.type_bool(&cg.m), u32(n))
}

spv_as_bool :: proc(cg: ^Spv_CG, v: spv.Id, type: ^Type) -> spv.Id {
	t := default_type(type)
	elem, n := type_gen_break(t)
	_ = n
	if elem != nil && (type_is_boolean(elem) || type_is_integer(elem) || type_is_enum(elem) || type_is_bit_set(elem)) {
		z := spv_zero(cg, t)
		return spv.inot_equal_ty(&cg.m, spv_bool_type(cg, t), v, z)
	}
	return v
}

spv_from_bool :: proc(cg: ^Spv_CG, b: spv.Id, type: ^Type) -> spv.Id {
	type := default_type(type)
	elem, n := type_gen_break(type)
	if elem != nil && type_is_boolean(elem) && !type_is_untyped(elem) {
		ty := spv_type(cg, type)
		bits := u32(max(type_sizeof(elem)*8, 32))
		one_s := spv.const_int(&cg.m, spv_type(cg, elem), 1, bits)
		zero_s := spv.const_int(&cg.m, spv_type(cg, elem), 0, bits)
		one := one_s if n <= 1 else spv_splat(cg, type, one_s)
		zero := zero_s if n <= 1 else spv_splat(cg, type, zero_s)
		return spv.select(&cg.m, ty, b, one, zero)
	}
	return b
}

spv_u32 :: proc(cg: ^Spv_CG, v: spv.Id, from: ^Type) -> spv.Id {
	from := default_type(from)
	if type_eq(from, t_u32) || type_eq(from, t_b32) {
		return v
	}
	dst := spv.type_u32(&cg.m)
	if type_is_float(from) {
		return spv.convert_f_to_u(&cg.m, dst, v)
	}
	if spv_unsigned(from) {
		if type_sizeof(from) == 4 {
			return v
		}
		return spv.uconvert(&cg.m, dst, v)
	}
	return spv.sconvert(&cg.m, dst, v) if type_sizeof(from) != 4 else spv.bitcast(&cg.m, dst, v)
}

spv_convert :: proc(cg: ^Spv_CG, v: spv.Id, from, to: ^Type) -> spv.Id {
	from := default_type(from)
	to := default_type(to)
	if from == nil || to == nil || type_eq(from, to) {
		return v
	}
	if type_is_multi_pointer(from) && type_is_pointer(to) {
		return v
	}
	if type_is_pointer(from) && type_is_multi_pointer(to) {
		return v
	}
	dst := spv_type(cg, to)
	if type_is_boolean(to) && !type_is_untyped(to) && type_is_boolean(from) && type_is_untyped(from) {
		return spv_from_bool(cg, v, to)
	}
	if type_is_vector(from) && type_is_vector(to) {
		return spv_convert_scalar_like(cg, v, type_base(from), type_base(to), dst)
	}
	return spv_convert_scalar_like(cg, v, from, to, dst)
}

spv_convert_scalar_like :: proc(cg: ^Spv_CG, v: spv.Id, from, to: ^Type, dst: spv.Id) -> spv.Id {
	from_b := type_base(from)
	to_b := type_base(to)
	if from_b == nil || to_b == nil {
		return v
	}
	ff := type_is_float(from_b)
	tf := type_is_float(to_b)
	fs := type_sizeof(from_b)
	ts := type_sizeof(to_b)
	fu := spv_unsigned(from_b)
	tu := spv_unsigned(to_b)
	if ff && tf {
		if fs == ts do return v
		return spv.fconvert(&cg.m, dst, v)
	}
	if ff && !tf {
		if tu {
			return spv.convert_f_to_u(&cg.m, dst, v)
		}
		return spv.convert_f_to_s(&cg.m, dst, v)
	}
	if !ff && tf {
		if fu {
			return spv.convert_u_to_f(&cg.m, dst, v)
		}
		return spv.convert_s_to_f(&cg.m, dst, v)
	}
	if fs == ts {
		if fu == tu do return v
		return spv.bitcast(&cg.m, dst, v)
	}
	if tu {
		return spv.uconvert(&cg.m, dst, v)
	}
	return spv.sconvert(&cg.m, dst, v)
}
