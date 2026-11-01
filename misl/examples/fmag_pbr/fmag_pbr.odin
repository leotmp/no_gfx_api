package fmag_pbr

import "base:intrinsics"
import "core:fmt"

import "oge:gpu"
import "oge:misl"
import host "oge:misl/examples/host"

Data :: struct #align(16) {
	resolution: [2]f32,
	time:       f32,
	light:      f32,
	s2h_mouse:  [4]f32,
	code:       [][4]u32,
}

g: struct {
	time:  f32,
	light: f32,
	code:  [][4]u32,
}

upload_shade :: proc() {
	path := host.path_next_to_exe("shaders/fmag_pbr.misl")
	session := misl.create_session()
	defer misl.destroy_session(session)
	module := misl.load_module_from_file(session, path)
	fmt.assertf(module != nil, "failed to load '%s'", path)
	entry := misl.find_entry_with_name(module, "shade")
	fmt.assertf(entry != nil, "shade proc \"fmag\" not found in '%s'", path)
	r, ok := misl.compile_fmag_entry(entry, misl.Target{formats = {.fmag}})
	fmt.assertf(ok, "compile_fmag_entry(shade) failed")
	prog := r.fmag
	fmt.assertf(prog.header.regs <= misl.FMAG_REGS, "shade uses %d FMAG registers; core:fmag.REGS is %d", prog.header.regs, misl.FMAG_REGS)
	fmt.printfln("fmag shade: regs=%d args=%d rets=%d bytes=%d", prog.header.regs, prog.header.args, prog.header.rets, prog.stream.size)

	n := int(prog.stream.size) / size_of([4]u32)
	fmt.assertf(n > 0, "empty FMAG stream")
	cpu, gpu_code, err := gpu.make(.CPU, [][4]u32, n)
	fmt.assertf(err == .None, "gpu.make shade stream: %v", err)
	intrinsics.mem_copy(raw_data(cpu), prog.stream.data, int(prog.stream.size))
	g.code = gpu_code
}

main :: proc() {
	host.parse_cli()
	defer host.run(frame)
	g.light = 1
	host.init("fmag pbr")
	upload_shade()
}

frame :: proc(dt: f32) {
	g.time += dt
	host.s2h_nudge_float(&g.light, 1, 6, 1.5, dt)

	cmdbuf, swapchain, arena, winsize, ok := host.begin_frame()
	if !ok {
		return
	}
	host.s2h_hud_float(&g.light, 1, 6)
	host.begin_swapchain_pass(cmdbuf, swapchain, winsize)
	cpu, gpu_sd, _ := gpu.new(.CPU, Data, gpu.arena_allocator(arena))
	cpu^ = Data{
		resolution = {f32(winsize.x), f32(winsize.y)},
		time = g.time,
		light = g.light,
		s2h_mouse = host.s2h_mouse(),
		code = g.code,
	}
	host.draw_fullscreen(cmdbuf, gpu_sd)
	host.end_swapchain_pass(cmdbuf)
	host.end_frame(cmdbuf)
}
