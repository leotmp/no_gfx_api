package misl_ex

import "core:math"
import "oge:app"

// CPU hit-testing that matches core:s2h slider_float / print_lf / print_space
// (FONT_SIZE 8, set_cursor(16,16), scale 2). Shader SV_Data is read-only, so
// persisted values live here and are uploaded each frame.

S2H_FONT :: 8

@(private="file")
s2h_cap := -1

S2h_Lay :: struct {
	cursor:  [2]f32,
	left_x:  f32,
	scale:   f32,
	next_id: int,
}

s2h_ui_release :: proc() {
	s2h_cap = -1
}

s2h_panel :: proc(origin := [2]f32{16, 16}, scale: f32 = 2) -> S2h_Lay {
	return {cursor = origin, left_x = origin.x, scale = scale, next_id = 0}
}

s2h_lf :: proc(lay: ^S2h_Lay) {
	lay.cursor.x = lay.left_x
	lay.cursor.y += S2H_FONT * lay.scale
}

s2h_skip :: proc(lay: ^S2h_Lay, chars: f32) {
	lay.cursor.x += S2H_FONT * chars * lay.scale
}

s2h_slider_float :: proc(lay: ^S2h_Lay, width_in_characters: u32, value: ^f32, min_value, max_value: f32) {
	id := lay.next_id
	lay.next_id += 1
	mouse := s2h_mouse()
	scale := lay.scale
	outer_min := lay.cursor + 0.5
	outer_max := lay.cursor + [2]f32{f32(width_in_characters) * S2H_FONT, S2H_FONT - 2} * scale + 0.5
	inner_min := outer_min + [2]f32{1, 1} * scale
	inner_max := outer_max - [2]f32{1, 1} * scale
	over := mouse.x >= outer_min.x && mouse.x <= outer_max.x && mouse.y >= outer_min.y && mouse.y <= outer_max.y
	dragging := s2h_cap == id || (s2h_cap < 0 && over && mouse.z != 0)
	if dragging && mouse.z != 0 {
		s2h_cap = id
		span := inner_max.x - inner_min.x
		frac: f32 = 0
		if span > 0 {
			frac = clamp((mouse.x - inner_min.x) / span, 0, 1)
		}
		value^ = math.lerp(min_value, max_value, frac)
	}
	lay.cursor.x += f32(width_in_characters) * S2H_FONT * scale
}

s2h_slider_int :: proc(lay: ^S2h_Lay, width_in_characters: u32, value: ^i32, min_value, max_value: i32) {
	v := f32(value^)
	s2h_slider_float(lay, width_in_characters, &v, f32(min_value), f32(max_value))
	value^ = i32(math.round(v))
	if value^ < min_value {
		value^ = min_value
	}
	if value^ > max_value {
		value^ = max_value
	}
}

s2h_cycle_mode :: proc(mode: ^i32, count: i32) {
	if app.key_pressed(.Right) {
		mode^ = (mode^ + 1) %% count
	}
	if app.key_pressed(.Left) {
		mode^ = (mode^ + count - 1) %% count
	}
}

s2h_nudge_float :: proc(value: ^f32, min_value, max_value, units_per_second, dt: f32) {
	if app.key_down(.Up) {
		value^ = min(value^ + units_per_second * dt, max_value)
	}
	if app.key_down(.Down) {
		value^ = max(value^ - units_per_second * dt, min_value)
	}
}

// Skip the title row, then "mode " (5 chars) + 12-char slider. Shader overlays
// must print_lf after the title and use 5-character labels before each slider.
s2h_hud_mode :: proc(mode: ^i32, last: i32) {
	lay := s2h_panel()
	s2h_lf(&lay)
	s2h_skip(&lay, 5)
	s2h_slider_int(&lay, 12, mode, 0, last)
}

s2h_hud_mode_float :: proc(mode: ^i32, last: i32, param: ^f32, min_value, max_value: f32) {
	lay := s2h_panel()
	s2h_lf(&lay)
	s2h_skip(&lay, 5)
	s2h_slider_int(&lay, 12, mode, 0, last)
	s2h_lf(&lay)
	s2h_skip(&lay, 5)
	s2h_slider_float(&lay, 12, param, min_value, max_value)
}

s2h_hud_float :: proc(param: ^f32, min_value, max_value: f32) {
	lay := s2h_panel()
	s2h_lf(&lay)
	s2h_skip(&lay, 5)
	s2h_slider_float(&lay, 12, param, min_value, max_value)
}
