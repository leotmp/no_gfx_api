package misl

import "core:fmt"
import "core:strconv"
import "core:mem"
import "core:slice"
import "core:reflect"
import "core:strings"

import "base:intrinsics"
import "base:runtime"



Allowed_Semantics_Struct_Fields :: Semantics {
	.None,
	.Custom,
	.Position,
	.Target,
}

// TODO(Dragos): this should be somewhat recursive, we may return a struct that has these semantics
Allowed_Semantics_Shader_Results :: Semantics {
	.None,
	.Custom,
	.Target,
	.Position,
}

// TODO(Dragos): We should separate this for different stage types
Allowed_Semantics_Shader_Params :: Semantics {
	.None,
	.Custom,
	.Vertex_ID,
	.Instance_ID,
	.Data,
	.Indirect_Data,
}

Allowed_Semantics_Compute_Params :: Semantics {
	.None,
	.Custom,
	.Data,
	.Global_Thread,
	.Group_Thread,
	.Group,
	.Group_Index,
	.Num_Groups,
	.Group_Size,
}

Semantics :: bit_set[Semantic]
Semantic :: enum {
	None,
	Custom,
	Position,
	Target,
	Vertex_ID,
	Instance_ID,
	Data,
	Indirect_Data,
	Global_Thread,
	Group_Thread,
	Group,
	Group_Index,
	Num_Groups,
	Group_Size,
}

Semantic_Info :: struct {
	name: string,
	docs: string,
}

semantic_names :: [Semantic]Semantic_Info {
	.None = {},
	.Custom = {},
	.Position = {
		"SV_Position",
		"Clip-space vertex position.\n\n**Where:** struct fields; vertex/fragment results\n**GLSL:** `gl_Position` (output)",
	},
	.Target = {
		"SV_Target",
		"Fragment color / render-target write.\n\n**Where:** struct fields; fragment results\n**GLSL:** fragment output target(s)",
	},
	.Vertex_ID = {
		"SV_Vertex",
		"Vertex index within the draw.\n\n**Where:** vertex/fragment entry parameters\n**GLSL:** `gl_VertexIndex`",
	},
	.Instance_ID = {
		"SV_Instance",
		"Instance index for instanced draws.\n\n**Where:** vertex/fragment entry parameters\n**GLSL:** `gl_InstanceIndex`",
	},
	.Data = {
		"SV_Data",
		"Shader resource / push-constant block.\n\n**Where:** entry parameters only; type must be `^Struct`",
	},
	.Indirect_Data = {
		"SV_Indirect_Data",
		"Indirect-args push-constant slot (host `PC_Graphics.indirect_args`).\n\n**Where:** vertex/fragment entry parameters only; type must be `^Struct`",
	},
	.Global_Thread = {
		"SV_Global_Thread",
		"Global invocation id in the dispatch.\n\n**Where:** compute parameters\n**Type:** `[3]u32`\n**GLSL:** `gl_GlobalInvocationID`",
	},
	.Group_Thread = {
		"SV_Group_Thread",
		"Local id inside the workgroup.\n\n**Where:** compute parameters\n**Type:** `[3]u32`\n**GLSL:** `gl_LocalInvocationID`",
	},
	.Group = {
		"SV_Group",
		"Workgroup id in the dispatch.\n\n**Where:** compute parameters\n**Type:** `[3]u32`\n**GLSL:** `gl_WorkGroupID`",
	},
	.Group_Index = {
		"SV_Group_Index",
		"Flattened local index in the workgroup.\n\n**Where:** compute parameters\n**Type:** `u32`\n**GLSL:** `gl_LocalInvocationIndex`",
	},
	.Num_Groups = {
		"SV_Num_Groups",
		"Number of workgroups in the dispatch.\n\n**Where:** compute parameters\n**Type:** `[3]u32`\n**GLSL:** `gl_NumWorkGroups`",
	},
	.Group_Size = {
		"SV_Group_Size",
		"Workgroup size (local size).\n\n**Where:** compute parameters\n**Type:** `[3]u32`\n**GLSL:** `gl_WorkGroupSize`",
	},
}

semantic_name :: proc(sem: Semantic) -> string {
	infos := semantic_names
	return infos[sem].name
}

semantic_docs :: proc(sem: Semantic) -> string {
	infos := semantic_names
	return infos[sem].docs
}

semantic_from_string :: proc(name: string) -> Semantic {
	if name == "" do return .None
	infos := semantic_names
	for info, sem_kind in infos {
		if sem_kind == .None || sem_kind == .Custom do continue
		if info.name == name do return sem_kind
	}
	return .Custom
}





// Note(Dragos): probably a flag here for entities that have semantic names
Entity_Flags :: bit_set[Entity_Flag]
Entity_Flag :: enum {
	Used, // ?
	Flat,
	Noperspective,
	Centroid,
	No_Init, // explicit `---` — leave uninitialized in GLSL
	Param, // procedure parameter
	Immutable, // cannot assign / field-store (default params, for-elem)
	Ref, // #ref param — mutable with writeback; call site requires `&`
	Range_Ref, // for &elem — mutable lvalue alias into ranged container
	Shared, // @shared workgroup memory (compute entry locals)
	Poly_Const, // $name constant procedure parameter
	Using,      // using field / param — conversion + name inject
	Subtype,    // #subtype field — conversion without name inject
	Ambient_Builtin, // @(builtin) in compiler-integrated core — harvested into core:builtin
	Body_Checked,    // procedure/entry body typechecked under this instantiation
}

Entity_State :: enum {
	Unresolved,
	In_Progress,
	Resolved,
}

Scope_Kind :: enum {
	Module,
	Proc,
	Block,
	Loop,
	Switch,
}

Scope :: struct {
	outer: ^Scope,
	kind: Scope_Kind,
	proc_type: ^Type, // kind == .Proc
	proc_lit: ^Proc_Lit, // kind == .Proc
	label: ^Entity, // can be nil
	entities: map[string]^Entity,
}

scope_insert :: proc(scope: ^Scope, entity: ^Entity, loc := #caller_location) {
	if entity.name == "" do return
	fmt.assertf(entity.name not_in scope.entities, "entity '%s' already in scope", entity.name, loc = loc)
	entity.scope = scope
	scope.entities[entity.name] = entity
}

scope_lookup_current :: proc(scope: ^Scope, str: string) -> ^Entity {
	return scope.entities[str]
}

scope_lookup :: proc(scope: ^Scope, str: string) -> ^Entity {
	if scope == nil {
		return nil
	}
	if str in scope.entities {
		return scope.entities[str]
	}
	return scope_lookup(scope.outer, str)
}

create_scope :: proc(parent: ^Scope, kind: Scope_Kind = .Block) -> ^Scope {
	s := new(Scope)
	s.outer = parent
	s.kind = kind
	return s
}

scope_has_kind :: proc(scope: ^Scope, kind: Scope_Kind) -> bool {
	for s := scope; s != nil; s = s.outer {
		if s.kind == kind {
			return true
		}
	}
	return false
}

Exact_Value_Kind :: enum {
	Invalid,
	Bool,
	String,
	Integer,
	Float,
	Complex,
	Quaternion, // TODO(Dragos): hmm, quaternions...no clue how to use them
	Pointer, // hmm, is this needed?
	Compound,
	Procedure,
	Typeid,
}

Exact_Value:: union {
	i128,
	f64,
	bool,
	quaternion256,
	complex128,
	string,
	^Expr,
	^Entity, // $fn procedure constant
}

exact_int :: #force_inline proc "contextless"(#any_int val: i128) -> Exact_Value { return val }
exact_bool :: #force_inline proc "contextless"(val: bool) -> Exact_Value { return val }
exact_float :: #force_inline proc "contextless"(val: f64) -> Exact_Value { return val }

Parameter_Value :: union {
	Exact_Value,
	^Basic_Lit,
}

Entity_Constant_Flags :: bit_set[Entity_Constant_Flag]
Entity_Constant_Flag :: enum {
	Implicit_Enum_Value,
}


Entity_Kind :: enum {
	Invalid,
	Constant,
	Variable,
	Dummy, // name == "_"
	Type_Name,
	Procedure,
	Entry,
	Pipeline,
	Builtin,
	Import, // bound import name → imported_module
	Nil,
	Label,
	Proc_Group,
}

// Folded `pipeline { ... }` data for host Raster_Desc conversion (no sidecar emit).
Checked_Blend_Mode :: struct {
	src, dst, op: i128, // Blend_Factor / Blend_Op enum indices
}

Checked_Blend_State :: struct {
	color, alpha: Checked_Blend_Mode,
}

Checked_Pipeline_Target :: struct {
	format: i128, // Format enum index
	has_write_mask: bool,
	write_mask: i128,
	has_blend: bool,
	blend: Checked_Blend_State,
}

Checked_Pipeline :: struct {
	vertex, fragment: ^Entity, // nil if field omitted
	has_topology, has_cull, has_sample_count, has_depth_format,
	has_stencil_format, has_flags, has_view_count, has_targets: bool,
	topology: i128,
	cull: i128, // Cull_Modes bit_set bits
	sample_count: i128,
	depth_format: i128,
	stencil_format: i128,
	flags: i128, // Raster_Flags bits
	view_count: i32,
	targets: [dynamic]Checked_Pipeline_Target,
}

Entity :: struct {
	kind: Entity_Kind,
	id: u64,
	flags: Entity_Flags,
	state: Entity_State,
	scope: ^Scope,
	type: ^Type,

	pos: Token_Pos,
	name, ir_name: string, // misl name + backend produced name
	ident: ^Ident, // can be nil

	module: ^Module,

	mode: Addressing_Mode, // TODO

	aliased_of: ^Entity,
	using_base: ^Expr,     // `using value` / param: emit this then using_chain
	using_chain: []^Entity, // field path from using_base (or from a struct selector)

	deprecated_msg: string,
	warning_msg: string,

	value: Exact_Value, // for constants
	semantic: Semantic,
	semantic_name: string, // if semantic == .Custom

	field_offset: int,

	builtin_id: Builtin_Proc,

	// Constant (`::`) decl binding — used by collect/resolve (Phase 4)
	decl: ^Value_Decl,
	decl_value_index: int,
	// Enclosing procedure entity for nested hoist mangling (nil = module-scope)
	owner_proc: ^Entity,
	// Proc_Lit for Procedure/Entry (set during resolve)
	proc_lit: ^Proc_Lit,
	// Direct Procedure/Entry callees (for GLSL no-recursion check)
	callees: [dynamic]^Entity,
	// Imported module for kind == .Import
	imported_module: ^Module,
	// kind == .Pipeline — folded fields for host conversion
	checked_pipeline: ^Checked_Pipeline,
	// Polymorphic specializations keyed by Exact_Value (on the generic entity)
	gen_procs: [dynamic]^Entity,
	// kind == .Proc_Group — named concrete members
	proc_group_members: []^Entity,
}



// Note: the alloc_id is for allocating unresolved entities. It's quite hacky
new_entity :: proc(kind: Entity_Kind, scope: ^Scope, pos: Token_Pos, name: string, type: ^Type, alloc_id := true) -> ^Entity {
	e, _ := mem.new(Entity)
	e.kind = kind
	e.pos = pos
	e.name = name
	e.type = type
	e.id = alloc_entity_id() if alloc_id else 0
	e.state = .Unresolved
	return e
}

new_entity_dummy :: proc(pos: Token_Pos) -> ^Entity {
	e := new_entity(.Dummy, nil, pos, "_", nil)
	return e
}



entity_kind_string :: proc(e: ^Entity) -> string {
	switch e.kind {
	case .Invalid: return "invalid"
	case .Constant: return "constant"
	case .Variable: return "variable"
	case .Type_Name: return "type name"
	case .Procedure: return "procedure"
	case .Builtin: return "builtin"
	case .Label: return "label"
	case .Nil: return "nil"
	case .Dummy: return "dummy"
	case .Entry: return "shader"
	case .Pipeline: return "pipeline"
	case .Import: return "import"
	case .Proc_Group: return "proc group"
	}
	return "invalid entity"
}

alloc_entity_id :: proc "contextless"() -> u64 {
	@static id: u64 = 1
	defer id += 1
	return id
}

entity_from_expr :: proc(expr: ^Expr) -> ^Entity {
	expr := unparen_expr(expr)
	if expr == nil do return nil
	#partial switch e in expr.derived {
	case ^Ident: return e.entity
	case ^Selector_Expr: return entity_from_expr(e.field) // TODO(Dragos): check if correct
	}
	return nil
}

strip_entity_wrapping_entity :: proc(e: ^Entity) -> ^Entity {
	if e == nil do return nil
	if e.aliased_of != nil && e.using_base == nil {
		return strip_entity_wrapping_entity(e.aliased_of)
	}
	if e.kind == .Constant do return e
	return e
}

strip_entity_wrapping_expr :: proc(expr: ^Expr) -> ^Entity {
	e := entity_from_expr(expr)
	return strip_entity_wrapping(e)
}

strip_entity_wrapping :: proc {
	strip_entity_wrapping_entity,
	strip_entity_wrapping_expr,
}

// #config(name, default_value) — per-module record of a declared config key.
Configurable :: struct {
	default_value: Exact_Value, // from AST in this module
	value:         Exact_Value, // effective after load-time override (or default)
}

find_active_config_override :: proc(session: ^Session, name: string) -> (Exact_Value, bool) {
	if session == nil do return nil, false
	for cfg in session.active_configs {
		if cfg.name == name {
			return cfg.value, true
		}
	}
	return nil, false
}

// Apply load-time override type rules: same kind; int→float OK; float→int / bool mismatch → error.
config_override_value :: proc(default_val, override_val: Exact_Value) -> (Exact_Value, bool) {
	#partial switch d in default_val {
	case bool:
		if o, ok := override_val.(bool); ok {
			return o, true
		}
	case i128:
		if o, ok := override_val.(i128); ok {
			return o, true
		}
	case f64:
		#partial switch o in override_val {
		case f64:
			return o, true
		case i128:
			return f64(o), true
		}
	}
	return nil, false
}

exact_value_to_string :: proc(v: Exact_Value) -> string {
	#partial switch val in v {
	case bool:
		return "true" if val else "false"
	case i128:
		return fmt.tprintf("%d", val)
	case f64:
		return fmt.tprintf("%v", val)
	case string:
		return fmt.tprintf("%q", val)
	case ^Expr:
		return "<compound>"
	}
	return "<invalid>"
}

// Kind name for load-time / CLI Exact_Value overrides (no MISL Type attached).
exact_value_type_name :: proc(v: Exact_Value) -> string {
	#partial switch _ in v {
	case bool:
		return "bool"
	case i128:
		return "integer"
	case f64:
		return "float"
	case string:
		return "string"
	case ^Expr:
		return "compound"
	}
	return "unknown"
}

check_config_expr :: proc(checker: ^Checker, call: ^Call_Expr, operand: ^Operand) {
	operand.mode = .Invalid
	operand.type = t_invalid

	if len(call.args) != 2 {
		check_err(checker, call.pos, "#config expects 2 arguments (IDENTIFIER, default), got %d", len(call.args))
		return
	}

	key_expr := unparen_expr(call.args[0])
	key_ident, is_ident := key_expr.derived.(^Ident)
	if !is_ident {
		check_err(checker, call.args[0].pos, "#config key must be an identifier")
		return
	}
	key := key_ident.name

	default_op := check_expr(checker, call.args[1])
	if default_op.mode != .Constant || default_op.value == nil {
		check_err(checker, call.args[1].pos, "#config default must be a constant expression")
		return
	}
	#partial switch _ in default_op.value {
	case i128, f64, bool:
	case:
		check_err(checker, call.args[1].pos, "#config default must be a constant integer, float, or boolean")
		return
	}
	if !(type_is_integer(default_op.type) || type_is_float(default_op.type) || type_is_boolean(default_op.type)) {
		check_err(checker, call.args[1].pos, "#config default must be an integer, float, or boolean type, got '%s'", string_from_type(default_op.type))
		return
	}

	session := checker.session
	module := checker.module

	if session != nil {
		if prev, exists := session.config_decls[key]; exists {
			check_err(checker, call.pos, "#config key '%s' already declared in this import chain (also at %s:%d:%d)", key, prev.module_path, prev.pos.line, prev.pos.column)
			check_err(checker, prev.pos, "#config key '%s' redeclared here via '%s'", key, module.fullpath)
			return
		}
		session.config_decls[strings.clone(key, context.allocator)] = Config_Key_Site{
			pos = call.pos,
			module_path = module.fullpath,
		}
		session.config_used[key] = true
	}

	effective := default_op.value
	if session != nil {
		if override_val, has := find_active_config_override(session, key); has {
			if promoted, ok := config_override_value(default_op.value, override_val); ok {
				effective = promoted
			} else {
				check_err(checker, call.pos,
					"#config override for '%s' is %s (%s), expected %s",
					key,
					exact_value_to_string(override_val),
					exact_value_type_name(override_val),
					string_from_type(default_op.type),
				)
				return
			}
		}
	}

	if module.configs == nil {
		module.configs = make(map[string]Configurable, context.allocator)
	}
	module.configs[strings.clone(key, context.allocator)] = Configurable{
		default_value = default_op.value,
		value = effective,
	}

	operand.mode = .Constant
	operand.type = default_op.type
	operand.value = effective
}

check_intrinsic_expr :: proc(checker: ^Checker, call: ^Call_Expr, operand: ^Operand) {
	operand.mode = .Invalid
	operand.type = t_invalid

	if len(call.args) != 1 {
		check_err(checker, call.pos, "#intrinsic expects 1 string argument, got %d", len(call.args))
		return
	}

	key_expr := unparen_expr(call.args[0])
	lit, is_lit := key_expr.derived.(^Basic_Lit)
	if !is_lit || lit.tok.kind != .String {
		check_err(checker, call.args[0].pos, "#intrinsic key must be a string literal")
		return
	}
	key := unescape_misl_string(lit.tok.text)

	if id, ok := intrinsic_key_to_builtin(key); ok {
		operand.mode = .Builtin
		operand.builtin_id = id
		operand.type = nil
		return
	}
	if t, ok := intrinsic_key_to_type(key); ok {
		operand.mode = .Type
		operand.type = t
		return
	}
	if key == "compiler.mode" {
		e := scope_lookup(checker.curr_scope, "Mode")
		if e != nil {
			ensure_entity_resolved(checker, e)
		}
		enum_t: ^Type = t_invalid
		if e != nil && e.kind == .Type_Name && e.type != nil {
			enum_t = e.type
		}
		operand.mode = .Constant
		operand.type = enum_t
		operand.value = exact_int(i128(u32(checker.compile_mode)))
		return
	}
	check_err(checker, call.args[0].pos, "unknown #intrinsic key '%s'", key)
}

entity_compiler_builtin :: proc(e: ^Entity) -> (id: Builtin_Proc, ok: bool) {
	for cur := e; cur != nil; cur = cur.aliased_of {
		if cur.kind == .Builtin && cur.builtin_id != .Invalid {
			return cur.builtin_id, true
		}
	}
	return .Invalid, false
}


// TODO(Dragos): Handle errors better
Checker :: struct {
	session: ^Session,
	module: ^Module,
	curr_scope: ^Scope,

	curr_proc: ^Type_Proc,
	curr_proc_entity: ^Entity, // Procedure/Entry being checked (for nesting / mangling)

	compile_mode: Misl_Mode,
	check_target: Target,
	check_configs: []User_Config,
	check_opts: Load_Options,
	builtin_instance: ^Module,
	gpu: Gpu_Iface_Types,

	// Element types of device pointers/slices stored through in the current entry check
	device_store_elems: map[^Type]bool,

	err: Error_Handler,
	warn: Warning_Handler,

	err_scope: ^Scope,

	error_count: int,
}

