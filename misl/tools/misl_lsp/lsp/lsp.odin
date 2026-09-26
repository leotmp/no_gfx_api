/*
	This file will try to enclose all the lsp protocol specs. 
	Note(Dragos): try to document this as needed, as we go
	The aim should be to finally separate this in it's own package
	Note(Dragos): it seems that the types are also defined by name, should we keep it? e.g. CompletionOptions vs Completion_Options
	Note(Dragos): In addition, should the properties be snake_case in our code and then marshal them to camelCase later?
	Note(dragos): should we enclose `:?` types into `Maybe` types?
*/
package lsp

VERSION_MAJ :: 3
VERSION_MIN :: 17
VERSION_STR :: "3.17"

import "core:io"
import "core:encoding/json"
import "core:strings"
import "core:strconv"
import "core:fmt"
import "core:log"
import "core:os"

Type_Hierarchy_Item :: struct {
	// todo
}

Request_Id :: union {
	string,
	i64,
}


Symbol_Tag :: enum {
	Deprecated = 1,
}

Header :: struct {
	content_length: int,
	content_type: string,
}

URI :: string
Document_Uri :: string

Package :: struct {
	name         : string,
	base         : string,
	base_original: string,
	original     : string,
}

// Note(Dragos): This is not defined by LSP per se. What should we do?
Request_Type :: enum {
	Initialize,
	Initialized,
	Shutdown,
	Exit,
	Did_Open,
	Did_Change,
	Did_Close,
	Did_Save,
	Definition,
	Completion,
	Signature_Help,
	Document_Symbol,
	Semantic_Tokens_Full,
	Semantic_Tokens_Range,
	Format_Document,
	Hover,
	Cancel_Request,
	Inlay_Hint,
}


/*
RequestInfo :: struct {
	root:     json.Value,
	params:   json.Value,
	document: ^Document,
	id:       RequestId,
	config:   ^common.Config,
	writer:   ^Writer,
	result:   common.Error,
}
*/


Diagnostic_Severity :: enum {
	Error       = 1,
	Warning     = 2,
	Information = 3,
	Hint        = 4,
}

Position :: struct {
	line     : int,
	character: int,
}

Range :: struct {
	start: Position,
	end  : Position,
}

Location :: struct {
	uri  : string,
	range: Range,
}

Diagnostic_Related_Information :: struct {
	location: Location,
	message : string,
}

Diagnostic :: struct {
	range              : Range,
	severity           : Diagnostic_Severity,
	code               : string,
	message            : string,
	related_information: []Diagnostic_Related_Information `json:"relatedInformation,omitempty"`,
}



Save_Options :: struct {
	/**
	 * The client is supposed to include the content on save.
	 */
	include_text: bool `json:"includeText"`,
}

Text_Document_Sync_Kind :: enum {
	/**
	 * Documents should not be synced at all.
	 */
	None = 0,

	/**
	 * Documents are synced by always sending the full content
	 * of the document.
	 */
	Full = 1,

	/**
	 * Documents are synced by sending the full content on open.
	 * After that only incremental updates to the document are
	 * sent.
	 */
	Incremental = 2,
}

Text_Document_Sync_Options :: struct {
	/**
	 * Open and close notifications are sent to the server. If omitted open
	 * close notifications should not be sent.
	 */
	open_close: bool `json:"openClose"`,

	/**
	 * Change notifications are sent to the server. See
	 * TextDocumentSyncKind.None, TextDocumentSyncKind.Full and
	 * TextDocumentSyncKind.Incremental. If omitted it defaults to
	 * TextDocumentSyncKind.None.
	 */
	change   : Text_Document_Sync_Kind,

	/**
	 * If present save notifications are sent to the server. If omitted the
	 * notification should not be sent.
	 */
	save     : Save_Options,
}

// Note(Dragos): this extends WorkDoneProgressOptions. Should we add that? OLS doesn't. Test later
Completion_Options :: struct {
	resolveProvider  : bool,
	triggerCharacters: []string,
	completionItem   : struct {
		labelDetailsSupport: bool,
	}
}

Signature_Help_Options :: struct {
	trigger_characters  : []string `json:"triggerCharacters"`,
	retrigger_characters: []string `json:"retriggerCharacters"`,
}

