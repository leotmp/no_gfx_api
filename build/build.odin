
#+vet !unused-imports

package build

import "core:fmt"
import "core:os"
import "core:log"
import "core:mem"
import "core:strings"
import "core:sync"
import "core:slice"
import "core:sys/info"
import "core:time"
import fp "core:path/filepath"

Command :: struct
{
    name: string,
    code: proc() -> bool,
}

COMMANDS := []Command {
    { "default",   cmd_default   },  // Not specifying any command runs this.
    { "build_all_with_slang", cmd_build_all_with_slang },
    { "vercheck",  cmd_vercheck  },
    { "check_gpu", cmd_check_gpu },
    { "compiler",  cmd_compiler  },
    { "shaders_nosl", cmd_shaders_nosl },
    { "shaders_slang", cmd_shaders_slang },
    { "run_compiler_tests", cmd_run_compiler_tests },
    { "tests_gen_local_goldens", cmd_tests_gen_local_goldens },
    { "tests_compare_local_goldens", cmd_tests_compare_local_goldens },
    { "tests_compare_global_goldens", cmd_tests_compare_global_goldens },              // Only to be used in GitHub Actions
    { "tests_gen_local_goldens_gh_actions", cmd_tests_gen_local_goldens_gh_actions },  // Only to be used in GitHub Actions
}

Example :: struct
{
    shaders_slang: [dynamic]string,
	shaders_nosl: [dynamic]string,
    input_path: string,
    output_path: string,
}

EXAMPLES: [dynamic]Example

cmd_default :: proc() -> bool
{
    cmd_check_gpu() or_return
    res := true
    res &= cmd_compiler()
    res &= cmd_build_examples_parallel()
    return res
}

cmd_build_all_with_slang :: proc() -> bool
{
    cmd_check_gpu() or_return
    res := true
    res &= cmd_build_examples_parallel(build_shaders_nosl = false, build_shaders_slang = true)
    return res
}

Shader_Stage :: enum { Vertex, Fragment, Compute }
Shader_Stages :: distinct bit_set[Shader_Stage]

cmd_vercheck :: proc() -> bool
{
    res := true
    res &= run_task("odin", "version")
    res &= run_task("glslangValidator", "--version")
    res &= run_task("slangc", "-v")
    res &= run_task("vulkaninfo", "--summary")
    return res
}

cmd_check_gpu :: proc() -> bool
{
    res := true
    res &= run_task("odin", "check", "gpu", "-no-entry-point", "-vet")
    return res
}

cmd_check_tests :: proc() -> bool
{
    res := true
    res &= run_task("odin", "check", "tests")
    return res
}

cmd_compiler :: proc() -> bool
{
    res := true
    res &= run_task("odin", "build", "nosl/tools/noslc", "-debug", with_exe_ext("-out=build/noslc"))
    return res
}

cmd_shaders_nosl :: proc() -> bool
{
    cmd_compiler() or_return
    res := true
    res &= cmd_build_examples_parallel(build_odin = false)
    return res
}

cmd_shaders_slang :: proc() -> bool
{
    cmd_compiler() or_return
    res := true
    res &= cmd_build_examples_parallel(build_odin = false, build_shaders_nosl = false, build_shaders_slang = true)
    return res
}

cmd_run_compiler_tests :: proc() -> bool
{
    cmd_compiler() or_return

    _, shaders_nosl := get_shaders_in_dir("tests")

    group: Task_Group
    defer delete_task_group(&group)
    for shader in shaders_nosl
    {
        shader_dir, _ := os.split_path(shader)
        out_flag := fmt.tprintf("-out:%v", shader_dir)
        add_task(&group, with_exe_ext("./build/noslc"), shader, out_flag, "-target:spirv", "-target:asm")
    }

    ok := run_tasks(&group)
    for task in group.tasks
    {
        shader := task.args[1]
        if task.exit_code == 0 {
            fmt.printfln("%v - Ok.", shader)
        } else {
            fmt.printfln("%v - Fail!", shader)
        }
    }
    return ok
}

