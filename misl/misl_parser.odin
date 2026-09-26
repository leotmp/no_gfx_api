// We use a modified version of "core:odin"
// TODO: figure out licensing

// TODO(Dragos): i do not like the union api. Maybe we can switch to #raw_union
package misl

import "core:mem"
import "base:intrinsics"
import "core:fmt"
import "core:strings"

Proc_Tags :: bit_set[Proc_Tag]
Proc_Tag :: enum {
	Bounds_Check,
	No_Bounds_Check,
}

Proc_Inline :: enum {
	None,
	Inline,
	No_Inline,
}

Proc_Calling_Convention :: string

Node_State_Flags :: bit_set[Node_State_Flag]
Node_State_Flag :: enum {
	Bounds_Check,
	No_Bounds_Check,
	Type_Assert,
	No_Type_Assert,
}



Node :: struct {
	pos: Token_Pos,
	end: Token_Pos,
	state_flags: Node_State_Flags,
	derived: Any_Node,
}

Comment_Group :: struct {
	using node: Node,
	list: []Token,
}

Module_Kind :: enum {
	Normal,
	Builtin, // compiler-integrated core:builtin (parsed from core/builtin.misl)
	Synthetic, // leftover compiler-synthesized packages
}



Expr :: struct {
	using expr_base: Node,
	tav: Type_And_Value,
	derived_expr: Any_Expr,
}

Stmt :: struct {
	using stmt_base: Node,
	derived_stmt: Any_Stmt,
}

Decl :: struct {
	using decl_base: Stmt,
}

Bad_Expr :: struct {
	using node: Expr,
}

Ident :: struct {
	using node: Expr,
	name: string,
	entity: ^Entity,
}

Implicit  :: struct {
	using node: Expr,
	tok: Token,
}

Undef :: struct {
	using node: Expr,
	tok: Token_Kind,
}

Basic_Lit :: struct {
	using node: Expr,
	tok: Token,
}

Basic_Directive :: struct {
	using ode: Expr,
	tok: Token,
	name: string,
}

Ellipsis :: struct {
	using node: Expr,
	tok: Token_Kind,
	expr: ^Expr, // can be nil
}

Proc_Lit :: struct {
	using node: Expr,
	type: ^Proc_Type,
	body: ^Stmt, // nil if it's a foreign proc
	tags: Proc_Tags,
	inlining: Proc_Inline,
	where_token: Token,
	where_clauses: []^Expr,
}

Comp_Lit :: struct {
	using node: Expr,
	type: ^Expr, // nil when type is inferred TODO(Dragos): infer it in the typechecker
	open: Token_Pos,
	elems: []^Expr,
	close: Token_Pos,
	tag: ^Expr, // can be nil
}

Tag_Expr :: struct {
	using node: Expr,
	op: Token,
	name: string,
	expr: ^Expr,
}

Unary_Expr :: struct {
	using node: Expr,
	op: Token,
	expr: ^Expr, // nil in the case of [?]T x.?
}

Binary_Expr :: struct {
	using node: Expr,
	left: ^Expr,
	op: Token,
	right: ^Expr,
}

Paren_Expr :: struct {
	using node: Expr,
	open: Token_Pos,
	expr: ^Expr,
	close: Token_Pos,
}

Selector_Expr :: struct {
	using node: Expr,
	expr: ^Expr,
	op: Token,
	field: ^Ident,
}

Implicit_Selector_Expr :: struct {
	using node: Expr,
	field: ^Ident,
}

Selector_Call_Expr :: struct {
	using node: Expr,
	expr: ^Expr,
	call: ^Call_Expr,
	modified_call: bool,
}

Index_Expr :: struct {
	using node: Expr,
	expr: ^Expr,
	open: Token_Pos,
	index: ^Expr,
	close: Token_Pos,
}

Deref_Expr :: struct {
	using node: Expr,
	expr: ^Expr,
	op: Token,
}

Slice_Expr :: struct {
	using node: Expr,
	expr: ^Expr,
	open: Token_Pos,
	low: ^Expr, // can be nil
	interval: Token,
	high: ^Expr, // can be nil
	close: Token_Pos,
}

Matrix_Index_Expr :: struct {
	using node: Expr,
	expr: ^Expr,
	open: Token_Pos,
	row_index: ^Expr,
	column_index: ^Expr,
	close: Token_Pos,
}

Call_Expr :: struct {
	using node: Expr,
	inlining: Proc_Inline,
	expr: ^Expr,
	open: Token_Pos,
	args: []^Expr,
	ellipsis: Token,
	close: Token_Pos,
}

Field_Value :: struct {
	using node: Expr,
	field: ^Expr,
	sep: Token_Pos,
	value: ^Expr,
} 

Ternary_If_Expr :: struct {
	using node: Expr,
	x: ^Expr,
	op1: Token,
	cond: ^Expr,
	op2: Token,
	y: ^Expr,
}

Ternary_When_Expr :: struct {
	using node: Expr,
	x: ^Expr,
	op1: Token,
	cond: ^Expr,
	op2: Token,
	y: ^Expr,
}

Type_Cast :: struct {
	using node: Expr,
	tok: Token,
	open: Token_Pos,
	type: ^Expr,
	close: Token_Pos,
	expr: ^Expr,
}

Auto_Cast :: struct {
	using node: Expr,
	op: Token,
	expr: ^Expr,
}

Bad_Stmt :: struct {
	using node: Stmt,
}

Empty_Stmt :: struct {
	using node: Stmt,
	semicolon: Token_Pos, // position of the following ';'
}

Expr_Stmt :: struct {
	using node: Stmt,
	expr: ^Expr,
}

Tag_Stmt :: struct {
	using node: Stmt,
	op: Token,
	name: string,
	stmt: ^Stmt,
}

Assign_Stmt :: struct {
	using node: Stmt,
	lhs: []^Expr,
	op: Token,
	rhs: []^Expr,
}

Block_Stmt :: struct {
	using node: Stmt,
	label: ^Expr,
	open: Token_Pos,
	stmts: []^Stmt,
	close: Token_Pos,
	uses_do: bool,

	scope: ^Scope,
}

If_Stmt :: struct {
	using node: Stmt,
	label: ^Expr, // can be nil
	if_pos: Token_Pos,
	init: ^Stmt, // can be nil
	cond: ^Expr,
	body: ^Stmt, // TODO: probably all bodies can be block_stmt
	else_pos: Token_Pos,
	else_stmt: ^Stmt, // can be nil

	scope: ^Scope,
}

When_Stmt :: struct {
	using node: Stmt,
	when_pos: Token_Pos,
	cond: ^Expr,
	body: ^Stmt,
	else_stmt: ^Stmt, // can be nil
}

// Compile-time switch: only the taken `case` is collected, checked, and emitted.
// No new scope. No `break` / `fallthrough`. `#partial which` matches `#partial switch`.
Which_Stmt :: struct {
	using node: Stmt,
	which_pos: Token_Pos,
	cond: ^Expr, // nil → conditionless `which { case bool: … }`
	body: ^Stmt, // Block_Stmt of Case_Clause
	partial: bool,
}

Return_Stmt :: struct {
	using node: Stmt,
	results: []^Expr,
}

For_Stmt :: struct {
	using node: Stmt,
	label: ^Expr,
	for_pos: Token_Pos,
	init: ^Stmt,
	cond: ^Expr,
	post: ^Stmt,
	body: ^Stmt,
	
	scope: ^Scope,
}

Using_Stmt :: struct {
	using node: Stmt,
	list: []^Expr,
}

Range_Stmt :: struct {
	using node: Stmt,
	label: ^Expr,
	for_pos: Token_Pos,
	vals: []^Expr,
	in_pos: Token_Pos,
	expr: ^Expr,
	body: ^Stmt,
	reverse: bool,

	scope: ^Scope,
}

Case_Clause :: struct {
	using node: Stmt,
	case_pos: Token_Pos,
	list: []^Expr, 
	terminator: Token,
	body: []^Stmt,
	
	scope: ^Scope,
}

Switch_Stmt :: struct {
	using node: Stmt,
	label: ^Expr,
	switch_pos: Token_Pos,
	init: ^Stmt,
	cond: ^Expr,
	body: ^Stmt,
	partial: bool,

	scope: ^Scope,
}

Branch_Stmt :: struct {
	using node: Stmt,
	tok: Token,
	label: ^Ident,
}

Bad_Decl :: struct {
	using node: Decl,
}

Value_Decl :: struct {
	using node: Decl,
	docs: ^Comment_Group,
	attributes: [dynamic]^Attribute,
	names: []^Expr,
	type: ^Expr,
	values: []^Expr,
	comment: ^Comment_Group,
	is_using: bool,
	is_mutable: bool,
}

Package_Decl :: struct {
	using node: Decl,
	docs: ^Comment_Group,
	token: Token,
	name: string,
	comment: ^Comment_Group,
}

Import_Decl :: struct {
	using node: Decl,
	docs: ^Comment_Group,
	attributes: [dynamic]^Attribute,
	is_using: bool,
	import_tok: Token,
	name: Token,
	relpath: Token,
	fullpath: string,
	comment: ^Comment_Group,
}

Semantic_Tag :: struct {

}

ast_unparen_expr :: proc(expr: ^Expr) -> (val: ^Expr) {
	val = expr
	if expr == nil {
		return
	}
	for {
		e := val.derived.(^Paren_Expr) or_break
		if e.expr == nil {
			break
		}
		val = e.expr
	}
	return val
}

ast_strip_or_return_expr :: proc(expr: ^Expr) -> (val: ^Expr) {
	val = expr
	if expr == nil {
		return
	}
	for {
		inner: ^Expr
		#partial switch e in val.derived {
		case ^Paren_Expr:
			inner = e.expr
		}
		if inner == nil {
			break
		}
		val = inner
	}
	return val
}

Field_Flags :: bit_set[Field_Flag]
Field_Flag :: enum {
	Invalid,
	Unknown,

	Ellipsis,
	Using,
	Subtype,
	Any_Int,

	Typeid_Token,

	Results,
	Tags,
	Default_Parameters,
	Semantics,

	// Interpolation (struct varyings)
	Flat,
	Noperspective,
	Centroid,

	// Signature
	Ref, // #ref — mutable value parameter (call site requires `&`)
	Poly_Names, // $name constant parapoly on procedure parameters
}

Field_Flags_Struct :: Field_Flags{
	.Using,
	.Tags,
	.Subtype,
	.Semantics,
	.Flat,
	.Noperspective,
	.Centroid,
}

Field_Flags_Signature :: Field_Flags{
	.Ellipsis,
	.Using,
	.Any_Int,
	.Default_Parameters,
	.Semantics,
	.Ref,
	.Poly_Names,
}

Field_Flags_Record_Poly_Params :: Field_Flags{
	.Typeid_Token,
	.Default_Parameters,
}

Field_Flags_Signature_Params :: Field_Flags_Signature
Field_Flags_Signature_Results :: Field_Flags_Signature

field_hash_flag_strings := []struct{key: string, flag: Field_Flag} {
	{"flat", .Flat},
	{"noperspective", .Noperspective},
	{"centroid", .Centroid},
	{"ref", .Ref},
	{"subtype", .Subtype},
}

Proc_Group :: struct {
	using node: Expr,
	tok: Token,
	open: Token_Pos,
	args: []^Expr,
	close: Token_Pos,
}

Attribute :: struct {
	using node: Node,
	tok: Token_Kind,
	open: Token_Pos,
	elems: []^Expr,
	close: Token_Pos,
}

Field :: struct {
	using node: Node,
	docs: ^Comment_Group,
	names: []^Expr,
	type: ^Expr,
	default_value: ^Expr,
	tag: Token,
	flags: Field_Flags,
	semantics: ^Ident,
	comment: ^Comment_Group,
}

Field_List :: struct {
	using node: Node,
	open: Token_Pos,
	list: []^Field,
	close: Token_Pos,
}

Typeid_Type :: struct {
	using node: Expr,
	tok: Token_Kind,
	specialization: ^Expr,
}

Helper_Type :: struct {
	using node: Expr,
	tok: Token_Kind,
	type: ^Expr,
}

Distinct_Type :: struct {
	using node: Expr,
	tok: Token_Kind,
	type: ^Expr,
}

Poly_Type :: struct {
	using node: Expr,
	dollar: Token_Pos,
	type: ^Ident,
	specialization: ^Expr,
}

Proc_Type :: struct {
	using node: Expr,
	tok: Token,
	calling_convention: Proc_Calling_Convention,
	params: ^Field_List,
	arrow: Token_Pos,
	results: ^Field_List,
	tags: Proc_Tags,
	generic: bool,

	scope: ^Scope,
}

Pointer_Type :: struct {
	using node: Expr,
	tag: ^Expr,
	pointer: Token_Pos,
	elem: ^Expr,
}

Multi_Pointer_Type :: struct {
	using node: Expr,
	open: Token_Pos,
	pointer: Token_Pos,
	close: Token_Pos,
	elem: ^Expr,
}

Array_Type :: struct {
	using node: Expr,
	open: Token_Pos,
	tag: ^Expr,
	len: ^Expr, // unary expr for [?]T, nil for slice types
	close: Token_Pos,
	elem: ^Expr,
	force_array: bool, // `#array [N]T` — keep as array, not a vector
}

Struct_Type :: struct {
	using node: Expr,
	poly_params: ^Field_List,
	align: ^Expr, 
	where_token: Token,
	where_clauses: []^Expr,
	fields: ^Field_List,
	name_count: int,

	scope: ^Scope,
}

Enum_Type :: struct {
	using node: Expr,
	tok_pos: Token_Pos,
	base_type: ^Expr,
	open: Token_Pos,
	fields: []^Expr,
	close: Token_Pos,
	is_using: bool,

	scope: ^Scope,
}


// TODO(Dragos): Should this also have a scope?
Bit_Set_Type :: struct {
	using node: Expr,
	tok_pos: Token_Pos,
	open: Token_Pos,
	elem: ^Expr,
	underlying: ^Expr,
	close: Token_Pos,

	scope: ^Scope,
}

// `pipeline` in `name :: pipeline { ... }`
Pipeline_Type :: struct {
	using node: Expr,
	tok: Token,
}

Matrix_Type :: struct {
	using node: Expr,
	tok_pos: Token_Pos,
	row_count: ^Expr,
	column_count: ^Expr,
	elem: ^Expr,
}



