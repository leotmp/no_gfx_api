package spirv

import "core:fmt"

type_void :: proc(m: ^Module) -> Id {
	if m.ty_void != NONE {
		return m.ty_void
	}
	id := alloc_id(m)
	emit_types(m, .TypeVoid, Word(id))
	m.ty_void = id
	name(m, id, "void")
	return id
}

type_bool :: proc(m: ^Module) -> Id {
	if m.ty_bool != NONE {
		return m.ty_bool
	}
	id := alloc_id(m)
	emit_types(m, .TypeBool, Word(id))
	m.ty_bool = id
	name(m, id, "bool")
	return id
}

type_int :: proc(m: ^Module, width: u32, signed: bool) -> Id {
	switch width {
	case 8: require_cap(m, .Int8)
	case 16: require_cap(m, .Int16)
	case 64: require_cap(m, .Int64)
	}
	key := fmt.tprintf("i:%d:%v", width, signed)
	if id, ok := intern_key(m, key, &m.type_map); ok {
		return id
	}
	id := alloc_id(m)
	emit_types(m, .TypeInt, Word(id), width, 1 if signed else 0)
	put_key(m, key, id, &m.type_map)
	return id
}

type_float :: proc(m: ^Module, width: u32) -> Id {
	if width == 64 {
		require_cap(m, .Float64)
	}
	key := fmt.tprintf("f:%d", width)
	if id, ok := intern_key(m, key, &m.type_map); ok {
		return id
	}
	id := alloc_id(m)
	emit_types(m, .TypeFloat, Word(id), width)
	put_key(m, key, id, &m.type_map)
	return id
}

type_i8  :: proc(m: ^Module) -> Id { require_cap(m, .Int8);  return type_int(m, 8, true) }
type_i16 :: proc(m: ^Module) -> Id { require_cap(m, .Int16); return type_int(m, 16, true) }
type_i32 :: proc(m: ^Module) -> Id { return type_int(m, 32, true) }
type_i64 :: proc(m: ^Module) -> Id { require_cap(m, .Int64); return type_int(m, 64, true) }
type_u8  :: proc(m: ^Module) -> Id { require_cap(m, .Int8);  return type_int(m, 8, false) }
type_u16 :: proc(m: ^Module) -> Id { require_cap(m, .Int16); return type_int(m, 16, false) }
type_u32 :: proc(m: ^Module) -> Id { return type_int(m, 32, false) }
type_u64 :: proc(m: ^Module) -> Id { require_cap(m, .Int64); return type_int(m, 64, false) }
type_f32 :: proc(m: ^Module) -> Id { return type_float(m, 32) }
type_f64 :: proc(m: ^Module) -> Id { require_cap(m, .Float64); return type_float(m, 64) }

type_vector :: proc(m: ^Module, elem: Id, n: u32) -> Id {
	key := fmt.tprintf("v:%d:%d", elem, n)
	if id, ok := intern_key(m, key, &m.type_map); ok {
		return id
	}
	id := alloc_id(m)
	emit_types(m, .TypeVector, Word(id), Word(elem), n)
	put_key(m, key, id, &m.type_map)
	return id
}

type_matrix :: proc(m: ^Module, col_ty: Id, cols: u32) -> Id {
	key := fmt.tprintf("m:%d:%d", col_ty, cols)
	if id, ok := intern_key(m, key, &m.type_map); ok {
		return id
	}
	id := alloc_id(m)
	emit_types(m, .TypeMatrix, Word(id), Word(col_ty), cols)
	put_key(m, key, id, &m.type_map)
	return id
}

type_pointer :: proc(m: ^Module, sc: Storage_Class, pointee: Id) -> Id {
	key := fmt.tprintf("p:%d:%d", u32(sc), pointee)
	if id, ok := intern_key(m, key, &m.type_map); ok {
		return id
	}
	id := alloc_id(m)
	emit_types(m, .TypePointer, Word(id), Word(sc), Word(pointee))
	put_key(m, key, id, &m.type_map)
	return id
}

type_forward_pointer :: proc(m: ^Module, sc: Storage_Class) -> Id {
	id := alloc_id(m)
	emit_types(m, .TypeForwardPointer, Word(id), Word(sc))
	return id
}

