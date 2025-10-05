const std = @import("std");

const attack = @import("attack.zig");
const bitboard = @import("bitboard.zig");
const piece = @import("piece.zig");
const square = @import("square.zig");
const color = @import("color.zig");

const Bitboard = bitboard.Bitboard;
const Piece = piece.Piece;
const PieceType = piece.PieceType;
const Square = square.Square;
const Color = color.Color;

pub const Board = struct {
    empty: Bitboard,
    pawns: Bitboard,
    knights: Bitboard,
    bishops: Bitboard,
    rooks: Bitboard,
    queens: Bitboard,
    kings: Bitboard,
    white: Bitboard,
    black: Bitboard,

    pub fn equals(self: Board, other: Board) bool {
        return self.empty == other.empty and
            self.pawns == other.pawns and
            self.knights == other.knights and
            self.bishops == other.bishops and
            self.rooks == other.rooks and
            self.queens == other.queens and
            self.kings == other.kings and
            self.white == other.white and
            self.black == other.black;
    }

    pub fn removeOn(self: *Board, sq: Square) void {
        self.pawns.clearBit(sq);
        self.knights.clearBit(sq);
        self.bishops.clearBit(sq);
        self.rooks.clearBit(sq);
        self.queens.clearBit(sq);
        self.kings.clearBit(sq);
        self.white.clearBit(sq);
        self.black.clearBit(sq);
        self.empty.setBit(sq);
    }

    pub fn setPieceOn(self: *Board, pc: Piece, sq: Square) void {
        self.removeOn(sq);
        switch (pc.color) {
            .White => self.white.setBit(sq),
            .Black => self.black.setBit(sq),
        }

        switch (pc.piece_type) {
            .Pawn => self.pawns.setBit(sq),
            .Knight => self.knights.setBit(sq),
            .Bishop => self.bishops.setBit(sq),
            .Rook => self.rooks.setBit(sq),
            .Queen => self.queens.setBit(sq),
            .King => self.kings.setBit(sq),
            .Empty => unreachable,
            .Other => unreachable,
        }

        self.empty.clearBit(sq);
    }

    pub fn ofColor(self: Board, clr: Color) Bitboard {
        return switch (clr) {
            .White => self.white,
            .Black => self.black,
        };
    }

    pub fn ofPiece(self: Board, pc: Piece) Bitboard {
        return switch (pc.piece_type) {
            .Pawn => self.pawns,
            .Knight => self.knights,
            .Bishop => self.bishops,
            .Rook => self.rooks,
            .Queen => self.queens,
            .King => self.kings,
            .Empty => self.empty,
            .Other => unreachable,
        }.bitAnd(self.ofColor(pc.color));
    }

    pub fn ofPieceType(self: Board, pt: PieceType) Bitboard {
        return switch (pt) {
            .Pawn => self.pawns,
            .Knight => self.knights,
            .Bishop => self.bishops,
            .Rook => self.rooks,
            .Queen => self.queens,
            .King => self.kings,
            .Empty => self.empty,
            .Other => unreachable,
        };
    }

    pub fn attackersOf(self: Board, sq: Square, attacker: Color) Bitboard {
        const other = self.ofColor(attacker);
        const rq = attack.rookFrom(sq, self.occupied()).bitAnd(self.rooks.bitOr(self.queens));
        const bq = attack.bishopFrom(sq, self.occupied()).bitAnd(self.bishops.bitOr(self.queens));
        const n = attack.knightFrom(sq).bitAnd(self.knights);
        const p = attack.pawnFrom(attacker.invert(), sq).bitAnd(self.pawns);
        const k = attack.kingFrom(sq).bitAnd(self.kings);

        return other.bitAnd(rq.bitOr(bq).bitOr(n).bitOr(p).bitOr(k));
    }

    pub fn sliders(self: Board) Bitboard {
        return Bitboard{ .bits = self.bishops.bits ^ self.rooks.bits ^ self.queens.bits };
    }

    pub fn checkers(self: Board, player: Color) callconv(.Inline) Bitboard {
        const king: Square = self.ofPiece(Piece{ .piece_type = PieceType.King, .color = player }).toSquare().?;
        return self.attackersOf(king, player.invert());
    }

    pub fn sliderBlockers(self: Board, enemies: Bitboard, king: Square) callconv(.Inline) Bitboard {
        const r = attack.rookFrom(king, bitboard.empty).bitAnd(self.rooks.xor(self.queens));
        const b = attack.bishopFrom(king, bitboard.empty).bitAnd(self.bishops.xor(self.queens));
        const snipers = r.bitOr(b);
        var blockers = bitboard.empty;
        var sniper_enemies = snipers.bitAnd(enemies);
        while (sniper_enemies.next()) |sniper| {
            const blocker = attack.between(king, sniper).bitAnd(self.occupied());
            if (blocker.isOneSquare()) {
                blockers = blockers.bitOr(blocker);
            }
        }
        return blockers;
    }

    pub fn occupied(self: Board) Bitboard {
        return self.empty.invert();
    }

    pub fn fromFen(fen: []const u8) !Board {
        var board = empty();
        var file: usize = 0;
        var rank: usize = 7;

        std.debug.print("Board.FromFen: {s}\n", .{fen});
        for (fen) |c| {
            switch (c) {
                '1' => file += 1,
                '2' => file += 2,
                '3' => file += 3,
                '4' => file += 4,
                '5' => file += 5,
                '6' => file += 6,
                '7' => file += 7,
                '8' => file += 8,
                '/' => {},
                else => {
                    const pc = try Piece.fromChar(c);
                    board.setPieceOn(pc, Square{ .file = @intCast(file), .rank = @intCast(rank) });
                    file += 1;
                },
            }

            if (file == 8) {
                file = 0;
                if (rank == 0) {
                    break;
                }

                rank -= 1;
            }
        }

        return board;
    }

    pub fn toFen(self: Board) ![]const u8 {
        var result = std.ArrayList(u8).init(std.heap.page_allocator);
        defer result.deinit();

        var rank: usize = 8;
        while (rank > 0) {
            rank -= 1;
            var empty_count: u8 = 0;
            for (0..8) |file| {
                const sq = Square{ .file = @intCast(file), .rank = @intCast(rank) };
                const pc = try self.pieceOn(sq);
                if (pc == null or if (pc) |p| p.isEmpty() else false) {
                    empty_count += 1;
                } else {
                    if (empty_count > 0) {
                        try result.append('0' + @as(u8, empty_count));
                        empty_count = 0;
                    }
                    try result.append(pc.?.toChar());
                }
            }
            if (empty_count > 0) {
                try result.append('0' + @as(u8, empty_count));
            }
            if (rank != 0) {
                try result.append('/');
            }
        }

        return result.toOwnedSlice();
    }

    pub fn pieceTypeOn(self: Board, sq: Square) callconv(.Inline) !PieceType {
        if (sq.in(self.empty)) {
            return PieceType.Empty;
        } else if (sq.in(self.pawns)) {
            return PieceType.Pawn;
        } else if (sq.in(self.knights)) {
            return PieceType.Knight;
        } else if (sq.in(self.bishops)) {
            return PieceType.Bishop;
        } else if (sq.in(self.rooks)) {
            return PieceType.Rook;
        } else if (sq.in(self.queens)) {
            return PieceType.Queen;
        } else if (sq.in(self.kings)) {
            return PieceType.King;
        } else {
            return error.InvalidSquareError;
        }
    }

    pub fn pieceOn(self: Board, sq: Square) !?Piece {
        return Piece{
            .color = if (sq.in(self.white)) Color.White else if (sq.in(self.black)) Color.Black else return null,
            .piece_type = try pieceTypeOn(self, sq),
        };
    }

    pub fn debug(self: *const Board) ![72:0]u8 {
        var result: [72:0]u8 = undefined;

        for (&result, 0..) |*val, i| {
            const file: usize = i % 9;
            const rank: usize = (71 - i) / 9;

            if (file == 8) {
                val.* = '\n';
            } else {
                const p = try self.pieceOn(Square{ .file = @intCast(file), .rank = @intCast(rank) });
                val.* = if (p == null) '.' else p.?.toChar();
            }
        }

        return result;
    }

    pub fn clone(self: Board) Board {
        return Board{
            .empty = self.empty.clone(),
            .pawns = self.pawns.clone(),
            .knights = self.knights.clone(),
            .bishops = self.bishops.clone(),
            .rooks = self.rooks.clone(),
            .queens = self.queens.clone(),
            .kings = self.kings.clone(),
            .white = self.white.clone(),
            .black = self.black.clone(),
        };
    }
};

