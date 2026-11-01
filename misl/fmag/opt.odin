// Copyright 2026 Dale Weiler
// SPDX-License-Identifier: MIT

package fmag

Opt :: struct {
	builder: ^IR_Builder,
	forward: []^IR_Value,
	live:    []u8,
	consts:  [dynamic]^IR_Value,
	values:  [dynamic]^IR_Value,
	fast:    bool,
}

intern_const :: proc(opt: ^Opt, value: f32, existing: ^IR_Value) -> ^IR_Value {
	for c in opt.consts {
		if c.value == value {
			return c
		}
	}
	canonical := existing if existing != nil else ir_const(opt.builder, value)
	append(&opt.consts, canonical)
	return canonical
}

resolve :: proc(opt: ^Opt, value: ^IR_Value) -> ^IR_Value {
	value := value
	for value.kind == .Op && opt.forward[value.id] != nil {
		value = opt.forward[value.id]
	}
	return value
}

is_const_value :: proc(v: ^IR_Value, x: f32) -> bool {
	return v.kind == .Const && v.value == x
}

is_unconditional :: proc(v: ^IR_Value) -> bool {
	return v.kind == .Op && is_const_value(v.operands[4], 1)
}

fold :: proc(opt: ^Opt, op: ^IR_Value) -> ^IR_Value {
	a := op.operands[0]
	b := op.operands[1]
	c := op.operands[2]
	d := op.operands[3]
	e := op.operands[4]
	a_const := a.kind == .Const
	b_const := b.kind == .Const
	c_zero := c.kind == .Const && c.value == 0
	if a == d && b_const && b.value == 1 && c_zero {
		return a
	}
	if e.kind != .Const {
		return nil
	}
	if e.value <= 0 {
		return d
	}
	if a_const && b_const && c.kind == .Const {
		return intern_const(opt, a.value * b.value + c.value, nil)
	}
	if a_const && b_const && a.value * b.value == 0 {
		return c
	}
	if opt.fast && b_const && b.value == 0 {
		return c
	}
	if c_zero && b_const && b.value == 1 {
		return a
	}
	if c_zero && a_const && a.value == 1 {
		return b
	}
	return nil
}

is_sign_boolean :: proc(value: ^IR_Value) -> (ok: bool, tested: ^IR_Value) {
	if value.kind != .Op {
		return false, nil
	}
	t := value.operands[0]
	o := value.operands[1]
	a := value.operands[2]
	f := value.operands[3]
	if t.kind == .Const && t.value == 1 &&
	   o.kind == .Const && o.value == 1 &&
	   a.kind == .Const && a.value == 0 &&
	   f.kind == .Const && f.value == 0 {
		return true, value.operands[4]
	}
	return false, nil
}

strip_guard :: proc(opt: ^Opt, guard: ^IR_Value) -> ^IR_Value {
	guard := guard
	for {
		ok, tested := is_sign_boolean(guard)
		if !ok {
			break
		}
		guard = resolve(opt, tested)
	}
	return guard
}

complement_guard :: proc(guard: ^IR_Value) -> ^IR_Value {
	if guard.kind != .Op {
		return nil
	}
	boolean := guard.operands[0]
	if !(guard.operands[1].kind == .Const && guard.operands[1].value == -1 &&
	     guard.operands[2].kind == .Const && guard.operands[2].value == 1 &&
	     guard.operands[3].kind == .Const && guard.operands[3].value == 0 &&
	     guard.operands[4].kind == .Const && guard.operands[4].value == 1) {
		return nil
	}
	ok, tested := is_sign_boolean(boolean)
	return tested if ok else nil
}

canonicalize_factor :: proc(opt: ^Opt, op: ^IR_Value) {
	a := op.operands[0]
	b := op.operands[1]
	if a.kind != .Const {
		return
	}
	if b.kind != .Const {
		op.operands[0] = b
		op.operands[1] = a
		return
	}
	product := a.value * b.value
	c := op.operands[2]
	e := op.operands[4]
	if c.kind != .Const {
		op.operands[0] = c
		op.operands[1] = ir_const(opt.builder, 1)
		op.operands[2] = ir_const(opt.builder, product)
	} else if e.kind != .Const {
		op.operands[0] = e
		op.operands[1] = ir_const(opt.builder, 0)
		op.operands[2] = ir_const(opt.builder, product + c.value)
	}
}

