package color_dither

import "oge:gpu"
import host "oge:misl/examples/host"

MODE_COUNT :: 6

Data :: struct #align(16) {
	resolution: [2]f32,
	time:       f32,
	mode:       i32,
	s2h_mouse:  [4]f32,
	levels:     f32,
	noise:      gpu.t32,
	samp:       gpu.s32,
}

g: struct {
	time:   f32,
	mode:   i32,
	levels: f32,
	noise:  gpu.t32,
}

make_noise_tex :: proc() -> []u8 {
	n := 64
	pix := make([]u8, n * n * 4)
	s: u32 = 1
	for i in 0 ..< n * n {
		s = s * 747796405 + 2891336453
		w := ((s >> ((s >> 28) + 4)) ~ s) * 277803737
		h := (w >> 22) ~ w
		v := u8(h >> 24)
		pix[i * 4 + 0] = v
		pix[i * 4 + 1] = v
		pix[i * 4 + 2] = v
		pix[i * 4 + 3] = 255
	}
	return pix
}

main :: proc() {
	host.parse_cli()
	defer host.run(frame)
	g.mode = 0
	g.levels = 8
	host.init("color dither")
	pix := make_noise_tex()
	defer delete(pix)
	g.noise, _, _ = host.create_rgba8_texture(64, 64, pix)
}

frame :: proc(dt: f32) {
	g.time += dt
	host.s2h_cycle_mode(&g.mode, MODE_COUNT)
	host.s2h_nudge_float(&g.levels, 2, 64, 8, dt)

	cmdbuf, swapchain, arena, winsize, ok := host.begin_frame()
	if !ok {
		return
	}
	host.s2h_hud_mode_float(&g.mode, MODE_COUNT - 1, &g.levels, 2, 64)
	host.begin_swapchain_pass(cmdbuf, swapchain, winsize)
	cpu, gpu_sd, _ := gpu.new(.CPU, Data, gpu.arena_allocator(arena))
	cpu^ = Data{
		resolution = {f32(winsize.x), f32(winsize.y)},
		time = g.time,
		mode = g.mode,
		s2h_mouse = host.s2h_mouse(),
		levels = g.levels,
		noise = g.noise,
		samp = host.nearest_sampler(),
	}
	host.draw_fullscreen(cmdbuf, gpu_sd)
	host.end_swapchain_pass(cmdbuf)
	host.end_frame(cmdbuf)
}
