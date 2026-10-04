// Copyright 2026 Dale Weiler
// SPDX-License-Identifier: MIT

package fmag

NONE        :: max(Length)
NO_REGISTER :: max(Register)

Lower :: struct {
	builder:        ^IR_Builder,
	cg:             ^CG_Builder,
	reg:            []Register,
	op_last_use:    []Length,
	param_last_use: []Length,
	out_index:      []Length,
	used:           []u8,
	capacity:       Length,
	regs:           Length,
	notes:          [dynamic]string,
}

value_reg :: proc(lower: ^Lower, value: ^IR_Value) -> Register {
	return Register(value.index) if value.kind == .Param else lower.reg[value.id]
}

operand_word :: proc(lower: ^Lower, value: ^IR_Value) -> Word {
	return cg_imm(value.value) if value.kind == .Const else cg_reg(value_reg(lower, value))
}

alloc_register :: proc(lower: ^Lower, hint: Register) -> Register {
	r := hint
	if hint == NO_REGISTER || lower.used[hint] != 0 {
		r = 0
		for lower.used[r] != 0 {
			r += 1
		}
	}
	lower.used[r] = 1
	if Length(r) + 1 > lower.regs {
		lower.regs = Length(r) + 1
	}
	return r
}

free_dying :: proc(lower: ^Lower, op: ^IR_Value, position: Length, keep: ^IR_Value) {
	for k in 0 ..< 5 {
		v := op.operands[k]
		if v == nil || v == keep {
			continue
		}
		if v.kind == .Op && lower.op_last_use[v.id] == position {
			lower.used[lower.reg[v.id]] = 0
		} else if v.kind == .Param && lower.param_last_use[v.index] == position {
			lower.used[v.index] = 0
		}
	}
}

dying_operand_in :: proc(lower: ^Lower, op: ^IR_Value, reg: Register, position: Length) -> ^IR_Value {
	for k in 0 ..< 5 {
		v := op.operands[k]
		if v == nil {
			continue
		}
		dies := false
		if v.kind == .Op {
			dies = lower.op_last_use[v.id] == position
		} else if v.kind == .Param {
			dies = lower.param_last_use[v.index] == position
		}
		if dies && value_reg(lower, v) == reg {
			return v
		}
	}
	return nil
}

emit_copy :: proc(lower: ^Lower, dst: Register, source: Word, note := "") {
	cg_fmag(lower.cg, dst, dst, cg_imm(0), source, cg_imm(1))
	append(&lower.notes, note)
}

emit_move :: proc(lower: ^Lower, dst, source: Register, note := "") {
	cg_fmag(lower.cg, dst, source, cg_imm(1), cg_imm(0), cg_imm(1))
	append(&lower.notes, note)
}

lower_fail :: proc(cg: ^CG_Builder) -> (Program, []string) {
	stream := cg_finalize(cg)
	cg_builder_delete(cg)
	return Program{stream = stream}, nil
}

lower :: proc(builder: ^IR_Builder, function: ^IR_Function) -> Program {
	prog, _ := lower_with_notes(builder, function)
	return prog
}

