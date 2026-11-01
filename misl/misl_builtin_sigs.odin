package misl

// Declarative signature/doc table for MISL builtins (`Builtin_Proc`). This is
// pure metadata for tooling (LSP hover / signature help / inlay hints) — it
// does not participate in `check_builtin` and must stay in sync with it by
// hand. Nothing here changes checker behavior.

import "core:fmt"
import "core:strings"

// Coarse display class for a builtin parameter/result. Mirrors the shapes
// `check_builtin` actually accepts, simplified for docs.
Builtin_Type_Class :: enum {
	Concrete,            // exact type, see `type_name`
	Gen_Float,           // f32/f64 or vector thereof — displays "genType"
	Gen_Numeric,         // int/float gen — displays "genNumeric"
	Gen_Float_Scalar_Ok, // gen float that also accepts scalar broadcast — still "genType"
	Any,                 // printf value slots
	Texture,             // t8_2d/t16_2d/t32_2d resource id
	Sampler,             // s8/s16/s32 resource id
	Void,                // no value
}

Builtin_Param_Info :: struct {
	name:      string,
	class:     Builtin_Type_Class,
	type_name: string, // used when class == .Concrete
}

Builtin_Sig_Kind :: enum {
	Fixed,  // fixed arity, `params` lists every parameter
	Printf, // format string + variadic value args (printf/printfln)
}

Builtin_Sig_Info :: struct {
	kind:             Builtin_Sig_Kind,
	params:           []Builtin_Param_Info,
	result_class:     Builtin_Type_Class,
	result_type_name: string, // used when result_class == .Concrete
	docs:             string,
}

// Renders the display type for a class ("genType" / "genNumeric" / "any" /
// concrete `type_name` / texture/sampler handle name / "" for Void).
builtin_type_class_string :: proc(class: Builtin_Type_Class, type_name: string = "") -> string {
	switch class {
	case .Concrete:            return type_name
	case .Gen_Float:           return "genType"
	case .Gen_Float_Scalar_Ok: return "genType"
	case .Gen_Numeric:         return "genNumeric"
	case .Any:                 return "any"
	case .Texture:             return "t32_2d"
	case .Sampler:             return "s32"
	case .Void:                return ""
	}
	return ""
}

builtin_param_type_string :: proc(p: Builtin_Param_Info) -> string {
	return builtin_type_class_string(p.class, p.type_name)
}

// e.g. "sin(x: genType) -> genType". `name` overrides the display name
// (falls back to `builtin_names[id]` when empty — useful since GLSL/MISL
// names can diverge, e.g. `lerp` vs `mix`).
builtin_sig_label :: proc(id: Builtin_Proc, name: string = "") -> string {
	sig := builtin_sigs[id]
	proc_name := name
	if proc_name == "" {
		proc_name = builtin_names[id]
	}

	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, proc_name)
	strings.write_byte(&b, '(')
	for p, i in sig.params {
		if i > 0 do strings.write_string(&b, ", ")
		fmt.sbprintf(&b, "%s: %s", p.name, builtin_param_type_string(p))
	}
	if sig.kind == .Printf {
		if len(sig.params) > 0 do strings.write_string(&b, ", ")
		strings.write_string(&b, "args: ..any")
	}
	strings.write_byte(&b, ')')

	result_str := builtin_type_class_string(sig.result_class, sig.result_type_name)
	if result_str != "" {
		fmt.sbprintf(&b, " -> %s", result_str)
	}
	return strings.to_string(b)
}

// Hover-ready markdown: a ```misl fenced signature, plus a `---` + docs
// section when docs are present. Mirrors `hover_semantic_markdown`'s shape
// in the LSP so callers can drop this straight into a Hover response.
builtin_sig_docs_markdown :: proc(id: Builtin_Proc, name := "") -> string {
	label := builtin_sig_label(id, name)
	docs := builtin_sigs[id].docs
	if docs == "" {
		return fmt.tprintf("```misl\n%s\n```", label)
	}
	return fmt.tprintf("```misl\n%s\n```\n---\n%s", label, docs)
}

// --- shared parameter shapes (reused across many identical signatures) -----

