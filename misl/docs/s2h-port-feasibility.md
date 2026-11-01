# ShaderToHuman → MISL / gpu: feasibility

Status: analysis only. Not a port. Source tree: `research/Shader2Human` (EA ShaderToHuman v13).

## Verdict

**Yes — the useful library is implementable in MISL with the current language and `oge/gpu` ABI.** No uniforms, no bound sampler/texture objects, no push-constant layout change.

It is **not** a mechanical HLSL→MISL translation. The original API leans on preprocessor, function overloading, link-time “implement this function” callbacks, and GLSL shims. A port should keep the **algorithm** (per-pixel gather overlay, optional scatter writes, optional 3D ray overlay) and express it in MISL/gpu terms.

Gather 2D (print / draw / immediate UI) and 3D ray overlays are doable today. Scatter is doable today if the user callback becomes `store(rw32_2d, …)` (or a BDA write) instead of `onGfxForAllScatter`. Tables / function plots / `sceneWithShadows` callbacks need a data-driven reshape, not new GPU ABI.

---

## What the library actually is

Header-only **immediate-mode debug overlay inside the shader**. Designed for “print a few numbers, draw a few 2D/3D gizmos” with almost no host work. Not a general UI kit and not a bindless renderer.

Three headers:

| Header | Mode | How drawing happens |
|--------|------|---------------------|
| `s2h.hlsl` | **Gather** | Every pixel (fragment or full-screen compute thread) runs the same UI code. Each call tests “does **this** pixel hit this glyph/shape?” and composites into `ContextGather.dstColor`. |
| `s2h_scatter.hlsl` | **Scatter** | One thread loops over glyph pixels and writes many destinations via user `onGfxForAllScatter(px, color)`. |
| `s2h_3d.hlsl` | **3D gather** | Per-pixel ray (`ro`, `rd`, `depth`). Primitives are IQ-style intersectors; closest hit wins. Optional `scene()` + shadow ray. |

HLSL is the source of truth. `s2h_glsl.hlsl` is a **macro shim** (`float2`→`vec2`, `lerp`→`mix`, `asuint`→`floatBitsToUint`, …). `transpileToGLSL.bat` runs the MSVC preprocessor to produce standalone `.glsl` for the WebGL docs. That is why it “works on both”: one algorithm, two spellings — not a second implementation.

### What it does **not** depend on

These look like graphics-API surface in comments/examples. They are **not** the library’s contract, and they should not become MISL/gpu requirements:

- **Uniforms / cbuffers.** Overlay state is a local `Context*` struct. Host values in examples (`iFrameBufferSize`, mouse, camera) are whatever the **host shader** already has. In MISL that is `^T \| SV_Data` (BDA via push constants), same as `Combine_Data`.
- **Bound `Texture2D` / `SamplerState`.** Core gather font is a **192-`uint` bitpacked bitmap** (`g_miniFont`), not a texture. `S2H_DISABLE_EMBEDDED_FONT` exists so a user *may* supply a texture font; that is optional. Scatter’s `RWTexture2D` is the example’s output target, not a library type.
- **Wave/subgroup, `asfloat`/`asuint`, `f16` pack, `groupshared`.** Present only in the GLSL shim. Unused by gather / scatter / 3D cores.

### What the examples *do* bind

Hello-world gather:

```hlsl
s2h_init(ui, pxPos);          // pxPos = SV_POSITION.xy or DispatchThreadID + 0.5
s2h_printTxt(ui, _H, _e, _l, _l, _o);
return lerp(background, ui.dstColor.rgb, ui.dstColor.a);
```

Pixel position comes from the stage builtin. Blend is premultiplied over the existing color. That maps 1:1 onto `combine_fs` / a debug compute pass.

Interactive widgets keep an `int4` across frames (`s2h_deinit` → next frame’s `s2h_State`) plus mouse `float4` (xy pixel, z/w buttons). In gpu terms: two fields on the existing shader-data struct, filled by the host. Not a new descriptor type.

---

## MISL / gpu as they stand (relevant bits)

Language: Odin-like, lowers to Vulkan GLSL / SPIR-V.

Already enough for the **math and control flow**:

