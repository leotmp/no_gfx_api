// Minimal Shading Language 
package misl

import "base:runtime"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
import "core:fmt"



// TODO(Dragos): taken directly from odin, remove/add what is needed. Most things here won't be useful
Token_Kind :: enum {
	Invalid,
	EOF,
	Comment,
	File_Tag,

	_Literal_Begin,
		Ident     ,   // main
		Integer   ,   // 12345
		Imaginary ,   // 123.45i
		Float     ,   // 123.45
		Rune      ,   // 'a'
		String    ,   // "abc" `abc`
	_Literal_End,

	_Operator_Begin,
		Eq       ,   // =
		Not      ,   // !
		Hash     ,   // #
		At       ,   // @
		Dollar   ,   // $
		Pointer ,    // ^
		Question,    // ?
		Add      ,   // +
		Sub      ,   // -
		Mul      ,   // *
		Quo      ,   // /
		Mod      ,   // %
		And     ,    // &
		Or      ,    // |
		Xor     ,    // ~
		And_Not ,    // &~
		Shl     ,    // <<
		Shr     ,    // >>
		Cmp_And ,    // &&
		Cmp_Or  ,    // ||

	_Assign_Op_Begin,
		Add_Eq    ,  // +=
		Sub_Eq    ,  // -=
		Mul_Eq    ,  // *=
		Quo_Eq    ,  // /=
		Mod_Eq    ,  // %=
		And_Eq    ,  // &=
		Or_Eq     ,  // |=
		Xor_Eq    ,  // ~=
		And_Not_Eq,  // &~=
		Shl_Eq    ,  // <<=
		Shr_Eq    ,  // >>=
		Cmp_And_Eq,  // &&=
		Cmp_Or_Eq ,  // ||=
	_Assign_Op_End,
		
		Increment  ,  // ++
		Decrement  ,  // --
		Arrow_Right,  // ->
		Undef      ,  // ---

	_Comparison_Begin,
		Cmp_Eq,  // ==
		Not_Eq,  // !=
		Lt    ,  // <
		Gt    ,  // >
		Lt_Eq ,  // <=
		Gt_Eq ,  // >=
	_Comparison_End,

		Open_Paren     ,  // (
		Close_Paren    ,  // )
		Open_Bracket   ,  // [
		Close_Bracket  ,  // ]
		Open_Brace     ,  // {
		Close_Brace    ,  // }
		Colon          ,  // :
		Semicolon      ,  // ;
		Period         ,  // .
		Comma          ,  // ,
		Ellipsis       ,  // ..
		Range_Exclusive,  // ..<
		Range_Inclusive,  // ..=

	_Operator_End,

	_Keyword_Begin,
		Import      ,   // import // Note(Dragos): this will likely take a while to implement. It's not currently needed
		When        ,   // when
		Which       ,   // which
		Where       ,   // where
		If          ,   // if
		Else        ,   // else
		For         ,   // for
		Switch      ,   // switch
		Case        ,   // case
		In          ,   // in
		Not_In      ,   // not_in
		Enum        ,   // enum
		Bit_Set     ,   // bit_set
		Cast        ,   // cast
		Auto_Cast   ,   // auto_cast
		Using       ,   // using
		Matrix      ,   // matrix
		Non_Uniform ,   // non_uniform
		Return      ,   // return
		Continue    ,   // continue
		Break       ,   // break
		Fallthrough ,   // fallthrough
		Module      ,   // module
		Discard     ,   // discard
		Proc        ,   // proc
		Do          ,   // do
		Typeid      ,   // typeid
		Struct      ,   // struct
		Pipeline    ,   // pipeline
	_Keyword_End,
}

token_is_operator :: proc(kind: Token_Kind) -> bool {
	#partial switch kind {
	case ._Operator_Begin ..= ._Operator_End:
		return true
	case .In, .Not_In:
		return true
	case .If:
		return true
	}
	return false
}

token_is_newline :: proc(tok: Token) -> bool {
	return tok.kind == .Semicolon && tok.text == "\n"
}

token_is_literal  :: proc(kind: Token_Kind) -> bool {
	return ._Literal_Begin  < kind && kind < ._Literal_End
}

