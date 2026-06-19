
// The following code has been used for inspiration/guide: https://github.com/xzores/Odin-glsl-lang/tree/main

package glslang

import "core:c"

when ODIN_OS == .Windows
{
    @(extra_linker_flags = "/NODEFAULTLIB:libcmt")
    foreign import glslang {
        "libs/GenericCodeGen.lib",
        "libs/glslang-default-resource-limits.lib",
        "libs/glslang.lib",
        "libs/MachineIndependent.lib",
        "libs/SPIRV-Tools-opt.lib",
        "libs/SPIRV-Tools.lib",
        "libs/SPIRV.lib",
    }
}
else when ODIN_OS == .Linux
{
    @(extra_linker_flags = "-lstdc++")
    foreign import glslang {
        "libs/libGenericCodeGen.a",
        "libs/libglslang-default-resource-limits.a",
        "libs/libglslang.a",
        "libs/libMachineIndependent.a",
        "libs/libSPIRV-Tools-opt.a",
        "libs/libSPIRV-Tools.a",
        "libs/libSPIRV.a",
    }
}
else do #panic("OS not supported.")

// Procs

@(default_calling_convention="c")
@(link_prefix = "glslang_")
foreign glslang
{
    shader_create                :: proc(input: Input) -> Shader ---
    shader_delete                :: proc(shader: Shader) ---
    shader_set_preamble          :: proc(shader: Shader, s: cstring) ---
    shader_shift_binding         :: proc(shader: Shader, res: Resource_type, base: c.uint) ---
    shader_shift_binding_for_set :: proc(shader: Shader, res: Resource_type, base: c.uint, set: c.uint) ---
    shader_set_options           :: proc(shader: Shader, options: c.int) ---
    shader_set_glsl_version      :: proc(shader: Shader, version: c.int) ---
    shader_preprocess            :: proc(shader: Shader, input: Input) -> c.int ---
    shader_parse                 :: proc(shader: Shader, input: Input) -> c.int ---
    shader_get_preprocessed_code :: proc(shader: Shader) -> cstring ---
    shader_get_info_log          :: proc(shader: Shader) -> cstring ---
    shader_get_info_debug_log    :: proc(shader: Shader) -> cstring ---

    program_create                      :: proc() -> Program ---
    program_delete                      :: proc(program: Program) ---
    program_add_shader                  :: proc(program: Program, shader: Shader) ---
    program_link                        :: proc(program: Program, messages: messages_t) -> c.int ---
    program_add_source_text             :: proc(program: Program, stage: Stage, text: cstring, len: c.size_t) ---
    program_set_source_file             :: proc(program: Program, stage: Stage, file: cstring) ---
    program_map_io                      :: proc(program: Program) -> c.int ---
    program_SPIRV_generate              :: proc(program: Program, stage: Stage) ---
    program_SPIRV_generate_with_options :: proc(program: Program, stage: Stage, spv_options: ^spv_options_t) ---
    program_SPIRV_get_size              :: proc(program: Program) -> c.size_t ---
    program_SPIRV_get                   :: proc(program: Program, out: ^c.uint) ---
    program_SPIRV_get_ptr               :: proc(program: Program) -> ^c.uint ---
    program_SPIRV_get_messages          :: proc(program: Program) -> cstring ---
    program_get_info_log                :: proc(program: Program) -> cstring ---
    program_get_info_debug_log          :: proc(program: Program) -> cstring ---

    // Returns a struct that can be use to create custom resource values.
    resource :: proc() -> Resource ---

    // These are the default resources for TBuiltInResources, used for both
    //  - parsing this string for the case where the user didn't supply one,
    //  - dumping out a template for user construction of a config file.
    default_resource :: proc() -> Resource ---

    // Returns the DefaultTBuiltInResource as a human-readable string.
    // NOTE: User is responsible for freeing this string.
    default_resource_string :: proc() -> cstring ---

    // Decodes the resource limits from |config| to |resources|.
    decode_resource_limits :: proc(resources : Resource, config : cstring) ---
}

// Structs

Shader :: distinct rawptr //^shader_t
Program :: distinct rawptr //^program_t
Input :: ^input_t
Resource :: ^resource_t

