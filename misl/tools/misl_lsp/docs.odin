package misl_lsp

import "core:fmt"
import "core:strings"
import "oge:misl"

// Strip `//` / `/* */` delimiters from a single comment token and trim
// surrounding whitespace, keeping any inner text (including newlines inside
// block comments) intact.
comment_token_markdown :: proc(text: string) -> string {
	text := text
	switch {
	case len(text) >= 2 && text[:2] == "//":
		text = text[2:]
	case len(text) >= 4 && text[:2] == "/*" && text[len(text)-2:] == "*/":
		text = text[2 : len(text)-2]
	}
	return strings.trim_space(text)
}

// Render a `Comment_Group` (leading `//` lines or a `/* */` block) as plain
// markdown text — one source line per output line.
comment_group_markdown :: proc(docs: ^misl.Comment_Group) -> string {
	if docs == nil || len(docs.list) == 0 do return ""
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	for tok in docs.list {
		line := comment_token_markdown(tok.text)
		if line == "" do continue
		if strings.builder_len(b) > 0 do strings.write_byte(&b, '\n')
		strings.write_string(&b, line)
	}
	return strings.to_string(b)
}

// ```misl\n<code>\n``` fence, followed by a `---` separated markdown doc
// section when `docs_md` is non-empty.
// KaTeX in editor hovers treats `$...` as math and can strip the `$` from
// `$n: i32`. A ZWSP after `$` keeps the glyph visible inside the fence.
// Hash tags (`#ref`, `#flat`, …) are not math; they stay as-is inside the
// ```misl fence. Do not emit them at column 0 outside a fence — markdown
// would treat `#` as a heading.
markdown_code_for_hover :: proc(code: string) -> string {
	if strings.index_byte(code, '$') < 0 do return code
	out, _ := strings.replace_all(code, "$", fmt.tprintf("$%c", rune(0x200B)), context.temp_allocator)
	return out
}

markdown_fence_with_docs :: proc(code, docs_md: string) -> string {
	code := markdown_code_for_hover(code)
	if docs_md == "" {
		return fmt.tprintf("```misl\n%s\n```", code)
	}
	return fmt.tprintf("```misl\n%s\n```\n---\n%s", code, docs_md)
}

// Leading `///`-style doc comment attached to the entity's declaration, if any.
entity_leading_docs :: proc(e: ^misl.Entity) -> string {
	if e == nil || e.decl == nil || e.decl.docs == nil do return ""
	return comment_group_markdown(e.decl.docs)
}

// Hover markdown for a resolved identifier: OLS-style symbol line inside a
// ```misl fence, plus doc text (if any) after `---`.
//
// Builtins (`e.kind == .Builtin`) prefer `misl.builtin_sigs`'s generic
// templated signature ("genType" params etc.) and hand-written docs over the
// bare, call-site-resolved signature `hover_symbol_info` would otherwise show.
// Optional `reference_uri` appends a markdown link (no editor underline).
entity_hover_markdown :: proc(e: ^misl.Entity, ident: ^misl.Ident, reference_uri := "") -> string {
	if e != nil {
		if id, ok := misl.entity_compiler_builtin(e); ok {
			name := e.name
			if ident != nil && ident.name != "" {
				name = ident.name
			}
			md := misl.builtin_sig_docs_markdown(id, name)
			if reference_uri != "" {
				md = fmt.tprintf("%s\n\n[Open language reference](%s)", md, reference_uri)
			}
			return md
		}
	}

	info := hover_symbol_info(ident)
	if info == "" do return ""
	docs_md := entity_leading_docs(e)
	if e != nil && e.type != nil {
		if pt, ok := e.type.derived.(^misl.Type_Proc); ok && pt.is_fmag {
			note := "FMAG bytecode entry — not a GPU pipeline stage. Host: `compile_fmag_entry` (`header.regs` ≤ 16, matching `core:fmag.REGS`). Fragment packs `[fmag.REGS]f32` and calls `fmag.run`."
			docs_md = note if docs_md == "" else fmt.tprintf("%s\n\n%s", docs_md, note)
		}
	}
	return markdown_fence_with_docs(info, docs_md)
}
