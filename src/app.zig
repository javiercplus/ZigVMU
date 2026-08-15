//! GTK application initialization.

const std = @import("std");
const gtk = @import("bindings/gtk.zig");
const c = gtk.c;
const config = @import("config.zig");
const ui = @import("ui/mod.zig");

var g_allocator: std.mem.Allocator = undefined;
var g_cfg: config.Config = undefined;
var g_window: gtk.Widget = null;

/// Starts the application main loop. Does not return until the user closes
/// the main window.
pub fn run(allocator: std.mem.Allocator, args_vector: std.process.Args.Vector) !void {
    g_allocator = allocator;
    g_cfg = try config.Config.init(allocator);
    defer g_cfg.deinit(allocator);

    const app = c.gtk_application_new(config.app_id, c.G_APPLICATION_FLAGS_NONE);
    if (app == null) return error.FailedToCreateApplication;
    _ = c.g_object_ref_sink(app);
    defer c.g_object_unref(app);

    gtk.signalConnect(@ptrCast(app), "activate", onActivate, null);

    const cargv = try allocator.alloc(?[*:0]u8, args_vector.len + 1);
    defer allocator.free(cargv);
    for (args_vector, 0..) |arg, i| cargv[i] = @ptrCast(@constCast(arg));
    cargv[args_vector.len] = null;

    _ = c.g_application_run(@ptrCast(app), @intCast(args_vector.len), @ptrCast(cargv.ptr));
}

fn onActivate(app: ?*c.GtkApplication, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    applyNoRoundedCorners();
    if (g_window != null) return;
    g_window = ui.main_window.build(app, g_allocator, &g_cfg);
    gtk.signalConnect(@ptrCast(g_window), "destroy", onWindowDestroy, null);
    c.gtk_widget_show_all(g_window);
}

/// Removes the rounded corners from all widgets (square theme). GTK must be
/// initialized for the default screen to be available.
fn applyNoRoundedCorners() void {
    const css = c.gtk_css_provider_new();
    defer c.g_object_unref(css);
    c.gtk_css_provider_load_from_data(css, "* { border-radius: 0px; }", -1, null);
    c.gtk_style_context_add_provider_for_screen(
        c.gdk_screen_get_default(),
        css,
        c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
}

fn onWindowDestroy(widget: gtk.Widget, data: ?*anyopaque) callconv(.c) void {
    _ = widget;
    _ = data;
    g_window = null;
}