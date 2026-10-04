package misl

import "base:runtime"
import "core:os"
import vm "core:mem/virtual"
import "core:fmt"
import "core:strings"
import "core:slice"
import "core:path/filepath"
import "core:time"

import "spirv_tools"
import fmag "fmag"

// SPIR-V optimizer recipe applied after emit. Default is none.
// `All` is performance passes then size passes (spirv-opt -O then -Os).
Optimization :: enum {
	None,
	Size,
	Performance,
	All,
}

parse_spirv_opt :: proc(s: string) -> (Optimization, bool) {
	switch s {
	case "none":
		return .None, true
	case "size":
		return .Size, true
	case "performance", "perf", "speed":
		return .Performance, true
	case "all":
		return .All, true
	}
	return .None, false
}

Collection :: struct {
	name: string,
	path: string,
}

Session_Desc :: struct {
	collections: []Collection,
}

Entry_Kind :: enum {
	Vertex,
	Fragment,
	Compute,
	Fmag,
}

Entry :: struct {
	name:   string,
	node:   ^Value_Decl,
	kind:   Entry_Kind,
	entity: ^Entity, // nil until typechecked under the matching Mode
	module: ^Module,
}

Pipeline :: struct {
	name:   string,
	node:   ^Value_Decl,
	entity: ^Entity, // nil until typechecked
	module: ^Module,
}

Target_Format :: enum {
	spirv,
	spirv_asm,
	fmag,
	fmag_asm,
}

Target_Formats :: bit_set[Target_Format]

Target_Flag :: enum {
	Debug,            // DebugInfo + OpLine + OpName/OpMemberName + embed source
	No_Source,        // with Debug: skip DebugSource text; ignored otherwise
	Named_Entry,
	No_Bounds_Check,
	Disable_Asserts,
}

Target_Flags :: bit_set[Target_Flag]

Target :: struct {
	formats:               Target_Formats,
	configs:               []User_Config,
	opt:                   Optimization,
	flags:                 Target_Flags,
	no_gfx_compatibility:  bool,
	assert_buffer_spec_id: u32,
}

Compile_Options :: struct {
	allocator: runtime.Allocator,
	diags:     ^[dynamic]Diagnostic,
	timings:   ^Timings,
}

Compile_Result :: struct {
	spirv:     []u8,
	spirv_asm: string,
	fmag_asm:  string,
	fmag:      fmag.Program,
}

GPU_TARGET_FORMATS :: Target_Formats{.spirv, .spirv_asm}
FMAG_TARGET_FORMATS :: Target_Formats{.fmag, .fmag_asm}

// User-exposed API will be here
// TODO(Dragos): figure out memory allocations.

// A module is a single file (or a compiler-synthesized builtin module).
Module :: struct {
	using node: Node,

	id: int,
	kind: Module_Kind,
	scope: ^Scope,

	fullpath: string, // on-disk path for LSP, or virtual key (`core:builtin`)
	code: string,
	from_file: bool, // true if loaded from disk (import paths are relative to this file)
	compiler_core: bool, // baked `oge/misl/core` (set by the compiler on `#load_directory` loads)
	session: ^Session,
	parsed_origin: ^Module, // instantiation points at the parse-only module
	is_checked: bool,
	check_mode: Misl_Mode,
	loading: bool,   // true while parsing or checking — used for cycle detection

	tags: [dynamic]Token,
	docs: ^Comment_Group, // can be nil

	pkg_decl: ^Package_Decl,
	pkg_token: Token,
	pkg_name: string,

	decls: [dynamic]^Stmt,
	imports: [dynamic]^Import_Decl,
	imports_resolved: [dynamic]^Module,
	directive_count: int,

	comments: [dynamic]^Comment_Group,

	syntax_warning_count: int,
	syntax_error_count: int,

	type_warning_count: int,
	type_error_count: int,

	definitions: [dynamic]^Entity,
	entitites: [dynamic]^Entity,
	configs: map[string]Configurable, // arena; keys declared in THIS file only
	entries: [dynamic]^Entry,
	pipelines: [dynamic]^Pipeline,

	no_bounds_check: bool, // #+feature no_bounds_check or Target flags
	disable_asserts: bool, // #+feature disable-asserts or Target flags
	compat: Misl_Compat, // ABI / layout (Target.no_gfx_compatibility)
}

