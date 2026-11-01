package ssao

import "oge:gpu"
import host "oge:misl/examples/host"

TEX :: 128
MODE_COUNT :: 2

Data :: struct #align(16) {
	resolution: [2]f32,
	time:       f32,
	mode:       i32,
	s2h_mouse:  [4]f32,
	depth:      gpu.t32,
	samp:       gpu.s32,
	radius:     f32,
}

g: struct {
	time:   f32,
	mode:   i32,
	depth:  gpu.t32,
	radius: f32,
}

make_depth :: proc() -> []u8 {
	pix := make([]u8, TEX * TEX * 4)
	for y in 0 ..< TEX {
		for x in 0 ..< TEX {
			i := (y * TEX + x) * 4
			fx := (f32(x) / f32(TEX) - 0.5) * 2
			fy := (f32(y) / f32(TEX) - 0.5) * 2
			d := 180.0
			if fx * fx + fy * fy < 0.25 {
				d = 80
			}
			if abs(fx) < 0.15 && fy > -0.2 && fy < 0.5 {
				d = 110
			}
			v := u8(d)
			pix[i + 0] = v
			pix[i + 1] = v
			pix[i + 2] = v
			pix[i + 3] = 255
		}
	}
	return pix
}

main :: proc() {
	host.parse_cli()
	defer host.run(frame)
	g.radius = 12
	host.init("ssao")
	pix := make_depth()
	defer delete(pix)
	g.depth, _, _ = host.create_rgba8_texture(TEX, TEX, pix)
}

frame :: proc(dt: f32) {
	g.time += dt
	host.s2h_cycle_mode(&g.mode, MODE_COUNT)
	host.s2h_nudge_float(&g.radius, 2, 24, 8, dt)

	cmdbuf, swapchain, arena, winsize, ok := host.begin_frame()
	if !ok {
		return
	}
	host.s2h_hud_mode_float(&g.mode, MODE_COUNT - 1, &g.radius, 2, 24)
	host.begin_swapchain_pass(cmdbuf, swapchain, winsize)
	cpu, gpu_sd, _ := gpu.new(.CPU, Data, gpu.arena_allocator(arena))
	cpu^ = Data{
		resolution = {f32(winsize.x), f32(winsize.y)},
		time = g.time,
		mode = g.mode,
		s2h_mouse = host.s2h_mouse(),
		depth = g.depth,
		samp = host.nearest_sampler(),
		radius = g.radius,
	}
	host.draw_fullscreen(cmdbuf, gpu_sd)
	host.end_swapchain_pass(cmdbuf)
	host.end_frame(cmdbuf)
}