Any_Node :: union {
	^Module,
	^Comment_Group,

	^Bad_Expr,
	^Ident,
	^Implicit,
	^Undef,
	^Basic_Lit,
	^Basic_Directive,
	^Ellipsis,
	^Proc_Lit,
	^Comp_Lit,
	^Tag_Expr,
	^Unary_Expr,
	^Binary_Expr,
	^Paren_Expr,
	^Selector_Expr,
	^Implicit_Selector_Expr,
	^Selector_Call_Expr,
	^Index_Expr,
	^Deref_Expr,
	^Slice_Expr,
	^Matrix_Index_Expr,
	^Call_Expr,
	^Field_Value,
	^Ternary_If_Expr,
	^Ternary_When_Expr,
	// ^Or_Else_Expr,
	// ^Or_Return_Expr,
	// ^Or_Branch_Expr,
	// ^Type_Assertion,
	^Type_Cast,
	^Auto_Cast,
	// ^Inline_Asm_Expr,

	^Proc_Group,

	^Typeid_Type,
	^Helper_Type,
	^Distinct_Type,
	^Poly_Type,
	^Proc_Type,
	^Pointer_Type,
	^Multi_Pointer_Type,
	^Array_Type,
	// ^Dynamic_Array_Type,
	^Struct_Type,
	// ^Union_Type,
	^Enum_Type,
	^Bit_Set_Type,
	^Pipeline_Type,
	//^Map_Type,
	//^Relative_Type,
	^Matrix_Type,
	//^Bit_Field_Type,

	^Bad_Stmt,
	^Empty_Stmt,
	^Expr_Stmt,
	^Tag_Stmt,
	^Assign_Stmt,
	^Block_Stmt,
	^If_Stmt,
	^When_Stmt,
	^Which_Stmt,
	^Return_Stmt,
	//^Defer_Stmt,
	^For_Stmt,
	^Range_Stmt,
	//^Inline_Range_Stmt,
	^Case_Clause,
	^Switch_Stmt,
	//^Type_Switch_Stmt,
	^Branch_Stmt,
	^Using_Stmt,

	^Bad_Decl,
	^Value_Decl,
	^Package_Decl,
	^Import_Decl,
	//^Foreign_Block_Decl,
	//^Foreign_Import_Decl,

	^Attribute,
	^Field,
	^Field_List,
	//^Bit_Field_Field,
}


Any_Expr :: union {
	^Bad_Expr,
	^Ident,
	^Implicit,
	^Undef,
	^Basic_Lit,
	^Basic_Directive,
	^Ellipsis,
	^Proc_Lit,
	^Comp_Lit,
	^Tag_Expr,
	^Unary_Expr,
	^Binary_Expr,
	^Paren_Expr,
	^Selector_Expr,
	^Implicit_Selector_Expr,
	^Selector_Call_Expr,
	^Index_Expr,
	^Deref_Expr,
	^Slice_Expr,
	^Matrix_Index_Expr,
	^Call_Expr,
	^Field_Value,
	^Ternary_If_Expr,
	^Ternary_When_Expr,
	// ^Or_Else_Expr,
	// ^Or_Return_Expr,
	// ^Or_Branch_Expr,
	// ^Type_Assertion,
	^Type_Cast,
	^Auto_Cast,
	// ^Inline_Asm_Expr,

	^Proc_Group,

	^Typeid_Type,
	^Helper_Type,
	^Distinct_Type,
	^Poly_Type,
	^Proc_Type,
	^Pointer_Type,
	^Multi_Pointer_Type,
	^Array_Type,
	//^Dynamic_Array_Type,
	^Struct_Type,
	//^Union_Type,
	^Enum_Type,
	^Bit_Set_Type,
	^Pipeline_Type,
	//^Map_Type,
	//^Relative_Type,
	^Matrix_Type,
	//^Bit_Field_Type,
}


Any_Stmt :: union {
	^Bad_Stmt,
	^Empty_Stmt,
	^Expr_Stmt,
	^Tag_Stmt,
	^Assign_Stmt,
	^Block_Stmt,
	^If_Stmt,
	^When_Stmt,
	^Which_Stmt,
	^Return_Stmt,
	//^Defer_Stmt,
	^For_Stmt,
	^Range_Stmt,
	//^Inline_Range_Stmt,
	^Case_Clause,
	^Switch_Stmt,
	//^Type_Switch_Stmt,
	^Branch_Stmt,
	^Using_Stmt,

	^Bad_Decl,
	^Value_Decl,
	^Package_Decl,
	^Import_Decl,
	//^Foreign_Block_Decl,
	//^Foreign_Import_Decl,
}

ast_new_from_positions :: proc($T: typeid, pos, end: Token_Pos) -> ^T {
	n, _ := mem.new(T)
	n.pos = pos
	n.end = end
	n.derived = n
	
	// do some checks
	base: ^Node = n
	_ = base
	when intrinsics.type_has_field(T, "derived_expr") {
		n.derived_expr = n
	}
	when intrinsics.type_has_field(T, "derived_stmt") {
		n.derived_stmt = n
	}
	return n
}

ast_new_from_pos_and_end_node :: proc($T: typeid, pos: Token_Pos, end: ^Node) -> ^T {
	return ast_new(T, pos, end.end if end != nil else pos)
}

ast_new :: proc {
	ast_new_from_positions,
	ast_new_from_pos_and_end_node,
}

Parser_Flags :: bit_set[Parser_Flag]
Parser_Flag :: enum {
	Optional_Semicolons,
}

Parser :: struct {
	module: ^Module,
	lex: Lexer,

	flags: Parser_Flags,

	warn: Warning_Handler,
	err: Error_Handler,

	prev_tok: Token,
	curr_tok: Token,

	// >= 0: in expression
	// < 0: in control clause
	expr_level: int,
	allow_range: bool,
	allow_in_expr: bool,
	in_foreign_block: bool,
	allow_type: bool,

	lead_comment: ^Comment_Group,
	line_comment: ^Comment_Group,

	curr_proc: ^Node,

	allow_import: bool, // file-scope only; false inside when/which/blocks

	error_count: int,

	fix_count: int,
	fix_prev_pos: Token_Pos,

	peeking: bool,
}

PARSER_MAX_FIX_COUNT :: 10

Stmt_Allow_Flags :: distinct bit_set[Stmt_Allow_Flag]
Stmt_Allow_Flag :: enum {
	In,
	Label,
}

Import_Decl_Kind :: enum {
	Standard,
	Using,
}

parse_file_tag :: proc(p: ^Parser, tok: Token) {
	append(&p.module.tags, tok)
	text := strings.trim_space(tok.text)
	rest := text
	if strings.has_prefix(rest, "#+") {
		rest = rest[2:]
	} else if strings.has_prefix(rest, "#") {
		rest = rest[1:]
	}
	fields := strings.fields(rest)
	if len(fields) == 0 {
		parse_err(p, tok.pos, "empty file tag")
		return
	}
	dir_ok := false
	for d in FILE_TAG_DIRECTIVES {
		if fields[0] == d.name {
			dir_ok = true
			break
		}
	}
	if !dir_ok {
		parse_err(p, tok.pos, "unknown file tag '#+%s'", fields[0])
		return
	}
	if fields[0] != "feature" {
		return
	}
	if len(fields) != 2 {
		parse_err(p, tok.pos, "expected '#+feature <name>'")
		return
	}
	for f in FILE_TAG_FEATURES {
		if f.name != fields[1] {
			continue
		}
		switch f.name {
		case "no_bounds_check":
			p.module.no_bounds_check = true
		case "disable-asserts":
			p.module.disable_asserts = true
		}
		return
	}
	parse_err(p, tok.pos, "unknown #+feature '%s'", fields[1])
}

parse_check_directive_for_statement :: proc(p: ^Parser, stmt: ^Stmt, tag: Token, flag: Node_State_Flag) -> ^Stmt {
	if stmt == nil {
		parse_err(p, tag.pos, "invalid operand for '#%s'", tag.text)
		return stmt
	}
	if _, is_empty := stmt.derived.(^Empty_Stmt); is_empty {
		if p.prev_tok.text == "\n" {
			parse_err(p, tag.pos, "#%s cannot be followed by a newline", tag.text)
		} else {
			parse_err(p, tag.pos, "#%s cannot be applied to an empty statement ';'", tag.text)
		}
	}
	if flag in stmt.state_flags {
		parse_err(p, tag.pos, "#%s has been applied multiple times", tag.text)
	}
	stmt.state_flags += {flag}
	if .Bounds_Check in stmt.state_flags && .No_Bounds_Check in stmt.state_flags {
		parse_err(p, tag.pos, "#bounds_check and #no_bounds_check cannot be applied together")
	}
	ok := false
	#partial switch s in stmt.derived_stmt {
	case ^Block_Stmt, ^If_Stmt, ^When_Stmt, ^Which_Stmt, ^For_Stmt, ^Range_Stmt, ^Switch_Stmt, ^Return_Stmt, ^Assign_Stmt:
		ok = true
	case ^Value_Decl:
		if !s.is_mutable {
			parse_err(p, tag.pos, "#%s may only be applied to a variable declaration, and not a constant value declaration", tag.text)
		}
		ok = true
	}
	if !ok {
		parse_err(p, tag.pos, "#%s may only be applied to the following statements: block, 'if', 'when', 'which', 'for', 'switch', 'return', assignment, variable declaration", tag.text)
	}
	return stmt
}

parse_check_directive_for_expr :: proc(p: ^Parser, expr: ^Expr, tag: Token, flag: Node_State_Flag) -> ^Expr {
	if expr == nil {
		parse_err(p, tag.pos, "invalid operand for '#%s'", tag.text)
		return expr
	}
	if flag in expr.state_flags {
		parse_err(p, tag.pos, "#%s has been applied multiple times", tag.text)
	}
	expr.state_flags += {flag}
	if .Bounds_Check in expr.state_flags && .No_Bounds_Check in expr.state_flags {
		parse_err(p, tag.pos, "#bounds_check and #no_bounds_check cannot be applied together")
	}
	return expr
}

apply_proc_bound_tags_to_body :: proc(body: ^Stmt, tags: Proc_Tags) {
	if body == nil do return
	if .No_Bounds_Check in tags {
		body.state_flags += {.No_Bounds_Check}
	}
	if .Bounds_Check in tags {
		body.state_flags += {.Bounds_Check}
	}
}

parse_warn :: proc(p: ^Parser, pos: Token_Pos, msg: string, args: ..any) {
	if p.warn != nil {
		p.warn(pos, msg, ..args)
	}
	p.module.syntax_warning_count += 1
}

parse_err :: proc(p: ^Parser, pos: Token_Pos, msg: string, args: ..any) {
	if p.err != nil {
		p.err(pos, msg, ..args)
	}
	p.module.syntax_error_count += 1
	p.error_count += 1
}

default_parser :: proc(flags := Parser_Flags{.Optional_Semicolons}) -> Parser {
	return {
		flags = flags,
		err = default_error_handler,
		warn = default_warning_handler,
	}
}

err_unimplemented_tokens :: proc(p: ^Parser, tok: Token) -> bool {
	#partial switch tok.kind {
	// Note: .When is implemented (`when` stmts) — do not gate it here.
	// .Using is implemented (Using_Stmt, field prefix, import name).
	case .Imaginary, .Non_Uniform, .Module:
		parse_err(p, tok.pos, "token '%v' is currently unimplemented", tok.text)
		return true
	}
	return false
}

parse_module :: proc(p: ^Parser, module: ^Module) -> bool {
	zero_parser: {
		p.prev_tok = {}
		p.curr_tok = {}
		p.expr_level = {}
		p.allow_range = {}
		p.allow_in_expr = {}
		p.in_foreign_block = {}
		p.allow_type = {}
		p.lead_comment = {}
		p.line_comment = {}
		p.curr_proc = {}
		p.allow_import = true
	}
	
	p.lex.flags += {.Insert_Semicolons}

	p.module = module
	lexer_init(&p.lex, module.code, module.fullpath, p.err)
	if p.lex.ch <= 0 {
		return true
	}

	advance_token(p)

	for p.curr_tok.kind == .File_Tag {
		parse_file_tag(p, p.curr_tok)
		advance_token(p)
	}

	for p.curr_tok.kind != .EOF {
		stmt := parse_stmt(p)
		if stmt != nil {
			if _, ok := stmt.derived.(^Empty_Stmt); !ok {
				append(&p.module.decls, stmt)
				if es, es_ok := stmt.derived.(^Expr_Stmt); es_ok && es.expr != nil {
					if _, pl_ok := es.expr.derived.(^Proc_Lit); pl_ok {
						parse_err(p, stmt.pos, "procedure literal evaluated but not used")
					}
				}
			}
		}
	}

	collect_parsed_entries(p.module)
	
	return true
}

expect_token :: proc(p: ^Parser, kind: Token_Kind) -> Token {
	prev := p.curr_tok
	if prev.kind != kind {
		parse_err(p, prev.pos, "expected '%v', got '%v'", token_kind_to_string(kind), token_to_string(prev))
	}
	advance_token(p)
	return prev
}

expect_token_after :: proc(p: ^Parser, kind: Token_Kind, msg: string) -> Token {
	prev := p.curr_tok
	if prev.kind != kind {
		e := token_kind_to_string(kind)
		g := token_to_string(prev)
		parse_err(p, prev.pos, "expected '%v' after %v, got '%v'", e, msg, g)
	}
	advance_token(p)
	return prev
}

expect_operator :: proc(p: ^Parser) -> Token {
	prev := p.curr_tok
	#partial switch prev.kind {
	case .If, .When:
		// ok
	case:
		if !token_is_operator(prev.kind) {
			g := token_to_string(prev)
			parse_err(p, prev.pos, "expected an operator, got '%s'", g)
		}
	}
	advance_token(p)
	return prev
}

allow_token :: proc(p: ^Parser, kind: Token_Kind) -> bool {
	if p.curr_tok.kind == kind {
		advance_token(p)
		return true
	}
	return false
}

advance_token :: proc(p: ^Parser) -> Token {
	p.lead_comment = nil
	p.line_comment = nil
	p.prev_tok = p.curr_tok
	prev := p.prev_tok
	if next_token(p) {
		consume_comment_groups(p, prev)
	}
	return prev
}

next_token :: proc(p: ^Parser) -> bool {
	p.curr_tok, _ = lex_scan(&p.lex)
	if err_unimplemented_tokens(p, p.curr_tok) do return false
	if p.curr_tok.kind == .EOF {
		return false
	}
	return true
}

end_of_line_pos :: proc(p: ^Parser, tok: Token) -> Token_Pos {
	offset := clamp(tok.pos.offset, 0, len(p.lex.code)-1)
	s := p.lex.code[offset:]
	pos := tok.pos
	pos.column -= 1
	for len(s) != 0 && s[0] != 0 && s[0] != '\n' {
		s = s[1:]
		pos.column += 1
	}
	return pos
}

is_blank_ident :: proc{
	is_blank_ident_string,
	is_blank_ident_token,
	is_blank_ident_node,
}

token_is_non_inserted_semicolon :: proc(tok: Token) -> bool {
	return tok.kind == .Semicolon && tok.text != "\n"
}