// `#+<directive>` names allowed at the start of a module. LSP and the parser share this list.
File_Tag_Directive :: struct {
	name: string,
	docs: string,
}

FILE_TAG_DIRECTIVES := []File_Tag_Directive{
	{name = "feature", docs = "File-level compiler feature. Written as `#+feature <name>`."},
}

// Names after `#+feature`. LSP and the parser share this list.
File_Tag_Feature :: struct {
	name: string,
	docs: string,
}

FILE_TAG_FEATURES := []File_Tag_Feature{
	{
		name = "no_bounds_check",
		docs = "Turn off default `[]T` index/store checks in this file. Overridden by `#bounds_check` / `#no_bounds_check` on statements.",
	},
	{
		name = "disable-asserts",
		docs = "Typecheck `debug.assert` / `debug.panic` but emit no GPU claim (`assert` still evaluates `cond`).",
	},
}

Stages :: bit_set[Stage]
Stage :: enum {
	Vertex,
	Fragment,
	Compute,
}

// Locked by `check` / `compile_entry`. Declaration order matches `core:builtin.misl`.
Misl_Mode :: enum u32 {
	SPIRV,
	FMAG,
}

// Host / SPIR-V ABI. Default matches oge/gpu. `No_Gfx` matches research/no_gfx
// (descriptor sets 0–3, compute SpecIds 13370–72, DrawID-indexed indirect).
Misl_Compat :: enum u32 {
	None,
	No_Gfx,
}

NO_GFX_LOCAL_SIZE_X_ID :: 13370
NO_GFX_LOCAL_SIZE_Y_ID :: 13371
NO_GFX_LOCAL_SIZE_Z_ID :: 13372

entry_kind_from_calling_convention :: proc(cc: string) -> (kind: Entry_Kind, ok: bool) {
	switch cc {
	case "vertex", "vert", "vs":
		return .Vertex, true
	case "fragment", "frag", "fs", "pixel", "ps":
		return .Fragment, true
	case "compute", "comp", "cs":
		return .Compute, true
	case "fmag":
		return .Fmag, true
	}
	return {}, false
}

entry_kind_from_stage :: proc(s: Stage) -> Entry_Kind {
	switch s {
	case .Vertex: return .Vertex
	case .Fragment: return .Fragment
	case .Compute: return .Compute
	}
	return .Vertex
}

// Stages a builtin (or a helper that inherited one) may run in.
// Empty set = available in every stage.
Builtin_Stage :: enum {
	Vertex,
	Fragment,
	Compute,
	Mesh,
}
Builtin_Stages :: bit_set[Builtin_Stage]

builtin_stage_from_stage :: proc(s: Stage) -> Builtin_Stage {
	switch s {
	case .Vertex: return .Vertex
	case .Fragment: return .Fragment
	case .Compute: return .Compute
	}
	return .Vertex
}

stage_adjective :: proc(s: Stage) -> string {
	switch s {
	case .Vertex: return "vertex"
	case .Fragment: return "fragment"
	case .Compute: return "compute"
	}
	return "shader"
}

builtin_stages_adjective :: proc(stages: Builtin_Stages) -> string {
	if stages == {.Fragment} do return "fragment"
	if stages == {.Vertex} do return "vertex"
	if stages == {.Compute} do return "compute"
	if stages == {.Mesh} do return "mesh"
	if stages == {.Fragment, .Compute} do return "fragment and compute"
	return "stage-gated"
}

// First declaration site of a #config key within one root load's import chain.
Config_Key_Site :: struct {
	pos:         Token_Pos,
	module_path: string,
}

// Check/compile-time override supplied by the host / mislc `-config:ident=value`.
// Slice is user-owned; not stored on Module.
User_Config :: struct {
	name:  string,
	value: Exact_Value, // literals fine: User_Config{"SAMPLES", 32}
}

