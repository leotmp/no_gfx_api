
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

    init = proc(validation := true, loc := #caller_location) -> bool
    {
        fmt.println("Hello!")
        return true
    },

    cleanup = proc(loc := #caller_location) -> bool
    {
        fmt.println("bye bye")

        serialize_call("cleanup", loc)

        return true
    },

    commands_begin = proc(queue: Queue, loc := #caller_location) -> bool
    {
        serialize_call("commands_begin", queue, loc)
        return true
    },

/*
    queue_submit = proc(queue: Queue, cmd_bufs: []Command_Buffer, loc := #caller_location) -> bool
    {
        serialize_call("queue_submit", cmd_bufs, loc)
        return true
    },

    cmd_begin_render_pass = proc(cmd_buf: Command_Buffer, desc: Render_Pass_Desc, loc := #caller_location) -> bool
    {
        serialize_call("cmd_begin_render_pass", cmd_buf, desc, loc)
        return true
    }
*/
}

serialize_call :: proc(lib_proc_name: string, args: ..any)
{
    fmt.print(lib_proc_name, "- ")
    is_first := true
    for arg in args
    {
        if !is_first do fmt.print(", ")
        fmt.print(arg)
        is_first = false
    }
    fmt.println("")
}
