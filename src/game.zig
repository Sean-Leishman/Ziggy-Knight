const std = @import("std");
const testing = std.testing;
const board = @import("board.zig");
const color = @import("color.zig");
const setup = @import("setup.zig");
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

pub const GameState = struct {
    castles: Bitboard,
    en_passant: ?Square,
    halfmove_clock: u8,
    fullmove_number: u10,
    hash: u64,
};

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

    pub fn equals(self: Game, other: Game) bool {
        return self.board.equals(other.board) and self.color == other.color and self.castles == other.castles and self.en_passant == other.en_passant and self.halfmove_clock == other.halfmove_clock and self.fullmove_number == other.fullmove_number and self.hash == other.hash;
    }

    pub fn saveState(self: *Game) GameState {
        return GameState{
            .castles = self.castles,
            .en_passant = self.en_passant,
            .halfmove_clock = self.halfmove_clock,
            .fullmove_number = self.fullmove_number,
            .hash = self.hash,
        };
    }

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

    pub fn playCheckMove(self: *Game, mv: Move) !GameState {
        const legal_mv = self.checkMove(mv) catch |err| {
            return err;
        };
        return self.playMove(legal_mv);
    }

    pub fn checkMove(self: Game, mv: Move) !Move {
        var legalMoves = try move_generator.legalMoves(self);
        if (legalMoves.isEmpty()) {
            return error.NoLegalMoves;
        }

        for (legalMoves.range()) |legalMove| {
            if (legalMove.from == mv.from and legalMove.to == mv.to) {
                std.debug.print("Found legal move: {} {}\n", .{ legalMove, mv });
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

    pub fn playMove(self: *Game, mv: Move) !GameState {
        const game_state = self.saveState();

        if (self.en_passant) |old_ep| {
            self.hash ^= zobrist.EnPassantHash[old_ep.file];
        }
        self.en_passant = null;

        self.hash ^= zobrist.CastlingHash[self.castles.castleIndex()]; // hash out old castle rights
        self.hash ^= zobrist.TurnHash;

        const back = bitboard.relativeRank(self.color, 0);
        const king_side = (mv.to.toBitboard().bitAnd(bitboard.kingside)).isNotEmpty();
        const back_side = back.bitAnd(if (king_side) bitboard.kingside else bitboard.queenside);
        if (mv.mover == PieceType.King) {
            self.castles = self.castles.bitAnd(back.invert());
            if (mv.special) {
                self.removePiece(back_side.bitAnd(bitboard.corners).toSquare().?) catch return error.InvalidMove; // remove the rook from its original square
                const rook = back_side.bitAnd(bitboard.rook_castle).toSquare().?;
                self.addPiece(Piece{ .piece_type = PieceType.Rook, .color = self.color }, rook) catch return error.InvalidMove; // place the rook on its destination square
            }
        }
        if (mv.special and mv.mover == PieceType.Pawn) { // separating these as if statements improves performance
            if (mv.result == PieceType.Pawn) {
                // en passant capture
                self.removePiece(Square{ .file = mv.to.file, .rank = mv.from.rank }) catch return error.InvalidMove;
            } else if (mv.result == PieceType.Empty) {
                // en passant available
                self.en_passant = Square{ .rank = self.color.wlbr(u3, 2, 5), .file = mv.from.file };
                self.hash ^= zobrist.EnPassantHash[self.en_passant.?.file];
            }
        }
        self.castles.clearBit(mv.from);
        self.castles.clearBit(mv.to); // if we ever move to a castles square, clear it permanently
        self.hash ^= zobrist.CastlingHash[self.castles.castleIndex()]; // hash in new castle rights

        self.removePiece(mv.from) catch return error.InvalidMove; // remove the piece from the source square
        self.addPiece(Piece{ .piece_type = mv.mover, .color = self.color }, mv.to) catch return error.InvalidMove; // place the piece on the destination square

        self.halfmove_clock = if (mv.resetsHalfMoveClock()) 0 else self.halfmove_clock + 1;
        self.fullmove_number += self.color.wlbr(u10, 0, 1);

        self.color = self.color.invert();
        self.checkers = self.board.checkers(self.color); // calculate new checkers for new player
        self.legalMoves = move_generator.legalMoves(self.*) catch MoveList{};

        return game_state;
    }

    fn addPiece(self: *Game, pce: Piece, sq: Square) !void {
        self.board.setPieceOn(pce, sq);
        self.hash ^= zobrist.ZobristTable[pce.index()][sq.index()];
    }

    fn removePiece(self: *Game, sq: Square) !void {
        const pc = self.board.pieceOn(sq) catch return error.InvalidMove;
        if (pc == null) {
            return error.NoPieceOnSquare;
        }

        std.debug.assert(pc.?.index() < zobrist.N_PIECES);
        std.debug.assert(sq.index() < zobrist.N_SQUARES);

        self.hash ^= zobrist.ZobristTable[pc.?.index()][sq.index()];
        self.board.removeOn(sq);
    }

    pub fn undoMove(self: *Game, mv: Move, state: GameState) !void {
        self.color = self.color.invert();

        const back = bitboard.relativeRank(self.color, 0);
        if (mv.mover == PieceType.King) {
            if (mv.special) {
                const king_side = (mv.to.toBitboard().bitAnd(bitboard.kingside)).isNotEmpty();
                const back_side = back.bitAnd(if (king_side) bitboard.kingside else bitboard.queenside);
                self.removePiece(back_side.bitAnd(bitboard.rook_castle).toSquare().?) catch return error.InvalidMove; // remove the rook from its destination square
                //
                self.addPiece(Piece{ .piece_type = PieceType.Rook, .color = self.color }, back_side.bitAnd(bitboard.corners).toSquare().?) catch return error.InvalidMove; // place the rook back on its original square
            }
        }
        if (mv.special and mv.mover == PieceType.Pawn) { // separating these as if statements improves performance
            if (mv.result == PieceType.Pawn) {
                self.addPiece(Piece{ .piece_type = PieceType.Pawn, .color = self.color.invert() }, Square{ .rank = self.color.invert().wlbr(u3, 3, 4), .file = mv.to.file }) catch return error.InvalidMove; // place the captured pawn back on the square
            }
        }

        self.removePiece(mv.to) catch return error.InvalidMove; // remove the piece from the destination square
        self.addPiece(Piece{ .piece_type = mv.mover, .color = self.color }, mv.from) catch return error.InvalidMove; // place the piece back on the source square
        if (mv.result != PieceType.Empty and !mv.special) { // if the move was a capture, we need to place the captured piece back on the board
            self.addPiece(Piece{ .piece_type = mv.result, .color = self.color.invert() }, mv.to) catch return error.InvalidMove;
        }

        self.castles = state.castles;
        self.en_passant = state.en_passant;
        self.halfmove_clock = state.halfmove_clock;
        self.fullmove_number = state.fullmove_number;
        self.hash = state.hash;

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
            if (self.castles.contains(Square{ .file = 7, .rank = 0 })) {
                try fen.append('Q');
            }
            if (self.castles.contains(Square{ .file = 0, .rank = 7 })) {
                try fen.append('k');
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

    pub fn setFen(self: *Game, fen: []const u8) !void {
        var it = std.mem.splitAny(u8, fen, " ");
        const board_fen = it.next() orelse return error.InvalidFen;

        var file: usize = 0;
        var rank: usize = 7;

        for (board_fen) |c| {
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
                    self.addPiece(pc, Square{ .file = @intCast(file), .rank = @intCast(rank) }) catch return error.InvalidFen;
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

        const color_fen = it.next() orelse return error.InvalidFen;
        if (color_fen.len != 1) {
            return error.InvalidFen;
        }

        const clr = switch (color_fen[0]) {
            'w' => Color.White,
            'b' => Color.Black,
            else => return error.InvalidFen,
        };

        if (clr == Color.Black) {
            self.hash ^= zobrist.TurnHash;
        }

        const castles_fen = it.next() orelse return error.InvalidFen;
        var castles = bitboard.empty;
        for (castles_fen) |c| {
            switch (c) {
                'K' => castles.setBits(bitboard.rank(0).bitAnd(bitboard.file(7))),
                'Q' => castles.setBits(bitboard.rank(0).bitAnd(bitboard.file(0))),
                'k' => castles.setBits(bitboard.rank(7).bitAnd(bitboard.file(7))),
                'q' => castles.setBits(bitboard.rank(7).bitAnd(bitboard.file(0))),
                '-' => {}, // do nothing,
                else => return error.InvalidFen,
            }
        }
        self.hash ^= zobrist.CastlingHash[castles.castleIndex()];

        const en_passant_fen = it.next() orelse return error.InvalidFen;
        var en_passant: ?Square = null;
        if (en_passant_fen.len == 2) {
            en_passant = Square.fromString(en_passant_fen) catch return error.InvalidFen;
            self.hash ^= zobrist.EnPassantHash[en_passant.?.file];
        }

        const halfmove_clock_fen = it.next() orelse return error.InvalidFen;
        const halfmove_clock = std.fmt.parseInt(u8, halfmove_clock_fen, 10) catch return error.InvalidFen;

        const fullmove_number_fen = it.next() orelse return error.InvalidFen;
        const fullmove_number = std.fmt.parseInt(u8, fullmove_number_fen, 10) catch return error.InvalidFen;

        self.castles = castles;
        self.checkers = self.board.checkers(self.color);
        self.halfmove_clock = halfmove_clock;
        self.fullmove_number = fullmove_number;
        self.color = clr;
        self.en_passant = en_passant;
    }

    pub fn clone(self: Game) Game {
        return Game{
            .board = self.board.clone(),
            .color = self.color.clone(),
            .castles = self.castles.clone(),
            .en_passant = self.en_passant,
            .halfmove_clock = self.halfmove_clock,
            .fullmove_number = self.fullmove_number,
            .hash = self.hash,
        };
    }
};

pub fn standard() Game {
    var gme = empty();
    gme.setFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") catch unreachable;
    gme.legalMoves = move_generator.legalMoves(gme) catch MoveList{};

    return gme;
}

pub fn empty() Game {
    return Game{
        .board = board.empty(),
        .color = Color.White,
        .castles = bitboard.empty,
        .en_passant = null,
        .halfmove_clock = 0,
        .fullmove_number = 1,
    };
}

test "Zobrist FEN round trip hash" {
    const gme = standard();
    const fen = try gme.toFen();

    var gme2 = empty();
    try gme2.setFen(fen);
    try std.testing.expectEqual(gme.hash, gme2.hash);
}

test "Game FEN round trip" {
    var gme = standard();
    const fen = try gme.toFen();

    std.debug.print("Standard FEN: {s}\n", .{fen});

    var gme2 = empty();
    try gme2.setFen(fen);
    const fen2 = try gme2.toFen();
    std.debug.print("Round trip FEN: {s}\n", .{fen2});

    try std.testing.expectEqualStrings(fen, fen2);
}

test "zobrist hash changes after move" {
    setup.init();

    var gm = standard();
    const initial_hash = gm.hash;

    const mv = Move{ .from = .{ .file = 4, .rank = 1 }, .to = .{ .file = 4, .rank = 3 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm.playMove(mv);

    try std.testing.expect(gm.hash != initial_hash);
}
test "zobrist hash is reversible with undoMove" {
    setup.init();

    var gm1 = standard();
    const initial_hash = gm1.hash;

    var gm2 = gm1.clone();

    try std.testing.expectEqual(initial_hash, gm2.hash);

    // Make moves on gm1
    const mv1 = Move{ .from = .{ .file = 4, .rank = 1 }, .to = .{ .file = 4, .rank = 3 }, .special = false, .mover = .Pawn, .result = .Empty };
    const state1 = gm1.playMove(mv1);

    const mv2 = Move{ .from = .{ .file = 4, .rank = 6 }, .to = .{ .file = 4, .rank = 4 }, .special = false, .mover = .Pawn, .result = .Empty };
    const state2 = gm2.playMove(mv2);

    try std.testing.expect(gm1.hash != gm2.hash);

    try std.testing.expect(gm1.hash != initial_hash);
    gm1.undoMove(mv1, state1) catch unreachable;
    try std.testing.expectEqual(initial_hash, gm1.hash);

    try std.testing.expect(gm2.hash != initial_hash);
    gm2.undoMove(mv2, state2) catch unreachable;
    try std.testing.expectEqual(initial_hash, gm2.hash);
}

test "game state is revsersible" {
    setup.init();

    var gm = standard();
    const gm_clone = gm.clone();

    // Make a move
    const mv = Move{ .from = .{ .file = 4, .rank = 1 }, .to = .{ .file = 4, .rank = 3 }, .special = false, .mover = .Pawn, .result = .Empty };
    const state = gm.playMove(mv);

    // Undo the move
    gm.undoMove(mv, state) catch unreachable;

    try std.testing.expectEqualDeep(gm.saveState(), state);
    try std.testing.expect(gm.equals(gm_clone));
    try std.testing.expectEqualStrings(try gm.toFen(), try gm_clone.toFen());
}

test "game state is reversible with castling move" {
    setup.init();

    var gm = standard();

    // Make moves to enable castling
    const e4 = Move{ .from = .{ .file = 4, .rank = 1 }, .to = .{ .file = 4, .rank = 3 }, .special = false, .mover = .Pawn, .result = .Empty };
    const e4_state = gm.playMove(e4);
    const e4_fen = try gm.toFen();

    const e5 = Move{ .from = .{ .file = 4, .rank = 6 }, .to = .{ .file = 4, .rank = 4 }, .special = false, .mover = .Pawn, .result = .Empty };
    const e5_state = gm.playMove(e5);
    const e5_fen = try gm.toFen();

    const nf3 = Move{ .from = .{ .file = 6, .rank = 0 }, .to = .{ .file = 5, .rank = 2 }, .special = false, .mover = .Knight, .result = .Empty };
    const nf3_state = gm.playMove(nf3);
    const nf3_fen = try gm.toFen();

    const nc6 = Move{ .from = .{ .file = 1, .rank = 7 }, .to = .{ .file = 2, .rank = 5 }, .special = false, .mover = .Knight, .result = .Empty };
    const nc6_state = gm.playMove(nc6);
    const nc6_fen = try gm.toFen();

    const bf2 = Move{ .from = .{ .file = 5, .rank = 0 }, .to = .{ .file = 2, .rank = 3 }, .special = false, .mover = .Bishop, .result = .Empty };
    const bf2_state = gm.playMove(bf2);
    const bf2_fen = try gm.toFen();

    const bc5 = Move{ .from = .{ .file = 5, .rank = 7 }, .to = .{ .file = 2, .rank = 4 }, .special = false, .mover = .Bishop, .result = .Empty };
    const bc5_state = gm.playMove(bc5);
    const bc5_fen = try gm.toFen();

    const state_before_castle = gm.saveState();

    // Now castle
    const o_o_move = Move{ .from = .{ .file = 4, .rank = 0 }, .to = .{ .file = 6, .rank = 0 }, .special = true, .mover = .King, .result = .Empty };
    const castle_state = gm.playMove(o_o_move);
    try std.testing.expectEqualStrings(try gm.toFen(), "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQ1RK1 b kq - 5 4");

    // Undo the castling move
    gm.undoMove(o_o_move, castle_state) catch unreachable;
    try std.testing.expectEqualDeep(state_before_castle, gm.saveState());
    try std.testing.expectEqualStrings(try gm.toFen(), bc5_fen);

    // Undo all previous moves
    const moves_to_undo = [_]Move{ bc5, bf2, nc6, nf3, e5, e4 };
    const states_to_undo = [_]GameState{ bc5_state, bf2_state, nc6_state, nf3_state, e5_state, e4_state };
    const fen_states = [_][]const u8{ bc5_fen, bf2_fen, nc6_fen, nf3_fen, e5_fen, e4_fen };
    var current_state = gm.saveState();
    var current_fen = try gm.toFen();
    var idx: usize = 0;
    for (moves_to_undo) |mve| {
        gm.undoMove(mve, states_to_undo[idx]) catch unreachable;
        current_state = gm.saveState();
        try std.testing.expectEqualDeep(current_state, states_to_undo[idx]);
        try std.testing.expectEqualStrings(current_fen, fen_states[idx]);
        current_fen = try gm.toFen();
        idx += 1;
    }
}

test "game state is reversible with en passant move" {
    setup.init();

    var gm = standard();

    // Make moves to enable en passant
    const e4 = Move{ .from = .{ .file = 4, .rank = 1 }, .to = .{ .file = 4, .rank = 3 }, .special = false, .mover = .Pawn, .result = .Empty };
    const e4_state = gm.playMove(e4);
    const e4_fen = try gm.toFen();

    const d5 = Move{ .from = .{ .file = 3, .rank = 6 }, .to = .{ .file = 3, .rank = 4 }, .special = false, .mover = .Pawn, .result = .Empty };
    const d5_state = gm.playMove(d5);
    const d5_fen = try gm.toFen();

    const e5 = Move{ .from = .{ .file = 4, .rank = 3 }, .to = .{ .file = 4, .rank = 4 }, .special = false, .mover = .Pawn, .result = .Empty };
    const e5_state = gm.playMove(e5);
    const e5_fen = try gm.toFen();

    const f5 = Move{ .from = .{ .file = 5, .rank = 6 }, .to = .{ .file = 5, .rank = 4 }, .special = true, .mover = .Pawn, .result = .Empty };
    const f5_state = gm.playMove(f5);
    const f5_fen = try gm.toFen();

    const state_before_en_passant = gm.saveState();

    // Now perform en passant
    const exf5 = Move{ .from = .{ .file = 4, .rank = 4 }, .to = .{ .file = 5, .rank = 5 }, .special = true, .mover = .Pawn, .result = .Pawn };
    const exf5_state = gm.playMove(exf5);
    try std.testing.expectEqualStrings(try gm.toFen(), "rnbqkbnr/ppp1p1pp/5P2/3p4/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 3");

    // Undo the en passant move
    gm.undoMove(exf5, exf5_state) catch unreachable;
    try std.testing.expectEqualDeep(state_before_en_passant, gm.saveState());
    try std.testing.expectEqualStrings(try gm.toFen(), f5_fen);

    // Undo all previous moves
    const moves_to_undo = [_]Move{ f5, e5, d5, e4 };
    const states_to_undo = [_]GameState{ f5_state, e5_state, d5_state, e4_state };
    const fen_states = [_][]const u8{ f5_fen, e5_fen, d5_fen, e4_fen };
    var current_state = gm.saveState();
    var current_fen = try gm.toFen();
    var idx: usize = 0;
    for (moves_to_undo) |mve| {
        gm.undoMove(mve, states_to_undo[idx]) catch unreachable;
        current_state = gm.saveState();
        try std.testing.expectEqualDeep(current_state, states_to_undo[idx]);
        try std.testing.expectEqualStrings(current_fen, fen_states[idx]);
        current_fen = try gm.toFen();
        idx += 1;
    }
}

test "zobrist hash is reversible with clone" {
    setup.init();

    var gm1 = standard();
    const initial_hash = gm1.hash;

    // Clone the game
    const gm2 = gm1.clone();

    // Make moves on gm1
    const mv1 = Move{ .from = .{ .file = 4, .rank = 1 }, .to = .{ .file = 4, .rank = 3 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm1.playMove(mv1);

    const mv2 = Move{ .from = .{ .file = 4, .rank = 6 }, .to = .{ .file = 4, .rank = 4 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm1.playMove(mv2);

    // gm2 should still have the initial hash
    try std.testing.expectEqual(initial_hash, gm2.hash);

    // gm1 should have a different hash
    try std.testing.expect(gm1.hash != initial_hash);
}

test "zobrist same position different move order" {
    setup.init();

    // 1: e4, e5, Nf3, Nc6
    var gm1 = standard();

    const e4 = Move{ .from = .{ .file = 4, .rank = 1 }, .to = .{ .file = 4, .rank = 3 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm1.playMove(e4);

    const e5 = Move{ .from = .{ .file = 4, .rank = 6 }, .to = .{ .file = 4, .rank = 4 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm1.playMove(e5);

    const nf3 = Move{ .from = .{ .file = 6, .rank = 0 }, .to = .{ .file = 5, .rank = 2 }, .special = false, .mover = .Knight, .result = .Empty };
    _ = gm1.playMove(nf3);

    const nc6 = Move{ .from = .{ .file = 1, .rank = 7 }, .to = .{ .file = 2, .rank = 5 }, .special = false, .mover = .Knight, .result = .Empty };
    _ = gm1.playMove(nc6);

    const hash1 = gm1.hash;

    // 2: Nf3, Nc6, e4, e5 (different order, same position)
    var gm2 = standard();
    _ = gm2.playMove(nf3);
    _ = gm2.playMove(nc6);
    _ = gm2.playMove(e4);
    _ = gm2.playMove(e5);

    const hash2 = gm2.hash;

    // Same position should have same hash
    try std.testing.expectEqual(hash1, hash2);
}

test "zobrist hash unique for different positions" {
    setup.init();

    var gm1 = standard();
    var gm2 = standard();
    var gm3 = standard();

    // Position 1: e4
    const e4 = Move{ .from = .{ .file = 4, .rank = 1 }, .to = .{ .file = 4, .rank = 3 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm1.playMove(e4);

    // Position 2: d4
    const d4 = Move{ .from = .{ .file = 3, .rank = 1 }, .to = .{ .file = 3, .rank = 3 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm2.playMove(d4);

    // Position 3: Nf3
    const nf3 = Move{ .from = .{ .file = 6, .rank = 0 }, .to = .{ .file = 5, .rank = 2 }, .special = false, .mover = .Knight, .result = .Empty };
    _ = gm3.playMove(nf3);

    // All three should have different hashes
    try std.testing.expect(gm1.hash != gm2.hash);
    try std.testing.expect(gm1.hash != gm3.hash);
    try std.testing.expect(gm2.hash != gm3.hash);
}

test "zobrist hash changes with side to move" {
    setup.init();

    var gm = standard();
    const white_hash = gm.hash;

    // After one move, it's black's turn
    const e4 = Move{ .from = .{ .file = 4, .rank = 1 }, .to = .{ .file = 4, .rank = 3 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm.playMove(e4);

    // Hash should be different (different side to move)
    try std.testing.expect(gm.hash != white_hash);
}

test "zobrist hash with captures" {
    setup.init();

    var gm = standard();

    // Set up a position with a capture available
    const e4 = Move{ .from = .{ .file = 4, .rank = 1 }, .to = .{ .file = 4, .rank = 3 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm.playMove(e4);

    const d5 = Move{ .from = .{ .file = 3, .rank = 6 }, .to = .{ .file = 3, .rank = 4 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm.playMove(d5);

    const hash_before_capture = gm.hash;

    // Capture exd5
    const exd5 = Move{ .from = .{ .file = 4, .rank = 3 }, .to = .{ .file = 3, .rank = 4 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm.playMove(exd5);

    // Hash should be different after capture
    try std.testing.expect(gm.hash != hash_before_capture);
}

test "zobrist hash with en passant" {
    setup.init();

    var gm = standard();

    // Move white pawn to e4
    const e4 = Move{ .from = .{ .file = 4, .rank = 1 }, .to = .{ .file = 4, .rank = 3 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm.playMove(e4);

    // Move black pawn
    const a6 = Move{ .from = .{ .file = 0, .rank = 6 }, .to = .{ .file = 0, .rank = 5 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm.playMove(a6);

    // White pawn to e5
    const e5 = Move{ .from = .{ .file = 4, .rank = 3 }, .to = .{ .file = 4, .rank = 4 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm.playMove(e5);

    const hash_before_ep = gm.hash;

    // Black pawn d7-d5 (creates en passant opportunity)
    const d5 = Move{ .from = .{ .file = 3, .rank = 6 }, .to = .{ .file = 3, .rank = 4 }, .special = true, .mover = .Pawn, .result = .Empty };
    _ = gm.playMove(d5);

    // Hash should be different (en passant square is now available)
    try std.testing.expect(gm.hash != hash_before_ep);
    try std.testing.expect(gm.en_passant != null);
}

test "zobrist hash with castling rights change" {
    setup.init();

    var gm = standard();
    const initial_hash = gm.hash;

    // Move white king (loses all white castling rights)
    const ke2 = Move{ .from = .{ .file = 4, .rank = 0 }, .to = .{ .file = 4, .rank = 1 }, .special = false, .mover = .King, .result = .Empty };
    _ = gm.playMove(ke2);

    // Hash should change because castling rights changed
    try std.testing.expect(gm.hash != initial_hash);
}

test "zobrist hash out and hash in" {
    setup.init();

    var gm = standard();
    const initial_hash = gm.hash;

    const castled_out_hash = gm.hash ^ zobrist.CastlingHash[gm.castles.castleIndex()];
    try std.testing.expect(castled_out_hash != initial_hash);

    const castled_in_hash = castled_out_hash ^ zobrist.CastlingHash[gm.castles.castleIndex()];
    try std.testing.expectEqual(castled_in_hash, initial_hash);
}

test "zobrist FEN parsing produces correct hash" {
    setup.init();

    // Create position via moves
    var gm1 = standard();
    const e4 = Move{ .from = .{ .file = 4, .rank = 1 }, .to = .{ .file = 4, .rank = 3 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm1.playMove(e4); // white e4

    var gm1Temp = empty();
    try gm1Temp.setFen("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1");
    try std.testing.expectEqualStrings(gm1.toFen() catch "", gm1Temp.toFen() catch "");
    try std.testing.expectEqual(gm1.hash, gm1Temp.hash);

    const e5 = Move{ .from = .{ .file = 4, .rank = 6 }, .to = .{ .file = 4, .rank = 4 }, .special = false, .mover = .Pawn, .result = .Empty };
    _ = gm1.playMove(e5); // black e5

    const hash1 = gm1.hash;

    // Create same position via FEN
    var gm2 = empty();
    try gm2.setFen("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2");
    const hash2 = gm2.hash;

    // Should have same hash and same Fen
    try std.testing.expectEqualStrings(gm1.toFen() catch "", gm2.toFen() catch "");
    try std.testing.expectEqual(hash1, hash2);

    const nf3 = Move{ .from = .{ .file = 6, .rank = 0 }, .to = .{ .file = 5, .rank = 2 }, .special = false, .mover = .Knight, .result = .Empty };
    _ = gm1.playMove(nf3); // white Nf3
    const hash3 = gm1.hash;
    try std.testing.expect(hash3 != hash2);
    try std.testing.expect(hash3 != hash1);

    var gm3 = empty();
    try gm3.setFen("rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2");
    const hash4 = gm3.hash;
    try std.testing.expectEqualStrings(gm1.toFen() catch "", gm3.toFen() catch "");
    try std.testing.expectEqual(hash3, hash4);
}
