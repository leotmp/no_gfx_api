package misl

import "core:fmt"
import "core:strings"

// --- Format scan / check ----------------------------------------------------

Printf_Slot_Kind :: enum {
	Compact, // %v
	Pretty,  // %#v
}

printf_count_slots :: proc(format: string) -> (count: int, err: string) {
	slots, ferr := printf_scan_slots(format, context.temp_allocator)
	if ferr != "" do return 0, ferr
	return len(slots), ""
}

// Returns one Compact (%v) / Pretty (%#v) entry per value slot. Allocates on `allocator`.
printf_scan_slots :: proc(format: string, allocator := context.temp_allocator) -> (slots: []Printf_Slot_Kind, err: string) {
	list := make([dynamic]Printf_Slot_Kind, allocator)
	i := 0
	for i < len(format) {
		if format[i] != '%' {
			i += 1
			continue
		}
		if i + 1 >= len(format) {
			return nil, "incomplete format specifier at end of string"
		}
		switch format[i + 1] {
		case '%':
			i += 2
		case 'v':
			append(&list, Printf_Slot_Kind.Compact)
			i += 2
		case '#':
			if i + 2 >= len(format) || format[i + 2] != 'v' {
				return nil, "expected '%#v' in printf format"
			}
			append(&list, Printf_Slot_Kind.Pretty)
			i += 3
		case:
			return nil, fmt.tprintf("unsupported printf specifier '%%%c' (only %%v, %%#v, and %%%% are allowed)", format[i + 1])
		}
	}
	return list[:], ""
}

printf_type_supported :: proc(type: ^Type) -> bool {
	if type == nil || type == t_invalid do return false
	#partial switch t in type.derived {
	case ^Type_Scalar:
		if .Untyped in t.flags {
			return type_is_numeric(type) || type_is_boolean(type)
		}
		return type_is_numeric(type) || type_is_boolean(type)
	case ^Type_Vector:
		return printf_type_supported(t.elem)
	case ^Type_Array:
		return printf_type_supported(t.elem)
	case ^Type_Matrix:
		return type_eq(t.elem, t_f32) || type_eq(t.elem, t_f64)
	case ^Type_Struct:
		for f in t.fields.variables {
			if !printf_type_supported(f.type) do return false
		}
		return true
	case ^Type_Pointer, ^Type_Multi_Pointer:
		return true
	case ^Type_Slice:
		return true
	case ^Type_Enum:
		return true
	case ^Type_Bit_Set:
		return true
	}
	return false
}

check_printf :: proc(checker: ^Checker, call: ^Call_Expr, id: Builtin_Proc) -> Operand {
	name := builtin_names[id]
	if len(call.args) < 1 {
		check_err(checker, call.pos, "'%s' expects a format string argument", name)
		return builtin_fail(checker, call)
	}

	fmt_op := check_expr(checker, call.args[0])
	if fmt_op.mode != .Constant {
		check_err(checker, call.args[0].pos, "'%s' format must be a constant string", name)
		return builtin_fail(checker, call)
	}
	format, is_str := fmt_op.value.(string)
	if !is_str {
		check_err(checker, call.args[0].pos, "'%s' format must be a constant string", name)
		return builtin_fail(checker, call)
	}

	slot_count, ferr := printf_count_slots(format)
	if ferr != "" {
		check_err(checker, call.args[0].pos, "%s", ferr)
		return builtin_fail(checker, call)
	}
	value_argc := len(call.args) - 1
	if value_argc != slot_count {
		check_err(checker, call.pos, "'%s' format has %d value slot%s, got %d argument%s",
			name,
			slot_count, "" if slot_count == 1 else "s",
			value_argc, "" if value_argc == 1 else "s")
		return builtin_fail(checker, call)
	}

	for i in 1 ..< len(call.args) {
		op := check_expr(checker, call.args[i])
		if op.mode == .Invalid do continue
		if type_is_untyped(op.type) {
			convert_to_typed(checker, &op, default_type(op.type))
			call.args[i].tav.type = op.type
			call.args[i].tav.mode = op.mode
			call.args[i].tav.value = op.value
		}
		if !printf_type_supported(op.type) {
			check_err(checker, call.args[i].pos, "'%s' cannot print type '%s'", name, string_from_type(op.type))
		}
	}

	return builtin_no_value(call, id)
}

// --- Expand IR --------------------------------------------------------------

Printf_Value_Arg :: struct {
	spec:      string,
	glsl_expr: string,
}