lower_with_notes :: proc(builder: ^IR_Builder, function: ^IR_Function) -> (Program, []string) {
	plain := context_allocator(builder.ctx)
	cg := cg_builder_create(plain)

	if !ir_inline(builder) {
		return lower_fail(cg)
	}
	ir_select_pass(builder)
	if !ir_flatten(builder) {
		return lower_fail(cg)
	}
	ir_optimize(builder)

	block := function.blocks[0]
	count := Length(len(block.instructions))
	rets := function.return_count
	alloc := ir_alloc(builder)

	lower := Lower{
		builder  = builder,
		cg       = cg,
		capacity = function.param_count + 2 * count + rets + 2,
		regs     = function.param_count if function.param_count > rets else rets,
	}
	lower.notes.allocator = alloc
	lower.reg = make([]Register, builder.next_id, alloc)
	lower.op_last_use = make([]Length, builder.next_id, alloc)
	lower.out_index = make([]Length, builder.next_id, alloc)
	lower.param_last_use = make([]Length, function.param_count + 1, alloc)
	lower.used = make([]u8, lower.capacity, alloc)
	for i in 0 ..< builder.next_id {
		lower.reg[i] = NO_REGISTER
		lower.op_last_use[i] = NONE
		lower.out_index[i] = NONE
	}
	for i in 0 ..< function.param_count {
		lower.param_last_use[i] = NONE
		lower.used[i] = 1
	}

	for j in 0 ..< count {
		op := block.instructions[j]
		for k in 0 ..< 5 {
			v := op.operands[k]
			if v == nil {
				continue
			}
			if v.kind == .Op {
				lower.op_last_use[v.id] = j
			} else if v.kind == .Param {
				lower.param_last_use[v.index] = j
			}
		}
	}
	for i in 0 ..< rets {
		v := block.results[i]
		if v.kind == .Op {
			lower.op_last_use[v.id] = count
			if lower.out_index[v.id] == NONE {
				lower.out_index[v.id] = i
			}
		} else if v.kind == .Param {
			lower.param_last_use[v.index] = count
		}
	}

	for j in 0 ..< count {
		op := block.instructions[j]
		a := op.operands[0]
		b := op.operands[1]
		c := op.operands[2]
		d := op.operands[3]
		e := op.operands[4]
		pending := op.note

		hint := Register(lower.out_index[op.id]) if lower.out_index[op.id] != NONE else NO_REGISTER
		unconditional := e.kind == .Const && e.value > 0

		keep: ^IR_Value
		dst: Register
		dying_hint := dying_operand_in(&lower, op, hint, j) if unconditional && hint != NO_REGISTER && lower.used[hint] != 0 else nil
		if !unconditional && d.kind == .Op && lower.op_last_use[d.id] == j {
			dst = lower.reg[d.id]
			keep = d
		} else if !unconditional && d.kind == .Param && lower.param_last_use[d.index] == j {
			dst = Register(d.index)
			keep = d
		} else if dying_hint != nil {
			dst = hint
			keep = dying_hint
		} else {
			dst = alloc_register(&lower, hint)
			if !unconditional {
				emit_copy(&lower, dst, operand_word(&lower, d), pending)
				pending = ""
			}
		}
		lower.reg[op.id] = dst

		a_reg := value_reg(&lower, a)
		b_word := operand_word(&lower, b)
		c_word := operand_word(&lower, c)
		guard := cg_imm(1) if unconditional else cg_reg(value_reg(&lower, e))
		cg_fmag(cg, dst, a_reg, b_word, c_word, guard)
		append(&lower.notes, pending)
		free_dying(&lower, op, j, keep)
	}

	for i in 0 ..< rets {
		lower.used[i] = 1
	}
	src := make([]Register, rets + 1, alloc)
	is_const := make([]u8, rets + 1, alloc)
	done := make([]u8, rets + 1, alloc)
	for i in 0 ..< rets {
		is_const[i] = 1 if block.results[i].kind == .Const else 0
		if is_const[i] == 0 {
			src[i] = value_reg(&lower, block.results[i])
		}
	}
	placed: Length
	for placed < rets {
		progress := false
		for i in 0 ..< rets {
			if done[i] != 0 {
				continue
			}
			blocked := false
			for j in 0 ..< rets {
				if j != i && done[j] == 0 && is_const[j] == 0 && src[j] == Register(i) {
					blocked = true
				}
			}
			if blocked {
				continue
			}
			if is_const[i] != 0 {
				emit_copy(&lower, Register(i), cg_imm(block.results[i].value))
			} else if src[i] != Register(i) {
				emit_move(&lower, Register(i), src[i])
			}
			done[i] = 1
			placed += 1
			progress = true
		}
		if !progress {
			for i in 0 ..< rets {
				if done[i] == 0 && is_const[i] == 0 {
					scratch := alloc_register(&lower, NO_REGISTER)
					emit_move(&lower, scratch, src[i])
					src[i] = scratch
					break
				}
			}
		}
	}

	stream := cg_finalize(cg)
	header := HDR{
		magic = MAGIC,
		crc16 = crc16(stream.data, stream.size),
		regs  = u16(lower.regs),
		args  = u16(function.param_count),
		rets  = u16(rets),
	}
	notes := make([]string, len(lower.notes), alloc)
	copy(notes, lower.notes[:])
	cg_builder_delete(cg)
	return Program{header = header, stream = stream}, notes
}