common :: proc(opt: ^Opt, op: ^IR_Value) -> ^IR_Value {
	for candidate in opt.values {
		k := 0
		for k < 5 && candidate.operands[k] == op.operands[k] {
			k += 1
		}
		if k == 5 {
			return candidate
		}
	}
	return nil
}

fuse :: proc(opt: ^Opt, op: ^IR_Value) {
	b := op.operands[1]
	if b.kind != .Const {
		return
	}
	a := op.operands[0]
	c := op.operands[2]
	if b.value == 1 {
		if is_unconditional(a) {
			ac := a.operands[2]
			if is_const_value(c, 0) {
				op.operands[0] = a.operands[0]
				op.operands[1] = a.operands[1]
				op.operands[2] = ac
				absorb_note(op, a)
				return
			}
			if is_const_value(ac, 0) {
				op.operands[0] = a.operands[0]
				op.operands[1] = a.operands[1]
				absorb_note(op, a)
				return
			}
		}
		if is_unconditional(c) && is_const_value(c.operands[2], 0) {
			op.operands[0] = c.operands[0]
			op.operands[1] = c.operands[1]
			op.operands[2] = a
			absorb_note(op, c)
			return
		}
	}
	if !opt.fast || !is_unconditional(a) || a.operands[1].kind != .Const {
		return
	}
	ac := a.operands[2]
	if is_const_value(ac, 0) {
		op.operands[0] = a.operands[0]
		op.operands[1] = ir_const(opt.builder, a.operands[1].value * b.value)
		absorb_note(op, a)
		return
	}
	if b.value == 1 && ac.kind == .Const && c.kind == .Const {
		op.operands[0] = a.operands[0]
		op.operands[1] = a.operands[1]
		op.operands[2] = ir_const(opt.builder, ac.value + c.value)
		absorb_note(op, a)
	}
}

absorb_note :: proc(dst, src: ^IR_Value) {
	if dst != nil && dst.note == "" && src != nil {
		dst.note = src.note
	}
}

fold_and_cse :: proc(opt: ^Opt, function: ^IR_Function) {
	clear(&opt.consts)
	clear(&opt.values)
	for block in function.blocks {
		kept := 0
		for op in block.instructions {
			if op.kind == .Call {
				for k in 0 ..< op.arg_count {
					op.args[k] = resolve(opt, op.args[k])
				}
				block.instructions[kept] = op
				kept += 1
				continue
			}
			if op.kind == .Phi {
				for &edge in op.edges {
					edge.value = resolve(opt, edge.value)
				}
				block.instructions[kept] = op
				kept += 1
				continue
			}
			for k in 0 ..< 5 {
				operand := resolve(opt, op.operands[k])
				if operand.kind == .Const {
					operand = intern_const(opt, operand.value, operand)
				}
				op.operands[k] = operand
			}
			if is_const_value(op.operands[1], 1) && is_const_value(op.operands[2], 0) {
				tested := complement_guard(op.operands[4])
				if tested != nil {
					swap := op.operands[0]
					op.operands[0] = op.operands[3]
					op.operands[3] = swap
					op.operands[4] = resolve(opt, tested)
				}
			}
			op.operands[4] = strip_guard(opt, op.operands[4])
			if op.operands[0].kind == .Const && op.operands[1].kind != .Const {
				swap := op.operands[0]
				op.operands[0] = op.operands[1]
				op.operands[1] = swap
			}
			fuse(opt, op)
			folded := fold(opt, op)
			if folded != nil {
				opt.forward[op.id] = folded
				continue
			}
			prior := common(opt, op)
			if prior != nil {
				opt.forward[op.id] = prior
				continue
			}
			append(&opt.values, op)
			block.instructions[kept] = op
			kept += 1
		}
		resize(&block.instructions, kept)
		if block.guard != nil {
			block.guard = resolve(opt, block.guard)
		}
		for i in 0 ..< len(block.results) {
			result := resolve(opt, block.results[i])
			if result.kind == .Const {
				result = intern_const(opt, result.value, result)
			}
			block.results[i] = result
		}
	}
}

