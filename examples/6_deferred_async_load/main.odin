// This example demonstrates:
// - Using multiple render targets to render the G-buffer and passing them to the final pass shader as textures
// - Using multiple render passes
// - glTF texture loading and using textures for rendering
// - Asynchronous texture loading by rendering a default texture and swapping it out for the actual textures once loaded
// - Multithreaded texture loading

package main

import "../../gpu"
import intr "base:intrinsics"
import "base:runtime"
import "core:container/queue"
import "core:fmt"
import "core:image"
import log "core:log"
import "core:math"
import "core:math/linalg"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:sys/info"

import sdl "vendor:sdl3"

import shared "../shared"
import gltf2 "../shared/gltf2"

Start_Window_Size_X :: 1000
Start_Window_Size_Y :: 1000
Frames_In_Flight :: 3
Example_Name_Format :: "Right-click + WASD for first-person controls. Left click to toggle texture type. Current: %v"

Sponza_Scene :: #load("../shared/assets/sponza.glb")

// Whether to load textures in parallel in the background or preload them in main thread before running the screne
Load_Textures_Async :: true
Num_Async_Worker_Threads := clamp(info.cpu.logical_cores - 1, 2, 6)

// How many textures to load in a single batch / command buffer
Loader_Chunk_Size :: 16

// Use CPU block-compressed mip generation instead of GPU mipmaps.
Compress_Textures :: false

// G-buffer texture indices in texture heap
GBUFFER_ALBEDO_IDX :: 1000
GBUFFER_NORMAL_IDX :: 1001
GBUFFER_METALLIC_ROUGHNESS_IDX :: 1002

// G-buffer texture type for toggling display
GBuffer_Texture_Type :: enum u32 {
	Albedo             = 0,
	Normal             = 1,
	Metallic_Roughness = 2,
}

// Currently selected gbuffer texture type to display
selected_texture_type: GBuffer_Texture_Type = .Albedo

// Textures can be loaded/unloaded on different threads, so we need to synchronize access to loaded_textures, image_to_texture and image_uploaded
mutex: sync.Mutex
// Every texture from loaded_textures array needs to be freed when we are done
loaded_textures: [dynamic]gpu.Owned_Texture
// Enables asynchronous cancellation of texture loading
cancel_loading_textures: bool
next_texture_idx: u32 = shared.MISSING_TEXTURE_ID + 1
// Cache for image_index -> texture mapping, reused across texture loading chunks
image_to_texture: map[int]struct {
	texture:     gpu.Owned_Texture,
	texture_idx: u32,
    upload_completed_semaphore_value: u64,
}
image_uploaded: map[int]^sync.One_Shot_Event
texture_upload_semaphore: gpu.Semaphore
texture_upload_semaphore_value: u64

