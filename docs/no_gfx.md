
# no_gfx API Documentation

This is a high-level overview, it is more than good enough for getting started. For more info, take a look at [the procedure signatures](https://github.com/LeonardoTemperanza/no_gfx_api/blob/main/gpu/gpu.odin).

## Memory Allocation

Overview:
```odin
gpuptr :: struct { ptr: rawptr, _impl: [2]u64 }
ptr :: struct { cpu: rawptr, using gpu: gpuptr }
null :: gpuptr {}
mem_alloc_raw: proc(#any_int el_size, #any_int el_count, #any_int align: i64, mem_type := Memory.Default, alloc_type := Allocation_Type.Default, loc := #caller_location) -> ptr : _mem_alloc_raw
mem_suballoc: proc(addr: ptr, offset, el_size, el_count: i64, loc := #caller_location) -> ptr : _mem_suballoc
mem_free_raw: proc(addr: gpuptr, loc := #caller_location) : _mem_free_raw
```

**no_gfx** defines the following types of memory allocation:

- Host, a.k.a. system RAM. This is just obtained with OS API calls and does not pertain to this library.
- GPU Local, a.k.a. VRAM.
- Shared, which is GPU memory that can be written to directly from the CPU, and will be coherent w.r.t. reads which happen on the GPU. Although it is indeed GPU memory, it is still advised to use local GPU memory for large amounts of static data (e.g. vertices), as that does not require the GPU to listen to external writes. While writing to this memory on the CPU is fast, reading is not (it will cause a roundtrip back from the GPU), so be careful of not doing any accidental reads!
- Readback, shared memory that optimizes accesses for the use-case of reading back data from the GPU, not the other way around. This is less common in real-time applications.

If you've ever used CUDA before, this may seem very familiar to you:

```odin
Vertex :: struct
{
    pos: [3]f32,
    normal: [3]f32
}

// Shared memory allocation - can write to it!
verts := gpu.mem_alloc(Vertex, 3)
verts.cpu[0].pos   = { -0.5, 0.5, 0.0 }
verts.cpu[0].color = {  1.0, 0.0, 0.0 }
// verts.gpu is read coherently with these writes.

// GPU local memory allocation
verts_local := gpu.mem_alloc(Vertex, 3, gpu.Memory.GPU)
// verts_local.cpu is nil!
// Can still use verts.gpu for various operations...
```

A common pattern when uploading large amounts of static data to the GPU is to allocate a so called "staging buffer", which then gets copied into GPU local memory, like so:

```odin
Vertex :: struct
{
    pos: [3]f32,
    normal: [3]f32
}

verts := gpu.mem_alloc(Vertex, 3)
verts[0].cpu
```

The problem with this is that GPU commands are asynchronous, so we can't simply free this allocation immediately:

```odin
data_staging := gpu.mem_alloc(Some_Struct)
data_staging.cpu.test = 2

data := gpu.mem_alloc(Some_Struct, gpu.Memory.GPU)
cmd_buf := gpu.commands_begin(.Main)
gpu.cmd_mem_copy(data_local, data,
gpu.queue_submit(.Main, { cmd_buf })

// Wrong! We only submitted cmd_buf, its execution
// is still probably happening, and it's not allowed
// to remove data_staging from under the GPU's nose!
// This can be corrected by putting a gpu.wait_queue(.Main)
// right before this line, which blocks the CPU until
// cmd_buf has finished.
gpu.mem_free(data_staging)
```

If only there was a way to group allocations together and free them all at a later time... Enter the arena.

TALK ABOUT THE ARENA...

Coming from other graphics APIs, it might be surprising to you that there is no concept of "buffer object". Memory is simply allocated using mem_alloc, and then resources such as textures and BVHs are then linked to an underlying storage, like so:

```odin
texture_desc := gpu.Texture_Desc { /* ... */ }
size, align := gpu.texture_size_and_align(texture_desc)
texture_storage := gpu.mem_alloc_raw(size, 1, align)
texture := gpu.texture_create(texture_desc)
defer gpu.texture_destroy(texture)
defer gpu.mem_free_raw(texture_storage)

// In the case of textures this is a common pattern, so there's a shortcut:
texture := gpu.texture_alloc_and_create(/* texture_desc */)
defer gpu.texture_free_and_destroy(texture)
```

This flexility enables you to use different kinds of allocators and even custom ones to store your resources. For example, if you're building a videogame with predefined levels/scenes, you may decide to join all resources into a single arena, since they all share the same lifetime. You may even have temporary per-frame textures for some rendering techniques.

GPU pointers are bounds checked — at least the ones directly passed to no_gfx procedures, shader-side pointer validation is not yet present. On top of this, languages which support generics have the option to use slices. Slices are typed ranges of addresses and (in my opinion) they make the code a lot nicer to read, on top of adding some extra type-safety.

```odin
// no_gfx -> Odin slice semantics
gpu.subslice(s, 3)     // Equivalent to s[3:]
gpu.subslice(s, 3, 4)  // Equivalent to s[3:4]
gpu.slice_len(s)       // Equivalent to len(s)
gpu.slice_to_ptr(s)    // Equivalent to raw_data(s)
```

```odin
// Very small data so no need for staging.
indices := gpu.mem_alloc(u32, 6)
// ...

// Only draw last 3 indices
gpu.cmd_draw_indexed(cmd_buf, {}, {}, gpu.subslice(indices, 3))
```

TALK ABOUT SUBALLOCATIONS

## Shaders

Overview:
```odin
...
```

TALK ABOUT: NO UNIFORMS, NO BINDINGS, SINGLE GPU POINTER

## Synchronization

Overview:
```odin
...
```

Talk about semaphores.

## Render Passes

Overview:
```odin
...
```

## Descriptors

Overview:
```odin
...
```

Descriptors are tricky. It's one of those cases where the underlying Graphics APIs make things more complicated.

## Textures

Overview:
```odin
...
```

## Raytracing

Overview:
```odin
...
```

## Debug Utilities

Overview:
```odin
...
```
