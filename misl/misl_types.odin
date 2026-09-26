package misl

import "core:fmt"
import "core:strings"
import vm "core:mem/virtual"

Scalar_Kind :: enum {
	Invalid,

	i8, i16, i32, i64,
	u8, u16, u32, u64,

	b8, b16, b32, b64,

	f32, f64,

	complex32, complex64, complex128,

	// Distinct resource ids (still integer scalars; kind differs so type_eq stays correct).
	// 2D views are t8_2d / t16_2d / t32_2d and rw8_2d / rw16_2d / rw32_2d.
	t8_2d, t16_2d, t32_2d,
	t8_1d, t16_1d, t32_1d,
	t8_3d, t16_3d, t32_3d,
	t8_cube, t16_cube, t32_cube,
	t8_1d_array, t16_1d_array, t32_1d_array,
	t8_2d_array, t16_2d_array, t32_2d_array,
	t8_cube_array, t16_cube_array, t32_cube_array,
	s8, s16, s32,
	s8_cmp, s16_cmp, s32_cmp,
	rw8_2d, rw16_2d, rw32_2d,
	rw8_1d, rw16_1d, rw32_1d,
	rw8_3d, rw16_3d, rw32_3d,
	rw8_cube, rw16_cube, rw32_cube,
	rw8_1d_array, rw16_1d_array, rw32_1d_array,
	rw8_2d_array, rw16_2d_array, rw32_2d_array,
	rw8_cube_array, rw16_cube_array, rw32_cube_array,
	bvh32,

	rune,
	Untyped_Rune,

	Untyped_Bool,
	Untyped_Integer,
	Untyped_Float,
	Untyped_Complex,
	Untyped_Nil,
	Untyped_Unint,
}

Scalar_Flags :: bit_set[Scalar_Flag]
Scalar_Flag :: enum {
	Boolean,
	Integer,
	Unsigned,
	Float,
	Complex,
	Untyped,
	Nil,
	Texture_Id,
	Sampler_Id,
	Compare_Sampler_Id,
	RW_Texture_Id,
	Bvh_Id,
	Rune,
}

Quaternion_Kind :: enum {
	Invalid,
	quat64, quat128, quat256,
	Untyped,
}

Atom_Kind :: enum {
	Invalid,
	string, rune,
	rawptr, uptr,
	any, typeid_,
	Ray_Query,
	Untyped_String, Untyped_Rune,
}

Atom_Flags :: bit_set[Atom_Flag]
Atom_Flag :: enum {
	Pointer,
	String,
	Rune,
	Untyped,
}

Typeid_Kind :: enum {
	Invalid,
	Integer,
	Rune,
	Float,
	Complex,
	Quaternion,
	String,
	Boolean,
	Any,
	Type_ID,
	Pointer,
	Procedure,
	Array,
	Enumerated_Array,
	Slice,
	Tuple,
	Struct,
	Enum,
	Bit_Set,
	Matrix,
}

Type_Info_Flags :: bit_set[Type_Info_Flag]
Type_Info_Flag :: enum {
	Comparable,
	Simple_Compare,
}

Type_Scalar :: struct {
	using base: Type,
	kind: Scalar_Kind,
	flags: Scalar_Flags,
	size: int,
	name: string,
}

Type_Quaternion :: struct {
	using base: Type,
	kind: Quaternion_Kind,
	size: int,
	name: string,
}

Type_Atom :: struct {
	using base: Type,
	kind: Atom_Kind,
	flags: Atom_Flags,
	size: int,
	name: string,
}

Type_Struct :: struct {
	using base: Type,
	scope: ^Scope,
	size: int,
	align: int,
	fields: ^Type_Tuple,
}

Type_Proc :: struct {
	using base: Type,
	scope: ^Scope,
	params, results: ^Type_Tuple,

	stage: Maybe(Stage),
	data_t: ^Type,
	local_size: [3]u32, // compute workgroup size; default 1,1,1
	is_polymorphic: bool,
	is_poly_specialized: bool,
	poly_origin: ^Entity,
	// Element types of device pointers/slices stored through in this procedure body
	device_store_elems: map[^Type]bool,
	// @shared locals hoisted to GLSL shared (compute entries only)
	shared_vars: [dynamic]^Entity,
	// barrier / memory_barrier_* used in this body (compute-only effect)
	uses_compute_sync: bool,
	// Non-empty inherited builtin stage gate. Empty + has_stage_gate=false → every stage.
	has_stage_gate: bool,
	stage_gate:     Builtin_Stages,
	gate_reason:    string, // builtin name that caused the gate (e.g. "fwidth")
	// proc "fmag" — FMAG bytecode entry, not a GPU pipeline stage.
	is_fmag: bool,
	// Unstaged helper uses something proc "fmag" cannot (if, fwidth, …). GPU entries ignore this.
	fmag_illegal:        bool,
	fmag_illegal_reason: string,
}

Type_Array :: struct {
	using base: Type,
	elem: ^Type,
	len: int,
	force_array: bool, // `#array [N]T` — not a vector even for [2..4] scalars
}

Type_Vector :: struct {
	using base: Type,
	elem: ^Type,
	len: int,
}

Type_Slice :: struct {
	using base: Type,
	elem: ^Type,
}

// [^]T — buffer device address / contiguous multipointer (no length)
Type_Multi_Pointer :: struct {
	using base: Type,
	elem: ^Type,
}

Type_Enum :: struct {
	using base: Type,
	fields: [dynamic]^Entity,
	node: ^Node,
	scope: ^Scope,
	base_type: ^Type,
	min_val, max_val: Exact_Value,
	min_val_index, max_val_index: int,
}

Type_Tuple :: struct {
	using base: Type,
	variables: [dynamic]^Entity,
}

Type_Bit_Set :: struct {
	using base: Type,
	elem: ^Type,
	underlying: ^Type,
	lower, upper: int,
	node: ^Node,
}

// Compile-time pipeline constant type (`name :: pipeline { ... }`)
Type_Pipeline :: struct {
	using base: Type,
}

Type_Matrix :: struct {
	using base: Type,
	elem: ^Type,
	rows, columns: int,
}

Type_Pointer :: struct {
	using base: Type,
	elem: ^Type,
}

Any_Type :: union {
	^Type_Scalar,
	^Type_Quaternion,
	^Type_Atom,
	^Type_Pointer,
	^Type_Multi_Pointer,
	^Type_Array,
	^Type_Vector,
	^Type_Slice,
	^Type_Struct,
	^Type_Enum,
	^Type_Tuple,
	^Type_Proc,
	^Type_Bit_Set,
	^Type_Pipeline,
	^Type_Matrix,
}

Type :: struct {
	derived: Any_Type,
	ir_name: string,
	name:    string, // declared type name (`Foo :: struct`), if any
}

scalar_has :: proc(s: ^Type_Scalar, flag: Scalar_Flag) -> bool {
	return flag in s.flags
}

type_scalar_has :: proc(t: ^Type, flag: Scalar_Flag) -> bool {
	s, ok := t.derived.(^Type_Scalar)
	return ok && flag in s.flags
}

type_split_tuple :: proc(type: ^Type) -> []^Type {
	if type == nil do return nil
	result := make([dynamic]^Type, context.temp_allocator)
	if tuple_t, is_tuple := type.derived.(^Type_Tuple); is_tuple {
		for var in tuple_t.variables do append(&result, var.type)
	} else {
		append(&result, type)
	}
	return result[:]
}

