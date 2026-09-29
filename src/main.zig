const std = @import("std");
const fox16 = @import("./fox16.zig");
const assembler = @import("./assembler.zig");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    try test_assembler(init);
}



pub fn test_assembler(init: std.process.Init) !void {
    const source: []const u8 = 
        \\ mov r1, 100
        \\ syscall 256
    ;

    var lexer = assembler.Lexer.init(init.arena, source);
    const tokens = try lexer.lex();

    var compiler = assembler.Compiler.init(tokens);
    defer compiler.deinit();

    try compiler.compile_all();

    for (compiler.program.items) |inst| {
        std.debug.print("{X} ", .{inst});
    }

    std.debug.print("\n", .{});
}





pub fn test_cpu(init: std.process.Init) !void {
    var stdout = fox16.io_helper.ZStdout.init(&init);
    var stderr = fox16.io_helper.ZStderr.init(&init);

    var buf: [1024]u8 = undefined;
    var stdin = fox16.io_helper.ZStdin.init(&buf, &init);

    var cpu: fox16.CPU = fox16.CPU.new(&stdout, &stderr, &stdin);
    defer cpu.deinit();

    var program = [_]u32{
    };

    cpu.put_program(&program);
    try cpu.execute_all();
}