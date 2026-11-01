package misl

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

// Decimal floats plus Odin-style IEEE hex (`0h` + 4/8/16 digits → f16/f32/f64 bits).
parse_misl_float_literal :: proc(text: string) -> (f64, bool) {
	if len(text) >= 3 && text[0] == '0' && (text[1] == 'h' || text[1] == 'H') {
		n: u64
		digits: int
		for r in text[2:] {
			if r == '_' {
				continue
			}
			v: u64
			switch r {
			case '0' ..= '9':
				v = u64(r - '0')
			case 'a' ..= 'f':
				v = u64(r - 'a' + 10)
			case 'A' ..= 'F':
				v = u64(r - 'A' + 10)
			case:
				return 0, false
			}
			n = (n << 4) | v
			digits += 1
		}
		switch digits {
		case 4:
			return f64(transmute(f16)u16(n)), true
		case 8:
			return f64(transmute(f32)u32(n)), true
		case 16:
			return transmute(f64)n, true
		}
		return 0, false
	}
	return strconv.parse_f64(text)
}

// Empty `string` is nil-able, so a bare `""` in Exact_Value collapses to union nil.
// Keep a non-nil data pointer with length 0 so empty compile-time strings are real values.
exact_empty_backing: [1]u8

exact_string :: proc(s: string) -> Exact_Value {
	if len(s) == 0 {
		return string(exact_empty_backing[:0])
	}
	return s
}

exact_value_is_compound :: proc(v: Exact_Value) -> bool {
	_, ok := v.(^Expr)
	return ok
}

exact_values_equal :: proc(a, b: Exact_Value) -> bool {
	if a == nil && b == nil do return true
	if a == nil || b == nil do return false
	#partial switch av in a {
	case string:
		bv, ok := b.(string)
		return ok && av == bv
	case i128:
		bv, ok := b.(i128)
		return ok && av == bv
	case f64:
		bv, ok := b.(f64)
		return ok && av == bv
	case bool:
		bv, ok := b.(bool)
		return ok && av == bv
	case ^Entity:
		bv, ok := b.(^Entity)
		return ok && av == bv
	}
	return false
}

fnv32a_bytes :: proc(data: []u8) -> u32 {
	h: u32 = 2166136261
	for b in data {
		h ~= u32(b)
		h *= 16777619
	}
	return h
}

exact_value_fnv32 :: proc(v: Exact_Value) -> u32 {
	#partial switch val in v {
	case string:
		return fnv32a_bytes(transmute([]u8)val)
	case i128:
		x := val
		return fnv32a_bytes(([^]u8)(&x)[:size_of(i128)])
	case f64:
		x := val
		return fnv32a_bytes(([^]u8)(&x)[:size_of(f64)])
	case bool:
		b: u8 = 1 if val else 0
		return fnv32a_bytes([]u8{b})
	case ^Entity:
		if val == nil do return 0
		x := val.id
		return fnv32a_bytes(([^]u8)(&x)[:size_of(u64)])
	}
	return 0
}

poly_const_key_hash :: proc(e: ^Entity) -> u32 {
	if e == nil || e.type == nil do return 0
	proc_t, ok := e.type.derived.(^Type_Proc)
	if !ok do return 0
	h: u32 = 2166136261
	for p in proc_t.params.variables {
		if .Poly_Const not_in p.flags do continue
		ph := exact_value_fnv32(p.value)
		h ~= ph
		h *= 16777619
	}
	return h
}

entity_is_poly_const :: proc(e: ^Entity) -> bool {
	return e != nil && .Poly_Const in e.flags
}

proc_is_generic_template :: proc(t: ^Type_Proc) -> bool {
	return t != nil && t.is_polymorphic && !t.is_poly_specialized
}

hex_digit_val :: proc(c: u8) -> (int, bool) {
	switch c {
	case '0'..='9': return int(c - '0'), true
	case 'a'..='f': return int(c - 'a' + 10), true
	case 'A'..='F': return int(c - 'A' + 10), true
	}
	return 0, false
}