token_is_assignment_operator :: proc(kind: Token_Kind) -> bool {
	return ._Assign_Op_Begin < kind && kind < ._Assign_Op_End || kind == .Eq
}

token_is_keyword :: proc(kind: Token_Kind) -> bool {
	switch {
	case ._Keyword_Begin < kind && kind < ._Keyword_End:
		return true
	}
	return false
}



Lit_Val :: enum {
	u64,
	i64, // Note(dragos): should the sign be treated as an operator?
	f64,
}

Token_Pos :: struct {
	file: string,
	offset: int,
	line: int,
	column: int,
}

Token :: struct {
	kind: Token_Kind,
	text: string,
	pos: Token_Pos,
	val: Lit_Val,
}

tokens := [Token_Kind]string{
	.Invalid = "Invalid",
	.EOF = "EOF",
	.Comment = "Comment",
	.File_Tag = "FileTag",

	._Literal_Begin = "",
		.Ident          = "identifier",   // main
		.Integer        = "intger",       // 12345
		.Imaginary      = "imaginary",    // 123.45i
		.Float          = "float",        // 123.45
		.Rune           = "rune",         // 'a'
		.String         = "string",       // "abc" `abc`
	._Literal_End   = "",

	._Operator_Begin = "",
		.Eq        = "=",   // =
		.Not       = "!",   // !
		.Hash      = "#",   // #
		.At        = "@",   // @
		.Dollar    = "$",   // $
		.Pointer   = "^",   // ^
		.Question  = "?",   // ?
		.Add       = "+",   // +
		.Sub       = "-",   // -
		.Mul       = "*",   // *
		.Quo       = "/",   // /
		.Mod       = "%",   // %
		.And       = "&",   // &
		.Or        = "|",   // |
		.Xor       = "~",   // ~
		.And_Not   = "&~",  // &~
		.Shl       = "<<",  // <<
		.Shr       = ">>",  // >>
		.Cmp_And   = "&&",  // &&
		.Cmp_Or    = "||",  // ||

	._Assign_Op_Begin = "",
		.Add_Eq           = "+=",    // +=
		.Sub_Eq           = "-=",    // -=
		.Mul_Eq           = "*=",    // *=
		.Quo_Eq           = "/=",    // /=
		.Mod_Eq           = "%=",    // %=
		.And_Eq           = "&=",    // &=
		.Or_Eq            = "|=",    // |=
		.Xor_Eq           = "~=",    // ~=
		.And_Not_Eq       = "&~=",   // &~=
		.Shl_Eq           = "<<=",   // <<=
		.Shr_Eq           = ">>=",   // >>=
		.Cmp_And_Eq       = "&&=",   // &&=
		.Cmp_Or_Eq        = "||=",   // ||=
	._Assign_Op_End   = "",
		
		.Increment   = "++",    // ++
		.Decrement   = "--",    // --
		.Arrow_Right = "->",    // ->
		.Undef       = "---",   // ---

	._Comparison_Begin = "",
		.Cmp_Eq = "==",  // ==
		.Not_Eq = "!=",  // !=
		.Lt     = "<",  // <
		.Gt     = ">",  // >
		.Lt_Eq  = "<=",  // <=
		.Gt_Eq  = ">=",  // >=
	._Comparison_End = "",

		.Open_Paren      = "(",  // (
		.Close_Paren     = ")",  // )
		.Open_Bracket    = "[",  // [
		.Close_Bracket   = "]",  // ]
		.Open_Brace      = "{",  // {
		.Close_Brace     = "}",  // }
		.Colon           = ":",  // :
		.Semicolon       = ";",  // ;
		.Period          = ".",  // .
		.Comma           = ",",  // ,
		.Ellipsis        = "..",  // ..
		.Range_Exclusive = "..<",  // ..<
		.Range_Inclusive = "..=",  // ..=

	._Operator_End = "",

	._Keyword_Begin = "",
		.Import      = "import",
		.When        = "when",
		.Which       = "which",
		.Where       = "where", 
		.If          = "if", 
		.Else        = "else", 
		.For         = "for", 
		.Switch      = "switch", 
		.Case        = "case",
		.In          = "in", 
		.Not_In      = "not_in", 
		.Enum        = "enum", 
		.Bit_Set     = "bit_set", 
		.Cast        = "cast",
		.Auto_Cast   = "auto_cast",
		.Using       = "using", 
		.Matrix      = "matrix", 
		.Non_Uniform = "non_uniform", 
		.Return      = "return",
		.Continue    = "continue",
		.Break       = "break",
		.Fallthrough = "fallthrough",
		.Module      = "module",
		.Discard     = "discard",
		.Proc        = "proc",
		.Do          = "do",
		.Typeid      = "typeid",
		.Struct      = "struct",
		.Pipeline    = "pipeline",
	._Keyword_End = "",
	
}