main :: proc() {
	ok_i := sdl.Init({.VIDEO})
	assert(ok_i)

	console_logger := log.create_console_logger()
	defer log.destroy_console_logger(console_logger)
	context.logger = console_logger

	ts_freq := sdl.GetPerformanceFrequency()
	max_delta_time: f32 = 1.0 / 10.0 // 10fps

	window_flags :: sdl.WindowFlags{.HIGH_PIXEL_DENSITY, .VULKAN, .RESIZABLE}
	window_title := strings.clone_to_cstring(
		fmt.tprintf(Example_Name_Format, selected_texture_type),
	)
	defer delete(window_title)
	window := sdl.CreateWindow(
		window_title,
		Start_Window_Size_X,
		Start_Window_Size_Y,
		window_flags,
	)
	ensure(window != nil)

	window_size_x := i32(Start_Window_Size_X)
	window_size_y := i32(Start_Window_Size_Y)

	gpu.init()
	defer gpu.cleanup()

	gpu.swapchain_init_from_sdl(window, Frames_In_Flight)

	vert_shader_gbuffer := gpu.shader_create(#load("shaders/gbuffer.vert.spv", []u32), .Vertex)
	frag_shader_gbuffer := gpu.shader_create(#load("shaders/gbuffer.frag.spv", []u32), .Fragment)
	defer {
		gpu.shader_destroy(vert_shader_gbuffer)
		gpu.shader_destroy(frag_shader_gbuffer)
	}

	vert_shader_final := gpu.shader_create(#load("shaders/final_pass.vert.spv", []u32), .Vertex)
	frag_shader_final := gpu.shader_create(#load("shaders/final_pass.frag.spv", []u32), .Fragment)
	defer {
		gpu.shader_destroy(vert_shader_final)
		gpu.shader_destroy(frag_shader_final)
	}

	upload_arena := gpu.arena_init(128 * 1024 * 1024)
	defer gpu.arena_destroy(&upload_arena)

    texture_upload_semaphore = gpu.semaphore_create(texture_upload_semaphore_value)
    defer gpu.semaphore_destroy(&texture_upload_semaphore)

	queue := gpu.Queue_Type.Main
	upload_cmd_buf := gpu.commands_begin(queue)

	full_screen_quad_verts_gpu, full_screen_quad_indices_gpu := create_fullscreen_quad(
		&upload_arena,
		upload_cmd_buf,
	)
	defer {
		gpu.mem_free(full_screen_quad_verts_gpu)
		gpu.mem_free(full_screen_quad_indices_gpu)
	}

	// Set up texture heap
	texture_heap := gpu.mem_alloc(
		size_of(gpu.Texture_Descriptor) * 2048,
		alloc_type = .Descriptors,
	)
	defer gpu.mem_free(texture_heap)
	sampler_heap := gpu.mem_alloc(size_of(gpu.Sampler_Descriptor) * 10, alloc_type = .Descriptors)
	defer gpu.mem_free(sampler_heap)

	// Set up read-write texture heap for G-buffer textures
	texture_rw_heap_size := gpu.get_texture_rw_view_descriptor_size()
	texture_rw_heap := gpu.mem_alloc(u64(texture_rw_heap_size) * 2048, alloc_type = .Descriptors)
	defer gpu.mem_free(texture_rw_heap)

	magenta_texture := create_magenta_texture(&upload_arena, upload_cmd_buf, texture_heap)
	defer gpu.free_and_destroy_texture(&magenta_texture)

	scene, texture_infos, gltf_data := shared.load_scene_gltf(Sponza_Scene)
	defer {
		shared.destroy_scene(&scene)
		gltf2.unload(gltf_data)
	}

	// Upload meshes
	meshes_gpu: [dynamic]Mesh_GPU
	defer {
		for &mesh_gpu in meshes_gpu do mesh_destroy(&mesh_gpu)
		delete(meshes_gpu)
	}

	for mesh in scene.meshes {
		append(&meshes_gpu, upload_mesh(&upload_arena, upload_cmd_buf, mesh))
	}

	defer {
		// Clean up loaded textures
		sync.guard(&mutex)
		for &tex in loaded_textures {
			gpu.free_and_destroy_texture(&tex)
		}
	}

	when Load_Textures_Async {
		worker_threads: [dynamic]^thread.Thread
		defer {
			cancel_loading_textures = true
			for t in worker_threads {
				thread.terminate(t, 0)
			}
		}

		Texture_Loader_Data :: struct {
			texture_infos: []shared.Gltf_Texture_Info,
			gltf_data:     ^gltf2.Data,
			scene:         ^shared.Scene,
			texture_heap:  rawptr,
			logger:        log.Logger,
			current_chunk: ^int,
		}
		loader_data := Texture_Loader_Data {
			texture_infos = texture_infos,
			gltf_data     = gltf_data,
			scene         = &scene,
			texture_heap  = texture_heap,
			logger        = console_logger,
			current_chunk = new(int),
		}

		texture_loader_thread_proc :: proc(thread: ^thread.Thread) {
			data := cast(^Texture_Loader_Data)thread.data
			context.logger = data.logger

			for !cancel_loading_textures {
				current_chunk_start := sync.atomic_add(data.current_chunk, Loader_Chunk_Size)
				current_chunk_end := min(current_chunk_start + Loader_Chunk_Size, len(data.texture_infos))

				if current_chunk_start >= len(data.texture_infos) {
					break
				}

				log.debug(
					fmt.tprintf("Creating texture loader for chunk %v of %v", current_chunk_start, len(data.texture_infos)),
				)

				load_scene_textures_from_gltf(
					data.texture_infos[current_chunk_start:current_chunk_end],
					data.gltf_data,
					data.scene,
					data.texture_heap,
				)
			}
		}

		for i := 0; i < Num_Async_Worker_Threads; i += 1 {
			texture_loader_thread := thread.create(texture_loader_thread_proc)
			texture_loader_thread.data = &loader_data
			thread.start(texture_loader_thread)
			append(&worker_threads, texture_loader_thread)
		}
	} else {
		for i := 0; i < len(texture_infos); i += Loader_Chunk_Size {
			end := min(i + Loader_Chunk_Size, len(texture_infos))
			chunk := texture_infos[i:end]
			load_scene_textures_from_gltf(chunk, gltf_data, &scene, texture_heap)
		}
	}

	gpu.set_sampler_desc(
		sampler_heap,
		0,
		gpu.sampler_descriptor({ max_anisotropy = min(16.0, gpu.device_limits().max_anisotropy) }),
	)


	gbuffer_albedo, gbuffer_normal, gbuffer_metallic_roughness, depth_texture :=
		create_gbuffer_textures(
			u32(window_size_x),
			u32(window_size_y),
			texture_heap,
			texture_rw_heap,
		)
	defer {
		gpu.free_and_destroy_texture(&gbuffer_albedo)
		gpu.free_and_destroy_texture(&gbuffer_normal)
		gpu.free_and_destroy_texture(&gbuffer_metallic_roughness)
		gpu.free_and_destroy_texture(&depth_texture)
	}

	gpu.cmd_barrier(upload_cmd_buf, .Transfer, .All, {})
	gpu.queue_submit(queue, {upload_cmd_buf})

	now_ts := sdl.GetPerformanceCounter()

	frame_arenas: [Frames_In_Flight]gpu.Arena
	for &frame_arena in frame_arenas do frame_arena = gpu.arena_init(10 * 1024 * 1024)
	defer for &frame_arena in frame_arenas do gpu.arena_destroy(&frame_arena)
	next_frame := u64(1)
	frame_sem := gpu.semaphore_create(0)
	defer gpu.semaphore_destroy(&frame_sem)
	for true {
		proceed := shared.handle_window_events(window)
		if !proceed do break

		// Toggle gbuffer texture type on left mouse button click
		if shared.INPUT.left_click_pressed {
			selected_texture_type = GBuffer_Texture_Type((u32(selected_texture_type) + 1) % 3)
			title := strings.clone_to_cstring(
				fmt.tprintf(Example_Name_Format, selected_texture_type),
			)
			sdl.SetWindowTitle(window, title)
			delete(title)
		}

		old_window_size_x := window_size_x
		old_window_size_y := window_size_y
		sdl.GetWindowSize(window, &window_size_x, &window_size_y)
		if .MINIMIZED in sdl.GetWindowFlags(window) || window_size_x <= 0 || window_size_y <= 0 {
			sdl.Delay(16)
			continue
		}

		if next_frame > Frames_In_Flight {
			gpu.semaphore_wait(frame_sem, next_frame - Frames_In_Flight)
		}
		if old_window_size_x != window_size_x || old_window_size_y != window_size_y {
			gpu.queue_wait_idle(queue)
			gpu.swapchain_resize({u32(max(0, window_size_x)), u32(max(0, window_size_y))})

			gpu.free_and_destroy_texture(&gbuffer_albedo)
			gpu.free_and_destroy_texture(&gbuffer_normal)
			gpu.free_and_destroy_texture(&gbuffer_metallic_roughness)
			gpu.free_and_destroy_texture(&depth_texture)
			gbuffer_albedo, gbuffer_normal, gbuffer_metallic_roughness, depth_texture =
				create_gbuffer_textures(
					u32(window_size_x),
					u32(window_size_y),
					texture_heap,
					texture_rw_heap,
				)
		}

		last_ts := now_ts
		now_ts = sdl.GetPerformanceCounter()
		delta_time := min(
			max_delta_time,
			f32(f64((now_ts - last_ts) * 1000) / f64(ts_freq)) / 1000.0,
		)

		world_to_view := shared.first_person_camera_view(delta_time)
		aspect_ratio := f32(window_size_x) / f32(window_size_y)
		view_to_proj := linalg.matrix4_perspective_f32(
			math.RAD_PER_DEG * 59.0,
			aspect_ratio,
			0.1,
			1000.0,
			false,
		)

		frame_arena := &frame_arenas[next_frame % Frames_In_Flight]

		swapchain := gpu.swapchain_acquire_next() // Blocks CPU until at least one frame is available.

		cmd_buf := gpu.commands_begin(queue)

		// G-buffer pass: render geometry to multiple color attachments
		render_pass_gbuffer(
			cmd_buf,
			gbuffer_albedo,
			gbuffer_normal,
			gbuffer_metallic_roughness,
			depth_texture,
			vert_shader_gbuffer,
			frag_shader_gbuffer,
			texture_heap,
			texture_rw_heap,
			sampler_heap,
			frame_arena,
			&scene,
			meshes_gpu[:],
			world_to_view,
			view_to_proj,
		)

		// Final pass: composite from G-buffer
		render_pass_final(
			cmd_buf,
			swapchain,
			gbuffer_albedo,
			gbuffer_normal,
			gbuffer_metallic_roughness,
			vert_shader_final,
			frag_shader_final,
			texture_heap,
			texture_rw_heap,
			sampler_heap,
			frame_arena,
			full_screen_quad_verts_gpu,
			full_screen_quad_indices_gpu,
		)

		gpu.cmd_add_signal_semaphore(cmd_buf, frame_sem, next_frame)
		gpu.queue_submit(queue, {cmd_buf})

		gpu.swapchain_present(queue, frame_sem, next_frame)
		next_frame += 1

		gpu.arena_free_all(frame_arena)
	}

	gpu.wait_idle()
}

render_pass_gbuffer :: proc(
	cmd_buf: gpu.Command_Buffer,
	gbuffer_albedo: gpu.Texture,
	gbuffer_normal: gpu.Texture,
	gbuffer_metallic_roughness: gpu.Texture,
	depth_texture: gpu.Texture,
	vert_shader: gpu.Shader,
	frag_shader: gpu.Shader,
	texture_heap: rawptr,
	texture_rw_heap: rawptr,
	sampler_heap: rawptr,
	frame_arena: ^gpu.Arena,
	scene: ^shared.Scene,
	meshes_gpu: []Mesh_GPU,
	world_to_view: matrix[4, 4]f32,
	view_to_proj: matrix[4, 4]f32,
) {
	gpu.cmd_begin_render_pass(
		cmd_buf,
		{
			color_attachments = {
				{texture = gbuffer_albedo, clear_color = {0.0, 0.0, 0.0, 1.0}},
				{texture = gbuffer_normal, clear_color = {0.5, 0.5, 1.0, 1.0}},
				{texture = gbuffer_metallic_roughness, clear_color = {0.0, 0.0, 0.0, 1.0}},
			},
			depth_attachment = gpu.Render_Attachment{texture = depth_texture, clear_color = 1.0},
		},
	)
	gpu.cmd_set_shaders(cmd_buf, vert_shader, frag_shader)

	// Set texture and sampler heaps
	textures_ptr := gpu.host_to_device_ptr(texture_heap)
	textures_rw_ptr := gpu.host_to_device_ptr(texture_rw_heap)
	samplers_ptr := gpu.host_to_device_ptr(sampler_heap)
	gpu.cmd_set_desc_heap(cmd_buf, textures_ptr, textures_rw_ptr, samplers_ptr, nil)

	gpu.cmd_set_depth_state(cmd_buf, {mode = {.Read, .Write}, compare = .Less})

	for instance in scene.instances {
		mesh := meshes_gpu[instance.mesh_idx]
		base_color_map := scene.meshes[instance.mesh_idx].base_color_map
		metallic_roughness_map := scene.meshes[instance.mesh_idx].metallic_roughness_map
		normal_map := scene.meshes[instance.mesh_idx].normal_map

		Vert_Data :: struct #all_or_none {
			positions:             rawptr,
			normals:               rawptr,
			uvs:                   rawptr,
			model_to_world:        [16]f32,
			model_to_world_normal: [16]f32,
			world_to_view:         [16]f32,
			view_to_proj:          [16]f32,
		}
		#assert(size_of(Vert_Data) == 8 + 8 + 8 + 64 + 64 + 64 + 64)
		verts_data := gpu.arena_alloc(frame_arena, Vert_Data)
		verts_data.cpu^ = {
			positions             = mesh.pos,
			normals               = mesh.normals,
			uvs                   = mesh.uvs,
			model_to_world        = intr.matrix_flatten(instance.transform),
			model_to_world_normal = intr.matrix_flatten(
				linalg.transpose(linalg.inverse(instance.transform)),
			),
			world_to_view         = intr.matrix_flatten(world_to_view),
			view_to_proj          = intr.matrix_flatten(view_to_proj),
		}

		Frag_Data :: struct #all_or_none {
			base_color_map:                 u32,
			base_color_map_sampler:         u32,
			metallic_roughness_map:         u32,
			metallic_roughness_map_sampler: u32,
			normal_map:                     u32,
			normal_map_sampler:             u32,
		}
		frag_data := gpu.arena_alloc(frame_arena, Frag_Data)
		frag_data.cpu^ = {
			base_color_map                 = base_color_map,
			base_color_map_sampler         = 0,
			metallic_roughness_map         = metallic_roughness_map,
			metallic_roughness_map_sampler = 0,
			normal_map                     = normal_map,
			normal_map_sampler             = 0,
		}

		gpu.cmd_draw_indexed_instanced(
			cmd_buf,
			verts_data.gpu,
			frag_data.gpu,
			mesh.indices,
			mesh.idx_count,
			1,
		)
	}

	gpu.cmd_end_render_pass(cmd_buf)
	// Barrier to ensure G-buffer textures are ready for sampling in next pass
	gpu.cmd_barrier(cmd_buf, .Raster_Color_Out, .Fragment_Shader, {})
}

render_pass_final :: proc(
	cmd_buf: gpu.Command_Buffer,
	swapchain: gpu.Texture,
	gbuffer_albedo: gpu.Texture,
	gbuffer_normal: gpu.Texture,
	gbuffer_metallic_roughness: gpu.Texture,
	vert_shader: gpu.Shader,
	frag_shader: gpu.Shader,
	texture_heap: rawptr,
	texture_rw_heap: rawptr,
	sampler_heap: rawptr,
	frame_arena: ^gpu.Arena,
	fsq_verts_gpu: rawptr,
	fsq_indices_gpu: rawptr,
) {
	gpu.cmd_begin_render_pass(
		cmd_buf,
		{color_attachments = {{texture = swapchain, clear_color = {0.7, 0.7, 0.7, 1.0}}}},
	)
	gpu.cmd_set_shaders(cmd_buf, vert_shader, frag_shader)

	// Set texture and sampler heaps
	textures_ptr := gpu.host_to_device_ptr(texture_heap)
	textures_rw_ptr := gpu.host_to_device_ptr(texture_rw_heap)
	samplers_ptr := gpu.host_to_device_ptr(sampler_heap)
	gpu.cmd_set_desc_heap(cmd_buf, textures_ptr, textures_rw_ptr, samplers_ptr, nil)

	// Disable depth testing for fullscreen quad
	gpu.cmd_set_depth_state(cmd_buf, {mode = {}, compare = .Always})

	// Vertex data for fullscreen quad
	Vert_Data :: struct #all_or_none {
		verts: rawptr,
	}
	verts_data := gpu.arena_alloc(frame_arena, Vert_Data)
	verts_data.cpu.verts = fsq_verts_gpu

	// Fragment data with all G-buffer textures and selected texture type
	Frag_Data :: struct #all_or_none {
		gbuffer_albedo:                     u32,
		gbuffer_albedo_sampler:             u32,
		gbuffer_normal:                     u32,
		gbuffer_normal_sampler:             u32,
		gbuffer_metallic_roughness:         u32,
		gbuffer_metallic_roughness_sampler: u32,
		selected_texture_type:              i32,
	}
	frag_data := gpu.arena_alloc(frame_arena, Frag_Data)
	frag_data.cpu^ = {
		gbuffer_albedo                     = GBUFFER_ALBEDO_IDX,
		gbuffer_albedo_sampler             = 0,
		gbuffer_normal                     = GBUFFER_NORMAL_IDX,
		gbuffer_normal_sampler             = 0,
		gbuffer_metallic_roughness         = GBUFFER_METALLIC_ROUGHNESS_IDX,
		gbuffer_metallic_roughness_sampler = 0,
		selected_texture_type              = i32(selected_texture_type),
	}

	// Render fullscreen quad
	gpu.cmd_draw_indexed_instanced(cmd_buf, verts_data.gpu, frag_data.gpu, fsq_indices_gpu, 6, 1)

	gpu.cmd_end_render_pass(cmd_buf)
}

