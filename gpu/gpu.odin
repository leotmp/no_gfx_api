
package gpu

import "core:slice"
import "base:runtime"

import sdl "vendor:sdl3"
import vk "vendor:vulkan"

// This API follows the ZII (Zero Is Initialization) principle. Initializing to 0
// will yield predictable and reasonable behavior in general.

// Handles
Handle :: rawptr
Texture_Handle :: distinct Handle
Command_Buffer :: distinct Handle
Semaphore :: distinct Handle
Shader :: distinct Handle
BVH :: struct { _: Handle }
Texture_Descriptor :: struct { bytes: [4]u64 }
Sampler_Descriptor :: struct { bytes: [2]u64 }
BVH_Descriptor :: struct { bytes: [2]u64 }

// Enums
Feature :: enum { Raytracing = 0 }
Features :: bit_set[Feature; u32]
Allocation_Type :: enum { Default = 0, Descriptors }
Memory :: enum { Default = 0, GPU, Readback }
Queue_Type :: enum { Main = 0, Compute, Transfer }
Texture_Type :: enum { D2 = 0, D3, D1 }
Texture_Format :: enum {
	Default = 0,
	RGBA8_Unorm,
	BGRA8_Unorm,
	D32_Float,
	RGBA16_Float,
	BC1_RGBA_Unorm,
	BC3_RGBA_Unorm,
	BC7_RGBA_Unorm,
	ASTC_4x4_RGBA_Unorm,
	ETC2_RGB8_Unorm,
	ETC2_RGBA8_Unorm,
	EAC_R11_Unorm,
	EAC_RG11_Unorm,
}
Usage :: enum { Sampled = 0, Storage, Transfer_Src, Color_Attachment, Depth_Stencil_Attachment }
Usage_Flags :: bit_set[Usage; u32]
Shader_Type_Graphics :: enum { Vertex = 0, Fragment }
Load_Op :: enum { Clear = 0, Load, Dont_Care }
Store_Op :: enum { Store = 0, Dont_Care }
Compare_Op :: enum { Never = 0, Less, Equal, Less_Equal, Greater, Not_Equal, Greater_Equal, Always }
Blend_Op :: enum { Add, Subtract, Rev_Subtract, Min, Max }
Blend_Factor :: enum { Zero, One, Src_Color, Dst_Color, Src_Alpha }
Depth_Mode :: enum { Read = 0, Write }
Depth_Flags :: bit_set[Depth_Mode; u32]
Hazard :: enum { Draw_Arguments = 0, Descriptors, Depth_Stencil, BVHs }
Hazard_Flags :: bit_set[Hazard; u32]
Stage :: enum { Transfer = 0, Compute, Raster_Color_Out, Fragment_Shader, Vertex_Shader, Build_BVH, All }
Color_Component_Flag :: enum { R = 0, G = 1, B = 2, A = 3 }
Color_Component_Flags :: distinct bit_set[Color_Component_Flag; u8]
Filter :: enum { Linear = 0, Nearest }
Address_Mode :: enum { Repeat = 0, Mirrored_Repeat, Clamp_To_Edge }
BVH_Instance_Flag :: enum { Disable_Culling = 0, Flip_Facing = 1, Force_Opaque = 2, Force_Not_Opaque = 3 }
BVH_Instance_Flags :: distinct bit_set[BVH_Instance_Flag; u32]
BVH_Opacity :: enum { Fully_Opaque = 0, Transparent }
BVH_Hint :: enum { Default = 0, Prefer_Fast_Trace, Prefer_Fast_Build, Prefer_Low_Memory }
BVH_Capability :: enum { Update = 0, Compaction }
BVH_Capabilities :: distinct bit_set[BVH_Capability; u32]

// Constants
All_Mips: u8 : max(u8)
All_Layers: u16 : max(u16)

// Structs
Blit_Rect :: struct
{
    offset_a: [3]i32,  // offset_a == 0 && offset_b == 0 -> full image
    offset_b: [3]i32,  // offset_a == 0 && offset_b == 0 -> full image
    mip_level: u32,
    base_layer: u32,
    layer_count: u32,
}

Mip_Copy_Region :: struct {
	src_offset:  u64, // Offset in staging buffer
	mip_level:   u32,
	array_layer: u32,
	layer_count: u32,
}

