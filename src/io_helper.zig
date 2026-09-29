const std = @import("std");
const Io = std.Io;

pub fn print(device: anytype, comptime fmt: []const u8, args: anytype) !void {
    var buf: [1024]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&buf, fmt, args);

    try device.print(formatted);
}

pub fn println(device: anytype, comptime fmt: []const u8, args: anytype) !void {
    var buf: [1024]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&buf, fmt, args);

    try device.print(formatted);
    try device.print("\n");
}

pub const ZStdout = struct {
    const Self = @This();
    process_init: *const std.process.Init,

    pub fn init(process_init: *const std.process.Init) ZStdout {
        return ZStdout{
            .process_init = process_init
        };
    }

    pub fn print(self: *const Self, bytes: []const u8) !void {
        try std.Io.File.stdout().writeStreamingAll(self.process_init.io, bytes);
    }
};

pub const ZStderr = struct {
    const Self = @This();
    process_init: *const std.process.Init,

    pub fn init(process_init: *const std.process.Init) ZStderr {
        return ZStderr{
            .process_init = process_init
        };
    }

    pub fn print(self: *const Self, bytes: []const u8) !void {
        try std.Io.File.stderr().writeStreamingAll(self.process_init.io, bytes);
    }
};




pub const ZStdin = struct {
    const Self = @This();

    file_reader: std.Io.File.Reader,

    pub fn init(buf: []u8, process_init: *const std.process.Init) ZStdin {
        var inst: ZStdin = undefined;
        inst.file_reader = .init(std.Io.File.stdin(), process_init.io, buf);

        return inst;
    }

    pub fn reader(self: *Self) *std.Io.Reader {
        return &self.file_reader.interface;
    }

    pub fn read_until_delim(self: *Self, delimiter: u8) ![]const u8 {
        const result = try self.reader().takeDelimiter('\n');

        if (result == null) return "";
        const trimmed = std.mem.trim(u8, result orelse unreachable, "\r\n");

        var tokens = std.mem.splitAny(u8, trimmed, ([_]u8{delimiter})[0..]);
        const final = tokens.first();
        return final;
    }

    pub fn readln(self: *Self) ![]const u8 {
        const result = try self.reader().takeDelimiter('\n');

        if (result == null) return "";
        const trimmed = std.mem.trim(u8, result orelse unreachable, "\r\n");

        return trimmed;
    }
    
    pub fn readch(self: *Self) !u8 {
        const ch = try self.reader().take(1);
        return ch[0];
    }

    pub fn read(self: *Self) ![]const u8 {
        return self.read_until_delim(' ');
    }
};