Session :: struct {
	arena: vm.Arena,
	modules: map[string]^Module,
	collections: map[string]string, // name → filesystem root (core is virtual)
	builtin_module: ^Module,
	debug_module: ^Module,
	check_cache: map[string]^Module, // parsed origin + Mode + configs + bounds + no_gfx

	timings: Timings,

	// Check-scoped #config state (cleared when outermost check returns).
	config_load_depth: int,
	active_configs:    []User_Config, // borrowed from caller for duration of root load
	config_decls:      map[string]Config_Key_Site, // chain-wide uniqueness
	config_used:       map[string]bool, // declared keys (for unknown-override warnings)
	no_bounds_check:   bool, // Target flags for this check chain
	disable_asserts:   bool,
	compat:            Misl_Compat,
}

create_session :: proc(desc := Session_Desc{}) -> (session: ^Session) {
	arena: vm.Arena
	arena_err := vm.arena_init_growing(&arena)
	fmt.assertf(arena_err == nil, "misl arena error: %v")
	session = new(Session, vm.arena_allocator(&arena))
	session.arena = arena
	alloc := vm.arena_allocator(&session.arena)
	session.modules = make(map[string]^Module, alloc)
	session.collections = make(map[string]string, alloc)
	session.check_cache = make(map[string]^Module, alloc)
	for col in desc.collections {
		assert(col.name != "")
		if col.name == CORE_COLLECTION {
			continue
		}
		session.collections[strings.clone(col.name, alloc)] = strings.clone(col.path, alloc)
	}
	start := time.tick_now()
	session_ensure_builtin(session)
	session.timings.misl_init += time.tick_diff(start, time.tick_now())
	timings_sync_init(&session.timings)
	return session
}

destroy_session :: proc(session: ^Session) {
	delete(session.timings.entries)
	arena := session.arena
	vm.arena_destroy(&arena)
}

Load_Options :: struct {
	soft_fail: bool, // return module even with parse/check errors
	// Optional overrides; nil keeps default_parser / default_checker handlers (print + hard-fail path).
	err:  Error_Handler,
	warn: Warning_Handler,
	// If set, lexer/LSP path (`module.fullpath`) while `name` remains the session key
	// (`core:s2h.misl` vs on-disk `oge/misl/core/s2h.misl`).
	origin_path: string,
	compiler_core: bool, // baked `oge/misl/core` load
}

session_config_load_begin :: proc(session: ^Session, configs: []User_Config) {
	if session.config_load_depth == 0 {
		alloc := vm.arena_allocator(&session.arena)
		if session.config_decls == nil {
			session.config_decls = make(map[string]Config_Key_Site, alloc)
			session.config_used = make(map[string]bool, alloc)
		} else {
			clear(&session.config_decls)
			clear(&session.config_used)
		}
		session.active_configs = configs
	}
	session.config_load_depth += 1
}

session_config_load_end :: proc(session: ^Session, warn: Warning_Handler) {
	session.config_load_depth -= 1
	if session.config_load_depth != 0 {
		return
	}
	handler: Warning_Handler = default_warning_handler
	if warn != nil {
		handler = warn
	}
	for cfg in session.active_configs {
		if cfg.name not_in session.config_used {
			handler(Token_Pos{}, "unknown #config key '%s' — ignored", cfg.name)
		}
	}
	session.active_configs = {}
	clear(&session.config_decls)
	clear(&session.config_used)
}

apply_load_diag_handlers :: proc(parser: ^Parser, checker: ^Checker, opts: Load_Options) {
	if opts.err != nil {
		parser.err = opts.err
		checker.err = opts.err
	}
	if opts.warn != nil {
		parser.warn = opts.warn
		checker.warn = opts.warn
	}
}

// Load from an in-memory source. `name` is the session module key.
// `Load_Options.origin_path` is the on-disk path for the lexer and LSP when `name` is virtual
// (`core:s2h.misl`). Imports without a collection resolve to other keys already in the session.
load_module_from_memory :: proc(session: ^Session, name: string, code: string, from_file := false) -> ^Module {
	return load_module_from_memory_opts(session, name, code, from_file, Load_Options{
		soft_fail = false,
	})
}