Lexer_Flags :: bit_set[Lexer_Flag]
Lexer_Flag :: enum {
	Insert_Semicolons,
}


Warning_Handler :: #type proc(pos: Token_Pos, msg: string, args: ..any)
default_warning_handler :: proc(pos: Token_Pos, msg: string, args: ..any) {
	fmt.eprintf("%s:%s:%s: Warning: ", pos.file, pos.line, pos.column)
	fmt.eprintfln(msg, ..args)
}

Error_Handler :: #type proc(pos: Token_Pos, msg: string, args: ..any)
default_error_handler :: proc(pos: Token_Pos, msg: string, args: ..any) {
	fmt.eprintf("%v:%v:%v: ", pos.file, pos.line, pos.column)
	fmt.eprintfln(msg, ..args)
}

token_to_string :: proc(tok: Token) -> string {
	return token_kind_to_string(tok.kind)
}

token_kind_to_string :: proc(kind: Token_Kind) -> string {
	return tokens[kind]
}


Lexer :: struct {
	path: string,
	code: string,
	err: Error_Handler,
	flags: Lexer_Flags,

	// Tokenizing state
	ch: rune, // the most recent rune
	offset: int, // offset of Lexer.ch
	read_offset: int, // the next rune offset
	line_offset: int,
	line_count: int,
	insert_semicolon: bool,
	error_count: int,
}

lexer_init :: proc(l: ^Lexer, code: string, path: string, err: Error_Handler = default_error_handler) {
	l.code = code
	l.err = err
	l.ch = ' '
	l.offset = 0
	l.read_offset = 0
	l.line_offset = 0
	l.line_count = 1 if len(code) > 0 else 0
	l.insert_semicolon = false
	l.error_count = 0
	l.path = path
	lex_advance_rune(l)
	if l.ch == utf8.RUNE_BOM {
		lex_advance_rune(l)
	}
}

@private
lex_offset_to_pos :: proc(l: ^Lexer, offset: int) -> Token_Pos {
	return {
		file = l.path,
		offset = offset,
		line = l.line_count,
		column = offset - l.line_offset + 1,
	}
}

lex_err :: proc(l: ^Lexer, offset: int, msg: string, args: ..any) {
	pos := lex_offset_to_pos(l, offset)
	if l.err != nil {
		l.err(pos, msg, ..args)
	}
	l.error_count += 1
}

lex_advance_rune :: proc(l: ^Lexer) {
	if l.read_offset < len(l.code) {
		l.offset = l.read_offset
		if l.ch == '\n' {
			l.line_offset = l.offset
			l.line_count += 1
		}
		r, w := rune(l.code[l.read_offset]), 1
		switch {
		case r == 0:
			lex_err(l, l.offset, "illegal character NUL")
		case r >= utf8.RUNE_SELF:
			r, w = utf8.decode_rune_in_string(l.code[l.read_offset:])
			if r == utf8.RUNE_ERROR && w == 1 {
				lex_err(l, l.offset, "illegal UTF-8 encoding")
			} else if r == utf8.RUNE_BOM && l.offset > 0 {
				lex_err(l, l.offset, "illegal byte order mark")
			}
		}
		l.read_offset += w
		l.ch = r
	} else {
		l.offset = len(l.code)
		if l.ch == '\n' {
			l.line_offset = l.offset
			l.line_count += 1
		}
		l.ch = -1
	}
}

lex_peek_byte :: proc(l: ^Lexer, offset := 0) -> byte {
	if l.read_offset + offset < len(l.code) {
		return l.code[l.read_offset + offset]
	}
	return 0
}