// Target type for binary mutual convert: untyped scalars broadcast against
// vector/matrix by converting to the element type, not the composite.
binary_convert_type :: proc(other: ^Type) -> ^Type {
	if other == nil do return nil
	#partial switch t in other.derived {
	case ^Type_Vector: return t.elem
	case ^Type_Matrix: return t.elem
	}
	return other
}

// Rank among untyped numeric kinds (higher wins in mutual conversion).
untyped_rank :: proc(t: ^Type) -> int {
	switch t {
	case t_untyped_bool:  return 0
	case t_untyped_int:   return 1
	case t_untyped_float: return 2
	}
	return -1
}

// Recursively stamp `type` onto untyped subexpressions. Unlike Odin, we always
// recurse into constant folds so folded literal ASTs stay correctly typed.
update_untyped_expr_type :: proc(e: ^Expr, type: ^Type) {
	if e == nil || type == nil || type == t_invalid do return

	#partial switch n in e.derived_expr {
	case ^Paren_Expr:
		update_untyped_expr_type(n.expr, type)
	case ^Unary_Expr:
		update_untyped_expr_type(n.expr, type)
	case ^Binary_Expr:
		if op_is_relation(n.op.kind) || op_is_logical(n.op.kind) {
			// Result is boolean; leave operand types alone.
		} else if n.op.kind == .Shl || n.op.kind == .Shr {
			update_untyped_expr_type(n.left, type)
		} else if n.op.kind == .In || n.op.kind == .Not_In {
			// Element / set keep their own types.
		} else {
			update_untyped_expr_type(n.left, type)
			update_untyped_expr_type(n.right, type)
		}
	case ^Ternary_If_Expr:
		update_untyped_expr_type(n.x, type)
		update_untyped_expr_type(n.y, type)
	case ^Ternary_When_Expr:
		update_untyped_expr_type(n.x, type)
		update_untyped_expr_type(n.y, type)
	}

	if e.tav.type == nil || type_is_untyped(e.tav.type) {
		e.tav.type = type
	}
}

// Coerce an untyped operand toward `target_type`, updating the AST recursively.
// Typed operands are left alone.
convert_to_typed :: proc(c: ^Checker, operand: ^Operand, target_type: ^Type) {
	if target_type == nil || target_type == t_invalid do return
	if operand == nil || operand.mode == .Invalid || operand.mode == .Type do return
	if operand.type == nil || !type_is_untyped(operand.type) do return

	if type_is_untyped(target_type) {
		if type_is_untyped_rune(operand.type) && type_is_untyped_int(target_type) {
			return
		}
		if type_is_untyped_int(operand.type) && type_is_untyped_rune(target_type) {
			if i, ok := operand.value.(i128); ok && !untyped_int_fits_rune(i) {
				operand.mode = .Invalid
				if c != nil && operand.expr != nil {
					check_err(c, operand.expr.pos, "untyped integer '%v' cannot convert to rune", i)
				}
				return
			}
			operand.type = target_type
			update_untyped_expr_type(operand.expr, target_type)
			return
		}
		if type_is_numeric(operand.type) && type_is_numeric(target_type) {
			if untyped_rank(operand.type) < untyped_rank(target_type) {
				operand.type = target_type
				update_untyped_expr_type(operand.expr, target_type)
			}
		} else if operand.type != target_type {
			operand.mode = .Invalid
			if c != nil && operand.expr != nil {
				check_err(c, operand.expr.pos, "cannot convert untyped '%s' to '%s'", string_from_type(operand.type), string_from_type(target_type))
			}
		}
		return
	}

	if !type_is_implicit_castable(operand.type, target_type) {
		operand.mode = .Invalid
		if c != nil && operand.expr != nil {
			check_err(c, operand.expr.pos, "cannot convert untyped '%s' to '%s'", string_from_type(operand.type), string_from_type(target_type))
		}
		return
	}

	if type_is_untyped_rune(operand.type) {
		if s, ok := target_type.derived.(^Type_Scalar); ok && .Integer in s.flags && .Rune not_in s.flags {
			if i, iok := operand.value.(i128); iok {
				if !rune_fits_unsigned(rune(i), s.size) {
					operand.mode = .Invalid
					if c != nil && operand.expr != nil {
						check_err(c, operand.expr.pos, "rune value does not fit in '%s'", string_from_type(target_type))
					}
					return
				}
			}
		}
	}
	if type_is_untyped_int(operand.type) && type_is_rune(target_type) {
		if i, ok := operand.value.(i128); ok && !untyped_int_fits_rune(i) {
			operand.mode = .Invalid
			if c != nil && operand.expr != nil {
				check_err(c, operand.expr.pos, "integer '%v' is not a valid rune", i)
			}
			return
		}
	}

	if operand.mode == .Constant && operand.value != nil && c != nil {
		pos := operand.expr.pos if operand.expr != nil else Token_Pos{}
		if !check_constant_fits(c, pos, operand.value, target_type) {
			operand.mode = .Invalid
			return
		}
	}

	update_untyped_expr_type(operand.expr, target_type)
	operand.type = target_type
}

// Silent coerce used by builtins (no new diagnostics). Prefer convert_to_typed
// when a Checker is available.
resolve_operand_type :: proc(op: ^Operand, ctx: ^Type) {
	if op == nil || ctx == nil do return
	if op.type == nil || !type_is_untyped(op.type) do return
	if !type_is_implicit_castable(op.type, ctx) do return
	update_untyped_expr_type(op.expr, ctx)
	op.type = ctx
}

type_matches_gen :: proc(t, gen_elem: ^Type) -> bool {
	if type_is_gen(t, gen_elem) do return true
	if type_is_untyped(t) && type_is_implicit_castable(t, gen_elem) do return true
	return false
}

type_is_matrix :: proc(type: ^Type) -> bool {
	_, ok := type.derived.(^Type_Matrix)
	return ok
}

type_is_vector :: proc(type: ^Type) -> bool {
	_, ok := type.derived.(^Type_Vector)
	return ok
}

type_is_scalar :: proc(type: ^Type) -> bool {
	_, ok := type.derived.(^Type_Scalar)
	return ok
}

type_base :: proc(type: ^Type) -> ^Type {
	if type == nil do return nil
	#partial switch t in type.derived {
	case ^Type_Enum:
		return type_base(t.base_type)
	case ^Type_Matrix:
		return type_base(t.elem)
	case ^Type_Vector:
		return type_base(t.elem)
	}
	return type
}

type_is_gen :: proc(type: ^Type, elem_type: ^Type) -> bool {
	elem, _ := type_gen_break(type)
	if elem == nil do return false
	scalar := elem.derived.(^Type_Scalar)
	return elem == elem_type || .Untyped in scalar.flags
}

type_is_gen_f32 :: proc(type: ^Type) -> bool {
	return type_is_gen(type, t_f32)
}

type_is_gen_i32 :: proc(type: ^Type) -> bool {
	return type_is_gen(type, t_i32)
}

type_gen_break :: proc(type: ^Type) -> (elem: ^Type, len: int) {
	#partial switch t in type.derived {
	case ^Type_Vector: return t.elem, t.len
	case ^Type_Scalar: return t, 1
	}
	return nil, 0
}

