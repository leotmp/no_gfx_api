package lsp

import "core:encoding/json"
import "base:intrinsics"

Workspace_Folder :: struct {
	/**
	 * The associated URI for this workspace folder.
	 */
	uri: URI,

	/**
	 * The name of the workspace folder. Used to refer to this
	 * workspace folder in the user interface.
	 */
	name: string,
}

Request_Message :: struct($Params: typeid) where intrinsics.type_is_variant_of(Request_Params, Params) {
	jsonrpc: string,
	id     : Request_Id,
	method : string,
	params : Params,
}

Work_Done_Progress_Create_Params :: struct {
	/**
	 * The token to be used to report progress.
	 */
	token: Progress_Token,
}

Work_Done_Progress_Cancel_Params :: struct {
	/**
	 * The token to be used to report progress.
	 */
	token: Progress_Token,
}

Initialize_Params :: struct {
	/**
	 * An optional token that a server can use to report work done progress.
	 */
	 work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,

	/**
	 * The process Id of the parent process that started the server. Is null if
	 * the process has not been started by another process. If the parent
	 * process is not alive then the server should exit (see exit notification)
	 * its process.
	 */
	process_id: Maybe(i64) `json:"processId"`,

	/**
	 * Information about the client
	 *
	 * @since 3.15.0
	 */
	client_info: Maybe(struct {
		/**
		 * The name of the client as defined by the client.
		 */
		name: string,

		/**
		 * The client's version as defined by the client.
		 */
		version: Maybe(string),
	}) `json:"clientInfo"`,

	/**
	 * The locale the client is currently showing the user interface
	 * in. This must not necessarily be the locale of the operating
	 * system.
	 *
	 * Uses IETF language tags as the value's syntax
	 * (See https://en.wikipedia.org/wiki/IETF_language_tag)
	 *
	 * @since 3.16.0
	 */
	locale: Maybe(string),

	/**
	 * The rootPath of the workspace. Is null
	 * if no folder is open.
	 *
	 * @deprecated in favour of `rootUri`.
	 */
	root_path: Maybe(string) `json:"rootPath"`,

	/**
	 * The rootUri of the workspace. Is null if no
	 * folder is open. If both `rootPath` and `rootUri` are set
	 * `rootUri` wins.
	 *
	 * @deprecated in favour of `workspaceFolders`
	 */
	root_uri: Maybe(Document_Uri) `json:"rootUri"`,

	/**
	 * User provided initialization options.
	 */
	initialization_options: Maybe(json.Value) `json:"initializationOptions"`,

	/**
	 * The capabilities provided by the client (editor or tool)
	 */
	capabilities: Client_Capabilities,

	/**
	 * The initial trace setting. If omitted trace is disabled ('off').
	 */
	trace: Maybe(string), // todo TraceValue

	/**
	 * The workspace folders configured in the client when the server starts.
	 * This property is only available if the client supports workspace folders.
	 * It can be `null` if the client supports workspace folders but none are
	 * configured.
	 *
	 * @since 3.6.0
	 */
	workspace_folders: Maybe([]Workspace_Folder) `json:"workspaceFolders"`,
}

/**
 * General parameters to register for a capability.
 */
 Registration :: struct {
	/**
	 * The id used to register the request. The id can be used to deregister
	 * the request again.
	 */
	id: string,

	/**
	 * The method / capability to register for.
	 */
	method: string,

	/**
	 * Options necessary for the registration.
	 */
	register_options: Maybe(json.Value) `json:"registerOptions"`,
}

Registration_Params :: struct {
	registrations: []Registration,
}

Unregistration :: struct {
	/**
	 * The id used to unregister the request or notification. Usually an id
	 * provided during the register request.
	 */
	id: string,

	/**
	 * The method / capability to unregister for.
	 */
	method: string,
}

