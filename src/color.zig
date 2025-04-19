pub const Color = enum(u1) {
    White = 0,
    Black = 1,

    pub fn wlbr(self: Color, comptime T: type, left: T, right: T) callconv(.Inline) T {
        return switch (self) {
            .White => left,
            .Black => right,
        };
    }

    pub fn invert(self: Color) Color {
        return switch (self) {
            .White => .Black,
            .Black => .White,
        };
    }

    pub fn toChar(self: Color) u8 {
        return switch (self) {
            .White => 'w',
            .Black => 'b',
        };
    }

    pub fn clone(self: Color) Color {
        return self;
    }
};

pub fn fromChar(c: u8) ?Color {
    return switch (c) {
        'w', 'W' => Color.White,
        'b', 'B' => Color.Black,
        else => null,
    };
}
