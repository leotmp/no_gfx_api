package misl

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import vm "core:mem/virtual"

// Compile-time copy of oge/misl/core. `#load_directory` is relative to this file.
// `CORE_SOURCE_DIR` is the matching on-disk path so LSP go-to can open the real files.
CORE_SOURCE_DIR :: #directory + "core"
FMAG_FILENAME :: "fmag.misl"
core_embedded_files := #load_directory("core")

// `.misl` filenames baked into the compiler (`s2h.misl`, …). Used by LSP import completion.
core_embedded_misl_names :: proc(allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	for f in core_embedded_files {
		if strings.equal_fold(filepath.ext(f.name), ".misl") {
			append(&out, f.name)
		}
	}
	return out[:]
}

core_import_key :: proc(filename: string, allocator := context.temp_allocator) -> string {
	return fmt.tprintf("%s:%s", CORE_COLLECTION, filename)
}

core_file_system_path :: proc(filename: string, allocator := context.allocator) -> string {
	joined, _ := filepath.join({CORE_SOURCE_DIR, filename}, allocator)
	cleaned, _ := filepath.clean(joined, allocator)
	return cleaned
}

core_embedded_match :: proc(want: string) -> (name: string, data: []byte, ok: bool) {
	for f in core_embedded_files {
		if !strings.equal_fold(filepath.ext(f.name), ".misl") {
			continue
		}
		if f.name == want || strings.equal_fold(f.name, want) {
			return f.name, f.data, true
		}
	}
	return
}

core_embedded_lookup :: proc(rest: string) -> (name: string, data: []byte, ok: bool) {
	rest := strings.trim(rest, "/\\")
	if rest == "" ||
	   rest == BUILTIN_BIND_NAME ||
	   rest == DEBUG_BIND_NAME ||
	   rest == "builtin.misl" ||
	   rest == "debug.misl" {
		return
	}
	if name, data, ok = core_embedded_match(rest); ok {
		return
	}
	if !strings.equal_fold(filepath.ext(rest), ".misl") {
		return core_embedded_match(fmt.tprintf("%s.misl", rest))
	}
	return
}

core_embedded_from_session_key :: proc(key: string) -> (name: string, data: []byte, ok: bool) {
	prefix := CORE_COLLECTION + ":"
	if !strings.has_prefix(key, prefix) {
		return
	}
	rest := key[len(prefix):]
	if rest == BUILTIN_BIND_NAME || rest == DEBUG_BIND_NAME {
		return
	}
	return core_embedded_lookup(rest)
}

session_module_with_fullpath :: proc(session: ^Session, path: string) -> ^Module {
	if m, ok := session.modules[path]; ok {
		return m
	}
	for _, m in session.modules {
		if m != nil && m.fullpath != "" && strings.equal_fold(m.fullpath, path) {
			return m
		}
	}
	return nil
}

session_alias_module :: proc(session: ^Session, key: string, mod: ^Module) {
	if key == "" || mod == nil {
		return
	}
	if _, exists := session.modules[key]; exists {
		return
	}
	alloc := vm.arena_allocator(&session.arena)
	session.modules[strings.clone(key, alloc)] = mod
}

session_load_embedded_core :: proc(session: ^Session, filename: string, data: []byte, opts: Load_Options) -> ^Module {
	opts := opts
	opts.origin_path = core_file_system_path(filename, context.temp_allocator)
	opts.compiler_core = true
	mod := load_module_from_memory_opts(session, core_import_key(filename), string(data), from_file = false, opts = opts)
	if mod != nil {
		mod.compiler_core = true
	}
	return mod
}