unescape_quoted_bytes :: proc(text: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	i := 0
	for i < len(text) {
		if text[i] == '\\' && i + 1 < len(text) {
			i += 1
			switch text[i] {
			case 'a':
				strings.write_byte(&b, 0x07)
				i += 1
			case 'b':
				strings.write_byte(&b, '\b')
				i += 1
			case 'e':
				strings.write_byte(&b, 0x1b)
				i += 1
			case 'f':
				strings.write_byte(&b, '\f')
				i += 1
			case 'n':
				strings.write_byte(&b, '\n')
				i += 1
			case 'r':
				strings.write_byte(&b, '\r')
				i += 1
			case 't':
				strings.write_byte(&b, '\t')
				i += 1
			case 'v':
				strings.write_byte(&b, '\v')
				i += 1
			case '\\', '"', '\'':
				strings.write_byte(&b, text[i])
				i += 1
			case 'x':
				i += 1
				val := 0
				n := 0
				for n < 2 && i < len(text) {
					d, ok := hex_digit_val(text[i])
					if !ok do break
					val = val * 16 + d
					i += 1
					n += 1
				}
				strings.write_byte(&b, u8(val))
			case 'u':
				i += 1
				val := 0
				for _ in 0..<4 {
					if i >= len(text) do break
					d, ok := hex_digit_val(text[i])
					if !ok do break
					val = val * 16 + d
					i += 1
				}
				strings.write_rune(&b, rune(val))
			case 'U':
				i += 1
				val := 0
				for _ in 0..<8 {
					if i >= len(text) do break
					d, ok := hex_digit_val(text[i])
					if !ok do break
					val = val * 16 + d
					i += 1
				}
				strings.write_rune(&b, rune(val))
			case '0'..='7':
				val := 0
				for n := 0; n < 3 && i < len(text); n += 1 {
					c := text[i]
					if c < '0' || c > '7' do break
					val = val * 8 + int(c - '0')
					i += 1
				}
				strings.write_byte(&b, u8(val))
			case:
				strings.write_byte(&b, text[i])
				i += 1
			}
		} else {
			strings.write_byte(&b, text[i])
			i += 1
		}
	}
	return strings.to_string(b)
}

// Quoted lexer text is the interior (no quotes). Raw lexer text includes backticks.
unescape_misl_string :: proc(tok_text: string, allocator := context.allocator) -> string {
	if len(tok_text) >= 2 && tok_text[0] == '`' && tok_text[len(tok_text) - 1] == '`' {
		return strings.clone(tok_text[1:len(tok_text) - 1], allocator)
	}
	return unescape_quoted_bytes(tok_text, allocator)
}

parse_rune_literal :: proc(text: string) -> (r: rune, ok: bool) {
	if len(text) < 3 || text[0] != '\'' || text[len(text) - 1] != '\'' {
		return 0, false
	}
	inner := unescape_quoted_bytes(text[1:len(text) - 1])
	rr, n := utf8.decode_rune(inner)
	if n == 0 || (rr == utf8.RUNE_ERROR && n == 1) {
		if len(inner) == 1 {
			return rune(inner[0]), true
		}
		return 0, false
	}
	rest := inner[n:]
	if len(rest) != 0 {
		return 0, false
	}
	return rr, true
}

rune_utf8_size :: proc(r: rune) -> int {
	_, n := utf8.encode_rune(r)
	return n
}

rune_fits_unsigned :: proc(r: rune, size: int) -> bool {
	n := rune_utf8_size(r)
	return n > 0 && n <= size
}

untyped_int_fits_rune :: proc(v: i128) -> bool {
	return v >= 0 && v <= i128(utf8.MAX_RUNE)
}

compound_assign_binary_op :: proc(kind: Token_Kind) -> (Token_Kind, bool) {
	#partial switch kind {
	case .Add_Eq: return .Add, true
	case .Sub_Eq: return .Sub, true
	case .Mul_Eq: return .Mul, true
	case .Quo_Eq: return .Quo, true
	case .Mod_Eq: return .Mod, true
	case .And_Eq: return .And, true
	case .Or_Eq: return .Or, true
	case .Xor_Eq: return .Xor, true
	case .And_Not_Eq: return .And_Not, true
	case .Shl_Eq: return .Shl, true
	case .Shr_Eq: return .Shr, true
	}
	return kind, false
}

zero_exact_for_type :: proc(t: ^Type) -> Exact_Value {
	if type_is_boolean(t) do return exact_bool(false)
	if type_is_float(t) do return exact_float(0)
	return exact_int(0)
}

const_array_elem_value :: proc(value: Exact_Value, index: int, elem_type: ^Type) -> (Exact_Value, bool) {
	expr, ok := value.(^Expr)
	if !ok || expr == nil do return nil, false
	lit, is_lit := expr.derived.(^Comp_Lit)
	if !is_lit do return nil, false
	if len(lit.elems) == 0 {
		return zero_exact_for_type(elem_type), true
	}
	if index < 0 || index >= len(lit.elems) do return nil, false
	elem := lit.elems[index]
	if fv, is_fv := elem.derived.(^Field_Value); is_fv {
		elem = fv.value
	}
	if elem == nil || elem.tav.value == nil {
		return zero_exact_for_type(elem_type), true
	}
	return elem.tav.value, true
}

