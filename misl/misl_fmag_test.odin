
#+build ignore

package misl

import "core:math"
import "core:strings"
import "core:testing"

import fmag "fmag"

fmag_test_compile :: proc(t: ^testing.T, src: string, name: string) -> (prog: fmag.Program, ok: bool) {
	session := create_session()
	defer destroy_session(session)
	module := load_module_from_memory(session, "fmag_test.misl", src)
	if !testing.expect(t, module != nil, "load_module_from_memory failed") {
		return
	}
	entry := find_entry_with_name(module, name)
	if !testing.expect(t, entry != nil, "entry not found") {
		return
	}
	r: Compile_Result
	r, ok = compile_fmag_entry(entry, Target{formats = {.fmag}})
	testing.expect(t, ok, "compile_fmag_entry failed")
	prog = r.fmag
	return
}

@(test)
test_compile_fmag_add :: proc(t: ^testing.T) {
	src := `
add :: proc "fmag"(a: f32, b: f32) -> f32 {
	return a + b
}
`
	prog, ok := fmag_test_compile(t, src, "add")
	if !ok do return
	defer delete(([^]u8)(prog.stream.data)[:int(prog.stream.size)])
	regs := make([]f32, max(int(prog.header.regs), 2))
	defer delete(regs)
	regs[0] = 2
	regs[1] = 3
	fmag.run(prog, regs)
	testing.expect(t, math.abs(regs[0] - 5) < 1e-5)
}

@(test)
test_compile_fmag_helper :: proc(t: ^testing.T) {
	src := `
double :: proc(x: f32) -> f32 {
	return x + x
}
scale :: proc(v: [3]f32, s: f32) -> [3]f32 {
	return v * s
}
inner :: proc(a: f32, b: f32) -> f32 {
	return double(a) + b
}
k :: proc "fmag"(a: f32, b: f32, v: [3]f32, s: f32) -> [3]f32 {
	return scale(v, s) + inner(a, b)
}
`
	prog, ok := fmag_test_compile(t, src, "k")
	if !ok do return
	defer delete(([^]u8)(prog.stream.data)[:int(prog.stream.size)])
	regs := make([]f32, max(int(prog.header.regs), 6))
	defer delete(regs)
	regs[0] = 2
	regs[1] = 3
	regs[2] = 1
	regs[3] = 2
	regs[4] = 3
	regs[5] = 4
	fmag.run(prog, regs)
	testing.expect(t, math.abs(regs[0] - 11) < 1e-5)
	testing.expect(t, math.abs(regs[1] - 15) < 1e-5)
	testing.expect(t, math.abs(regs[2] - 19) < 1e-5)
}

@(test)
test_emit_fmag_asm_helper_notes :: proc(t: ^testing.T) {
	src := `
double :: proc(x: f32) -> f32 {
	return x + x
}
scale :: proc(v: [3]f32, s: f32) -> [3]f32 {
	return v * s
}
inner :: proc(a: f32, b: f32) -> f32 {
	return double(a) + b
}
k :: proc "fmag"(a: f32, b: f32, v: [3]f32, s: f32) -> [3]f32 {
	return scale(v, s) + inner(a, b)
}
`
	session := create_session()
	defer destroy_session(session)
	module := load_module_from_memory(session, "fmag_asm.misl", src)
	if !testing.expect(t, module != nil, "load_module_from_memory failed") {
		return
	}
	entry := find_entry_with_name(module, "k")
	if !testing.expect(t, entry != nil, "entry not found") {
		return
	}
	text, ok := emit_fmag_asm(entry)
	if !testing.expect(t, ok, "emit_fmag_asm failed") {
		return
	}
	defer delete(text)
	testing.expect(t, strings.contains(text, ".def k"), text)
	testing.expect(t, strings.contains(text, "; scale("), text)
	testing.expect(t, strings.contains(text, "; inner("), text)
}