type_is_integer :: proc(type: ^Type) -> bool {
	if type == nil do return false
	type := type_base(type)
	if type == nil do return false
	s, ok := type.derived.(^Type_Scalar)
	if !ok do return false
	if .Nil in s.flags do return false
	return .Integer in s.flags
}

type_is_float :: proc(type: ^Type) -> bool {
	s, ok := type.derived.(^Type_Scalar)
	if !ok do return false
	if .Nil in s.flags do return false
	return .Float in s.flags
}

type_vector_elem :: proc(type: ^Type) -> ^Type {
	return type.derived.(^Type_Vector).elem
}

type_vector_len :: proc(type: ^Type) -> int {
	return cast(int)type.derived.(^Type_Vector).len
}

type_is_untyped_nil :: proc(t: ^Type) -> bool {
	s, ok := t.derived.(^Type_Scalar)
	return ok && .Nil in s.flags
}

type_is_complex :: proc(type: ^Type) -> bool {
	s, ok := type.derived.(^Type_Scalar)
	return ok && .Complex in s.flags
}

type_is_quaternion :: proc(type: ^Type) -> bool {
	_, ok := type.derived.(^Type_Quaternion)
	return ok
}

default_type :: proc(type: ^Type) -> ^Type {
	switch type {
	case t_untyped_float: return t_f32
	case t_untyped_int: return t_i32
	case t_untyped_bool: return t_b32
	case t_untyped_rune: return t_rune
	}
	return type
}

type_alignof :: proc(type: ^Type) -> int {
	switch t in type.derived {
	case ^Type_Scalar: return t.size
	case ^Type_Quaternion: return t.size
	case ^Type_Atom: return t.size
	case ^Type_Vector: return type_alignof(t.elem)
	case ^Type_Array: return type_alignof(t.elem)
	case ^Type_Struct: return t.align
	case ^Type_Slice: return 8
	case ^Type_Multi_Pointer: return 8
	case ^Type_Pointer: return 8
	case ^Type_Matrix: return type_alignof(t.elem)
	case ^Type_Enum: return type_alignof(t.base_type)
	case ^Type_Bit_Set: return type_alignof(t.underlying)
	case ^Type_Pipeline: return 0
	case ^Type_Tuple: return 0
	case ^Type_Proc: return 0
	}
	unreachable()
}

type_sizeof :: proc(type: ^Type) -> int {
	switch t in type.derived {
	case ^Type_Scalar: return t.size
	case ^Type_Quaternion: return t.size
	case ^Type_Atom: return t.size
	case ^Type_Vector: return t.len * type_sizeof(t.elem)
	case ^Type_Array: return t.len * type_sizeof(t.elem)
	case ^Type_Struct: return t.size
	case ^Type_Slice: return 16 // { data: [^]T, len: i64 } — Odin-matching fat slice
	case ^Type_Multi_Pointer: return 8
	case ^Type_Pointer: return 8
	case ^Type_Matrix: return t.columns * t.rows * type_sizeof(t.elem)
	case ^Type_Enum: return type_sizeof(t.base_type)
	case ^Type_Bit_Set: return type_sizeof(t.underlying)
	case ^Type_Pipeline: return 0
	case ^Type_Tuple: return 0
	case ^Type_Proc: return 0
	}
	unreachable()
}

type_is_numeric :: proc(type: ^Type) -> bool {
	s, ok := type.derived.(^Type_Scalar)
	if !ok do return false
	if .Nil in s.flags do return false
	return s.flags | {.Integer, .Float} != nil
}

type_is_boolean :: proc(type: ^Type) -> bool {
	if type == nil do return false
	s, ok := type.derived.(^Type_Scalar)
	return ok && .Boolean in s.flags
}

type_is_untyped :: proc(type: ^Type) -> bool {
	if type == nil do return false
	if s, ok := type.derived.(^Type_Scalar); ok {
		return .Untyped in s.flags
	}
	if a, ok := type.derived.(^Type_Atom); ok {
		return .Untyped in a.flags
	}
	return false
}

type_is_string :: proc(type: ^Type) -> bool {
	if type == nil do return false
	a, ok := type.derived.(^Type_Atom)
	return ok && .String in a.flags && .Untyped not_in a.flags
}

type_is_untyped_string :: proc(type: ^Type) -> bool {
	if type == nil do return false
	a, ok := type.derived.(^Type_Atom)
	return ok && .String in a.flags && .Untyped in a.flags
}

type_is_string_kind :: proc(type: ^Type) -> bool {
	return type_is_string(type) || type_is_untyped_string(type)
}

type_is_rune :: proc(type: ^Type) -> bool {
	if type == nil do return false
	s, ok := type.derived.(^Type_Scalar)
	return ok && .Rune in s.flags && .Untyped not_in s.flags
}

type_is_untyped_rune :: proc(type: ^Type) -> bool {
	if type == nil do return false
	s, ok := type.derived.(^Type_Scalar)
	return ok && .Rune in s.flags && .Untyped in s.flags
}

type_is_rune_value :: proc(type: ^Type) -> bool {
	return type_is_rune(type) || type_is_untyped_rune(type)
}

type_is_poly_const_ok :: proc(type: ^Type) -> bool {
	if type == nil do return false
	if type_is_string(type) do return true
	if type_is_rune(type) do return true
	if type_is_proc(type) do return true
	s, ok := type.derived.(^Type_Scalar)
	if !ok do return false
	if type_is_resource_id(type) do return false
	if .Untyped in s.flags do return false
	if .Rune in s.flags do return true
	return .Integer in s.flags || .Float in s.flags || .Boolean in s.flags
}

type_is_proc :: proc(type: ^Type) -> bool {
	if type == nil do return false
	_, ok := type.derived.(^Type_Proc)
	return ok
}

type_is_const_array_elem_ok :: proc(type: ^Type) -> bool {
	if type == nil do return false
	if type_is_rune(type) do return true
	s, ok := type.derived.(^Type_Scalar)
	if !ok do return false
	if type_is_resource_id(type) do return false
	if .Untyped in s.flags do return false
	return .Integer in s.flags || .Float in s.flags || .Boolean in s.flags || .Rune in s.flags
}

type_is_numeric_composite :: proc(type: ^Type) -> bool {
	if type_is_numeric(type) do return true
	if v, ok := type.derived.(^Type_Vector); ok {
		return type_is_numeric(v.elem)
	}
	if m, ok := type.derived.(^Type_Matrix); ok {
		return type_is_numeric(m.elem)
	}
	return false
}

type_is_castable :: proc(from: ^Type, to: ^Type) -> bool {
	if type_is_implicit_castable(from, to) do return true
	if type_is_numeric(from) && type_is_numeric(to) do return true
	if type_is_vector(from) && type_is_vector(to) do return type_vector_len(from) == type_vector_len(to)
	// enum ↔ integer (same spirit as Odin)
	if type_is_enum(from) && type_is_integer(to) do return true
	if type_is_integer(from) && type_is_enum(to) do return true
	if type_is_enum(from) && type_is_enum(to) do return true
	// bit_set ↔ integer backing
	if type_is_bit_set(from) && type_is_integer(to) do return true
	if type_is_integer(from) && type_is_bit_set(to) do return true
	// [^]T → ^T (same element)
	if mp, is_mp := from.derived.(^Type_Multi_Pointer); is_mp {
		if ptr, is_ptr := to.derived.(^Type_Pointer); is_ptr {
			return type_eq(mp.elem, ptr.elem)
		}
	}
	return false
}