Semantic_Tokens_Legend :: struct {
	token_types    : []string `json:"tokenTypes"`,
	token_modifiers: []string `json:"tokenModifiers"`,
}

Document_Link_Options :: struct {
	resolve_provider: bool `json:"resolveProvider"`,
}

Server_Capabilities :: struct {
	/**
	 * Encoding used for all character offsets exchanged with the client.
	 */
	position_encoding            : string `json:"positionEncoding"`,

	/**
	 * Defines how text documents are synced. Is either a detailed structure
	 * defining each notification or for backwards compatibility the
	 * TextDocumentSyncKind number. If omitted it defaults to
	 * `TextDocumentSyncKind.None`.
	 */
	text_document_sync          : Text_Document_Sync_Options `json:"textDocumentSync"`,

	/**
	 * The server provides goto definition support.
	 */
	definition_provider         : bool `json:"definitionProvider"`,

	/**
	 * The server provides goto type definition support.
	 */
	type_definition_provider    : bool `json:"typeDefinitionProvider"`,

	/**
	 * The server provides completion support.
	 */
	completion_provider         : Completion_Options `json:"completionProvider"`,

	/**
	 * The server provides signature help support.
	 */
	signature_help_provider     : Signature_Help_Options `json:"signatureHelpProvider"`,

	/**
	 * The server provides semantic tokens support.
	 *
	 * @since 3.16.0
	 */
	semantic_tokens_provider    : Semantic_Tokens_Options `json:"semanticTokensProvider"`,

	/**
	 * The server provides document symbol support.
	 */
	document_symbol_provider    : bool `json:"documentSymbolProvider"`,

	/**
	 * The server provides hover support.
	 */
	hover_provider              : bool `json:"hoverProvider"`,

	/**
	 * The server provides document formatting.
	 */
	document_formatting_provider: bool `json:"documentFormattingProvider"`,

	/**
	 * The server provides inlay hints.
	 *
	 * @since 3.17.0
	 */
	inlay_hint_provider         : bool `json:"inlayHintProvider"`,

	/**
	 * The server provides rename support. RenameOptions may only be
	 * specified if the client states that it supports
	 * `prepareSupport` in its initial `initialize` request.
	 */
	rename_provider             : bool `json:"renameProvider"`,

	/**
	 * The server provides find references support.
	 */
	references_provider          : bool `json:"referencesProvider"`,

	/**
	 * The server provides document highlight support.
	 */
	document_highlight_provider  : bool `json:"documentHighlightProvider"`,

	/**
	 * The server provides workspace symbol support.
	 */
	workspace_symbol_provider   : bool `json:"workspaceSymbolProvider"`,

	/**
	 * The server provides document link support.
	 */
	document_link_provider      : Maybe(Document_Link_Options) `json:"documentLinkProvider"`,

	/**
	 * The server provides code actions.
	 */
	code_action_provider        : bool `json:"codeActionProvider"`,

	/**
	 * The server provides code lens support.
	 */
	code_lens_provider          : Maybe(Code_Lens_Options) `json:"codeLensProvider"`,

	/**
	 * The server provides execute command support.
	 */
	execute_command_provider    : Maybe(Execute_Command_Options) `json:"executeCommandProvider"`,
}

Code_Lens_Options :: struct {
	resolve_provider: bool `json:"resolveProvider"`,
}

Execute_Command_Options :: struct {
	commands: []string,
}

Code_Lens :: struct {
	range:     Range,
	command:   Maybe(Command) `json:"command"`,
	data:      Maybe(json.Value) `json:"data"`,
}

Command :: struct {
	title:     string,
	command:   string,
	arguments: Maybe([]json.Value) `json:"arguments"`,
}

Code_Lens_Params :: struct {
	text_document:   Text_Document_Identifier `json:"textDocument"`,
	work_done_token: Maybe(Progress_Token) `json:"workDoneToken"`,
}

Server_Info :: struct {
	name   : string,
	version: string,
}