create_gbuffer_textures :: proc(
	window_size_x: u32,
	window_size_y: u32,
	texture_heap: rawptr,
	texture_rw_heap: rawptr,
) -> (
	gbuffer_albedo: gpu.Owned_Texture,
	gbuffer_normal: gpu.Owned_Texture,
	gbuffer_metallic_roughness: gpu.Owned_Texture,
	depth_texture: gpu.Owned_Texture,
) {
	gbuffer_desc := gpu.Texture_Desc {
		dimensions   = {u32(window_size_x), u32(window_size_y), 1},
		format       = .RGBA8_Unorm,
		mip_count    = 1,
		layer_count  = 1,
		sample_count = 1,
		usage        = {.Color_Attachment, .Sampled, .Storage},
	}

	depth_desc := gpu.Texture_Desc {
		dimensions   = {u32(window_size_x), u32(window_size_y), 1},
		format       = .D32_Float,
		mip_count    = 1,
		layer_count  = 1,
		sample_count = 1,
		usage        = {.Depth_Stencil_Attachment},
	}

	// Albedo
	{
		new_gbuffer_albedo := gpu.alloc_and_create_texture(gbuffer_desc)
		gpu.set_texture_desc(
			texture_heap,
			GBUFFER_ALBEDO_IDX,
			gpu.texture_view_descriptor(new_gbuffer_albedo, {format = .RGBA8_Unorm}),
		)
		gpu.set_texture_rw_desc(
			texture_rw_heap,
			GBUFFER_ALBEDO_IDX,
			gpu.texture_rw_view_descriptor(new_gbuffer_albedo, {format = .RGBA8_Unorm}),
		)
		gbuffer_albedo = new_gbuffer_albedo
	}

	// Normal
	{
		new_gbuffer_normal := gpu.alloc_and_create_texture(gbuffer_desc)
		gpu.set_texture_rw_desc(
			texture_rw_heap,
			GBUFFER_NORMAL_IDX,
			gpu.texture_rw_view_descriptor(new_gbuffer_normal, {format = .RGBA8_Unorm}),
		)
		gpu.set_texture_desc(
			texture_heap,
			GBUFFER_NORMAL_IDX,
			gpu.texture_view_descriptor(new_gbuffer_normal, {format = .RGBA8_Unorm}),
		)
		gbuffer_normal = new_gbuffer_normal
	}

	// Metallic roughness
	{
		new_gbuffer_metallic_roughness := gpu.alloc_and_create_texture(gbuffer_desc)
		gpu.set_texture_desc(
			texture_heap,
			GBUFFER_METALLIC_ROUGHNESS_IDX,
			gpu.texture_view_descriptor(new_gbuffer_metallic_roughness, {format = .RGBA8_Unorm}),
		)
		gpu.set_texture_rw_desc(
			texture_rw_heap,
			GBUFFER_METALLIC_ROUGHNESS_IDX,
			gpu.texture_rw_view_descriptor(
				new_gbuffer_metallic_roughness,
				{format = .RGBA8_Unorm},
			),
		)
		gbuffer_metallic_roughness = new_gbuffer_metallic_roughness
	}

	// Depth
	{
		new_depth_texture := gpu.alloc_and_create_texture(depth_desc)
		depth_texture = new_depth_texture
	}

	return gbuffer_albedo, gbuffer_normal, gbuffer_metallic_roughness, depth_texture
}

