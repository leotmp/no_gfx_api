package spirv_tools

import "core:c"

@(extra_linker_flags = "/NODEFAULTLIB:libcmt")
foreign import lib {
	"../../gpu_compiler/glslang_odin/libs/SPIRV-Tools.lib",
	"../../gpu_compiler/glslang_odin/libs/SPIRV-Tools-opt.lib",
}

@(default_calling_convention = "c")
foreign lib {
	// Returns the SPIRV-Tools software version as a null-terminated string.
	// The contents of the underlying storage is valid for the remainder of
	// the process.
	@(link_name = "spvSoftwareVersionString")
	software_version_string :: proc() -> cstring ---

	// Returns a null-terminated string containing the name of the project,
	// the software version string, and commit details.
	// The contents of the underlying storage is valid for the remainder of
	// the process.
	@(link_name = "spvSoftwareVersionDetailsString")
	software_version_details_string :: proc() -> cstring ---

	// Returns a string describing the given SPIR-V target environment.
	@(link_name = "spvTargetEnvDescription")
	target_env_description :: proc(env: Target_Env) -> cstring ---

	// Parses s into *env and returns true if successful.  If unparsable, returns
	// false and sets *env to SPV_ENV_UNIVERSAL_1_0.
	@(link_name = "spvParseTargetEnv")
	parse_target_env :: proc(cstring, env: ^Target_Env) -> bool ---

	// Determines the target env value with the least features but which enables
	// the given Vulkan and SPIR-V versions. If such a target is supported, returns
	// true and writes the value to |env|, otherwise returns false.
	//
	// The Vulkan version is given as an unsigned 32-bit number as specified in
	// Vulkan section "29.2.1 Version Numbers": the major version number appears
	// in bits 22 to 21, and the minor version is in bits 12 to 21.  The SPIR-V
	// version is given in the SPIR-V version header word: major version in bits
	// 16 to 23, and minor version in bits 8 to 15.
	@(link_name = "spvParseVulkanEnv")
	parse_vulkan_env :: proc(vulkan_ver: u32, spirv_ver: u32, env: ^Target_Env) -> bool ---

	// Creates a context object for most of the SPIRV-Tools API.
	// Returns null if env is invalid.
	//
	// See specific API calls for how the target environment is interpreted
	// (particularly assembly and validation).
	@(link_name = "spvContextCreate")
	context_create :: proc(env: Target_Env) -> Context ---

	// Destroys the given context object.
	@(link_name = "spvContextDestroy")
	context_destroy :: proc(context_: Context) ---

	// Creates a Validator options object with default options. Returns a valid
	// options object. The object remains valid until it is passed into
	// spvValidatorOptionsDestroy.
	@(link_name = "spvValidatorOptionsCreate")
	validator_options_create :: proc() -> Validator_Options ---

	// Destroys the given Validator options object.
	@(link_name = "spvValidatorOptionsDestroy")
	validator_options_destroy :: proc(options: Validator_Options) ---

	// Records the maximum Universal Limit that is considered valid in the given
	// Validator options object. <options> argument must be a valid options object.
	@(link_name = "spvValidatorOptionsSetUniversalLimit")
	validator_options_set_universal_limit :: proc(options: Validator_Options, limit_type: Validator_Limit, limit: u32) ---

	// Record whether or not the validator should relax the rules on types for
	// stores to structs.  When relaxed, it will allow a type mismatch as long as
	// the types are structs with the same layout.  Two structs have the same layout
	// if
	//
	// 1) the members of the structs are either the same type or are structs with
	// same layout, and
	//
	// 2) the decorations that affect the memory layout are identical for both
	// types.  Other decorations are not relevant.
	@(link_name = "spvValidatorOptionsSetRelaxStoreStruct")
	validator_options_set_relax_store_struct :: proc(options: Validator_Options, val: bool) ---
	
	// Records whether or not the validator should relax the rules on pointer usage
	// in logical addressing mode.
	//
	// When relaxed, it will allow the following usage cases of pointers:
	// 1) OpVariable allocating an object whose type is a pointer type
	// 2) OpReturnValue returning a pointer value
	@(link_name = "spvValidatorOptionsSetRelaxLogicalPointer")
	validator_options_set_relax_logical_pointer :: proc(options: Validator_Options, val: bool) ---

	// @(link_name = spv"")
	// Records whether or not the validator should relax the rules because it is
	// expected that the optimizations will make the code legal.
	//
	// When relaxed, it will allow the following:
	// 1) It will allow relaxed logical pointers.  Setting this option will also
	//    set that option.
	// 2) Pointers that are pass as parameters to function calls do not have to
	//    match the storage class of the formal parameter.
	// 3) Pointers that are actual parameters on function calls do not have to point
	//    to the same type pointed as the formal parameter.  The types just need to
	//    logically match.
	// 4) GLSLstd450 Interpolate* instructions can have a load of an interpolant
	//    for a first argument.
	@(link_name = "spvValidatorOptionsSetBeforeHlslLegalization")
	validator_options_set_before_hlsl_legalization :: proc(options: Validator_Options, val: bool) ---

	// Records whether the validator should use "relaxed" block layout rules.
	// Relaxed layout rules are described by Vulkan extension
	// VK_KHR_relaxed_block_layout, and they affect uniform blocks, storage blocks,
	// and push constants.
	//
	// This is enabled by default when targeting Vulkan 1.1 or later.
	// Relaxed layout is more permissive than the default rules in Vulkan 1.0.
	@(link_name = "spvValidatorOptionsSetRelaxBlockLayout")
	validator_options_set_relax_block_layout :: proc(options: Validator_Options, val: bool) ---

	// Records whether the validator should use standard block layout rules for
	// uniform blocks.
	@(link_name = "spvValidatorOptionsSetUniformBufferStandardLayout")
	validator_options_set_uniform_buffer_standard_layout :: proc(options: Validator_Options, val: bool) ---

	// Records whether the validator should use "scalar" block layout rules.
	// Scalar layout rules are more permissive than relaxed block layout.
	//
	// See Vulkan extension VK_EXT_scalar_block_layout.  The scalar alignment is
	// defined as follows:
	// - scalar alignment of a scalar is the scalar size
	// - scalar alignment of a vector is the scalar alignment of its component
	// - scalar alignment of a matrix is the scalar alignment of its component
	// - scalar alignment of an array is the scalar alignment of its element
	// - scalar alignment of a struct is the max scalar alignment among its
	//   members
	//
	// For a struct in Uniform, StorageClass, or PushConstant:
	// - a member Offset must be a multiple of the member's scalar alignment
	// - ArrayStride or MatrixStride must be a multiple of the array or matrix
	//   scalar alignment
	@(link_name = "spvValidatorOptionsSetScalarBlockLayout")
	validator_options_set_scalar_block_layout :: proc(options: Validator_Options, val: bool) ---

	// Records whether the validator should use "scalar" block layout
	// rules (as defined above) for Workgroup blocks.  See Vulkan
	// extension VK_KHR_workgroup_memory_explicit_layout.
	@(link_name = "spvValidatorOptionsSetWorkgroupScalarBlockLayout")
	validator_options_set_workgroup_scalar_block_layout :: proc(options: Validator_Options, val: bool) ---

	// Records whether or not the validator should skip validating standard
	// uniform/storage block layout.
	@(link_name = "spvValidatorOptionsSetSkipBlockLayout")
	validator_options_set_skip_block_layout :: proc(options: Validator_Options, val: bool) ---

	// Records whether or not the validator should allow the LocalSizeId
	// decoration where the environment otherwise would not allow it.
	@(link_name = "spvValidatorOptionsSetAllowLocalSizeId")
	validator_options_set_allow_local_size_id :: proc(options: Validator_Options, val: bool) ---

	// Allow Offset (in addition to ConstOffset) for texture operations.
	// Was added for VK_KHR_maintenance8
	@(link_name = "spvValidatorOptionsSetAllowOffsetTextureOperand")
	validator_options_set_allow_offset_texture_operand :: proc(options: Validator_Options, val: bool) ---

	// Allow base operands of some bit operations to be non-32-bit wide.
	// Was added for VK_KHR_maintenance9
	@(link_name = "spvValidatorOptionsSetAllowVulkan32BitBitwise")
	validator_options_set_allow_vulkan32_bit_bitwise :: proc(options: Validator_Options, val: bool) ---

	// Whether friendly names should be used in validation error messages.
	@(link_name = "spvValidatorOptionsSetFriendlyNames")
	validator_options_set_friendly_names :: proc(options: Validator_Options, val: bool) ---

	// Creates an optimizer options object with default options. Returns a valid
	// options object. The object remains valid until it is passed into
	// |spvOptimizerOptionsDestroy|.
	@(link_name = "spvOptimizerOptionsCreate")
	optimizer_options_create :: proc() -> Optimizer_Options ---

	// Destroys the given optimizer options object.
	@(link_name = "spvOptimizerOptionsDestroy")
	optimizer_options_destroy :: proc(options: Optimizer_Options) ---

	// Records whether or not the optimizer should run the validator before
	// optimizing.  If |val| is true, the validator will be run.
	@(link_name = "spvOptimizerOptionsSetRunValidator")
	optimizer_options_set_run_validator :: proc(options: Optimizer_Options, val: bool) ---

	// Records the validator options that should be passed to the validator if it is
	// run.
	@(link_name = "spvOptimizerOptionsSetValidatorOptions")
	optimizer_options_set_validator_options :: proc(options: Optimizer_Options, val: Validator_Options) ---

	// Records the maximum possible value for the id bound.
	@(link_name = "spvOptimizerOptionsSetMaxIdBound")
	optimizer_options_set_max_id_bound :: proc(options: Optimizer_Options, val: u32) ---

	// Records whether all bindings within the module should be preserved.
	@(link_name = "spvOptimizerOptionsSetPreserveBindings")
	optimizer_options_set_preserve_bindings :: proc(options: Optimizer_Options, val: bool) ---

	// Records whether all specialization constants within the module
	// should be preserved.
	@(link_name = "spvOptimizerOptionsSetPreserveSpecConstants")
	optimizer_options_set_preserve_spec_constants :: proc(options: Optimizer_Options, val: bool) ---

	// Creates a reducer options object with default options. Returns a valid
	// options object. The object remains valid until it is passed into
	// |spvReducerOptionsDestroy|.
	@(link_name = "spvReducerOptionsCreate")
	reducer_options_create :: proc() -> Reducer_Options ---

	// Destroys the given reducer options object.
	@(link_name = "spvReducerOptionsDestroy")
	reducer_options_destroy :: proc(options: Reducer_Options) ---

	// Sets the maximum number of reduction steps that should run before the reducer
	// gives up.
	@(link_name = "spvReducerOptionsSetStepLimit")
	reducer_options_set_step_limit :: proc(options: Reducer_Options, step_limit: u32) ---

	// Sets the fail-on-validation-error option; if true, the reducer will return
	// kStateInvalid if a reduction step yields a state that fails SPIR-V
	// validation. Otherwise, an invalid state is treated as uninteresting and the
	// reduction backtracks and continues.
	@(link_name = "spvReducerOptionsSetFailOnValidationError")
	reducer_options_set_fail_on_validation_error :: proc(options: Reducer_Options, fail_on_validation_error: bool) ---

	// Sets the function that the reducer should target.  If set to zero the reducer
	// will target all functions as well as parts of the module that lie outside
	// functions.  Otherwise the reducer will restrict reduction to the function
	// with result id |target_function|, which is required to exist.
	@(link_name = "spvReducerOptionsSetTargetFunction")
	reducer_options_set_target_function :: proc(options: Reducer_Options, target_function: u32) ---

	// Creates a fuzzer options object with default options. Returns a valid
	// options object. The object remains valid until it is passed into
	// |spvFuzzerOptionsDestroy|.
	@(link_name = "spvFuzzerOptionsCreate")
	fuzzer_options_create :: proc() -> Fuzzer_Options ---

	// Destroys the given fuzzer options object.
	@(link_name = "spvFuzzerOptionsDestroy")
	fuzzer_options_destroy :: proc(options: Fuzzer_Options) ---

	// Enables running the validator after every transformation is applied during
	// a replay.
	@(link_name = "spvFuzzerOptionsEnableReplayValidation")
	fuzzer_options_enable_replay_validation :: proc(options: Fuzzer_Options) ---

	// Sets the seed with which the random number generator used by the fuzzer
	// should be initialized.
	@(link_name = "spvFuzzerOptionsSetRandomSeed")
	fuzzer_options_set_random_seed :: proc(options: Fuzzer_Options, seed: u32) ---

	// Sets the range of transformations that should be applied during replay: 0
	// means all transformations, +N means the first N transformations, -N means all
	// except the final N transformations.
	@(link_name = "spvFuzzerOptionsSetReplayRange")
	fuzzer_options_set_replay_range :: proc(options: Fuzzer_Options, replay_range: i32) ---

	// Sets the maximum number of steps that the shrinker should take before giving
	// up.
	@(link_name = "spvFuzzerOptionsSetShrinkerStepLimit")
	fuzzer_options_set_shrinker_step_limit :: proc(options: Fuzzer_Options, shrinker_step_limit: u32) ---

	// Enables running the validator after every pass is applied during a fuzzing
	// run.
	@(link_name = "spvFuzzerOptionsEnableFuzzerPassValidation")
	fuzzer_options_enable_fuzzer_pass_validation :: proc(options: Fuzzer_Options) ---

	// Enables all fuzzer passes during a fuzzing run (instead of a random subset
	// of passes).
	@(link_name = "spvFuzzerOptionsEnableAllPasses")
	fuzzer_options_enable_all_passes :: proc(options: Fuzzer_Options) ---

	// Encodes the given SPIR-V assembly text to its binary representation. The
	// length parameter specifies the number of bytes for text. Encoded binary will
	// be stored into *binary. Any error will be written into *diagnostic if
	// diagnostic is non-null, otherwise the context's message consumer will be
	// used. The generated binary is independent of the context and may outlive it.
	// The SPIR-V binary version is set to the highest version of SPIR-V supported
	// by the context's target environment.
	@(link_name = "spvTextToBinary")
	text_to_binary :: proc(context_: Context, text: [^]u8, length: int, binary: ^^Binary, diagnostic: ^Diagnostic) -> Result ---

	// Encodes the given SPIR-V assembly text to its binary representation. Same as
	// spvTextToBinary but with options. The options parameter is a bit field of
	// spv_text_to_binary_options_t.
	@(link_name = "spvTextToBinaryWithOptions")
	text_to_binary_with_options :: proc(context_: Context, text: [^]u8, length: int, options: u32, binary: ^^Binary, diagnostic: ^^Diagnostic) -> Result ---

	// Frees an allocated text stream. This is a no-op if the text parameter
	// is a null pointer.
	@(link_name = "spvTextDestroy")
	text_destroy :: proc(text: ^Text) ---

	// Decodes the given SPIR-V binary representation to its assembly text. The
	// word_count parameter specifies the number of words for binary. The options
	// parameter is a bit field of spv_binary_to_text_options_t. Decoded text will
	// be stored into *text. Any error will be written into *diagnostic if
	// diagnostic is non-null, otherwise the context's message consumer will be
	// used.
	@(link_name = "spvBinaryToText")
	binary_to_text :: proc(context_: Context, binary: [^]u32, word_count: int, options: u32, text: ^^Text, diagnostic: ^^Diagnostic) -> Result ---

	// Frees a binary stream from memory. This is a no-op if binary is a null
	// pointer.
	@(link_name = "spvBinaryDestroy")
	binary_destroy :: proc(binary: ^Binary) ---

	// Validates a SPIR-V binary for correctness. Any errors will be written into
	// *diagnostic if diagnostic is non-null, otherwise the context's message
	// consumer will be used.
	//
	// Validate for SPIR-V spec rules for the SPIR-V version named in the
	// binary's header (at word offset 1).  Additionally, if the context target
	// environment is a client API (such as Vulkan 1.1), then validate for that
	// client API version, to the extent that it is verifiable from data in the
	// binary itself.
	@(link_name = "spvValidate")
	validate :: proc(context_: Context, #by_ptr binary: Binary, diagnostic: ^^Diagnostic) -> Result ---

	// Validates a SPIR-V binary for correctness. Uses the provided Validator
	// options. Any errors will be written into *diagnostic if diagnostic is
	// non-null, otherwise the context's message consumer will be used.
	//
	// Validate for SPIR-V spec rules for the SPIR-V version named in the
	// binary's header (at word offset 1).  Additionally, if the context target
	// environment is a client API (such as Vulkan 1.1), then validate for that
	// client API version, to the extent that it is verifiable from data in the
	// binary itself, or in the validator options.
	@(link_name = "spvValidateWithOptions")
	validate_with_options :: proc(
		context_:       Context,
		options:        Validator_Options,
		#by_ptr binary: Binary,
		diagnostic:     ^^Diagnostic,
	) -> Result ---

	// Validates a raw SPIR-V binary for correctness. Any errors will be written
	// into *diagnostic if diagnostic is non-null, otherwise the context's message
	// consumer will be used.
	@(link_name = "spvValidateBinary")
	validate_binary :: proc(
		context_:   Context,
		words:      [^]u32,
		num_words:  int,
		diagnostic: ^^Diagnostic,
	) -> Result ---

	// Creates a diagnostic object. The position parameter specifies the location in
	// the text/binary stream. The message parameter, copied into the diagnostic
	// object, contains the error message to display.
	@(link_name = "spvDiagnosticCreate")
	diagnostic_create :: proc(#by_ptr position: Position, message: cstring) -> ^Diagnostic ---

	// Destroys a diagnostic object.  This is a no-op if diagnostic is a null
	// pointer.
	@(link_name = "spvDiagnosticDestroy")
	diagnostic_destroy :: proc(diagnostic: ^Diagnostic) ---

	// Prints the diagnostic to stderr.
	@(link_name = "spvDiagnosticPrint")
	diagnostic_print :: proc(diagnostic: ^Diagnostic) -> Result ---

	// Gets the name of an instruction, without the "Op" prefix.
	@(link_name = "spvOpcodeString")
	opcode_string :: proc(opcode: u32) -> cstring ---

	// The binary parser interface.

	// Parses a SPIR-V binary, specified as counted sequence of 32-bit words.
	// Parsing feedback is provided via two callbacks provided as function
	// pointers.  Each callback function pointer can be a null pointer, in
	// which case it is never called.  Otherwise, in a valid parse the
	// parsed-header callback is called once, and then the parsed-instruction
	// callback once for each instruction in the stream.  The user_data parameter
	// is supplied as context to the callbacks.  Returns SPV_SUCCESS on successful
	// parse where the callbacks always return SPV_SUCCESS.  For an invalid parse,
	// returns a status code other than SPV_SUCCESS, and if diagnostic is non-null
	// also emits a diagnostic. If diagnostic is null the context's message consumer
	// will be used to emit any errors. If a callback returns anything other than
	// SPV_SUCCESS, then that status code is returned, no further callbacks are
	// issued, and no additional diagnostics are emitted.
	@(link_name = "spvBinaryParse")
	binary_parse :: proc(
		context_:          Context,
		user_data:         rawptr,
		words:             [^]u32,
		num_words:         int,
		parse_header:      Parsed_Header_Fn,
		parse_instruction: Parsed_Instruction_Fn,
		diagnostic:        ^^Diagnostic,
	) -> Result ---

	// The optimizer interface.

	// Creates and returns an optimizer object.  This object must be passed to
	// optimizer APIs below and is valid until passed to spvOptimizerDestroy.
	@(link_name = "spvOptimizerCreate")
	optimizer_create :: proc(env: Target_Env) -> Optimizer ---

	// Destroys the given optimizer object.
	@(link_name = "spvOptimizerDestroy")
	optimizer_destroy :: proc(optimizer: Optimizer) ---

	// Sets an spv_message_consumer on an optimizer object.
	@(link_name = "spvOptimizerSetMessageConsumer")
	optimizer_set_message_consumer :: proc(optimizer: Optimizer, consumer: Message_Consumer) ---

	// Registers passes that attempt to legalize the generated code.
	@(link_name = "spvOptimizerRegisterLegalizationPasses")
	optimizer_register_legalization_passes :: proc(optimizer: Optimizer) ---

	// Registers passes that attempt to improve performance of generated code.
	@(link_name = "spvOptimizerRegisterPerformancePasses")
	optimizer_register_performance_passes :: proc(optimizer: Optimizer) ---

	// Registers passes that attempt to improve the size of generated code.
	@(link_name = "spvOptimizerRegisterSizePasses")
	optimizer_register_size_passes :: proc(optimizer: Optimizer) ---

	// Registers a pass specified by a flag in an optimizer object.
	@(link_name = "spvOptimizerRegisterPassFromFlag")
	optimizer_register_pass_from_flag :: proc(optimizer: Optimizer, flag: cstring) -> bool ---

	// Registers passes specified by length number of flags in an optimizer object.
	// Passes may remove interface variables that are unused.
	@(link_name = "spvOptimizerRegisterPassesFromFlags")
	optimizer_register_passes_from_flags :: proc(optimizer: Optimizer, flags: [^]cstring, flag_count: int) -> bool ---

	// Registers passes specified by length number of flags in an optimizer object.
	// Passes will not remove interface variables.
	@(link_name = "spvOptimizerRegisterPassesFromFlagsWhilePreservingTheInterface")
	optimizer_register_passes_from_flags_while_preserving_the_interface :: proc(optimizer: Optimizer, flags: [^]cstring, flag_count: int) -> bool ---

	// Optimizes the SPIR-V code of size |word_count| pointed to by |binary| and
	// returns an optimized spv_binary in |optimized_binary|.
	//
	// Returns SPV_SUCCESS on successful optimization, whether or not the module is
	// modified.  Returns an SPV_ERROR_* if the module fails to validate or if
	// errors occur when processing using any of the registered passes.  In that
	// case, no further passes are executed and the |optimized_binary| contents may
	// be invalid.
	//
	// By default, the binary is validated before any transforms are performed,
	// and optionally after each transform.  Validation uses SPIR-V spec rules
	// for the SPIR-V version named in the binary's header (at word offset 1).
	// Additionally, if the target environment is a client API (such as
	// Vulkan 1.1), then validate for that client API version, to the extent
	// that it is verifiable from data in the binary itself, or from the
	// validator options set on the optimizer options.
	@(link_name = "spvOptimizerRun")
	optimizer_run :: proc(optimizer: Optimizer, binary: [^]u32, word_count: int, optimized_binary: ^^Binary, options: Optimizer_Options) -> Result ---
}

Validator_Limit :: enum {
	Max_Struct_Members,
	Max_Struct_Depth,
	Max_Local_Variables,
	Max_Global_Variables,
	Max_Switch_Branches,
	Max_Function_Args,
	Max_Control_Flow_Nesting_Depth,
	Max_Access_Chain_Indexes,
	Max_Id_Bound,
}

Result :: enum i32 {
	Success                  = 0,
	Unsupported              = 1,
	End_Of_Stream            = 2,
	Warning                  = 3,
	Failed_Match             = 4,
	Requested_Termination    = 5,  // Success, but signals early termination.
	Error_Internal           = -1,
	Error_Out_Of_Memory      = -2,
	Error_Invalid_Pointer    = -3,
	Error_Invalid_Binary     = -4,
	Error_Invalid_Text       = -5,
	Error_Invalid_Table      = -6,
	Error_Invalid_Value      = -7,
	Error_Invalid_Diagnostic = -8,
	Error_Invalid_Lookup     = -9,
	Error_Invalid_ID         = -10,
	Error_Invalid_Cfg        = -11,
	Error_Invalid_Layout     = -12,
	Error_Invalid_Capability = -13,
	Error_Invalid_Data       = -14,  // Indicates data rules validation failure.
	Error_Missing_Extension  = -15,
	Error_Wrong_Version      = -16,  // Indicates wrong SPIR-V version
	Error_Fnvar              = -17,  // Error related to SPV_INTEL_function_variants extension
}

Target_Env :: enum {
	Universal_1_0,  // SPIR-V 1.0 latest revision, no other restrictions.
	Vulkan_1_0,     // Vulkan 1.0 latest revision.
	Universal_1_1,  // SPIR-V 1.1 latest revision, no other restrictions.
	Opencl_2_1,     // OpenCL Full Profile 2.1 latest revision.
	Opencl_2_2,     // OpenCL Full Profile 2.2 latest revision.
	Opengl_4_0,     // OpenGL 4.0 plus GL_ARB_gl_spirv, latest revisions.
	Opengl_4_1,     // OpenGL 4.1 plus GL_ARB_gl_spirv, latest revisions.
	Opengl_4_2,     // OpenGL 4.2 plus GL_ARB_gl_spirv, latest revisions.
	Opengl_4_3,     // OpenGL 4.3 plus GL_ARB_gl_spirv, latest revisions.
	// There is no variant for OpenGL 4.4.
	Opengl_4_5,     // OpenGL 4.5 plus GL_ARB_gl_spirv, latest revisions.
	Universal_1_2,  // SPIR-V 1.2, latest revision, no other restrictions.
	Opencl_1_2,     // OpenCL Full Profile 1.2 plus cl_khr_il_program,
	                      // latest revision.
	Opencl_Embedded_1_2,  // OpenCL Embedded Profile 1.2 plus
	                            // cl_khr_il_program, latest revision.
	Opencl_2_0,  // OpenCL Full Profile 2.0 plus cl_khr_il_program,
	                   // latest revision.
	Opencl_Embedded_2_0,  // OpenCL Embedded Profile 2.0 plus
	                            // cl_khr_il_program, latest revision.
	Opencl_Embedded_2_1,  // OpenCL Embedded Profile 2.1 latest revision.
	Opencl_Embedded_2_2,  // OpenCL Embedded Profile 2.2 latest revision.
	Universal_1_3,  // SPIR-V 1.3 latest revision, no other restrictions.
	Vulkan_1_1,     // Vulkan 1.1 latest revision.
	Webgpu_0,       // DEPRECATED, may be removed in the future.
	Universal_1_4,  // SPIR-V 1.4 latest revision, no other restrictions.

	// vulkan 1.1 with VK_KHR_spirv_1_4, i.e. SPIR-V 1.4 binary.
	Vulkan_1_1_Spirv_1_4,

	Universal_1_5,  // SPIR-V 1.5 latest revision, no other restrictions.
	Vulkan_1_2,     // Vulkan 1.2 latest revision.

	Universal_1_6,  // SPIR-V 1.6 latest revision, no other restrictions.
	Vulkan_1_3,     // Vulkan 1.3 latest revision.
	Vulkan_1_4,     // Vulkan 1.4 latest revision.
}


// Severity levels of messages communicated to the consumer.
Message_Level :: enum {
	Fatal,           // Unrecoverable error due to environment.
	               // Will exit the program immediately. E.g.,
	               // out of memory.
	Internal_Error,  // Unrecoverable error due to SPIRV-Tools
	               // internals.
	               // Will exit the program immediately. E.g.,
	               // unimplemented feature.
	Error,           // Normal error due to user input.
	Warning,         // Warning information.
	Info,            // General information.
	Debug,           // Debug information.
}

Endianness :: enum u32 {
	Little,
	Big,
}

Context           :: distinct rawptr
Validator_Options :: distinct rawptr
Optimizer         :: distinct rawptr
Optimizer_Options :: distinct rawptr
Reducer_Options   :: distinct rawptr
Fuzzer_Options    :: distinct rawptr

Position :: struct {
	line:   int,
	column: int,
	index:  int,
}

Diagnostic :: struct {
	position:     Position,
	error:        cstring,
	isTextSource: bool,
}

// spv_text_t / spv_binary_t — C allocates these; destroy with text_destroy / binary_destroy.
Text :: struct {
	str:    cstring,
	length: c.size_t,
}

Binary :: struct {
	code:       [^]u32,
	word_count: c.size_t,
}

// spv_binary_to_text_options_t bit positions (SPV_BIT(n)).
Binary_To_Text_Option :: enum u32 {
	None                = 0,
	Print               = 1,
	Color               = 2,
	Indent              = 3,
	Show_Byte_Offset    = 4,
	No_Header           = 5,
	Friendly_Names      = 6,
	Comment             = 7,
	Nested_Indent       = 8,
	Reorder_Numeric_Ids = 9,
}
Binary_To_Text_Options :: bit_set[Binary_To_Text_Option; u32]

Operand_Type :: enum u32 {
	// A sentinel value.
	SPV_OPERAND_TYPE_NONE = 0,

	// Set 1:  Operands that are IDs.
	SPV_OPERAND_TYPE_ID,
	SPV_OPERAND_TYPE_TYPE_ID,
	SPV_OPERAND_TYPE_RESULT_ID,
	SPV_OPERAND_TYPE_MEMORY_SEMANTICS_ID,  // SPIR-V Sec 3.25
	SPV_OPERAND_TYPE_SCOPE_ID,             // SPIR-V Sec 3.27

	// Set 2:  Operands that are literal numbers.
	SPV_OPERAND_TYPE_LITERAL_INTEGER,  // Always unsigned 32-bits.
	// The Instruction argument to OpExtInst. It's an unsigned 32-bit literal
	// number indicating which instruction to use from an extended instruction
	// set.
	SPV_OPERAND_TYPE_EXTENSION_INSTRUCTION_NUMBER,
	// The Opcode argument to OpSpecConstantOp. It determines the operation
	// to be performed on constant operands to compute a specialization constant
	// result.
	SPV_OPERAND_TYPE_SPEC_CONSTANT_OP_NUMBER,
	// A literal number whose format and size are determined by a previous operand
	// in the same instruction.  It's a signed integer, an unsigned integer, or a
	// floating point number.  It also has a specified bit width.  The width
	// may be larger than 32, which would require such a typed literal value to
	// occupy multiple SPIR-V words.
	SPV_OPERAND_TYPE_TYPED_LITERAL_NUMBER,
	SPV_OPERAND_TYPE_LITERAL_FLOAT,  // Always 32-bit float.

	// Set 3:  The literal string operand type.
	SPV_OPERAND_TYPE_LITERAL_STRING,

	// Set 4:  Operands that are a single word enumerated value.
	SPV_OPERAND_TYPE_SOURCE_LANGUAGE,               // SPIR-V Sec 3.2
	SPV_OPERAND_TYPE_EXECUTION_MODEL,               // SPIR-V Sec 3.3
	SPV_OPERAND_TYPE_ADDRESSING_MODEL,              // SPIR-V Sec 3.4
	SPV_OPERAND_TYPE_MEMORY_MODEL,                  // SPIR-V Sec 3.5
	SPV_OPERAND_TYPE_EXECUTION_MODE,                // SPIR-V Sec 3.6
	SPV_OPERAND_TYPE_STORAGE_CLASS,                 // SPIR-V Sec 3.7
	SPV_OPERAND_TYPE_DIMENSIONALITY,                // SPIR-V Sec 3.8
	SPV_OPERAND_TYPE_SAMPLER_ADDRESSING_MODE,       // SPIR-V Sec 3.9
	SPV_OPERAND_TYPE_SAMPLER_FILTER_MODE,           // SPIR-V Sec 3.10
	SPV_OPERAND_TYPE_SAMPLER_IMAGE_FORMAT,          // SPIR-V Sec 3.11
	SPV_OPERAND_TYPE_IMAGE_CHANNEL_ORDER,           // SPIR-V Sec 3.12
	SPV_OPERAND_TYPE_IMAGE_CHANNEL_DATA_TYPE,       // SPIR-V Sec 3.13
	SPV_OPERAND_TYPE_FP_ROUNDING_MODE,              // SPIR-V Sec 3.16
	SPV_OPERAND_TYPE_LINKAGE_TYPE,                  // SPIR-V Sec 3.17
	SPV_OPERAND_TYPE_ACCESS_QUALIFIER,              // SPIR-V Sec 3.18
	SPV_OPERAND_TYPE_FUNCTION_PARAMETER_ATTRIBUTE,  // SPIR-V Sec 3.19
	SPV_OPERAND_TYPE_DECORATION,                    // SPIR-V Sec 3.20
	SPV_OPERAND_TYPE_BUILT_IN,                      // SPIR-V Sec 3.21
	SPV_OPERAND_TYPE_GROUP_OPERATION,               // SPIR-V Sec 3.28
	SPV_OPERAND_TYPE_KERNEL_ENQ_FLAGS,              // SPIR-V Sec 3.29
	SPV_OPERAND_TYPE_KERNEL_PROFILING_INFO,         // SPIR-V Sec 3.30
	SPV_OPERAND_TYPE_CAPABILITY,                    // SPIR-V Sec 3.31
	SPV_OPERAND_TYPE_FPENCODING,                    // SPIR-V Sec 3.51

	// NOTE: New concrete enum values should be added at the end.

	// Set 5:  Operands that are a single word bitmask.
	// Sometimes a set bit indicates the instruction requires still more operands.
	SPV_OPERAND_TYPE_IMAGE,                  // SPIR-V Sec 3.14
	SPV_OPERAND_TYPE_FP_FAST_MATH_MODE,      // SPIR-V Sec 3.15
	SPV_OPERAND_TYPE_SELECTION_CONTROL,      // SPIR-V Sec 3.22
	SPV_OPERAND_TYPE_LOOP_CONTROL,           // SPIR-V Sec 3.23
	SPV_OPERAND_TYPE_FUNCTION_CONTROL,       // SPIR-V Sec 3.24
	SPV_OPERAND_TYPE_MEMORY_ACCESS,          // SPIR-V Sec 3.26
	SPV_OPERAND_TYPE_FRAGMENT_SHADING_RATE,  // SPIR-V Sec 3.FSR

	// NOTE: New concrete enum values should be added at the end.

	// The "optional" and "variable"  operand types are only used internally by
	// the assembler and the binary parser.
	// There are two categories:
	//    Optional : expands to 0 or 1 operand, like ? in regular expressions.
	//    Variable : expands to 0, 1 or many operands or pairs of operands.
	//               This is similar to * in regular expressions.

	// Use characteristic function spvOperandIsConcrete to classify the
	// operand types; when it returns false, the operand is optional or variable.
	//
	// Any variable operand type is also optional.

	// An optional operand represents zero or one logical operands.
	// In an instruction definition, this may only appear at the end of the
	// operand types.
	SPV_OPERAND_TYPE_OPTIONAL_ID,
	// An optional image operand type.
	SPV_OPERAND_TYPE_OPTIONAL_IMAGE,
	// An optional memory access type.
	SPV_OPERAND_TYPE_OPTIONAL_MEMORY_ACCESS,
	// An optional literal integer.
	SPV_OPERAND_TYPE_OPTIONAL_LITERAL_INTEGER,
	// An optional literal number, which may be either integer or floating point.
	SPV_OPERAND_TYPE_OPTIONAL_LITERAL_NUMBER,
	// Like SPV_OPERAND_TYPE_TYPED_LITERAL_NUMBER, but optional, and integral.
	SPV_OPERAND_TYPE_OPTIONAL_TYPED_LITERAL_INTEGER,
	// An optional literal string.
	SPV_OPERAND_TYPE_OPTIONAL_LITERAL_STRING,
	// An optional access qualifier
	SPV_OPERAND_TYPE_OPTIONAL_ACCESS_QUALIFIER,
	// An optional context-independent value, or CIV.  CIVs are tokens that we can
	// assemble regardless of where they occur -- literals, IDs, immediate
	// integers, etc.
	SPV_OPERAND_TYPE_OPTIONAL_CIV,
	// An optional floating point encoding enum
	SPV_OPERAND_TYPE_OPTIONAL_FPENCODING,

	// A variable operand represents zero or more logical operands.
	// In an instruction definition, this may only appear at the end of the
	// operand types.
	SPV_OPERAND_TYPE_VARIABLE_ID,
	SPV_OPERAND_TYPE_VARIABLE_LITERAL_INTEGER,
	// A sequence of zero or more pairs of (typed literal integer, Id).
	// Expands to zero or more:
	//  (SPV_OPERAND_TYPE_TYPED_LITERAL_INTEGER, SPV_OPERAND_TYPE_ID)
	// where the literal number must always be an integer of some sort.
	SPV_OPERAND_TYPE_VARIABLE_LITERAL_INTEGER_ID,
	// A sequence of zero or more pairs of (Id, Literal integer)
	SPV_OPERAND_TYPE_VARIABLE_ID_LITERAL_INTEGER,

	// The following are concrete enum types from the DebugInfo extended
	// instruction set.
	SPV_OPERAND_TYPE_DEBUG_INFO_FLAGS,  // DebugInfo Sec 3.2.  A mask.
	SPV_OPERAND_TYPE_DEBUG_BASE_TYPE_ATTRIBUTE_ENCODING,  // DebugInfo Sec 3.3
	SPV_OPERAND_TYPE_DEBUG_COMPOSITE_TYPE,                // DebugInfo Sec 3.4
	SPV_OPERAND_TYPE_DEBUG_TYPE_QUALIFIER,                // DebugInfo Sec 3.5
	SPV_OPERAND_TYPE_DEBUG_OPERATION,                     // DebugInfo Sec 3.6

	// The following are concrete enum types from the OpenCL.DebugInfo.100
	// extended instruction set.
	SPV_OPERAND_TYPE_CLDEBUG100_DEBUG_INFO_FLAGS,  // Sec 3.2. A Mask
	SPV_OPERAND_TYPE_CLDEBUG100_DEBUG_BASE_TYPE_ATTRIBUTE_ENCODING,  // Sec 3.3
	SPV_OPERAND_TYPE_CLDEBUG100_DEBUG_COMPOSITE_TYPE,                // Sec 3.4
	SPV_OPERAND_TYPE_CLDEBUG100_DEBUG_TYPE_QUALIFIER,                // Sec 3.5
	SPV_OPERAND_TYPE_CLDEBUG100_DEBUG_OPERATION,                     // Sec 3.6
	SPV_OPERAND_TYPE_CLDEBUG100_DEBUG_IMPORTED_ENTITY,               // Sec 3.7

	// The following are concrete enum types from SPV_INTEL_float_controls2
	// https://github.com/intel/llvm/blob/39fa9b0cbfbae88327118990a05c5b387b56d2ef/sycl/doc/extensions/SPIRV/SPV_INTEL_float_controls2.asciidoc
	SPV_OPERAND_TYPE_FPDENORM_MODE,     // Sec 3.17 FP Denorm Mode
	SPV_OPERAND_TYPE_FPOPERATION_MODE,  // Sec 3.18 FP Operation Mode
	// A value enum from https://github.com/KhronosGroup/SPIRV-Headers/pull/177
	SPV_OPERAND_TYPE_QUANTIZATION_MODES,
	// A value enum from https://github.com/KhronosGroup/SPIRV-Headers/pull/177
	SPV_OPERAND_TYPE_OVERFLOW_MODES,

	// Concrete operand types for the provisional Vulkan ray tracing feature.
	SPV_OPERAND_TYPE_RAY_FLAGS,               // SPIR-V Sec 3.RF
	SPV_OPERAND_TYPE_RAY_QUERY_INTERSECTION,  // SPIR-V Sec 3.RQIntersection
	SPV_OPERAND_TYPE_RAY_QUERY_COMMITTED_INTERSECTION_TYPE,  // SPIR-V Sec
	                                                       // 3.RQCommitted
	SPV_OPERAND_TYPE_RAY_QUERY_CANDIDATE_INTERSECTION_TYPE,  // SPIR-V Sec
	                                                       // 3.RQCandidate

	// Concrete operand types for integer dot product.
	// Packed vector format
	SPV_OPERAND_TYPE_PACKED_VECTOR_FORMAT,  // SPIR-V Sec 3.x
	// An optional packed vector format
	SPV_OPERAND_TYPE_OPTIONAL_PACKED_VECTOR_FORMAT,

	// Concrete operand types for cooperative matrix.
	SPV_OPERAND_TYPE_COOPERATIVE_MATRIX_OPERANDS,
	// An optional cooperative matrix operands
	SPV_OPERAND_TYPE_OPTIONAL_COOPERATIVE_MATRIX_OPERANDS,
	SPV_OPERAND_TYPE_COOPERATIVE_MATRIX_LAYOUT,
	SPV_OPERAND_TYPE_COOPERATIVE_MATRIX_USE,

	// Enum type from SPV_INTEL_global_variable_fpga_decorations
	SPV_OPERAND_TYPE_INITIALIZATION_MODE_QUALIFIER,
	// Enum type from SPV_INTEL_global_variable_host_access
	SPV_OPERAND_TYPE_HOST_ACCESS_QUALIFIER,
	// Enum type from SPV_INTEL_cache_controls
	SPV_OPERAND_TYPE_LOAD_CACHE_CONTROL,
	// Enum type from SPV_INTEL_cache_controls
	SPV_OPERAND_TYPE_STORE_CACHE_CONTROL,
	// Enum type from SPV_INTEL_maximum_registers
	SPV_OPERAND_TYPE_NAMED_MAXIMUM_NUMBER_OF_REGISTERS,
	// Enum type from SPV_NV_raw_access_chains
	SPV_OPERAND_TYPE_RAW_ACCESS_CHAIN_OPERANDS,
	// Optional enum type from SPV_NV_raw_access_chains
	SPV_OPERAND_TYPE_OPTIONAL_RAW_ACCESS_CHAIN_OPERANDS,
	// Enum type from SPV_NV_tensor_addressing
	SPV_OPERAND_TYPE_TENSOR_CLAMP_MODE,
	// Enum type from SPV_NV_cooperative_matrix2
	SPV_OPERAND_TYPE_COOPERATIVE_MATRIX_REDUCE,
	// Enum type from SPV_NV_cooperative_matrix2
	SPV_OPERAND_TYPE_TENSOR_ADDRESSING_OPERANDS,
	// Optional types from SPV_INTEL_subgroup_matrix_multiply_accumulate
	SPV_OPERAND_TYPE_MATRIX_MULTIPLY_ACCUMULATE_OPERANDS,
	SPV_OPERAND_TYPE_OPTIONAL_MATRIX_MULTIPLY_ACCUMULATE_OPERANDS,

	SPV_OPERAND_TYPE_COOPERATIVE_VECTOR_MATRIX_LAYOUT,
	SPV_OPERAND_TYPE_COMPONENT_TYPE,

	// From nonesmantic.clspvreflection
	SPV_OPERAND_TYPE_KERNEL_PROPERTY_FLAGS,

	// From nonesmantic.shader.debuginfo.100
	SPV_OPERAND_TYPE_SHDEBUG100_BUILD_IDENTIFIER_FLAGS,
	SPV_OPERAND_TYPE_SHDEBUG100_DEBUG_BASE_TYPE_ATTRIBUTE_ENCODING,
	SPV_OPERAND_TYPE_SHDEBUG100_DEBUG_COMPOSITE_TYPE,
	SPV_OPERAND_TYPE_SHDEBUG100_DEBUG_IMPORTED_ENTITY,
	SPV_OPERAND_TYPE_SHDEBUG100_DEBUG_INFO_FLAGS,
	SPV_OPERAND_TYPE_SHDEBUG100_DEBUG_OPERATION,
	SPV_OPERAND_TYPE_SHDEBUG100_DEBUG_TYPE_QUALIFIER,

	// SPV_ARM_tensors
	SPV_OPERAND_TYPE_TENSOR_OPERANDS,
	SPV_OPERAND_TYPE_OPTIONAL_TENSOR_OPERANDS,

	// SPV_INTEL_function_variants
	SPV_OPERAND_TYPE_OPTIONAL_CAPABILITY,
	SPV_OPERAND_TYPE_VARIABLE_CAPABILITY,

	// This is a sentinel value, and does not represent an operand type.
	// It should come last.
	SPV_OPERAND_TYPE_NUM_OPERAND_TYPES,
}

// This determines at a high level the kind of a binary-encoded literal
// number, but not the bit width.
// In principle, these could probably be folded into new entries in
// spv_operand_type_t.  But then we'd have some special case differences
// between the assembler and disassembler.
Number_Kind :: enum {
	None = 0, // The default for value initialization.
	Unsigned_Int,
	Signed_Int,
	Floating,
}

// Represent the encoding of floating point values
Fp_Encoding :: enum {
	SPV_FP_ENCODING_UNKNOWN = 0,  // The encoding is not specified. Has to be deduced from bitwidth
	SPV_FP_ENCODING_IEEE754_BINARY16,  // half float
	SPV_FP_ENCODING_IEEE754_BINARY32,  // single float
	SPV_FP_ENCODING_IEEE754_BINARY64,  // double float
	SPV_FP_ENCODING_BFLOAT16,
	SPV_FP_ENCODING_FLOAT8_E4M3,
	SPV_FP_ENCODING_FLOAT8_E5M2,
}

// Information about an operand parsed from a binary SPIR-V module.
// Note that the values are not included.  You still need access to the binary
// to extract the values.
Parsed_Operand :: struct {
	// Location of the operand, in words from the start of the instruction.
	offset:           u16,
	// Number of words occupied by this operand.
	num_words:        u16,
	// The "concrete" operand type.  See the definition of spv_operand_type_t
	// for details.
	type:             Operand_Type,
	// If type is a literal number type, then number_kind says whether it's
	// a signed integer, an unsigned integer, or a floating point number.
	number_kind:      Number_Kind,
	// The number of bits for a literal number type.
	number_bit_width: u32,
	// The encoding used for floating point values
	fp_encoding:      Fp_Encoding,
}

Ext_Inst_Type :: enum u32 {
	NONE = 0,
	GLSL_STD_450,
	OPENCL_STD,
	SPV_AMD_SHADER_EXPLICIT_VERTEX_PARAMETER,
	SPV_AMD_SHADER_TRINARY_MINMAX,
	SPV_AMD_GCN_SHADER,
	SPV_AMD_SHADER_BALLOT,
	DEBUGINFO,
	OPENCL_DEBUGINFO_100,
	NONSEMANTIC_CLSPVREFLECTION,
	NONSEMANTIC_SHADER_DEBUGINFO_100,
	NONSEMANTIC_VKSPREFLECTION,
	TOSA_001000_1,
	ARM_MOTION_ENGINE_100,

	// Multiple distinct extended instruction set types could return this
	// value, if they are prefixed with NonSemantic. and are otherwise
	// unrecognised
	NONSEMANTIC_UNKNOWN,
}

// An instruction parsed from a binary SPIR-V module.
Parsed_Instruction :: struct {
	// An array of words for this instruction, in native endianness.
	words:         [^]u32,
	// The number of words in this instruction.
	num_words:     u16,
	opcode:        u16,
	// The extended instruction type, if opcode is OpExtInst.  Otherwise
	// this is the "none" value.
	ext_inst_type: Ext_Inst_Type,
	// The type id, or 0 if this instruction doesn't have one.
	type_id:       u32,
	// The result id, or 0 if this instruction doesn't have one.
	result_id:     u32,
	// The array of parsed operands.
	operands:      [^]Parsed_Operand,
	num_operands:  u16,
}

// A pointer to a function that accepts a parsed SPIR-V header.
// The integer arguments are the 32-bit words from the header, as specified
// in SPIR-V 1.0 Section 2.3 Table 1.
// The function should return SPV_SUCCESS if parsing should continue.
Parsed_Header_Fn :: #type proc "c" (user_data: rawptr, endianness: Endianness, magic, version, generator, id_bound, reserved: u32) -> Result

// A pointer to a function that accepts a parsed SPIR-V instruction.
// The parsed_instruction value is transient: it may be overwritten
// or released immediately after the function has returned.  That also
// applies to the words array member of the parsed instruction.  The
// function should return SPV_SUCCESS if and only if parsing should
// continue.
Parsed_Instruction_Fn :: #type proc "c" (user_data: rawptr, #by_ptr parsed_instruction: Parsed_Instruction)

// A pointer to a function that accepts a log message from an optimizer.
Message_Consumer :: #type proc "c" (Message_Level, cstring, #by_ptr Position, cstring)