Completion_Item_Kind :: enum {
	Text          = 1,
	Method        = 2,
	Function      = 3,
	Constructor   = 4,
	Field         = 5,
	Variable      = 6,
	Class         = 7,
	Interface     = 8,
	Module        = 9,
	Property      = 10,
	Unit          = 11,
	Value         = 12,
	Enum          = 13,
	Keyword       = 14,
	Snippet       = 15,
	Color         = 16,
	File          = 17,
	Reference     = 18,
	Folder        = 19,
	Enum_Member    = 20,
	Constant      = 21,
	Struct        = 22,
	Event         = 23,
	Operator      = 24,
	TypeParameter = 25,
}

// @since 3.17.0
Completion_Item_Label_Details :: struct {
	detail     : string `json:"detail,omitempty"`,
	description: string `json:"description,omitempty"`,
}

Insert_Text_Format :: enum {
	Plain_Text = 1,
	Snippet    = 2,
}

Completion_Item :: struct {
	label           : string,
	labelDetails    : Maybe(Completion_Item_Label_Details) `json:"labelDetails,omitempty"`,
	kind            : Completion_Item_Kind,
	detail          : string `json:"detail,omitempty"`,
	documentation   : Maybe(Markup_Content) `json:"documentation,omitempty"`,
	insertText      : string `json:"insertText,omitempty"`,
	insertTextFormat: Maybe(Insert_Text_Format) `json:"insertTextFormat,omitempty"`,
	textEdit        : Maybe(Text_Edit) `json:"textEdit,omitempty"`,
	filterText      : string `json:"filterText,omitempty"`,
	command         : Maybe(Command) `json:"command,omitempty"`,
	// Opaque payload for completionItem/resolve (P2). Kept as json.Value so the
	// server can stash small structured keys without a dedicated wire type.
	data            : Maybe(json.Value) `json:"data,omitempty"`,
}

Completion_List :: struct {
	isIncomplete: bool,
	items: []Completion_Item,
}

Signature_Information :: struct {
	label        : string,
	documentation: string,
	parameters   : []Parameter_Information,
}

Parameter_Information  :: struct {
	label: string,
}

Signature_Help :: struct {
	signatures     : []Signature_Information,
	activeSignature: int,
	activeParameter: int,
}

Symbol_Kind :: enum {
	File          = 1,
	Module        = 2,
	Namespace     = 3,
	Package       = 4,
	Class         = 5,
	Method        = 6,
	Property      = 7,
	Field         = 8,
	Constructor   = 9,
	Enum          = 10,
	Interface     = 11,
	Function      = 12,
	Variable      = 13,
	Constant      = 14,
	String        = 15,
	Number        = 16,
	Boolean       = 17,
	Array         = 18,
	Object        = 19,
	Key           = 20,
	Null          = 21,
	Enum_Member    = 22,
	Struct        = 23,
	Event         = 24,
	Operator      = 25,
	Type_Parameter = 26,
}

Document_Symbol :: struct {
	name: string,
	detail: string `json:"detail,omitempty"`,
	kind: Symbol_Kind,
	range: Range,
	selection_range: Range `json:"selectionRange"`,
	children: []Document_Symbol,
}



Markup_Content :: struct {
	kind : string,
	value: string,
}

Hover :: struct {
	contents: Markup_Content,
	range   : Range,
}

Text_Edit :: struct {
	range  : Range,
	new_text: string `json:"newText"`,
}

Insert_Replace_Edit :: struct {
	insert : Range,
	new_text: string `json:"newText"`,
	replace: Range,
}

Inlay_Hint_Kind :: enum {
	Type      = 1,
	Parameter = 2,
}

Inlay_Hint :: struct {
	position: Position,
	kind    : Inlay_Hint_Kind,
	label   : string,
}

Document_Link_Client_Capabilities :: struct {
	tooltip_support: bool `json:"tooltipSupport"`,
}

Text_Document_Identifier :: struct {
	uri: string,
}

Document_Link_Params :: struct {
	text_document: Text_Document_Identifier `json:"textDocument"`,
}

Document_Link :: struct {
	range  : Range,
	target : string,
	tooltip: string,
}

Workspace_Symbol :: struct {
	name: string,
	kind: Symbol_Kind,
	location: Location,
}

Text_Document_Item :: struct {
	uri:         string,
	language_id: string `json:"languageId"`,
	version:     int,
	text:        string,
}

Versioned_Text_Document_Identifier :: struct {
	uri:     string,
	version: int,
}