is_blank_ident_string :: proc(str: string) -> bool {
	return str == "_"
}
is_blank_ident_token :: proc(tok: Token) -> bool {
	if tok.kind == .Ident do return is_blank_ident_string(tok.text)
	return false
}
is_blank_ident_node :: proc(node: ^Node) -> bool {
	if ident, ok := node.derived.(^Ident); ok {
		return is_blank_ident(ident.name)
	}
	return false
}

consume_comment_groups :: proc(p: ^Parser, prev: Token) {
	if p.curr_tok.kind != .Comment {
		return
	}
	comment: ^Comment_Group
	end_line := 0

	if p.curr_tok.pos.line == prev.pos.line {
		comment, end_line = consume_comment_group(p, 0)
		if p.curr_tok.pos.line != end_line ||
		   p.curr_tok.pos.line == prev.pos.line + 1 ||
		   p.curr_tok.kind == .EOF {
			p.line_comment = comment
		}
	}

	end_line = -1
	for p.curr_tok.kind == .Comment {
		comment, end_line = consume_comment_group(p, 1)
		if end_line+1 >= p.curr_tok.pos.line || end_line < 0 {
			p.lead_comment = comment
		}
	}

	assert(p.curr_tok.kind != .Comment)
}

consume_comment_group :: proc(p: ^Parser, n: int) -> (comments: ^Comment_Group, end_line: int) {
	list: [dynamic]Token
	end_line = p.curr_tok.pos.line
	for p.curr_tok.kind == .Comment && p.curr_tok.pos.line <= end_line+n {
		comment: Token
		comment, end_line = consume_comment(p)
		append(&list, comment)
	}

	if len(list) > 0 && !p.peeking {
		comments = ast_new(Comment_Group, list[0].pos, token_end_pos(list[len(list)-1]))
		comments.list = list[:]
		append(&p.module.comments, comments)
	}

	return comments, end_line
}

consume_comment :: proc(p: ^Parser) -> (tok: Token, end_line: int) {
	tok = p.curr_tok
	assert(tok.kind == .Comment)
	end_line = tok.pos.line
	if tok.text[1] == '*' {
		for c in tok.text {
			if c == '\n' {
				end_line += 1
			}
		}
	}
	next_token(p)
	if p.curr_tok.pos.line > tok.pos.line {
		end_line += 1
	}
	return tok, end_line
}

token_precedence :: proc(p: ^Parser, kind: Token_Kind) -> int {
	#partial switch kind {
	case .Question, .If, .When, .Invalid:
		return 1
	case .Ellipsis, .Range_Exclusive, .Range_Inclusive: return 0 if !p.allow_range else 2
	case .Cmp_Or: return 3
	case .Cmp_And: return 4
	case .Cmp_Eq, .Not_Eq, .Lt, .Gt, .Lt_Eq, .Gt_Eq: return 5
	case .In, .Not_In: return 0 if p.expr_level < 0 && !p.allow_in_expr else 6
	case .Add, .Sub, .Or, .Xor: return 6
	case .Mul, .Quo, .Mod, .And, .And_Not, .Shl, .Shr: return 7
	}
	return 0
}

parse_type_or_ident :: proc(p: ^Parser) -> ^Expr {
	prev_allow_type := p.allow_type
	prev_expr_level := p.expr_level
	defer {
		p.allow_type = prev_allow_type
		p.expr_level = prev_expr_level
	}

	p.allow_type = true
	p.expr_level = -1
	lhs := true
	return parse_atom_expr(p, parse_operand(p, lhs), lhs)
}

parse_type :: proc(p: ^Parser) -> ^Expr {
	type := parse_type_or_ident(p)
	if type == nil {
		parse_err(p, p.curr_tok.pos, "expected a type")
		return ast_new(Bad_Expr, p.curr_tok.pos, token_end_pos(p.curr_tok))
	}
	return type
}

parse_atom_expr :: proc(p: ^Parser, value: ^Expr, lhs: bool) -> (operand: ^Expr) {
	operand = value
	if operand == nil {
		if p.allow_type {
			return nil
		}
		parse_err(p, p.curr_tok.pos, "expected an operand")
		fix_advance_to_next_stmt(p)
		be := ast_new(Bad_Expr, p.curr_tok.pos, token_end_pos(p.curr_tok))
		operand = be
	}

	loop := true
	is_lhs := lhs
	for loop {
		#partial switch p.curr_tok.kind {
		case: loop = false
		case .Open_Paren: operand = parse_call_expr(p, operand)
		case .Open_Bracket:
			prev_allow_range := p.allow_range
			defer p.allow_range = prev_allow_range
			p.allow_range = false

			indices: [2]^Expr
			interval: Token
			is_slice_op := false // TODO(Dragos): remove slicing eventually

			p.expr_level += 1
			open := expect_token(p, .Open_Bracket)
			
			#partial switch p.curr_tok.kind {
			case .Colon, .Ellipsis, .Range_Exclusive, .Range_Inclusive: break
			case: indices[0] = parse_expr(p, false)
			}

			#partial switch p.curr_tok.kind {
			case .Ellipsis, .Range_Exclusive, .Range_Inclusive:
				parse_err(p, p.curr_tok.pos, "expected a colon, not a range")
				fallthrough
			case .Colon, .Comma:
				interval = advance_token(p)
				is_slice_op = true
				if p.curr_tok.kind != .Close_Bracket && p.curr_tok.kind != .EOF {
					indices[1] = parse_expr(p, false)
				}
			}

			close := expect_token(p, .Close_Bracket)
			p.expr_level -= 1

			if is_slice_op {
				if interval.kind == .Comma {
					if indices[0] == nil || indices[1] == nil {
						parse_err(p, p.curr_tok.pos, "matrix index expression requires both row and column indices")
					}
					se := ast_new(Matrix_Index_Expr, operand.pos, token_end_pos(close))
					se.expr = operand
					se.open, se.close = open.pos, close.pos
					se.row_index, se.column_index = indices[0], indices[1]

					operand = se
				} else {
					se := ast_new(Slice_Expr, operand.pos, token_end_pos(close)) // Todo(dragos): Probably slice expr isn't needed
					se.expr = operand
					se.open, se.close = open.pos, close.pos
					se.low, se.high = indices[0], indices[1]
					se.interval = interval
					
					operand = se
				}
			} else {
				ie := ast_new(Index_Expr, operand.pos, token_end_pos(close))
				ie.expr = operand
				ie.open, ie.close = open.pos, close.pos
				ie.index = indices[0]

				operand = ie
			}

		case .Period:
			tok := expect_token(p, .Period)
			#partial switch p.curr_tok.kind {
			case .Ident:
				// Newline after `.` → incomplete `foo.` (next line's ident is a new statement).
				if p.curr_tok.pos.line > tok.pos.line {
					parse_warn(p, tok.pos, "expected a selector")
					operand = empty_selector_expr(tok, operand)
				} else {
					field := parse_ident(p)

					sel := ast_new(Selector_Expr, operand.pos, field)
					sel.expr = operand
					sel.op = tok
					sel.field = field

					operand = sel
				}

			case:
				// Trailing `.` while typing — recover with an empty field so checking
				// can still type the LHS (IDE field completion).
				parse_warn(p, p.curr_tok.pos, "expected a selector")
				operand = empty_selector_expr(tok, operand)
			}
		
		case .Arrow_Right: // method-style `v->f()` is not part of MISL
			tok := expect_token(p, .Arrow_Right)
			parse_err(p, tok.pos, "'->' method selectors are not supported; use '.' or a call")
			#partial switch p.curr_tok.kind {
			case .Ident:
				field := parse_ident(p)
				sel := ast_new(Selector_Expr, operand.pos, field)
				sel.expr = operand
				sel.op = tok
				sel.field = field
				operand = sel
			case:
				operand = empty_selector_expr(tok, operand)
			}
		
		case .Pointer:
			op := expect_token(p, .Pointer)
			deref := ast_new(Deref_Expr, operand.pos, token_end_pos(op))
			deref.expr = operand
			deref.op = op

			operand = deref

		case .Open_Brace:
			if !is_lhs && is_literal_type(operand) && p.expr_level >= 0 {
				operand = parse_literal_value(p, operand)
			} else {
				loop = false
			}
		
		case .Increment, .Decrement:
			if !lhs {
				tok := advance_token(p)
				parse_err(p, tok.pos, "postfix '%s' operator is not supported", tok.text)
			} else {
				loop = false
			}
		}

		is_lhs = false
	}

	return operand
}

parse_operand :: proc(p: ^Parser, lhs: bool) -> ^Expr {
	#partial switch p.curr_tok.kind {
	case .Ident:
		return parse_ident(p)

	case .Pipeline:
		tok := expect_token(p, .Pipeline)
		pt := ast_new(Pipeline_Type, tok.pos, token_end_pos(tok))
		pt.tok = tok
		return pt
	
	case .Undef:
		tok := expect_token(p, .Undef)
		undef := ast_new(Undef, tok.pos, token_end_pos(tok))
		undef.tok = tok.kind
		return undef

	case .Integer, .Float, .Imaginary, .Rune, .String:
		tok := advance_token(p)
		bl := ast_new(Basic_Lit, tok.pos, token_end_pos(tok))
		bl.tok = tok
		return bl

	case .Open_Brace:
		if !lhs {
			return parse_literal_value(p, nil)
		}

	case .Open_Paren:
		open := expect_token(p, .Open_Paren)
		p.expr_level += 1
		expr := parse_expr(p, false)
		skip_possible_newline(p)
		p.expr_level -= 1
		close := expect_token(p, .Close_Paren)

		pe := ast_new(Paren_Expr, open.pos, token_end_pos(close))
		pe.open, pe.close = open.pos, close.pos
		pe.expr = expr
		return pe

	case .Hash:
		tok := expect_token(p, .Hash)
		name := expect_token(p, .Ident)
		switch name.text {
		case "type":
			type := parse_type(p)
			hp := ast_new(Helper_Type, tok.pos, type)
			hp.tok = tok.kind
			hp.type = type
			return type

		case "array":
			type := parse_type(p)
			if at, ok := type.derived.(^Array_Type); ok {
				if at.len == nil {
					parse_err(p, name.pos, "'#array' requires a fixed-length [N]T, not a slice")
				} else {
					at.force_array = true
				}
				return type
			}
			parse_err(p, name.pos, "'#array' applies to [N]T array types")
			return type

		
		case "assert", "panic", "config", "intrinsic":
			bd := ast_new(Basic_Directive, tok.pos, token_end_pos(name))
			bd.tok = tok
			bd.name = name.text
			return parse_call_expr(p, bd)

		case "partial": // TODO(Dragos): i don't think partial is required as an operand

		case "inline", "no_inline":
			return parse_inlining_operand(p, lhs, name)

		case "bounds_check":
			return parse_check_directive_for_expr(p, parse_expr(p, lhs), name, .Bounds_Check)
		case "no_bounds_check":
			return parse_check_directive_for_expr(p, parse_expr(p, lhs), name, .No_Bounds_Check)
		
		case:
			parse_err(p, name.pos, "unknown directive '#%s'", name.text)
			expr := parse_expr(p, lhs)
			end := expr.pos if expr != nil else token_end_pos(tok)
			te := ast_new(Tag_Expr, tok.pos, end)
			te.op = tok
			te.name = name.text
			te.expr = expr
			return te
		}
	
	case .Proc:
		tok := expect_token(p, .Proc)
		if p.curr_tok.kind == .Open_Brace {
			open := expect_token(p, .Open_Brace)
			args: [dynamic]^Expr
			for p.curr_tok.kind != .Close_Brace && p.curr_tok.kind != .EOF {
				elem := parse_expr(p, false)
				append(&args, elem)
				allow_token(p, .Comma) or_break
			}
			close := expect_closing_brace_of_field_list(p)

			if len(args) == 0 {
				parse_err(p, tok.pos, "expected at least 1 argument in procedure group")
			}

			pg := ast_new(Proc_Group, tok.pos, token_end_pos(close))
			pg.tok = tok
			pg.open, pg.close = open.pos, close.pos
			pg.args = args[:]
			return pg
		}

		type := parse_proc_type(p, tok)
		tags: Proc_Tags
		where_token: Token
		where_clauses: []^Expr

		skip_possible_newline_for_literal(p)

		if p.curr_tok.kind == .Where {
			where_token = expect_token(p, .Where)
			prev_level := p.expr_level
			p.expr_level = -1
			where_clauses = parse_rhs_expr_list(p)
			p.expr_level = prev_level
		}
		tags = parse_proc_tags(p)
		type.tags = tags

		if p.allow_type && p.expr_level < 0 {
			if where_token.kind != .Invalid {
				parse_err(p, where_token.pos, "'where' clauses are not allowed on procedure types")
			}
			return type
		}
		
		body: ^Stmt
		skip_possible_newline_for_literal(p)

		if allow_token(p, .Undef) {
			body = nil
			if where_token.kind != .Invalid {
				parse_err(p, where_token.pos, "'where' clauses are not allowed on procedure literals without a defined body")
			}
		} else if p.curr_tok.kind == .Open_Brace {
			prev_proc := p.curr_proc
			p.curr_proc = type
			body = parse_body(p)
			p.curr_proc = prev_proc
		} else if allow_token(p, .Do) {
			prev_proc := p.curr_proc
			p.curr_proc = type
			body = convert_stmt_to_body(p, parse_stmt(p))
			p.curr_proc = prev_proc
			if type.pos.line != body.pos.line {
				parse_err(p, body.pos, "the body of a 'do' must be on the same line as the signature")
			}
		} else {
			return type
		}
		apply_proc_bound_tags_to_body(body, tags)

		pl := ast_new(Proc_Lit, tok.pos, token_end_pos(p.prev_tok))
		pl.type = type
		pl.body = body
		pl.tags = tags
		pl.where_token = where_token
		pl.where_clauses = where_clauses
		return pl

	case .Dollar:
		tok := advance_token(p)
		type := parse_ident(p)
		end := type.end

		specialization: ^Expr
		if allow_token(p, .Quo) {
			specialization = parse_type(p)
			end = specialization.pos
		}
		if is_blank_ident(type) {
			parse_err(p, type.pos, "invalid polymorphic type definition with a blank identifier")
		}

		pt := ast_new(Poly_Type, tok.pos, end)
		pt.dollar = tok.pos
		pt.type = type
		pt.specialization = specialization
		return pt

	case .Typeid:
		tok := advance_token(p)
		ti := ast_new(Typeid_Type, tok.pos, token_end_pos(tok))
		ti.tok = tok.kind
		ti.specialization = nil
		return ti

	case .Pointer:
		tok := expect_token(p, .Pointer)
		elem := parse_type(p)
		ptr := ast_new(Pointer_Type, tok.pos, elem)
		ptr.pointer = tok.pos
		ptr.elem = elem
		return ptr

	case .Open_Bracket:
		open := expect_token(p, .Open_Bracket)
		count: ^Expr
		#partial switch p.curr_tok.kind {
		case .Pointer: // [^]T multipointer (BDA)
			tok := expect_token(p, .Pointer)
			close := expect_token(p, .Close_Bracket)
			elem := parse_type(p)
			mp := ast_new(Multi_Pointer_Type, open.pos, elem)
			mp.open = open.pos
			mp.pointer = tok.pos
			mp.close = close.pos
			mp.elem = elem
			return mp
		case .Question: // TODO(dragos): check if this handles [?]T {...}
			tok := expect_token(p, .Question)
			q := ast_new(Unary_Expr, tok.pos, token_end_pos(tok))
			q.op = tok
			count = q
		case:
			p.expr_level += 1
			count = parse_expr(p, false)
			p.expr_level -= 1
		case .Close_Bracket:
			// handled below
		}
		close := expect_token(p, .Close_Bracket)
		elem := parse_type(p)
		at := ast_new(Array_Type, open.pos, elem)
		at.open = open.pos
		at.len = count
		at.close = close.pos
		at.elem = elem
		return at

	case .Struct:
		tok := expect_token(p, .Struct)

		poly_params: ^Field_List
		align: ^Expr
		fields: ^Field_List
		name_count: int
		
		if allow_token(p, .Open_Paren) {
			param_count: int
			poly_params, param_count = parse_field_list(p, .Close_Paren, Field_Flags_Record_Poly_Params)
			if param_count == 0 {
				parse_err(p, poly_params.pos, "expected at least 1 polymorphic parameter")
				poly_params = nil
			}
			expect_token_after(p, .Close_Paren, "parameter list")
		}

		prev_level := p.expr_level
		p.expr_level = -1
		for allow_token(p, .Hash) {
			tag := expect_token_after(p, .Ident, "#")
			switch tag.text { // TODO(Dragos): figure out what struct tags we want (probably align)
			case "align":
				if align != nil {
					parse_err(p, tag.pos, "duplicate struct tag '#%s'", tag.text)
				}
				align = parse_expr(p, true)
			case: parse_err(p, tag.pos, "invalid struct tag '#%s'", tag.text)
			}
		}
		p.expr_level = prev_level

		where_token: Token
		where_clauses: []^Expr

		skip_possible_newline_for_literal(p)

		if p.curr_tok.kind == .Where {
			where_token = expect_token(p, .Where)
			where_prev_level := p.expr_level
			p.expr_level = -1
			where_clauses = parse_rhs_expr_list(p)
			p.expr_level = where_prev_level
		}

		skip_possible_newline_for_literal(p)
		expect_token(p, .Open_Brace)
		fields, name_count = parse_field_list(p, .Close_Brace, Field_Flags_Struct) // TODO(Dragos): probably in this proc we need to implement our semantics syntax
		close := expect_closing_brace_of_field_list(p)

		st := ast_new(Struct_Type, tok.pos, token_end_pos(close))
		st.poly_params = poly_params
		st.align = align
		st.fields = fields
		st.name_count = name_count
		st.where_token = where_token
		st.where_clauses = where_clauses
		return st

	case .Enum:
		tok := expect_token(p, .Enum)
		base_type: ^Expr
		if p.curr_tok.kind != .Open_Brace {
			base_type = parse_type(p)
		}

		skip_possible_newline_for_literal(p)
		open := expect_token(p, .Open_Brace)
		fields := parse_elem_list(p)
		close := expect_closing_brace_of_field_list(p)

		et := ast_new(Enum_Type, tok.pos, token_end_pos(close))
		et.base_type = base_type
		et.open = open.pos
		et.fields = fields
		et.close = close.pos
		return et

	case .Bit_Set:
		tok := expect_token(p, .Bit_Set)
		open := expect_token(p, .Open_Bracket)
		elem, underlying: ^Expr

		// Recover while typing: `bit_set[` then newline/EOF before elem.
		if p.curr_tok.kind == .Close_Bracket || p.curr_tok.kind == .EOF || token_is_newline(p.curr_tok) || p.curr_tok.kind == .Semicolon {
			if p.curr_tok.kind == .Close_Bracket {
				close := advance_token(p)
				bst := ast_new(Bit_Set_Type, tok.pos, token_end_pos(close))
				bst.tok_pos = tok.pos
				bst.open = open.pos
				bst.elem = ast_new(Bad_Expr, open.pos, token_end_pos(close))
				bst.underlying = nil
				bst.close = close.pos
				return bst
			}
			// Leave `]` unclosed — still produce a Bit_Set_Type so checker soft-fails.
			bst := ast_new(Bit_Set_Type, tok.pos, token_end_pos(p.curr_tok))
			bst.tok_pos = tok.pos
			bst.open = open.pos
			bst.elem = ast_new(Bad_Expr, open.pos, token_end_pos(p.curr_tok))
			bst.underlying = nil
			bst.close = p.curr_tok.pos
			return bst
		}

		prev_allow_range := p.allow_range
		p.allow_range = true
		elem = parse_expr(p, false)
		p.allow_range = prev_allow_range

		if allow_token(p, .Semicolon) {
			underlying = parse_type(p)
		}

		close := expect_token(p, .Close_Bracket)
		
		bst := ast_new(Bit_Set_Type, tok.pos, token_end_pos(close))
		bst.tok_pos = tok.pos
		bst.open = open.pos
		bst.elem = elem
		bst.underlying = underlying
		bst.close = close.pos
		return bst

	case .Matrix:
		tok := expect_token(p, .Matrix)
		expect_token(p, .Open_Bracket)
		row_count := parse_expr(p, false)
		expect_token(p, .Comma)
		column_count := parse_expr(p, false)
		expect_token(p, .Close_Bracket)
		elem := parse_type(p)

		mt := ast_new(Matrix_Type, tok.pos, elem)
		mt.tok_pos = tok.pos
		mt.row_count = row_count
		mt.column_count = column_count
		mt.elem = elem
		return mt
	}
	return nil
}

