const std = @import("std");
const fox16 = @import("./fox16.zig");
const assembler = @import("./assembler.zig");
const Io = std.Io;
const gpa = std.heap.page_allocator;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len == 1) return;

    const mode = args[1];
    if (args.len == 2){
        std.debug.print("expected mode arguments\n", .{});
        std.debug.print("   -c FILENAME.f16     : assemble a file\n", .{});
        std.debug.print("   -o FILENAME.xf      : execute an assembled file\n", .{});
        std.process.exit(3);
    }

    if (std.mem.eql(u8, mode, "-c")){
        try test_assembler(init, args[2..], arena);
    }

    else if (std.mem.eql(u8, mode, "-r")){
        try test_execution(init, args[2..], arena);
    }
}



pub fn test_assembler(init: std.process.Init, args: []const []const u8, arena_alloc: std.mem.Allocator) !void {

    // read source file

    const file_name = args[0];
    _, const source = fox16.io_helper.read_file(init.io, arena_alloc, file_name);

    // lex
    var lexer = assembler.Lexer.init(init.arena, source);
    const tokens = lexer.lex() catch {
        std.log.err("fatal tokenization error", .{});
        std.process.exit(1);
        return &[_]assembler.Token{};
    };

    // compile
    var compiler = assembler.Compiler.init(tokens);
    defer compiler.deinit();
    compiler.compile_all() catch {
        std.log.err("fatal compilation error", .{});
        std.process.exit(1);
    };
    compiler.resolve_labels() catch {
        std.log.err("fatal post-compilation error", .{});
        std.process.exit(1);
    };

    // log
    var machine_code_builder: std.ArrayList(u8) = .empty;
    defer machine_code_builder.deinit(gpa);

    var buf: [1024]u8 = undefined;
    for (compiler.program.items) |inst| {
        const result = try std.fmt.bufPrint(&buf, "{X} ", .{inst});
        try machine_code_builder.appendSlice(gpa, result);
    }

    // make new name
    const new_file_name = try std.fmt.bufPrint(&buf, "{s}.xf", .{file_name});

    // write final contents
    const owned = try arena_alloc.dupe(u8, machine_code_builder.items);
    fox16.io_helper.write_file(init.io, new_file_name, owned);
}



pub fn test_execution(init: std.process.Init, args: []const []const u8, arena_alloc: std.mem.Allocator) !void {
    const file_name = args[0];

    _, const contents = fox16.io_helper.read_file(init.io, arena_alloc, file_name);

    // get each hexadecimal value and add them to program.
    var program_builder: std.ArrayList(u32) = .empty;
    defer program_builder.deinit(gpa);

    var split_iterator = std.mem.splitAny(u8, contents, " ");
    
    while (split_iterator.next()) |part| {
        const num = std.fmt.parseInt(i32, part, 16) catch -1;
        if (num == -1){
            std.log.warn("invalid instruction '{s}'", .{part});
        }
        try program_builder.append(gpa, @intCast(@max(num, 0)));
    }

    // turn into slice
    const slice = try arena_alloc.dupe(u32, program_builder.items);

    // make cpu and insert the program
    var stdout = fox16.io_helper.ZStdout.init(&init);
    var stderr = fox16.io_helper.ZStderr.init(&init);

    var buf: [1024]u8 = undefined;
    var stdin = fox16.io_helper.ZStdin.init(&buf, &init);

    var cpu = fox16.CPU.new(&stdout, &stderr, &stdin);
    defer cpu.deinit();

    cpu.put_program(slice);

    // execute
    cpu.execute_all() catch {
        std.log.err("fatal execution error", .{});
        std.process.exit(1);
    };
}