@(test)
test_compile_fmag_if_abs :: proc(t: ^testing.T) {
	src := `
k :: proc "fmag"(x: f32) -> f32 {
	if x < 0 {
		return -x
	}
	return x
}
`
	prog, ok := fmag_test_compile(t, src, "k")
	if !ok do return
	defer delete(([^]u8)(prog.stream.data)[:int(prog.stream.size)])
	regs := make([]f32, max(int(prog.header.regs), 1))
	defer delete(regs)
	regs[0] = -3
	fmag.run(prog, regs)
	testing.expect(t, math.abs(regs[0] - 3) < 1e-5)
}

@(test)
test_compile_fmag_if_assign :: proc(t: ^testing.T) {
	src := `
k :: proc "fmag"(x: f32) -> f32 {
	m := x
	e := 0.0
	if m >= 2 {
		m = m * 0.5
		e = e + 1
	}
	if m < 1 {
		m = m * 2
		e = e - 1
	}
	return m + e
}
`
	prog, ok := fmag_test_compile(t, src, "k")
	if !ok do return
	defer delete(([^]u8)(prog.stream.data)[:int(prog.stream.size)])
	regs := make([]f32, max(int(prog.header.regs), 1))
	defer delete(regs)
	regs[0] = 4
	fmag.run(prog, regs)
	testing.expect(t, math.abs(regs[0] - 3) < 1e-5)
}

@(test)
test_compile_fmag_if_vec_assign :: proc(t: ^testing.T) {
	src := `
k :: proc "fmag"(c: f32, a: [3]f32) -> [3]f32 {
	v := a
	if c > 0 {
		v = v * 2
	}
	return v
}
`
	prog, ok := fmag_test_compile(t, src, "k")
	if !ok do return
	defer delete(([^]u8)(prog.stream.data)[:int(prog.stream.size)])
	regs := make([]f32, max(int(prog.header.regs), 4))
	defer delete(regs)
	regs[0] = 1
	regs[1] = 1
	regs[2] = 2
	regs[3] = 3
	fmag.run(prog, regs)
	testing.expect(t, math.abs(regs[0] - 2) < 1e-5)
	testing.expect(t, math.abs(regs[1] - 4) < 1e-5)
	testing.expect(t, math.abs(regs[2] - 6) < 1e-5)
	regs[0] = -1
	regs[1] = 1
	regs[2] = 2
	regs[3] = 3
	fmag.run(prog, regs)
	testing.expect(t, math.abs(regs[0] - 1) < 1e-5)
	testing.expect(t, math.abs(regs[1] - 2) < 1e-5)
	testing.expect(t, math.abs(regs[2] - 3) < 1e-5)
}

@(test)
test_compile_fmag_helper_if :: proc(t: ^testing.T) {
	src := `
absish :: proc(x: f32) -> f32 {
	if x < 0 {
		return -x
	}
	return x
}
k :: proc "fmag"(x: f32) -> f32 {
	return absish(x)
}
`
	prog, ok := fmag_test_compile(t, src, "k")
	if !ok do return
	defer delete(([^]u8)(prog.stream.data)[:int(prog.stream.size)])
	regs := make([]f32, max(int(prog.header.regs), 1))
	defer delete(regs)
	regs[0] = -4
	fmag.run(prog, regs)
	testing.expect(t, math.abs(regs[0] - 4) < 1e-5)
}

@(test)
test_compile_fmag_lerp_vec :: proc(t: ^testing.T) {
	src := `
shade :: proc "fmag"(a: [3]f32, b: [3]f32, t: f32) -> [3]f32 {
	return lerp(a, b, t)
}
`
	prog, ok := fmag_test_compile(t, src, "shade")
	if !ok do return
	defer delete(([^]u8)(prog.stream.data)[:int(prog.stream.size)])
	regs := make([]f32, max(int(prog.header.regs), 7))
	defer delete(regs)
	regs[0] = 0
	regs[1] = 0
	regs[2] = 0
	regs[3] = 1
	regs[4] = 2
	regs[5] = 3
	regs[6] = 0.5
	fmag.run(prog, regs)
	testing.expect(t, math.abs(regs[0] - 0.5) < 1e-5)
	testing.expect(t, math.abs(regs[1] - 1.0) < 1e-5)
	testing.expect(t, math.abs(regs[2] - 1.5) < 1e-5)
}

