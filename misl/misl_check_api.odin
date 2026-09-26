package misl

import "core:fmt"
import "core:strings"
import vm "core:mem/virtual"
import "core:time"

module_parsed_origin :: proc(m: ^Module) -> ^Module {
	if m == nil do return nil
	if m.parsed_origin != nil do return m.parsed_origin
	return m
}

configs_fingerprint :: proc(configs: []User_Config, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	for cfg in configs {
		fmt.sbprintf(&b, "%s=", cfg.name)
		#partial switch v in cfg.value {
		case i128:
			fmt.sbprintf(&b, "%d;", v)
		case bool:
			fmt.sbprintf(&b, "%v;", v)
		case string:
			fmt.sbprintf(&b, "%q;", v)
		case f64:
			fmt.sbprintf(&b, "%g;", v)
		case:
			fmt.sbprint(&b, "?;")
		}
	}
	return strings.to_string(b)
}

check_instance_key :: proc(parsed: ^Module, target: Target) -> string {
	origin := module_parsed_origin(parsed)
	mode, _ := target_mode(target)
	return fmt.tprintf("%p|%v|%v|%v|%v|%s",
		rawptr(origin),
		mode,
		target_no_bounds(target),
		target_disable_asserts(target),
		target.no_gfx_compatibility,
		configs_fingerprint(target.configs),
	)
}

instantiate_parsed_module :: proc(parsed: ^Module, opts: Load_Options, target: Target) -> ^Module {
	inst := new(Module)
	inst.kind = parsed.kind
	inst.session = parsed.session
	inst.fullpath = parsed.fullpath
	inst.code = parsed.code
	inst.from_file = parsed.from_file
	inst.compiler_core = parsed.compiler_core
	inst.parsed_origin = module_parsed_origin(parsed)
	inst.no_bounds_check = parsed.no_bounds_check || target_no_bounds(target)
	inst.disable_asserts = parsed.disable_asserts || target_disable_asserts(target)
	inst.compat = .No_Gfx if target.no_gfx_compatibility else parsed.compat
	if target.no_gfx_compatibility {
		inst.compat = .No_Gfx
	}
	inst.configs = make(map[string]Configurable)
	parser := default_parser()
	if opts.err != nil {
		parser.err = opts.err
	}
	if opts.warn != nil {
		parser.warn = opts.warn
	}
	parse_module(&parser, inst)
	return inst
}

// Check a baked core file with this checker's Mode and harvest @builtin
// into the current `core:builtin` instantiation. Used for FMAG math in `fmag.misl`
// so helpers stay in that file's scope (not ambient).
check_attached_core_file :: proc(c: ^Checker, filename: string) {
	if c == nil || c.session == nil || c.builtin_instance == nil do return
	name, data, ok := core_embedded_match(filename)
	if !ok {
		fmt.eprintfln("internal: missing baked core:%s", filename)
		return
	}
	opts := c.check_opts
	opts.compiler_core = true
	opts.soft_fail = true
	if opts.err == nil {
		opts.err = c.err
	}
	if opts.warn == nil {
		opts.warn = c.warn
	}
	parsed := session_load_embedded_core(c.session, name, data, opts)
	if parsed == nil do return
	parsed.compiler_core = true
	inst := instantiate_parsed_module(parsed, opts, c.check_target)
	inst.compiler_core = true
	inst.kind = .Normal
	inst.is_checked = true
	inst.check_mode = c.compile_mode
	old_mod := c.module
	old_scope := c.curr_scope
	_ = check_module(c, inst)
	c.module = old_mod
	c.curr_scope = old_scope
}

target_for_mode :: proc(src: Target, mode: Misl_Mode) -> Target {
	t := src
	switch mode {
	case .SPIRV:
		gpu := t.formats & GPU_TARGET_FORMATS
		if gpu == {} {
			gpu = {.spirv}
		}
		t.formats = gpu
	case .FMAG:
		fm := t.formats & FMAG_TARGET_FORMATS
		if fm == {} {
			fm = {.fmag}
		}
		t.formats = fm
	}
	return t
}

