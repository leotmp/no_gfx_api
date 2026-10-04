package spirv

import "core:fmt"
import "core:slice"
import "core:strings"

Inst_View :: struct {
	op:        Op,
	words:     []Word, // including header
	operands:  []Word, // after header
}

walk :: proc(words: []u32, visit: proc(inst: Inst_View)) {
	if len(words) < 5 {
		return
	}
	i := 5
	for i < len(words) {
		first := words[i]
		n := int(first >> 16)
		if n < 1 || i + n > len(words) {
			return
		}
		op := Op(first & 0xffff)
		visit(Inst_View{op = op, words = words[i:i + n], operands = words[i + 1:i + n]})
		i += n
	}
}

literal_string :: proc(words: []Word) -> string {
	bytes := slice.reinterpret([]u8, words)
	n := 0
	for b, i in bytes {
		if b == 0 {
			n = i
			break
		}
	}
	return string(bytes[:n])
}

Abi_Image :: struct {
	dim:     u32,
	sampled: u32, // 1 sampled, 2 storage
	arrayed: u32,
	ms:      u32,
	depth:   u32,
	format:  u32,
}

Abi_Member :: struct {
	struct_id: u32,
	member:    u32,
	offset:    u32,
}

Abi :: struct {
	caps:         [dynamic]u32,
	exts:         [dynamic]string,
	model:        u32,
	entry_name:   string,
	modes:        [dynamic]string,
	decos:        [dynamic]string,
	images:       [dynamic]Abi_Image,
	samplers:     int,
	push_members: [dynamic]string,
	spec_ids:     [dynamic]u32,
}

abi_cap_relevant :: proc(c: u32) -> bool {
	#partial switch Capability(c) {
	case .PhysicalStorageBufferAddresses, .RayQueryKHR, .DrawParameters:
		return true
	}
	return false
}

abi_ext_relevant :: proc(name: string) -> bool {
	switch name {
	case EXT_RAY_QUERY:
		return true
	}
	return false
}

abi_builtin_relevant :: proc(b: u32) -> bool {
	#partial switch Built_In(b) {
	case .Position, .FragCoord, .VertexIndex, .InstanceIndex, .DrawIndex,
	     .GlobalInvocationId, .LocalInvocationId, .WorkgroupId, .LocalInvocationIndex, .NumWorkgroups:
		return true
	}
	return false
}

