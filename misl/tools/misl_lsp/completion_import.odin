package misl_lsp

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "oge:misl"
import "./lsp"

Import_Path_At :: struct {
	prefix:     string, // typed path up to the cursor
	path_start: int,    // byte offset after opening `"`
	path_end:   int,    // byte offset of closing `"` or end of line
}

import_ident_start :: proc(c: u8) -> bool {
	return c == '_' ||
		(c >= 'a' && c <= 'z') ||
		(c >= 'A' && c <= 'Z')
}

import_ident_continue :: proc(c: u8) -> bool {
	return import_ident_start(c) || (c >= '0' && c <= '9')
}

// Cursor is inside `import [name] "…"`. Works with an unclosed quote.
import_path_at :: proc(text: string, offset: int) -> (info: Import_Path_At, ok: bool) {
	if offset < 0 || offset > len(text) do return
	line_start := offset
	for line_start > 0 && text[line_start - 1] != '\n' && text[line_start - 1] != '\r' {
		line_start -= 1
	}
	line_end := offset
	for line_end < len(text) && text[line_end] != '\n' && text[line_end] != '\r' {
		line_end += 1
	}
	line := text[line_start:line_end]
	i := 0
	for i < len(line) && (line[i] == ' ' || line[i] == '\t') {
		i += 1
	}
	if i + 6 > len(line) || line[i:i + 6] != "import" {
		return
	}
	i += 6
	if i < len(line) && import_ident_continue(line[i]) {
		return
	}
	for i < len(line) && (line[i] == ' ' || line[i] == '\t') {
		i += 1
	}
	if i < len(line) && import_ident_start(line[i]) {
		i += 1
		for i < len(line) && import_ident_continue(line[i]) {
			i += 1
		}
		for i < len(line) && (line[i] == ' ' || line[i] == '\t') {
			i += 1
		}
	}
	if i >= len(line) || line[i] != '"' {
		return
	}
	path_start := line_start + i + 1
	close := -1
	for j := i + 1; j < len(line); j += 1 {
		if line[j] == '"' {
			close = line_start + j
			break
		}
	}
	path_end := close if close >= 0 else line_end
	if offset < path_start {
		return
	}
	if close >= 0 && offset >= close {
		return
	}
	if offset > path_end {
		return
	}
	info = {
		prefix = text[path_start:offset],
		path_start = path_start,
		path_end = path_end,
	}
	return info, true
}

import_split_collection :: proc(path: string) -> (collection, rest: string, is_collection: bool) {
	path, _ := strings.replace_all(path, "\\", "/", context.temp_allocator)
	colon := strings.index_byte(path, ':')
	if colon <= 0 {
		return "", path, false
	}
	col := path[:colon]
	if len(col) == 1 {
		c := col[0]
		if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') {
			return "", path, false
		}
	}
	return col, path[colon + 1:], true
}

import_dir_leaf :: proc(path: string) -> (dir, leaf: string) {
	path, _ := strings.replace_all(path, "\\", "/", context.temp_allocator)
	if path == "" {
		return "", ""
	}
	if strings.has_suffix(path, "/") {
		inner := path[:len(path) - 1]
		return inner, ""
	}
	if slash := strings.last_index(path, "/"); slash >= 0 {
		return path[:slash], path[slash + 1:]
	}
	return "", path
}

import_trigger_suggest :: proc() -> lsp.Command {
	return {title = "Suggest", command = "editor.action.triggerSuggest"}
}

append_import_item :: proc(
	items: ^[dynamic]lsp.Completion_Item,
	seen: ^map[string]bool,
	insert: string,
	prefix: string,
	kind: lsp.Completion_Item_Kind,
	detail: string,
	replace: lsp.Range,
	retrigger: bool,
) {
	if insert == "" || insert in seen^ do return
	if prefix != "" && !strings.has_prefix(insert, prefix) && !strings.has_prefix(strings.to_lower(insert), strings.to_lower(prefix)) {
		return
	}
	seen^[insert] = true
	item := lsp.Completion_Item{
		label = insert,
		kind = kind,
		detail = detail,
		filterText = insert,
		textEdit = lsp.Text_Edit{range = replace, new_text = insert},
	}
	if retrigger {
		item.command = import_trigger_suggest()
	}
	append(items, item)
}

