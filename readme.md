# "No Graphics API" Prototype

I was feeling incredibly inspired by Sebastian Aaltonen's ["No Graphics API"](https://www.sebastianaaltonen.com/blog/no-graphics-api) blog post, so I started to implement the proposed API on top of Vulkan (except I also got rid of PSOs completely), to see how much of it is possible. It is still a proof of concept but there's a working example in this repository.

## API Usage

The API is straightforward to use:

```odin
// --- Initialization
gpu.init()
defer gpu.cleanup()
gpu.swapchain_init(surface, Frames_In_Flight)

// --- Create shaders
vert_shader := gpu.shader_create(/* ... */, .Vertex)
frag_shader := gpu.shader_create(/* ... */, .Fragment)
defer {
    gpu.shader_destroy(vert_shader)
    gpu.shader_destroy(frag_shader)
}

// --- Create arenas and allocate memory
arena := gpu.arena_init(1024 * 1024)
defer gpu.arena_destroy(&arena)

verts := gpu.arena_alloc_array(&arena, Vertex, 3)
// verts.cpu[0].pos = ...

indices := gpu.arena_alloc_array(&arena, u32, 3)
// indices.cpu[0] = ...

verts_local := gpu.mem_alloc_typed_gpu(Vertex, 3)
indices_local := gpu.mem_alloc_typed_gpu(u32, 3)
defer {
    gpu.mem_free(verts_local)
    gpu.mem_free(indices_local)
}

// --- Issue copy commands to GPU local memory
upload_cmd_buf := gpu.commands_begin(.Main)
gpu.cmd_mem_copy(upload_cmd_buf, verts.gpu, verts_local, 3 * size_of(Vertex))
// ...
gpu.cmd_barrier(upload_cmd_buf, .Transfer, .All, {})
gpu.queue_submit(.Main, { upload_cmd_buf })

// --- Frame resources
frame_arenas: [Frames_In_Flight]gpu.Arena
for &frame_arena in frame_arenas do frame_arena = gpu.arena_init(1024 * 1024)
defer for &frame_arena in frame_arenas do gpu.arena_destroy(&frame_arena)
next_frame := u64(1)
frame_sem := gpu.semaphore_create(0)
defer gpu.semaphore_destroy(&frame_sem)
for true
{
    proceed := handle_window_events(window)
    if !proceed do break

    if next_frame > Frames_In_Flight {
        gpu.semaphore_wait(frame_sem, next_frame - Frames_In_Flight)
    }
    frame_arena := &frame_arenas[next_frame % Frames_In_Flight]

    // --- Render frame
    swapchain := gpu.swapchain_acquire_next()  // Blocks CPU until at least one frame is available.

    cmd_buf := gpu.commands_begin(.Main)
    gpu.cmd_begin_render_pass(cmd_buf, {
        color_attachments = {
            { texture = swapchain, clear_color = { 1.0, 0.0, 0.0, 1.0 } }
            // Other settings...
        }
    })
    gpu.cmd_set_shaders(cmd_buf, vert_shader, frag_shader)
    Vert_Data :: struct {
        verts: rawptr,
        // Uniforms...
    }
    verts_data := gpu.arena_alloc(frame_arena, Vert_Data)
    verts_data.cpu.verts = verts_local

    // Just pass pointers to your data!
    gpu.cmd_draw_indexed_instanced(cmd_buf, verts_data.gpu, nil, indices_local, 3, 1)
    gpu.cmd_end_render_pass(cmd_buf)
    gpu.queue_submit(.Main, { cmd_buf }, frame_sem, next_frame)

    gpu.swapchain_present(.Main, frame_sem, next_frame)
    next_frame += 1

    gpu.arena_free_all(frame_arena)
}

gpu.wait_idle()  // Wait until the end of execution for resource destruction
```

For a full, working example check out the examples/example1 directory in this repository.

## Problems
There are a few problems with building this API on top of Vulkan:
1) Vulkan is still a buffer-centric API, so unfortunately in some places I needed a tree lookup for "pointer → (buffer_handle, offset)" translation. This in theory shouldn't be a huge deal as long as we do few allocations and rely on sub-allocation schemes.
2) Shader arguments are all passed via a single pointer. This prevents the prefetching discussed in the article from taking place, so I think shaders will in general be slightly slower.
3) If you're trying to debug the examples using RenderDoc, and you can't, that's because debugging of descriptor buffers is simply broken on AMD due to a driver bug, and this project uses them. [The bug has been reported](https://github.com/baldurk/renderdoc/issues/2880) on July 2025, so you can either switch to an NVidia card or annoy AMD if you want this fixed (half joking).

## Mockup Shading Language (MUSL)

For fun, I also whipped up a quick prototype of a shading language with decent pointer syntax:

```jai
Vertex :: struct
{
    pos: vec3,
    color: vec3
}

Data :: struct
{
    verts: []Vertex,
}

Output :: struct
{
    pos: vec4 @position,
    color: vec4 @out_loc(0),
}

main :: (vert_id: uint @vert_id, data: ^Data @data) -> Output
{
    vert_out: Output;
    vert_out.pos = vec4(data.verts[vert_id].pos.xyz, 1.0);
    vert_out.color = vec4(data.verts[vert_id].color, 1.0);
    return vert_out;
}
```

The compiler itself just transpiles to GLSL.

## Building (Windows)

- Update git submodules:

```bash
git submodule update --init --recursive
```

- Build Odin VMA, refer to [Odin VMA README](gpu/vma/README.md) for more details.
- [for example 6] Build ImGui, refer to [ImGui README](examples/6_imgui/odin-imgui/README.md) for more details.
- Build compiler

```bash
odin build gpu_compiler -debug -out=build/gpu_compiler.exe
```

- Build example shaders:

```bash
examples/build_shaders.bat
```

- Build examples:

```bash
examples/build.bat
```

- Or run them directly:

```bash
odin run examples/1_triangle -debug -out=build/1_triangle.exe
```

Feel free to [contact me on discord](https://discord.com/users/leon2058) for any questions.
