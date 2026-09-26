package atmosphere

import "oge:gpu"
import host "oge:misl/examples/host"

MODE_COUNT :: 4

Data :: struct #align(16) {
	resolution: [2]f32,
	time:       f32,
	mode:       i32,
	s2h_mouse:  [4]f32,
	sun:        f32,
}

g: struct {
	time: f32,
	mode: i32,
	sun:  f32,
}

main :: proc() {
	host.parse_cli()
	defer host.run(frame)
	g.sun = 0.8
	host.init("atmosphere")
}

frame :: proc(dt: f32) {
	g.time += dt
	host.s2h_cycle_mode(&g.mode, MODE_COUNT)
	host.s2h_nudge_float(&g.sun, 0, 6.2831853, 1, dt)

	cmdbuf, swapchain, arena, winsize, ok := host.begin_frame()
	if !ok {
		return
	}
	host.s2h_hud_mode_float(&g.mode, MODE_COUNT - 1, &g.sun, 0, 6.2831853)
	host.begin_swapchain_pass(cmdbuf, swapchain, winsize)
	cpu, gpu_sd, _ := gpu.new(.CPU, Data, gpu.arena_allocator(arena))
	cpu^ = Data{
		resolution = {f32(winsize.x), f32(winsize.y)},
		time = g.time,
		mode = g.mode,
		s2h_mouse = host.s2h_mouse(),
		sun = g.sun,
	}
	host.draw_fullscreen(cmdbuf, gpu_sd)
	host.end_swapchain_pass(cmdbuf)
	host.end_frame(cmdbuf)
}