Texture_Desc :: struct
{
    type: Texture_Type,
    dimensions: [3]u32,
    mip_count: u32,     // 0 = 1
    layer_count: u32,   // 0 = 1
    sample_count: u32,  // 0 = 1
    format: Texture_Format,
    usage: Usage_Flags,
}

Sampler_Desc :: struct
{
    min_filter: Filter,
    mag_filter: Filter,
    mip_filter: Filter,
    address_mode_u: Address_Mode,
    address_mode_v: Address_Mode,
    address_mode_w: Address_Mode,
    mip_lod_bias: f32,
    min_lod: f32,
    max_lod: f32,  // 0.0 = use all lods
    max_anisotropy: f32,
}

Texture_View_Desc :: struct
{
    type: Texture_Type,
    format: Texture_Format,  // .Default = inherits the texture's format
    base_mip: u32,
    mip_count: u8,     // 0 = All_Mips
    base_layer: u16,
    layer_count: u16,  // 0 = All_Layers
}

Render_Attachment :: struct
{
    texture: Texture,
    view: Texture_View_Desc,
    load_op: Load_Op,
    store_op: Store_Op,
    clear_color: [4]f32,
}

Render_Pass_Desc :: struct
{
    render_area_offset: [2]i32,
    render_area_size:   [2]u32,  // 0 = full texture size
    layer_count:        u32,     // 0 = 1
    view_mask:          u32,
    color_attachments:  []Render_Attachment,
    depth_attachment:   Maybe(Render_Attachment),
    stencil_attachment: Maybe(Render_Attachment),
}

Texture :: struct #all_or_none
{
    dimensions: [3]u32,
    format: Texture_Format,
    mip_count: u32,
    handle: Texture_Handle
}

Depth_State :: struct
{
    mode: Depth_Flags,
    compare: Compare_Op
}

Blend_State :: struct
{
    enable: bool,
    color_op: Blend_Op,
    src_color_factor: Blend_Factor,
    dst_color_factor: Blend_Factor,
    alpha_op: Blend_Op,
    src_alpha_factor: Blend_Factor,
    dst_alpha_factor: Blend_Factor,
    color_write_mask: u8,
}

Draw_Indexed_Indirect_Command :: struct
{
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
}

Dispatch_Indirect_Command :: struct
{
    num_groups_x: u32,
    num_groups_y: u32,
    num_groups_z: u32,
}

BVH_Instance :: struct
{
    transform: [12]f32,  // Row-major 3x4 matrix!
    using _: bit_field u32 {
        custom_idx: u32 | 24,
        mask:       u32 | 8,
    },
    using _: bit_field u32 {
        _unused: u32 | 24,
        disable_culling: bool | 1,
        flip_facing: bool | 1,
        force_opaque: bool | 1,
        force_not_opaque: bool | 1,
        force_opacity_micromaps: bool | 1,
        disable_opacity_micromaps: bool | 1,
        _unused_flags: bool | 2,
    },
    blas_root: rawptr,
}

BVH_Mesh_Desc :: struct
{
    opacity: BVH_Opacity,
    vertex_stride: u32,
    max_vertex: u32,  // e.g. if reading vertices [200..300], this value must be 300.
    tri_count: u32,
}
BVH_AABB_Desc :: struct
{
    opacity: BVH_Opacity,
    stride: u32,
    aabb_count: u32,
}
BVH_Shape_Desc :: union { BVH_Mesh_Desc, BVH_AABB_Desc }

BVH_Mesh  :: struct { verts: rawptr, indices: rawptr }
BVH_AABBs :: struct { data: rawptr }
BVH_Shape :: union { BVH_Mesh, BVH_AABBs }

BLAS_Desc :: struct
{
    hint: BVH_Hint,
    caps: BVH_Capabilities,
    shapes: []BVH_Shape_Desc,
}

TLAS_Desc :: struct
{
    hint: BVH_Hint,
    caps: BVH_Capabilities,
    instance_count: u32,
}

Device_Limits :: struct
{
    max_anisotropy: f32,
}

// Procedures