check_warn :: proc(c: ^Checker, pos: Token_Pos, msg: string, args: ..any) {
	if c.warn != nil {
		c.warn(pos, msg, ..args)
	}
	c.module.type_warning_count += 1
}

check_err :: proc(c: ^Checker, pos: Token_Pos, msg: string, args: ..any) {
	if c.err != nil {
		c.err(pos, msg, ..args)
	}
	c.module.type_error_count += 1
	c.error_count += 1
}

default_checker :: proc() -> Checker {
	return {
		err = default_error_handler,
		warn = default_warning_handler,
	}
}

add_global_type_name :: proc(module: ^Module, type: ^Type, name: string) -> ^Entity {
	type_name := new_entity(.Type_Name, module.scope, {}, name, type)
	defer type_name.state = .Resolved
	if type != nil && type.name == "" {
		type.name = name
	}
	scope_insert(module.scope, type_name)
	return type_name
}

add_global_builtin :: proc(module: ^Module, id: Builtin_Proc) -> ^Entity {
	name := builtin_names[id]
	builtin := new_entity(.Builtin, module.scope, {}, name, nil)
	builtin.builtin_id = id
	scope_insert(module.scope, builtin)
	return builtin
}

add_global_constant :: proc(module: ^Module, type: ^Type, name: string, val: Exact_Value) -> ^Entity {
	const := new_entity(.Constant, module.scope, {}, name, type)
	const.value = val
	defer const.state = .Resolved
	scope_insert(module.scope, const)
	return const
}

add_builtin_entitites :: proc(c: ^Checker) {
	module := c.module
	for type in scalar_types {
		if type == nil do continue
		if type_is_resource_id(type) do continue
		add_global_type_name(module, type, type.derived.(^Type_Scalar).name)
	}
	for type in quaternion_types {
		if type != nil {
			add_global_type_name(module, type, type.derived.(^Type_Quaternion).name)
		}
	}
	for type in atom_types {
		if type == nil do continue
		if type_is_ray_query(type) do continue
		name := type.derived.(^Type_Atom).name
		if name == "rune" || strings.contains_rune(name, ' ') {
			continue
		}
		add_global_type_name(module, type, name)
	}

	// Callable math/resource builtins still injected here except names that live in core MISL.
	for id in Builtin_Proc {
		if id == .Invalid || !builtin_injected_by_compiler(id) {
			continue
		}
		add_global_builtin(module, id)
	}

	add_global_constant(module, scalar_types[.Untyped_Bool], "true", exact_bool(true))
	add_global_constant(module, scalar_types[.Untyped_Bool], "false", exact_bool(false))
}

check_module_collect_and_resolve :: proc(c: ^Checker) {
	module := c.module
	entities := make([dynamic]^Entity, context.temp_allocator)
	collect_const_decls(c, module.decls[:], module.scope, &entities)
	for e in entities {
		decl_resolve(c, e)
	}
	for decl in module.decls {
		check_stmt_after_const_collect(c, decl)
	}
	check_no_proc_recursion(c)
	check_graphics_device_store_effects(c)
	check_stage_gates(c)
}

harvest_ambient_builtins :: proc(c: ^Checker) {
	mod := c.module
	if !module_is_compiler_core(mod) do return
	ambient: ^Scope
	if c.builtin_instance != nil {
		ambient = c.builtin_instance.scope
	} else if c.session != nil && c.session.builtin_module != nil {
		ambient = c.session.builtin_module.scope
	}
	if ambient == nil do return

	for e in mod.definitions {
		if e == nil || .Ambient_Builtin not_in e.flags do continue
		if e.scope == ambient {
			continue
		}
		if found := scope_lookup_current(ambient, e.name); found != nil {
			if found != e {
				// Editor overlay of a baked core file: same ambient name, skip.
				if module_is_compiler_core(found.module) && module_is_compiler_core(e.module) {
					continue
				}
				check_err(c, e.pos, "redeclaring ambient builtin '%s'", e.name)
			}
			continue
		}
		scope_insert(ambient, e)
	}
}

check_module :: proc(c: ^Checker, module: ^Module) -> bool {
	init_core_types()
	c.err_scope = create_scope(nil, .Module)
	c.module = module
	c.curr_proc = nil
	c.curr_proc_entity = nil

	if module.kind == .Builtin || module.kind == .Synthetic {
		c.curr_scope = module.scope
		if len(module.decls) == 0 {
			return true
		}
		check_module_collect_and_resolve(c)
		harvest_ambient_builtins(c)
		return true
	}

	// Parent to this check's core:builtin instantiation so unqualified builtins resolve
	parent: ^Scope
	if c.builtin_instance != nil {
		parent = c.builtin_instance.scope
	} else if c.session != nil && c.session.builtin_module != nil {
		parent = c.session.builtin_module.scope
	}
	module.scope = create_scope(parent, .Module)
	c.curr_scope = module.scope

	check_module_imports(c, c.session)
	check_module_using_stmts(c)

	check_module_collect_and_resolve(c)
	harvest_ambient_builtins(c)
	return true
}

fmag_gate_stmt :: proc(c: ^Checker, pos: Token_Pos, what: string) {
	if c.curr_proc == nil do return
	if c.curr_proc.is_fmag {
		check_err(c, pos, "'%s' is not allowed in proc \"fmag\"", what)
		return
	}
	if c.curr_proc.stage == nil {
		mark_fmag_illegal(c.curr_proc, what)
	}
}

check_stmts :: proc(c: ^Checker, stmts: []^Stmt) {
	check_block_stmts(c, stmts)
}

check_stmt :: proc(c: ^Checker, stmt: ^Stmt) -> (diverging: bool) {
	#partial switch d in stmt.derived {
	case: check_err(c, stmt.pos, "unhandled statement: %v", reflect.union_variant_typeid(stmt.derived))
	case ^Bad_Decl, ^Bad_Stmt:
		// Incomplete / recovered parse while typing (soft_fail LSP).
		return false
	case ^Import_Decl:
		// Handled in check_module_imports before collect/resolve
		return false
	case ^Value_Decl:
		if !d.is_mutable {
			// `::` decls are handled by collect/resolve
			for name in d.names {
				if ident, ok := name.derived.(^Ident); ok && ident.entity != nil && ident.entity.state == .Resolved {
					return false
				}
			}
		}
		check_value_decl(c, d)
	case ^Assign_Stmt: check_assign_stmt(c, d)
	case ^Using_Stmt:
		check_using_stmt(c, d)
	case ^Return_Stmt:
		// Soft-fail / incomplete edits can leave `return` outside a procedure
		// (e.g. brace mismatch while typing `switch`). Never assert — diagnose.
		if c.curr_proc == nil {
			check_err(c, d.pos, "'return' is only allowed inside a procedure")
			return true
		}
		proc_t := c.curr_proc
		return_index := 0
		n_results := len(proc_t.results.variables) if proc_t.results != nil else 0
		if len(d.results) == 0 {
			// Naked `return`: allowed for void procs, or when every result is named.
			if n_results > 0 {
				for r in proc_t.results.variables {
					if r.name == "" {
						check_err(c, d.pos, "naked return requires named results")
						break
					}
				}
			}
			return true
		}
		for e, ei in d.results {
			hint: ^Type
			if return_index < n_results {
				hint = proc_t.results.variables[return_index].type
			}
			val := check_expr(c, e, type_hint = hint, allow_multi_value = true)
			if tuple_t, is_tuple := val.type.derived.(^Type_Tuple); is_tuple {
				for field in tuple_t.variables {
					if return_index >= n_results {
						check_err(c, e.pos, "too many values for return statement")
						break
					}
					if !type_is_implicit_castable(field.type, proc_t.results.variables[return_index].type) {
						check_err(c, e.pos, "mismatched type in return statement: '%v' vs '%v'", string_from_type(proc_t.results.variables[return_index].type), string_from_type(field.type))
					}
					return_index += 1
				}
			} else {
				if return_index >= n_results {
					check_err(c, e.pos, "too many values in return statement")
					break
				}
				if !type_is_implicit_castable(val.type, proc_t.results.variables[return_index].type) {
					want := proc_t.results.variables[return_index].type
					if conv, reported := try_using_convert(c, e, val.type, want); conv != nil {
						d.results[ei] = conv
					} else if !reported {
						check_err(c, e.pos, "mismatched type in return statement: '%v' vs '%v'", string_from_type(want), string_from_type(val.type))
					}
				}
				return_index += 1
			}
		}
		if return_index != 0 && return_index != n_results {
			check_err(c, d.pos, "expected %d values for return statement, got %d", n_results, return_index)
		}
		return true
	
	case ^If_Stmt:
		last_scope := c.curr_scope
		if d.init != nil {
			d.scope = create_scope(c.curr_scope, .Block)
			c.curr_scope = d.scope
			_, is_decl := d.init.derived.(^Value_Decl)
			_, is_assign := d.init.derived.(^Assign_Stmt)
			if is_decl || is_assign {
				check_stmt(c, d.init)
			} else {
				check_err(c, d.init.pos, "if init must be a value declaration or assignment")
			}
		}
		if d.cond == nil {
			check_err(c, d.pos, "expected a boolean condition")
		} else {
			cond := check_expr(c, d.cond)
			if !type_is_boolean(cond.type) {
				check_err(c, d.cond.pos, "expected a boolean condition, got '%s'", string_from_type(cond.type))
			}
		}
		check_stmt(c, d.body)
		if d.else_stmt != nil {
			check_stmt(c, d.else_stmt)
		}
		c.curr_scope = last_scope

	case ^Range_Stmt:
		fmag_gate_stmt(c, d.pos, "for")
		d.scope = create_scope(c.curr_scope, .Loop)
		last_scope := c.curr_scope
		c.curr_scope = d.scope
		defer c.curr_scope = last_scope

		ranged := check_expr(c, d.expr)

		bind_range_var :: proc(c: ^Checker, expr: ^Expr, type: ^Type, immutable := false, range_ref := false) {
			ident, is_ident := expr.derived.(^Ident)
			if !is_ident {
				check_err(c, expr.pos, "expected an identifier in range statement")
				return
			}
			if is_blank_ident(ident.name) {
				ident.entity = new_entity_dummy(ident.pos)
				ident.entity.ident = ident
				return
			}
			if found := scope_lookup_current(c.curr_scope, ident.name); found != nil {
				check_err(c, ident.pos, "redeclaration of '%s' in this scope", ident.name)
				return
			}
			e := new_entity(.Variable, c.curr_scope, ident.pos, ident.name, type)
			e.ident = ident
			ident.entity = e
			if immutable do e.flags += {.Immutable}
			if range_ref do e.flags += {.Range_Ref}
			scope_insert(c.curr_scope, e)
		}

		range_val_elem :: proc(expr: ^Expr) -> (inner: ^Expr, is_mut_ref: bool) {
			return peel_unary_and(expr)
		}

		record_device_store_elem :: proc(c: ^Checker, pos: Token_Pos, elem: ^Type) {
			if c.curr_proc != nil {
				if stage, ok := c.curr_proc.stage.?; ok {
					#partial switch stage {
					case .Vertex, .Fragment:
						check_err(c, pos, "cannot store through device pointer/slice in %s shader", stage)
						return
					}
				}
				if c.curr_proc.device_store_elems == nil {
					c.curr_proc.device_store_elems = make(map[^Type]bool)
				}
				c.curr_proc.device_store_elems[elem] = true
			}
			if c.device_store_elems == nil {
				c.device_store_elems = make(map[^Type]bool)
			}
			c.device_store_elems[elem] = true
		}

		if expr_is_range(d.expr) {
			if len(d.vals) != 1 {
				check_err(c, d.pos, "numeric range 'for' expects 1 value, got %d", len(d.vals))
				break
			}
			iter_type := default_type(ranged.type)
			if !type_is_integer(iter_type) {
				check_err(c, d.expr.pos, "range bounds must be integers, got '%s'", string_from_type(iter_type))
				break
			}
			bind_range_var(c, d.vals[0], iter_type, immutable = true)
		} else if slice_t, is_slice := ranged.type.derived.(^Type_Slice); is_slice {
			if len(d.vals) < 1 || len(d.vals) > 2 {
				check_err(c, d.pos, "slice range 'for' expects 1 or 2 values, got %d", len(d.vals))
				break
			}
			elem_expr, elem_mut := range_val_elem(d.vals[0])
			bind_range_var(c, elem_expr, slice_t.elem, immutable = !elem_mut, range_ref = elem_mut)
			if elem_mut {
				record_device_store_elem(c, d.pos, slice_t.elem)
			}
			if len(d.vals) == 2 {
				bind_range_var(c, d.vals[1], t_i64, immutable = true)
			}
		} else if array_t, is_array := ranged.type.derived.(^Type_Array); is_array {
			if len(d.vals) < 1 || len(d.vals) > 2 {
				check_err(c, d.pos, "array range 'for' expects 1 or 2 values, got %d", len(d.vals))
				break
			}
			elem_expr, elem_mut := range_val_elem(d.vals[0])
			bind_range_var(c, elem_expr, array_t.elem, immutable = !elem_mut, range_ref = elem_mut)
			if len(d.vals) == 2 {
				bind_range_var(c, d.vals[1], t_i64, immutable = true)
			}
		} else {
			check_err(c, d.expr.pos, "cannot range over '%s'", string_from_type(ranged.type))
			break
		}

		check_stmt(c, d.body)

	case ^For_Stmt:
		fmag_gate_stmt(c, d.pos, "for")
		scope := create_scope(c.curr_scope, .Loop)
		last_scope := c.curr_scope
		c.curr_scope = scope
		if d.init != nil {
			decl, is_decl := d.init.derived.(^Value_Decl)
			if !is_decl {
				check_err(c, d.init.pos, "expected a value declaration for the init stmt")
				break
			}
			check_value_decl(c, decl)
		}

		if d.cond != nil {
			cond := check_expr(c, d.cond)
			if !type_is_boolean(cond.type) {
				check_err(c, d.cond.pos, "expected a boolean condition, got '%s'", string_from_type(cond.type))
				break
			}
		}

		if d.post != nil {
			check_stmt(c, d.post)
		}

		check_stmt(c, d.body)
		c.curr_scope = last_scope

	case ^Branch_Stmt:
		if d.label != nil {
			check_err(c, d.label.pos, "labeled '%s' is not supported", d.tok.text)
			break
		}
		#partial switch d.tok.kind {
		case .Discard:
			if c.curr_proc != nil && c.curr_proc.is_fmag {
				check_err(c, d.pos, "'discard' is not allowed in proc \"fmag\"")
			} else {
				is_fragment := false
				if c.curr_proc != nil {
					if stage, ok := c.curr_proc.stage.?; ok && stage == .Fragment {
						is_fragment = true
					}
				}
				if !is_fragment {
					check_err(c, d.pos, "'discard' is only allowed in fragment stage procedures")
				}
			}
		case .Break:
			if !scope_has_kind(c.curr_scope, .Loop) && !scope_has_kind(c.curr_scope, .Switch) {
				check_err(c, d.pos, "'break' is only allowed inside a loop or switch")
			}
		case .Continue:
			if !scope_has_kind(c.curr_scope, .Loop) {
				check_err(c, d.pos, "'continue' is only allowed inside a loop")
			}
		case .Fallthrough:
			check_err(c, d.pos, "'fallthrough' is only allowed as the last statement of a switch case")
		case:
			check_err(c, d.pos, "unhandled branch statement '%s'", d.tok.text)
		}

	case ^Switch_Stmt:
		fmag_gate_stmt(c, d.pos, "switch")
		check_switch_stmt(c, d)

	case ^When_Stmt:
		check_when_stmt(c, d)

	case ^Which_Stmt:
		check_which_stmt(c, d)

	case ^Expr_Stmt:
		check_expr(c, d.expr, allow_no_value = true)

	case ^Block_Stmt:
		last_scope := c.curr_scope
		d.scope = create_scope(c.curr_scope, .Block)
		c.curr_scope = d.scope
		check_block_stmts(c, d.stmts)
		c.curr_scope = last_scope
	}

	return false
}

expr_is_blank_ident :: proc(expr: ^Expr) -> bool {
	ident, ok := unparen_expr(expr).derived.(^Ident)
	return ok && ident.name == "_"
}

stmt_is_fallthrough :: proc(stmt: ^Stmt) -> bool {
	branch, ok := stmt.derived.(^Branch_Stmt)
	return ok && branch.tok.kind == .Fallthrough
}

check_switch_stmt :: proc(c: ^Checker, d: ^Switch_Stmt) {
	last_scope := c.curr_scope
	if d.init != nil {
		c.curr_scope = create_scope(c.curr_scope, .Block)
		_, is_decl := d.init.derived.(^Value_Decl)
		_, is_assign := d.init.derived.(^Assign_Stmt)
		if is_decl || is_assign {
			check_stmt(c, d.init)
		} else {
			check_err(c, d.init.pos, "switch init must be a value declaration or assignment")
		}
	}

	tag_type: ^Type = t_invalid
	is_bool_switch := d.cond == nil
	if d.cond != nil {
		tag := check_expr(c, d.cond)
		tag_type = default_type(tag.type)
		if tag_type == nil {
			tag_type = t_invalid
		}
		if !type_is_integer(tag_type) && !type_is_enum(tag_type) {
			check_err(c, d.cond.pos, "switch condition must be an integer or enum, got '%s'", string_from_type(tag_type))
		}
	}

	switch_scope := create_scope(c.curr_scope, .Switch)
	d.scope = switch_scope
	c.curr_scope = switch_scope

	body, ok := d.body.derived.(^Block_Stmt)
	if !ok {
		check_err(c, d.pos, "switch body must be a block of case clauses")
		c.curr_scope = last_scope
		return
	}

	has_default := false
	seen_consts: map[i128]bool
	defer delete(seen_consts)

	for clause_stmt, clause_i in body.stmts {
		clause, is_clause := clause_stmt.derived.(^Case_Clause)
		if !is_clause {
			check_err(c, clause_stmt.pos, "expected a 'case' clause in switch")
			continue
		}

		case_scope := create_scope(switch_scope, .Switch)
		clause.scope = case_scope
		c.curr_scope = case_scope

		if len(clause.list) == 0 {
			if has_default {
				check_err(c, clause.pos, "multiple default cases in switch")
			}
			has_default = true
		} else if is_bool_switch {
			for expr in clause.list {
				val := check_expr(c, expr)
				if val.type == nil || val.type == t_invalid || !type_is_boolean(val.type) {
					check_err(c, expr.pos, "case condition must be boolean in a conditionless switch, got '%s'", string_from_type(val.type))
				}
			}
		} else {
			for expr in clause.list {
				val := check_expr(c, expr, type_hint = tag_type if tag_type != t_invalid else nil)
				if val.mode != .Constant || val.value == nil {
					check_err(c, expr.pos, "case values must be constant")
					continue
				}
				if tag_type != t_invalid && !type_is_implicit_castable(val.type, tag_type) && !type_eq(val.type, tag_type) {
					check_err(c, expr.pos, "case value type '%s' is not compatible with switch type '%s'", string_from_type(val.type), string_from_type(tag_type))
				}
				key: i128
				#partial switch v in val.value {
				case i128: key = v
				case bool: key = 1 if v else 0
				case: check_err(c, expr.pos, "unsupported case constant kind"); continue
				}
				if key in seen_consts {
					check_err(c, expr.pos, "duplicate case value")
				} else {
					seen_consts[key] = true
				}
			}
		}

		for stmt, i in clause.body {
			if stmt_is_fallthrough(stmt) {
				if i != len(clause.body) - 1 {
					check_err(c, stmt.pos, "'fallthrough' must be the last statement in a case")
				} else if clause_i == len(body.stmts) - 1 {
					check_err(c, stmt.pos, "cannot fallthrough final case in switch")
				}
				continue
			}
			check_stmt(c, stmt)
		}
	}

	// Non-partial enum switches should be exhaustive or have a default
	if !is_bool_switch && !d.partial && !has_default {
		if enum_t, is_enum := tag_type.derived.(^Type_Enum); is_enum {
			variant_count := 0
			for _ in enum_t.fields {
				variant_count += 1
			}
			if len(seen_consts) < variant_count {
				check_err(c, d.pos, "switch on enum '%s' is not exhaustive; use '#partial switch' or add a default case", string_from_type(tag_type))
			}
		}
	}

	c.curr_scope = last_scope
}