load_module_from_memory_opts :: proc(session: ^Session, name: string, code: string, from_file: bool, opts: Load_Options) -> ^Module {
	context.allocator = vm.arena_allocator(&session.arena)
	session_ensure_builtin(session)

	if existing, ok := session.modules[name]; ok {
		if existing.loading {
			fmt.eprintfln("cyclic import involving '%s'", name)
			return nil
		}
		return existing
	}
	if opts.origin_path != "" {
		if existing := session_module_with_fullpath(session, opts.origin_path); existing != nil {
			session_alias_module(session, name, existing)
			return existing
		}
	}

	module := new(Module, context.allocator)
	module.kind = .Normal
	module.session = session
	session_key := strings.clone(name, context.allocator)
	file_path := session_key
	if opts.origin_path != "" {
		file_path = strings.clone(opts.origin_path, context.allocator)
	}
	module.fullpath = file_path
	module.code = strings.clone(code, context.allocator)
	module.from_file = from_file
	module.compiler_core = opts.compiler_core
	module.loading = true
	module.configs = make(map[string]Configurable, context.allocator)
	session.modules[session_key] = module
	if file_path != session_key {
		session.modules[file_path] = module
	}

	parser := default_parser()
	if opts.err != nil {
		parser.err = opts.err
	}
	if opts.warn != nil {
		parser.warn = opts.warn
	}

	parse_start := time.tick_now()
	parse_module(&parser, module)
	session.timings.parse += time.tick_diff(parse_start, time.tick_now())
	had_errors := parser.error_count != 0

	if !had_errors || opts.soft_fail {
		parse_nested_imports(session, module, opts)
	}

	module.loading = false
	if had_errors && !opts.soft_fail {
		return nil
	}
	return module
}

load_module_from_file :: proc(session: ^Session, filename: string) -> ^Module {
	return load_module_from_file_opts(session, filename, Load_Options{
		soft_fail = false,
	})
}

load_module_from_file_opts :: proc(session: ^Session, filename: string, opts: Load_Options) -> ^Module {
	context.allocator = vm.arena_allocator(&session.arena)
	session_ensure_builtin(session)

	cleaned, _ := filepath.clean(filename, context.temp_allocator)
	key := strings.clone(cleaned, context.allocator)

	if existing, ok := session.modules[key]; ok {
		if existing.loading {
			fmt.eprintfln("cyclic import involving '%s'", key)
			return nil
		}
		return existing
	}

	code_bytes, read_err := os.read_entire_file(filename, context.temp_allocator)
	if read_err != nil {
		fmt.eprintfln("failed to read '%s': %v", filename, read_err)
		return nil
	}
	return load_module_from_memory_opts(session, key, transmute(string)code_bytes, from_file = true, opts = opts)
}

find_entry_with_name :: proc(module: ^Module, name: string) -> ^Entry {
	if module == nil do return nil
	for entry in module.entries {
		if entry != nil && entry.name == name {
			return entry
		}
	}
	return nil
}

entry_is_fmag :: proc(e: ^Entry) -> bool {
	return e != nil && e.kind == .Fmag
}

find_pipeline_with_name :: proc(module: ^Module, name: string) -> ^Pipeline {
	if module == nil do return nil
	for pipe in module.pipelines {
		if pipe != nil && pipe.name == name {
			return pipe
		}
	}
	return nil
}

pipeline_field_ident_name :: proc(decl: ^Value_Decl, field: string) -> string {
	if decl == nil do return ""
	lit: ^Comp_Lit
	if len(decl.values) > 0 {
		lit, _ = decl.values[0].derived.(^Comp_Lit)
	}
	if lit == nil do return ""
	for elem in lit.elems {
		fv, ok := elem.derived.(^Field_Value)
		if !ok || fv.field == nil do continue
		ident, iok := fv.field.derived.(^Ident)
		if !iok || ident.name != field do continue
		if fv.value == nil do return ""
		val, vok := unparen_expr(fv.value).derived.(^Ident)
		if vok {
			return val.name
		}
	}
	return ""
}

