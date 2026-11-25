package noslc

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import fpath "core:path/filepath"

import nosl "../.."

Exit_Code :: enum {
	Ok           = 0,
	Usage        = 1,
	Check_Failed = 2,
	Emit_Failed  = 3,
}

Command :: enum {
	Build,
	Check,
}

Target_Kind :: enum {
	Spirv,
	Asm,
	Fmag,
}
Targets :: bit_set[Target_Kind]

Dump_Kind :: enum {
	Tokens,
	Ast,
	Types,
}
Dump_Kinds :: bit_set[Dump_Kind]

Color_Mode :: enum {
	Auto,
	Always,
	Never,
}

Collection_Opt :: struct {
	name: string,
	path: string,
}

Options :: struct {
	command:      Command,
	inputs:       [dynamic]string,
	out_dir:      string,
	targets:      Targets,
	entries:      [dynamic]string,
	pipelines:    [dynamic]string,
	configs:      [dynamic]nosl.User_Config,
	collections:  [dynamic]Collection_Opt,
	list_entries: bool,
	quiet:        bool,
	no_bounds_check: bool,
	disable_asserts: bool,
	no_gfx:          bool,
	verbose:      bool,
	show_timings: bool,
	show_more_timings: bool,
	error_limit:  int,
	color:        Color_Mode,
	json:         bool,
	dumps:        Dump_Kinds,
	dump_path:    string,
	spirv_opt:    nosl.Optimization,
	debug:        bool,
	no_source:    bool,
	named_entry:  bool,
}

print_usage :: proc() {
	compat := ""
	when !nosl.NOSL_COMPAT_NOGFX {
		compat = `  -compat:no_gfx             no_gfx ABI: sets 0–3, compute SpecIds 13370–72, assert SpecId 13373.
                             SPIR-V: {stem}.spv, or {stem}.{entry}.spv when the file has several entries.
                             Implies -no-bounds-check and -disable-asserts
`
	}
	fmt.eprintf(
`noslc -- NOSL (no_gfx Shading Language) compiler

USAGE
  noslc build  <input.nosl> [flags]
  noslc check  <input.nosl> [flags]
  noslc <input.nosl> [flags]              same as build

FLAG STYLE (Odin)
  -flag
  -flag:key
  -flag:key=value

COMMANDS
  build     Parse, check, and emit outputs (default)
  check     Parse and typecheck only (no SPIR-V / file emit unless dumping)

BUILD / EMIT
  -out:<dir>                 Output directory for build artifacts
  -target:spirv              Write per-entry .spv (repeatable; default if no -target)
  -target:asm                Write per-entry SPIR-V assembly .spvasm and FMAG .fmagasm (repeatable)
  -target:fmag               Write per-entry FMAG bytecode .fmag (repeatable)
  -o:none                    SPIR-V optimizer (default). Also size, performance, all
                             performance aliases: perf, speed. all = -O then -Os
  -debug                     DebugInfo + OpLine + OpName/OpMemberName + embed NOSL source
  -no-source                 With -debug: skip DebugSource text (no-op otherwise)
  -named-entry               Direct OpEntryPoint uses the NOSL proc name (default is "main")
  -entry:<name>              Compile only this entry (repeatable)
  -pipeline:<name>           Compile this pipeline constant (stages + raster meta)
  -config:ident=value        Set a #config key for this check/compile (repeatable; covers imports)
  -collection:<name>=<path>  Named import root (repeatable); use as import "name:file.nosl"
                             core is built into the compiler; do not pass -collection:core
  -list-entries              Print entry and pipeline names, then exit

DIAGNOSTICS
  -quiet                     Errors only
  -no-bounds-check           Default off for []T index checks (overridden by #bounds_check)
  -disable-asserts           Typecheck debug.assert/panic; emit no claim
%s  -verbose                   Extra logging
  -error-limit:<n>           Stop after n errors (0 = unlimited)
  -color:auto                Color diagnostics (default)
  -color:always
  -color:never
  -json                      Machine-readable diagnostics

TIMINGS
  -show-timings              Print stage timings (parse/check/SPIRV sum)
  -show-more-timings         Implies -show-timings; split init; per-entry SPIRV phases

DUMPS (allowed on build and check)
  -dump:tokens               Dump lexer tokens
  -dump:ast                  Dump parsed AST
  -dump:types                Dump checked types / entities
  -dump-path:<path>          Directory for dump files (defaults to -out path)

NOTES
  Vulkan / SPIR-V language versions are fixed by the compiler
  and are not configurable via flags.

EXIT CODES
  0   Success
  1   Usage / unknown flag
  2   Parse or typecheck errors
  3   Emit, I/O, or backend failure

EXAMPLES
  noslc check path/to/shader.nosl
  noslc build shader.nosl -out:out/nosl_test
  noslc shader.nosl -out:out -target:spirv
  noslc shader.nosl -out:out -target:asm -o:all
  noslc shader.nosl -out:out -debug -no-source
  noslc build main.nosl -out:out -entry:sprite_vs -entry:sprite_fs
  noslc build main.nosl -out:out -pipeline:sprite_pipeline
  noslc check shader.nosl -dump:ast -dump-path:out/dumps
  noslc main.nosl -list-entries
`, compat)
}