// Create a 1x1 magenta texture (useful as default/missing texture indicator)
create_magenta_texture :: proc(
	upload_arena: ^gpu.Arena,
	cmd_buf: gpu.Command_Buffer,
	texture_heap: rawptr,
) -> gpu.Owned_Texture {
	magenta_pixels := [4]u8{255, 0, 255, 255}
	staging, staging_gpu := gpu.arena_alloc_untyped(upload_arena, 4)
	runtime.mem_copy(staging, raw_data(magenta_pixels[:]), 4)

	texture := gpu.alloc_and_create_texture(
		{
			type = .D2,
			dimensions = {1, 1, 1},
			mip_count = 1,
			layer_count = 1,
			sample_count = 1,
			format = .RGBA8_Unorm,
			usage = {.Sampled},
		},
	)
	gpu.cmd_copy_to_texture(cmd_buf, texture, staging_gpu, texture.mem)
	gpu.set_texture_desc(
		texture_heap,
		shared.MISSING_TEXTURE_ID,
		gpu.texture_view_descriptor(texture, {format = .RGBA8_Unorm}),
	)
	return texture
}

create_fullscreen_quad :: proc(
	upload_arena: ^gpu.Arena,
	cmd_buf: gpu.Command_Buffer,
) -> (
	rawptr,
	rawptr,
) {
	Fullscreen_Vertex :: struct {
		pos: [3]f32,
		uv:  [2]f32,
	}

	fsq_verts := gpu.arena_alloc_array(upload_arena, Fullscreen_Vertex, 4)
	fsq_verts.cpu[0].pos = {-1.0, 1.0, 0.0} // Top-left
	fsq_verts.cpu[1].pos = {1.0, -1.0, 0.0} // Bottom-right
	fsq_verts.cpu[2].pos = {1.0, 1.0, 0.0} // Top-right
	fsq_verts.cpu[3].pos = {-1.0, -1.0, 0.0} // Bottom-left
	fsq_verts.cpu[0].uv = {0.0, 1.0}
	fsq_verts.cpu[1].uv = {1.0, 0.0}
	fsq_verts.cpu[2].uv = {1.0, 1.0}
	fsq_verts.cpu[3].uv = {0.0, 0.0}

	fsq_indices := gpu.arena_alloc_array(upload_arena, u32, 6)
	fsq_indices.cpu[0] = 0
	fsq_indices.cpu[1] = 2
	fsq_indices.cpu[2] = 1
	fsq_indices.cpu[3] = 0
	fsq_indices.cpu[4] = 1
	fsq_indices.cpu[5] = 3

	full_screen_quad_verts_gpu := gpu.mem_alloc_typed_gpu(Fullscreen_Vertex, 4)
	full_screen_quad_indices_gpu := gpu.mem_alloc_typed_gpu(u32, 6)

	gpu.cmd_mem_copy(
		cmd_buf,
		fsq_verts.gpu,
		full_screen_quad_verts_gpu,
		u64(len(fsq_verts.cpu)) * size_of(fsq_verts.cpu[0]),
	)
	gpu.cmd_mem_copy(
		cmd_buf,
		fsq_indices.gpu,
		full_screen_quad_indices_gpu,
		u64(len(fsq_indices.cpu)) * size_of(fsq_indices.cpu[0]),
	)

	return full_screen_quad_verts_gpu, full_screen_quad_indices_gpu
}

