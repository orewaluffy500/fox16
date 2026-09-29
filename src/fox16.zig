const std = @import("std");
const alloc = std.heap.page_allocator;

pub const io_helper = @import("./io_helper.zig");
pub const defs = @import("./foxconst.zig");

// COMP INFO struct

const CompInfo = struct {
    const Self = @This();

    equal: bool = false,
    larger: bool = false,
    smaller: bool = false,

    pub fn feed(self: *Self, operand1: u16, operand2: u16) void {
        self.equal = operand1 == operand2;
        self.larger = operand1 > operand2;
        self.smaller = operand1 < operand2;
    }
};

const ArithOper = enum { add, sub, mul, div, pow, none };

const ArithInfo = struct {
    const Self = @This();

    oper: ArithOper = .none,
    operand1: u16 = 0,
    operand2: u16 = 0,

    pub fn feed(self: *Self, oper: ArithOper, operand1: u16, operand2: u16) void {
        self.operand1 = operand1;
        self.operand2 = operand2;
        self.oper = oper;
    }

    pub fn eval(self: *Self) u16 {
        switch (self.oper) {
            .add => {
                return self.operand1 +% self.operand2;
            },
            .sub => {
                return self.operand1 -% self.operand2;
            },
            .mul => {
                return self.operand1 *% self.operand2;
            },
            .div => {
                return self.operand1 / self.operand2;
            },
            .pow => {
                return defs.safe_pow(self.operand1, self.operand2);
            },
            .none => {
                return self.operand1;
            },
        }
    }

    pub fn feed_and_eval(self: *Self, oper: ArithOper, operand1: u16, operand2: u16) u16 {
        self.feed(oper, operand1, operand2);
        return self.eval();
    }
};

