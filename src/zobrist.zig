const std = @import("std");

pub const N_SQUARES: usize = 64;
pub const N_PIECES: usize = 13;

pub var ZobristTable: [N_PIECES][N_SQUARES]u64 = std.mem.zeroes([N_PIECES][N_SQUARES]u64);
pub var TurnHash: u64 = 0;
pub var EnPassantHash: [8]u64 = std.mem.zeroes([8]u64);
pub var CastlingHash: [16]u64 = std.mem.zeroes([16]u64);
pub var DepthHash: [64]u64 = std.mem.zeroes([64]u64);

pub const PRNG = struct {
    seed: u128,

    pub fn rand64(self: *PRNG) u64 {
        var x = self.seed;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.seed = x;
        var r: u64 = @truncate(x);
        r = r ^ @as(u64, @truncate(x >> 64));
        return r;
    }

    // Less bits
    pub fn sparse_rand64(self: *PRNG) u64 {
        return self.rand64() & self.rand64() & self.rand64();
    }

    pub fn new(seed: u128) PRNG {
        return PRNG{ .seed = seed };
    }
};

pub fn first_index(comptime T: type, arr: []const T, val: T) ?usize {
    var i: usize = 0;
    const end = arr.len;
    while (i < end) : (i += 1) {
        if (arr[i] == val) {
            return i;
        }
    }
    return null;
}

pub fn init_zobrist() void {
    var prng = PRNG.new(0x246C_CB2D_3B40_2853_9918_0A6D_BC3A_F444);
    var i: usize = 0;
    while (i < N_PIECES - 1) : (i += 1) {
        var j: usize = 0;
        while (j < N_SQUARES) : (j += 1) {
            ZobristTable[i][j] = prng.rand64();
        }
    }
    TurnHash = prng.rand64();

    var l: usize = 0;
    while (l < 8) : (l += 1) {
        EnPassantHash[l] = prng.rand64();
    }

    var k: usize = 0;
    while (k < 64) : (k += 1) {
        DepthHash[k] = prng.rand64();
    }

    var m: usize = 0;
    while (m < 16) : (m += 1) {
        CastlingHash[m] = prng.rand64();
    }
}

pub fn StandardHash() u64 {
    var h: u64 = 0;
    // White pieces
    h ^= ZobristTable[1][0]; // a1 R
    h ^= ZobristTable[3][1]; // b1 N
    h ^= ZobristTable[5][2]; // c1 B
    h ^= ZobristTable[6][3]; // d1 Q
    h ^= ZobristTable[4][4]; // e1 K
    h ^= ZobristTable[5][5]; // f1 B
    h ^= ZobristTable[3][6]; // g1 N
    h ^= ZobristTable[1][7]; // h1 R

    var i: usize = 0;
    while (i < 8) : (i += 1) {
        h ^= ZobristTable[2][8 + i]; // a2-h2 P
    }

    // Black pieces
    h ^= ZobristTable[7][56 + 0]; // a8 r
    h ^= ZobristTable[9][56 + 1]; // b8 n
    h ^= ZobristTable[11][56 + 2]; // c8 b
    h ^= ZobristTable[12][56 + 3]; // d8 q
    h ^= ZobristTable[10][56 + 4]; // e8 k
    h ^= ZobristTable[11][56 + 5]; // f8 b
    h ^= ZobristTable[9][56 + 6]; // g8 n
    h ^= ZobristTable[7][56 + 7]; // h8 r

    var j: usize = 0;
    while (j < 8) : (j += 1) {
        h ^= ZobristTable[8][48 + j]; // a7-h7 p
    }

    // Side to move (white)
    h ^= TurnHash;

    // Castling rights (KQkq)
    h ^= CastlingHash[0b1111];

    return h;
}