cmd_tests_gen_local_goldens :: proc() -> bool
{
    cmd_run_compiler_tests() or_return
    res := true
    res &= run_task("odin", "run", "tests", "--", "gen_local_goldens")
    return res
}

cmd_tests_compare_local_goldens :: proc() -> bool
{
    cmd_run_compiler_tests() or_return
    res := true
    res &= run_task("odin", "run", "tests", "--", "compare_to_local")
    return res
}

cmd_tests_compare_global_goldens :: proc() -> bool
{
    cmd_run_compiler_tests() or_return
    res := true
    res &= run_task("odin", "run", "tests", "--", "compare_to_global", "is_gh_actions")
    return res
}

cmd_tests_gen_local_goldens_gh_actions :: proc() -> bool
{
    cmd_run_compiler_tests() or_return
    res := true
    res &= run_task("odin", "run", "tests", "--", "gen_local_goldens", "is_gh_actions")
    return res
}

main :: proc()
{
    console_logger := log.create_console_logger()
    // defer log.destroy_console_logger(console_logger)
    context.logger = console_logger

    cmd_args := os.args
    if len(cmd_args) <= 0 do exit_with_error("No arguments found.")

    change_working_dir_to_project_root()

    default_arg := []string { "default" }
    args := cmd_args[1:]
    if len(args) == 0 {
        args = default_arg
    }

    // Retrieve example names
    add_examples("examples")
    add_examples("examples/third_party", output_prefix = "third_party_")

    res := true
    for arg in args
    {
        for cmd in COMMANDS
        {
            if cmd.name == arg {
                res &= cmd.code()
                break
            }

            mem.free_all(context.temp_allocator)
        }
    }

    os.exit(int(!res))
}

// Adds examples found in dir to the EXAMPLES global variable
add_examples :: proc(dir: string, output_prefix := "")
{
    examples_dir, err_o := os.open(dir)
    defer os.close(examples_dir)
    ensure(err_o == nil)
    it := os.read_directory_iterator_create(examples_dir)
    defer os.read_directory_iterator_destroy(&it)

    for info in os.read_directory_iterator(&it)
    {
        if info.type == .Directory && info.name != "shared" && info.name != "third_party"
        {
            // NOTE: Check if directory contains .odin files. If not, skip it.
            // This can happen because when/if an example is renamed or removed,
            // git will leave an empty directory for the old name.
            if !contains_odin_files(info.fullpath) do continue

            // Look for shaders
            shaders_slang, shaders_nosl := get_shaders_in_dir(info.fullpath)

            example := Example {
                input_path = strings.clone(fmt.tprintf("%v/%v", dir, strings.clone(info.name))),
                output_path = strings.concatenate({ output_prefix, strings.clone(info.name) }),
                shaders_slang = shaders_slang,
				shaders_nosl = shaders_nosl,
            }
            append(&EXAMPLES, example)
        }
    }

    if path, err := os.read_directory_iterator_error(&it); err != nil
    {
        log.errorf("Read directory failed at %v: %v", path, err)
        return
    }
}

contains_odin_files :: proc(path: string) -> bool
{
    dir, err_o := os.open(path)
    defer os.close(dir)
    ensure(err_o == nil)
    it := os.read_directory_iterator_create(dir)
    defer os.read_directory_iterator_destroy(&it)

    for info in os.read_directory_iterator(&it)
    {
        if info.type != .Directory && fp.ext(info.name) == ".odin" {
            return true
        }
    }

    if path, err := os.read_directory_iterator_error(&it); err != nil
    {
        log.errorf("Read directory failed at %v: %v", path, err)
        return false
    }

    return false
}

