
package main

import "core:fmt"
import "core:os"
import "core:mem"
import vmem "core:mem/virtual"
import str "core:strings"
import "base:runtime"
import fp "core:path/filepath"
import "core:slice"
import "core:math"
import "core:flags"

import "core:sys/windows"

import glslang "glslang_odin"

Options :: struct
{
    file: ^os.File `args:"pos=0,required,file=r" usage:"Input file."`,
    out: ^os.File `args:"pos=1,file=cw" usage:"Output file. Default: 'output.spv'"`,
    print_glsl: bool `usage:"Print transpiled GLSL output."`
}

main :: proc()
{
    opt: Options
    style: flags.Parsing_Style = .Odin
    flags.parse_or_exit(&opt, os.args, style)

    if opt.out == nil
    {
        output, err := os.open("./output.spv", { .Read, .Write, .Create, .Trunc })
        ensure(err == nil)
        opt.out = output
    }

    when ODIN_OS == .Windows
    {
        handle := windows.GetStdHandle(windows.STD_OUTPUT_HANDLE)
        mode: windows.DWORD
        windows.GetConsoleMode(handle, &mode)
        windows.SetConsoleMode(handle, mode | windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING)
    }

    init_scratch_arenas()

    perm_arena_backing: vmem.Arena
    ok_a := vmem.arena_init_growing(&perm_arena_backing)
    assert(ok_a == nil)
    perm_arena := vmem.arena_allocator(&perm_arena_backing)
    defer free_all(perm_arena)

    input_path := os.args[1]
    shader_type_str := fp.ext(fp.stem(input_path))
    shader_type: Shader_Type
    if shader_type_str == ".vert" {
        shader_type = .Vertex
    } else if shader_type_str == ".frag" {
        shader_type = .Fragment
    } else if shader_type_str == ".comp" {
        shader_type = .Compute
    } else {
        fmt.println("Could not infer shader type. Try '*.vert.nosl', '*.frag.nosl', or '*.comp.nosl'.")
        os.exit(1)
    }

    // output_path_glsl := str.concatenate({ fp.dir(input_path), "/", fp.stem(input_path), ".glsl" }, allocator = perm_arena)
    output_path_spv := str.concatenate({ fp.dir(input_path), "/", fp.stem(input_path), ".spv" }, allocator = perm_arena)

    file_content, ok := load_file_and_null_terminate(input_path, allocator = perm_arena)
    if !ok
    {
        fmt.println("Error: Failed to read file.")
        os.exit(1)
    }

    file := File { input_path, file_content }

    tokens := lex_file(file, allocator = perm_arena)
    ast, ok_p := parse_file(file, tokens, allocator = perm_arena)
    if !ok_p do os.exit(1)
    ok_t := typecheck_ast(&ast, file, allocator = perm_arena)
    if !ok_t do os.exit(1)
    glsl_source := codegen(ast, shader_type, input_path)

    ok_c := compile_glsl_to_spirv(shader_type, glsl_source, input_path, output_path_spv)
    if !ok_c do os.exit(1)

    if opt.print_glsl {
        print_file_with_line_nums(glsl_source)
    }

    fmt.println(input_path)
}

load_file_and_null_terminate :: proc(path: string, allocator: runtime.Allocator) -> ([]u8, bool)
{
    file_content, err := os.read_entire_file_from_path(path, allocator = context.allocator)
    if err != nil do return {}, false
    defer delete(file_content)

    file_content_null_term := make([]u8, len(file_content) + 1, allocator = allocator)
    copy(file_content_null_term[:], file_content[:])
    file_content_null_term[len(file_content)] = 0
    return file_content_null_term, true
}

// Scratch arenas

scratch_arenas: [4]vmem.Arena

init_scratch_arenas :: proc()
{
    for &scratch in scratch_arenas
    {
        error := vmem.arena_init_growing(&scratch)
        assert(error == nil)
    }
}

@(deferred_out = release_scratch)
acquire_scratch :: proc(used_allocators: ..mem.Allocator) -> (mem.Allocator, vmem.Arena_Temp)
{
    available_arena: ^vmem.Arena
    if len(used_allocators) < 1
    {
        available_arena = &scratch_arenas[0]
    }
    else
    {
        for &scratch in scratch_arenas
        {
            for used_alloc in used_allocators
            {
                // NOTE: We assume that if the data points to the same exact address,
                // it's an arena allocator and it's the same arena
                if used_alloc.data != &scratch
                {
                    available_arena = &scratch
                    break
                }

                if available_arena != nil do break
            }
        }
    }

    assert(available_arena != nil, "Available scratch arena not found.")

    return vmem.arena_allocator(available_arena), vmem.arena_temp_begin(available_arena)
}

