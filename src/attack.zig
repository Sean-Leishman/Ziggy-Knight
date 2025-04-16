const bitboard = @import("bitboard.zig");
const color = @import("color.zig");
const square = @import("square.zig");
const setup = @import("setup.zig");
const piece = @import("piece.zig");

const Bitboard = bitboard.Bitboard;
const Color = color.Color;
const Square = square.Square;
const Piece = piece.Piece;

pub fn pawnFrom(clr: Color, sq: Square) Bitboard {
    return switch (clr) {
        .White => setup.white_pawn_attacks[sq.index()],
        .Black => setup.black_pawn_attacks[sq.index()],
    };
}

pub fn knightFrom(sq: Square) Bitboard {
    return setup.knight_attacks[sq.index()];
}

pub fn bishopFrom(sq: Square, occupied: Bitboard) Bitboard {
    const m = setup.bishop_magic[sq.index()];
    const i = ((m.factor *% (occupied.bits & m.mask)) >> (64 - setup.bishop_shift)) + m.offset;
    return setup.rook_bishop_attacks[i];
}

pub fn rookFrom(sq: Square, occupied: Bitboard) Bitboard {
    const m = setup.rook_magic[sq.index()];
    const i = ((m.factor *% (occupied.bits & m.mask)) >> (64 - setup.rook_shift)) + m.offset;
    return setup.rook_bishop_attacks[i];
}

pub fn queenFrom(sq: Square, occupied: Bitboard) Bitboard {
    return bishopFrom(sq, occupied).xor(rookFrom(sq, occupied));
}

pub fn kingFrom(sq: Square) Bitboard {
    return setup.king_attacks[sq.index()];
}

pub fn pieceFrom(sq: Square, pce: Piece, occupied: Bitboard) Bitboard {
    return switch (pce.piece_type) {
        .Pawn => pawnFrom(pce.color, sq),
        .Knight => knightFrom(sq),
        .Bishop => bishopFrom(sq, occupied),
        .Rook => rookFrom(sq, occupied),
        .Queen => queenFrom(sq, occupied),
        .King => kingFrom(sq),
        .Other => unreachable,
        .Empty => unreachable,
    };
}

pub fn ray(from: Square, to: Square) Bitboard {
    return setup.rook_bishop_rays[from.index()][to.index()];
}

pub fn aligned(a: Square, b: Square, c: Square) bool {
    return ray(a, b).contains(c);
}

pub fn between(a: Square, b: Square) Bitboard {
    const bits = ray(a, b).bits & ((bitboard.all.bits << a.index()) ^ (bitboard.all.bits << b.index()));
    return Bitboard{ .bits = bits & (bits -% 1) };
}