lex_skip_whitespace :: proc(l: ^Lexer) {
	if l.insert_semicolon {
		for {
			switch l.ch {
			case ' ', '\t', '\r':
				lex_advance_rune(l)
			case:
				return
			}
		}
	} else {
		for {
			switch l.ch {
			case ' ', '\t', '\r', '\n':
				lex_advance_rune(l)
			case:
				return
			}
		}
	}
}

@private
is_letter :: proc(r: rune) -> bool {
	if r < utf8.RUNE_SELF {
		switch r {
		case '_', 'A'..='Z', 'a'..='z':
			return true
		}
	}
	return unicode.is_letter(r)
}

@private
is_digit :: proc(r: rune) -> bool {
	if '0' <= r && r <= '9' {
		return true
	}
	return unicode.is_digit(r)
}

lex_scan_comment :: proc(l: ^Lexer) -> string {
	offset := l.offset - 1
	next := -1
	general: {
		// [// /!] comments
		if l.ch == '/' || l.ch == '!' { 
			lex_advance_rune(l)
			for l.ch != '\n' && l.ch >= 0 {
				lex_advance_rune(l)
			}

			next = l.offset
			if l.ch == '\n' {
				next += 1
			}
			break general
		}

		/* multi-line comments */
		lex_advance_rune(l)
		nest := 1
		for l.ch >= 0 && nest > 0 {
			ch := l.ch
			lex_advance_rune(l)
			if ch == '/' && l.ch == '*' {
				nest += 1
			}

			if ch == '*' && l.ch == '/' {
				nest -= 1
				lex_advance_rune(l)
				next = l.offset
				if nest == 0 {
					break general
				}
			}
		}

		lex_err(l, offset, "comment not terminated")
	}

	lit := l.code[offset : l.offset]

	// strip CR for line comments
	for len(lit) > 2 && lit[1] == '/' && lit[len(lit)-1] == 'r' {
		lit = lit[:len(lit)-1]
	}

	return lit
}

lex_scan_file_tag :: proc(l: ^Lexer) -> string {
	offset := l.offset - 1
	for l.ch != '\n' && l.ch != utf8.RUNE_EOF {
		if l.ch == '/' {
			next := lex_peek_byte(l)
			if next == '/' || next == '*' {
				break
			}
		}
		lex_advance_rune(l)
	}
	return l.code[offset : l.offset]
}

lex_scan_identifier :: proc(l: ^Lexer) -> string {
	offset := l.offset
	for is_letter(l.ch) || is_digit(l.ch) {
		lex_advance_rune(l)
	}
	return l.code[offset : l.offset]
}

lex_scan_string :: proc(l: ^Lexer) -> string {
	offset := l.offset
	for {
		ch := l.ch
		if ch == '\n' || ch == 0 || ch == utf8.RUNE_EOF {
			lex_err(l, offset, "string literal not terminated")
			return l.code[offset : l.offset]
		}
		lex_advance_rune(l)
		if ch == '"' {
			break
		}
		if ch == '\\' {
			lex_scan_escape(l)
		}
	}
	return l.code[offset : l.offset-1]
}

lex_scan_raw_string :: proc(l: ^Lexer) -> string {
	offset := l.offset - 1
	for {
		ch := l.ch
		if ch == utf8.RUNE_EOF {
			lex_err(l, offset, "raw string literal was not terminated")
			break
		}
		lex_advance_rune(l)
		if ch == '`' {
			break
		}
	}
	return l.code[offset : l.offset]
}

@private
digit_val :: proc(r: rune) -> int {
	switch r {
	case '0'..='9':
		return int(r - '0')
	case 'A'..='F':
		return int(r - 'A' + 10)
	case 'a'..='f':
		return int(r - 'a' + 10)
	}
	return 16
}

