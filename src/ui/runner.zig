//! QEMU launch in the background: hides the window, runs QEMU in a separate
//! thread and shows the window again with a summary when it finishes.

const std = @import("std");
const gtk = @import("../bindings/gtk.zig");
const c = gtk.c;
const config = @import("../config.zig");
const system = @import("../system/mod.zig");
const qemu = @import("../qemu/mod.zig");
const messages = @import("messages.zig");
const launch_dialog = @import("launch_dialog.zig");

const VmCtx = struct {
    allocator: std.mem.Allocator,
    window: gtk.Widget,
    argv: []const []const u8,
    term: u16 = 0,
    exit_code: u8 = 0,
};

/// Launches QEMU with the confirmed options. Hides the main window and
/// returns immediately; QEMU runs in a separate thread.
pub fn launch(
    allocator: std.mem.Allocator,
    parent: gtk.Widget,
    cfg: *config.Config,
    result: launch_dialog.Result,
) void {
    const opts = result.opts;
    const backend = result.audio_backend;

    if (!cfg.qemuAvailable(allocator, opts.arch)) {
        messages.errorDialog(
            parent,
            "Error",
            "QEMU binary not found or not executable.\n\nOpen 'Configuration' to set the AppImage path or switch to the system QEMU binaries.",
        );
        return;
    }

    const bin = cfg.qemuBinaryAlloc(allocator, opts.arch) catch {
        messages.errorDialog(parent, "Error", "Could not build the QEMU command.");
        return;
    };
    defer allocator.free(bin);

    const argv = qemu.command.build(allocator, bin, cfg.bios_path, backend, opts) catch {
        messages.errorDialog(parent, "Error", "Could not build the QEMU command.");
        return;
    };

    if (cfg.mode == .appimage and !system.fs.fileExecutable(bin)) {
        qemu.command.freeArgv(allocator, argv);
        messages.errorDialog(
            parent,
            "Error",
            "QEMU AppImage is not executable. Make sure it has execute permissions (chmod +x).",
        );
        return;
    }

    const ctx = allocator.create(VmCtx) catch {
        qemu.command.freeArgv(allocator, argv);
        messages.errorDialog(parent, "Error", "Not enough memory to launch QEMU.");
        return;
    };
    ctx.* = .{
        .allocator = allocator,
        .window = parent,
        .argv = argv,
    };

    if (cfg.mode == .appimage and !system.process.hasFuse(allocator)) {
        messages.warning(
            parent,
            "FUSE",
            "FUSE is not available on your system.\n\nTo run the QEMU AppImage you need FUSE support.\nInstall fuse or switch to the system QEMU binaries (Configuration).",
        );
    }

    c.gtk_widget_hide(parent);
    const thread = std.Thread.spawn(.{}, vmMain, .{ctx}) catch {
        allocator.destroy(ctx);
        qemu.command.freeArgv(allocator, argv);
        c.gtk_widget_show_all(parent);
        messages.errorDialog(parent, "Error", "Could not create thread to launch QEMU.");
        return;
    };
    thread.detach();
}

/// Worker thread: runs QEMU and notifies the main thread when it finishes.
fn vmMain(ctx: *VmCtx) void {
    var io_host = system.process.ioHost(ctx.allocator);
    defer io_host.deinit();
    const io = io_host.io();

    var child = std.process.spawn(io, .{
        .argv = ctx.argv,
    }) catch |err| {
        ctx.term = @intCast(@intFromError(err));
        _ = c.g_idle_add(onVmDone, ctx);
        return;
    };
    const term = child.wait(io) catch |err| {
        ctx.term = @intCast(@intFromError(err));
        _ = c.g_idle_add(onVmDone, ctx);
        return;
    };
    ctx.exit_code = system.process.exitCode(term);
    _ = c.g_idle_add(onVmDone, ctx);
}

/// Runs on the GTK main thread when QEMU has finished.
fn onVmDone(data: ?*anyopaque) callconv(.c) c_int {
    const ctx: *VmCtx = @ptrCast(@alignCast(data.?));
    defer {
        qemu.command.freeArgv(ctx.allocator, ctx.argv);
        ctx.allocator.destroy(ctx);
    }

    if (ctx.term != 0) {
        messages.errorDialog(ctx.window, "QEMU", "Failed to launch QEMU.");
    } else if (ctx.exit_code != 0) {
        const owned = std.fmt.allocPrint(
            ctx.allocator,
            "QEMU exited with an error (code {d}).\n\nCheck the terminal output for details.",
            .{ctx.exit_code},
        ) catch null;
        defer if (owned) |m| ctx.allocator.free(m);
        messages.errorDialog(ctx.window, "QEMU", owned orelse "QEMU exited with an error.");
    } else {
        messages.info(ctx.window, "QEMU", "QEMU exited normally.");
    }

    c.gtk_widget_show_all(ctx.window);
    return 0;
}
