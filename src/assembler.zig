const std = @import("std");
const defs = @import("./foxconst.zig");

const AssemblerError = error {
    undefined_symbol,
    unexpected_char,
    expected_value_not_found,
    existing_symbol,
};

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
        "mov", "halt", "syscall", "ld", "st", "spinc", "spdec", "nop", "str", "cpy", "decl",

        // ARITHMETIC
        "inc", "dec", "add", "sub", "mul", "div", "pow",

        // LOGICAL
        "cmp", "jz", "jnz", "jl", "jg", "jle", "jge", "je", "jne",

        // CONTROL FLOW
        "jmp", "call", "ret", "label",
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

    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    source: []const u8,
    pos: Position = .{},
    current: u8 = 0,

    pub fn init(arena: std.mem.Allocator, gpa: std.mem.Allocator, source: []const u8) Lexer {
        return Lexer{ .arena = arena, .gpa = gpa, .source = source };
    }

    pub fn next(self: *Self) void {
        self.pos.next(self.current == '\n');
        self.current = if (self.pos.index < self.source.len) self.source[self.pos.index] else 0;
    }

    pub fn lex(self: *Self) ![]Token {
        var tokens: std.ArrayList(Token) = .empty;
        defer tokens.deinit(self.gpa);

        self.next();

        while (self.current != 0){
            if (std.mem.find(u8, " \r\t", &.{self.current}) != null){
                self.next();
            }

            else if (self.current == ';'){
                while (self.current != 0 and self.current != '\n'){
                    self.next();
                }
            }
            
            else if (self.current == ','){
                try tokens.append(self.gpa, Token.init(.comma, self.pos, null));
                self.next();
            }

            else if (self.current == '"'){
                try tokens.append(self.gpa, try self.lex_string());
            }

            else if (self.current == '\n'){
                try tokens.append(self.gpa, Token.init(.newline, self.pos, null));
                self.next();
            }

            else if (self.current == '{'){
                self.next();
                const start = self.pos;
                var buf: [1024]u8 = undefined;

                if (self.current == '\\'){
                    self.next();
                    const escape_char = self.current;
                    const final_char: ?u8 = switch (escape_char) {
                        'n' => '\n',
                        'q' => '\"',
                        'a' => '\'',
                        't' => '\t',
                        'r' => '\r',
                        '\\' => '\\',
                        else => null
                    };
                    if (final_char) |ch| {
                        // format the char into a string and make the slice outlive the buffer
                        const final = try self.arena.dupe(u8, try std.fmt.bufPrint(&buf, "{}", .{ch}));
                        try tokens.append(self.gpa, Token.init(.int, start, final));
                    } else {
                        fault("unexpected escape character '\\{c}'!", .{escape_char}, self.pos);
                        return AssemblerError.unexpected_char;
                    }
                }
                else {
                    // format the char into a string and make the slice outlive the buffer
                    const final = try self.arena.dupe(u8, try std.fmt.bufPrint(&buf, "{}", .{self.current}));
                    try tokens.append(self.gpa, Token.init(.int, start, final));
                }

                self.next();
                if (self.current != '}'){
                    fault("expected closing bracket '}}'!", .{}, self.pos);
                    return AssemblerError.unexpected_char;
                }

                self.next();
            }

            else if (self.current == '.'){
                const start = self.pos;
                self.next(); // go past register
                var token = try self.lex_int();
                token.pos = start;
                token.variant = .register;

                try tokens.append(self.gpa, token);
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

                try tokens.append(self.gpa, token);
            }

            else if (std.ascii.isAlphabetic(self.current) or self.current == '_'){
                try tokens.append(self.gpa, try self.lex_identifier());
            }

            else if (std.ascii.isDigit(self.current)){
                try tokens.append(self.gpa, try self.lex_int());
            }

            else {
                fault("unexpected char '{c}'", .{self.current}, self.pos);
                return AssemblerError.unexpected_char;
            }
        }

        try tokens.append(self.gpa, .init(.end, self.pos, null));
        return try self.arena.dupe(Token, tokens.items);
    }

    pub fn lex_int(self: *Self) !Token {
        var str: std.ArrayList(u8) = .empty;
        defer str.deinit(self.gpa);

        const start = self.pos;

        while (self.current != 0 and std.ascii.isDigit(self.current)){
            try str.append(self.gpa, self.current);
            self.next();
        }

        return Token.init(.int, start, try self.arena.dupe(u8, str.items));
    }

    pub fn lex_string(self: *Self) !Token {
        var str: std.ArrayList(u8) = .empty;
        defer str.deinit(self.gpa);

        const start = self.pos;

        self.next(); // skip first quote

        while (self.current != 0 and self.current != '"'){
            try str.append(self.gpa, self.current);
            self.next();
        }

        self.next(); // skip second quote

        return Token.init(.string, start, try self.arena.dupe(u8, str.items));
    }

    pub fn lex_identifier(self: *Self) !Token {
        var str: std.ArrayList(u8) = .empty;
        defer str.deinit(self.gpa);

        const start = self.pos;
        while (self.current != 0 and (std.ascii.isAlphanumeric(self.current) or self.current == '_')){
            try str.append(self.gpa, self.current);
            self.next();
        }

        var variant = Token.Variant.ident;
        const slice = try self.arena.dupe(u8, str.items);

        // check if the identifier is a keyword
        for (Token.KEYWORDS) |keyword| {
            if (std.mem.eql(u8, slice, keyword)){
                variant = .keyword;
                break; // immediately stop
            }
        }

        return Token.init(variant, start, slice);
    }
};



