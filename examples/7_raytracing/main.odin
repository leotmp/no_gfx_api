
package main

import log "core:log"
import "core:math"
import "core:math/linalg"
import "base:runtime"
import intr "base:intrinsics"
import "core:fmt"

import "../../gpu"

import sdl "vendor:sdl3"

import shared "../shared"
import gltf2 "../shared/gltf2"

Start_Window_Size_X :: 1000
Start_Window_Size_Y :: 1000
Frames_In_Flight :: 3
Example_Name :: "Raytracing"

Sponza_Scene :: #load("../shared/assets/sponza.glb")

main :: proc()
{
    fmt.println("Right-click + WASD for first-person controls.")

    ok_i := sdl.Init({ .VIDEO })
    assert(ok_i)

    console_logger := log.create_console_logger()
    defer log.destroy_console_logger(console_logger)
    context.logger = console_logger

    ts_freq := sdl.GetPerformanceFrequency()
    max_delta_time: f32 = 1.0 / 10.0  // 10fps

    window_flags :: sdl.WindowFlags {
        .HIGH_PIXEL_DENSITY,
        .VULKAN,
        .RESIZABLE,
    }
    window := sdl.CreateWindow(Example_Name, Start_Window_Size_X, Start_Window_Size_Y, window_flags)
    ensure(window != nil)

    window_size_x := i32(Start_Window_Size_X)
    window_size_y := i32(Start_Window_Size_Y)

    gpu.init()
    defer gpu.cleanup()

    if !(.Raytracing in gpu.features_available()) {
        log.error("Raytracing is not supported, but it is mandatory for this example.")
        return
    }

    gpu.swapchain_init_from_sdl(window, Frames_In_Flight)

    group_size_x := u32(8)
    group_size_y := u32(8)
    vert_shader := gpu.shader_create(#load("shaders/test.vert.spv", []u32), .Vertex)
    frag_shader := gpu.shader_create(#load("shaders/test.frag.spv", []u32), .Fragment)
    pathtrace_shader := gpu.shader_create_compute(#load("shaders/pathtracer.comp.spv", []u32), group_size_x, group_size_y, 1)
    defer {
        gpu.shader_destroy(vert_shader)
        gpu.shader_destroy(frag_shader)
        gpu.shader_destroy(pathtrace_shader)
    }

    upload_arena := gpu.arena_init(1024 * 1024 * 1024)
    defer gpu.arena_destroy(&upload_arena)
    bvh_scratch_arena := gpu.arena_init(1024 * 1024 * 1024, .GPU)
    defer gpu.arena_destroy(&bvh_scratch_arena)

    gltf_scene, _, gltf_data := shared.load_scene_gltf(Sponza_Scene)
    defer {
        shared.destroy_scene(&gltf_scene)
        gltf2.unload(gltf_data)
    }

    // Create a texture for the compute shader to write to
    output_desc := gpu.Texture_Desc {
        type = .D2,
        dimensions = { u32(window_size_x), u32(window_size_y), 1 },
        mip_count = 1,
        layer_count = 1,
        sample_count = 1,
        format = .RGBA16_Float,
        usage = { .Storage, .Sampled },
    }
    output_texture := gpu.alloc_and_create_texture(output_desc)
    defer gpu.free_and_destroy_texture(&output_texture)

    // Create texture descriptor for RW access (compute shader)
    texture_rw_desc := gpu.texture_rw_view_descriptor(output_texture, {})

    texture_id := u32(0)
    sampler_id := u32(0)

    // Allocate texture heap for compute shader
    texture_rw_heap_size := gpu.get_texture_rw_view_descriptor_size()
    texture_rw_heap := gpu.mem_alloc(u64(texture_rw_heap_size), alloc_type = .Descriptors)
    defer gpu.mem_free(texture_rw_heap)
    gpu.set_texture_rw_desc(texture_rw_heap, texture_id, texture_rw_desc)
    texture_rw_heap_gpu := gpu.host_to_device_ptr(texture_rw_heap)

    // Create texture descriptor for sampled access (fragment shader)
    texture_desc := gpu.texture_view_descriptor(output_texture, {})

    // Allocate texture heap for fragment shader
    texture_heap := gpu.mem_alloc(size_of(gpu.Texture_Descriptor) * 65536, alloc_type = .Descriptors)
    defer gpu.mem_free(texture_heap)
    gpu.set_texture_desc(texture_heap, texture_id, texture_desc)

    // Create sampler
    sampler_heap := gpu.mem_alloc(size_of(gpu.Sampler_Descriptor) * 10, alloc_type = .Descriptors)
    defer gpu.mem_free(sampler_heap)
    gpu.set_sampler_desc(sampler_heap, sampler_id, gpu.sampler_descriptor({}))

    // BVH descriptor heap
    bvh_heap := gpu.mem_alloc(size_of(gpu.BVH_Descriptor) * 10, alloc_type = .Descriptors)
    defer gpu.mem_free(bvh_heap)

    Compute_Data :: struct {
        output_texture_id: u32,
        scene: Scene_Shader,
        resolution: [2]f32,
        accum_counter: u32,
        camera_to_world: [16]f32,
    }

    Vertex :: struct { pos: [3]f32, uv: [2]f32 }

    arena := gpu.arena_init(1024 * 1024)
    defer gpu.arena_destroy(&arena)

    // Create fullscreen quad
    verts := gpu.arena_alloc_array(&arena, Vertex, 4)
    verts.cpu[0].pos = { -1.0,  1.0, 0.0 }  // Top-left
    verts.cpu[1].pos = {  1.0, -1.0, 0.0 }  // Bottom-right
    verts.cpu[2].pos = {  1.0,  1.0, 0.0 }  // Top-right
    verts.cpu[3].pos = { -1.0, -1.0, 0.0 }  // Bottom-left
    verts.cpu[0].uv  = {  0.0,  0.0 }
    verts.cpu[1].uv  = {  1.0,  1.0 }
    verts.cpu[2].uv  = {  1.0,  0.0 }
    verts.cpu[3].uv  = {  0.0,  1.0 }

    indices := gpu.arena_alloc_array(&arena, u32, 6)
    indices.cpu[0] = 0
    indices.cpu[1] = 2
    indices.cpu[2] = 1
    indices.cpu[3] = 0
    indices.cpu[4] = 1
    indices.cpu[5] = 3

    verts_local := gpu.mem_alloc_typed_gpu(Vertex, 4)
    indices_local := gpu.mem_alloc_typed_gpu(u32, 6)
    defer {
        gpu.mem_free(verts_local)
        gpu.mem_free(indices_local)
    }

    queue := gpu.Queue_Type.Main

    upload_cmd_buf := gpu.commands_begin(queue)
    gpu.cmd_mem_copy(upload_cmd_buf, verts.gpu, verts_local, u64(len(verts.cpu)) * size_of(verts.cpu[0]))
    gpu.cmd_mem_copy(upload_cmd_buf, indices.gpu, indices_local, u64(len(indices.cpu)) * size_of(indices.cpu[0]))

    scene := upload_scene(gltf_scene, &upload_arena, &bvh_scratch_arena, upload_cmd_buf)
    defer {
        scene_destroy(&scene)
    }

    gpu.cmd_barrier(upload_cmd_buf, .Transfer, .All, {})
    gpu.queue_submit(queue, { upload_cmd_buf })

    gpu.set_bvh_desc(bvh_heap, 0, gpu.bvh_descriptor(scene.bvh))

    now_ts := sdl.GetPerformanceCounter()
    total_time: f32 = 0.0

    camera_to_world: matrix[4, 4]f32 = 1

    accum_counter := u32(0)

    frame_arenas: [Frames_In_Flight]gpu.Arena
    for &frame_arena in frame_arenas do frame_arena = gpu.arena_init(1024 * 1024)
    defer for &frame_arena in frame_arenas do gpu.arena_destroy(&frame_arena)
    next_frame := u64(1)
    frame_sem := gpu.semaphore_create(0)
    defer gpu.semaphore_destroy(&frame_sem)
    for true
    {
        proceed := shared.handle_window_events(window)
        if !proceed do break

        old_window_size_x := window_size_x
        old_window_size_y := window_size_y
        sdl.GetWindowSize(window, &window_size_x, &window_size_y)
        if .MINIMIZED in sdl.GetWindowFlags(window) || window_size_x <= 0 || window_size_y <= 0
        {
            sdl.Delay(16)
            continue
        }

        if next_frame > Frames_In_Flight {
            gpu.semaphore_wait(frame_sem, next_frame - Frames_In_Flight)
        }
        if old_window_size_x != window_size_x || old_window_size_y != window_size_y
        {
            gpu.queue_wait_idle(queue)
            gpu.swapchain_resize({ u32(window_size_x), u32(window_size_y) })

            output_desc.dimensions.x = u32(window_size_x)
            output_desc.dimensions.y = u32(window_size_y)
            gpu.free_and_destroy_texture(&output_texture)
            output_texture = gpu.alloc_and_create_texture(output_desc)

            // Update descriptor for new texture
            texture_desc = gpu.texture_view_descriptor(output_texture, {})
            texture_rw_desc := gpu.texture_rw_view_descriptor(output_texture, {})
            gpu.set_texture_desc(texture_heap, texture_id, texture_desc)
            gpu.set_texture_rw_desc(texture_rw_heap, texture_id, texture_rw_desc)

            accum_counter = 0
        }

        if shared.INPUT.pressing_right_click do accum_counter = 0

        last_ts := now_ts
        now_ts = sdl.GetPerformanceCounter()
        delta_time := min(max_delta_time, f32(f64((now_ts - last_ts)*1000) / f64(ts_freq)) / 1000.0)
        total_time += delta_time

        frame_arena := &frame_arenas[next_frame % Frames_In_Flight]

        old_camera_to_world := camera_to_world
        camera_to_world := linalg.inverse(shared.first_person_camera_view(delta_time))

        swapchain := gpu.swapchain_acquire_next()  // Blocks CPU until at least one frame is available.

        // Allocate compute data for this frame with current time and resolution
        compute_data := gpu.arena_alloc(frame_arena, Compute_Data)
        compute_data.cpu.output_texture_id = texture_id
        compute_data.cpu.scene = scene.scene_shader
        compute_data.cpu.accum_counter = accum_counter
        compute_data.cpu.resolution = { f32(window_size_x), f32(window_size_y) }
        compute_data.cpu.camera_to_world = intr.matrix_flatten(camera_to_world)

        cmd_buf := gpu.commands_begin(queue)

        // Dispatch compute shader to write to texture
        gpu.cmd_set_desc_heap(cmd_buf, nil, texture_rw_heap_gpu, nil, gpu.host_to_device_ptr(bvh_heap))
        gpu.cmd_set_compute_shader(cmd_buf, pathtrace_shader)

        num_groups_x := (u32(window_size_x) + group_size_x - 1) / group_size_x
        num_groups_y := (u32(window_size_y) + group_size_y - 1) / group_size_y
        num_groups_z := u32(1)

        gpu.cmd_dispatch(cmd_buf, compute_data.gpu, num_groups_x, num_groups_y, num_groups_z)

        // Barrier to ensure compute shader finishes before rendering
        gpu.cmd_barrier(cmd_buf, .Compute, .Fragment_Shader, {})

        // Render the texture to the swapchain using a fullscreen quad
        gpu.cmd_begin_render_pass(cmd_buf, {
            color_attachments = {
                { texture = swapchain, clear_color = { 0.0, 0.0, 0.0, 1.0 } }
            }
        })
        gpu.cmd_set_shaders(cmd_buf, vert_shader, frag_shader)
        textures := gpu.host_to_device_ptr(texture_heap)
        samplers := gpu.host_to_device_ptr(sampler_heap)
        gpu.cmd_set_desc_heap(cmd_buf, textures, nil, samplers, nil)

        Vert_Data :: struct {
            verts: rawptr,
        }
        verts_data := gpu.arena_alloc(frame_arena, Vert_Data)
        verts_data.cpu.verts = verts_local

        Frag_Data :: struct {
            texture_id: u32,
            sampler_id: u32,
        }
        frag_data := gpu.arena_alloc(frame_arena, Frag_Data)
        frag_data.cpu.texture_id = texture_id
        frag_data.cpu.sampler_id = sampler_id

        gpu.cmd_draw_indexed_instanced(cmd_buf, verts_data.gpu, frag_data.gpu, indices_local, u32(len(indices.cpu)), 1)
        gpu.cmd_end_render_pass(cmd_buf)
        gpu.cmd_add_signal_semaphore(cmd_buf, frame_sem, next_frame)
        gpu.queue_submit(queue, { cmd_buf })

        gpu.swapchain_present(queue, frame_sem, next_frame)
        next_frame += 1

        gpu.arena_free_all(frame_arena)
        accum_counter += 1
    }

    gpu.wait_idle()
}

Mesh_GPU :: struct
{
    mesh_gpu: Mesh_Shader,
    idx_count: u32,
    vert_count: u32,
    bvh: gpu.Owned_BVH,
}

Mesh_Shader :: struct
{
    pos: rawptr,
    normals: rawptr,
    indices: rawptr,
}

upload_mesh :: proc(upload_arena: ^gpu.Arena, cmd_buf: gpu.Command_Buffer, mesh: shared.Mesh) -> Mesh_Shader
{
    assert(len(mesh.pos) == len(mesh.normals))
    assert(len(mesh.pos) == len(mesh.uvs))

    positions_staging := gpu.arena_alloc_array(upload_arena, [4]f32, len(mesh.pos))
    normals_staging := gpu.arena_alloc_array(upload_arena, [4]f32, len(mesh.normals))
    uvs_staging := gpu.arena_alloc_array(upload_arena, [2]f32, len(mesh.uvs))
    indices_staging := gpu.arena_alloc_array(upload_arena, u32, len(mesh.indices))
    copy(positions_staging.cpu, mesh.pos[:])
    copy(normals_staging.cpu, mesh.normals[:])
    copy(uvs_staging.cpu, mesh.uvs[:])
    copy(indices_staging.cpu, mesh.indices[:])

    res: Mesh_Shader
    res.pos = gpu.mem_alloc_typed_gpu([4]f32, len(mesh.pos))
    res.normals = gpu.mem_alloc_typed_gpu([4]f32, len(mesh.normals))
    //res.uvs = gpu.mem_alloc_typed_gpu([2]f32, len(mesh.uvs))
    res.indices = gpu.mem_alloc_typed_gpu(u32, len(mesh.indices))
    gpu.cmd_mem_copy(cmd_buf, positions_staging.gpu, res.pos, u64(len(mesh.pos) * size_of(mesh.pos[0])))
    gpu.cmd_mem_copy(cmd_buf, normals_staging.gpu, res.normals, u64(len(mesh.normals) * size_of(mesh.normals[0])))
    //gpu.cmd_mem_copy(cmd_buf, uvs_staging.gpu, res.uvs, u64(len(mesh.uvs) * size_of(mesh.uvs[0])))
    gpu.cmd_mem_copy(cmd_buf, indices_staging.gpu, res.indices, u64(len(mesh.indices) * size_of(mesh.indices[0])))
    return res
}

mesh_destroy :: proc(mesh: ^Mesh_GPU)
{
    gpu.free_and_destroy_bvh(&mesh.bvh)
    gpu.mem_free(mesh.mesh_gpu.pos)
    gpu.mem_free(mesh.mesh_gpu.normals)
    gpu.mem_free(mesh.mesh_gpu.indices)
    mesh^ = {}
}

build_blas :: proc(bvh_scratch_arena: ^gpu.Arena, cmd_buf: gpu.Command_Buffer, positions: rawptr, indices: rawptr, idx_count: u32, vert_count: u32) -> gpu.Owned_BVH
{
    assert(idx_count % 3 == 0)

    desc := gpu.BLAS_Desc {
        hint = .Prefer_Fast_Trace,
        shapes = {
            gpu.BVH_Mesh_Desc {
                vertex_stride = 16,
                max_vertex = vert_count - 1,
                tri_count = idx_count / 3,
            }
        }
    }
    bvh := gpu.alloc_and_create_bvh(desc)
    scratch := gpu.alloc_bvh_build_scratch_buffer(bvh_scratch_arena, desc)
    gpu.cmd_build_blas(cmd_buf, bvh, bvh.mem, scratch, { gpu.BVH_Mesh { verts = positions, indices = indices } })
    return bvh
}

build_tlas :: proc(bvh_scratch_arena: ^gpu.Arena, cmd_buf: gpu.Command_Buffer, instances: rawptr, instance_count: u32) -> gpu.Owned_BVH
{
    desc := gpu.TLAS_Desc {
        hint = .Prefer_Fast_Trace,
        instance_count = instance_count
    }
    bvh := gpu.alloc_and_create_bvh(desc)
    scratch := gpu.alloc_bvh_build_scratch_buffer(bvh_scratch_arena, desc)
    gpu.cmd_build_tlas(cmd_buf, bvh, bvh.mem, scratch, instances)
    return bvh
}

upload_bvh_instances :: proc(upload_arena: ^gpu.Arena, cmd_buf: gpu.Command_Buffer, instances: []shared.Instance, meshes: []Mesh_GPU) -> rawptr
{
    instances_staging := gpu.arena_alloc_array(upload_arena, gpu.BVH_Instance, len(instances))
    for &instance, i in instances_staging.cpu
    {
        instance = {
            transform = shared.transform_to_gpu_transform(instances[i].transform),
            blas_root = gpu.bvh_root_ptr(meshes[instances[i].mesh_idx].bvh),
            disable_culling = true,
            flip_facing = true,
            mask = 1,
        }
    }
    instances_local := gpu.mem_alloc_typed_gpu(gpu.BVH_Instance, len(instances))
    gpu.cmd_mem_copy(cmd_buf, instances_staging.gpu, instances_local, len(instances_staging.cpu) * size_of(gpu.BVH_Instance))
    return instances_local
}

Scene_GPU :: struct
{
    scene_shader: Scene_Shader,
    bvh: gpu.Owned_BVH,
    meshes: [dynamic]Mesh_GPU,
    instances_bvh: rawptr,  // Array of gpu.BVH_Instance
}

Scene_Shader :: struct
{
    instances: rawptr,
    meshes: rawptr,
}

Instance_GPU :: struct
{
    mesh_idx: u32,
}

upload_scene :: proc(scene: shared.Scene, upload_arena: ^gpu.Arena, bvh_scratch_arena: ^gpu.Arena, cmd_buf: gpu.Command_Buffer) -> Scene_GPU
{
    res: Scene_GPU

    // Upload meshes
    for mesh in scene.meshes
    {
        to_add := Mesh_GPU {
            mesh_gpu = upload_mesh(upload_arena, cmd_buf, mesh),
            idx_count = u32(len(mesh.indices)),
            vert_count = u32(len(mesh.pos)),
            bvh = {},
        }
        append(&res.meshes, to_add)
    }

    // Construct structures used by the shader
    instances_gpu := gpu.arena_alloc_array(upload_arena, Instance_GPU, len(scene.instances))
    for &instance, i in instances_gpu.cpu {
        instance = { mesh_idx = scene.instances[i].mesh_idx }
    }
    res.scene_shader.instances = gpu.mem_alloc_typed_gpu(Instance_GPU, len(scene.instances))
    gpu.cmd_mem_copy(cmd_buf, instances_gpu.gpu, res.scene_shader.instances, size_of(Instance_GPU) * len(scene.instances))

    meshes_gpu := gpu.arena_alloc_array(upload_arena, Mesh_Shader, len(scene.meshes))
    for &mesh, i in meshes_gpu.cpu {
        mesh = res.meshes[i].mesh_gpu
    }
    res.scene_shader.meshes = gpu.mem_alloc_typed_gpu(Mesh_Shader, len(scene.meshes))
    gpu.cmd_mem_copy(cmd_buf, meshes_gpu.gpu, res.scene_shader.meshes, size_of(Mesh_Shader) * len(scene.meshes))

    // Build BVHs
    gpu.cmd_barrier(cmd_buf, .Transfer, .Build_BVH)
    for &mesh in res.meshes {
        mesh.bvh = build_blas(bvh_scratch_arena, cmd_buf, mesh.mesh_gpu.pos, mesh.mesh_gpu.indices, mesh.idx_count, mesh.vert_count)
    }

    res.instances_bvh = upload_bvh_instances(upload_arena, cmd_buf, scene.instances[:], res.meshes[:])
    gpu.cmd_barrier(cmd_buf, .Transfer, .Build_BVH)

    res.bvh = build_tlas(upload_arena, cmd_buf, res.instances_bvh, u32(len(scene.instances)))
    gpu.cmd_barrier(cmd_buf, .Build_BVH, .All)

    return res
}

scene_destroy :: proc(scene: ^Scene_GPU)
{
    gpu.free_and_destroy_bvh(&scene.bvh)
    gpu.mem_free(scene.scene_shader.instances)
    gpu.mem_free(scene.scene_shader.meshes)
    gpu.mem_free(scene.instances_bvh)
    for &mesh in scene.meshes {
        mesh_destroy(&mesh)
    }
    delete(scene.meshes)
    scene^ = {}
}
