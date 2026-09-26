package misl_lsp

import "core:fmt"
import "oge:misl"
import "./lsp"

signature_help_at :: proc(ws: ^Workspace, params: lsp.Signature_Help_Params) -> Maybe(lsp.Signature_Help) {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil do return nil
	offset, ok := offset_from_position(doc.text, params.position)
	if !ok do return nil
	mod := workspace_module_for_uri(ws, params.text_document.uri, offset)
	if mod == nil do return nil

	hit := ast_find_at_offset(mod, offset)
	call := hit.call
	if call == nil do return nil

	callee_entity: ^misl.Entity
	callee_name: string
	#partial switch e in call.expr.derived_expr {
	case ^misl.Ident:
		callee_entity = e.entity
		callee_name = e.name
	case ^misl.Selector_Expr:
		if e.field != nil {
			callee_entity = e.field.entity
			callee_name = e.field.name
		}
	}
	if callee_entity != nil && callee_entity.name != "" {
		callee_name = callee_entity.name
	}

	label: string
	documentation: string
	params_info := make([dynamic]lsp.Parameter_Information, context.temp_allocator)

	if id, ok := misl.entity_compiler_builtin(callee_entity); ok {
		sig := misl.builtin_sigs[id]
		name := callee_name if callee_name != "" else (callee_entity.name if callee_entity != nil else "")
		if name == "" {
			name = misl.builtin_names[id]
		}
		documentation = sig.docs

		if sig.kind == .Printf {
			// Dynamic arity from format string when arg0 is a constant string.
			format_ok := false
			if len(call.args) >= 1 {
				arg0 := call.args[0]
				if arg0 != nil && arg0.tav.mode == .Constant {
					if format, is_str := arg0.tav.value.(string); is_str {
						slots, ferr := misl.printf_scan_slots(format, context.temp_allocator)
						if ferr == "" {
							format_ok = true
							clear(&params_info)
							append(&params_info, lsp.Parameter_Information{label = "fmt: string"})
							label = fmt.tprintf("%s(fmt: string", name)
							for slot, i in slots {
								spec := "%v" if slot == .Compact else "%#v"
								pl := fmt.tprintf("%s: any", spec)
								append(&params_info, lsp.Parameter_Information{label = pl})
								label = fmt.tprintf("%s, %s", label, pl)
								_ = i
							}
							label = fmt.tprintf("%s)", label)
						}
					}
				}
			}
			if !format_ok {
				clear(&params_info)
				append(&params_info, lsp.Parameter_Information{label = "fmt: string"})
				append(&params_info, lsp.Parameter_Information{label = "…"})
				label = fmt.tprintf("%s(fmt: string, …)", name)
			}
		} else {
			label = misl.builtin_sig_label(id, name)
			for p in sig.params {
				append(&params_info, lsp.Parameter_Information{
					label = fmt.tprintf("%s: %s", p.name, misl.builtin_param_type_string(p)),
				})
			}
		}
	} else {
		callee_type: ^misl.Type
		if callee_entity != nil do callee_type = callee_entity.type
		if callee_type == nil do return nil

		t, is_proc := proc_type_for_display(callee_type)
		switch {
		case is_proc:
			prefix := callee_name if callee_name != "" else "proc"
			if cc := misl.proc_cc_label(t); cc != "" {
				label = fmt.tprintf("%s :: proc \"%s\"(", prefix, cc)
			} else {
				label = fmt.tprintf("%s(", prefix)
			}
			if t.params != nil {
				for p, i in t.params.variables {
					if p == nil do continue
					pl := hover_proc_param_label(p)
					if pl == "" {
						pl = fmt.tprintf("arg%d: %s", i, misl.string_from_type(p.type) if p.type != nil else "?")
					}
					append(&params_info, lsp.Parameter_Information{label = pl})
					if i > 0 do label = fmt.tprintf("%s, %s", label, pl)
					else do label = fmt.tprintf("%s%s", label, pl)
				}
			}
			label = fmt.tprintf("%s)", label)
			if t.results != nil && len(t.results.variables) > 0 {
				if f := t.results.variables[0]; f != nil && f.type != nil {
					label = fmt.tprintf("%s -> %s", label, misl.string_from_type(f.type))
				}
			}
		case:
			// type constructor
			label = fmt.tprintf("%s(...)", misl.string_from_type(callee_type))
		}
		documentation = entity_leading_docs(callee_entity)
	}

	active := 0
	for arg in call.args {
		if offset_in_span(offset, arg.pos, arg.end) || offset >= arg.end.offset {
			active += 1
		} else {
			break
		}
	}
	if active > 0 && len(call.args) > 0 {
		// if past last arg start, clamp
		if active >= len(params_info) && len(params_info) > 0 {
			active = len(params_info) - 1
		} else if active > 0 {
			active -= 1 // count of completed args → index of current
		}
	}

	sigs := make([]lsp.Signature_Information, 1, context.temp_allocator)
	sigs[0] = {
		label = label,
		documentation = documentation,
		parameters = params_info[:],
	}
	return lsp.Signature_Help{
		signatures = sigs,
		activeSignature = 0,
		activeParameter = active,
	}
}