release_scratch :: #force_inline proc(allocator: mem.Allocator, temp: vmem.Arena_Temp)
{
    vmem.arena_temp_end(temp)
}

compile_glsl_to_spirv :: proc(shader_type: Shader_Type, glsl_source: string, input_path: string, output_path: string) -> bool
{
    stage: glslang.Stage
    switch shader_type
    {
        case .Vertex:   stage = .VERTEX
        case .Fragment: stage = .FRAGMENT
        case .Compute:  stage = .COMPUTE
    }

    scratch, _ := acquire_scratch()
    glsl_source_cstr := str.clone_to_cstring(glsl_source, allocator = scratch)

    input := glslang.input_t {
        language = .GLSL,
        stage = stage,
        client = .VULKAN,
        client_version = .VULKAN_1_3,
        target_language = .SPV,
        target_language_version = .SPV_1_5,
        code = glsl_source_cstr,
        default_version = 130,
        default_profile = .NO_PROFILE,
        force_default_version_and_profile = false,
        forward_compatible = false,
        messages = .DEFAULT_BIT,
        resource = glslang.default_resource(),
    }

    shader := glslang.shader_create(&input)
    defer glslang.shader_delete(shader)

    if glslang.shader_preprocess(shader, &input) == 0
    {
        fmt.printf("%s: GLSL preprocessing failed. This is a bug, please report.\n", input_path)
        fmt.printf("%s\n", glslang.shader_get_info_log(shader))
        fmt.printf("%s\n", glslang.shader_get_info_debug_log(shader))
        fmt.printf("GLSL source:\n")
        print_file_with_line_nums(glsl_source)
        return false
    }

    if glslang.shader_parse(shader, &input) == 0
    {
        preprocessed := str.clone_from_cstring(glslang.shader_get_preprocessed_code(shader), allocator = scratch)

        fmt.printf("%s: GLSL parsing failed. This is a bug, please report.\n", input_path)
        fmt.printf("%s\n", glslang.shader_get_info_log(shader))
        fmt.printf("%s\n", glslang.shader_get_info_debug_log(shader))
        fmt.printf("GLSL source (preprocessed):\n")
        print_file_with_line_nums(preprocessed)
        return false
    }

    program := glslang.program_create()
    defer glslang.program_delete(program)
    glslang.program_add_shader(program, shader)

    if glslang.program_link(program, .SPV_RULES_BIT | .VULKAN_RULES_BIT) == 0
    {
        fmt.printf("%s: GLSL linking failed. This is a bug, please report.\n", input_path)
        fmt.printf("%s\n", glslang.program_get_info_log(program))
        fmt.printf("%s\n", glslang.program_get_info_debug_log(program))
        return false
    }

    glslang.program_SPIRV_generate(program, stage)

    spirv_binary := make([]u32, glslang.program_SPIRV_get_size(program))
    defer delete(spirv_binary)
    glslang.program_SPIRV_get(program, raw_data(spirv_binary))

    spirv_messages := glslang.program_SPIRV_get_messages(program)
    if spirv_messages != nil {
        fmt.printf("(%s) %s\b", input_path, spirv_messages)
    }

    err := os.write_entire_file_from_bytes(output_path, slice.to_bytes(spirv_binary))
    ensure(err == nil)

    return true
}

// NOTE: Only used for debugging of compiler bugs, speed doesn't matter here.
print_file_with_line_nums :: proc(content: string)
{
    if content == "" do return

    line_count := 1
    for c in content {
        if c == '\n' do line_count += 1
    }

    cur_line := 1
    print_line_num(cur_line, line_count)
    for c in content
    {
        if c == '\n'
        {
            fmt.print("\n")
            cur_line += 1
            print_line_num(cur_line, line_count)
        }
        else
        {
            fmt.print(c)
        }
    }

    fmt.println("")

    print_line_num :: proc(line_num: int, total_line_count: int)
    {
        total_digit_count := math.count_digits_of_base(total_line_count, 10)
        line_num_digit_count := math.count_digits_of_base(line_num, 10)
        fmt.print(line_num)
        for _ in 0..<total_digit_count - line_num_digit_count + 4 {
            fmt.print(" ")
        }
    }
}
