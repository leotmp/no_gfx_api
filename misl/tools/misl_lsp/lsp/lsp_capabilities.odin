package lsp

import "core:encoding/json"

Workspace_Edit_Client_Capabilities :: struct {
	/**
	 * The client supports versioned document changes in `Workspace_Edit`s
	 */
	document_changes: bool `json:"documentChanges"`,

	/**
	 * The resource operations the client supports. Clients should at least
	 * support 'create', 'rename' and 'delete' files and folders.
	 *
	 * @since 3.13.0
	 */
	resource_operations: []string `json:"resourceOperations""`, // Todo(Dragos): Turn this into an enum on parse
	
	/**
	 * The failure handling strategy of a client if applying the workspace edit
	 * fails.
	 *
	 * @since 3.13.0
	 */
	failure_handling: Maybe(string) `json"failureHandling"`,
	
	/**
	 * Whether the client normalizes line endings to the client specific
	 * setting.
	 * If set to `true` the client will normalize line ending characters
	 * in a workspace edit to the client specific new line character(s).
	 *
	 * @since 3.16.0
	 */
	normalizes_line_endings: bool `json:"normalizesLineEndings"`,
	
	/**
	 * Whether the client in general supports change annotations on text edits,
	 * create file, rename file and delete file changes.
	 *
	 * @since 3.16.0
	 */
	change_annotation_support: Maybe(struct {
		/**
		 * Whether the client groups edits with equal labels into tree nodes,
		 * for instance all edits labelled with "Changes in Strings" would
		 * be a tree node.
		 */
		groups_on_label: bool `json"groupsOnLabel"`,
	}) `json:"changeAnnotationSupport"`
}

Did_Change_Configuration_Client_Capabilities :: struct {
	/**
	 * Did change configuration notification supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,
}

Did_Change_Watched_Files_Client_Capabilities :: struct {
	/**
	 * Did change watched files notification supports dynamic registration.
	 * Please note that the current protocol doesn't support static
	 * configuration for file changes from the server side.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,
	
	 /**
	 * Whether the client has support for relative patterns
	 * or not.
	 *
	 * @since 3.17.0
	 */
	relative_pattern_support: bool `json:"relativePatternSupport"`,
}

Workspace_Symbol_Client_Capabilities :: struct {
	/**
	 * Symbol request supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,

	/**
	 * Specific capabilities for the `Symbol_Kind` in the `workspace/symbol`
	 * request.
	 */
	symbol_kind: Maybe(struct {
		/**
		 * The symbol kind values the client supports. When this
		 * property exists the client also guarantees that it will
		 * handle values outside its set gracefully and falls back
		 * to a default value when unknown.
		 *
		 * If this property is not present the client only supports
		 * the symbol kinds from `File` to `Array` as defined in
		 * the initial version of the protocol.
		 */
		value_set: []Symbol_Kind `json"valueSet"`,
	}) `json:"symbolKind"`,

	/**
	 * The client supports tags on `Symbol_Information` and `Workspace_Symbol`.
	 * Clients supporting tags have to handle unknown tags gracefully.
	 *
	 * @since 3.16.0
	 */
	tag_support: Maybe(struct {
		/**
		 * The tags supported by the client.
		 */
		value_set: []Symbol_Tag,
	}) `json:"tagSupport"`,

	/**
	 * The client support partial workspace symbols. The client will send the
	 * request `workspaceSymbol/resolve` to the server to resolve additional
	 * properties.
	 *
	 * @since 3.17.0 - proposedState
	 */
	resolve_support: Maybe(struct {
		/**
		 * The properties that a client can resolve lazily. Usually
		 * `location.range`
		 */
		properties: []string,
	}) `json:"resolveSupport"`,
}

Execute_Command_Client_Capabilities :: struct {
	/**
	 * Execute command supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,
}



Semantic_Tokens_Workspace_Client_Capabilities :: struct {
	/**
	 * Whether the client implementation supports a refresh request sent from
	 * the server to the client.
	 *
	 * Note that this event is global and will force the client to refresh all
	 * semantic tokens currently shown. It should be used with absolute care
	 * and is useful for situation where a server for example detect a project
	 * wide change that requires such a calculation.
	 */
	refresh_support: bool `json:"refreshSupport"`,
}

Code_Lens_Workspace_Client_Capabilities :: struct {
	/**
	 * Whether the client implementation supports a refresh request sent from the
	 * server to the client.
	 *
	 * Note that this event is global and will force the client to refresh all
	 * code lenses currently shown. It should be used with absolute care and is
	 * useful for situation where a server for example detect a project wide
	 * change that requires such a calculation.
	 */
	refresh_support: bool `json:"refreshSupport"`,
}

/**
 * Client workspace capabilities specific to inline values.
 *
 * @since 3.17.0
 */
Inline_Value_Workspace_Client_Capabilities :: struct {
	/**
	 * Whether the client implementation supports a refresh request sent from
	 * the server to the client.
	 *
	 * Note that this event is global and will force the client to refresh all
	 * inline values currently shown. It should be used with absolute care and
	 * is useful for situation where a server for example detect a project wide
	 * change that requires such a calculation.
	 */
	refresh_support: bool `json:"refreshSupport"`,
}