parse_field_list :: proc(p: ^Parser, follow: Token_Kind, allowed_flags: Field_Flags) -> (field_list: ^Field_List, total_name_count: int) {
	handle_field :: proc(p: ^Parser, seen_ellipsis: ^bool, fields: ^[dynamic]^Field, 
	                     docs: ^Comment_Group, names: []^Expr, allowed_flags, set_flags: Field_Flags) -> bool {
		expect_field_separator :: proc(p: ^Parser, param: ^Expr) -> bool {
			tok := p.curr_tok
			if allow_token(p, .Comma) {
				return true
			}
			if allow_token(p, .Semicolon) {
				if !token_is_newline(tok) {
					parse_err(p, tok.pos, "expected a comma, got a semicolon")
				}
				return true
			}
			return false
		}

		is_type_ellipsis :: proc(type: ^Expr) -> bool { // TODO(Dragos): figure out if ellipsis is something our syntax wants to support
			if type == nil {
				return false
			}
			_, ok := type.derived.(^Ellipsis)
			return ok
		}

		is_signature := (allowed_flags & Field_Flags_Signature_Params) == Field_Flags_Signature_Params

		any_polymorphic_names := validate_procedure_name_list(p, names)
		flags := validate_field_flag_prefixes(p, len(names), allowed_flags, set_flags)
		
		type, default_value: ^Expr
		tag: Token
		semantics: ^Ident

		expect_token_after(p, .Colon, "field list")

		if p.curr_tok.kind != .Eq {
			type = parse_var_type(p, allowed_flags)
			tt := unparen_expr(type)
			if is_signature && !any_polymorphic_names {
				if ti, ok := tt.derived.(^Typeid_Type); ok && ti.specialization != nil {
					parse_err(p, tt.pos, "specialization of typeid is not allowed without polymorphic names")
				}
			}
		}

		// semantic name with Pipe operator
		if allow_token(p, .Or) {
			semantics = parse_ident(p)
			if .Semantics not_in allowed_flags {
				parse_err(p, p.curr_tok.pos, "semantic names are only allowed on structs and shader stage parameters")
				semantics = nil
			}
		}

		if allow_token(p, .Eq) {
			default_value = parse_expr(p, false)
			if .Default_Parameters not_in allowed_flags { // TODO(Dragos): figure out if we want default parameters in structs
				parse_err(p, p.curr_tok.pos, "default parameters are only allowed for procedures")
				default_value = nil
			}
		}

		if default_value != nil && len(names) > 1 {
			parse_err(p, p.curr_tok.pos, "default parameters can only be applied to single values")
		}

		if allowed_flags == Field_Flags_Struct && default_value != nil {
			parse_err(p, default_value.pos, "default parameters are not allowed in structs")
			default_value = nil
		}

		if is_type_ellipsis(type) {
			if seen_ellipsis^ {
				parse_err(p, type.pos, "extra variadic parameter after ellipsis")
			}
			seen_ellipsis^ = true
			if len(names) != 1 {
				parse_err(p, type.pos, "variadic parameters can only have one field name")
			}
		} else if seen_ellipsis^ && default_value == nil {
			parse_err(p, p.curr_tok.pos, "extra parameter after ellipsis without a default value")
		}

		if type != nil && default_value == nil {
			if p.curr_tok.kind == .String {
				tag = expect_token(p, .String)
				if .Tags not_in allowed_flags {
					parse_err(p, tag.pos, "field tags are only allowed within structures")
				}
			}
		}

		ok := expect_field_separator(p, type)

		field := new_ast_field(names, type, default_value)
		field.tag = tag
		field.docs = docs
		field.flags = flags
		field.comment = p.line_comment
		field.semantics = semantics
		append(fields, field)
		
		return ok
	}

	start_tok := p.curr_tok
	docs := p.lead_comment
	fields: [dynamic]^Field
	list: [dynamic]Expr_And_Flags
	defer delete(list)

	seen_ellipsis := false

	allow_typeid_token := .Typeid_Token in allowed_flags
	allow_poly_names := allow_typeid_token || .Poly_Names in allowed_flags

	for p.curr_tok.kind != follow && p.curr_tok.kind != .Colon && p.curr_tok.kind != .EOF {
		prefix_flags := parse_field_prefixes(p)
		param := parse_var_type(p, allowed_flags & {.Typeid_Token, .Ellipsis})
		if _, ok := param.derived.(^Ellipsis); ok {
			if seen_ellipsis {
				parse_err(p, param.pos, "extra variadic parameter after ellipsis")
			}
			seen_ellipsis = true
		} else if seen_ellipsis {
			parse_err(p, param.pos, "extra parameter after ellipsis")
		}

		eaf := Expr_And_Flags{param, prefix_flags}
		append(&list, eaf)
		allow_token(p, .Comma) or_break
	}

	if p.curr_tok.kind != .Colon {
		for eaf in list {
			type := eaf.expr
			tok: Token
			tok.pos = type.pos
			if .Results not_in allowed_flags {
				tok.text = "_"
			}

			names := make([]^Expr, 1)
			names[0] = ast_new(Ident, tok.pos, token_end_pos(tok))
			#partial switch ident in names[0].derived_expr {
			case ^Ident: ident.name = tok.text
			case: unreachable()
			}

			flags := validate_field_flag_prefixes(p, len(list), allowed_flags, eaf.flags)

			field := new_ast_field(names, type, nil)
			field.docs = docs
			field.flags = flags
			field.comment = p.line_comment
			append(&fields, field)
 		}
	} else {
		names := convert_to_ident_list(p, list[:], true, allow_poly_names)
		if len(names) == 0 {
			parse_err(p, p.curr_tok.pos, "empty field declaration")
		}

		set_flags: Field_Flags
		if len(list) > 0 {
			set_flags = list[0].flags
		}
		total_name_count += len(names)
		handle_field(p, &seen_ellipsis, &fields, docs, names, allowed_flags, set_flags)

		for p.curr_tok.kind != follow && p.curr_tok.kind != .EOF {
			docs = p.lead_comment
			set_flags = parse_field_prefixes(p)
			names = parse_ident_list(p, allow_poly_names)
			total_name_count += len(names)
			handle_field(p, &seen_ellipsis, &fields, docs, names, allowed_flags, set_flags) or_break
		}
	}

	field_list = ast_new(Field_List, start_tok.pos, p.curr_tok.pos)
	field_list.list = fields[:]
	return field_list, total_name_count
}

parse_ident_list :: proc(p: ^Parser, allow_poly_names: bool) -> []^Expr {
	list: [dynamic]^Expr
	for {
		if allow_poly_names && p.curr_tok.kind == .Dollar {
			tok := expect_token(p, .Dollar)
			ident := parse_ident(p)
			if is_blank_ident(ident) {
				parse_err(p, ident.pos, "invalid polymorphic type definition with a blank identifier")
			}
			poly_name := ast_new(Poly_Type, tok.pos, ident)
			poly_name.type = ident
			append(&list, poly_name)
		} else {
			ident := parse_ident(p)
			append(&list, ident)
		}
		if p.curr_tok.kind != .Comma || p.curr_tok.kind == .EOF {
			break
		}
		advance_token(p)
	}
	return list[:]
}

convert_to_ident_list :: proc(p: ^Parser, list: []Expr_And_Flags, ignore_flags, allow_poly_names: bool) -> []^Expr {
	idents := make([dynamic]^Expr, 0, len(list))
	
	for ident, i in list {
		if !ignore_flags {
			if i != 0 {
				parse_err(p, ident.expr.pos, "illegal use of prefixes in parameter list")
			}
		}

		id: ^Expr = ident.expr

		#partial switch n in ident.expr.derived_expr {
		case ^Ident:
		case ^Bad_Expr:
		case ^Poly_Type:
			if allow_poly_names {
				if n.specialization == nil {
					break
				} else {
					parse_err(p, ident.expr.pos, "expected a poly identifier without a specialization")
				}
			} else {
				parse_err(p, ident.expr.pos, "expected a non-poly identifier")
			}
		
		case:
			parse_err(p, ident.expr.pos, "expected an identifier")
			id = ast_new(Ident, ident.expr.pos, ident.expr.end)
		}
		
		append(&idents, id)
	}

	return idents[:]
}

// TODO(Dragos): add here our new flags
is_token_field_prefix :: proc(p: ^Parser) -> Field_Flag {
	#partial switch p.curr_tok.kind {
	case .EOF:
		return .Invalid
	case .Using:
		advance_token(p)
		return .Using
	case .Hash:
		tok: Token
		hash_pos := p.curr_tok.pos
		advance_token(p)
		tok = p.curr_tok
		advance_token(p)
		if tok.kind == .Ident {
			if tok.text == "inout" {
				parse_err(p, tok.pos, "'#inout' was renamed to '#ref'")
				return .Unknown
			}
			for kf in field_hash_flag_strings {
				if kf.key == tok.text {
					return kf.flag
				}
			}
			parse_err(p, tok.pos, "unknown field tag '#%s'", tok.text)
		} else {
			parse_err(p, hash_pos, "expected identifier after '#'")
		}
		return .Unknown
	}
	return .Invalid
}

