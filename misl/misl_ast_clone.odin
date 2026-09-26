package misl

// Deep-clone a Proc_Lit so a polymorphic specialization can be rechecked without
// overwriting Ident.entity / tav / scopes on the generic AST.

clone_proc_lit :: proc(src: ^Proc_Lit) -> ^Proc_Lit {
	if src == nil do return nil
	cloned := clone_expr(src)
	return cloned.derived.(^Proc_Lit)
}

clone_expr_slice :: proc(src: []^Expr) -> []^Expr {
	if src == nil do return nil
	out := make([]^Expr, len(src))
	for e, i in src {
		out[i] = clone_expr(e)
	}
	return out
}

clone_stmt_slice :: proc(src: []^Stmt) -> []^Stmt {
	if src == nil do return nil
	out := make([]^Stmt, len(src))
	for s, i in src {
		out[i] = clone_stmt(s)
	}
	return out
}

clone_copy_node :: proc(dst, src: ^$T) {
	dst.state_flags = src.state_flags
}

clone_ident :: proc(src: ^Ident) -> ^Ident {
	if src == nil do return nil
	n := ast_new(Ident, src.pos, src.end)
	clone_copy_node(n, src)
	n.name = src.name
	return n
}

clone_field :: proc(src: ^Field) -> ^Field {
	if src == nil do return nil
	n := ast_new(Field, src.pos, src.end)
	clone_copy_node(n, src)
	n.docs = src.docs
	n.names = clone_expr_slice(src.names)
	n.type = clone_expr(src.type)
	n.default_value = clone_expr(src.default_value)
	n.tag = src.tag
	n.flags = src.flags
	n.semantics = clone_ident(src.semantics)
	n.comment = src.comment
	return n
}

clone_field_list :: proc(src: ^Field_List) -> ^Field_List {
	if src == nil do return nil
	n := ast_new(Field_List, src.pos, src.end)
	clone_copy_node(n, src)
	n.open = src.open
	n.close = src.close
	if src.list != nil {
		list := make([]^Field, len(src.list))
		for f, i in src.list {
			list[i] = clone_field(f)
		}
		n.list = list
	}
	return n
}

