//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
//!

const std = @import("std");
const zap = @import("zap");
const setup = @import("setup.zig");
const game = @import("game.zig");
const move = @import("move.zig");
const move_generator = @import("move_generator.zig");
const search = @import("search.zig");

const Game = game.Game;
const Move = move.Move;
const MoveRequest = move.MoveRequest;

var gm: *game.Game = undefined;
var searcher: *search.Searcher = undefined;

fn on_request(r: zap.Request) anyerror!void {
    // /move make a move on the board
    if (r.path) |the_path| {
        if (std.mem.eql(u8, the_path, "/move")) {
            std.debug.print("Request path: {?s}\n", .{the_path});
            std.debug.print("Request method: {?s}\n", .{r.method});

            // Parse the request body
            if (r.body) |body| {
                const allocator = std.heap.page_allocator;
                const json = try std.json.parseFromSlice(MoveRequest, allocator, body, .{ .allocate = .alloc_always });
                defer json.deinit();

                std.debug.print("Parsed JSON: {}\n", .{json.value});

                var local_gm = game.empty();
                try local_gm.setFen(json.value.fen);

                const mv = Move.fromRequest(json.value) catch |err| {
                    std.debug.print("Error parsing move request: {}\n", .{err});
                    return err;
                };
                std.debug.print("Parsed move: {}\n\t{!s}\n", .{ mv, local_gm.toFen() });

                local_gm.playCheckMove(mv) catch |err| {
                    std.debug.print("Error playing move: {}\n", .{err});
                    return err;
                };

                const new_fen = local_gm.toFen() catch |err| {
                    std.debug.print("Error converting to FEN: {}\n", .{err});
                    return err;
                };
                std.debug.print("Move played: {} {s}\n", .{ mv, new_fen });

                const score = searcher.search(&local_gm, 5);
                const best_move = searcher.best_move;

                local_gm.playMove(best_move);
                const computer_fen = local_gm.toFen() catch |err| {
                    std.debug.print("Error converting to FEN: {}\n", .{err});
                    return err;
                };
                std.debug.print("Computer move played: {} => {} {s}\n", .{ best_move, score, computer_fen });

                var jsonbuf: [1024]u8 = undefined;
                const res_json = try zap.util.stringifyBuf(&jsonbuf, .{
                    .fen = new_fen,
                    .in_check = local_gm.isCheck(),
                    .in_checkmate = local_gm.isCheckmate(),
                    .in_stalemate = local_gm.isStalemate(),
                    .computer_score = score,
                    .computer_move = best_move,
                    .computer_fen = computer_fen,
                }, .{});
                try r.sendJson(res_json);
            }
        }
    }
}

pub fn main() !void {
    setup.init();

    const allocator = std.heap.page_allocator;
    gm = try allocator.create(Game);
    gm.* = game.standard();
    searcher = try allocator.create(search.Searcher);

    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = on_request,
        .log = true,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:3000\n", .{});
    std.debug.print("Board:\n{!s}", .{gm.board.debug()});
    std.debug.print("Board FEN: {!s}\n", .{gm.toFen()});

    var timer = try std.time.Timer.start();
    _ = try move_generator.legalMoves(gm.*);
    std.debug.print("Legal moves generated in time {}\n", .{@as(f64, @floatFromInt(timer.lap())) / 1e9});

    // start worker threads
    zap.start(.{
        .threads = 2,
        .workers = 2,
    });

    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // Don't forget to flush!
}