Inlay_Hint_Workspace_Client_Capabilities :: struct {
	/**
	 * Whether the client implementation supports a refresh request sent from
	 * the server to the client.
	 *
	 * Note that this event is global and will force the client to refresh all
	 * inlay hints currently shown. It should be used with absolute care and
	 * is useful for situation where a server for example detects a project wide
	 * change that requires such a calculation.
	 */
	refresh_support: bool `json:"refreshSupport"`,
}

/**
 * Workspace client capabilities specific to diagnostic pull requests.
 *
 * @since 3.17.0
 */
Diagnostic_Workspace_Client_Capabilities :: struct {
	/**
	 * Whether the client implementation supports a refresh request sent from
	 * the server to the client.
	 *
	 * Note that this event is global and will force the client to refresh all
	 * pulled diagnostics currently shown. It should be used with absolute care
	 * and is useful for situation where a server for example detects a project
	 * wide change that requires such a calculation.
	 */
	refresh_support: bool `json:"refreshSupport"`,
}

Text_Document_Sync_Client_Capabilities :: struct {
	/**
	 * Whether text document synchronization supports dynamic registration.
	 */
	 dynamic_registration: bool `json:"dynamicRegistration"`,
	 
	/**
	 * The client supports sending will save notifications.
	 */
	 will_save: bool `json:"willSave"`,

	/**
	 * The client supports sending a will save request and
	 * waits for a response providing text edits which will
	 * be applied to the document before it is saved.
	 */
	will_save_wait_until: bool `json:"willSaveWaitUntil"`,

	/**
	 * The client supports did save notifications.
	 */
	did_save: bool `json:"didSave"`,
}

Completion_Client_Capabilities :: struct {
	/**
	 * Whether completion supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,
	
	/**
	 * The client supports the following `CompletionItem` specific
	 * capabilities.
	 */
	completion_item: Maybe(struct {
		/**
		 * Client supports snippets as insert text.
		 *
		 * A snippet can define tab stops and placeholders with `$1`, `$2`
		 * and `${3:foo}`. `$0` defines the final tab stop, it defaults to
		 * the end of the snippet. Placeholders with equal identifiers are
		 * linked, that is typing in one will update others too.
		 */
		snippet_support: bool `json:"snippetSupport"`,

		/**
		 * Client supports commit characters on a completion item.
		 */
		commit_characters_support: bool `json:"commitCharactersSupport"`,

		/**
		 * Client supports the follow content formats for the documentation
		 * property. The order describes the preferred format of the client.
		 */
		documentation_format: []string `json:"documentationFormat"`,

		/**
		 * Client supports the deprecated property on a completion item.
		 */
		deprecated_support: bool `json:"deprecatedSupport"`,

		/**
		 * Client supports the preselect property on a completion item.
		 */
		preselect_support: bool `json:"preselectSupport"`,

		/**
		 * Client supports the tag property on a completion item. Clients
		 * supporting tags have to handle unknown tags gracefully. Clients
		 * especially need to preserve unknown tags when sending a completion
		 * item back to the server in a resolve call.
		 *
		 * @since 3.15.0
		 */
		tag_support: Maybe(struct {
			value_set: []Completion_Item_Tag `json:"valueSet"`,
		}) `json:"tagSupport"`,

		/**
		 * Client supports insert replace edit to control different behavior if
		 * a completion item is inserted in the text or should replace text.
		 *
		 * @since 3.16.0
		 */
		insert_replace_support: bool `json:"insertReplaceSupport"`,

		/**
		 * Indicates which properties a client can resolve lazily on a
		 * completion item. Before version 3.16.0 only the predefined properties
		 * `documentation` and `detail` could be resolved lazily.
		 *
		 * @since 3.16.0
		 */
		resolve_support: Maybe(struct {
			/**
			 * The properties that a client can resolve lazily.
			 */
			properties: []string,
		}) `json:"resolveSupport"`,

		/**
		 * The client supports the `insert_text_mode` property on
		 * a completion item to override the whitespace handling mode
		 * as defined by the client (see `Insert_Text_Mode`).
		 *
		 * @since 3.16.0
		 */
		insert_text_mode_support: Maybe(struct {
			value_set: []Insert_Text_Mode `json:"valueSet"`,
		}) `json:"insertTextModeSupport"`,

		/**
		 * The client has support for completion item label
		 * details (see also `Completion_Item_Label_Details`).
		 *
		 * @since 3.17.0
		 */
		label_details_support: bool `json:"labelDetailsSupport"`,
	}) `json:"completionItem"`,
	
	completion_item_kind: Maybe(struct {
		/**
		 * The completion item kind values the client supports. When this
		 * property exists the client also guarantees that it will
		 * handle values outside its set gracefully and falls back
		 * to a default value when unknown.
		 *
		 * If this property is not present the client only supports
		 * the completion items kinds from `Text` to `Reference` as defined in
		 * the initial version of the protocol.
		 */
		value_set: []Completion_Item_Kind `json:"valueSet"`,
	}) `json:"completionItemKind"`,

	/**
	 * The client supports to send additional context information for a
	 * `textDocument/completion` request.
	 */
	context_support: bool `json:"contextSupport"`,

	/**
	 * The client's default when the completion item doesn't provide a
	 * `insert_text_mode` property.
	 *
	 * @since 3.17.0
	 */
	insert_text_mode: Maybe(Insert_Text_Mode) `json:"insertTextMode"`,

	/**
	 * The client supports the following `Completion_List` specific
	 * capabilities.
	 *
	 * @since 3.17.0
	 */
	 completion_list: Maybe(struct {
		/**
		 * The client supports the following itemDefaults on
		 * a completion list.
		 *
		 * The value lists the supported property names of the
		 * `CompletionList.itemDefaults` object. If omitted
		 * no properties are supported.
		 *
		 * @since 3.17.0
		 */
		item_defaults: []string `json:"itemDefaults"`,
	 }) `json:"completionList"`,
}

