const std = @import("std");
const game = @import("game.zig");
const move_generator = @import("move_generator.zig");
const move = @import("move.zig");
const piece = @import("piece.zig");
const square = @import("square.zig");
const evaluate = @import("evaluate.zig");
const color = @import("color.zig");
const setup = @import("setup.zig");
const tt = @import("transposition_table.zig");

const Color = color.Color;
const Game = game.Game;
const Move = move.Move;
const PieceType = piece.PieceType;
const Square = square.Square;

const INF = 1_000_000_000;

const indent_levels = [_][]const u8{
    "",
    "  ",
    "    ",
    "      ",
    "        ",
    "          ",
    "            ",
    "              ",
    "                ",
    "                  ",
};

pub const SearcherMetrics = struct {
    tt_hits: u32,
    tt_hits_at_depth: u32,
    depth: u32,
    time_ms: i64,
};

pub const Searcher = struct {
    nodes: u32 = 0,
    best_move: Move = undefined,

    root_depth: u32 = 0,
    metrics: SearcherMetrics = .{ .tt_hits = 0, .tt_hits_at_depth = 0, .depth = 0, .time_ms = 0 },
    ttable: tt.TranspositionTable = tt.TranspositionTable.new(),

    pub fn toString(self: *Searcher) void {
        std.debug.print("Nodes: {}, Best Move: {}, TT Hits: {}, TT Hits at Depth: {}, Depth: {}, TimeMs: {}\n", .{
            self.nodes,
            self.best_move,
            self.metrics.tt_hits,
            self.metrics.tt_hits_at_depth,
            self.metrics.depth,
            self.metrics.time_ms,
        });
    }

    pub fn search(self: *Searcher, gme: *Game, depth: u32) i32 {
        self.root_depth = depth;
        self.nodes = 0;

        const clr = gme.ourColor();
        std.debug.print("Starting search for color {} at depth {}\n", .{ clr, depth });

        self.metrics.time_ms = std.time.milliTimestamp();
        const best_value = self.alpha_beta(gme, clr, depth, @as(i32, -INF), @as(i32, INF));
        self.metrics.time_ms = std.time.milliTimestamp() - self.metrics.time_ms;
        return best_value;
    }

    pub fn alpha_beta(self: *Searcher, gme: *Game, clr: Color, depth: u32, alpha: i32, beta: i32) i32 {
        self.nodes += 1;
        const opp_clr = clr.invert();

        if (depth == 0 or gme.isGameOver()) {
            const value = evaluate.evaluate(gme, clr);
            if (gme.isCheckmate()) {
                // Prefer faster checkmates
                return -INF + @as(i32, @intCast(self.root_depth - depth));
            } else if (gme.isStalemate()) {
                return 0;
            }

            return value;
        }

        const tt_entry = self.ttable.get(gme.hash);
        if (tt_entry) |entry| {
            self.metrics.tt_hits += 1;
            if (entry.depth >= depth) {
                self.metrics.tt_hits_at_depth += 1;
                return entry.eval;
            }
        }

        var alpha_local = alpha;
        var best_value: i32 = -INF;
        var best_move: ?Move = null;

        var legal_moves = move_generator.legalMoves(gme.*) catch return -INF;

        for (legal_moves.range()) |mve| {
            const game_state = gme.playMove(mve);
            const opponent_score = self.alpha_beta(gme, opp_clr, depth - 1, -beta, -alpha_local);
            gme.undoMove(mve, game_state) catch return -INF;
            const our_score = -opponent_score;

            if (our_score > best_value) {
                best_value = our_score;
                best_move = mve;

                if (depth == self.root_depth) {
                    self.best_move = mve;
                }
            }

            if (our_score > alpha_local) {
                alpha_local = our_score;
            }

            if (alpha_local >= beta) {
                break;
            }
        }

        self.ttable.set(gme.hash, best_value, self.best_move, depth);

        return best_value;
    }
};

test "searcher basic functionality" {
    setup.init();

    var gme = game.standard();
    var searcher = Searcher{};

    const depth = 3;
    const score = searcher.search(&gme, depth);
    std.debug.print("Search completed. Best Move: {}, Score: {}, Nodes: {}\n", .{ searcher.best_move, score, searcher.nodes });
    std.debug.assert(searcher.nodes > 0);
    std.debug.assert(searcher.best_move.mover != PieceType.Empty);
}

test "searcher checkmate detection" {
    setup.init();

    var gme = game.standard();
    // Fool's mate position
    _ = gme.playMove(move.Move{
        .from = try Square.fromString("f2"),
        .to = try Square.fromString("f3"),
        .mover = PieceType.Pawn,
        .result = PieceType.Empty,
        .special = false,
    });
    _ = gme.playMove(Move{
        .from = try Square.fromString("e7"),
        .to = try Square.fromString("e5"),
        .mover = PieceType.Pawn,
        .result = PieceType.Empty,
        .special = false,
    });
    _ = gme.playMove(Move{
        .from = try Square.fromString("g2"),
        .to = try Square.fromString("g4"),
        .mover = PieceType.Pawn,
        .result = PieceType.Empty,
        .special = false,
    });
    std.debug.print("Current Board FEN: {s} Color: {c}, Board Hash: {}\n", .{ gme.toFen() catch "", gme.color.toChar(), gme.hash });

    std.debug.print("Fool's mate position set up. Board FEN: {s} Board Hash: {}\n", .{ gme.toFen() catch "", gme.hash });
    std.debug.print("All legal moves:\n", .{});
    var legal_moves = move_generator.legalMoves(gme) catch {
        std.debug.print("Error generating moves\n", .{});
        return;
    };
    for (legal_moves.range()) |mve| {
        std.debug.print("  Move: {}\n", .{mve});
    }

    var searcher = Searcher{};
    const depth = 2;
    const score = searcher.search(&gme, depth);
    std.debug.print("Search completed. Best Move: {}, Score: {}, Nodes: {}\n", .{ searcher.best_move, score, searcher.nodes });

    std.debug.print("Checkmate by move: {}\n", .{searcher.best_move});
    try std.testing.expectEqual(searcher.best_move.mover, PieceType.Queen);

    _ = gme.playMove(searcher.best_move);
    try std.testing.expect(gme.isCheckmate());
}