// `check` locks `#config` plus `MISL_MODE` from Target.formats, then collect+typecheck.
// Untaken `when` / `which` arms are gone. Instantiations are cached on the session.
check :: proc(parsed: ^Module, target: Target, opts := Load_Options{}) -> ^Module {
	if parsed == nil do return nil
	target := target_apply_compat(target)
	parsed := module_parsed_origin(parsed)
	session := parsed.session
	if session == nil {
		fmt.eprintfln("misl.check: module '%s' has no session", parsed.fullpath)
		return nil
	}
	mode, mode_ok := target_mode(target)
	if !mode_ok {
		fmt.eprintfln("misl.check: Target.formats must pick one Mode (GPU or FMAG), got %v", target.formats)
		return nil
	}
	context.allocator = vm.arena_allocator(&session.arena)

	key := check_instance_key(parsed, target)
	if existing, ok := session.check_cache[key]; ok {
		if existing.loading {
			fmt.eprintfln("cyclic import involving '%s'", parsed.fullpath)
			return nil
		}
		return existing
	}

	session_config_load_begin(session, target.configs)
	if session.config_load_depth == 1 {
		session.no_bounds_check = target_no_bounds(target) || parsed.no_bounds_check
		session.disable_asserts = target_disable_asserts(target) || parsed.disable_asserts
		session.compat = .No_Gfx if target.no_gfx_compatibility else .None
	}
	defer session_config_load_end(session, opts.warn)

	inst := instantiate_parsed_module(parsed, opts, target)
	inst.is_checked = true
	inst.check_mode = mode
	inst.loading = true
	session.check_cache[strings.clone(key)] = inst

	checker := default_checker()
	if opts.err != nil {
		checker.err = opts.err
	}
	if opts.warn != nil {
		checker.warn = opts.warn
	}
	checker.session = session
	checker.compile_mode = mode
	checker.check_target = target
	checker.check_configs = target.configs
	checker.check_opts = opts
	if opts.soft_fail {
		if checker.err == nil {
			checker.err = default_error_handler
		}
	}

	check_start := time.tick_now()
	is_builtin := parsed.kind == .Builtin || parsed == session.builtin_module
	if is_builtin {
		inst.kind = .Builtin
		inst.scope = create_scope(nil, .Module)
		checker.builtin_instance = inst
		checker.module = inst
		checker.curr_scope = inst.scope
		add_builtin_entitites(&checker)
		_ = check_module(&checker, inst)
		bind_gpu_iface_types(&checker)
		if mode == .FMAG {
			check_attached_core_file(&checker, FMAG_FILENAME)
		}
	} else {
		builtin_inst := check(session.builtin_module, target, opts)
		checker.builtin_instance = builtin_inst
		bind_gpu_iface_types(&checker)
		_ = check_module(&checker, inst)
	}
	session.timings.check += time.tick_diff(check_start, time.tick_now())
	inst.loading = false

	if checker.error_count != 0 && !opts.soft_fail {
		return nil
	}
	return inst
}

module_has_fmag_entry :: proc(m: ^Module) -> bool {
	if m == nil do return false
	for e in m.entries {
		if e != nil && e.kind == .Fmag {
			return true
		}
	}
	return false
}

// SPIRV check (from GPU formats / default); second FMAG check when the file has proc "fmag".
check_for_diagnostics :: proc(parsed: ^Module, target: Target, opts := Load_Options{}) -> bool {
	if parsed == nil do return false
	target := target_apply_compat(target)
	opts := opts
	opts.soft_fail = true
	ok := true
	run :: proc(parsed: ^Module, target: Target, opts: Load_Options, ok: ^bool) {
		m := check(parsed, target, opts)
		if m == nil || m.type_error_count > 0 || m.syntax_error_count > 0 {
			ok^ = false
		}
	}
	gpu := target.formats & GPU_TARGET_FORMATS
	fm := target.formats & FMAG_TARGET_FORMATS
	spirv_t := target
	if gpu == {} && fm == {} {
		spirv_t.formats = {.spirv}
	} else if gpu != {} {
		spirv_t.formats = gpu
	}
	if gpu != {} || fm == {} {
		run(parsed, spirv_t, opts, &ok)
	}
	if module_has_fmag_entry(parsed) || fm != {} {
		run(parsed, target_for_mode(target, .FMAG), opts, &ok)
	}
	return ok && parsed.syntax_error_count == 0
}

specialize_entry :: proc(entry: ^Entry, target: Target, opts := Load_Options{}) -> ^Entry {
	if entry == nil || entry.module == nil do return nil
	origin := module_parsed_origin(entry.module)
	checked := check(origin, target, opts)
	if checked == nil do return nil
	return find_entry_with_name(checked, entry.name)
}