pipeline_vertex :: proc(pipe: ^Pipeline) -> ^Entry {
	if pipe == nil do return nil
	name := pipeline_field_ident_name(pipe.node, "vertex")
	return find_entry_with_name(pipe.module, name)
}

pipeline_fragment :: proc(pipe: ^Pipeline) -> ^Entry {
	if pipe == nil do return nil
	name := pipeline_field_ident_name(pipe.node, "fragment")
	return find_entry_with_name(pipe.module, name)
}

target_apply_compat :: proc(t: Target) -> Target {
	t := t
	t.no_gfx_compatibility = t.no_gfx_compatibility || MISL_COMPAT_NOGFX
	return t
}

target_mode :: proc(t: Target) -> (mode: Misl_Mode, ok: bool) {
	gpu := t.formats & GPU_TARGET_FORMATS
	fm := t.formats & FMAG_TARGET_FORMATS
	if gpu != {} && fm != {} {
		return .SPIRV, false
	}
	if gpu != {} {
		return .SPIRV, true
	}
	if fm != {} {
		return .FMAG, true
	}
	return .SPIRV, false
}

target_no_bounds :: proc(t: Target) -> bool {
	return .No_Bounds_Check in t.flags // || t.no_gfx_compatibility
}

target_disable_asserts :: proc(t: Target) -> bool {
	return .Disable_Asserts in t.flags // || t.no_gfx_compatibility
}

compile_allocator :: proc(opts: Compile_Options) -> runtime.Allocator {
	if opts.allocator.procedure != nil {
		return opts.allocator
	}
	return context.temp_allocator
}

entry_point_name :: proc(entry: ^Entry, target: Target) -> string {
	if entry == nil {
		return "main"
	}
	if .Named_Entry not_in target.flags {
		return "main"
	}
	if .spirv not_in target.formats && .spirv_asm not_in target.formats {
		return "main"
	}
	return entry.name
}

entity_is_fmag :: proc(e: ^Entity) -> bool {
	if e == nil || e.type == nil do return false
	pt, ok := e.type.derived.(^Type_Proc)
	return ok && pt.is_fmag
}

clone_spirv_bytes :: proc(words: []u32, allocator: runtime.Allocator) -> []u8 {
	if len(words) == 0 {
		return nil
	}
	spv_bytes := slice.bytes_from_ptr(raw_data(words), len(words) * size_of(u32))
	return slice.clone(spv_bytes, allocator)
}

spirv_words_to_asm :: proc(words: []u32, module: ^Module, allocator: runtime.Allocator, out_diags: ^[dynamic]Diagnostic) -> string {
	if len(words) == 0 {
		return ""
	}
	text := disassemble_spirv(words, allocator, out_diags, spv_target_env(module, false))
	if text == nil {
		return ""
	}
	return string(text)
}

optimize_spirv_words :: proc(words: []u32, target: Target, out_diags: ^[dynamic]Diagnostic) -> []u32 {
	if target.opt == .None || len(words) == 0 {
		return words
	}
	preserve_debug := .Debug in target.flags
	opt_words := optimize_spirv(raw_data(words), len(words), context.temp_allocator, out_diags, target.opt, preserve_debug)
	if opt_words == nil {
		return nil
	}
	return opt_words
}