Resource_type :: resource_type_t
Stage :: stage_t

// TLimits counterpart
limits_t :: struct
{
    non_inductive_for_loops: bool,
    while_loops: bool,
    do_while_loops: bool,
    general_uniform_indexing: bool,
    general_attribute_matrix_vector_indexing: bool,
    general_varying_indexing: bool,
    general_sampler_indexing: bool,
    general_variable_indexing: bool,
    general_constant_matrix_vector_indexing: bool,
}

// TBuiltInResource counterpart
resource_t :: struct
{
    max_lights: c.int,
    max_clip_planes: c.int,
    max_texture_units: c.int,
    max_texture_coords: c.int,
    max_vertex_attribs: c.int,
    max_vertex_uniform_components: c.int,
    max_varying_floats: c.int,
    max_vertex_texture_image_units: c.int,
    max_combined_texture_image_units: c.int,
    max_texture_image_units: c.int,
    max_fragment_uniform_components: c.int,
    max_draw_buffers: c.int,
    max_vertex_uniform_vectors: c.int,
    max_varying_vectors: c.int,
    max_fragment_uniform_vectors: c.int,
    max_vertex_output_vectors: c.int,
    max_fragment_input_vectors: c.int,
    min_program_texel_offset: c.int,
    max_program_texel_offset: c.int,
    max_clip_distances: c.int,
    max_compute_work_group_count_x: c.int,
    max_compute_work_group_count_y: c.int,
    max_compute_work_group_count_z: c.int,
    max_compute_work_group_size_x: c.int,
    max_compute_work_group_size_y: c.int,
    max_compute_work_group_size_z: c.int,
    max_compute_uniform_components: c.int,
    max_compute_texture_image_units: c.int,
    max_compute_image_uniforms: c.int,
    max_compute_atomic_counters: c.int,
    max_compute_atomic_counter_buffers: c.int,
    max_varying_components: c.int,
    max_vertex_output_components: c.int,
    max_geometry_input_components: c.int,
    max_geometry_output_components: c.int,
    max_fragment_input_components: c.int,
    max_image_units: c.int,
    max_combined_image_units_and_fragment_outputs: c.int,
    max_combined_shader_output_resources: c.int,
    max_image_samples: c.int,
    max_vertex_image_uniforms: c.int,
    max_tess_control_image_uniforms: c.int,
    max_tess_evaluation_image_uniforms: c.int,
    max_geometry_image_uniforms: c.int,
    max_fragment_image_uniforms: c.int,
    max_combined_image_uniforms: c.int,
    max_geometry_texture_image_units: c.int,
    max_geometry_output_vertices: c.int,
    max_geometry_total_output_components: c.int,
    max_geometry_uniform_components: c.int,
    max_geometry_varying_components: c.int,
    max_tess_control_input_components: c.int,
    max_tess_control_output_components: c.int,
    max_tess_control_texture_image_units: c.int,
    max_tess_control_uniform_components: c.int,
    max_tess_control_total_output_components: c.int,
    max_tess_evaluation_input_components: c.int,
    max_tess_evaluation_output_components: c.int,
    max_tess_evaluation_texture_image_units: c.int,
    max_tess_evaluation_uniform_components: c.int,
    max_tess_patch_components: c.int,
    max_patch_vertices: c.int,
    max_tess_gen_level: c.int,
    max_viewports: c.int,
    max_vertex_atomic_counters: c.int,
    max_tess_control_atomic_counters: c.int,
    max_tess_evaluation_atomic_counters: c.int,
    max_geometry_atomic_counters: c.int,
    max_fragment_atomic_counters: c.int,
    max_combined_atomic_counters: c.int,
    max_atomic_counter_bindings: c.int,
    max_vertex_atomic_counter_buffers: c.int,
    max_tess_control_atomic_counter_buffers: c.int,
    max_tess_evaluation_atomic_counter_buffers: c.int,
    max_geometry_atomic_counter_buffers: c.int,
    max_fragment_atomic_counter_buffers: c.int,
    max_combined_atomic_counter_buffers: c.int,
    max_atomic_counter_buffer_size: c.int,
    max_transform_feedback_buffers: c.int,
    max_transform_feedback_interleaved_components: c.int,
    max_cull_distances: c.int,
    max_combined_clip_and_cull_distances: c.int,
    max_samples: c.int,
    max_mesh_output_vertices_nv: c.int,
    max_mesh_output_primitives_nv: c.int,
    max_mesh_work_group_size_x_nv: c.int,
    max_mesh_work_group_size_y_nv: c.int,
    max_mesh_work_group_size_z_nv: c.int,
    max_task_work_group_size_x_nv: c.int,
    max_task_work_group_size_y_nv: c.int,
    max_task_work_group_size_z_nv: c.int,
    max_mesh_view_count_nv: c.int,
    max_mesh_output_vertices_ext: c.int,
    max_mesh_output_primitives_ext: c.int,
    max_mesh_work_group_size_x_ext: c.int,
    max_mesh_work_group_size_y_ext: c.int,
    max_mesh_work_group_size_z_ext: c.int,
    max_task_work_group_size_x_ext: c.int,
    max_task_work_group_size_y_ext: c.int,
    max_task_work_group_size_z_ext: c.int,
    max_mesh_view_count_ext: c.int,
    max_dual_source_draw_buffers_ext: c.int,
    limits: limits_t,
}