lex_scan_escape :: proc(l: ^Lexer) -> bool {
	offset := l.offset
	n: int
	base, max: u32
	switch l.ch {
	case 'a', 'b', 'e', 'f', 'n', 't', 'v', 'r', '\\', '\'', '"':
		lex_advance_rune(l)
		return true
	case '0'..='7':
		n, base, max = 3, 8, 255
	case 'x':
		lex_advance_rune(l)
		n, base, max = 2, 16, 255
	case 'u':
		lex_advance_rune(l)
		n, base, max = 4, 16, utf8.MAX_RUNE
	case 'U':
		lex_advance_rune(l)
		n, base, max = 8, 16, utf8.MAX_RUNE
	case:
		if l.ch < 0 {
			lex_err(l, offset, "escape sequence was not terminated")
		} else {
			lex_err(l, offset, "unknown escape sequence")
		}
		return false
	}

	x: u32
	for n > 0 {
		d := u32(digit_val(l.ch))
		for d >= base {
			if l.ch < 0 {
				lex_err(l, l.offset, "escape sequence was not terminated")
			} else {
				lex_err(l, l.offset, "illegal character %d in escape sequence", l.ch)
			}
			return false
		}

		x = x * base + d
		lex_advance_rune(l)
		n -= 1
	}

	if x > max || 0xd800 <= x && x <= 0xdfff {
		lex_err(l, offset, "escape sequence is not a valid Unicode code point")
		return false
	}

	return true
}

lex_scan_rune :: proc(l: ^Lexer) -> string {
	offset := l.offset - 1
	valid := true
	n := 0
	for {
		ch := l.ch
		if ch == '\n' || ch < 0 {
			if valid {
				lex_err(l, offset, "rune literal not terminated")
				valid = false
			}
			break
		}
		lex_advance_rune(l)
		if ch == '\'' {
			break
		}
		n += 1
		if ch == '\\' {
			if !lex_scan_escape(l) {
				valid = false
			}
		}
	}

	if valid && n != 1 {
		lex_err(l, offset, "illegal rune literal")
	}
	
	return l.code[offset : l.offset]
}

lex_scan_number :: proc(l: ^Lexer, seen_decimal_point: bool) -> (Token_Kind, string) {
	scan_mantissa :: proc(l: ^Lexer, base: int) {
		for digit_val(l.ch) < base || l.ch == '_' {
			lex_advance_rune(l)
		}
	}

	scan_exponent :: proc(l: ^Lexer, kind: ^Token_Kind) {
		if l.ch == 'e' || l.ch == 'E' {
			kind^ = .Float
			lex_advance_rune(l)
			if l.ch == '-' || l.ch == '+' {
				lex_advance_rune(l)
			}
			if digit_val(l.ch) < 10 {
				scan_mantissa(l, 10)
			} else {
				lex_err(l, l.offset, "illegal floating-point exponent")
			}
		}

		switch l.ch {
		case 'i', 'j', 'k':
			kind^ = .Imaginary
			lex_advance_rune(l)
		}
	}

	scan_fraction :: proc(l: ^Lexer, kind: ^Token_Kind) -> (early_exit: bool) {
		if l.ch == '.' && lex_peek_byte(l) == '.' {
			return true
		}
		if l.ch == '.' {
			kind^ = .Float
			lex_advance_rune(l)
			scan_mantissa(l, 10)
		}
		return false
	}

	offset := l.offset
	kind: Token_Kind = .Integer
	seen_point := seen_decimal_point

	if seen_point {
		offset -= 1
		kind = .Float
		scan_mantissa(l, 10)
		scan_exponent(l, &kind)
	} else {
		if l.ch == '0' {
			int_base :: proc(l: ^Lexer, kind: ^Token_Kind, base: int, err_msg: string) {
				prev := l.offset
				lex_advance_rune(l)
				scan_mantissa(l, base)
				if l.offset - prev <= 1 {
					kind^ = .Invalid
					lex_err(l, l.offset, err_msg)
				}
			}

			lex_advance_rune(l)
			switch l.ch {
			case 'b': int_base(l, &kind, 2, "illegal binary integer")
			case 'o': int_base(l, &kind, 8, "illegal octal integer")
			case 'd': int_base(l, &kind, 10, "illegal decimal integer")
			case 'z': int_base(l, &kind, 12, "illegal dozenal integer")
			case 'x': int_base(l, &kind, 16, "illegal hexadecimal integer")
			case 'h':
				prev := l.offset
				lex_advance_rune(l)
				scan_mantissa(l, 16)
				if l.offset - prev <= 1 {
					kind = .Invalid
					lex_err(l, l.offset, "illegal hexadecimal floating-point number")
				} else {
					sub := l.code[prev+1 : l.offset]
					digit_count := 0
					for d in sub {
						if d != '_' {
							digit_count += 1
						}
					}

					switch digit_count {
					case 4, 8, 16:
						kind = .Float
					case:
						lex_err(l, l.offset, "invalid hexadecimal floating point, expected 4, 8, or 16 digits, got %d", digit_count)
					}
				}
				return kind, l.code[offset : l.offset]
			case: 
				seen_point = false
				scan_mantissa(l, 10)
				if l.ch == '.' {
					seen_point = true
					if scan_fraction(l, &kind) {
						return kind, l.code[offset : l.offset]
					}
				}
				scan_exponent(l, &kind)
				return kind, l.code[offset : l.offset]
			}
		}
	}

	scan_mantissa(l, 10)

	if scan_fraction(l, &kind) {
		return kind, l.code[offset : l.offset]
	}

	scan_exponent(l, &kind)
	
	return kind, l.code[offset : l.offset]
}