mark_live :: proc(opt: ^Opt, value: ^IR_Value) {
	if value.kind == .Op || value.kind == .Call || value.kind == .Phi {
		opt.live[value.id] = 1
	}
}

dce :: proc(opt: ^Opt, function: ^IR_Function) {
	n_blocks := len(function.blocks)
	for block in function.blocks {
		if block.term == .Cond_Br && block.guard != nil {
			mark_live(opt, block.guard)
		}
		for r in block.results {
			mark_live(opt, r)
		}
	}
	for bi := n_blocks - 1; bi >= 0; bi -= 1 {
		block := function.blocks[bi]
		n_instructions := len(block.instructions)
		for i := n_instructions - 1; i >= 0; i -= 1 {
			op := block.instructions[i]
			if opt.live[op.id] == 0 {
				continue
			}
			switch op.kind {
			case .Call:
				for k in 0 ..< op.arg_count {
					mark_live(opt, op.args[k])
				}
			case .Phi:
				for edge in op.edges {
					mark_live(opt, edge.value)
				}
			case .Op, .Const, .Param, .Return, .Result:
				for k in 0 ..< 5 {
					if op.operands[k] != nil {
						mark_live(opt, op.operands[k])
					}
				}
			}
		}
	}
	for block in function.blocks {
		kept := 0
		for op in block.instructions {
			if opt.live[op.id] != 0 {
				block.instructions[kept] = op
				kept += 1
			}
		}
		resize(&block.instructions, kept)
	}
}

Clone :: struct {
	builder:   ^IR_Builder,
	values:    []^IR_Value,
	blocks:    []^IR_Block,
	args:      [^]^IR_Value,
	arg_count: Length,
}

clone_value :: proc(c: ^Clone, value: ^IR_Value) -> ^IR_Value {
	switch value.kind {
	case .Param:
		return c.args[value.index] if value.index < c.arg_count else nil
	case .Const:
		return value
	case .Op, .Call, .Phi, .Result, .Return:
		return c.values[value.id]
	}
	return nil
}

clone_shell :: proc(c: ^Clone, op: ^IR_Value) -> ^IR_Value {
	copy := ir_value_new(c.builder, op.kind)
	copy.note = op.note
	c.values[op.id] = copy
	return copy
}

stamp_inline_note :: proc(c: ^Clone, src: []^IR_Value, note: string) {
	if note == "" do return
	for inst in src {
		if inst == nil || inst.id >= Length(len(c.values)) do continue
		copy := c.values[inst.id]
		if copy != nil && copy.note == "" {
			copy.note = note
		}
	}
}

clone_fill :: proc(c: ^Clone, op: ^IR_Value) {
	copy := c.values[op.id]
	if op.kind == .Phi {
		copy.edges = make([dynamic]IR_Edge, ir_alloc(c.builder))
		for edge in op.edges {
			append(&copy.edges, IR_Edge{from = c.blocks[edge.from.id], value = clone_value(c, edge.value)})
		}
	} else {
		for k in 0 ..< 5 {
			if op.operands[k] != nil {
				copy.operands[k] = clone_value(c, op.operands[k])
			}
		}
	}
}

clone_instruction :: proc(c: ^Clone, op: ^IR_Value) -> ^IR_Value {
	clone_shell(c, op)
	clone_fill(c, op)
	return c.values[op.id]
}