@(test)
test_compile_fmag_pbr_shade :: proc(t: ^testing.T) {
	src := `
vec3 :: [3]f32
shade :: proc "fmag"(
	ndv: f32, ndl: f32, ldh: f32, vdh: f32,
	albedo: [3]f32,
	metallic: f32, roughness: f32,
	D: f32, G: f32,
	light: f32,
) -> [3]f32 {
	f0 := lerp(vec3(0.04, 0.04, 0.04), albedo, metallic)
	one_m := 1 - metallic
	f90 := 0.5 + 2 * ldh * ldh * roughness
	oml := 1 - ndl
	omv := 1 - ndv
	oml2 := oml * oml
	omv2 := omv * omv
	fl := 1 + (f90 - 1) * oml2 * oml2 * oml
	fv := 1 + (f90 - 1) * omv2 * omv2 * omv
	burley := 0.318309886 * fl * fv
	diff := albedo * one_m * burley
	omh := 1 - vdh
	omh2 := omh * omh
	F := f0 + (1 - f0) * omh2 * omh2 * omh
	spec := D * G * F * ndl
	return (diff + spec) * vec3(3, 2.8, 2.5) * light
}
`
	prog, ok := fmag_test_compile(t, src, "shade")
	if !ok do return
	defer delete(([^]u8)(prog.stream.data)[:int(prog.stream.size)])
	testing.expect(t, prog.header.args == 12)
	testing.expect(t, prog.header.rets == 3)
	testing.expect(t, prog.header.regs <= FMAG_REGS)

	ndv, ndl, ldh, vdh: f32 = 0.7, 0.6, 0.5, 0.55
	albedo := [3]f32{0.72, 0.12, 0.08}
	metallic, roughness, D, G, light: f32 = 0.4, 0.3, 0.8, 0.9, 1.5
	want := fmag_shade_cpu(ndv, ndl, ldh, vdh, albedo, metallic, roughness, D, G, light)
	regs := make([]f32, max(int(prog.header.regs), 12))
	defer delete(regs)
	regs[0] = ndv
	regs[1] = ndl
	regs[2] = ldh
	regs[3] = vdh
	regs[4] = albedo[0]
	regs[5] = albedo[1]
	regs[6] = albedo[2]
	regs[7] = metallic
	regs[8] = roughness
	regs[9] = D
	regs[10] = G
	regs[11] = light
	fmag.run(prog, regs)
	testing.expect(t, math.abs(regs[0] - want[0]) < 1e-4)
	testing.expect(t, math.abs(regs[1] - want[1]) < 1e-4)
	testing.expect(t, math.abs(regs[2] - want[2]) < 1e-4)
}

fmag_shade_cpu :: proc(
	ndv, ndl, ldh, vdh: f32,
	albedo: [3]f32,
	metallic, roughness, D, G, light: f32,
) -> [3]f32 {
	f0: [3]f32
	for i in 0 ..< 3 {
		f0[i] = 0.04 + (albedo[i] - 0.04) * metallic
	}
	one_m := 1 - metallic
	f90 := 0.5 + 2 * ldh * ldh * roughness
	oml := 1 - ndl
	omv := 1 - ndv
	oml2 := oml * oml
	omv2 := omv * omv
	fl := 1 + (f90 - 1) * oml2 * oml2 * oml
	fv := 1 + (f90 - 1) * omv2 * omv2 * omv
	burley := 0.318309886 * fl * fv
	omh := 1 - vdh
	omh2 := omh * omh
	p5 := omh2 * omh2 * omh
	scale := [3]f32{3, 2.8, 2.5}
	out: [3]f32
	for i in 0 ..< 3 {
		diff := albedo[i] * one_m * burley
		F := f0[i] + (1 - f0[i]) * p5
		spec := D * G * F * ndl
		out[i] = (diff + spec) * scale[i] * light
	}
	return out
}

