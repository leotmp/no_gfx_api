
package gpu

import "core:fmt"

add_debug_layer :: proc()
{
    append(&LAYERS, LAYER_DEBUG)
}

@(private="file")
Debug_Context :: struct
{
    recording: bool
}

@(private="file")
dbg: Debug_Context

LAYER_DEBUG := Layer {

    init = proc(validation := true, debugging := false, loc := #caller_location) -> bool
    {
        if !dbg.recording do return true
        serialize_call(.init, validation, loc)
        return true
    },

    cleanup = proc(loc := #caller_location) -> bool
    {
        if !dbg.recording do return true
        serialize_call(.cleanup, loc)
        return true
    },

    debug_record_begin = proc(loc := #caller_location) -> bool
    {
        dbg.recording = true

        scratch, _ := acquire_scratch()

        // Record all GPU resources
        allocs          := pool_get_alive_list(&ctx.allocs, scratch)
        textures        := pool_get_alive_list(&ctx.textures, scratch)
        bvhs            := pool_get_alive_list(&ctx.bvhs, scratch)
        shaders         := pool_get_alive_list(&ctx.shaders, scratch)
        command_buffers := pool_get_alive_list(&ctx.command_buffers, scratch)
        semaphores      := pool_get_alive_list(&ctx.semaphores, scratch)
        desc_heaps      := pool_get_alive_list(&ctx.desc_heaps, scratch)
        fmt.println("Saving state:")
        for alloc in allocs {
            fmt.println(alloc.info)
        }
        for texture in textures {
            fmt.println(texture.info)
        }
        for bvh in bvhs {
            fmt.println(bvh.info)
        }
        for shader in shaders {
            fmt.println(shader.info)
        }
        for command_buffer in command_buffers {
            fmt.println(command_buffer.info)
        }
        for semaphore in semaphores {
            fmt.println(semaphore.info)
        }
        for desc_heap in desc_heaps {
            fmt.println(desc_heap.info)
        }

        serialize_call(.debug_record_begin, loc)
        return true
    },

    debug_record_end = proc(loc := #caller_location) -> bool
    {
        serialize_call(.debug_record_end, loc)
        dbg.recording = false
        return true
    },

    commands_begin = proc(queue: Queue, loc := #caller_location) -> bool
    {
        if !dbg.recording do return true
        serialize_call(.commands_begin, queue, loc)
        return true
    },

    queue_submit = proc(queue: Queue, cmd_bufs: []Command_Buffer, loc := #caller_location) -> bool
    {
        if !dbg.recording do return true
        serialize_call(.queue_submit, cmd_bufs, loc)
        return true
    },

    cmd_begin_render_pass = proc(cmd_buf: Command_Buffer, desc: Render_Pass_Desc, loc := #caller_location) -> bool
    {
        if !dbg.recording do return true
        serialize_call(.cmd_begin_render_pass, cmd_buf, desc, loc)
        return true
    },

    cmd_end_render_pass = proc(cmd_buf: Command_Buffer, loc := #caller_location) -> bool
    {
        if !dbg.recording do return true
        serialize_call(.cmd_end_render_pass, cmd_buf, loc)
        return true
    },

    cmd_set_shaders = proc(cmd_buf: Command_Buffer, vert_shader: Shader, frag_shader: Shader, loc := #caller_location) -> bool
    {
        if !dbg.recording do return true
        serialize_call(.cmd_set_shaders, vert_shader, frag_shader, loc)
        return true
    },

    cmd_draw_indexed_raw = proc(cmd_buf: Command_Buffer, vertex_data, fragment_data, indices: gpuptr, index_format: Index_Format, index_count: u32, instance_count: u32 = 1, loc := #caller_location) -> bool
    {
        if !dbg.recording do return true
        serialize_call(.cmd_draw_indexed_raw, cmd_buf, vertex_data, fragment_data, indices, index_format, index_count, loc)
        return true
    },
}

serialize_call :: proc(lib_proc_id: Lib_Proc_ID, args: ..any)
{
    fmt.print(lib_proc_id, "- ")
    is_first := true
    for arg in args
    {
        if !is_first do fmt.print(", ")
        fmt.print(arg)
        is_first = false
    }
    fmt.println("")
}