replace_uses :: proc(function: ^IR_Function, old, with: ^IR_Value) {
	for block in function.blocks {
		for op in block.instructions {
			switch op.kind {
			case .Call:
				for k in 0 ..< op.arg_count {
					if op.args[k] == old {
						op.args[k] = with
					}
				}
			case .Phi:
				for &edge in op.edges {
					if edge.value == old {
						edge.value = with
					}
				}
			case .Op, .Const, .Param, .Return, .Result:
				for k in 0 ..< 5 {
					if op.operands[k] == old {
						op.operands[k] = with
					}
				}
			}
		}
		if block.guard == old {
			block.guard = with
		}
		for i in 0 ..< len(block.results) {
			if block.results[i] == old {
				block.results[i] = with
			}
		}
	}
}

inline_single :: proc(builder: ^IR_Builder, function: ^IR_Function, block: ^IR_Block, at: int) {
	call := block.instructions[at]
	body := call.callee.blocks[0]
	clone := Clone{
		builder   = builder,
		values    = make([]^IR_Value, builder.next_id, ir_alloc(builder)),
		args      = call.args,
		arg_count = call.arg_count,
	}
	rebuilt := make([dynamic]^IR_Value, ir_alloc(builder))
	append(&rebuilt, ..block.instructions[:at])
	for inst in body.instructions {
		append(&rebuilt, clone_instruction(&clone, inst))
	}
	stamp_inline_note(&clone, body.instructions[:], call.note)
	append(&rebuilt, ..block.instructions[at + 1:])
	block.instructions = rebuilt
	n_results := len(body.results)
	for i in 0 ..< call.result_count {
		if call.results[i] == nil {
			continue
		}
		result: ^IR_Value
		if int(i) < n_results {
			result = clone_value(&clone, body.results[i])
		}
		replace_uses(function, call.results[i], result)
	}
}

inline_multi :: proc(builder: ^IR_Builder, function: ^IR_Function, block: ^IR_Block, at: int) {
	call := block.instructions[at]
	callee := call.callee
	n := len(block.instructions)

	cont := ir_block(builder, function)
	append(&cont.instructions, ..block.instructions[at + 1:])
	cont.term = block.term
	cont.guard = block.guard
	cont.then_block = block.then_block
	cont.else_block = block.else_block
	clear(&cont.results)
	append(&cont.results, ..block.results[:])
	resize(&block.instructions, at)

	clone := Clone{
		builder   = builder,
		values    = make([]^IR_Value, builder.next_id, ir_alloc(builder)),
		blocks    = make([]^IR_Block, len(callee.blocks), ir_alloc(builder)),
		args      = call.args,
		arg_count = call.arg_count,
	}
	for src in callee.blocks {
		clone.blocks[src.id] = ir_block(builder, function)
	}
	n_results := call.result_count
	phis := make([]^IR_Value, n_results if n_results != 0 else 1, ir_alloc(builder))
	for i in 0 ..< n_results {
		phis[i] = ir_value_new(builder, .Phi)
		phis[i].edges = make([dynamic]IR_Edge, ir_alloc(builder))
	}
	for src in callee.blocks {
		for inst in src.instructions {
			clone_shell(&clone, inst)
		}
	}
	for src in callee.blocks {
		copy := clone.blocks[src.id]
		for inst in src.instructions {
			clone_fill(&clone, inst)
			append(&copy.instructions, clone.values[inst.id])
		}
		stamp_inline_note(&clone, src.instructions[:], call.note)
		switch src.term {
		case .Br:
			copy.term = .Br
			copy.then_block = clone.blocks[src.then_block.id]
		case .Cond_Br:
			copy.term = .Cond_Br
			copy.guard = clone_value(&clone, src.guard)
			copy.then_block = clone.blocks[src.then_block.id]
			copy.else_block = clone.blocks[src.else_block.id]
		case .Ret:
			copy.term = .Br
			copy.then_block = cont
			n_source := len(src.results)
			for i in 0 ..< n_results {
				value: ^IR_Value
				if int(i) < n_source {
					value = clone_value(&clone, src.results[i])
				}
				append(&phis[i].edges, IR_Edge{from = copy, value = value})
			}
		case .None:
		}
	}

	block.term = .Br
	block.then_block = clone.blocks[callee.blocks[0].id]

	result_values := make([]^IR_Value, n_results if n_results != 0 else 1, ir_alloc(builder))
	leading := make([dynamic]^IR_Value, ir_alloc(builder))
	for i in 0 ..< n_results {
		if len(phis[i].edges) == 1 {
			result_values[i] = phis[i].edges[0].value
		} else {
			result_values[i] = phis[i]
			if call.results[i] != nil {
				append(&leading, phis[i])
			}
		}
	}
	if len(leading) != 0 {
		instructions := make([dynamic]^IR_Value, ir_alloc(builder))
		append(&instructions, ..leading[:])
		append(&instructions, ..cont.instructions[:])
		cont.instructions = instructions
	}
	for i in 0 ..< n_results {
		if call.results[i] != nil {
			replace_uses(function, call.results[i], result_values[i])
		}
	}
	_ = n
}

