const move = @import("move.zig");
const std = @import("std");

const Move = move.Move;

pub const TItem = packed struct {
    pub hash: u64,
    pub eval: i32,
    pub best_move: Move,
    pub depth: u8,
};

pub var TTAlloc = std.heap.ArenaAllocator.init(std.heap.c_allocator);

pub const TranspositionTable = struct {
    data: std.ArrayList(i128),
    size: usize,

    pub fn new() TranspositionTable {
        return TranspositionTable{
            .data = std.ArrayList(i128).init(TTAlloc.allocator()),
            .size = 16 * MB / @sizeOf(TItem),
        };
    }

    pub fn set(
        self: *TranspositionTable,
        hash: u64,
        eval: i32,
        best_move: Move,
        depth: u8,
    ) void {
        const item = TItem{
            .hash = hash,
            .eval = eval,
            .best_move = best_move,
            .depth = depth,
        };
        self.data.append(@intToPtr(i128, item)) catch unreachable;
    }
};