Hover_Client_Capabilities :: struct {
	/**
	 * Whether hover supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,

	/**
	 * Client supports the follow content formats if the content
	 * property refers to a `literal of type MarkupContent`.
	 * The order describes the preferred format of the client.
	 */
	content_format: []string `json:"contentFormat"`,
}

Signature_Help_Client_Capabilities :: struct {
	/**
	 * Whether signature help supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,

	/**
	 * The client supports the following `Signature_Information`
	 * specific properties.
	 */
	signature_information: Maybe(struct {
		/**
		 * Client supports the follow content formats for the documentation
		 * property. The order describes the preferred format of the client.
		 */
		documentation_format: []string `json:"documentationFormat"`,

		/**
		 * Client capabilities specific to parameter information.
		 */
		parameter_information: Maybe(struct {
			/**
			 * The client supports processing label offsets instead of a
			 * simple label string.
			 *
			 * @since 3.14.0
			 */
			label_offset_support: bool `json:"labelOffsetSupport"`,
		}) `json:"parameterInformation"`,

		/**
		 * The client supports the `activeParameter` property on
		 * `SignatureInformation` literal.
		 *
		 * @since 3.16.0
		 */
		active_parameter_support: bool `json:"activeParameterSupport"`,
	}) `json:"signatureInformation"`,

	/**
	 * The client supports to send additional context information for a
	 * `textDocument/signatureHelp` request. A client that opts into
	 * contextSupport will also support the `retriggerCharacters` on
	 * `Signature_Help_Options`.
	 *
	 * @since 3.15.0
	 */
	context_support: bool `json:"contextSupport"`,
}

Declaration_Client_Capabilities :: struct {
	/**
	 * Whether declaration supports dynamic registration. If this is set to
	 * `true` the client supports the new `Declaration_Registration_Options`
	 * return value for the corresponding server capability as well.
	 */
	 dynamic_registration: bool `json:"dynamicRegistration"`,

	 /**
	 * The client supports additional metadata in the form of declaration links.
	 */
	 link_support: bool `json:"linkSupport"`,
 
}

Definition_Client_Capabilities :: struct {
	/**
	 * Whether definition supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,

	/**
	 * The client supports additional metadata in the form of definition links.
	 *
	 * @since 3.14.0
	 */
	link_support: bool `json:"linkSupport"`,
}

Type_Definition_Client_Capabilities :: struct {
	/**
	 * Whether implementation supports dynamic registration. If this is set to
	 * `true` the client supports the new `TypeDefinitionRegistrationOptions`
	 * return value for the corresponding server capability as well.
	 */
	 dynamic_registration: bool `json:"dynamicRegistration"`,

	 /**
	 * The client supports additional metadata in the form of definition links.
	 *
	 * @since 3.14.0
	 */
	 link_support: bool `json:"linkSupport"`,
}

Implementation_Client_Capabilities :: struct {
	/**
	 * Whether implementation supports dynamic registration. If this is set to
	 * `true` the client supports the new `ImplementationRegistrationOptions`
	 * return value for the corresponding server capability as well.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,

	/**
	 * The client supports additional metadata in the form of definition links.
	 *
	 * @since 3.14.0
	 */
	 link_support: bool `json:"linkSupport"`,
}

Reference_Client_Capabilities :: struct {
	/**
	 * Whether references supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,
}

Document_Highlight_Client_Capabilities :: struct {
	/**
	 * Whether document highlight supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,
}

Document_Symbol_Client_Capabilities :: struct {
	/**
	 * Whether document symbol supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,

	/**
	 * Specific capabilities for the `SymbolKind` in the
	 * `textDocument/documentSymbol` request.
	 */
	symbol_kind: Maybe(struct {
		value_set: []Symbol_Kind `json:"valueSet"`,
	}) `json:"symbolKind"`,

	/**
	 * The client supports hierarchical document symbols.
	 */
	hierarchical_document_symbol_support: bool `json:"hierarchicalDocumentSymbolSupport"`,

	/**
	 * The client supports tags on `SymbolInformation`. Tags are supported on
	 * `DocumentSymbol` if `hierarchicalDocumentSymbolSupport` is set to true.
	 * Clients supporting tags have to handle unknown tags gracefully.
	 *
	 * @since 3.16.0
	 */
	tag_support: Maybe(struct {
		value_set: []Symbol_Kind,
	}) `json:"tagSupport"`,

	/**
	 * The client supports an additional label presented in the UI when
	 * registering a document symbol provider.
	 *
	 * @since 3.16.0
	 */
	label_support: bool `json:"labelSupport"`,
}

