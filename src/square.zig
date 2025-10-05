const bitboard = @import("bitboard.zig");
const Bitboard = bitboard.Bitboard;

pub const Square = packed struct {
    file: u3,
    rank: u3,

    pub fn init(file: u3, rank: u3) Square {
        return Square{
            .file = file,
            .rank = rank,
        };
    }

    pub fn fromString(s: []const u8) !Square {
        if (s.len != 2) return error.InvalidInput;
        if (s[0] < 'a' or s[0] > 'h') return error.InvalidInput;
        if (s[1] < '1' or s[1] > '8') return error.InvalidInput;

        const file = @as(u3, @intCast(s[0] - 'a'));
        const rank = @as(u3, @intCast(s[1] - '1'));

        return Square{
            .file = file,
            .rank = rank,
        };
    }

    pub fn index(self: Square) u6 {
        return @bitCast(self);
    }

    pub fn offset(self: Square, off: i32) ?Square {
        return fromInt(i32, @as(i32, self.index()) + off);
    }

    pub fn in(self: Square, bit: Bitboard) bool {
        return ((bit.bits >> self.index()) & 1) > 0;
    }

    pub fn distance(self: Square, other: Square) u3 {
        const f = if (self.file > other.file) self.file - other.file else other.file - self.file;
        const r = if (self.rank > other.rank) self.rank - other.rank else other.rank - self.rank;
        return if (f > r) f else r;
    }

    pub fn toBitboard(square: Square) Bitboard {
        return Bitboard{ .bits = @as(u64, 1) << square.index() };
    }

    pub fn toString(self: Square) [2]u8 {
        const f: u8 = @as(u8, self.file) + 'a';
        const r: u8 = @as(u8, self.rank) + '1';

        return [2]u8{
            f,
            r,
        };
    }
};

pub fn fromIndex(number: u6) Square {
    return @bitCast(number);
}

pub fn fromInt(comptime T: type, int: T) ?Square {
    return switch (int) {
        0...63 => fromIndex(@intCast(int)),
        else => null,
    };
}
