package misl

// Collected by callers that override Error_Handler / Warning_Handler.
// Format the message in the handler (e.g. context.temp_allocator); no bag allocator.
Diagnostic_Severity :: enum {
	Error,
	Warning,
}

Diagnostic :: struct {
	pos:      Token_Pos,
	severity: Diagnostic_Severity,
	message:  string,
}