Code_Action_Client_Capabilities :: struct {
	/**
	 * Whether code action supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,

	/**
	 * The client supports code action literals as a valid
	 * response of the `textDocument/codeAction` request.
	 *
	 * @since 3.8.0
	 */
	code_action_literal_support: Maybe(struct {
		/**
		 * The code action kind is supported with the following value
		 * set.
		 */
		code_action_kind: Maybe(struct {
			/**
			 * The code action kind values the client supports. When this
			 * property exists the client also guarantees that it will
			 * handle values outside its set gracefully and falls back
			 * to a default value when unknown.
			 */
			value_set: []string `json:"valueSet"`,
		}) `json:"codeActionKind"`,
	}) `json:"codeActionLiteralSupport"`,

	/**
	 * Whether code action supports the `isPreferred` property.
	 *
	 * @since 3.15.0
	 */
	is_preferred_support: bool `json:"isPreferredSupport"`,

	/**
	 * Whether code action supports the `disabled` property.
	 *
	 * @since 3.16.0
	 */
	disabled_support: bool `json:"disabledSupport"`,

	/**
	 * Whether code action supports the `data` property which is
	 * preserved between a `textDocument/codeAction` and a
	 * `codeAction/resolve` request.
	 *
	 * @since 3.16.0
	 */
	data_support: bool `json:"dataSupport"`,

	/**
	 * Whether the client supports resolving additional code action
	 * properties via a separate `codeAction/resolve` request.
	 *
	 * @since 3.16.0
	 */
	resolve_support: Maybe(struct {
		/**
		 * The properties that a client can resolve lazily.
		 */
		properties: []string,
	}) `json:"resolveSupport"`,

	/**
	 * Whether the client honors the change annotations in
	 * text edits and resource operations returned via the
	 * `CodeAction#edit` property by for example presenting
	 * the workspace edit in the user interface and asking
	 * for confirmation.
	 *
	 * @since 3.16.0
	 */
	honors_change_annotations: bool `json:"honorsChangeAnnotations"`,
}

Document_Color_Client_Capabilities :: struct {
	/**
	 * Whether document color supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,
}

Document_Formatting_Client_Capabilities :: struct {
	/**
	 * Whether formatting supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,
}

Document_Range_Formatting_Client_Capabilities :: struct {
	/**
	 * Whether formatting supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,
}

Document_On_Type_Formatting_Client_Capabilities :: struct {
	/**
	 * A character on which formatting should be triggered, like `{`.
	 */
	first_trigger_character: string `json:"firstTriggerCharacter"`,

	/**
	 * More trigger characters.
	 */
	more_trigger_character: []string `json:"moreTriggerCharacter"`,
}

Rename_Client_Capabilities :: struct {
	/**
	 * Whether rename supports dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,

	/**
	 * Client supports testing for validity of rename operations
	 * before execution.
	 *
	 * @since version 3.12.0
	 */
	prepare_support: bool `json:"prepareSupport"`,

	/**
	 * Client supports the default behavior result
	 * (`{ defaultBehavior: boolean }`).
	 *
	 * The value indicates the default behavior used by the
	 * client.
	 *
	 * @since version 3.16.0
	 */
	prepare_support_default_behavior: Maybe(Prepare_Support_Default_Behavior) `json:"prepareSupportDefaultBehavior"`,

	/**
	 * Whether the client honors the change annotations in
	 * text edits and resource operations returned via the
	 * rename request's workspace edit by for example presenting
	 * the workspace edit in the user interface and asking
	 * for confirmation.
	 *
	 * @since 3.16.0
	 */
	honors_change_annotations: bool `json:"honorsChangeAnnotations"`,
}

Publish_Diagnostics_Client_Capabilities :: struct {
	/**
	 * Whether the clients accepts diagnostics with related information.
	 */
	related_information: bool `json:"relatedInformation"`,

	/**
	 * Client supports the tag property to provide meta data about a diagnostic.
	 * Clients supporting tags have to handle unknown tags gracefully.
	 *
	 * @since 3.15.0
	 */
	tag_support: Maybe(struct {
		/**
		 * The tags supported by the client.
		 */
		value_set: []Diagnostic_Tag `json:"valueSet"`,
	}) `json:"tagSupport"`,

	/**
	 * Whether the client interprets the version property of the
	 * `textDocument/publishDiagnostics` notification's parameter.
	 *
	 * @since 3.15.0
	 */
	version_support: bool `json:"versionSupport"`,

	/**
	 * Client supports a codeDescription property
	 *
	 * @since 3.16.0
	 */
	code_description_support: bool `json:"codeDescriptionSupport"`,

	/**
	 * Whether code action supports the `data` property which is
	 * preserved between a `textDocument/publishDiagnostics` and
	 * `textDocument/codeAction` request.
	 *
	 * @since 3.16.0
	 */
	data_support: bool `json:"dataSupport"`,
}