parse_odin_flag :: proc(arg: string) -> (name, key, value: string, has_key, has_value: bool) {
	assert(strings.has_prefix(arg, "-"))
	body := arg[1:]
	colon := strings.index_byte(body, ':')
	if colon < 0 {
		return body, "", "", false, false
	}
	name = body[:colon]
	rest := body[colon + 1:]
	eq := strings.index_byte(rest, '=')
	if eq < 0 {
		return name, rest, "", true, false
	}
	return name, rest[:eq], rest[eq + 1:], true, true
}

parse_config_literal :: proc(s: string) -> (nosl.Exact_Value, bool) {
	switch s {
	case "true":
		return true, true
	case "false":
		return false, true
	}
	if i, ok := strconv.parse_i128(s); ok {
		return i, true
	}
	if f, ok := strconv.parse_f64(s); ok {
		return f, true
	}
	return nil, false
}

parse_options :: proc(args: []string) -> (opt: Options, ok: bool) {
	opt.command = .Build
	opt.color = .Auto
	opt.inputs = make([dynamic]string, context.temp_allocator)
	opt.entries = make([dynamic]string, context.temp_allocator)
	opt.pipelines = make([dynamic]string, context.temp_allocator)
	opt.configs = make([dynamic]nosl.User_Config, context.temp_allocator)
	opt.collections = make([dynamic]Collection_Opt, context.temp_allocator)

	i := 0
	if i < len(args) && len(args[i]) > 0 && args[i][0] != '-' {
		switch args[i] {
		case "build":
			opt.command = .Build
			i += 1
		case "check":
			opt.command = .Check
			i += 1
		}
	}

	for i < len(args) {
		a := args[i]
		i += 1
		if len(a) == 0 {
			continue
		}
		if a[0] != '-' {
			append(&opt.inputs, a)
			continue
		}

		name, key, value, has_key, has_value := parse_odin_flag(a)
		switch name {
		case "out":
			if !has_key {
				fmt.eprintfln("noslc: -out requires -out:<dir>")
				return opt, false
			}
			opt.out_dir = value if has_value else key
		case "target":
			if !has_key {
				fmt.eprintfln("noslc: use -target:spirv, -target:asm, or -target:fmag")
				return opt, false
			}
			switch key {
			case "spirv": opt.targets += {.Spirv}
			case "asm":   opt.targets += {.Asm}
			case "fmag":  opt.targets += {.Fmag}
			case:
				fmt.eprintfln("noslc: unknown -target:%s", key)
				return opt, false
			}
		case "o":
			if !has_key {
				fmt.eprintfln("noslc: use -o:none, -o:size, -o:performance, or -o:all")
				return opt, false
			}
			parsed, parsed_ok := nosl.parse_spirv_opt(key)
			if !parsed_ok {
				fmt.eprintfln("noslc: unknown -o:%s (use none, size, performance, all)", key)
				return opt, false
			}
			opt.spirv_opt = parsed
		case "debug":
			opt.debug = true
		case "no-source":
			opt.no_source = true
		case "named-entry":
			opt.named_entry = true
		case "entry":
			if !has_key {
				fmt.eprintfln("noslc: use -entry:<name>")
				return opt, false
			}
			append(&opt.entries, value if has_value else key)
		case "pipeline":
			if !has_key {
				fmt.eprintfln("noslc: use -pipeline:<name>")
				return opt, false
			}
			append(&opt.pipelines, value if has_value else key)
		case "config":
			if !has_key || !has_value {
				fmt.eprintfln("noslc: use -config:ident=value")
				return opt, false
			}
			cfg_val, cfg_ok := parse_config_literal(value)
			if !cfg_ok {
				fmt.eprintfln("noslc: invalid -config value '%s' (expected bool, int, or float)", value)
				return opt, false
			}
			append(&opt.configs, nosl.User_Config{name = key, value = cfg_val})
		case "list-entries":
			opt.list_entries = true
		case "quiet":
			opt.quiet = true
		case "no-bounds-check":
			opt.no_bounds_check = true
		case "disable-asserts":
			opt.disable_asserts = true
		case "compat":
			if !has_key {
				fmt.eprintfln("noslc: use -compat:no_gfx")
				return opt, false
			}
			switch key {
			case "no_gfx":
				opt.no_gfx = true
			case:
				fmt.eprintfln("noslc: unknown -compat:%s (use no_gfx)", key)
				return opt, false
			}
		case "verbose":
			opt.verbose = true
		case "show-timings":
			opt.show_timings = true
		case "show-more-timings":
			opt.show_more_timings = true
			opt.show_timings = true
		case "error-limit":
			if !has_key {
				fmt.eprintfln("noslc: use -error-limit:<n>")
				return opt, false
			}
			n, n_ok := strconv.parse_int(value if has_value else key)
			if !n_ok {
				fmt.eprintfln("noslc: invalid -error-limit")
				return opt, false
			}
			opt.error_limit = n
		case "color":
			if !has_key {
				fmt.eprintfln("noslc: use -color:auto|always|never")
				return opt, false
			}
			switch key {
			case "auto":   opt.color = .Auto
			case "always": opt.color = .Always
			case "never":  opt.color = .Never
			case:
				fmt.eprintfln("noslc: unknown -color:%s", key)
				return opt, false
			}
		case "json":
			opt.json = true
		case "dump":
			if !has_key {
				fmt.eprintfln("noslc: use -dump:tokens|ast|types")
				return opt, false
			}
			switch key {
			case "tokens": opt.dumps += {.Tokens}
			case "ast":    opt.dumps += {.Ast}
			case "types":  opt.dumps += {.Types}
			case:
				fmt.eprintfln("noslc: unknown -dump:%s", key)
				return opt, false
			}
		case "dump-path":
			if !has_key {
				fmt.eprintfln("noslc: use -dump-path:<path>")
				return opt, false
			}
			opt.dump_path = value if has_value else key
		case "collection":
			if !has_key || !has_value {
				fmt.eprintfln("noslc: use -collection:<name>=<path>")
				return opt, false
			}
			if key == "" || value == "" {
				fmt.eprintfln("noslc: use -collection:<name>=<path>")
				return opt, false
			}
			append(&opt.collections, Collection_Opt{name = key, path = value})
		case:
			fmt.eprintfln("noslc: unknown flag '%s'", a)
			return opt, false
		}
	}

	when nosl.NOSL_COMPAT_NOGFX {
		opt.no_gfx = true
	}


	if len(opt.inputs) == 0 {
		fmt.eprintfln("noslc: missing input .nosl file")
		return opt, false
	}
	if opt.command == .Build && !opt.list_entries && opt.out_dir == "" && opt.dumps == {} {
		fmt.eprintfln("noslc: build requires -out:<dir>")
		return opt, false
	}
	if opt.targets == {} {
		opt.targets = {.Spirv}
	}
	if opt.dump_path == "" {
		opt.dump_path = opt.out_dir
	}

	return opt, true
}