type_is_implicit_castable :: proc(from, to: ^Type) -> bool {
	if from == nil || to == nil {
		return false
	}
	if type_is_untyped_string(from) && type_is_string(to) {
		return true
	}
	if type_is_untyped_rune(from) {
		if type_is_rune(to) do return true
		if s, ok := to.derived.(^Type_Scalar); ok {
			if .Integer in s.flags && .Unsigned in s.flags && !type_is_resource_id(to) && .Rune not_in s.flags {
				#partial switch s.kind {
				case .u8, .u16, .u32:
					return true
				}
			}
		}
		return false
	}
	if type_is_untyped_int(from) && type_is_rune(to) {
		return true
	}
	if type_eq(from, to) {
		return true
	}

	#partial switch from_type in from.derived {
	case ^Type_Scalar:
		if type_is_untyped_nil(from) {
			return false
		}
		if .Rune in from_type.flags {
			return type_is_rune(to)
		}
		if .Untyped in from_type.flags && type_is_numeric(from) {
			#partial switch to_type in to.derived {
			case: return false
			case ^Type_Scalar:
				switch {
				case .Integer in from_type.flags: return type_is_numeric(to)
				case .Float in from_type.flags: return .Float in to_type.flags
				}

			case ^Type_Vector:
				switch {
				case .Integer in from_type.flags: return type_is_numeric(to_type.elem)
				case .Float in from_type.flags: return type_is_float(to_type.elem)
				}

			case ^Type_Matrix:
				switch {
				case .Integer in from_type.flags: return type_is_numeric(to_type.elem)
				case .Float in from_type.flags: return type_is_float(to_type.elem)
				}
			}
		}
	}

	return false
}

type_is_pointer :: proc(type: ^Type) -> bool {
	if type == nil do return false
	_, ok := type.derived.(^Type_Pointer)
	return ok
}

type_pointer_elem :: proc(type: ^Type) -> ^Type {
	if type == nil do return nil
	p, ok := type.derived.(^Type_Pointer)
	if !ok do return nil
	return p.elem
}

type_is_multi_pointer :: proc(type: ^Type) -> bool {
	if type == nil do return false
	_, ok := type.derived.(^Type_Multi_Pointer)
	return ok
}

type_is_pipeline :: proc(type: ^Type) -> bool {
	if type == nil do return false
	_, ok := type.derived.(^Type_Pipeline)
	return ok
}

type_is_slice :: proc(type: ^Type) -> bool {
	if type == nil do return false
	_, ok := type.derived.(^Type_Slice)
	return ok
}

type_is_array :: proc(type: ^Type) -> bool {
	if type == nil do return false
	_, ok := type.derived.(^Type_Array)
	return ok
}

type_is_bit_set :: proc(type: ^Type) -> bool {
	if type == nil do return false
	_, ok := type.derived.(^Type_Bit_Set)
	return ok
}

type_is_enum :: proc(type: ^Type) -> bool {
	if type == nil do return false
	_, ok := type.derived.(^Type_Enum)
	return ok
}

type_has_operator :: proc(type: ^Type, op: Token_Kind) -> bool {
	return false
}

type_is_comparable :: proc(type: ^Type) -> bool {
	#partial switch _ in type.derived {
	case ^Type_Proc: return false
	case ^Type_Tuple: return false
	}
	return true
}

proc_cc_label :: proc(t: ^Type_Proc) -> string {
	if t == nil do return ""
	if t.is_fmag do return "fmag"
	if stage, ok := t.stage.?; ok {
		switch stage {
		case .Vertex:   return "vertex"
		case .Fragment: return "fragment"
		case .Compute:  return "compute"
		}
	}
	return ""
}

type_proc_string :: proc(t: ^Type_Proc) -> string {
	if t == nil do return "proc"
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	if cc := proc_cc_label(t); cc != "" {
		fmt.sbprintf(&b, "proc \"%s\"(", cc)
	} else {
		strings.write_string(&b, "proc(")
	}
	if t.params != nil {
		for p, i in t.params.variables {
			if i > 0 do strings.write_string(&b, ", ")
			strings.write_string(&b, string_from_type(p.type if p != nil else nil))
		}
	}
	strings.write_string(&b, ")")
	if t.results != nil && len(t.results.variables) > 0 {
		strings.write_string(&b, " -> ")
		if len(t.results.variables) == 1 {
			strings.write_string(&b, string_from_type(t.results.variables[0].type))
		} else {
			strings.write_string(&b, "(")
			for r, i in t.results.variables {
				if i > 0 do strings.write_string(&b, ", ")
				strings.write_string(&b, string_from_type(r.type if r != nil else nil))
			}
			strings.write_string(&b, ")")
		}
	}
	return strings.to_string(b)
}

string_from_type :: proc(type: ^Type) -> string {
	if type == nil do return "<nil>"
	switch v in type.derived {
	case ^Type_Scalar:
		return v.name
	case ^Type_Quaternion:
		return v.name
	case ^Type_Atom:
		return v.name
	case ^Type_Pointer:
		return fmt.tprintf("^%s", string_from_type(v.elem))
	case ^Type_Multi_Pointer:
		return fmt.tprintf("[^]%s", string_from_type(v.elem))
	case ^Type_Vector:
		return fmt.tprintf("[%d]%s", v.len, string_from_type(v.elem))
	case ^Type_Slice:
		return fmt.tprintf("[]%s", string_from_type(v.elem))
	case ^Type_Array:
		if v.force_array {
			return fmt.tprintf("#array [%d]%s", v.len, string_from_type(v.elem))
		}
		return fmt.tprintf("[%d]%s", v.len, string_from_type(v.elem))
	case ^Type_Struct:
		if type.name != "" {
			return type.name
		}
		return "struct"
	case ^Type_Tuple: return fmt.tprintf("tuple %v", v.variables)
	case ^Type_Proc:
		return type_proc_string(v)
	case ^Type_Matrix: return fmt.tprintf("matrix[%d, %d]%s", v.rows, v.columns, string_from_type(v.elem))
	case ^Type_Enum:
		if type.name != "" {
			return type.name
		}
		return "enum"
	case ^Type_Bit_Set:
		if type.name != "" {
			return type.name
		}
		return fmt.tprintf("bit_set[%s; %s]", string_from_type(v.elem), string_from_type(v.underlying))
	case ^Type_Pipeline:
		if type.name != "" {
			return type.name
		}
		return "pipeline"
	}
	unreachable()
}

new_type :: proc($T: typeid) -> ^T {
	t := new(T)
	t.derived = t
	base: ^Type = t
	_ = base
	return t
}

new_scalar_type :: proc(kind: Scalar_Kind, name: string, size: int, flags: Scalar_Flags, ir_name: string = "") -> ^Type_Scalar {
	t := new_type(Type_Scalar)
	t.flags = flags
	t.size = size
	t.name = name
	t.kind = kind
	t.ir_name = ir_name
	return t
}

new_quaternion_type :: proc(kind: Quaternion_Kind, name: string, size: int, ir_name: string = "") -> ^Type_Quaternion {
	t := new_type(Type_Quaternion)
	t.size = size
	t.name = name
	t.kind = kind
	t.ir_name = ir_name
	return t
}