type_pointer_define :: proc(m: ^Module, id: Id, sc: Storage_Class, pointee: Id) {
	key := fmt.tprintf("p:%d:%d", u32(sc), pointee)
	emit_types(m, .TypePointer, Word(id), Word(sc), Word(pointee))
	put_key(m, key, id, &m.type_map)
}

type_array :: proc(m: ^Module, elem: Id, length_id: Id, stride: u32 = 0) -> Id {
	key := fmt.tprintf("a:%d:%d:%d", elem, length_id, stride)
	if id, ok := intern_key(m, key, &m.type_map); ok {
		return id
	}
	id := alloc_id(m)
	emit_types(m, .TypeArray, Word(id), Word(elem), Word(length_id))
	if stride != 0 {
		decorate(m, id, .ArrayStride, stride)
	}
	put_key(m, key, id, &m.type_map)
	return id
}

type_runtime_array :: proc(m: ^Module, elem: Id, stride: u32 = 0) -> Id {
	key := fmt.tprintf("ra:%d:%d", elem, stride)
	if id, ok := intern_key(m, key, &m.type_map); ok {
		return id
	}
	id := alloc_id(m)
	emit_types(m, .TypeRuntimeArray, Word(id), Word(elem))
	if stride != 0 {
		decorate(m, id, .ArrayStride, stride)
	}
	put_key(m, key, id, &m.type_map)
	return id
}

type_struct :: proc(m: ^Module, members: []Id, key := "") -> Id {
	k := key
	if k == "" {
		k = fmt.tprintf("s:%v", members)
	}
	if id, ok := intern_key(m, k, &m.type_map); ok {
		return id
	}
	id := alloc_id(m)
	ops := make([]Word, 1 + len(members), context.temp_allocator)
	ops[0] = Word(id)
	for mem, i in members {
		ops[1 + i] = Word(mem)
	}
	append_inst(&m.types, .TypeStruct, ops)
	put_key(m, k, id, &m.type_map)
	return id
}

type_function :: proc(m: ^Module, ret: Id, params: []Id) -> Id {
	key := fmt.tprintf("fn:%d:%v", ret, params)
	if id, ok := intern_key(m, key, &m.type_map); ok {
		return id
	}
	id := alloc_id(m)
	ops := make([]Word, 2 + len(params), context.temp_allocator)
	ops[0] = Word(id)
	ops[1] = Word(ret)
	for p, i in params {
		ops[2 + i] = Word(p)
	}
	append_inst(&m.types, .TypeFunction, ops)
	put_key(m, key, id, &m.type_map)
	return id
}

type_image :: proc(
	m: ^Module,
	sampled_ty: Id,
	dim: Dim,
	depth, arrayed, ms, sampled: u32,
	format: Image_Format,
) -> Id {
	key := fmt.tprintf("img:%d:%d:%d:%d:%d:%d:%d", sampled_ty, u32(dim), depth, arrayed, ms, sampled, u32(format))
	if id, ok := intern_key(m, key, &m.type_map); ok {
		return id
	}
	id := alloc_id(m)
	emit_types(m, .TypeImage, Word(id), Word(sampled_ty), Word(dim), depth, arrayed, ms, sampled, Word(format))
	put_key(m, key, id, &m.type_map)
	return id
}

type_sampler :: proc(m: ^Module) -> Id {
	if m.ty_sampler != NONE {
		return m.ty_sampler
	}
	id := alloc_id(m)
	emit_types(m, .TypeSampler, Word(id))
	m.ty_sampler = id
	return id
}

type_sampled_image :: proc(m: ^Module, image: Id) -> Id {
	key := fmt.tprintf("simg:%d", image)
	if id, ok := intern_key(m, key, &m.type_map); ok {
		return id
	}
	id := alloc_id(m)
	emit_types(m, .TypeSampledImage, Word(id), Word(image))
	put_key(m, key, id, &m.type_map)
	return id
}

type_acceleration_structure :: proc(m: ^Module) -> Id {
	key := "as"
	if id, ok := intern_key(m, key, &m.type_map); ok {
		return id
	}
	require_cap(m, .RayQueryKHR)
	require_ext(m, EXT_RAY_QUERY)
	id := alloc_id(m)
	emit_types(m, .TypeAccelerationStructureKHR, Word(id))
	put_key(m, key, id, &m.type_map)
	return id
}

