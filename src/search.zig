const std = @import("std");
const game = @import("game.zig");
const move_generator = @import("move_generator.zig");
const move = @import("move.zig");
const evaluate = @import("evaluate.zig");
const color = @import("color.zig");

const Color = color.Color;
const Game = game.Game;
const Move = move.Move;

const INF = 1_000_000_000;

pub const Searcher = struct {
    nodes: u32 = 0,
    best_move: Move = undefined,

    transposition_table: std.AutoHashMap(u64, i32) = undefined,
    root_depth: u32 = 0,

    pub fn search(self: *Searcher, gme: *Game, depth: u32) i32 {
        self.root_depth = depth;
        self.nodes = 0;

        const clr = gme.ourColor();
        const best_value = self.alpha_beta(gme, clr, depth, @as(i32, -INF), @as(i32, INF));
        return best_value;
    }

    pub fn alpha_beta(self: *Searcher, gme: *Game, clr: Color, depth: u32, alpha: i32, beta: i32) i32 {
        self.nodes += 1;
        const opp_clr = clr.invert();

        if (depth == 0 or gme.isGameOver()) {
            const value = evaluate.evaluate(gme, clr);
            return value;
        }

        var alpha_local = @as(i32, alpha);
        var best_value = @as(i32, -INF);

        var legal_moves = move_generator.legalMoves(gme.*) catch return -INF;
        for (legal_moves.range()) |mve| {
            gme.playMove(mve);
            const value: i32 = -self.alpha_beta(gme, opp_clr, depth - 1, -beta, -alpha_local);

            if (value > best_value) {
                best_value = value;

                if (depth == self.root_depth) {
                    // Store the best move for the root node
                    self.best_move = mve; // Store the best mve
                }
            }
            gme.undoMove(mve);
            if (value > alpha_local) {
                alpha_local = value;
            }
            if (alpha_local >= beta) {
                break;
            }
        }
        return best_value;
    }
};