Text_Document_Content_Change_Event :: struct {
	range:        Maybe(Range),
	range_length: Maybe(int) `json:"rangeLength"`,
	text:         string,
}

Document_Highlight_Kind :: enum {
	Text  = 1,
	Read  = 2,
	Write = 3,
}

Document_Highlight :: struct {
	range: Range,
	kind:  Maybe(Document_Highlight_Kind),
}

Prepare_Rename_Result :: struct {
	range: Range,
	placeholder: Maybe(string),
}

Optinal_Versioned_Text_Document_Identifier :: struct {
	uri    : string,
	version: Maybe(int),
}

Text_Document_Edit :: struct {
	textDocument: Optinal_Versioned_Text_Document_Identifier,
	edits: []Text_Edit,
}

Workspace_Edit :: struct {
	documentChanges: []Text_Document_Edit,
}

Code_Action :: struct {
	title       : string,
	kind        : string `json:"kind,omitempty"`,
	is_preferred: bool `json:"isPreferred,omitempty"`,
	edit        : Workspace_Edit,
}




Error_Code :: enum {
	// Defined by JSON-RPC
	Parse_Error      = -32700,
	Invalid_Request  = -32600,
	Method_Not_Found = -32601,
	Invalid_Params   = -32602,
	Internal_Error   = -32603,

	/**
	 * This is the range of JSON-RPC reserved error codes.
	 * It doesn't denote a real error code. No LSP error codes should
	 * be defined between the start and end range. For backwards
	 * compatibility the `ServerNotInitialized` and the `UnknownErrorCode`
	 * are left in the range.
	 *
	 * @since 3.16.0
	 */
	JSONRPC_Reserved_Error_Range_Start = -32099,
	Server_Not_Initialized             = -32002,
	Unknown_Error_Code                 = -32001,
	JSONRPC_Reserved_Error_Range_End   = -32000,

	/**
	 * This is the start range of LSP reserved error codes.
	 * It doesn't denote a real error code.
	 *
	 * @since 3.16.0
	 */
	LSP_Reserved_Error_Range_Start = -32899,

	/**
	 * A request failed but it was syntactically correct, e.g the
	 * method name was known and the parameters were valid. The error
	 * message should contain human readable information about why
	 * the request failed.
	 *
	 * @since 3.17.0
	 */
	Request_Failed = -32803,

	/**
	 * The server cancelled the request. This error code should
	 * only be used for requests that explicitly support being
	 * server cancellable.
	 *
	 * @since 3.17.0
	 */
	Server_Cancelled = -32802,

	/**
	 * The server detected that the content of a document got
	 * modified outside normal conditions. A server should
	 * NOT send this error code if it detects a content change
	 * in it unprocessed messages. The result even computed
	 * on an older state might still be useful for the client.
	 *
	 * If a client decides that a result is not of any use anymore
	 * the client should cancel the request.
	 */
	Content_Modified = -32801,

	/**
	 * The client has canceled a request and a server has detected
	 * the cancel.
	 */
	Request_Cancelled = -32800,

	/**
	 * This is the end range of LSP reserved error codes.
	 * It doesn't denote a real error code.
	 *
	 * @since 3.16.0
	 */
	LSP_Reserved_Error_Range_End = -32800,
}



/**
 * Completion item tags are extra annotations that tweak the rendering of a
 * completion item.
 *
 * @since 3.15.0
 */
Completion_Item_Tag :: enum {
	/**
	 * Render a completion as obsolete, usually using a strike-out.
	 */
	Deprecated = 1,
}

/**
 * How whitespace and indentation is handled during completion
 * item insertion.
 *
 * @since 3.16.0
 */
Insert_Text_Mode :: enum {
	/**
	 * The insertion or replace strings is taken as it is. If the
	 * value is multi line the lines below the cursor will be
	 * inserted using the indentation defined in the string value.
	 * The client will not apply any kind of adjustments to the
	 * string.
	 */
	As_Is = 1,

	/**
	 * The editor adjusts leading whitespace of new lines so that
	 * they match the indentation up to the cursor of the line for
	 * which the item is accepted.
	 *
	 * Consider a line like this: <2tabs><cursor><3tabs>foo. Accepting a
	 * multi line completion item is indented using 2 tabs and all
	 * following lines inserted will be indented using 2 tabs as well.
	 */
	Adjust_Indentation = 2,
}

