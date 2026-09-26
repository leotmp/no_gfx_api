package misl

import "core:fmt"
import "core:strings"

import spv "spirv"

SPV_ASSERT_KIND_USER :: u32(1)
SPV_ASSERT_KIND_PANIC :: u32(2)
SPV_ASSERT_KIND_SLICE_INDEX :: u32(3)

spv_named_type :: proc(cg: ^Spv_CG, name: string) -> ^Type {
	if cg.module == nil || cg.module.scope == nil {
		return nil
	}
	e := scope_lookup(cg.module.scope, name)
	if e == nil || e.type == nil {
		return nil
	}
	return e.type
}

spv_view_dim :: proc(view: Resource_View) -> (dim: spv.Dim, arrayed: u32) {
	switch view {
	case .Invalid, .D2:
		return ._2D, 0
	case .D1:
		return ._1D, 0
	case .D3:
		return ._3D, 0
	case .Cube:
		return .Cube, 0
	case .D1_Array:
		return ._1D, 1
	case .D2_Array:
		return ._2D, 1
	case .Cube_Array:
		return .Cube, 1
	}
	return ._2D, 0
}

spv_bindless_name :: proc(rw: bool, view: Resource_View) -> string {
	if rw {
		switch view {
		case .Invalid, .D2: return "RW_TEXTURES"
		case .D1: return "RW_TEXTURES_1D"
		case .D3: return "RW_TEXTURES_3D"
		case .Cube: return "RW_TEXTURES_CUBE"
		case .D1_Array: return "RW_TEXTURES_1D_ARRAY"
		case .D2_Array: return "RW_TEXTURES_2D_ARRAY"
		case .Cube_Array: return "RW_TEXTURES_CUBE_ARRAY"
		}
	} else {
		switch view {
		case .Invalid, .D2: return "TEXTURES"
		case .D1: return "TEXTURES_1D"
		case .D3: return "TEXTURES_3D"
		case .Cube: return "TEXTURES_CUBE"
		case .D1_Array: return "TEXTURES_1D_ARRAY"
		case .D2_Array: return "TEXTURES_2D_ARRAY"
		case .Cube_Array: return "TEXTURES_CUBE_ARRAY"
		}
	}
	return "TEXTURES"
}

spv_image_type :: proc(cg: ^Spv_CG, view: Resource_View, storage: bool) -> spv.Id {
	dim, arrayed := spv_view_dim(view)
	sampled: u32 = 2 if storage else 1
	return spv.type_image(&cg.m, spv.type_f32(&cg.m), dim, 0, arrayed, 0, sampled, .Unknown)
}

spv_bindless_array :: proc(cg: ^Spv_CG, set, binding: u32, elem_ty: spv.Id, name: string) -> spv.Id {
	ra := spv.type_runtime_array(&cg.m, elem_ty)
	pty := spv.type_pointer(&cg.m, .UniformConstant, ra)
	var := spv.global_var(&cg.m, pty, .UniformConstant)
	spv.decorate(&cg.m, var, .DescriptorSet, set)
	spv.decorate(&cg.m, var, .Binding, binding)
	spv.name(&cg.m, var, name)
	spv_iface(cg, var)
	return var
}

spv_emit_bindless :: proc(cg: ^Spv_CG) {
	tex_set, rw_set, samp_set: u32 = 0, 0, 0
	tex_bind, rw_bind, samp_bind: u32 = 0, 1, 2
	bvh_set, bvh_bind: u32 = 0, 3
	if cg.compat == .No_Gfx {
		rw_set, samp_set = 1, 2
		rw_bind, samp_bind = 0, 0
		bvh_set, bvh_bind = 3, 0
	}
	views := []Resource_View{.D2, .D1, .D3, .Cube, .D1_Array, .D2_Array, .Cube_Array}
	for view in views {
		img := spv_image_type(cg, view, false)
		cg.bindless.tex[view] = spv_bindless_array(cg, tex_set, tex_bind, img, spv_bindless_name(false, view))
	}
	for view in views {
		img := spv_image_type(cg, view, true)
		cg.bindless.rw[view] = spv_bindless_array(cg, rw_set, rw_bind, img, spv_bindless_name(true, view))
	}
	samp_ty := spv.type_sampler(&cg.m)
	cg.bindless.samp = spv_bindless_array(cg, samp_set, samp_bind, samp_ty, "SAMPLERS")
	cg.bindless.samp_cmp = spv_bindless_array(cg, samp_set, samp_bind, samp_ty, "SAMPLERS_CMP")
	if cg.needs_ray_query {
		as := spv.type_acceleration_structure(&cg.m)
		cg.bindless.bvh = spv_bindless_array(cg, bvh_set, bvh_bind, as, "BVHS")
	}
}

spv_nu_load :: proc(cg: ^Spv_CG, result_ty, array_var: spv.Id, index: spv.Id) -> spv.Id {
	spv.decorate(&cg.m, index, .NonUniform)
	elem_ptr := spv.type_pointer(&cg.m, .UniformConstant, result_ty)
	ch := spv.access_chain(&cg.m, elem_ptr, array_var, {index})
	spv.decorate(&cg.m, ch, .NonUniform)
	loaded := spv.load(&cg.m, result_ty, ch)
	spv.decorate(&cg.m, loaded, .NonUniform)
	return loaded
}

spv_handle_u32 :: proc(cg: ^Spv_CG, expr: ^Expr) -> spv.Id {
	return spv_u32(cg, spv_rvalue(cg, expr), expr.tav.type)
}

spv_sample :: proc(cg: ^Spv_CG, call: ^Call_Expr) -> spv.Id {
	tex_t := call.args[0].tav.type
	samp_t := call.args[1].tav.type
	view := resource_view_of(tex_t)
	if view == .Invalid {
		view = .D2
	}
	idx := spv_handle_u32(cg, call.args[0])
	sidx := spv_handle_u32(cg, call.args[1])
	img_ty := spv_image_type(cg, view, false)
	img := spv_nu_load(cg, img_ty, cg.bindless.tex[view], idx)
	is_cmp := type_is_compare_sampler_id(samp_t)
	samp_arr := cg.bindless.samp_cmp if is_cmp else cg.bindless.samp
	samp := spv_nu_load(cg, spv.type_sampler(&cg.m), samp_arr, sidx)
	sampled_ty := spv.type_sampled_image(&cg.m, img_ty)
	comb := spv.sampled_image(&cg.m, sampled_ty, img, samp)
	coord := spv_rvalue(cg, call.args[2])
	if is_cmp {
		dim, arrayed := spv_view_dim(view)
		_ = spv.type_image(&cg.m, spv.type_f32(&cg.m), dim, 1, arrayed, 0, 1, .Unknown)
		ref := spv_rvalue(cg, call.args[3])
		has_lod := len(call.args) == 5
		if has_lod {
			lod := spv_rvalue(cg, call.args[4])
			return spv.image_sample_dref_explicit_lod(&cg.m, spv.type_f32(&cg.m), comb, coord, ref, lod)
		}
		return spv.image_sample_dref_implicit(&cg.m, spv.type_f32(&cg.m), comb, coord, ref)
	}
	res := spv.type_vector(&cg.m, spv.type_f32(&cg.m), 4)
	if len(call.args) == 4 {
		lod := spv_rvalue(cg, call.args[3])
		return spv.image_sample_explicit_lod(&cg.m, res, comb, coord, lod)
	}
	return spv.image_sample_implicit(&cg.m, res, comb, coord)
}

spv_image_load :: proc(cg: ^Spv_CG, call: ^Call_Expr) -> spv.Id {
	handle_t := call.args[0].tav.type
	view := resource_view_of(handle_t)
	if view == .Invalid {
		view = .D2
	}
	idx := spv_handle_u32(cg, call.args[0])
	coord := spv_rvalue(cg, call.args[1])
	res := spv.type_vector(&cg.m, spv.type_f32(&cg.m), 4)
	if type_is_rw_texture_id(handle_t) {
		img_ty := spv_image_type(cg, view, true)
		img := spv_nu_load(cg, img_ty, cg.bindless.rw[view], idx)
		return spv.image_read(&cg.m, res, img, coord)
	}
	img_ty := spv_image_type(cg, view, false)
	img := spv_nu_load(cg, img_ty, cg.bindless.tex[view], idx)
	lod := spv.const_u32(&cg.m, 0)
	if len(call.args) >= 3 {
		lod = spv_u32(cg, spv_rvalue(cg, call.args[2]), call.args[2].tav.type)
	}
	return spv.image_fetch(&cg.m, res, img, coord, lod)
}

