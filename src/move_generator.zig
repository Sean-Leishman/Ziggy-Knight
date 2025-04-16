const std = @import("std");
const game = @import("game.zig");
const move = @import("move.zig");
const piece = @import("piece.zig");
const attack = @import("attack.zig");
const bitboard = @import("bitboard.zig");
const square = @import("square.zig");

const Game = game.Game;
const MoveList = move.MoveList;
const Piece = piece.Piece;
const PieceType = piece.PieceType;
const Bitboard = bitboard.Bitboard;
const Square = square.Square;
const Move = move.Move;

pub fn legalMoves(gme: Game) !MoveList {
    var moves = MoveList{};
    const king_square = gme.our(PieceType.King).toSquare().?;
    std.debug.print("InCheck: {} {}\n", .{ gme.isCheck(), gme.checkers });

    if (!gme.isCheck()) {
        const not_us = gme.us().invert();

        try pieceMoves(&moves, gme, PieceType.Knight, not_us);
        try pieceMoves(&moves, gme, PieceType.Bishop, not_us);
        try pieceMoves(&moves, gme, PieceType.Rook, not_us);
        try pieceMoves(&moves, gme, PieceType.Queen, not_us);
        try pawnMoves(&moves, gme, not_us);
        try kingMoves(&moves, gme, not_us);
        try castlingMoves(&moves, gme, king_square);
    } else {
        try evasions(&moves, gme);
    }
    const blockers = gme.board.sliderBlockers(gme.them(), king_square);
    if (blockers.isNotEmpty() or gme.en_passant != null) {
        var i: usize = 0;
        while (i < moves.len()) {
            if (isSafe(&moves.moves[i], gme, king_square, blockers)) {
                i += 1;
            } else {
                _ = moves.swapRemove(i);
            }
        }
    }
    return moves;
}

fn isSafe(m: *Move, gme: Game, king: Square, blockers: Bitboard) callconv(.Inline) bool {
    if (m.mover == PieceType.King) return true;
    if ((m.mover == PieceType.Pawn) and (m.result == PieceType.Pawn) and m.special) {
        var occupied = gme.board.occupied();
        occupied.toggle(m.from);
        occupied.toggle(Square{ .file = m.to.file, .rank = m.from.rank });
        occupied = occupied.addSquare(m.to);
        const rooks_and_queens = gme.board.rooks.xor(gme.board.queens);
        const bishops_and_queens = gme.board.bishops.xor(gme.board.queens);
        const r_ray = attack.rookFrom(king, occupied).bitAnd(gme.them());
        const b_ray = attack.bishopFrom(king, occupied).bitAnd(gme.them());
        return (r_ray.bitAnd(rooks_and_queens)).isEmpty() and b_ray.bitAnd(bishops_and_queens).isEmpty();
    } else {
        return !blockers.contains(m.from) or attack.aligned(m.from, m.to, king);
    }
}

fn pieceMoves(moves: *MoveList, gme: Game, piece_type: PieceType, target: Bitboard) !void {
    const pce = Piece{ .piece_type = piece_type, .color = gme.color };
    var from_iter = gme.our(piece_type);
    while (from_iter.next()) |from_square| {
        var to_iter = attack.pieceFrom(from_square, pce, gme.board.occupied()).bitAnd(target);
        while (to_iter.next()) |to_square| {
            const captured_type = gme.board.pieceTypeOn(to_square) catch |err| {
                std.debug.print("Error PIECE: {} {} {} {} {}\n", .{ from_square, to_square, gme.board.occupied(), pce, err });
                return err;
            };
            try moves.push(Move.new(from_square, to_square, false, piece_type, captured_type));
        }
    }
}