Printf_Print :: struct {
	format: string,
	args:   []Printf_Value_Arg,
}

Printf_Enum_Op :: struct {
	glsl_expr: string,
	enum_t:    ^Type_Enum,
}

Printf_Bit_Set_Op :: struct {
	glsl_expr: string,
	bs_t:      ^Type_Bit_Set,
	pretty:    bool,
	indent:    int,
}

Printf_Op :: union {
	Printf_Print,
	Printf_Enum_Op,
	Printf_Bit_Set_Op,
}

Printf_Builder :: struct {
	ops:  [dynamic]Printf_Op,
	fmt:  strings.Builder,
	args: [dynamic]Printf_Value_Arg,
}

printf_builder_flush :: proc(b: ^Printf_Builder) {
	if strings.builder_len(b.fmt) == 0 && len(b.args) == 0 do return
	op := Printf_Print {
		format = strings.clone(strings.to_string(b.fmt)),
		args   = make([]Printf_Value_Arg, len(b.args)),
	}
	copy(op.args, b.args[:])
	append(&b.ops, op)
	strings.builder_reset(&b.fmt)
	clear(&b.args)
}

printf_builder_lit :: proc(b: ^Printf_Builder, s: string) {
	strings.write_string(&b.fmt, s)
}

printf_builder_val :: proc(b: ^Printf_Builder, spec, glsl_expr: string) {
	strings.write_string(&b.fmt, spec)
	append(&b.args, Printf_Value_Arg{spec = spec, glsl_expr = glsl_expr})
}

printf_indent :: proc(n: int) -> string {
	if n <= 0 do return ""
	return strings.repeat("  ", n, context.temp_allocator)
}

printf_nl_indent :: proc(pretty: bool, indent: int) -> string {
	if !pretty do return ""
	return fmt.tprintf("\n%s", printf_indent(indent))
}

printf_sep :: proc(pretty: bool, indent: int) -> string {
	if pretty do return fmt.tprintf(",\n%s", printf_indent(indent))
	return ", "
}

printf_scalar_spec_and_cast :: proc(type: ^Type, glsl_base: string) -> (spec, expr: string, ok: bool) {
	type := default_type(type)
	#partial switch t in type.derived {
	case ^Type_Scalar:
		switch {
		case type_eq(type, t_f32):
			return "%f", glsl_base, true
		case type_eq(type, t_f64):
			return "%f", fmt.tprintf("float(%s)", glsl_base), true
		case type_eq(type, t_i32):
			return "%d", glsl_base, true
		case type_eq(type, t_u32), type_eq(type, t_b32):
			return "%u", glsl_base, true
		case type_eq(type, t_i8), type_eq(type, t_i16):
			return "%d", fmt.tprintf("int(%s)", glsl_base), true
		case type_eq(type, t_u8), type_eq(type, t_u16), type_eq(type, t_b8), type_eq(type, t_b16):
			return "%u", fmt.tprintf("uint(%s)", glsl_base), true
		case type_eq(type, t_i64):
			return "%lu", fmt.tprintf("uint64_t(%s)", glsl_base), true
		case type_eq(type, t_u64), type_eq(type, t_b64):
			return "%lu", glsl_base, true
		}
		// t32_2d/s32/rw32_2d (and 8/16-bit variants) are distinct scalar kinds with
		// unsigned integer backing — same GLSL types as u8/u16/u32.
		if .Integer in t.flags && .Unsigned in t.flags {
			switch t.size {
			case 1, 2:
				return "%u", fmt.tprintf("uint(%s)", glsl_base), true
			case 4:
				return "%u", glsl_base, true
			case 8:
				return "%lu", glsl_base, true
			}
		}
	}
	return "", "", false
}

printf_vector_fast_spec :: proc(v: ^Type_Vector) -> (spec: string, ok: bool) {
	letter: string
	switch {
	case type_eq(v.elem, t_f32): letter = "f"
	case type_eq(v.elem, t_i32): letter = "i"
	case type_eq(v.elem, t_u32): letter = "u"
	case: return "", false
	}
	if v.len < 2 || v.len > 4 do return "", false
	return fmt.tprintf("%%v%d%s", v.len, letter), true
}