Folding_Range_Client_Capabilities :: struct {
	/**
	 * Whether implementation supports dynamic registration for folding range
	 * providers. If this is set to `true` the client supports the new
	 * `FoldingRangeRegistrationOptions` return value for the corresponding
	 * server capability as well.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,

	/**
	 * The maximum number of folding ranges that the client prefers to receive
	 * per document. The value serves as a hint, servers are free to follow the
	 * limit.
	 */
	range_limit: Maybe(int) `json:"rangeLimit"`,

	/**
	 * If set, the client signals that it only supports folding complete lines.
	 * If set, client will ignore specified `startCharacter` and `endCharacter`
	 * properties in a FoldingRange.
	 */
	line_folding_only: bool `json:"lineFoldingOnly"`,

	/**
	 * Specific options for the folding range kind.
	 *
	 * @since 3.17.0
	 */
	folding_range_kind: Maybe(struct {
		/**
		 * The folding range kind values the client supports. When this
		 * property exists the client also guarantees that it will
		 * handle values outside its set gracefully and falls back
		 * to a default value when unknown.
		 */
		value_set: []string `json:"valueSet"`,
	}) `json:"foldingRangeKind"`,

	/**
	 * Specific options for the folding range.
	 * @since 3.17.0
	 */
	folding_range: Maybe(struct {
		/**
		 * If set, the client signals that it supports setting collapsedText on
		 * folding ranges to display custom labels instead of the default text.
		 *
		 * @since 3.17.0
		 */
		collapsed_text: bool `json:"collapsedText"`,
	}) `json:"foldingRange"`,
}

Selection_Range_Client_Capabilities :: struct {
	/**
	 * Whether implementation supports dynamic registration for selection range
	 * providers. If this is set to `true` the client supports the new
	 * `SelectionRangeRegistrationOptions` return value for the corresponding
	 * server capability as well.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,
}

Linked_Editing_Range_Client_Capabilities :: struct {
	/**
	 * Whether the implementation supports dynamic registration.
	 * If this is set to `true` the client supports the new
	 * `(TextDocumentRegistrationOptions & StaticRegistrationOptions)`
	 * return value for the corresponding server capability as well.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,
}

Call_Hierarchy_Client_Capabilities :: struct {
	/**
	 * Whether implementation supports dynamic registration. If this is set to
	 * `true` the client supports the new `(Text_Document_Registration_Options &
	 * Static_Registration_Options)` return value for the corresponding server
	 * capability as well.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,
}

Semantic_Tokens_Client_Capabilities :: struct {
	/**
	 * Whether implementation supports dynamic registration. If this is set to
	 * `true` the client supports the new `(Text_Document_Registration_Options &
	 * Static_Registration_Options)` return value for the corresponding server
	 * capability as well.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,

	/**
	 * Which requests the client supports and might send to the server
	 * depending on the server's capability. Please note that clients might not
	 * show semantic tokens or degrade some of the user experience if a range
	 * or full request is advertised by the client but not provided by the
	 * server. If for example the client capability `requests.full` and
	 * `request.range` are both set to true but the server only provides a
	 * range provider the client might not render a minimap correctly or might
	 * even decide to not show any semantic tokens at all.
	 */
	requests: struct {
		/**
		 * The client will send the `textDocument/semanticTokens/range` request
		 * if the server provides a corresponding handler.
		 */
		range: union {bool, struct{}}, // Note(Dragos): What the fuck is this.

		/**
		 * The client will send the `textDocument/semanticTokens/full` request
		 * if the server provides a corresponding handler.
		 */
		full: union {bool, struct { // Note(Dragos): psychotic
			/**
			 * The client will send the `textDocument/semanticTokens/full/delta`
			 * request if the server provides a corresponding handler.
			 */
			delta: bool,
		}},
	},

	/**
	 * The token types that the client supports.
	 */
	token_types: []string `json:"tokenTypes"`,

	/**
	 * The token modifiers that the client supports.
	 */
	token_modifiers: []string `json:"tokenModifiers"`,

	/**
	 * The formats the clients supports.
	 */
	formats: []string,

	/**
	 * Whether the client supports tokens that can overlap each other.
	 */
	overlapping_token_support: bool `json:"overlappingTokenSupport"`,

	/**
	 * Whether the client supports tokens that can span multiple lines.
	 */
	multiline_token_support: bool `json:"multilineTokenSupport"`,

	/**
	 * Whether the client allows the server to actively cancel a
	 * semantic token request, e.g. supports returning
	 * ErrorCodes.ServerCancelled. If a server does the client
	 * needs to retrigger the request.
	 *
	 * @since 3.17.0
	 */
	server_cancel_support: bool `json:"serverCancelSupport"`,

	/**
	 * Whether the client uses semantic tokens to augment existing
	 * syntax tokens. If set to `true` client side created syntax
	 * tokens and semantic tokens are both used for colorization. If
	 * set to `false` the client only uses the returned semantic tokens
	 * for colorization.
	 *
	 * If the value is `undefined` then the client behavior is not
	 * specified.
	 *
	 * @since 3.17.0
	 */
	augments_syntax_tokens: bool `json:"augmentsSyntaxTokens"`,
}

Moniker_Client_Capabilities :: struct {
	/**
	 * Whether implementation supports dynamic registration. If this is set to
	 * `true` the client supports the new `(TextDocumentRegistrationOptions &
	 * StaticRegistrationOptions)` return value for the corresponding server
	 * capability as well.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,
}

Type_Hierarchy_Client_Capabilities :: struct {
	/**
	 * Whether implementation supports dynamic registration. If this is set to
	 * `true` the client supports the new `(TextDocumentRegistrationOptions &
	 * StaticRegistrationOptions)` return value for the corresponding server
	 * capability as well.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`
}

Inline_Value_Client_Capabilities :: struct {
	/**
	 * Whether implementation supports dynamic registration for inline
	 * value providers.
	 */
	 dynamic_registration: bool `json:"dynamicRegistration"`,
}