@(private)
_cli_diags: ^[dynamic]nosl.Diagnostic
@(private)
_cli_error_limit: int
@(private)
_cli_error_count: int
@(private)
_cli_use_color: bool

cli_collect_error :: proc(pos: nosl.Token_Pos, msg: string, args: ..any) {
	if _cli_diags == nil do return
	if _cli_error_limit > 0 && _cli_error_count >= _cli_error_limit do return
	_cli_error_count += 1
	append(_cli_diags, nosl.Diagnostic{
		pos = pos,
		severity = .Error,
		message = fmt.tprintf(msg, ..args),
	})
}

cli_collect_warning :: proc(pos: nosl.Token_Pos, msg: string, args: ..any) {
	if _cli_diags == nil do return
	append(_cli_diags, nosl.Diagnostic{
		pos = pos,
		severity = .Warning,
		message = fmt.tprintf(msg, ..args),
	})
}

want_color :: proc(mode: Color_Mode) -> bool {
	switch mode {
	case .Always: return true
	case .Never:  return false
	case .Auto:   return true
	}
	return false
}

print_diagnostic :: proc(d: nosl.Diagnostic) {
	sev := "error" if d.severity == .Error else "warning"
	if _cli_use_color {
		color := "\x1b[31m" if d.severity == .Error else "\x1b[33m"
		fmt.eprintf("%s%s\x1b[0m: %v:%v:%v: %s\n", color, sev, d.pos.file, d.pos.line, d.pos.column, d.message)
	} else {
		fmt.eprintf("%v:%v:%v: %s: %s\n", d.pos.file, d.pos.line, d.pos.column, sev, d.message)
	}
}