// Initialization and interaction with the OS. This is simpler than it would probably be, for brevity.
init: proc() : _init
cleanup: proc() : _cleanup
wait_idle: proc() : _wait_idle
swapchain_init: proc(surface: vk.SurfaceKHR, init_size: [2]u32, frames_in_flight: u32) : _swapchain_init
swapchain_resize: proc(size: [2]u32) : _swapchain_resize  // NOTE: Do not call this every frame! Only if the dimensions change.
swapchain_acquire_next: proc() -> Texture : _swapchain_acquire_next  // Blocks CPU until at least one frame is available.
// TODO: The only queue that makes sense here is .Main. Remove the queue param?
swapchain_present: proc(queue: Queue_Type, sem_wait: Semaphore, wait_value: u64) : _swapchain_present
features_available: proc() -> Features : _features_available
device_limits: proc() -> Device_Limits : _device_limits

// Memory
mem_alloc: proc(bytes: u64, align: u64 = 1, mem_type := Memory.Default, alloc_type := Allocation_Type.Default) -> rawptr : _mem_alloc
mem_free: proc(ptr: rawptr, loc := #caller_location) : _mem_free
host_to_device_ptr: proc(ptr: rawptr) -> rawptr : _host_to_device_ptr  // Only supports base allocation pointers, like mem_free!

// Textures
texture_size_and_align: proc(desc: Texture_Desc) -> (size: u64, align: u64) : _texture_size_and_align
texture_create: proc(desc: Texture_Desc, storage: rawptr, queue: Queue_Type = .Main, signal_sem: Semaphore = {}, signal_value: u64 = 0) -> Texture : _texture_create
texture_destroy: proc(texture: ^Texture) : _texture_destroy
texture_view_descriptor: proc(texture: Texture, view_desc: Texture_View_Desc) -> Texture_Descriptor : _texture_view_descriptor
texture_rw_view_descriptor: proc(texture: Texture, view_desc: Texture_View_Desc) -> Texture_Descriptor : _texture_rw_view_descriptor
sampler_descriptor: proc(sampler_desc: Sampler_Desc) -> Sampler_Descriptor : _sampler_descriptor
get_texture_view_descriptor_size: proc() -> u32 : _get_texture_view_descriptor_size
get_texture_rw_view_descriptor_size: proc() -> u32 : _get_texture_rw_view_descriptor_size
get_sampler_descriptor_size: proc() -> u32 : _get_sampler_descriptor_size

// Shaders
shader_create: proc(code: []u32, type: Shader_Type_Graphics, entry_point_name: string = "main") -> Shader : _shader_create
shader_create_compute: proc(code: []u32, group_size_x: u32, group_size_y: u32 = 1, group_size_z: u32 = 1, entry_point_name: string = "main") -> Shader : _shader_create_compute
shader_destroy: proc(shader: Shader) : _shader_destroy

// Semaphores
semaphore_create: proc(init_value: u64 = 0) -> Semaphore : _semaphore_create
semaphore_wait: proc(sem: Semaphore, wait_value: u64) : _semaphore_wait
semaphore_destroy: proc(sem: ^Semaphore) : _semaphore_destroy

// Queues
queue_wait_idle: proc(queue: Queue_Type) : _queue_wait_idle
queue_submit: proc(queue: Queue_Type, cmd_bufs: []Command_Buffer, signal_sem: Semaphore = {}, signal_value: u64 = 0) : _queue_submit

// Raytracing
blas_size_and_align: proc(desc: BLAS_Desc) -> (size: u64, align: u64) : _blas_size_and_align
blas_create: proc(desc: BLAS_Desc, storage: rawptr) -> BVH : _blas_create
blas_build_scratch_buffer_size_and_align: proc(desc: BLAS_Desc) -> (size: u64, align: u64) : _blas_build_scratch_buffer_size_and_align
//blas_update_scratch_buffer_size_and_align
tlas_size_and_align: proc(desc: TLAS_Desc) -> (size: u64, align: u64) : _tlas_size_and_align
tlas_create: proc(desc: TLAS_Desc, storage: rawptr) -> BVH : _tlas_create
tlas_build_scratch_buffer_size_and_align: proc(desc: TLAS_Desc) -> (size: u64, align: u64) : _tlas_build_scratch_buffer_size_and_align
bvh_size_and_align :: proc { blas_size_and_align, tlas_size_and_align }
bvh_create :: proc { blas_create, tlas_create }
bvh_build_scratch_buffer_size_and_align :: proc { blas_build_scratch_buffer_size_and_align, tlas_build_scratch_buffer_size_and_align }
bvh_root_ptr: proc(bvh: BVH) -> rawptr : _bvh_root_ptr
bvh_descriptor: proc(bvh: BVH) -> BVH_Descriptor : _bvh_descriptor
get_bvh_descriptor_size: proc() -> u32 : _get_bvh_descriptor_size
bvh_destroy: proc(bvh: ^BVH) : _bvh_destroy

// Command buffer
commands_begin: proc(queue: Queue_Type) -> Command_Buffer : _commands_begin

// Commands
cmd_mem_copy: proc(cmd_buf: Command_Buffer, src, dst: rawptr, #any_int bytes: i64) : _cmd_mem_copy
cmd_copy_to_texture: proc(cmd_buf: Command_Buffer, texture: Texture, src, dst: rawptr) : _cmd_copy_to_texture
cmd_copy_mips_to_texture: proc(cmd_buf: Command_Buffer, texture: Texture, src_buffer: rawptr, regions: []Mip_Copy_Region) : _cmd_copy_mips_to_texture
cmd_blit_texture: proc(cmd_buf: Command_Buffer, src, dst: Texture, src_rects: []Blit_Rect, dst_rects: []Blit_Rect, filter: Filter) : _cmd_blit_texture

cmd_set_desc_heap: proc(cmd_buf: Command_Buffer, textures, textures_rw, samplers, bvhs: rawptr) : _cmd_set_desc_heap

cmd_barrier: proc(cmd_buf: Command_Buffer, before: Stage, after: Stage, hazards: Hazard_Flags = {}) : _cmd_barrier
//cmd_signal_after: proc() : _cmd_signal_after
//cmd_wait_before: proc() : _cmd_wait_before

cmd_set_shaders: proc(cmd_buf: Command_Buffer, vert_shader: Shader, frag_shader: Shader) : _cmd_set_shaders
cmd_set_compute_shader: proc(cmd_buf: Command_Buffer, compute_shader: Shader) : _cmd_set_compute_shader
cmd_set_depth_state: proc(cmd_buf: Command_Buffer, state: Depth_State) : _cmd_set_depth_state
cmd_set_blend_state: proc(cmd_buf: Command_Buffer, state: Blend_State) : _cmd_set_blend_state

// Run compute shader based on number of groups
cmd_dispatch: proc(cmd_buf: Command_Buffer, compute_data: rawptr, num_groups_x: u32, num_groups_y: u32 = 1, num_groups_z: u32 = 1) : _cmd_dispatch

// Schedule indirect compute shader based on number of groups, arguments is a pointer to a Dispatch_Indirect_Command struct
cmd_dispatch_indirect: proc(cmd_buf: Command_Buffer, compute_data: rawptr, arguments: rawptr) : _cmd_dispatch_indirect

cmd_begin_render_pass: proc(cmd_buf: Command_Buffer, desc: Render_Pass_Desc) : _cmd_begin_render_pass
cmd_end_render_pass: proc(cmd_buf: Command_Buffer) : _cmd_end_render_pass

// Indices can be nil
cmd_draw_indexed_instanced: proc(cmd_buf: Command_Buffer, vertex_data: rawptr, fragment_data: rawptr,
                                 indices: rawptr, index_count: u32, instance_count: u32 = 1) : _cmd_draw_indexed_instanced
cmd_draw_indexed_instanced_indirect: proc(cmd_buf: Command_Buffer, vertex_data: rawptr, fragment_data: rawptr,
                                          indices: rawptr, indirect_arguments: rawptr) : _cmd_draw_indexed_instanced_indirect
cmd_draw_indexed_instanced_indirect_multi: proc(cmd_buf: Command_Buffer, data_vertex: rawptr, data_pixel: rawptr,
                                                 indices: rawptr, indirect_arguments: rawptr, stride: u32, draw_count: rawptr) : _cmd_draw_indexed_instanced_indirect_multi

cmd_build_blas: proc(cmd_buf: Command_Buffer, bvh: BVH, bvh_storage: rawptr, scratch_storage: rawptr, shapes: []BVH_Shape) : _cmd_build_blas
cmd_build_tlas: proc(cmd_buf: Command_Buffer, bvh: BVH, bvh_storage: rawptr, scratch_storage: rawptr, instances: rawptr) : _cmd_build_tlas

/////////////////////////
// Userland Utilities

mem_alloc_typed :: proc($T: typeid, #any_int count: i64) -> []T
{
    assert(count > 0)

    ptr := mem_alloc(size_of(T) * u64(count), align_of(T))
    return slice.from_ptr(cast(^T) ptr, int(count))
}

mem_alloc_typed_gpu :: proc($T: typeid, #any_int count: i64) -> rawptr
{
    assert(count > 0)

    ptr := mem_alloc(size_of(T) * u64(count), align_of(T), mem_type = .GPU)
    return ptr
}

// Avoid -vet warnings about unused "slice" package
@(private="file")
_fictitious :: proc() { mem_alloc_typed(u32, 0) }

mem_free_typed :: proc(mem: []$T, loc := #caller_location)
{
    mem_free(raw_data(mem), loc = loc)
}

Arena :: struct
{
    cpu: rawptr,
    gpu: rawptr,
    offset: u64,
    size: u64,
}

Allocation_Slice :: struct($T: typeid)
{
    cpu: []T,
    gpu: rawptr,
}

Allocation :: struct($T: typeid)
{
    cpu: ^T,
    gpu: rawptr,
}

arena_init :: proc(storage: u64, mem_type := Memory.Default) -> Arena
{
    res: Arena
    res.size = storage
    alloc := mem_alloc(storage, mem_type = mem_type)
    res.cpu = nil if mem_type == .GPU else alloc
    res.gpu = alloc if mem_type == .GPU else host_to_device_ptr(alloc)
    return res
}

arena_alloc_untyped :: proc(using arena: ^Arena, bytes: u64, align: u64 = 16) -> (alloc_cpu: rawptr, alloc_gpu: rawptr)
{
    assert(bytes > 0 && align > 0)

    gpu_addr := uintptr(arena.gpu) + uintptr(arena.offset)
    offset = align_up(u64(gpu_addr), align) - u64(uintptr(arena.gpu))

    if offset + bytes > size do panic("GPU Arena ran out of space!")

    alloc_cpu = nil if cpu == nil else auto_cast(uintptr(cpu) + uintptr(offset))
    alloc_gpu = auto_cast(uintptr(gpu) + uintptr(offset))
    offset += bytes
    return
}

arena_alloc :: proc(using arena: ^Arena, $T: typeid) -> Allocation(T)
{
    alloc_cpu, alloc_gpu := arena_alloc_untyped(arena, size_of(T), align_of(T))
    return {
        cpu = cast(^T) alloc_cpu,
        gpu = alloc_gpu
    }
}

arena_alloc_array :: proc(using arena: ^Arena, $T: typeid, #any_int count: i64) -> Allocation_Slice(T)
{
    assert(count > 0)

    alloc_cpu, alloc_gpu := arena_alloc_untyped(arena, size_of(T) * u64(count), align_of(T))
    return {
        cpu = slice.from_ptr(cast(^T) alloc_cpu, int(count)),
        gpu = alloc_gpu
    }
}

arena_free_all :: proc(using arena: ^Arena)
{
    offset = 0
}

arena_destroy :: proc(using arena: ^Arena)
{
    offset = 0
    size = 0
    if cpu == nil {
        mem_free(gpu)
    } else {
        mem_free(cpu)
    }
    cpu = nil
    gpu = nil
}

@(private="file")
align_up :: proc(x, align: u64) -> (aligned: u64)
{
    assert(0 == (align & (align - 1)), "must align to a power of two")
    return (x + (align - 1)) &~ (align - 1)
}

Owned_Texture :: struct
{
    using tex: Texture,
    mem: rawptr,
}

alloc_and_create_texture :: proc(desc: Texture_Desc, queue: Queue_Type = .Main, signal_sem: Semaphore = {}, signal_value: u64 = 0) -> Owned_Texture
{
    size, align := texture_size_and_align(desc)
    ptr := mem_alloc(size, align, .GPU)
    texture := texture_create(desc, ptr, queue, signal_sem, signal_value)
    return Owned_Texture { texture, ptr }
}

free_and_destroy_texture :: proc(texture: ^Owned_Texture)
{
    texture_destroy(texture)
    mem_free(texture.mem)
    texture^ = {}
}

set_texture_desc :: #force_inline proc(desc_heap: rawptr, idx: u32, desc: Texture_Descriptor)
{
    desc_size := #force_inline get_texture_view_descriptor_size()
    tmp := desc
    runtime.mem_copy(auto_cast(uintptr(desc_heap) + uintptr(idx * desc_size)), &tmp, int(desc_size))
}

set_texture_rw_desc :: #force_inline proc(desc_heap: rawptr, idx: u32, desc: Texture_Descriptor)
{
    desc_size := #force_inline get_texture_rw_view_descriptor_size()
    tmp := desc
    runtime.mem_copy(auto_cast(uintptr(desc_heap) + uintptr(idx * desc_size)), &tmp, int(desc_size))
}

set_sampler_desc :: #force_inline proc(desc_heap: rawptr, idx: u32, desc: Sampler_Descriptor)
{
    desc_size := #force_inline get_sampler_descriptor_size()
    tmp := desc
    runtime.mem_copy(auto_cast(uintptr(desc_heap) + uintptr(idx * desc_size)), &tmp, int(desc_size))
}

set_bvh_desc :: #force_inline proc(desc_heap: rawptr, idx: u32, desc: BVH_Descriptor)
{
    desc_size := #force_inline get_bvh_descriptor_size()
    tmp := desc
    runtime.mem_copy(auto_cast(uintptr(desc_heap) + uintptr(idx * desc_size)), &tmp, int(desc_size))
}

Owned_BVH :: struct
{
    using handle: BVH,
    mem: rawptr,
}

alloc_and_create_blas :: proc(desc: BLAS_Desc) -> Owned_BVH
{
    size, align := bvh_size_and_align(desc)
    ptr := mem_alloc(size, align, .GPU)
    bvh := bvh_create(desc, ptr)
    return Owned_BVH { bvh, ptr }
}

alloc_and_create_tlas :: proc(desc: TLAS_Desc) -> Owned_BVH
{
    size, align := bvh_size_and_align(desc)
    ptr := mem_alloc(size, align, .GPU)
    bvh := bvh_create(desc, ptr)
    return Owned_BVH { bvh, ptr }
}

alloc_and_create_bvh :: proc { alloc_and_create_blas, alloc_and_create_tlas }

free_and_destroy_bvh :: proc(bvh: ^Owned_BVH)
{
    bvh_destroy(bvh)
    mem_free(bvh.mem)
    bvh^ = {}
}

alloc_blas_build_scratch_buffer :: proc(arena: ^Arena, desc: BLAS_Desc) -> rawptr
{
    size, align := blas_build_scratch_buffer_size_and_align(desc)
    _, gpu := arena_alloc_untyped(arena, size, align)
    return gpu
}

alloc_tlas_build_scratch_buffer :: proc(arena: ^Arena, desc: TLAS_Desc) -> rawptr
{
    size, align := tlas_build_scratch_buffer_size_and_align(desc)
    _, gpu := arena_alloc_untyped(arena, size, align)
    return gpu
}

alloc_bvh_build_scratch_buffer :: proc { alloc_blas_build_scratch_buffer, alloc_tlas_build_scratch_buffer }

// Swapchain utils

swapchain_init_from_sdl :: proc(window: ^sdl.Window, frames_in_flight: u32)
{
    vk_surface: vk.SurfaceKHR
    ok := sdl.Vulkan_CreateSurface(window, get_vulkan_instance(), nil, &vk_surface)
    ensure(ok, "Could not create surface.")

    window_size_x: i32
    window_size_y: i32
    sdl.GetWindowSize(window, &window_size_x, &window_size_y)
    swapchain_init(vk_surface, { u32(max(0, window_size_x)), u32(max(0, window_size_y)) }, frames_in_flight)
}

// Texture utils
cmd_generate_mipmaps :: proc(cmd_buf: Command_Buffer, texture: Texture)
{
    for mip in 1..<texture.mip_count
    {
        if mip > 1 {
            cmd_barrier(cmd_buf, .Transfer, .Transfer)
        }

        src := Blit_Rect { mip_level = mip - 1 }
        dst := Blit_Rect { mip_level = mip }
        cmd_blit_texture(cmd_buf, texture, texture, { src }, { dst }, .Linear)
    }
}
