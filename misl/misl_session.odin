package misl

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import vm "core:mem/virtual"

CORE_COLLECTION :: "core"
BUILTIN_MODULE_PATH :: "core:builtin"
BUILTIN_BIND_NAME :: "builtin"
DEBUG_MODULE_PATH :: "core:debug"
DEBUG_BIND_NAME :: "debug"

module_is_compiler_core :: proc(m: ^Module) -> bool {
	return m != nil && (m.kind == .Builtin || m.compiler_core)
}

session_ensure_builtin :: proc(session: ^Session) {
	if session.builtin_module != nil do return
	context.allocator = vm.arena_allocator(&session.arena)

	init_core_types()
	context.allocator = vm.arena_allocator(&session.arena)

	filename, data, found := core_embedded_match("builtin.misl")
	fmt.assertf(found, "missing baked core:builtin.misl")

	disk_path := core_file_system_path(filename)
	mod := new(Module)
	mod.kind = .Builtin
	mod.session = session
	mod.fullpath = disk_path
	mod.from_file = false
	mod.compiler_core = true
	mod.code = strings.clone(string(data))

	session.builtin_module = mod
	session.modules[BUILTIN_MODULE_PATH] = mod
	session_alias_module(session, core_import_key(filename), mod)
	session_alias_module(session, disk_path, mod)

	if CORE_COLLECTION not_in session.collections {
		session.collections[CORE_COLLECTION] = ""
	}

	parser := default_parser()
	parse_module(&parser, mod)
	if parser.error_count != 0 {
		fmt.eprintfln("internal: core:builtin.misl parse failed")
	}
}

session_ensure_debug :: proc(session: ^Session, opts := Load_Options{}) {
	if session.debug_module != nil do return
	session_ensure_builtin(session)
	filename, data, found := core_embedded_match("debug.misl")
	fmt.assertf(found, "missing baked core:debug.misl")
	load_opts := opts
	load_opts.compiler_core = true
	mod := session_load_embedded_core(session, filename, data, load_opts)
	session.debug_module = mod
	session_alias_module(session, DEBUG_MODULE_PATH, mod)
}

import_default_bind_name :: proc(relpath: string) -> string {
	path := strings.trim(relpath, "\"")
	if path == BUILTIN_MODULE_PATH || path == BUILTIN_BIND_NAME {
		return BUILTIN_BIND_NAME
	}
	if path == DEBUG_MODULE_PATH || path == DEBUG_BIND_NAME {
		return DEBUG_BIND_NAME
	}
	rest := path
	if colon := strings.index_byte(path, ':'); colon >= 0 {
		col := path[:colon]
		if !(len(col) == 1 && ((col[0] >= 'A' && col[0] <= 'Z') || (col[0] >= 'a' && col[0] <= 'z'))) {
			rest = path[colon + 1:]
		}
	}
	stem := filepath.stem(rest)
	if stem == "" do return rest
	return stem
}

// Parse "lib:foo.misl" → (collection="lib", rest="foo.misl"); no colon → ("", path).
// Single-letter "C:..." is treated as a Windows drive path, not a collection.
split_collection_path :: proc(path: string) -> (collection, rest: string) {
	path := strings.trim(path, "\"")
	colon := strings.index_byte(path, ':')
	if colon < 0 {
		return "", path
	}
	col := path[:colon]
	if len(col) == 1 {
		c := col[0]
		if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') {
			return "", path
		}
	}
	return col, path[colon + 1:]
}

resolve_import_key :: proc(session: ^Session, importer: ^Module, relpath_tok: string) -> (key: string, err: string) {
	collection, rest := split_collection_path(relpath_tok)

	if collection != "" {
		if collection not_in session.collections {
			return "", fmt.tprintf("unknown collection '%s'", collection)
		}
		if collection == CORE_COLLECTION && (rest == BUILTIN_BIND_NAME || rest == "builtin.misl") {
			return BUILTIN_MODULE_PATH, ""
		}
		if collection == CORE_COLLECTION && (rest == DEBUG_BIND_NAME || rest == "debug.misl") {
			return DEBUG_MODULE_PATH, ""
		}
		if collection == CORE_COLLECTION {
			if filename, _, found := core_embedded_lookup(rest); found {
				return core_import_key(filename), ""
			}
		}
		root := session.collections[collection]
		if root == "" {
			if collection == CORE_COLLECTION {
				return "", fmt.tprintf("unknown core module '%s'", rest)
			}
			return "", fmt.tprintf("collection '%s' has no filesystem root", collection)
		}
		joined, _ := filepath.join({root, rest}, context.temp_allocator)
		cleaned, _ := filepath.clean(joined, context.temp_allocator)
		return cleaned, ""
	}

	if importer.from_file {
		dir := filepath.dir(importer.fullpath)
		joined, _ := filepath.join({dir, rest}, context.temp_allocator)
		cleaned, _ := filepath.clean(joined, context.temp_allocator)
		return cleaned, ""
	}
	return rest, ""
}