get_shaders_in_dir :: proc(path: string) -> (shaders_slang: [dynamic]string, shaders_nosl: [dynamic]string)
{
    cur_example_dir, cur_example_err_o := os.open(path)
    defer os.close(cur_example_dir)
    ensure(cur_example_err_o == nil)
    cur_example_it := os.read_directory_iterator_create(cur_example_dir)
    defer os.read_directory_iterator_destroy(&cur_example_it)

    for example_info in os.read_directory_iterator(&cur_example_it)
    {
        if example_info.type == .Directory && example_info.name == "shaders"
        {
            shaders_dir, shaders_err_o := os.open(example_info.fullpath)
            defer os.close(shaders_dir)
            ensure(shaders_err_o == nil)
            shaders_it := os.read_directory_iterator_create(shaders_dir)
            defer os.read_directory_iterator_destroy(&shaders_it)
            for shader_info in os.read_directory_iterator(&shaders_it)
            {
                ext := os.ext(shader_info.name)
                if ext == ".slang"
                {
                    append(&shaders_slang, strings.clone(shader_info.fullpath))
                }
				else if ext == ".nosl"
				{
					append(&shaders_nosl, strings.clone(shader_info.fullpath))
				}
            }
        }
    }

    return shaders_slang, shaders_nosl
}

cmd_build_examples_parallel :: proc(build_odin := true, build_shaders_nosl := true, build_shaders_slang := false) -> bool
{
    res := true

    if build_shaders_nosl || build_shaders_slang
    {
        shaders: Task_Group
        defer delete_task_group(&shaders)

        for example in EXAMPLES
        {
            if build_shaders_nosl
            {
                for shader in example.shaders_nosl
                {
                    dir, _ := os.split_path(shader)
                    out_flag := fmt.tprintf("-out:%v", dir)
                    add_task(&shaders, with_exe_ext("./build/noslc"), shader, out_flag, "-target:spirv", "-target:asm")
                }
            }

            if build_shaders_slang
            {
                for shader in example.shaders_slang
                {
                    dir, _ := os.split_path(shader)
                    stages := get_slang_stages(shader)
                    if .Vertex in stages
                    {
                        spv_path := fmt.tprintf("%v/%v.vert.spv", dir, os.stem(shader))
                        add_task(&shaders, "slangc",
                                 "-target", "spirv",
                                 "-fvk-use-c-layout", "-fvk-use-scalar-layout", "-force-glsl-scalar-layout",
                                 "-validate-ir", "-no-mangle", "-entry", "vertexMain",
                                 "-stage", "vertex", shader, "-o", spv_path)
                    }
                    if .Fragment in stages
                    {
                        spv_path := fmt.tprintf("%v/%v.frag.spv", dir, os.stem(shader))
                        add_task(&shaders, "slangc",
                                 "-target", "spirv",
                                 "-fvk-use-c-layout", "-fvk-use-scalar-layout", "-force-glsl-scalar-layout",
                                 "-validate-ir", "-no-mangle", "-entry", "fragmentMain",
                                 "-stage", "fragment", shader, "-o", spv_path)
                    }
                    if .Compute in stages
                    {
                        spv_path := fmt.tprintf("%v/%v.comp.spv", dir, os.stem(shader))
                        add_task(&shaders, "slangc",
                                 "-target", "spirv",
                                 "-fvk-use-c-layout", "-fvk-use-scalar-layout", "-force-glsl-scalar-layout",
                                 "-validate-ir", "-no-mangle", "-entry", "computeMain",
                                 "-stage", "compute", shader, "-o", spv_path)
                    }
                }
            }
        }

        res &= run_tasks(&shaders)
    }

    if build_odin
    {
        builds: Task_Group
        defer delete_task_group(&builds)
        for example in EXAMPLES
        {
            out_flag := with_exe_ext(fmt.tprintf("-out=build/%v", example.output_path))
            add_task(&builds, "odin", "build", example.input_path, "-debug", out_flag)
        }
        res &= run_tasks(&builds)
    }

    return res
}

exit_with_error :: proc(fmt: string, args: ..any)
{
    log.errorf(fmt, ..args)
    os.exit(1)
}

MUTEX: sync.Mutex

