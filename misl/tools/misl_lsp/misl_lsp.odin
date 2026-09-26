package misl_lsp

import "core:encoding/json"
import "core:os"
import "core:slice"
import "./lsp"

token_encoder: lsp.Token_Encoder
logger: lsp.Logger
shutting_down: bool

server := lsp.Server{
	callbacks = {
		on_initialize = msg_initialize,
		on_initialized = msg_initialized,
		on_shutdown = msg_shutdown,
		on_exit = msg_exit,
		on_document_open = msg_did_open,
		on_document_change = msg_did_change,
		on_document_close = msg_did_close,
		on_document_save = msg_did_save,
		on_did_change_configuration = msg_did_change_configuration,
		on_did_change_watched_files = msg_did_change_watched_files,
		on_hover = msg_hover,
		on_definition = msg_definition,
		on_type_definition = msg_type_definition,
		on_document_symbol = msg_document_symbol,
		on_completion = msg_completion,
		on_completion_resolve = msg_completion_resolve,
		on_signature_help = msg_signature_help,
		on_inlay_hint = msg_inlay_hint,
		on_semantic_tokens_full = msg_semantic_tokens_full,
		on_semantic_tokens_range = msg_semantic_tokens_range,
		on_references = msg_references,
		on_document_highlight = msg_document_highlight,
		on_prepare_rename = msg_prepare_rename,
		on_rename = msg_rename,
		on_workspace_symbol = msg_workspace_symbol,
		on_document_link = msg_document_link,
		on_code_action = msg_code_action,
		on_code_lens = msg_code_lens,
		on_fmag_preview = msg_fmag_preview,
		on_spirv_preview = msg_spirv_preview,
	},
}

msg_initialize :: proc(id: lsp.Request_Id, params: lsp.Initialize_Params) -> (result: lsp.Initialize_Result, error: Maybe(lsp.Response_Error)) {
	_ = id
	lsp.token_encoder_init(
		encoder = &token_encoder,
		token_set = {
			.Namespace, .Class, .Parameter, .Variable, .Function,
			.Keyword, .Number, .String, .Comment, .Property,
		},
		modifier_set = {.Declaration, .Readonly, .Modification, .Default_Library},
	)

	if root, has := params.root_uri.?; has && root != "" {
		if path, ok := lsp.uri_to_filepath(root); ok {
			workspace.root_path = path
		}
	} else if folders, has := params.workspace_folders.?; has && len(folders) > 0 {
		if path, ok := lsp.uri_to_filepath(folders[0].uri); ok {
			workspace.root_path = path
		}
	}

	workspace_load_config(&workspace, params.initialization_options)

	token_types, token_modifiers := lsp.token_encoder_make_capability_slices(token_encoder, context.temp_allocator)

	caps: lsp.Server_Capabilities
	caps.text_document_sync = {
		open_close = true,
		change = .Full,
		save = {include_text = true},
	}
	caps.position_encoding = "utf-16"
	caps.hover_provider = true
	caps.definition_provider = true
	caps.type_definition_provider = true
	caps.references_provider = true
	caps.document_highlight_provider = true
	caps.document_symbol_provider = true
	caps.workspace_symbol_provider = true
	caps.rename_provider = true
	caps.inlay_hint_provider = true
	caps.code_action_provider = true
	// Intentionally no documentLinkProvider: linking builtins underlined them in the editor.
	caps.completion_provider = {
		resolveProvider = true,
		triggerCharacters = slice.clone([]string{".", "#", "+", "|", "\"", " ", ":", "/"}, context.temp_allocator),
		completionItem = {labelDetailsSupport = true},
	}
	caps.signature_help_provider = {
		trigger_characters = slice.clone([]string{"(", ","}, context.temp_allocator),
		retrigger_characters = slice.clone([]string{","}, context.temp_allocator),
	}
	caps.semantic_tokens_provider = {
		range = true,
		full = true,
		legend = {
			token_types = token_types,
			token_modifiers = token_modifiers,
		},
	}
	caps.code_lens_provider = lsp.Code_Lens_Options{
		resolve_provider = false,
	}

	result = {capabilities = caps}
	return
}

msg_initialized :: proc(params: lsp.Initialized_Params) {
	_ = params
}

msg_shutdown :: proc(id: lsp.Request_Id) -> Maybe(lsp.Response_Error) {
	_ = id
	shutting_down = true
	return nil
}

msg_exit :: proc() {
	if !shutting_down {
		os.exit(1)
	}
}

msg_did_open :: proc(params: lsp.Did_Open_Text_Document_Params) {
	document_open(&workspace, params)
}

msg_did_change :: proc(params: lsp.Did_Change_Text_Document_Params) {
	document_change(&workspace, params)
}

msg_did_close :: proc(params: lsp.Did_Close_Text_Document_Params) {
	document_close(&workspace, params)
}

msg_did_save :: proc(params: lsp.Did_Save_Text_Document_Params) {
	document_save(&workspace, params)
}

msg_did_change_configuration :: proc(params: lsp.Did_Change_Configuration_Params) {
	apply_did_change_configuration(&workspace, params)
	workspace_recheck(&workspace)
}

msg_did_change_watched_files :: proc(params: lsp.Did_Change_Watched_Files_Params) {
	apply_did_change_watched_files(&workspace, params)
}