find_call :: proc(function: ^IR_Function) -> (call: ^IR_Value, block: ^IR_Block, index: int, ok: bool) {
	for b in function.blocks {
		for inst, i in b.instructions {
			if inst.kind == .Call {
				return inst, b, i, true
			}
		}
	}
	return nil, nil, 0, false
}

inline_calls :: proc(builder: ^IR_Builder, function: ^IR_Function) {
	for {
		call, block, at, ok := find_call(function)
		if !ok {
			return
		}
		if len(call.callee.blocks) == 1 {
			inline_single(builder, function, block, at)
		} else {
			inline_multi(builder, function, block, at)
		}
	}
}

function_index :: proc(builder: ^IR_Builder, function: ^IR_Function) -> int {
	for f, i in builder.functions {
		if f == function {
			return i
		}
	}
	return 0
}

inline_order :: proc(builder: ^IR_Builder, function: ^IR_Function, state: []u8, order: ^[dynamic]^IR_Function) -> bool {
	idx := function_index(builder, function)
	if state[idx] == 2 {
		return true
	}
	if state[idx] == 1 {
		return false
	}
	state[idx] = 1
	for block in function.blocks {
		for op in block.instructions {
			if op.kind == .Call && !inline_order(builder, op.callee, state, order) {
				return false
			}
		}
	}
	state[idx] = 2
	append(order, function)
	return true
}

ir_inline :: proc(builder: ^IR_Builder) -> bool {
	n := len(builder.functions)
	state := make([]u8, n if n != 0 else 1, ir_alloc(builder))
	order := make([dynamic]^IR_Function, ir_alloc(builder))
	for f in builder.functions {
		if !inline_order(builder, f, state, &order) {
			return false
		}
	}
	for f in order {
		inline_calls(builder, f)
	}
	return true
}

block_pred_count :: proc(function: ^IR_Function, target: ^IR_Block) -> int {
	count := 0
	for block in function.blocks {
		if block.term == .Br && block.then_block == target {
			count += 1
		} else if block.term == .Cond_Br {
			if block.then_block == target {
				count += 1
			}
			if block.else_block == target {
				count += 1
			}
		}
	}
	return count
}

drop_blocks :: proc(builder: ^IR_Builder, function: ^IR_Function, drop: []^IR_Block) {
	kept := make([dynamic]^IR_Block, ir_alloc(builder))
	for block in function.blocks {
		remove := false
		for d in drop {
			if block == d {
				remove = true
				break
			}
		}
		if !remove {
			append(&kept, block)
		}
	}
	for b, i in kept {
		b.id = Length(i)
	}
	function.blocks = kept
}

arm_return_block :: proc(function: ^IR_Function, arm: ^IR_Block) -> ^IR_Block {
	if arm.term == .Ret {
		return arm
	}
	if arm.term == .Br && arm.then_block.term == .Ret && block_pred_count(function, arm.then_block) == 1 {
		return arm.then_block
	}
	return nil
}

phi_edge_value :: proc(phi: ^IR_Value, from: ^IR_Block) -> ^IR_Value {
	for edge in phi.edges {
		if edge.from == from {
			return edge.value
		}
	}
	return nil
}

