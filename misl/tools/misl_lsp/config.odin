package misl_lsp

import "core:encoding/json"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "./lsp"

LSP_CONFIG_FILENAME :: "misl.lsp.json"
LEGACY_CONFIG_FILENAME :: "misl.json"

Lsp_Features :: struct {
	hover:              bool,
	definition:         bool,
	type_definition:    bool,
	references:         bool,
	document_highlight: bool,
	document_symbol:    bool,
	workspace_symbol:   bool,
	rename:             bool,
	completion:         bool,
	signature_help:     bool,
	semantic_tokens:    bool,
	inlay_hints:        bool,
	code_actions:       bool,
	code_lens:          bool,
	fmag_preview:       bool,
	spirv_preview:      bool,
}

Lsp_Config :: struct {
	server_path: string,
	features:    Lsp_Features,
}

default_lsp_features :: proc() -> Lsp_Features {
	return Lsp_Features{
		hover = true,
		definition = true,
		type_definition = true,
		references = true,
		document_highlight = true,
		document_symbol = true,
		workspace_symbol = true,
		rename = true,
		completion = true,
		signature_help = true,
		semantic_tokens = true,
		inlay_hints = true,
		code_actions = true,
		code_lens = true,
		fmag_preview = true,
		spirv_preview = true,
	}
}

default_lsp_config :: proc() -> Lsp_Config {
	return Lsp_Config{
		server_path = "",
		features = default_lsp_features(),
	}
}

clear_workspace_collections :: proc(ws: ^Workspace) {
	for k, v in ws.collections {
		delete(k)
		delete(v)
	}
	clear(&ws.collections)
}

resolve_collection_path :: proc(ws: ^Workspace, path: string, allocator := context.allocator) -> string {
	resolved := path
	if !filepath.is_abs(path) && ws.root_path != "" {
		joined, _ := filepath.join({ws.root_path, path}, context.temp_allocator)
		resolved = joined
	}
	cleaned, _ := filepath.clean(resolved, allocator)
	return cleaned
}

set_collection :: proc(ws: ^Workspace, name, path: string) {
	if name == "" do return
	cleaned := resolve_collection_path(ws, path)
	to_remove: string
	found := false
	for k, v in ws.collections {
		if k == name {
			delete(v)
			to_remove = k
			found = true
			break
		}
	}
	if found {
		delete_key(&ws.collections, to_remove)
		delete(to_remove)
	}
	ws.collections[strings.clone(name)] = cleaned
}

apply_collections_object :: proc(ws: ^Workspace, collections: json.Object, replace: bool) {
	if replace {
		clear_workspace_collections(ws)
	}
	for name, path_val in collections {
		path, is_str := path_val.(string)
		if !is_str do continue
		set_collection(ws, name, path)
	}
}

apply_collections_array :: proc(ws: ^Workspace, arr: json.Array, replace: bool) {
	if replace {
		clear_workspace_collections(ws)
	}
	for elem in arr {
		obj, is_obj := elem.(json.Object)
		if !is_obj do continue
		name_val, has_name := obj["name"]
		path_val, has_path := obj["path"]
		if !has_name || !has_path do continue
		name, name_ok := name_val.(string)
		path, path_ok := path_val.(string)
		if !name_ok || !path_ok do continue
		set_collection(ws, name, path)
	}
}

// Accepts either `"collections": { "name": "path" }` or `"collections": [{ "name", "path" }]`.
apply_collections_from_json_value :: proc(ws: ^Workspace, value: json.Value, replace := false) {
	obj, is_obj := value.(json.Object)
	if !is_obj do return

	collections_val, has := obj["collections"]
	if !has do return

	if collections, is_map := collections_val.(json.Object); is_map {
		apply_collections_object(ws, collections, replace)
		return
	}
	if arr, is_arr := collections_val.(json.Array); is_arr {
		apply_collections_array(ws, arr, replace)
	}
}

apply_feature_bool :: proc(dst: ^bool, obj: json.Object, key: string) {
	val, has := obj[key]
	if !has do return
	if b, ok := val.(json.Boolean); ok {
		dst^ = bool(b)
	}
}

apply_features_from_json_object :: proc(features: ^Lsp_Features, obj: json.Object) {
	apply_feature_bool(&features.hover, obj, "hover")
	apply_feature_bool(&features.definition, obj, "definition")
	apply_feature_bool(&features.type_definition, obj, "type_definition")
	apply_feature_bool(&features.references, obj, "references")
	apply_feature_bool(&features.document_highlight, obj, "document_highlight")
	apply_feature_bool(&features.document_symbol, obj, "document_symbol")
	apply_feature_bool(&features.workspace_symbol, obj, "workspace_symbol")
	apply_feature_bool(&features.rename, obj, "rename")
	apply_feature_bool(&features.completion, obj, "completion")
	apply_feature_bool(&features.signature_help, obj, "signature_help")
	apply_feature_bool(&features.semantic_tokens, obj, "semantic_tokens")
	apply_feature_bool(&features.inlay_hints, obj, "inlay_hints")
	apply_feature_bool(&features.code_actions, obj, "code_actions")
	apply_feature_bool(&features.code_lens, obj, "code_lens")
	apply_feature_bool(&features.fmag_preview, obj, "fmag_preview")
	apply_feature_bool(&features.spirv_preview, obj, "spirv_preview")
}

