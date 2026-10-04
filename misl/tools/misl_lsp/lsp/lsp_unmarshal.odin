#+feature dynamic-literals
package lsp

import "core:encoding/json"
import "core:mem"

json_get :: proc(obj: json.Object, field: string, $as_type: typeid) -> (result: as_type, ok: bool) {
	value := obj[field] or_return
	result = value.(as_type) or_return
	return result, true
}

json_get_maybe :: proc(obj: json.Object, field: string, $as_type: typeid) -> (Maybe(as_type)) {
	value, has_field := obj[field]
	if !has_field do return nil
	if v, ok := value.(as_type); ok do return v
	return nil
}

// rules
// temp-allocate the return value
// return it as a value, by derefencing the allocated pointer
Unmarshal_Proc :: #type proc(value: json.Value) -> any

// todo(dragos): unfinished
@private
unmarshal_Initialize_Params :: proc(value: json.Value) -> any {
	params := new(Initialize_Params, context.temp_allocator)
	obj := value.(json.Object) or_return
	if work_done_token, has_work_done_token := obj["workDoneToken"]; has_work_done_token {
		#partial switch v in work_done_token {
		case string: params.work_done_token = v
		case i64:    params.work_done_token = v
		case:        params.work_done_token = nil
		}
	}
	params.process_id = json_get_maybe(obj, "processId", i64)
	if client_info, has_field := json_get(obj, "clientInfo", json.Object); has_field {	
		params_client_info: type_of(params.client_info.?)
		params_client_info.name = json_get(client_info, "name", string) or_else ""
		params_client_info.version = json_get_maybe(client_info, "version", string)
		params.client_info = params_client_info
	}
	
	if locale, has_locale := obj["locale"]; has_locale do if locale, is_str := locale.(string); is_str {
		params.locale = locale
	}

	if root_path, has_root_path := obj["rootPath"]; has_root_path do if root_path, is_str := root_path.(string); is_str {
		params.root_path = root_path
	}

	if root_uri, has_root_uri := obj["rootUri"]; has_root_uri do if root_uri, is_str := root_uri.(string); is_str {
		params.root_uri = root_uri
	}

	if initialization_opts, has_opts := obj["initializationOptions"]; has_opts {
		params.initialization_options = initialization_opts
	}

	if workspace_folders, has_field := obj["workspaceFolders"]; has_field do if workspace_folders, is_arr := workspace_folders.(json.Array); is_arr {
		params.workspace_folders = make([]Workspace_Folder, len(workspace_folders), context.temp_allocator)
		params_folders := &params.workspace_folders.?
		for v, i in workspace_folders {
			if folder, is_obj := v.(json.Object); is_obj {
				params_folder := &params_folders[i]
				if uri, has_field := folder["uri"]; has_field do if uri, is_str := uri.(string); is_str {
					params_folder.uri = uri
				}
				if name, has_field := folder["name"]; has_field do if name, is_str := name.(string); is_str {
					params_folder.name = name
				}
			}
		}
	}
	
	if caps, ok := obj["capabilities"]; ok do if caps, ok := caps.(json.Object); ok {
		capabilities := &params.capabilities
		if wks, ok := caps["workspace"]; ok do if wks, ok := wks.(json.Object); ok {
			workspace := &capabilities.workspace
			if v, ok := wks["applyEdit"]; ok do if v, ok := v.(bool); ok {
				workspace.apply_edit = v
			}
			if wks_edit, ok := json_get(wks, "workspaceEdit", json.Object); ok {
				workspace.workspace_edit.document_changes, _ = json_get(wks_edit, "documentChanges", bool)
			}
		}
	}
	
	return params^
}

unmarshal_map := map[typeid]Unmarshal_Proc {
	Initialize_Params = unmarshal_Initialize_Params,
} 