const std = @import("std");
const square = @import("square.zig");

const Square = square.Square;
const PieceType = @import("piece.zig").PieceType;

pub const MoveRequest = struct {
    fen: []const u8,
    from: []const u8,
    to: []const u8,
};

pub const Move = packed struct {
    from: Square,
    to: Square,

    special: bool,
    mover: PieceType,
    result: PieceType,

    pub fn new(from: Square, to: Square, special: bool, mover: PieceType, result: PieceType) Move {
        return Move{ .from = from, .to = to, .special = special, .mover = mover, .result = result };
    }

    pub fn fromRequest(request: MoveRequest) !Move {
        const from = try Square.fromString(request.from);
        const to = try Square.fromString(request.to);
        return Move.new(from, to, false, PieceType.Empty, PieceType.Empty);
    }

    pub fn isCapture(self: Move) bool {
        return !((self.result == PieceType.Empty) or ((self.mover == PieceType.King) and self.special));
    }

    pub fn resetsHalfMoveClock(self: Move) bool {
        return ((self.special) or (self.mover == PieceType.Pawn) or (self.result != PieceType.Empty));
    }

    pub fn isPromotion(self: Move) bool {
        return self.special and (self.mover == PieceType.Pawn) and (self.from.rank == 6) and (self.to.rank == 7);
    }

    pub fn getMvvLvaScore(self: Move) u8 {
        return self.result.victimScore() * 60 - self.mover.victimScore() / 100;
    }
};

pub const MoveList = struct {
    moves: [64]Move = undefined,
    count: usize = 0,

    pub fn len(self: *MoveList) usize {
        return self.count;
    }

    pub fn range(self: *MoveList) []Move {
        return self.moves[0..self.count];
    }

    pub fn new() MoveList {
        return MoveList{ .moves = undefined, .count = 0 };
    }

    pub fn push(self: *MoveList, move: Move) !void {
        if (self.count >= self.moves.len) {
            return error.OutOfSpace;
        }
        self.moves[self.count] = move;
        self.count += 1;
    }

    pub fn clear(self: *MoveList) void {
        self.count = 0;
    }

    pub fn get(self: *MoveList, index: usize) Move {
        if (index >= self.count) {
            std.debug.panic("Index out of bounds");
        }
        return self.moves[index];
    }

    pub fn isEmpty(self: MoveList) bool {
        return self.count == 0;
    }

    pub fn pop(self: *MoveList) ?Move {
        if (self.count == 0) {
            return null;
        }
        self.count -= 1;
        return self.moves[self.count];
    }

    pub fn swapRemove(self: *MoveList, i: usize) callconv(.Inline) ?Move {
        if (self.moves.len - 1 == i) return self.pop();
        const old_item = self.moves[i];
        self.moves[i] = self.pop().?;
        return old_item;
    }
};