printf_expand_type :: proc(b: ^Printf_Builder, type: ^Type, glsl_base: string, pretty: bool, indent: int) {
	type := default_type(type)

	#partial switch t in type.derived {
	case ^Type_Scalar:
		spec, expr, ok := printf_scalar_spec_and_cast(type, glsl_base)
		if ok {
			printf_builder_val(b, spec, expr)
		} else {
			printf_builder_lit(b, "<invalid>")
		}

	case ^Type_Enum:
		printf_builder_flush(b)
		append(&b.ops, Printf_Enum_Op{glsl_expr = glsl_base, enum_t = t})

	case ^Type_Bit_Set:
		if enum_t, is_enum := t.elem.derived.(^Type_Enum); is_enum {
			_ = enum_t
			printf_builder_flush(b)
			append(&b.ops, Printf_Bit_Set_Op{
				glsl_expr = glsl_base,
				bs_t      = t,
				pretty    = pretty,
				indent    = indent,
			})
		} else {
			// range bit_set → underlying scalar
			spec, expr, ok := printf_scalar_spec_and_cast(t.underlying, glsl_base)
			if ok {
				printf_builder_val(b, spec, expr)
			} else {
				printf_builder_lit(b, "<bit_set>")
			}
		}

	case ^Type_Pointer, ^Type_Multi_Pointer:
		printf_builder_val(b, "%p", glsl_base)

	case ^Type_Slice:
		printf_builder_lit(b, "{")
		printf_builder_lit(b, printf_nl_indent(pretty, indent + 1))
		printf_builder_lit(b, "data = ")
		printf_builder_val(b, "%p", fmt.tprintf("%s.data", glsl_base))
		printf_builder_lit(b, printf_sep(pretty, indent + 1))
		printf_builder_lit(b, "len = ")
		printf_builder_val(b, "%lu", fmt.tprintf("uint64_t(%s.len)", glsl_base))
		printf_builder_lit(b, printf_nl_indent(pretty, indent))
		printf_builder_lit(b, "}")

	case ^Type_Vector:
		if !pretty {
			if vspec, ok := printf_vector_fast_spec(t); ok {
				printf_builder_lit(b, "{")
				printf_builder_val(b, vspec, glsl_base)
				printf_builder_lit(b, "}")
				return
			}
		}
		printf_expand_sequence(b, t.len, t.elem, glsl_base, pretty, indent, index_style = .Bracket)

	case ^Type_Array:
		printf_expand_sequence(b, t.len, t.elem, glsl_base, pretty, indent, index_style = .Bracket)

	case ^Type_Matrix:
		printf_builder_lit(b, "{")
		printf_builder_lit(b, printf_nl_indent(pretty, indent + 1))
		for c in 0 ..< t.columns {
			if c > 0 {
				printf_builder_lit(b, printf_sep(pretty, indent + 1))
			}
			col := fmt.tprintf("%s[%d]", glsl_base, c)
			// column as brace-vector
			inner_pretty := pretty
			printf_expand_sequence(b, t.rows, t.elem, col, inner_pretty, indent + 1, index_style = .Bracket)
		}
		printf_builder_lit(b, printf_nl_indent(pretty, indent))
		printf_builder_lit(b, "}")

	case ^Type_Struct:
		printf_builder_lit(b, "{")
		printf_builder_lit(b, printf_nl_indent(pretty, indent + 1))
		for field, i in t.fields.variables {
			if i > 0 {
				printf_builder_lit(b, printf_sep(pretty, indent + 1))
			}
			fname := field.ir_name if field.ir_name != "" else field.name
			printf_builder_lit(b, fmt.tprintf("%s = ", field.name))
			printf_expand_type(b, field.type, fmt.tprintf("%s.%s", glsl_base, fname), pretty, indent + 1)
		}
		printf_builder_lit(b, printf_nl_indent(pretty, indent))
		printf_builder_lit(b, "}")

	case:
		printf_builder_lit(b, "<unsupported>")
	}
}

Printf_Index_Style :: enum {
	Bracket,
}

printf_expand_sequence :: proc(
	b: ^Printf_Builder,
	count: int,
	elem: ^Type,
	glsl_base: string,
	pretty: bool,
	indent: int,
	index_style: Printf_Index_Style,
) {
	printf_builder_lit(b, "{")
	if count == 0 {
		printf_builder_lit(b, "}")
		return
	}
	printf_builder_lit(b, printf_nl_indent(pretty, indent + 1))
	for i in 0 ..< count {
		if i > 0 {
			printf_builder_lit(b, printf_sep(pretty, indent + 1))
		}
		elem_expr := fmt.tprintf("%s[%d]", glsl_base, i)
		printf_expand_type(b, elem, elem_expr, pretty, indent + 1)
	}
	printf_builder_lit(b, printf_nl_indent(pretty, indent))
	printf_builder_lit(b, "}")
}