// Load textures from Texture_Info and update mesh texture IDs
load_scene_textures_from_gltf :: proc(
	texture_infos: []shared.Gltf_Texture_Info,
	data: ^gltf2.Data,
	scene: ^shared.Scene,
	texture_heap: rawptr,
) {
	upload_arena := gpu.arena_init(Loader_Chunk_Size * 4 * 1024 * 1024)
	defer gpu.arena_destroy(&upload_arena)

	for info in texture_infos {
		if cancel_loading_textures {
			return
		}

		if info.mesh_id >= u32(len(scene.meshes)) {
			log.error(
				fmt.tprintf(
					"Invalid mesh_id %v (only %v meshes available)",
					info.mesh_id,
					len(scene.meshes),
				),
			)
			continue
		}

		sync.mutex_lock(&mutex)
		if event, ok := image_uploaded[info.image_index]; ok {
			sync.mutex_unlock(&mutex)
			sync.one_shot_event_wait(event)
		} else {
			texture_idx := next_texture_idx
			next_texture_idx += 1
			event := new(sync.One_Shot_Event)
			image_uploaded[info.image_index] = event
			sync.mutex_unlock(&mutex)


            img := shared.load_texture_from_gltf(
                info.image_index,
                data,
            )
            defer image.destroy(img)

            if Compress_Textures {
                compressed := shared.bc3_compress_rgba8_mips(
                    img.pixels.buf[:],
                    u32(img.width),
                    u32(img.height),
                )
                defer delete(compressed.data)
                defer delete(compressed.offsets)
                texture, upload_completed_semaphore_value := upload_bc3_texture(
                    img,
                    compressed,
                    &upload_arena,
                )

                if sync.guard(&mutex) do image_to_texture[info.image_index] = {texture, texture_idx, upload_completed_semaphore_value}
            } else {
                texture, upload_completed_semaphore_value := upload_texture(
                    img,
                    &upload_arena,
                )

                if sync.guard(&mutex) do image_to_texture[info.image_index] = {texture, texture_idx, upload_completed_semaphore_value}
            }

			sync.one_shot_event_signal(event)

			log.info(
				fmt.tprintf(
					"Loaded texture for mesh %v, type %v, texture_id %v",
					info.mesh_id,
					info.texture_type,
					texture_idx,
				),
			)
		}
	}

	for info in texture_infos {
        sync.mutex_lock(&mutex)
        texture := image_to_texture[info.image_index]
        sync.mutex_unlock(&mutex)

        gpu.semaphore_wait(texture_upload_semaphore, texture.upload_completed_semaphore_value)
        
		sync.guard(&mutex)
		switch info.texture_type {
		case .Base_Color:
			scene.meshes[info.mesh_id].base_color_map = texture.texture_idx
		case .Metallic_Roughness:
			scene.meshes[info.mesh_id].metallic_roughness_map = texture.texture_idx
		case .Normal:
			scene.meshes[info.mesh_id].normal_map = texture.texture_idx
		}

		view_format: gpu.Texture_Format = .RGBA8_Unorm
		if Compress_Textures do view_format = .BC3_RGBA_Unorm
		gpu.set_texture_desc(
			texture_heap,
			texture.texture_idx,
			gpu.texture_view_descriptor(texture.texture, {format = view_format}),
		)
	}
}