f32_ulp_dist :: proc(a, b: f32) -> u32 {
	if a == b {
		return 0
	}
	ordered :: proc(x: f32) -> u32 {
		u := transmute(u32)x
		if u >= 0x8000_0000 {
			return ~u
		}
		return u + 0x8000_0000
	}
	au := ordered(a)
	bu := ordered(b)
	return au >= bu ? au - bu : bu - au
}

fmag_expect_unary_f32 :: proc(t: ^testing.T, src: string, x, want: f32, max_ulp: u32, loc := #caller_location) {
	prog, ok := fmag_test_compile(t, src, "k")
	if !ok {
		return
	}
	defer delete(([^]u8)(prog.stream.data)[:int(prog.stream.size)])
	if !testing.expectf(t, prog.header.regs <= FMAG_REGS, "regs=%v > %v", prog.header.regs, FMAG_REGS, loc = loc) {
		return
	}
	regs := make([]f32, max(int(prog.header.regs), 1))
	defer delete(regs)
	regs[0] = x
	fmag.run(prog, regs)
	d := f32_ulp_dist(regs[0], want)
	testing.expectf(t, d <= max_ulp, "x=%v got=%v want=%v ulp=%v max=%v", x, regs[0], want, d, max_ulp, loc = loc)
}

@(test)
test_parse_misl_hex_float :: proc(t: ^testing.T) {
	v, ok := parse_misl_float_literal("0h3F800000")
	testing.expect(t, ok)
	testing.expect(t, f32(v) == 1)
	v2, ok2 := parse_misl_float_literal("2.5")
	testing.expect(t, ok2)
	testing.expect(t, v2 == 2.5)
}

@(test)
test_compile_fmag_math_trig :: proc(t: ^testing.T) {
	src := `
k :: proc "fmag"(x: f32) -> f32 {
	return sin(x)
}
`
	fmag_expect_unary_f32(t, src, 0.5, math.sin_f32(0.5), 1)
	src_v := `
k :: proc "fmag"(v: [2]f32) -> [2]f32 {
	return sin(v)
}
`
	prog, ok := fmag_test_compile(t, src_v, "k")
	if !ok {
		return
	}
	defer delete(([^]u8)(prog.stream.data)[:int(prog.stream.size)])
	testing.expect(t, prog.header.regs <= FMAG_REGS)
	regs := make([]f32, max(int(prog.header.regs), 2))
	defer delete(regs)
	regs[0] = 0.5
	regs[1] = 1.0
	fmag.run(prog, regs)
	testing.expect(t, f32_ulp_dist(regs[0], math.sin_f32(0.5)) <= 1)
	testing.expect(t, f32_ulp_dist(regs[1], math.sin_f32(1.0)) <= 1)
}

@(test)
test_compile_fmag_math_sqrt :: proc(t: ^testing.T) {
	src := `
k :: proc "fmag"(x: f32) -> f32 {
	return sqrt(x)
}
`
	fmag_expect_unary_f32(t, src, 4.0, 2.0, 0)
	src_is := `
k :: proc "fmag"(x: f32) -> f32 {
	return isqrt(x)
}
`
	fmag_expect_unary_f32(t, src_is, 4.0, 0.5, 2)
	src_v := `
k :: proc "fmag"(v: [2]f32) -> [2]f32 {
	return sqrt(v)
}
`
	prog, ok := fmag_test_compile(t, src_v, "k")
	if !ok {
		return
	}
	defer delete(([^]u8)(prog.stream.data)[:int(prog.stream.size)])
	testing.expect(t, prog.header.regs <= FMAG_REGS)
	regs := make([]f32, max(int(prog.header.regs), 2))
	defer delete(regs)
	regs[0] = 9.0
	regs[1] = 16.0
	fmag.run(prog, regs)
	testing.expect(t, f32_ulp_dist(regs[0], 3.0) <= 0)
	testing.expect(t, f32_ulp_dist(regs[1], 4.0) <= 0)
}