which_reject_branches :: proc(c: ^Checker, d: ^Which_Stmt) {
	body, ok := d.body.derived.(^Block_Stmt)
	if !ok do return
	for clause_stmt in body.stmts {
		clause, is_clause := clause_stmt.derived.(^Case_Clause)
		if !is_clause do continue
		for stmt in clause.body {
			branch, is_branch := stmt.derived.(^Branch_Stmt)
			if !is_branch do continue
			#partial switch branch.tok.kind {
			case .Fallthrough:
				check_err(c, stmt.pos, "'fallthrough' is not allowed in 'which'")
			case .Break:
				check_err(c, stmt.pos, "'break' is not allowed in 'which'")
			case .Continue:
				check_err(c, stmt.pos, "'continue' is not allowed in 'which'")
			}
		}
	}
}

// `which` does not introduce a scope — decls bind in the enclosing scope.
// Const decls are collected in collect_const_decls; this checks the taken case stmts.
check_which_stmt :: proc(c: ^Checker, d: ^Which_Stmt) {
	taken, ok := eval_which_taken_clause(c, d, true)
	if !ok do return
	which_reject_branches(c, d)
	if taken == nil do return
	for stmt in taken.body {
		if _, is_branch := stmt.derived.(^Branch_Stmt); is_branch {
			continue
		}
		check_stmt_after_const_collect(c, stmt)
	}
}

// `when` does not introduce a scope — decls bind in the enclosing scope.
// Const decls are collected in collect_const_decls; this checks the taken branch stmts.
check_when_stmt :: proc(c: ^Checker, d: ^When_Stmt) {
	taken, ok := eval_when_condition(c, d)
	if !ok do return
	if taken {
		check_when_body_stmts(c, d.body)
	} else if d.else_stmt != nil {
		if else_when, is_when := d.else_stmt.derived.(^When_Stmt); is_when {
			check_when_stmt(c, else_when)
		} else {
			check_when_body_stmts(c, d.else_stmt)
		}
	}
}

check_assign_lvalue_mutability :: proc(c: ^Checker, expr: ^Expr) {
	expr := unparen_expr(expr)
	if expr == nil do return

	// Device stores through ^T / [^]T / []T
	if device_store_elem, is_dev := expr_device_store_elem(expr); is_dev {
		if c.curr_proc != nil {
			if stage, ok := c.curr_proc.stage.?; ok {
				#partial switch stage {
				case .Vertex, .Fragment:
					check_err(c, expr.pos, "cannot store through device pointer/slice in %s shader", stage)
					return
				}
			}
			if c.curr_proc.device_store_elems == nil {
				c.curr_proc.device_store_elems = make(map[^Type]bool)
			}
			c.curr_proc.device_store_elems[device_store_elem] = true
		}
		if c.device_store_elems == nil {
			c.device_store_elems = make(map[^Type]bool)
		}
		c.device_store_elems[device_store_elem] = true
		return
	}

	// Immutable value bindings (params without #ref, immutable for-elems)
	e := entity_from_expr(expr)
	if e == nil {
		// selector / index into value — find root
		#partial switch d in expr.derived {
		case ^Selector_Expr:
			check_assign_lvalue_mutability(c, d.expr)
			return
		case ^Index_Expr:
			check_assign_lvalue_mutability(c, d.expr)
			return
		case ^Unary_Expr:
			if d.op.kind == .Pointer { // dereference
				return
			}
		}
		return
	}
	if .Immutable in e.flags {
		check_err(c, expr.pos, "cannot assign to immutable '%s'", e.name)
	}
}

// If expr is a store target through device memory, return the element type written.
expr_device_store_elem :: proc(expr: ^Expr) -> (elem: ^Type, ok: bool) {
	expr := unparen_expr(expr)
	if expr == nil do return nil, false
	#partial switch d in expr.derived {
	case ^Index_Expr:
		base := check_expr_type_only(d.expr) // can't re-check easily — use tav
		if d.expr.tav.type == nil do return nil, false
		#partial switch t in d.expr.tav.type.derived {
		case ^Type_Multi_Pointer: return t.elem, true
		case ^Type_Slice: return t.elem, true
		case ^Type_Array: return nil, false // local array
		case ^Type_Pointer: return t.elem, true // p[0] style if allowed
		}
		// indexed field of struct that is itself through pointer — recurse on base store?
		if inner, inner_ok := expr_device_store_elem(d.expr); inner_ok {
			return inner, true
		}
		return nil, false
	case ^Selector_Expr:
		// data.particles[i].pos — selector after index already handled; selector on ^Struct field of value
		if d.expr.tav.type != nil {
			#partial switch t in d.expr.tav.type.derived {
			case ^Type_Pointer:
				return t.elem, true // store to field through ^T counts as writing pointee type's... actually writing a field of the struct pointee
				// For Ptr_RW of the struct type T when we do (^T).field = 
				// return t.elem, true marks struct T as "written" which upgrades T_Ptr — correct for ^T stores
			case ^Type_Multi_Pointer, ^Type_Slice:
				return nil, false
			}
		}
		return expr_device_store_elem(d.expr)
	case ^Unary_Expr:
		if d.op.kind == .Pointer { // ^
			if d.expr.tav.type != nil {
				if pt, is_ptr := d.expr.tav.type.derived.(^Type_Pointer); is_ptr {
					return pt.elem, true
				}
			}
		}
	}
	return nil, false
}

// Avoid full re-check; placeholder — not used
check_expr_type_only :: proc(expr: ^Expr) -> ^Type {
	return expr.tav.type if expr != nil else nil
}

check_assign_stmt :: proc(c: ^Checker, assign: ^Assign_Stmt) {
	assert(assign.lhs != nil)
	assert(assign.rhs != nil)
	for expr in assign.lhs {
		o := check_expr(c, expr)
		if expr_is_blank_ident(expr) {
			continue
		}
		if o.mode != .Variable && o.mode != .Swizzle_Variable {
			check_err(c, expr.pos, "detected a non-lvalue expression on the left-hand side: %s", o.mode)
		}
		check_assign_lvalue_mutability(c, expr)
	}

	lhs_count := len(assign.lhs)
	rhs_count := 0

	// Multi-assign from one call: `a, b = f()` / `a.x, b = f()`
	if len(assign.rhs) == 1 && lhs_count > 1 {
		types := make([]^Type, lhs_count, context.temp_allocator)
		for lhs, i in assign.lhs {
			types[i] = lhs.tav.type
		}
		hint := make_results_tuple(types)
		rhs := check_expr(c, assign.rhs[0], type_hint = hint, allow_multi_value = true)
		rhs_count = call_result_count(rhs)
		if lhs_count != rhs_count {
			check_err(c, assign.pos, "assignment mismatch: %d variables for %d values", lhs_count, rhs_count)
			return
		}
		slots := type_split_tuple(rhs.type)
		for lhs, i in assign.lhs {
			if expr_is_blank_ident(lhs) do continue
			if i >= len(slots) do break
			if !type_is_implicit_castable(slots[i], lhs.tav.type) {
				check_err(c, lhs.pos, "cannot assign '%s' to '%s'", string_from_type(slots[i]), string_from_type(lhs.tav.type))
			}
		}
		return
	}

	if lhs_count > 1 && len(assign.rhs) > 1 {
		check_err(c, assign.pos, "parallel multi-value assignment is not supported; unpack from a single call (`a, b = f()`) or assign one value at a time")
		return
	}

	for expr, i in assign.rhs {
		hint: ^Type
		binop: Token_Kind
		is_compound := false
		if i < lhs_count && !expr_is_blank_ident(assign.lhs[i]) {
			lhs_t := assign.lhs[i].tav.type
			if op, ok := compound_assign_binary_op(assign.op.kind); ok {
				hint = binary_convert_type(lhs_t)
				binop = op
				is_compound = true
			} else {
				hint = lhs_t
			}
		}
		rhs := check_expr(c, expr, type_hint = hint)
		rhs_count += call_result_count(rhs)
		if hint != nil && type_is_untyped(rhs.type) {
			convert_to_typed(c, &rhs, hint)
		}
		if is_compound && i < lhs_count && !expr_is_blank_ident(assign.lhs[i]) {
			lhs_t := assign.lhs[i].tav.type
			result_t := type_from_binary_op(lhs_t, binop, rhs.type)
			if result_t == t_invalid || (!type_eq(result_t, lhs_t) && !type_is_implicit_castable(result_t, lhs_t)) {
				check_err(c, expr.pos, "cannot assign '%s' to '%s'", string_from_type(result_t if result_t != t_invalid else rhs.type), string_from_type(lhs_t))
			}
		} else if hint != nil && rhs.mode != .Invalid && !type_is_implicit_castable(rhs.type, hint) {
			if conv, reported := try_using_convert(c, expr, rhs.type, hint); conv != nil {
				assign.rhs[i] = conv
			} else if !reported {
				check_err(c, expr.pos, "cannot assign '%s' to '%s'", string_from_type(rhs.type), string_from_type(hint))
			}
		}
	}
	if lhs_count != rhs_count {
		check_err(c, assign.pos, "assignment mismatch: %d variables for %d values", lhs_count, rhs_count)
	}
	// &&= / ||= require boolean operands (same as && / ||).
	if assign.op.kind == .Cmp_And_Eq || assign.op.kind == .Cmp_Or_Eq {
		if lhs_count == 1 && !expr_is_blank_ident(assign.lhs[0]) {
			lt := assign.lhs[0].tav.type
			if lt != nil && lt != t_invalid && !type_is_boolean(lt) {
				check_err(c, assign.lhs[0].pos, "'%s' requires a boolean left-hand side, got '%s'",
					assign.op.text, string_from_type(lt))
			}
		}
		if len(assign.rhs) == 1 {
			rt := assign.rhs[0].tav.type
			if rt != nil && rt != t_invalid && !type_is_boolean(rt) {
				check_err(c, assign.rhs[0].pos, "'%s' requires a boolean right-hand side, got '%s'",
					assign.op.text, string_from_type(rt))
			}
		}
	}
}

type_eq :: proc(a, b: ^Type) -> bool {
	if a == t_invalid || b == t_invalid do return false
	if a == nil || b == nil do return false
	if a == b do return true
	if a, is_scalar := a.derived.(^Type_Scalar); is_scalar {
		if b, is_scalar := b.derived.(^Type_Scalar); is_scalar {
			if a.kind == b.kind do return true
			if .Rune in a.flags || .Rune in b.flags {
				return false
			}
			if .Untyped in a.flags || .Untyped in b.flags do return true
		}
		return false
	}
	if a, is_array := a.derived.(^Type_Array); is_array {
		if b, is_array := b.derived.(^Type_Array); is_array {
			if a.len == b.len {
				return type_eq(a.elem, b.elem)
			}
			return false
		}
		return false
	}
	if a, is_vector := a.derived.(^Type_Vector); is_vector {
		if b, is_vector := b.derived.(^Type_Vector); is_vector {
			if a.len == b.len {
				return type_eq(a.elem, b.elem)
			}
		}
	}

	if a, ok := a.derived.(^Type_Matrix); ok {
		if b, ok := b.derived.(^Type_Matrix); ok {
			return a.rows == b.rows && a.columns == b.columns && type_eq(a.elem, b.elem)
		}
	}
	// ^T / [^]T / []T are allocated per syntax node; match by element type.
	if a, ok := a.derived.(^Type_Pointer); ok {
		if b, ok := b.derived.(^Type_Pointer); ok {
			return type_eq(a.elem, b.elem)
		}
		return false
	}
	if a, ok := a.derived.(^Type_Multi_Pointer); ok {
		if b, ok := b.derived.(^Type_Multi_Pointer); ok {
			return type_eq(a.elem, b.elem)
		}
		return false
	}
	if a, ok := a.derived.(^Type_Slice); ok {
		if b, ok := b.derived.(^Type_Slice); ok {
			return type_eq(a.elem, b.elem)
		}
		return false
	}
	if a, ok := a.derived.(^Type_Proc); ok {
		if b, ok := b.derived.(^Type_Proc); ok {
			return type_proc_eq(a, b)
		}
		return false
	}
	return false
}

type_tuple_eq :: proc(a, b: ^Type_Tuple) -> bool {
	an := 0 if a == nil else len(a.variables)
	bn := 0 if b == nil else len(b.variables)
	if an != bn do return false
	for i in 0 ..< an {
		av := a.variables[i]
		bv := b.variables[i]
		if av == nil || bv == nil do return false
		if !type_eq(av.type, bv.type) do return false
		if (.Ref in av.flags) != (.Ref in bv.flags) do return false
	}
	return true
}

type_proc_eq :: proc(a, b: ^Type_Proc) -> bool {
	if a == nil || b == nil do return false
	if a.stage != b.stage do return false
	return type_tuple_eq(a.params, b.params) && type_tuple_eq(a.results, b.results)
}

op_is_relation :: proc(kind: Token_Kind) -> bool {
	#partial switch kind {
	case .Cmp_Eq, .Lt_Eq, .Lt, .Gt, .Gt_Eq, .Not_Eq:
		return true
	}
	return false
}

op_is_arithmetic :: proc(kind: Token_Kind) -> bool {
	#partial switch kind {
	case .Add, .Sub, .Mul, .Quo, .Mod:
		return true
	}
	return false
}

op_is_bitwise :: proc(kind: Token_Kind) -> bool {
	#partial switch kind {
	case .And, .Or, .Xor, .And_Not, .Shl, .Shr:
		return true
	}
	return false
}

op_is_logical :: proc(kind: Token_Kind) -> bool {
	#partial switch kind {
	case .Cmp_And, .Cmp_Or:
		return true
	}
	return false
}

eval_const_bit_set_op :: proc(checker: ^Checker, lhs, rhs: Exact_Value, expr: ^Binary_Expr) -> Exact_Value {
	l, lok := lhs.(i128)
	r, rok := rhs.(i128)
	if !lok || !rok {
		return nil
	}
	#partial switch expr.op.kind {
	case .Or, .Add: return l | r
	case .And: return l & r
	case .Xor: return l ~ r
	case .And_Not, .Sub: return l &~ r
	case .Cmp_Eq: return l == r
	case .Not_Eq: return l != r
	case .Lt_Eq: return (l & r) == l
	case .Lt: return (l & r) == l && l != r
	case .Gt_Eq: return (r & l) == r
	case .Gt: return (r & l) == r && l != r
	}
	check_err(checker, expr.pos, "invalid constant bit_set operation '%s'", expr.op.text)
	return nil
}

eval_const_in_op :: proc(checker: ^Checker, elem, set: Exact_Value, expr: ^Binary_Expr) -> Exact_Value {
	e, eok := elem.(i128)
	s, sok := set.(i128)
	if !eok || !sok {
		return nil
	}
	member := (s & (i128(1) << uint(e))) != 0
	if expr.op.kind == .Not_In {
		return !member
	}
	return member
}

eval_const_unary_op :: proc(checker: ^Checker, operand: Exact_Value, expr: ^Unary_Expr) -> Exact_Value {
	if operand == nil || exact_value_is_compound(operand) {
		return nil
	}
	#partial switch expr.op.kind {
	case .Add:
		return operand
	case .Sub:
		#partial switch v in operand {
		case i128: return -v
		case f64: return -v
		case: check_err(checker, expr.pos, "unary '-' requires a numeric constant")
		}
	case .Not:
		if b, ok := operand.(bool); ok {
			return !b
		}
		check_err(checker, expr.pos, "unary '!' requires a boolean constant")
	case .Xor:
		if i, ok := operand.(i128); ok {
			return ~i
		}
		check_err(checker, expr.pos, "unary '~' requires an integer constant")
	}
	return nil
}

eval_const_binary_op :: proc(checker: ^Checker, lhs, rhs: Exact_Value, expr: ^Binary_Expr) -> Exact_Value {
	lhs, rhs := lhs, rhs
	if lhs == nil || rhs == nil do return nil
	if exact_value_is_compound(lhs) || exact_value_is_compound(rhs) do return nil
	if _, ok := lhs.(string); ok do return nil
	if _, ok := rhs.(string); ok do return nil
	if expr_is_range(expr) {
		return nil
	}

	lhs_tag := reflect.get_union_variant_raw_tag(lhs)
	rhs_tag := reflect.get_union_variant_raw_tag(rhs)

	if lhs_tag != rhs_tag {
		if lhs_int, ok := lhs.(i128); ok {
			lhs = f64(lhs_int)
		} else if rhs_int, ok := rhs.(i128); ok {
			rhs = f64(rhs_int)
		}
	}

	same_type :: proc(lhs, rhs: Exact_Value, $T: typeid) -> (T, T, bool) {
		x, x_ok := lhs.(T)
		y, y_ok := rhs.(T)
		return x, y, x_ok && y_ok
	}

	if l, r, ok := same_type(lhs, rhs, i128); ok do #partial switch expr.op.kind {
	case .And: return l & r
	case .Or: return l | r
	case .Xor: return l ~ r
	case .And_Not: return l &~ r
	case .Add: return l + r
	case .Sub: return l - r
	case .Mul: return l * r
	case .Quo:
		if r == 0 {
			check_err(checker, expr.pos, "division by zero")
			return nil
		}
		return l / r
	case .Mod: // TODO: maybe add mod_mod as mod floored
		if r == 0 {
			check_err(checker, expr.pos, "modulo with zero")
			return nil
		}
		return l % r
	case .Lt: return l < r
	case .Gt: return l > r
	case .Cmp_Eq: return l == r
	case .Not_Eq: return l != r
	case .Lt_Eq: return l <= r
	case .Gt_Eq: return l >= r
	case .Shl: 
		if r < 0 {
			check_err(checker, expr.pos, "shift amount must be an unsigned integer")
			return nil
		}
		return l << uint(r)
	case .Shr:
		if r < 0 {
			check_err(checker, expr.pos, "shift amount must be an unsigned integer")
			return nil
		}
		return l >> uint(r)
	}

	if l, r, ok := same_type(lhs, rhs, f64); ok do #partial switch expr.op.kind {
	case .Add: return l + r
	case .Sub: return l - r
	case .Mul: return l * r
	case .Quo: return l / r
	case .Lt: return l < r
	case .Gt: return l > r
	case .Cmp_Eq: return l == r
	case .Not_Eq: return l != r
	case .Lt_Eq: return l <= r
	case .Gt_Eq: return l >= r
	}

	if l, r, ok := same_type(lhs, rhs, bool); ok do #partial switch expr.op.kind {
	case .And: return l & r
	case .Or: return l | r
	case .Xor: return l ~ r
	case .Cmp_And: return l && r
	case .Cmp_Or: return l || r
	case .Cmp_Eq: return l == r
	case .Not_Eq: return l != r
	}

	check_err(checker, expr.pos, "mismatched types in binary expression: '%v' vs '%v'", string_from_type(expr.left.tav.type), string_from_type(expr.right.tav.type))
	return nil
}

Addressing_Mode :: enum {
	Invalid,
	No_Value, // void
	Value, // rvalue
	Variable, // addressable variable (lvalue)
	Constant,
	Type,
	Builtin, // built-in proc
	Proc,
	Shader,
	Import, // imported module binding

	// These aren't yet used
	Proc_Group, // overloaded proc
	Swizzle_Value, // swizzle indexed value
	Swizzle_Variable, // swizzle indexed variable
}