spv_image_store :: proc(cg: ^Spv_CG, call: ^Call_Expr) {
	handle_t := call.args[0].tav.type
	view := resource_view_of(handle_t)
	if view == .Invalid {
		view = .D2
	}
	idx := spv_handle_u32(cg, call.args[0])
	img_ty := spv_image_type(cg, view, true)
	img := spv_nu_load(cg, img_ty, cg.bindless.rw[view], idx)
	coord := spv_rvalue(cg, call.args[1])
	texel := spv_rvalue(cg, call.args[2])
	spv.image_write(&cg.m, img, coord, texel)
}

spv_image_dim :: proc(cg: ^Spv_CG, call: ^Call_Expr) -> spv.Id {
	handle_t := call.args[0].tav.type
	view := resource_view_of(handle_t)
	if view == .Invalid {
		view = .D2
	}
	n := resource_view_dim_len(view)
	res_t := call.tav.type
	idx := spv_handle_u32(cg, call.args[0])
	if type_is_rw_texture_id(handle_t) {
		img_ty := spv_image_type(cg, view, true)
		img := spv_nu_load(cg, img_ty, cg.bindless.rw[view], idx)
		sz := spv.image_query_size(&cg.m, spv_type(cg, res_t), img)
		return sz
	}
	img_ty := spv_image_type(cg, view, false)
	img := spv_nu_load(cg, img_ty, cg.bindless.tex[view], idx)
	lod := spv.const_u32(&cg.m, 0)
	sz := spv.image_query_size_lod(&cg.m, spv_type(cg, res_t), img, lod)
	_ = n
	return sz
}

spv_const_from_entity :: proc(cg: ^Spv_CG, e: ^Entity) -> spv.Id {
	if e.value == nil {
		return spv_zero(cg, e.type)
	}
	if expr, ok := e.value.(^Expr); ok {
		if lit, lok := expr.derived.(^Comp_Lit); lok {
			return spv_const_comp_lit(cg, lit, e.type)
		}
	}
	return spv_const_value(cg, e.type, e.value)
}

// Named array consts are Private globals. SPIR-V 1.4+ puts every referenced
// global on OpEntryPoint; unused tables from imported modules (MINI_FONT, Bayer)
// still listed there AV some GPUs at vkCreateGraphicsPipelines. Emit on use.
spv_ensure_array_const :: proc(cg: ^Spv_CG, e: ^Entity) {
	if e == nil {
		return
	}
	if _, ok := cg.entity_ptr[e]; ok {
		return
	}
	init := spv_const_from_entity(cg, e)
	pty := spv_ptr_ty(cg, .Private, e.type)
	var := spv.global_var(&cg.m, pty, .Private, init)
	spv.name(&cg.m, var, spv_debug_name(e))
	spv_bind_entity(cg, e, var, .Private)
	spv_iface(cg, var)
}

spv_const_comp_lit :: proc(cg: ^Spv_CG, v: ^Comp_Lit, type: ^Type) -> spv.Id {
	t := default_type(type if type != nil else v.tav.type)
	if arr, ok := t.derived.(^Type_Array); ok {
		parts := make([]spv.Id, arr.len, context.temp_allocator)
		z := spv_zero(cg, arr.elem)
		for i in 0 ..< arr.len {
			parts[i] = z
		}
		for elem, i in v.elems {
			value := elem
			if fv, is_fv := elem.derived.(^Field_Value); is_fv {
				value = fv.value
			}
			if i < arr.len && value != nil && value.tav.value != nil {
				parts[i] = spv_const_value(cg, arr.elem, value.tav.value)
			}
		}
		return spv.const_composite(&cg.m, spv_type(cg, t), parts)
	}
	return spv_zero(cg, t)
}

spv_pc_member_ty :: proc(cg: ^Spv_CG, t: ^Type) -> spv.Id {
	if t == nil {
		return cg.voidptr
	}
	return spv_type(cg, t, .Stored)
}

spv_emit_push_constants :: proc(cg: ^Spv_CG, pt: ^Type_Proc) -> (used_data: ^Type, used_indirect: ^Type) {
	for param in pt.params.variables {
		if param.semantic == .Data {
			used_data = param.type
		} else if param.semantic == .Indirect_Data {
			used_indirect = param.type
		}
	}
	if used_data == nil && used_indirect == nil {
		return
	}
	is_compute := cg.stage == .Compute
	members: [dynamic]spv.Id
	members.allocator = context.temp_allocator
	if is_compute {
		append(&members, spv_pc_member_ty(cg, used_data))
	} else {
		data_index := 1 if cg.stage == .Fragment else 0
		for index in 0 ..< 2 {
			if used_data != nil && index == data_index {
				append(&members, spv_pc_member_ty(cg, used_data))
			} else {
				append(&members, cg.voidptr)
			}
		}
		append(&members, spv_pc_member_ty(cg, used_indirect))
	}
	cg.pc_ty = spv.type_struct(&cg.m, members[:], fmt.tprintf("pc:%p:%v", pt, cg.stage))
	spv.decorate(&cg.m, cg.pc_ty, .Block)
	spv.name(&cg.m, cg.pc_ty, "PC_Compute" if is_compute else "PC_Graphics")
	off: u32 = 0
	for _, i in members {
		spv.member_decorate(&cg.m, cg.pc_ty, u32(i), .Offset, off)
		off += 8
	}
	if is_compute {
		spv.member_name(&cg.m, cg.pc_ty, 0, "_data_")
	} else {
		spv.member_name(&cg.m, cg.pc_ty, 0, "_data_" if cg.stage == .Vertex && used_data != nil else "_0_")
		spv.member_name(&cg.m, cg.pc_ty, 1, "_data_" if cg.stage == .Fragment && used_data != nil else "_1_")
		if cg.stage == .Vertex && used_data != nil {
			spv.member_name(&cg.m, cg.pc_ty, 0, "_data_")
		}
		spv.member_name(&cg.m, cg.pc_ty, 2, "_indirect_data_")
	}
	pty := spv.type_pointer(&cg.m, .PushConstant, cg.pc_ty)
	cg.pc_var = spv.global_var(&cg.m, pty, .PushConstant)
	spv.name(&cg.m, cg.pc_var, "_pc_")
	spv_iface(cg, cg.pc_var)
	return
}

spv_builtin_var :: proc(cg: ^Spv_CG, builtin: spv.Built_In, ty: spv.Id, name: string, sc: spv.Storage_Class = .Input) -> spv.Id {
	pty := spv.type_pointer(&cg.m, sc, ty)
	v := spv.global_var(&cg.m, pty, sc)
	spv.decorate(&cg.m, v, .BuiltIn, u32(builtin))
	spv.name(&cg.m, v, name)
	spv_iface(cg, v)
	if builtin == .DrawIndex {
		spv.require_cap(&cg.m, .DrawParameters)
	}
	return v
}

spv_io_var :: proc(cg: ^Spv_CG, field: ^Entity, location: u32, sc: spv.Storage_Class, prefix: string) -> spv.Id {
	ty := spv_type(cg, field.type)
	pty := spv.type_pointer(&cg.m, sc, ty)
	v := spv.global_var(&cg.m, pty, sc)
	spv.decorate(&cg.m, v, .Location, location)
	if .Flat in field.flags || type_is_integer(field.type) || type_is_enum(field.type) || type_is_bit_set(field.type) || type_is_boolean(field.type) {
		spv.decorate(&cg.m, v, .Flat)
	}
	if .Noperspective in field.flags {
		spv.decorate(&cg.m, v, .NoPerspective)
	}
	if .Centroid in field.flags {
		spv.decorate(&cg.m, v, .Centroid)
	}
	nm := fmt.tprintf("%s%s", prefix, field.name)
	spv.name(&cg.m, v, nm)
	spv_iface(cg, v)
	return v
}