fn pawnMoves(moves: *MoveList, gme: Game, target: Bitboard) callconv(.Inline) !void {
    const not_eighth_rank = bitboard.relativeRank(gme.color, 7).invert(); // 7 is 8th rank
    const pawntarget = target.bitAnd(not_eighth_rank).bitAnd(gme.them()); // them not on 8th
    // non-seventh rank pawn captures
    try pieceMoves(moves, gme, PieceType.Pawn, pawntarget);
    { // 7th rank pawn captures and promotions
        var from_iter = gme.our(PieceType.Pawn).bitAnd(bitboard.relativeRank(gme.color, 6)); // 7th rank
        while (from_iter.next()) |from| {
            var to_iter = attack.pawnFrom(gme.color, from).bitAnd(gme.them()).bitAnd(target);
            while (to_iter.next()) |to| {
                const captured_type = gme.board.pieceTypeOn(to) catch |err| {
                    std.debug.print("Error PAWN: {}\n", .{err});
                    return err;
                };
                try pushPawnPromotions(moves, from, to, captured_type);
            }
        }
    }
    // advance all our pawns one step forward to any empty squares
    const single_moves = gme.our(PieceType.Pawn).relativeShift(gme.color, 8).bitAnd(gme.board.empty);
    {
        var to_iter = single_moves.bitAnd(target);
        while (to_iter.next()) |to| {
            if (to.offset(gme.color.wlbr(i32, -8, 8))) |from| {
                // "mover" type becomes the "promoted to" type
                if ((to.rank == 7) or (to.rank == 0)) { // back ranks
                    try pushPawnPromotions(moves, from, to, PieceType.Empty);
                } else {
                    try moves.push(Move.new(from, to, false, PieceType.Pawn, PieceType.Empty));
                }
            }
        }
    }
    // advance our pawns that moved a single square, a second step forward to any empty squares
    const double_moves = single_moves.relativeShift(gme.color, 8).bitAnd(gme.board.empty);
    {
        var to_iter = double_moves.bitAnd(bitboard.relativeRank(gme.color, 3)).bitAnd(target);
        while (to_iter.next()) |to| {
            if (to.offset(gme.color.wlbr(i32, -16, 16))) |from| {
                try moves.push(Move.new(from, to, true, PieceType.Pawn, PieceType.Empty));
            }
        }
    }
    // en passant ... I should be able to optimize this...
    if (gme.en_passant) |ep_square| {
        const ep_file: i8 = @as(i8, ep_square.file);
        var fifth_rank = gme.our(PieceType.Pawn).bitAnd(bitboard.relativeRank(gme.color, 4));
        while (fifth_rank.next()) |from| {
            const pawn_file: i8 = @as(i8, from.file);
            if (((ep_file + 1) == pawn_file) or ((ep_file - 1) == pawn_file)) {
                try moves.push(Move.new(from, ep_square, true, PieceType.Pawn, PieceType.Pawn));
            }
        }
    }
}

fn kingMoves(moves: *MoveList, gme: Game, target: Bitboard) callconv(.Inline) !void {
    // try move_list.append((try gme.pieceMoves(PieceType.King, target)).constSlice());
    const king: Square = gme.our(PieceType.King).toSquare().?;
    var king_moves = attack.kingFrom(king).bitAnd(target);
    while (king_moves.next()) |to| {
        if (gme.board.attackersOf(to, gme.theirColor()).isEmpty()) {
            const captured_piece = gme.board.pieceTypeOn(to) catch |err| {
                std.debug.print("Error KING: {}\n", .{err});
                return err;
            };
            try moves.push(Move.new(king, to, false, PieceType.King, captured_piece));
        }
    }
}

fn castlingMoves(moves: *MoveList, gme: Game, king: Square) callconv(.Inline) !void {
    // expects that the checkers to the king are 0
    const back_rank: Bitboard = bitboard.relativeRank(gme.color, 0);
    var rook_squares: Bitboard = gme.castles.bitAnd(back_rank); // the corner squares
    while (rook_squares.next()) |rook| { // rook corner squares
        const side = if (king.distance(rook) == 3) bitboard.kingside else bitboard.queenside;
        const back_side = side.bitAnd(back_rank); // the four corner squares
        const collision_path = bitboard.rook_path.bitAnd(back_side); // squares the rook goes through
        if (collision_path.bitAnd(gme.board.occupied()).isNotEmpty()) continue; // in the way!
        var king_walk = back_side.bitAnd(bitboard.king_path); // squares the king goes through
        var found_attacker = false;
        while (king_walk.next()) |kwalk_square| { // check for attackers and abort if any!
            if (gme.board.attackersOf(kwalk_square, gme.theirColor()).isNotEmpty()) {
                found_attacker = true;
            }
        }
        if (!found_attacker) {
            const castle = bitboard.king_castle.bitAnd(back_side).toSquare().?;
            const mover = if (king.distance(rook) == 3) PieceType.King else PieceType.Queen;
            try moves.push(Move.new(king, castle, true, PieceType.King, mover));
        }
    }
}

fn evasions(moves: *MoveList, gme: Game) callconv(.Inline) !void {
    const king: Square = gme.our(PieceType.King).toSquare().?;
    var attacked = bitboard.empty;
    var sliders = gme.checkers.bitAnd(gme.board.sliders());
    while (sliders.next()) |checker| {
        attacked.bits |= (attack.ray(checker, king).bits ^ checker.toBitboard().bits);
    }
    try kingMoves(moves, gme, (gme.us().bitOr(attacked)).invert());
    // if single checker then we can capture the checker or block any of the squares between
    if (gme.checkers.isOneSquare()) {
        const target = attack.between(king, gme.checkers.toSquare().?).bitOr(gme.checkers);
        try pieceMoves(moves, gme, PieceType.Knight, target);
        try pieceMoves(moves, gme, PieceType.Bishop, target);
        try pieceMoves(moves, gme, PieceType.Rook, target);
        try pieceMoves(moves, gme, PieceType.Queen, target);
        try pawnMoves(moves, gme, target);
    }
}

/// Convienience function the code a bit cleaner for move pushing
pub fn pushPawnPromotions(moves: *MoveList, from: Square, to: Square, result: PieceType) callconv(.Inline) !void {
    try moves.push(Move.new(from, to, true, PieceType.Knight, result));
    try moves.push(Move.new(from, to, true, PieceType.Bishop, result));
    try moves.push(Move.new(from, to, true, PieceType.Rook, result));
    try moves.push(Move.new(from, to, true, PieceType.Queen, result));
}