Operand :: struct {
	expr: ^Expr,
	type: ^Type,
	mode: Addressing_Mode,
	value: Exact_Value,
	builtin_id: Builtin_Proc,
	is_call: bool,
	checked_pipeline: ^Checked_Pipeline, // set by check_pipeline_lit
	ref_syntax: bool, // argument written as `&x` (for #ref params / overload ranking)
}

check_expr_internal :: proc(checker: ^Checker, expr: ^Expr, type_hint: ^Type = nil) -> (operand: Operand) {
	operand.expr = expr
	defer {
		expr.tav.type = operand.type
		expr.tav.value = operand.value
		expr.tav.mode = operand.mode
	}

	#partial switch v in expr.derived {
	case: check_err(checker, expr.pos, "unhandled expression: %v", reflect.union_variant_typeid(expr.derived_expr))
		operand.mode = .Invalid
		operand.type = t_invalid
		return

	case ^Bad_Expr:
		// Incomplete / recovered parse while typing (soft_fail LSP).
		operand.mode = .Invalid
		operand.type = t_invalid
		return

	case ^Undef:
		if type_hint == nil {
			check_err(checker, expr.pos, "'---' requires a type context")
			operand.mode = .Invalid
			operand.type = t_invalid
			return
		}
		operand.mode = .Value
		operand.type = type_hint
		// Marker for codegen: no Exact_Value and we'll set Entity_Flag.No_Init on the binding
		return
	
	case ^Paren_Expr: return check_expr_internal(checker, v.expr, type_hint)
	case ^Comp_Lit:
		type: ^Type
		if v.type != nil {
			type = check_type(checker, v.type)
		} else {
			type = type_hint
		}

		if type == nil {
			check_err(checker, v.pos, "missing type in compound literal")
			operand.mode = .Invalid
			operand.type = t_invalid
			return
		}

		operand.type = type
		operand.mode = .Value

		#partial switch t in type.derived {
		case ^Type_Struct:
			check_struct_comp_lit(checker, v, t, &operand)

		case ^Type_Bit_Set:
			operand.mode = .Constant
			operand.type = type
			mask: i128 = 0
			for elem in v.elems {
				e := check_expr(checker, elem, type_hint = t.elem)
				if e.mode != .Constant || e.value == nil {
					check_err(checker, elem.pos, "bit_set compound literal elements must be constant")
					operand.mode = .Value
					continue
				}
				bit, ok := e.value.(i128)
				if !ok {
					check_err(checker, elem.pos, "bit_set element must be an integer constant")
					operand.mode = .Value
					continue
				}
				if bit < i128(t.lower) || bit > i128(t.upper) {
					check_err(checker, elem.pos, "bit_set element out of range")
					continue
				}
				mask |= i128(1) << uint(bit)
			}
			if operand.mode == .Constant {
				operand.value = exact_int(mask)
			}

		case ^Type_Pipeline:
			check_pipeline_lit(checker, v, &operand)

		case ^Type_Array:
			check_sequence_comp_lit(checker, v, t.len, t.elem, &operand)

		case ^Type_Vector:
			check_vector_comp_lit(checker, v, t, &operand)

		case ^Type_Matrix:
			check_matrix_comp_lit(checker, v, t, &operand)

		case:
			check_err(checker, v.pos, "illegal type '%s' in compound literal", string_from_type(type))
			operand.type = t_invalid
			operand.mode = .Invalid
			return
		}


		
	case ^Basic_Lit:
		operand.mode = .Constant
		
		#partial switch v.tok.kind {
		case .String:
			operand.value = exact_string(unescape_misl_string(v.tok.text))
			operand.type = t_untyped_string
			
		case .Rune:
			r, rok := parse_rune_literal(v.tok.text)
			if !rok {
				check_err(checker, v.pos, "invalid rune literal '%s'", v.tok.text)
				operand.type = t_invalid
				operand.mode = .Invalid
				return
			}
			operand.value = exact_int(i128(r))
			operand.type = t_untyped_rune
			
		case .Float:
			number, ok := parse_misl_float_literal(v.tok.text)
			if !ok {
				check_err(checker, v.pos, "invalid float literal '%s'", v.tok.text)
				operand.type = t_invalid
				operand.mode = .Invalid
				return
			}
			operand.value = exact_float(number)
			operand.type = t_untyped_float

		case .Integer:
			number, ok := strconv.parse_int(v.tok.text)
			if !ok {
				check_err(checker, v.pos, "invalid integer literal '%s'", v.tok.text)
				operand.type = t_invalid
				operand.mode = .Invalid
				return
			}
			operand.value = exact_int(number)
			operand.type = t_untyped_int
		}

		/*
		if type_hint != nil { // maybe this shouldn't be here 
			if type_is_implicit_castable(operand.type, type_hint) {
				operand.type = type_hint
			} else {
				check_err(checker, v.pos, "cannot convert '%s' to '%s'", string_from_type(operand.type), string_from_type(type_hint))
			}
		} else {
			// operand.type = default_type(operand.type) // probably we should call default_type outside of this, in different places
		}
		*/
		
		
		
	case ^Unary_Expr:
		inner := check_expr(checker, v.expr)
		operand.mode = .Constant if inner.mode == .Constant else .Value
		#partial switch v.op.kind {
		case .Add, .Sub:
			if !type_is_numeric_composite(inner.type) {
				check_err(checker, v.pos, "unary '%s' requires a numeric operand, got '%s'", v.op.text, string_from_type(inner.type))
				operand.mode = .Invalid
				operand.type = t_invalid
				return
			}
			operand.type = inner.type
			if inner.mode != .Constant || inner.value == nil || exact_value_is_compound(inner.value) {
				operand.mode = .Value
			}
		case .Not:
			if !type_is_boolean(inner.type) {
				check_err(checker, v.pos, "unary '!' requires a boolean operand, got '%s'", string_from_type(inner.type))
				operand.mode = .Invalid
				operand.type = t_invalid
				return
			}
			operand.type = t_untyped_bool if type_is_untyped(inner.type) else inner.type
		case .Xor:
			if !type_is_integer(inner.type) && !type_is_bit_set(inner.type) {
				check_err(checker, v.pos, "unary '~' requires an integer or bit_set operand, got '%s'", string_from_type(inner.type))
				operand.mode = .Invalid
				operand.type = t_invalid
				return
			}
			operand.type = inner.type
		case .And:
			// Stack address-of is illegal: pointers are BDA-only (`^T` / `[^]T` / `[]T`).
			// `for &elem in …` and `#ref` call arguments peel unary `&` and never reach here.
			check_err(checker, v.pos, "misl does not support stack pointers")
			operand.mode = .Invalid
			operand.type = t_invalid
			return
		case:
			check_err(checker, v.pos, "unhandled unary operator '%v'", v.op.kind)
			operand.mode = .Invalid
			operand.type = t_invalid
			return
		}
		if operand.mode == .Constant {
			operand.value = eval_const_unary_op(checker, inner.value, v)
			if operand.value == nil {
				operand.mode = .Value
			} else if v.op.kind == .Xor && type_is_bit_set(operand.type) {
				if i, ok := operand.value.(i128); ok {
					bs := operand.type.derived.(^Type_Bit_Set)
					bits := bs.upper - bs.lower + 1
					mask := (i128(1) << uint(bits)) - 1
					if bs.lower != 0 {
						mask <<= uint(bs.lower)
					}
					operand.value = exact_int((~i) & mask)
				}
			}
		}

	
	case ^Binary_Expr:
		lhs, rhs: Operand
		if v.op.kind == .In || v.op.kind == .Not_In {
			// Resolve the set first so `.A in s` can type-hint the enum element
			rhs = check_expr(checker, v.right)
			elem_hint: ^Type
			if bs, ok := rhs.type.derived.(^Type_Bit_Set); ok {
				elem_hint = bs.elem
			}
			lhs = check_expr(checker, v.left, type_hint = elem_hint)
		} else {
			lhs = check_expr(checker, v.left)
			rhs_hint := binary_convert_type(lhs.type)
			if type_is_rune_value(lhs.type) && (v.op.kind == .Add || v.op.kind == .Sub) {
				rhs_hint = nil
			}
			rhs = check_expr(checker, v.right, type_hint = rhs_hint)
			is_rune_arith := (v.op.kind == .Add || v.op.kind == .Sub) && (
				(type_is_rune_value(lhs.type) && type_is_integer(rhs.type)) ||
				(type_is_integer(lhs.type) && type_is_rune_value(rhs.type))
			)
			if is_rune_arith {
				if type_is_untyped_rune(lhs.type) {
					convert_to_typed(checker, &lhs, t_rune)
				}
				if type_is_untyped_rune(rhs.type) {
					convert_to_typed(checker, &rhs, t_rune)
				}
			} else {
				convert_to_typed(checker, &lhs, binary_convert_type(rhs.type))
				if lhs.mode == .Invalid {
					operand.mode = .Invalid
					operand.type = t_invalid
					return
				}
				convert_to_typed(checker, &rhs, binary_convert_type(lhs.type))
				if rhs.mode == .Invalid {
					operand.mode = .Invalid
					operand.type = t_invalid
					return
				}
			}
			if lhs.mode == .Invalid || rhs.mode == .Invalid {
				operand.mode = .Invalid
				operand.type = t_invalid
				return
			}
		}
		operand.mode = .Constant if lhs.mode == .Constant && rhs.mode == .Constant else .Value
		operand.type = type_from_binary_op(lhs.type, v.op.kind, rhs.type)

		if operand.type == t_invalid {
			operand.mode = .Invalid
			check_err(checker, v.pos, "invalid binary operation: %v %v %v", string_from_type(lhs.type), v.op.kind, string_from_type(rhs.type))
			return
		}

		if type_hint != nil && type_is_untyped(operand.type) {
			convert_to_typed(checker, &operand, type_hint)
			if operand.mode == .Invalid {
				operand.type = t_invalid
				return
			}
		}

		if operand.mode == .Constant {
			if exact_value_is_compound(lhs.value) || exact_value_is_compound(rhs.value) {
				operand.mode = .Value
				operand.value = nil
			} else if _, lok := lhs.value.(string); lok {
				operand.mode = .Value
				operand.value = nil
			} else if _, rok := rhs.value.(string); rok {
				operand.mode = .Value
				operand.value = nil
			} else if type_is_bit_set(lhs.type) {
				operand.value = eval_const_bit_set_op(checker, lhs.value, rhs.value, v)
			} else if v.op.kind == .In || v.op.kind == .Not_In {
				operand.value = eval_const_in_op(checker, lhs.value, rhs.value, v)
			} else {
				operand.value = eval_const_binary_op(checker, lhs.value, rhs.value, v)
			}
			if operand.value == nil {
				operand.mode = .Value
			}
		}

	case ^Ternary_If_Expr:
		cond := check_expr(checker, v.cond)
		if !type_is_boolean(cond.type) {
			check_err(checker, v.cond.pos, "expected a boolean condition in ternary, got '%s'", string_from_type(cond.type))
		}
		x := check_expr(checker, v.x, type_hint = type_hint)
		y := check_expr(checker, v.y, type_hint = type_hint if type_hint != nil else x.type)

		convert_to_typed(checker, &x, type_hint if type_hint != nil else y.type)
		convert_to_typed(checker, &y, type_hint if type_hint != nil else x.type)

		result_type: ^Type
		if type_hint != nil && type_is_implicit_castable(x.type, type_hint) && type_is_implicit_castable(y.type, type_hint) {
			result_type = type_hint
		} else if type_eq(x.type, y.type) {
			result_type = x.type
		} else if type_is_untyped(x.type) && type_is_implicit_castable(x.type, y.type) {
			result_type = y.type
		} else if type_is_untyped(y.type) && type_is_implicit_castable(y.type, x.type) {
			result_type = x.type
		} else if type_is_implicit_castable(y.type, x.type) {
			result_type = x.type
		} else if type_is_implicit_castable(x.type, y.type) {
			result_type = y.type
		} else {
			check_err(checker, v.pos, "ternary branches have incompatible types '%s' and '%s'", string_from_type(x.type), string_from_type(y.type))
			result_type = t_invalid
		}
		operand.type = result_type
		if type_hint != nil && type_is_untyped(operand.type) {
			convert_to_typed(checker, &operand, type_hint)
			result_type = operand.type
		} else if result_type != nil && result_type != t_invalid {
			// Stamp concrete result into still-untyped branch ASTs
			if type_is_untyped(x.type) do convert_to_typed(checker, &x, result_type)
			if type_is_untyped(y.type) do convert_to_typed(checker, &y, result_type)
			if !type_is_untyped(result_type) {
				update_untyped_expr_type(v.x, result_type)
				update_untyped_expr_type(v.y, result_type)
			}
		}
		operand.mode = .Constant if cond.mode == .Constant && x.mode == .Constant && y.mode == .Constant else .Value
		if operand.mode == .Constant {
			if b, ok := cond.value.(bool); ok {
				operand.value = x.value if b else y.value
			} else {
				operand.mode = .Value
			}
		}

	case ^Ternary_When_Expr:
		cond := check_expr(checker, v.cond)
		if cond.mode != .Constant {
			check_err(checker, v.cond.pos, "'when' expression condition must be a constant")
			operand.mode = .Invalid
			operand.type = t_invalid
			return
		}
		taken := false
		if b, ok := cond.value.(bool); ok {
			taken = b
		} else {
			check_err(checker, v.cond.pos, "'when' expression condition must be a boolean constant")
			operand.mode = .Invalid
			operand.type = t_invalid
			return
		}
		// Only check the taken branch (Odin-style)
		branch := check_expr(checker, v.x if taken else v.y, type_hint = type_hint)
		operand.type = branch.type
		operand.mode = branch.mode
		operand.value = branch.value

	case ^Ident:
		if v.name == "_" {
			v.entity = new_entity_dummy(expr.pos)
			operand.mode = .Variable // discard lvalue only; reading `_` is invalid elsewhere
			operand.type = type_hint if type_hint != nil else t_invalid
			return
		}
		e := scope_lookup(checker.curr_scope, v.name)
		if e == nil {
			check_err(checker, expr.pos, "unknown identifier '%v'", v.name)
			operand.type = t_invalid
			operand.mode = .Invalid
			return
		}
		ensure_entity_resolved(checker, e)
		check_capture_rules(checker, expr.pos, e)
		v.entity = e
		operand.type = e.type
		
		#partial switch e.kind {
		case .Constant:
			if type_is_proc(e.type) && .Poly_Const in e.flags {
				operand.mode = .Proc
				if e.aliased_of != nil {
					operand.type = e.aliased_of.type
				}
			} else {
				operand.mode = .Constant
				operand.value = e.value
			}
		case .Type_Name:
			operand.mode = .Type
		case .Variable:
			operand.mode = .Variable
		case .Procedure:
			operand.mode = .Proc
		case .Entry:
			operand.mode = .Shader
		case .Pipeline:
			operand.mode = .Constant
		case .Builtin:
			operand.mode = .Builtin
			operand.builtin_id = e.builtin_id
		case .Import:
			operand.mode = .Import
			operand.type = t_invalid
		case .Proc_Group:
			operand.mode = .Proc_Group
			operand.type = t_invalid
		case .Dummy:
			operand.mode = .Variable
			operand.type = type_hint if type_hint != nil else t_invalid
		}

	case ^Proc_Lit:
		// Anonymous / non-collected proc literal (e.g. mutable binding)
		lit := v
		type := check_proc_type(checker, lit.type)
		lit.type.scope = type.scope
		if should_check_proc_body_now(checker, type) {
			check_proc_lit_body(checker, lit, type, checker.curr_proc_entity)
		}
		operand.type = type
		operand.mode = .Proc if type.stage == nil else .Shader

	case ^Proc_Group:
		op, _ := check_proc_group_expr(checker, v)
		operand = op
		return

	case ^Implicit_Selector_Expr:
		if type_hint == nil {
			check_err(checker, v.pos, "cannot resolve implicit selector")
			operand.mode = .Invalid
			operand.type = t_invalid
			return
		}

		#partial switch type in type_hint.derived {
		case: check_err(checker, v.pos, "implicit selectors are only supported on enums, got '%s'", string_from_type(type_hint))
		case ^Type_Enum:
			if v.field.name == "" {
				// Incomplete `.` while typing — keep hint; skip empty-field error for the IDE.
				operand.mode = .Invalid
				operand.type = t_invalid
				return
			}
			entity := scope_lookup_current(type.scope, v.field.name)
			if entity == nil {
				check_err(checker, v.pos, "enum '%s' has no field '%s'", string_from_type(type), v.field.name)
				operand.mode = .Invalid
				operand.type = t_invalid
				return
			}
			operand.mode = .Constant
			operand.type = entity.type
			operand.value = entity.value
			v.field.entity = entity
			v.field.tav.value = operand.value // TODO: make this nicer. Currently some ast nodes don't properly store the tav
			v.field.tav.type = operand.type
		}
		
	
	case ^Selector_Expr:
		lhs := check_expr_or_type(checker, v.expr)
		if lhs.mode == .Invalid {
			operand.mode = .Invalid
			operand.type = t_invalid
			return
		}

		// import.name → look up in imported module scope (builtin.sin, foo.Helper, …)
		if lhs.mode == .Import {
			imp_e := entity_from_expr(v.expr)
			if imp_e == nil || imp_e.imported_module == nil || imp_e.imported_module.scope == nil {
				check_err(checker, v.pos, "invalid import selector")
				operand.mode = .Invalid
				operand.type = t_invalid
				return
			}
			found := scope_lookup_current(imp_e.imported_module.scope, v.field.name)
			if found == nil {
				check_err(checker, v.field.pos, "module '%s' has no member '%s'", imp_e.name, v.field.name)
				operand.mode = .Invalid
				operand.type = t_invalid
				return
			}
			ensure_entity_resolved(checker, found)
			v.field.entity = found
			operand.type = found.type
			#partial switch found.kind {
			case .Constant:
				operand.mode = .Constant
				operand.value = found.value
			case .Type_Name:
				operand.mode = .Type
			case .Procedure:
				operand.mode = .Proc
			case .Entry:
				operand.mode = .Shader
			case .Builtin:
				operand.mode = .Builtin
				operand.builtin_id = found.builtin_id
			case .Pipeline:
				operand.mode = .Constant
			case .Proc_Group:
				operand.mode = .Proc_Group
				operand.type = t_invalid
			case:
				check_err(checker, v.field.pos, "cannot select '%s' of kind %s", v.field.name, entity_kind_string(found))
				operand.mode = .Invalid
				operand.type = t_invalid
			}
			return
		}

		if lhs.mode == .Type {
			if enum_t, is_enum := lhs.type.derived.(^Type_Enum); is_enum {
				if v.field.name == "" {
					// Incomplete `Enum_Name.` while typing.
					operand.mode = .Invalid
					operand.type = t_invalid
					return
				}
				entity := scope_lookup_current(enum_t.scope, v.field.name)
				if entity == nil {
					check_err(checker, v.field.pos, "enum '%s' has no field '%s'", string_from_type(lhs.type), v.field.name)
					operand.mode = .Invalid
					operand.type = t_invalid
					return
				}
				operand.mode = .Constant
				operand.type = entity.type
				operand.value = entity.value
				v.field.entity = entity
				v.field.tav.value = operand.value
				v.field.tav.type = operand.type
				return
			}
			check_err(checker, v.pos, "selectors on types aren't doing anything yet")
			return
		}

		// swizzles are possible on a vector
		if vec, is_vec := lhs.type.derived.(^Type_Vector); is_vec {
			duplicates := false // if indices repeat (e.g. v.rr), than the addressing mode cannot be an lvalue
			seen_index: [4]bool
			for char in v.field.name {
				index := -1
				switch char {
				case 'r', 'x': index = 0
				case 'g', 'y': index = 1
				case 'b', 'z': index = 2
				case 'a', 'w': index = 3
				}

				if index == -1 {
					check_err(checker, v.field.pos, "'%v' is not a valid swizzle index", char)
					return
				}
				
				if index >= cast(int)vec.len {
					check_err(checker, v.field.pos, "'%v' swizzle index is larger than vector's size", char)
				}
				
				if seen_index[index] {
					duplicates = true
				}
				seen_index[index] = true
			}

			if len(v.field.name) == 1 {
				operand.type = vec.elem
				operand.mode = .Swizzle_Variable if lhs.mode == .Variable else lhs.mode
				return
			}

			new_vec := new_type(Type_Vector)
			new_vec.len = auto_cast len(v.field.name)
			new_vec.elem = vec.elem
			operand.type = new_vec
			if duplicates || lhs.mode != .Variable {
				operand.mode = .Value
			} else {
				operand.mode = .Swizzle_Variable
			}
			return
		}

		// Incomplete `mp.` / `arr.` / `slice.` while typing — these types have no fields
		// (index first). Keep LHS typed; skip the empty-field error for the IDE.
		if v.field.name == "" {
			#partial switch _ in lhs.type.derived {
			case ^Type_Multi_Pointer, ^Type_Array, ^Type_Slice:
				operand.mode = .Invalid
				operand.type = t_invalid
				return
			}
		}

		// TODO(Dragos): this is a hacky way of "dereferencing pointers"
		struct_t, is_struct := lhs.type.derived.(^Type_Struct)
		ptr_t, is_ptr := lhs.type.derived.(^Type_Pointer)
		if is_ptr {
			struct_t, is_struct = ptr_t.elem.derived.(^Type_Struct)
		}
		if is_struct {
			if v.field.name == "" {
				// Incomplete `foo.` while typing — LHS is typed; skip the empty-field error.
				operand.mode = .Invalid
				operand.type = t_invalid
				return
			}
			found := scope_lookup_current(struct_t.scope, v.field.name)
			if found == nil {
				for field in struct_t.fields.variables {
					if field != nil && field.name == v.field.name {
						found = field
						break
					}
				}
			}
			if found != nil {
				if len(found.using_chain) > 0 {
					rewrite_selector_using_chain(v, found.using_chain)
					operand.type = found.type
					operand.mode = lhs.mode
					return
				}
				operand.type = found.type
				operand.mode = lhs.mode
				v.field.entity = found
				return
			}
		}
		
		check_err(checker, v.pos, "expression of type '%v' has no field called '%s'", reflect.union_variant_type_info(lhs.type.derived), v.field.name)
		return

	case ^Type_Cast:
		operand.type = check_type(checker, v.type)
		// Do not pass dest as type_hint: `cast(i32)1.5` is an explicit truncate,
		// not an implicit untyped-float → i32 conversion.
		value := check_expr(checker, v.expr)
		if !type_is_castable(value.type, operand.type) {
			check_err(checker, v.pos, "cannot cast expression of type '%v' to '%v'", string_from_type(value.type), string_from_type(operand.type))
		}
		if value.mode == .Constant && exact_value_is_numeric(value.value) {
			if converted, ok := fold_constant_cast(checker, v.pos, value.value, operand.type); ok {
				operand.mode = .Constant
				operand.value = converted
			} else {
				operand.mode = .Invalid
			}
		} else {
			operand.mode = .Value
		}

	case ^Auto_Cast:
		if type_hint == nil {
			check_err(checker, v.pos, "auto_cast requires a contextual destination type")
			operand.mode = .Invalid
			operand.type = t_invalid
			return
		}
		value := check_expr(checker, v.expr, type_hint = type_hint)
		if !type_is_castable(value.type, type_hint) {
			check_err(checker, v.pos, "cannot auto_cast expression of type '%v' to '%v'", string_from_type(value.type), string_from_type(type_hint))
			operand.mode = .Invalid
			operand.type = t_invalid
			return
		}
		operand.type = type_hint
		operand.mode = .Value

	case ^Call_Expr: // casts, fn calls, builtin calls, and special cases for vector and matrix types
		if bd, is_bd := unparen_expr(v.expr).derived.(^Basic_Directive); is_bd {
			switch bd.name {
			case "config":
				check_config_expr(checker, v, &operand)
				return
			case "intrinsic":
				check_intrinsic_expr(checker, v, &operand)
				return
			}
		}
		fn := check_expr_internal(checker, v.expr, nil)
		if fn.mode == .Proc_Group {
			chosen := resolve_proc_group_overload(checker, v, fn)
			if chosen == nil {
				operand.mode = .Invalid
				operand.type = t_invalid
				return
			}
			rebind_call_callee(v, chosen)
			fn.mode = .Proc
			fn.type = chosen.type
		}
		#partial switch fn.mode {
		case .Invalid:
			check_err(checker, fn.expr.pos, "expected a callable expression, got an invalid expression")
			return
		case .Builtin:
			builtin := check_builtin(checker, v, fn.builtin_id, type_hint)
			operand.mode = builtin.mode
			operand.is_call = builtin.is_call
			operand.builtin_id = builtin.builtin_id
			operand.type = builtin.type
			operand.value = builtin.value

		
		case .Type:
			if type_is_vector(fn.type) {
				return_t := fn.type.derived.(^Type_Vector)
				return_t_elem := return_t.elem
				return_vec_len := cast(int)return_t.len
				ctor_elems := 0
				for arg in v.args {
					o := check_expr(checker, arg, type_hint = return_t.elem)
					#partial switch arg_type in o.type.derived {
					case ^Type_Vector:
						if !type_eq(return_t_elem, arg_type.elem) {
							check_err(checker, arg.pos, "incompatible type for vector constructor. Expression must evaluate to a '%v' or a vector of it, got '%v'", string_from_type(return_t_elem), string_from_type(arg_type))
							return
						}
						ctor_elems += auto_cast arg_type.len

					case ^Type_Scalar:
						if !type_eq(return_t_elem, arg_type) {
							check_err(checker, arg.pos, "incompatible type for vector constructor. Expression must evaluate to a '%v' or a vector of it, got '%v'", string_from_type(return_t_elem), string_from_type(arg_type))
							return
						}
						ctor_elems += 1

					case:
						check_err(checker, arg.pos, "expression of type '%v' is incompatible with this vector constructor", string_from_type(o.type))
						return
					}
					
					// TODO: better error messaging
					// we should split the constructor in each expression and tell the user what it evaluates to
					if ctor_elems > return_vec_len {
						check_err(checker, arg.pos, "vector constructor needs to evaluate to %v elements, but we got more", return_vec_len)
						return
					}
				}
				
				operand.mode = .Value
				operand.type = return_t
			} else if type_is_matrix(fn.type) { // allows (matrix[R, C]f32)(a, b, c, ....)
				return_t := fn.type.derived.(^Type_Matrix)
				return_t_elem := return_t.elem
				// TODO: add more constructor options
				if !(len(v.args) == 1 || len(v.args) == int(return_t.columns * return_t.rows)) {
					check_err(checker, v.pos, "matrix constructor expects either 1 or %d parameters, got %d", return_t.columns * return_t.rows, len(v.args))
					break
				}
				
				for arg in v.args {
					op := check_expr(checker, arg, type_hint = return_t.elem)
					_ = op
				}

				operand.mode = .Value
				operand.type = return_t

			} else if type_is_scalar(fn.type) || type_is_boolean(fn.type) || type_is_enum(fn.type) || type_is_bit_set(fn.type) {
				// Scalar / enum / bit_set type-call cast: `i32(x)`, `f32(y)`
				if len(v.args) != 1 {
					check_err(checker, v.pos, "cast to '%s' expects 1 argument, got %d", string_from_type(fn.type), len(v.args))
					return
				}
				arg := check_expr(checker, v.args[0])
				if !type_is_castable(arg.type, fn.type) && !type_is_implicit_castable(arg.type, fn.type) {
					check_err(checker, v.args[0].pos, "cannot cast '%s' to '%s'", string_from_type(arg.type), string_from_type(fn.type))
					return
				}
				operand.type = fn.type
				if arg.mode == .Constant && exact_value_is_numeric(arg.value) {
					if converted, ok := fold_constant_cast(checker, v.args[0].pos, arg.value, fn.type); ok {
						operand.mode = .Constant
						operand.value = converted
					} else {
						operand.mode = .Invalid
					}
				} else {
					operand.mode = .Constant if arg.mode == .Constant else .Value
					if operand.mode == .Constant {
						operand.value = arg.value
					}
				}
			} else {
				check_err(checker, fn.expr.pos, "casts not yet implemented for type '%s'", string_from_type(fn.type))
				return
			}
		
		case:
			if proc_t, is_proc := fn.type.derived.(^Type_Proc); !is_proc {
				check_err(checker, v.pos, "expected a procedure in call expression")
				return
			}
			proc_t := fn.type.derived.(^Type_Proc)
			arg_index := 0
			for e, i in v.args {
				type_hint: ^Type
				param_e: ^Entity
				if arg_index < len(proc_t.params.variables) {
					param_e = proc_t.params.variables[arg_index]
					type_hint = param_e.type
				}
				value := check_call_argument(checker, e, param_e, type_hint)
				if arg_index >= len(proc_t.params.variables) {
					continue
				}

				if tuple_t, is_tuple := value.type.derived.(^Type_Tuple); is_tuple {
					for var in tuple_t.variables {
						if arg_index >= len(proc_t.params.variables) {
							break
						}

						if !type_is_implicit_castable(var.type, proc_t.params.variables[arg_index].type) {
							check_err(checker, value.expr.pos, "mismatched type at argument %d: '%v' vs '%v'", arg_index, string_from_type(proc_t.params.variables[arg_index].type), string_from_type(var.type))
						}

						e.tav.type = proc_t.params.variables[arg_index].type
						arg_index += 1
					}
				} else {
					if !type_is_implicit_castable(value.type, proc_t.params.variables[arg_index].type) {
						want := proc_t.params.variables[arg_index].type
						if conv, reported := try_using_convert(checker, e, value.type, want); conv != nil {
							v.args[i] = conv
							value.type = want
							value.mode = conv.tav.mode
							value.expr = conv
						} else if !reported {
							check_err(checker, value.expr.pos, "mismatmismatched type at argument %d: '%v' vs '%v'", arg_index, string_from_type(want), string_from_type(value.type))
						}
					}
					v.args[i].tav.type = proc_t.params.variables[arg_index].type
					arg_index += 1
				}
			}
			if arg_index != len(proc_t.params.variables) {
				check_err(checker, v.pos, "exepcted %d arguments but got %d", len(proc_t.params.variables), arg_index)
				// should we return here?
			}
			callee := strip_entity_wrapping(entity_from_expr(v.expr))
			if proc_is_generic_template(proc_t) {
				arg_ops := make([]Operand, len(proc_t.params.variables), context.temp_allocator)
				ai := 0
				for e in v.args {
					if ai >= len(arg_ops) do break
					op: Operand
					op.expr = e
					op.type = e.tav.type
					op.mode = e.tav.mode
					op.value = e.tav.value
					if tuple_t, is_tuple := e.tav.type.derived.(^Type_Tuple); is_tuple {
						for var in tuple_t.variables {
							if ai >= len(arg_ops) do break
							arg_ops[ai] = Operand{expr = e, type = var.type, mode = .Value}
							ai += 1
						}
					} else {
						arg_ops[ai] = op
						ai += 1
					}
				}
				spec := find_or_generate_poly_proc(checker, callee, arg_ops, v)
				if spec != nil && spec.type != nil {
					rebind_call_callee(v, spec)
					proc_t = spec.type.derived.(^Type_Proc)
					callee = spec
				}
			}
			// Results are always a Type_Tuple (0, 1, or N elements) so unpack /
			// call_result_count / return-forwarding stay uniform. Single-value
			// contexts flatten 1-tuples in check_expr (!allow_multi_value).
			has_values := proc_t.results != nil && len(proc_t.results.variables) != 0
			operand.type = proc_t.results
			operand.mode = .Value if has_values else .No_Value
			operand.is_call = true
			if fn.mode == .Proc || fn.mode == .Shader {
				if callee != nil {
					ensure_proc_body_checked(checker, callee)
				}
				record_proc_call(checker, callee, v.pos)
			}
		}

	case ^Index_Expr:
		indexed_expr := check_expr(checker, v.expr)
		index := check_expr(checker, v.index)
		operand.mode = .Value
		operand.type = t_invalid

		index_i: i128
		index_const := index.mode == .Constant && index.value != nil
		if index_const {
			if ii, ok := index.value.(i128); ok {
				index_i = ii
			} else {
				index_const = false
			}
		}

		#partial switch indexed_type in indexed_expr.type.derived {
		case ^Type_Array:
			operand.type = indexed_type.elem
			if index_const {
				if index_i < 0 || index_i >= i128(indexed_type.len) {
					check_err(checker, v.index.pos, "index %v is out of range 0..<%d", index_i, indexed_type.len)
				} else if indexed_expr.mode == .Constant {
					if elem, ok := const_array_elem_value(indexed_expr.value, int(index_i), indexed_type.elem); ok {
						operand.mode = .Constant
						operand.value = elem
					}
				}
			}
			if operand.mode != .Constant {
				#partial switch indexed_expr.mode {
				case .Variable, .Swizzle_Variable:
					operand.mode = .Variable
				case:
					operand.mode = .Value
				}
			}
		case ^Type_Vector:
			operand.type = indexed_type.elem
			#partial switch indexed_expr.mode {
			case .Variable, .Swizzle_Variable:
				operand.mode = .Variable
			case:
				operand.mode = .Value
			}
		case ^Type_Slice:
			operand.type = indexed_type.elem
			#partial switch indexed_expr.mode {
			case .Variable, .Swizzle_Variable:
				operand.mode = .Variable
			case:
				operand.mode = .Value
			}
		case ^Type_Multi_Pointer:
			operand.type = indexed_type.elem
			#partial switch indexed_expr.mode {
			case .Variable, .Swizzle_Variable:
				operand.mode = .Variable
			case:
				operand.mode = .Value
			}
		case ^Type_Atom:
			if type_is_string_kind(indexed_expr.type) {
				operand.type = t_u8
				s, is_str := indexed_expr.value.(string)
				if indexed_expr.mode == .Constant && is_str {
					n := i128(len(s))
					if index_const {
						if index_i < 0 || index_i >= n {
							check_err(checker, v.index.pos, "index %v is out of range 0..<%d", index_i, len(s))
						} else {
							operand.mode = .Constant
							operand.value = exact_int(i128(s[index_i]))
						}
					}
				}
				if operand.mode != .Constant {
					operand.mode = .Value
				}
			}
		}

		if operand.type == t_invalid {
			check_err(checker, v.expr.pos, "expression of type '%v' cannot be indexed", reflect.union_variant_typeid(indexed_expr.type.derived))
		}

	case ^Struct_Type:
		operand.mode = .Type
		operand.type = check_struct_type(checker, v)

	case ^Enum_Type:
		operand.mode = .Type
		operand.type = check_enum_type(checker, v)

	case ^Matrix_Type:
		operand.mode = .Type
		operand.type = check_matrix_type(checker, v)

	case ^Array_Type:
		operand.mode = .Type
		operand.type = check_array_type(checker, v)

	case ^Multi_Pointer_Type:
		operand.mode = .Type
		operand.type = check_multi_pointer_type(checker, v)

	case ^Bit_Set_Type:
		operand.mode = .Type
		operand.type = check_bit_set_type(checker, v)

	case ^Pointer_Type:
		operand.mode = .Type
		operand.type = check_pointer_type(checker, v)
	case ^Proc_Type:
		operand.mode = .Type
		operand.type = check_proc_type(checker, v)
	case ^Helper_Type:
		operand.mode = .Type
		operand.type = check_type(checker, v.type)
	case ^Basic_Directive:
		check_err(checker, expr.pos, "directive '%s' is not valid in this expression context", v.name)

	case ^Deref_Expr:
		inner := check_expr(checker, v.expr)
		ptr, is_ptr := inner.type.derived.(^Type_Pointer)
		if !is_ptr {
			check_err(checker, v.pos, "cannot dereference non-pointer type '%s'", string_from_type(inner.type))
			operand.mode = .Invalid
			operand.type = t_invalid
			return
		}
		operand.type = ptr.elem
		operand.mode = .Variable if inner.mode == .Variable || inner.mode == .Value else inner.mode

	case ^Slice_Expr:
		base := check_expr(checker, v.expr)
		#partial switch bt in base.type.derived {
		case ^Type_Multi_Pointer:
			// mp[:high] / mp[low:high] → []T
			// mp[low:]                 → [^]T (pointer advance; no length)
			// mp[:]                    → error (neither offset nor length)
			if v.high == nil && v.low == nil {
				check_err(checker, v.pos, "cannot slice multipointer with 'mp[:]'; use 'mp[:n]', 'mp[i:j]', or 'mp[i:]'")
				operand.mode = .Invalid
				operand.type = t_invalid
				return
			}
			if v.low != nil {
				check_slice_bound(checker, v.low, "start index")
			}
			if v.high != nil {
				check_slice_bound(checker, v.high, "end index")
				slice_t := new_type(Type_Slice)
				slice_t.elem = bt.elem
				operand.type = slice_t
				operand.mode = .Value
			} else {
				// mp[low:] — advance multipointer
				mp_t := new_type(Type_Multi_Pointer)
				mp_t.elem = bt.elem
				operand.type = mp_t
				operand.mode = .Value
			}
		case ^Type_Slice:
			// s[low:high] / s[low:] / s[:high] / s[:]
			if v.low != nil {
				check_slice_bound(checker, v.low, "start index")
			}
			if v.high != nil {
				check_slice_bound(checker, v.high, "end index")
			}
			slice_t := new_type(Type_Slice)
			slice_t.elem = bt.elem
			operand.type = slice_t
			operand.mode = .Value
		case:
			check_err(checker, v.pos, "cannot slice type '%s'", string_from_type(base.type))
			operand.mode = .Invalid
			operand.type = t_invalid
		}
	}

	return operand
}

