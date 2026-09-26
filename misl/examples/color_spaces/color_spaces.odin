package color_spaces

import "oge:gpu"
import host "oge:misl/examples/host"

MODE_COUNT :: 32
LUT_TILES :: 16

Data :: struct #align(16) {
	resolution: [2]f32,
	time:       f32,
	mode:       i32,
	s2h_mouse:  [4]f32,
	lut:        gpu.t32,
	samp:       gpu.s32,
	param:      f32,
}

g: struct {
	time:  f32,
	mode:  i32,
	param: f32,
	lut:   gpu.t32,
}

make_identity_lut :: proc() -> []u8 {
	n := LUT_TILES
	w := n * n
	h := n
	pix := make([]u8, w * h * 4)
	for bz in 0 ..< n {
		for gy in 0 ..< n {
			for rx in 0 ..< n {
				x := bz * n + rx
				i := (gy * w + x) * 4
				den := f32(n - 1)
				pix[i + 0] = u8(f32(rx) / den * 255 + 0.5)
				pix[i + 1] = u8(f32(gy) / den * 255 + 0.5)
				pix[i + 2] = u8(f32(bz) / den * 255 + 0.5)
				pix[i + 3] = 255
			}
		}
	}
	return pix
}

main :: proc() {
	host.parse_cli()
	defer host.run(frame)
	g.mode = 0
	g.param = 0.5
	host.init("color spaces")
	pix := make_identity_lut()
	defer delete(pix)
	g.lut, _, _ = host.create_rgba8_texture(LUT_TILES * LUT_TILES, LUT_TILES, pix)
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
		lut = g.lut,
		samp = host.linear_sampler(),
		param = g.param,
	}
	host.draw_fullscreen(cmdbuf, gpu_sd)
	host.end_swapchain_pass(cmdbuf)
	host.end_frame(cmdbuf)
}
