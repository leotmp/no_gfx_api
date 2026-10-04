package lsp

import "core:log"

Semantic_Tokens_Options :: struct {
	legend: Semantic_Tokens_Legend,
	range : bool,
	full  : bool,
}

Semantic_Token_Type :: enum u32 {
	Namespace,
	/**
	 * Represents a generic type. Acts as a fallback for types which
	 * can't be mapped to a specific type like class or enum.
	 */
	Type,
	Class,
	Enum,
	Interface,
	Struct,
	Type_Parameter,
	Parameter,
	Variable,
	Property,
	Enum_Member,
	Event,
	Function,
	Method,
	Macro,
	Keyword,
	Modifier,
	Comment,
	String,
	Number,
	Regexp,
	Operator,
	/**
	 * @since 3.17.0
	 */
	Decorator,
}

semantic_token_type_strings := [Semantic_Token_Type]string {
	.Namespace      = "namespace",
	.Type           = "type",
	.Class          = "class",
	.Enum           = "enum",
	.Interface      = "interface",
	.Struct         = "struct",
	.Type_Parameter = "typeParameter",
	.Parameter      = "parameter",
	.Variable       = "variable",
	.Property       = "property",
	.Enum_Member    = "enumMember",
	.Event          = "event",
	.Function       = "function",
	.Method         = "method",
	.Macro          = "macro",
	.Keyword        = "keyword",
	.Modifier       = "modifier",
	.Comment        = "comment",
	.String         = "string",
	.Number         = "number",
	.Regexp         = "regexp",
	.Operator       = "operator",
	.Decorator      = "decorator",
}

Semantic_Token_Types :: bit_set[Semantic_Token_Type]

Semantic_Token_Modifier :: enum u32 {
	Declaration,
	Definition,
	Readonly,
	Static,
	Deprecated,
	Abstract,
	Async,
	Modification,
	Documentation,
	Default_Library,
}

Semantic_Token_Modifiers :: bit_set[Semantic_Token_Modifier; u32]

semantic_token_modifier_strings := [Semantic_Token_Modifier]string {
	.Declaration     = "declaration",
	.Definition      = "definition",
	.Readonly        = "readonly",
	.Static          = "static",
	.Deprecated      = "deprecated",
	.Abstract        = "abstract",
	.Async           = "async",
	.Modification    = "modification",
	.Documentation   = "documentation",
	.Default_Library = "defaultLibrary",
}

// Utility struct for encoding semantic tokens to be passed to the client
Token_Encoder :: struct {
	token_set: Semantic_Token_Types, // Supported tokens
	modifier_set: Semantic_Token_Modifiers, // Supported modifiers
	token_indices: [Semantic_Token_Type]int, // token legend
	modifier_bits: [Semantic_Token_Modifier]u32, // modifier legend
}

token_encoder_init :: proc(encoder: ^Token_Encoder, token_set: Semantic_Token_Types, modifier_set: Semantic_Token_Modifiers) {
	encoder.token_set = token_set
	encoder.modifier_set = modifier_set
	{ // Token types are looked by index in the slice we make based on the token_set
		index := 0
		for token in Semantic_Token_Type do if token in token_set {
			encoder.token_indices[token] = index
			index += 1
		}
	}

	{ // Token modifiers are also looked by index, but since a token can have multiple modifiers, we'll store the "bit" of each modifier. The index of a modifier is the bit set
		bit := u32(1)
		for modifier in Semantic_Token_Modifier do if modifier in modifier_set {
			encoder.modifier_bits[modifier] = bit
			bit <<= 1
		}
	}
}

encode_token_type :: proc(encoder: Token_Encoder, token_type: Semantic_Token_Type, loc := #caller_location) -> u32 {
	if token_type not_in encoder.token_set {
		log.errorf("Token type %v not found in the token set %v", token_type, encoder.token_set, location = loc)
		return 0
	}
	return auto_cast encoder.token_indices[token_type]
}

encode_token_modifiers :: proc(encoder: Token_Encoder, modifiers: Semantic_Token_Modifiers, loc := #caller_location) -> u32 {
	if modifiers > encoder.modifier_set {
		log.errorf("Requested modifier encoding for %v but the encoder supports %v", modifiers, encoder.modifier_set, location = loc)
		return 0
	}
	code := u32(0)
	for mod in Semantic_Token_Modifier do if mod in modifiers {
		code |= encoder.modifier_bits[mod]
	}
	return code
}

// These slices are to be passed to Server_Capabilities.semantic_token_provider.legend
token_encoder_make_capability_slices :: proc(encoder: Token_Encoder, allocator := context.allocator) -> (token_types: []string, token_modifiers: []string) {
	token_set := encoder.token_set
	modifier_set := encoder.modifier_set
	tokens_len := card(token_set) // The number of 1-bits the in the bitset
	modifiers_len := card(modifier_set)
	token_types = make([]string, tokens_len, allocator)
	token_modifiers = make([]string, modifiers_len, allocator)
	{
		index := 0
		for token in Semantic_Token_Type do if token in token_set {
			token_types[index] = semantic_token_type_strings[token]
			index += 1
		}
	}
	{
		index := 0
		for modifier in Semantic_Token_Modifier do if modifier in modifier_set {
			token_modifiers[index] = semantic_token_modifier_strings[modifier]
			index += 1
		}
	}
	return token_types, token_modifiers
}

Encoded_Token :: struct {
	line: u32,
	start_char: u32,
	length: u32,
	type: u32,
	modifiers: u32,
}

token_data_token_count :: proc(data: [dynamic]u32) -> int {
	return len(data) / 5
}

token_data_last_token :: proc(data: [dynamic]u32) -> Encoded_Token {
	return token_data_token_at(data, token_data_token_count(data) - 1)
}

token_data_token_at :: proc(data: [dynamic]u32, index: int) -> Encoded_Token {
	assert(index < token_data_token_count(data))
	start := data[index * 5 :]
	token: Encoded_Token
	token.line = start[0]
	token.start_char = start[1]
	token.length = start[2]
	token.type = start[3]
	token.modifiers = start[4]
	return token
}

token_data_append :: proc(data: ^[dynamic]u32, token: Encoded_Token) {
	append(data, token.line)
	append(data, token.start_char)
	append(data, token.length)
	append(data, token.type)
	append(data, token.modifiers)
}

Semantic_Tokens :: struct {
	/**
	 * An optional result ID. If provided and clients support delta updating,
	 * the client will include the result ID in the next semantic token request.
	 * A server can then, instead of computing all semantic tokens again, simply
	 * send a delta.
	 */
	result_id: Maybe(string) `json:"resultId"`,

	/**
	 * The actual tokens.
	 */
	data: []u32,
}

Semantic_Tokens_Partial_Result :: struct {
	data: []u32,
}