check_slice_bound :: proc(checker: ^Checker, expr: ^Expr, what: string) {
	op := check_expr(checker, expr, type_hint = t_i64)
	if !type_is_integer(op.type) {
		check_err(checker, expr.pos, "slice %s must be integer, got '%s'", what, string_from_type(op.type))
	}
}

// Flatten 1-tuples for single-value contexts; reject N>=2. Call results keep
// addressing mode Value (foo().val is not assignable).
flatten_tuple_for_single_value :: proc(c: ^Checker, expr: ^Expr, operand: ^Operand) {
	if operand.type == nil || operand.mode == .Invalid || operand.mode == .No_Value {
		return
	}
	tuple_t, is_tuple := operand.type.derived.(^Type_Tuple)
	if !is_tuple {
		return
	}
	n := len(tuple_t.variables)
	if n == 1 {
		operand.type = tuple_t.variables[0].type
	} else if n > 1 {
		check_err(c, expr.pos, "multiple return values (%d) cannot be used in a single-value context", n)
		operand.mode = .Invalid
		operand.type = t_invalid
	}
}

check_expr_or_type :: proc(checker: ^Checker, expr: ^Expr, type_hint: ^Type = nil) -> (operand: Operand) {
	operand = check_expr_internal(checker, expr, type_hint)
	#partial switch operand.mode {
	case .Variable, .Value, .Constant, .Type, .Proc, .Shader, .Import, .Builtin:
		flatten_tuple_for_single_value(checker, expr, &operand)
		if expr != nil {
			expr.tav.type = operand.type
			expr.tav.mode = operand.mode
			expr.tav.value = operand.value
		}
		if operand.mode == .Invalid {
			return operand
		}
		// Builtin/Import allowed as selector LHS (builtin.sin) or call callee
		if operand.mode != .Import && operand.mode != .Builtin && operand.type == nil {
			check_err(checker, expr.pos, "internal: expression has no type")
			operand.mode = .Invalid
			operand.type = t_invalid
		}
		return
	case .No_Value:
		check_err(checker, expr.pos, "expected an expression, got no value")

	case .Invalid:
		check_err(checker, expr.pos, "invalid expression")
	}
	operand.mode = .Invalid
	operand.type = t_invalid
	return operand
}