// Print complete lines as they arrive. "pending" stores the current partial line
stream_pipe :: proc(src: ^os.File, pending: ^[dynamic]byte, done: ^bool, to_stdout: bool) -> bool
{
    if done^ do return false

    has_data, err := os.pipe_has_data(src)
    n := 0
    tmp: [4096]byte
    if has_data || err == .Broken_Pipe {
        n, err = os.read(src, tmp[:])
    }

    end := false
    switch err
    {
        case nil:
        {
            if n <= 0 do return false
        }
        case .EOF, .Broken_Pipe:
        {
            end = true
        }
        case:
        {
            ensure(false, "Pipe read failed.")
            return false
        }
    }

    if n > 0 do append(pending, ..tmp[:n])

    cut := 0
    if end
    {
        cut = len(pending)
    }
    else
    {
        for i := len(pending) - 1; i >= 0; i -= 1
        {
            if pending[i] == '\n' {
                cut = i + 1
                break
            }
        }
    }

    if cut > 0
    {
        if sync.mutex_guard(&MUTEX)
        {
            if to_stdout {
                fmt.print(string(pending[:cut]))
                os.flush(os.stdout)
            } else {
                fmt.eprint(string(pending[:cut]))
                os.flush(os.stderr)
            }
        }

        if cut < len(pending)
        {
            tail := slice.clone(pending[cut:])
            resize(pending, 0)
            append(pending, ..tail)
            delete(tail)
        }
        else
        {
            resize(pending, 0)
        }
    }

    if end do done^ = true
    return true
}

run_task :: proc(args: ..string, silent := false) -> bool
{
    if !silent do print_cmd(args)

    stdout_r, stdout_w, err_stdout := os.pipe()
    ensure(err_stdout == nil)
    stderr_r, stderr_w, err_stderr := os.pipe()
    ensure(err_stderr == nil)

    process, err_start := os.process_start({
        command = args,
        stdout = stdout_w,
        stderr = stderr_w,
    })
    ensure(err_start == nil)

    os.close(stdout_w)
    os.close(stderr_w)

    defer os.close(stdout_r)
    defer os.close(stderr_r)

    // Partial lines
    stdout_rest, stderr_rest: [dynamic]byte
    defer delete(stdout_rest)
    defer delete(stderr_rest)

    stdout_done, stderr_done, exited: bool
    exit_code: int
    for !exited || !stdout_done || !stderr_done
    {
        progress := false
        progress |= stream_pipe(stdout_r, &stdout_rest, &stdout_done, true)
        progress |= stream_pipe(stderr_r, &stderr_rest, &stderr_done, false)

        if !exited
        {
            state, err_wait := os.process_wait(process, 0)
            if err_wait == nil {
                exited = true
                exit_code = state.exit_code
                progress = true
            } else if err_wait != .Timeout {
                log.errorf("Failed to run command %v: %v.", args, err_wait)
                return false
            }
        }

        if !progress do time.sleep(10 * time.Millisecond)
    }

    return exit_code == 0
}

print_cmd :: proc(args: []string)
{
    if sync.mutex_guard(&MUTEX)
    {
        for arg, i in args {
            fmt.printf("%v", arg)
            if i < len(args)-1 do fmt.print(" ")
        }
        fmt.println("")
    }
}

with_exe_ext :: proc(str: string) -> string
{
    when ODIN_OS == .Windows {
        return fmt.tprintf("%v.exe", str)
    } else {
        return str
    }
}

change_working_dir_to_project_root :: proc()
{
    process_info, err := os.current_process_info({.Executable_Path}, allocator = context.temp_allocator)
    ensure(err == nil, "Could not get current process info")

    exe_path := process_info.executable_path

    exe_path_abs, err_a := os.get_absolute_path(exe_path, allocator = context.temp_allocator)
    ensure(err_a == nil)

    // "odin run" creates an .exe at the current working directory, so support that case as well.
    exe_dir := fp.dir(exe_path_abs)
    if os.stem(exe_dir) == "build"
    {
        root_dir := fp.dir(exe_dir)
        os.chdir(root_dir)
    }
    else if os.stem(exe_dir) == "no_gfx_api"
    {
        os.chdir(exe_dir)
    }
    else
    {
        exit_with_error("Incorrect executable directory '%v', must be either 'no_gfx_api' or 'build'.", os.stem(exe_dir))
    }
}

