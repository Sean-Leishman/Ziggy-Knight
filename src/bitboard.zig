const std = @import("std");
const square = @import("square.zig");
const color = @import("color.zig");

const Color = color.Color;
const Square = square.Square;

pub const Bitboard = packed struct {
    bits: u64,

    pub fn clone(self: Bitboard) Bitboard {
        return Bitboard{ .bits = self.bits };
    }

    pub fn debug(self: Bitboard) void {
        std.debug.print("Bitboard: {:#x}\n", .{self.bits});
    }

    pub fn toString(self: Bitboard) []const u8 {
        var result: [72]u8 = undefined;
        var i: usize = 0;
        while (i < 72) {
            i += 1;
            const f: usize = i % 9;
            const r: usize = i / 9;
            if (f == 8) {
                result[i] = '\n';
            } else if (self.contains(square.fromInt(usize, f | (r << 3)).?)) {
                result[i] = '+';
            } else {
                result[i] = '.';
            }
        }
        return result;
    }

    pub fn eq(self: Bitboard, other: Bitboard) bool {
        return self.bits == other.bits;
    }

    pub fn contains(self: Bitboard, sq: Square) bool {
        return ((self.bits >> sq.index()) & 1) > 0;
    }

    pub fn isEmpty(self: Bitboard) bool {
        return self.bits == 0;
    }

    pub fn isFull(self: Bitboard) bool {
        return self.bits == 0xFFFF_FFFF_FFFF_FFFF;
    }

    pub fn isNotEmpty(self: Bitboard) bool {
        return self.bits != 0;
    }

    pub fn isNotFull(self: Bitboard) bool {
        return self.bits != 0xFFFF_FFFF_FFFF_FFFF;
    }

    pub fn isOneSquare(self: Bitboard) bool {
        return (self.bits & (self.bits -% 1) == 0) and (self.isNotEmpty());
    }

    pub fn toggle(self: *Bitboard, sq: Square) callconv(.Inline) void {
        self.bits ^= (sq.toBitboard().bits);
    }

    pub fn countBits(self: Bitboard) u8 {
        var count: u8 = 0;
        var bits = self.bits;
        while (bits != 0) {
            count += 1;
            bits &= bits -% 1;
        }
        return count;
    }

    pub fn first(self: Bitboard) ?Square {
        return if (self.isNotEmpty()) square.fromIndex(@intCast(@ctz(self.bits))) else null;
    }

    pub fn lsb(self: Bitboard) i32 {
        return @intCast(@ctz(self.bits));
    }

    pub fn toSquare(self: Bitboard) ?Square {
        return if (self.isOneSquare()) self.first() else null;
    }

    pub fn addSquare(self: Bitboard, sq: Square) Bitboard {
        return Bitboard{ .bits = (self.bits | sq.toBitboard().bits) };
    }

    pub fn relativeShift(self: Bitboard, clr: Color, shift: u6) Bitboard {
        return switch (clr) {
            Color.White => Bitboard{ .bits = self.bits << shift },
            Color.Black => Bitboard{ .bits = self.bits >> shift },
        };
    }

    pub fn copy(self: Bitboard) Bitboard {
        return Bitboard{ .bits = self.bits };
    }

    pub fn invert(self: Bitboard) Bitboard {
        return Bitboard{ .bits = ~self.bits };
    }

    pub fn bitAnd(self: Bitboard, other: Bitboard) Bitboard {
        return Bitboard{ .bits = self.bits & other.bits };
    }

    pub fn bitOr(self: Bitboard, other: Bitboard) Bitboard {
        return Bitboard{ .bits = self.bits | other.bits };
    }

    pub fn xor(self: Bitboard, other: Bitboard) Bitboard {
        return Bitboard{ .bits = self.bits ^ other.bits };
    }

    pub fn not(self: Bitboard) Bitboard {
        return Bitboard{ .bits = ~self.bits };
    }

    pub fn clearBits(self: *Bitboard, bits: Bitboard) void {
        self.bits &= ~bits.bits;
    }

    pub fn clearBit(self: *Bitboard, sq: Square) void {
        self.bits &= (~sq.toBitboard().bits);
    }

    pub fn setBit(self: *Bitboard, sq: Square) void {
        self.bits |= sq.toBitboard().bits;
    }

    pub fn setBits(self: *Bitboard, bits: Bitboard) void {
        self.bits |= bits.bits;
    }

    pub fn shiftRight(self: Bitboard, shift: u6) Bitboard {
        return Bitboard{ .bits = (self.bits >> shift) };
    }

    pub fn next(self: *Bitboard) ?Square {
        if (self.first()) |sq| {
            self.bits &= self.bits -% 1;
            return sq;
        } else {
            return null;
        }
    }
};

pub const empty = Bitboard{ .bits = 0 };
pub const all = Bitboard{ .bits = 0xFFFF_FFFF_FFFF_FFFF };
pub const dark_squares = Bitboard{ .bits = 0xAA_AA_AA_AA_AA_AA_AA_AA };
pub const light_squares = Bitboard{ .bits = 0x55_55_55_55_55_55_55_55 };
pub const corners = Bitboard{ .bits = 0x81_00_00_00_00_00_00_81 };
pub const center = Bitboard{ .bits = 0x00_00_00_3C_3C_00_00_00 };

pub const rook_path = Bitboard{ .bits = 0x6E_00_00_00_00_00_00_6E };
pub const king_path = Bitboard{ .bits = 0x6C_00_00_00_00_00_00_6C };
pub const king_castle = Bitboard{ .bits = 0x44_00_00_00_00_00_00_44 };
pub const rook_castle = Bitboard{ .bits = 0x28_00_00_00_00_00_00_28 };

pub const kingside = Bitboard{ .bits = 0xF0_F0_F0_F0_F0_F0_F0_F0 };
pub const queenside = Bitboard{ .bits = 0x0F_0F_0F_0F_0F_0F_0F_0F };

pub const ranks = [_]Bitboard{
    Bitboard{ .bits = 0x00_00_00_00_00_00_00_FF },
    Bitboard{ .bits = 0x00_00_00_00_00_00_FF_00 },
    Bitboard{ .bits = 0x00_00_00_00_00_FF_00_00 },
    Bitboard{ .bits = 0x00_00_00_00_FF_00_00_00 },
    Bitboard{ .bits = 0x00_00_00_FF_00_00_00_00 },
    Bitboard{ .bits = 0x00_00_FF_00_00_00_00_00 },
    Bitboard{ .bits = 0x00_FF_00_00_00_00_00_00 },
    Bitboard{ .bits = 0xFF_00_00_00_00_00_00_00 },
};

pub const files = [_]Bitboard{
    Bitboard{ .bits = 0x01_01_01_01_01_01_01_01 },
    Bitboard{ .bits = 0x02_02_02_02_02_02_02_02 },
    Bitboard{ .bits = 0x04_04_04_04_04_04_04_04 },
    Bitboard{ .bits = 0x08_08_08_08_08_08_08_08 },
    Bitboard{ .bits = 0x10_10_10_10_10_10_10_10 },
    Bitboard{ .bits = 0x20_20_20_20_20_20_20_20 },
    Bitboard{ .bits = 0x40_40_40_40_40_40_40_40 },
    Bitboard{ .bits = 0x80_80_80_80_80_80_80_80 },
};

pub fn rank(r: u8) Bitboard {
    return ranks[r];
}

pub fn relativeRank(clr: Color, r: u8) Bitboard {
    return rank(switch (clr) {
        Color.White => r,
        Color.Black => 7 - r,
    });
}

pub inline fn file_plain(sq: usize) usize {
    return sq & 0b111;
}