stamp_expr_operand :: proc(expr: ^Expr, op: Operand) {
	expr := expr
	for expr != nil {
		expr.tav.type = op.type
		expr.tav.mode = op.mode
		expr.tav.value = op.value
		if p, ok := expr.derived.(^Paren_Expr); ok {
			expr = p.expr
			continue
		}
		break
	}
}

check_call_argument :: proc(c: ^Checker, e: ^Expr, param_e: ^Entity, type_hint: ^Type) -> Operand {
	is_ref_param := param_e != nil && .Ref in param_e.flags
	inner, has_and := peel_unary_and(e)
	if is_ref_param {
		if !has_and {
			check_err(c, e.pos, "'#ref' argument requires '&'")
			return check_expr(c, e, type_hint = type_hint, allow_multi_value = true)
		}
		value := check_expr(c, inner, type_hint = type_hint, allow_multi_value = true)
		stamp_expr_operand(e, value)
		if value.mode != .Variable && value.mode != .Swizzle_Variable {
			check_err(c, e.pos, "'#ref' argument must be an addressable lvalue")
		}
		value.expr = e
		value.ref_syntax = true
		return value
	}
	return check_expr(c, e, type_hint = type_hint, allow_multi_value = true)
}

check_expr :: proc(c: ^Checker, expr: ^Expr, type_hint: ^Type = nil, allow_no_value := false, allow_multi_value := false) -> (operand: Operand) {
	operand = check_expr_internal(c, expr, type_hint = type_hint)
	if type_hint != nil && type_is_untyped(operand.type) && operand.mode != .Invalid {
		convert_to_typed(c, &operand, type_hint)
	}
	// Flatten 1-tuples for single-value contexts; reject N>=2. The Call_Expr's
	// tav.type remains the full tuple until this write-back (check_expr_internal defer).
	// Builtins/types may have a nil type until rejected below — do not touch .derived.
	if !allow_multi_value {
		flatten_tuple_for_single_value(c, expr, &operand)
	}
	if operand.mode == .Constant {
		if !check_constant_fits(c, expr.pos, operand.value, operand.type) {
			operand.mode = .Invalid
		}
	}
	#partial switch operand.mode {
	case .Value, .Variable, .Constant, .Proc, .Swizzle_Variable, .Swizzle_Value:
		if operand.type == nil {
			// Soft-fail / incomplete buffers can produce typed modes without a type.
			// Never slice module.code with possibly-inverted spans for the assert message.
			check_err(c, expr.pos, "internal: expression has no type")
			operand.mode = .Invalid
			operand.type = t_invalid
		}
	case .Builtin:
		check_err(c, expr.pos, "expected an expression, got builtin")
		operand.mode = .Invalid
		operand.type = t_invalid
	case .Type:
		check_err(c, expr.pos, "exprected an expression, got type")
		operand.mode = .Invalid
		operand.type = t_invalid
	case .No_Value:
		if !allow_no_value {
			if operand.builtin_id == .fmag_exec {
				check_err(c, expr.pos, "fmag.exec cannot infer result types")
			} else {
				check_err(c, expr.pos, "expected a value, got none")
			}
			operand.mode = .Invalid
			operand.type = t_invalid
		}
	case:
		operand.mode = .Invalid
		operand.type = t_invalid
	}
	// check_expr_internal's defer may have written a nil/pre-normalize type; keep AST in sync.
	if expr != nil {
		expr.tav.type = operand.type
		expr.tav.mode = operand.mode
		expr.tav.value = operand.value
	}
	return
}

call_result_count :: proc(v: Operand) -> int {
	if v.mode == .No_Value do return 0
	if v.type == nil do return 1
	if tuple_t, ok := v.type.derived.(^Type_Tuple); ok {
		return len(tuple_t.variables)
	}
	return 1
}

value_decl_has_shared_attr :: proc(c: ^Checker, decl: ^Value_Decl) -> bool {
	found := false
	for attr in decl.attributes {
		for elem in attr.elems {
			name: string
			if ident, ok := elem.derived.(^Ident); ok {
				name = ident.name
			} else if fv, ok := elem.derived.(^Field_Value); ok {
				if ident, ok := fv.field.derived.(^Ident); ok {
					name = ident.name
				}
			}
			switch name {
			case "shared":
				if found {
					check_err(c, elem.pos, "duplicate 'shared' attribute")
				}
				found = true
				if fv, ok := elem.derived.(^Field_Value); ok {
					check_err(c, fv.pos, "'@shared' takes no value")
				}
			case "size":
				check_err(c, elem.pos, "'@(size=…)' is only allowed on compute entry procedures")
			case "":
				check_err(c, elem.pos, "invalid attribute")
			case:
				check_err(c, elem.pos, "unknown attribute '%s'", name)
			}
		}
	}
	return found
}

type_contains_device_address :: proc(type: ^Type) -> bool {
	if type == nil do return false
	#partial switch t in type.derived {
	case ^Type_Pointer, ^Type_Multi_Pointer, ^Type_Slice:
		return true
	case ^Type_Array:
		return type_contains_device_address(t.elem)
	case ^Type_Struct:
		for f in t.fields.variables {
			if type_contains_device_address(f.type) do return true
		}
	}
	return false
}

check_shared_decl_ok :: proc(c: ^Checker, decl: ^Value_Decl, type: ^Type) -> bool {
	if c.curr_proc == nil {
		check_err(c, decl.pos, "'@shared' is only allowed inside a compute entry body")
		return false
	}
	stage, ok := c.curr_proc.stage.?
	if !ok || stage != .Compute {
		check_err(c, decl.pos, "'@shared' is only allowed inside a compute entry body")
		return false
	}
	if !decl.is_mutable {
		check_err(c, decl.pos, "'@shared' requires a mutable declaration (`name: Type`)")
		return false
	}
	if type_contains_device_address(type) {
		check_err(c, decl.pos, "'@shared' type must not contain device pointers (^T / [^]T / []T)")
		return false
	}
	// Must be sized: reject open slices already covered; arrays/structs/scalars/vectors OK
	#partial switch t in type.derived {
	case ^Type_Proc, ^Type_Pipeline:
		check_err(c, decl.pos, "invalid '@shared' type '%s'", string_from_type(type))
		return false
	}
	return true
}

check_value_decl :: proc(c: ^Checker, decl: ^Value_Decl) {
	if decl.is_using {
		check_err(c, decl.pos, "'using' on a declaration is not supported")
		return
	}
	is_global := c.curr_scope == c.module.scope
	if is_global && decl.is_mutable {
		check_err(c, decl.pos, "only constant declarations are allowed at module scope")
		return
	}

	is_shared := value_decl_has_shared_attr(c, decl)

	new_name_count := 0
	for name in decl.names {
		ident, is_ident := name.derived.(^Ident)
		if !is_ident {
			check_err(c, name.pos, "expected an identifier")
			return
		}

		if is_blank_ident(ident.name) {
			ident.entity = new_entity_dummy(ident.pos)
			ident.entity.ident = ident
		} else {
			if found := scope_lookup_current(c.curr_scope, ident.name); found != nil {
				check_err(c, found.ident.pos, "redeclaration of '%s' in this scope", found.ident.name)
				return
			} else {
				new_name_count += 1
			}
		}
	}

	if new_name_count == 0 {
		check_err(c, decl.pos, "no new declarations found in declaration statement")
		return
	}

	init_type: ^Type
	if decl.type != nil {
		init_type = check_type(c, decl.type)
	}

	// `i: i32` — typed mutable decl with no initializer (zero value). Valid Odin/MISL.
	// `@shared tile: [64]f32` — same shape; left uninitialized in GLSL.
	if len(decl.values) == 0 {
		if init_type == nil {
			check_err(c, decl.pos, "missing variable type or initialization")
			return
		}
		if !decl.is_mutable {
			check_err(c, decl.pos, "constant declaration requires an initializer")
			return
		}
		if type_is_string_kind(init_type) {
			check_err(c, decl.pos, "string is compile-time only")
			return
		}
		if is_shared {
			if !check_shared_decl_ok(c, decl, init_type) {
				return
			}
		}
		for name in decl.names {
			ident := name.derived.(^Ident)
			name.tav.type = init_type
			if ident.entity == nil {
				e := new_entity(.Variable, c.curr_scope, ident.pos, ident.name, init_type)
				ident.entity = e
				e.ident = ident
				e.module = c.module
				if is_shared {
					e.flags += {.Shared, .No_Init}
					append(&c.curr_proc.shared_vars, e)
				}
				scope_insert(c.curr_scope, e)
			}
		}
		return
	}

	if is_shared {
		check_err(c, decl.pos, "'@shared' declarations must not have an initializer")
		return
	}

	rhs_count := 0
	lhs_count := len(decl.names)
	rhs := make([dynamic]Operand)
	for value, i in decl.values {
		// Keep full result tuples for multi-name unpack (`a, b := f()`).
		v := check_expr(c, value, type_hint = init_type, allow_multi_value = true)
		// Untyped RHS: convert only with an explicit type hint, or when defaulting
		// a mutable inferred decl (`x := 2` → i32). Constants keep the exact
		// expression type (`A :: 2` stays untyped integer).
		if type_is_untyped(v.type) {
			if init_type != nil {
				convert_to_typed(c, &v, init_type)
			} else if decl.is_mutable {
				if type_is_string_kind(v.type) {
					check_err(c, value.pos, "string is compile-time only")
				} else {
					convert_to_typed(c, &v, default_type(v.type))
				}
			}
		} else if init_type != nil && call_result_count(v) == 1 {
			slots := type_split_tuple(v.type)
			if len(slots) == 1 && type_is_implicit_castable(slots[0], init_type) {
				v.type = init_type
			} else if len(slots) == 1 && !type_is_implicit_castable(slots[0], init_type) {
				if conv, reported := try_using_convert(c, value, slots[0], init_type); conv != nil {
					decl.values[i] = conv
					v.type = init_type
					v.expr = conv
				} else if !reported {
					check_err(c, value.pos, "cannot initialize '%s' with '%s'", string_from_type(init_type), string_from_type(slots[0]))
				}
			}
		}

		if v.mode == .No_Value {
			check_err(c, value.pos, "expected a value returning expression")
			return
		}

		rhs_count += call_result_count(v)
		append(&rhs, v)
	}

	if lhs_count != rhs_count {
		check_err(c, decl.pos, "expected %d values on the right-hand side, got %d", lhs_count, rhs_count)
		return
	}

	name_offset := 0
	for v in rhs {
		value_types := type_split_tuple(v.type)
		entity_kind: Entity_Kind
		#partial switch v.mode {
		case:
			snippet := ""
			if v.expr != nil && c.module != nil {
				start := v.expr.pos.offset
				end := v.expr.end.offset
				if start >= 0 && end <= len(c.module.code) && start < end {
					snippet = c.module.code[start:end]
				}
			}
			check_err(c, v.expr.pos, "unexpected addressing mode '%v' for expression '%v'", v.mode, snippet)
		case .Proc: entity_kind = .Procedure
		case .Shader: entity_kind = .Entry
		case .Type: entity_kind = .Type_Name
		case .Variable, .Value, .Swizzle_Variable, .Swizzle_Value: entity_kind = .Variable
		case .Constant:
			if type_is_pipeline(v.type) {
				if decl.is_mutable {
					check_err(c, v.expr.pos, "pipeline must be a constant declaration (`::`)")
					return
				}
				entity_kind = .Pipeline
			} else {
				entity_kind = .Variable if decl.is_mutable else .Constant
			}
		}
		for value_type, i in value_types {
			defer name_offset += 1
			name := decl.names[name_offset]
			ident := name.derived.(^Ident)
			name.tav.type = value_type
			if decl.is_mutable && type_is_string_kind(value_type) {
				check_err(c, name.pos, "string is compile-time only")
			}
			if ident.entity == nil {
				e := new_entity(entity_kind, c.curr_scope, ident.pos, ident.name, value_type)
				ident.entity = e
				e.ident = ident
				e.module = c.module
				if entity_kind == .Type_Name && value_type != nil && value_type.name == "" {
					value_type.name = ident.name
				}
				if entity_kind == .Constant {
					if v.value == nil {
						check_err(c, v.expr.pos, "constant declaration requires a constant expression")
					} else {
						e.value = v.value
					}
				}
				if _, is_undef := v.expr.derived.(^Undef); is_undef {
					if entity_kind != .Variable {
						check_err(c, v.expr.pos, "'---' can only initialize variables")
					}
					e.flags += {.No_Init}
				}
				scope_insert(c.curr_scope, e)
				if entity_kind == .Entry {
					bind_entry_entity(c.module, e)
				}
				if entity_kind == .Pipeline {
					e.checked_pipeline = v.checked_pipeline
					bind_pipeline_entity(c.module, e)
				}
			}
		}
	}
}

check_decl :: proc(c: ^Checker, decl: ^Stmt) {
	#partial switch d in decl.derived {
	case: check_err(c, decl.pos, "unexpected or invalid declaration detected")
	case ^Value_Decl: check_value_decl(c, d)
	}
}

check_proc_type :: proc(c: ^Checker, pt: ^Proc_Type, poly_operands: []Operand = nil) -> ^Type_Proc {
	type := new_type(Type_Proc)
	type.local_size = {1, 1, 1}
	type.is_polymorphic = pt.generic
	type.is_poly_specialized = pt.generic && poly_operands != nil
	// Parent to current scope so nested procs see enclosing `::` bindings
	type.scope = create_scope(c.curr_scope, .Proc)
	type.scope.proc_type = type
	
	switch pt.calling_convention {
	case "vertex", "vert", "vs": type.stage = .Vertex
	case "fragment", "frag", "fs", "pixel", "ps": type.stage = .Fragment
	case "compute", "comp", "cs": type.stage = .Compute
	case "fmag":
		type.stage = nil
		type.is_fmag = true
	case "": type.stage = nil
	case: check_err(c, pt.pos, "unknown stage type '%s'", pt.calling_convention)
	}

	allowed_params: Semantics
	allowed_results: Semantics
	if stage, ok := type.stage.?; ok {
		switch stage {
		case .Compute:
			allowed_params = Allowed_Semantics_Compute_Params
			allowed_results = {} // void only
		case .Vertex, .Fragment:
			allowed_params = Allowed_Semantics_Shader_Params
			allowed_results = Allowed_Semantics_Shader_Results
		}
	}
	
	type.params = check_field_list(c, type.scope, pt.params, allowed_params if type.stage != nil else nil, true, poly_operands, allow_using = true)
	type.results = check_field_list(c, type.scope, pt.results, allowed_results if type.stage != nil else nil, false)
	inject_param_using(c, type.params)

	if stage, ok := type.stage.?; ok && stage == .Compute {
		if type.results != nil && len(type.results.variables) != 0 {
			check_err(c, pt.pos, "compute shaders must not have results")
		}
	}
	
	if proc_is_generic_template(type) {
		if type.is_fmag {
			check_err(c, pt.pos, "proc \"fmag\" cannot be polymorphic")
		} else if type.stage != nil {
			check_err(c, pt.pos, "shader entry points cannot be polymorphic")
		}
	}
	
	if type.stage != nil {
		seen_sem: Semantics
		sem_infos := semantic_names
		for param in type.params.variables {
			if param.semantic == .None || param.semantic == .Custom do continue
			if param.semantic in seen_sem {
				check_err(c, param.pos, "duplicate semantic '%s' on procedure parameters", sem_infos[param.semantic].name)
			}
			seen_sem += {param.semantic}

			if param.semantic == .Data || param.semantic == .Indirect_Data {
				sem_name := sem_infos[param.semantic].name
				ptr_t, is_ptr := param.type.derived.(^Type_Pointer)
				if !is_ptr {
					check_err(c, param.pos, "'%s' parameter must be a pointer type '^T', got '%s'", sem_name, string_from_type(param.type))
					continue
				}
				_, is_struct := ptr_t.elem.derived.(^Type_Struct)
				if !is_struct {
					check_err(c, param.pos, "'%s' pointee must be a struct, got '%s'", sem_name, string_from_type(ptr_t.elem))
					continue
				}
				if param.semantic == .Data {
					type.data_t = ptr_t.elem
				}
			} else {
				check_compute_semantic_type(c, param)
			}
		}

		// Recurse into nested structs on stage params/results for semantic legality.
		if stage, ok := type.stage.?; ok {
			#partial switch stage {
			case .Vertex, .Fragment:
				for param in type.params.variables {
					if param.semantic == .None || param.semantic == .Custom {
						check_nested_semantics(c, param.type, Allowed_Semantics_Struct_Fields)
					}
				}
				if type.results != nil {
					for result in type.results.variables {
						check_nested_semantics(c, result.type, Allowed_Semantics_Shader_Results + Allowed_Semantics_Struct_Fields)
					}
				}
			}
		}
	}

	if type.is_fmag {
		if type.params != nil {
			for param in type.params.variables {
				if param == nil || param.type == nil do continue
				if !fmag_value_type_ok(param.type) {
					check_err(c, param.pos, "proc \"fmag\" parameters must be f32 or [2/3/4]f32, got '%s'", string_from_type(param.type))
				}
				if .Ref in param.flags {
					check_err(c, param.pos, "'#ref' is not allowed in proc \"fmag\"")
				}
			}
		}
		if type.results != nil {
			for result in type.results.variables {
				if result == nil || result.type == nil do continue
				if !fmag_value_type_ok(result.type) {
					check_err(c, result.pos, "proc \"fmag\" results must be f32 or [2/3/4]f32, got '%s'", string_from_type(result.type))
				}
			}
		}
	}
	return type
}

fmag_value_type_ok :: proc(type: ^Type) -> bool {
	if type == nil do return false
	if type_eq(type, t_f32) do return true
	if v, ok := type.derived.(^Type_Vector); ok {
		return type_eq(v.elem, t_f32) && v.len >= 2 && v.len <= 4
	}
	return false
}

check_nested_semantics :: proc(c: ^Checker, type: ^Type, allowed: Semantics) {
	if type == nil do return
	st, ok := type.derived.(^Type_Struct)
	if !ok do return
	sem_infos := semantic_names
	for f in st.fields.variables {
		if f.semantic != .None && f.semantic != .Custom && f.semantic not_in allowed {
			check_err(c, f.pos, "semantic '%s' not allowed in this context", sem_infos[f.semantic].name)
		}
		check_nested_semantics(c, f.type, allowed)
	}
}

check_compute_semantic_type :: proc(c: ^Checker, param: ^Entity) {
	sem_infos := semantic_names
	#partial switch param.semantic {
	case .Global_Thread, .Group_Thread, .Group, .Num_Groups, .Group_Size:
		vec, is_vec := param.type.derived.(^Type_Vector)
		if !is_vec || vec.len != 3 || !type_eq(vec.elem, t_u32) {
			check_err(c, param.pos, "'%s' parameter must be '[3]u32', got '%s'", sem_infos[param.semantic].name, string_from_type(param.type))
		}
	case .Group_Index:
		if !type_eq(param.type, t_u32) {
			check_err(c, param.pos, "'%s' parameter must be 'u32', got '%s'", sem_infos[param.semantic].name, string_from_type(param.type))
		}
	}
}