Inlay_Hint_Client_Capabilities :: struct {
	/**
	 * Whether inlay hints support dynamic registration.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,

	/**
	 * Indicates which properties a client can resolve lazily on an inlay
	 * hint.
	 */
	resolve_support: Maybe(struct {
		/**
		 * The properties that a client can resolve lazily.
		 */
		properties: []string,
	}) `json:"resolveSupport"`,
}

Diagnostic_Client_Capabilities :: struct {
	/**
	 * Whether implementation supports dynamic registration. If this is set to
	 * `true` the client supports the new
	 * `(Text_Document_Registration_Options & Static_Registration_Options)`
	 * return value for the corresponding server capability as well.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,

	/**
	 * Whether the clients supports related documents for document diagnostic
	 * pulls.
	 */
	related_document_support: bool `json:"relatedDocumentSupport"`,
}

/**
 * Text document specific client capabilities.
 */
Text_Document_Client_Capabilities :: struct {
	synchronization: Maybe(Text_Document_Sync_Client_Capabilities),

	/**
	 * Capabilities specific to the `textDocument/completion` request.
	 */
	completion: Maybe(Completion_Client_Capabilities),

	/**
	 * Capabilities specific to the `textDocument/hover` request.
	 */
	hover: Maybe(Hover_Client_Capabilities),

	/**
	 * Capabilities specific to the `textDocument/signatureHelp` request.
	 */
	signature_help: Maybe(Signature_Help_Client_Capabilities) `json:"signatureHelp"`,

	/**
	 * Capabilities specific to the `textDocument/declaration` request.
	 *
	 * @since 3.14.0
	 */
	declaration: Maybe(Declaration_Client_Capabilities),

	/**
	 * Capabilities specific to the `textDocument/definition` request.
	 */
	definition: Maybe(Definition_Client_Capabilities),

	/**
	 * Capabilities specific to the `textDocument/typeDefinition` request.
	 *
	 * @since 3.6.0
	 */
	type_definition: Type_Definition_Client_Capabilities `json:"typeDefinition"`,

	/**
	 * Capabilities specific to the `textDocument/implementation` request.
	 *
	 * @since 3.6.0
	 */
	implementation: Implementation_Client_Capabilities,

	/**
	 * Capabilities specific to the `textDocument/references` request.
	 */
	references: Maybe(Reference_Client_Capabilities),

	/**
	 * Capabilities specific to the `textDocument/documentHighlight` request.
	 */
	document_highlight: Maybe(Document_Highlight_Client_Capabilities) `json:"documentHighlight"`,

	/**
	 * Capabilities specific to the `textDocument/documentSymbol` request.
	 */
	document_symbol: Maybe(Document_Symbol_Client_Capabilities) `json:"documentSymbol"`,

	/**
	 * Capabilities specific to the `textDocument/codeAction` request.
	 */
	code_action: Maybe(Code_Action_Client_Capabilities) `json:"codeAction"`,

	/**
	 * Capabilities specific to the `textDocument/documentLink` request.
	 */
	document_link: Maybe(Document_Link_Client_Capabilities) `json:"documentLink"`,

	/**
	 * Capabilities specific to the `textDocument/documentColor` and the
	 * `textDocument/colorPresentation` request.
	 *
	 * @since 3.6.0
	 */
	color_provider: Maybe(Document_Color_Client_Capabilities) `json:"colorProvider"`,

	/**
	 * Capabilities specific to the `textDocument/formatting` request.
	 */
	formatting: Maybe(Document_Formatting_Client_Capabilities),

	/**
	 * Capabilities specific to the `textDocument/rangeFormatting` request.
	 */
	range_formatting: Maybe(Document_Range_Formatting_Client_Capabilities) `json:"rangeFormatting"`,

	/** request.
	 * Capabilities specific to the `textDocument/onTypeFormatting` request.
	 */
	on_type_formatting: Maybe(Document_On_Type_Formatting_Client_Capabilities) `json:"onTypeFormatting"`,

	/**
	 * Capabilities specific to the `textDocument/rename` request.
	 */
	rename: Maybe(Rename_Client_Capabilities),

	/**
	 * Capabilities specific to the `textDocument/publishDiagnostics`
	 * notification.
	 */
	publish_diagnostics: Maybe(Publish_Diagnostics_Client_Capabilities) `json:"publishDiagnostics"`,

	/**
	 * Capabilities specific to the `textDocument/foldingRange` request.
	 *
	 * @since 3.10.0
	 */
	folding_range: Maybe(Folding_Range_Client_Capabilities) `json:"foldingRange"`,

	/**
	 * Capabilities specific to the `textDocument/selectionRange` request.
	 *
	 * @since 3.15.0
	 */
	selection_range: Maybe(Selection_Range_Client_Capabilities) `json:"selectionRange"`,

	/**
	 * Capabilities specific to the `textDocument/linkedEditingRange` request.
	 *
	 * @since 3.16.0
	 */
	linked_editing_range: Maybe(Linked_Editing_Range_Client_Capabilities) `json:"linkedEditingRange"`,

	/**
	 * Capabilities specific to the various call hierarchy requests.
	 *
	 * @since 3.16.0
	 */
	call_hierarchy: Maybe(Call_Hierarchy_Client_Capabilities) `json:"callHierarchy"`,

	/**
	 * Capabilities specific to the various semantic token requests.
	 *
	 * @since 3.16.0
	 */
	semantic_tokens: Maybe(Semantic_Tokens_Client_Capabilities) `json:"semanticTokens"`,

	/**
	 * Capabilities specific to the `textDocument/moniker` request.
	 *
	 * @since 3.16.0
	 */
	moniker: Maybe(Moniker_Client_Capabilities),

	/**
	 * Capabilities specific to the various type hierarchy requests.
	 *
	 * @since 3.17.0
	 */
	type_hierarchy: Maybe(Type_Hierarchy_Client_Capabilities) `json:"typeHierarchy"`,

	/**
	 * Capabilities specific to the `textDocument/inlineValue` request.
	 *
	 * @since 3.17.0
	 */
	inline_value: Maybe(Inline_Value_Client_Capabilities) `json:"inlineValue"`,

	/**
	 * Capabilities specific to the `textDocument/inlayHint` request.
	 *
	 * @since 3.17.0
	 */
	inlay_hint: Maybe(Inlay_Hint_Client_Capabilities) `json:"inlayHint"`,

	/**
	 * Capabilities specific to the diagnostic pull model.
	 *
	 * @since 3.17.0
	 */
	diagnostic: Maybe(Diagnostic_Client_Capabilities),
}