abi_from_words :: proc(words: []u32, allocator := context.allocator) -> Abi {
	a: Abi
	context.allocator = allocator
	a.caps = make([dynamic]u32, allocator)
	a.exts = make([dynamic]string, allocator)
	a.modes = make([dynamic]string, allocator)
	a.decos = make([dynamic]string, allocator)
	a.images = make([dynamic]Abi_Image, allocator)
	a.push_members = make([dynamic]string, allocator)
	a.spec_ids = make([dynamic]u32, allocator)

	id_type := make(map[u32]u32, allocator)
	type_kind := make(map[u32]Op, allocator)
	struct_members := make(map[u32][]u32, allocator)
	ptr_pointee := make(map[u32]u32, allocator)
	ptr_sc := make(map[u32]u32, allocator)
	offsets := make([dynamic]Abi_Member, allocator)
	push_vars := make([dynamic]u32, allocator)
	set_of := make(map[u32]u32, allocator)
	bind_of := make(map[u32]u32, allocator)
	loc_of := make(map[u32]u32, allocator)
	builtin_of := make(map[u32]u32, allocator)
	flat_of := make(map[u32]bool, allocator)
	nopersp_of := make(map[u32]bool, allocator)
	centroid_of := make(map[u32]bool, allocator)
	member_builtin := make(map[u64]u32, allocator)
	var_sc := make(map[u32]u32, allocator)

	i := 5
	for i < len(words) {
		first := words[i]
		n := int(first >> 16)
		if n < 1 || i + n > len(words) {
			break
		}
		op := Op(first & 0xffff)
		ops := words[i + 1:i + n]
		#partial switch op {
		case .Capability:
			if len(ops) >= 1 && abi_cap_relevant(ops[0]) {
				append(&a.caps, ops[0])
			}
		case .Extension:
			name := strings.clone(literal_string(ops), allocator)
			if abi_ext_relevant(name) {
				append(&a.exts, name)
			}
		case .EntryPoint:
			if len(ops) >= 3 {
				a.model = ops[0]
				a.entry_name = strings.clone(literal_string(ops[2:]), allocator)
			}
		case .ExecutionMode, .ExecutionModeId:
			if len(ops) >= 2 {
				append(&a.modes, fmt.aprintf("%v extra=%v", Execution_Mode(ops[1]), ops[2:], allocator = allocator))
			}
		case .Decorate:
			if len(ops) >= 2 {
				target := ops[0]
				dec := Decoration(ops[1])
				extra: u32
				if len(ops) >= 3 {
					extra = ops[2]
				}
				#partial switch dec {
				case .DescriptorSet:
					set_of[target] = extra
				case .Binding:
					bind_of[target] = extra
				case .Location:
					loc_of[target] = extra
				case .BuiltIn:
					if abi_builtin_relevant(extra) {
						builtin_of[target] = extra
					}
				case .SpecId:
					append(&a.spec_ids, extra)
				case .Flat:
					flat_of[target] = true
				case .NoPerspective:
					nopersp_of[target] = true
				case .Centroid:
					centroid_of[target] = true
				}
			}
		case .MemberDecorate:
			if len(ops) >= 4 {
				if Decoration(ops[2]) == .Offset {
					append(&offsets, Abi_Member{struct_id = ops[0], member = ops[1], offset = ops[3]})
				} else if Decoration(ops[2]) == .BuiltIn && abi_builtin_relevant(ops[3]) {
					member_builtin[(u64(ops[0]) << 32) | u64(ops[1])] = ops[3]
				}
			}
		case .TypeImage:
			if len(ops) >= 8 {
				append(&a.images, Abi_Image{
					dim = ops[2],
					depth = ops[3],
					arrayed = ops[4],
					ms = ops[5],
					sampled = ops[6],
					format = ops[7],
				})
				type_kind[ops[0]] = .TypeImage
			}
		case .TypeSampler:
			if len(ops) >= 1 {
				a.samplers += 1
				type_kind[ops[0]] = .TypeSampler
			}
		case .TypePointer:
			if len(ops) >= 3 {
				ptr_sc[ops[0]] = ops[1]
				ptr_pointee[ops[0]] = ops[2]
				type_kind[ops[0]] = .TypePointer
			}
		case .TypeStruct:
			if len(ops) >= 1 {
				type_kind[ops[0]] = .TypeStruct
				struct_members[ops[0]] = ops[1:]
			}
		case .TypeRuntimeArray:
			if len(ops) >= 1 {
				type_kind[ops[0]] = .TypeRuntimeArray
			}
		case .Variable:
			if len(ops) >= 3 {
				id := ops[1]
				sc := ops[2]
				ty := ops[0]
				id_type[id] = ty
				var_sc[id] = sc
				if Storage_Class(sc) == .PushConstant {
					append(&push_vars, id)
				}
			}
		}
		i += n
	}

	for vid, sc in var_sc {
		#partial switch Storage_Class(sc) {
		case .UniformConstant:
			append(&a.decos, fmt.aprintf("bind set=%d bind=%d", set_of[vid], bind_of[vid], allocator = allocator))
		case .Input, .Output:
			b, has_b := builtin_of[vid]
			if has_b {
				append(&a.decos, fmt.aprintf("io sc=%d builtin=%d", sc, b, allocator = allocator))
			} else {
				pointee := ptr_pointee[id_type[vid]]
				emitted_member := false
				if members, mok := struct_members[pointee]; mok {
					for _, mi in members {
						key := (u64(pointee) << 32) | u64(mi)
						if mb, hb := member_builtin[key]; hb {
							append(&a.decos, fmt.aprintf("io sc=%d builtin=%d", sc, mb, allocator = allocator))
							emitted_member = true
						}
					}
				}
				if !emitted_member {
					if _, has_loc := loc_of[vid]; has_loc {
						qual := ""
						if flat_of[vid] do qual = fmt.tprintf("%s flat", qual)
						if nopersp_of[vid] do qual = fmt.tprintf("%s nopersp", qual)
						if centroid_of[vid] do qual = fmt.tprintf("%s centroid", qual)
						append(&a.decos, fmt.aprintf("io sc=%d loc=%d%s", sc, loc_of[vid], qual, allocator = allocator))
					}
				}
			}
		}
	}

	for vid in push_vars {
		ty := id_type[vid]
		pointee := ptr_pointee[ty]
		members := struct_members[pointee]
		for _, mi in members {
			off: u32
			for om in offsets {
				if om.struct_id == pointee && int(om.member) == mi {
					off = om.offset
					break
				}
			}
			append(&a.push_members, fmt.aprintf("m%d off=%d", mi, off, allocator = allocator))
		}
	}

	slice.sort(a.caps[:])
	slice.sort(a.exts[:])
	slice.sort(a.modes[:])
	slice.sort(a.decos[:])
	slice.sort(a.push_members[:])
	slice.sort(a.spec_ids[:])
	slice.sort_by(a.images[:], proc(x, y: Abi_Image) -> bool {
		if x.dim != y.dim do return x.dim < y.dim
		if x.sampled != y.sampled do return x.sampled < y.sampled
		if x.arrayed != y.arrayed do return x.arrayed < y.arrayed
		if x.ms != y.ms do return x.ms < y.ms
		if x.depth != y.depth do return x.depth < y.depth
		return x.format < y.format
	})
	return a
}