select_collapse :: proc(builder: ^IR_Builder, function: ^IR_Function) -> bool {
	n := len(function.blocks)
	for i in 0 ..< n {
		head := function.blocks[i]
		if head.term != .Cond_Br {
			continue
		}
		then_block := head.then_block
		else_block := head.else_block
		guard := head.guard
		if then_block == else_block || then_block == head || else_block == head {
			continue
		}
		if block_pred_count(function, then_block) != 1 || block_pred_count(function, else_block) != 1 {
			continue
		}
		n_then := len(then_block.instructions)
		n_else := len(else_block.instructions)

		then_ret := arm_return_block(function, then_block)
		else_ret := arm_return_block(function, else_block)
		if then_ret != nil && else_ret != nil && then_ret != else_ret {
			builder.current = head
			append(&head.instructions, ..then_block.instructions[:n_then])
			if then_ret != then_block {
				append(&head.instructions, ..then_ret.instructions[:])
			}
			append(&head.instructions, ..else_block.instructions[:n_else])
			if else_ret != else_block {
				append(&head.instructions, ..else_ret.instructions[:])
			}
			clear(&head.results)
			for r in 0 ..< len(then_ret.results) {
				append(&head.results, ir_select(builder, then_ret.results[r], else_ret.results[r], guard))
			}
			head.term = .Ret
			drop: [4]^IR_Block
			n_drop := 0
			drop[n_drop] = then_block; n_drop += 1
			drop[n_drop] = else_block; n_drop += 1
			if then_ret != then_block {
				drop[n_drop] = then_ret; n_drop += 1
			}
			if else_ret != else_block {
				drop[n_drop] = else_ret; n_drop += 1
			}
			drop_blocks(builder, function, drop[:n_drop])
			return true
		}

		if then_block.term == .Br && else_block.term == .Br && then_block.then_block == else_block.then_block {
			merge := then_block.then_block
			if merge == head || merge == then_block || merge == else_block || block_pred_count(function, merge) != 2 {
				continue
			}
			builder.current = head
			append(&head.instructions, ..then_block.instructions[:n_then])
			append(&head.instructions, ..else_block.instructions[:n_else])
			rest := make([dynamic]^IR_Value, ir_alloc(builder))
			for op in merge.instructions {
				if op.kind == .Phi {
					sel := ir_select(builder, phi_edge_value(op, then_block), phi_edge_value(op, else_block), guard)
					replace_uses(function, op, sel)
				} else {
					append(&rest, op)
				}
			}
			append(&head.instructions, ..rest[:])
			head.term = merge.term
			head.guard = merge.guard
			head.then_block = merge.then_block
			head.else_block = merge.else_block
			clear(&head.results)
			append(&head.results, ..merge.results[:])
			drop := [3]^IR_Block{then_block, else_block, merge}
			drop_blocks(builder, function, drop[:])
			return true
		}
	}
	return false
}

remove_empty_block :: proc(builder: ^IR_Builder, function: ^IR_Function) -> bool {
	n_blocks := len(function.blocks)
	for bi in 1 ..< n_blocks {
		block := function.blocks[bi]
		if block.term != .Br || len(block.instructions) != 0 {
			continue
		}
		target := block.then_block
		if target == block {
			continue
		}
		target_has_phi := false
		for inst in target.instructions {
			if inst.kind == .Phi {
				target_has_phi = true
				break
			}
		}
		if target_has_phi {
			continue
		}
		for pred in function.blocks {
			if pred.term == .Br {
				if pred.then_block == block {
					pred.then_block = target
				}
			} else if pred.term == .Cond_Br {
				if pred.then_block == block {
					pred.then_block = target
				}
				if pred.else_block == block {
					pred.else_block = target
				}
			}
		}
		one := [1]^IR_Block{block}
		drop_blocks(builder, function, one[:])
		return true
	}
	return false
}

