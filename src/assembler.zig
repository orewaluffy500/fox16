const std = @import("std");
const defs = @import("./foxconst.zig");
const gpa = std.heap.page_allocator;

const Position = struct {
    index: usize = 0,
    line: usize = 0,
    col: usize = 0,

    pub fn next(self: *@This(), is_newline: bool) void {
        self.index += 1;
        self.col += 1;
        if (is_newline){
            self.col = 0;
            self.line += 1;
        }
    }
};

pub const Token = struct {
    const Variant = enum { int, ident, keyword, string, newline, register, stack_offset, stackptr_offset, end, comma };
    const KEYWORDS = [_][]const u8{
        "mov", "halt", "syscall", "ld", "st", "spinc", "spdec", "nop",
    };

    variant: Variant,
    pos: Position,
    value: []const u8 = "",

    pub fn init(variant: Variant, pos: Position, value: ?[]const u8) Token {
        return Token{
            .variant = variant,
            .pos = pos,
            .value = value orelse ""
        };
    }
};

pub const Lexer = struct {
    const Self = @This();

    arena: *std.heap.ArenaAllocator,
    source: []const u8,
    pos: Position = .{},
    current: u8 = 0,

    pub fn init(arena: *std.heap.ArenaAllocator, source: []const u8) Lexer {
        return Lexer{ .arena = arena, .source = source };
    }

    pub fn next(self: *Self) void {
        self.pos.next(self.current == '\n');
        self.current = if (self.pos.index < self.source.len) self.source[self.pos.index] else 0;
    }

    pub fn lex(self: *Self) ![]Token {
        var tokens: std.ArrayList(Token) = .empty;
        self.next();

        while (self.current != 0){
            if (std.mem.find(u8, " \r\t", &.{self.current}) != null){
                self.next();
            }
            
            else if (self.current == ','){
                try tokens.append(gpa, Token.init(.comma, self.pos, null));
                self.next();
            }

            else if (self.current == '"'){
                try tokens.append(gpa, try self.lex_string());
            }

            else if (self.current == '\n'){
                try tokens.append(gpa, Token.init(.newline, self.pos, null));
                self.next();
            }

            else if (self.current == 'r'){
                const start = self.pos;
                self.next(); // go past register
                var token = try self.lex_int();
                token.pos = start;
                token.variant = .register;

                try tokens.append(gpa, token);
            }

            else if (self.current == '$'){
                const start = self.pos;
                var variant: Token.Variant = .stack_offset;
                self.next(); // go past stack oper
                if (self.current == '$'){ // stack ptr offset
                    self.next();
                    variant = .stackptr_offset;
                }

                var token = try self.lex_int();
                token.pos = start;
                token.variant = variant;

                try tokens.append(gpa, token);
            }

            else if (std.ascii.isAlphabetic(self.current) or self.current == '_'){
                try tokens.append(gpa, try self.lex_identifier());
            }

            else if (std.ascii.isDigit(self.current)){
                try tokens.append(gpa, try self.lex_int());
            }
        }

        try tokens.append(gpa, .init(.end, self.pos, null));
        return try tokens.toOwnedSlice(gpa);
    }

    pub fn lex_int(self: *Self) !Token {
        var str: std.ArrayList(u8) = .empty;
        defer str.deinit(gpa);

        const start = self.pos;

        while (self.current != 0 and std.ascii.isDigit(self.current)){
            try str.append(gpa, self.current);
            self.next();
        }

        return Token.init(.int, start, try self.arena_alloc().dupe(u8, str.items));
    }

    pub fn lex_string(self: *Self) !Token {
        var str: std.ArrayList(u8) = .empty;
        defer str.deinit(gpa);

        const start = self.pos;

        self.next(); // skip first quote

        while (self.current != '"'){
            try str.append(gpa, self.current);
            self.next();
        }

        self.next(); // skip second quote

        return Token.init(.string, start, try self.arena_alloc().dupe(u8, str.items));
    }

    pub fn lex_identifier(self: *Self) !Token {
        var str: std.ArrayList(u8) = .empty;
        defer str.deinit(gpa);

        const start = self.pos;
        while (self.current != 0 and (std.ascii.isAlphanumeric(self.current) or self.current == '_')){
            try str.append(gpa, self.current);
            self.next();
        }

        var variant = Token.Variant.ident;
        const slice = try self.arena_alloc().dupe(u8, str.items);

        // check if the identifier is a keyword
        for (Token.KEYWORDS) |keyword| {
            if (std.mem.eql(u8, slice, keyword)){
                variant = .keyword;
                break; // immediately stop
            }
        }

        return Token.init(variant, start, slice);
    }

    pub fn arena_alloc(self: *Self) std.mem.Allocator {
        return self.arena.allocator();
    }
};