Expr_And_Flags :: struct {
	expr: ^Expr,
	flags: Field_Flags,
}

parse_var_type :: proc(p: ^Parser, flags: Field_Flags) -> ^Expr {
	if .Ellipsis in flags && p.curr_tok.kind == .Ellipsis {
		tok := advance_token(p)
		type := parse_type_or_ident(p)
		if type == nil {
			parse_err(p, tok.pos, "variadic field missing type after '..'")
			type = ast_new(Bad_Expr, tok.pos, token_end_pos(tok))
 		}
		e := ast_new(Ellipsis, type.pos, type)
		e.tok = tok.kind
		e.expr = type
		return e
	}
	type: ^Expr
	if .Typeid_Token in flags && p.curr_tok.kind == .Typeid {
		tok := expect_token(p, .Typeid)
		specialization: ^Expr
		end := tok.pos
		if allow_token(p, .Quo) {
			specialization = parse_type(p)
			end = specialization.end
		}

		ti := ast_new(Typeid_Type, tok.pos, end)
		ti.tok = tok.kind
		ti.specialization = specialization
		type = ti
	} else {
		type = parse_type(p)
	}
	return type
}


parse_field_prefixes :: proc(p: ^Parser) -> (flags: Field_Flags) {
	counts: [len(Field_Flag)]int

	for {
		kind := is_token_field_prefix(p)
		if kind == .Invalid {
			break
		}

		if kind == .Unknown {
			// Error already reported in is_token_field_prefix
			continue
		}

		counts[kind] += 1
	}

	for kind in Field_Flag {
		count := counts[kind]
		if kind == .Invalid || kind == .Unknown {
			// ignore
		} else {
			if count > 1 do parse_err(p, p.curr_tok.pos, "multiple '%s' in this field list", kind)
			if count > 0 do flags += {kind}
		}
	}

	return flags
}

validate_field_flag_prefixes :: proc(p: ^Parser, name_count: int, allowed_flags, set_flags: Field_Flags) -> (flags: Field_Flags) {
	flags = set_flags
	if name_count > 1 && .Using in flags {
		parse_err(p, p.curr_tok.pos, "cannot apply 'using' to more than one of the same type")
		flags -= {.Using}
	}

	for flag in Field_Flag {
		if flag not_in allowed_flags && flag in flags {
			#partial switch flag {
			case .Unknown, .Invalid: // ignore
			case .Tags, .Ellipsis, .Results, .Default_Parameters, .Typeid_Token:
				parse_err(p, p.curr_tok.pos, "internal: unexpected field list prefix '%v'", flag)
			case: // TODO(dragos): stringify flag
				parse_err(p, p.curr_tok.pos, "'%v' is not allowed within this field list", flag)
			}
			flags -= {flag}
		}
	}

	return flags
}

validate_procedure_name_list :: proc(p: ^Parser, names: []^Expr) -> bool {
	if len(names) == 0 {
		return false
	}

	_, first_is_polymorphic := names[0].derived.(^Poly_Type)
	any_polymorphic_names := first_is_polymorphic

	for i := 0; i < len(names); i += 1 {
		name := names[i]

		if first_is_polymorphic {
			if _, ok := name.derived.(^Poly_Type); ok {
				any_polymorphic_names = true
			} else {
				parse_err(p, name.pos, "mixture of polymorphic and non-polymorphic identifiers")
				return any_polymorphic_names
			}
		} else {
			if _, ok := name.derived.(^Poly_Type); ok {
				any_polymorphic_names = true
				parse_err(p, name.pos, "mixture of polymoprhic and non-polymorphic identifiers")
				return any_polymorphic_names
			} else {
				// ok
			}
		}
	}
	
	return any_polymorphic_names
}

parse_proc_tags :: proc(p: ^Parser) -> (tags: Proc_Tags) {
	for p.curr_tok.kind == .Hash {
		_ = expect_token(p, .Hash)
		ident := expect_token(p, .Ident)

		switch ident.text {
		case "bounds_check":
			tags += {.Bounds_Check}
		case "no_bounds_check":
			tags += {.No_Bounds_Check}
		case:
			parse_err(p, ident.pos, "unknown procedure tag '#%s'", ident.text)
		}
	}

	if .Bounds_Check in tags && .No_Bounds_Check in tags {
		parse_err(p, p.curr_tok.pos, "#bounds_check and #no_bounds_check applied to the same procedure type")
	}

	return tags
}

parse_proc_type :: proc(p: ^Parser, tok: Token) -> ^Proc_Type {
	cc: Proc_Calling_Convention
	if p.curr_tok.kind == .String {
		str := expect_token(p, .String)
		cc = str.text
	}

	expect_token(p, .Open_Paren)
	p.expr_level += 1
	params, _ := parse_field_list(p, .Close_Paren, Field_Flags_Signature)
	p.expr_level -= 1
	expect_closing_parenthesis_of_field_list(p) 
	results := parse_results(p)

	is_generic := false
	loop: for param in params.list {
		if param.type != nil {
			if _, ok := param.type.derived.(^Poly_Type); ok {
				is_generic = true
				break loop
			}
			for name in param.names {
				if _, ok  := name.derived.(^Poly_Type); ok {
					is_generic = true
					break loop
				}
			}
		}
	}

	end := token_end_pos(p.prev_tok)
	pt := ast_new(Proc_Type, tok.pos, end)
	pt.tok = tok
	pt.calling_convention = cc
	pt.params = params
	pt.results = results
	pt.generic = is_generic
	return pt
}

parse_results :: proc(p: ^Parser) -> (list: ^Field_List) {
	if !allow_token(p, .Arrow_Right) {
		return
	}

	prev_level := p.expr_level
	defer p.expr_level = prev_level

	if p.curr_tok.kind != .Open_Paren {
		type := parse_type(p)
		field := new_ast_field(nil, type, nil)
		list = ast_new(Field_List, field.pos, field.end)
		list.list = make([]^Field, 1)
		list.list[0] = field
		return list
	}

	expect_token(p, .Open_Paren)
	list, _ = parse_field_list(p, .Close_Paren, Field_Flags_Signature_Results)
	expect_token_after(p, .Close_Paren, "parameter list")
	return list
}

fix_advance_to_next_stmt :: proc(p: ^Parser) {
	for {
		#partial switch t := p.curr_tok; t.kind {
		case .EOF, .Semicolon: return
		case .Module, .Import, .If, .For, .When, .Which, .Return, .Switch, .Using, .Break, .Continue, .Fallthrough, .Discard:
			if t.pos == p.fix_prev_pos && p.fix_count < PARSER_MAX_FIX_COUNT {
				p.fix_count += 1
				return
			}
			if t.pos.offset < p.fix_prev_pos.offset {
				p.fix_prev_pos = t.pos
				p.fix_count = 0
				return
			}
		}
		advance_token(p)
	}
}

is_literal_type :: proc(expr: ^Expr) -> bool {
	val := unparen_expr(expr)
	if val == nil {
		return false
	}
	#partial switch _ in val.derived_expr {
	case ^Bad_Expr,
	     ^Ident,
		 ^Selector_Expr,
		 ^Array_Type,
		 ^Struct_Type,
		 ^Enum_Type,
		 ^Bit_Set_Type,
		 ^Pipeline_Type,
		 ^Matrix_Type,
		 ^Call_Expr:
		return true
	}
	return false
}

is_semicolon_optional_for_node :: proc(p: ^Parser, node: ^Node) -> bool {
	if node == nil {
		return false
	}

	if .Optional_Semicolons in p.flags {
		return true
	}

	#partial switch n in node.derived {
	case ^Empty_Stmt, ^Block_Stmt:
		return true
	case ^If_Stmt, ^When_Stmt, ^Which_Stmt, ^For_Stmt, ^Range_Stmt, ^Switch_Stmt:
		return true
	case ^Helper_Type:
		return is_semicolon_optional_for_node(p, n.type)
	case ^Distinct_Type:
		return is_semicolon_optional_for_node(p, n.type)
	case ^Pointer_Type:
		return is_semicolon_optional_for_node(p, n.elem)
	case ^Multi_Pointer_Type:
		return is_semicolon_optional_for_node(p, n.elem)
	case ^Struct_Type, ^Enum_Type, ^Bit_Set_Type:
		return p.curr_proc == nil
	case ^Proc_Lit, ^Package_Decl, ^Import_Decl:
		return true
	case ^Value_Decl:
		if n.is_mutable {
			return false
		}
		if len(n.values) > 0 {
			return is_semicolon_optional_for_node(p, n.values[len(n.values)-1])
		}
	}

	return false
} 

expect_semicolon_newline_error :: proc(p: ^Parser, token: Token, s: ^Node) {
	if .Optional_Semicolons not_in p.flags && .Insert_Semicolons in p.lex.flags && token.text == "\n" {
		#partial switch token.kind {
		case .Close_Brace, .Close_Paren:
		case .Else: return
		}
		if is_semicolon_optional_for_node(p, s) {
			return
		}

		tok := token
		tok.pos.column -= 1
		parse_err(p, tok.pos, "expected ';', got newline")
	}
}

expect_semicolon :: proc(p: ^Parser, node: ^Node) -> bool {
	if allow_token(p, .Semicolon) {
		expect_semicolon_newline_error(p, p.prev_tok, node)
		return true
	}

	prev := p.prev_tok
	if prev.kind == .Semicolon {
		expect_semicolon_newline_error(p, p.prev_tok, node)
		return true
	}

	if p.curr_tok.kind == .EOF {
		return true
	}

	if node != nil {
		if .Insert_Semicolons in p.lex.flags {
			#partial switch p.curr_tok.kind {
			case .Close_Brace, .Close_Paren, .Else, .EOF:
				return true
			}

			if is_semicolon_optional_for_node(p, node) {
				return true
			}
		} else if prev.pos.line != p.curr_tok.pos.line {
			if is_semicolon_optional_for_node(p, node) {
				return true
			}
		} else {
			#partial switch p.curr_tok.kind {
			case .Close_Brace, .Close_Paren, .Else:
				return true
			case .EOF:
				if is_semicolon_optional_for_node(p, node) {
					return true
				}
			}
		}
	} else {
		if p.curr_tok.kind == .EOF {
			return true
		}
	}

	parse_err(p, prev.pos, "expected ';', got %s", token_to_string(p.curr_tok))
	fix_advance_to_next_stmt(p)
	return false
}

new_blank_ident :: proc(p: ^Parser, pos: Token_Pos) -> ^Ident {
	tok: Token
	tok.pos = pos
	i := ast_new(Ident, pos, token_end_pos(tok))
	i.name = "_"
	return i
}

parse_ident :: proc(p: ^Parser) -> ^Ident {
	tok := p.curr_tok
	pos := tok.pos
	name := "_"
	if tok.kind == .Ident {
		name = tok.text
		advance_token(p)
	} else {
		expect_token(p, .Ident)
	}
	i := ast_new(Ident, pos, token_end_pos(tok))
	i.name = name
	return i
}

parse_unary_expr :: proc(p: ^Parser, lhs: bool) -> ^Expr {
	#partial switch p.curr_tok.kind {
	case .Cast: // TODO(Dragos): allow cast to be an auto_cast too i.e. (cast n)
		tok := advance_token(p)
		open := expect_token(p, .Open_Paren)
		type := parse_type(p)
		close := expect_token(p, .Close_Paren)
		expr := parse_unary_expr(p, lhs)

		tc := ast_new(Type_Cast, tok.pos, expr)
		tc.tok = tok
		tc.open = open.pos
		tc.type = type
		tc.close = close.pos
		tc.expr = expr
		return tc

	case .Auto_Cast:
		op := advance_token(p)
		expr := parse_unary_expr(p, lhs)
		ac := ast_new(Auto_Cast, op.pos, expr)
		ac.op = op
		ac.expr = expr
		return ac
	
	case .Add, .Sub, .Not, .Xor, .And:
		op := advance_token(p)
		expr := parse_unary_expr(p, lhs)

		ue := ast_new(Unary_Expr, op.pos, expr)
		ue.op = op
		ue.expr = expr
		return ue

	case .Increment, .Decrement:
		op := advance_token(p)
		parse_err(p, op.pos, "unary '%s' operator is not supported", op.text)
		expr := parse_unary_expr(p, lhs)

		ue := ast_new(Unary_Expr, op.pos, expr)
		ue.op = op
		ue.expr = expr
		return ue

	case .Period:
		op := advance_token(p)
		// Incomplete `.` / `.` before newline — empty implicit selector for IDE recovery.
		if p.curr_tok.kind != .Ident || p.curr_tok.pos.line > op.pos.line {
			parse_warn(p, op.pos, "expected a selector")
			return empty_implicit_selector_expr(op)
		}
		field := parse_ident(p)
		ise := ast_new(Implicit_Selector_Expr, op.pos, field)
		ise.field = field
		return ise
	}
	return parse_atom_expr(p, parse_operand(p, lhs), lhs)
}

parse_binary_expr :: proc(p: ^Parser, lhs: bool, prec_in: int) -> ^Expr {
	start_pos := p.curr_tok.pos
	expr := parse_unary_expr(p, lhs)

	if expr == nil {
		return ast_new(Bad_Expr, start_pos, token_end_pos(p.prev_tok))
	}

	for prec := token_precedence(p, p.curr_tok.kind); prec >= prec_in; prec -= 1 {
		loop: for {
			op := p.curr_tok
			op_prec := token_precedence(p, op.kind)
			if op_prec != prec {
				break loop
			}

			#partial switch op.kind {
			case .If, .When:
				if p.prev_tok.pos.line < op.pos.line {
					break loop
				}
			}

			expect_operator(p)

			#partial switch op.kind {
			case .Question:
				cond := expr
				x := parse_expr(p, lhs)
				colon := expect_token(p, .Colon)
				y := parse_expr(p, lhs)
				te := ast_new(Ternary_If_Expr, expr.pos, token_end_pos(p.prev_tok))
				te.cond = cond
				te.op1 = op
				te.x = x
				te.op2 = colon
				te.y = y

				expr = te

			case .If:
				x := expr
				cond := parse_expr(p, lhs)
				else_tok := expect_token(p, .Else)
				y := parse_expr(p, lhs)
				te := ast_new(Ternary_If_Expr, expr.pos, token_end_pos(p.prev_tok))
				te.x = x
				te.op1 = op
				te.cond = cond
				te.op2 = else_tok
				te.y = y

				expr = te

			case .When:
				x := expr
				cond := parse_expr(p, lhs)
				skip_possible_newline(p)
				else_tok := expect_token(p, .Else)
				y := parse_expr(p, lhs)
				te := ast_new(Ternary_When_Expr, expr.pos, token_end_pos(p.prev_tok))
				te.x = x
				te.op1 = op
				te.cond = cond
				te.op2 = else_tok
				te.y = y

				expr = te

			case:
				right := parse_binary_expr(p, false, prec+1)
				if right == nil {
					parse_err(p, op.pos, "expected expression on the right-hand side of the binary operator")
				}
				be := ast_new(Binary_Expr, expr.pos, token_end_pos(p.prev_tok))
				be.left = expr
				be.op = op
				be.right = right

				expr = be
			}
		}
	}

	return expr
}

