const std = @import("std");

pub const Engine = struct {
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) Engine {
        return Engine{ .allocator = alloc };
    }

    pub fn process(self: *Engine, data: []const u8) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Zig processed: {s}\n", .{data});
    }
};