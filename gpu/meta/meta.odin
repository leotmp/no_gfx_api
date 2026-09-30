
package meta

import "core:fmt"
import "core:os"
import "core:odin/ast"
import "core:odin/parser"

main :: proc()
{
    if len(os.args) != 2 {
        fmt.eprintln("usage: meta <source_path.odin> <dst_path.odin>")
        return
    }

    src_path := os.args[1]
    dst_path := os.args[2]
    generate_code(src_path, dst_path)
}

generate_code :: proc(source_path: string, dst_path: string)
{
    data, err := os.read_entire_file(source_path, allocator = context.allocator)
    if err != nil
    {
        fmt.eprintln("failed to read file:", err)
        return
    }
    defer delete(data)

    file := ast.File {
        fullpath = source_path,
        src      = string(data),
    }

    p := parser.default_parser()

    if !parser.parse_file(&p, &file)
    {
        fmt.eprintln("Failed to parse:", source_path)
        return
    }

    // sb := strings.

    for stmt in file.decls {
        analyze_proc(stmt)
    }
}

analyze_proc :: proc(stmt: ^ast.Stmt) -> bool
{
    decl := stmt.derived_stmt.(^ast.Value_Decl) or_return
    if decl.type == nil do return false
    _ = decl.type.derived_expr.(^ast.Proc_Type) or_return

    for name in decl.names
    {
        ident := name.derived_expr.(^ast.Ident) or_continue

        fmt.println(ident.name)
    }

    return true
}