upload_texture :: proc(
	img: ^image.Image,
	upload_arena: ^gpu.Arena,
) -> (texture: gpu.Owned_Texture, upload_completed_semaphore_value: u64) {
	staging, staging_gpu := gpu.arena_alloc_untyped(upload_arena, u64(len(img.pixels.buf)))
	runtime.mem_copy(staging, raw_data(img.pixels.buf), len(img.pixels.buf))

	upload_completed_semaphore_value = sync.atomic_add(&texture_upload_semaphore_value, 3)

	texture = gpu.alloc_and_create_texture(
		{
			type = .D2,
			dimensions = {u32(img.width), u32(img.height), 1},
			mip_count = u32(math.log2(f32(max(img.width, img.height)))),
			layer_count = 1,
			sample_count = 1,
			format = .RGBA8_Unorm,
			usage = { .Sampled, .Transfer_Src },
		},
		.Transfer,
		texture_upload_semaphore,
		upload_completed_semaphore_value + 1,
	)
	if sync.guard(&mutex) do append(&loaded_textures, texture)

	// Upload and mipmap generation happen on separate queues so they need to be synchronized using timeline semaphores

	{
		// Upload texture to GPU
		upload_cmd_buf := gpu.commands_begin(.Transfer)
		gpu.cmd_copy_to_texture(upload_cmd_buf, texture, staging_gpu, texture.mem)
		gpu.cmd_add_wait_semaphore(upload_cmd_buf, texture_upload_semaphore, upload_completed_semaphore_value + 1)
		gpu.cmd_add_signal_semaphore(upload_cmd_buf, texture_upload_semaphore, upload_completed_semaphore_value + 2)
		gpu.queue_submit(.Transfer, {upload_cmd_buf})
	}

    if Compress_Textures {
		compressed := shared.bc3_compress_rgba8_mips(
			img.pixels.buf[:],
			u32(img.width),
			u32(img.height),
		)
		defer {
			delete(compressed.data)
			delete(compressed.offsets)
		}

		staging, staging_gpu := gpu.arena_alloc_untyped(upload_arena, u64(len(compressed.data)))
		runtime.mem_copy(staging, raw_data(compressed.data), len(compressed.data))

		upload_completed_semaphore_value = sync.atomic_add(&texture_upload_semaphore_value, 1)

		texture = gpu.alloc_and_create_texture(
			{
				type = .D2,
				dimensions = {u32(img.width), u32(img.height), 1},
				mip_count = compressed.mip_count,
				layer_count = 1,
				sample_count = 1,
				format = .BC3_RGBA_Unorm,
				usage = { .Sampled, .Transfer_Src },
			},
			.Transfer,
			texture_upload_semaphore,
			upload_completed_semaphore_value + 1,
		)
		if sync.guard(&mutex) do append(&loaded_textures, texture)

		regions := make([]gpu.Mip_Copy_Region, int(compressed.mip_count))
		for mip: u32 = 0; mip < compressed.mip_count; mip += 1 {
			regions[mip] = {
				src_offset = compressed.offsets[mip],
				mip_level = mip,
				array_layer = 0,
				layer_count = 1,
			}
		}

		upload_cmd_buf := gpu.commands_begin(.Transfer)
        gpu.cmd_barrier(upload_cmd_buf, .Transfer, .Transfer, {})
		gpu.cmd_copy_mips_to_texture(upload_cmd_buf, texture, staging_gpu, regions)
		gpu.cmd_add_wait_semaphore(upload_cmd_buf, texture_upload_semaphore, upload_completed_semaphore_value + 1)
		gpu.cmd_add_signal_semaphore(upload_cmd_buf, texture_upload_semaphore, upload_completed_semaphore_value + 2)
		gpu.queue_submit(.Transfer, {upload_cmd_buf})

		return texture, upload_completed_semaphore_value + 2
	} else {
		// Generate mipmaps
		mipmaps_cmd_buf := gpu.commands_begin(.Main)
		gpu.cmd_barrier(mipmaps_cmd_buf, .Transfer, .Transfer, {})
		gpu.cmd_generate_mipmaps(mipmaps_cmd_buf, texture)
		gpu.cmd_add_wait_semaphore(mipmaps_cmd_buf, texture_upload_semaphore, upload_completed_semaphore_value + 2)
		gpu.cmd_add_signal_semaphore(mipmaps_cmd_buf, texture_upload_semaphore, upload_completed_semaphore_value + 3)
		gpu.queue_submit(.Main, {mipmaps_cmd_buf})
	}

	return texture, upload_completed_semaphore_value + 3
}