Prepare_Support_Default_Behavior :: enum {
	/**
	 * The client's default behavior is to select the identifier
	 * according to the language's syntax rule.
	 */
	Identifier = 1,
}

/**
 * The diagnostic tags.
 *
 * @since 3.15.0
 */
Diagnostic_Tag :: enum {
	/**
	 * Unused or unnecessary code.
	 *
	 * Clients are allowed to render diagnostics with this tag faded out
	 * instead of having an error squiggle.
	 */
	Unnecessary = 1,

	/**
	 * Deprecated or obsolete code.
	 *
	 * Clients are allowed to rendered diagnostics with this tag strike through.
	 */
	Deprecated = 2,
}

send :: proc(msg: any, writer: io.Writer) -> bool {
	data, marshal_error := json.marshal(msg, {}, context.temp_allocator)
	
	if marshal_error != nil {
		log.errorf("Error %v. Failed to marshal message %v", marshal_error, msg)
		return false
	}

	header := fmt.tprintf("Content-Length: %v\r\n\r\n", len(data))
	
	if _, err := io.write_string(writer, header); err != nil {
		return false
	}

	if _, err := io.write_string(writer, transmute(string)data); err != nil {
		return false
	}

	return true
}

send_notification :: proc(method: string, params: $T, writer: io.Writer) -> bool {
	notif := Notification_Message(T){
		jsonrpc = "2.0",
		method  = method,
		params  = params,
	}
	return send(notif, writer)
}

send_response :: proc(id: Request_Id, result: Response_Params, writer: io.Writer, error: Maybe(Response_Error) = nil) {
	response: Response_Message
	response.jsonrpc = "2.0"
	response.id = id
	if err, has_err := error.?; has_err {
		response.error = err
	} else {
		response.result = result
	}
	send(response, writer)
}

send_null_result :: proc(id: Request_Id, writer: io.Writer, error: Maybe(Response_Error) = nil) {
	send_response(id, json.Value(json.Null{}), writer, error)
}

reply_rpc_error :: proc(id: Request_Id, code: Error_Code, message: string, writer: io.Writer) {
	if id == nil do return
	send_null_result(id, writer, Response_Error{code = code, message = message})
}


read_byte :: proc(reader: io.Reader) -> (b: u8, ok: bool) {
	buf: [1]u8
	n, err := io.read(reader, buf[:])
	if err != nil || n != 1 {
		return 0, false
	}
	return buf[0], true
}

// Pipes may return partial reads — loop until the buffer is full.
read_full :: proc(reader: io.Reader, data: []u8) -> bool {
	n := 0
	for n < len(data) {
		got, err := io.read(reader, data[n:])
		if err != nil || got == 0 {
			return false
		}
		n += got
	}
	return true
}

read_until_byte :: proc(reader: io.Reader, delimiter: u8, sb: ^strings.Builder) -> bool {
	for {
		b, ok := read_byte(reader)
		if !ok {
			return false
		}
		strings.write_byte(sb, b)
		if b == delimiter {
			return true
		}
	}
}

read_header :: proc(reader: io.Reader) -> (header: Header, ok: bool) {
	sb := strings.builder_make(context.temp_allocator)
	found_content_length := false
	for {
		strings.builder_reset(&sb)
		if !read_until_byte(reader, '\n', &sb) {
			log.errorf("Failed to read header line")
			return {}, false
		}
		message := strings.to_string(sb)
		if len(message) < 2 || message[len(message) - 2] != '\r' {
			log.errorf("No carriage return in header")
			return {}, false
		}
		if len(message) == 2 {
			break
		}

		index := strings.last_index_byte(message, ':')
		if index == -1 {
			log.errorf("Failed to find colon in header line %s", message)
			return {}, false
		}
		header_name := message[:index]
		header_value := message[len(header_name) + 2 : len(message) - 2]
		switch header_name {
		case "Content-Length":
			if len(header_value) == 0 {
				log.errorf("Header %s has no value", header_name)
				return {}, false
			}
			value, value_parsed := strconv.parse_int(header_value)
			if !value_parsed {
				log.errorf("Failed to parse content length value")
				return {}, false
			}
			header.content_length = value
			found_content_length = true
		case "Content-Type":
			if len(header_value) == 0 {
				log.errorf("Header %s has no value", header_name)
				return {}, false
			}
			header.content_type = strings.clone(header_value, context.temp_allocator)
		}
	}
	return header, found_content_length
}