print_diagnostic_json :: proc(d: nosl.Diagnostic) {
	sev := "error" if d.severity == .Error else "warning"
	esc, _ := strings.replace_all(d.message, "\\", "\\\\", context.temp_allocator)
	esc, _ = strings.replace_all(esc, "\"", "\\\"", context.temp_allocator)
	file, _ := strings.replace_all(d.pos.file, "\\", "\\\\", context.temp_allocator)
	file, _ = strings.replace_all(file, "\"", "\\\"", context.temp_allocator)
	fmt.eprintf("{{\"severity\":\"%s\",\"file\":\"%s\",\"line\":%d,\"column\":%d,\"message\":\"%s\"}}\n",
		sev, file, d.pos.line, d.pos.column, esc)
}

flush_diagnostics :: proc(diags: []nosl.Diagnostic, as_json: bool) {
	for d in diags {
		if as_json {
			print_diagnostic_json(d)
		} else {
			print_diagnostic(d)
		}
	}
}

// One GPU entry: {stem}.spv. Several entries: {stem}.{entry}.spv. Assembly uses the same stem with .spvasm.
spv_artifact_name :: proc(input, entry_name, ext: string, multiple: bool) -> string {
	stem := fpath.stem(input)
	if multiple {
		return fmt.tprintf("%s.%s%s", stem, entry_name, ext)
	}
	return fmt.tprintf("%s%s", stem, ext)
}

noslc_flags :: proc(opt: Options) -> nosl.Target_Flags {
	flags: nosl.Target_Flags
	if opt.no_bounds_check {
		flags += {.No_Bounds_Check}
	}
	if opt.disable_asserts {
		flags += {.Disable_Asserts}
	}
	if opt.debug {
		flags += {.Debug}
	}
	if opt.no_source {
		flags += {.No_Source}
	}
	if opt.named_entry {
		flags += {.Named_Entry}
	}
	return flags
}

noslc_gpu_formats :: proc(opt: Options) -> nosl.Target_Formats {
	fm: nosl.Target_Formats
	if .Spirv in opt.targets {
		fm += {.spirv}
	}
	if .Asm in opt.targets {
		fm += {.spirv_asm}
	}
	return fm
}

noslc_gpu_target :: proc(opt: Options) -> nosl.Target {
	return {
		formats = noslc_gpu_formats(opt),
		configs = opt.configs[:],
		opt = opt.spirv_opt,
		flags = noslc_flags(opt),
		no_gfx_compatibility = opt.no_gfx,
	}
}

noslc_fmag_target :: proc(opt: Options) -> nosl.Target {
	fm: nosl.Target_Formats
	if .Fmag in opt.targets {
		fm += {.fmag}
	}
	if .Asm in opt.targets {
		fm += {.fmag_asm}
	}
	return {
		formats = fm,
		configs = opt.configs[:],
		flags = noslc_flags(opt) & {.No_Bounds_Check, .Disable_Asserts},
		no_gfx_compatibility = opt.no_gfx,
	}
}

noslc_diag_target :: proc(opt: Options) -> nosl.Target {
	t := noslc_gpu_target(opt)
	gpu := t.formats & nosl.GPU_TARGET_FORMATS
	if gpu == {} {
		t.formats = {.spirv}
	} else {
		t.formats = gpu
	}
	return t
}

write_artifact :: proc(src, path: string, data: []u8, quiet: bool) -> bool {
	if !quiet {
		fmt.printfln("'%s' -> '%s'", src, path)
	}
	if write_err := os.write_entire_file(path, data); write_err != nil {
		fmt.eprintfln("noslc: failed to write '%s'", path)
		return false
	}
	return true
}

flush_entry_diags :: proc(diags: []nosl.Diagnostic, module: ^nosl.Module, fallback: string, json: bool) {
	if len(diags) == 0 do return
	file := fallback
	if module != nil && module.fullpath != "" {
		file = module.fullpath
	}
	for &d in diags {
		if d.pos.file == "" || d.pos.file == "<spirv>" {
			d.pos.file = file
		}
	}
	flush_diagnostics(diags, json)
}