upload_bc3_texture :: proc(
    img: ^image.Image,
	compressed: shared.Block_Compressed_Mips,
	upload_arena: ^gpu.Arena,
) -> (texture: gpu.Owned_Texture, upload_completed_semaphore_value: u64) {
	upload_completed_semaphore_value = sync.atomic_add(&texture_upload_semaphore_value, 2)

    upload_cmd_buf := gpu.commands_begin(.Transfer)
    staging, staging_gpu := gpu.arena_alloc_untyped(upload_arena, u64(len(compressed.data)))
    runtime.mem_copy(staging, raw_data(compressed.data), len(compressed.data))

    upload_completed_semaphore_value = sync.atomic_add(&texture_upload_semaphore_value, 1)

    texture = gpu.alloc_and_create_texture(
        {
            type = .D2,
            dimensions = {u32(img.width), u32(img.height), 1},
            mip_count = compressed.mip_count,
            layer_count = 1,
            sample_count = 1,
            format = .BC3_RGBA_Unorm,
            usage = { .Sampled, .Transfer_Src },
        },
        .Transfer,
        texture_upload_semaphore,
        upload_completed_semaphore_value + 1,
    )
    if sync.guard(&mutex) do append(&loaded_textures, texture)

    regions := make([]gpu.Mip_Copy_Region, int(compressed.mip_count))
    for mip: u32 = 0; mip < compressed.mip_count; mip += 1 {
        regions[mip] = {
            src_offset = compressed.offsets[mip],
            mip_level = mip,
            array_layer = 0,
            layer_count = 1,
        }
    }

    gpu.cmd_copy_mips_to_texture(upload_cmd_buf, texture, staging_gpu, regions)
    gpu.cmd_barrier(upload_cmd_buf, .Transfer, .Transfer, {})
    gpu.cmd_add_wait_semaphore(upload_cmd_buf, texture_upload_semaphore, upload_completed_semaphore_value + 1)
    gpu.cmd_add_signal_semaphore(upload_cmd_buf, texture_upload_semaphore, upload_completed_semaphore_value + 2)
    gpu.queue_submit(.Transfer, {upload_cmd_buf})

	return texture, upload_completed_semaphore_value + 2
}