// CPU struct
pub const CPU = struct {
    const Self = CPU;

    memory: Memory(65536) = .{},
    register_file: [129]u16 = [_]u16{0} ** 129,
    program_file: [16384]u32 = [_]u32{0} ** 16384,

    call_stack: std.ArrayList(usize),
    comp_info: CompInfo = .{},
    arith_info: ArithInfo = .{},
    pc: usize = 0,

    stdout: *io_helper.ZStdout,
    stderr: *io_helper.ZStderr,
    stdin: *io_helper.ZStdin,

    pub fn new(stdout: *io_helper.ZStdout, stderr: *io_helper.ZStderr, stdin: *io_helper.ZStdin) CPU {
        return CPU{ .stdin = stdin, .stdout = stdout, .stderr = stderr, .call_stack = std.ArrayList(usize){
            .items = &.{},
            .capacity = 0,
        } };
    }

    pub fn deinit(self: *Self) void {
        self.call_stack.deinit(alloc);
    }

    pub fn next(self: *Self) u32 {
        self.pc += 1;
        return self.program_file[self.pc - 1];
    }

    pub fn execute(self: *Self) !bool {
        const instruction = self.next();

        switch (instruction) {
            defs.Instructions.HALT => {
                return false;
            },
            defs.Instructions.NOP => {},
            defs.Instructions.SYSCALL => {
                const syscall = self.next();
                try self.handle_syscall(syscall);
            },

            // REGISTER-RELATED
            defs.Instructions.MOV => {
                const index = self.next();
                const value = self.next_value();

                self.set_register(index, value);
            },

            defs.Instructions.ZZ => {
                const index = self.next();
                self.set_register(index, 0);
            },

            // STACK RELATED
            defs.Instructions.LD => {
                const out = self.next();
                const offset = self.next_value();
                self.set_register(out, self.memory.read(offset));
            },

            defs.Instructions.ST => {
                const offset = self.next_value();
                const value = self.next_value();
                self.memory.write(offset, value);
            },

            defs.Instructions.SPI => {
                const value = self.next_value();
                self.memory.sp +%= value;
            },

            defs.Instructions.SPD => {
                const value = self.next_value();
                self.memory.sp -%= value;
            },

            // FLOW-RELATED
            defs.Instructions.JMP => {
                const dest = self.next();
                self.jump(dest);
            },

            defs.Instructions.CALL => {
                const dest = self.next();
                try self.call_stack.append(alloc, self.pc);
                self.jump(dest);
            },

            defs.Instructions.RET => {
                if (self.call_stack.items.len < 1) {
                    self.runtime_fault("unable to return from empty call stack", .{});
                }
                const dest = self.call_stack.pop() orelse unreachable;
                self.pc = dest;
            },

            defs.Instructions.JZ => {
                const dest = self.next();
                const operand = self.next_value();
                if (operand == 0) self.jump(dest);
            },

            defs.Instructions.JNZ => {
                const dest = self.next();
                const operand = self.next_value();
                if (operand != 0) self.jump(dest);
            },

            defs.Instructions.JE => {
                const dest = self.next();
                if (self.comp_info.equal) self.jump(dest);
            },

            defs.Instructions.JNE => {
                const dest = self.next();
                if (!self.comp_info.equal) self.jump(dest);
            },

            defs.Instructions.JLE => {
                const dest = self.next();
                if (self.comp_info.smaller or self.comp_info.equal) self.jump(dest);
            },

            defs.Instructions.JGE => {
                const dest = self.next();
                if (self.comp_info.larger or self.comp_info.equal) self.jump(dest);
            },

            defs.Instructions.JL => {
                const dest = self.next();
                if (self.comp_info.smaller) self.jump(dest);
            },

            defs.Instructions.JG => {
                const dest = self.next();
                if (self.comp_info.larger) self.jump(dest);
            },

            defs.Instructions.CMP => {
                const operand1 = self.next_value();
                const operand2 = self.next_value();

                self.comp_info.feed(operand1, operand2);
            },

            // ARITHMETIC OPERATIONS

            defs.Instructions.ADD => {
                self.do_arith_oper(.add);
            },

            defs.Instructions.SUB => {
                self.do_arith_oper(.sub);
            },

            defs.Instructions.MUL => {
                self.do_arith_oper(.mul);
            },

            defs.Instructions.DIV => {
                self.do_arith_oper(.div);
            },

            defs.Instructions.POW => {
                self.do_arith_oper(.pow);
            },

            else => {
                self.runtime_fault("unexpected instruction '{}'", .{instruction});
            },
        }

        return true;
    }

    pub fn execute_all(self: *Self) !void {
        while (try self.execute()) {}
    }

    // HELPERS

    fn jump(self: *Self, dest: u32) void {
        if (dest < 0 or dest >= self.program_file.len) {
            self.runtime_fault("out of bounds jump destination '{}'", .{dest});
        }

        self.pc = dest;
    }

    fn runtime_fault(self: *Self, comptime fmt: []const u8, args: anytype) void {
        std.debug.print("runtime fault: ", .{});
        std.debug.print(fmt, args);
        std.debug.print(" (at {})\n", .{self.pc});
        std.process.exit(1);
    }

    pub fn put_program(self: *Self, data: []u32) void {
        @memcpy(self.program_file[0..data.len], data);
    }

    pub fn get_register(self: *Self, register: usize) u16 {
        if (register < 0 or register >= self.register_file.len) {
            self.runtime_fault("out of bounds registers '{}'", .{register});
        }
        return self.register_file[register];
    }

    pub fn set_register(self: *Self, register: usize, value: anytype) void {
        _ = self.get_register(register);
        self.register_file[register] = @truncate(value);
    }

    pub fn get_from_stack(self: *Self, offset: usize) u16 {
        if (offset < 0 or offset >= self.memory.stack.len) {
            self.runtime_fault("invalid offset '{}'", .{offset});
        }

        return self.memory.read(offset);
    }

    pub fn set_to_stack(self: *Self, offset: usize, value: anytype) void {
        _ = self.get_from_stack(offset);

        self.memory.write(offset, @truncate(value));
    }

    fn next_value(self: *Self) u16 {
        const raw = self.next();
        const info = defs.decode_value(raw);
        if (info[0] == defs.Mode.CONST) {
            return @intCast(info[1]);
        } else if (info[0] == defs.Mode.SPOFFSET) {
            return @truncate(self.memory.relative_offset(@truncate(info[1])));
        } else {
            return self.get_register(@intCast(info[1]));
        }
    }

    pub fn load_as_string(self: *Self, offset: usize) ![]u8 {
        var list = std.ArrayList(u8){ .capacity = 0, .items = &.{} };
        defer list.deinit(alloc);

        var current_offset = offset;
        while (self.get_from_stack(current_offset) != 0) {
            try list.append(alloc, @truncate(self.get_from_stack(current_offset)));
            current_offset += 1;
        }

        return list.toOwnedSlice(alloc);
    }

    pub fn store_string(self: *Self, offset: usize, string: []const u8) void {
        var current_offset = offset;
        var index = current_offset - offset;
        while (index < string.len) {
            const wide: u16 = @intCast(string[index]);
            self.set_to_stack(current_offset, wide);

            current_offset += 1;
            index = current_offset - offset;
        }
    }

    // SYSCALLS

    pub fn handle_syscall(self: *Self, syscall_key: u32) !void {
        switch (syscall_key) {
            defs.Syscalls.PINT => {
                try io_helper.print(self.stdout, "{}", .{self.get_register(128)});
            },
            defs.Syscalls.PCHAR => {
                const value: u8 = @truncate(std.math.clamp(self.get_register(128), 0, 255));
                try io_helper.print(self.stdout, "{c}", .{value});
            },
            defs.Syscalls.PSTR => {
                const offset = self.get_register(128);
                const string = try self.load_as_string(offset);
                defer alloc.free(string);

                try io_helper.print(self.stdout, "{s}", .{string});
            },
            defs.Syscalls.RINT => {
                const input = try self.stdin.read();
                const asint = try std.fmt.parseInt(u16, input, 10);
                self.set_register(128, asint);
            },
            defs.Syscalls.RCHAR => {
                const input = try self.stdin.readch();
                const asint: u16 = @intCast(input);
                self.set_register(128, asint);
            },
            defs.Syscalls.RSTR => {
                const input = try self.stdin.readln();
                const offset = self.get_register(128);
                self.store_string(offset, input);
            },
            else => {
                self.runtime_fault("unexpected syscall '{}'", .{syscall_key});
            },
        }
    }

    // IMPLEMENTATION TEMPLATES

    fn do_arith_oper(self: *Self, oper: ArithOper) void {
        const output = self.next();
        const operand1 = self.next_value();
        const operand2 = self.next_value();

        const result = self.arith_info.feed_and_eval(oper, operand1, operand2);
        self.set_register(output, result);
    }
};

// MEMORY STRUCT GENERIC
fn Memory(size: u32) type {
    return struct {
        const Self = @This();
        stack: [size]u16 = [_]u16{0} ** size,
        sp: usize = 0,

        pub fn write(self: *Self, offset: usize, value: u16) void {
            self.stack[offset] = value;
        }

        pub fn read(self: *Self, offset: usize) u16 {
            return self.stack[offset];
        }

        pub fn relative_offset(self: *Self, offset: usize) usize {
            return self.sp + offset;
        }
    };
}