- Structs, `#ref` (GLSL `inout`), named/unnamed results, helpers, `import`
- Vectors/matrices, swizzles, bitwise, `clamp` / `lerp` / `fract` / `mag` / `isqrt` / `atan2` / `acos` / `step` / `dot` / `normalize`
- C-style `for` with **runtime** bounds (see `data/shader/main.misl` flare loop, `test/branch_basic.misl`)
- Local arrays + runtime index (sprite vertex `positions := [4]vec2 { … }; positions[vertex_id]`)
- Fragment `SV_Position` is `gl_FragCoord` (window pixels) — exactly S2H’s `pxPos`
- Compute: `SV_Global_Thread`, `@(size=…)`, `store(rw32_2d, [2]i32, [4]f32)`, `cmd_dispatch`
- Bindless ids `t32_2d` / `s32` / `rw32_2d`; BDA `^T` / `[^]T` / `[]T` on `SV_Data`
- `#config` / `when` for stripping debug code at load time
- `#ref` structs lower to GLSL `inout`

Explicitly **out** (and used or implied by a naïve S2H clone):

| S2H / HLSL | MISL today |
|------------|------------|
| Function overloading (`printTxt` 1–6 args) | **[out]** — unique names |
| Default arguments | Parsed, then **error** (`test/fail/default_param.misl`) |
| `#define`, `#ifdef S2H_GLSL` | No preprocessor; `when` + `#config` + constants |
| `'A'` / rune as integer | Lexer has `.Rune`; checker does not type it. Language doc: strings/runes **[out]** as values. `_A = 65` constants already exist in S2H for GLSL |
| `while` | No keyword; `for ; cond; { }` |
| `if (float_mask)` HLSL truthiness | Condition must be `b32` (`mask > 0`) |
| Link-time callbacks (`onGfxForAllScatter`, `s2h_tableLookupInt`, `scene`) | Import is a **DAG**. An imported module cannot call the importer. No proc values / `$T` |
| `transmute` / `asuint` | **[out]** — unused by core |
| Recursion | Hard error — S2H cores are non-recursive |
| Device stores from VS/FS | Hard error for BDA. `store(rw*)` is a different path (imageStore). Fragment image stores need `fragmentStoresAndAtomics` (gpu turns this on with `.Assert_Buffer`, not as a general scatter feature) |

Codegen gap that matters for the **font**:

- Module-level `::` constants are **inlined** when they have an `Exact_Value`. Array compound literals are marked constant but **do not** store an array `Exact_Value`.
- GLSL emit: array compound literals are not free expressions; they must be assigned. Locals work (element-wise fill into a temp).
- A `MINI_FONT :: [192]u32{…}` used as `MINI_FONT[i]` with a **runtime** `i` has no robust lowering today (no global `const uint arr[192] = uint[](…)` emit).

gpu ABI: **do not change**. Overlay inputs are fields on existing `^Shader_Data`. Scatter writes `rw32_2d` or a BDA. Font-as-buffer is `[^]u32` / `[]u32` on that same struct.

---

## Feature map (algorithm → MISL)

### Gather 2D — **yes, current MISL**

This is the product. Print, boxes, discs, lines, arrows, coordinate system, buttons, sliders, frames.

Per-pixel coverage, not a mesh. `printCharacter` computes local pixel in the 8×8 glyph, `fontLookup` tests one bit, lerps `dstColor`. Shapes use `saturate(radius - length(px))` etc.

Sketch (not a port):

```misl
import "s2h/s2h.misl"

combine_fs :: proc "fragment"(
	fin: Fullscreen_VS_Out,
	data: ^Combine_Data | SV_Data,
) -> (out: [4]f32 | SV_Target) {
	color := /* existing combine */
	ui := s2h.init(fin.pos.xy)
	ui.mouse = data.s2h_mouse
	ui.state = data.s2h_state
	s2h.set_cursor(&ui, {10, 10})  // #ref call site; `&` is the ref marker, not a stack pointer
	s2h.print_txt(&ui, s2h.H, s2h.e, s2h.l, s2h.l, s2h.o)
	s2h.print_int(&ui, data.flare_count)
	color.rgb = lerp(color.rgb, ui.dst.rgb, ui.dst.a)
	return color
}
```

`#ref ui: Context` is the S2H `inout ContextGather`. Prefer `init() -> Context` plus `#ref` mutators so `out` params are unnecessary.

`print_txt` overloads → `print_txt2`…`print_txt6`, or one `print_txt(ui, chars: [6]u32)` with `0` terminator, or only `print_char` and let the user write a tiny helper. ASCII table is `H :: 72` (already how GLSL S2H works).