msg_hover :: proc(id: lsp.Request_Id, params: lsp.Hover_Params) -> (result: Maybe(lsp.Hover), error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.hover do return nil, nil
	return hover_at(&workspace, params), nil
}

msg_definition :: proc(id: lsp.Request_Id, params: lsp.Definition_Params) -> (result: []lsp.Location, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.definition do return nil, nil
	return definition_at(&workspace, params), nil
}

msg_type_definition :: proc(id: lsp.Request_Id, params: lsp.Definition_Params) -> (result: []lsp.Location, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.type_definition do return nil, nil
	return type_definition_at(&workspace, params), nil
}

msg_document_symbol :: proc(id: lsp.Request_Id, params: lsp.Document_Symbol_Params) -> (result: []lsp.Document_Symbol, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.document_symbol do return nil, nil
	return document_symbols(&workspace, params), nil
}

msg_completion :: proc(id: lsp.Request_Id, params: lsp.Completion_Params) -> (result: lsp.Completion_List, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.completion do return {}, nil
	return completion_at(&workspace, params), nil
}

msg_completion_resolve :: proc(id: lsp.Request_Id, params: lsp.Completion_Item) -> (result: lsp.Completion_Item, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.completion do return params, nil
	return completion_resolve(&workspace, params), nil
}

msg_signature_help :: proc(id: lsp.Request_Id, params: lsp.Signature_Help_Params) -> (result: Maybe(lsp.Signature_Help), error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.signature_help do return nil, nil
	return signature_help_at(&workspace, params), nil
}

msg_inlay_hint :: proc(id: lsp.Request_Id, params: lsp.Inlay_Hint_Params) -> (result: []lsp.Inlay_Hint, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.inlay_hints do return nil, nil
	return inlay_hints(&workspace, params), nil
}

msg_semantic_tokens_full :: proc(id: lsp.Request_Id, params: lsp.Semantic_Tokens_Params) -> (result: lsp.Semantic_Tokens, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.semantic_tokens do return {}, nil
	return semantic_tokens_full(&workspace, params, token_encoder), nil
}

msg_semantic_tokens_range :: proc(id: lsp.Request_Id, params: lsp.Semantic_Tokens_Range_Params) -> (result: lsp.Semantic_Tokens, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.semantic_tokens do return {}, nil
	return semantic_tokens_range(&workspace, params, token_encoder), nil
}

msg_references :: proc(id: lsp.Request_Id, params: lsp.Reference_Params) -> (result: []lsp.Location, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.references do return nil, nil
	return references_at(&workspace, params), nil
}

msg_document_highlight :: proc(id: lsp.Request_Id, params: lsp.Document_Highlight_Params) -> (result: []lsp.Document_Highlight, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.document_highlight do return nil, nil
	return document_highlights_at(&workspace, params), nil
}

msg_prepare_rename :: proc(id: lsp.Request_Id, params: lsp.Prepare_Rename_Params) -> (result: Maybe(lsp.Range), error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.rename do return nil, nil
	return prepare_rename_at(&workspace, params), nil
}

msg_rename :: proc(id: lsp.Request_Id, params: lsp.Rename_Params) -> (result: Maybe(lsp.Workspace_Edit), error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.rename do return nil, nil
	return rename_at(&workspace, params), nil
}

msg_workspace_symbol :: proc(id: lsp.Request_Id, params: lsp.Workspace_Symbol_Params) -> (result: []lsp.Workspace_Symbol, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.workspace_symbol do return nil, nil
	return workspace_symbols(&workspace, params), nil
}

msg_document_link :: proc(id: lsp.Request_Id, params: lsp.Document_Link_Params) -> (result: []lsp.Document_Link, error: Maybe(lsp.Response_Error)) {
	_ = id
	return document_links(&workspace, params), nil
}

msg_code_action :: proc(id: lsp.Request_Id, params: lsp.Code_Action_Params) -> (result: []lsp.Code_Action, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.code_actions do return nil, nil
	return code_actions(&workspace, params), nil
}

msg_code_lens :: proc(id: lsp.Request_Id, params: lsp.Code_Lens_Params) -> (result: []lsp.Code_Lens, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.code_lens do return nil, nil
	return code_lenses_at(&workspace, params), nil
}

msg_fmag_preview :: proc(id: lsp.Request_Id, params: json.Value) -> (result: json.Value, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.fmag_preview {
		return nil, lsp.Response_Error{code = .Request_Failed, message = "fmag_preview disabled in misl.lsp.json"}
	}
	return fmag_preview_request(&workspace, params)
}

msg_spirv_preview :: proc(id: lsp.Request_Id, params: json.Value) -> (result: json.Value, error: Maybe(lsp.Response_Error)) {
	_ = id
	if !workspace.features.spirv_preview {
		return nil, lsp.Response_Error{code = .Request_Failed, message = "spirv_preview disabled in misl.lsp.json"}
	}
	return spirv_preview_request(&workspace, params)
}

main :: proc() {
	lsp.server_init_stdio(&server)
	lsp.logger_init(&logger, .Warning, server.write, server.write)
	context.logger = logger
	context.assertion_failure_proc = lsp.default_assertion_failure_proc

	workspace_init(&workspace, &server)
	defer workspace_destroy(&workspace)

	for lsp.poll_message(&server) {
		defer free_all(context.temp_allocator)
	}
}