read_body :: proc(reader: io.Reader, header: Header, allocator := context.allocator) -> (json.Object, bool) {
	data := make([]u8, header.content_length, context.temp_allocator)
	if !read_full(reader, data) {
		log.errorf("Failed to read body")
		return nil, false
	}
	value, parse_err := json.parse(data = data, parse_integers = true, allocator = allocator)
	if parse_err != nil {
		log.errorf("Failed to parse body: %v", parse_err)
		return nil, false
	}
	return value.(json.Object), true
}



server_init_stdio :: proc(s: ^Server) {
	s.read  = os.to_stream(os.stdin)
	s.write = os.to_stream(os.stdout)
	s.err   = os.to_stream(os.stderr)
}

Server :: struct {
	read : io.Reader,
	write: io.Writer,
	err  : io.Writer,

	callbacks: struct {
		on_initialize:              proc(id: Request_Id, params: Initialize_Params) -> (result: Initialize_Result, error: Maybe(Response_Error)),
		on_initialized:             proc(params: Initialized_Params),
		on_shutdown:                proc(id: Request_Id) -> (error: Maybe(Response_Error)),
		on_exit:                    proc(),
		on_document_open:           proc(params: Did_Open_Text_Document_Params),
		on_document_change:         proc(params: Did_Change_Text_Document_Params),
		on_document_close:          proc(params: Did_Close_Text_Document_Params),
		on_document_save:           proc(params: Did_Save_Text_Document_Params),
		on_did_change_configuration: proc(params: Did_Change_Configuration_Params),
		on_did_change_watched_files: proc(params: Did_Change_Watched_Files_Params),
		on_hover:                   proc(id: Request_Id, params: Hover_Params) -> (result: Maybe(Hover), error: Maybe(Response_Error)),
		on_definition:              proc(id: Request_Id, params: Definition_Params) -> (result: []Location, error: Maybe(Response_Error)),
		on_type_definition:         proc(id: Request_Id, params: Definition_Params) -> (result: []Location, error: Maybe(Response_Error)),
		on_document_symbol:         proc(id: Request_Id, params: Document_Symbol_Params) -> (result: []Document_Symbol, error: Maybe(Response_Error)),
		on_completion:              proc(id: Request_Id, params: Completion_Params) -> (result: Completion_List, error: Maybe(Response_Error)),
		on_completion_resolve:      proc(id: Request_Id, params: Completion_Item) -> (result: Completion_Item, error: Maybe(Response_Error)),
		on_signature_help:          proc(id: Request_Id, params: Signature_Help_Params) -> (result: Maybe(Signature_Help), error: Maybe(Response_Error)),
		on_inlay_hint:              proc(id: Request_Id, params: Inlay_Hint_Params) -> (result: []Inlay_Hint, error: Maybe(Response_Error)),
		on_semantic_tokens_full:    proc(id: Request_Id, params: Semantic_Tokens_Params) -> (result: Semantic_Tokens, error: Maybe(Response_Error)),
		on_semantic_tokens_range:   proc(id: Request_Id, params: Semantic_Tokens_Range_Params) -> (result: Semantic_Tokens, error: Maybe(Response_Error)),
		on_references:              proc(id: Request_Id, params: Reference_Params) -> (result: []Location, error: Maybe(Response_Error)),
		on_document_highlight:      proc(id: Request_Id, params: Document_Highlight_Params) -> (result: []Document_Highlight, error: Maybe(Response_Error)),
		on_prepare_rename:          proc(id: Request_Id, params: Prepare_Rename_Params) -> (result: Maybe(Range), error: Maybe(Response_Error)),
		on_rename:                  proc(id: Request_Id, params: Rename_Params) -> (result: Maybe(Workspace_Edit), error: Maybe(Response_Error)),
		on_workspace_symbol:        proc(id: Request_Id, params: Workspace_Symbol_Params) -> (result: []Workspace_Symbol, error: Maybe(Response_Error)),
		on_document_link:           proc(id: Request_Id, params: Document_Link_Params) -> (result: []Document_Link, error: Maybe(Response_Error)),
		on_code_action:             proc(id: Request_Id, params: Code_Action_Params) -> (result: []Code_Action, error: Maybe(Response_Error)),
		on_code_lens:               proc(id: Request_Id, params: Code_Lens_Params) -> (result: []Code_Lens, error: Maybe(Response_Error)),
		on_fmag_preview:            proc(id: Request_Id, params: json.Value) -> (result: json.Value, error: Maybe(Response_Error)),
		on_spirv_preview:           proc(id: Request_Id, params: json.Value) -> (result: json.Value, error: Maybe(Response_Error)),
	},
}


