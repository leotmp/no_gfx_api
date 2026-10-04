package misl_ex

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import fpath "core:path/filepath"
import "core:strings"
import "core:time"

import "oge:app"
import "oge:gpu"
import "oge:misl"

FRAMES_IN_FLIGHT :: 2
BENCH_WARMUP :: 20
BENCH_SAMPLES :: 240
BENCH_WALL :: 8 * time.Second

bench: bool
assert_buffer: bool = true
shader_opt: misl.Optimization = .All

@(private)
Host :: struct {
	next_frame:      u64,
	frame_fence:     gpu.Fence,
	frame_arenas:    [FRAMES_IN_FLIGHT]gpu.Arena,
	upload_arena:    gpu.Arena,
	pipeline:        gpu.Pipeline,
	rt_size:         [2]int,
	bench_frame:     int,
	bench_n:         int,
	bench_t0:        time.Tick,
	linear_sampler:  gpu.s32,
	nearest_sampler: gpu.s32,
}

@(private)
h: Host

parse_cli :: proc() {
	bench = false
	assert_buffer = true
	shader_opt = .All
	for arg in os.args[1:] {
		if arg == "-bench" {
			bench = true
			continue
		}
		if arg == "-no-assert-buffer" {
			assert_buffer = false
			continue
		}
		if strings.has_prefix(arg, "-o:") {
			key := arg[len("-o:"):]
			parsed, ok := misl.parse_spirv_opt(key)
			if !ok {
				fmt.eprintfln("unknown -o:%s (use none, size, performance, all)", key)
				os.exit(1)
			}
			shader_opt = parsed
		}
	}
}

exe_dir :: proc() -> string {
	// `os.args[0]` is often a relative path (how the process was launched). Resolve
	// against the process cwd so `shaders/` next to the exe still works when
	// `misl_examples` runs from `out/misl_examples/<name>`.
	abs, err := fpath.abs(os.args[0], context.temp_allocator)
	if err != nil {
		return fpath.dir(os.args[0])
	}
	return fpath.dir(abs)
}

path_next_to_exe :: proc(rel: string) -> string {
	p, _ := fpath.join({exe_dir(), rel}, context.temp_allocator)
	return p
}

linear_sampler :: proc() -> gpu.s32 {
	return h.linear_sampler
}

nearest_sampler :: proc() -> gpu.s32 {
	return h.nearest_sampler
}

// Upload pixels and bind a sampled descriptor. Call after init().
create_sampled_texture :: proc(td: gpu.Texture_Desc, view: gpu.View_Desc, pixels: []u8) -> (desc: gpu.t32, handle: gpu.Texture, storage: rawptr) {
	_, storage, _ = gpu.malloc(.GPU, gpu.texture_size_align(td))
	handle = gpu.create_texture(td, storage)
	if len(pixels) > 0 {
		staging_cpu, staging_gpu, _ := gpu.make(.CPU, []u8, len(pixels), gpu.arena_allocator(&h.upload_arena))
		copy(staging_cpu, pixels)
		cmdbuf := gpu.record(.Direct)
		gpu.cmd_copy(cmdbuf, handle, raw_data(staging_gpu), td.size)
		gpu.cmd_barrier(cmdbuf, .Copy, .All)
		gpu.submit({cmdbuf})
	}
	desc = gpu.allocate_texture_descriptor()
	gpu.write_texture_descriptor(desc, handle, view)
	return
}

create_rgba8_texture :: proc(width, height: int, pixels: []u8) -> (desc: gpu.t32, handle: gpu.Texture, storage: rawptr) {
	return create_sampled_texture({
		type = .D2,
		size = {width, height, 1},
		mip_count = 1,
		layer_count = 1,
		sample_count = ._1,
		format = .rgba_u8_norm,
		usage = {.Sampled},
	}, {
		type = .D2,
		format = .rgba_u8_norm,
	}, pixels)
}

create_sampler :: proc(desc: gpu.Sampler_Desc) -> gpu.s32 {
	s := gpu.allocate_sampler_descriptor()
	gpu.write_sampler_descriptor(s, desc)
	return s
}

pipeline :: proc() -> gpu.Pipeline {
	return h.pipeline
}

s2h_mouse :: proc() -> [4]f32 {
	pos := app.mouse_pos()
	left := app.mouse_button_state(.Left)
	down: f32 = 1 if .Down in left.flags else 0
	return {f32(pos.x) + 0.5, f32(pos.y) + 0.5, down, 0}
}

@(private)
gpu_wsi_procs :: proc() -> gpu.Vulkan_WSI_Procs {
	return {
		GetFramebufferSize = nil,
		GetInstanceProcAddr = auto_cast app.get_vkGetInstanceProcAddr(),
		GetInstanceExtensions = proc "system"(userdata: rawptr, pCount: ^u32, pNames: [^]cstring) -> gpu.VkResult {
			context = runtime.default_context()
			exts := app.get_required_vulkan_extensions()
			if pNames == nil {
				pCount^ = auto_cast len(exts)
			} else {
				for ext, i in exts {
					pNames[i] = exts[i]
				}
			}
			return .SUCCESS
		},
		CreateSurface = proc "system"(userdata: rawptr, instance: gpu.VkInstance, surface: ^gpu.VkSurface) -> gpu.VkResult {
			context = runtime.default_context()
			app.vulkan_create_surface(instance, surface)
			return .SUCCESS if surface^ != 0 else .ERROR_UNKNOWN
		},
	}
}