spv_emit_entry_io :: proc(cg: ^Spv_CG, e: ^Entity, pt: ^Type_Proc) {
	_ = e
	used_data, used_indirect := spv_emit_push_constants(cg, pt)
	_ = used_data
	_ = used_indirect
	if pt.shared_vars != nil {
		for var in pt.shared_vars {
			pty := spv_ptr_ty(cg, .Workgroup, var.type)
			id := spv.global_var(&cg.m, pty, .Workgroup)
			spv.name(&cg.m, id, var.name)
			spv_bind_entity(cg, var, id, .Workgroup)
			spv_iface(cg, id)
		}
	}
	semantic: [Semantic]^Entity
	other: ^Entity
	in_loc := 0
	if cg.stage != .Compute {
		for param in pt.params.variables {
			if param.semantic != .None && param.semantic != .Custom {
				semantic[param.semantic] = param
			} else {
				other = param
				if st, ok := param.type.derived.(^Type_Struct); ok {
					for field in st.fields.variables {
						if field.semantic != .None && field.semantic != .Custom {
							semantic[field.semantic] = field
						} else {
							id := spv_io_var(cg, field, u32(in_loc), .Input, "_in_")
							spv_bind_entity(cg, field, id, .Input)
							in_loc += 1
						}
					}
				}
			}
		}
	} else {
		for param in pt.params.variables {
			if param.semantic != .None && param.semantic != .Custom {
				semantic[param.semantic] = param
			}
		}
	}
	out_loc := 0
	if cg.stage != .Compute && pt.results != nil {
		for result in pt.results.variables {
			if result.semantic != .None && result.semantic != .Custom {
				semantic[result.semantic] = result
				if result.semantic == .Target {
					id := spv_io_var(cg, result, u32(out_loc), .Output, "_out_")
					spv_bind_entity(cg, result, id, .Output)
					append(&cg.stage_outs, id)
					append(&cg.stage_out_ents, result)
					out_loc += 1
				} else if result.semantic == .Position && cg.stage == .Vertex {
					v4 := spv.type_vector(&cg.m, spv.type_f32(&cg.m), 4)
					id := spv_builtin_var(cg, .Position, v4, "gl_Position", .Output)
					spv_bind_entity(cg, result, id, .Output)
					append(&cg.stage_outs, id)
					append(&cg.stage_out_ents, result)
				}
			} else if st, ok := result.type.derived.(^Type_Struct); ok {
				for field in st.fields.variables {
					if field.semantic == .Position {
						semantic[.Position] = field
						if cg.stage == .Vertex {
							v4 := spv.type_vector(&cg.m, spv.type_f32(&cg.m), 4)
							id := spv_builtin_var(cg, .Position, v4, "gl_Position", .Output)
							spv_bind_entity(cg, field, id, .Output)
							append(&cg.stage_outs, id)
							append(&cg.stage_out_ents, field)
						}
					} else if field.semantic == .Target {
						id := spv_io_var(cg, field, u32(out_loc), .Output, "_out_")
						spv_bind_entity(cg, field, id, .Output)
						append(&cg.stage_outs, id)
						append(&cg.stage_out_ents, field)
						out_loc += 1
					} else if field.semantic != .None && field.semantic != .Custom {
						semantic[field.semantic] = field
					} else {
						id := spv_io_var(cg, field, u32(out_loc), .Output, "_out_")
						spv_bind_entity(cg, field, id, .Output)
						append(&cg.stage_outs, id)
						append(&cg.stage_out_ents, field)
						out_loc += 1
					}
				}
			}
		}
	}
	if pos := semantic[.Position]; pos != nil && cg.stage == .Fragment {
		v4 := spv.type_vector(&cg.m, spv.type_f32(&cg.m), 4)
		id := spv_builtin_var(cg, .FragCoord, v4, "gl_FragCoord", .Input)
		spv_bind_entity(cg, pos, id, .Input)
	}
	if vid := semantic[.Vertex_ID]; vid != nil {
		id := spv_builtin_var(cg, .VertexIndex, spv_type(cg, vid.type), "gl_VertexIndex")
		spv_bind_entity(cg, vid, id, .Input)
	}
	if iid := semantic[.Instance_ID]; iid != nil {
		id := spv_builtin_var(cg, .InstanceIndex, spv_type(cg, iid.type), "gl_InstanceIndex")
		spv_bind_entity(cg, iid, id, .Input)
	}
	uvec3 := spv.type_vector(&cg.m, spv.type_u32(&cg.m), 3)
	if g := semantic[.Global_Thread]; g != nil {
		id := spv_builtin_var(cg, .GlobalInvocationId, uvec3, "gl_GlobalInvocationID")
		spv_bind_entity(cg, g, id, .Input)
	}
	if g := semantic[.Group_Thread]; g != nil {
		id := spv_builtin_var(cg, .LocalInvocationId, uvec3, "gl_LocalInvocationID")
		spv_bind_entity(cg, g, id, .Input)
	}
	if g := semantic[.Group]; g != nil {
		id := spv_builtin_var(cg, .WorkgroupId, uvec3, "gl_WorkGroupID")
		spv_bind_entity(cg, g, id, .Input)
	}
	if g := semantic[.Group_Index]; g != nil {
		id := spv_builtin_var(cg, .LocalInvocationIndex, spv.type_u32(&cg.m), "gl_LocalInvocationIndex")
		spv_bind_entity(cg, g, id, .Input)
	}
	if g := semantic[.Num_Groups]; g != nil {
		id := spv_builtin_var(cg, .NumWorkgroups, uvec3, "gl_NumWorkGroups")
		spv_bind_entity(cg, g, id, .Input)
	}
	cg.curr_entity = e
	_ = other
	_ = semantic
}

spv_pc_load_member :: proc(cg: ^Spv_CG, member: u32, ty: spv.Id) -> spv.Id {
	pty := spv.type_pointer(&cg.m, .PushConstant, ty)
	idx := spv.const_u32(&cg.m, member)
	ch := spv.access_chain(&cg.m, pty, cg.pc_var, {idx})
	return spv.load(&cg.m, ty, ch)
}

spv_emit_entry_prolog :: proc(cg: ^Spv_CG, e: ^Entity, pt: ^Type_Proc) {
	semantic: [Semantic]^Entity
	other: ^Entity
	for param in pt.params.variables {
		if param.semantic != .None && param.semantic != .Custom {
			semantic[param.semantic] = param
		} else if cg.stage != .Compute {
			other = param
		}
	}
	if other != nil {
		loc := spv_fn_var(cg, other.type, other.name, pos = other.pos)
		spv_bind_entity(cg, other, loc, .Function)
		if st, ok := other.type.derived.(^Type_Struct); ok {
			parts := make([]spv.Id, len(st.fields.variables), context.temp_allocator)
			for field, i in st.fields.variables {
				if field.semantic == .Position && cg.stage == .Fragment {
					src := cg.entity_ptr[field]
					parts[i] = spv.load(&cg.m, spv_type(cg, field.type), src)
				} else if src, sok := cg.entity_ptr[field]; sok {
					parts[i] = spv.load(&cg.m, spv_type(cg, field.type), src)
				} else {
					parts[i] = spv_zero(cg, field.type)
				}
			}
			spv.store(&cg.m, loc, spv.composite_construct(&cg.m, spv_type(cg, other.type), parts))
		}
	}
	if v := semantic[.Vertex_ID]; v != nil {
		src := cg.entity_ptr[v]
		loc := spv_fn_var(cg, v.type, v.name, pos = v.pos)
		spv.store(&cg.m, loc, spv.load(&cg.m, spv_type(cg, v.type), src))
		spv_bind_entity(cg, v, loc, .Function)
	}
	if v := semantic[.Instance_ID]; v != nil {
		src := cg.entity_ptr[v]
		loc := spv_fn_var(cg, v.type, v.name, pos = v.pos)
		spv.store(&cg.m, loc, spv.load(&cg.m, spv_type(cg, v.type), src))
		spv_bind_entity(cg, v, loc, .Function)
	}
	if v := semantic[.Data]; v != nil {
		member: u32 = 0
		if cg.stage == .Fragment {
			member = 1
		}
		val := spv_pc_load_member(cg, member, spv_type(cg, v.type, .Stored))
		loc := spv_fn_var(cg, v.type, v.name, pos = v.pos)
		spv.store(&cg.m, loc, val)
		spv_bind_entity(cg, v, loc, .Function)
	}
	if v := semantic[.Indirect_Data]; v != nil {
		pointee := type_pointer_elem(v.type)
		if pointee == nil {
			pointee = v.type
		}
		wrap := spv_type(cg, v.type, .Stored)
		ptr_val := spv_pc_load_member(cg, 2 if cg.stage != .Compute else 0, wrap)
		idx := spv.const_u32(&cg.m, 0)
		if cg.stage == .Vertex {
			draw := spv_builtin_var(cg, .DrawIndex, spv.type_u32(&cg.m), "gl_DrawID")
			idx = spv.load(&cg.m, spv.type_u32(&cg.m), draw)
		}
		loaded := spv_psb_index(cg, ptr_val, pointee, idx)
		loc := spv_fn_var(cg, pointee, v.name, pos = v.pos)
		spv.store(&cg.m, loc, loaded)
		spv_bind_entity(cg, v, loc, .Function)
	}
	compute_sems := [5]Semantic{.Global_Thread, .Group_Thread, .Group, .Group_Index, .Num_Groups}
	for sem in compute_sems {
		v := semantic[sem]
		if v == nil do continue
		src := cg.entity_ptr[v]
		val := spv.load(&cg.m, spv_type(cg, v.type), src)
		loc := spv_fn_var(cg, v.type, v.name, pos = v.pos)
		spv.store(&cg.m, loc, val)
		spv_bind_entity(cg, v, loc, .Function)
	}
	if v := semantic[.Group_Size]; v != nil {
		x := spv.const_u32(&cg.m, u32(pt.local_size[0]))
		y := spv.const_u32(&cg.m, u32(pt.local_size[1]))
		z := spv.const_u32(&cg.m, u32(pt.local_size[2]))
		uvec3 := spv.type_vector(&cg.m, spv.type_u32(&cg.m), 3)
		val := spv.composite_construct(&cg.m, uvec3, {x, y, z})
		loc := spv_fn_var(cg, v.type, v.name)
		spv.store(&cg.m, loc, val)
		spv_bind_entity(cg, v, loc, .Function)
	}
	if pt.results != nil && cg.stage != .Compute {
		for result in pt.results.variables {
			if result.semantic == .Target || result.semantic == .Position {
				continue
			}
			loc := spv_fn_var(cg, result.type, result.name if result.name != "" else "_ret")
			spv_bind_entity(cg, result, loc, .Function)
			spv.store(&cg.m, loc, spv_zero(cg, result.type))
		}
	}
	_ = e
}