type_ray_query :: proc(m: ^Module) -> Id {
	key := "rq"
	if id, ok := intern_key(m, key, &m.type_map); ok {
		return id
	}
	require_cap(m, .RayQueryKHR)
	require_ext(m, EXT_RAY_QUERY)
	id := alloc_id(m)
	emit_types(m, .TypeRayQueryKHR, Word(id))
	put_key(m, key, id, &m.type_map)
	return id
}

const_bool :: proc(m: ^Module, v: bool) -> Id {
	key := fmt.tprintf("cb:%v", v)
	if id, ok := intern_key(m, key, &m.const_map); ok {
		return id
	}
	id := alloc_id(m)
	ty := type_bool(m)
	op := Op.ConstantTrue if v else Op.ConstantFalse
	emit_types(m, op, Word(ty), Word(id))
	put_key(m, key, id, &m.const_map)
	return id
}

const_int :: proc(m: ^Module, ty: Id, bits: u64, width: u32) -> Id {
	key := fmt.tprintf("ci:%d:%d:%d", ty, bits, width)
	if id, ok := intern_key(m, key, &m.const_map); ok {
		return id
	}
	id := alloc_id(m)
	if width > 32 {
		emit_types(m, .Constant, Word(ty), Word(id), u32(bits), u32(bits >> 32))
	} else {
		emit_types(m, .Constant, Word(ty), Word(id), u32(bits))
	}
	put_key(m, key, id, &m.const_map)
	return id
}

const_u32 :: proc(m: ^Module, v: u32) -> Id {
	return const_int(m, type_u32(m), u64(v), 32)
}

const_i32 :: proc(m: ^Module, v: i32) -> Id {
	return const_int(m, type_i32(m), u64(u32(v)), 32)
}

const_u64 :: proc(m: ^Module, v: u64) -> Id {
	return const_int(m, type_u64(m), v, 64)
}

const_i64 :: proc(m: ^Module, v: i64) -> Id {
	return const_int(m, type_i64(m), u64(v), 64)
}

const_f32 :: proc(m: ^Module, v: f32) -> Id {
	bits := transmute(u32)v
	key := fmt.tprintf("cf32:%d", bits)
	if id, ok := intern_key(m, key, &m.const_map); ok {
		return id
	}
	id := alloc_id(m)
	emit_types(m, .Constant, Word(type_f32(m)), Word(id), bits)
	put_key(m, key, id, &m.const_map)
	return id
}

const_f64 :: proc(m: ^Module, v: f64) -> Id {
	bits := transmute(u64)v
	key := fmt.tprintf("cf64:%d", bits)
	if id, ok := intern_key(m, key, &m.const_map); ok {
		return id
	}
	id := alloc_id(m)
	emit_types(m, .Constant, Word(type_f64(m)), Word(id), u32(bits), u32(bits >> 32))
	put_key(m, key, id, &m.const_map)
	return id
}

const_composite :: proc(m: ^Module, ty: Id, parts: []Id) -> Id {
	key := fmt.tprintf("cc:%d:%v", ty, parts)
	if id, ok := intern_key(m, key, &m.const_map); ok {
		return id
	}
	id := alloc_id(m)
	ops := make([]Word, 2 + len(parts), context.temp_allocator)
	ops[0] = Word(ty)
	ops[1] = Word(id)
	for p, i in parts {
		ops[2 + i] = Word(p)
	}
	append_inst(&m.types, .ConstantComposite, ops)
	put_key(m, key, id, &m.const_map)
	return id
}

const_null :: proc(m: ^Module, ty: Id) -> Id {
	key := fmt.tprintf("cn:%d", ty)
	if id, ok := intern_key(m, key, &m.const_map); ok {
		return id
	}
	id := alloc_id(m)
	emit_types(m, .ConstantNull, Word(ty), Word(id))
	put_key(m, key, id, &m.const_map)
	return id
}

spec_const_int :: proc(m: ^Module, ty: Id, bits: u64, width: u32) -> Id {
	id := alloc_id(m)
	if width > 32 {
		emit_types(m, .SpecConstant, Word(ty), Word(id), u32(bits), u32(bits >> 32))
	} else {
		emit_types(m, .SpecConstant, Word(ty), Word(id), u32(bits))
	}
	return id
}
