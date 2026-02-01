
package main

import log "core:log"
import "core:image"
import "core:image/png"
import "base:runtime"
import "core:math"

import "../../gpu"

import sdl "vendor:sdl3"

Start_Window_Size_X :: 1000
Start_Window_Size_Y :: 1000
Frames_In_Flight :: 3
Example_Name :: "Textures"

Peach_Texture :: #load("textures/peach.png")
Bowser_Texture :: #load("textures/bowser.png")

main :: proc()
{
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

    gpu.swapchain_init_from_sdl(window, Frames_In_Flight)

    vert_shader := gpu.shader_create(#load("shaders/test.vert.spv", []u32), .Vertex)
    frag_shader := gpu.shader_create(#load("shaders/test.frag.spv", []u32), .Fragment)
    defer {
        gpu.shader_destroy(vert_shader)
        gpu.shader_destroy(frag_shader)
    }

    texture_heap := gpu.mem_alloc(size_of(gpu.Texture_Descriptor) * 65536, alloc_type = .Descriptors)
    defer gpu.mem_free(texture_heap)
    sampler_heap := gpu.mem_alloc(size_of(gpu.Sampler_Descriptor) * 10, alloc_type = .Descriptors)
    defer gpu.mem_free(sampler_heap)

    Vertex :: struct { pos: [3]f32, uv: [2]f32 }

    arena := gpu.arena_init(1024 * 1024)
    defer gpu.arena_destroy(&arena)

    verts := gpu.arena_alloc_array(&arena, Vertex, 4)
    verts.cpu[0].pos = { -0.5,  0.5, 0.0 }
    verts.cpu[1].pos = {  0.5, -0.5, 0.0 }
    verts.cpu[2].pos = {  0.5,  0.5, 0.0 }
    verts.cpu[3].pos = { -0.5, -0.5, 0.0 }
    verts.cpu[0].uv  = {  0.0,  1.0 }
    verts.cpu[1].uv  = {  1.0,  0.0 }
    verts.cpu[2].uv  = {  1.0,  1.0 }
    verts.cpu[3].uv  = {  0.0,  0.0 }

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

    upload_arena := gpu.arena_init(10 * 1024 * 1024)
    defer gpu.arena_destroy(&upload_arena)

    peach_tex := load_texture(Peach_Texture, &upload_arena, upload_cmd_buf)
    bowser_tex := load_texture(Bowser_Texture, &upload_arena, upload_cmd_buf)
    defer {
        gpu.free_and_destroy_texture(&peach_tex)
        gpu.free_and_destroy_texture(&bowser_tex)
    }
    gpu.cmd_mem_copy(upload_cmd_buf, verts.gpu, verts_local, u64(len(verts.cpu)) * size_of(verts.cpu[0]))
    gpu.cmd_mem_copy(upload_cmd_buf, indices.gpu, indices_local, u64(len(indices.cpu)) * size_of(indices.cpu[0]))
    gpu.cmd_barrier(upload_cmd_buf, .Transfer, .All, {})

    gpu.queue_submit(queue, { upload_cmd_buf })

    gpu.set_texture_desc(texture_heap, 0, gpu.texture_view_descriptor(bowser_tex, { format = .RGBA8_Unorm }))
    gpu.set_texture_desc(texture_heap, 1, gpu.texture_view_descriptor(peach_tex, { format = .RGBA8_Unorm }))
    gpu.set_sampler_desc(sampler_heap, 0, gpu.sampler_descriptor({}))

    now_ts := sdl.GetPerformanceCounter()

    frame_arenas: [Frames_In_Flight]gpu.Arena
    for &frame_arena in frame_arenas do frame_arena = gpu.arena_init(1024 * 1024)
    defer for &frame_arena in frame_arenas do gpu.arena_destroy(&frame_arena)
    next_frame := u64(1)
    frame_sem := gpu.semaphore_create(0)
    defer gpu.semaphore_destroy(&frame_sem)
    for true
    {
        proceed := handle_window_events(window)
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
        if old_window_size_x != window_size_x || old_window_size_y != window_size_y {
            gpu.swapchain_resize({ u32(max(0, window_size_x)), u32(max(0, window_size_y)) })
        }

        last_ts := now_ts
        now_ts = sdl.GetPerformanceCounter()
        delta_time := min(max_delta_time, f32(f64((now_ts - last_ts)*1000) / f64(ts_freq)) / 1000.0)

        frame_arena := &frame_arenas[next_frame % Frames_In_Flight]

        swapchain := gpu.swapchain_acquire_next()  // Blocks CPU until at least one frame is available.

        cmd_buf := gpu.commands_begin(queue)
        gpu.cmd_begin_render_pass(cmd_buf, {
            color_attachments = {
                { texture = swapchain, clear_color = { 0.7, 0.7, 0.7, 1.0 } }
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
            texture_a: u32,
            texture_b: u32,
            sampler: u32,
            fade: f32
        }
        frag_data := gpu.arena_alloc(frame_arena, Frag_Data)
        frag_data.cpu.texture_a = 0
        frag_data.cpu.texture_b = 1
        frag_data.cpu.sampler = 0
        frag_data.cpu.fade = changing_fade(delta_time)

        gpu.cmd_draw_indexed_instanced(cmd_buf, verts_data.gpu, frag_data.gpu, indices_local, u32(len(indices.cpu)), 1)
        gpu.cmd_end_render_pass(cmd_buf)
        gpu.cmd_add_signal_semaphore(cmd_buf, frame_sem, next_frame)
        gpu.queue_submit(queue, { cmd_buf })

        gpu.swapchain_present(queue, frame_sem, next_frame)
        next_frame += 1

        gpu.arena_free_all(frame_arena)
    }

    gpu.wait_idle()
}

handle_window_events :: proc(window: ^sdl.Window) -> (proceed: bool)
{
    event: sdl.Event
    proceed = true
    for sdl.PollEvent(&event)
    {
        #partial switch event.type
        {
            case .QUIT:
                proceed = false
            case .WINDOW_CLOSE_REQUESTED:
            {
                if event.window.windowID == sdl.GetWindowID(window) {
                    proceed = false
                }
            }
        }
    }

    return
}

load_texture :: proc(bytes: []byte, upload_arena: ^gpu.Arena, cmd_buf: gpu.Command_Buffer) -> gpu.Owned_Texture
{
    options := image.Options {
        .alpha_add_if_missing,
    }
    img, err := image.load_from_bytes(bytes, options)
    ensure(err == nil, "Could not load texture.")
    defer image.destroy(img)

    staging, staging_gpu := gpu.arena_alloc_untyped(upload_arena, u64(len(img.pixels.buf)))
    runtime.mem_copy(staging, raw_data(img.pixels.buf), len(img.pixels.buf))

    texture := gpu.alloc_and_create_texture({
        type = .D2,
        dimensions = { u32(img.width), u32(img.height), 1 },
        mip_count = 1,
        layer_count = 1,
        sample_count = 1,
        format = .RGBA8_Unorm,
        usage = { .Sampled },
    })
    gpu.cmd_copy_to_texture(cmd_buf, texture, staging_gpu, texture.mem)
    return texture
}

// To get around the fact that I need to import "core:image/png" to load pngs,
// but then -vet complains because it's not used.
@(private="file")
_fictitious :: proc() -> png.Error { return {} }

changing_fade :: proc(delta_time: f32) -> f32
{
    @(static) t: f32
    t = math.mod(t + delta_time * 1.7, math.PI * 2)
    return math.sin(t) * 0.5 + 0.5
}
