//! Execution of external processes (qemu, qemu-img, audio utilities).

const std = @import("std");

const Threaded = std.Io.Threaded;

/// The real process environment. `std.Io.Threaded` does not capture the
/// environment by default (it is empty), and child processes (qemu, qemu-img,
/// sh...) need it to find binaries on the PATH and for DISPLAY/HOME.
fn realEnviron() std.process.Environ {
    const c_environ = std.c.environ;
    var count: usize = 0;
    while (c_environ[count] != null) : (count += 1) {}
    const slice: [:null]const ?[*:0]const u8 = c_environ[0..count :null];
    return .{ .block = .{ .slice = slice } };
}

pub const RunResult = struct {
    term: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,
};

pub fn ioHost(allocator: std.mem.Allocator) Threaded {
    return Threaded.init(allocator, .{
        .async_limit = .nothing,
        .concurrent_limit = .nothing,
        .environ = realEnviron(),
    });
}

/// Runs a command waiting for it to finish and captures its output.
/// Each call creates its own I/O instance, so it is safe from any thread.
pub fn runCollect(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    max_output_bytes: usize,
) !RunResult {
    var io_host = ioHost(allocator);
    defer io_host.deinit();
    const io = io_host.io();

    const res = try std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(max_output_bytes),
        .stderr_limit = .limited(max_output_bytes),
    });
    return .{ .term = res.term, .stdout = res.stdout, .stderr = res.stderr };
}

/// Runs a command without capturing output and returns its exit code.
/// Safe from any thread.
pub fn spawnAndWait(allocator: std.mem.Allocator, argv: []const []const u8) !u8 {
    var io_host = ioHost(allocator);
    defer io_host.deinit();
    const io = io_host.io();

    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdout = .inherit,
        .stderr = .inherit,
        .stdin = .inherit,
    });
    const term = try child.wait(io);
    return exitCode(term);
}

/// Normalizes an exit state into an integer code.
pub fn exitCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        .signal => |sig| 128 + @as(u8, @intCast(@intFromEnum(sig))),
        .stopped, .unknown => 1,
    };
}

/// Checks whether an executable exists on the PATH.
pub fn existsOnPath(allocator: std.mem.Allocator, name: []const u8) bool {
    const cmd = std.fmt.allocPrint(allocator, "command -v {s} >/dev/null 2>&1", .{name}) catch return false;
    defer allocator.free(cmd);

    var io_host = ioHost(allocator);
    defer io_host.deinit();
    const io = io_host.io();
    var child = std.process.spawn(io, .{
        .argv = &.{ "sh", "-c", cmd },
        .stdout = .ignore,
        .stderr = .ignore,
        .stdin = .ignore,
    }) catch return false;
    const term = child.wait(io) catch return false;
    return exitCode(term) == 0;
}

/// Checks whether FUSE is available on the system.
pub fn hasFuse(allocator: std.mem.Allocator) bool {
    return existsOnPath(allocator, "fusermount") or existsOnPath(allocator, "mount.fuse");
}