`while (tmp != 0)` in `printInt` → C-style `for ; tmp != 0; { … }`. Digit count is ≤ 10 for `u32`; fine for SPIR-V.

**Font without new language:**

1. **Preferred with current features:** host uploads 192 `u32`s once; shader data has `font: [^]u32` or `[]u32`. Lookup is `font[dword_id]`. Matches BDA style; not a texture; not an ABI change.
2. **Zero host, heavier codegen:** local `[192]u32{…}` inside `font_lookup`. Same pattern as sprite `positions`. Risk: glslang may **not** hoist 192 stores if this is called per character per pixel — measure before relying on it.
3. **Language improvement (see below):** emit module-scope const arrays as GLSL global `const`.

Interactive UI: pass `mouse: [4]f32` and `state: [4]i32` on `Combine_Data` (or a debug-only struct). Host copies `state` back from a tiny persistent buffer **or** keeps it on the CPU (sliders already run on every pixel; the “next frame” state is just which widget is captured). A CPU copy of `int4` is enough if the host writes it into shader data each frame. No extra descriptor.

### Scatter — **yes, with API reshape (not ABI)**

Original: user implements `onGfxForAllScatter`. That is link-time patching in one translation unit. MISL imports cannot call back into the user module.

Port: library takes the destination explicitly:

```misl
print_char_scatter :: proc(#ref ui: Context_Scatter, ascii: u32, dst: rw32_2d) {
	for y := 0; y < 8 * ui.scale; y += 1 {
		for x := 0; x < 8 * ui.scale; x += 1 {
			if font_lookup(ascii, {x, y} / ui.scale) {
				store(dst, ui.cursor + {x, y}, ui.text_color)
			}
		}
	}
}
```

Host: `write_rw_texture_descriptor`, `cmd_dispatch`. Already exists. Prefer **compute** for scatter (graphics entries cannot BDA-store; fragment `imageStore` is a feature we should not require). Gather overlay in fragment remains the cheap path.

### 3D overlay — **yes, current MISL**

Ray-sphere / box / cylinder / cone, checkerboard, skybox (uses gather text for ±X/±Z labels). All scalar math + `matrix[4,4]f32 * [4]f32`. Camera ray from existing `camera` / inv-VP on shader data (`gpu.flatten`). Same gather blend onto `SV_Target`.

`scene(inout Context3D)` + `sceneWithShadows` calling `scene` twice: **cannot live in an imported library** that calls a user proc. Port as:

- Library: `init`, `draw_aabb`, `draw_sphere`, … only.
- User writes `scene` in **their** module and, if they want shadows, the 15-line shadow-ray loop (documented snippet), or a helper they paste.

Do not add GPU function pointers. GLSL cannot express them; S2H only gets “callbacks” because everything is one TU.

### Tables / function plots — **yes, data-driven**

Disabled under `S2H_GLSL` in the original (forward-declared user lookups). Same problem in MISL, worse with modules.

Port: `table_int(#ref ui, values: []i32, …)` / `plot(#ref ui, ys: []f32, range, …)`. Slices are already first-class on BDA. No callback.

---

## Language features that would help (ranked)

None of these are required to ship a useful gather overlay. They make the port closer to the original API or cheaper to compile.

### Would actually help this library

1. **Module-level const arrays emitted as GLSL `const T name[N] = T[](…)`**  
   Embedded 192-`uint` font without host buffer and without 192 stores per lookup. Also useful for any LUT. Today `::` arrays have no `Exact_Value` and are skipped in global emit.

2. **Rune literals as untyped integers** (`'A'` → 65)  
   Lexer already tokenizes `.Rune`; checker/codegen ignore it. S2H GLSL already uses `_A` constants; runes are convenience, not a blocker. Do **not** add a `rune` value type for shaders.

3. **Procedure overloading (or default params lowered to overloads)**  
   `print_txt` 1–6 `u32`s. Vulkan GLSL already allows overloading; MISL forbids it. Workaround: numbered procs / `[N]u32`. Default params are currently a hard error.

### Nice, not needed

4. `while` as sugar for `for ; cond;`.  
5. `saturate(x)` alias for `clamp(x, 0, 1)`.  
6. `out` parameter distinct from `#ref` — named results already cover `init() -> Context`.  
7. Constant **procedure parameters** that the compiler **must inline** (not true fn pointers). Would restore `table_int(ui, lookup, …)` and `sceneWithShadows(scene)`. Bigger language than this port is worth; slices are the MISL-shaped substitute.