Notebook_Document_Sync_Client_Capabilities :: struct {
	/**
	 * Whether implementation supports dynamic registration. If this is
	 * set to `true` the client supports the new
	 * `(NotebookDocumentSyncRegistrationOptions & NotebookDocumentSyncOptions)`
	 * return value for the corresponding server capability as well.
	 */
	dynamic_registration: bool `json:"dynamicRegistration"`,

	/**
	 * The client supports sending execution summary data per cell.
	 */
	execution_summary_support: bool `json:"executionSummarySupport"`,
}

/**
 * Capabilities specific to the notebook document support.
 *
 * @since 3.17.0
 */
Notebook_Document_Client_Capabilities :: struct {
	/**
	 * Capabilities specific to notebook document synchronization
	 *
	 * @since 3.17.0
	 */
	synchronization: Maybe(Notebook_Document_Sync_Client_Capabilities),
}

/**
 * Show message request client capabilities
 */
Show_Message_Request_Client_Capabilities :: struct {
	/**
	 * Capabilities specific to the `MessageActionItem` type.
	 */
	message_action_item: Maybe(struct {
		/**
		 * Whether the client supports additional attributes which
		 * are preserved and sent back to the server in the
		 * request's response.
		 */
		additional_properties_support: bool `json:"additionalPropertiesSupport"`,
	}) `json:"messageActionItem"`,
}

/**
 * Client capabilities for the show document request.
 *
 * @since 3.16.0
 */
Show_Document_Client_Capabilities :: struct {
	/**
	 * The client has support for the show document
	 * request.
	 */
	support: bool, // Note(Dragos): this is so cool that you wrap this in a struct { bool }
}

/**
 * Client capabilities specific to regular expressions.
 */
Regular_Expressions_Client_Capabilities :: struct {
	/**
	 * The engine's name.
	 */
	engine: string,

	/**
	 * The engine's version.
	 */
	version: Maybe(string),
}

/**
 * Client capabilities specific to the used markdown parser.
 *
 * @since 3.16.0
 */
Markdown_Client_Capabilities :: struct {
	/**
	 * The name of the parser.
	 */
	parser: string,
	
	/**
	 * The version of the parser.
	 */
	version: Maybe(string),

	/**
	 * A list of HTML tags that the client allows / supports in
	 * Markdown.
	 *
	 * @since 3.17.0
	 */
	allowed_tags: []string `json:"allowedTags"`,
}

