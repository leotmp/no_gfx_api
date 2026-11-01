package misl_lsp

import "core:unicode/utf8"
import "oge:misl"
import "./lsp"

// LSP Position is 0-based line + UTF-16 character offset.
// Token_Pos is 1-based line/column with byte offset into the file.

position_from_offset :: proc(text: string, offset: int) -> lsp.Position {
	offset := clamp(offset, 0, len(text))
	data := transmute([]u8)text
	pos: lsp.Position
	i := 0
	for i < offset {
		r, w := utf8.decode_rune(data[i:])
		if w == 0 {
			break
		}
		if r == '\n' {
			pos.line += 1
			pos.character = 0
		} else if r == '\r' {
			// handle \r\n as one newline
			if i + 1 < offset && data[i + 1] == '\n' {
				i += 1
			}
			pos.line += 1
			pos.character = 0
		} else if r < 0x10000 {
			pos.character += 1
		} else {
			pos.character += 2
		}
		i += w
	}
	return pos
}

offset_from_position :: proc(text: string, position: lsp.Position) -> (offset: int, ok: bool) {
	data := transmute([]u8)text
	if len(data) == 0 {
		return 0, position.line == 0 && position.character == 0
	}

	line := 0
	i := 0
	for line < position.line && i < len(data) {
		if data[i] == '\n' {
			line += 1
			i += 1
		} else if data[i] == '\r' {
			line += 1
			i += 1
			if i < len(data) && data[i] == '\n' {
				i += 1
			}
		} else {
			i += 1
		}
	}
	if line != position.line {
		return 0, false
	}

	utf16_idx := 0
	line_start := i
	for utf16_idx < position.character && i < len(data) {
		r, w := utf8.decode_rune(data[i:])
		if w == 0 || r == '\n' || r == '\r' {
			break
		}
		if r < 0x10000 {
			utf16_idx += 1
		} else {
			utf16_idx += 2
		}
		i += w
	}
	_ = line_start
	return i, true
}

token_pos_to_lsp_position :: proc(pos: misl.Token_Pos, text: string) -> lsp.Position {
	if pos.offset >= 0 && pos.offset <= len(text) {
		return position_from_offset(text, pos.offset)
	}
	// fallback from 1-based line/column (byte column → UTF-16 best-effort)
	line := max(pos.line - 1, 0)
	col := max(pos.column - 1, 0)
	offset, ok := offset_from_position(text, {line = line, character = 0})
	if !ok {
		return {line = line, character = col}
	}
	end := min(offset + col, len(text))
	return position_from_offset(text, end)
}

token_pos_to_range :: proc(pos: misl.Token_Pos, length: int, text: string) -> lsp.Range {
	start := token_pos_to_lsp_position(pos, text)
	end_off := min(pos.offset + max(length, 0), len(text))
	end := position_from_offset(text, end_off)
	return {start = start, end = end}
}

ident_range :: proc(ident: ^misl.Ident, text: string) -> lsp.Range {
	if ident == nil {
		return {}
	}
	length := len(ident.name)
	if ident.end.offset > ident.pos.offset {
		length = ident.end.offset - ident.pos.offset
	}
	return token_pos_to_range(ident.pos, length, text)
}

node_range :: proc(pos, end: misl.Token_Pos, text: string) -> lsp.Range {
	start := token_pos_to_lsp_position(pos, text)
	end_pos := token_pos_to_lsp_position(end, text)
	return {start = start, end = end_pos}
}