new_atom_type :: proc(kind: Atom_Kind, name: string, size: int, flags: Atom_Flags, ir_name: string = "") -> ^Type_Atom {
	t := new_type(Type_Atom)
	t.flags = flags
	t.size = size
	t.name = name
	t.kind = kind
	t.ir_name = ir_name
	return t
}

Selection :: struct {
	entity: ^Entity,
	index: [dynamic]i32,
	indirect: bool,
	swizzle_count: u8,
	swizzle_indices: u8,
	pseudo_field: bool,
}

scalar_types: [Scalar_Kind]^Type
quaternion_types: [Quaternion_Kind]^Type
atom_types: [Atom_Kind]^Type

t_invalid: ^Type
t_pipeline: ^Type
t_b8 : ^Type
t_b16: ^Type
t_b32: ^Type
t_b64: ^Type
t_u8 : ^Type
t_u16: ^Type
t_u32: ^Type
t_u64: ^Type
t_i8 : ^Type
t_i16: ^Type
t_i32: ^Type
t_i64: ^Type
t_f32: ^Type
t_f64: ^Type
t_t8_2d: ^Type
t_t16_2d: ^Type
t_t32_2d: ^Type
t_s8: ^Type
t_s16: ^Type
t_s32: ^Type
t_s8_cmp: ^Type
t_s16_cmp: ^Type
t_s32_cmp: ^Type
t_rw8_2d: ^Type
t_rw16_2d: ^Type
t_rw32_2d: ^Type
t_bvh32: ^Type
t_ray_query: ^Type
t_untyped_bool: ^Type
t_untyped_int: ^Type
t_untyped_float: ^Type
t_untyped_string: ^Type
t_untyped_nil: ^Type
t_string: ^Type
t_rune: ^Type
t_untyped_rune: ^Type

core_types_initialized: bool
core_types_arena: vm.Arena