parse_expr :: proc(p: ^Parser, lhs: bool) -> ^Expr {
	return parse_binary_expr(p, lhs, 0+1)
}

parse_expr_list :: proc(p: ^Parser, lhs: bool) -> []^Expr {
	list: [dynamic]^Expr
	for {
		expr := parse_expr(p, lhs)
		append(&list, expr)
		if p.curr_tok.kind != .Comma || p.curr_tok.kind == .EOF {
			break
		}
		advance_token(p)
	}
	return list[:]
}

parse_lhs_expr_list :: proc(p: ^Parser) -> []^Expr {
	return parse_expr_list(p, true)
}

parse_rhs_expr_list :: proc(p: ^Parser) -> []^Expr {
	return parse_expr_list(p, false)
}

peek_token :: proc(p: ^Parser, lookahead := 0) -> Token {
	prev_parser := p^
	p.peeking = true
	defer {
		p^ = prev_parser
		p.peeking = false
	}

	p.lex.err = nil
	for i := 0; i <= lookahead; i += 1 {
		advance_token(p)
	}
	return p.curr_tok
}
 
parse_simple_stmt :: proc(p: ^Parser, flags: Stmt_Allow_Flags) -> ^Stmt {
	start_tok := p.curr_tok
	docs := p.lead_comment

	lhs := parse_lhs_expr_list(p)
	op := p.curr_tok
	switch {
	case token_is_assignment_operator(op.kind):
		advance_token(p)
		rhs := parse_rhs_expr_list(p)
		if len(rhs) == 0 {
			parse_err(p, p.curr_tok.pos, "no right-hand side in assignment statement")
			return ast_new(Bad_Stmt, start_tok.pos, token_end_pos(p.curr_tok))
		}
		stmt := ast_new(Assign_Stmt, lhs[0].pos, rhs[len(rhs)-1])
		stmt.lhs = lhs
		stmt.op = op
		stmt.rhs = rhs
		return stmt
	
	case op.kind == .In:
		if .In in flags {
			allow_token(p, .In)
			prev_allow_range := p.allow_range
			p.allow_range = true
			expr := parse_expr(p, false)
			p.allow_range = prev_allow_range
			rhs := make([]^Expr, 1)
			rhs[0] = expr
			
			stmt := ast_new(Assign_Stmt, lhs[0].pos, rhs[len(rhs)-1])
			stmt.lhs = lhs
			stmt.op = op
			stmt.rhs = rhs
			return stmt
		}
	
	case op.kind == .Colon:
		expect_token_after(p, .Colon, "identifier list")
		if .Label in flags && len(lhs) == 1 {
			is_partial := false
			is_reverse := false
			
			partial_token: Token
			if p.curr_tok.kind == .Hash {
				name := peek_token(p)
				if name.kind == .Ident && name.text == "partial" && peek_token(p, 1).kind == .Switch {
					partial_token = expect_token(p, .Hash)
					expect_token(p, .Ident)
					is_partial = true
				} else if name.kind == .Ident && name.text == "reverse" && peek_token(p, 1).kind == .For {
					partial_token = expect_token(p, .Hash)
					expect_token(p, .Ident)
					is_reverse = true
				}
			}

			#partial switch p.curr_tok.kind {
			case .Open_Brace, .If, .For, .Switch:
				label := lhs[0]
				stmt := parse_stmt(p)

				if stmt != nil {
					#partial switch n in stmt.derived_stmt {
					case ^Block_Stmt:  n.label = label
					case ^If_Stmt:     n.label = label
					case ^For_Stmt:    n.label = label
					case ^Switch_Stmt: n.label = label
					case ^Range_Stmt:  n.label = label
					}

					if is_partial {
						#partial switch n in stmt.derived_stmt {
						case ^Switch_Stmt: n.partial = true
						case ^Which_Stmt:  n.partial = true
						case: parse_err(p, partial_token.pos, "incorrect use of directive, use '%s: #partial switch' or '%s: #partial which'", partial_token.text, partial_token.text)
						}
					}
					if is_reverse {
						#partial switch n in stmt.derived_stmt {
						case ^Range_Stmt: n.reverse = true
						case: parse_err(p, partial_token.pos, "iincorrect use of directive, use '%s: #reverse for'", partial_token.text)
						}
					}
				}

				return stmt
			}
		}

		return parse_value_decl(p, lhs, docs)
	}

	if len(lhs) > 1 {
		parse_err(p, op.pos, "expected 1 expression, got %d", len(lhs))
		return ast_new(Bad_Stmt, start_tok.pos, token_end_pos(p.curr_tok))
	}

	// TODO(Dragos): should we allow increments/decrements?
	#partial switch op.kind {
	case .Increment, .Decrement:
		advance_token(p)
		parse_err(p, op.pos, "postfix '%s' statement is not supported", op.text)
	}

	es := ast_new(Expr_Stmt, lhs[0].pos, lhs[0])
	es.expr = lhs[0]
	return es
}

parse_value_decl :: proc(p: ^Parser, names: []^Expr, docs: ^Comment_Group) -> ^Decl {
	is_mutable := true
	
	values: []^Expr
	// While typing `name:` the next statement is often `other := …` / `other :: …`.
	// Without a semicolon after `:`, that identifier would be swallowed as a type and
	// `:=` misread as a typed-constant separator (`name: other := …`), which is not
	// valid MISL/Odin and breaks the following statement. Leave the Ident for the
	// next stmt when it clearly starts `:=` / `::`.
	type: ^Expr
	if p.curr_tok.kind == .Ident {
		after := peek_token(p, 0)
		if after.kind == .Colon {
			after2 := peek_token(p, 1)
			if after2.kind == .Eq || after2.kind == .Colon {
				type = nil
			} else {
				type = parse_type_or_ident(p)
			}
		} else {
			type = parse_type_or_ident(p)
		}
	} else {
		type = parse_type_or_ident(p)
	}

	#partial switch p.curr_tok.kind {
	case .Eq, .Colon: // = / :  (typed init / typed const); not `:=` (see above)
		sep := advance_token(p)
		is_mutable = sep.kind != .Colon

		values = parse_rhs_expr_list(p)
		if len(values) > len(names) {
			parse_err(p, p.curr_tok.pos, "too many values on the right hand side of the declaration")
		} else if len(values) < len(names) && !is_mutable {
			parse_err(p, p.curr_tok.pos, "all constant declarations must be defined")
		} else if len(values) == 0 {
			parse_err(p, p.curr_tok.pos, "expected an expression for this declaration")
		}
	}

	if is_mutable {
		if type == nil && len(values) == 0 {
			parse_err(p, p.curr_tok.pos, "missing variable type or initialization")
			return ast_new(Bad_Decl, names[0].pos, token_end_pos(p.curr_tok))
		}
	}

	end := p.prev_tok

	if p.expr_level >= 0 {
		end: ^Expr
		if !is_mutable && len(values) > 0 {
			end = values[len(values)-1]
		}
		if p.curr_tok.kind == .Close_Brace && p.curr_tok.pos.line == p.prev_tok.pos.line {
			
		} else {
			expect_semicolon(p, end)
		}
	}

	if p.curr_proc == nil {
		if len(values) > 0 && len(names) != len(values) {
			parse_err(p, values[0].pos, "expected %d expressions on the right-hand side, got %d", len(names), len(values))
		}
	}

	decl := ast_new(Value_Decl, names[0].pos, token_end_pos(end))
	decl.docs = docs
	decl.names = names
	decl.type = type
	decl.values = values
	decl.is_mutable = is_mutable
	return decl
}

parse_import_decl :: proc(p: ^Parser, kind: Import_Decl_Kind = .Standard) -> ^Import_Decl {
	docs := p.lead_comment
	tok := expect_token(p, .Import)

	import_name: Token
	is_using := kind != .Standard

	#partial switch p.curr_tok.kind {
	case .Ident:
		import_name = advance_token(p)
	case:
		import_name.pos = p.curr_tok.pos
	}

	path := expect_token_after(p, .String, "import")

	decl := ast_new(Import_Decl, tok.pos, token_end_pos(path))
	decl.docs = docs
	decl.is_using = is_using
	decl.import_tok = tok
	decl.name = import_name
	decl.relpath = path
	decl.fullpath = path.text

	if is_using {
		parse_err(p, decl.pos, "'using import' is not supported")
	}
	if !p.allow_import || p.curr_proc != nil {
		parse_err(p, decl.pos, "import declarations must be at file scope, not inside when/which or a nested block")
	} else {
		append(&p.module.imports, decl)
	}
	expect_semicolon(p, decl)
	decl.comment = p.line_comment
	return decl
}

parse_if_stmt :: proc(p: ^Parser) -> ^If_Stmt {
	tok := expect_token(p, .If)
	
	init: ^Stmt
	cond: ^Expr
	body: ^Stmt
	else_stmt: ^Stmt

	prev_level := p.expr_level
	p.expr_level = -1
	prev_allow_in_expr := p.allow_in_expr
	p.allow_in_expr = true
	if allow_token(p, .Semicolon) {
		cond = parse_expr(p, false)
	} else {
		init = parse_simple_stmt(p, nil)
		if parse_control_statement_semicolon_operator(p) {
			cond = parse_expr(p, false)
		} else {
			cond = convert_stmt_to_expr(p, init, "boolean expression")
			init = nil
		}
	}

	p.expr_level = prev_level
	p.allow_in_expr = prev_allow_in_expr

	if cond == nil {
		parse_err(p, p.curr_tok.pos, "expected a condition for if statement")
	}
	if allow_token(p, .Do) {
		body = convert_stmt_to_body(p, parse_stmt(p))
		if cond.pos.line != body.pos.line {
			parse_err(p, body.pos, "the body of a 'do' must be on the same line as the if condition")
		}
	} else {
		body = parse_block_stmt(p, false)
	}

	else_tok := p.curr_tok.pos
	
	skip_possible_newline_for_literal(p)
	if p.curr_tok.kind == .Else {
		else_tok := expect_token(p, .Else)
		#partial switch p.curr_tok.kind {
		case .If: else_stmt = parse_if_stmt(p)
		case .Open_Brace: else_stmt = parse_block_stmt(p, false)
		case .Do:
			expect_token(p, .Do)
			else_stmt = convert_stmt_to_body(p, parse_stmt(p))
			if else_tok.pos.line != else_stmt.pos.line {
				parse_err(p, body.pos, "the body of a 'do' must be on the same line as 'else'")
			}
		case:
			parse_err(p, p.curr_tok.pos, "expected if statement block statement")
			else_stmt = ast_new(Bad_Stmt, p.curr_tok.pos, token_end_pos(p.curr_tok))
		}
	}

	end: Token_Pos
	if body != nil {
		end = body.end
	}
	if else_stmt != nil {
		end = else_stmt.end
	}

	ifs := ast_new(If_Stmt, tok.pos, end)
	ifs.if_pos = tok.pos
	ifs.init = init
	ifs.cond = cond
	ifs.body = body
	ifs.else_stmt = else_stmt
	ifs.else_pos = else_tok
	return ifs
}

parse_when_stmt :: proc(p: ^Parser) -> ^When_Stmt {
	tok := expect_token(p, .When)
	prev_import := p.allow_import
	p.allow_import = false
	defer p.allow_import = prev_import
	
	cond: ^Expr
	body: ^Stmt
	else_stmt: ^Stmt

	prev_level := p.expr_level
	p.expr_level = -1
	prev_allow_in_expr := p.allow_in_expr
	p.allow_in_expr = true
	cond = parse_expr(p, false)
	p.allow_in_expr = prev_allow_in_expr
	p.expr_level = prev_level

	if cond == nil {
		parse_err(p, p.curr_tok.pos, "expected a condition for when statement")
	}
	if allow_token(p, .Do) {
		body = convert_stmt_to_body(p, parse_stmt(p))
		if cond.pos.line != body.pos.line {
			parse_err(p, body.pos, "the body of a 'do' must be on the same line as when statement")
		}
	} else {
		body = parse_block_stmt(p, true)
	}

	skip_possible_newline_for_literal(p)
	if p.curr_tok.kind == .Else {
		else_tok := expect_token(p, .Else)
		#partial switch p.curr_tok.kind {
		case .When:
			else_stmt = parse_when_stmt(p)
		case .Open_Brace:
			else_stmt = parse_block_stmt(p, true)
		case .Do:
			expect_token(p, .Do)
			else_stmt = convert_stmt_to_body(p, parse_stmt(p))
			if else_tok.pos.line != else_stmt.pos.line {
				parse_err(p, else_stmt.pos, "the body of a 'do' must be on the same as 'else'")
			}
		case:
			parse_err(p, p.curr_tok.pos, "expected when statement block statement")
			else_stmt = ast_new(Bad_Stmt, p.curr_tok.pos, token_end_pos(p.curr_tok))
		}
	}

	end := body.end
	if else_stmt != nil {
		end = else_stmt.end
	}

	when_stmt := ast_new(When_Stmt, tok.pos, end)
	when_stmt.when_pos = tok.pos
	when_stmt.cond = cond
	when_stmt.body = body
	when_stmt.else_stmt = else_stmt
	return when_stmt
}

parse_which_stmt :: proc(p: ^Parser) -> ^Which_Stmt {
	tok := expect_token(p, .Which)
	prev_import := p.allow_import
	p.allow_import = false
	defer p.allow_import = prev_import

	cond: ^Expr
	if p.curr_tok.kind != .Open_Brace {
		prev_level := p.expr_level
		p.expr_level = -1
		prev_allow_in_expr := p.allow_in_expr
		p.allow_in_expr = true
		cond = parse_expr(p, false)
		p.allow_in_expr = prev_allow_in_expr
		p.expr_level = prev_level
	}

	skip_possible_newline(p)
	open := expect_token(p, .Open_Brace)

	if p.curr_tok.kind != .Case {
		parse_err(p, p.curr_tok.pos, "'which' requires 'case' arms; use 'when' for a boolean condition")
		for p.curr_tok.kind != .Close_Brace && p.curr_tok.kind != .EOF && p.curr_tok.kind != .Case {
			_ = parse_stmt(p)
		}
	}

	clauses: [dynamic]^Stmt
	for p.curr_tok.kind == .Case {
		append(&clauses, parse_case_clause(p))
	}

	close := expect_token(p, .Close_Brace)
	body := ast_new(Block_Stmt, open.pos, token_end_pos(close))
	body.open = open.pos
	body.close = close.pos
	body.stmts = clauses[:]

	ws := ast_new(Which_Stmt, tok.pos, body)
	ws.which_pos = tok.pos
	ws.cond = cond
	ws.body = body
	return ws
}

