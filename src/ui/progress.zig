//! Modal dialog with a progress bar to run a job in the background
//! without blocking the UI.

const std = @import("std");
const gtk = @import("../bindings/gtk.zig");
const c = gtk.c;

pub const Outcome = union(enum) {
    success: void,
    failure: anyerror,
};

pub const Work = struct {
    runFn: *const fn (*anyopaque) anyerror!void,
    ctx: *anyopaque,
};

const Ctx = struct {
    work: Work,
    outcome: Outcome = .{ .success = {} },
    dialog: gtk.Widget = null,
    bar: gtk.Widget = null,
    pulse_source: u32 = 0,
    destroyed: bool = false,
};

/// Shows a progress dialog, runs `work` in a separate thread and waits for
/// it to finish. Returns the result of the work.
pub fn run(
    parent: gtk.Widget,
    title: []const u8,
    work: Work,
) !Outcome {
    var ctx = Ctx{ .work = work };

    const dialog = c.gtk_dialog_new();
    ctx.dialog = dialog;
    c.gtk_window_set_title(dialog, gtk.toC(title));
    c.gtk_window_set_modal(dialog, 1);
    if (parent != null) c.gtk_window_set_transient_for(dialog, parent);
    c.gtk_window_set_default_size(dialog, 420, 120);
    c.gtk_window_set_position(dialog, c.GTK_WIN_POS_CENTER);

    const area = c.gtk_dialog_get_content_area(dialog);
    c.gtk_container_set_border_width(area, 12);
    const bar = c.gtk_progress_bar_new();
    ctx.bar = bar;
    c.gtk_progress_bar_set_text(bar, gtk.toC(title));
    c.gtk_progress_bar_set_show_text(bar, 1);
    c.gtk_progress_bar_set_pulse_step(bar, 0.05);
    c.gtk_container_add(area, bar);
    c.gtk_widget_show_all(dialog);
    gtk.signalConnect(@ptrCast(dialog), "destroy", onDialogDestroy, @ptrCast(&ctx));

    ctx.pulse_source = c.g_timeout_add(80, onPulse, @ptrCast(&ctx));
    defer _ = c.g_source_remove(ctx.pulse_source);

    const thread = std.Thread.spawn(.{}, workerMain, .{&ctx}) catch {
        c.gtk_widget_destroy(dialog);
        return error.ThreadSpawnFailed;
    };

    _ = c.gtk_dialog_run(dialog);

    thread.join();
    return ctx.outcome;
}

fn workerMain(ctx: *Ctx) void {
    ctx.outcome = if (ctx.work.runFn(ctx.work.ctx)) |_| .{ .success = {} } else |err| .{ .failure = err };
    _ = c.g_idle_add(onIdle, @ptrCast(ctx));
}

fn onDialogDestroy(widget: gtk.Widget, data: ?*anyopaque) callconv(.c) void {
    _ = widget;
    const ctx: *Ctx = @ptrCast(@alignCast(data.?));
    ctx.destroyed = true;
}

fn onPulse(data: ?*anyopaque) callconv(.c) c_int {
    const ctx: *Ctx = @ptrCast(@alignCast(data.?));
    if (ctx.destroyed) return 0;
    c.gtk_progress_bar_pulse(ctx.bar.?);
    return 1;
}

fn onIdle(data: ?*anyopaque) callconv(.c) c_int {
    const ctx: *Ctx = @ptrCast(@alignCast(data.?));
    if (!ctx.destroyed) c.gtk_widget_destroy(ctx.dialog.?);
    return 0;
}