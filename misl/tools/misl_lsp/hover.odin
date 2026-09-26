package misl_lsp

import "core:fmt"
import "core:strings"
import "oge:misl"
import "./lsp"

hover_at :: proc(ws: ^Workspace, params: lsp.Hover_Params) -> Maybe(lsp.Hover) {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil do return nil
	offset, ok := offset_from_position(doc.text, params.position)
	if !ok do return nil
	mod := workspace_module_for_uri(ws, params.text_document.uri, offset)
	if mod == nil do return nil

	hit := ast_find_at_offset(mod, offset)
	if hit.ident == nil do return nil

	// Prefer SV_* documentation when hovering a semantic tag (usually no entity).
	if hit.ident.entity == nil {
		if md, sem_ok := hover_semantic_markdown(hit.ident.name); sem_ok {
			return lsp.Hover{
				contents = {kind = "markdown", value = md},
				range = ident_range(hit.ident, doc.text),
			}
		}
	}

	value := entity_hover_markdown(hit.ident.entity, hit.ident, language_reference_uri(ws))
	if value == "" do return nil

	return lsp.Hover{
		contents = {kind = "markdown", value = value},
		range = ident_range(hit.ident, doc.text),
	}
}

hover_semantic_markdown :: proc(name: string) -> (string, bool) {
	sem := misl.semantic_from_string(name)
	if sem == .None || sem == .Custom do return "", false
	infos := misl.semantic_names
	info := infos[sem]
	if info.name == "" do return "", false
	if info.docs == "" {
		return fmt.tprintf("```misl\n%s\n```", info.name), true
	}
	return fmt.tprintf("```misl\n%s\n```\n---\n%s", info.name, info.docs), true
}

// OLS-style symbol line(s) inside a ```misl fence (no English kind prefix).
hover_symbol_info :: proc(ident: ^misl.Ident) -> string {
	if ident == nil do return ""

	e := ident.entity
	name := ident.name
	if e != nil && e.name != "" {
		name = e.name
	}

	if e != nil {
		#partial switch e.kind {
		case .Type_Name:
			if e.type != nil {
				return hover_type_definition(name, e.type)
			}
			return fmt.tprintf("%s :: typeid", name)

		case .Constant:
			if misl.entity_is_poly_const(e) {
				type_str := misl.string_from_type(e.type) if e.type != nil else ""
				if type_str != "" {
					return fmt.tprintf("$%s: %s", name, type_str)
				}
				return fmt.tprintf("$%s", name)
			}
			// Enum member: `E: .A` / `E: .A = 1`
			if e.type != nil {
				if _, is_enum := e.type.derived.(^misl.Type_Enum); is_enum {
					type_name := e.type.name if e.type.name != "" else misl.string_from_type(e.type)
					if val, has := exact_value_string(e.value); has {
						return fmt.tprintf("%s: .%s = %s", type_name, name, val)
					}
					return fmt.tprintf("%s: .%s", type_name, name)
				}
			}
			type_str := misl.string_from_type(e.type) if e.type != nil else ""
			if val, has := exact_value_string(e.value); has {
				if type_str != "" {
					return fmt.tprintf("%s :: %s = %s", name, type_str, val)
				}
				return fmt.tprintf("%s :: %s", name, val)
			}
			if type_str != "" {
				return fmt.tprintf("%s :: %s", name, type_str)
			}
			return name

		case .Variable, .Dummy:
			if .Param in e.flags {
				return hover_proc_param_label(e)
			}
			type_str := misl.string_from_type(e.type) if e.type != nil else ""
			if type_str != "" {
				return fmt.tprintf("%s: %s", name, type_str)
			}
			return name

		case .Procedure, .Entry, .Builtin:
			// Note: entity_hover_markdown() intercepts .Builtin before calling here and
			// uses misl.builtin_sig_docs_markdown() instead (generic "genType" signature +
			// hand-written docs). This branch still backs non-hover callers (e.g.
			// hover_type_definition's Type_Proc case) and any .Builtin entity with no
			// resolved builtin_id.
			if e.type != nil {
				return fmt.tprintf("%s :: %s", name, hover_proc_signature(e.type))
			}
			return fmt.tprintf("%s :: proc", name)

		case .Pipeline:
			return fmt.tprintf("%s :: pipeline", name)

		case .Proc_Group:
			b: strings.Builder
			strings.builder_init(&b, context.temp_allocator)
			fmt.sbprintf(&b, "%s :: proc {{", name)
			if e.proc_group_members != nil {
				for m, i in e.proc_group_members {
					if m == nil do continue
					if i > 0 do strings.write_string(&b, ", ")
					strings.write_string(&b, m.name)
				}
			}
			strings.write_string(&b, "}")
			return strings.to_string(b)

		case .Import:
			return fmt.tprintf("%s :: import", name)

		case .Label:
			return fmt.tprintf("%s:", name)
		}
	}

	if ident.tav.type != nil {
		return fmt.tprintf("%s: %s", name, misl.string_from_type(ident.tav.type))
	}
	return name
}