Unregistration_Params :: struct {
	// This should correctly be named `unregistrations`. However changing this
	// is a breaking change and needs to wait until we deliver a 4.x version
	// of the specification.
	unregisterations: []Unregistration, // Note(dragos): yes. It is a typo in the specs themselves. Fixing it is a breaking change. Yes, LSP is retarded.
}

Type_Hierarchy_Prepare_Params :: struct {
	/**
	 * The text document.
	 */
	text_document: Text_Document_Identifier `json:"textDocument"`,

	/**
	 * The position inside the text document.
	 */
	position: Position,

	/**
	 * An optional token that a server can use to report work done progress.
	 */
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,
}

Type_Hierarchy_Supertypes_Params :: struct {
	/**
	 * An optional token that a server can use to report work done progress.
	 */
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,

	 /**
	 * An optional token that a server can use to report partial results (e.g.
	 * streaming) to the client.
	 */
	partial_result_token: Maybe(Progress_Token) `json:"partialResultToken"`,
	
	item: Type_Hierarchy_Item,
}

Type_Hierarchy_Subtypes_Params :: struct {
	/**
	 * An optional token that a server can use to report work done progress.
	 */
	 work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,

	 /**
	 * An optional token that a server can use to report partial results (e.g.
	 * streaming) to the client.
	 */
	partial_result_token: Maybe(Progress_Token) `json:"partialResultToken"`,
	
	item: Type_Hierarchy_Item,
}

Document_Diagnostic_Params :: struct {
	/**
	 * An optional token that a server can use to report work done progress.
	 */
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,

	 /**
	 * An optional token that a server can use to report partial results (e.g.
	 * streaming) to the client.
	 */
	partial_result_token: Maybe(Progress_Token) `json:"partialResultToken"`,

	/**
	 * The text document. // say no more, quality docs. Are you being paid by words typed?
	 */
	text_document: Text_Document_Identifier `json:"textDocument"`,

	/**
	 * The additional identifier  provided during registration.
	 */
	identifier: Maybe(string),

	/**
	 * The result id of a previous response if provided.
	 */
	previous_result_id: Maybe(string) `json:"previousResultId"`,
}

/**
 * A previous result id in a workspace pull request.
 *
 * @since 3.17.0
 */
Previous_Result_Id :: struct {
	/**
	 * The URI for which the client knows a
	 * result id.
	 */
	uri: Document_Uri,

	/**
	 * The value of the previous result id.
	 */
	value: string,
}

Workspace_Diagnostic_Params :: struct {
	/**
	 * An optional token that a server can use to report work done progress.
	 */
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,

	 /**
	 * An optional token that a server can use to report partial results (e.g.
	 * streaming) to the client.
	 */
	partial_result_token: Maybe(Progress_Token) `json:"partialResultToken"`,

	/**
	 * The additional identifier provided during registration.
	 */
	identifier: Maybe(string),

	/**
	 * The currently known diagnostic reports with their
	 * previous result ids.
	 */
	previous_result_ids: []Previous_Result_Id `json:"previousResultIds"`
}

Workspace_Symbol_Params :: struct {
	/**
	 * An optional token that a server can use to report work done progress.
	 */
	 work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,

	 /**
	 * An optional token that a server can use to report partial results (e.g.
	 * streaming) to the client.
	 */
	partial_result_token: Maybe(Progress_Token) `json:"partialResultToken"`,

	/**
	 * A query string to filter symbols by. Clients may send an empty
	 * string here to request all symbols.
	 */
	query: string,
}

Configuration_Item :: struct {
	
}

Configuration_Params :: struct {
	items: []Configuration_Item,
}

/**
 * Represents information on a file/folder create.
 *
 * @since 3.16.0
 */
File_Create :: struct {
	/**
	 * A file:// URI for the location of the file/folder being created.
	 */
	uri: string,
}

/**
 * The parameters sent in notifications/requests for user-initiated creation
 * of files.
 *
 * @since 3.16.0
 */
Create_Files_Params :: struct {
	/**
	 * An array of all files/folders created in this operation.
	 */
	files: []File_Create,
}