// Independent: must not reallocate — builtin module entities keep pointers into these types.
// Allocates into a process-lifetime arena (never the session/temp allocator). Host apps
// create/destroy many sessions; types must outlive every session.
init_core_types :: proc(allocator := context.allocator) {
	_ = allocator // ignored: core types are never session-scoped
	if core_types_initialized do return
	core_types_initialized = true
	err := vm.arena_init_growing(&core_types_arena)
	fmt.assertf(err == nil, "misl core types arena: %v", err)
	context.allocator = vm.arena_allocator(&core_types_arena)
	scalar_types = {
		.Invalid = new_scalar_type(.Invalid, "invalid type", 0, nil),

		.b8  = new_scalar_type(.b8,  "b8",  1,  {.Boolean}, "uint8_t"),
		.b16 = new_scalar_type(.b16, "b16", 2,  {.Boolean}, "uint16_t"),
		.b32 = new_scalar_type(.b32, "b32", 4,  {.Boolean}, "uint"),
		.b64 = new_scalar_type(.b64, "b64", 8,  {.Boolean}, "uint64_t"),

		.u8  = new_scalar_type(.u8,  "u8",  1, {.Integer, .Unsigned}, "uint8_t"),
		.u16 = new_scalar_type(.u16, "u16", 2, {.Integer, .Unsigned}, "uint16_t"),
		.u32 = new_scalar_type(.u32, "u32", 4, {.Integer, .Unsigned}, "uint"),
		.u64 = new_scalar_type(.u64, "u64", 8, {.Integer, .Unsigned}, "uint64_t"),

		.i8  = new_scalar_type(.i8,  "i8",  1, {.Integer}, "int8_t"),
		.i16 = new_scalar_type(.i16, "i16", 2, {.Integer}, "int16_t"),
		.i32 = new_scalar_type(.i32, "i32", 4, {.Integer}, "int"),
		.i64 = new_scalar_type(.i64, "i64", 8, {.Integer}, "int64_t"),

		.f32 = new_scalar_type(.f32, "f32", 4, {.Float}, "float"),
		.f64 = new_scalar_type(.f64, "f64", 8, {.Float}, "double"),

		.complex32  = new_scalar_type(.complex32,  "complex32",  4,  {.Complex}),
		.complex64  = new_scalar_type(.complex64,  "complex64",  8,  {.Complex}),
		.complex128 = new_scalar_type(.complex128, "complex128", 16, {.Complex}),

		.t8_2d  = new_scalar_type(.t8_2d,  "t8_2d",  1, {.Integer, .Unsigned, .Texture_Id}, "uint8_t"),
		.t16_2d = new_scalar_type(.t16_2d, "t16_2d", 2, {.Integer, .Unsigned, .Texture_Id}, "uint16_t"),
		.t32_2d = new_scalar_type(.t32_2d, "t32_2d", 4, {.Integer, .Unsigned, .Texture_Id}, "uint"),
		.t8_1d = new_scalar_type(.t8_1d, "t8_1d", 1, {.Integer, .Unsigned, .Texture_Id}, "uint8_t"),
		.t16_1d = new_scalar_type(.t16_1d, "t16_1d", 2, {.Integer, .Unsigned, .Texture_Id}, "uint16_t"),
		.t32_1d = new_scalar_type(.t32_1d, "t32_1d", 4, {.Integer, .Unsigned, .Texture_Id}, "uint"),
		.t8_3d = new_scalar_type(.t8_3d, "t8_3d", 1, {.Integer, .Unsigned, .Texture_Id}, "uint8_t"),
		.t16_3d = new_scalar_type(.t16_3d, "t16_3d", 2, {.Integer, .Unsigned, .Texture_Id}, "uint16_t"),
		.t32_3d = new_scalar_type(.t32_3d, "t32_3d", 4, {.Integer, .Unsigned, .Texture_Id}, "uint"),
		.t8_cube = new_scalar_type(.t8_cube, "t8_cube", 1, {.Integer, .Unsigned, .Texture_Id}, "uint8_t"),
		.t16_cube = new_scalar_type(.t16_cube, "t16_cube", 2, {.Integer, .Unsigned, .Texture_Id}, "uint16_t"),
		.t32_cube = new_scalar_type(.t32_cube, "t32_cube", 4, {.Integer, .Unsigned, .Texture_Id}, "uint"),
		.t8_1d_array = new_scalar_type(.t8_1d_array, "t8_1d_array", 1, {.Integer, .Unsigned, .Texture_Id}, "uint8_t"),
		.t16_1d_array = new_scalar_type(.t16_1d_array, "t16_1d_array", 2, {.Integer, .Unsigned, .Texture_Id}, "uint16_t"),
		.t32_1d_array = new_scalar_type(.t32_1d_array, "t32_1d_array", 4, {.Integer, .Unsigned, .Texture_Id}, "uint"),
		.t8_2d_array = new_scalar_type(.t8_2d_array, "t8_2d_array", 1, {.Integer, .Unsigned, .Texture_Id}, "uint8_t"),
		.t16_2d_array = new_scalar_type(.t16_2d_array, "t16_2d_array", 2, {.Integer, .Unsigned, .Texture_Id}, "uint16_t"),
		.t32_2d_array = new_scalar_type(.t32_2d_array, "t32_2d_array", 4, {.Integer, .Unsigned, .Texture_Id}, "uint"),
		.t8_cube_array = new_scalar_type(.t8_cube_array, "t8_cube_array", 1, {.Integer, .Unsigned, .Texture_Id}, "uint8_t"),
		.t16_cube_array = new_scalar_type(.t16_cube_array, "t16_cube_array", 2, {.Integer, .Unsigned, .Texture_Id}, "uint16_t"),
		.t32_cube_array = new_scalar_type(.t32_cube_array, "t32_cube_array", 4, {.Integer, .Unsigned, .Texture_Id}, "uint"),
		.s8  = new_scalar_type(.s8,  "s8",  1, {.Integer, .Unsigned, .Sampler_Id}, "uint8_t"),
		.s16 = new_scalar_type(.s16, "s16", 2, {.Integer, .Unsigned, .Sampler_Id}, "uint16_t"),
		.s32 = new_scalar_type(.s32, "s32", 4, {.Integer, .Unsigned, .Sampler_Id}, "uint"),
		.s8_cmp = new_scalar_type(.s8_cmp, "s8_cmp", 1, {.Integer, .Unsigned, .Sampler_Id, .Compare_Sampler_Id}, "uint8_t"),
		.s16_cmp = new_scalar_type(.s16_cmp, "s16_cmp", 2, {.Integer, .Unsigned, .Sampler_Id, .Compare_Sampler_Id}, "uint16_t"),
		.s32_cmp = new_scalar_type(.s32_cmp, "s32_cmp", 4, {.Integer, .Unsigned, .Sampler_Id, .Compare_Sampler_Id}, "uint"),
		.rw8_2d  = new_scalar_type(.rw8_2d,  "rw8_2d",  1, {.Integer, .Unsigned, .RW_Texture_Id}, "uint8_t"),
		.rw16_2d = new_scalar_type(.rw16_2d, "rw16_2d", 2, {.Integer, .Unsigned, .RW_Texture_Id}, "uint16_t"),
		.rw32_2d = new_scalar_type(.rw32_2d, "rw32_2d", 4, {.Integer, .Unsigned, .RW_Texture_Id}, "uint"),
		.rw8_1d = new_scalar_type(.rw8_1d, "rw8_1d", 1, {.Integer, .Unsigned, .RW_Texture_Id}, "uint8_t"),
		.rw16_1d = new_scalar_type(.rw16_1d, "rw16_1d", 2, {.Integer, .Unsigned, .RW_Texture_Id}, "uint16_t"),
		.rw32_1d = new_scalar_type(.rw32_1d, "rw32_1d", 4, {.Integer, .Unsigned, .RW_Texture_Id}, "uint"),
		.rw8_3d = new_scalar_type(.rw8_3d, "rw8_3d", 1, {.Integer, .Unsigned, .RW_Texture_Id}, "uint8_t"),
		.rw16_3d = new_scalar_type(.rw16_3d, "rw16_3d", 2, {.Integer, .Unsigned, .RW_Texture_Id}, "uint16_t"),
		.rw32_3d = new_scalar_type(.rw32_3d, "rw32_3d", 4, {.Integer, .Unsigned, .RW_Texture_Id}, "uint"),
		.rw8_cube = new_scalar_type(.rw8_cube, "rw8_cube", 1, {.Integer, .Unsigned, .RW_Texture_Id}, "uint8_t"),
		.rw16_cube = new_scalar_type(.rw16_cube, "rw16_cube", 2, {.Integer, .Unsigned, .RW_Texture_Id}, "uint16_t"),
		.rw32_cube = new_scalar_type(.rw32_cube, "rw32_cube", 4, {.Integer, .Unsigned, .RW_Texture_Id}, "uint"),
		.rw8_1d_array = new_scalar_type(.rw8_1d_array, "rw8_1d_array", 1, {.Integer, .Unsigned, .RW_Texture_Id}, "uint8_t"),
		.rw16_1d_array = new_scalar_type(.rw16_1d_array, "rw16_1d_array", 2, {.Integer, .Unsigned, .RW_Texture_Id}, "uint16_t"),
		.rw32_1d_array = new_scalar_type(.rw32_1d_array, "rw32_1d_array", 4, {.Integer, .Unsigned, .RW_Texture_Id}, "uint"),
		.rw8_2d_array = new_scalar_type(.rw8_2d_array, "rw8_2d_array", 1, {.Integer, .Unsigned, .RW_Texture_Id}, "uint8_t"),
		.rw16_2d_array = new_scalar_type(.rw16_2d_array, "rw16_2d_array", 2, {.Integer, .Unsigned, .RW_Texture_Id}, "uint16_t"),
		.rw32_2d_array = new_scalar_type(.rw32_2d_array, "rw32_2d_array", 4, {.Integer, .Unsigned, .RW_Texture_Id}, "uint"),
		.rw8_cube_array = new_scalar_type(.rw8_cube_array, "rw8_cube_array", 1, {.Integer, .Unsigned, .RW_Texture_Id}, "uint8_t"),
		.rw16_cube_array = new_scalar_type(.rw16_cube_array, "rw16_cube_array", 2, {.Integer, .Unsigned, .RW_Texture_Id}, "uint16_t"),
		.rw32_cube_array = new_scalar_type(.rw32_cube_array, "rw32_cube_array", 4, {.Integer, .Unsigned, .RW_Texture_Id}, "uint"),
		.bvh32 = new_scalar_type(.bvh32, "bvh32", 4, {.Integer, .Unsigned, .Bvh_Id}, "uint"),

		.rune = new_scalar_type(.rune, "rune", 4, {.Integer, .Unsigned, .Rune}, "uint"),
		.Untyped_Rune = new_scalar_type(.Untyped_Rune, "untyped rune", 0, {.Untyped, .Rune}),

		.Untyped_Bool    = new_scalar_type(.Untyped_Bool,    "untyped bool",          0, {.Untyped, .Boolean}),
		.Untyped_Integer = new_scalar_type(.Untyped_Integer, "untyped integer",       0, {.Untyped, .Integer}, "int"),
		.Untyped_Float   = new_scalar_type(.Untyped_Float,   "untyped float",         0, {.Untyped, .Float}),
		.Untyped_Complex = new_scalar_type(.Untyped_Complex, "untyped complex",       0, {.Untyped, .Complex}),
		.Untyped_Nil     = new_scalar_type(.Untyped_Nil,     "untyped nil",           0, {.Untyped, .Nil}),
		.Untyped_Unint   = new_scalar_type(.Untyped_Unint,   "untyped uninitialized", 0, {.Untyped}),
	}

	quaternion_types = {
		.Invalid = new_quaternion_type(.Invalid, "invalid quaternion", 0),
		.quat64  = new_quaternion_type(.quat64,  "quat64",  4),
		.quat128 = new_quaternion_type(.quat128, "quat128", 8),
		.quat256 = new_quaternion_type(.quat256, "quat256", 16),
		.Untyped = new_quaternion_type(.Untyped,  "untyped quaternion", 0),
	}

	atom_types = {
		.Invalid = new_atom_type(.Invalid, "invalid atom", 0, nil),

		.rune   = new_atom_type(.rune,   "rune",   4, {.Rune}),
		.string = new_atom_type(.string, "string", -1, {.String}),

		.uptr   = new_atom_type(.uptr,   "uptr",   8, nil),
		.rawptr = new_atom_type(.rawptr, "rawptr", 8, {.Pointer}),

		.any     = new_atom_type(.any,     "any",     16, nil),
		.typeid_ = new_atom_type(.typeid_, "typeid",   8, nil),
		.Ray_Query = new_atom_type(.Ray_Query, "Ray_Query", 0, nil, "rayQueryEXT"),

		.Untyped_String = new_atom_type(.Untyped_String, "untyped string", 0, {.Untyped, .String}),
		.Untyped_Rune   = new_atom_type(.Untyped_Rune,   "untyped rune",   0, {.Untyped, .Rune}),
	}

	t_invalid = scalar_types[.Invalid]
	t_b8 = scalar_types[.b8]
	t_b16 = scalar_types[.b16]
	t_b32 = scalar_types[.b32]
	t_b64 = scalar_types[.b64]
	t_u8 = scalar_types[.u8]
	t_u16 = scalar_types[.u16]
	t_u32 = scalar_types[.u32]
	t_u64 = scalar_types[.u64]
	t_i8 = scalar_types[.i8]
	t_i16 = scalar_types[.i16]
	t_i32 = scalar_types[.i32]
	t_i64 = scalar_types[.i64]
	t_f32 = scalar_types[.f32]
	t_f64 = scalar_types[.f64]
	t_t8_2d = scalar_types[.t8_2d]
	t_t16_2d = scalar_types[.t16_2d]
	t_t32_2d = scalar_types[.t32_2d]
	t_s8 = scalar_types[.s8]
	t_s16 = scalar_types[.s16]
	t_s32 = scalar_types[.s32]
	t_s8_cmp = scalar_types[.s8_cmp]
	t_s16_cmp = scalar_types[.s16_cmp]
	t_s32_cmp = scalar_types[.s32_cmp]
	t_rw8_2d = scalar_types[.rw8_2d]
	t_rw16_2d = scalar_types[.rw16_2d]
	t_rw32_2d = scalar_types[.rw32_2d]
	t_bvh32 = scalar_types[.bvh32]
	t_ray_query = atom_types[.Ray_Query]
	t_untyped_bool = scalar_types[.Untyped_Bool]
	t_untyped_int = scalar_types[.Untyped_Integer]
	t_untyped_float = scalar_types[.Untyped_Float]
	t_untyped_nil = scalar_types[.Untyped_Nil]
	t_untyped_string = atom_types[.Untyped_String]
	t_string = atom_types[.string]
	t_rune = scalar_types[.rune]
	t_untyped_rune = scalar_types[.Untyped_Rune]
	t_pipeline = new_type(Type_Pipeline)
}