ir_select_pass :: proc(builder: ^IR_Builder) {
	for function in builder.functions {
		for remove_empty_block(builder, function) || select_collapse(builder, function) {
		}
	}
}

Pred :: struct {
	from:  ^IR_Block,
	guard: ^IR_Value,
	kind:  int,
}

edge_pred :: proc(builder: ^IR_Builder, from_pred: ^IR_Value, edge: ^Pred) -> ^IR_Value {
	if edge.kind == 0 {
		return from_pred
	}
	zero := ir_const(builder, 0)
	if edge.kind == 1 {
		return ir_select(builder, from_pred, zero, edge.guard)
	}
	return ir_select(builder, zero, from_pred, edge.guard)
}

flatten_order :: proc(builder: ^IR_Builder, block: ^IR_Block, state: []u8, order: ^[dynamic]^IR_Block) -> bool {
	state[block.id] = 1
	successors: [2]^IR_Block
	count := 0
	switch block.term {
	case .Br:
		successors[0] = block.then_block
		count = 1
	case .Cond_Br:
		successors[0] = block.then_block
		successors[1] = block.else_block
		count = 2
	case .Ret, .None:
	}
	for i in 0 ..< count {
		next := successors[i]
		if state[next.id] == 1 {
			return false
		}
		if state[next.id] == 0 && !flatten_order(builder, next, state, order) {
			return false
		}
	}
	state[block.id] = 2
	append(order, block)
	return true
}

flatten_function :: proc(builder: ^IR_Builder, function: ^IR_Function) -> bool {
	n_blocks := len(function.blocks)
	if n_blocks <= 1 {
		return true
	}

	state := make([]u8, n_blocks, ir_alloc(builder))
	order := make([dynamic]^IR_Block, ir_alloc(builder))
	if !flatten_order(builder, function.blocks[0], state, &order) {
		return false
	}
	n_order := len(order)
	for i in 0 ..< n_order / 2 {
		order[i], order[n_order - 1 - i] = order[n_order - 1 - i], order[i]
	}

	incoming := make([][dynamic]Pred, n_blocks, ir_alloc(builder))
	for i in 0 ..< n_blocks {
		incoming[i] = make([dynamic]Pred, ir_alloc(builder))
	}
	for block in function.blocks {
		if block.term == .Br {
			append(&incoming[block.then_block.id], Pred{from = block, kind = 0})
		} else if block.term == .Cond_Br {
			append(&incoming[block.then_block.id], Pred{from = block, guard = block.guard, kind = 1})
			append(&incoming[block.else_block.id], Pred{from = block, guard = block.guard, kind = 2})
		}
	}

	predicate := make([]^IR_Value, n_blocks, ir_alloc(builder))
	remap := make([]^IR_Value, builder.next_id, ir_alloc(builder))
	edge_of := make([]^IR_Value, n_blocks, ir_alloc(builder))
	merged := ir_block(builder, function)

	for block in order {
		if block == function.blocks[0] {
			predicate[block.id] = ir_const(builder, 1)
		} else {
			for i in 0 ..< n_blocks {
				edge_of[i] = nil
			}
			combined: ^IR_Value
			for &edge in incoming[block.id] {
				if predicate[edge.from.id] == nil {
					continue
				}
				ep := edge_pred(builder, predicate[edge.from.id], &edge)
				edge_of[edge.from.id] = ep
				combined = ir_max(builder, combined, ep) if combined != nil else ep
			}
			predicate[block.id] = combined if combined != nil else ir_const(builder, 0)
		}
		here := predicate[block.id]
		always := here.kind == .Const && here.value > 0

		for op in block.instructions {
			if op.kind != .Phi {
				continue
			}
			n_edges := len(op.edges)
			acc: ^IR_Value
			for k := n_edges - 1; k >= 0; k -= 1 {
				value := op.edges[k].value
				if k == n_edges - 1 {
					acc = value
					continue
				}
				guard := edge_of[op.edges[k].from.id]
				acc = ir_select(builder, value, acc, guard)
			}
			remap[op.id] = acc if acc != nil else ir_const(builder, 0)
		}

		for op in block.instructions {
			if op.kind == .Phi {
				continue
			}
			if !always {
				off := ir_const(builder, -1)
				op.operands[4] = ir_select(builder, op.operands[4], off, here)
			}
			append(&merged.instructions, op)
		}
	}

	for op in merged.instructions {
		if op.kind != .Op {
			continue
		}
		for k in 0 ..< 5 {
			operand := op.operands[k]
			if operand != nil && operand.kind == .Phi && remap[operand.id] != nil {
				op.operands[k] = remap[operand.id]
			}
		}
	}

	returns := make([dynamic]^IR_Block, ir_alloc(builder))
	for b in order {
		if b.term == .Ret {
			append(&returns, b)
		}
	}
	n_returns := len(returns)
	rets := int(function.return_count)
	clear(&merged.results)
	for r in 0 ..< rets {
		acc: ^IR_Value
		for i := n_returns - 1; i >= 0; i -= 1 {
			block := returns[i]
			value := block.results[r]
			if value.kind == .Phi && remap[value.id] != nil {
				value = remap[value.id]
			}
			acc = value if i == n_returns - 1 else ir_select(builder, value, acc, predicate[block.id])
		}
		append(&merged.results, acc)
	}
	merged.term = .Ret

	function.blocks[0] = merged
	resize(&function.blocks, 1)
	return true
}