clone_expr :: proc(src: ^Expr) -> ^Expr {
	if src == nil do return nil
	switch v in src.derived_expr {
	case ^Bad_Expr:
		n := ast_new(Bad_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		return n
	case ^Ident:
		return clone_ident(v)
	case ^Implicit:
		n := ast_new(Implicit, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok = v.tok
		return n
	case ^Undef:
		n := ast_new(Undef, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok = v.tok
		return n
	case ^Basic_Lit:
		n := ast_new(Basic_Lit, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok = v.tok
		return n
	case ^Basic_Directive:
		n := ast_new(Basic_Directive, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok = v.tok
		n.name = v.name
		return n
	case ^Ellipsis:
		n := ast_new(Ellipsis, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok = v.tok
		n.expr = clone_expr(v.expr)
		return n
	case ^Proc_Lit:
		n := ast_new(Proc_Lit, v.pos, v.end)
		clone_copy_node(n, v)
		n.type = clone_expr(v.type).derived.(^Proc_Type) if v.type != nil else nil
		n.body = clone_stmt(v.body)
		n.tags = v.tags
		n.inlining = v.inlining
		n.where_token = v.where_token
		n.where_clauses = clone_expr_slice(v.where_clauses)
		return n
	case ^Comp_Lit:
		n := ast_new(Comp_Lit, v.pos, v.end)
		clone_copy_node(n, v)
		n.type = clone_expr(v.type)
		n.open = v.open
		n.elems = clone_expr_slice(v.elems)
		n.close = v.close
		n.tag = clone_expr(v.tag)
		return n
	case ^Tag_Expr:
		n := ast_new(Tag_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		n.op = v.op
		n.name = v.name
		n.expr = clone_expr(v.expr)
		return n
	case ^Unary_Expr:
		n := ast_new(Unary_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		n.op = v.op
		n.expr = clone_expr(v.expr)
		return n
	case ^Binary_Expr:
		n := ast_new(Binary_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		n.left = clone_expr(v.left)
		n.op = v.op
		n.right = clone_expr(v.right)
		return n
	case ^Paren_Expr:
		n := ast_new(Paren_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		n.open = v.open
		n.expr = clone_expr(v.expr)
		n.close = v.close
		return n
	case ^Selector_Expr:
		n := ast_new(Selector_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		n.expr = clone_expr(v.expr)
		n.op = v.op
		n.field = clone_ident(v.field)
		return n
	case ^Implicit_Selector_Expr:
		n := ast_new(Implicit_Selector_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		n.field = clone_ident(v.field)
		return n
	case ^Selector_Call_Expr:
		n := ast_new(Selector_Call_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		n.expr = clone_expr(v.expr)
		n.call = clone_expr(v.call).derived.(^Call_Expr) if v.call != nil else nil
		n.modified_call = v.modified_call
		return n
	case ^Index_Expr:
		n := ast_new(Index_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		n.expr = clone_expr(v.expr)
		n.open = v.open
		n.index = clone_expr(v.index)
		n.close = v.close
		return n
	case ^Deref_Expr:
		n := ast_new(Deref_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		n.expr = clone_expr(v.expr)
		n.op = v.op
		return n
	case ^Slice_Expr:
		n := ast_new(Slice_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		n.expr = clone_expr(v.expr)
		n.open = v.open
		n.low = clone_expr(v.low)
		n.interval = v.interval
		n.high = clone_expr(v.high)
		n.close = v.close
		return n
	case ^Matrix_Index_Expr:
		n := ast_new(Matrix_Index_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		n.expr = clone_expr(v.expr)
		n.open = v.open
		n.row_index = clone_expr(v.row_index)
		n.column_index = clone_expr(v.column_index)
		n.close = v.close
		return n
	case ^Call_Expr:
		n := ast_new(Call_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		n.inlining = v.inlining
		n.expr = clone_expr(v.expr)
		n.open = v.open
		n.args = clone_expr_slice(v.args)
		n.ellipsis = v.ellipsis
		n.close = v.close
		return n
	case ^Field_Value:
		n := ast_new(Field_Value, v.pos, v.end)
		clone_copy_node(n, v)
		n.field = clone_expr(v.field)
		n.sep = v.sep
		n.value = clone_expr(v.value)
		return n
	case ^Ternary_If_Expr:
		n := ast_new(Ternary_If_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		n.x = clone_expr(v.x)
		n.op1 = v.op1
		n.cond = clone_expr(v.cond)
		n.op2 = v.op2
		n.y = clone_expr(v.y)
		return n
	case ^Ternary_When_Expr:
		n := ast_new(Ternary_When_Expr, v.pos, v.end)
		clone_copy_node(n, v)
		n.x = clone_expr(v.x)
		n.op1 = v.op1
		n.cond = clone_expr(v.cond)
		n.op2 = v.op2
		n.y = clone_expr(v.y)
		return n
	case ^Type_Cast:
		n := ast_new(Type_Cast, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok = v.tok
		n.open = v.open
		n.type = clone_expr(v.type)
		n.close = v.close
		n.expr = clone_expr(v.expr)
		return n
	case ^Auto_Cast:
		n := ast_new(Auto_Cast, v.pos, v.end)
		clone_copy_node(n, v)
		n.op = v.op
		n.expr = clone_expr(v.expr)
		return n
	case ^Proc_Group:
		n := ast_new(Proc_Group, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok = v.tok
		n.open = v.open
		n.args = clone_expr_slice(v.args)
		n.close = v.close
		return n
	case ^Typeid_Type:
		n := ast_new(Typeid_Type, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok = v.tok
		n.specialization = clone_expr(v.specialization)
		return n
	case ^Helper_Type:
		n := ast_new(Helper_Type, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok = v.tok
		n.type = clone_expr(v.type)
		return n
	case ^Distinct_Type:
		n := ast_new(Distinct_Type, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok = v.tok
		n.type = clone_expr(v.type)
		return n
	case ^Poly_Type:
		n := ast_new(Poly_Type, v.pos, v.end)
		clone_copy_node(n, v)
		n.dollar = v.dollar
		n.type = clone_ident(v.type)
		n.specialization = clone_expr(v.specialization)
		return n
	case ^Proc_Type:
		n := ast_new(Proc_Type, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok = v.tok
		n.calling_convention = v.calling_convention
		n.params = clone_field_list(v.params)
		n.arrow = v.arrow
		n.results = clone_field_list(v.results)
		n.tags = v.tags
		n.generic = v.generic
		n.scope = nil
		return n
	case ^Pointer_Type:
		n := ast_new(Pointer_Type, v.pos, v.end)
		clone_copy_node(n, v)
		n.tag = clone_expr(v.tag)
		n.pointer = v.pointer
		n.elem = clone_expr(v.elem)
		return n
	case ^Multi_Pointer_Type:
		n := ast_new(Multi_Pointer_Type, v.pos, v.end)
		clone_copy_node(n, v)
		n.open = v.open
		n.pointer = v.pointer
		n.close = v.close
		n.elem = clone_expr(v.elem)
		return n
	case ^Array_Type:
		n := ast_new(Array_Type, v.pos, v.end)
		clone_copy_node(n, v)
		n.open = v.open
		n.tag = clone_expr(v.tag)
		n.len = clone_expr(v.len)
		n.close = v.close
		n.elem = clone_expr(v.elem)
		n.force_array = v.force_array
		return n
	case ^Struct_Type:
		n := ast_new(Struct_Type, v.pos, v.end)
		clone_copy_node(n, v)
		n.poly_params = clone_field_list(v.poly_params)
		n.align = clone_expr(v.align)
		n.where_token = v.where_token
		n.where_clauses = clone_expr_slice(v.where_clauses)
		n.fields = clone_field_list(v.fields)
		n.name_count = v.name_count
		n.scope = nil
		return n
	case ^Enum_Type:
		n := ast_new(Enum_Type, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok_pos = v.tok_pos
		n.base_type = clone_expr(v.base_type)
		n.open = v.open
		n.fields = clone_expr_slice(v.fields)
		n.close = v.close
		n.is_using = v.is_using
		n.scope = nil
		return n
	case ^Bit_Set_Type:
		n := ast_new(Bit_Set_Type, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok_pos = v.tok_pos
		n.open = v.open
		n.elem = clone_expr(v.elem)
		n.underlying = clone_expr(v.underlying)
		n.close = v.close
		n.scope = nil
		return n
	case ^Pipeline_Type:
		n := ast_new(Pipeline_Type, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok = v.tok
		return n
	case ^Matrix_Type:
		n := ast_new(Matrix_Type, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok_pos = v.tok_pos
		n.row_count = clone_expr(v.row_count)
		n.column_count = clone_expr(v.column_count)
		n.elem = clone_expr(v.elem)
		return n
	}
	return nil
}

clone_attribute :: proc(src: ^Attribute) -> ^Attribute {
	if src == nil do return nil
	n := ast_new(Attribute, src.pos, src.end)
	clone_copy_node(n, src)
	n.tok = src.tok
	n.open = src.open
	n.elems = clone_expr_slice(src.elems)
	n.close = src.close
	return n
}

clone_stmt :: proc(src: ^Stmt) -> ^Stmt {
	if src == nil do return nil
	switch v in src.derived_stmt {
	case ^Bad_Stmt:
		n := ast_new(Bad_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		return n
	case ^Empty_Stmt:
		n := ast_new(Empty_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		n.semicolon = v.semicolon
		return n
	case ^Expr_Stmt:
		n := ast_new(Expr_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		n.expr = clone_expr(v.expr)
		return n
	case ^Tag_Stmt:
		n := ast_new(Tag_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		n.op = v.op
		n.name = v.name
		n.stmt = clone_stmt(v.stmt)
		return n
	case ^Assign_Stmt:
		n := ast_new(Assign_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		n.lhs = clone_expr_slice(v.lhs)
		n.op = v.op
		n.rhs = clone_expr_slice(v.rhs)
		return n
	case ^Block_Stmt:
		n := ast_new(Block_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		n.label = clone_expr(v.label)
		n.open = v.open
		n.stmts = clone_stmt_slice(v.stmts)
		n.close = v.close
		n.uses_do = v.uses_do
		n.scope = nil
		return n
	case ^If_Stmt:
		n := ast_new(If_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		n.label = clone_expr(v.label)
		n.if_pos = v.if_pos
		n.init = clone_stmt(v.init)
		n.cond = clone_expr(v.cond)
		n.body = clone_stmt(v.body)
		n.else_pos = v.else_pos
		n.else_stmt = clone_stmt(v.else_stmt)
		n.scope = nil
		return n
	case ^When_Stmt:
		n := ast_new(When_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		n.when_pos = v.when_pos
		n.cond = clone_expr(v.cond)
		n.body = clone_stmt(v.body)
		n.else_stmt = clone_stmt(v.else_stmt)
		return n
	case ^Which_Stmt:
		n := ast_new(Which_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		n.which_pos = v.which_pos
		n.cond = clone_expr(v.cond)
		n.body = clone_stmt(v.body)
		n.partial = v.partial
		return n
	case ^Return_Stmt:
		n := ast_new(Return_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		n.results = clone_expr_slice(v.results)
		return n
	case ^For_Stmt:
		n := ast_new(For_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		n.label = clone_expr(v.label)
		n.for_pos = v.for_pos
		n.init = clone_stmt(v.init)
		n.cond = clone_expr(v.cond)
		n.post = clone_stmt(v.post)
		n.body = clone_stmt(v.body)
		n.scope = nil
		return n
	case ^Range_Stmt:
		n := ast_new(Range_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		n.label = clone_expr(v.label)
		n.for_pos = v.for_pos
		n.vals = clone_expr_slice(v.vals)
		n.in_pos = v.in_pos
		n.expr = clone_expr(v.expr)
		n.body = clone_stmt(v.body)
		n.reverse = v.reverse
		n.scope = nil
		return n
	case ^Case_Clause:
		n := ast_new(Case_Clause, v.pos, v.end)
		clone_copy_node(n, v)
		n.case_pos = v.case_pos
		n.list = clone_expr_slice(v.list)
		n.terminator = v.terminator
		n.body = clone_stmt_slice(v.body)
		n.scope = nil
		return n
	case ^Switch_Stmt:
		n := ast_new(Switch_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		n.label = clone_expr(v.label)
		n.switch_pos = v.switch_pos
		n.init = clone_stmt(v.init)
		n.cond = clone_expr(v.cond)
		n.body = clone_stmt(v.body)
		n.partial = v.partial
		n.scope = nil
		return n
	case ^Branch_Stmt:
		n := ast_new(Branch_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		n.tok = v.tok
		n.label = clone_ident(v.label)
		return n
	case ^Using_Stmt:
		n := ast_new(Using_Stmt, v.pos, v.end)
		clone_copy_node(n, v)
		n.list = clone_expr_slice(v.list)
		return n
	case ^Bad_Decl:
		n := ast_new(Bad_Decl, v.pos, v.end)
		clone_copy_node(n, v)
		return n
	case ^Value_Decl:
		n := ast_new(Value_Decl, v.pos, v.end)
		clone_copy_node(n, v)
		n.docs = v.docs
		if len(v.attributes) > 0 {
			attrs := make([dynamic]^Attribute, 0, len(v.attributes))
			for a in v.attributes {
				append(&attrs, clone_attribute(a))
			}
			n.attributes = attrs
		}
		n.names = clone_expr_slice(v.names)
		n.type = clone_expr(v.type)
		n.values = clone_expr_slice(v.values)
		n.comment = v.comment
		n.is_using = v.is_using
		n.is_mutable = v.is_mutable
		return n
	case ^Package_Decl:
		n := ast_new(Package_Decl, v.pos, v.end)
		clone_copy_node(n, v)
		n.docs = v.docs
		n.token = v.token
		n.name = v.name
		n.comment = v.comment
		return n
	case ^Import_Decl:
		n := ast_new(Import_Decl, v.pos, v.end)
		clone_copy_node(n, v)
		n.docs = v.docs
		if len(v.attributes) > 0 {
			attrs := make([dynamic]^Attribute, 0, len(v.attributes))
			for a in v.attributes {
				append(&attrs, clone_attribute(a))
			}
			n.attributes = attrs
		}
		n.is_using = v.is_using
		n.import_tok = v.import_tok
		n.name = v.name
		n.relpath = v.relpath
		n.fullpath = v.fullpath
		n.comment = v.comment
		return n
	}
	return nil
}