check_field_list :: proc(c: ^Checker, scope: ^Scope, list: ^Field_List, allowed_semantics: Semantics, is_params := false, poly_operands: []Operand = nil, allow_using := false) -> ^Type_Tuple {
	tuple := new_type(Type_Tuple)
	if list == nil {
		return tuple
	}
	param_i := 0
	for field in list.list {
		if field.default_value != nil {
			check_err(c, field.pos, "default parameter values are not supported")
			field.default_value = nil
		}
		if field.type == nil {
			check_err(c, field.pos, "missing type in field list")
			continue
		}
		field_type := check_type(c, field.type) // TODO: the allowed semantic names should recurse when checking

		// Unnamed field (e.g. `-> f32`) — still allocate a result/param entity
		if len(field.names) == 0 {
			if type_is_string_kind(field_type) {
				check_err(c, field.pos, "string is compile-time only")
			}
			var := new_entity(.Variable, scope, field.pos, "", field_type)
			var.type = field_type
			if is_params {
				var.flags += {.Param, .Immutable}
			}
			if field.semantics != nil {
				for info, i in semantic_names {
					if field.semantics.name == info.name {
						if i in allowed_semantics {
							var.semantic = i
						} else {
							check_err(c, field.semantics.pos, "semantic name not allowed in this context")
						}
					}
				}
			}
			append(&tuple.variables, var)
			param_i += 1
			continue
		}

		for name in field.names {
			ident: ^Ident
			is_poly := false
			if poly, is_poly_type := name.derived.(^Poly_Type); is_poly_type {
				is_poly = true
				if poly.specialization != nil {
					check_err(c, name.pos, "polymorphic type specialization is not supported")
				}
				ident = poly.type
			} else {
				ident, _ = name.derived.(^Ident)
			}
			if ident == nil {
				check_err(c, field.pos, "field name must be an identifier")
				param_i += 1
				continue
			}
			if ident.entity != nil {
				// Soft-fail rechecks / recovered ASTs can revisit bound idents.
				check_err(c, ident.pos, "internal: field '%s' already has an entity", ident.name)
				ident.entity = nil
			}
			existing := scope_lookup_current(scope, ident.name)
			if existing != nil {
				check_err(c, ident.pos, "redeclaration of '%s' in this scope")
				param_i += 1
				continue
			}
			if is_poly {
				if !is_params {
					check_err(c, ident.pos, "constant parapoly '$%s' is only allowed on procedure parameters", ident.name)
				} else if !type_is_poly_const_ok(field_type) {
					check_err(c, ident.pos, "constant parapoly '$%s' requires a constant scalar, string, or procedure type, got '%s'", ident.name, string_from_type(field_type))
				}
				if .Ref in field.flags {
					check_err(c, ident.pos, "'#ref' is not allowed on constant parapoly parameters")
				}
			} else if type_is_string_kind(field_type) {
				check_err(c, ident.pos, "string is compile-time only; use '$%s: string' for a constant parameter", ident.name)
			} else if type_is_ray_query(field_type) && !is_params {
				check_err(c, ident.pos, "Ray_Query cannot be stored in a struct")
			}
			kind: Entity_Kind = .Constant if is_poly else .Variable
			var := new_entity(kind, scope, ident.pos, ident.name, field_type)
			ident.entity = var
			var.ident = ident
			var.type = field_type
			if is_params {
				var.flags += {.Param, .Immutable}
			}
			if is_poly {
				var.flags += {.Poly_Const}
				if param_i < len(poly_operands) {
					op := poly_operands[param_i]
					if type_is_proc(field_type) {
						callee := strip_entity_wrapping(entity_from_expr(op.expr))
						if callee != nil {
							var.aliased_of = callee
							var.value = callee
						}
					} else if op.mode == .Constant {
						convert_to_typed(c, &op, field_type)
						var.value = op.value
					}
				}
			}
			if .Flat in field.flags do var.flags += {.Flat}
			if .Noperspective in field.flags do var.flags += {.Noperspective}
			if .Centroid in field.flags do var.flags += {.Centroid}
			if .Ref in field.flags {
				if !is_params {
					check_err(c, ident.pos, "'#ref' is only allowed on procedure parameters")
				} else if is_poly {
					// already diagnosed
				} else if type_is_pointer(field_type) || type_is_multi_pointer(field_type) || type_is_slice(field_type) {
					check_err(c, ident.pos, "'#ref' is not allowed on device pointer/slice types; write through the pointee instead")
				} else {
					var.flags -= {.Immutable}
					var.flags += {.Ref}
				}
			}
			apply_using_flags_to_field(c, field, var, allow_using)
			scope_insert(scope, var)
			if field.semantics != nil {
				if len(field.names) > 1 {
					check_err(c, field.semantics.pos, "semantic names are not allowed on multi-name fields")
				} else {
					for info, i in semantic_names {
						if field.semantics.name == info.name {
							if i in allowed_semantics {
								var.semantic = i
							} else {
								check_err(c, field.semantics.pos, "semantic name not allowed in this context")
							}
						}
					}
				}
			}
			append(&tuple.variables, var)
			param_i += 1
		}
	}

	return tuple
}

Type_And_Value :: struct {
	type: ^Type,
	value: Exact_Value,
	mode: Addressing_Mode,
}

check_struct_type :: proc(c: ^Checker, st: ^Struct_Type) -> ^Type_Struct {
	st.scope = create_scope(c.curr_scope)
	type := new_type(Type_Struct)
	type.fields = check_field_list(c, st.scope, st.fields, Allowed_Semantics_Struct_Fields, allow_using = true)
	if type.fields == nil {
		type.fields = new_type(Type_Tuple)
	}
	type.scope = st.scope
	inject_struct_using_fields(c, type)
	requested_align := 0
	align_check: if st.align != nil {
		align := check_expr(c, st.align)
		if align.mode != .Constant {
			check_err(c, align.expr.pos, "struct alignment must be a constant expression")
			break align_check
		}
		if !type_is_integer(align.type) {
			check_err(c, align.expr.pos, "struct alignment expects integer, got '%s'", string_from_type(align.type))
			break align_check
		}

		align_i, is_int := align.value.(i128)
		if !is_int {
			check_err(c, align.expr.pos, "struct alignment must be an integer constant")
			break align_check
		}
		if align_i <= 0 {
			check_err(c, align.expr.pos, "struct alignment must be a positive power of 2, got '%v'", align_i)
			break align_check
		}
		align_value := cast(u64)align_i
		// check if it's a power of 2 (!NOT it for displaying error)
		if !(align_value != 0 && (align_value & (align_value - 1)) == 0) {
			check_err(c, align.expr.pos, "struct alignment must be a power of 2, got '%v'", align_value)
		}

		requested_align = auto_cast align_value
	}

	max_align := 0
	for field in type.fields.variables {
		if field == nil || field.type == nil do continue
		field_align := type_alignof(field.type)
		if field_align > max_align {
			max_align = field_align
		}
	}

	type.align = requested_align if requested_align != 0 else max_align
	
	{ // calculate field paddings and final struct size
		offset := 0
		for field in type.fields.variables {
			if field == nil || field.type == nil do continue
			field_align := type_alignof(field.type)
			field_size := type_sizeof(field.type)
			if field_align <= 0 {
				field.field_offset = offset
				offset += field_size
				continue
			}
			padding := (field_align - (offset % field_align)) % field_align
			offset += padding
			field.field_offset = offset
			offset += field_size
		}

		// Empty / incomplete structs (soft-fail while typing `S :: struct`) can have
		// align 0 — never modulo by zero.
		if type.align <= 0 {
			type.align = 1 if offset > 0 else 0
			type.size = offset
		} else {
			final_padding := (type.align - (offset % type.align)) % type.align
			type.size = offset + final_padding
		}
	}

	type.scope = st.scope
	return type
}

check_enum_type :: proc(c: ^Checker, et: ^Enum_Type) -> ^Type {
	et.scope = create_scope(nil)
	type := new_type(Type_Enum)
	type.scope = et.scope
	if et.base_type == nil {
		check_err(c, et.pos, "missing enum backing type. misl mandates this to be explicit")
		return t_invalid
	}
	base_type := check_type(c, et.base_type)
	if !type_is_integer(base_type) {
		check_err(c, et.base_type.pos, "expected an integer backing type, got '%s'", string_from_type(base_type))
		return t_invalid
	}
	type.base_type = base_type

	current_value: u64
	for field in et.fields {
		#partial switch f in field.derived {
		case:
			check_err(c, field.pos, "unexpected field in enum type")
			continue
		case ^Ident:
			f.entity = scope_lookup_current(et.scope, f.name)
			if f.entity != nil {
				check_err(c, f.pos, "redeclaration of '%s' within this scope", f.name)
				return t_invalid
			}
			const := new_entity(.Constant, et.scope, f.pos, f.name, type)
			const.value = cast(i128)current_value
			current_value += 1
			f.entity = const
			scope_insert(et.scope, f.entity)
			append(&type.fields, const)

		case ^Field_Value:
			ident, is_ident := f.field.derived.(^Ident)
			if !is_ident {
				check_err(c, f.pos, "expected an identifier, got %v", reflect.union_variant_typeid(f.field))
				return t_invalid
			}
			ident.entity = scope_lookup(et.scope, ident.name)
			if ident.entity != nil {
				check_err(c, ident.pos, "redeclaration of '%s' within this scope", ident.name)
				return t_invalid
			}
			const := new_entity(.Constant, et.scope, ident.pos, ident.name, type)
			val := check_expr(c, f.value, type_hint = type.base_type)
			if val.mode != .Constant {
				check_err(c, val.expr.pos, "expected a constant, got %s", val.mode)
				return t_invalid
			}

			if !type_is_integer(val.expr.tav.type) {
				check_err(c, val.expr.pos, "expected an integer expression got '%s'", string_from_type(val.expr.tav.type))
				return t_invalid
			}
			current_value = auto_cast val.expr.tav.value.(i128)
			const.value = cast(i128)current_value
			current_value += 1
			ident.entity = const
			scope_insert(et.scope, ident.entity)
			append(&type.fields, const)
			
		}
	}

	return type
}

check_basic_lit :: proc(c: ^Checker, lit: ^Basic_Lit) -> Exact_Value {
	if lit.tav.value != nil do return lit.tav.value
	#partial switch lit.tok.kind {
	case .String:
		lit.tav.value = exact_string(unescape_misl_string(lit.tok.text))
		lit.tav.type = t_untyped_string
	case .Rune:
		r, rok := parse_rune_literal(lit.tok.text)
		if !rok {
			check_err(c, lit.pos, "invalid rune literal '%s'", lit.tok.text)
			lit.tav.type = t_invalid
			return nil
		}
		lit.tav.value = exact_int(i128(r))
		lit.tav.type = t_untyped_rune
	case .Float:
		f, ok := parse_misl_float_literal(lit.tok.text)
		if !ok {
			check_err(c, lit.pos, "invalid float literal '%s'", lit.tok.text)
			lit.tav.type = t_invalid
			return nil
		}
		lit.tav.value = exact_float(f)
		lit.tav.type = t_untyped_float
	case .Integer:
		i, ok := strconv.parse_int(lit.tok.text)
		if !ok {
			check_err(c, lit.pos, "invalid integer literal '%s'", lit.tok.text)
			lit.tav.type = t_invalid
			return nil
		}
		lit.tav.value = exact_int(i)
		lit.tav.type = t_untyped_int
	}
	return lit.tav.value
}

check_matrix_type :: proc(c: ^Checker, mt: ^Matrix_Type) -> ^Type {
	elem_type := check_type(c, mt.elem)
	// GLSL only has float/double matrices (mat* / dmat*).
	// Elem comes from check_type, so it is never an untyped literal type.
	if !type_is_float(elem_type) {
		check_err(c, mt.elem.pos, "matrix element type must be f32 or f64, got '%s'", string_from_type(elem_type))
		return t_invalid
	}
	rows := check_expr(c, mt.row_count)

	cols := check_expr(c, mt.column_count)
	type := new_type(Type_Matrix)
	type.elem = elem_type
	type.rows = auto_cast rows.value.(i128)
	type.columns = auto_cast cols.value.(i128)
	mt.tav.type = type
	return type
}

check_multi_pointer_type :: proc(c: ^Checker, mt: ^Multi_Pointer_Type) -> ^Type {
	type := new_type(Type_Multi_Pointer)
	type.elem = check_type(c, mt.elem)
	mt.tav.type = type
	return type
}

check_pointer_type :: proc(c: ^Checker, pt: ^Pointer_Type) -> ^Type {
	if _, is_nested := pt.elem.derived.(^Pointer_Type); is_nested {
		check_err(c, pt.pos, "nested pointers '^^T' are not supported")
		return t_invalid
	}
	if _, is_nested := pt.elem.derived.(^Multi_Pointer_Type); is_nested {
		check_err(c, pt.pos, "nested pointers '^[^]T' are not supported")
		return t_invalid
	}
	type := new_type(Type_Pointer)
	type.elem = check_type(c, pt.elem)
	if _, is_ptr := type.elem.derived.(^Type_Pointer); is_ptr {
		check_err(c, pt.pos, "nested pointers '^^T' are not supported")
		return t_invalid
	}
	if _, is_mp := type.elem.derived.(^Type_Multi_Pointer); is_mp {
		check_err(c, pt.pos, "nested pointers '^[^]T' are not supported")
		return t_invalid
	}
	pt.tav.type = type
	return type
}

// Array compound literals: `{}` (zero), or exactly `count` elements.
check_sequence_comp_lit :: proc(c: ^Checker, lit: ^Comp_Lit, count: int, elem_type: ^Type, operand: ^Operand) {
	operand.mode = .Value
	if len(lit.elems) == 0 {
		operand.mode = .Constant
		operand.value = lit
		return // {}
	}
	if len(lit.elems) != count {
		check_err(c, lit.pos, "compound literal of type '%s' expects 0 or %d elements, got %d",
			string_from_type(operand.type), count, len(lit.elems))
	}
	all_const := true
	for elem in lit.elems {
		value := elem
		if fv, is_fv := elem.derived.(^Field_Value); is_fv {
			value = fv.value
		}
		e := check_expr(c, value, type_hint = elem_type)
		if e.mode != .Constant {
			all_const = false
		}
	}
	if all_const {
		operand.mode = .Constant
		operand.value = lit
	}
}

// Vector compound literals: `{}` or all N scalar components.
// Unlike `vecN(...)` constructors, elements cannot be vectors (no splicing).
check_vector_comp_lit :: proc(c: ^Checker, lit: ^Comp_Lit, vec: ^Type_Vector, operand: ^Operand) {
	operand.mode = .Value
	n := int(vec.len)
	if len(lit.elems) == 0 {
		return // {}
	}
	if len(lit.elems) != n {
		check_err(c, lit.pos, "vector compound literal of type '%s' expects 0 or %d scalar elements, got %d",
			string_from_type(operand.type), n, len(lit.elems))
	}
	all_const := true
	for elem in lit.elems {
		value := elem
		if _, is_fv := elem.derived.(^Field_Value); is_fv {
			check_err(c, elem.pos, "vector compound literals do not support named fields")
			continue
		}
		e := check_expr(c, value, type_hint = vec.elem)
		if e.mode == .Invalid do continue
		// Constructors may splice vectors; compound literals may not.
		if type_is_vector(e.type) || type_is_matrix(e.type) {
			check_err(c, value.pos, "vector compound literal elements must be scalars of type '%s', got '%s' (use a vector constructor to splice vectors)",
				string_from_type(vec.elem), string_from_type(e.type))
			continue
		}
		if e.mode != .Constant {
			all_const = false
		}
	}
	if all_const {
		operand.mode = .Constant
	}
}

// Matrix compound literals: `{}` or all R*C scalar components (column-major, same as matN(...)).
// Unlike constructors, elements cannot be vectors/matrices (no splicing / no named fields).
check_matrix_comp_lit :: proc(c: ^Checker, lit: ^Comp_Lit, mat: ^Type_Matrix, operand: ^Operand) {
	operand.mode = .Value
	n := int(mat.rows * mat.columns)
	if len(lit.elems) == 0 {
		return // {}
	}
	if len(lit.elems) != n {
		check_err(c, lit.pos, "matrix compound literal of type '%s' expects 0 or %d scalar elements, got %d",
			string_from_type(operand.type), n, len(lit.elems))
	}
	all_const := true
	for elem in lit.elems {
		value := elem
		if _, is_fv := elem.derived.(^Field_Value); is_fv {
			check_err(c, elem.pos, "matrix compound literals do not support named fields")
			continue
		}
		e := check_expr(c, value, type_hint = mat.elem)
		if e.mode == .Invalid do continue
		if type_is_vector(e.type) || type_is_matrix(e.type) {
			check_err(c, value.pos, "matrix compound literal elements must be scalars of type '%s', got '%s' (use a matrix constructor to splice columns)",
				string_from_type(mat.elem), string_from_type(e.type))
			continue
		}
		if e.mode != .Constant {
			all_const = false
		}
	}
	if all_const {
		operand.mode = .Constant
	}
}

check_struct_comp_lit :: proc(c: ^Checker, lit: ^Comp_Lit, st: ^Type_Struct, operand: ^Operand) {
	operand.type = st
	operand.mode = .Constant
	fields := st.fields.variables
	if len(lit.elems) == 0 {
		return
	}

	named := false
	positional := false
	seen := make([]bool, len(fields), context.temp_allocator)

	for elem, i in lit.elems {
		if fv, is_fv := elem.derived.(^Field_Value); is_fv {
			named = true
			if positional {
				check_err(c, elem.pos, "cannot mix named and positional fields in compound literal")
				return
			}
			fname, ok := fv.field.derived.(^Ident)
			if !ok {
				check_err(c, fv.field.pos, "expected field name")
				continue
			}
			field_index := -1
			field_type: ^Type
			for f, fi in fields {
				if f.name == fname.name {
					field_index = fi
					field_type = f.type
					break
				}
			}
			if field_index < 0 {
				check_err(c, fname.pos, "type '%s' has no field '%s'", string_from_type(st), fname.name)
				continue
			}
			seen[field_index] = true
			val := check_expr(c, fv.value, type_hint = field_type)
			if val.mode != .Constant {
				operand.mode = .Value
			}
		} else {
			positional = true
			if named {
				check_err(c, elem.pos, "cannot mix named and positional fields in compound literal")
				return
			}
			if i >= len(fields) {
				check_err(c, elem.pos, "too many elements for '%s'", string_from_type(st))
				return
			}
			seen[i] = true
			val := check_expr(c, elem, type_hint = fields[i].type)
			if val.mode != .Constant {
				operand.mode = .Value
			}
		}
	}

	// Color_Attachment_Desc.format is required in pipeline targets
	if st == c.gpu.Color_Attachment_Desc {
		for f, i in fields {
			if f.name == "format" && !seen[i] {
				check_err(c, lit.pos, "Color_Attachment_Desc requires 'format'")
			}
		}
	}
}

pipeline_interp_flags :: Entity_Flags{.Flat, .Noperspective, .Centroid}

pipeline_require_const_i128 :: proc(c: ^Checker, o: Operand, what: string) -> (i128, bool) {
	if o.mode != .Constant || o.value == nil {
		check_err(c, o.expr.pos, "pipeline.%s must be a constant expression", what)
		return 0, false
	}
	v, ok := o.value.(i128)
	if !ok {
		check_err(c, o.expr.pos, "pipeline.%s must be a constant integer/enum value", what)
		return 0, false
	}
	return v, true
}