spv_unpack_stage_result :: proc(cg: ^Spv_CG, result: ^Entity) {
	if result == nil {
		return
	}
	if result.semantic == .Target || result.semantic == .Position {
		if dst, ok := cg.entity_ptr[result]; ok {
			if src, sok := cg.entity_ptr[result]; sok {
				_ = dst
				_ = src
			}
		}
		return
	}
	src_ptr, ok := cg.entity_ptr[result]
	if !ok {
		return
	}
	if st, is_st := result.type.derived.(^Type_Struct); is_st {
		agg := spv.load(&cg.m, spv_type(cg, result.type), src_ptr)
		for field, i in st.fields.variables {
			dst, dok := cg.entity_ptr[field]
			if !dok do continue
			part := spv.composite_extract(&cg.m, spv_type(cg, field.type), agg, u32(i))
			spv.store(&cg.m, dst, part)
		}
		return
	}
}

spv_emit_assert_types :: proc(cg: ^Spv_CG) {
	u32_t := spv.type_u32(&cg.m)
	i64_t := spv.type_i64(&cg.m)
	u8_t := spv.type_u8(&cg.m)
	n256 := spv.const_u32(&cg.m, 256)
	arr := spv.type_array(&cg.m, u8_t, n256)
	spv.decorate(&cg.m, arr, .ArrayStride, 1)
	members := []spv.Id{u32_t, u32_t, u32_t, u32_t, u32_t, u32_t, u32_t, i64_t, i64_t, arr, arr}
	block := spv.type_struct(&cg.m, members, "assert_rec")
	spv.decorate(&cg.m, block, .Block)
	offs := []u32{0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 304}
	names := []string{"fired", "overflow", "kind", "line", "column", "path_len", "msg_len", "index", "length", "path", "message"}
	for name, i in names {
		spv.member_name(&cg.m, block, u32(i), name)
		spv.member_decorate(&cg.m, block, u32(i), .Offset, offs[i])
	}
	cg.assert_block = block
	cg.assert_ptr_ty = spv.type_pointer(&cg.m, .PhysicalStorageBuffer, block)
	cg.assert_spec = spv.spec_const_int(&cg.m, spv.type_u64(&cg.m), 0, 64)
	spv.decorate(&cg.m, cg.assert_spec, .SpecId, cg.assert_buffer_spec_id)
	spv.name(&cg.m, cg.assert_spec, "_misl_assert_addr")
}

spv_assert_rec_ptr :: proc(cg: ^Spv_CG) -> spv.Id {
	return spv.convert_u_to_ptr(&cg.m, cg.assert_ptr_ty, cg.assert_spec)
}

spv_assert_member_ptr :: proc(cg: ^Spv_CG, rec: spv.Id, member: u32, elem_ty: spv.Id) -> spv.Id {
	pty := spv.type_pointer(&cg.m, .PhysicalStorageBuffer, elem_ty)
	idx := spv.const_u32(&cg.m, member)
	return spv.access_chain(&cg.m, pty, rec, {idx})
}

spv_assert_try_claim :: proc(cg: ^Spv_CG) -> spv.Id {
	tmp := spv_fn_var(cg, t_b32, "_claim")
	zero64 := spv.const_u64(&cg.m, 0)
	nz := spv.inot_equal(&cg.m, cg.assert_spec, zero64)
	then_b := spv.block_new(&cg.m)
	else_b := spv.block_new(&cg.m)
	merge := spv.block_new(&cg.m)
	spv.selection_merge(&cg.m, merge)
	spv.branch_cond(&cg.m, nz, then_b, else_b)
	spv_block(cg, else_b)
	spv.store(&cg.m, tmp, spv_from_bool(cg, spv.const_bool(&cg.m, false), t_b32))
	spv.branch(&cg.m, merge)
	spv_block(cg, then_b)
	rec := spv_assert_rec_ptr(cg)
	fired_p := spv_assert_member_ptr(cg, rec, 0, spv.type_u32(&cg.m))
	scope := spv.const_u32(&cg.m, u32(spv.Scope.Device))
	eq_sem := spv.const_u32(&cg.m, u32(spv.Memory_Semantics.AcquireRelease) | u32(spv.Memory_Semantics.UniformMemory))
	uneq_sem := spv.const_u32(&cg.m, u32(spv.Memory_Semantics.Acquire) | u32(spv.Memory_Semantics.UniformMemory))
	one := spv.const_u32(&cg.m, 1)
	zero := spv.const_u32(&cg.m, 0)
	prev := spv.atomic_compare_exchange(&cg.m, spv.type_u32(&cg.m), fired_p, scope, eq_sem, uneq_sem, one, zero)
	taken := spv.iequal(&cg.m, prev, zero)
	ok_b := spv.block_new(&cg.m)
	fail_b := spv.block_new(&cg.m)
	inner := spv.block_new(&cg.m)
	spv.selection_merge(&cg.m, inner)
	spv.branch_cond(&cg.m, taken, ok_b, fail_b)
	spv_block(cg, fail_b)
	ov_p := spv_assert_member_ptr(cg, rec, 1, spv.type_u32(&cg.m))
	_ = spv.atomic_iadd(&cg.m, spv.type_u32(&cg.m), ov_p, scope, eq_sem, one)
	spv.store(&cg.m, tmp, spv_from_bool(cg, spv.const_bool(&cg.m, false), t_b32))
	spv.branch(&cg.m, inner)
	spv_block(cg, ok_b)
	spv.store(&cg.m, tmp, spv_from_bool(cg, spv.const_bool(&cg.m, true), t_b32))
	spv.branch(&cg.m, inner)
	spv_block(cg, inner)
	spv.branch(&cg.m, merge)
	spv_block(cg, merge)
	return spv_as_bool(cg, spv.load(&cg.m, spv_type(cg, t_b32), tmp), t_b32)
}

spv_store_u8_bytes :: proc(cg: ^Spv_CG, rec: spv.Id, member: u32, data: string, len_member: u32) {
	n := min(len(data), 256)
	len_p := spv_assert_member_ptr(cg, rec, len_member, spv.type_u32(&cg.m))
	spv.store_aligned(&cg.m, len_p, spv.const_u32(&cg.m, u32(n)), 4)
	arr_ty := spv.type_array(&cg.m, spv.type_u8(&cg.m), spv.const_u32(&cg.m, 256))
	base := spv_assert_member_ptr(cg, rec, member, arr_ty)
	elem_p := spv.type_pointer(&cg.m, .PhysicalStorageBuffer, spv.type_u8(&cg.m))
	for i in 0 ..< n {
		ch := spv.access_chain(&cg.m, elem_p, base, {spv.const_u32(&cg.m, u32(i))})
		spv.store_aligned(&cg.m, ch, spv.const_int(&cg.m, spv.type_u8(&cg.m), u64(data[i]), 8), 1)
	}
}

