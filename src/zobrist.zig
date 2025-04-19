const std = @import("std");

const N_SQUARES: usize = 64;
const N_PIECES: usize = 13;

pub var ZobristTable: [N_PIECES][N_SQUARES]u64 = std.mem.zeroes([N_PIECES][N_SQUARES]u64);
pub var TurnHash: u64 = 0;
pub var EnPassantHash: [8]u64 = std.mem.zeroes([8]u64);
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
}
