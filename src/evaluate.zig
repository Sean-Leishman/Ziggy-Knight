const game = @import("game.zig");
const color = @import("color.zig");
const piece = @import("piece.zig");
const bitboard = @import("bitboard.zig");

const std = @import("std");

const Bitboard = bitboard.Bitboard;
const Color = color.Color;
const Game = game.Game;
const Piece = piece.Piece;
const PieceType = piece.PieceType;

pub const CHECKMATE = 1000;
pub const STALEMATE = 0;
pub const DRAW = 0;
pub const CHECK = 50;

// https://github.com/SnowballSH/Avalanche/blob/master/src/engine/hce.zig
pub const Material: [8][2]i32 = .{
    .{ 82, 94 }, // Pawn
    .{ 337, 281 }, // Knight
    .{ 365, 297 }, // Bishop
    .{ 477, 512 }, // Rook
    .{ 1025, 936 }, // Queen
    .{ 0, 0 }, // King
    .{ 0, 0 }, // King
    .{ 0, 0 }, // King
};

pub const DistanceScore: [64]i32 = .{
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 1, 2, 3, 4, 5, 6, 7,
    1, 2, 3, 4, 5, 6, 7, 8,
    1, 2, 3, 4, 5, 6, 7, 8,
    0, 1, 2, 3, 4, 5, 6, 7,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
};

pub fn distanceEval(bit: Bitboard, count: i32) i32 {
    var score: i32 = 0;

    var lsb: i32 = bit.lsb();
    var idx: i32 = 1;
    while (idx < count) {
        lsb += bit.shiftRight(@intCast(lsb)).lsb();
        score += DistanceScore[@intCast(lsb)];

        idx += 1;
        lsb += 1;
    }

    return score;
}

pub fn evaluate(gme: *Game, clr: Color) i32 {
    var score: i32 = 0;

    inline for (@typeInfo(PieceType).@"enum".fields) |pieceTypeField| {
        const pieceType: PieceType = @enumFromInt(pieceTypeField.value);
        if (pieceType == PieceType.Empty or pieceType == PieceType.Other) {
            continue;
        }

        const pieceBitboard: Bitboard = gme.board.ofPiece(Piece{
            .piece_type = pieceType,
            .color = clr,
        });
        const pieceCount: i32 = pieceBitboard.countBits();
        const pieceMaterial: i32 = Material[@intFromEnum(pieceType)][if (clr == Color.White) 0 else 1] * pieceCount;

        const other_clr = clr.invert();
        const other_pieceBitboard: Bitboard = gme.board.ofPiece(Piece{
            .piece_type = pieceType,
            .color = other_clr,
        });
        const other_pieceCount: i32 = other_pieceBitboard.countBits();
        const other_pieceMaterial: i32 = Material[@intFromEnum(pieceType)][if (other_clr == Color.White) 0 else 1] * other_pieceCount;

        const finalPieceScore: i32 = pieceMaterial - other_pieceMaterial;
        const distanceScore: i32 = distanceEval(pieceBitboard, pieceCount);

        score += finalPieceScore + distanceScore;
    }

    return score;
}