type_is_texture_id :: proc(type: ^Type) -> bool {
	s, ok := type.derived.(^Type_Scalar)
	return ok && .Texture_Id in s.flags
}

type_is_sampler_id :: proc(type: ^Type) -> bool {
	s, ok := type.derived.(^Type_Scalar)
	return ok && .Sampler_Id in s.flags
}

type_is_rw_texture_id :: proc(type: ^Type) -> bool {
	s, ok := type.derived.(^Type_Scalar)
	return ok && .RW_Texture_Id in s.flags
}

type_is_compare_sampler_id :: proc(type: ^Type) -> bool {
	s, ok := type.derived.(^Type_Scalar)
	return ok && .Compare_Sampler_Id in s.flags
}

Resource_View :: enum {
	Invalid,
	D1,
	D2,
	D3,
	Cube,
	D1_Array,
	D2_Array,
	Cube_Array,
}

resource_view_of :: proc(type: ^Type) -> Resource_View {
	s, ok := type.derived.(^Type_Scalar)
	if !ok do return .Invalid
	#partial switch s.kind {
	case .t8_2d, .t16_2d, .t32_2d, .rw8_2d, .rw16_2d, .rw32_2d:
		return .D2
	case .t8_1d, .t16_1d, .t32_1d, .rw8_1d, .rw16_1d, .rw32_1d:
		return .D1
	case .t8_3d, .t16_3d, .t32_3d, .rw8_3d, .rw16_3d, .rw32_3d:
		return .D3
	case .t8_cube, .t16_cube, .t32_cube, .rw8_cube, .rw16_cube, .rw32_cube:
		return .Cube
	case .t8_1d_array, .t16_1d_array, .t32_1d_array, .rw8_1d_array, .rw16_1d_array, .rw32_1d_array:
		return .D1_Array
	case .t8_2d_array, .t16_2d_array, .t32_2d_array, .rw8_2d_array, .rw16_2d_array, .rw32_2d_array:
		return .D2_Array
	case .t8_cube_array, .t16_cube_array, .t32_cube_array, .rw8_cube_array, .rw16_cube_array, .rw32_cube_array:
		return .Cube_Array
	}
	return .Invalid
}

resource_view_supports_compare :: proc(view: Resource_View) -> bool {
	return view != .Invalid && view != .D3
}

resource_view_sample_coord_len :: proc(view: Resource_View) -> int {
	switch view {
	case .Invalid: return 0
	case .D1: return 1
	case .D2, .D1_Array: return 2
	case .D3, .Cube, .D2_Array: return 3
	case .Cube_Array: return 4
	}
	return 0
}

resource_view_load_coord_len :: proc(view: Resource_View) -> int {
	switch view {
	case .Invalid: return 0
	case .D1: return 1
	case .D2, .D1_Array: return 2
	case .D3, .Cube, .D2_Array, .Cube_Array: return 3
	}
	return 0
}

resource_view_dim_len :: proc(view: Resource_View) -> int {
	switch view {
	case .Invalid: return 0
	case .D1: return 1
	case .D2, .Cube, .D1_Array: return 2
	case .D3, .D2_Array, .Cube_Array: return 3
	}
	return 0
}

resource_view_compare_lod_ok :: proc(view: Resource_View) -> bool {
	#partial switch view {
	case .D1, .D2, .Cube:
		return true
	}
	return false
}

resource_view_sampled_load_ok :: proc(view: Resource_View) -> bool {
	#partial switch view {
	case .Cube, .Cube_Array:
		return false
	}
	return view != .Invalid
}

type_is_resource_id :: proc(type: ^Type) -> bool {
	return type_is_texture_id(type) || type_is_sampler_id(type) || type_is_rw_texture_id(type) || type_is_bvh_id(type)
}

type_is_bvh_id :: proc(type: ^Type) -> bool {
	s, ok := type.derived.(^Type_Scalar)
	return ok && .Bvh_Id in s.flags
}

type_is_ray_query :: proc(type: ^Type) -> bool {
	a, ok := type.derived.(^Type_Atom)
	return ok && a.kind == .Ray_Query
}

scalar_type :: proc(kind: Scalar_Kind) -> ^Type {
	return scalar_types[kind]
}

quaternion_type :: proc(kind: Quaternion_Kind) -> ^Type {
	return quaternion_types[kind]
}

atom_type :: proc(kind: Atom_Kind) -> ^Type {
	return atom_types[kind]
}

