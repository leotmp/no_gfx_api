package sampling_demo

import "oge:gpu"
import host "oge:misl/examples/host"

MODE_COUNT :: 11
TEX :: 64

Data :: struct #align(16) {
	resolution: [2]f32,
	time:       f32,
	mode:       i32,
	s2h_mouse:  [4]f32,
	tex:        gpu.t32,
	samp:       gpu.s32,
	nearest:    gpu.s32,
}

g: struct {
	time: f32,
	mode: i32,
	tex:  gpu.t32,
}

make_scene :: proc() -> []u8 {
	pix := make([]u8, TEX * TEX * 4)
	for y in 0 ..< TEX {
		for x in 0 ..< TEX {
			i := (y * TEX + x) * 4
			chk := (x / 8 + y / 8) % 2
			pix[i + 0] = u8(40 + chk * 180)
			pix[i + 1] = u8(x * 4)
			pix[i + 2] = u8(y * 4)
			pix[i + 3] = 255
		}
	}
	return pix
}

main :: proc() {
	host.parse_cli()
	defer host.run(frame)
	host.init("sampling")
	pix := make_scene()
	defer delete(pix)
	g.tex, _, _ = host.create_rgba8_texture(TEX, TEX, pix)
}

frame :: proc(dt: f32) {
	g.time += dt
	host.s2h_cycle_mode(&g.mode, MODE_COUNT)

	cmdbuf, swapchain, arena, winsize, ok := host.begin_frame()
	if !ok {
		return
	}
	host.s2h_hud_mode(&g.mode, MODE_COUNT - 1)
	host.begin_swapchain_pass(cmdbuf, swapchain, winsize)
	cpu, gpu_sd, _ := gpu.new(.CPU, Data, gpu.arena_allocator(arena))
	cpu^ = Data{
		resolution = {f32(winsize.x), f32(winsize.y)},
		time = g.time,
		mode = g.mode,
		s2h_mouse = host.s2h_mouse(),
		tex = g.tex,
		samp = host.linear_sampler(),
		nearest = host.nearest_sampler(),
	}
	host.draw_fullscreen(cmdbuf, gpu_sd)
	host.end_swapchain_pass(cmdbuf)
	host.end_frame(cmdbuf)
}