abi_mismatch :: proc(a, b: Abi, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	check_u32 :: proc(out: ^[dynamic]string, label: string, x, y: []u32) {
		if len(x) != len(y) {
			append(out, fmt.tprintf("%s count %d vs %d", label, len(x), len(y)))
			return
		}
		for v, i in x {
			if v != y[i] {
				append(out, fmt.tprintf("%s[%d] %d vs %d", label, i, v, y[i]))
			}
		}
	}
	check_str :: proc(out: ^[dynamic]string, label: string, x, y: []string) {
		if len(x) != len(y) {
			append(out, fmt.tprintf("%s count %d vs %d", label, len(x), len(y)))
			return
		}
		for v, i in x {
			if v != y[i] {
				append(out, fmt.tprintf("%s[%d] %s vs %s", label, i, v, y[i]))
			}
		}
	}
	if a.model != b.model {
		append(&out, fmt.tprintf("execution model %d vs %d", a.model, b.model))
	}
	check_u32(&out, "capability", a.caps[:], b.caps[:])
	check_str(&out, "extension", a.exts[:], b.exts[:])
	check_str(&out, "exec_mode", a.modes[:], b.modes[:])
	check_str(&out, "decoration", a.decos[:], b.decos[:])
	check_str(&out, "push_member", a.push_members[:], b.push_members[:])
	check_u32(&out, "spec_id", a.spec_ids[:], b.spec_ids[:])
	if len(a.images) != len(b.images) {
		append(&out, fmt.tprintf("image type count %d vs %d", len(a.images), len(b.images)))
	} else {
		for img, i in a.images {
			o := b.images[i]
			if img.dim != o.dim || img.sampled != o.sampled || img.arrayed != o.arrayed || img.ms != o.ms || img.depth != o.depth {
				append(&out, fmt.tprintf("image[%d] dim/sampled/array mismatch", i))
			}
		}
	}
	if a.samplers != b.samplers {
		append(&out, fmt.tprintf("sampler type count %d vs %d", a.samplers, b.samplers))
	}
	return out[:]
}
