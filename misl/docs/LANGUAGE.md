# MISL Language Overview

**MISL** (Minimal Shader Language) is a small, Odin-flavoured shading language. It is designed for GPU programs: vertex, fragment, and compute shaders. GPU SPIR-V comes from the **direct backend** (`compile_entry` with `Target.formats = {.spirv}` / `mislc -target:spirv`). There is no GLSL text backend and no glslang SPIR-V path. `build ms` / `mst` emit Direct SPIR-V + `.spvasm` (and FMAG where present).

This document is an introduction to MISL. You are assumed to know basic programming concepts (variables, statements, types) and the idea of a graphics pipeline. Familiarity with [Odin](https://odin-lang.org/docs/overview/) helps, because MISL deliberately reuses much of Odin’s declaration and expression syntax — but it is **not** a full Odin implementation. Many host-language features are omitted on purpose.

Status tags used below:

- **[core]** — part of the language surface; intended for production shaders such as `data/shader/main.misl`
- **[planned]** — designed, not necessarily implemented yet
- **[out]** — will not be implemented (reject at parse or never add)

---

## Introduction

A MISL **module** is a single `.misl` file. Modules contain:

- Type aliases, structs, enums
- Helper procedures
- Shader **entry points** (`proc "vertex"`, `proc "fragment"`, …)

There is no `package` clause and no host `main`. Execution on the GPU starts at an entry the host selects by name when compiling SPIR-V.

Example sketch:

```misl
vec2 :: [2]f32
vec4 :: [4]f32
mat4 :: matrix[4, 4]f32

VS_Out :: struct {
	pos: [4]f32 | SV_Position,
	uv:  [2]f32,
}

Shader_Data :: struct #align(16) {
	camera: mat4,
}

vs :: proc "vertex"(
	data: ^Shader_Data | SV_Data,
	vertex_id: u32 | SV_Vertex,
) -> (out: VS_Out) {
	out.pos = data.camera * vec4(0, 0, 0, 1)
	out.uv = vec2(0, 0)
	return out
}
```

---

## Design principles

1. **Odin-like surface** — `::`, `:=`, `proc`, `struct`, arrays, swizzles feel like Odin.
2. **GPU-first** — no heap, no maps, no host FFI.
3. **Explicit shader ABI** — stages and system values (`SV_*`) are part of the type of parameters and results.
4. **Small grammar** — features not on the MISL surface are left out of the lexer/parser so the compiler stays maintainable.
5. **Scalar-friendly data** — structs with `#align`, multipointers for device buffers (BDA), real slices `[]T`, fixed vectors/matrices for math.

---

## Comments

Comments may appear anywhere outside a string literal.

Single-line comments begin with `//`:

```misl
// A comment
x: f32 // documentation on a declaration
```

Nested block comments begin with `/*` and end with `*/` **[core]** (nesting allowed):

```misl
/*
	outer
	/* nested */
*/
```

---

## Declarations

MISL uses the same declaration aesthetic as Odin. There are only **two** declaration operators:

| Operator | Role |
|----------|------|
| `:` | Type ascription (“of type”) / constant marker when doubled |
| `=` | Initialize / assign a value |

Written forms like `::` and `:=` are **not** separate operators — each is two of the above in a row:

| Written | Tokens | Meaning |
|---------|--------|---------|
| `name: Type` | `:` | Declare with an explicit type |
| `name: Type = value` | `:` then `=` | Typed variable (or field) with initializer |
| `name := value` | `:` then `=` | Variable; type inferred from `value` |
| `name :: value` | `:` then `:` | Constant; type inferred from `value` |
| `name: Type : value` | `:` then `:` | Constant with an explicit type (no inference of the entity’s type) |

### Constant / type bindings **[core]**

```misl
PI :: 3.14159265          // constant — `:` `:`
vec3 :: [3]f32            // type alias
mat4 :: matrix[4, 4]f32

// Same idea with an explicit type on the constant (no inference of the entity type):
fn: proc() : proc() {}
```

`Name :: Type` introduces a type alias. `Name :: proc ...` or `Name :: value` introduces a constant entity (procedure or compile-time value).

### Variables **[core]**

```misl
x: f32           // `:` only
y: f32 = 1.0     // `:` then `=`
z := 1.0         // `:` then `=` — infer type from initializer (after untyped defaults: f32)
```

Declarations must be unique within a scope.

### Declaration order **[core]**

Only **constant declarations** (`::` — types, procedures, value constants, pipelines) are unordered: a `::` name may be used before its textual definition in the same scope (module or local). Mutable declarations (`:=` / `: T`) stay source-ordered.

The compiler collects `::` entities first, then resolves types/signatures and bodies. Type and constant-initializer graphs must be **acyclic** (hard error). **Procedure call graphs must also be acyclic** (hard error): SPIR-V cannot express recursion, so direct, mutual, or multi-hop recursive calls (`foo → bar → baz → foo`) are rejected in the checker. Unordered `::` still allows procedures to *refer* to each other textually (signatures resolve first); only *calling* in a cycle is forbidden. Nested symbols are hoisted because SPIR-V has no nested functions or nested type definitions.

### Blank identifier `_` **[core]**

`_` is the **dummy** (blank) identifier, as in Odin. It discards a value and does not bind a usable name. It may appear multiple times in the same scope.

```misl
_, y := multi_value()     // ignore first result
for _ in 0..<n { }        // ignore iteration value
x, _ = a, b               // assign only x
```

`_` is not a readable variable: it cannot appear as an expression operand (except as a discard target on the left of `=` / `:=` / in patterns that ignore a value).

### Assignment **[core]**

```misl
x = 637
out.rgb *= mask.r
i += 1
```

These are equivalent when the type is inferred:

```misl
x: f32 = 123
x := 123       // `:` `=`
```

---

## Literals

### Numbers **[core]**

Integer and floating-point literals work like Odin:

```misl
0
42
1.0
2.2
1.0e-10
```

Underscores in numbers **[core]**: `1_000_000`.

Binary prefix **[core]**: `0b1010`. Hex prefix **[core]**: `0x` / `0X` with digits `0-9` `a-f` `A-F` (and `_` separators). IEEE hex floats **[core]**: `0h` / `0H` plus 4, 8, or 16 hex digits (`f16` / `f32` / `f64` bit patterns), same as Odin (`0h3F800000` is `1.0`).

There are **no** imaginary (`2i`) literals **[out]**. Character literals (`'A'`) are untyped **runes**. Quoted `"…"` / raw `` `…` `` literals are untyped **strings** (compile-time only — see below).

### Untyped literals **[core]**

Numeric literals are **untyped** until context gives them a concrete type (same idea as Odin).

```misl
a := 1        // defaults to i32 when no stronger context
b := 1.0      // defaults to f32
c: f32 = 1    // context forces f32
d := 1 + 2.0  // untyped int promotes with float → f32
```

Default types when no context remains:

| Untyped kind | Default |
|--------------|---------|
| integer      | `i32`   |
| float        | `f32`   |
| boolean      | `b32` |
| rune         | `rune` |
| string       | `string` (compile-time only) |

An untyped integer may convert to any numeric type. An untyped float may convert to floating types. After an expression is typed, all untyped subexpressions in that tree are updated to the final type (so leaf literals do not stay “untyped” forever).

When a constant expression is given a concrete numeric type (`x := 1` defaulting to `i32`, `x: T = …`, `T(…)`, `cast(T)`, arguments, returns), its folded value must **fit** that type. Integers use the closed range of the destination (`i32` is `-2147483648…2147483647`). Explicit casts truncate finite floats toward zero (`cast(i32)1.5` is `1`) and then apply the same range check. Floats may round (IEEE 754); only overflow to infinity is an error (`1.0e40` does not fit in `f32`). Untyped named constants (`A :: 4294967295`) stay unlimited until a typed use.

Folded numeric constants lower to SPIR-V `OpConstant` / `OpConstantComposite` of the destination type (not GLSL suffix tokens or constructor wraps).

```misl
i := 4294967295 + 100 // error: does not fit in i32
i: f32 = 4294967295 + 100 // ok (finite f32, with rounding)
```

### Booleans **[core]**

```misl
flag := true   // untyped bool → b32 by default
flag = false
```

The concrete boolean scalar is `b32`. A `bool` type alias is **not** registered (use `b32`).

---

## Types **[core]**

### Scalars

Booleans, integers, and floats are the **scalar** kinds.

| Subcategory | Types |
|-------------|--------|
| Boolean | `b32` (and smaller widths `b8` / `b16` where registered) |
| Integer | `i8`, `u8`, `i16`, `u16`, `i32`, `u32`, `i64`, `u64` |
| Rune | `rune` — distinctly typed 32-bit Unicode scalar (GLSL `uint`); not interchangeable with `u32` |
| Float | `f16`, `f32`, `f64` |
| Complex | `complex32`, `complex64`, `complex128` |
| Quaternion | `quaternion64`, `quaternion128`, `quaternion256` |

Complex and quaternion are scalar kinds for the purposes of **vectors** (`[2..4]` of these are vectors) and numeric conversion rules (same spirit as Odin). Untyped complex / untyped quaternion literals (e.g. imaginary suffix `2i`) are **[planned]** — not checked yet.

### Vectors vs arrays

`[N]T` syntax is shared, but **vectors and arrays are distinct types**:

| Kind | Rule |
|------|------|
| **Vector** | `[2]S`, `[3]S`, or `[4]S` where `S` is a **scalar** — swizzles, broadcast, and vector arithmetic apply |
| **Array** | Everything else with `[N]T` — e.g. `[5]f32`, `[4]vec2` (element is not a scalar), `[1]i32`, … |

To force a length-2..4 scalar sequence to be an **array** instead of a vector, use the `#array` tag on the type:

```misl
v: [2]f32              // vector
a: #array [2]f32       // array of two f32 — not a vector
a2: #array [4]u32      // array, not a uint vector
```

Named constant arrays (`MINI_FONT :: [192]u32{…}`) are compile-time values with **scalar** elements only (bool/int/float/rune). `[2|3|4]f32` and friends are vectors, not arrays — use `[1]T` or `N >= 5`, or `#array`. GLSL emit is a scoped `const T name[N] = T[](...)` (file-scope for module `::`, function-local for proc-local `::`). Uses of the name are not inlined.

```misl
vec2 :: [2]f32         // vector alias (common in shaders)
vec3 :: [3]f32
vec4 :: [4]f32
mat4 :: matrix[4, 4]f32
```

Resource ids are **builtin distinct integer scalars** **[core]** (not `u32` aliases, not user `distinct`). They are named in [`core/builtin.misl`](../core/builtin.misl) via `#intrinsic`. 2D views use the `_2d` suffix:

| Kind | Types |
|------|--------|
| Texture | `t8_2d`, `t16_2d`, `t32_2d`; view suffixes `_1d`, `_3d`, `_cube`, `_1d_array`, `_2d_array`, `_cube_array` at each width |
| Sampler | `s8`, `s16`, `s32`; comparison `s8_cmp`, `s16_cmp`, `s32_cmp` |
| RW texture | `rw8_2d`, `rw16_2d`, `rw32_2d`; same view suffixes as textures at each width |
| BVH | `bvh32` (bindless acceleration-structure id; same compiler-type stack as `t32_2d`) |

Untyped integers convert when context uniquely determines the kind (`tex: t32_2d = 0`, `sample(tex, 0, uv)`). Ambiguous `load`/`dim` handles require an explicit cast (`load(t32_2d(0), …)`). Typed `u32` does not convert. Builtins dispatch on kind (`load(t*)` vs `load(rw*)`). `bvh32` converts the same way (`rayquery_init(desc, 0)`).

`Ray_Query` is an opaque GLSL `rayQueryEXT` handle: locals and procedure parameters only — not struct, array, or slice fields. `Ray_Desc` and `Ray_Result` are `@builtin` structs in `core:builtin`. `Ray_Result.object_to_world` / `world_to_object` are `matrix[3, 4]f32` (GLSL `mat4x3`); helpers assign `rayQueryGetIntersection*EXT` directly, matching no_gfx NOSL. Ops (GLSL/SPIR-V only): `rayquery_init(desc, bvh)` must initialize a local (`rq := rayquery_init(...)`; GLSL cannot assign `rayQueryEXT`), `rayquery_proceed`, `rayquery_result` / `rayquery_candidate` (return `Ray_Result`), optional `rayquery_accept`. `-compat:no_gfx` places the BVH heap at `set=3,binding=0` and only emits it when ray query is used.

Host descriptors stay `gpu.t8` / `gpu.t16` / `gpu.t32` (and `gpu.t*_2d` aliases), `gpu.s8` / `gpu.s16` / `gpu.s32`, `gpu.rw8` / `gpu.rw16` / `gpu.rw32` (and `gpu.rw*_2d` aliases). Shader 2D views are `t32_2d` / `rw32_2d` (no unsuffixed `t32` / `rw32`). View types (`t16_cube`, `rw8_3d`, `s8_cmp`, …) are MISL-only; the host field is the matching-width index. Shader view types pick GLSL sampler/image type and the coord rank of `sample` / `load` / `store` / `dim`. Comparison `sample(tex, s*_cmp, coord, ref[, lod])` returns `f32`. Sampled cube views cannot `load` (no `texelFetch` on cube). Comparison + explicit lod is only 1D, 2D, and cube. `dim` matches Vulkan `textureSize` / `imageSize` (cube is `[2]i32`; cube-array is `[3]i32`).

### Other types

| Kind | Form |
|------|------|
| Matrix | `matrix[R, C]T` — element type `f32` or `f64` only (GLSL `mat*` / `dmat*`) |
| Pointer | `^T` — device pointer to one `T` (BDA) |
| Multipointer | `[^]T` — BDA / contiguous device pointer |
| Slice | `[]T` — real slice (`ptr` + `len`) |
| Struct | `struct { ... }` / `struct #align(N) { ... }` |
| Enum | `enum Underlying { ... }` — underlying type required |
| Bit set | `bit_set[E; Underlying]` — underlying type required **[core]** |
| Procedure | `proc(...) -> ...`, including stage procs |

### Zero values **[core]**

Unset locals / fields are treated as zero values of their type where the backend allows (same spirit as Odin / GLSL).

### Compile-time `string` **[core]**

`string` is **not** a runtime type. Legal uses:

- Named constants: `MSG :: "hello"` / `MSG: string : "hello"`
- Arguments to constant parapoly `$str: string`
- Constant format/messages for `debug.printf` / `assert` / `panic`

Illegal: `s: string = "hello"`, `s := "hello"`, `proc(s: string)` without `$`, string results, mutable locals, or struct fields of `string`.

`len("hello")` is the **byte** length (`i64`, same as arrays) and folds when the operand is a constant string (including `$str`). `s[i]` yields that byte as `u8`. A constant index folds; an out-of-range constant index is an error. A runtime index is a value (not a copy of the string’s constant mode). The empty string `""` has `len` 0; indexing it is out of range.

GLSL lowering interns every **used** compile-time string (literals, named constants, `$str`, printf/assert messages) once as a **file-scope** `const uint8_t` array, with a `// "original"` comment immediately above it. Identical decoded bytes share one array. The empty string is **not** interned (no dummy byte). Indexing `$str` / a named string constant uses that global; `len` still folds to an integer.

### Runes **[core]**

Typed `rune` is a distinctly typed unsigned 32-bit scalar (same size as `u32`, not the same type). Untyped rune literals (`'A'`) convert to `rune`, and to `u8` / `u16` / `u32` when the UTF-8 encoding fits. An untyped integer converts to `rune` when it is in `0…utf8.MAX_RUNE`. Rune `+` / `-` integer yields `rune`. Typed `i32`/`u32` need an explicit `rune(x)`; typed `rune` needs `u32(ch)` to become an integer.

### What is not supported **[out]**

`cstring`, `any`, `typeid`, `rawptr`, maps, dynamic arrays, unions, and **runtime** string variables. Device pointers (`^T` / `[^]T` / `[]T`) are not stack pointers — unary `&expr` is illegal (`misl does not support stack pointers`). Use `for &elem in …` for mutable range aliases.

---

## Type conversion

### Implicit conversion **[core]**

Only for untyped literals (and untyped expression results) into a concrete numeric context. Typed `i32` does **not** silently become `f32`.

### `cast` **[core]**

```misl
src_size := cast(vec2)dim(sprite.texture)
p := cast(^Sprite)mp          // [^]T → ^T (same element type)
```

### Type-call constructors **[core]**

Calling a type constructs a value of that type (vector/matrix sugar):

```misl
vec2(1, 2)
vec4(pos, 0, 1)          // pad constructor
mat4(c, s, 0, 0, ...)
```

### `auto_cast` **[core]**

Like Odin, `auto_cast` casts an expression to the destination type inferred from context (assignment, parameter, etc.) when the conversion is allowed:

```misl
x: f32 = 123
y: i32 = auto_cast x
```

Unlike untyped literal conversion, `auto_cast` applies to **already typed** values. Prefer explicit `cast(T)` in most shader code; `auto_cast` is for brevity when the target type is obvious.

`transmute` **[out]** for shaders unless a clear need appears.

---

## Advanced types

### Type aliases **[core]**

```misl
vec3 :: [3]f32
```

### Distinct types **[partial]**

General user-defined `distinct` is not required. Resource ids (`t32_2d`/`s32`/`rw32_2d`/…) are builtin distinct integer scalars.

### Vectors **[core]**

Only `[2]S` / `[3]S` / `[4]S` for scalar `S` (unless `#array` forces an array). Component-wise ops and **swizzles** apply:

```misl
c.rgb
c.bg
p.xyw
out.rgb *= mask.r
c.xxx                    // broadcast swizzle
```

Swizzle read and write are both supported.

### Arrays **[core]**

Fixed-length arrays: non-vector `[N]T`, or `#array [2..4]S`. Indexing only (no swizzle):

```misl
positions := [4]vec2 {   // array of vectors (elem is not scalar)
	vec2(0, 0),
	vec2(1, 0),
	vec2(0, 1),
	vec2(1, 1),
}
p := positions[vertex_id]

packed: #array [4]f32    // four floats as an array, not a vec4
```

### Matrices **[core]**

```misl
m: matrix[4, 4]f32
out.pos = data.camera * vec4(pos, 0, 1)
```

Element type must be `f32` or `f64` (GLSL only has `mat*` / `dmat*`; integer/complex/bool matrix elems are rejected in the checker).

Compound literals follow the same rules as vectors: `{}` or exactly `R*C` **scalar** elements (**column-major**, same order as GLSL `mat4(...)`: first `R` values are column 0). No named fields and no splicing vectors/columns — use a type-call constructor for that.

Do not write HLSL/textbook **rows**. A 2D rotation `[[c,-s],[s,c]]` is:

```misl
return {
	c,  s, 0, 0,
	-s, c, 0, 0,
	0,  0, 1, 0,
	0,  0, 0, 1,
}
```

### Multipointers `[^]T` **[core]**

A multipointer is a pointer to the first element of a contiguous sequence of `T`. In MISL this is the **device-address / BDA** type: it lowers to the backend’s buffer-reference (or equivalent) ABI.

```misl
Sprite_Shader_Data :: struct #align(16) {
	sprites: [^]Sprite,   // BDA to Sprite elements
	camera: mat4,
}
sprite := data.sprites[sprite_id]
```

Indexing `p[i]` on a `[^]T` means element access at offset `i` (no built-in bounds). Multipointers do **not** carry a length.

**Conversions / slicing:**
- `cast(^T)mp` → single-element device pointer
- `mp[:n]` / `mp[low:high]` → `[]T` (end index supplies the length)
- `mp[low:]` → `[^]T` (advance the multipointer; no length involved)
- `mp[:]` is illegal (neither offset nor length)

### Single pointers `^T` **[core]**

`^T` is a **device** pointer to one `T` (same BDA family as `[^]T`, single-element view). It is **not** the address of a local — unary `&expr` is a hard error (`misl does not support stack pointers`). Field access uses Odin-like `p.field` (implicit deref through `^Struct`). Mutable range binding `for &elem in …` is unrelated (alias, not `^T`).

```misl
vs :: proc "vertex"(data: ^Shader_Data | SV_Data, ...) { ... }
p := cast(^Sprite)data.sprites
```

### Slices `[]T` **[core]**

A slice is a **real fat pointer**: a multipointer plus a length (same idea as Odin’s `[]T`).

```misl
// Conceptual layout (exact field names are implementation-defined):
// []T  ≈  struct { data: [^]T, len: i64 /* or similar */ }

items: []Sprite
count := len(items)          // builtin; arrays, slices, and compile-time strings (byte length)
sprite := items[i]           // []T index; OOB records a GPU assert and skips the load/store
s := mp[:n]                  // [^]T → []T (length n)
s = mp[i:j]                  // [^]T → []T window [i, j)
p := mp[i:]                  // [^]T → [^]T advanced by i
t := items[i:j]              // reslice [i, j)
t = items[i:]               // from i to end
t = items[:j]               // from start to j
t = items[:]                // full fat-pointer copy
```

Slice bounds are half-open `[low, high)`. Omitted `low` defaults to `0`; omitted `high` on a `[]T` defaults to `len(s)`. On a multipointer, omitted `high` keeps the result a multipointer (`mp[i:]`); an end index is required to build a `[]T`.

Slices are first-class values (can appear in structs, locals, parameters). They are **not** growable host slices and not dynamic arrays (`[dynamic]T` remains **[out]**).

**Migration note:** existing shaders that used `[]T` to mean “GPU buffer address” should move that field to `[^]T`. Use `[]T` when both base and length are part of the value.

### Structs **[core]**

```misl
Sprite :: struct #align(16) {
	pos: [2]f32,
	size: [2]f32,
	texture: t32_2d,
	sampler: s32,
}
```

`#align(N)` sets minimum alignment for the struct (important for host-matching layouts).

**No cyclic types:** a struct (or type alias chain) must not contain itself directly or indirectly (e.g. `A` has a field of type `B` while `B` has a field of type `A`). Cycles are a hard error.

Field semantics attach with `|`. Multiple names may share one type (and one semantic):

```misl
Sprite_VS_Out :: struct {
	pos: [4]f32 | SV_Position,
	uv: [2]f32,
}

MRT :: struct {
	a, b: [4]f32 | SV_Target, // each name is a separate SV_Target attachment
}
```

Struct compound literals `Foo{ ... }` **[core]**, including named field init (`Foo{ field = value, ... }`).

### Enums **[core]**

Unlike Odin, the **underlying type is mandatory**. A bare `enum { }` is a compile error.

```misl
// valid
Mask_Type :: enum u32 {
	Sprite,
	Cone,
}

// invalid — missing underlying type
// Mask_Type :: enum {
// 	Sprite,
// 	Cone,
// }
```

Implicit selectors (`.Sprite`) resolve from context. Float-backed enums are rejected; use an integer backing type (`u32`, `i32`, …).

### `bit_set` **[core]**

Unlike Odin, the **underlying type is mandatory**. The element type (usually an enum) and the integer storage type are both required, separated by `;`:

```misl
Flags :: enum u32 {
	A,
	B,
	C,
}

// valid
B :: bit_set[Flags; u32]

// invalid — missing underlying type
// B :: bit_set[Flags]
```

Semantics are the usual bit-set / flag-mask operations over the named underlying integer. Growable or allocator-backed sets are **[out]**.

### Pointers

| Form | Status | Role |
|------|--------|------|
| `^T` | **[core]** | Device pointer to one `T` (BDA) |
| `[^]T` | **[core]** | Multipointer — BDA / contiguous device memory |
| `[]T` | **[core]** | Slice — multipointer + length |

`^T` / `[^]T` / `[]T` are **device addresses only** (not stack references). GLSL buffer-reference types are emitted as `_Ptr_RO` by default and upgraded to `_Ptr_RW` when the entry’s call graph stores through that origin. Helper parameters follow the same rule per procedure (a read-only helper stays `_Ptr_RO` even if another helper writes that element type). Nested BDAs can be `_Ptr_RW` inside an `_Ptr_RO` parent.

---

## Modules and imports

### Modules **[core]**

One `.misl` file = one module. All top-level declarations in the file are in that module’s scope.

### `import` **[core]**

File-level imports (one file = one module). No `package` keyword and no package graph.

```misl
import "common.misl"           // path relative to this file’s directory
import foo "other_name.misl"   // same, bind as `foo`
import "lib:math.misl"         // collection `lib` + path under that root
import m "lib:math.misl"       // collection + explicit bind name
import "core:builtin"          // compiler-synthesized builtin module → name `builtin`
import "core:s2h.misl"         // compiler-embedded core library file → name `s2h`
```

**Path rules:** If the string has `name:rest`, resolve `rest` under collection `name`. If there is no collection prefix:
- Module loaded from a **file** → path is relative to that file’s directory.
- Module loaded from **source/memory** (API name only, no directory) → the string names another module **already loaded in the session** (no filesystem lookup).

**Bind name:** optional identifier before the string (`import name "…"`). If omitted, the default is the path stem (and `builtin` for `core:builtin`).

**Collections** are named directory roots (Odin-style). User collections are passed at `create_session({collections = …})` (`Session_Desc`), via `-collection:name=path`, and (for the language server) the workspace-root `misl.lsp.json` `collections` array (`[{ "name", "path" }]`). Legacy `misl.json` object maps are still accepted when `misl.lsp.json` is absent. Collections cannot be added after the session is created.

**`import` is file-scope only.** It is illegal inside `when` / `which` / nested blocks (the import DAG is load-time and cannot wait on `#config` / `MISL_MODE`). `when` / `which` may still gate **uses** of imported names.

The compiler pre-registers **`core`**. It is **not** a `-collection:core` directory. `core` holds baked files under `oge/misl/core` (including `builtin.misl` and `debug.misl`), imported as `import "core:file.misl"`. Go-to-definition uses the on-disk path of those files so they stay openable from the language server.

The language server completes import strings: collection names after `import "`, `core:` members (synthetics and baked files), other collection roots, and relative `.misl` files / folders from the current file.

**No cyclic imports:** the import graph must be a DAG. Mutual or indirect import cycles are a hard error.

### `using` and `#subtype` **[core]**

`using` injects names (Odin [using statement](https://odin-lang.org/docs/overview/#using-statement)). Combined `using import "path"` stays rejected; write `import "foo"` then `using foo`.

- **Import name:** `using foo` brings `foo`’s exported names into the current scope.
- **Struct value:** `using entity` / `using entity.position` injects that struct’s field names (including names already injected by `using` fields).
- **Parameter:** `foo :: proc(using entity: Entity)`.
- **Struct field:** `using position: Vector3` so `e.x` works as well as `e.position.x`.

`#subtype base: Base` is the same **conversion** as `using` but does **not** inject names (`e.x` is illegal; `e.base.x` is fine). `using` and `#subtype` on the same field are mutually exclusive.

Conversion is field selection at any index: `foo(e)` where `foo :: proc(b: Base)` becomes `foo(e.base)`. The callsite picks the unique using/#subtype field whose type matches; two fields of the same type are ambiguous. SPIR-V has no `using`: injected names emit as field access chains.

`using foo := bar` (declaration using) is not supported.

Qualified types in type position (`geom.AABB`, `^geom.AABB`) are **[core]**.

### `core:builtin` **[core]**

Builtin procedures and type names (`i32`, `f32`, `sin`, `sample`, …) live in the **ambient** `core:builtin` module, parent of every user module’s scope. The module is a real baked file ([`oge/misl/core/builtin.misl`](../core/builtin.misl)), not an empty synthesized package. Compiler-supported names are `@builtin name :: #intrinsic("key")`; scalar types (`i32`, `f32`, …) and `true`/`false` are still injected by the compiler. A Fmag `check` also typechecks baked [`oge/misl/core/fmag.misl`](../core/fmag.misl) on the same checker and harvests `@builtin` names (proc groups such as `sin`) into that instantiation; helpers (`__sin_kernel`, `sin_f32`, …) stay in that file’s scope and are used via `import "core:fmag"`.

Each `misl.check` instantiates `core:builtin` for that compile’s `MISL_MODE` (`.SPIRV` or `.FMAG`, from `Target.formats`). GPU names (`sample` / `load` / `store` / `dim`, derivatives, compute sync) exist under `which MISL_MODE { case .SPIRV: … }`. There is no `MISL_KERNEL`. Stage-specific builtins stay in scope under `.SPIRV` and are **gated at the call**: `fwidth` / `dFdx` / `dFdy` are fragment-only; `barrier` / `memory_barrier*` are compute-only. A helper that calls `fwidth` typechecks; a vertex entry that reaches that helper is an error (“only valid in fragment shaders” / “proc contains fwidth”), not `unknown identifier`. A Fmag check does not take the `.SPIRV` arm, so those GPU names are undeclared.

`MISL_MODE` is a typed enum constant (`Mode` in `core:builtin.misl`).

- Every user module **implicitly** sees builtin names unqualified (module scope parents to the builtin module scope).
- `import "core:builtin"` binds the name `builtin` (unless aliased) so you can qualify after overriding a name:

```misl
import "core:builtin"

sin :: proc(x: f32) -> f32 {
	return builtin.sin(x) * 2
}
```

Types work the same way (`builtin.i32`, etc.). Explicit import is optional for normal code; it exists so overrides do not lose access to the originals.

### `core:debug` **[core]**

Debug helpers live in the baked file [`oge/misl/core/debug.misl`](../core/debug.misl). Not in the ambient builtin scope — import explicitly:

```misl
import "core:debug"

debug.printf("x=%v\n", x)
debug.printfln("x=%v", x) // same as printf(...\n)
```

Default bind name is `debug`. Alias works (`import d "core:debug"` → `d.printf` / `d.printfln` / `d.assert` / `d.panic`).

### `core:wave` **[core]**

Wave / subgroup ops live in [`oge/misl/core/wave.misl`](../core/wave.misl). Not ambient — import explicitly:

```misl
import "core:wave"

s := wave.sum(x)
id := wave.lane_id()
```

Default bind name is `wave`. Predicates and boolean-like results are `b32` / `[N]b32` (untyped `true`/`false` coerce). These are SIMD-lane ops, not workgroup `barrier()`.

Query / vote / broadcast / reduce / ballot / exclusive prefix (`wave.prefix_sum`, `wave.prefix_product`, `wave.prefix_bit_count`) and portable shuffles (`wave.read`, `wave.shuffle_xor` / `shuffle_up` / `shuffle_down`) are valid in every GPU stage. Quad ops (`wave.quad_x` / `quad_y` / `quad_diag` / `quad_read`) are fragment and compute only (call-site gate, like `fwidth`). Clustered reduce takes a compile-time power-of-two cluster size. `wave.rotate` / `wave.clustered_rotate` emit `SPV_KHR_subgroup_rotate`. Vendor-only subgroup ops are not provided. `proc "fmag"` rejects them.

#### `debug.assert` / `debug.panic` **[core]**

Shaders cannot abort the process. These builtins CAS-write a single host-mapped record (Vulkan SpecId from `Target.assert_buffer_spec_id`, default `0`; `oge/gpu` specializes the same id). The host waits that queue after `gpu.submit` and `gpu.fatal`s if the record fired. The default address is `0`; every fail path no-ops when the address is 0 (gpu feature off, omitted specialization, or compiler omitted the helper). Direct SPIR-V names the pointer `_misl_assert_addr`.

```misl
debug.assert(cond)
debug.assert(cond, "compile-time string")
debug.panic("compile-time string")
```

- `assert`: first argument is a runtime `bool`. Optional second argument is a **constant** string (same rule as `printf` format). Omitted message → empty `msg_len`.
- `panic(message)`: required constant string; **always** records (equivalent to `debug.assert(false, message)`, not `true`).
- `#+feature disable-asserts` / `mislc -disable-asserts`: both builtins still typecheck; `assert` still evaluates `cond` for side effects; `panic` emits nothing.

Slice `[]T` index/store uses the same record (`kind = Slice_Index`) when bounds checks are on. The shader **skips** the illegal load/store after an OOB claim. Range-`for` over a slice is not checked (the loop index is already bounded by `s.len`). `[N]T` and `[^]T` are not checked.

#### File tags, statement tags, mislc flags **[core]**

File tags are only at the start of a module (`#+feature <name>` to end of line):

| Tag / flag | Effect |
|---|---|
| `#+feature no_bounds_check` / `-no-bounds-check` | Default **off** for `[]T` index/store in that file / load. **Overridden** by `#bounds_check` / `#no_bounds_check` on statements, expressions, and procedure tags |
| `#+feature disable-asserts` / `-disable-asserts` | Typecheck `debug.assert` / `debug.panic`; emit no claim (`assert` still evaluates `cond`) |

CLI **OR** file tag turns a thing off. `#bounds_check` re-enables slice checks even under `#+feature no_bounds_check` / `-no-bounds-check`. Both `#bounds_check` and `#no_bounds_check` on the same statement or procedure is an error. The tag must sit on the same line as the statement (`#no_bounds_check {` is fine; a newline between the tag and `{` is not).

Allowed statement hosts: `{}`, `if`, `when`, `which`, `for`, `switch`, `return`, assignment, mutable `:=` declaration. Expression form: `x := #no_bounds_check s[i]`. Procedure suffix: `proc() #no_bounds_check { … }`.

The compiler injects a Vulkan spec constant for the assert buffer address; the id is `Target.assert_buffer_spec_id` (default `0`; oge/gpu uses `0`). `#config` is check/compile-time and is not a user SpecId.

#### `debug.printf` / `debug.printfln` **[core]**

Lowers to SPIR-V `NonSemantic.DebugPrintf`. The format string must be a **constant** string. Author placeholders:

| Spec | Meaning |
|------|---------|
| `%v` | Compact pretty-print inferred from the argument type |
| `%#v` | Same shape with newlines and indentation |
| `%%` | Literal `%` |

`printfln` is identical to `printf` but always appends a trailing newline (`printf("hello\n")` ≡ `printfln("hello")`).

Raw VVL specs (`%f`, `%v4f`, …) are rejected in the source format. The compiler rewrites `%v`/`%#v` into VVL-compatible format strings and arguments.

**Shapes (MISL-like):**

| Type | Compact `%v` |
|------|----------------|
| scalars / `b32` / `t32_2d` `s32` `rw32_2d` | bare number (`0`/`1` for bools; resource ids as their unsigned integer backing) |
| vector / array | `{a, b, c}` |
| matrix | `{{a, b}, {c, d}}` (columns) |
| struct | `{ field = val, … }` |
| `^T` / `[^]T` | `%p` |
| `[]T` | `{ data = %p, len = %lu }` |
| enum | `.Name` or `INVALID_ENUM` |
| `bit_set[Enum; U]` | `{.A, .C}` — **set bits only** |

Enums and set-only bit_sets use segmented `debugPrintfEXT` calls (names are literal strings selected at runtime). Integer-range bit_sets print as the underlying integer.

---

## Control flow

### `if` **[core]**

```misl
if fsin.shadow_intensity > 0.5 {
	out.rgb *= mask.r * shadow.r
} else {
	out.rgb *= mask.r
}
```

`else if` is supported. If-with-init (`if x := ...; cond`) is **[core]**.

### C-style `for` **[core]**

```misl
for i := 0; i < data.point_light_count; i += 1 {
	light := data.point_lights[i]
	out.rgb += point_light(...)
}
```

### Range `for` **[core]**

Binding order is **element first, index second** (not Odin). Element bindings are **immutable references** unless prefixed with `&` (mutable lvalue alias — not a `^T`).

```misl
for i in 0..<n { }              // numeric iterator
for elem in xs { }              // immutable ref to element
for &elem in xs { }             // mutable ref (writes through to xs)
for elem, index in xs { }       // element, then index
for &elem, index in xs { }      // mutable element, then index
```

`for &` requires a device slice/array whose pointees may be stored (compute); stores in vertex/fragment are errors.

### `switch` **[core]**

```misl
switch mask.kind {
case .Sprite:
	...
case .Cone:
	...
}
```

Enum switches are exhaustiveness-checked. Use `#partial switch` when not all variants are covered (or provide a `case:` default).

A **conditionless** `switch` evaluates boolean case expressions in source order and runs only the **first** true case (optional `case:` default). It stays MISL `switch` syntax; GLSL lowers to an ordered `if` / `else if` / `else` chain.

```misl
switch {
case x > 0:
	y = 1
case x < 0:
	y = -1
case:
	y = 0
}
```

### `which` **[core]**

`which` is a **compile-time** `switch`. Boolean gating stays **`when`** — there is no `which cond { stmts }` form (that is a parse error; use `when`).

```misl
which KIND {
case .A:
	...
case .B, .C:
	...
case:
	...
}
```

- Enum exhaustiveness matches `switch`: cover every variant, add a `case:` default, or use `#partial which`.
- Only the taken arm is collected, typechecked, and emitted (same DCE as `when`). Untaken arms may contain identifiers that would not resolve.
- No `break` / `fallthrough`. No new scope.
- Empty `which { case bool: … }` matches conditionless `switch`: first true **constant** bool wins.
- Legal at file scope and in procedure bodies, including `proc "fmag"` (unlike runtime `switch`).
- Core uses `#partial which MISL_MODE` so GPU builtins (`sample`, `fwidth`, `barrier`, …) are only in scope for a `.SPIRV` check. Stage is gated at the call, not by a kernel intrinsic.

### `discard` **[core]**

Fragment-only early-out (`discard;` in GLSL). Illegal in vertex/compute.

### `break` / `continue` **[core]**

Valid inside loops (`for` / range-`for`). `continue` still runs the C-for post clause and range-for increment (lowered as a GLSL `for (;; post)` so it matches CPU `for`). `break` also leaves the innermost `switch`. No labels / multi-level break.

### `defer` **[out for now]**

`defer` does **not** unwind the stack. Like Odin, it only schedules a statement (or block) to run when the current scope exits — so it is implementable in MISL if we choose to add it later (emit the deferred code on every exit path of the scope).

It is left out of the initial language surface for scope control, not because of a GPU impossibility. Revisit when there is a clear shader use case.

### `when` / `#config` **[core]**

`when` is **strictly compile-time** (constant condition only). There is no runtime `when` — use `if` for runtime control flow. Used for shader variants / `#config`, not general host metaprogramming. File-scope `when` is allowed (taken-arm `::` decls bind in the enclosing module).

```misl
DO_STUFF :: #config(DO_STUFF, false)   // bool
N        :: #config(SAMPLES, 16)       // config key "SAMPLES" ≠ binding name
```

- Syntax: `#config(IDENTIFIER, default_constant_value)`.
- The config key (`IDENTIFIER`) is a **name string**, not a scope binding — it is not inserted into the module scope.
- `default_constant_value` must be a **constant** expression of **integer, float, or boolean**. The expression’s type is the type of that default.
- Result is a normal constant: `NAME :: #config(...)` behaves like any other `::` constant for folding / `when`.
- Config keys must be **unique across the entire import chain** of a load (root + all recursively imported modules). A second `#config(SAME, …)` anywhere in that chain is an error.
- Host / CLI (`-config:ident=value`) set values by **config key string**, not by the Odin binding name.
- One `[]User_Config` applies to **every** module in that check/compile (including keys declared only in imports). `#config` is **check/compile-time**, not parse/`load_module`-time.
- Unknown names in the user slice (no `#config` anywhere in the chain): **warn + ignore** at the end of that check.
- Instantiations are cached per `(origin module, Mode, configs, bounds/assert flags, no_gfx)`. A different config set is a different check.

### `#intrinsic` / `@builtin` **[core]**

`#intrinsic("key")` binds a `::` declaration to a **stable compiler key** (not the MISL identifier). Check and emit dispatch on that key. Unknown keys are a check error.

```misl
@builtin abs :: #intrinsic("spirv.abs")
@builtin t32_2d :: #intrinsic("builtin.t32_2d")
```

Multi-line decls keep `@builtin` on the line above (`@(builtin)` is the same attribute):

```misl
@builtin
Backend :: enum u32 {
	Glsl,
	Spirv,
	Fmag,
}
```

`@builtin` / `@(builtin)` is **only** legal in compiler-integrated `oge/misl/core` files. After a core module checks, those entities are harvested into ambient `core:builtin`. Using `@builtin` in a user shader is an error. `core:debug` and `core:wave` names are `#intrinsic` **without** `@builtin` so they stay behind `import "core:debug"` / `import "core:wave"`.

The compiler loads those files via `#load_directory`. The language server additionally treats an **open** `.misl` whose parent folder is named `core` as compiler-integrated so `@builtin` is not an error while editing them.

### Ternary **[core]**

Three forms:

```misl
c ? a : b                 // C-style
a if c else b             // Odin-style if-expression
x when CONST else y       // compile-time only (constant condition)
```

---

## Procedures

### Helpers **[core]**

```misl
linear_from_srgb :: proc(srgb_color: [3]f32) -> (linear_color: [3]f32) {
	return pow(srgb_color, 2.2)
}
```

Parameters are **immutable by default** (cannot assign to the param or its fields). Use `#ref` for mutable **value** parameters (GLSL `inout` writeback). The call site must pass `&` on an assignable lvalue — the same marker as `for &elem in xs`. That `&` is not address-of: MISL still has no stack pointers, so `&` is illegal except on `#ref` arguments and range-for bindings. Inside the procedure the parameter is a mutable `T`; forwarding it to another `#ref` parameter still needs `&`. `#ref` is illegal on `^T` / `[^]T` / `[]T` — device writes go through those pointees directly (compute). `^T` / `[^]T` / `[]T` parameters match by element type, so a helper `proc(data: ^Data)` can take `SV_Data` or any other `^Data`.

```misl
init_obj :: proc(#ref obj: Obj) {
	obj.a = 1
}
obj: Obj
init_obj(&obj)

for &obj in objs {
	init_obj(&obj)
}
```

### Shader stages **[core]**

```misl
sprite_vs :: proc "vertex"(...) -> (out: Sprite_VS_Out) { ... }
sprite_fs :: proc "fragment"(...) -> (out: [4]f32 | SV_Target) { ... }

@(size = 64)
cs :: proc "compute"(data: ^Data | SV_Data, gid: [3]u32 | SV_Global_Thread) { ... }
```

Calling conventions (string after `proc`):

| Convention | Role |
|------------|------|
| `"vertex"` | Vertex entry |
| `"fragment"` | Fragment entry |
| `"compute"` | Compute entry |
| `"fmag"` | FMAG bytecode entry (not a GPU pipeline stage) |

Short aliases are **[core]**: `"vert"` / `"vs"`, `"frag"` / `"fs"` / `"pixel"` / `"ps"`, `"comp"` / `"cs"`.

`proc "fmag"` is a compile-time entry the host lowers with `misl.compile_fmag_entry`. `mislc -target:fmag` writes `{stem}.entry.{name}.fmag`; `-target:asm` also writes `{stem}.entry.{name}.fmagasm` (same text as LSP **Show FMAG**). It is **not** a GPU pipeline stage (`pipeline.vertex` / `pipeline.fragment` reject it).

Checker subset (hard errors):

- Parameters and results must be `f32` or `[2/3/4]f32` (no integers, bools, `f64`, structs, pointers, slices, matrices, arrays, textures, …).
- No `SV_*` semantics.
- No `for` / range `for`, `switch`, or `discard` in the kernel **or** in any helper it calls. `if` / `else` is allowed (acyclic); it becomes IR branches that `fmag.lower` if-converts to selects, same as FSL (`std.fsl` `frexp` / `__rcp` ladders). Loops cannot be flattened. Compile-time `when` / `which` are allowed (untaken arms are dropped before FMAG emit).
- No polymorphism (`$n`), no nested entries.
- GPU-only names behind `which MISL_MODE { case .SPIRV }` (`sample` / `load` / `store` / `dim`, derivatives, compute sync) are undeclared in a Fmag check. Matrix ops (`transpose`, `inverse`, …), `card`, and `printf` / `printfln` / `assert` / `panic` are still illegal if they are in scope (including via helpers).
- Helpers without those features are allowed (unstaged `proc`, inlined into FMAG bytecode). Calling another shader entry (`proc "vertex"` / `"fragment"` / `"compute"` / `"fmag"`) is not. Type constructors (`f32(x)`, `vec3(...)`) and builtins that are allowed (`fma`, `lerp`, …) are not helper calls.
- Helper parameters and results must be `f32` or `[2/3/4]f32` when reachable from `proc "fmag"`.
- No `#ref`. `@shared` and `@(size=…)` are compute-only (same as other non-compute stages).

Ternary `cond ? a : b`, statement `if`, and f32 arithmetic / `fma` / `lerp` are allowed by the checker and **are** what `compile_fmag_entry` lowers (typed AST → FMAG IR → bytecode). The opcode is still a guarded FMA. Vector ops are scheduled one component at a time (and independent scalar defs are ordered to shorten live ranges) so a three-wide mix like `examples/fmag_pbr` `shade` fits in 16 registers — there is no hardcoded kernel. Builtins with no FMAG encoding (`sin`, `sqrt`, …) fail at `compile_fmag_entry` even if GLSL emit would accept them. The GPU interpreter in [`core:fmag`](../core/fmag.misl) has **16** registers (`REGS`); if `header.regs` exceeds that, shrink the kernel (precompute in the fragment) rather than growing the interpreter.

### System values (`SV_*`) **[core]**

Semantics are attached with `|` on parameters, results, or struct fields. **Which semantics are legal — and what they mean — depends on the shader stage.** The same name can denote different backend builtins in different stages (notably `SV_Position`).

Naming: `SV_` + Pascal_Case segments separated by underscores for multi-word names (e.g. `SV_Global_Thread`).

Direction:

- **in** — provided by the pipeline / previous stage / dispatch (read-only binding)
- **out** — written by this stage

#### Vertex stage (`proc "vertex"`)

| Semantic | Where | Direction | Meaning |
|----------|-------|-----------|---------|
| `SV_Data` | Parameter typed `^T` | in | Push-constant slot for this stage (`PC_Graphics.vertex_data`) |
| `SV_Indirect_Data` | Parameter typed `^T` | in | Push-constant slot 2 (`PC_Graphics.indirect_args`); any `^Struct` |
| `SV_Vertex` | Parameter | in | Vertex index (`gl_VertexIndex`) |
| `SV_Instance` | Parameter | in | Instance index (`gl_InstanceIndex`) |
| `SV_Position` | Result or field of a result struct | out | Clip-space position (`gl_Position`) |

```misl
VS_Out :: struct {
	pos: [4]f32 | SV_Position,
	uv:  [2]f32,
}

vs :: proc "vertex"(
	data: ^Shader_Data | SV_Data,
	vertex_id: u32 | SV_Vertex,
	instance_id: u32 | SV_Instance,
) -> (out: VS_Out) {
	out.pos = data.camera * vec4(0, 0, 0, 1)
	out.uv = vec2(0, 0)
	return out
}
```

`SV_Data` **requires** an explicit `^T` (struct pointee). Bare `T | SV_Data` is a hard error. Device pointee **stores** from vertex/fragment are hard errors (graphics stays read-only BDA).

`SV_Indirect_Data` has the same `^Struct` rule and at-most-one-per-entry cardinality as `SV_Data`. It binds push-constant slot 2 (host `indirect_args`); the pointee type is whatever struct the shader wants to read there.

`SV_Target` is **not** available in the vertex stage.

#### Fragment stage (`proc "fragment"`)

| Semantic | Where | Direction | Meaning |
|----------|-------|-----------|---------|
| `SV_Data` | Parameter typed `^T` | in | Push-constant slot for this stage (`PC_Graphics.fragment_data`) |
| `SV_Indirect_Data` | Parameter typed `^T` | in | Push-constant slot 2 (`PC_Graphics.indirect_args`); any `^Struct` |
| `SV_Position` | Field of an input struct from the previous stage (or equivalent in param) | in | Fragment window coordinates (`gl_FragCoord`), **not** the interpolated clip-space `gl_Position` from the vertex stage |
| `SV_Target` | Result, field of a result, or multi-name field list | out | Color render target (`layout(location = N) out`) |

```misl
fs :: proc "fragment"(
	fsin: VS_Out,
	data: ^Shader_Data | SV_Data,
) -> (out: [4]f32 | SV_Target) {
	return sample(data.texture, data.sampler, fsin.uv)
}
```

`SV_Target` may apply to a **multi-variable declaration**: one type and semantic shared by every name. Each name is its own color attachment; locations are assigned in declaration order (left to right, then field order in the struct).

```misl
// Two targets, same type — equivalent to separate a: … | SV_Target and b: … | SV_Target
MRT :: struct {
	a, b: [4]f32 | SV_Target,
}

// Unnamed single target
fs_color :: proc "fragment"(fsin: VS_Out) -> [4]f32 | SV_Target {
	return vec4(1, 0, 0, 1)
}

// Multi-name results (named) or unnamed pair
fs_mrt :: proc "fragment"(fsin: VS_Out) -> (a, b: [4]f32 | SV_Target) {
	a = vec4(1, 0, 0, 1)
	b = vec4(0, 1, 0, 1)
	return a, b
}
```

`SV_Vertex` and `SV_Instance` are **not** available as fragment inputs (use varyings if the vertex stage must forward them).

**`SV_Position` summary:**

| Stage | Role | Backend |
|-------|------|---------|
| Vertex | output position | `gl_Position` (clip space) |
| Fragment | input fragment coordinate | `gl_FragCoord` (window space) |

Do not assume a fragment `SV_Position` field is the interpolated vertex clip position; ordinary non-semantic fields on the inter-stage struct are what get interpolated as varyings.

#### Compute stage (`proc "compute"`) **[core]**

Compute entries are **void** (no results). Device pointee stores are allowed; GLSL buffer refs upgrade from `_Ptr_RO` to `_Ptr_RW` when written.

Optional workgroup size attribute (defaults to `(1,1,1)` if omitted). RHS must be a constant convertible to `u32`, `[2]u32`, or `[3]u32` (missing axes pad to `1`):

```misl
@(size = 64)                 // (64, 1, 1)
@(size = {8, 8})             // (8, 8, 1)
@(size = {4, 4, 4})
cs :: proc "compute"(
	data: ^Data | SV_Data,
	gid: [3]u32 | SV_Global_Thread,
) {
	i := gid.x
	if i >= data.count do return
	data.particles[i].pos += data.particles[i].vel
}
```

Compute `SV_Data` is host `PC_Compute.data` — **one** device pointer. Graphics entries use the 3-slot `PC_Graphics` block (`vertex_data`, `fragment_data`, `indirect_args`). `SV_Indirect_Data` is illegal on compute.

| Semantic | Type | Direction | GLSL | Meaning |
|----------|------|-----------|------|---------|
| `SV_Data` | `^T` | in | `PC_Compute.data` (one device pointer) | Shader data block |
| `SV_Global_Thread` | `[3]u32` | in | `gl_GlobalInvocationID` | Global dispatch thread id |
| `SV_Group_Thread` | `[3]u32` | in | `gl_LocalInvocationID` | Thread id within workgroup |
| `SV_Group` | `[3]u32` | in | `gl_WorkGroupID` | Workgroup id in the dispatch |
| `SV_Group_Index` | `u32` | in | `gl_LocalInvocationIndex` | Flattened id in the workgroup |
| `SV_Num_Groups` | `[3]u32` | in | `gl_NumWorkGroups` | Dispatch workgroup count |
| `SV_Group_Size` | `[3]u32` | in | `gl_WorkGroupSize` | Workgroup size (`@(size=…)`) |

`SV_Position`, `SV_Target`, `SV_Vertex`, and `SV_Instance` are **not** used in compute.

##### `@shared` workgroup memory **[core]**

Inside a compute entry body only (not helpers, not VS/FS, not module scope):

```misl
@(size = 64)
cs :: proc "compute"(
	data: ^Data | SV_Data,
	lid: u32 | SV_Group_Index,
) {
	@shared tile: [64]f32
	tile[lid] = data.values[lid]
	barrier()
	// ...
}
```

- Declaration shape: `@shared name: Type` (no initializer in v1).
- Type must be compile-time sized (arrays/structs/scalars/vectors); must **not** be or contain `^T` / `[^]T` / `[]T`.
- Lowers to GLSL `shared`. Cross-thread use requires a sync builtin.

##### Compute sync builtins **[core]**

Snake_case MISL names (same convention as `round_even`, `matrix_comp_mult`):

| MISL | GLSL | Role |
|------|------|------|
| `barrier()` | `barrier` | Workgroup execution barrier (+ shared visibility per GLSL) |
| `memory_barrier()` | `memoryBarrier` | Full memory barrier |
| `memory_barrier_shared()` | `memoryBarrierShared` | Shared-memory visibility |
| `memory_barrier_buffer()` | `memoryBarrierBuffer` | Buffer visibility |
| `memory_barrier_image()` | `memoryBarrierImage` | Image visibility |
| `group_memory_barrier()` | `groupMemoryBarrier` | Workgroup-scoped memory barrier |

Declared in `core:builtin.misl` under `which MISL_MODE { case .SPIRV }` with a compute-only call-site stage gate. Vertex/fragment entries (and helpers they can reach) error; `proc "fmag"` sees `unknown identifier` because the name is not in the FMAG arm.

#### Cross-stage availability (quick reference)

| Semantic | Vertex | Fragment | Compute |
|----------|:------:|:--------:|:-------:|
| `SV_Data` (`^T`) | in | in | in |
| `SV_Indirect_Data` (`^T`) | in | in | — |
| `SV_Vertex` | in | — | — |
| `SV_Instance` | in | — | — |
| `SV_Position` | out (clip) | in (`gl_FragCoord`) | — |
| `SV_Target` | — | out | — |
| `SV_Global_Thread` | — | — | in |
| `SV_Group_Thread` | — | — | in |
| `SV_Group` | — | — | in |
| `SV_Group_Index` | — | — | in |
| `SV_Num_Groups` | — | — | in |
| `SV_Group_Size` | — | — | in |

Helper `proc`s (no stage string) must not use stage semantics on their signatures.

#### Interpolation modifiers **[core]**

Vertex outputs that become fragment inputs are **varyings**. By default they use perspective-correct linear interpolation (GLSL `smooth` / HLSL `linear`). Override that with **prefix field tags** — not keywords, and not via `|` (that operator is reserved for `SV_*` / ABI semantics).

```misl
VS_Out :: struct {
	pos: [4]f32 | SV_Position,       // system value — no interpolation tag
	#flat id: u32,                   // no interpolation (required for integers)
	#noperspective uv: [2]f32,
	#centroid color: [3]f32,         // linear + centroid
	#noperspective #centroid color2: [3]f32,
	normal: [3]f32,                  // default: smooth / linear
}
```

| Tag | ≈ HLSL | ≈ GLSL |
|-----|--------|--------|
| *(none)* | `linear` | `smooth` |
| `#flat` | `nointerpolation` | `flat` |
| `#noperspective` | `noperspective` | `noperspective` |
| `#centroid` | `centroid` (with linear or noperspective) | `centroid` |

Explicit `#smooth` / `#linear` tags to name the default are **[planned]**. `#sample` is **not** an interpolation tag (texture sampling stays the `sample` builtin).

**Rules:**

1. Tags apply to **inter-stage varyings** only (ordinary fields of VS→FS structs / matching FS inputs).
2. Illegal on `SV_Data`, `SV_Vertex`, `SV_Instance`, `SV_Target`, and on helper `proc` signatures.
3. `SV_Position` does not take interpolation tags in the usual varying sense (vertex out → `gl_Position`; fragment in → `gl_FragCoord`).
4. Integer, enum, and bit_set varyings require `#flat`.
5. Tags may stack where the backend allows (e.g. `#noperspective #centroid`).
6. v1: declare modifiers on the **vertex output** struct; the fragment input of the same layout inherits them. Fragment-side override is optional later (HLSL allows the FS argument to win).

Do **not** write `color: [3]f32 | flat` — that fights the semantic syntax.

### Results **[core]**

Return values may be **named or unnamed**. Parentheses are used for a result list; a single unnamed result may omit them when there is no ambiguity (same spirit as Odin).

```misl
// Named (binds a result entity you can assign before return)
-> (out: Sprite_VS_Out)
-> (out: [4]f32 | SV_Target)

// Unnamed — type (and optional semantic) only
-> [4]f32 | SV_Target
-> (VS_Out)
-> (i32, i32)
-> (a, b: [4]f32 | SV_Target)   // multi-name + semantic still ok
```

Unnamed results are still full results for typing, `return`, and ABI (`SV_Target` locations, multi-return lowering, etc.). Names are optional sugar for assigning into the result in the body (`out.pos = …; return out` vs `return expr`).

Named results are **zero-initialized** on entry (same spirit as Odin), including early results that lower to GLSL `out` parameters in multi-return helpers.

### Naked `return` **[core]**

A bare `return` (no expressions) is allowed when:

- the procedure has **no** results, or
- **every** result is **named** (the named result locals are what get returned / unpacked).

It is an error on unnamed results (e.g. `-> i32` or `-> (i32, i32)`). Prefer `return value` / `return a, b` for those.

```misl
helper :: proc() -> (x: i32, y: i32) {
	x = 1
	y = 2
	return  // ok — named results
}

fs_main :: proc() -> [4]f32 | SV_Target {
	return  // error — result is unnamed
}
```

### Multiple results **[core]**

MISL lowers multi-return to a GLSL-friendly calling convention: the **last** result is the GLSL return value; earlier results become `out` parameters. Full Odin tuple values are not a goal. Names are optional on each result (`-> (i32, i32)` and `-> (a: i32, b: i32)` are both fine).

Procedure call results are typed as a **result tuple** of length 0, 1, or N (uniform representation). Unpack with `a, b := f()` / `a, b = f()`; LHS may be any assignable lvalue (idents, selectors, indices, swizzles, blanks). A call with N≥2 results cannot be used in a single-value context. A 1-result call is a **value**: `foo().val` and `foo2().xyz` are legal; `foo().val = 1` is not (not an lvalue). `return f()` forwards when `f`’s result arity matches the callee.

### Nested procedures and nested types **[core]**

Procedures and type/struct declarations (`::`) may appear inside procedure bodies. They are scoped to the enclosing block. Because GLSL has no nested functions or nested type definitions, the compiler **hoists** them to file scope with mangled names (`_<ownerPath>_<name>`).

**Capture:** nested procs may use module-scope bindings and enclosing `::` constants/types/procs only. Capturing outer **params or mutable locals** is a hard error — pass values as arguments. Nested stage entry points (`"vertex"` / `"fragment"`) and nested `pipeline` decls are not allowed.

### Constant parapoly `$name: T` **[core]**

A `$` on a **parameter name** (not a type) is **constant polymorphism**, as in Odin `proc($str: string)` / `proc($n: i32)`:

```misl
print_len :: proc($str: string) -> i32 {
	return i32(len(str))
}

add_n :: proc($n: i32, x: i32) -> i32 {
	return x + n
}
```

Each distinct compile-time argument produces a **specialized** procedure (cached by exact value). `print_len("hello")` and `print_len("world")` are different functions; the same string twice shares one. `$` parameters are omitted from the GLSL signature — they are inlined as constants (strings via the interned `uint8_t` pool). Mixed `proc($str: string, n: i32)` lowers to a GLSL function of `n` only.

`T` must be a foldable constant type: `string`, integer/float/bool scalars, `rune`, or a **procedure type** (`$fn: Proc_Type`). Not slices, structs, vectors, resource ids, or type variables.

A `$fn` argument is a **named procedure** (not a runtime value). Each distinct callee produces a specialized procedure; `$fn` is omitted from the GLSL signature and `fn(...)` emits a direct call to that callee’s GLSL name. Shader entries cannot be passed as `$fn`.

Illegal: `#ref` / defaults on `$` params; polymorphic **stage entries**; `$name: $T`; `x: $T`; `$T/[$N]$E` specializations; `where` clauses.

Using `$n` as an **array length in a signature** (`-> [n]f32`) is not supported in this slice. Using `$n` / `$str` as **values in the body** is.

Body checking of the generic is deferred to the first callsite. The unspecialized template is not emitted to GLSL.

### Proc groups, overloading **[core]**

Odin-style **explicit** overload sets: named concrete procedures bound together; the callsite picks exactly one member. This is not C++/GLSL implicit overloading of one `foo` with two bodies, and not `$fn: Proc_Type`.

```misl
foo_f32 :: proc(f: f32) { }
foo_i32 :: proc(f: i32) { }
foo :: proc {
	foo_f32,
	foo_i32,
}
foo(1)     // foo_i32 (untyped int prefers integer)
foo(1.0)   // foo_f32
```

The checker ranks exact matches over implicit conversions (untyped integer → integer before float). No match or two equally good members is an error. GLSL emit calls the chosen member’s already-mangled name. Members must be named procedures (not literals or shader entries). Duplicate signatures in one group are an error.

### Polymorphic types `$T` / `where` **[out]**

User type parapoly (`proc(x: $T)`, `$T/[$N]$E`, `where`) is out of scope. `#intrinsic` hooks may still be generic over vector length (`N = 2..4`) without exposing user `$T`. MISL-written builtin bodies (FMAG math in `core/fmag.misl`) are concrete proc-group members (`sin_f32`, `sin_f32x2`, …), not `$T`.

### `foreign` **[out]**

No CPU FFI from shaders.

---

## Operators **[core]**

Operator set matches Odin for the forms MISL supports (including bitwise). Same precedence and compound-assign shorthands as Odin unless noted.

### Arithmetic

Unary: `+`, `-` (including numeric vectors and matrices)  
Binary: `+`, `-`, `*`, `/`, `%` (truncated modulo), `%%` (floored remainder)  
Vector/matrix: mat×vec, scalar broadcast, component-wise ops on vectors where applicable.

### Bitwise (same as Odin)

Unary: `~` (bitwise complement)  
Binary: `|`, `~` (xor), `&`, `&~` (and-not), `<<`, `>>`  

Operands are integers (and enums where Odin would allow). Right-hand side of shifts follows Odin’s unsigned / untyped rules.

### Comparison

`==` `!=` `<` `>` `<=` `>=`

### Logical

`&&` `||` `!` on booleans (short-circuit where the backend model allows; GPU lowering may constrain this).

### Compound assign

All corresponding forms, including bitwise. Compound assign is typed as `lhs = lhs op rhs` (so scalar broadcast works: `hs /= mag(hs.xy)`).

`+=` `-=` `*=` `/=` `%=` `%%=`  
`|=` `~=` `&=` `&~=` `<<=` `>>=`  
`&&=` `||=` **[core]** (lowered to `a = a && b` / `a = a || b`; typed `b32` uses GLSL `bool` predicates then stores `uint`)

### Indexing and selection

```misl
data.sprites[i]
out.pos.xy          // swizzle — vectors only
```

### Precedence

Aligned with [Odin’s operator precedence](https://odin-lang.org/docs/overview/#operator-precedence).

---

## Built-in procedures **[core set]**

Math / geom / matrix builtins take GLSL-style **genType** arguments. Untyped literals coerce from a typed sibling, or default to `f32` / `i32`. Where GLSL allows a scalar overload (`lerp`/`mix`, `step`, `smoothstep`, `clamp`, `min`, `max`), a scalar may mix with a vector result type.

| Builtin | Notes |
|---------|--------|
| `radians`, `degrees`, trig (`sin`…`atanh`), `pow`, `exp`, `log`, `exp2`, `log2`, `sqrt`, `isqrt` | SPIR-V: `#intrinsic("spirv.*")` (`isqrt` → `inversesqrt`). FMAG: MISL proc groups in `core/fmag.misl` for the FSL intersection (not hyperbolic). |
| `abs`, `sign`, `floor`, `trunc`, `round`, `round_even`, `ceil`, `fract`, `mod` | Component-wise. `abs` / FMAG rounding live as source or opcodes; `mod` is SPIR-V ExtInst until ported to FMAG. |
| `modf`, `frexp` | Multi-return. SPIR-V `frexp` → integer exp. FMAG `frexp` is `(exp: f32, significand: f32)` (significand in `[0.5, 1)`). |
| `min`, `max` | Variadic (2+ args) → nested SPIR-V binary min/max; scalar broadcast allowed |
| `clamp`, `lerp`, `step`, `smoothstep`, `fma` | `lerp` → `spirv.mix`; scalar broadcast where the ExtInst allows |
| `is_nan`, `is_inf`, `ldexp` | |
| `f32_from_u32_bits`, `u32_from_f32_bits` | IEEE bitcast; SPIR-V `OpBitcast` (scalar or matching uvec/vec) |
| `mag`, `dist`, `dot`, `cross`, `normalize`, `facefoward`, `reflect`, `refract` | `mag` → `length`; `facefoward` spelling kept |
| `matrix_comp_mult`, `outer_product`, `transpose`, `determinant`, `inverse` | |
| `sample`, `load`, `store`, `dim` | Bindless resource ids (`t*` / `s*` / `rw*`, including view types and `s8_cmp` / `s16_cmp` / `s32_cmp`). Optional last `lod: f32` on `sample` → `textureLod`. |
| `dFdx`, `dFdy`, `fwidth` | Declared under `which MISL_MODE { case .SPIRV }` with a fragment-only call-site gate. A helper may call them; a vertex/compute entry that reaches that helper is an error. `proc "fmag"` sees `unknown identifier`. |
| `barrier`, `memory_barrier*` | Same SPIRV arm, compute-only call-site gate. Vertex/fragment entries that reach them error. `proc "fmag"` sees `unknown identifier`. |
| `card`, `len` | `bit_set` cardinality; slice/array length |

Wave / subgroup ops are not ambient; see [`core:wave`](#corewave-core). Debug printing is `debug.printf` via [`core:debug`](#coredebug-core) **[core]**.

---

## Explicitly out of scope

These Odin (or host) features are **not** part of MISL:

| Feature | Reason |
|---------|--------|
| `package` / package imports | File modules + collections only (no package graph) |
| `foreign`, `context`, allocators | Host concerns |
| `defer` | Omitted for now (scope-exit scheduling is implementable; not a stack-unwind feature) |
| `map`, `union`, `[dynamic]T` | Not shader data model |
| `or_else`, `or_return`, … | Host error style; shader-only `or_discard` may be considered later |
| Combined `using import "path"` | Overview form is `import "foo"` then `using foo` |
| User `$T` / `where` | Keep type generics to builtins; constant `$name: T` is **[core]** |
| `typeid`, `any` | |
| `transmute` | Bit reinterpret; not needed for core shaders |
| Runtime string variables | Compile-time `string` / `$str: string` only |
| Inline assembly | |

---

## Pipelines **[experimental]**

A **pipeline** groups optional stage bindings and optional fixed-function raster fields in one compile-time constant. The host converts a MISL pipeline to `gpu.Raster_Desc` (and selects SPIR-V entries) on its side — the compiler does **not** emit sidecar metadata.

### Constant-only

A pipeline is a **strict compile-time constant** (`::` binding). Every field that *is* written must be a constant expression resolvable at check time. Omitted fields are simply unset (no compiler-filled defaults).

Consequences:

- Only `Name :: pipeline { ... }` (never `:=` / mutable locals).
- When present, `vertex` / `fragment` refer to known stage procs (or literals written in place), not values computed later.
- Enums, bit_sets, and blend literals are constant expressions.
- The host maps whatever fields were set into a `Raster_Desc`; unspecified fields are the host’s concern.

### Why

A MISL `pipeline` keeps stages and raster state in one entity so the checker can validate **cross-links among fields that are present** (e.g. VS↔FS interface, `targets` vs `SV_Target` count) before the host builds GPU objects.

### Syntax

`pipeline` is a keyword. Declaration form: `name :: pipeline { ... }` (constant declaration only).

**All fields are optional.** Checks run only for fields that appear (and for combinations that need more than one field — see below).

```misl
name :: pipeline {
	// any subset of these may appear
	topology = .Triangle_Strip,
	cull = {.Back},
	sample_count = ._1,
	depth_format = .None,
	stencil_format = .None,
	flags = {},
	view_count = 0,

	vertex = some_vs,
	fragment = some_fs,

	// If present *and* fragment is present: length must match fragment SV_Target count.
	// format is required on each listed target entry; write_mask / blend may be omitted.
	targets = {
		{
			format = .rgba_u8_srgb,
			write_mask = .All,
			blend = {
				color = { .Src_Alpha, .One_Minus_Src_Alpha, .Add },
				alpha = { .One, .One_Minus_Src_Alpha, .Add },
			},
		},
	},
}
```

**Stage values** (when `vertex` / `fragment` are set) may be:

1. A previously declared `proc "vertex"` / `proc "fragment"` name, or
2. An anonymous stage proc literal (`proc "vertex"(...) -> ... { ... }`).

**Fields** (all omittable at the pipeline level):

| Field | When present |
|-------|----------------|
| `topology`, `cull`, `sample_count`, `depth_format`, `stencil_format`, `flags`, `view_count` | Must type-check as the matching gpu-mirrored enum / bit_set / `i32` |
| `vertex` | Must be a vertex entry |
| `fragment` | Must be a fragment entry |
| `targets` | Non-empty list of attachment lits; each entry requires `format`; `write_mask` / `blend` optional within an entry |
| `targets` + `fragment` both set | `len(targets)` must equal fragment `SV_Target` count |
| `vertex` + `fragment` both set | VS↔FS interface checks (see below) |

Blend state uses **full literals** (`Blend_State` / `Blend_Mode`), not presets like `.Alpha`. Factor and op enums track `gpu.Blend_Factor` / `gpu.Blend_Op`.

**Compile-time checks** (only where applicable):

- If `vertex` is set → must be a vertex entry; its `SV_*` usage must obey the vertex ABI table.
- If `fragment` is set → must be a fragment entry; its `SV_*` usage must obey the fragment ABI table.
- If **both** `vertex` and `fragment` are set → inter-stage struct match; varying / `#flat` rules on the shared VS→FS layout.
- If **both** `targets` and `fragment` are set → `len(targets)` equals fragment `SV_Target` count (including targets nested in a result struct).
- If `targets` is set without `fragment` → type-check the attachment list only; **no** `SV_Target` length check.
- Each stage’s `SV_Data` is independent (types need not match across stages).

**Host mapping** (host converts MISL → `gpu.Raster_Desc`):

| Pipeline field (if set) | Typical `Raster_Desc` field |
|-------------------------|-----------------------------|
| `topology` | `topology` |
| `cull` | `cull` |
| `sample_count` | `sample_count` |
| `depth_format` | `depth_format` |
| `stencil_format` | `stencil_format` |
| `flags` | `flags` |
| `view_count` | `view_count` |
| `targets` | `colors` |
| `vertex` / `fragment` | which SPIR-V entries to bind |

Field names stay aligned with `Raster_Desc` / `Color_Attachment_Desc` (`targets` ↔ color attachments).

Builtin enums/bit_sets (`Topology`, `Format`, `Cull_Mode`, `Raster_Flag`, `Blend_Factor`, `Blend_Op`, `Color_Write_Mask`, …) are declared in [`core/builtin.misl`](../core/builtin.misl) with **required underlying types**. Exact members track `oge/gpu`. The compiler looks them up by name after each `core:builtin` check so pointer identity is per instantiation.

The compiler keeps a **duplicate Odin mirror** of those enums in [`misl_gpu_iface.odin`](../misl_gpu_iface.odin) for host `pipeline` → `gpu.Raster_Desc` conversion — there is **no** import between `misl` and `gpu`. When gpu raster enums change, update that file **and** `core/builtin.misl` to match.

### Complete example program

Minimal module — only enough to show naming, interface matching, named vs inline stages, and `targets` count.

```misl
vec2 :: [2]f32
vec4 :: [4]f32

Data :: struct #align(16) {
	color: [4]f32,
}

VS_Out :: struct {
	pos: [4]f32 | SV_Position,
	uv: [2]f32,
	#flat id: u32,
}

// Named stages, referenced by a pipeline
vs :: proc "vertex"(
	data: ^Data | SV_Data,
	vid: u32 | SV_Vertex,
) -> (out: VS_Out) {
	out.pos = vec4(0, 0, 0, 1)
	out.uv = vec2(0, 0)
	out.id = vid
	return out
}

fs :: proc "fragment"(
	fsin: VS_Out,
	data: ^Data | SV_Data,
) -> (out: [4]f32 | SV_Target) {
	return data.color
}

// Raster fields omitted → gpu zero defaults. format is required on each target.
named_pipeline :: pipeline {
	topology = .Triangle_Strip,
	vertex = vs,
	fragment = fs,
	targets = {
		{
			format = .rgba_u8_srgb,
			write_mask = .All,
			blend = {
				color = { .Src_Alpha, .One_Minus_Src_Alpha, .Add },
				alpha = { .One, .One_Minus_Src_Alpha, .Add },
			},
		},
	},
}

// Inline stages. No blend → blending disabled (gpu nil default).
inline_pipeline :: pipeline {
	topology = .Triangle_List,
	cull = {.Back},
	depth_format = .depth_f32,
	vertex = proc "vertex"(data: ^Data | SV_Data, vid: u32 | SV_Vertex) -> (out: VS_Out) {
		out.pos = vec4(0, 0, 0, 1)
		out.uv = vec2(0, 0)
		out.id = 0
		return out
	},
	fragment = proc "fragment"(fsin: VS_Out, data: ^Data | SV_Data) -> (out: [4]f32 | SV_Target) {
		return vec4(fsin.uv, 0, 1)
	},
	targets = {
		{ format = .rgba_u8_srgb, write_mask = .All },
	},
}

// Multi-target: targets len must match number of SV_Target outputs
MRT :: struct {
	a, b: [4]f32 | SV_Target, // multi-name + SV_Target → two attachments
}

mrt_pipeline :: pipeline {
	vertex = vs,
	fragment = proc "fragment"(fsin: VS_Out, data: ^Data | SV_Data) -> (out: MRT) {
		out.a = data.color
		out.b = data.color
		return out
	},
	targets = {
		{ format = .rgba_u8_srgb, write_mask = .All },
		{ format = .rgba_u8_norm, write_mask = .All },
	},
}
```

### Decisions

1. **Blend** — full `Blend_State` literals only (`color` / `alpha` each `{ src, dst, op }`). No preset enums in the pipeline surface.
2. **All top-level fields optional** — checks apply only to fields that are set; cross-field checks (`targets`↔`SV_Target`, VS↔FS) only when the needed fields are all present.
3. **`targets[i].format`** — required on each listed target entry; `write_mask` / `blend` may be omitted on an entry.
4. **Keyword** — `pipeline` is the chosen form (`name :: pipeline { ... }`).
5. **Field names** — stay aligned with `gpu.Raster_Desc` / attachment descs for now.
6. **Constant** — pipelines are compile-time only; unset fields stay unset for the host conversion.
7. **Host conversion** — user maps MISL pipeline → `Raster_Desc`; no compiler metadata emit.

---

## Compilation model (host view)

MISL is consumed through a host API (and a small CLI):

1. **`create_session(Session_Desc)`** — growing arena, baked `core:builtin`, empty check cache. `desc.collections` (and each name/path) are cloned onto the session arena. No `session_add_collection`.
2. **`load_module_*`** — parse the file and its import DAG. No typecheck, no emit, no `#config`. The parser fills `module.entries` (`[]^Entry`) from `proc "vertex"` / `"fragment"` / `"compute"` / `"fmag"` and `module.pipelines` from `name :: pipeline { … }`. `entry.entity` is nil until check.
3. **`misl.check(parsed, target)`** — optional for hosts. Re-parse, then lock `#config` plus bounds/`no_gfx` plus **`MISL_MODE` from `Target.formats`** (GPU bits → `.SPIRV`, FMAG bits → `.FMAG`). Typecheck helpers + every GPU entry (`.SPIRV`) or every `proc "fmag"` (`.FMAG`). `target.no_gfx_compatibility` is OR’d with baked `MISL_COMPAT_NOGFX`.
4. **Find** an entry or pipeline by name on the **parsed** module (`find_entry_with_name` / `find_pipeline_with_name` / `for e in module.entries`).
5. **`compile_entry(entry, target, opts)`** — `check` for this Target’s Mode if needed, then emit Direct SPIR-V. `Target.flags`: `.Debug` (DebugInfo + OpLine + OpName/OpMemberName + embed source), `.No_Source` (with Debug: skip DebugSource text), `.Named_Entry` (`OpEntryPoint` uses the MISL proc name; otherwise `"main"`). Opt (`target.opt`) does not strip debug when `.Debug` is on. Assert buffer SpecId is `target.assert_buffer_spec_id` (default `0`; `mislc -assert-buffer-id:<n>`). **`compile_fmag_entry`** — same `check` for `.FMAG`, then FMAG emit.
6. **Unload** modules / destroy the session.

`check` / `check_for_diagnostics` stay for tools. The game path does not call `check` before `find_*`. `-list-entries` is parse-only.

### CLI (`mislc`)

Flags use **Odin-style** spelling only: `-flag`, `-flag:key`, or `-flag:key=value`.

```text
mislc build <input.misl> [flags]    # default if no subcommand
mislc check <input.misl> [flags]
```

| Flag | Meaning |
|------|---------|
| `-out:<dir>` | Output directory for build artifacts |
| `-target:spirv` / `-target:asm` / `-target:fmag` | Repeatable emit targets (default: spirv if none given). `asm` writes GPU `.spvasm` and `proc "fmag"` `.fmagasm`. `fmag` writes `.fmag` bytecode (`{stem}.entry.{name}.fmag` / `.fmagasm`). |
| `-o:none` / `-o:size` / `-o:performance` / `-o:all` | SPIRV-Tools optimizer after SPIR-V generation (default `none`). `performance` aliases: `perf`, `speed`. `all` is `-O` then `-Os`. Bindings are preserved. Independent of debug flags. |
| `-debug` | DebugInfo + OpLine + OpName/OpMemberName + embed MISL source (default off). |
| `-no-source` | With `-debug`: skip DebugSource text (no-op otherwise). |
| `-named-entry` | `OpEntryPoint` uses the MISL proc name (default is `"main"`). |
| `-assert-buffer-id:<n>` | Assert-buffer SpecId (u32, default `0`). |
| `-entry:<name>` | Repeatable; only these entries |
| `-pipeline:<name>` | Compile a `pipeline` constant |
| `-list-entries` | Print entry/pipeline names and exit (parse-only) |
| `-quiet` / `-verbose` | Log noise |
| `-no-bounds-check` | Default off for `[]T` index checks (overridden by `#bounds_check`) |
| `-disable-asserts` | Typecheck `debug.assert`/`panic`; emit no claim |
| `-compat:no_gfx` | no_gfx ABI: bindless sets 0–3, compute SpecIds 13370–72 with `@(size)` defaults, SPIR-V names `{stem}.vert.spv` / `.frag.spv` / `.comp.spv`. Implies `-no-bounds-check` and `-disable-asserts`. Omitted from usage when `mislc` is baked with `MISL_COMPAT_NOGFX`. |
| `-error-limit:<n>` | Cap reported errors |
| `-color:auto\|always\|never` | Diagnostics color |
| `-json` | Machine-readable diagnostics |
| `-dump:tokens` / `-dump:ast` / `-dump:types` | Allowed on **build** and **check** |
| `-dump-path:<path>` | Where dump files go; defaults to `-out` path |

Vulkan / SPIR-V language versions are **fixed** by the compiler (not CLI flags).

Examples:

```text
mislc check oge/misl/test/minimal.misl
mislc build minimal.misl -out:out/shaders_rewrite -target:spirv
mislc build main.misl -out:out -entry:sprite_vs -entry:sprite_fs
mislc check minimal.misl -dump:ast -dump-path:out/dumps
mislc shader.misl -out:out -debug -no-source
```

Exit codes: `0` ok, `1` usage, `2` parse/check errors, `3` emit/I/O failure.

---

## Relationship to Odin

MISL borrows syntax and several typing ideas from Odin (especially untyped constants and declaration style). It is a **shader dialect**, not a subset that aims for source compatibility with Odin programs. When in doubt, this document and the compiler’s grammar win over “whatever Odin does.”

Reference implementations of Odin (parser/tokenizer and the full C++ compiler) may be consulted for algorithms — for example untyped literal conversion — but their feature set is not a checklist for MISL.
