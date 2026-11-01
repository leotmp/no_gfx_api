package texture_views

import "oge:gpu"
import host "oge:misl/examples/host"

MODE_COUNT :: 6
TEX :: 64
VOL :: 16
FACE :: 16

Data :: struct #align(16) {
	resolution: [2]f32,
	time:       f32,
	mode:       i32,
	s2h_mouse:  [4]f32,
	tex:        gpu.t32,
	tex3d:      gpu.t32,
	cube:       gpu.t32,
	depth:      gpu.t32,
	samp:       gpu.s32,
	samp_cmp:   gpu.s32,
	param:      f32,
}

g: struct {
	time:     f32,
	mode:     i32,
	param:    f32,
	tex:      gpu.t32,
	tex3d:    gpu.t32,
	cube:     gpu.t32,
	depth:    gpu.t32,
	samp_cmp: gpu.s32,
}

fill_rgba :: proc(w, h: int, shade: proc(x, y: int) -> [4]u8) -> []u8 {
	pix := make([]u8, w * h * 4)
	for y in 0 ..< h {
		for x in 0 ..< w {
			c := shade(x, y)
			i := (y * w + x) * 4
			pix[i + 0] = c.x
			pix[i + 1] = c.y
			pix[i + 2] = c.z
			pix[i + 3] = c.w
		}
	}
	return pix
}

main :: proc() {
	host.parse_cli()
	defer host.run(frame)
	g.param = 0.35
	host.init("texture_views")

	pix2 := fill_rgba(TEX, TEX, proc(x, y: int) -> [4]u8 {
		chk := (x / 8 + y / 8) % 2
		return {u8(40 + chk * 180), u8(x * 4), u8(y * 4), 255}
	})
	defer delete(pix2)
	g.tex, _, _ = host.create_sampled_texture({
		type = .D2,
		size = {TEX, TEX, 1},
		mip_count = 4,
		layer_count = 1,
		sample_count = ._1,
		format = .rgba_u8_norm,
		usage = {.Sampled},
	}, {
		type = .D2,
		format = .rgba_u8_norm,
	}, pix2)

	pix3 := make([]u8, VOL * VOL * VOL * 4)
	defer delete(pix3)
	for z in 0 ..< VOL {
		for y in 0 ..< VOL {
			for x in 0 ..< VOL {
				i := ((z * VOL + y) * VOL + x) * 4
				pix3[i + 0] = u8(x * 16)
				pix3[i + 1] = u8(y * 16)
				pix3[i + 2] = u8(z * 16)
				pix3[i + 3] = 255
			}
		}
	}
	g.tex3d, _, _ = host.create_sampled_texture({
		type = .D3,
		size = {VOL, VOL, VOL},
		mip_count = 1,
		layer_count = 1,
		sample_count = ._1,
		format = .rgba_u8_norm,
		usage = {.Sampled},
	}, {
		type = .D3,
		format = .rgba_u8_norm,
	}, pix3)

	pix_cube := fill_rgba(FACE, FACE, proc(x, y: int) -> [4]u8 {
		return {u8(40 + x * 12), u8(40 + y * 12), 200, 255}
	})
	defer delete(pix_cube)
	g.cube, _, _ = host.create_sampled_texture({
		type = .D2,
		size = {FACE, FACE, 1},
		mip_count = 1,
		layer_count = 6,
		sample_count = ._1,
		format = .rgba_u8_norm,
		usage = {.Sampled},
	}, {
		type = .Cube,
		format = .rgba_u8_norm,
		layer_count = 6,
	}, pix_cube)

	depth := make([]u8, TEX * TEX * 4)
	defer delete(depth)
	for y in 0 ..< TEX {
		for x in 0 ..< TEX {
			i := (y * TEX + x) * 4
			fx := f32(x) / f32(TEX)
			bits := transmute(u32)fx
			depth[i + 0] = u8(bits)
			depth[i + 1] = u8(bits >> 8)
			depth[i + 2] = u8(bits >> 16)
			depth[i + 3] = u8(bits >> 24)
		}
	}
	g.depth, _, _ = host.create_sampled_texture({
		type = .D2,
		size = {TEX, TEX, 1},
		mip_count = 1,
		layer_count = 1,
		sample_count = ._1,
		format = .depth_f32,
		usage = {.Sampled},
	}, {
		type = .D2,
		format = .depth_f32,
	}, depth)

	g.samp_cmp = host.create_sampler({
		filters = {.Linear, .Linear, .Linear},
		wrap = {.Clamp_To_Edge, .Clamp_To_Edge, .Clamp_To_Edge},
		compare = .Less,
	})
}

frame :: proc(dt: f32) {
	g.time += dt
	host.s2h_cycle_mode(&g.mode, MODE_COUNT)
	host.s2h_nudge_float(&g.param, 0, 1, 0.5, dt)

	cmdbuf, swapchain, arena, winsize, ok := host.begin_frame()
	if !ok {
		return
	}
	host.s2h_hud_mode_float(&g.mode, MODE_COUNT - 1, &g.param, 0, 1)
	host.begin_swapchain_pass(cmdbuf, swapchain, winsize)
	cpu, gpu_sd, _ := gpu.new(.CPU, Data, gpu.arena_allocator(arena))
	cpu^ = Data{
		resolution = {f32(winsize.x), f32(winsize.y)},
		time = g.time,
		mode = g.mode,
		s2h_mouse = host.s2h_mouse(),
		tex = g.tex,
		tex3d = g.tex3d,
		cube = g.cube,
		depth = g.depth,
		samp = host.linear_sampler(),
		samp_cmp = g.samp_cmp,
		param = g.param,
	}
	host.draw_fullscreen(cmdbuf, gpu_sd)
	host.end_swapchain_pass(cmdbuf)
	host.end_frame(cmdbuf)
}
