
#+vet !unused-imports

package main

import log "core:log"
import "core:image"
import "core:image/png"
import "core:math"
import "core:math/linalg"
import "core:fmt"
import intr "base:intrinsics"

import "../../gpu"
import sdl "vendor:sdl3"

import shared "../shared"

Start_Window_Size_X :: 1000
Start_Window_Size_Y :: 1000
Frames_In_Flight :: 3
Example_Name :: "Textures (Advanced)"

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

    ok := gpu.init()
    ensure(ok)
    defer gpu.cleanup()

    gpu.swapchain_init_from_sdl(window, Frames_In_Flight)

    depth_desc := gpu.Texture_Desc {
        dimensions = { u32(window_size_x), u32(window_size_y), 1 },
        format = .D32_Float,
        usage = { .Depth_Stencil_Attachment },
    }
    depth_texture := gpu.texture_alloc_and_create(depth_desc)
    defer gpu.texture_free_and_destroy(&depth_texture)

    sky_vert_shader := gpu.shader_create(#load("shaders/shader.vert.spv", []u32), .Vertex)
    sky_frag_shader := gpu.shader_create(#load("shaders/shader.frag.spv", []u32), .Fragment)
    defer {
        gpu.shader_destroy(sky_vert_shader)
        gpu.shader_destroy(sky_frag_shader)
    }

    cloud_vert_shader := gpu.shader_create(#load("shaders/cloud.vert.spv", []u32), .Vertex)
    cloud_frag_shader := gpu.shader_create(#load("shaders/cloud.frag.spv", []u32), .Fragment)
    defer {
        gpu.shader_destroy(cloud_vert_shader)
        gpu.shader_destroy(cloud_frag_shader)
    }

    desc_pool := gpu.desc_pool_create()
    defer gpu.desc_pool_destroy(&desc_pool)

    upload_arena := gpu.arena_init()
    defer gpu.arena_destroy(&upload_arena)

    upload_cmd_buf := gpu.commands_begin(.Main)

    sky_cubemap := build_sky_cubemap(&upload_arena, upload_cmd_buf)
    defer gpu.texture_free_and_destroy(&sky_cubemap)

    sky_verts, sky_indices := build_sky_mesh(&upload_arena, upload_cmd_buf)
    defer {
        gpu.mem_free(sky_verts)
        gpu.mem_free(sky_indices)
    }

    gpu.cmd_barrier(upload_cmd_buf, .Transfer, .All, {})
    gpu.queue_submit(.Main, { upload_cmd_buf })

    sky_cubemap_id := gpu.desc_pool_alloc_texture(&desc_pool, gpu.texture_view_descriptor(sky_cubemap, {}))
    linear_sampler_id := gpu.desc_pool_alloc_sampler(&desc_pool, gpu.sampler_descriptor({}))

    now_ts := sdl.GetPerformanceCounter()

    frame_arenas: [Frames_In_Flight]gpu.Arena
    for &frame_arena in frame_arenas do frame_arena = gpu.arena_init()
    defer for &frame_arena in frame_arenas do gpu.arena_destroy(&frame_arena)
    next_frame := u64(1)
    frame_sem := gpu.semaphore_create(0)
    defer gpu.semaphore_destroy(frame_sem)
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
            gpu.queue_wait_idle(.Main)
            gpu.swapchain_resize({ u32(max(0, window_size_x)), u32(max(0, window_size_y)) })
            depth_desc.dimensions.x = u32(window_size_x)
            depth_desc.dimensions.y = u32(window_size_y)
            gpu.texture_free_and_destroy(&depth_texture)
            depth_texture = gpu.texture_alloc_and_create(depth_desc)
        }

        swapchain := gpu.swapchain_acquire_next()  // Blocks CPU until at least one frame is available.

        frame_arena := &frame_arenas[next_frame % Frames_In_Flight]
        gpu.arena_free_all(frame_arena)

        last_ts := now_ts
        now_ts = sdl.GetPerformanceCounter()
        delta_time := min(max_delta_time, f32(f64((now_ts - last_ts)*1000) / f64(ts_freq)) / 1000.0)

        world_to_view := shared.first_person_camera_view(delta_time)
        aspect_ratio := f32(window_size_x) / f32(window_size_y)
        view_to_proj := linalg.matrix4_perspective_f32(math.RAD_PER_DEG * 59.0, aspect_ratio, 0.1, 1000.0, false)

        cmd_buf := gpu.commands_begin(.Main)
        gpu.cmd_begin_render_pass(cmd_buf, {
            color_attachments = {
                { texture = swapchain, clear_color = { 0.7, 0.7, 0.7, 1.0 } }
            },
            depth_attachment = gpu.Render_Attachment {
                texture = depth_texture, clear_color = 1.0
            },
        })

        gpu.cmd_set_desc_heap(cmd_buf, desc_pool)

        // Draw skysphere
        {
            gpu.cmd_set_shaders(cmd_buf, sky_vert_shader, sky_frag_shader)
            gpu.cmd_set_depth_state(cmd_buf, { compare = .Always })
            // Render the skysphere inside out
            gpu.cmd_set_raster_state(cmd_buf, { cull_mode = .Cull_CCW })

            Vert_Data :: struct #all_or_none {
                positions: rawptr,
                model_to_world: [16]f32,
                model_to_world_normal: [16]f32,
                world_to_view: [16]f32,
                view_to_proj: [16]f32,
            }
            verts_data := gpu.arena_alloc(frame_arena, Vert_Data)
            verts_data.cpu^ = {
                positions = sky_verts.gpu.ptr,
                model_to_world = intr.matrix_flatten(cast(matrix[4, 4]f32) 1),
                model_to_world_normal = intr.matrix_flatten(cast(matrix[4, 4]f32) 1),
                world_to_view = intr.matrix_flatten(world_to_view),
                view_to_proj = intr.matrix_flatten(view_to_proj),
            }

            Frag_Data :: struct #all_or_none {
                sky_texture: u32,
                sky_sampler: u32,
            }
            frag_data := gpu.arena_alloc(frame_arena, Frag_Data)
            frag_data.cpu^ = {
                sky_texture = sky_cubemap_id,
                sky_sampler = linear_sampler_id,
            }

            gpu.cmd_draw_indexed(cmd_buf, verts_data, frag_data, sky_indices)
        }

        // Draw cloud
        {
            gpu.cmd_set_shaders(cmd_buf, cloud_vert_shader, cloud_frag_shader)
            gpu.cmd_set_depth_state(cmd_buf, { mode = { .Read, .Write }, compare = .Less })
            gpu.cmd_set_raster_state(cmd_buf, { cull_mode = .Cull_CW })

            Vert_Data :: struct #all_or_none {
                positions: rawptr,
                model_to_world: [16]f32,
                model_to_world_normal: [16]f32,
                world_to_view: [16]f32,
                view_to_proj: [16]f32,
            }
            verts_data := gpu.arena_alloc(frame_arena, Vert_Data)
            verts_data.cpu^ = {
                positions = sky_verts.gpu.ptr,
                model_to_world = intr.matrix_flatten(cast(matrix[4, 4]f32) 1),
                model_to_world_normal = intr.matrix_flatten(cast(matrix[4, 4]f32) 1),
                world_to_view = intr.matrix_flatten(world_to_view),
                view_to_proj = intr.matrix_flatten(view_to_proj),
            }

            gpu.cmd_draw_indexed(cmd_buf, verts_data, {}, sky_indices)
        }

        gpu.cmd_end_render_pass(cmd_buf)
        gpu.cmd_add_signal_semaphore(cmd_buf, frame_sem, next_frame)
        gpu.queue_submit(.Main, { cmd_buf })

        gpu.swapchain_present(.Main, frame_sem, next_frame)
        next_frame += 1
    }

    gpu.wait_idle()
}