Client_Capabilities :: struct {
	/**
	 * Workspace specific client capabilities.
	 */
	workspace: struct {
		/**
		 * The client supports applying batch edits
		 * to the workspace by supporting the request
		 * 'workspace/applyEdit'
		 */
		apply_edit: bool `json:"applyEdit"`,
		/**
		 * Capabilities specific to `WorkspaceEdit`s
		 */
		workspace_edit: Workspace_Edit_Client_Capabilities `json:"workspaceEdit"`,
		/**
		 * Capabilities specific to the `workspace/didChangeConfiguration`
		 * notification.
		 */
		did_change_configuration: Did_Change_Configuration_Client_Capabilities `json:"didChangeConfiguration"`,
		/**
		 * Capabilities specific to the `workspace/didChangeWatchedFiles`
		 * notification.
		 */
		did_change_watched_files: Did_Change_Watched_Files_Client_Capabilities `json:"didChangeWatchedFiles"`,
		/**
		 * Capabilities specific to the `workspace/symbol` request.
		 */
		symbol: Workspace_Symbol_Client_Capabilities,
		/**
		 * Capabilities specific to the `workspace/executeCommand` request.
		 */
		execute_command: Execute_Command_Client_Capabilities `json:"executeCommand"`,
		/**
		 * The client has support for workspace folders.
		 *
		 * @since 3.6.0
		 */
		workspace_folders: bool `json:"workspaceFolders"`,
		/**
		 * The client supports `workspace/configuration` requests.
		 *
		 * @since 3.6.0
		 */
		configuration: bool,
		/**
		 * Capabilities specific to the semantic token requests scoped to the
		 * workspace.
		 *
		 * @since 3.16.0
		 */
		semantic_tokens: Semantic_Tokens_Workspace_Client_Capabilities `json:"semanticTokens"`,
		/**
		 * Capabilities specific to the code lens requests scoped to the
		 * workspace.
		 *
		 * @since 3.16.0
		 */
		code_lens: Code_Lens_Workspace_Client_Capabilities `json:"codeLens"`,
		/**
		 * The client has support for file requests/notifications.
		 *
		 * @since 3.16.0
		 */
		file_operations: struct {
			/**
			 * Whether the client supports dynamic registration for file
			 * requests/notifications.
			 */
			dynamic_registration: bool `json:"dynamicRegistration"`,
			/**
			 * The client has support for sending didCreateFiles notifications.
			 */
			did_create: bool `json:"didCreate"`,
			/**
			 * The client has support for sending willCreateFiles requests.
			 */
			will_create: bool `json:"willCreate"`,
			/**
			 * The client has support for sending didRenameFiles notifications.
			 */
			did_rename_file: bool `json:"didRenameFile"`,
			/**
			 * The client has support for sending willRenameFiles requests.
			 */
			will_rename_file: bool `json:"willRenameFile"`,
			/**
			 * The client has support for sending didDeleteFiles notifications.
			 */
			did_delete: bool `json:"didDelete"`,
			/**
			 * The client has support for sending willDeleteFiles requests.
			 */
			will_delete: bool `json:"willDelete"`,
		} `json:"fileOperations"`,
		/**
		 * Client workspace capabilities specific to inline values.
		 *
		 * @since 3.17.0
		 */
		inline_value: Inline_Value_Workspace_Client_Capabilities `json:"inlineValue"`,
		/**
		 * Client workspace capabilities specific to inlay hints.
		 *
		 * @since 3.17.0
		 */
		inlay_hint: Inlay_Hint_Workspace_Client_Capabilities `json:"inlayHint"`,
		/**
		 * Client workspace capabilities specific to diagnostics.
		 *
		 * @since 3.17.0.
		 */
		 diagnostics: Diagnostic_Workspace_Client_Capabilities,
	},
	/**
	 * Text document specific client capabilities.
	 */
	text_document: Text_Document_Client_Capabilities `json:"textDocument"`,
	/**
	 * Capabilities specific to the notebook document support.
	 *
	 * @since 3.17.0
	 */
	notebook_document: Notebook_Document_Client_Capabilities `json:"notebookDocument"`,
	/**
	 * Window specific client capabilities.
	 */
	window: struct {
		/**
		 * It indicates whether the client supports server initiated
		 * progress using the `window/workDoneProgress/create` request.
		 *
		 * The capability also controls Whether client supports handling
		 * of progress notifications. If set servers are allowed to report a
		 * `workDoneProgress` property in the request specific server
		 * capabilities.
		 *
		 * @since 3.15.0
		 */
		work_done_progress: bool `json:"workDoneProgress"`,
		/**
		 * Capabilities specific to the showMessage request
		 *
		 * @since 3.16.0
		 */
		show_message: Show_Message_Request_Client_Capabilities `json:"showMessage"`,
		/**
		 * Client capabilities for the show document request.
		 *
		 * @since 3.16.0
		 */
		show_document: Show_Document_Client_Capabilities `json:"showDocument"`,
	},
	/**
	 * General client capabilities.
	 *
	 * @since 3.16.0
	 */
	general: struct {
		/**
		 * Client capability that signals how the client
		 * handles stale requests (e.g. a request
		 * for which the client will not process the response
		 * anymore since the information is outdated).
		 *
		 * @since 3.17.0
		 */
		stale_request_support: struct {
			/**
			 * The client will actively cancel the request.
			 */
			cancel: bool,
			/**
			 * The list of requests for which the client
			 * will retry the request if it receives a
			 * response with error code `ContentModified``
			 */
			retry_on_content_modified: []string `json:"retryOnContentModified"`,
		} `json:"stateRequestSupport"`,
		/**
		 * Client capabilities specific to regular expressions.
		 *
		 * @since 3.16.0
		 */
		regular_expressions: Regular_Expressions_Client_Capabilities `json:"regularExpressions"`,
		/**
		 * Client capabilities specific to the client's markdown parser.
		 *
		 * @since 3.16.0
		 */
		markdown: Markdown_Client_Capabilities,
		/**
		 * The position encodings supported by the client. Client and server
		 * have to agree on the same position encoding to ensure that offsets
		 * (e.g. character position in a line) are interpreted the same on both
		 * side.
		 *
		 * To keep the protocol backwards compatible the following applies: if
		 * the value 'utf-16' is missing from the array of position encodings
		 * servers can assume that the client supports UTF-16. UTF-16 is
		 * therefore a mandatory encoding.
		 *
		 * If omitted it defaults to ['utf-16'].
		 *
		 * Implementation considerations: since the conversion from one encoding
		 * into another requires the content of the file / line the conversion
		 * is best done where the file is read which is usually on the server
		 * side.
		 *
		 * @since 3.17.0
		 */
		position_encodings: []string `json:"positionEncodings"`,
	},
	/**
	 * Experimental client capabilities.
	 */
	 experimental: Maybe(json.Value), // Note(Dragos): How do we encode this properly? maybe a map?
}