@(test)
test_compile_fmag_math_exp_log_pow :: proc(t: ^testing.T) {
	src_e := `
k :: proc "fmag"(x: f32) -> f32 {
	return exp(x)
}
`
	fmag_expect_unary_f32(t, src_e, 1.0, math.exp_f32(1.0), 1)
	src_l := `
k :: proc "fmag"(x: f32) -> f32 {
	return log(x)
}
`
	fmag_expect_unary_f32(t, src_l, math.exp_f32(1.0), 1.0, 1)
	src_p := `
k :: proc "fmag"(x: f32) -> f32 {
	return pow(x, 3.0)
}
`
	fmag_expect_unary_f32(t, src_p, 2.0, 8.0, 4)
	src_v := `
k :: proc "fmag"(v: [2]f32) -> [2]f32 {
	return exp2(v)
}
`
	prog, ok := fmag_test_compile(t, src_v, "k")
	if !ok {
		return
	}
	defer delete(([^]u8)(prog.stream.data)[:int(prog.stream.size)])
	testing.expect(t, prog.header.regs <= FMAG_REGS)
	regs := make([]f32, max(int(prog.header.regs), 2))
	defer delete(regs)
	regs[0] = 1.0
	regs[1] = 3.0
	fmag.run(prog, regs)
	testing.expect(t, f32_ulp_dist(regs[0], 2.0) <= 1)
	testing.expect(t, f32_ulp_dist(regs[1], 8.0) <= 1)
}

@(test)
test_compile_fmag_math_rounding :: proc(t: ^testing.T) {
	src_f := `
k :: proc "fmag"(x: f32) -> f32 {
	return floor(x)
}
`
	fmag_expect_unary_f32(t, src_f, 2.3, 2.0, 0)
	src_r := `
k :: proc "fmag"(x: f32) -> f32 {
	return round_even(x)
}
`
	fmag_expect_unary_f32(t, src_r, 2.5, 2.0, 0)
	src_v := `
k :: proc "fmag"(v: [2]f32) -> [2]f32 {
	return ceil(v)
}
`
	prog, ok := fmag_test_compile(t, src_v, "k")
	if !ok {
		return
	}
	defer delete(([^]u8)(prog.stream.data)[:int(prog.stream.size)])
	testing.expect(t, prog.header.regs <= FMAG_REGS)
	regs := make([]f32, max(int(prog.header.regs), 2))
	defer delete(regs)
	regs[0] = 1.1
	regs[1] = -1.1
	fmag.run(prog, regs)
	testing.expect(t, f32_ulp_dist(regs[0], 2.0) <= 0)
	testing.expect(t, f32_ulp_dist(regs[1], -1.0) <= 0)
}

@(test)
test_compile_fmag_math_frexp :: proc(t: ^testing.T) {
	src := `
k :: proc "fmag"(x: f32) -> [2]f32 {
	e, m := frexp(x)
	return [2]f32{e, m}
}
`
	prog, ok := fmag_test_compile(t, src, "k")
	if !ok {
		return
	}
	defer delete(([^]u8)(prog.stream.data)[:int(prog.stream.size)])
	testing.expect(t, prog.header.regs <= FMAG_REGS)
	regs := make([]f32, max(int(prog.header.regs), 2))
	defer delete(regs)
	x: f32 = 6.0
	regs[0] = x
	fmag.run(prog, regs)
	recon := regs[1] * math.pow2_f32(regs[0])
	testing.expect(t, f32_ulp_dist(recon, x) <= 0)
	testing.expect(t, regs[1] >= 0.5 && regs[1] < 1.0)
}
