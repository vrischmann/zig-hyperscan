const std = @import("std");
const debug = std.debug;
const heap = std.heap;
const os = std.os;

const hyperscan = @import("hyperscan.zig");

const logger = std.log.scoped(.main);

pub const log_level: std.log.Level = .debug;

var matches: usize = 0;

fn matchEventHandler(id: c_uint, from: usize, to: usize, flags: c_uint, context: ?*anyopaque) callconv(.C) c_int {
    _ = id;
    _ = from;
    _ = to;
    _ = flags;
    _ = context;

    matches += 1;

    // const scan_context = @ptrCast(*hyperscan.ScanContext, @alignCast(8, context.?));

    // logger.debug("Match for pattern from {d} to {d}: {s}", .{
    //     from,
    //     to,
    //     scan_context.input_data[from..to],
    // });

    return 0;
}

pub fn main() anyerror!void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit()) {
        debug.panic("leaks detected", .{});
    };

    var arena = heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    //

    var hs_arena = heap.ArenaAllocator.init(gpa.allocator());
    defer hs_arena.deinit();

    // try hyperscan.setAllocator(&hs_arena.allocator);

    //

    var args_iter = std.process.args();
    if (!args_iter.skip()) debug.panic("expected self arg", .{});

    const pattern = args_iter.next() orelse debug.panic("expected 'pattern' arg", .{});
    const input = args_iter.next() orelse debug.panic("expected 'input' arg", .{});

    const input_file = try std.fs.cwd().openFile(input, .{});

    // const input_data = try input_file.reader().readAllAlloc(allocator, std.math.maxInt(usize));

    const input_data = try os.mmap(
        null,
        (try input_file.stat()).size,
        os.PROT.READ,
        os.MAP.SHARED,
        input_file.handle,
        0,
    );

    var db: hyperscan.Database = undefined;
    {
        var compile_arena = heap.ArenaAllocator.init(gpa.allocator());
        defer compile_arena.deinit();

        var compile_diags: hyperscan.CompileDiagnostics = undefined;
        db.compile(
            compile_arena.allocator(),
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

    //

    var scan_context = hyperscan.ScanContext{
        .input_data = input_data,
        .pattern = pattern,
    };
    try db.scan(input_data, 0, &scratch, &scan_context, matchEventHandler);

    //

    logger.info("matches: {d}", .{matches});
}
