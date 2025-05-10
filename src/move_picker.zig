const std = @import("std");
const game = @import("game.zig");
const move = @import("move.zig");
const searcher = @import("searcher.zig");

const Game = game.Game;
const MoveList = move.MoveList;
const Move = move.Move;
const Searcher = searcher.Searcher;

const SortWinningCapture: i32 = 1_000_000;

pub fn scoreMoves(srchr: *Searcher, gme: *Game, moves: *MoveList) void {
    for (moves.range()) |mve| {
        var score: i32 = 0;
        if (mve.isPromotion()) {
            score += 1_000_000;
        }

        if (mve.isCapture())
            score += SortWinningCapture + mve.getMvvLvaScore();
        }
    }
}