spv_assert_record :: proc(cg: ^Spv_CG, pos: Token_Pos, kind: u32, index, length: spv.Id, message: string) {
	if !cg.needs_assert {
		return
	}
	claimed := spv_assert_try_claim(cg)
	then_b := spv.block_new(&cg.m)
	merge := spv.block_new(&cg.m)
	spv.selection_merge(&cg.m, merge)
	spv.branch_cond(&cg.m, claimed, then_b, merge)
	spv_block(cg, then_b)
	rec := spv_assert_rec_ptr(cg)
	store_u32 :: proc(cg: ^Spv_CG, rec: spv.Id, member: u32, v: spv.Id) {
		p := spv_assert_member_ptr(cg, rec, member, spv.type_u32(&cg.m))
		spv.store_aligned(&cg.m, p, v, 4)
	}
	store_u32(cg, rec, 2, spv.const_u32(&cg.m, kind))
	store_u32(cg, rec, 3, spv.const_u32(&cg.m, u32(pos.line if pos.line > 0 else 0)))
	store_u32(cg, rec, 4, spv.const_u32(&cg.m, u32(pos.column if pos.column > 0 else 0)))
	idx_p := spv_assert_member_ptr(cg, rec, 7, spv.type_i64(&cg.m))
	spv.store_aligned(&cg.m, idx_p, index, 8)
	len_p := spv_assert_member_ptr(cg, rec, 8, spv.type_i64(&cg.m))
	spv.store_aligned(&cg.m, len_p, length, 8)
	path := ""
	if cg.curr_entity != nil && cg.curr_entity.module != nil {
		path = cg.curr_entity.module.fullpath
	} else if cg.module != nil {
		path = cg.module.fullpath
	}
	spv_store_u8_bytes(cg, rec, 9, path, 5)
	spv_store_u8_bytes(cg, rec, 10, message, 6)
	spv.branch(&cg.m, merge)
	spv_block(cg, merge)
}

spv_assert_or_panic :: proc(cg: ^Spv_CG, call: ^Call_Expr, id: Builtin_Proc) {
	if id == .assert {
		if len(call.args) == 0 do return
		if cg.disable_asserts {
			_ = spv_rvalue(cg, call.args[0])
			return
		}
		msg := ""
		if len(call.args) >= 2 {
			msg, _ = call_const_string_arg(call.args[1])
		}
		cond := spv_as_bool(cg, spv_rvalue(cg, call.args[0]), call.args[0].tav.type)
		fail := spv.logical_not(&cg.m, cond)
		then_b := spv.block_new(&cg.m)
		merge := spv.block_new(&cg.m)
		spv.selection_merge(&cg.m, merge)
		spv.branch_cond(&cg.m, fail, then_b, merge)
		spv_block(cg, then_b)
		spv_assert_record(cg, call.pos, SPV_ASSERT_KIND_USER, spv.const_i64(&cg.m, 0), spv.const_i64(&cg.m, 0), msg)
		spv.branch_if_open(&cg.m, merge)
		spv_block(cg, merge)
		return
	}
	if cg.disable_asserts {
		return
	}
	msg := ""
	if len(call.args) >= 1 {
		msg, _ = call_const_string_arg(call.args[0])
	}
	spv_assert_record(cg, call.pos, SPV_ASSERT_KIND_PANIC, spv.const_i64(&cg.m, 0), spv.const_i64(&cg.m, 0), msg)
}

spv_emit_slice_bounds :: proc(cg: ^Spv_CG, index_expr: ^Expr, idx_u32, len_i64: spv.Id) {
	if !cg.bounds_check || cg.disable_asserts {
		return
	}
	idx := spv.sconvert(&cg.m, spv.type_i64(&cg.m), idx_u32)
	neg := spv.sless_than(&cg.m, idx, spv.const_i64(&cg.m, 0))
	hi := spv.sgreater_equal(&cg.m, idx, len_i64)
	bad := spv.logical_or(&cg.m, neg, hi)
	then_b := spv.block_new(&cg.m)
	merge := spv.block_new(&cg.m)
	spv.selection_merge(&cg.m, merge)
	spv.branch_cond(&cg.m, bad, then_b, merge)
	spv_block(cg, then_b)
	pos := index_expr.pos if index_expr != nil else Token_Pos{}
	spv_assert_record(cg, pos, SPV_ASSERT_KIND_SLICE_INDEX, idx, len_i64, "slice index out of range")
	spv.branch_if_open(&cg.m, merge)
	spv_block(cg, merge)
}

spv_printf :: proc(cg: ^Spv_CG, call: ^Call_Expr, append_nl: bool) {
	if len(call.args) < 1 {
		return
	}
	format, _ := call.args[0].tav.value.(string)
	arg_i := 1
	i := 0
	for i < len(format) {
		if format[i] != '%' {
			start := i
			for i < len(format) && format[i] != '%' {
				i += 1
			}
			spv_printf_lit(cg, format[start:i])
			continue
		}
		if i + 1 < len(format) && format[i + 1] == '%' {
			spv_printf_lit(cg, "%")
			i += 2
			continue
		}
		pretty := false
		if i + 1 < len(format) && format[i + 1] == '#' {
			pretty = true
			i += 1
		}
		if i + 1 >= len(format) || format[i + 1] != 'v' {
			i += 1
			continue
		}
		i += 2
		if arg_i >= len(call.args) {
			continue
		}
		spv_printf_value(cg, call.args[arg_i], pretty, 0)
		arg_i += 1
	}
	if append_nl {
		spv_printf_lit(cg, "\n")
	}
}

spv_printf_lit :: proc(cg: ^Spv_CG, s: string) {
	if s == "" {
		return
	}
	sid := spv.op_string(&cg.m, s)
	spv.debug_printf(&cg.m, sid, {})
}

spv_printf_fmt :: proc(cg: ^Spv_CG, spec: string, v: spv.Id) {
	sid := spv.op_string(&cg.m, spec)
	spv.debug_printf(&cg.m, sid, {v})
}

spv_printf_value :: proc(cg: ^Spv_CG, expr: ^Expr, pretty: bool, indent: int) {
	t := default_type(expr.tav.type)
	v := spv_rvalue(cg, expr)
	spv_printf_typed(cg, t, v, pretty, indent)
}

spv_printf_typed :: proc(cg: ^Spv_CG, t: ^Type, v: spv.Id, pretty: bool, indent: int) {
	t := default_type(t)
	if spec, vv, ok := spv_printf_scalar(cg, t, v); ok {
		spv_printf_fmt(cg, spec, vv)
		return
	}
	if type_is_enum(t) {
		et := t.derived.(^Type_Enum)
		spv_printf_enum(cg, et, v)
		return
	}
	if type_is_bit_set(t) {
		bs := t.derived.(^Type_Bit_Set)
		spv_printf_bit_set(cg, bs, v, pretty, indent)
		return
	}
	if type_is_vector(t) {
		vt := t.derived.(^Type_Vector)
		spv_printf_lit(cg, "{")
		for i in 0 ..< vt.len {
			if i > 0 {
				spv_printf_lit(cg, ", ")
			}
			comp := spv.composite_extract(&cg.m, spv_type(cg, vt.elem), v, u32(i))
			spv_printf_typed(cg, vt.elem, comp, pretty, indent)
		}
		spv_printf_lit(cg, "}")
		return
	}
	if st, ok := t.derived.(^Type_Struct); ok && st.fields != nil {
		spv_printf_lit(cg, "{")
		for field, i in st.fields.variables {
			if i > 0 {
				spv_printf_lit(cg, ", ")
			}
			spv_printf_lit(cg, fmt.tprintf("%s = ", field.name))
			part := spv.composite_extract(&cg.m, spv_type(cg, field.type), v, u32(i))
			spv_printf_typed(cg, field.type, part, pretty, indent + 1)
		}
		spv_printf_lit(cg, "}")
		return
	}
	if type_is_pointer(t) || type_is_multi_pointer(t) {
		u := spv.convert_ptr_to_u(&cg.m, spv.type_u64(&cg.m), v)
		spv_printf_fmt(cg, "%lu", u)
		return
	}
	if type_is_slice(t) {
		st := t.derived.(^Type_Slice)
		rw := spv_elem_needs_rw(cg, st.elem, nil)
		ptr_ty := spv_psb_ptr(cg, st.elem, rw).ptr_ty
		data := spv.composite_extract(&cg.m, ptr_ty, v, 0)
		ln := spv.composite_extract(&cg.m, spv.type_i64(&cg.m), v, 1)
		spv_printf_lit(cg, "{data = ")
		spv_printf_typed(cg, new_type_dummy_ptr(st.elem), data, pretty, indent)
		spv_printf_lit(cg, ", len = ")
		spv_printf_fmt(cg, "%lu", spv.bitcast(&cg.m, spv.type_u64(&cg.m), ln))
		spv_printf_lit(cg, "}")
		return
	}
	spv_printf_lit(cg, "<unsupported>")
}