emit_gpu_entry :: proc(
	entry: ^nosl.Entry,
	module: ^nosl.Module,
	src, spv_path, asm_path: string,
	write_spirv, write_asm: bool,
	timings: ^nosl.Timings,
	json, quiet: bool,
	target: nosl.Target,
) -> bool {
	diags: [dynamic]nosl.Diagnostic
	r, ok := nosl.compile_entry(entry, target, nosl.Compile_Options{
		allocator = context.temp_allocator,
		diags = &diags,
		timings = timings,
	})
	flush_entry_diags(diags[:], module, src, json)
	if !ok {
		fmt.eprintfln("noslc: failed to compile entry '%s'", entry.name)
		return false
	}
	if write_spirv && !write_artifact(src, spv_path, r.spirv, quiet) {
		return false
	}
	if write_asm {
		if r.spirv_asm == "" {
			fmt.eprintfln("noslc: failed to disassemble entry '%s'", entry.name)
			return false
		}
		if !write_artifact(src, asm_path, transmute([]u8)r.spirv_asm, quiet) {
			return false
		}
	}
	return true
}

run :: proc(opt: Options) -> Exit_Code {
	cols := make([]nosl.Collection, len(opt.collections), context.temp_allocator)
	for col, i in opt.collections {
		cols[i] = {name = col.name, path = col.path}
	}
	session := nosl.create_session({collections = cols})
	defer nosl.destroy_session(session)
	defer if opt.show_timings {
		nosl.timings_print(session.timings, opt.show_more_timings)
	}

	_cli_use_color = want_color(opt.color) && !opt.json
	_cli_error_limit = opt.error_limit

	gpu_target := noslc_gpu_target(opt)
	fmag_target := noslc_fmag_target(opt)
	diag_target := noslc_diag_target(opt)
	compile_opts := nosl.Compile_Options{
		allocator = context.temp_allocator,
		timings = &session.timings,
	}
	for input in opt.inputs {
		diags: [dynamic]nosl.Diagnostic
		defer delete(diags)
		_cli_diags = &diags
		_cli_error_count = 0
		defer { _cli_diags = nil }

		module := nosl.load_module_from_file_opts(session, input, nosl.Load_Options{
			soft_fail = true,
			err = cli_collect_error,
			warn = cli_collect_warning,
		})

		check_opts := nosl.Load_Options{
			soft_fail = true,
			err = cli_collect_error,
			warn = cli_collect_warning,
		}

		if opt.list_entries {
			flush_diagnostics(diags[:], opt.json)
			if module == nil || module.syntax_error_count > 0 {
				if !opt.quiet && !opt.json {
					fmt.eprintfln("%s: Error: failed to load module", input)
				}
				return .Check_Failed
			}
			for entry in module.entries {
				fmt.printfln("entry %s", entry.name)
			}
			for pipe in module.pipelines {
				fmt.printfln("pipeline %s", pipe.name)
			}
			continue
		}

		check_ok := module != nil && module.syntax_error_count == 0 && nosl.check_for_diagnostics(module, diag_target, check_opts)
		flush_diagnostics(diags[:], opt.json)

		has_errors := module == nil || module.syntax_error_count > 0 || !check_ok
		if !has_errors {
			for d in diags {
				if d.severity == .Error {
					has_errors = true
					break
				}
			}
		}
		if has_errors {
			if !opt.quiet && !opt.json && (module == nil || len(diags) > 0) {
				fmt.eprintfln("%s: Error: failed to load module", input)
			}
			return .Check_Failed
		}

		if opt.dumps != {} {
			if opt.dump_path == "" {
				fmt.eprintfln("noslc: -dump requires -dump-path:<path> or -out:<dir>")
				return .Usage
			}
			if !opt.quiet {
				fmt.eprintfln("noslc: dumps not implemented yet")
			}
			_ = opt.dumps
		}

		if opt.command == .Check {
			continue
		}

		os.make_directory_all(opt.out_dir)
		stem := fpath.stem(input)

		entries := make([dynamic]^nosl.Entry, context.temp_allocator)
		if len(opt.pipelines) > 0 {
			for name in opt.pipelines {
				pipe := nosl.find_pipeline_with_name(module, name)
				if pipe == nil {
					fmt.eprintfln("noslc: pipeline '%s' not found in '%s'", name, input)
					return .Check_Failed
				}
				if vs := nosl.pipeline_vertex(pipe); vs != nil {
					append(&entries, vs)
				}
				if fs := nosl.pipeline_fragment(pipe); fs != nil {
					append(&entries, fs)
				}
			}
		}

		if len(opt.pipelines) == 0 {
			if len(opt.entries) == 0 {
				for entry in module.entries {
					append(&entries, entry)
				}
			} else {
				for name in opt.entries {
					entry := nosl.find_entry_with_name(module, name)
					if entry == nil {
						fmt.eprintfln("noslc: entry '%s' not found in '%s'", name, input)
						return .Check_Failed
					}
					append(&entries, entry)
				}
			}
		} else if len(opt.entries) > 0 {
			for name in opt.entries {
				entry := nosl.find_entry_with_name(module, name)
				if entry == nil {
					fmt.eprintfln("noslc: entry '%s' not found in '%s'", name, input)
					return .Check_Failed
				}
				append(&entries, entry)
			}
		}

		write_spirv := .Spirv in opt.targets
		write_asm := .Asm in opt.targets
		write_fmag := .Fmag in opt.targets
		gpu_entries := 0
		if module != nil {
			for e in module.entries {
				if !nosl.entry_is_fmag(e) {
					gpu_entries += 1
				}
			}
		}
		if gpu_entries == 0 {
			for e in entries {
				if !nosl.entry_is_fmag(e) {
					gpu_entries += 1
				}
			}
		}
		multiple_entries := gpu_entries > 1
		for entry in entries {
			if nosl.entry_is_fmag(entry) {
				if !write_fmag && !write_asm {
					if !opt.quiet {
						fmt.printfln("skipping proc \"fmag\" entry '%s' (use -target:fmag or -target:asm)", entry.name)
					}
					continue
				}
				ft := fmag_target
				if ft.formats == {} {
					if write_fmag {
						ft.formats += {.fmag}
					}
					if write_asm {
						ft.formats += {.fmag_asm}
					}
				}
				r, notes, compiled := nosl.compile_fmag_entry_ex(entry, ft, compile_opts)
				if !compiled {
					fmt.eprintfln("noslc: failed to compile proc \"fmag\" entry '%s'", entry.name)
					return .Emit_Failed
				}
				if write_fmag {
					fmag_path := fmt.tprintf("%s/%s.entry.%s.fmag", opt.out_dir, stem, entry.name)
					if !opt.quiet {
						fmt.printfln("'%s' -> '%s'", input, fmag_path)
					}
					if !nosl.write_fmag_file(fmag_path, r.fmag) {
						return .Emit_Failed
					}
				}
				if write_asm {
					asm_path := fmt.tprintf("%s/%s.entry.%s.fmagasm", opt.out_dir, stem, entry.name)
					if !opt.quiet {
						fmt.printfln("'%s' -> '%s'", input, asm_path)
					}
					text := r.fmag_asm
					if text == "" {
						text = nosl.format_fmag_asm(entry.name, r.fmag, notes, context.temp_allocator)
					}
					if write_err := os.write_entire_file(asm_path, transmute([]u8)text); write_err != nil {
						fmt.eprintfln("noslc: failed to write '%s'", asm_path)
						return .Emit_Failed
					}
				}
				continue
			}
			spv_path := fmt.tprintf("%s/%s", opt.out_dir, spv_artifact_name(input, entry.name, ".spv", multiple_entries))
			asm_path := fmt.tprintf("%s/%s", opt.out_dir, spv_artifact_name(input, entry.name, ".spvasm", multiple_entries))

			src := module.fullpath if module != nil && module.fullpath != "" else input
			if write_spirv || write_asm {
				if !emit_gpu_entry(
					entry,
					module,
					src,
					spv_path,
					asm_path,
					write_spirv,
					write_asm,
					&session.timings,
					opt.json,
					opt.quiet,
					gpu_target,
				) {
					return .Emit_Failed
				}
			}
		}
	}

	return .Ok
}

main :: proc() {
	context.allocator = context.temp_allocator
	args := os.args[1:]
	if len(args) < 1 {
		print_usage()
		os.exit(int(Exit_Code.Usage))
	}

	opt, ok := parse_options(args)
	if !ok {
		os.exit(int(Exit_Code.Usage))
	}

	code := run(opt)
	if !opt.quiet {
		fmt.println()
	}
	os.exit(int(code))
}