stmt_contains_offset :: proc(stmt: ^Stmt, offset: int) -> bool {
	if stmt == nil do return false
	lo := stmt.pos.offset
	hi := stmt.end.offset if stmt.end.offset > lo else lo + 1
	return offset >= lo && offset < hi
}

expr_contains_offset :: proc(expr: ^Expr, offset: int) -> bool {
	if expr == nil do return false
	lo := expr.pos.offset
	hi := expr.end.offset if expr.end.offset > lo else lo + 1
	return offset >= lo && offset < hi
}

ident_name :: proc(expr: ^Expr) -> string {
	if expr == nil do return ""
	ident, ok := unparen_expr(expr).derived.(^Ident)
	if !ok do return ""
	return ident.name
}

enum_member_name :: proc(expr: ^Expr) -> string {
	if expr == nil do return ""
	e := unparen_expr(expr)
	#partial switch v in e.derived {
	case ^Ident:
		return v.name
	case ^Implicit_Selector_Expr:
		if v.field != nil do return v.field.name
	case ^Selector_Expr:
		if v.field != nil do return v.field.name
	}
	return ""
}

mode_from_enum_name :: proc(name: string) -> (Misl_Mode, bool) {
	switch name {
	case "SPIRV", "Spirv":
		return .SPIRV, true
	case "FMAG", "Fmag":
		return .FMAG, true
	}
	return .SPIRV, false
}

cond_is_name :: proc(expr: ^Expr, name: string) -> bool {
	return ident_name(expr) == name
}

when_eq_enum_member :: proc(cond: ^Expr, ident: string) -> (member: string, ok: bool) {
	if cond == nil do return
	bin, is_bin := unparen_expr(cond).derived.(^Binary_Expr)
	if !is_bin || bin.op.kind != .Cmp_Eq do return
	if cond_is_name(bin.left, ident) {
		return enum_member_name(bin.right), true
	}
	if cond_is_name(bin.right, ident) {
		return enum_member_name(bin.left), true
	}
	return
}

Mode_Hit :: struct {
	mode: Misl_Mode,
	span: int,
	has:  bool,
}

consider_mode :: proc(hit: ^Mode_Hit, span: int, mode: Misl_Mode) {
	if span <= 0 do return
	if !hit.has || span <= hit.span {
		hit.span = span
		hit.mode = mode
		hit.has = true
	}
}

// Cursor Mode for LSP: innermost which/when on MISL_MODE, else entry convention, else SPIRV.
compile_mode_from_cursor :: proc(m: ^Module, offset: int) -> Misl_Mode {
	if m == nil || offset < 0 do return .SPIRV

	hit: Mode_Hit
	walk_stmt_mode(m.decls[:], offset, &hit)
	if hit.has {
		return hit.mode
	}

	cc := enclosing_calling_convention(m, offset)
	if kind, ok := entry_kind_from_calling_convention(cc); ok && kind == .Fmag {
		return .FMAG
	}
	return .SPIRV
}

walk_stmt_mode :: proc(stmts: []^Stmt, offset: int, hit: ^Mode_Hit) {
	for stmt in stmts {
		walk_one_stmt_mode(stmt, offset, hit)
	}
}

walk_one_stmt_mode :: proc(stmt: ^Stmt, offset: int, hit: ^Mode_Hit) {
	if stmt == nil do return
	#partial switch s in stmt.derived {
	case ^Value_Decl:
		for v in s.values {
			walk_expr_mode(v, offset, hit)
		}
	case ^Block_Stmt:
		walk_stmt_mode(s.stmts, offset, hit)
	case ^When_Stmt:
		if stmt_contains_offset(s.body, offset) {
			if member, ok := when_eq_enum_member(s.cond, "MISL_MODE"); ok {
				if mode, mok := mode_from_enum_name(member); mok {
					span := s.body.end.offset - s.body.pos.offset
					consider_mode(hit, span, mode)
				}
			}
		}
		walk_one_stmt_mode(s.body, offset, hit)
		walk_one_stmt_mode(s.else_stmt, offset, hit)
	case ^Which_Stmt:
		walk_which_mode(s, offset, hit)
	case ^Case_Clause:
		walk_stmt_mode(s.body, offset, hit)
	case ^If_Stmt:
		walk_one_stmt_mode(s.body, offset, hit)
		walk_one_stmt_mode(s.else_stmt, offset, hit)
	case ^For_Stmt:
		walk_one_stmt_mode(s.body, offset, hit)
	case ^Range_Stmt:
		walk_one_stmt_mode(s.body, offset, hit)
	case ^Switch_Stmt:
		walk_one_stmt_mode(s.body, offset, hit)
	}
}