pipeline_register_anon_stage :: proc(c: ^Checker, expr: ^Expr, o: Operand, stage: Stage) -> ^Entity {
	e := entity_from_expr(expr)
	if e != nil {
		ensure_entity_resolved(c, e)
		return e
	}
	lit_expr := unparen_expr(expr)
	lit, is_lit := lit_expr.derived.(^Proc_Lit)
	if !is_lit || o.type == nil {
		return nil
	}
	@static anon_id: int
	anon_id += 1
	stage_tag := "cs"
	switch stage {
	case .Vertex: stage_tag = "vs"
	case .Fragment: stage_tag = "fs"
	case .Compute: stage_tag = "cs"
	}
	name := fmt.tprintf("_pipeline_%s_%d", stage_tag, anon_id)
	e = new_entity(.Entry, c.curr_scope, expr.pos, name, o.type)
	e.module = c.module
	e.state = .Resolved
	e.proc_lit = lit
	append(&c.module.definitions, e)
	bind_entry_entity(c.module, e)
	return e
}

pipeline_field_const_i128 :: proc(c: ^Checker, expr: ^Expr, what: string) -> (i128, bool) {
	if expr == nil {
		check_err(c, {}, "%s must be a constant expression", what)
		return 0, false
	}
	if expr.tav.mode != .Constant || expr.tav.value == nil {
		check_err(c, expr.pos, "%s must be a constant expression", what)
		return 0, false
	}
	v, ok := expr.tav.value.(i128)
	if !ok {
		check_err(c, expr.pos, "%s must be a constant integer/enum value", what)
		return 0, false
	}
	return v, true
}

pipeline_extract_blend_mode :: proc(c: ^Checker, expr: ^Expr) -> (mode: Checked_Blend_Mode, ok: bool) {
	expr := unparen_expr(expr)
	lit, is_lit := expr.derived.(^Comp_Lit)
	if !is_lit {
		check_err(c, expr.pos, "Blend_Mode must be a compound literal")
		return {}, false
	}
	ok = true
	named := false
	for elem, i in lit.elems {
		if fv, is_fv := elem.derived.(^Field_Value); is_fv {
			named = true
			fname, is_ident := fv.field.derived.(^Ident)
			if !is_ident {
				ok = false
				continue
			}
			v, vok := pipeline_field_const_i128(c, fv.value, "Blend_Mode field")
			if !vok {
				ok = false
				continue
			}
			switch fname.name {
			case "src": mode.src = v
			case "dst": mode.dst = v
			case "op":  mode.op = v
			case:
				check_err(c, fname.pos, "unknown Blend_Mode field '%s'", fname.name)
				ok = false
			}
		} else {
			if named {
				check_err(c, elem.pos, "cannot mix named and positional fields in Blend_Mode")
				ok = false
				continue
			}
			v, vok := pipeline_field_const_i128(c, elem, "Blend_Mode element")
			if !vok {
				ok = false
				continue
			}
			switch i {
			case 0: mode.src = v
			case 1: mode.dst = v
			case 2: mode.op = v
			case:
				check_err(c, elem.pos, "too many elements for Blend_Mode")
				ok = false
			}
		}
	}
	return mode, ok
}

pipeline_extract_blend_state :: proc(c: ^Checker, expr: ^Expr) -> (state: Checked_Blend_State, ok: bool) {
	expr := unparen_expr(expr)
	lit, is_lit := expr.derived.(^Comp_Lit)
	if !is_lit {
		check_err(c, expr.pos, "Blend_State must be a compound literal")
		return {}, false
	}
	ok = true
	has_color, has_alpha: bool
	for elem in lit.elems {
		fv, is_fv := elem.derived.(^Field_Value)
		if !is_fv {
			check_err(c, elem.pos, "Blend_State fields must be named (color = ..., alpha = ...)")
			ok = false
			continue
		}
		fname, is_ident := fv.field.derived.(^Ident)
		if !is_ident {
			ok = false
			continue
		}
		mode, mok := pipeline_extract_blend_mode(c, fv.value)
		if !mok {
			ok = false
			continue
		}
		switch fname.name {
		case "color":
			has_color = true
			state.color = mode
		case "alpha":
			has_alpha = true
			state.alpha = mode
		case:
			check_err(c, fname.pos, "unknown Blend_State field '%s'", fname.name)
			ok = false
		}
	}
	if !has_color || !has_alpha {
		check_err(c, expr.pos, "Blend_State requires both 'color' and 'alpha'")
		ok = false
	}
	return state, ok
}

pipeline_extract_target :: proc(c: ^Checker, elem: ^Expr) -> (target: Checked_Pipeline_Target, ok: bool) {
	elem := unparen_expr(elem)
	lit, is_lit := elem.derived.(^Comp_Lit)
	if !is_lit {
		check_err(c, elem.pos, "pipeline target must be a Color_Attachment_Desc compound literal")
		return {}, false
	}
	ok = true
	has_format := false
	for e in lit.elems {
		fv, is_fv := e.derived.(^Field_Value)
		if !is_fv {
			if !has_format {
				if v, vok := pipeline_field_const_i128(c, e, "pipeline target format"); vok {
					target.format = v
					has_format = true
					continue
				}
			}
			ok = false
			continue
		}
		fname, is_ident := fv.field.derived.(^Ident)
		if !is_ident {
			ok = false
			continue
		}
		switch fname.name {
		case "format":
			v, vok := pipeline_field_const_i128(c, fv.value, "pipeline target format")
			if !vok {
				ok = false
				continue
			}
			target.format = v
			has_format = true
		case "write_mask":
			v, vok := pipeline_field_const_i128(c, fv.value, "pipeline target write_mask")
			if !vok {
				ok = false
				continue
			}
			target.has_write_mask = true
			target.write_mask = v
		case "blend":
			blend, bok := pipeline_extract_blend_state(c, fv.value)
			if !bok {
				ok = false
				continue
			}
			target.has_blend = true
			target.blend = blend
		}
	}
	if !has_format {
		ok = false
	}
	return target, ok
}

check_pipeline_varying_fields :: proc(c: ^Checker, pos: Token_Pos, vs_st, fs_st: ^Type_Struct) {
	if vs_st == nil || fs_st == nil do return
	vs_fields: []^Entity
	fs_fields: []^Entity
	if vs_st.fields != nil do vs_fields = vs_st.fields.variables[:]
	if fs_st.fields != nil do fs_fields = fs_st.fields.variables[:]
	for fs_f in fs_fields {
		vs_f: ^Entity
		for v in vs_fields {
			if v.name == fs_f.name {
				vs_f = v
				break
			}
		}
		if vs_f == nil {
			check_err(c, pos, "pipeline VS/FS interface mismatch: fragment field '%s' missing on vertex result", fs_f.name)
			continue
		}
		if vs_f.type != fs_f.type && !type_eq(vs_f.type, fs_f.type) {
			check_err(c, pos, "pipeline VS/FS interface mismatch: field '%s' type differs (vertex '%s' vs fragment '%s')",
				fs_f.name, string_from_type(vs_f.type), string_from_type(fs_f.type))
		}
		if (vs_f.flags & pipeline_interp_flags) != (fs_f.flags & pipeline_interp_flags) {
			check_err(c, pos, "pipeline VS/FS interface mismatch: field '%s' interpolation differs (#flat/#noperspective/#centroid)", fs_f.name)
		}
	}
}

check_pipeline_vs_fs_interface :: proc(c: ^Checker, pos: Token_Pos, vertex_e, fragment_e: ^Entity) {
	if vertex_e == nil || fragment_e == nil || vertex_e.type == nil || fragment_e.type == nil do return
	vs_t, vs_ok := vertex_e.type.derived.(^Type_Proc)
	fs_t, fs_ok := fragment_e.type.derived.(^Type_Proc)
	if !vs_ok || !fs_ok do return

	vs_out: ^Type
	if vs_t.results != nil && len(vs_t.results.variables) > 0 {
		vs_out = vs_t.results.variables[0].type
	}
	vs_st: ^Type_Struct
	if vs_out != nil {
		vs_st, _ = vs_out.derived.(^Type_Struct)
	}

	if fs_t.params == nil do return
	for param in fs_t.params.variables {
		if param.semantic != .None && param.semantic != .Custom do continue
		fs_st, is_struct := param.type.derived.(^Type_Struct)
		if !is_struct do continue

		if vs_st == nil {
			check_err(c, pos, "pipeline VS/FS interface mismatch: fragment input struct does not match vertex result")
			continue
		}
		if param.type != vs_out {
			check_err(c, pos, "pipeline VS/FS interface mismatch: fragment input struct does not match vertex result")
		}
		check_pipeline_varying_fields(c, pos, vs_st, fs_st)
	}
}

count_fragment_sv_targets :: proc(fragment_e: ^Entity) -> int {
	if fragment_e == nil || fragment_e.type == nil do return 0
	fs_t, ok := fragment_e.type.derived.(^Type_Proc)
	if !ok || fs_t.results == nil do return 0
	n := 0
	for res in fs_t.results.variables {
		if res.semantic == .Target {
			n += 1
		} else if st, is_st := res.type.derived.(^Type_Struct); is_st && st.fields != nil {
			for field in st.fields.variables {
				if field.semantic == .Target {
					n += 1
				}
			}
		}
	}
	return n
}

check_pipeline_lit :: proc(c: ^Checker, lit: ^Comp_Lit, operand: ^Operand) {
	operand.type = t_pipeline
	operand.mode = .Constant

	cp := new(Checked_Pipeline)
	cp.targets = make([dynamic]Checked_Pipeline_Target)

	seen_fields := make(map[string]bool, context.temp_allocator)

	for elem in lit.elems {
		fv, ok := elem.derived.(^Field_Value)
		if !ok {
			check_err(c, elem.pos, "pipeline fields must be named (field = value)")
			continue
		}
		field_ident, is_ident := fv.field.derived.(^Ident)
		if !is_ident {
			check_err(c, fv.field.pos, "pipeline field name must be an identifier")
			continue
		}
		if field_ident.name in seen_fields {
			check_err(c, field_ident.pos, "duplicate pipeline field '%s'", field_ident.name)
			continue
		}
		seen_fields[field_ident.name] = true

		switch field_ident.name {
		case "vertex":
			o := check_expr_internal(c, fv.value, nil)
			if o.mode != .Shader || o.type == nil {
				check_err(c, fv.value.pos, "pipeline.vertex must be a vertex entry")
				continue
			}
			proc_t, is_proc := o.type.derived.(^Type_Proc)
			if !is_proc || proc_t.stage != .Vertex {
				check_err(c, fv.value.pos, "pipeline.vertex must be a vertex entry")
				continue
			}
			cp.vertex = pipeline_register_anon_stage(c, fv.value, o, .Vertex)

		case "fragment":
			o := check_expr_internal(c, fv.value, nil)
			if o.mode != .Shader || o.type == nil {
				check_err(c, fv.value.pos, "pipeline.fragment must be a fragment entry")
				continue
			}
			proc_t, is_proc := o.type.derived.(^Type_Proc)
			if !is_proc || proc_t.stage != .Fragment {
				check_err(c, fv.value.pos, "pipeline.fragment must be a fragment entry")
				continue
			}
			cp.fragment = pipeline_register_anon_stage(c, fv.value, o, .Fragment)

		case "targets":
			cp.has_targets = true
			targets_lit, is_lit := fv.value.derived.(^Comp_Lit)
			if !is_lit {
				check_err(c, fv.value.pos, "pipeline.targets must be a compound literal list of Color_Attachment_Desc")
				continue
			}
			if len(targets_lit.elems) == 0 {
				check_err(c, fv.value.pos, "pipeline.targets must be non-empty when present")
			}
			for t_elem in targets_lit.elems {
				_ = check_expr(c, t_elem, type_hint = c.gpu.Color_Attachment_Desc)
				target, tok := pipeline_extract_target(c, t_elem)
				if tok {
					append(&cp.targets, target)
				}
			}

		case "topology":
			o := check_expr(c, fv.value, type_hint = c.gpu.Topology)
			if v, vok := pipeline_require_const_i128(c, o, "topology"); vok {
				cp.has_topology = true
				cp.topology = v
			}
		case "cull":
			o := check_expr(c, fv.value, type_hint = c.gpu.Cull_Modes)
			if v, vok := pipeline_require_const_i128(c, o, "cull"); vok {
				cp.has_cull = true
				cp.cull = v
			}
		case "sample_count":
			o := check_expr(c, fv.value, type_hint = c.gpu.Sample_Count)
			if v, vok := pipeline_require_const_i128(c, o, "sample_count"); vok {
				cp.has_sample_count = true
				cp.sample_count = v
			}
		case "depth_format":
			o := check_expr(c, fv.value, type_hint = c.gpu.Format)
			if v, vok := pipeline_require_const_i128(c, o, "depth_format"); vok {
				cp.has_depth_format = true
				cp.depth_format = v
			}
		case "stencil_format":
			o := check_expr(c, fv.value, type_hint = c.gpu.Format)
			if v, vok := pipeline_require_const_i128(c, o, "stencil_format"); vok {
				cp.has_stencil_format = true
				cp.stencil_format = v
			}
		case "flags":
			o := check_expr(c, fv.value, type_hint = c.gpu.Raster_Flags)
			if v, vok := pipeline_require_const_i128(c, o, "flags"); vok {
				cp.has_flags = true
				cp.flags = v
			}
		case "view_count":
			o := check_expr(c, fv.value, type_hint = t_i32)
			if v, vok := pipeline_require_const_i128(c, o, "view_count"); vok {
				cp.has_view_count = true
				cp.view_count = i32(v)
			}
		case:
			check_err(c, field_ident.pos, "unknown pipeline field '%s'", field_ident.name)
		}
	}

	if cp.vertex != nil && cp.fragment != nil {
		check_pipeline_vs_fs_interface(c, lit.pos, cp.vertex, cp.fragment)
	}

	if cp.has_targets && cp.fragment != nil {
		sv_target_count := count_fragment_sv_targets(cp.fragment)
		if len(cp.targets) != sv_target_count {
			check_err(c, lit.pos, "pipeline.targets length (%d) must match fragment SV_Target count (%d)", len(cp.targets), sv_target_count)
		}
	}

	operand.checked_pipeline = cp
}

check_bit_set_type :: proc(c: ^Checker, bst: ^Bit_Set_Type) -> ^Type {
	if bst.underlying == nil {
		check_err(c, bst.pos, "bit_set requires an explicit underlying type: bit_set[E; Underlying]")
		return t_invalid
	}
	elem := check_type(c, bst.elem)
	if elem == nil || elem == t_invalid {
		return t_invalid
	}
	if _, is_enum := elem.derived.(^Type_Enum); !is_enum {
		check_err(c, bst.elem.pos, "bit_set element type must be an enum, got '%s'", string_from_type(elem))
		return t_invalid
	}
	underlying := check_type(c, bst.underlying)
	if !type_is_integer(underlying) {
		check_err(c, bst.underlying.pos, "bit_set underlying type must be an integer, got '%s'", string_from_type(underlying))
		return t_invalid
	}
	type := new_type(Type_Bit_Set)
	type.elem = elem
	type.underlying = underlying
	enum_t := elem.derived.(^Type_Enum)
	type.lower = 0
	type.upper = 0
	if len(enum_t.fields) > 0 {
		max_bit := 0
		for f in enum_t.fields {
			if v, ok := f.value.(i128); ok {
				if int(v) > max_bit {
					max_bit = int(v)
				}
			}
		}
		type.upper = max_bit
	}
	bst.tav.type = type
	return type
}

// TODO: should we assign at.tav.type here?
check_array_type :: proc(c: ^Checker, at: ^Array_Type) -> ^Type {
	if at.len == nil { // []T real slice (ptr + len), not BDA
		type := new_type(Type_Slice)
		type.elem = check_type(c, at.elem)
		if type_is_ray_query(type.elem) {
			check_err(c, at.pos, "Ray_Query cannot be stored in a slice or buffer")
		}
		at.tav.type = type
		return type
	} else {
		count := check_expr(c, at.len) // note: does this need a type hint?
		if count.mode != .Constant {
			check_err(c, at.len.pos, "array length must be constant")
			return t_invalid
		}

		if !type_is_integer(count.type) {
			check_err(c, at.len.pos, "expected a constant integer as array length, got type '%s'", string_from_type(count.type))
			return t_invalid
		}

		array_size := cast(u64)count.value.(i128)

		elem_type := check_type(c, at.elem) // TODO: we should probably check if the type is valid
		if type_is_ray_query(elem_type) {
			check_err(c, at.pos, "Ray_Query cannot be stored in an array")
		}
		
	
		if !at.force_array && 2 <= array_size && array_size <= 4 do switch elem_type {
		case t_f32, t_i32, t_u32, t_b32:
			type := new_type(Type_Vector)
			type.len = auto_cast array_size
			type.elem = elem_type
			at.tav.type = type
			return type
		}

		type := new_type(Type_Array)
		type.len = auto_cast array_size
		type.elem = elem_type
		type.force_array = at.force_array
		at.tav.type = type
		return type
	}
}

check_type_ident :: proc(c: ^Checker, ident: ^Ident) -> ^Type {
	if ident.entity == nil {
		ident.entity = scope_lookup(c.curr_scope, ident.name)
	}
	if ident.entity == nil {
		check_err(c, ident.pos, "unknown type: '%s'", ident.name)
		return t_invalid
	}
	ensure_entity_resolved(c, ident.entity)
	if ident.entity.kind != .Type_Name && ident.entity.kind != .Constant {
		// Type aliases are Type_Name; allow resolved type entities
		if ident.entity.type == nil {
			check_err(c, ident.pos, "unknown type: '%s'", ident.name)
			return t_invalid
		}
	}
	if ident.entity.type == nil {
		check_err(c, ident.pos, "unknown type: '%s'", ident.name)
		return t_invalid
	}
	if ident.entity.kind != .Type_Name {
		check_err(c, ident.pos, "'%s' is not a type", ident.name)
		return t_invalid
	}
	return ident.entity.type
}

check_type :: proc(c: ^Checker, type_expr: ^Expr) -> ^Type {
	// Note: not sure if this should be here or not. The main usage for this is type inferences in '::' ':='
	// in the end nil should be a valid return, and an invalid type should be returned when erroring
	if type_expr == nil {
		return nil
	}
	// TODO: check for struct{},  proc() type, typeid, index expr for arrays, some other shit
	#partial switch d in type_expr.derived {
	case ^Bad_Expr:
		// Incomplete / recovered parse (e.g. `bit_set[` before `]` while typing).
		return t_invalid
	case ^Matrix_Type: return check_matrix_type(c, d)
	case ^Ident      : return check_type_ident(c, d)
	case ^Selector_Expr:
		op := check_expr_or_type(c, type_expr)
		if op.mode == .Type && op.type != nil && op.type != t_invalid {
			return op.type
		}
		if op.mode != .Invalid {
			check_err(c, type_expr.pos, "invalid type expression")
		}
		return t_invalid
	case ^Array_Type : return check_array_type(c, d)
	case ^Multi_Pointer_Type: return check_multi_pointer_type(c, d)
	case ^Bit_Set_Type: return check_bit_set_type(c, d)
	case ^Pipeline_Type: return t_pipeline
	case ^Pointer_Type: return check_pointer_type(c, d)
	case ^Proc_Type  : return check_proc_type(c, d)
	case ^Helper_Type: return check_type(c, d.type)
	case ^Struct_Type: return check_struct_type(c, d)
	case ^Enum_Type: return check_enum_type(c, d)
	case ^Poly_Type:
		check_err(c, type_expr.pos, "type polymorphism '$T' is not supported")
		return t_invalid
	case:
		// Soft-fail for IDE: never trap the LSP on unexpected AST while typing.
		check_err(c, type_expr.pos, "invalid type expression")
		return t_invalid
	}
}

check_ident :: proc(c: ^Checker, ident: ^Ident) {
	if ident.entity == nil {
		ident.entity = scope_lookup(c.curr_scope, ident.name)
	}
	ensure_entity_resolved(c, ident.entity)
}