ir_flatten :: proc(builder: ^IR_Builder) -> bool {
	for function in builder.functions {
		if !flatten_function(builder, function) {
			return false
		}
	}
	return true
}

output_rank :: proc(v: ^IR_Value) -> int {
	if v.kind != .Param {
		return 1
	}
	return 0 if v.index == 0 else 2 + int(v.index)
}

orient_minmax :: proc(opt: ^Opt, function: ^IR_Function) {
	uses := make([]Length, opt.builder.next_id, ir_alloc(opt.builder))
	for block in function.blocks {
		for op in block.instructions {
			if op.kind == .Op {
				for k in 0 ..< 5 {
					if op.operands[k] != nil && op.operands[k].kind == .Op {
						uses[op.operands[k].id] += 1
					}
				}
			}
		}
		for r in block.results {
			if r.kind == .Op {
				uses[r.id] += 1
			}
		}
		if block.guard != nil && block.guard.kind == .Op {
			uses[block.guard.id] += 1
		}
	}
	for block in function.blocks {
		for s in block.instructions {
			if s.kind != .Op {
				continue
			}
			if !(is_const_value(s.operands[1], 1) && is_const_value(s.operands[2], 0)) {
				continue
			}
			t, f, g := s.operands[0], s.operands[3], s.operands[4]
			if !is_unconditional(g) || !is_const_value(g.operands[1], -1) {
				continue
			}
			g0, g2 := g.operands[0], g.operands[2]
			if g0.kind == .Const || g2.kind == .Const {
				continue
			}
			minmax := (g0 == t && g2 == f) || (g0 == f && g2 == t)
			if minmax && uses[g.id] == 1 && output_rank(t) < output_rank(f) {
				s.operands[0] = f
				s.operands[3] = t
				g.operands[0] = g2
				g.operands[2] = g0
			}
		}
	}
}

ir_optimize :: proc(builder: ^IR_Builder) {
	opt := Opt{
		builder = builder,
		forward = make([]^IR_Value, builder.next_id, ir_alloc(builder)),
		live    = make([]u8, builder.next_id, ir_alloc(builder)),
		consts  = make([dynamic]^IR_Value, ir_alloc(builder)),
		values  = make([dynamic]^IR_Value, ir_alloc(builder)),
		fast    = builder.fast_math,
	}
	for function in builder.functions {
		fold_and_cse(&opt, function)
		dce(&opt, function)
		orient_minmax(&opt, function)
		for block in function.blocks {
			for inst in block.instructions {
				if inst.kind == .Op {
					canonicalize_factor(&opt, inst)
				}
			}
		}
	}
}
