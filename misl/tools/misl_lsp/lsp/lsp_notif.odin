package lsp

import "core:encoding/json"

Notification_Message :: struct($Params: typeid) {
	jsonrpc: string,
	method : string,
	params : Params,
}

Publish_Diagnostics_Params :: struct {
	/**
	 * The URI for which diagnostic information is reported.
	 */
	uri: string,

	/**
	 * Optional the version number of the document the diagnostics are published
	 * for.
	 *
	 * @since 3.15.0
	 */
	version: Maybe(int),

	/**
	 * An array of diagnostic information items.
	 */
	diagnostics: []Diagnostic,
}

Message_Type :: enum {
	Error   = 1,
	Warning = 2,
	Info    = 3,
	Log     = 4,
	Debug   = 5,
}

Log_Message_Params :: struct {
	type   : Message_Type,
	message: string,
}

Show_Message_Params :: struct {
	type   : Message_Type,
	message: string,
}

Cancel_Params :: struct {
	/**
	 * The request id to cancel.
	 */
	id: Request_Id,
}

Progress_Token :: union {
	i64,
	string,
}

Progress_Params :: struct {
	/**
	 * The progress token provided by the client or server.
	 */
	token: Progress_Token,

	/**
	 * The progress data.
	 */
	value: json.Value,
}

Initialized_Params :: struct { }

Set_Trace_Params :: struct {
	/**
	 * The new value that should be assigned to the trace setting.
	 */
	value: string, // todo TraceValue
}

Log_Trace_Params :: struct {
	/**
	 * The message to be logged.
	 */
	message: string,

	/**
	 * Additional information that can be computed if the `trace` configuration
	 * is set to `'verbose'`
	 */
	verbose: Maybe(string),
}

Did_Open_Text_Document_Params :: struct {
	/**
	 * The document that was opened.
	 */
	text_document: Text_Document_Item `json:"textDocument"`,
}

Did_Change_Text_Document_Params :: struct {
	text_document:   Versioned_Text_Document_Identifier `json:"textDocument"`,
	content_changes: []Text_Document_Content_Change_Event `json:"contentChanges"`,
}

Did_Close_Text_Document_Params :: struct {
	text_document: Text_Document_Identifier `json:"textDocument"`,
}

Did_Save_Text_Document_Params :: struct {
	/**
	 * The document that was saved.
	 */
	text_document: Text_Document_Identifier `json:"textDocument"`,

	/**
	 * Optional the content when saved. Depends on the includeText value
	 * when the save notification was requested.
	 */
	text: Maybe(string),
}

Text_Document_Save_Reason :: enum {
	/**
	 * Manually triggered, e.g. by the user pressing save, by starting
	 * debugging, or by an API call.
	 */
	Manual = 1,

	/**
	 * Automatic after a delay.
	 */
	After_Delay = 2,

	/**
	 * When the editor lost focus.
	 */
	Focus_Out = 3,
}

Will_Save_Text_Document_Params :: struct {
	/**
	 * The document that will be saved.
	 */
	text_document: Text_Document_Identifier `json:"textDocument"`,

	/**
	 * The 'TextDocumentSaveReason'. // no fucking shit. This is not even worth formatting to something good
	 */
	reason: Text_Document_Save_Reason,
}

Did_Change_Configuration_Params :: struct {
	/**
	 * The actual changed settings
	 */
	settings: json.Value,
}

Workspace_Folder_Change_Event :: struct {
	/**
	 * The array of added workspace folders
	 */
	added: []Workspace_Folder,

	/**
	 * The array of the removed workspace folders
	 */
	removed: []Workspace_Folder,
}

Did_Change_Workspace_Folders_Params :: struct {
	/**
	 * The actual workspace folder change event.
	 */
	event: Workspace_Folder_Change_Event,
}

File_Change_Type :: enum {
	Created = 1,
	Changed = 2,
	Deleted = 3,
}

/**
 * An event describing a file change.
 */
File_Event :: struct {
	/**
	 * The file's URI.
	 */
	uri: Document_Uri,

	/**
	 * The change type. // Another useless piece of documentation
	 */
	type: File_Change_Type,
}

Did_Change_Watched_Files_Params :: struct {
	/**
	 * The actual file events.
	 */
	changes: []File_Event,
}

// Note(Dragos): not handled: telemetry/event

Notification_Params :: union {
	Log_Message_Params,
	Publish_Diagnostics_Params,
	Cancel_Params,
	Progress_Params,
	Initialized_Params,
	Set_Trace_Params,
	Did_Open_Text_Document_Params,
	Did_Change_Text_Document_Params,
	Did_Close_Text_Document_Params,
	Did_Save_Text_Document_Params,
	Will_Save_Text_Document_Params,
	Did_Change_Configuration_Params,
	Did_Change_Workspace_Folders_Params,
	Create_Files_Params,
	Rename_Files_Params,
	Delete_Files_Params,
	Did_Change_Watched_Files_Params,
	Show_Message_Params,
}