parse_switch_stmt :: proc(p: ^Parser) -> ^Switch_Stmt {
	tok := expect_token(p, .Switch)

	init, tag: ^Stmt
	clauses: [dynamic]^Stmt

	if p.curr_tok.kind != .Open_Brace {
		prev_level := p.expr_level
		defer p.expr_level = prev_level
		p.expr_level = -1

		tag = parse_simple_stmt(p, {.In}) // TODO(Dragos): figure out if .In is required here
		
		if parse_control_statement_semicolon_operator(p) {
			init = tag
			tag = nil
			if p.curr_tok.kind != .Open_Brace {
				tag = parse_simple_stmt(p, nil)
			}
		}
	}

	skip_possible_newline(p)
	open := expect_token(p, .Open_Brace)

	for p.curr_tok.kind == .Case {
		clause := parse_case_clause(p)
		append(&clauses, clause)
	}

	close := expect_token(p, .Close_Brace)

	body := ast_new(Block_Stmt, open.pos, token_end_pos(close))
	body.stmts = clauses[:]

	cond := convert_stmt_to_expr(p, tag, "switch expression")
	ts := ast_new(Switch_Stmt, tok.pos, body)
	ts.init = init
	ts.cond = cond
	ts.body = body
	ts.switch_pos = tok.pos

	return ts
}

parse_case_clause :: proc(p: ^Parser) -> ^Case_Clause {
	tok := expect_token(p, .Case)

	list: []^Expr

	if p.curr_tok.kind != .Colon {
		prev_allow_range, prev_allow_in_expr := p.allow_range, p.allow_in_expr
		defer p.allow_range, p.allow_in_expr = prev_allow_range, prev_allow_in_expr
		p.allow_range, p.allow_in_expr = true, true

		list = parse_rhs_expr_list(p)
	}

	terminator := expect_token(p, .Colon)
	
	stmts := parse_stmt_list(p)
	
	cc := ast_new(Case_Clause, tok.pos, token_end_pos(p.prev_tok))
	cc.list = list
	cc.terminator = terminator
	cc.body = stmts
	cc.case_pos = tok.pos
	return cc
}

parse_for_stmt :: proc(p: ^Parser) -> ^Stmt {
	if p.curr_proc == nil {
		parse_err(p, p.curr_tok.pos, "you cannot use a for statement in the module scope")
	}

	tok := expect_token(p, .For)

	init, cond, post, body: ^Stmt
	is_range := false

	if p.curr_tok.kind != .Open_Brace && p.curr_tok.kind != .Do {
		prev_level := p.expr_level
		defer p.expr_level = prev_level
		p.expr_level = -1

		if p.curr_tok.kind == .In {
			in_tok := expect_token(p, .In)
			rhs: ^Expr

			prev_allow_range := p.allow_range
			p.allow_range = true
			rhs = parse_expr(p, false)
			p.allow_range = prev_allow_range

			if allow_token(p, .Do) {
				body = convert_stmt_to_body(p, parse_stmt(p))
				if tok.pos.line != body.pos.line {
					parse_err(p, body.pos, "the body of a 'do' must be on the same line as the 'for' token")
				}
			} else {
				body = parse_body(p)
			}

			range_stmt := ast_new(Range_Stmt, tok.pos, body)
			range_stmt.for_pos = tok.pos
			range_stmt.in_pos = in_tok.pos
			range_stmt.expr = rhs
			range_stmt.body = body
			return range_stmt
		}

		if p.curr_tok.kind != .Semicolon {
			cond = parse_simple_stmt(p, {.In})
			if as, ok := cond.derived.(^Assign_Stmt); ok && as.op.kind == .In {
				is_range = true
			}
		}

		if !is_range && parse_control_statement_semicolon_operator(p) {
			init = cond
			cond = nil

			if p.curr_tok.kind == .Open_Brace || p.curr_tok.kind == .Do {
				parse_err(p, p.curr_tok.pos, "expected ';', followed by a condition expression and post statement, got '%s'", tokens[p.curr_tok.kind])
			} else {
				if p.curr_tok.kind != .Semicolon {
					cond = parse_simple_stmt(p, nil)
				}

				ALLOW_EMPTY_POST_SEMICOLON :: true
				when !ALLOW_EMPTY_POST_SEMICOLON {
					if allow_token(p, .Semicolon) {
						post = parse_simple_stmt(p, nil)
					}
				} else {
					if p.curr_tok.kind == .Semicolon {
						expect_semicolon(p, nil)
						if p.curr_tok.kind != .Open_Brace && p.curr_tok.kind != .Do { // this if stmt allows empty post statement, so semicolon followed by brace `for init; cond;{}`
							post = parse_simple_stmt(p, nil)
						}
					}
				}
				
			}
		}
	}

	if allow_token(p, .Do) {
		body = convert_stmt_to_body(p, parse_stmt(p))
		if tok.pos.line != body.pos.line {
			parse_err(p, body.pos, "the body of a 'do' must be on the same line as the 'for' token")
		}
	} else {
		allow_token(p, .Semicolon)
		body = parse_body(p)
	}

	if is_range {
		assign_stmt := cond.derived.(^Assign_Stmt)
		vals := assign_stmt.lhs[:]

		rhs: ^Expr
		if len(assign_stmt.rhs) > 0 {
			rhs = assign_stmt.rhs[0]
		}

		range_stmt := ast_new(Range_Stmt, tok.pos, body)
		range_stmt.for_pos = tok.pos
		range_stmt.vals = vals
		range_stmt.in_pos = assign_stmt.op.pos
		range_stmt.expr = rhs
		range_stmt.body = body
		return range_stmt
	}

	cond_expr := convert_stmt_to_expr(p, cond, "boolean expression")
	for_stmt := ast_new(For_Stmt, tok.pos, body)
	for_stmt.for_pos = tok.pos
	for_stmt.init = init
	for_stmt.cond = cond_expr
	for_stmt.post = post
	for_stmt.body = body
	return for_stmt
}

skip_possible_newline :: proc(p: ^Parser) -> bool {
	if token_is_newline(p.curr_tok) {
		advance_token(p)
		return true
	}
	return false
}

skip_possible_newline_for_literal :: proc(p: ^Parser) -> bool {
	if .Optional_Semicolons not_in p.flags {
		return false
	}

	curr_pos := p.curr_tok.pos
	if token_is_newline(p.curr_tok) {
		next := peek_token(p)
		if curr_pos.line+1 >= next.pos.line {
			#partial switch next.kind {
			case .Open_Brace, .Else, .Where:
				advance_token(p)
				return true
			}
		}
	}
	return false
}

parse_block_stmt :: proc(p: ^Parser, is_when: bool) -> ^Stmt {
	skip_possible_newline_for_literal(p)
	if !is_when && p.curr_proc == nil {
		parse_err(p, p.curr_tok.pos, "you cannot use a block statement in the module scope")
	}
	return parse_body(p)
}

parse_body :: proc(p: ^Parser) -> ^Block_Stmt {
	prev_expr_level := p.expr_level
	prev_import := p.allow_import
	defer {
		p.expr_level = prev_expr_level
		p.allow_import = prev_import
	}
	
	p.expr_level = 0
	p.allow_import = false
	open := expect_token(p, .Open_Brace)
	stmts := parse_stmt_list(p)
	close := expect_token(p, .Close_Brace)

	bs := ast_new(Block_Stmt, open.pos, token_end_pos(close))
	bs.open = open.pos
	bs.stmts = stmts
	bs.close = close.pos
	return bs
}

convert_stmt_to_expr :: proc(p: ^Parser, stmt: ^Stmt, kind: string) -> ^Expr {
	if stmt == nil {
		return nil
	}
	if es, ok := stmt.derived.(^Expr_Stmt); ok {
		return es.expr
	}
	parse_err(p, stmt.pos, "expected %s, found a simple statement", kind)
	return ast_new(Bad_Expr, p.curr_tok.pos, token_end_pos(p.curr_tok))
}

convert_stmt_to_body :: proc(p: ^Parser, stmt: ^Stmt) -> ^Stmt {
	#partial switch s in stmt.derived_stmt {
	case ^Block_Stmt:
		parse_err(p, stmt.pos, "expected a normal statement rather than a block statement")
		return stmt
	case ^Empty_Stmt:
		parse_err(p, stmt.pos, "expected a non-empty statement")
	}

	bs := ast_new(Block_Stmt, stmt.pos, stmt)
	bs.open = stmt.pos
	bs.stmts = make([]^Stmt, 1)
	bs.stmts[0] = stmt
	bs.close = stmt.end
	bs.uses_do = true
	return bs
}

new_ast_field :: proc(names: []^Expr, type: ^Expr, default_value: ^Expr) -> ^Field {
	pos, end: Token_Pos

	if len(names) > 0 {
		pos = names[0].pos
		if default_value != nil {
			end = default_value.end
		} else if type != nil {
			end = type.end
		} else {
			end = names[len(names)-1].pos
		}
	} else {
		if type != nil {
			pos = type.pos
		} else if default_value != nil {
			pos = default_value.pos
		}

		if default_value != nil {
			end = default_value.end
		} else if type != nil {
			end = type.end
		}
	}

	field := ast_new(Field, pos, end)
	field.names = names
	field.type = type
	field.default_value = default_value
	return field
}

parse_control_statement_semicolon_operator :: proc(p: ^Parser) -> bool {
	tok := peek_token(p)
	if tok.kind != .Open_Brace {
		return allow_token(p, .Semicolon)
	}
	if p.curr_tok.text == ";" {
		return allow_token(p, .Semicolon)
	}
	return false
}

parse_stmt :: proc(p: ^Parser) -> ^Stmt {
	#partial switch p.curr_tok.kind {
	case .Proc, 
		 .Ident,
		 .Integer, .Float, .Imaginary,
		 .Rune, .String,
		 .Open_Paren,
		 .Pointer,
		 .Add, .Sub, .Xor, .Not, .And:
		s := parse_simple_stmt(p, {.Label}) 
		expect_semicolon(p, s)
		return s

	case .Import: return parse_import_decl(p)
	case .If: return parse_if_stmt(p)
	case .When: return parse_when_stmt(p)
	case .Which: return parse_which_stmt(p)
	case .For: return parse_for_stmt(p)
	case .Switch: return parse_switch_stmt(p)

	case .Return:
		tok := advance_token(p)
		
		if p.expr_level > 0 {
			parse_err(p, tok.pos, "cannot use a return statement within an expression")
		}

		results: [dynamic]^Expr
		for p.curr_tok.kind != .Semicolon && p.curr_tok.kind != .Close_Brace {
			result := parse_expr(p, false)
			append(&results, result)
			if p.curr_tok.kind != .Comma || p.curr_tok.kind == .EOF {
				break
			}
			advance_token(p)
		}

		end := token_end_pos(tok)
		if len(results) > 0 {
			end = results[len(results)-1].end
		}

		rs := ast_new(Return_Stmt, tok.pos, end)
		rs.results = results[:]
		expect_semicolon(p, rs)
		return rs
	
	case .Break, .Continue, .Fallthrough, .Discard:
		tok := advance_token(p)
		label: ^Ident
		if tok.kind != .Fallthrough && tok.kind != .Discard && p.curr_tok.kind == .Ident {
			label = parse_ident(p)
		}
		s := ast_new(Branch_Stmt, tok.pos, label)
		s.tok = tok
		s.label = label
		expect_semicolon(p, s)
		return s

	case .Using:
		docs := p.lead_comment
		tok := expect_token(p, .Using)

		if p.curr_tok.kind == .Import {
			return parse_import_decl(p, Import_Decl_Kind.Using)
		}

		list := parse_lhs_expr_list(p)
		if len(list) == 0 {
			parse_err(p, tok.pos, "illegal use of 'using' statement")
			expect_semicolon(p, nil)
			return ast_new(Bad_Stmt, tok.pos, token_end_pos(p.prev_tok))
		}

		if p.curr_tok.kind != .Colon {
			end := list[len(list)-1]
			expect_semicolon(p, end)
			us := ast_new(Using_Stmt, tok.pos, end)
			us.list = list
			return us
		}
		expect_token_after(p, .Colon, "identifier list")
		decl := parse_value_decl(p, list, docs)
		if decl != nil {
			#partial switch d in decl.derived_stmt {
			case ^Value_Decl:
				d.is_using = true
				return decl
			}
		}

		parse_err(p, tok.pos, "illegal use of 'using' statement")
		return ast_new(Bad_Stmt, tok.pos, token_end_pos(p.prev_tok))

	case .At:
		docs := p.lead_comment
		tok := advance_token(p)
		return parse_attribute(p, tok, .Open_Paren, .Close_Paren, docs)
	
	case .Hash: // TODO(Dragos): allow this in more situations, and possibly allow #ident(N)
		tok := expect_token(p, .Hash)
		tag := expect_token(p, .Ident)
		name := tag.text

		// TODO(Dragos): figure out what tags we allow here
		switch name {
		case "partial":
			stmt := parse_stmt(p)
			#partial switch s in stmt.derived_stmt {
			case ^Switch_Stmt: s.partial = true
			case ^Which_Stmt:  s.partial = true
			case: parse_err(p, stmt.pos, "#partial can only be applied to switch or which statements")
			}
			return stmt
		case "bounds_check":
			return parse_check_directive_for_statement(p, parse_stmt(p), tag, .Bounds_Check)
		case "no_bounds_check":
			return parse_check_directive_for_statement(p, parse_stmt(p), tag, .No_Bounds_Check)
		case "assert", "panic":
			bd := ast_new(Basic_Directive, tok.pos, token_end_pos(tag))
			bd.tok = tok
			bd.name = name
			ce := parse_call_expr(p, bd)
			es := ast_new(Expr_Stmt, ce.pos, ce)
			es.expr = ce
			return es

		case "inline", "no_inline":
			expr := parse_inlining_operand(p, true, tag)
			es := ast_new(Expr_Stmt, expr.pos, expr)
			es.expr = expr
			return es

		case "reverse":
			stmt := parse_stmt(p)
			if range, is_range := stmt.derived.(^Range_Stmt); is_range {
				if range.reverse {
					parse_err(p, range.pos, "#reverse already applied to a 'for in' statement")
				} else {
					range.reverse = true
				}
			} else {
				parse_err(p, stmt.pos, "#reverse can only be applied to a 'for in' statement")
			}
			return stmt
		
		case:
			parse_err(p, tag.pos, "unknown directive '#%s'", name)
			stmt := parse_stmt(p)
			return stmt
		}

	case .File_Tag:
		parse_err(p, p.curr_tok.pos, "file tags are only allowed at the start of the file")
		advance_token(p)
		return parse_stmt(p)

	case .Open_Brace:
		return parse_block_stmt(p, false)
	
	case .Semicolon:
		tok := advance_token(p)
		s := ast_new(Empty_Stmt, tok.pos, token_end_pos(tok))
		return s
	}

	#partial switch p.curr_tok.kind {
	case .Else:
		token := expect_token(p, .Else)
		parse_err(p, token.pos, "'else' unattached to an 'if' statement")
		#partial switch p.curr_tok.kind {
		case .If: return parse_if_stmt(p)
		case .When: return parse_when_stmt(p)
		case .Open_Brace: return parse_block_stmt(p, false)
		case .Do:
			expect_token(p, .Do)
			return convert_stmt_to_body(p, parse_stmt(p))
		case:
			fix_advance_to_next_stmt(p)
			return ast_new(Bad_Stmt, token.pos, token_end_pos(p.curr_tok))
		}
	}

	tok := advance_token(p)
	parse_err(p, tok.pos, "expected a statement, got %s", token_to_string(tok))
	fix_advance_to_next_stmt(p)
	s := ast_new(Bad_Stmt, tok.pos, token_end_pos(tok))
	return s
}