new_type_dummy_ptr :: proc(elem: ^Type) -> ^Type {
	p := new_type(Type_Pointer)
	p.elem = elem
	return p
}

spv_printf_scalar :: proc(cg: ^Spv_CG, t: ^Type, v: spv.Id) -> (spec: string, out: spv.Id, ok: bool) {
	t := default_type(t)
	if type_eq(t, t_f32) {
		return "%f", v, true
	}
	if type_eq(t, t_f64) {
		return "%f", spv.fconvert(&cg.m, spv.type_f32(&cg.m), v), true
	}
	if type_eq(t, t_i32) {
		return "%d", v, true
	}
	if type_eq(t, t_u32) || type_eq(t, t_b32) {
		return "%u", v, true
	}
	if type_eq(t, t_i8) || type_eq(t, t_i16) {
		return "%d", spv.sconvert(&cg.m, spv.type_i32(&cg.m), v), true
	}
	if type_eq(t, t_u8) || type_eq(t, t_u16) || type_eq(t, t_b8) || type_eq(t, t_b16) {
		return "%u", spv.uconvert(&cg.m, spv.type_u32(&cg.m), v), true
	}
	if type_eq(t, t_i64) {
		return "%lu", spv.bitcast(&cg.m, spv.type_u64(&cg.m), v), true
	}
	if type_eq(t, t_u64) || type_eq(t, t_b64) {
		return "%lu", v, true
	}
	s, sok := t.derived.(^Type_Scalar)
	if sok && .Integer in s.flags && .Unsigned in s.flags {
		if s.size <= 4 {
			return "%u", spv_u32(cg, v, t), true
		}
		return "%lu", v, true
	}
	return "", v, false
}

spv_printf_enum :: proc(cg: ^Spv_CG, et: ^Type_Enum, v: spv.Id) {
	done := spv_fn_var(cg, t_b32, "_pf_e")
	spv.store(&cg.m, done, spv_from_bool(cg, spv.const_bool(&cg.m, false), t_b32))
	seen := make(map[i128]bool, context.temp_allocator)
	for field in et.fields {
		val := exact_value_to_i128(field.value)
		if val in seen do continue
		seen[val] = true
		cv := spv_const_value(cg, et.base_type, field.value)
		eq := spv.iequal(&cg.m, v, cv)
		already := spv_as_bool(cg, spv.load(&cg.m, spv_type(cg, t_b32), done), t_b32)
		take := spv.logical_and(&cg.m, spv.logical_not(&cg.m, already), eq)
		then_b := spv.block_new(&cg.m)
		else_b := spv.block_new(&cg.m)
		spv.selection_merge(&cg.m, else_b)
		spv.branch_cond(&cg.m, take, then_b, else_b)
		spv_block(cg, then_b)
		spv.store(&cg.m, done, spv_from_bool(cg, spv.const_bool(&cg.m, true), t_b32))
		spv_printf_lit(cg, fmt.tprintf(".%s", field.name))
		spv.branch_if_open(&cg.m, else_b)
		spv_block(cg, else_b)
	}
	inv := spv.logical_not(&cg.m, spv_as_bool(cg, spv.load(&cg.m, spv_type(cg, t_b32), done), t_b32))
	then_b := spv.block_new(&cg.m)
	merge := spv.block_new(&cg.m)
	spv.selection_merge(&cg.m, merge)
	spv.branch_cond(&cg.m, inv, then_b, merge)
	spv_block(cg, then_b)
	spv_printf_lit(cg, "INVALID_ENUM")
	spv.branch_if_open(&cg.m, merge)
	spv_block(cg, merge)
}

spv_printf_bit_set :: proc(cg: ^Spv_CG, bs: ^Type_Bit_Set, v: spv.Id, pretty: bool, indent: int) {
	spv_printf_lit(cg, "{" if !pretty else fmt.tprintf("{{\n%s", printf_indent(indent + 1)))
	enum_t, ok := bs.elem.derived.(^Type_Enum)
	if !ok {
		spv_printf_lit(cg, "}")
		return
	}
	first := spv_fn_var(cg, t_u32, "_pf_first")
	spv.store(&cg.m, first, spv.const_u32(&cg.m, 1))
	seen := make(map[i128]bool, context.temp_allocator)
	for field in enum_t.fields {
		bit := exact_value_to_i128(field.value)
		if bit in seen do continue
		seen[bit] = true
		one := spv_const_value(cg, bs.underlying, exact_int(1))
		sh := spv.shift_left(&cg.m, spv_type(cg, bs.underlying), one, spv_const_value(cg, bs.underlying, exact_int(bit)))
		masked := spv.bitwise_and(&cg.m, spv_type(cg, bs.underlying), v, sh)
		z := spv_zero(cg, bs.underlying)
		hit := spv.inot_equal(&cg.m, masked, z)
		then_b := spv.block_new(&cg.m)
		merge := spv.block_new(&cg.m)
		spv.selection_merge(&cg.m, merge)
		spv.branch_cond(&cg.m, hit, then_b, merge)
		spv_block(cg, then_b)
		is_first := spv.iequal(&cg.m, spv.load(&cg.m, spv.type_u32(&cg.m), first), spv.const_u32(&cg.m, 1))
		sep_t := spv.block_new(&cg.m)
		sep_e := spv.block_new(&cg.m)
		sep_m := spv.block_new(&cg.m)
		spv.selection_merge(&cg.m, sep_m)
		spv.branch_cond(&cg.m, is_first, sep_t, sep_e)
		spv_block(cg, sep_t)
		spv.store(&cg.m, first, spv.const_u32(&cg.m, 0))
		spv.branch(&cg.m, sep_m)
		spv_block(cg, sep_e)
		if pretty {
			spv_printf_lit(cg, fmt.tprintf(",\n%s", printf_indent(indent + 1)))
		} else {
			spv_printf_lit(cg, ", ")
		}
		spv.branch(&cg.m, sep_m)
		spv_block(cg, sep_m)
		spv_printf_lit(cg, fmt.tprintf(".%s", field.name))
		spv.branch(&cg.m, merge)
		spv_block(cg, merge)
	}
	if pretty {
		spv_printf_lit(cg, fmt.tprintf("\n%s}}", printf_indent(indent)))
	} else {
		spv_printf_lit(cg, "}")
	}
}

spv_ray_query_ptr :: proc(cg: ^Spv_CG, expr: ^Expr) -> spv.Id {
	return spv_lval(cg, expr).ptr
}

spv_ray_query_init :: proc(cg: ^Spv_CG, dest: spv.Id, call: ^Call_Expr) {
	if call == nil || len(call.args) < 2 {
		spv_err(cg, call.pos if call != nil else {}, "codegen_spirv: rayquery_init")
		return
	}
	desc := spv_rvalue(cg, call.args[0])
	desc_t := default_type(call.args[0].tav.type)
	st, _ := desc_t.derived.(^Type_Struct)
	field :: proc(cg: ^Spv_CG, st: ^Type_Struct, agg: spv.Id, name: string) -> spv.Id {
		idx := spv_field_index_name(st, name)
		ft := st.fields.variables[idx].type
		return spv.composite_extract(&cg.m, spv_type(cg, ft), agg, u32(idx))
	}
	flags := spv_u32(cg, field(cg, st, desc, "flags"), st.fields.variables[spv_field_index_name(st, "flags")].type)
	cull := spv_u32(cg, field(cg, st, desc, "cull_mask"), st.fields.variables[spv_field_index_name(st, "cull_mask")].type)
	origin := field(cg, st, desc, "origin")
	tmin := field(cg, st, desc, "t_min")
	dir := field(cg, st, desc, "dir")
	tmax := field(cg, st, desc, "t_max")
	bvh_i := spv_handle_u32(cg, call.args[1])
	as_ty := spv.type_acceleration_structure(&cg.m)
	accel := spv_nu_load(cg, as_ty, cg.bindless.bvh, bvh_i)
	spv.ray_query_initialize(&cg.m, dest, accel, flags, cull, origin, tmin, dir, tmax)
}