build_sky_mesh :: proc(upload_arena: ^gpu.Arena, cmd_buf: gpu.Command_Buffer) -> (gpu.slice_t([3]f32), gpu.slice_t(u32))
{
    verts, indices := shared.build_sphere()
    defer {
        delete(verts)
        delete(indices)
    }

    verts_staging := gpu.arena_alloc(upload_arena, [3]f32, len(verts))
    indices_staging := gpu.arena_alloc(upload_arena, u32, len(indices))
    copy(verts_staging.cpu, verts[:])
    copy(indices_staging.cpu, indices[:])

    verts_local := gpu.mem_alloc([3]f32, len(verts))
    indices_local := gpu.mem_alloc(u32, len(indices))
    gpu.cmd_mem_copy(cmd_buf, verts_local, verts_staging)
    gpu.cmd_mem_copy(cmd_buf, indices_local, indices_staging)
    return verts_local, indices_local
}

Sky_Textures: [gpu.Cubemap_Side][]u8 = {
    .PX = #load("textures/px.png"),
    .NX = #load("textures/nx.png"),
    .PY = #load("textures/py.png"),
    .NY = #load("textures/ny.png"),
    .PZ = #load("textures/pz.png"),
    .NZ = #load("textures/nz.png"),
}
build_sky_cubemap :: proc(upload_arena: ^gpu.Arena, cmd_buf: gpu.Command_Buffer) -> gpu.Owned_Texture
{
    texture: gpu.Owned_Texture

    for side in gpu.Cubemap_Side
    {
        options := image.Options {
            .alpha_add_if_missing,
        }
        img, err := image.load_from_bytes(Sky_Textures[side], options)
        ensure(err == nil, "Could not load texture.")
        defer image.destroy(img)

        if texture == {}
        {
            texture = gpu.texture_alloc_and_create({
                type = .Cube,
                dimensions = { u32(img.width), u32(img.height), 1 },
                format = .RGBA8_Unorm,
                usage = { .Sampled },
                layer_count = 6,
            })
        }

        staging := gpu.arena_alloc(upload_arena, u8, len(img.pixels.buf))
        copy(staging.cpu, img.pixels.buf[:])
        gpu.cmd_copy_to_texture(cmd_buf, texture, staging, region = { base_layer = u32(side) })
    }
    return texture
}