poll_message :: proc(s: ^Server) -> bool {
	header, header_ok := read_header(s.read)
	if !header_ok {
		log.error("Failed to read header")
		return false
	}
	content_data := make([]u8, header.content_length, context.temp_allocator)
	if !read_full(s.read, content_data) {
		log.errorf("Failed to read the message body (%d bytes)", header.content_length)
		return false
	}

	pm: Partial_Message
	pm_parse_err := json.unmarshal(content_data, &pm, allocator = context.temp_allocator)
	if pm_parse_err != nil {
		log.errorf("Failed to partially parse the message: %v", pm_parse_err)
		return true
	}

	method := pm.method
	id := pm.id
	callbacks := &s.callbacks

	parse_fail :: proc(method: string, err: json.Unmarshal_Error, id: Request_Id, writer: io.Writer) {
		log.errorf("Failed to parse parameters for message %s. Error %v", method, err)
		reply_rpc_error(id, .Invalid_Params, fmt.tprintf("failed to parse %s", method), writer)
	}

	switch method {
	case "initialize":
		msg: Request_Message(Initialize_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_initialize != nil {
			result, err := callbacks.on_initialize(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "initialized":
		msg: Notification_Message(Initialized_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_initialized != nil {
			callbacks.on_initialized(msg.params)
		}

	case "shutdown":
		if callbacks.on_shutdown != nil {
			err := callbacks.on_shutdown(id)
			send_null_result(id, s.write, err)
		} else {
			send_null_result(id, s.write, nil)
		}

	case "exit":
		if callbacks.on_exit != nil {
			callbacks.on_exit()
		}
		return false

	case "textDocument/didOpen":
		msg: Notification_Message(Did_Open_Text_Document_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_document_open != nil {
			callbacks.on_document_open(msg.params)
		}

	case "textDocument/didChange":
		msg: Notification_Message(Did_Change_Text_Document_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_document_change != nil {
			callbacks.on_document_change(msg.params)
		}

	case "textDocument/didClose":
		msg: Notification_Message(Did_Close_Text_Document_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_document_close != nil {
			callbacks.on_document_close(msg.params)
		}

	case "textDocument/didSave":
		msg: Notification_Message(Did_Save_Text_Document_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_document_save != nil {
			callbacks.on_document_save(msg.params)
		}

	case "workspace/didChangeConfiguration":
		msg: Notification_Message(Did_Change_Configuration_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_did_change_configuration != nil {
			callbacks.on_did_change_configuration(msg.params)
		}

	case "workspace/didChangeWatchedFiles":
		msg: Notification_Message(Did_Change_Watched_Files_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_did_change_watched_files != nil {
			callbacks.on_did_change_watched_files(msg.params)
		}

	case "textDocument/hover":
		msg: Request_Message(Hover_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_hover != nil {
			result, err := callbacks.on_hover(id, msg.params)
			if h, ok := result.?; ok {
				send_response(id, h, s.write, err)
			} else {
				send_null_result(id, s.write, err)
			}
		}

	case "textDocument/definition":
		msg: Request_Message(Definition_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_definition != nil {
			result, err := callbacks.on_definition(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "textDocument/typeDefinition":
		msg: Request_Message(Definition_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_type_definition != nil {
			result, err := callbacks.on_type_definition(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "textDocument/documentSymbol":
		msg: Request_Message(Document_Symbol_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_document_symbol != nil {
			result, err := callbacks.on_document_symbol(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "textDocument/completion":
		msg: Request_Message(Completion_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_completion != nil {
			result, err := callbacks.on_completion(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "completionItem/resolve":
		msg: Request_Message(Completion_Item)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_completion_resolve != nil {
			result, err := callbacks.on_completion_resolve(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "textDocument/signatureHelp":
		msg: Request_Message(Signature_Help_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_signature_help != nil {
			result, err := callbacks.on_signature_help(id, msg.params)
			if sh, ok := result.?; ok {
				send_response(id, sh, s.write, err)
			} else {
				send_null_result(id, s.write, err)
			}
		}

	case "textDocument/inlayHint":
		msg: Request_Message(Inlay_Hint_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_inlay_hint != nil {
			result, err := callbacks.on_inlay_hint(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "textDocument/semanticTokens/full":
		msg: Request_Message(Semantic_Tokens_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_semantic_tokens_full != nil {
			result, err := callbacks.on_semantic_tokens_full(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "textDocument/semanticTokens/range":
		msg: Request_Message(Semantic_Tokens_Range_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_semantic_tokens_range != nil {
			result, err := callbacks.on_semantic_tokens_range(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "textDocument/references":
		msg: Request_Message(Reference_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_references != nil {
			result, err := callbacks.on_references(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "textDocument/documentHighlight":
		msg: Request_Message(Document_Highlight_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_document_highlight != nil {
			result, err := callbacks.on_document_highlight(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "textDocument/prepareRename":
		msg: Request_Message(Prepare_Rename_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_prepare_rename != nil {
			result, err := callbacks.on_prepare_rename(id, msg.params)
			if r, ok := result.?; ok {
				send_response(id, r, s.write, err)
			} else {
				send_null_result(id, s.write, err)
			}
		}

	case "textDocument/rename":
		msg: Request_Message(Rename_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_rename != nil {
			result, err := callbacks.on_rename(id, msg.params)
			if edit, ok := result.?; ok {
				send_response(id, edit, s.write, err)
			} else {
				send_null_result(id, s.write, err)
			}
		}

	case "workspace/symbol":
		msg: Request_Message(Workspace_Symbol_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_workspace_symbol != nil {
			result, err := callbacks.on_workspace_symbol(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "textDocument/documentLink":
		msg: Request_Message(Document_Link_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_document_link != nil {
			result, err := callbacks.on_document_link(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "textDocument/codeAction":
		msg: Request_Message(Code_Action_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_code_action != nil {
			result, err := callbacks.on_code_action(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "textDocument/codeLens":
		msg: Request_Message(Code_Lens_Params)
		msg_parse_err := json.unmarshal(content_data, &msg, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_code_lens != nil {
			result, err := callbacks.on_code_lens(id, msg.params)
			send_response(id, result, s.write, err)
		}

	case "misl/fmagPreview":
		raw: struct {
			jsonrpc: string,
			id:      Request_Id,
			method:  string,
			params:  json.Value,
		}
		msg_parse_err := json.unmarshal(content_data, &raw, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_fmag_preview != nil {
			result, err := callbacks.on_fmag_preview(raw.id, raw.params)
			send_response(raw.id, result, s.write, err)
		}

	case "misl/spirvPreview":
		raw: struct {
			jsonrpc: string,
			id:      Request_Id,
			method:  string,
			params:  json.Value,
		}
		msg_parse_err := json.unmarshal(content_data, &raw, allocator = context.temp_allocator)
		if msg_parse_err != nil {
			parse_fail(method, msg_parse_err, id, s.write)
		} else if callbacks.on_spirv_preview != nil {
			result, err := callbacks.on_spirv_preview(raw.id, raw.params)
			send_response(raw.id, result, s.write, err)
		}

	case:
		log.logf(.Debug, "Received unhandled request %s", method)
		if id != nil {
			reply_rpc_error(id, .Method_Not_Found, fmt.tprintf("method not found: %s", method), s.write)
		}
	}


	return true
}

log_json_message :: proc(msg: json.Object) {
	opts: json.Marshal_Options
	opts.pretty = true
	data, err := json.marshal(msg, opts, context.temp_allocator)
	if err == nil {
		log.infof("Received message: %v", transmute(string)data)
	} else {
		log.warnf("Failed to log a received message: %v", err)
	}
}