append_fs_import_entries :: proc(
	items: ^[dynamic]lsp.Completion_Item,
	seen: ^map[string]bool,
	fs_dir: string,
	head: string,
	prefix: string,
	replace: lsp.Range,
	skip_path: string,
) {
	if fs_dir == "" || !os.is_directory(fs_dir) do return
	entries, err := os.read_directory_by_path(fs_dir, -1, context.temp_allocator)
	if err != nil do return
	for fi in entries {
		name := fi.name
		if name == "" || name == "." || name == ".." || name[0] == '.' {
			continue
		}
		is_dir := os.is_directory(fi.fullpath)
		if !is_dir && !strings.equal_fold(filepath.ext(name), ".misl") {
			continue
		}
		insert := fmt.tprintf("%s%s%s", head, name, "/" if is_dir else "")
		if skip_path != "" && !is_dir {
			full, _ := filepath.join({fs_dir, name}, context.temp_allocator)
			cleaned, _ := filepath.clean(full, context.temp_allocator)
			if strings.equal_fold(cleaned, skip_path) {
				continue
			}
		}
		kind: lsp.Completion_Item_Kind = .Folder if is_dir else .File
		detail := "folder" if is_dir else "module"
		append_import_item(items, seen, insert, prefix, kind, detail, replace, is_dir)
	}
}

append_import_path_completions :: proc(
	items: ^[dynamic]lsp.Completion_Item,
	ws: ^Workspace,
	doc: ^Document,
	offset: int,
) -> bool {
	info, ok := import_path_at(doc.text, offset)
	if !ok do return false

	replace := lsp.Range{
		start = position_from_offset(doc.text, info.path_start),
		end = position_from_offset(doc.text, info.path_end),
	}
	seen := make(map[string]bool, context.temp_allocator)
	prefix, _ := strings.replace_all(info.prefix, "\\", "/", context.temp_allocator)
	collection, rest, is_collection := import_split_collection(prefix)

	if is_collection {
		dir, _ := import_dir_leaf(rest)
		head := fmt.tprintf("%s:", collection)
		if dir != "" {
			head = fmt.tprintf("%s:%s/", collection, dir)
		}
		if collection == misl.CORE_COLLECTION && dir == "" {
			append_import_item(
				items, &seen, misl.CORE_COLLECTION + ":" + misl.BUILTIN_BIND_NAME,
				prefix, .Module, "core", replace, false,
			)
			append_import_item(
				items, &seen, misl.CORE_COLLECTION + ":" + misl.DEBUG_BIND_NAME,
				prefix, .Module, "core", replace, false,
			)
			append_import_item(
				items, &seen, misl.CORE_COLLECTION + ":wave",
				prefix, .Module, "core", replace, false,
			)
			for name in misl.core_embedded_misl_names() {
				if name == "builtin.misl" || name == "debug.misl" || name == "wave.misl" {
					continue
				}
				append_import_item(
					items, &seen, fmt.tprintf("%s:%s", misl.CORE_COLLECTION, name),
					prefix, .File, "core", replace, false,
				)
			}
		}
		root := ws.collections[collection] or_else ""
		if root != "" {
			fs_dir := root
			if dir != "" {
				fs_dir, _ = filepath.join({root, dir}, context.temp_allocator)
			}
			append_fs_import_entries(items, &seen, fs_dir, head, prefix, replace, "")
		}
		return true
	}

	if !strings.contains(prefix, "/") {
		append_import_item(items, &seen, misl.CORE_COLLECTION + ":", prefix, .Module, "collection", replace, true)
		for name, path in ws.collections {
			if name == "" || name == misl.CORE_COLLECTION || path == "" do continue
			append_import_item(items, &seen, fmt.tprintf("%s:", name), prefix, .Module, "collection", replace, true)
		}
	}

	file_dir := filepath.dir(doc.path)
	dir, _ := import_dir_leaf(prefix)
	head := ""
	if dir != "" {
		head = fmt.tprintf("%s/", dir)
	}
	fs_dir := file_dir
	if dir != "" {
		fs_dir, _ = filepath.join({file_dir, dir}, context.temp_allocator)
	}
	skip := ""
	if doc.path != "" {
		skip, _ = filepath.clean(doc.path, context.temp_allocator)
	}
	append_fs_import_entries(items, &seen, fs_dir, head, prefix, replace, skip)
	return true
}