parse_inlining_operand :: proc(p: ^Parser, lhs: bool, tok: Token) -> ^Expr {
	parse_err(p, tok.pos, "'#%s' is not supported", tok.text)
	// Recover by parsing the following operand so the rest of the file can check.
	expr := parse_expr(p, lhs)
	if expr == nil {
		return ast_new(Bad_Expr, tok.pos, token_end_pos(tok))
	}
	return expr
}

parse_call_expr :: proc(p: ^Parser, operand: ^Expr) -> ^Expr {
	args: [dynamic]^Expr
	ellipsis: Token
	
	p.expr_level += 1
	open := expect_token(p, .Open_Paren)

	seen_ellipsis := false
	for p.curr_tok.kind != .Close_Paren && p.curr_tok.kind != .EOF {
		if p.curr_tok.kind == .Comma {
			parse_err(p, p.curr_tok.pos, "expected an expression, got ','")
		} else if p.curr_tok.kind == .Eq {
			parse_err(p, p.curr_tok.pos, "expected an expression, got '='")
		}

		prefix_ellipsis := false
		if p.curr_tok.kind == .Ellipsis {
			prefix_ellipsis = true
			ellipsis = expect_token(p, .Ellipsis)
		}

		arg := parse_expr(p, false)
		if p.curr_tok.kind == .Eq {
			eq := expect_token(p, .Eq)
			if prefix_ellipsis {
				parse_err(p, ellipsis.pos, "'..' must be applied to value rather than a field name")
			}

			value := parse_value(p)
			fv := ast_new(Field_Value, arg.pos, value)
			fv.field = arg
			fv.sep = eq.pos
			fv.value = value

			arg = fv
		} else if seen_ellipsis {
			parse_err(p, arg.pos, "positional arguments are not allowed after '..'")
		}

		append(&args, arg)

		if ellipsis.pos.line != 0 {
			seen_ellipsis = true
		}

		allow_token(p, .Comma) or_break
	}

	close := expect_closing_token_of_field_list(p, .Close_Paren, "argument list")
	p.expr_level -= 1

	ce := ast_new(Call_Expr, operand.pos, token_end_pos(close))
	ce.expr = operand
	ce.open = open.pos
	ce.args = args[:]
	ce.ellipsis = ellipsis
	ce.close = close.pos

	// TODO(Dragos): probably not useful to have selector calls
	o := unparen_expr(operand)
	if se, ok := o.derived.(^Selector_Expr); ok && se.op.kind == .Arrow_Right {
		sce := ast_new(Selector_Call_Expr, ce.pos, ce)
		sce.expr = o
		sce.call = ce
		return sce
	}

	return ce
}

empty_selector_expr :: proc(tok: Token, operand: ^Expr) -> ^Selector_Expr {
	field := ast_new(Ident, tok.pos, token_end_pos(tok))
	field.name = ""

	sel := ast_new(Selector_Expr, operand.pos, field)
	sel.expr = operand
	sel.op = tok
	sel.field = field

	return sel
}

empty_implicit_selector_expr :: proc(tok: Token) -> ^Implicit_Selector_Expr {
	field := ast_new(Ident, tok.pos, token_end_pos(tok))
	field.name = ""
	ise := ast_new(Implicit_Selector_Expr, tok.pos, field)
	ise.field = field
	return ise
}

unparen_expr :: proc(expr: ^Expr) -> (val: ^Expr) {
	if expr == nil {
		return nil
	}
	val = expr
	for {
		e := val.derived.(^Paren_Expr) or_break
		if e.expr == nil {
			break
		}
		val = e.expr
	}
	return val
}

// `for &elem in …` and `#ref` call arguments. Unary `&` is a ref marker, not address-of.
peel_unary_and :: proc(expr: ^Expr) -> (inner: ^Expr, is_ref: bool) {
	expr := unparen_expr(expr)
	if expr == nil {
		return nil, false
	}
	if u, ok := expr.derived.(^Unary_Expr); ok && u.op.kind == .And {
		return u.expr, true
	}
	return expr, false
}

strip_or_return_expr :: proc(expr: ^Expr) -> (val: ^Expr) {
	if expr == nil {
		return nil
	}
	val = expr
	for {
		inner: ^Expr
		#partial switch e in val.derived {
		case ^Paren_Expr: inner  = e.expr
		}
		if inner == nil {
			break
		}
		val = inner
	}
	return val
}

expect_closing_token_of_field_list :: proc(p: ^Parser, close_kind: Token_Kind, msg: string) -> Token {
	token := p.curr_tok
	if allow_token(p, close_kind) {
		return token
	}
	if allow_token(p, .Semicolon) && token_is_newline(token) {
		parse_err(p, end_of_line_pos(p, p.prev_tok), "expected comma, got %s", token_to_string(token))
	}
	expect_closing := expect_token_after(p, close_kind, msg)

	if expect_closing.kind != close_kind {
		for p.curr_tok.kind != close_kind && p.curr_tok.kind != .EOF && !token_is_non_inserted_semicolon(p.curr_tok) {
			advance_token(p)
		}
		return p.curr_tok
	}

	return expect_closing
}

expect_closing_parenthesis_of_field_list :: proc(p: ^Parser) -> Token {
	token := p.curr_tok
	if allow_token(p, .Close_Paren) {
		return token
	}
	
	if allow_token(p, .Semicolon) && !token_is_newline(token) {
		parse_err(p, end_of_line_pos(p, p.prev_tok), "expected comman, got %s", token_to_string(token))
	}

	for p.curr_tok.kind != .Close_Paren && p.curr_tok.kind != .EOF && !token_is_non_inserted_semicolon(p.curr_tok) {
		advance_token(p)
	}
	
	return expect_token(p, .Close_Paren)
}

parse_value :: proc(p: ^Parser) -> ^Expr {
	if p.curr_tok.kind == .Open_Brace {
		return parse_literal_value(p, nil)
	}
	prev_allow_range := p.allow_range
	defer p.allow_range = prev_allow_range
	p.allow_range = true
	return parse_expr(p, false)
}

parse_elem_list :: proc(p: ^Parser) -> []^Expr {
	elems: [dynamic]^Expr

	for p.curr_tok.kind != .Close_Brace && p.curr_tok.kind != .EOF {
		elem := parse_value(p)
		if p.curr_tok.kind == .Eq {
			eq := expect_token(p, .Eq)
			value := parse_value(p)

			fv := ast_new(Field_Value, elem.pos, value)
			fv.field = elem
			fv.sep = eq.pos
			fv.value = value
			elem = fv
		}

		append(&elems, elem)

		allow_token(p, .Comma) or_break
	}

	return elems[:]
}

parse_literal_value :: proc(p: ^Parser, type: ^Expr) -> ^Comp_Lit {
	elems: []^Expr
	open := expect_token(p, .Open_Brace)
	p.expr_level += 1
	if p.curr_tok.kind != .Close_Brace {
		elems = parse_elem_list(p)
	}
	p.expr_level -= 1

	skip_possible_newline(p)
	close := expect_closing_brace_of_field_list(p)

	pos := type.pos if type != nil else open.pos
	lit := ast_new(Comp_Lit, pos, token_end_pos(close))
	lit.type = type
	lit.open = open.pos
	lit.elems = elems
	lit.close = close.pos
	return lit
}
 
expect_closing_brace_of_field_list :: proc(p: ^Parser) -> Token {
	return expect_closing_token_of_field_list(p, .Close_Brace, "field list")
}

parse_attribute :: proc(p: ^Parser, tok: Token, open_kind, close_kind: Token_Kind, docs: ^Comment_Group) -> ^Stmt {
	elems: [dynamic]^Expr
	open, close: Token

	if p.curr_tok.kind == open_kind {
		open = expect_token(p, open_kind)
		p.expr_level += 1
		for p.curr_tok.kind != close_kind && p.curr_tok.kind != .EOF {
			elem: ^Expr = parse_ident(p)
			if p.curr_tok.kind == .Eq {
				eq := expect_token(p, .Eq)
				value := parse_value(p)
				fv := ast_new(Field_Value, elem.pos, value)
				fv.field = elem
				fv.sep = eq.pos
				fv.value = value
				elem = fv
			}
			append(&elems, elem)
			allow_token(p, .Comma) or_break
		}
		p.expr_level -= 1
		close = expect_token_after(p, close_kind, "attribute")
	} else if p.curr_tok.kind == .Ident {
		// Bare `@shared` (Odin-style attribute without parentheses)
		elem := parse_ident(p)
		append(&elems, elem)
		open = tok
		close = p.prev_tok
	} else {
		parse_err(p, p.curr_tok.pos, "expected '(' or identifier after '@'")
		open = tok
		close = p.curr_tok
	}

	attribute := ast_new(Attribute, tok.pos, token_end_pos(close))
	attribute.tok = tok.kind
	attribute.open = open.pos
	attribute.elems = elems[:]
	attribute.close = close.pos

	skip_possible_newline(p)

	decl := parse_stmt(p)
	#partial switch d in decl.derived_stmt {
	case ^Value_Decl:
		if d.docs == nil { d.docs = docs }
		append(&d.attributes, attribute)
	case:
		parse_err(p, decl.pos, "expected a declaration after an attribute")
	}
	return decl
}

parse_stmt_list :: proc(p: ^Parser) -> []^Stmt {
	list: [dynamic]^Stmt
	for p.curr_tok.kind != .Case && p.curr_tok.kind != .Close_Brace && p.curr_tok.kind != .EOF {
		stmt := parse_stmt(p)
		if stmt != nil {
			if _, ok := stmt.derived.(^Empty_Stmt); !ok {
				append(&list, stmt)
				if es, es_ok := stmt.derived.(^Expr_Stmt); es_ok && es.expr != nil {
					if _, pl_ok := es.expr.derived.(^Proc_Lit); pl_ok {
						parse_err(p, stmt.pos, "procedure literal evaluated but not used")
					}
				}
			}
		}
	}
	return list[:]
}

expr_is_range :: proc(expr: ^Expr) -> bool {
	if expr == nil {
		return false
	}

	binary := expr.derived.(^Binary_Expr) or_return

	return binary.op.kind == .Range_Exclusive || binary.op.kind == .Range_Inclusive
}

value_decl_ident_name :: proc(expr: ^Expr) -> string {
	if expr == nil do return ""
	ident, ok := expr.derived.(^Ident)
	if !ok do return ""
	return ident.name
}

value_decl_is_pipeline :: proc(decl: ^Value_Decl) -> bool {
	if decl == nil || decl.is_mutable do return false
	if decl.type != nil {
		if _, ok := decl.type.derived.(^Pipeline_Type); ok {
			return true
		}
	}
	if len(decl.values) > 0 {
		if cl, ok := decl.values[0].derived.(^Comp_Lit); ok && cl.type != nil {
			if _, pok := cl.type.derived.(^Pipeline_Type); pok {
				return true
			}
		}
	}
	return false
}

collect_parsed_entries :: proc(module: ^Module) {
	if module == nil do return
	clear(&module.entries)
	clear(&module.pipelines)
	collect_parsed_entries_stmts(module, module.decls[:])
}

collect_parsed_entries_stmts :: proc(module: ^Module, stmts: []^Stmt) {
	for stmt in stmts {
		collect_parsed_entries_stmt(module, stmt)
	}
}

collect_parsed_entries_stmt :: proc(module: ^Module, stmt: ^Stmt) {
	if stmt == nil do return
	#partial switch s in stmt.derived {
	case ^Value_Decl:
		collect_parsed_value_decl(module, s)
	case ^Block_Stmt:
		collect_parsed_entries_stmts(module, s.stmts)
	case ^When_Stmt:
		collect_parsed_entries_stmt(module, s.body)
		collect_parsed_entries_stmt(module, s.else_stmt)
	case ^Which_Stmt:
		collect_parsed_entries_stmt(module, s.body)
	case ^Case_Clause:
		collect_parsed_entries_stmts(module, s.body)
	case ^If_Stmt:
		collect_parsed_entries_stmt(module, s.body)
		collect_parsed_entries_stmt(module, s.else_stmt)
	}
}

collect_parsed_value_decl :: proc(module: ^Module, decl: ^Value_Decl) {
	if decl == nil || decl.is_mutable do return
	if value_decl_is_pipeline(decl) {
		name := ""
		if len(decl.names) > 0 {
			name = value_decl_ident_name(decl.names[0])
		}
		if name == "" do return
		pipe := new(Pipeline)
		pipe.name = name
		pipe.node = decl
		pipe.module = module
		append(&module.pipelines, pipe)
		return
	}
	n := min(len(decl.names), len(decl.values))
	for i in 0 ..< n {
		lit, ok := decl.values[i].derived.(^Proc_Lit)
		if !ok || lit.type == nil do continue
		kind, kok := entry_kind_from_calling_convention(lit.type.calling_convention)
		if !kok do continue
		name := value_decl_ident_name(decl.names[i])
		if name == "" do continue
		e := new(Entry)
		e.name = name
		e.node = decl
		e.kind = kind
		e.module = module
		append(&module.entries, e)
	}
}