walk_which_mode :: proc(ws: ^Which_Stmt, offset: int, hit: ^Mode_Hit) {
	if ws.body == nil do return
	body, ok := ws.body.derived.(^Block_Stmt)
	if !ok do return
	if !cond_is_name(ws.cond, "MISL_MODE") {
		for clause_stmt in body.stmts {
			clause, cok := clause_stmt.derived.(^Case_Clause)
			if cok {
				walk_stmt_mode(clause.body, offset, hit)
			}
		}
		return
	}
	for clause_stmt in body.stmts {
		clause, cok := clause_stmt.derived.(^Case_Clause)
		if !cok do continue
		in_clause := stmt_contains_offset(clause, offset)
		if !in_clause {
			for st in clause.body {
				if stmt_contains_offset(st, offset) {
					in_clause = true
					break
				}
			}
			if !in_clause {
				for expr in clause.list {
					if expr_contains_offset(expr, offset) {
						in_clause = true
						break
					}
				}
			}
		}
		if !in_clause do continue
		member := ""
		for expr in clause.list {
			if expr_contains_offset(expr, offset) {
				member = enum_member_name(expr)
				break
			}
		}
		if member == "" && len(clause.list) > 0 {
			member = enum_member_name(clause.list[0])
		}
		span := clause.end.offset - clause.pos.offset
		if span <= 0 {
			span = 1
		}
		if mode, mok := mode_from_enum_name(member); mok {
			consider_mode(hit, span, mode)
		}
		walk_stmt_mode(clause.body, offset, hit)
	}
}

walk_expr_mode :: proc(expr: ^Expr, offset: int, hit: ^Mode_Hit) {
	if expr == nil do return
	#partial switch e in expr.derived {
	case ^Proc_Lit:
		walk_one_stmt_mode(e.body, offset, hit)
	case ^Comp_Lit:
		for elem in e.elems {
			walk_expr_mode(elem, offset, hit)
		}
	case ^Field_Value:
		walk_expr_mode(e.value, offset, hit)
	}
}

enclosing_calling_convention :: proc(m: ^Module, offset: int) -> string {
	best_span := max(int)
	cc: string
	if m == nil do return ""
	for decl in m.decls {
		enclosing_cc_stmt(decl, offset, &best_span, &cc)
	}
	return cc
}

enclosing_cc_stmt :: proc(stmt: ^Stmt, offset: int, best_span: ^int, cc: ^string) {
	if stmt == nil do return
	#partial switch s in stmt.derived {
	case ^Value_Decl:
		for v in s.values {
			enclosing_cc_expr(v, offset, best_span, cc)
		}
	case ^Block_Stmt:
		for st in s.stmts {
			enclosing_cc_stmt(st, offset, best_span, cc)
		}
	case ^When_Stmt:
		enclosing_cc_stmt(s.body, offset, best_span, cc)
		enclosing_cc_stmt(s.else_stmt, offset, best_span, cc)
	case ^Which_Stmt:
		enclosing_cc_stmt(s.body, offset, best_span, cc)
	case ^Case_Clause:
		for st in s.body {
			enclosing_cc_stmt(st, offset, best_span, cc)
		}
	case ^If_Stmt:
		enclosing_cc_stmt(s.body, offset, best_span, cc)
		enclosing_cc_stmt(s.else_stmt, offset, best_span, cc)
	}
}

enclosing_cc_expr :: proc(expr: ^Expr, offset: int, best_span: ^int, cc: ^string) {
	if expr == nil do return
	#partial switch e in expr.derived {
	case ^Proc_Lit:
		if e.body != nil && stmt_contains_offset(e.body, offset) {
			span := e.body.end.offset - e.body.pos.offset
			if span < best_span^ && e.type != nil && e.type.calling_convention != "" {
				best_span^ = span
				cc^ = e.type.calling_convention
			}
		}
		enclosing_cc_stmt(e.body, offset, best_span, cc)
	case ^Comp_Lit:
		for elem in e.elems {
			enclosing_cc_expr(elem, offset, best_span, cc)
		}
	case ^Field_Value:
		enclosing_cc_expr(e.value, offset, best_span, cc)
	}
}
