
package main

import "core:fmt"
import "core:log"

import "../../gpu"

main :: proc()
{
    console_logger := log.create_console_logger()
    defer log.destroy_console_logger(console_logger)
    context.logger = console_logger

    ok := gpu.init()
    ensure(ok)
    defer gpu.cleanup()
}
