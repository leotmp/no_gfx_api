
package main

import log "core:log"
import vk "vendor:vulkan"

import "../../../gpu"

import sdl "vendor:sdl3"
import imgui "odin-imgui"
import imgui_impl_sdl3 "odin-imgui/imgui_impl_sdl3"
import imgui_impl_vulkan "odin-imgui/imgui_impl_vulkan"

Start_Window_Size_X :: 1000
Start_Window_Size_Y :: 1000
Frames_In_Flight :: 3
Example_Name :: "ImGUI"

main :: proc()
{
    ok_i := sdl.Init({ .VIDEO })
    assert(ok_i)

    console_logger := log.create_console_logger()
    defer log.destroy_console_logger(console_logger)
    context.logger = console_logger

    ts_freq := sdl.GetPerformanceFrequency()
    max_delta_time: f32 = 1.0 / 10.0

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

    Vertex :: struct { pos: [4]f32, color: [4]f32 }

    upload_arena := gpu.arena_init(1024 * 1024)
    defer gpu.arena_destroy(&upload_arena)

    verts := gpu.arena_alloc_array(&upload_arena, Vertex, 3)
    verts.cpu[0].pos = { -0.5,  0.5, 0.0, 0.0 }
    verts.cpu[1].pos = {  0.0, -0.5, 0.0, 0.0 }
    verts.cpu[2].pos = {  0.5,  0.5, 0.0, 0.0 }
    verts.cpu[0].color = { 1.0, 0.0, 0.0, 0.0 }
    verts.cpu[1].color = { 0.0, 1.0, 0.0, 0.0 }
    verts.cpu[2].color = { 0.0, 0.0, 1.0, 0.0 }

    indices := gpu.arena_alloc_array(&upload_arena, u32, 3)
    indices.cpu[0] = 0
    indices.cpu[1] = 2
    indices.cpu[2] = 1

    verts_local := gpu.mem_alloc_typed_gpu(Vertex, 3)
    indices_local := gpu.mem_alloc_typed_gpu(u32, 3)
    defer {
        gpu.mem_free(verts_local)
        gpu.mem_free(indices_local)
    }

    texture_heap := gpu.mem_alloc(size_of(gpu.Texture_Descriptor) * 65536, alloc_type = .Descriptors)
    defer gpu.mem_free(texture_heap)
    sampler_heap := gpu.mem_alloc(size_of(gpu.Sampler_Descriptor) * 10, alloc_type = .Descriptors)
    defer gpu.mem_free(sampler_heap)

    gpu.set_sampler_desc(sampler_heap, 0, gpu.sampler_descriptor({}))

    queue := gpu.Queue_Type.Main
    upload_cmd_buf := gpu.commands_begin(queue)
    gpu.cmd_mem_copy(upload_cmd_buf, verts.gpu, verts_local, 3 * size_of(Vertex))
    gpu.cmd_mem_copy(upload_cmd_buf, indices.gpu, indices_local, 3 * size_of(u32))
    gpu.cmd_barrier(upload_cmd_buf, .Transfer, .All, {})
    gpu.queue_submit(queue, { upload_cmd_buf })

    imgui_ctx := init_imgui(window)
    defer {
        imgui_impl_vulkan.shutdown()
        imgui_impl_sdl3.shutdown()
        imgui.destroy_context(imgui_ctx)
    }

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

        imgui_impl_sdl3.new_frame()
        imgui.new_frame()

        imgui.show_demo_window()

        @(static) background_color := [4]f32 { 0.45, 0.55, 0.60, 1.0 }
        if imgui.begin("Background Color", nil, {
            .Always_Auto_Resize,
        })
        {
            imgui.color_picker4("Background", &background_color, {})
            imgui.end()
        }

        imgui.render()

        swapchain := gpu.swapchain_acquire_next()

        cmd_buf := gpu.commands_begin(queue)
        gpu.cmd_begin_render_pass(cmd_buf, {
            color_attachments = {
                { texture = swapchain, clear_color = background_color }
            }
        })

        // Render triangle
        gpu.cmd_set_shaders(cmd_buf, vert_shader, frag_shader)
        textures := gpu.host_to_device_ptr(texture_heap)
        samplers := gpu.host_to_device_ptr(sampler_heap)
        gpu.cmd_set_desc_heap(cmd_buf, textures, nil, samplers, nil)
        Vert_Data :: struct {
            verts: rawptr,
        }
        verts_data := gpu.arena_alloc(frame_arena, Vert_Data)
        verts_data.cpu.verts = verts_local
        gpu.cmd_draw_indexed_instanced(cmd_buf, verts_data.gpu, nil, indices_local, 3, 1)

        // Render ImGui on top
        draw_data := imgui.get_draw_data()
        if draw_data != nil && draw_data.cmd_lists_count > 0 {
            vk_cmd_buf := gpu.get_vulkan_command_buffer(cmd_buf)
            imgui_impl_vulkan.render_draw_data(draw_data, vk_cmd_buf)
        }

        gpu.cmd_end_render_pass(cmd_buf)
        gpu.queue_submit(queue, { cmd_buf }, frame_sem, next_frame)

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
        imgui_impl_sdl3.process_event(&event)

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

init_imgui :: proc(window: ^sdl.Window) -> ^imgui.Context
{
    imgui.CHECKVERSION()
    ctx := imgui.create_context(nil)
    io := imgui.get_io()
    io.config_flags += {.Nav_Enable_Keyboard, .Nav_Enable_Gamepad}
    io.display_size = {Start_Window_Size_X, Start_Window_Size_Y}

    imgui_impl_sdl3.init_for_vulkan(window)

    queue := gpu.Queue_Type.Main

    vk_instance := gpu.get_vulkan_instance()
    vk_physical_device := gpu.get_vulkan_physical_device()
    vk_device := gpu.get_vulkan_device()
    vk_queue := gpu.get_vulkan_queue(queue)
    vk_queue_family := gpu.get_vulkan_queue_family(queue)
    swapchain_image_count := gpu.get_swapchain_image_count()

    imgui_vk_init_info: imgui_impl_vulkan.Init_Info = {}
    color_format := vk.Format.B8G8R8A8_UNORM

    imgui_vk_init_info.api_version = vk.API_VERSION_1_3
    imgui_vk_init_info.instance = vk_instance
    imgui_vk_init_info.physical_device = vk_physical_device
    imgui_vk_init_info.device = vk_device
    imgui_vk_init_info.queue_family = vk_queue_family
    imgui_vk_init_info.queue = vk_queue
    imgui_vk_init_info.descriptor_pool = {}
    imgui_vk_init_info.render_pass = {}
    imgui_vk_init_info.min_image_count = 2
    imgui_vk_init_info.image_count = swapchain_image_count
    imgui_vk_init_info.msaa_samples = {}
    imgui_vk_init_info.pipeline_cache = {}
    imgui_vk_init_info.subpass = 0
    imgui_vk_init_info.descriptor_pool_size = 1000
    imgui_vk_init_info.use_dynamic_rendering = true
    imgui_vk_init_info.pipeline_rendering_create_info = {
        sType = .PIPELINE_RENDERING_CREATE_INFO_KHR,
        colorAttachmentCount = 1,
        pColorAttachmentFormats = &color_format,
    }
    imgui_vk_init_info.allocator = nil
    imgui_vk_init_info.check_vk_result_fn = nil
    imgui_vk_init_info.min_allocation_size = 1024 * 1024

    vk_loader_func :: proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
        instance := cast(vk.Instance) user_data
        return vk.GetInstanceProcAddr(instance, function_name)
    }
    load_result := imgui_impl_vulkan.load_functions(vk.API_VERSION_1_3, vk_loader_func, cast(rawptr) vk_instance)
    assert(load_result, "Failed to load Vulkan functions for imgui")

    result := imgui_impl_vulkan.init(&imgui_vk_init_info)
    assert(result, "Failed to initialize imgui vulkan backend")

    imgui_impl_vulkan.create_fonts_texture()

    return ctx
}