@(private)
checked_blend_mode_to_gpu :: proc(m: misl.Checked_Blend_Mode) -> gpu.Blend_Mode {
	return gpu.Blend_Mode{
		src = gpu.Blend_Factor(m.src),
		dst = gpu.Blend_Factor(m.dst),
		op  = gpu.Blend_Op(m.op),
	}
}

@(private)
checked_pipeline_to_raster_desc :: proc(cp: ^misl.Checked_Pipeline) -> gpu.Raster_Desc {
	desc: gpu.Raster_Desc
	if cp == nil do return desc
	if cp.has_topology do desc.topology = gpu.Topology(cp.topology)
	if cp.has_cull do desc.cull = transmute(gpu.Cull_Modes)u8(cp.cull)
	if cp.has_sample_count do desc.sample_count = gpu.Sample_Count(cp.sample_count)
	if cp.has_depth_format do desc.depth_format = gpu.Format(cp.depth_format)
	if cp.has_stencil_format do desc.stencil_format = gpu.Format(cp.stencil_format)
	if cp.has_flags do desc.flags = transmute(gpu.Raster_Flags)u8(cp.flags)
	if cp.has_view_count do desc.view_count = int(cp.view_count)
	if cp.has_targets {
		colors := make([]gpu.Color_Attachment_Desc, len(cp.targets), context.temp_allocator)
		for t, i in cp.targets {
			colors[i].format = gpu.Format(t.format)
			if t.has_write_mask {
				colors[i].write_mask = gpu.Color_Write_Mask(t.write_mask)
			}
			if t.has_blend {
				colors[i].blend = gpu.Blend_State{
					color = checked_blend_mode_to_gpu(t.blend.color),
					alpha = checked_blend_mode_to_gpu(t.blend.alpha),
				}
			}
		}
		desc.colors = colors
	}
	return desc
}

load_misl_pipeline :: proc(path, pipeline_name: string) -> gpu.Pipeline {
	fmt.printfln("compiling misl pipeline '%s' from '%s' (opt %v)", pipeline_name, path, shader_opt)

	session := misl.create_session()
	defer misl.destroy_session(session)

	module := misl.load_module_from_file(session, path)
	fmt.assertf(module != nil, "failed to load misl module '%s'", path)

	pipe := misl.find_pipeline_with_name(module, pipeline_name)
	fmt.assertf(pipe != nil, "pipeline '%s' not found in '%s'", pipeline_name, path)

	target := misl.Target{
		formats = {.spirv},
		opt = shader_opt,
		flags = {.Named_Entry},
	}
	when ODIN_DEBUG {
		target.flags += {.Debug}
	}
	opts := misl.Compile_Options{allocator = context.temp_allocator}
	vs_e := misl.pipeline_vertex(pipe)
	fs_e := misl.pipeline_fragment(pipe)
	fmt.assertf(vs_e != nil, "pipeline '%s' has no vertex stage", pipeline_name)
	fmt.assertf(fs_e != nil, "pipeline '%s' has no fragment stage", pipeline_name)

	vs_r, vs_ok := misl.compile_entry(vs_e, target, opts)
	fs_r, fs_ok := misl.compile_entry(fs_e, target, opts)
	fmt.assertf(vs_ok && fs_ok, "failed to compile pipeline '%s'", pipeline_name)

	cp := misl.checked_pipeline(pipe, target)
	fmt.assertf(cp != nil && cp.vertex != nil && cp.fragment != nil, "pipeline '%s' has no checked data", pipeline_name)
	desc := checked_pipeline_to_raster_desc(cp)
	desc.vertex_shader_name = strings.clone(misl.entry_point_name(vs_e, target), context.temp_allocator)
	desc.fragment_shader_name = strings.clone(misl.entry_point_name(fs_e, target), context.temp_allocator)
	return gpu.create_graphics_pipeline(vs_r.spirv, fs_r.spirv, desc)
}

