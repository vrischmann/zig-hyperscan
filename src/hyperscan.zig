const std = @import("std");
const mem = std.mem;

const c = @cImport({
    @cInclude("hs/hs.h");
});

pub const FlagCaseless = c.HS_FLAG_CASELESS;
pub const FlagDotall = c.HS_FLAG_DOTALL;

pub const ModeBlock = c.HS_MODE_BLOCK;

pub const CompileDiagnostics = struct {
    message: []const u8,
    expression: usize,
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
            else => unreachable,
        }
    }

    pub fn deinit(self: *Self) void {
        _ = c.hs_free_scratch(self.scratch);
    }
};
