const std = @import("std");
const debug = std.debug;
const heap = std.heap;

const hyperscan = @import("hyperscan.zig");

const logger = std.log.scoped(.main);

pub fn main() anyerror!void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) {
        debug.panic("leaks detected", .{});
    };

    var arena = heap.ArenaAllocator.init(&gpa.allocator);
    defer arena.deinit();
    var allocator = &arena.allocator;

    //

    var args_iter = std.process.args();
    if (!args_iter.skip()) debug.panic("expected self arg", .{});

    const pattern = try args_iter.next(allocator) orelse debug.panic("expected input arg", .{});

    var db: hyperscan.Database = undefined;
    {
        var compile_arena = heap.ArenaAllocator.init(&gpa.allocator);
        defer compile_arena.deinit();

        var compile_diags: hyperscan.CompileDiagnostics = undefined;
        db.compile(
            &compile_arena.allocator,
            pattern,
            hyperscan.FlagDotall,
            hyperscan.ModeBlock,
            &compile_diags,
        ) catch |err| {
            logger.err("pattern compile failed: {s}", .{compile_diags.message});
            return err;
        };
    }
    defer db.deinit();

    //

    var scratch = try hyperscan.Scratch.init(&db);
    defer scratch.deinit();
}