init :: proc(title: string, shader_rel := "", pipeline_name := "main_pipeline") {
	app.set_window_title(title)
	app.set_window_flags({.Resizable, .Vulkan})
	app.set_window_size({1280, 720})

	features: gpu.Features = {
		.Descriptor_Manager,
		.Panic_On_Allocator_Errors,
	}
	if assert_buffer {
		features += {.Assert_Buffer}
	}
	gpu.init({
		userdata = nil,
		wsi_procs = gpu_wsi_procs(),
		features = features,
		descriptor_manager = {
			reserved_rw_texture_descriptors = 0,
			reserved_texture_descriptors = 0,
			reserved_sampler_descriptors = 0,
		},
	})

	winsize := app.window_size()
	gpu.swapchain_config({
		size = winsize,
		format = .rgba_u8_srgb,
		texture_count = FRAMES_IN_FLIGHT,
	})
	h.rt_size = winsize
	h.next_frame = 1
	h.frame_fence = gpu.create_fence(0)
	for &arena in h.frame_arenas {
		gpu.arena_init(&arena, 4 * mem.Megabyte, .CPU)
	}
	gpu.arena_init(&h.upload_arena, 16 * mem.Megabyte, .CPU)

	h.linear_sampler = gpu.allocate_sampler_descriptor()
	gpu.write_sampler_descriptor(h.linear_sampler, {
		filters = {.Linear, .Linear, .Linear},
		wrap = {.Clamp_To_Edge, .Clamp_To_Edge, .Clamp_To_Edge},
	})
	h.nearest_sampler = gpu.allocate_sampler_descriptor()
	gpu.write_sampler_descriptor(h.nearest_sampler, {
		filters = {.Nearest, .Nearest, .Nearest},
		wrap = {.Clamp_To_Edge, .Clamp_To_Edge, .Clamp_To_Edge},
	})

	rel := shader_rel
	if rel == "" {
		rel = fmt.tprintf("shaders/%s.misl", fpath.stem(os.args[0]))
	}
	shader_path := path_next_to_exe(rel)
	h.pipeline = load_misl_pipeline(shader_path, pipeline_name)
}

run :: proc(frame: app.Frame_Proc) {
	app.start(frame)
}

begin_frame :: proc() -> (cmdbuf: gpu.Command_Buffer, swapchain: gpu.Texture, arena: ^gpu.Arena, winsize: [2]int, ok: bool) {
	if app.key_pressed(.Escape) {
		app.stop()
		return
	}
	if s2h_mouse().z == 0 {
		s2h_ui_release()
	}
	winsize = app.window_size()
	if winsize.x <= 0 || winsize.y <= 0 {
		return
	}
	if winsize != h.rt_size {
		gpu.swapchain_config({
			size = winsize,
			format = .rgba_u8_srgb,
			texture_count = FRAMES_IN_FLIGHT,
		})
		h.rt_size = winsize
	}
	if h.next_frame > FRAMES_IN_FLIGHT {
		gpu.wait_for_fence(h.frame_fence, h.next_frame - FRAMES_IN_FLIGHT)
	}
	arena = &h.frame_arenas[h.next_frame % FRAMES_IN_FLIGHT]
	gpu.arena_free_all(arena)
	swapchain = gpu.swapchain_acquire()
	cmdbuf = gpu.record(.Direct)
	gpu.cmd_set_viewport(cmdbuf, gpu.Viewport{
		pos = {0, 0},
		size = cast([2]f32)winsize,
		depth = {0, 1},
	})
	gpu.cmd_set_scissor(cmdbuf, {{0, 0}, cast([2]f32)winsize})
	ok = true
	return
}

begin_swapchain_pass :: proc(cmdbuf: gpu.Command_Buffer, swapchain: gpu.Texture, winsize: [2]int, clear := [4]f32{0, 0, 0, 1}) {
	gpu.cmd_begin_pass(cmdbuf, {
		area = {{0, 0}, winsize},
		colors = {
			{
				texture = {
					texture = swapchain,
					view = {.D2, .rgba_u8_srgb, 0, 1, 0, 1},
				},
				load = .Clear,
				store = .Store,
				clear = clear,
			},
		},
	})
}

end_swapchain_pass :: proc(cmdbuf: gpu.Command_Buffer) {
	gpu.cmd_end_pass(cmdbuf)
}

draw_fullscreen :: proc(cmdbuf: gpu.Command_Buffer, data: ^$T) {
	gpu.cmd_set_graphics_pipeline(cmdbuf, h.pipeline)
	gpu.cmd_draw(cmdbuf, data, data, 3, 1)
}

end_frame :: proc(cmdbuf: gpu.Command_Buffer) {
	gpu.cmd_signal_fence(cmdbuf, h.frame_fence, h.next_frame)
	gpu.submit({cmdbuf})
	gpu.swapchain_present(h.frame_fence, h.next_frame)
	h.next_frame += 1
	tick_bench()
}

@(private)
tick_bench :: proc() {
	if !bench do return
	if h.bench_frame == 0 {
		h.bench_t0 = time.tick_now()
	}
	h.bench_frame += 1
	if h.bench_frame > BENCH_WARMUP {
		h.bench_n += 1
	}
	elapsed := time.tick_since(h.bench_t0)
	done := h.bench_n >= BENCH_SAMPLES || elapsed >= BENCH_WALL
	if done {
		if h.bench_n > 0 {
			fmt.eprintfln("bench: ok frames=%d wall_ms=%.0f", h.bench_n, time.duration_milliseconds(elapsed))
		} else {
			fmt.eprintln("bench: no samples")
		}
		app.stop()
	}
}
