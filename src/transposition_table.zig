const move = @import("move.zig");
const std = @import("std");

const Move = move.Move;

const MB = 1024 * 1024;

pub const TItem = packed struct {
    hash: u64,
    eval: i32,
    best_move: Move,
    depth: u32,
};

pub var TTAlloc = std.heap.ArenaAllocator.init(std.heap.c_allocator);

pub const TranspositionTable = struct {
    data: std.ArrayList(TItem),
    size: usize,

    pub fn new() TranspositionTable {
        return TranspositionTable{
            .data = std.ArrayList(TItem).init(TTAlloc.allocator()),
            .size = 16 * MB / @sizeOf(TItem),
        };
    }

    pub inline fn index(self: *TranspositionTable, hash: u64) u64 {
        const _size: u64 = @intCast(self.size);
        const _index: u64 = hash % _size;
        return _index;
    }

    pub fn set(
        self: *TranspositionTable,
        hash: u64,
        eval: i32,
        best_move: Move,
        depth: u32,
    ) void {
        const _index: u64 = self.index(hash);
        if (self.data.items.len < self.size) {
            self.data.append(TItem{
                .hash = hash,
                .eval = eval,
                .best_move = best_move,
                .depth = depth,
            }) catch unreachable;
        } else {
            self.data.items[_index] = TItem{
                .hash = hash,
                .eval = eval,
                .best_move = best_move,
                .depth = depth,
            };
        }
    }

    pub fn get(self: *TranspositionTable, hash: u64) ?TItem {
        const _index: u64 = self.index(hash);
        if (_index >= self.data.items.len) {
            return null;
        }
        const item: TItem = self.data.items[_index];
        if (item.hash == hash) {
            return item;
        }
        return null;
    }
};

pub var GlobalTT: TranspositionTable = TranspositionTable.new();