import_parse_opts :: proc(session: ^Session, err: Error_Handler, warn: Warning_Handler) -> Load_Options {
	return Load_Options{
		soft_fail = true,
		err = err,
		warn = warn,
	}
}

session_load_parsed_dep :: proc(session: ^Session, importer: ^Module, rel: string, opts: Load_Options) -> (dep: ^Module, key: string, err: string) {
	resolved, rerr := resolve_import_key(session, importer, rel)
	key = resolved
	if rerr != "" {
		return nil, key, rerr
	}
	if key == BUILTIN_MODULE_PATH {
		session_ensure_builtin(session)
		return session.builtin_module, key, ""
	}
	if key == DEBUG_MODULE_PATH {
		debug_opts := opts
		debug_opts.compiler_core = true
		session_ensure_debug(session, debug_opts)
		return session.debug_module, key, ""
	}
	if m, ok := session.modules[key]; ok {
		if m.loading {
			return nil, key, fmt.tprintf("cyclic import involving '%s'", key)
		}
		return m, key, ""
	}
	if filename, data, found := core_embedded_from_session_key(key); found {
		dep = session_load_embedded_core(session, filename, data, opts)
		if dep == nil {
			return nil, key, fmt.tprintf("failed to load imported module '%s'", key)
		}
		if dep.loading {
			return nil, key, fmt.tprintf("cyclic import involving '%s'", key)
		}
		return dep, key, ""
	}
	collection, _ := split_collection_path(rel)
	can_load_file := importer.from_file || collection != ""
	if !can_load_file {
		return nil, key, fmt.tprintf("module '%s' is not loaded in the session", key)
	}
	dep = load_module_from_file_opts(session, key, opts)
	if dep == nil {
		return nil, key, fmt.tprintf("failed to load imported module '%s'", key)
	}
	return dep, key, ""
}

parse_nested_imports :: proc(session: ^Session, module: ^Module, opts: Load_Options) {
	if session == nil || module == nil do return
	if module.kind != .Normal do return
	load_opts := opts
	load_opts.soft_fail = true
	for imp in module.imports {
		rel := imp.relpath.text
		dep, key, err := session_load_parsed_dep(session, module, rel, load_opts)
		if err != "" {
			if load_opts.err != nil {
				load_opts.err(imp.relpath.pos, "%s", err)
			} else {
				fmt.eprintfln("%s", err)
			}
			continue
		}
		imp.fullpath = key
		_ = dep
	}
}

check_module_imports :: proc(c: ^Checker, session: ^Session) {
	module := c.module
	if module.kind != .Normal do return
	if session == nil {
		check_err(c, module.pos, "internal: checker session is nil")
		return
	}

	opts := import_parse_opts(session, c.err, c.warn)
	check_opts := c.check_opts
	check_opts.soft_fail = true
	check_opts.err = c.err
	check_opts.warn = c.warn

	for imp in module.imports {
		rel := imp.relpath.text
		parsed, key, rerr := session_load_parsed_dep(session, module, rel, opts)
		if rerr != "" {
			check_err(c, imp.relpath.pos, "%s", rerr)
			continue
		}

		dep: ^Module
		if key == BUILTIN_MODULE_PATH {
			dep = c.builtin_instance
			if dep == nil {
				dep = check(parsed, c.check_target, check_opts)
			}
		} else {
			dep = check(parsed, c.check_target, check_opts)
		}
		if dep == nil {
			check_err(c, imp.relpath.pos, "failed to load imported module '%s'", key)
			continue
		}

		bind := imp.name.text
		if bind == "" {
			bind = import_default_bind_name(rel)
		}
		if scope_lookup_current(module.scope, bind) != nil {
			pos := imp.name.pos if imp.name.text != "" else imp.pos
			check_err(c, pos, "redeclaration of import name '%s'", bind)
			continue
		}

		e := new_entity(.Import, module.scope, imp.pos, bind, nil)
		e.imported_module = dep
		e.state = .Resolved
		e.module = module
		scope_insert(module.scope, e)
		imp.fullpath = key
		append(&module.imports_resolved, dep)
	}
}