File_Rename :: struct {
	/**
	 * A file:// URI for the original location of the file/folder being renamed.
	 */
	old_uri: string `json:"oldUri"`,

	/**
	 * A file:// URI for the new location of the file/folder being renamed.
	 */
	new_uri: string `json:"newUri"`,
}

/**
 * The parameters sent in notifications/requests for user-initiated renames
 * of files.
 *
 * @since 3.16.0
 */
Rename_Files_Params :: struct {
	/**
	 * An array of all files/folders renamed in this operation. When a folder
	 * is renamed, only the folder will be included, and not its children.
	 */
	files: []File_Rename,
}

/**
 * Represents information on a file/folder delete.
 *
 * @since 3.16.0
 */
File_Delete :: struct {
	/**
	 * A file:// URI for the location of the file/folder being deleted.
	 */
	uri: string,
}

/**
 * The parameters sent in notifications/requests for user-initiated deletes
 * of files.
 *
 * @since 3.16.0
 */
Delete_Files_Params :: struct {
	/**
	 * An array of all files/folders deleted in this operation.
	 */
	files: []File_Delete,
}

Execute_Command_Params :: struct {
	/**
	 * An optional token that a server can use to report work done progress.
	 */
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,

	/**
	 * The identifier of the actual command handler.
	 */
	command: string,

	/**
	 * Arguments that the command should be invoked with.
	 */
	arguments: Maybe([]json.Value), // Note(Dragos): Maybe(any)?
}

Message_Action_Item :: struct {
	/**
	 * A short title like 'Retry', 'Open Log' etc.
	 */
	 title: string,
}

Apply_Workspace_Edit_Params :: struct {
	/**
	 * An optional label of the workspace edit. This label is
	 * presented in the user interface for example on an undo
	 * stack to undo the workspace edit.
	 */
	label: Maybe(string),

	/**
	 * The edits to apply.
	 */
	edit: Workspace_Edit,
}

Show_Message_Request_Params :: struct {
	type   : Message_Type,
	message: string,

	/**
	 * The message action items to present.
	 */
	actions: Maybe([]Message_Action_Item),
}

/**
 * Params to show a resource.
 *
 * @since 3.16.0
 */
Show_Document_Params :: struct {
	/**
	 * The uri to show.
	 */
	uri: URI,

	/**
	 * Indicates to show the resource in an external program.
	 * To show, for example, `https://code.visualstudio.com/`
	 * in the default WEB browser set `external` to `true`.
	 */
	external: Maybe(bool),

	/**
	 * An optional property to indicate whether the editor
	 * showing the document should take focus or not.
	 * Clients might ignore this property if an external
	 * program is started.
	 */
	take_focus: Maybe(bool) `json:"takeFocus"`,

	/**
	 * An optional selection range if the document is a text
	 * document. Clients might ignore the property if an
	 * external program is started or the file is not a text
	 * file.
	 */
	selection: Maybe(Range),
}

Semantic_Tokens_Params :: struct {
	/**
	 * An optional token that a server can use to report work done progress.
	 */
	work_done_token: Progress_Token `json:"workDoneToken"`,

	/**
	 * An optional token that a server can use to report partial results (e.g.
	 * streaming) to the client.
	 */
	partial_result_Token: Progress_Token `json:"partialResultToken"`,

	/**
	 * The text document.
	 */
	text_document: Text_Document_Identifier `json:"textDocument"`,
}

Text_Document_Position_Params :: struct {
	text_document: Text_Document_Identifier `json:"textDocument"`,
	position:      Position,
}

Hover_Params :: struct {
	text_document:   Text_Document_Identifier `json:"textDocument"`,
	position:        Position,
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,
}

Definition_Params :: struct {
	text_document:   Text_Document_Identifier `json:"textDocument"`,
	position:        Position,
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,
}