hover_type_definition :: proc(name: string, type: ^misl.Type) -> string {
	if type == nil do return name
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)

	#partial switch t in type.derived {
	case ^misl.Type_Struct:
		fmt.sbprintf(&b, "%s :: ", name if name != "" else (type.name if type.name != "" else "_"))
		write_struct_definition(&b, t)
		return strings.to_string(b)
	case ^misl.Type_Enum:
		fmt.sbprintf(&b, "%s :: ", name if name != "" else (type.name if type.name != "" else "_"))
		write_enum_definition(&b, t)
		return strings.to_string(b)
	case ^misl.Type_Bit_Set:
		fmt.sbprintf(&b, "%s :: %s", name if name != "" else type.name, misl.string_from_type(type))
		return strings.to_string(b)
	case ^misl.Type_Proc:
		fmt.sbprintf(&b, "%s :: %s", name, hover_proc_signature(type))
		return strings.to_string(b)
	}

	type_str := misl.string_from_type(type)
	if type_str != "" && type_str != name {
		return fmt.tprintf("%s :: %s", name, type_str)
	}
	return fmt.tprintf("%s :: typeid", name)
}

write_struct_definition :: proc(b: ^strings.Builder, st: ^misl.Type_Struct) {
	strings.write_string(b, "struct")
	if st.fields == nil || len(st.fields.variables) == 0 {
		strings.write_string(b, " {}")
		return
	}

	fields := st.fields.variables[:]
	longest := 0
	for f in fields {
		if f == nil do continue
		if len(f.name) > longest {
			longest = len(f.name)
		}
	}

	sem_names := misl.semantic_names
	strings.write_string(b, " {\n")
	for f in fields {
		if f == nil || f.name == "" do continue
		strings.write_string(b, "\t")
		write_entity_hash_prefixes(b, f)
		fmt.sbprintf(b, "%s:", f.name)
		pad := longest - len(f.name) + 1
		for _ in 0 ..< pad {
			strings.write_byte(b, ' ')
		}
		strings.write_string(b, misl.string_from_type(f.type))
		if f.semantic != .None && f.semantic != .Custom {
			fmt.sbprintf(b, " | %s", sem_names[f.semantic].name)
		} else if f.semantic == .Custom && f.semantic_name != "" {
			fmt.sbprintf(b, " | %s", f.semantic_name)
		}
		strings.write_string(b, ",\n")
	}
	strings.write_string(b, "}")
}

write_enum_definition :: proc(b: ^strings.Builder, et: ^misl.Type_Enum) {
	strings.write_string(b, "enum")
	if et.base_type != nil {
		fmt.sbprintf(b, " %s", misl.string_from_type(et.base_type))
	}
	if len(et.fields) == 0 {
		strings.write_string(b, " {}")
		return
	}

	longest := 0
	for f in et.fields {
		if f == nil do continue
		if len(f.name) > longest {
			longest = len(f.name)
		}
	}

	strings.write_string(b, " {\n")
	for f in et.fields {
		if f == nil || f.name == "" do continue
		strings.write_string(b, "\t")
		strings.write_string(b, f.name)
		// Always show discriminant when present — matches source-like OLS hover.
		if val, has := exact_value_string(f.value); has {
			pad := longest - len(f.name) + 1
			for _ in 0 ..< pad {
				strings.write_byte(b, ' ')
			}
			fmt.sbprintf(b, "= %s", val)
		}
		strings.write_string(b, ",\n")
	}
	strings.write_string(b, "}")
}

