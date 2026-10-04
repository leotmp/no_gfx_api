package misl_lsp

import "core:fmt"
import "oge:misl"
import "./lsp"

entity_symbol_detail :: proc(e: ^misl.Entity) -> string {
	if e == nil || e.type == nil do return ""
	pt, ok := e.type.derived.(^misl.Type_Proc)
	if !ok do return ""
	if cc := misl.proc_cc_label(pt); cc != "" {
		return fmt.tprintf("proc \"%s\"", cc)
	}
	return ""
}

entity_symbol_kind :: proc(e: ^misl.Entity) -> lsp.Symbol_Kind {
	#partial switch e.kind {
	case .Procedure, .Entry, .Builtin, .Proc_Group:
		return .Function
	case .Type_Name:
		if e.type != nil {
			#partial switch t in e.type.derived {
			case ^misl.Type_Struct: return .Struct
			case ^misl.Type_Enum:   return .Enum
			}
		}
		return .Class
	case .Constant:
		return .Constant
	case .Variable:
		return .Variable
	case .Import:
		return .Module
	}
	return .Variable
}

document_symbols :: proc(ws: ^Workspace, params: lsp.Document_Symbol_Params, allocator := context.temp_allocator) -> []lsp.Document_Symbol {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil do return nil
	mod := workspace_module_for_uri(ws, params.text_document.uri)
	if mod == nil do return nil

	syms := make([dynamic]lsp.Document_Symbol, allocator)

	entity_children :: proc(e: ^misl.Entity, text: string) -> []lsp.Document_Symbol {
		if e == nil || e.kind != .Type_Name || e.type == nil do return nil
		children := make([dynamic]lsp.Document_Symbol, context.temp_allocator)
		append_child :: proc(children: ^[dynamic]lsp.Document_Symbol, field: ^misl.Entity, kind: lsp.Symbol_Kind, text: string) {
			if field == nil || field.name == "" || field.name == "_" do return
			r := token_pos_to_range(field.pos, max(len(field.name), 1), text)
			append(children, lsp.Document_Symbol{
				name = field.name,
				kind = kind,
				range = r,
				selection_range = r,
			})
		}
		#partial switch type in e.type.derived {
		case ^misl.Type_Struct:
			if type.fields != nil {
				for field in type.fields.variables {
					append_child(&children, field, .Field, text)
				}
			}
		case ^misl.Type_Enum:
			for field in type.fields {
				append_child(&children, field, .Enum_Member, text)
			}
		}
		return children[:]
	}

	add_entity :: proc(syms: ^[dynamic]lsp.Document_Symbol, e: ^misl.Entity, text: string) {
		if e == nil || e.name == "" || e.name[0] == '_' && len(e.name) > 1 do return
		#partial switch e.kind {
		case .Nil, .Label: return
		}
		r := token_pos_to_range(e.pos, max(len(e.name), 1), text)
		append(syms, lsp.Document_Symbol{
			name = e.name,
			detail = entity_symbol_detail(e),
			kind = entity_symbol_kind(e),
			range = r,
			selection_range = r,
			children = entity_children(e, text),
		})
	}

	if mod.scope != nil {
		for _, e in mod.scope.entities {
			add_entity(&syms, e, doc.text)
		}
	}
	for e in mod.definitions {
		add_entity(&syms, e, doc.text)
	}
	for pe in mod.entries {
		add_entity(&syms, pe.entity, doc.text)
	}

	return syms[:]
}

workspace_symbols :: proc(ws: ^Workspace, params: lsp.Workspace_Symbol_Params, allocator := context.temp_allocator) -> []lsp.Workspace_Symbol {
	workspace_flush(ws)
	query := params.query
	out := make([dynamic]lsp.Workspace_Symbol, allocator)
	if ws.session == nil do return out[:]

	seen := make(map[string]bool, context.temp_allocator)
	add_from_module :: proc(mod: ^misl.Module, query: string, ws: ^Workspace, out: ^[dynamic]lsp.Workspace_Symbol, seen: ^map[string]bool) {
		if mod == nil || mod.scope == nil || mod.kind == .Builtin do return
		path := mod.fullpath
		if path == "" do return
		doc := workspace_doc_for_path(ws, path)
		uri := lsp.filepath_to_uri(path, context.temp_allocator)
		text := mod.code
		if doc != nil {
			uri = doc.uri
			text = doc.text
		}
		for name, e in mod.scope.entities {
			if query != "" && !contains_ci(name, query) do continue
			if e == nil || e.name == "" do continue
			key := fmt.tprintf("%s\x00%s", path, name)
			if seen[key] do continue
			seen[key] = true
			append(out, lsp.Workspace_Symbol{
				name = e.name,
				kind = entity_symbol_kind(e),
				location = {
					uri = uri,
					range = token_pos_to_range(e.pos, max(len(e.name), 1), text),
				},
			})
		}
	}

	for _, inst in ws.session.check_cache {
		add_from_module(inst, query, ws, &out, &seen)
	}
	for _, parsed in ws.modules_by_path {
		inst := workspace_check_parsed(ws, parsed, ws.target)
		add_from_module(inst, query, ws, &out, &seen)
	}
	return out[:]
}

contains_ci :: proc(s, sub: string) -> bool {
	if sub == "" do return true
	// simple case-sensitive contains for v1
	for i := 0; i + len(sub) <= len(s); i += 1 {
		if s[i:i+len(sub)] == sub do return true
	}
	return false
}