spv_ray_query_hit :: proc(cg: ^Spv_CG, call: ^Call_Expr, committed: bool) -> spv.Id {
	rq := spv_ray_query_ptr(cg, call.args[0])
	c := spv.const_u32(&cg.m, 1 if committed else 0)
	hit_t := default_type(call.tav.type)
	st, _ := hit_t.derived.(^Type_Struct)
	n := len(st.fields.variables) if st != nil && st.fields != nil else 0
	parts := make([]spv.Id, n, context.temp_allocator)
	for field, i in st.fields.variables {
		switch field.name {
		case "kind":
			parts[i] = spv.ray_query_get_intersection_type(&cg.m, rq, c)
		case "t":
			parts[i] = spv.ray_query_get_intersection_t(&cg.m, rq, c)
		case "instance_idx":
			id := spv.ray_query_get_intersection_instance_id(&cg.m, rq, c)
			parts[i] = spv.bitcast(&cg.m, spv.type_u32(&cg.m), id)
		case "primitive_idx":
			id := spv.ray_query_get_intersection_primitive(&cg.m, rq, c)
			parts[i] = spv.bitcast(&cg.m, spv.type_u32(&cg.m), id)
		case "barycentrics":
			parts[i] = spv.ray_query_get_intersection_barycentrics(&cg.m, rq, c)
		case "front_face":
			b := spv.ray_query_get_intersection_front_face(&cg.m, rq, c)
			parts[i] = spv_from_bool(cg, b, field.type)
		case "object_to_world":
			parts[i] = spv.ray_query_get_object_to_world(&cg.m, spv_type(cg, field.type), rq, c)
		case "world_to_object":
			parts[i] = spv.ray_query_get_world_to_object(&cg.m, spv_type(cg, field.type), rq, c)
		case:
			parts[i] = spv_zero(cg, field.type)
		}
	}
	return spv.composite_construct(&cg.m, spv_type(cg, hit_t), parts)
}

spv_fmag_exec_call :: proc(cg: ^Spv_CG, call: ^Call_Expr, dest_ptrs: []spv.Id, dest_types: []^Type) {
	if call == nil || len(call.args) < 1 {
		spv_err(cg, {}, "codegen_spirv: fmag.exec missing bytecode")
		return
	}
	if cg.fmag_r == spv.NONE {
		spv_err(cg, call.pos, "codegen_spirv: fmag.exec register file was not hoisted")
		return
	}
	exec_e := entity_from_expr(call.expr)
	run := fmag_run_entity(exec_e)
	if run == nil {
		spv_err(cg, call.pos, "codegen_spirv: fmag.run is not available")
		return
	}
	fn_id, fok := cg.fn_id[run]
	if !fok {
		spv_err(cg, call.pos, "codegen_spirv: fmag.run was not emitted")
		return
	}
	slot := 0
	elem_ty := spv.type_f32(&cg.m)
	arr_ptr_ty := spv.type_pointer(&cg.m, .Function, elem_ty)
	for i in 1 ..< len(call.args) {
		arg := call.args[i]
		width := fmag_exec_width(arg.tav.type)
		val := spv_rvalue(cg, arg)
		if width <= 1 {
			ch := spv.access_chain(&cg.m, arr_ptr_ty, cg.fmag_r, {spv.const_u32(&cg.m, u32(slot))})
			spv.store(&cg.m, ch, val)
		} else {
			for c in 0 ..< width {
				comp := spv.composite_extract(&cg.m, elem_ty, val, u32(c))
				ch := spv.access_chain(&cg.m, arr_ptr_ty, cg.fmag_r, {spv.const_u32(&cg.m, u32(slot + c))})
				spv.store(&cg.m, ch, comp)
			}
		}
		slot += width
	}
	code := spv_rvalue(cg, call.args[0])
	_ = spv.call(&cg.m, spv.type_void(&cg.m), fn_id, {code, cg.fmag_r})
	slot = 0
	n := min(len(dest_ptrs), len(dest_types))
	for i in 0 ..< n {
		if dest_ptrs[i] == spv.NONE || dest_types[i] == nil {
			continue
		}
		width := fmag_exec_width(dest_types[i])
		if width <= 0 {
			continue
		}
		if width == 1 {
			ch := spv.access_chain(&cg.m, arr_ptr_ty, cg.fmag_r, {spv.const_u32(&cg.m, u32(slot))})
			spv.store(&cg.m, dest_ptrs[i], spv.load(&cg.m, elem_ty, ch))
		} else {
			parts := make([]spv.Id, width, context.temp_allocator)
			for c in 0 ..< width {
				ch := spv.access_chain(&cg.m, arr_ptr_ty, cg.fmag_r, {spv.const_u32(&cg.m, u32(slot + c))})
				parts[c] = spv.load(&cg.m, elem_ty, ch)
			}
			spv.store(&cg.m, dest_ptrs[i], spv.composite_construct(&cg.m, spv_type(cg, dest_types[i]), parts))
		}
		slot += width
	}
}

spv_fmag_exec_value :: proc(cg: ^Spv_CG, call: ^Call_Expr) -> spv.Id {
	res_t := default_type(call.tav.type)
	tmp := spv_fn_var(cg, res_t, "_fmag_out")
	spv_fmag_exec_call(cg, call, {tmp}, {res_t})
	return spv.load(&cg.m, spv_type(cg, res_t), tmp)
}

spv_type_mentions_rt :: proc(type: ^Type) -> bool {
	if type == nil do return false
	if type_is_bvh_id(type) || type_is_ray_query(type) do return true
	#partial switch t in type.derived {
	case ^Type_Pointer: return spv_type_mentions_rt(t.elem)
	case ^Type_Multi_Pointer: return spv_type_mentions_rt(t.elem)
	case ^Type_Slice: return spv_type_mentions_rt(t.elem)
	case ^Type_Array: return spv_type_mentions_rt(t.elem)
	case ^Type_Struct:
		if t.fields != nil {
			for f in t.fields.variables {
				if f != nil && spv_type_mentions_rt(f.type) do return true
			}
		}
	case ^Type_Proc:
		if t.params != nil {
			for f in t.params.variables {
				if f != nil && spv_type_mentions_rt(f.type) do return true
			}
		}
		if t.results != nil {
			for f in t.results.variables {
				if f != nil && spv_type_mentions_rt(f.type) do return true
			}
		}
	}
	return false
}

spv_scan_expr_ray :: proc(expr: ^Expr) -> bool {
	if expr == nil do return false
	if spv_type_mentions_rt(expr.tav.type) do return true
	#partial switch v in expr.derived_expr {
	case ^Call_Expr:
		if spv_scan_expr_ray(v.expr) do return true
		for a in v.args {
			if spv_scan_expr_ray(a) do return true
		}
	case ^Selector_Expr: return spv_scan_expr_ray(v.expr) || spv_scan_expr_ray(v.field)
	case ^Index_Expr: return spv_scan_expr_ray(v.expr) || spv_scan_expr_ray(v.index)
	case ^Deref_Expr: return spv_scan_expr_ray(v.expr)
	case ^Paren_Expr: return spv_scan_expr_ray(v.expr)
	case ^Unary_Expr: return spv_scan_expr_ray(v.expr)
	case ^Auto_Cast: return spv_scan_expr_ray(v.expr)
	case ^Type_Cast: return spv_scan_expr_ray(v.expr)
	case ^Tag_Expr: return spv_scan_expr_ray(v.expr)
	case ^Binary_Expr: return spv_scan_expr_ray(v.left) || spv_scan_expr_ray(v.right)
	case ^Ternary_If_Expr: return spv_scan_expr_ray(v.cond) || spv_scan_expr_ray(v.x) || spv_scan_expr_ray(v.y)
	}
	return false
}