// COMPILER

pub const Compiler = struct {
    const Self = @This();

    program: std.ArrayList(u32) = .empty,
    tokens: []Token,
    current: Token,
    index: usize = 0,

    pub fn init(tokens: []Token) Compiler {
        return Compiler{
            .tokens = tokens,
            .current = tokens[tokens.len - 1],
        };
    }

    pub fn deinit(self: *Self) void {
        self.program.deinit(gpa);
    }

    pub fn next(self: *Self) void {
        self.current = if (self.index < self.tokens.len) self.tokens[self.index] else self.tokens[self.tokens.len - 1];
        self.index += 1;
    }

    pub fn compile_all(self: *Self) !void {
        var once = false;
        while (self.current.variant != .end or !once){
            try self.compile();
            once = true;
        }
    }

    pub fn compile(self: *Self) !void {
        self.next();
        const token = self.current;

        if (token.variant != .keyword){
            return;
        }

        const keyword = token.value;

        if (equal_to(keyword, "nop")){
            try self.insert_instruction(defs.Instructions.NOP);
        }

        else if (equal_to(keyword, "mov")){
            try self.insert_instruction(defs.Instructions.MOV);
            try self.insert_instruction(self.expect_register());
            self.expect_comma();
            try self.insert_instruction(self.expect_value());
        }

        else if (equal_to(keyword, "syscall")){
            try self.insert_instruction(defs.Instructions.SYSCALL);
            try self.insert_instruction(self.expect_integer());
        }
    }

    // HELPERS

    pub fn equal_to(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }

    pub fn insert_instruction(self: *Self, inst: u32) !void {
        try self.program.append(gpa, inst);
    }

    pub fn expect_integer(self: *Self) u16 {
        self.next();
        const token = self.current;
        if (token.variant != .int){
            assembler_fault("expected integer!", .{}, token.pos);
        }

        const num = std.fmt.parseInt(u16, token.value, 10) catch 0;
        return num;
    }

    pub fn expect_register(self: *Self) u16 {
        self.next();
        const token = self.current;
        if (token.variant != .register){
            assembler_fault("expected register!", .{}, token.pos);
        }

        const num = std.fmt.parseInt(u16, token.value, 10) catch 0;
        return num;
    }

    pub fn expect_stack_offset(self: *Self) u16 {
        self.next();
        const token = self.current;
        if (token.variant != .stack_offset){
            assembler_fault("expected stack offset!", .{}, token.pos);
        }

        const num = std.fmt.parseInt(u16, token.value, 10) catch 0;
        return num;
    }

    pub fn expect_stack_ptr_offset(self: *Self) u16 {
        self.next();
        const token = self.current;
        if (token.variant != .stackptr_offset){
            assembler_fault("expected stack ptr offset!", .{}, token.pos);
        }

        const num = std.fmt.parseInt(u16, token.value, 10) catch 0;
        return num;
    }

    pub fn expect_ident(self: *Self) []const u8 {
        self.next();
        const token = self.current;
        if (token.variant != .ident){
            assembler_fault("expected identifier!", .{}, token.pos);
        }

        return token.value;
    }

    pub fn expect_comma(self: *Self) void {
        self.next();
        const token = self.current;
        if (token.variant != .comma){
            assembler_fault("expected comma!", .{}, token.pos);
        }
    }

    pub fn expect_value(self: *Self) u32 {
        self.next();

        const token = self.current;
        if (token.variant != .int and token.variant != .register and token.variant != .stack_offset and token.variant != .stackptr_offset){
            assembler_fault("expected value, got {any}!", .{token.variant}, token.pos);
        }

        const num = std.fmt.parseInt(u16, token.value, 10) catch 0;
        var final: u32 = defs.const_encoded(num);

        // we dont handle .int and .stack_offset bcs both are const
        if (token.variant == .register){
            final = defs.register_encoded(num);
        }
        else if (token.variant == .stackptr_offset){
            final = defs.spoffset_encoded(num);
        }

        return final;
    }
};








pub fn assembler_fault(comptime fmt: []const u8, args: anytype, pos: Position) void {
    std.debug.print("assembler fault: ", .{});
    std.debug.print(fmt, args);
    std.debug.print(" (at line {}, column {})\n", .{pos.line, pos.col});
    std.process.exit(2);
}