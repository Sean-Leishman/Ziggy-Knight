const std = @import("std");
const board = @import("board.zig");
const color = @import("color.zig");
const move = @import("move.zig");
const bitboard = @import("bitboard.zig");
const square = @import("square.zig");
const piece = @import("piece.zig");
const move_generator = @import("move_generator.zig");
const zobrist = @import("zobrist.zig");

const Board = board.Board;
const Color = color.Color;
const Move = move.Move;
const MoveList = move.MoveList;
const Bitboard = bitboard.Bitboard;
const Square = square.Square;
const Piece = piece.Piece;
const PieceType = piece.PieceType;

pub const Game = struct {
    board: Board,
    color: Color,
    castles: Bitboard,
    en_passant: ?Square,
    halfmove_clock: u8,
    fullmove_number: u10,

    checkers: Bitboard = Bitboard{ .bits = 0 },
    legalMoves: MoveList = MoveList{},
    hash: u64 = 0,

    pub fn us(self: Game) Bitboard {
        return self.board.ofColor(self.color);
    }

    pub fn our(self: Game, piece_type: PieceType) Bitboard {
        return self.us().bitAnd(self.board.ofPieceType(piece_type));
    }

    pub fn them(self: Game) Bitboard {
        return self.board.ofColor(self.theirColor());
    }

    pub fn their(self: Game, piece_type: PieceType) Bitboard {
        return self.them().bitAnd(self.board.ofPieceType(piece_type));
    }

    pub fn ourColor(self: Game) Color {
        return self.color;
    }

    pub fn theirColor(self: Game) Color {
        return self.color.invert();
    }

    pub fn isCheck(self: Game) bool {
        return self.checkers.isNotEmpty();
    }

    pub fn isCheckmate(self: Game) bool {
        return self.isCheck() and self.legalMoves.isEmpty();
    }

    pub fn isStalemate(self: Game) bool {
        return !self.isCheck() and self.legalMoves.isEmpty();
    }

    pub fn isGameOver(self: Game) bool {
        return self.isCheckmate() or self.isStalemate();
    }

    pub fn playCheckMove(self: *Game, mv: Move) !void {
        const legal_mv = self.checkMove(mv) catch |err| {
            return err;
        };
        self.playMove(legal_mv);
    }

    pub fn checkMove(self: Game, mv: Move) !Move {
        var legalMoves = try move_generator.legalMoves(self);
        if (legalMoves.isEmpty()) {
            return error.NoLegalMoves;
        }

        for (legalMoves.range()) |legalMove| {
            if (legalMove.from == mv.from and legalMove.to == mv.to) {
                return Move{
                    .from = legalMove.from,
                    .to = legalMove.to,
                    .mover = legalMove.mover,
                    .special = legalMove.special,
                    .result = legalMove.result,
                };
            }
        }

        return error.IllegalMove;
    }

    pub fn playMove(self: *Game, mv: Move) void {
        self.en_passant = null;

        const back = bitboard.relativeRank(self.color, 0);
        const king_side = (mv.from.toBitboard().bitAnd(bitboard.kingside)).isNotEmpty();
        const back_side = back.bitAnd(if (king_side) bitboard.kingside else bitboard.queenside);
        if (mv.mover == PieceType.King) {
            self.castles = self.castles.bitAnd(back.invert());
            if (mv.special) {
                self.board.removeOn(back_side.bitAnd(bitboard.corners).toSquare().?);
                const rook = back_side.bitAnd(bitboard.rook_castle).toSquare().?;
                self.board.setPieceOn(Piece{ .piece_type = PieceType.Rook, .color = self.color }, rook);
            }
        }
        if (mv.special and mv.mover == PieceType.Pawn) { // separating these as if statements improves performance
            if (mv.result == PieceType.Pawn) {
                // en passant capture
                self.board.removeOn(Square{ .file = mv.to.file, .rank = mv.from.rank });
            } else if (mv.result == PieceType.Empty) {
                // en passant available
                self.en_passant = Square{ .rank = self.color.wlbr(u3, 2, 5), .file = mv.from.file };
            }
        }
        self.castles.clearBit(mv.from);
        self.castles.clearBit(mv.to); // if we ever move to a castles square, clear it permanently
        self.board.removeOn(mv.from); // no matter what, we move away from a square and to a square
        self.board.setPieceOn(Piece{ .piece_type = mv.mover, .color = self.color }, mv.to);

        self.halfmove_clock = if (mv.resetsHalfMoveClock()) 0 else self.halfmove_clock + 1;
        self.fullmove_number += self.color.wlbr(u10, 0, 1);

        self.color = self.color.invert();
        self.checkers = self.board.checkers(self.color); // calculate new checkers for new player
        self.legalMoves = move_generator.legalMoves(self.*) catch MoveList{};
    }

    pub fn undoMove(self: *Game, mv: Move) void {
        self.color = self.color.invert();

        if (mv.mover == PieceType.King) {
            self.castles.setBits(mv.from.toBitboard().bitAnd(bitboard.corners)); // set the castle bits
            self.castles.setBits(mv.to.toBitboard().bitAnd(bitboard.corners)); // for castling rights on corner
            if (mv.special) {
                self.board.removeOn(mv.to); // removes the king
                const back = bitboard.relativeRank(self.color, 0);
                const back_side = back.bitAnd(if (mv.from.file > mv.to.file) bitboard.kingside else bitboard.queenside);
                const rook = back_side.bitAnd(bitboard.rook_castle).toSquare().?;
                self.board.removeOn(rook); // removes the rook
                self.board.setPieceOn(Piece{ .piece_type = PieceType.King, .color = self.color }, mv.from);

                const dest_rook_square = back_side.bitAnd(bitboard.corners).toSquare().?; // place rook on the corner
                self.board.setPieceOn(Piece{ .piece_type = PieceType.Rook, .color = self.color }, dest_rook_square);
            }
        }
        if (mv.special and mv.mover == PieceType.Pawn) { // separating these as if statements improves performance
            if (mv.result == PieceType.Pawn) {
                self.en_passant = Square{ .rank = self.color.wlbr(u3, 2, 5), .file = mv.to.file };
                self.board.setPieceOn(Piece{ .piece_type = PieceType.Pawn, .color = self.color.invert() }, Square{ .rank = self.color.wlbr(u3, 2, 5), .file = mv.to.file }); // place the captured pawn back on the square
            } else if (mv.result == PieceType.Empty) {
                self.en_passant = null;
            }
        }

        // if we undo move to a castle square, we need to set the castle bit
        const relative_rank: u8 = if (self.color == Color.White) 0 else 7;
        if (relative_rank == mv.to.rank and (mv.to.file == 0 or mv.to.file == 7)) {
            self.castles.setBit((Square{ .file = mv.to.file, .rank = mv.to.rank }));
        }

        self.board.removeOn(mv.to); // remove the piece from the destination square
        self.board.setPieceOn(Piece{ .piece_type = mv.mover, .color = self.color }, mv.from); // place the piece back on the source square
        if (mv.result != PieceType.Empty and !mv.special) { // if the move was a capture, we need to place the captured piece back on the board
            self.board.setPieceOn(Piece{ .piece_type = mv.result, .color = self.color.invert() }, mv.to);
        }
        // self.halfmove_clock = if (mv.resetsHalfMoveClock()) 0 else self.halfmove_clock - 1;
        self.fullmove_number -= self.color.wlbr(u10, 0, 1);

        self.checkers = self.board.checkers(self.color); // calculate new checkers for new player
        self.legalMoves = move_generator.legalMoves(self.*) catch MoveList{};
    }

    pub fn toFen(self: Game) ![]const u8 {
        var fen = std.ArrayList(u8).init(std.heap.page_allocator);
        defer fen.deinit();

        try fen.appendSlice(try self.board.toFen());
        try fen.append(' ');
        try fen.append(self.color.toChar());
        try fen.append(' ');

        if (self.castles.isEmpty()) {
            try fen.append('-');
        } else {
            if (self.castles.contains(Square{ .file = 0, .rank = 0 })) {
                try fen.append('K');
            }
            if (self.castles.contains(Square{ .file = 0, .rank = 7 })) {
                try fen.append('k');
            }
            if (self.castles.contains(Square{ .file = 7, .rank = 0 })) {
                try fen.append('Q');
            }
            if (self.castles.contains(Square{ .file = 7, .rank = 7 })) {
                try fen.append('q');
            }
        }

        try fen.append(' ');
        if (self.en_passant) |ep| {
            try fen.appendSlice(&ep.toString());
        } else {
            try fen.append('-');
        }
        try fen.append(' ');
        try std.fmt.format(fen.writer(), "{d}", .{self.halfmove_clock});
        try fen.append(' ');
        try std.fmt.format(fen.writer(), "{d}", .{self.fullmove_number});

        return fen.toOwnedSlice();
    }

    pub fn fromFen(fen: []const u8) !Game {
        var it = std.mem.splitAny(u8, fen, " ");

        const board_fen = it.next() orelse return error.InvalidFen;
        const brd = Board.fromFen(board_fen) catch return error.InvalidFen;

        const color_fen = it.next() orelse return error.InvalidFen;
        if (color_fen.len != 1) {
            return error.InvalidFen;
        }

        const clr = switch (color_fen[0]) {
            'w' => Color.White,
            'b' => Color.Black,
            else => return error.InvalidFen,
        };

        const castles_fen = it.next() orelse return error.InvalidFen;
        var castles = bitboard.empty;
        for (castles_fen) |c| {
            switch (c) {
                'K' => castles.setBits(bitboard.kingside.bitAnd(bitboard.rank(0))),
                'Q' => castles.setBits(bitboard.queenside.bitAnd(bitboard.rank(0))),
                'k' => castles.setBits(bitboard.kingside.bitAnd(bitboard.rank(7))),
                'q' => castles.setBits(bitboard.queenside.bitAnd(bitboard.rank(7))),
                '-' => {}, // do nothing,
                else => return error.InvalidFen,
            }
        }

        const en_passant_fen = it.next() orelse return error.InvalidFen;
        var en_passant: ?Square = null;
        if (en_passant_fen.len == 2) {
            en_passant = Square.fromString(en_passant_fen) catch return error.InvalidFen;
        }

        const halfmove_clock_fen = it.next() orelse return error.InvalidFen;
        const halfmove_clock = std.fmt.parseInt(u8, halfmove_clock_fen, 10) catch return error.InvalidFen;

        const fullmove_number_fen = it.next() orelse return error.InvalidFen;
        const fullmove_number = std.fmt.parseInt(u8, fullmove_number_fen, 10) catch return error.InvalidFen;

        var gme = Game{
            .board = brd,
            .color = clr,
            .castles = castles,
            .en_passant = en_passant,
            .halfmove_clock = halfmove_clock,
            .fullmove_number = fullmove_number,
        };

        gme.checkers = gme.board.checkers(gme.color);
        return gme;
    }

    pub fn clone(self: Game) *Game {
        return &Game{
            .board = self.board.clone(),
            .color = self.color.clone(),
            .castles = self.castles.clone(),
            .en_passant = self.en_passant,
            .halfmove_clock = self.halfmove_clock,
            .fullmove_number = self.fullmove_number,
        };
    }
};

pub fn standard() Game {
    return Game{
        .board = board.standard(),
        .color = Color.White,
        .castles = bitboard.corners,
        .en_passant = null,
        .halfmove_clock = 0,
        .fullmove_number = 1,
    };
}