type_from_matrix_mul :: proc(left, right: ^Type) -> ^Type {
	if left == nil || right == nil {
		return t_invalid
	}

	if type_is_matrix(left) && type_is_matrix(right) {
		left := left.derived.(^Type_Matrix)
		right := right.derived.(^Type_Matrix)
		if left.columns != right.rows {
			return t_invalid
		}

		if !type_eq(left.elem, right.elem) {
			return t_invalid
		}

		result := new_type(Type_Matrix)
		result.rows = left.rows
		result.columns = right.columns
		result.elem = left.elem
		return result
	}

	if type_is_matrix(left) && type_is_vector(right) {
		mat := left.derived.(^Type_Matrix)
		vec := right.derived.(^Type_Vector)
		if mat.columns != vec.len {
			return t_invalid
		}

		if !type_eq(mat.elem, vec.elem) {
			return t_invalid
		}

		result := new_type(Type_Vector)
		result.len = mat.rows
		result.elem = vec.elem
		return result
	}

	if type_is_vector(left) && type_is_matrix(right) {
		vec := left.derived.(^Type_Vector)
		mat := right.derived.(^Type_Matrix)
		if vec.len != mat.rows {
			return t_invalid
		}

		if !type_eq(vec.elem, mat.elem) {
			return t_invalid
		}

		result := new_type(Type_Vector)
		result.len = mat.columns
		result.elem = vec.elem
		return result
	}

	if _, ok := left.derived.(^Type_Scalar); ok {
		right := right.derived.(^Type_Matrix)
		if !type_is_implicit_castable(left, right.elem) {
			return t_invalid
		}
		return right
	}

	if _, ok := right.derived.(^Type_Scalar); ok {
		left := left.derived.(^Type_Matrix)
		if !type_is_implicit_castable(right, left.elem) {
			return t_invalid
		}
		return left
	}

	return t_invalid
}

type_is_untyped_int :: proc(type: ^Type) -> bool {
	if type == nil do return false
	s, ok := type.derived.(^Type_Scalar)
	return ok && .Untyped in s.flags && .Integer in s.flags
}

type_from_binary_op :: proc(left: ^Type, op: Token_Kind, right: ^Type) -> ^Type {
	if left == nil || right == nil do return t_invalid

	if op == .Add || op == .Sub {
		if type_is_rune_value(left) && type_is_integer(right) && !type_is_rune_value(right) {
			return t_rune
		}
		if type_is_integer(left) && !type_is_rune_value(left) && type_is_rune_value(right) {
			return t_rune
		}
		if type_is_rune_value(left) && type_is_rune_value(right) {
			return t_rune
		}
	}

	// Numeric ranges: type is the iteration element type (bound type after joining).
	if op == .Range_Exclusive || op == .Range_Inclusive {
		if type_is_integer(left) && type_is_integer(right) {
			if type_is_untyped(left) && type_is_untyped(right) {
				return t_untyped_int
			}
			if type_is_untyped(left) {
				return right
			}
			if type_is_untyped(right) {
				return left
			}
			if type_eq(left, right) {
				return left
			}
		}
		return t_invalid
	}

	#partial switch left in left.derived {
	case ^Type_Matrix:
		#partial switch right in right.derived {
		case ^Type_Matrix:
			if op == .Mul {
				if left.columns != right.rows {
					return t_invalid
				}

				if !type_eq(left.elem, right.elem) {
					return t_invalid
				}

				result := new_type(Type_Matrix)
				result.rows = left.rows
				result.columns = right.columns
				result.elem = left.elem
				return result
			}

			if op_is_arithmetic(op) {
				if !type_eq(left, right) {
					return t_invalid
				}
				return left
			}

		case ^Type_Vector:
			if op == .Mul {
				if left.columns != right.len {
					return t_invalid
				}
				if !type_eq(left.elem, right.elem) {
					return t_invalid
				}
				result := new_type(Type_Vector)
				result.len = left.rows
				result.elem = right.elem
				return result
			}

		case ^Type_Scalar:
			if op_is_arithmetic(op) {
				if !type_is_implicit_castable(left.elem, right) {
					return t_invalid
				}
				return left
			}
		}

	case ^Type_Vector:
		#partial switch right in right.derived {
		case ^Type_Matrix:
			if op == .Mul {
				if left.len != right.rows {
					return t_invalid
				}
				if !type_eq(left.elem, right.elem) {
					return t_invalid
				}
				result := new_type(Type_Vector)
				result.len = right.columns
				result.elem = left.elem
				return result
			}

		case ^Type_Vector:
			if op_is_arithmetic(op) {
				if !type_eq(left, right) {
					return t_invalid
				}
				return left
			}

		case ^Type_Scalar:
			if op_is_arithmetic(op) {
				if !type_is_implicit_castable(left.elem, right) {
					return t_invalid
				}
				return left
			}
		}

	case ^Type_Scalar:
		#partial switch right in right.derived {
		case ^Type_Matrix:
			if op_is_arithmetic(op) {
				if !type_is_implicit_castable(left, right.elem) {
					return t_invalid
				}
				return right
			}
		case ^Type_Vector:
			if op_is_arithmetic(op) {
				if !type_is_implicit_castable(left, right.elem) {
					return t_invalid
				}
				return right
			}
		case ^Type_Scalar:
			if op_is_arithmetic(op) {
				if !type_is_implicit_castable(left, right) {
					return t_invalid
				}
				if .Untyped in left.flags && .Untyped in right.flags {
					return t_untyped_float if (.Float in left.flags) || (.Float in right.flags) else t_untyped_int
				}
				if .Untyped in left.flags {
					return right
				}
				return left
			}

			if op_is_bitwise(op) {
				if op == .Shl || op == .Shr {
					if !type_is_integer(left) || !type_is_integer(right) {
						return t_invalid
					}
					return left
				}
				// | & ~ &~ on integers; also | & ~ on booleans (Odin)
				if type_is_integer(left) && type_is_integer(right) {
					if !type_is_implicit_castable(left, right) && !type_is_implicit_castable(right, left) {
						return t_invalid
					}
					if .Untyped in left.flags {
						return right
					}
					return left
				}
				if type_is_boolean(left) && type_is_boolean(right) && (op == .And || op == .Or || op == .Xor) {
					return left
				}
				return t_invalid
			}

			if op_is_relation(op) {
				return t_untyped_bool
			}

			if op_is_logical(op) {
				if !type_is_boolean(left) || !type_is_boolean(right) {
					return t_invalid
				}
				if type_is_untyped(left) && type_is_untyped(right) {
					return t_untyped_bool
				}
				if type_is_untyped(left) {
					return right
				}
				if type_is_untyped(right) {
					return left
				}
				if type_eq(left, right) {
					return left
				}
				return t_invalid
			}
		}

	case ^Type_Enum:
		#partial switch right in right.derived {
		case ^Type_Enum:
			if op_is_relation(op) {
				if type_eq(left, right) {
					return t_untyped_bool
				}
			}
		}

	case ^Type_Bit_Set:
		#partial switch right in right.derived {
		case ^Type_Bit_Set:
			if !type_eq(left, right) {
				return t_invalid
			}
			// Set algebra: | + & &~ - ~ ; Odin also allows + / - aliases
			#partial switch op {
			case .Or, .Add, .And, .And_Not, .Sub, .Xor:
				return left
			case .Cmp_Eq, .Not_Eq, .Lt, .Lt_Eq, .Gt, .Gt_Eq:
				return t_untyped_bool
			}
		}
	}

	// e in S / e not_in S
	if op == .In || op == .Not_In {
		if bs, ok := right.derived.(^Type_Bit_Set); ok {
			if type_eq(left, bs.elem) || type_is_implicit_castable(left, bs.elem) {
				return t_untyped_bool
			}
		}
	}

	return t_invalid
}
