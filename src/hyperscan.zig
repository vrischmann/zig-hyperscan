const std = @import("std");
const mem = std.mem;

const c = @cImport({
    @cInclude("hs/hs.h");
});

pub const FlagCaseless = c.HS_FLAG_CASELESS;
pub const FlagDotall = c.HS_FLAG_DOTALL;
pub const FlagStartOfMatchLeftmost = c.HS_FLAG_SOM_LEFTMOST;

pub const ModeBlock = c.HS_MODE_BLOCK;
pub const ModeStartOfMatchHorizonLarge = c.HS_MODE_SOM_HORIZON_LARGE;

pub const CompileDiagnostics = struct {
    message: []const u8,
    expression: usize,
};

pub const MatchEventHandler = fn (id: c_uint, from: usize, to: usize, flags: c_uint, context: ?*c_void) callconv(.C) c_int;

pub const ScanContext = struct {
    pattern: []const u8,
    input_data: []const u8,
};

pub const Database = struct {
    const Self = @This();

    db: *c.hs_database,

    pub fn compile(self: *Self, allocator: *mem.Allocator, pattern: []const u8, flags: c_uint, mode: c_uint, diagnostics: ?*CompileDiagnostics) !void {
        var dummy_diags: CompileDiagnostics = undefined;
        var diags = diagnostics orelse &dummy_diags;

        // Hyperscan takes a nul-terminated string.
        const nul_terminated_pattern = try allocator.dupeZ(u8, pattern);
        defer allocator.free(nul_terminated_pattern);

        var compile_err: *c.hs_compile_error_t = undefined;
        const hs_err = c.hs_compile(
            nul_terminated_pattern,
            flags,
            mode,
            null,
            @ptrCast([*c]?*c.hs_database, &self.db),
            @ptrCast([*c][*c]c.hs_compile_error_t, &compile_err),
        );
        if (hs_err != c.HS_SUCCESS) {
            diags.message = try allocator.dupe(u8, mem.spanZ(compile_err.message));
            return error.HyperscanCompilerError;
        }
    }

    pub fn deinit(self: *Self) void {
        _ = c.hs_free_database(self.db);
    }

    pub fn scan(self: *Self, input: []const u8, flags: c_uint, scratch: *Scratch, scan_context: *ScanContext, event_handler: MatchEventHandler) !void {
        const hs_err = c.hs_scan(
            self.db,
            @ptrCast([*c]const u8, input),
            @intCast(c_uint, input.len),
            flags,
            scratch.scratch,
            event_handler,
            @ptrCast(*c_void, scan_context),
        );
        switch (hs_err) {
            c.HS_SUCCESS => return,
            c.HS_SCAN_TERMINATED => return error.HyperscanScanTerminated,
            else => std.debug.panic("unexpected error {d}\n", .{hs_err}),
        }
    }
};

pub const Scratch = struct {
    const Self = @This();

    scratch: ?*c.hs_scratch_t,

    pub fn init(database: *Database) !Self {
        var self: Self = undefined;
        self.scratch = null;

        const hs_err = c.hs_alloc_scratch(
            database.db,
            @ptrCast([*c]?*c.hs_scratch_t, &self.scratch),
        );
        switch (hs_err) {
            c.HS_SUCCESS => return self,
            c.HS_NOMEM => return error.OutOfMemory,
            c.HS_INVALID => return error.HyperscanInvalidParameter,
            else => std.debug.panic("unexpected error {d}\n", .{hs_err}),
        }
    }

    pub fn deinit(self: *Self) void {
        _ = c.hs_free_scratch(self.scratch);
    }
};

var hs_allocator: *mem.Allocator = undefined;

fn hsAlloc(len: usize) callconv(.C) ?*c_void {
    const data = hs_allocator.alloc(u8, len) catch return null;
    return @ptrCast(*c_void, data.ptr);
}

fn hsFree(ptr: ?*c_void) callconv(.C) void {
    if (ptr) |p| {
        const data = @ptrCast([*]u8, @alignCast(8, p))[0..];
        @breakpoint();
        hs_allocator.free(data);
    }
}

pub fn setAllocator(allocator: *mem.Allocator) !void {
    hs_allocator = allocator;

    const hs_err = c.hs_set_allocator(
        hsAlloc,
        hsFree,
    );
    switch (hs_err) {
        c.HS_SUCCESS => return,
        else => std.debug.panic("unexpected error {d}\n", .{hs_err}),
    }
}
