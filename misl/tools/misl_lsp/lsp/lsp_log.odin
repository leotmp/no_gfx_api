package lsp

import "base:runtime"
import "core:strings"
import "core:log"
import "core:fmt"
import "core:io"
import "core:os"
import "core:thread"
import "core:sync"
import "core:time"

Logger_Flag :: enum {
	Log_To_File,
}

Logger_Flags :: bit_set[Logger_Flag]

Logger :: struct {
	#subtype core_logger: log.Logger,
	using data: struct {
		out: io.Writer,
		err: io.Writer,
		flags: Logger_Flags,
	},
}

// Note(Dragos): these are handled by us. We dont' handle anything yet. Maybe remove these.
DEFAULT_LOGGER_OPTS := log.Options {
	.Level,
	.Terminal_Color,
	.Procedure,
	.Line,
}

logger_init :: proc(result: ^Logger, lower_level: log.Level, out: io.Writer, err: Maybe(io.Writer) = nil, opts := DEFAULT_LOGGER_OPTS) {
	result.out = out
	result.err = err.? or_else out
	result.core_logger.lowest_level = lower_level
	result.core_logger.options = opts
	result.core_logger.data = result // Note(Dragos): does this work?
	result.core_logger.procedure = logger_proc
}

logger_proc :: proc(
	data: rawptr, 
	level: log.Level, 
	text: string, 
	options: log.Options, 
	location :=  #caller_location
) {
	logger := cast(^Logger)data
	message := text
	message_type: Message_Type
	switch level {
	case .Debug:         message_type = .Log
	case .Info:          message_type = .Info
	case .Warning:       message_type = .Warning
	case .Error, .Fatal: message_type = .Error
	}

	notif := Notification_Message(Log_Message_Params) {
		jsonrpc = "2.0",
		method = "window/logMessage",
		params = Log_Message_Params {
			type = message_type,
			message = message,
		},
	}

	send(notif, logger.out if level < .Error else logger.err)

	{ // Mirror to local file for debugging (ignore open/write failures)
		@static first_message := true
		flags := os.O_CREATE | os.O_WRONLY | (os.O_TRUNC if first_message else os.O_APPEND)
		first_message = false
		file, err := os.open("misl_lsp.log", flags)
		if err == nil {
			os.write_string(file, message)
			os.write_byte(file, '\n')
			os.close(file)
		}
	}
}


write_caller_location :: proc(sb: ^strings.Builder, loc: runtime.Source_Code_Location) {
	strings.write_string(sb, loc.file_path)
	when ODIN_ERROR_POS_STYLE == .Default {
		strings.write_byte(sb, '(')
		strings.write_u64(sb, u64(loc.line))
		strings.write_byte(sb, ':')
		strings.write_u64(sb, u64(loc.column))
		strings.write_byte(sb, ')')
	} else when ODIN_ERROR_POS_STYLE == .Unix {
		strings.write_byte(sb, ':')
		write_u64(sb, u64(loc.line))
		strings.write_byte(sb, ':')
		write_u64(sb, u64(loc.column))
		strings.write_byte(sb, ':')
	} else {
		#panic("unhandled ODIN_ERROR_POS_STYLE")
	}
}

default_assertion_failure_proc :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
	sb := strings.builder_make(context.temp_allocator)
	when !ODIN_DISABLE_ASSERT {
		write_caller_location(&sb, loc)
		strings.write_string(&sb, " ")
	}
	strings.write_string(&sb, prefix)
	if len(message) > 0 {
		strings.write_string(&sb, ": ")
		strings.write_string(&sb, message)
	}
	//strings.write_byte(&sb, '\n')
	notif := Notification_Message(Log_Message_Params) {
		jsonrpc = "2.0",
		method = "window/logMessage",
		params = Log_Message_Params {
			type = .Error,
			message = strings.to_string(sb),
		},
	}
	
	send(notif, os.to_stream(os.stdout))
	time.sleep(100 * time.Millisecond) // if this works, i'm going to start doing amphetamines. (it worked). 
	runtime.trap()
	// Note(Dragos): sending to stderr seems to not really work for all clients. The better approach would be to save logs to a file.
}