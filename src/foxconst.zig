
// INSTRUCTION DEFINITIONS
pub const Instructions = struct {
    pub const NOP: u32      = 0x0;
    pub const HALT: u32     = 0x10;
    pub const SYSCALL: u32  = 0x11;

    // REGISTER-RELATED
    pub const MOV: u32      = 0x20;
    pub const ZZ: u32       = 0x21;
    
    // STACK-RELATED
    pub const LD: u32       = 0x30;
    pub const ST: u32       = 0x31;
    pub const SPI: u32      = 0x32;
    pub const SPD: u32      = 0x33;

    // FLOW-RELATED
    pub const JMP: u32      = 0x40;
    pub const CALL: u32     = 0x41;
    pub const RET: u32      = 0x42;
    pub const JZ: u32       = 0x43;
    pub const JNZ: u32      = 0x44;

    pub const JL: u32       = 0x45;
    pub const JLE: u32      = 0x46;
    pub const JG: u32       = 0x47;
    pub const JGE: u32      = 0x48;
    pub const JE: u32       = 0x49;
    pub const JNE: u32      = 0x4A;

    pub const CMP: u32      = 0x4B;

    // ARITHMETIC

    pub const ADD: u32      = 0x50;
    pub const SUB: u32      = 0x51;
    pub const MUL: u32      = 0x52;
    pub const DIV: u32      = 0x53;
    pub const POW: u32      = 0x54;
};

// SYSCALLS
pub const Syscalls = struct {
    pub const PINT: u32     = 0x100;
    pub const PCHAR: u32    = 0x101;
    pub const PSTR: u32     = 0x102;

    pub const RINT: u32     = 0x200;
    pub const RCHAR: u32    = 0x201;
    pub const RSTR: u32     = 0x202;
};

// MODE BITS
pub const Mode = struct {
    pub const CONST: u2     = 0b00; // i wanted to use binary for fun
    pub const REGIST: u2    = 0b01;
    pub const SPOFFSET: u2  = 0b10;
};


// HELPERS

pub fn encode_value(mode: u2, value: u31) u32 {
    return (@as(u32, mode) << 30) | @as(u32, value);
}

pub fn decode_value(value: u32) struct { u2, u31 } {
    return .{ @intCast(value >> 30), @intCast(value & 0x3FFFFFFF) };
}

pub fn register_encoded(index: u32) u32 {
    return encode_value(Mode.REGIST, @intCast(index));
}

pub fn const_encoded(value: u32) u32 {
    return encode_value(Mode.CONST, @intCast(value));
}

pub fn spoffset_encoded(offset: u31) u32 {
    return encode_value(Mode.SPOFFSET, offset);
}

pub fn safe_pow(base: u16, exp: u32) u16 {
    var result: u16 = 1;
    var b = base;
    var e = exp;
    while (e > 0) : (e >>= 1) {
        if (e & 1 == 1) result *%= b;
        b *%= b;
    }
    return result;
}