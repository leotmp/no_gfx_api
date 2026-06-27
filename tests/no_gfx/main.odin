
package main

import "core:fmt"

import "../../gpu"

main :: proc()
{
    ok := gpu.init()
    ensure(ok)
    defer gpu.cleanup()
}