get_slang_stages :: proc(path: string) -> Shader_Stages
{
    content, err := os.read_entire_file(path, allocator = context.allocator)
    defer delete(content)
    ensure(err == nil)

    content_str := string(content)
    res: Shader_Stages
    if strings.contains(content_str, "[shader(\"vertex\")]")   do res += { .Vertex }
    if strings.contains(content_str, "[shader(\"fragment\")]") do res += { .Fragment }
    if strings.contains(content_str, "[shader(\"compute\")]")  do res += { .Compute }
    return res
}

// Task running API
Task :: struct
{
    args: [dynamic]string,
    silent: bool,
    exit_code: int,
}

Task_Group :: struct
{
    tasks: [dynamic]Task
}

delete_task_group :: proc(group: ^Task_Group)
{
    for task in group.tasks {
        delete(task.args)
    }
    delete(group.tasks)
}

add_task :: proc(group: ^Task_Group, args: ..string, silent := false)
{
    append(&group.tasks, Task {
        args = slice.clone_to_dynamic(args[:]),
        silent = silent
    })
}

run_tasks :: proc(group: ^Task_Group) -> bool
{
    all_ok := true

    Process_State :: struct {
        process: os.Process,
        task_idx: int,
        stdout_r, stderr_r: ^os.File,
        stdout_rest, stderr_rest: [dynamic]byte,
        stdout_done, stderr_done: bool,
        exited: bool,
        finished: bool,
    }

    _, num_cores, ok_cores := info.cpu_core_count()
    ensure(ok_cores)

    for i in 0..< ((len(group.tasks) - 1) / num_cores) + 1
    {
        processes: [dynamic]Process_State
        defer
        {
            for &process in processes
            {
                if process.stdout_r != nil do os.close(process.stdout_r)
                if process.stderr_r != nil do os.close(process.stderr_r)
                delete(process.stdout_rest)
                delete(process.stderr_rest)
            }
            delete(processes)
        }

        // Launch processes
        for j in 0..<num_cores
        {
            task_idx := i * num_cores + j
            if task_idx >= len(group.tasks) do break

            task := group.tasks[task_idx]
            if !task.silent do print_cmd(task.args[:])

            stdout_r, stdout_w, err_out := os.pipe()
            ensure(err_out == nil)
            stderr_r, stderr_w, err_err := os.pipe()
            ensure(err_err == nil)

            process, err_start := os.process_start({
                command = task.args[:],
                stdout = stdout_w,
                stderr = stderr_w,
            })
            ensure(err_start == nil)

            os.close(stdout_w)
            os.close(stderr_w)

            append(&processes, Process_State {
                process = process,
                task_idx = task_idx,
                stdout_r = stdout_r,
                stderr_r = stderr_r,
            })
        }

        // Wait on processes and stream stderr and stdout
        num_remaining := len(processes)
        for num_remaining > 0
        {
            progress := false
            for &process in processes
            {
                if process.finished do continue

                progress |= stream_pipe(process.stdout_r, &process.stdout_rest, &process.stdout_done, true)
                progress |= stream_pipe(process.stderr_r, &process.stderr_rest, &process.stderr_done, false)

                if !process.exited
                {
                    state, err_wait := os.process_wait(process.process, 0)
                    if err_wait == nil {
                        process.exited = true
                        group.tasks[process.task_idx].exit_code = state.exit_code
                        if state.exit_code != 0 do all_ok = false
                        progress = true
                    } else {
                        ensure(err_wait == .Timeout)
                    }
                }

                if process.exited && process.stdout_done && process.stderr_done
                {
                    process.finished = true
                    num_remaining -= 1
                }
            }

            if !progress do time.sleep(10 * time.Millisecond)
        }
    }

    return all_ok
}