spv_scan_stmt_ray :: proc(stmt: ^Stmt) -> bool {
	if stmt == nil do return false
	#partial switch v in stmt.derived_stmt {
	case ^Expr_Stmt: return spv_scan_expr_ray(v.expr)
	case ^Assign_Stmt:
		for e in v.lhs { if spv_scan_expr_ray(e) do return true }
		for e in v.rhs { if spv_scan_expr_ray(e) do return true }
	case ^Value_Decl:
		for e in v.values { if spv_scan_expr_ray(e) do return true }
	case ^Block_Stmt:
		for s in v.stmts { if spv_scan_stmt_ray(s) do return true }
	case ^If_Stmt:
		if spv_scan_stmt_ray(v.init) || spv_scan_expr_ray(v.cond) || spv_scan_stmt_ray(v.body) do return true
		return spv_scan_stmt_ray(v.else_stmt)
	case ^For_Stmt:
		if spv_scan_stmt_ray(v.init) || spv_scan_expr_ray(v.cond) || spv_scan_stmt_ray(v.post) do return true
		return spv_scan_stmt_ray(v.body)
	case ^Range_Stmt: return spv_scan_expr_ray(v.expr) || spv_scan_stmt_ray(v.body)
	case ^Return_Stmt:
		for r in v.results { if spv_scan_expr_ray(r) do return true }
	case ^Switch_Stmt: return spv_scan_stmt_ray(v.init) || spv_scan_expr_ray(v.cond) || spv_scan_stmt_ray(v.body)
	case ^Case_Clause:
		for e in v.list { if spv_scan_expr_ray(e) do return true }
		for s in v.body { if spv_scan_stmt_ray(s) do return true }
	case ^When_Stmt: return spv_scan_stmt_ray(v.body) || spv_scan_stmt_ray(v.else_stmt)
	case ^Which_Stmt: return spv_scan_stmt_ray(v.body)
	}
	return false
}

spv_call_is_assert :: proc(expr: ^Expr) -> bool {
	call, is_call := unparen_expr(expr).derived.(^Call_Expr)
	if !is_call do return false
	callee := entity_from_expr(call.expr)
	if callee == nil || callee.kind != .Builtin do return false
	return callee.builtin_id == .assert || callee.builtin_id == .panic
}

spv_scan_expr_assert :: proc(expr: ^Expr, bounds_check, disable_asserts: bool) -> bool {
	if expr == nil do return false
	bounds_check := cg_bounds_from_flags(bounds_check, expr.state_flags)
	#partial switch v in expr.derived_expr {
	case ^Index_Expr:
		if spv_scan_expr_assert(v.expr, bounds_check, disable_asserts) do return true
		if spv_scan_expr_assert(v.index, bounds_check, disable_asserts) do return true
		if bounds_check && v.expr != nil && type_is_slice(v.expr.tav.type) do return true
	case ^Call_Expr:
		if !disable_asserts && spv_call_is_assert(expr) do return true
		if spv_scan_expr_assert(v.expr, bounds_check, disable_asserts) do return true
		for arg in v.args {
			if spv_scan_expr_assert(arg, bounds_check, disable_asserts) do return true
		}
	case ^Binary_Expr: return spv_scan_expr_assert(v.left, bounds_check, disable_asserts) || spv_scan_expr_assert(v.right, bounds_check, disable_asserts)
	case ^Unary_Expr: return spv_scan_expr_assert(v.expr, bounds_check, disable_asserts)
	case ^Paren_Expr: return spv_scan_expr_assert(v.expr, bounds_check, disable_asserts)
	case ^Deref_Expr: return spv_scan_expr_assert(v.expr, bounds_check, disable_asserts)
	case ^Type_Cast: return spv_scan_expr_assert(v.expr, bounds_check, disable_asserts)
	case ^Auto_Cast: return spv_scan_expr_assert(v.expr, bounds_check, disable_asserts)
	case ^Selector_Expr: return spv_scan_expr_assert(v.expr, bounds_check, disable_asserts) || spv_scan_expr_assert(v.field, bounds_check, disable_asserts)
	case ^Comp_Lit:
		for elem in v.elems {
			value := elem
			if fv, is_fv := elem.derived.(^Field_Value); is_fv {
				value = fv.value
			}
			if spv_scan_expr_assert(value, bounds_check, disable_asserts) do return true
		}
	case ^Ternary_If_Expr:
		return spv_scan_expr_assert(v.cond, bounds_check, disable_asserts) || spv_scan_expr_assert(v.x, bounds_check, disable_asserts) || spv_scan_expr_assert(v.y, bounds_check, disable_asserts)
	}
	return false
}

spv_scan_stmt_assert :: proc(stmt: ^Stmt, bounds_check, disable_asserts: bool) -> bool {
	if stmt == nil do return false
	bounds_check := cg_bounds_from_flags(bounds_check, stmt.state_flags)
	#partial switch v in stmt.derived_stmt {
	case ^Value_Decl:
		for value in v.values { if spv_scan_expr_assert(value, bounds_check, disable_asserts) do return true }
	case ^Assign_Stmt:
		for lhs in v.lhs { if spv_scan_expr_assert(lhs, bounds_check, disable_asserts) do return true }
		for rhs in v.rhs { if spv_scan_expr_assert(rhs, bounds_check, disable_asserts) do return true }
	case ^Expr_Stmt: return spv_scan_expr_assert(v.expr, bounds_check, disable_asserts)
	case ^Block_Stmt:
		for s in v.stmts { if spv_scan_stmt_assert(s, bounds_check, disable_asserts) do return true }
	case ^If_Stmt:
		if spv_scan_stmt_assert(v.init, bounds_check, disable_asserts) do return true
		if spv_scan_expr_assert(v.cond, bounds_check, disable_asserts) do return true
		if spv_scan_stmt_assert(v.body, bounds_check, disable_asserts) do return true
		return spv_scan_stmt_assert(v.else_stmt, bounds_check, disable_asserts)
	case ^When_Stmt: return spv_scan_stmt_assert(v.body, bounds_check, disable_asserts) || spv_scan_stmt_assert(v.else_stmt, bounds_check, disable_asserts)
	case ^Which_Stmt:
		if taken := which_taken_clause_from_tav(v); taken != nil {
			for s in taken.body { if spv_scan_stmt_assert(s, bounds_check, disable_asserts) do return true }
		}
	case ^For_Stmt:
		if spv_scan_stmt_assert(v.init, bounds_check, disable_asserts) do return true
		if spv_scan_expr_assert(v.cond, bounds_check, disable_asserts) do return true
		if spv_scan_stmt_assert(v.post, bounds_check, disable_asserts) do return true
		return spv_scan_stmt_assert(v.body, bounds_check, disable_asserts)
	case ^Range_Stmt: return spv_scan_expr_assert(v.expr, bounds_check, disable_asserts) || spv_scan_stmt_assert(v.body, bounds_check, disable_asserts)
	case ^Return_Stmt:
		for r in v.results { if spv_scan_expr_assert(r, bounds_check, disable_asserts) do return true }
	case ^Switch_Stmt: return spv_scan_stmt_assert(v.init, bounds_check, disable_asserts) || spv_scan_expr_assert(v.cond, bounds_check, disable_asserts) || spv_scan_stmt_assert(v.body, bounds_check, disable_asserts)
	case ^Case_Clause:
		for e in v.list { if spv_scan_expr_assert(e, bounds_check, disable_asserts) do return true }
		for s in v.body { if spv_scan_stmt_assert(s, bounds_check, disable_asserts) do return true }
	}
	return false
}

spv_dag_needs_ray_query :: proc(mods: []^Module) -> bool {
	for m in mods {
		if m == nil do continue
		for e in m.definitions {
			if e == nil do continue
			if spv_type_mentions_rt(e.type) do return true
			#partial switch e.kind {
			case .Procedure, .Entry:
				if e.proc_lit != nil && spv_scan_stmt_ray(e.proc_lit.body) {
					return true
				}
			}
		}
	}
	return false
}

spv_dag_needs_assert :: proc(mods: []^Module) -> bool {
	for m in mods {
		if m == nil do continue
		for e in m.definitions {
			if e == nil do continue
			#partial switch e.kind {
			case .Procedure, .Entry:
				if e.type != nil {
					if pt, ok := e.type.derived.(^Type_Proc); ok && proc_is_generic_template(pt) {
						continue
					}
				}
				if e.proc_lit == nil do continue
				bounds := !m.no_bounds_check
				disable := m.disable_asserts
				if spv_scan_stmt_assert(e.proc_lit.body, bounds, disable) {
					return true
				}
			}
		}
	}
	return false
}