apply_lsp_config_from_json_value :: proc(ws: ^Workspace, value: json.Value) {
	obj, is_obj := value.(json.Object)
	if !is_obj do return

	workspace_clear_server_path(ws)
	ws.config = default_lsp_config()
	ws.features = ws.config.features

	if sp_val, has := obj["server_path"]; has {
		if sp, ok := sp_val.(string); ok {
			ws.config.server_path = strings.clone(sp) if sp != "" else ""
		}
	}

	if feat_val, has := obj["features"]; has {
		if feat_obj, ok := feat_val.(json.Object); ok {
			apply_features_from_json_object(&ws.features, feat_obj)
			ws.config.features = ws.features
		}
	}

	apply_collections_from_json_value(ws, value, replace = true)
}

misl_lsp_json_path :: proc(ws: ^Workspace, allocator := context.temp_allocator) -> string {
	if ws.root_path == "" do return ""
	path, _ := filepath.join({ws.root_path, LSP_CONFIG_FILENAME}, allocator)
	return path
}

workspace_has_misl_lsp_json :: proc(ws: ^Workspace) -> bool {
	path := misl_lsp_json_path(ws)
	if path == "" do return false
	return os.exists(path)
}

load_misl_lsp_json :: proc(ws: ^Workspace) -> bool {
	path := misl_lsp_json_path(ws)
	if path == "" do return false
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return false
	value, parse_err := json.parse(data, parse_integers = true, allocator = context.temp_allocator)
	if parse_err != nil do return false
	apply_lsp_config_from_json_value(ws, value)
	ws.using_lsp_json = true
	return true
}

load_legacy_misl_json :: proc(ws: ^Workspace) {
	if ws.root_path == "" do return
	path, _ := filepath.join({ws.root_path, LEGACY_CONFIG_FILENAME}, context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return
	value, parse_err := json.parse(data, parse_integers = true, allocator = context.temp_allocator)
	if parse_err != nil do return
	apply_collections_from_json_value(ws, value, replace = false)
}

// Load project config: prefer misl.lsp.json; else defaults + init options + legacy misl.json.
workspace_clear_server_path :: proc(ws: ^Workspace) {
	if ws.config.server_path != "" {
		delete(ws.config.server_path)
		ws.config.server_path = ""
	}
}

workspace_load_config :: proc(ws: ^Workspace, init_options: Maybe(json.Value) = nil) {
	workspace_clear_server_path(ws)
	ws.config = default_lsp_config()
	ws.features = ws.config.features
	ws.using_lsp_json = false

	if load_misl_lsp_json(ws) {
		return
	}

	// No misl.lsp.json: keep defaults for features; merge collections from init + legacy.
	apply_initialization_options(ws, init_options)
	load_legacy_misl_json(ws)
}

reload_misl_lsp_json :: proc(ws: ^Workspace) {
	if load_misl_lsp_json(ws) {
		workspace_recheck(ws)
		return
	}
	// File removed or unreadable → fall back to defaults (empty collections, all features on).
	workspace_clear_server_path(ws)
	ws.config = default_lsp_config()
	ws.features = ws.config.features
	ws.using_lsp_json = false
	clear_workspace_collections(ws)
	workspace_recheck(ws)
}

uri_is_misl_lsp_json :: proc(uri: string) -> bool {
	path, ok := lsp.uri_to_filepath(uri)
	if !ok do return false
	defer delete(path)
	base := filepath.base(path)
	return strings.equal_fold(base, LSP_CONFIG_FILENAME)
}

apply_initialization_options :: proc(ws: ^Workspace, options: Maybe(json.Value)) {
	opts, has := options.?
	if !has do return
	apply_collections_from_json_value(ws, opts, replace = false)
}

apply_did_change_configuration :: proc(ws: ^Workspace, params: lsp.Did_Change_Configuration_Params) {
	// When misl.lsp.json is the source of truth, ignore VS Code settings merges.
	if ws.using_lsp_json do return
	apply_collections_from_json_value(ws, params.settings, replace = false)
	if obj, ok := params.settings.(json.Object); ok {
		if misl_val, has := obj["misl"]; has {
			apply_collections_from_json_value(ws, misl_val, replace = false)
		}
	}
}

apply_did_change_watched_files :: proc(ws: ^Workspace, params: lsp.Did_Change_Watched_Files_Params) {
	for change in params.changes {
		if uri_is_misl_lsp_json(change.uri) {
			reload_misl_lsp_json(ws)
			return
		}
	}
}
