//! Main launcher window with the available actions.

const std = @import("std");
const gtk = @import("../bindings/gtk.zig");
const c = gtk.c;
const config = @import("../config.zig");
const messages = @import("messages.zig");
const disk_dialog = @import("disk_dialog.zig");
const launch_dialog = @import("launch_dialog.zig");
const settings_dialog = @import("settings_dialog.zig");
const runner = @import("runner.zig");

const Ctx = struct {
    allocator: std.mem.Allocator,
    cfg: *config.Config,
    window: gtk.Widget,
};

/// Builds the main window.
pub fn build(app: ?*c.GtkApplication, allocator: std.mem.Allocator, cfg: *config.Config) gtk.Widget {
    const window = c.gtk_application_window_new(app);
    c.gtk_window_set_title(window, gtk.toC("ZigVMU"));
    c.gtk_window_set_default_size(window, 420, 350);
    c.gtk_window_set_position(window, c.GTK_WIN_POS_CENTER);

    const vbox = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 14);
    c.gtk_container_set_border_width(vbox, 24);

    const topbar = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 0);
    c.gtk_widget_set_hexpand(topbar, 1);
    c.gtk_widget_set_halign(topbar, c.GTK_ALIGN_FILL);
    const about_btn = c.gtk_button_new_with_label("?");
    c.gtk_widget_set_size_request(about_btn, 28, 28);
    c.gtk_box_pack_end(topbar, about_btn, 0, 0, 0);
    c.gtk_box_pack_start(vbox, topbar, 0, 0, 0);

    const title = c.gtk_label_new("");
    c.gtk_label_set_markup(title, "<b><big>ZigVMU</big></b>");
    c.gtk_widget_set_halign(title, c.GTK_ALIGN_CENTER);
    const subtitle = c.gtk_label_new("What would you like to do?");
    c.gtk_widget_set_halign(subtitle, c.GTK_ALIGN_CENTER);
    c.gtk_box_pack_start(vbox, title, 0, 0, 0);
    c.gtk_box_pack_start(vbox, subtitle, 0, 0, 0);

    const sep = c.gtk_separator_new(c.GTK_ORIENTATION_HORIZONTAL);
    c.gtk_box_pack_start(vbox, sep, 0, 0, 10);

    const launch_btn = c.gtk_button_new_with_label("Launch VM");
    const disk_btn = c.gtk_button_new_with_label("Create Disk");
    const cfg_btn = c.gtk_button_new_with_label("Configuration");
    c.gtk_widget_set_halign(launch_btn, c.GTK_ALIGN_CENTER);
    c.gtk_widget_set_halign(disk_btn, c.GTK_ALIGN_CENTER);
    c.gtk_widget_set_halign(cfg_btn, c.GTK_ALIGN_CENTER);
    c.gtk_widget_set_size_request(launch_btn, 200, 44);
    c.gtk_widget_set_size_request(disk_btn, 200, 44);
    c.gtk_widget_set_size_request(cfg_btn, 200, 36);
    c.gtk_box_pack_start(vbox, launch_btn, 0, 0, 0);
    c.gtk_box_pack_start(vbox, disk_btn, 0, 0, 0);
    c.gtk_box_pack_start(vbox, cfg_btn, 0, 0, 0);

    c.gtk_container_add(window, vbox);

    const ctx = allocator.create(Ctx) catch {
        messages.errorDialog(window, "Error", "Not enough memory to initialize the launcher.");
        return window;
    };
    ctx.* = .{ .allocator = allocator, .cfg = cfg, .window = window };

    gtk.signalConnect(launch_btn, "clicked", onLaunch, ctx);
    gtk.signalConnect(disk_btn, "clicked", onDisk, ctx);
    gtk.signalConnect(cfg_btn, "clicked", onConfig, ctx);
    gtk.signalConnect(about_btn, "clicked", onAbout, ctx);
    gtk.signalConnect(window, "destroy", onDestroy, ctx);

    return window;
}

fn onLaunch(button: ?*c.GtkWidget, data: ?*anyopaque) callconv(.c) void {
    _ = button;
    const ctx: *Ctx = @ptrCast(@alignCast(data.?));
    if (launch_dialog.run(ctx.allocator, ctx.window, ctx.cfg, null) catch null) |result| {
        defer launch_dialog.freeResult(ctx.allocator, &result);
        runner.launch(ctx.allocator, ctx.window, ctx.cfg, result);
    }
}

fn onDisk(button: ?*c.GtkWidget, data: ?*anyopaque) callconv(.c) void {
    _ = button;
    const ctx: *Ctx = @ptrCast(@alignCast(data.?));
    if (disk_dialog.run(ctx.allocator, ctx.window, ctx.cfg) catch null) |params| {
        defer ctx.allocator.free(params.name);

        const go_launch = messages.question(
            ctx.window,
            "Launch VM?",
            "Virtual disk creation completed.\n\nDo you want to launch a VM now?",
        );
        if (!go_launch) return;

        if (launch_dialog.run(ctx.allocator, ctx.window, ctx.cfg, params.name) catch null) |result| {
            defer launch_dialog.freeResult(ctx.allocator, &result);
            runner.launch(ctx.allocator, ctx.window, ctx.cfg, result);
        }
    }
}

fn onConfig(button: ?*c.GtkWidget, data: ?*anyopaque) callconv(.c) void {
    _ = button;
    const ctx: *Ctx = @ptrCast(@alignCast(data.?));
    settings_dialog.run(ctx.allocator, ctx.window, ctx.cfg);
}

fn onAbout(button: ?*c.GtkWidget, data: ?*anyopaque) callconv(.c) void {
    _ = button;
    const ctx: *Ctx = @ptrCast(@alignCast(data.?));
    messages.info(
        ctx.window,
        "About",
        "ZigVMU is a graphical QEMU virtual machine launcher written in Zig.\n\nAuthor: JavierC\nLicense: WTFPL",
    );
}

fn onDestroy(widget: ?*c.GtkWidget, data: ?*anyopaque) callconv(.c) void {
    _ = widget;
    const ctx: *Ctx = @ptrCast(@alignCast(data.?));
    ctx.allocator.destroy(ctx);
}