// Inclusion result structure allocated by C include_local/include_system callbacks
include_result_t :: struct
{
    // Header file name or NULL if inclusion failed
    header_name: cstring,

    // Header contents or NULL
    header_data: cstring,
    header_length: c.size_t,
}

// Callback for local file inclusion
include_local_func :: #type proc "c" (ctx: rawptr, header_name: cstring, includer_name: cstring, include_depth: c.size_t) -> ^include_result_t

// Callback for system file inclusion
include_system_func :: #type proc "c" (ctx: rawptr, header_name: cstring, includer_name: cstring, include_depth: c.size_t) -> ^include_result_t

// Callback for include result destruction
free_include_result_func :: #type proc "c" (ctx: rawptr, result: ^include_result_t) -> c.int

// Collection of callbacks for GLSL preprocessor
include_callbacks_t :: struct
{
    include_system: include_system_func,
    include_local: include_local_func,
    free_include_result: free_include_result_func,
}

input_t :: struct
{
    language: source_t,
    stage: stage_t,
    client: client_t,
    client_version: target_client_version_t,
    target_language: target_language_t,
    target_language_version: target_language_version_t,

    // Shader source code
    code: cstring,
    default_version: c.int,
    default_profile: profile_t,
    force_default_version_and_profile: b32,
    forward_compatible: b32,
    messages: messages_t,
    resource: Resource,
    callbacks: include_callbacks_t,
    callbacks_ctx: rawptr,
}

// SpvOptions counterpart
spv_options_t :: struct
{
    generate_debug_info: bool,
    strip_debug_info: bool,
    disable_optimizer: bool,
    optimize_size: bool,
    disassemble: bool,
    validate: bool,
    emit_nonsemantic_shader_debug_info: bool,
    emit_nonsemantic_shader_debug_source: bool,
    compile_only: bool,
}

////////////////////////  c_shader_types.h ////////////////////////

// EShLanguage counterpart
stage_t :: enum i32
{
    VERTEX,
    TESSCONTROL,
    TESSEVALUATION,
    GEOMETRY,
    FRAGMENT,
    COMPUTE,
    RAYGEN,
    INTERSECT,
    ANYHIT,
    CLOSESTHIT,
    MISS,
    CALLABLE,
    TASK,
    MESH
}

// EShLanguageMask counterpart
stage_mask_t :: bit_set[stage_t]

// EShSource counterpart
source_t :: enum i32
{
    NONE,
    GLSL,
    HLSL,
}

// EShClient counterpart
client_t :: enum i32
{
    NONE,
    VULKAN,
    OPENGL,
}

// EShTargetLanguage counterpart
target_language_t :: enum i32
{
    NONE,
    SPV,
}

