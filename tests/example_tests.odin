package tests

import gpu "../gpu"
import example1 "../examples/1_triangle"
import example2 "../examples/2_textures"
import example3 "../examples/3_3D"
import example4 "../examples/4_indirect_triangles"
import example5 "../examples/5_compute_shaders"
import example6 "../examples/6_deferred_async_load"
import shared "../examples/shared"
import log "core:log"
import "core:sync"
import testing "core:testing"
import "base:runtime"

// Collect validation errors from the GPU debug hook.
validation_errors: [dynamic]string

// Only one instance of no_gfx_api can be running at a time.
test_mutex: sync.Mutex

validation_error_logger :: proc(level: log.Level, message: cstring) {
    if level != .Error {
        return
    }

    append(&validation_errors, runtime.cstring_to_string(message))
}

setup_validation_error_hook :: proc() {
    clear(&validation_errors)
    ctx := runtime.default_context()
    validation_errors = make([dynamic]string, allocator = ctx.allocator)
    gpu.Hook_Debug_Log = validation_error_logger
}

assert_no_validation_errors :: proc(t: ^testing.T) {
    gpu.Hook_Debug_Log = nil
    if len(validation_errors) == 0 {
        return
    }

    for err in validation_errors {
        log.errorf("Validation error: %s", err)
    }
    testing.fail(t)
}

@(test)
example1_validation :: proc(t: ^testing.T) {
    sync.guard(&test_mutex)
    setup_validation_error_hook()
    example1.Total_Max_Frames = 10
    example1.main()
    assert_no_validation_errors(t)
}

@(test)
example2_validation :: proc(t: ^testing.T) {
    sync.guard(&test_mutex)
    setup_validation_error_hook()
    example2.Total_Max_Frames = 10
    example2.main()
    assert_no_validation_errors(t)
    gpu.cleanup()
}

@(test)
example3_validation :: proc(t: ^testing.T) {
    sync.guard(&test_mutex)
    setup_validation_error_hook()
    example3.Total_Max_Frames = 10
    example3.main()
    assert_no_validation_errors(t)
    gpu.cleanup()
}

@(test)
example4_validation_indirect_multi :: proc(t: ^testing.T) {
    sync.guard(&test_mutex)
    setup_validation_error_hook()
    example4.Use_Indirect_Multi = true
    example4.Total_Max_Frames = 10
    example4.main()
    assert_no_validation_errors(t)
    gpu.cleanup()
}

@(test)
example4_validation_single_indirect :: proc(t: ^testing.T) {
    sync.guard(&test_mutex)
    setup_validation_error_hook()
    example4.Use_Indirect_Multi = false
    example4.Total_Max_Frames = 10
    example4.main()
    assert_no_validation_errors(t)
    gpu.cleanup()
}

@(test)
example5_validation_indirect :: proc(t: ^testing.T) {
    sync.guard(&test_mutex)
    setup_validation_error_hook()
    example5.Use_Indirect = true
    example5.Total_Max_Frames = 10
    example5.main()
    assert_no_validation_errors(t)
    gpu.cleanup()
}

@(test)
example5_validation_direct :: proc(t: ^testing.T) {
    sync.guard(&test_mutex)
    setup_validation_error_hook()
    example5.Use_Indirect = false
    example5.Total_Max_Frames = 10
    example5.main()
    assert_no_validation_errors(t)
    gpu.cleanup()
}

reset_example6_static_state :: proc() {
	example6.Selected_Texture_Type = .Albedo
	example6.Cancel_Loading_Textures = false
	example6.Next_Texture_Idx = shared.MISSING_TEXTURE_ID + 1

	delete(example6.Loaded_Textures)
	example6.Loaded_Textures = nil

	delete(example6.Image_To_Texture)
	example6.Image_To_Texture = {}

	delete(example6.Image_Uploaded)
	example6.Image_Uploaded = {}
}


@(test)
example6_validation_async :: proc(t: ^testing.T) {
    sync.guard(&test_mutex)
    reset_example6_static_state()
    setup_validation_error_hook()
    example6.Load_Textures_Async = true
    example6.Total_Max_Frames = 10
    testing.cleanup(t, proc(_: rawptr) {
        reset_example6_static_state()
    }, nil)
    example6.main()
    assert_no_validation_errors(t)
    gpu.cleanup()
}

@(test)
example6_validation_sync :: proc(t: ^testing.T) {
    sync.guard(&test_mutex)
    reset_example6_static_state()
    setup_validation_error_hook()
    example6.Load_Textures_Async = false
    example6.Total_Max_Frames = 10
    testing.cleanup(t, proc(_: rawptr) {
        reset_example6_static_state()
    }, nil)
    example6.main()
    assert_no_validation_errors(t)
    gpu.cleanup()
}
