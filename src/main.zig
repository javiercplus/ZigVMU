//! ZigVMU entry point.

const std = @import("std");
const app = @import("app.zig");

pub fn main(args: std.process.Init.Minimal) !void {
    const allocator = std.heap.c_allocator;
    try app.run(allocator, args.args.vector);
}
