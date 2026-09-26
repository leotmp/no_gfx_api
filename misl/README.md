# MISL (mini shader language)

The goal of misl is to be a dialect of odin that compiles to spirv (and fmag, see below). The main rationale behind the language is to reduce the mental overhead of having to deal with cpu/gpu code written in 2 different syntaxes and wildly different semantics. 

```odin
vec2 :: [2]f32 // scalar arrays promote to vectors, you can alias if you want
vec4 :: [4]f32 // aliasing also allows us to use constructors for vectors and matrices
mat4 :: matrix[4, 4]f32 // warning: matrices are not directly translated to odin, odin's matrices need to be flattened to [R*C]T if you plan on passing them to the shader

VS_Out :: struct {
	pos: [4]f32 | SV_Position, // vertex position in vertex shaders, fragment coords in fragment shaders
	uv:  [2]f32,
}

Shader_Data :: struct #align(16) { // alignment can be specified, but it's not required
	camera: mat4,
	texture: t32_2d, // builtin distinct u32 Texture2D id
	sampler: s32_2d, // builtin distinct u32 Sampler id
}

vs :: proc "vertex"(
	data: ^Shader_Data | SV_Data,
	vertex_id: u32 | SV_Vertex,
) -> (out: VS_Out) {
	out.pos = data.camera * vec4(0, 0, 0, 1)
	out.uv = vec2(0, 0)
	return out
}

fs :: proc "fragment"(
	data: ^Shader_Data | SV_Data,
	fsin: VS_Out, // from previous stage,
) -> (out: [4]f32 | SV_Target) {
	return sample(data.texture, data.sampler, fsin.uv)
}
```

# Non-exhaustive feature list
- `import`, collections
- `if` `switch` `#partial switch` `for` `for in slice` `for in A..<B`
- `@shared` memory, barriers
- `core:wave` intrinsics
- `enum` `bit_set`
- `#config` and compile time constants. `when` and `<#partial> which` (a comptime switch!!!)
- multiple returns
- untyped literals
- limited parapoly support, see below
- `using`
- `#align` and odin-style automatic padding.
- `core:debug` printf, assert, bounds checking (Note: assert and bounds checking requires no_gfx_api support, currently not implemented). 
- `debug.printf` supports `%v` compile time reflection. Pass anything to it (including enums and bitsets and structs) and see their named values in renderdoc.
- full debug info. Step through support in renderdoc (`mislc file.misl -debug -o:none`)
- Compute, fragment, vertex, and fmag kernels
- [FMAG](https://github.com/jangafx/FMAG) builtin syntax support via `core:fmag.exec` and `proc "fmag"()` kernels. See `misl/examples/fmag_pbr` for a demo (warning: `misl/examples` is not yet built to compile with no_gfx_api during this PR, you can however see the syntax and compile the shaders themselves)
- arbitrary amount of shaders in a single file. compile them all via `mislc file.misl -out:out_folder` or specific  ones via `-entry:name`
- Batteries included, a somewhat rich `core` library, including [Shader2Human](https://github.com/electronicarts/ShaderToHuman) support in `core:s2h`


# Important differences from odin
- All scalar types have their sizes specified. There is no `int` `bool`. You must use `b32` `i32` `u32` etc. `enum` and `bit_set` also require specifying the underlying types. 
- Scalar arrays `[N]S` where `N in 2..=4` and `S` is float, int, or bool promote to vectors. If you want to explicitly declare an array (for whatever reason that's ever useful), you can do `#array [3]f32`. 
- Currently only arrays that promote to vectors support array programming.
- `matrix[R, C]T` is not directly translatable to odin's matrix due to alignment requirements of the odin matrix. `(misl)matrix[R, C]T == (odin)[R*C]T`. When passing matrices from odin to misl, you can convert them via `intrinsics.flatten`
- There is no `package` declaration. A "module" in misl is a single file that you can `import "collection:file.misl"`
- The `core` libraries are built into the compiler. Modifying them requires recompiling it. 
- pointers, multi-pointers, and slices represent  device addresses. You cannot have pointers to local variables. If you want to pass a reference to a function, you can do so via `foo :: proc(#ref val: i32)` and `foo(&val)`
- `&` operator is a "reference operator". It is limited to foreach loops `for &val in slice`, and `#ref` parameters `fo(&val)`. 
- The default inferred types for literals are  `n := 1 // i32` `n := 1.0 // f32` `n := true // b32`.
- `string` support is limited. They can be iterated on and passed as arguments, but the arguments must be constant (ex: `proc($str: string) { for ch in str do ...}` ). This feature was mostly added to support nicer api for `core:s2h.misl`. String iteration is currently per-byte, not per-unicode rune (to be changed later)
- vector/matrix constructors are allowed, glsl-style, by aliasing the types `vec4 :: [4]f32`. The alias is currently required because the syntax doesn't support `([4]f32)(1, 2, 3, 4)`, it must be `alias(1, 2, 3, 4)`
- parapoly support is limited to compile time arguments in procedures `proc($N: i32)`

# Missing feature that nosl has (to be implemented later)
- no specialization constants support yet
- no `@io(n)`. Interfaces are positional. 
- the raytracing example seems to not pass the goldens




# Notes

- Odin source code was of great help in creating the parser
- https://github.com/francisthecat/hephaistos was helpful in implementing a nice architecture for the typechecking. Francis is very cool guy
- https://github.com/LeonardoTemperanza/no_gfx_api similar project. The original inspiration of writing a shading language for the API. The developer is also epic cool guy and 10x smarter than me
- lsp is entirely vibe coded. No clue how it works, i do not care how it works, but it works. A prebuilt vscode extension is available in `misl/tools/misl.vsix`. Forgive my sins.