pub fn empty() Board {
    return Board{
        .empty = Bitboard{ .bits = 0xffff_ffff_ffff_ffff },
        .pawns = Bitboard{ .bits = 0 },
        .knights = Bitboard{ .bits = 0 },
        .bishops = Bitboard{ .bits = 0 },
        .rooks = Bitboard{ .bits = 0 },
        .queens = Bitboard{ .bits = 0 },
        .kings = Bitboard{ .bits = 0 },
        .white = Bitboard{ .bits = 0 },
        .black = Bitboard{ .bits = 0 },
    };
}

pub fn standard() Board {
    return Board{
        .pawns = Bitboard{ .bits = 0x00ff_0000_0000_ff00 },
        .knights = Bitboard{ .bits = 0x4200_0000_0000_0042 },
        .bishops = Bitboard{ .bits = 0x2400_0000_0000_0024 },
        .rooks = Bitboard{ .bits = 0x8100_0000_0000_0081 },
        .queens = Bitboard{ .bits = 0x0800_0000_0000_0008 },
        .kings = Bitboard{ .bits = 0x1000_0000_0000_0010 },
        .white = Bitboard{ .bits = 0x0000_0000_0000_ffff },
        .black = Bitboard{ .bits = 0xffff_0000_0000_0000 },
        .empty = Bitboard{ .bits = 0x0000_ffff_ffff_0000 },
    };
}
