package sh

import "oge:gpu"
import host "oge:misl/examples/host"

Data :: struct #align(16) {
	resolution: [2]f32,
	time:       f32,
	mode:       i32,
	s2h_mouse:  [4]f32,
	blend:      f32,
}

g: struct {
	time:  f32,
	blend: f32,
}

main :: proc() {
	host.parse_cli()
	defer host.run(frame)
	g.blend = 0
	host.init("sh")
}

frame :: proc(dt: f32) {
	g.time += dt
	host.s2h_nudge_float(&g.blend, 0, 1, 0.5, dt)

	cmdbuf, swapchain, arena, winsize, ok := host.begin_frame()
	if !ok {
		return
	}
	host.s2h_hud_float(&g.blend, 0, 1)
	host.begin_swapchain_pass(cmdbuf, swapchain, winsize)
	cpu, gpu_sd, _ := gpu.new(.CPU, Data, gpu.arena_allocator(arena))
	cpu^ = Data{
		resolution = {f32(winsize.x), f32(winsize.y)},
		time = g.time,
		s2h_mouse = host.s2h_mouse(),
		blend = g.blend,
	}
	host.draw_fullscreen(cmdbuf, gpu_sd)
	host.end_swapchain_pass(cmdbuf)
	host.end_frame(cmdbuf)
}
