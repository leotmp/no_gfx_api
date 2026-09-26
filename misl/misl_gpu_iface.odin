package misl

import "core:fmt"

/*
	MISL ↔ GPU ABI mirror (pipeline / raster state).

	IMPORTANT: This file must stay in sync with `oge/gpu` (`gpu.odin`), especially:
	  - Topology, Sample_Count, Format
	  - Cull_Mode / Cull_Modes, Raster_Flag / Raster_Flags
	  - Color_Write_Mask, Blend_Factor, Blend_Op
	  - Blend_Mode, Blend_State, Color_Attachment_Desc
	  - Raster_Desc field names and meanings (MISL `targets` ↔ gpu `colors`)

	Do NOT import `oge/gpu` from misl, and do NOT import misl from gpu.
	When you change an enum/member/order/underlying type in gpu, update this file
	to match (same names, same declaration order, same intent).

	These Odin enums exist so host conversion (`gpu.Topology(cp.topology)`) and
	name-order asserts stay aligned with `oge/gpu`. MISL types live in
	`core/builtin.misl`; `bind_gpu_iface_types` looks them up per check.
	They are not linked to gpu at compile time — keep them duplicate-by-design.
*/

// --- Enums (mirror oge/gpu) -------------------------------------------------

GPU_Topology :: enum {
	Triangle_List,
	Triangle_Strip,
	Triangle_Fan,
}

GPU_Component :: enum {
	R, G, B, A,
}

GPU_Color_Write_Mask :: enum {
	All,
	None,
	Color,
	Alpha,
}

GPU_Cull_Mode :: enum {
	Front,
	Back,
}

GPU_Sample_Count :: enum {
	_1,
	_2,
	_4,
	_8,
	_16,
	_32,
	_64,
}

GPU_Format :: enum {
	None,

	r_u8,
	r_u8_scaled,
	r_u8_norm,
	r_u8_srgb,

	r_i8,
	r_i8_scaled,
	r_i8_norm,

	r_f16,

	rgb_u8,
	rgb_u8_scaled,
	rgb_u8_norm,
	rgb_u8_srgb,

	rgb_i8,
	rgb_i8_scaled,
	rgb_i8_norm,

	rgba_u8,
	rgba_u8_scaled,
	rgba_u8_norm,
	rgba_u8_srgb,

	rgba_i8,
	rgba_i8_scaled,
	rgba_i8_norm,

	depth_f32,
	stencil_u8,
	depth_f32_stencil_u8,
}

GPU_Raster_Flag :: enum {
	Alpha_To_Coverage,
	Dual_Source_Blending,
}

GPU_Blend_Op :: enum {
	Add,
	Sub,
	Rev_Sub,
	Min,
	Max,
}

GPU_Blend_Factor :: enum {
	Zero,
	One,

	Src_Color,
	One_Minus_Src_Color,

	Src_Alpha,
	One_Minus_Src_Alpha,

	Dst_Color,
	One_Minus_Dst_Color,

	Dst_Alpha,
	One_Minus_Dst_Alpha,

	Secondary_Src_Color,
	One_Minus_Secondary_Src_Color,

	Secondary_Src_Alpha,
	One_Minus_Secondary_Src_Alpha,
}

// --- Name tables (order must match enum ordinals above / in gpu) ------------

gpu_topology_names := []string{
	"Triangle_List",
	"Triangle_Strip",
	"Triangle_Fan",
}

gpu_color_write_mask_names := []string{
	"All",
	"None",
	"Color",
	"Alpha",
}

gpu_cull_mode_names := []string{
	"Front",
	"Back",
}

gpu_sample_count_names := []string{
	"_1",
	"_2",
	"_4",
	"_8",
	"_16",
	"_32",
	"_64",
}

gpu_format_names := []string{
	"None",
	"r_u8",
	"r_u8_scaled",
	"r_u8_norm",
	"r_u8_srgb",
	"r_i8",
	"r_i8_scaled",
	"r_i8_norm",
	"r_f16",
	"rgb_u8",
	"rgb_u8_scaled",
	"rgb_u8_norm",
	"rgb_u8_srgb",
	"rgb_i8",
	"rgb_i8_scaled",
	"rgb_i8_norm",
	"rgba_u8",
	"rgba_u8_scaled",
	"rgba_u8_norm",
	"rgba_u8_srgb",
	"rgba_i8",
	"rgba_i8_scaled",
	"rgba_i8_norm",
	"depth_f32",
	"stencil_u8",
	"depth_f32_stencil_u8",
}

gpu_raster_flag_names := []string{
	"Alpha_To_Coverage",
	"Dual_Source_Blending",
}

gpu_blend_op_names := []string{
	"Add",
	"Sub",
	"Rev_Sub",
	"Min",
	"Max",
}

gpu_blend_factor_names := []string{
	"Zero",
	"One",
	"Src_Color",
	"One_Minus_Src_Color",
	"Src_Alpha",
	"One_Minus_Src_Alpha",
	"Dst_Color",
	"One_Minus_Dst_Color",
	"Dst_Alpha",
	"One_Minus_Dst_Alpha",
	"Secondary_Src_Color",
	"One_Minus_Secondary_Src_Color",
	"Secondary_Src_Alpha",
	"One_Minus_Secondary_Src_Alpha",
}

