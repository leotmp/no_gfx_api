package lsp

import "core:strings"
import "core:strconv"

uri_is_file :: proc(uri: string) -> bool {
	return strings.has_prefix(uri, "file:")
}

uri_to_filepath :: proc(uri: string, allocator := context.allocator) -> (path: string, ok: bool) {
	if !uri_is_file(uri) {
		return
	}
	starts := "file:///"
	if len(uri) < len(starts) {
		return
	}
	builder := strings.builder_make(allocator)
	uri := uri[len(starts):]
	for i := 0; i < len(uri); i += 1 {
		c := uri[i]
		if c == '%' { // Decode the %. It's an escape character followed by 2 HEX digits
			if i + 2 < len(uri) {
				v, parse_ok := strconv.parse_i64_of_base(uri[i + 1 : i + 3], 16)
				if !parse_ok {
					strings.builder_destroy(&builder)
					return
				}
				i += 2
				strings.write_byte(&builder, cast(byte)v)
			} else {
				strings.builder_destroy(&builder)
				return
			}
		} else {
			strings.write_byte(&builder, uri[i])
		}
	}
	return strings.to_string(builder), true
}

// Windows: file:///C:/path/to/file
filepath_to_uri :: proc(path: string, allocator := context.allocator) -> string {
	builder := strings.builder_make(allocator)
	strings.write_string(&builder, "file:///")
	normalized := path
	for i := 0; i < len(normalized); i += 1 {
		c := normalized[i]
		switch c {
		case '\\':
			strings.write_byte(&builder, '/')
		case ' ':
			strings.write_string(&builder, "%20")
		case:
			strings.write_byte(&builder, c)
		}
	}
	return strings.to_string(builder)
}