// COMPILER

pub const Compiler = struct {
    const Self = @This();

    program: std.ArrayList(u32) = .empty,
    pc: usize = 0,
    label_map: std.StringHashMap(usize),
    label_resolves: std.AutoHashMap(usize, []const u8),
    constant_definitions: std.StringHashMap(u16),
    tokens: []Token,
    current: Token,
    gpa: std.mem.Allocator,
    index: usize = 0,

    pub fn init(tokens: []Token, gpa: std.mem.Allocator) Compiler {
        return Compiler{
            .gpa = gpa,
            .tokens = tokens,
            .label_map = .init(gpa),
            .label_resolves = .init(gpa),
            .constant_definitions = .init(gpa),
            .current = tokens[tokens.len - 1],
        };
    }

    pub fn deinit(self: *Self) void {
        self.program.deinit(self.gpa);
        self.label_map.deinit();
        self.label_resolves.deinit();
        self.constant_definitions.deinit();
    }

    pub fn next(self: *Self) void {
        self.current = if (self.index < self.tokens.len) self.tokens[self.index] else self.tokens[self.tokens.len - 1];
        self.index += 1;
    }

    pub fn resolve_labels(self: *Self) !void {
        var it = self.label_resolves.iterator();
        while (it.next()) |entry| {
            const where = entry.key_ptr.*;
            const target = entry.value_ptr.*;

            if (self.label_map.get(target)) |dest| {
                self.program.items[where] = @truncate(dest);
            } else {
                fault("un-resolved label '{s}'!", .{target}, null);
                return AssemblerError.undefined_symbol;
            }
        }
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
            try self.insert_instruction(try self.expect_register());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
        }

        else if (equal_to(keyword, "syscall")){
            try self.insert_instruction(defs.Instructions.SYSCALL);
            try self.insert_instruction(try self.expect_integer());
        }
        
        else if (equal_to(keyword, "halt")){
            try self.insert_instruction(defs.Instructions.HALT);
        }

        // HELPERS

        else if (equal_to(keyword, "inc")){
            const register = try self.expect_register();
            try self.insert_instruction(defs.Instructions.ADD);
            try self.insert_instruction(register);
            try self.insert_instruction(defs.register_encoded(register));
            try self.insert_instruction(defs.const_encoded(1));
        }

        else if (equal_to(keyword, "dec")){
            const register = try self.expect_register();
            try self.insert_instruction(defs.Instructions.SUB);
            try self.insert_instruction(register);
            try self.insert_instruction(defs.register_encoded(register));
            try self.insert_instruction(defs.const_encoded(1));
        }

        else if (equal_to(keyword, "decl")){
            const identifier = try self.expect_ident();
            if (self.constant_definitions.get(identifier)) |_| {
                fault("constant named '{s}' already exists!", .{identifier}, token.pos);
                return AssemblerError.existing_symbol;
            }
            
            try self.expect_comma();
            try self.constant_definitions.put(identifier, try self.expect_integer());
        }

        else if (equal_to(keyword, "str")){
            const offset_begin = try self.expect_register();
            try self.expect_comma();
            const contents = try self.expect_string();

            var index: u32 = 0;
            while (index < contents.len) {
                try self.insert_instruction(defs.Instructions.ST);
                try self.insert_instruction(defs.register_encoded(offset_begin));
                try self.insert_instruction(defs.const_encoded(@intCast(contents[index])));

                // code for incrementation
                try self.insert_instruction(defs.Instructions.ADD);
                try self.insert_instruction(offset_begin);
                try self.insert_instruction(defs.register_encoded(offset_begin));
                try self.insert_instruction(defs.const_encoded(1));
                index += 1;
            }
        }
    
        // ARITHEMTIC

        else if (equal_to(keyword, "add")){
            try self.insert_instruction(defs.Instructions.ADD);
            try self.insert_instruction(try self.expect_register());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
        }

        else if (equal_to(keyword, "sub")){
            try self.insert_instruction(defs.Instructions.SUB);
            try self.insert_instruction(try self.expect_register());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
        }

        else if (equal_to(keyword, "mul")){
            try self.insert_instruction(defs.Instructions.MUL);
            try self.insert_instruction(try self.expect_register());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
        }

        else if (equal_to(keyword, "div")){
            try self.insert_instruction(defs.Instructions.DIV);
            try self.insert_instruction(try self.expect_register());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
        }

        else if (equal_to(keyword, "pow")){
            try self.insert_instruction(defs.Instructions.POW);
            try self.insert_instruction(try self.expect_register());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
        }

        // LOGICAL
        else if (equal_to(keyword, "cmp")){
            try self.insert_instruction(defs.Instructions.CMP);
            try self.insert_instruction(try self.expect_value());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
        }

        else if (equal_to(keyword, "jz")){
            try self.insert_instruction(defs.Instructions.JZ);
            try self.jump_to(try self.expect_ident());
            try self.insert_instruction(try self.expect_value());
        }

        else if (equal_to(keyword, "jnz")){
            try self.insert_instruction(defs.Instructions.JNZ);
            try self.jump_to(try self.expect_ident());
            try self.insert_instruction(try self.expect_value());
        }
        
        else if (equal_to(keyword, "jl")){
            try self.insert_instruction(defs.Instructions.JL);
            try self.jump_to(try self.expect_ident());
        }

        else if (equal_to(keyword, "jg")){
            try self.insert_instruction(defs.Instructions.JG);
            try self.jump_to(try self.expect_ident());
        }

        else if (equal_to(keyword, "jle")){
            try self.insert_instruction(defs.Instructions.JLE);
            try self.jump_to(try self.expect_ident());
        }

        else if (equal_to(keyword, "jge")){
            try self.insert_instruction(defs.Instructions.JGE);
            try self.jump_to(try self.expect_ident());
        }

        else if (equal_to(keyword, "je")){
            try self.insert_instruction(defs.Instructions.JE);
            try self.jump_to(try self.expect_ident());
        }

        else if (equal_to(keyword, "jne")){
            try self.insert_instruction(defs.Instructions.JNE);
            try self.jump_to(try self.expect_ident());
        }

        // STACK RELATED
        
        else if (equal_to(keyword, "ld")){
            try self.insert_instruction(defs.Instructions.LD);
            try self.insert_instruction(try self.expect_register());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
        }

        else if (equal_to(keyword, "st")){
            try self.insert_instruction(defs.Instructions.ST);
            try self.insert_instruction(try self.expect_value());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
        }

        else if (equal_to(keyword, "spinc")){
            try self.insert_instruction(defs.Instructions.SPI);
            try self.insert_instruction(try self.expect_value());
        }

        else if (equal_to(keyword, "spdec")){
            try self.insert_instruction(defs.Instructions.SPD);
            try self.insert_instruction(try self.expect_value());
        }

        else if (equal_to(keyword, "cpy")){
            try self.insert_instruction(defs.Instructions.MEMCPY);
            try self.insert_instruction(try self.expect_value());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
            try self.expect_comma();
            try self.insert_instruction(try self.expect_value());
        }

        // CONTROL FLOW

        else if (equal_to(keyword, "label")){
            const name = try self.expect_ident();

            try self.label_map.put(name, self.pc);
        }

        else if (equal_to(keyword, "jmp")){
            const name = try self.expect_ident();
            try self.insert_instruction(defs.Instructions.JMP);
            try self.jump_to(name);
        }
        
        else if (equal_to(keyword, "call")){
            const name = try self.expect_ident();
            try self.insert_instruction(defs.Instructions.CALL);
            try self.jump_to(name);
        }

        else if (equal_to(keyword, "ret")){
            try self.insert_instruction(defs.Instructions.RET);
        }
    }

    // HELPERS
    
    pub fn jump_to(self: *Self, name: []const u8) !void {
        if (self.label_map.get(name)) |location| {
            try self.insert_instruction(@truncate(location));
        }
        else {
            try self.label_resolves.put(self.pc, name);
            try self.insert_instruction(0);
        }
    }

    pub fn equal_to(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }

    pub fn insert_instruction(self: *Self, inst: u32) !void {
        try self.program.append(self.gpa, inst);
        self.pc += 1;
    }

    pub fn expect_integer(self: *Self) !u16 {
        self.next();
        const token = self.current;
        if (token.variant != .int){
            fault("expected integer!", .{}, token.pos);
            return AssemblerError.expected_value_not_found;
        }

        const num = std.fmt.parseInt(u16, token.value, 10) catch 0;
        return num;
    }

    pub fn expect_register(self: *Self) !u16 {
        self.next();
        const token = self.current;
        if (token.variant != .register){
            fault("expected register!", .{}, token.pos);
            return AssemblerError.expected_value_not_found;
        }

        const num = std.fmt.parseInt(u16, token.value, 10) catch 0;
        return num;
    }

    pub fn expect_stack_offset(self: *Self) !u16 {
        self.next();
        const token = self.current;
        if (token.variant != .stack_offset){
            fault("expected stack offset!", .{}, token.pos);
            return AssemblerError.expected_value_not_found;
        }

        const num = std.fmt.parseInt(u16, token.value, 10) catch 0;
        return num;
    }

    pub fn expect_stack_ptr_offset(self: *Self) !u16 {
        self.next();
        const token = self.current;
        if (token.variant != .stackptr_offset){
            fault("expected stack ptr offset!", .{}, token.pos);
            return AssemblerError.expected_value_not_found;
        }

        const num = std.fmt.parseInt(u16, token.value, 10) catch 0;
        return num;
    }

    pub fn expect_ident(self: *Self) ![]const u8 {
        self.next();
        const token = self.current;
        if (token.variant != .ident){
            fault("expected identifier!", .{}, token.pos);
            return AssemblerError.expected_value_not_found;
        }

        return token.value;
    }

    pub fn expect_comma(self: *Self) !void {
        self.next();
        const token = self.current;
        if (token.variant != .comma){
            fault("expected comma!", .{}, token.pos);
            return AssemblerError.expected_value_not_found;
        }
    }

    pub fn expect_string(self: *Self) ![]const u8 {
        self.next();
        const token = self.current;
        if (token.variant != .string){
            fault("expected string!", .{}, token.pos);
            return AssemblerError.expected_value_not_found;
        }

        return token.value;
    }

    pub fn expect_value(self: *Self) !u32 {
        self.next();

        const token = self.current;
        if (token.variant != .int and token.variant != .register and token.variant != .stack_offset and token.variant != .stackptr_offset and token.variant != .ident){
            fault("expected value, got {any}!", .{token.variant}, token.pos);
            return AssemblerError.expected_value_not_found;
        }

        if (token.variant == .ident){
            const ident = token.value;
            if (self.constant_definitions.get(ident)) |value| {
                return defs.const_encoded(value);
            }

            fault("undefined constant '{s}'", .{ident}, token.pos);
            return AssemblerError.undefined_symbol;
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



pub fn fault(comptime fmt: []const u8, args: anytype, pos: ?Position) void {
    std.debug.print("\nassembler fault: ", .{});
    std.debug.print(fmt, args);
    if (pos) |posn| {
        std.debug.print(" (at line {}, column {})\n", .{posn.line, posn.col});
    } else {
        std.debug.print("\n", .{});
    }
}