Gpu_Iface_Types :: struct {
	Topology:              ^Type,
	Sample_Count:          ^Type,
	Format:                ^Type,
	Color_Write_Mask:      ^Type,
	Cull_Mode:             ^Type,
	Cull_Modes:            ^Type,
	Raster_Flag:           ^Type,
	Raster_Flags:          ^Type,
	Blend_Op:              ^Type,
	Blend_Factor:          ^Type,
	Blend_Mode:            ^Type,
	Blend_State:           ^Type,
	Color_Attachment_Desc: ^Type,
}

gpu_iface_lookup_type :: proc(c: ^Checker, name: string) -> ^Type {
	if c == nil do return t_invalid
	if c.builtin_instance != nil && c.builtin_instance.scope != nil {
		if e := scope_lookup(c.builtin_instance.scope, name); e != nil && e.type != nil {
			return e.type
		}
	}
	if c.module != nil && c.module.scope != nil {
		if e := scope_lookup(c.module.scope, name); e != nil && e.type != nil {
			return e.type
		}
	}
	return t_invalid
}

gpu_iface_assert_enum_names :: proc(t: ^Type, names: []string, label: string) {
	if t == nil || t == t_invalid {
		fmt.assertf(false, "gpu iface: missing MISL type '%s'", label)
		return
	}
	enum_t, ok := t.derived.(^Type_Enum)
	fmt.assertf(ok, "gpu iface: '%s' is not an enum", label)
	fmt.assertf(len(enum_t.fields) == len(names), "gpu iface: '%s' has %d members, expected %d (keep core/builtin.misl in sync with oge/gpu)", label, len(enum_t.fields), len(names))
	for f, i in enum_t.fields {
		fmt.assertf(f != nil && f.name == names[i], "gpu iface: '%s' member %d is '%s', expected '%s'", label, i, f.name if f != nil else "", names[i])
	}
}

// After `core:builtin` is checked, bind this instantiation's GPU types (not process globals).
bind_gpu_iface_types :: proc(c: ^Checker) {
	if c == nil do return
	assert(len(gpu_topology_names) == len(GPU_Topology))
	assert(len(gpu_color_write_mask_names) == len(GPU_Color_Write_Mask))
	assert(len(gpu_cull_mode_names) == len(GPU_Cull_Mode))
	assert(len(gpu_sample_count_names) == len(GPU_Sample_Count))
	assert(len(gpu_format_names) == len(GPU_Format))
	assert(len(gpu_raster_flag_names) == len(GPU_Raster_Flag))
	assert(len(gpu_blend_op_names) == len(GPU_Blend_Op))
	assert(len(gpu_blend_factor_names) == len(GPU_Blend_Factor))

	c.gpu.Topology = gpu_iface_lookup_type(c, "Topology")
	c.gpu.Sample_Count = gpu_iface_lookup_type(c, "Sample_Count")
	c.gpu.Format = gpu_iface_lookup_type(c, "Format")
	c.gpu.Color_Write_Mask = gpu_iface_lookup_type(c, "Color_Write_Mask")
	c.gpu.Cull_Mode = gpu_iface_lookup_type(c, "Cull_Mode")
	c.gpu.Cull_Modes = gpu_iface_lookup_type(c, "Cull_Modes")
	c.gpu.Raster_Flag = gpu_iface_lookup_type(c, "Raster_Flag")
	c.gpu.Raster_Flags = gpu_iface_lookup_type(c, "Raster_Flags")
	c.gpu.Blend_Op = gpu_iface_lookup_type(c, "Blend_Op")
	c.gpu.Blend_Factor = gpu_iface_lookup_type(c, "Blend_Factor")
	c.gpu.Blend_Mode = gpu_iface_lookup_type(c, "Blend_Mode")
	c.gpu.Blend_State = gpu_iface_lookup_type(c, "Blend_State")
	c.gpu.Color_Attachment_Desc = gpu_iface_lookup_type(c, "Color_Attachment_Desc")

	gpu_iface_assert_enum_names(c.gpu.Topology, gpu_topology_names, "Topology")
	gpu_iface_assert_enum_names(c.gpu.Sample_Count, gpu_sample_count_names, "Sample_Count")
	gpu_iface_assert_enum_names(c.gpu.Format, gpu_format_names, "Format")
	gpu_iface_assert_enum_names(c.gpu.Color_Write_Mask, gpu_color_write_mask_names, "Color_Write_Mask")
	gpu_iface_assert_enum_names(c.gpu.Cull_Mode, gpu_cull_mode_names, "Cull_Mode")
	gpu_iface_assert_enum_names(c.gpu.Raster_Flag, gpu_raster_flag_names, "Raster_Flag")
	gpu_iface_assert_enum_names(c.gpu.Blend_Op, gpu_blend_op_names, "Blend_Op")
	gpu_iface_assert_enum_names(c.gpu.Blend_Factor, gpu_blend_factor_names, "Blend_Factor")
}