compile_checked_gpu_entity :: proc(entry: ^Entity, target: Target, opts: Compile_Options) -> (result: Compile_Result, ok: bool) {
	target := target_apply_compat(target)
	if entry == nil || entry.type == nil {
		fmt.eprintfln("compile_entry: nil entity")
		return
	}
	proc_t, pok := entry.type.derived.(^Type_Proc)
	if !pok || proc_t.is_fmag {
		fmt.eprintfln("compile_entry: '%s' is proc \"fmag\" — use compile_fmag_entry", entry.name)
		return
	}
	if _, has_stage := proc_t.stage.?; !has_stage {
		fmt.eprintfln("compile_entry: '%s' has no GPU stage", entry.name)
		return
	}
	allocator := compile_allocator(opts)
	out_diags := opts.diags
	timings := opts.timings
	if !ensure_spirv_builder_ok(out_diags) {
		fmt.eprintfln("compile_entry: SPIR-V builder self-test failed")
		return
	}

	need_direct := .spirv in target.formats || .spirv_asm in target.formats

	debug := .Debug in target.flags
	emit := Spirv_Emit{
		debug_info = debug,
		embed_source = debug && .No_Source not_in target.flags,
		names = debug,
		named_entry = .Named_Entry in target.flags,
		assert_buffer_spec_id = target.assert_buffer_spec_id,
	}

	entry_start := time.tick_now()
	et: Entry_Timing
	et.name = entry.name
	defer if timings != nil {
		et.total = time.tick_diff(entry_start, time.tick_now())
		append(&timings.entries, et)
		timings.entry_count += 1
		timings.spirv_codegen += et.total
	}

	if need_direct {
		words := compile_entry_direct(entry, timings, out_diags, emit, &et)
		if len(words) == 0 {
			return
		}
		opt_start := time.tick_now()
		words = optimize_spirv_words(words, target, out_diags)
		opt_d := time.tick_diff(opt_start, time.tick_now())
		et.optimize += opt_d
		if timings != nil {
			timings.spirv_optimize += opt_d
		}
		if words == nil {
			return
		}
		et.words_opt = len(words)
		if .spirv in target.formats {
			result.spirv = clone_spirv_bytes(words, allocator)
		}
		if .spirv_asm in target.formats {
			dasm_start := time.tick_now()
			result.spirv_asm = spirv_words_to_asm(words, entry.module, allocator, out_diags)
			et.disassemble += time.tick_diff(dasm_start, time.tick_now())
			if timings != nil {
				timings.spirv_disassemble += et.disassemble
			}
		}
	}

	ok = true
	return
}

compile_entry :: proc(entry: ^Entry, target: Target, opts := Compile_Options{}) -> (Compile_Result, bool) {
	target := target_apply_compat(target)
	if entry == nil {
		fmt.eprintfln("compile_entry: nil entry")
		return {}, false
	}
	if entry.kind == .Fmag {
		fmt.eprintfln("compile_entry: '%s' is proc \"fmag\" — use compile_fmag_entry", entry.name)
		return {}, false
	}
	gpu := target.formats & GPU_TARGET_FORMATS
	fm := target.formats & FMAG_TARGET_FORMATS
	if gpu == {} || fm != {} {
		fmt.eprintfln("compile_entry: Target.formats must be GPU-only (got %v)", target.formats)
		return {}, false
	}
	parsed := module_parsed_origin(entry.module)
	check_opts := Load_Options{soft_fail = true}
	checked := check(parsed, target, check_opts)
	if checked == nil {
		fmt.eprintfln("compile_entry: failed to check '%s'", entry.name)
		return {}, false
	}
	if checked.type_error_count != 0 {
		fmt.eprintfln("compile_entry: type errors in '%s'", entry.name)
		return {}, false
	}
	live := find_entry_with_name(checked, entry.name)
	if live == nil || live.entity == nil {
		fmt.eprintfln("compile_entry: entry '%s' not present after check", entry.name)
		return {}, false
	}
	entry.entity = live.entity
	return compile_checked_gpu_entity(live.entity, target, opts)
}

checked_pipeline :: proc(pipe: ^Pipeline, target: Target, opts := Load_Options{}) -> ^Checked_Pipeline {
	target := target_apply_compat(target)
	if pipe == nil || pipe.module == nil {
		return nil
	}
	parsed := module_parsed_origin(pipe.module)
	checked := check(parsed, target, opts)
	if checked == nil {
		return nil
	}
	live := find_pipeline_with_name(checked, pipe.name)
	if live == nil || live.entity == nil {
		return nil
	}
	pipe.entity = live.entity
	return live.entity.checked_pipeline
}

@(private)
_spirv_self_tested: bool

ensure_spirv_builder_ok :: proc(out_diags: ^[dynamic]Diagnostic = nil) -> bool {
	if _spirv_self_tested {
		return true
	}
	_spirv_self_tested = true
	return spirv_builder_self_test(out_diags)
}

