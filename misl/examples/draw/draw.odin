package draw

import "oge:gpu"
import host "oge:misl/examples/host"

MODE_COUNT :: 8

Data :: struct #align(16) {
	resolution: [2]f32,
	time:       f32,
	mode:       i32,
	s2h_mouse:  [4]f32,
	stroke_w:   f32,
}

g: struct {
	time:     f32,
	mode:     i32,
	stroke_w: f32,
}

main :: proc() {
	host.parse_cli()
	defer host.run(frame)
	g.stroke_w = 0.02
	host.init("draw")
}

frame :: proc(dt: f32) {
	g.time += dt
	host.s2h_cycle_mode(&g.mode, MODE_COUNT)
	host.s2h_nudge_float(&g.stroke_w, 0.004, 0.08, 0.05, dt)

	cmdbuf, swapchain, arena, winsize, ok := host.begin_frame()
	if !ok {
		return
	}
	host.s2h_hud_mode_float(&g.mode, MODE_COUNT - 1, &g.stroke_w, 0.004, 0.08)
	host.begin_swapchain_pass(cmdbuf, swapchain, winsize, {0.06, 0.07, 0.09, 1})
	cpu, gpu_sd, _ := gpu.new(.CPU, Data, gpu.arena_allocator(arena))
	cpu^ = Data{
		resolution = {f32(winsize.x), f32(winsize.y)},
		time = g.time,
		mode = g.mode,
		s2h_mouse = host.s2h_mouse(),
		stroke_w = g.stroke_w,
	}
	host.draw_fullscreen(cmdbuf, gpu_sd)
	host.end_swapchain_pass(cmdbuf)
	host.end_frame(cmdbuf)
}
