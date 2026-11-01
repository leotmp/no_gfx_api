package misl_lsp

import "oge:misl"
import "./lsp"

type_definition_named_type :: proc(type: ^misl.Type) -> ^misl.Type {
	type := type
	for type != nil {
		if type.name != "" do return type
		#partial switch t in type.derived {
		case ^misl.Type_Pointer:
			type = t.elem
		case ^misl.Type_Multi_Pointer:
			type = t.elem
		case ^misl.Type_Array:
			type = t.elem
		case ^misl.Type_Slice:
			type = t.elem
		case:
			return type
		}
	}
	return nil
}

type_definition_entity :: proc(ws: ^Workspace, type: ^misl.Type, current: ^misl.Module) -> ^misl.Entity {
	if type == nil do return nil
	search_mod :: proc(mod: ^misl.Module, type: ^misl.Type) -> (hit: ^misl.Entity, fallback: ^misl.Entity) {
		if mod == nil do return
		for s := mod.scope; s != nil; s = s.outer {
			for _, e in s.entities {
				if e == nil || e.kind != .Type_Name do continue
				if e.type == type do return e, fallback
				if fallback == nil && type.name != "" && e.name == type.name {
					fallback = e
				}
			}
		}
		return
	}
	if e, fb := search_mod(current, type); e != nil {
		return e
	} else if fb != nil {
		return fb
	}
	if ws == nil || ws.session == nil do return nil
	fallback: ^misl.Entity
	for _, mod in ws.session.check_cache {
		e, fb := search_mod(mod, type)
		if e != nil do return e
		if fallback == nil do fallback = fb
	}
	for _, mod in ws.session.modules {
		e, fb := search_mod(mod, type)
		if e != nil do return e
		if fallback == nil do fallback = fb
	}
	return fallback
}

type_definition_at :: proc(ws: ^Workspace, params: lsp.Definition_Params, allocator := context.temp_allocator) -> []lsp.Location {
	doc := ws.docs[params.text_document.uri] or_else nil
	if doc == nil do return nil
	offset, ok := offset_from_position(doc.text, params.position)
	if !ok do return nil
	mod := workspace_module_for_uri(ws, params.text_document.uri, offset)
	if mod == nil do return nil
	hit := ast_find_at_offset(mod, offset)

	type: ^misl.Type
	if hit.ident != nil {
		if hit.ident.entity != nil {
			type = hit.ident.entity.type
		}
		if type == nil {
			type = hit.ident.tav.type
		}
	} else if hit.expr != nil {
		type = hit.expr.tav.type
	} else if hit.entity != nil {
		type = hit.entity.type
	}
	type = type_definition_named_type(type)
	entity := type_definition_entity(ws, type, mod)
	if entity == nil do return nil

	target_mod := entity.module
	if target_mod == nil && ws.session != nil {
		for _, candidate in ws.session.modules {
			if candidate == nil || candidate.scope == nil do continue
			if found := candidate.scope.entities[entity.name] or_else nil; found == entity {
				target_mod = candidate
				break
			}
		}
	}

	uri := params.text_document.uri
	text := doc.text
	if target_mod != nil && target_mod.fullpath != "" {
		if target_doc := workspace_doc_for_path(ws, target_mod.fullpath); target_doc != nil {
			uri = target_doc.uri
			text = target_doc.text
		} else {
			uri = lsp.filepath_to_uri(target_mod.fullpath, allocator)
			text = target_mod.code
		}
	}

	result := make([]lsp.Location, 1, allocator)
	result[0] = {
		uri = uri,
		range = token_pos_to_range(entity.pos, max(len(entity.name), 1), text),
	}
	return result
}