glsl_safe_string_comment :: proc(s: string, allocator := context.temp_allocator) -> string {
	return fmt.tprintf("%q", s)
}

integer_type_limits :: proc(type: ^Type) -> (lo, hi: i128, ok: bool) {
	t := type_base(type)
	if t == nil do return
	if bs, is_bs := t.derived.(^Type_Bit_Set); is_bs {
		t = bs.underlying
	}
	s, sok := t.derived.(^Type_Scalar)
	if !sok || .Integer not_in s.flags || s.size <= 0 do return
	bits := uint(s.size * 8)
	if bits > 127 do return
	if .Unsigned in s.flags {
		return 0, (i128(1) << bits) - 1, true
	}
	hi = (i128(1) << (bits - 1)) - 1
	lo = -hi - 1
	return lo, hi, true
}

exact_value_is_numeric :: proc(value: Exact_Value) -> bool {
	#partial switch _ in value {
	case i128:
		return true
	case f64:
		return true
	case bool:
		return true
	}
	return false
}

// Explicit `cast(T)` / `T(x)`: truncate finite floats toward zero into integers.
// Implicit conversion must not call this (untyped float is not an i32).
convert_exact_value_for_type :: proc(value: Exact_Value, dest: ^Type) -> (out: Exact_Value, ok: bool) {
	if value == nil || dest == nil || dest == t_invalid do return value, true
	if type_is_untyped(dest) do return value, true
	t := type_base(dest)
	if bs, is_bs := t.derived.(^Type_Bit_Set); is_bs {
		t = bs.underlying
	}
	s, sok := t.derived.(^Type_Scalar)
	if !sok do return value, true
	if .Integer in s.flags {
		n: i128
		#partial switch v in value {
		case i128:
			n = v
		case f64:
			if math.is_nan(v) || math.is_inf(v) do return nil, false
			n = i128(v)
		case bool:
			n = 1 if v else 0
		case:
			return nil, false
		}
		return exact_int(n), true
	}
	if .Float in s.flags {
		#partial switch v in value {
		case i128:
			return value, true
		case f64:
			return value, true
		case bool:
			return exact_float(1 if v else 0), true
		}
		return nil, false
	}
	if .Boolean in s.flags {
		#partial switch v in value {
		case bool:
			return value, true
		case i128:
			return exact_int(1 if v != 0 else 0), true
		case f64:
			if math.is_nan(v) || math.is_inf(v) do return nil, false
			return exact_int(1 if v != 0 else 0), true
		}
		return nil, false
	}
	return value, true
}

exact_value_fits_type :: proc(value: Exact_Value, type: ^Type) -> bool {
	if value == nil || type == nil || type == t_invalid do return true
	if type_is_untyped(type) do return true
	t := type_base(type)
	if bs, is_bs := t.derived.(^Type_Bit_Set); is_bs {
		t = bs.underlying
	}
	s, ok := t.derived.(^Type_Scalar)
	if !ok do return true
	if .Integer in s.flags {
		n: i128
		#partial switch v in value {
		case i128:
			n = v
		case f64:
			return false
		case:
			return true
		}
		lo, hi, lok := integer_type_limits(t)
		return lok && n >= lo && n <= hi
	}
	if .Float in s.flags {
		x: f64
		#partial switch v in value {
		case i128:
			x = f64(v)
		case f64:
			x = v
		case:
			return true
		}
		if math.is_nan(x) do return true
		if math.is_inf(x) do return false
		if s.kind == .f32 {
			return !math.is_inf(f32(x))
		}
		return true
	}
	return true
}

check_constant_fits :: proc(c: ^Checker, pos: Token_Pos, value: Exact_Value, type: ^Type) -> bool {
	if exact_value_fits_type(value, type) do return true
	check_err(c, pos, "constant value does not fit in '%s'", string_from_type(type))
	return false
}

// Fold a numeric constant through an explicit cast. Reports a fit error and
// returns ok=false when the truncated value is out of range. Non-numeric
// constants are not folded (ok=false, no new diagnostic).
fold_constant_cast :: proc(c: ^Checker, pos: Token_Pos, src: Exact_Value, dest: ^Type) -> (value: Exact_Value, ok: bool) {
	if !exact_value_is_numeric(src) do return nil, false
	converted, cok := convert_exact_value_for_type(src, dest)
	if !cok {
		check_err(c, pos, "constant value does not fit in '%s'", string_from_type(dest))
		return nil, false
	}
	if !check_constant_fits(c, pos, converted, dest) do return nil, false
	return converted, true
}