p_unary_gen_float :: []Builtin_Param_Info{
	{name = "x", class = .Gen_Float},
}

p_xy_gen_float :: []Builtin_Param_Info{
	{name = "x", class = .Gen_Float},
	{name = "y", class = .Gen_Float},
}

p_xy_gen_numeric :: []Builtin_Param_Info{
	{name = "x", class = .Gen_Numeric},
	{name = "y", class = .Gen_Numeric},
}

p_format_only :: []Builtin_Param_Info{
	{name = "format", class = .Concrete, type_name = "string"},
}

// --- the table ---------------------------------------------------------------

_builtin_sigs_data :: [Builtin_Proc]Builtin_Sig_Info {
	.Invalid = {},

	// --- trig / unary gen float -> gen float --------------------------------
	.radians = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Converts x from degrees to radians, component-wise.",
	},
	.degrees = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Converts x from radians to degrees, component-wise.",
	},
	.sin = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Sine of x (radians), component-wise.",
	},
	.cos = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Cosine of x (radians), component-wise.",
	},
	.tan = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Tangent of x (radians), component-wise.",
	},
	.asin = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Arcsine of x, result in radians, component-wise.",
	},
	.acos = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Arccosine of x, result in radians, component-wise.",
	},
	.atan = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Arctangent of x, result in radians, component-wise.",
	},
	.atan2 = {
		kind = .Fixed, params = p_xy_gen_float, result_class = .Gen_Float,
		docs = "Two-argument arctangent of x/y (GLSL `atan(x, y)`), result in radians, component-wise.",
	},
	.sinh = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Hyperbolic sine of x, component-wise.",
	},
	.cosh = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Hyperbolic cosine of x, component-wise.",
	},
	.tanh = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Hyperbolic tangent of x, component-wise.",
	},
	.asinh = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Inverse hyperbolic sine of x, component-wise.",
	},
	.acosh = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Inverse hyperbolic cosine of x, component-wise.",
	},
	.atanh = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Inverse hyperbolic tangent of x, component-wise.",
	},

	// --- exponential / power -------------------------------------------------
	.pow = {
		kind = .Fixed, params = p_xy_gen_float, result_class = .Gen_Float,
		docs = "x raised to the power y, component-wise.",
	},
	.exp = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Natural exponential e^x, component-wise.",
	},
	.log = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Natural logarithm of x, component-wise.",
	},
	.exp2 = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Base-2 exponential 2^x, component-wise.",
	},
	.log2 = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Base-2 logarithm of x, component-wise.",
	},
	.sqrt = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Square root of x, component-wise.",
	},
	.isqrt = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Inverse square root of x (GLSL `inversesqrt`), component-wise.",
	},

	// --- basic math -----------------------------------------------------------
	.abs = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Absolute value of x, component-wise.",
	},
	.sign = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Sign of x: -1, 0, or 1, component-wise.",
	},
	.floor = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Largest integer value not greater than x, component-wise.",
	},
	.trunc = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Nearest integer towards zero from x, component-wise.",
	},
	.round = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Nearest integer to x, component-wise.",
	},
	.round_even = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Nearest integer to x, ties to even (GLSL `roundEven`), component-wise.",
	},
	.ceil = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Smallest integer value not less than x, component-wise.",
	},
	.fract = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Fractional part of x (x - floor(x)), component-wise.",
	},
	.mod = {
		kind = .Fixed, params = p_xy_gen_float, result_class = .Gen_Float,
		docs = "Floating-point modulus: x - y * floor(x / y), component-wise.",
	},
	.modf = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Splits x into integer and fractional parts; returns (whole, fract).",
	},
	.min = {
		kind = .Fixed, params = p_xy_gen_numeric, result_class = .Gen_Numeric,
		docs = "Smallest of 2 or more arguments, component-wise; scalar args broadcast.",
	},
	.max = {
		kind = .Fixed, params = p_xy_gen_numeric, result_class = .Gen_Numeric,
		docs = "Largest of 2 or more arguments, component-wise; scalar args broadcast.",
	},
	.clamp = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Gen_Numeric},
			{name = "min_val", class = .Gen_Numeric},
			{name = "max_val", class = .Gen_Numeric},
		},
		result_class = .Gen_Numeric,
		docs = "Clamps x to [min_val, max_val], component-wise; min_val/max_val may be scalar.",
	},
	.lerp = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "a", class = .Gen_Float_Scalar_Ok},
			{name = "b", class = .Gen_Float_Scalar_Ok},
			{name = "t", class = .Gen_Float_Scalar_Ok},
		},
		result_class = .Gen_Float,
		docs = "Linear interpolation between a and b by t (GLSL `mix`); t may be scalar.",
	},
	.step = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "edge", class = .Gen_Float_Scalar_Ok},
			{name = "x", class = .Gen_Float},
		},
		result_class = .Gen_Float,
		docs = "0 if x < edge, else 1, component-wise; edge may be scalar.",
	},
	.smoothstep = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "edge0", class = .Gen_Float_Scalar_Ok},
			{name = "edge1", class = .Gen_Float_Scalar_Ok},
			{name = "x", class = .Gen_Float},
		},
		result_class = .Gen_Float,
		docs = "Smooth Hermite interpolation between edge0 and edge1 at x; edges may be scalar.",
	},
	.is_nan = {
		kind = .Fixed, params = p_unary_gen_float,
		result_class = .Concrete, result_type_name = "genBType",
		docs = "Component-wise test for NaN; result is a boolean genType.",
	},
	.is_inf = {
		kind = .Fixed, params = p_unary_gen_float,
		result_class = .Concrete, result_type_name = "genBType",
		docs = "Component-wise test for +/-Inf; result is a boolean genType.",
	},
	.f32_from_u32_bits = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "u32/uvec"}},
		result_class = .Concrete, result_type_name = "f32/vec",
		docs = "Reinterpret IEEE-754 bits: u32/uvec → f32/vec (GLSL `uintBitsToFloat`). Used by `core:fmag` to decode immediates vs register indices.",
	},
	.u32_from_f32_bits = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "f32/vec"}},
		result_class = .Concrete, result_type_name = "u32/uvec",
		docs = "Reinterpret IEEE-754 bits: f32/vec → u32/uvec (GLSL `floatBitsToUint`).",
	},
	.fma = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "a", class = .Gen_Float},
			{name = "b", class = .Gen_Float},
			{name = "c", class = .Gen_Float},
		},
		result_class = .Gen_Float,
		docs = "Fused multiply-add: a * b + c, component-wise, computed with a single rounding.",
	},
	.frexp = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Splits x into a normalized significand and power-of-two exponent; returns (exp, significand).",
	},
	.ldexp = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Gen_Float},
			{name = "exp", class = .Gen_Numeric},
		},
		result_class = .Gen_Float,
		docs = "Builds a floating-point value from significand x and integer power-of-two exponent.",
	},

	// --- geometry ---------------------------------------------------------------
	.mag = {
		kind = .Fixed, params = p_unary_gen_float,
		result_class = .Concrete, result_type_name = "f32",
		docs = "Euclidean length of vector x (GLSL `length`).",
	},
	.dist = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "p0", class = .Gen_Float},
			{name = "p1", class = .Gen_Float},
		},
		result_class = .Concrete, result_type_name = "f32",
		docs = "Euclidean distance between points p0 and p1 (GLSL `distance`).",
	},
	.dot = {
		kind = .Fixed, params = p_xy_gen_float,
		result_class = .Concrete, result_type_name = "scalar",
		docs = "Dot product of x and y; result is the scalar element type of x/y.",
	},
	.cross = {
		kind = .Fixed, params = p_xy_gen_float, result_class = .Gen_Float,
		docs = "3-component cross product of x and y; both must be [3]genType.",
	},
	.normalize = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Unit-length vector in the direction of x; x must be a vector.",
	},
	.facefoward = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "N", class = .Gen_Float},
			{name = "I", class = .Gen_Float},
			{name = "Nref", class = .Gen_Float},
		},
		result_class = .Gen_Float,
		docs = "Returns N if dot(Nref, I) < 0, else -N (GLSL `faceforward`).",
	},
	.reflect = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "I", class = .Gen_Float},
			{name = "N", class = .Gen_Float},
		},
		result_class = .Gen_Float,
		docs = "Reflects incident vector I about normal N: I - 2 * dot(N, I) * N.",
	},
	.refract = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "I", class = .Gen_Float},
			{name = "N", class = .Gen_Float},
			{name = "eta", class = .Concrete, type_name = "f32"},
		},
		result_class = .Gen_Float,
		docs = "Refracts incident vector I about normal N with ratio of indices of refraction eta.",
	},

	// --- matrix -----------------------------------------------------------------
	.matrix_comp_mult = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "matrix"},
			{name = "y", class = .Concrete, type_name = "matrix"},
		},
		result_class = .Concrete, result_type_name = "matrix",
		docs = "Component-wise (Hadamard) product of two matrices of the same shape.",
	},
	.outer_product = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "c", class = .Gen_Float},
			{name = "r", class = .Gen_Float},
		},
		result_class = .Concrete, result_type_name = "matrix",
		docs = "Outer product of column vector c and row vector r, producing a matrix.",
	},
	.transpose = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "m", class = .Concrete, type_name = "matrix"}},
		result_class = .Concrete, result_type_name = "matrix",
		docs = "Transpose of matrix m (rows and columns swapped).",
	},
	.determinant = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "m", class = .Concrete, type_name = "matrix"}},
		result_class = .Concrete, result_type_name = "scalar",
		docs = "Determinant of square matrix m.",
	},
	.inverse = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "m", class = .Concrete, type_name = "matrix"}},
		result_class = .Concrete, result_type_name = "matrix",
		docs = "Inverse of square matrix m.",
	},

	.dFdx = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Partial derivative of x in screen x (fragment only). GLSL `dFdx`.",
	},
	.dFdy = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "Partial derivative of x in screen y (fragment only). GLSL `dFdy`.",
	},
	.fwidth = {
		kind = .Fixed, params = p_unary_gen_float, result_class = .Gen_Float,
		docs = "abs(dFdx(x)) + abs(dFdy(x)) (fragment only).",
	},

	// --- textures / resources -----------------------------------------------
	.sample = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "tex", class = .Texture},
			{name = "samp", class = .Sampler},
			{name = "coord", class = .Concrete, type_name = "coord"},
			{name = "lod_or_ref", class = .Concrete, type_name = "f32?"},
		},
		result_class = .Concrete, result_type_name = "[4]f32 | f32",
		docs = "Bindless sample. Color: sample(tex, s32, coord[, lod]) -> [4]f32. Compare: sample(tex, s32_cmp, coord, ref[, lod]) -> f32. Coord rank follows the view (t*_1d f32, t*_2d [2]f32, t*_3d/t*_cube/t*_2d_array [3]f32, t*_cube_array [4]f32). Sampler may be s8/s16/s32 or s*_cmp. No 3D comparison. Compare+lod is only 1D, 2D, and cube.",
	},
	.load = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "handle", class = .Concrete, type_name = "t8_2d/t16_2d/t32_2d | rw8_2d/rw16_2d/rw32_2d"},
			{name = "coord", class = .Concrete, type_name = "[2]i32"},
		},
		result_class = .Concrete, result_type_name = "[4]f32",
		docs = "Fetches a texel at integer coord; sampled textures accept an optional trailing mip: i32. Cube views cannot load.",
	},
	.store = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "handle", class = .Concrete, type_name = "rw8_2d/rw16_2d/rw32_2d"},
			{name = "coord", class = .Concrete, type_name = "[2]i32"},
			{name = "color", class = .Concrete, type_name = "[4]f32"},
		},
		result_class = .Void,
		docs = "Writes color to the read-write texture handle at integer coord (rank follows the rw view).",
	},
	.dim = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "handle", class = .Concrete, type_name = "t8_2d/t16_2d/t32_2d | rw8_2d/rw16_2d/rw32_2d"},
		},
		result_class = .Concrete, result_type_name = "[2]i32",
		docs = "Returns the pixel dimensions of a texture or rw handle (i32 / [2]i32 / [3]i32 by view).",
	},
	.rayquery_init = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "desc", class = .Concrete, type_name = "Ray_Desc"},
			{name = "bvh", class = .Concrete, type_name = "bvh32"},
		},
		result_class = .Concrete, result_type_name = "Ray_Query",
		docs = "Declares and initializes a ray query against bindless BVH `bvh` (GLSL `rayQueryInitializeEXT`). Assign into a Ray_Query local.",
	},
	.rayquery_proceed = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "rq", class = .Concrete, type_name = "Ray_Query"}},
		result_class = .Concrete, result_type_name = "b32",
		docs = "Advances the ray query (GLSL `rayQueryProceedEXT`). Returns whether a candidate is available.",
	},
	.rayquery_result = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "rq", class = .Concrete, type_name = "Ray_Query"}},
		result_class = .Concrete, result_type_name = "Ray_Result",
		docs = "Committed intersection for `rq` (GLSL accessors with committed=true).",
	},
	.rayquery_candidate = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "rq", class = .Concrete, type_name = "Ray_Query"}},
		result_class = .Concrete, result_type_name = "Ray_Result",
		docs = "Candidate intersection for `rq` (GLSL accessors with committed=false).",
	},
	.rayquery_accept = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "rq", class = .Concrete, type_name = "Ray_Query"}},
		result_class = .Void,
		docs = "Confirms the current candidate intersection (GLSL `rayQueryConfirmIntersectionEXT`).",
	},

	// --- bit_set / slice ----------------------------------------------------
	.card = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "s", class = .Concrete, type_name = "bit_set"}},
		result_class = .Concrete, result_type_name = "i32",
		docs = "Number of elements (population count) in bit_set s.",
	},
	.len = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "s", class = .Concrete, type_name = "[]T | [N]T"}},
		result_class = .Concrete, result_type_name = "i64",
		docs = "Number of elements in slice or array s.",
	},

	// --- debug printing -------------------------------------------------------
	.printf = {
		kind = .Printf, params = p_format_only, result_class = .Void,
		docs = "Formats and prints args using format; each `%v` (compact) or `%#v` (pretty) consumes one argument.",
	},
	.printfln = {
		kind = .Printf, params = p_format_only, result_class = .Void,
		docs = "Like printf, but appends a trailing newline; supports `%v` (compact) and `%#v` (pretty).",
	},
	.assert = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "cond", class = .Concrete, type_name = "bool"},
			{name = "message", class = .Concrete, type_name = "string"},
		},
		result_class = .Void,
		docs = "If cond is false, records a GPU assert (kind User). Optional second argument is a compile-time string. #+feature disable-asserts still evaluates cond.",
	},
	.panic = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "message", class = .Concrete, type_name = "string"},
		},
		result_class = .Void,
		docs = "Always records a GPU assert (kind Panic). Message must be a compile-time string. Equivalent to debug.assert(false, message). #+feature disable-asserts emits nothing.",
	},
	.fmag_exec = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "code", class = .Concrete, type_name = "[][4]u32"},
		},
		result_class = .Void,
		docs = "Packs remaining f32 / [2/3/4]f32 args into the FMAG register file, runs bytecode, and unpacks results from the typed destination. GLSL/SPIR-V only.",
	},

	// --- compute sync ---------------------------------------------------------
	.barrier = {
		kind = .Fixed, result_class = .Void,
		docs = "Synchronizes execution of all invocations in the workgroup (compute only).",
	},
	.memory_barrier = {
		kind = .Fixed, result_class = .Void,
		docs = "Orders memory accesses to all storage classes for this invocation (compute only).",
	},
	.memory_barrier_shared = {
		kind = .Fixed, result_class = .Void,
		docs = "Orders memory accesses to workgroup shared memory for this invocation (compute only).",
	},
	.memory_barrier_buffer = {
		kind = .Fixed, result_class = .Void,
		docs = "Orders memory accesses to buffer memory for this invocation (compute only).",
	},
	.memory_barrier_image = {
		kind = .Fixed, result_class = .Void,
		docs = "Orders memory accesses to image memory for this invocation (compute only).",
	},
	.group_memory_barrier = {
		kind = .Fixed, result_class = .Void,
		docs = "Orders memory accesses to all storage classes visible to the workgroup (compute only).",
	},

	.wave_is_first = {
		kind = .Fixed, result_class = .Concrete, result_type_name = "b32",
		docs = "True on the active non-helper lane with the smallest index (import core:wave).",
	},
	.wave_lane_count = {
		kind = .Fixed, result_class = .Concrete, result_type_name = "u32",
		docs = "Runtime subgroup size (4–128), including inactive and helper lanes.",
	},
	.wave_lane_id = {
		kind = .Fixed, result_class = .Concrete, result_type_name = "u32",
		docs = "Index of this lane in the current wave.",
	},
	.wave_any = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "p", class = .Concrete, type_name = "b32"}},
		result_class = .Concrete, result_type_name = "b32",
		docs = "True if p is true in any active non-helper lane.",
	},
	.wave_all = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "p", class = .Concrete, type_name = "b32"}},
		result_class = .Concrete, result_type_name = "b32",
		docs = "True if p is true in every active non-helper lane.",
	},
	.wave_ballot = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "p", class = .Concrete, type_name = "b32"}},
		result_class = .Concrete, result_type_name = "[4]u32",
		docs = "Bitmask of p across active non-helper lanes (uint4 / uvec4).",
	},
	.wave_broadcast_first = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "T"}},
		result_class = .Concrete, result_type_name = "T",
		docs = "Value of x from the first active non-helper lane.",
	},
	.wave_read = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "T"},
			{name = "lane", class = .Concrete, type_name = "u32"},
		},
		result_class = .Concrete, result_type_name = "T",
		docs = "Value of x from lane (Shuffle; non-uniform lane is a shuffle).",
	},
	.wave_all_equal = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "T"}},
		result_class = .Concrete, result_type_name = "b32",
		docs = "True (or per-component [N]b32) if x is the same in every active non-helper lane.",
	},
	.wave_bit_count = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "p", class = .Concrete, type_name = "b32"}},
		result_class = .Concrete, result_type_name = "u32",
		docs = "Number of active non-helper lanes where p is true.",
	},
	.wave_sum = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "T"}},
		result_class = .Concrete, result_type_name = "T",
		docs = "Sum of x across active non-helper lanes.",
	},
	.wave_product = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "T"}},
		result_class = .Concrete, result_type_name = "T",
		docs = "Product of x across active non-helper lanes.",
	},
	.wave_min = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "T"}},
		result_class = .Concrete, result_type_name = "T",
		docs = "Minimum of x across active non-helper lanes.",
	},
	.wave_max = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "T"}},
		result_class = .Concrete, result_type_name = "T",
		docs = "Maximum of x across active non-helper lanes.",
	},
	.wave_bit_and = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "T"}},
		result_class = .Concrete, result_type_name = "T",
		docs = "Bitwise AND of integer x across active non-helper lanes.",
	},
	.wave_bit_or = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "T"}},
		result_class = .Concrete, result_type_name = "T",
		docs = "Bitwise OR of integer x across active non-helper lanes.",
	},
	.wave_bit_xor = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "T"}},
		result_class = .Concrete, result_type_name = "T",
		docs = "Bitwise XOR of integer x across active non-helper lanes.",
	},
	.wave_prefix_sum = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "T"}},
		result_class = .Concrete, result_type_name = "T",
		docs = "Exclusive prefix sum of x (first active lane gets 0).",
	},
	.wave_prefix_product = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "T"}},
		result_class = .Concrete, result_type_name = "T",
		docs = "Exclusive prefix product of x (first active lane gets 1).",
	},
	.wave_prefix_bit_count = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "p", class = .Concrete, type_name = "b32"}},
		result_class = .Concrete, result_type_name = "u32",
		docs = "Exclusive prefix count of true p (first active lane gets 0).",
	},
	.wave_quad_x = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "T"}},
		result_class = .Concrete, result_type_name = "T",
		docs = "Value of x from the other lane in this quad along X (fragment and compute).",
	},
	.wave_quad_y = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "T"}},
		result_class = .Concrete, result_type_name = "T",
		docs = "Value of x from the other lane in this quad along Y (fragment and compute).",
	},
	.wave_quad_diag = {
		kind = .Fixed,
		params = []Builtin_Param_Info{{name = "x", class = .Concrete, type_name = "T"}},
		result_class = .Concrete, result_type_name = "T",
		docs = "Value of x from the diagonally opposite lane in this quad (fragment and compute).",
	},
	.wave_quad_read = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "T"},
			{name = "lane", class = .Concrete, type_name = "u32"},
		},
		result_class = .Concrete, result_type_name = "T",
		docs = "Value of x from quad lane 0..3 (fragment and compute).",
	},
	.wave_shuffle_xor = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "T"},
			{name = "mask", class = .Concrete, type_name = "u32"},
		},
		result_class = .Concrete, result_type_name = "T",
		docs = "Value of x from lane_id XOR mask.",
	},
	.wave_shuffle_up = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "T"},
			{name = "delta", class = .Concrete, type_name = "u32"},
		},
		result_class = .Concrete, result_type_name = "T",
		docs = "Value of x from lane_id - delta.",
	},
	.wave_shuffle_down = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "T"},
			{name = "delta", class = .Concrete, type_name = "u32"},
		},
		result_class = .Concrete, result_type_name = "T",
		docs = "Value of x from lane_id + delta.",
	},
	.wave_clustered_sum = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "T"},
			{name = "cluster", class = .Concrete, type_name = "u32"},
		},
		result_class = .Concrete, result_type_name = "T",
		docs = "Sum of x inside clusters of compile-time power-of-two size.",
	},
	.wave_clustered_product = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "T"},
			{name = "cluster", class = .Concrete, type_name = "u32"},
		},
		result_class = .Concrete, result_type_name = "T",
		docs = "Product of x inside clusters of compile-time power-of-two size.",
	},
	.wave_clustered_min = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "T"},
			{name = "cluster", class = .Concrete, type_name = "u32"},
		},
		result_class = .Concrete, result_type_name = "T",
		docs = "Minimum of x inside clusters of compile-time power-of-two size.",
	},
	.wave_clustered_max = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "T"},
			{name = "cluster", class = .Concrete, type_name = "u32"},
		},
		result_class = .Concrete, result_type_name = "T",
		docs = "Maximum of x inside clusters of compile-time power-of-two size.",
	},
	.wave_clustered_bit_and = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "T"},
			{name = "cluster", class = .Concrete, type_name = "u32"},
		},
		result_class = .Concrete, result_type_name = "T",
		docs = "Bitwise AND of integer x inside clusters of compile-time power-of-two size.",
	},
	.wave_clustered_bit_or = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "T"},
			{name = "cluster", class = .Concrete, type_name = "u32"},
		},
		result_class = .Concrete, result_type_name = "T",
		docs = "Bitwise OR of integer x inside clusters of compile-time power-of-two size.",
	},
	.wave_clustered_bit_xor = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "T"},
			{name = "cluster", class = .Concrete, type_name = "u32"},
		},
		result_class = .Concrete, result_type_name = "T",
		docs = "Bitwise XOR of integer x inside clusters of compile-time power-of-two size.",
	},
	.wave_rotate = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "T"},
			{name = "delta", class = .Concrete, type_name = "u32"},
		},
		result_class = .Concrete, result_type_name = "T",
		docs = "Rotate x by delta lanes (SPV_KHR_subgroup_rotate).",
	},
	.wave_clustered_rotate = {
		kind = .Fixed,
		params = []Builtin_Param_Info{
			{name = "x", class = .Concrete, type_name = "T"},
			{name = "delta", class = .Concrete, type_name = "u32"},
			{name = "cluster", class = .Concrete, type_name = "u32"},
		},
		result_class = .Concrete, result_type_name = "T",
		docs = "Clustered rotate of x (compile-time power-of-two cluster).",
	},
}

@(rodata)
builtin_sigs := _builtin_sigs_data