Inlay_Hint_Params :: struct {
	text_document:   Text_Document_Identifier `json:"textDocument"`,
	range:           Range,
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,
}

Completion_Context :: struct {
	trigger_kind:      int `json:"triggerKind"`,
	trigger_character: Maybe(string) `json:"triggerCharacter"`,
}

Completion_Params :: struct {
	text_document:   Text_Document_Identifier `json:"textDocument"`,
	position:        Position,
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,
	ctx:             Maybe(Completion_Context) `json:"context"`,
}

Signature_Help_Context :: struct {
	trigger_kind:          int `json:"triggerKind"`,
	trigger_character:     Maybe(string) `json:"triggerCharacter"`,
	is_retrigger:          bool `json:"isRetrigger"`,
	active_signature_help: Maybe(Signature_Help) `json:"activeSignatureHelp"`,
}

Signature_Help_Params :: struct {
	text_document:   Text_Document_Identifier `json:"textDocument"`,
	position:        Position,
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,
	ctx:             Maybe(Signature_Help_Context) `json:"context"`,
}

Document_Symbol_Params :: struct {
	text_document:   Text_Document_Identifier `json:"textDocument"`,
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,
}

Code_Action_Context :: struct {
	diagnostics: []Diagnostic,
	only:        []string `json:"only,omitempty"`,
}

Code_Action_Params :: struct {
	text_document:   Text_Document_Identifier `json:"textDocument"`,
	range:           Range,
	ctx:             Code_Action_Context `json:"context"`,
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,
}

Reference_Context :: struct {
	include_declaration: bool `json:"includeDeclaration"`,
}

Reference_Params :: struct {
	text_document:   Text_Document_Identifier `json:"textDocument"`,
	position:        Position,
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,
	ctx:             Reference_Context `json:"context"`,
}

Document_Highlight_Params :: struct {
	text_document:   Text_Document_Identifier `json:"textDocument"`,
	position:        Position,
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,
}

Prepare_Rename_Params :: struct {
	text_document: Text_Document_Identifier `json:"textDocument"`,
	position:      Position,
}

Rename_Params :: struct {
	text_document:   Text_Document_Identifier `json:"textDocument"`,
	position:        Position,
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,
	new_name:        string `json:"newName"`,
}

Semantic_Tokens_Range_Params :: struct {
	text_document:   Text_Document_Identifier `json:"textDocument"`,
	range:           Range,
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,
}

// note(Dragos): maybe this is not needed after all.
// Note(Dragos): Some requests are sent from server to client only, while some (most) are sent from client to server.
// we need a way to figure out how to get everything correctly setup in terms of API. I am not sure i currently like this approach
Request_Params :: union {
	Initialize_Params,
	Registration_Params,
	Unregistration_Params,
	Type_Hierarchy_Prepare_Params,
	Type_Hierarchy_Supertypes_Params,
	Type_Hierarchy_Subtypes_Params,
	Document_Diagnostic_Params,
	Workspace_Diagnostic_Params,
	Workspace_Symbol_Params,
	Workspace_Symbol,
	Configuration_Params,
	Create_Files_Params,
	Rename_Files_Params,
	Execute_Command_Params,
	Apply_Workspace_Edit_Params,
	Show_Document_Params,
	Work_Done_Progress_Create_Params,
	Work_Done_Progress_Cancel_Params,
	Semantic_Tokens_Params,
	Semantic_Tokens_Range_Params,
	Hover_Params,
	Definition_Params,
	Inlay_Hint_Params,
	Completion_Params,
	Completion_Item,
	Signature_Help_Params,
	Document_Symbol_Params,
	Document_Link_Params,
	Code_Action_Params,
	Reference_Params,
	Document_Highlight_Params,
	Prepare_Rename_Params,
	Rename_Params,
	Text_Document_Position_Params,
	Code_Lens_Params,
}

// This is to be used for partial unmarshaling
Partial_Message :: struct {
	jsonrpc: string,
	id     : Request_Id,
	method : string,
} 