//! GTK3 bindings through the shim in `c/gtk_shim.h`.
//!
//! This is the only module in the project that touches C directly.
//! The rest of the modules depend on the functions and constants exposed here.

const std = @import("std");

pub const c = @cImport({
    @cInclude("gtk_shim.h");
});

pub const Widget = ?*c.GtkWidget;

/// Connects a GTK signal to a Zig function with C calling convention.
pub fn signalConnect(
    instance: ?*anyopaque,
    comptime signal: [*:0]const u8,
    callback: anytype,
    data: ?*anyopaque,
) void {
    _ = c.g_signal_connect_data(
        instance,
        signal,
        @ptrCast(&callback),
        data,
        null,
        c.G_CONNECT_DEFAULT,
    );
}

/// Per-thread buffer for `toC`. GTK copies the strings synchronously during
/// the call, so the buffer only needs to live until the GTK function returns.
threadlocal var toC_buf: [32768]u8 = undefined;

/// Converts a Zig slice to a NUL-terminated C pointer using a per-thread
/// buffer. GTK copies the string synchronously during the call, so the
/// buffer only needs to live for the duration of the call.
pub fn toC(s: []const u8) [*c]const u8 {
    const z = std.fmt.bufPrintZ(&toC_buf, "{s}", .{s}) catch return @ptrCast("");
    return @ptrCast(z.ptr);
}

/// Converts a NUL-terminated C pointer to a Zig slice.
pub fn spanC(ptr: [*c]const u8) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
}

/// Takes ownership of a string returned by GTK (C memory), copies it into a
/// Zig allocator and frees the original with `g_free`.
pub fn ownCString(allocator: std.mem.Allocator, ptr: [*c]u8) ![]u8 {
    if (ptr == null) return error.NullString;
    defer c.g_free(ptr);
    return allocator.dupe(u8, spanC(ptr));
}