lex_scan :: proc(l: ^Lexer) -> (Token, bool) {
	lex_skip_whitespace(l)
	
	offset := l.offset

	kind: Token_Kind
	lit: string
	pos := lex_offset_to_pos(l, offset)

	switch ch := l.ch; true {
	case is_letter(ch):
		lit = lex_scan_identifier(l)
		kind = .Ident
		check_keyword: if len(lit) > 1 {
			for i in Token_Kind._Keyword_Begin ..< Token_Kind._Keyword_End {
				if lit == tokens[i] {
					kind = Token_Kind(i)
					break check_keyword
				}
			}
		}
	case '0' <= ch && ch <= '9':
		kind, lit = lex_scan_number(l, false)
	case:
		lex_advance_rune(l)
		switch ch {
		case -1:
			kind = .EOF
			if l.insert_semicolon {
				l.insert_semicolon = false
				kind = .Semicolon
				lit = "\n"
				return Token{kind = kind, text = lit, pos = pos}, false
			}
		case '\n':
			l.insert_semicolon = false
			kind = .Semicolon
			lit = "\n"
		case '\\':
			if .Insert_Semicolons in l.flags {
				l.insert_semicolon = false
			}
			token, _ := lex_scan(l)
			if token.pos.line == pos.line {
				lex_err(l, token.pos.offset, "expected a newline after \\")
			}
			return token, false
		
		case '\'':
			kind = .Rune
			lit = lex_scan_rune(l)
		case '"':
			kind = .String
			lit = lex_scan_string(l)
		case '`':
			kind = .String
			lit = lex_scan_raw_string(l)
		case '.':
			kind = .Period
			switch l.ch {
			case '0'..='9':
				kind, lit = lex_scan_number(l, true)
			case '.':
				lex_advance_rune(l)
				kind = .Ellipsis
				switch l.ch {
				case '<':
					lex_advance_rune(l)
					kind = .Range_Exclusive
				case '=':
					lex_advance_rune(l)
					kind = .Range_Inclusive
				}
			}
		case '@': kind = .At
		case '$': kind = .Dollar
		case '?': kind = .Question
		case '^': kind = .Pointer
		case ';': kind = .Semicolon
		case ',': kind = .Comma
		case ':': kind = .Colon
		case '(': kind = .Open_Paren
		case ')': kind = .Close_Paren
		case '[': kind = .Open_Bracket
		case ']': kind = .Close_Bracket
		case '{': kind = .Open_Brace
		case '}': kind = .Close_Brace
		case '%': kind = lex_scan_maybe_two_char_op(l, '=', .Mod, .Mod_Eq)
		case '*': kind = lex_scan_maybe_two_char_op(l, '=', .Mul, .Mul_Eq)
		case '=': kind = lex_scan_maybe_two_char_op(l, '=', .Eq, .Cmp_Eq)
		case '~': kind = lex_scan_maybe_two_char_op(l, '=', .Xor, .Xor_Eq)
		case '!': kind = lex_scan_maybe_two_char_op(l, '=', .Not, .Not_Eq)
		case '+':
			kind = .Add
			switch l.ch {
			case '=':
				lex_advance_rune(l)
				kind = .Add_Eq
			case '+':
				lex_advance_rune(l)
				kind = .Increment
			}
		case '-':
			kind = .Sub
			switch l.ch {
				case '-':
					lex_advance_rune(l)
					kind = .Decrement
					if l.ch == '-' {
						lex_advance_rune(l)
						kind = .Undef
					}
				case '=':
					lex_advance_rune(l)
					kind = .Sub_Eq
				case '>':
					lex_advance_rune(l)
					kind = .Arrow_Right
			}
		case '#':
			kind = .Hash
			if l.ch == '!' {
				kind = .Comment
				lit = lex_scan_comment(l)
			} else if l.ch == '+' {
				kind = .File_Tag
				lit = lex_scan_file_tag(l)
			}
		case '/':
			kind = .Quo
			switch l.ch {
			case '/', '*':
				kind = .Comment
				lit = lex_scan_comment(l)
			case '=':
				lex_advance_rune(l)
				kind = .Quo_Eq
			}
		case '<':
			kind = .Lt
			switch l.ch {
			case '=':
				lex_advance_rune(l)
				kind = .Lt_Eq
			case '<':
				lex_advance_rune(l)
				kind = .Shl
				if l.ch == '=' {
					lex_advance_rune(l)
					kind = .Shl_Eq
				}
			}
		case '>':
			kind = .Gt
			switch l.ch {
			case '=':
				lex_advance_rune(l)
				kind = .Gt_Eq
			case '>':
				lex_advance_rune(l)
				kind = .Shr
				if l.ch == '=' {
					lex_advance_rune(l)
					kind = .Shr_Eq
				}
			}
		case '&':
			kind = .And
			switch l.ch {
			case '~':
				lex_advance_rune(l)
				kind = .And_Not
				if l.ch == '=' {
					lex_advance_rune(l)
					kind = .And_Not_Eq
				}
			case '=':
				lex_advance_rune(l)
				kind = .And_Eq
			case '&':
				lex_advance_rune(l)
				kind = .Cmp_And
				if l.ch == '=' {
					lex_advance_rune(l)
					kind = .Cmp_And_Eq
				}
			}
		case '|':
			kind = .Or
			switch l.ch {
			case '=':
				lex_advance_rune(l)
				kind = .Or_Eq
			case '|':
				lex_advance_rune(l)
				kind = .Cmp_Or
				if l.ch == '=' {
					lex_advance_rune(l)
					kind = .Cmp_Or_Eq
				}
			}
		case:
			if ch == utf8.RUNE_BOM {
				lex_err(l, l.offset, "illegal character '%r': %d", ch, ch)
			}
			kind = .Invalid
		}
	}
	
	// Todo(Dragos): come back to this later and add/remove stuff
	if .Insert_Semicolons in l.flags {
		#partial switch kind {
		case .Invalid, .Comment: // preserve insert_semicolon info
		case .Ident, .Break, .Continue, .Fallthrough, .Return, .Integer,
		     .Float, .Imaginary, .Rune, .String, .Undef, .Question, .Pointer,
		     .Close_Paren, .Close_Bracket, .Close_Brace, .Increment, .Decrement:
			l.insert_semicolon = true	 
		case:
			l.insert_semicolon = false
		}
	}

	// Operators leave `lit` empty and take the source span. Quoted `""` also
	// scans to an empty interior — keep that; do not substitute the quotes.
	if lit == "" && kind != .String {
		lit = l.code[offset : l.offset]
	}
	return Token{kind, lit, pos, {}}, kind != .EOF && kind != .Invalid
}

lex_scan_maybe_two_char_op :: proc(l: ^Lexer, next_ch: rune, one_char_token: Token_Kind, two_char_token: Token_Kind) -> (kind: Token_Kind) {
	if l.ch == next_ch {
		lex_advance_rune(l)
		return two_char_token
	}
	return one_char_token
}

token_end_pos :: proc(tok: Token) -> Token_Pos {
	pos := tok.pos
	pos.offset += len(tok.text)
	if (tok.kind == .Comment && len(tok.text) >= 2 && tok.text[:2] == "/*") ||
	   (tok.kind == .String && len(tok.text) >= 1 && tok.text[:1] == "`") {
		for i := 0; i < len(tok.text); i += 1 {
			c := tok.text[i]
			if c == '\n' {
				pos.line += 1
				pos.column = 1
			} else {
				pos.column += 1
			}
		}
	} else {
		pos.column += len(tok.text)
	}
	return pos
}