### Do not add for this port

- Uniforms / `layout(binding=)` sampler2D / traditional texture objects  
- Wave ops, `transmute`, packHalf, workgroup scatter  
- Recursion, `$T`, proc values as runtime values  
- Growing `PC_Graphics` / `PC_Compute`  
- Fragment image stores as a required feature (compute + `rw32_2d` is the scatter path)

---

## gpu / gfx host

No alloc/draw signature changes.

Optional gfx wiring (application layer, not ABI):

| Need | How |
|------|-----|
| Pixel overlay | Call gather from `combine_fs` (or a dedicated fullscreen pass). `SV_Position.xy` is already pixel centre-ish (`gl_FragCoord`). |
| Mouse / UI capture `int4` | Fields on `Combine_Data` (or a debug struct). CPU keeps last `int4`. |
| Resolution | Already `data.resolution`. |
| Scatter | Compute dispatch over 1 thread (or a small group) + `rw32_2d` of the debug target. |
| Font BDA | `gpu.make` 192 `u32`s once at init; device pointer in shader data. |
| Strip in shipping | `when #config(S2H, false)` around overlay calls, or don’t import the module. |

`.Assert_Buffer` already enables fragment stores+atomics for the assert record. Do not piggyback scatter on that.

---

## GLSL lowering notes

S2H’s GLSL path is “HLSL with macros,” not idiomatic GLSL. MISL already **is** the GLSL-constrained dialect:

- No default args → they used overloads; we use unique names.
- No `'A'` in GLSL → they used `_A`; we use `A :: 65`.
- Tables/plots `#ifndef S2H_GLSL` → we use slices.
- `mul(M,v)` shim is `(a)*(b)` (GLSL column-vector). MISL `matrix * vec` matches gpu’s flattened column-major layout. Do not copy HLSL `mul` confusion.

Dynamic loops and dynamic index of a **runtime** array are already used in production shaders. WebGL 2 limits in the docs site are irrelevant; we target Vulkan GLSL.

Cost: gather re-executes **all** overlay calls on **every** pixel. That is intentional. Keep usage small (their README). `#config` to compile it out.

---

## Suggested MISL module split

```
oge/misl/lib/s2h/s2h.misl          // gather: context, font, print, 2d, widgets
oge/misl/lib/s2h/s2h_scatter.misl  // scatter loops + store(rw32_2d) / optional BDA
oge/misl/lib/s2h/s2h_3d.misl       // ray context + intersect/draw (no scene callback)
```

Collection e.g. `import "s2h:s2h.misl"` once a collection root is registered. Do not put this in `core:`.

Host Odin types for mouse/state/font pointer live next to the shader struct in gfx (layout match, `#align(16)`), not as new gpu primitives.

---

## Approaches

### A — Gather-only shader library (recommended first)

Port `ContextGather` + print/draw/widgets into `s2h.misl`. Font via BDA or local array. Hook optionally from `combine_fs` behind `#config`. No overloading, no callbacks, no gpu ABI, no scatter/3D.

**Pros:** Small, matches how people actually use S2H (print numbers on the pass they are debugging). Proves `#ref` structs, font lookup, blend.  
**Cons:** Not feature-complete vs the repo.

### B — A + 3D primitives + scatter via `rw32_2d`

Same as A, plus `s2h_3d.misl` (user-written scene) and scatter that takes `rw32_2d`. Tables take `[]T`.

**Pros:** Covers the three headers. Still no ABI.  
**Cons:** More compile cost if imported into hot shaders; scatter needs a compute pass in gfx.

### C — Language work first, then a closer clone

Const-array emit, rune ints, maybe overloading — then a more literal API (`print_txt` overloads, embedded font with no host buffer).

**Pros:** Nicer library surface; const arrays help other LUTs.  
**Cons:** Blocks the overlay on compiler work that is not required for a useful port. Proc-value callbacks still should not be the table/3D story.

**Recommendation:** **A**, then **B**. Treat **C** as independent MISL polish (const arrays especially), not a gate.

---

## Out of scope for a first port

- WebGL docs / Gigi techniques / gold-image Python  
- 80×25 text-screen, recorded command buffer, CUDA (upstream roadmap)  
- Gaussian-splatting example  
- Faithful `printTxt` overload names  
- Changing descriptor/push-constant ABI
