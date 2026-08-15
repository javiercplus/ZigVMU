//! Filesystem utilities.

const std = @import("std");

/// Checks whether a path exists on the system.
pub fn fileExists(path: []const u8) bool {
    // `Dir.access` with `.cwd()` accepts relative paths; `accessAbsolute`
    // asserts and would fail on paths like "hd.qcow2".
    const io = std.Io.Threaded.global_single_threaded.io();
    _ = std.Io.Dir.access(.cwd(), io, path, .{}) catch return false;
    return true;
}

/// Checks whether a path exists and has execute permission, equivalent to
/// the `[ -x "$QEMU_APPIMAGE" ]` check of the original launcher.
pub fn fileExecutable(path: []const u8) bool {
    const io = std.Io.Threaded.global_single_threaded.io();
    _ = std.Io.Dir.access(.cwd(), io, path, .{ .execute = true }) catch return false;
    return true;
}