compile_entry_direct :: proc(entry: ^Entity, timings: ^Timings, out_diags: ^[dynamic]Diagnostic, emit: Spirv_Emit, et: ^Entry_Timing = nil) -> []u32 {
	cg_start := time.tick_now()
	words, ok := codegen_spirv(entry.module, entry, context.temp_allocator, emit, et)
	if timings != nil {
		d := time.tick_diff(cg_start, time.tick_now())
		timings.spirv_direct_codegen += d
		if et != nil {
			timings.spirv_assemble += et.assemble
		}
	}
	if !ok || len(words) == 0 {
		fmt.eprintfln("compile_entry: SPIR-V emit failed for '%s'", entry.name)
		return nil
	}
	needs_ray := false
	env := spv_target_env(entry.module, false)
	if entry.module != nil {
		mods := spv_gather_emit_modules(entry.module)
		needs_ray = spv_dag_needs_ray_query(mods)
		env = spv_target_env(entry.module, needs_ray)
	}
	val_start := time.tick_now()
	if !spirv_validate_words(words, env, out_diags) {
		d := time.tick_diff(val_start, time.tick_now())
		if timings != nil {
			timings.spirv_validate += d
		}
		if et != nil {
			et.validate = d
		}
		fmt.eprintfln("compile_entry: SPIR-V validate failed for '%s'", entry.name)
		return nil
	}
	d := time.tick_diff(val_start, time.tick_now())
	if timings != nil {
		timings.spirv_validate += d
	}
	if et != nil {
		et.validate = d
	}
	return words
}

@(private = "file")
_opt_diags: ^[dynamic]Diagnostic

@(private = "file")
optimizer_log :: proc "c" (level: spirv_tools.Message_Level, _source: cstring, _pos: spirv_tools.Position, message: cstring) {
	context = runtime.default_context()
	if message == nil do return
	text := string(message)
	is_err := level == .Fatal || level == .Internal_Error || level == .Error
	if _opt_diags != nil {
		append(_opt_diags, Diagnostic{
			pos = {file = "<spirv-opt>", line = 1, column = 1},
			severity = .Error if is_err else .Warning,
			message = fmt.tprintf("spirv-opt: %s", text),
		})
	} else if is_err {
		fmt.eprintfln("SPIRV_OPT_ERR: %s", text)
	} else {
		fmt.eprintfln("SPIRV_OPT: %s", text)
	}
}