Mesh_GPU :: struct
{
	pos: rawptr,
	normals: rawptr,
	uvs: rawptr,
	indices: rawptr,
	idx_count: u32,
}

upload_mesh :: proc(upload_arena: ^gpu.Arena, cmd_buf: gpu.Command_Buffer, mesh: shared.Mesh) -> Mesh_GPU
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

	res: Mesh_GPU
	res.pos = gpu.mem_alloc_typed_gpu([4]f32, len(mesh.pos))
	res.normals = gpu.mem_alloc_typed_gpu([4]f32, len(mesh.normals))
	res.uvs = gpu.mem_alloc_typed_gpu([2]f32, len(mesh.uvs))
	res.indices = gpu.mem_alloc_typed_gpu(u32, len(mesh.indices))
	res.idx_count = u32(len(mesh.indices))
	gpu.cmd_mem_copy(cmd_buf, positions_staging.gpu, res.pos, u64(len(mesh.pos) * size_of(mesh.pos[0])))
	gpu.cmd_mem_copy(cmd_buf, normals_staging.gpu, res.normals, u64(len(mesh.normals) * size_of(mesh.normals[0])))
	gpu.cmd_mem_copy(cmd_buf, uvs_staging.gpu, res.uvs, u64(len(mesh.uvs) * size_of(mesh.uvs[0])))
	gpu.cmd_mem_copy(cmd_buf, indices_staging.gpu, res.indices, u64(len(mesh.indices) * size_of(mesh.indices[0])))
	return res
}

mesh_destroy :: proc(mesh: ^Mesh_GPU)
{
	gpu.mem_free(mesh.pos)
	gpu.mem_free(mesh.normals)
	gpu.mem_free(mesh.uvs)
	gpu.mem_free(mesh.indices)
	mesh^ = {}
}