// Specialized calls rebind the callee ident to a clone. Hover/signature must
// show the generic `$name` signature, not the specialized `name: T` view.
// Param hash flags (`#ref`, interpolation tags) live on the Entity, not the
// Type — `write_hover_proc_param` is the single printer for those.
proc_type_for_display :: proc(type: ^misl.Type) -> (^misl.Type_Proc, bool) {
	if type == nil do return nil, false
	pt, ok := type.derived.(^misl.Type_Proc)
	if !ok do return nil, false
	if pt.is_poly_specialized && pt.poly_origin != nil && pt.poly_origin.type != nil {
		if orig, orig_ok := pt.poly_origin.type.derived.(^misl.Type_Proc); orig_ok {
			return orig, true
		}
	}
	return pt, true
}

hover_proc_signature :: proc(type: ^misl.Type) -> string {
	pt, ok := proc_type_for_display(type)
	if !ok do return "proc"

	sem_names := misl.semantic_names
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, "proc")
	if cc := misl.proc_cc_label(pt); cc != "" {
		fmt.sbprintf(&b, " \"%s\"", cc)
	}
	strings.write_byte(&b, '(')
	if pt.params != nil {
		for f, i in pt.params.variables {
			if f == nil do continue
			if i > 0 do strings.write_string(&b, ", ")
			write_hover_proc_param(&b, f)
		}
	}
	strings.write_byte(&b, ')')
	if pt.results != nil && len(pt.results.variables) > 0 {
		strings.write_string(&b, " -> ")
		if len(pt.results.variables) == 1 {
			f := pt.results.variables[0]
			if f != nil {
				if f.name != "" {
					fmt.sbprintf(&b, "(%s: %s", f.name, misl.string_from_type(f.type))
					if f.semantic != .None && f.semantic != .Custom {
						fmt.sbprintf(&b, " | %s", sem_names[f.semantic].name)
					}
					strings.write_byte(&b, ')')
				} else {
					strings.write_string(&b, misl.string_from_type(f.type))
				}
			}
		} else {
			strings.write_byte(&b, '(')
			for f, i in pt.results.variables {
				if f == nil do continue
				if i > 0 do strings.write_string(&b, ", ")
				fmt.sbprintf(&b, "%s: %s", f.name, misl.string_from_type(f.type))
				if f.semantic != .None && f.semantic != .Custom {
					fmt.sbprintf(&b, " | %s", sem_names[f.semantic].name)
				}
			}
			strings.write_byte(&b, ')')
		}
	}
	return strings.to_string(b)
}

hover_param_name :: proc(f: ^misl.Entity) -> string {
	if f == nil do return ""
	if misl.entity_is_poly_const(f) || (f.kind == .Constant && .Param in f.flags) {
		return fmt.tprintf("$%s", f.name)
	}
	return f.name
}

// Hash tags the checker copies from Field.flags onto the Entity. Source order
// is tags, then `$name` / name, then `: type`, then `| Semantic`.
write_entity_hash_prefixes :: proc(b: ^strings.Builder, f: ^misl.Entity) {
	if f == nil do return
	if .Ref in f.flags do strings.write_string(b, "#ref ")
	if .Flat in f.flags do strings.write_string(b, "#flat ")
	if .Noperspective in f.flags do strings.write_string(b, "#noperspective ")
	if .Centroid in f.flags do strings.write_string(b, "#centroid ")
}

write_hover_proc_param :: proc(b: ^strings.Builder, f: ^misl.Entity) {
	if f == nil do return
	write_entity_hash_prefixes(b, f)
	fmt.sbprintf(b, "%s: %s", hover_param_name(f), misl.string_from_type(f.type))
	if f.semantic != .None && f.semantic != .Custom {
		sem_names := misl.semantic_names
		fmt.sbprintf(b, " | %s", sem_names[f.semantic].name)
	} else if f.semantic == .Custom && f.semantic_name != "" {
		fmt.sbprintf(b, " | %s", f.semantic_name)
	}
}

hover_proc_param_label :: proc(f: ^misl.Entity) -> string {
	if f == nil do return ""
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	write_hover_proc_param(&b, f)
	return strings.to_string(b)
}

exact_value_string :: proc(v: misl.Exact_Value) -> (string, bool) {
	switch val in v {
	case i128:
		return fmt.tprintf("%d", val), true
	case f64:
		return fmt.tprintf("%v", val), true
	case bool:
		return "true" if val else "false", true
	case string:
		return fmt.tprintf("%q", val), true
	case ^misl.Expr:
		return "<compound>", true
	case ^misl.Entity:
		if val != nil && val.name != "" {
			return val.name, true
		}
		return "", false
	case quaternion256, complex128:
		return "", false
	}
	return "", false
}