optimize_spirv :: proc(words: [^]u32, word_count: int, allocator := context.temp_allocator, out_diags: ^[dynamic]Diagnostic = nil, opt: Optimization, preserve_debug := false) -> []u32 {
	if opt == .None || words == nil || word_count <= 0 {
		return nil
	}

	optimizer := spirv_tools.optimizer_create(.Vulkan_1_2)
	if optimizer == nil {
		if out_diags != nil {
			append(out_diags, Diagnostic{
				pos = {file = "<spirv-opt>", line = 1, column = 1},
				severity = .Error,
				message = "spirv-opt: failed to create optimizer",
			})
		} else {
			fmt.eprintfln("SPIRV_OPT_ERR: failed to create optimizer")
		}
		return nil
	}
	defer spirv_tools.optimizer_destroy(optimizer)

	_opt_diags = out_diags
	defer _opt_diags = nil
	spirv_tools.optimizer_set_message_consumer(optimizer, optimizer_log)

	switch opt {
	case .None:
	case .Size:
		// Size recipes include strip-debug. With Debug, use perf passes instead.
		if preserve_debug {
			spirv_tools.optimizer_register_performance_passes(optimizer)
		} else {
			spirv_tools.optimizer_register_size_passes(optimizer)
		}
	case .Performance:
		spirv_tools.optimizer_register_performance_passes(optimizer)
	case .All:
		spirv_tools.optimizer_register_performance_passes(optimizer)
		if !preserve_debug {
			spirv_tools.optimizer_register_size_passes(optimizer)
		}
	}

	options := spirv_tools.optimizer_options_create()
	if options == nil {
		if out_diags != nil {
			append(out_diags, Diagnostic{
				pos = {file = "<spirv-opt>", line = 1, column = 1},
				severity = .Error,
				message = "spirv-opt: failed to create optimizer options",
			})
		} else {
			fmt.eprintfln("SPIRV_OPT_ERR: failed to create optimizer options")
		}
		return nil
	}
	defer spirv_tools.optimizer_options_destroy(options)

	spirv_tools.optimizer_options_set_run_validator(options, false)
	spirv_tools.optimizer_options_set_preserve_bindings(options, true)
	spirv_tools.optimizer_options_set_preserve_spec_constants(options, true)

	binary: ^spirv_tools.Binary
	result := spirv_tools.optimizer_run(optimizer, words, word_count, &binary, options)
	if result != .Success || binary == nil || binary.code == nil || binary.word_count == 0 {
		if out_diags != nil {
			append(out_diags, Diagnostic{
				pos = {file = "<spirv-opt>", line = 1, column = 1},
				severity = .Error,
				message = fmt.tprintf("spirv-opt: optimize failed (%v)", result),
			})
		} else {
			fmt.eprintfln("SPIRV_OPT_ERR: optimize failed (%v)", result)
		}
		if binary != nil {
			spirv_tools.binary_destroy(binary)
		}
		return nil
	}
	defer spirv_tools.binary_destroy(binary)

	n := int(binary.word_count)
	out := make([]u32, n, allocator)
	copy(out, binary.code[:n])
	return out
}

spirv_words_from_bytes :: proc(b: []u8, allocator := context.temp_allocator) -> []u32 {
	n := len(b) / size_of(u32)
	if n <= 0 {
		return nil
	}
	out := make([]u32, n, allocator)
	copy(slice.reinterpret([]u8, out), b[:n * size_of(u32)])
	return out
}

disassemble_spirv :: proc(words: []u32, code_allocator := context.temp_allocator, out_diags: ^[dynamic]Diagnostic = nil, env := spirv_tools.Target_Env.Vulkan_1_2) -> []u8 {
	if len(words) == 0 {
		return nil
	}
	ctx := spirv_tools.context_create(env)
	if ctx == nil {
		if out_diags != nil {
			append(out_diags, Diagnostic{
				pos = {file = "<spirv>", line = 1, column = 1},
				severity = .Error,
				message = "spirv-tools: failed to create context",
			})
		} else {
			fmt.eprintfln("SPIRV_TOOLS_ERR: failed to create context")
		}
		return nil
	}
	defer spirv_tools.context_destroy(ctx)

	opts := u32(spirv_tools.Binary_To_Text_Options{.Indent, .Friendly_Names})
	text: ^spirv_tools.Text
	diag: ^spirv_tools.Diagnostic
	result := spirv_tools.binary_to_text(ctx, raw_data(words), len(words), opts, &text, &diag)
	if diag != nil {
		defer spirv_tools.diagnostic_destroy(diag)
		msg := string(diag.error) if diag.error != nil else "disassemble failed"
		if out_diags != nil {
			append(out_diags, Diagnostic{
				pos = {file = "<spirv>", line = 1, column = 1},
				severity = .Error,
				message = fmt.tprintf("spirv-tools: %s", msg),
			})
		} else {
			fmt.eprintfln("SPIRV_TOOLS_ERR: %s", msg)
		}
		return nil
	}
	if result != .Success || text == nil || text.str == nil {
		if out_diags != nil {
			append(out_diags, Diagnostic{
				pos = {file = "<spirv>", line = 1, column = 1},
				severity = .Error,
				message = fmt.tprintf("spirv-tools: disassemble failed (%v)", result),
			})
		} else {
			fmt.eprintfln("SPIRV_TOOLS_ERR: disassemble failed (%v)", result)
		}
		return nil
	}
	defer spirv_tools.text_destroy(text)

	bytes := slice.bytes_from_ptr(rawptr(text.str), int(text.length))
	return slice.clone(bytes, code_allocator)
}