// SH_TARGET_ClientVersion counterpart
target_client_version_t :: enum i32
{
    VULKAN_1_0 = (1 << 22),
    VULKAN_1_1 = (1 << 22) | (1 << 12),
    VULKAN_1_2 = (1 << 22) | (2 << 12),
    VULKAN_1_3 = (1 << 22) | (3 << 12),
    OPENGL_450 = 450,
}

// SH_TARGET_LanguageVersion counterpart
target_language_version_t :: enum i32
{
    SPV_1_0 = (1 << 16),				// 0
    SPV_1_1 = (1 << 16) | (1 << 8), 	// 1
    SPV_1_2 = (1 << 16) | (2 << 8), 	// 2
    SPV_1_3 = (1 << 16) | (3 << 8), 	// 3
    SPV_1_4 = (1 << 16) | (4 << 8), 	// 4
    SPV_1_5 = (1 << 16) | (5 << 8), 	// 5
    SPV_1_6 = (1 << 16) | (6 << 8), 	// 6
}

// EShExecutable counterpart
executable_t :: enum i32
{
    VERTEX_FRAGMENT,
    FRAGMENT,
}

// EShOptimizationLevel counterpart
// This enum is not used in the current C interface, but could be added at a later date.
// OPT_NONE is the current default.
optimization_level_t :: enum i32
{
    NO_GENERATION,
    NONE,
    SIMPLE,
    FULL,
}

// EShTextureSamplerTransformMode counterpart
texture_sampler_transform_mode_t :: enum i32
{
    KEEP,
    UPGRADE_TEXTURE_REMOVE_SAMPLER,
}

// EShMessages counterpart
messages_t :: enum i32
{
    DEFAULT_BIT = 0,
    RELAXED_ERRORS_BIT = (1 << 0),
    SUPPRESS_WARNINGS_BIT = (1 << 1),
    AST_BIT = (1 << 2),
    SPV_RULES_BIT = (1 << 3),
    VULKAN_RULES_BIT = (1 << 4),
    ONLY_PREPROCESSOR_BIT = (1 << 5),
    READ_HLSL_BIT = (1 << 6),
    CASCADING_ERRORS_BIT = (1 << 7),
    KEEP_UNCALLED_BIT = (1 << 8),
    HLSL_OFFSETS_BIT = (1 << 9),
    DEBUG_INFO_BIT = (1 << 10),
    HLSL_ENABLE_16BIT_TYPES_BIT = (1 << 11),
    HLSL_LEGALIZATION_BIT = (1 << 12),
    HLSL_DX9_COMPATIBLE_BIT = (1 << 13),
    BUILTIN_SYMBOL_TABLE_BIT = (1 << 14),
    ENHANCED = (1 << 15),
}

// EShReflectionOptions counterpart
reflection_options_t :: enum i32
{
    DEFAULT_BIT = 0,
    STRICT_ARRAY_SUFFIX_BIT = (1 << 0),
    BASIC_ARRAY_SUFFIX_BIT = (1 << 1),
    INTERMEDIATE_IOO_BIT = (1 << 2),
    SEPARATE_BUFFERS_BIT = (1 << 3),
    ALL_BLOCK_VARIABLES_BIT = (1 << 4),
    UNWRAP_IO_BLOCKS_BIT = (1 << 5),
    ALL_IO_VARIABLES_BIT = (1 << 6),
    SHARED_STD140_SSBO_BIT = (1 << 7),
    SHARED_STD140_UBO_BIT = (1 << 8),
}

// EProfile counterpart (from Versions.h)
profile_t :: enum i32
{
    BAD_PROFILE = 0,
    NO_PROFILE = (1 << 0),
    CORE_PROFILE = (1 << 1),
    COMPATIBILITY_PROFILE = (1 << 2),
    ES_PROFILE = (1 << 3),
}

// Shader options
shader_options_t :: enum i32
{
    DEFAULT_BIT = 0,
    AUTO_MAP_BINDINGS = (1 << 0),
    AUTO_MAP_LOCATIONS = (1 << 1),
    VULKAN_RULES_RELAXED = (1 << 2),
}

// TResourceType counterpart
resource_type_t :: enum i32
{
    SAMPLER,
    TEXTURE,
    IMAGE,
    UBO,
    SSBO,
    UAV,
}
