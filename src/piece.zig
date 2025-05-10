const color = @import("color.zig");
const Color = color.Color;

pub const PieceType = enum(u3) {
    Pawn,
    Rook,
    Knight,
    Bishop,
    Queen,
    King,
    Empty,
    Other,

    pub fn fromChar(c: u8) PieceType {
        return switch (c) {
            'P', 'p' => PieceType.Pawn,
            'R', 'r' => PieceType.Rook,
            'N', 'n' => PieceType.Knight,
            'B', 'b' => PieceType.Bishop,
            'Q', 'q' => PieceType.Queen,
            'K', 'k' => PieceType.King,
            '%' => PieceType.Empty,
            '#' => PieceType.Other,
            else => unreachable,
        };
    }

    pub fn toChar(self: PieceType) u8 {
        return switch (self) {
            PieceType.Pawn => 'P',
            PieceType.Rook => 'R',
            PieceType.Knight => 'N',
            PieceType.Bishop => 'B',
            PieceType.Queen => 'Q',
            PieceType.King => 'K',
            PieceType.Empty => '%',
            PieceType.Other => '#',
        };
    }

    pub fn victimScore(self: PieceType) i32 {
        return switch (self) {
            PieceType.Pawn => 1,
            PieceType.Rook => 5,
            PieceType.Knight => 3,
            PieceType.Bishop => 3,
            PieceType.Queen => 9,
            PieceType.King => 0,
            PieceType.Empty => 0,
            PieceType.Other => 0,
        };
    }
};

pub const Piece = packed struct {
    color: Color,
    piece_type: PieceType,

    pub fn index(self: Piece) u8 {
        const piece_index: u8 = switch (self.piece_type) {
            PieceType.Pawn => 0,
            PieceType.Rook => 1,
            PieceType.Knight => 2,
            PieceType.Bishop => 3,
            PieceType.Queen => 4,
            PieceType.King => 5,
            PieceType.Empty => unreachable,
            PieceType.Other => unreachable,
        };
        const color_index: u8 = if (self.color == Color.White) 0 else 1;

        return piece_index + color_index * 6;
    }

    pub fn isEmpty(self: Piece) bool {
        return self.piece_type == PieceType.Empty;
    }

    pub fn fromChar(c: u8) !Piece {
        const piece_type = PieceType.fromChar(c);
        const clr = if (c >= 'a') Color.Black else Color.White;
        return Piece{ .color = clr, .piece_type = piece_type };
    }

    pub fn toChar(self: Piece) u8 {
        const offset: u8 = if (self.color == Color.Black) 32 else 0;
        return switch (self.piece_type) {
            PieceType.Pawn => 'P' + offset,
            PieceType.Rook => 'R' + offset,
            PieceType.Knight => 'N' + offset,
            PieceType.Bishop => 'B' + offset,
            PieceType.Queen => 'Q' + offset,
            PieceType.King => 'K' + offset,
            PieceType.Empty => '%',
            PieceType.Other => '#',
        };
    }

    pub fn victimScore(self: Piece) i32 {
        return switch (self.piece_type) {
            PieceType.Pawn => 1,
            PieceType.Rook => 5,
            PieceType.Knight => 3,
            PieceType.Bishop => 3,
            PieceType.Queen => 9,
            PieceType.King => 0,
            PieceType.Empty => 0,
            PieceType.Other => 0,
        };
    }
};
