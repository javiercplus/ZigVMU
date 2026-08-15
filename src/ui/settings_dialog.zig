//! Configuration dialog: QEMU mode (AppImage or system binaries) and EFI
//! firmware location. Changes are applied to the configuration and saved
//! to `~/.config/ZigVMU/zigvmu.ini`.

const std = @import("std");
const gtk = @import("../bindings/gtk.zig");
const c = gtk.c;
const config = @import("../config.zig");
const messages = @import("messages.zig");

const ModeCtx = struct {
    appimage_radio: gtk.Widget,
    qemu_chooser: gtk.Widget,
};

/// Opens the configuration dialog. Modifies `cfg` in memory and persists the
/// changes if the user presses "Save".
pub fn run(allocator: std.mem.Allocator, parent: gtk.Widget, cfg: *config.Config) void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const dialog = c.gtk_dialog_new();
    c.gtk_window_set_title(dialog, gtk.toC("Configuration"));
    c.gtk_window_set_modal(dialog, 1);
    if (parent != null) c.gtk_window_set_transient_for(dialog, parent);
    c.gtk_window_set_default_size(dialog, 620, 260);
    c.gtk_window_set_position(dialog, c.GTK_WIN_POS_CENTER);

    const content = c.gtk_dialog_get_content_area(dialog);
    c.gtk_container_set_border_width(content, 12);

    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(grid, 12);
    c.gtk_grid_set_column_spacing(grid, 12);

    const appimage_radio = c.gtk_radio_button_new_with_label(null, "Use QEMU AppImage");
    const system_radio = c.gtk_radio_button_new_with_label_from_widget(
        appimage_radio,
        "Use system QEMU binaries (qemu-system-x86_64, qemu-img)",
    );
    if (cfg.mode == .system) c.gtk_toggle_button_set_active(system_radio, 1);

    const qemu_chooser = c.gtk_file_chooser_button_new("Select QEMU AppImage", c.GTK_FILE_CHOOSER_ACTION_OPEN);
    if (cfg.mode == .appimage and cfg.qemu_path.len > 0) {
        setChooserFile(a, qemu_chooser, cfg.qemu_path);
    }
    c.gtk_widget_set_sensitive(qemu_chooser, if (cfg.mode == .appimage) 1 else 0);

    const bios_chooser = c.gtk_file_chooser_button_new("Select EFI BIOS (OVMF)", c.GTK_FILE_CHOOSER_ACTION_OPEN);
    if (cfg.bios_path.len > 0) {
        setChooserFile(a, bios_chooser, cfg.bios_path);
    }

    const mode_ctx = a.create(ModeCtx) catch null;
    if (mode_ctx) |ctx| {
        ctx.* = .{ .appimage_radio = appimage_radio, .qemu_chooser = qemu_chooser };
        gtk.signalConnect(appimage_radio, "toggled", onModeToggle, ctx);
        gtk.signalConnect(system_radio, "toggled", onModeToggle, ctx);
    }

    var row: c_int = 0;
    c.gtk_grid_attach(grid, rowLabel("QEMU mode:"), 0, row, 1, 1);
    const mode_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 6);
    c.gtk_box_pack_start(mode_box, appimage_radio, 0, 0, 0);
    c.gtk_box_pack_start(mode_box, system_radio, 0, 0, 0);
    c.gtk_grid_attach(grid, mode_box, 1, row, 3, 1);
    row += 1;

    c.gtk_grid_attach(grid, rowLabel("QEMU AppImage:"), 0, row, 1, 1);
    c.gtk_grid_attach(grid, qemu_chooser, 1, row, 3, 1);
    row += 1;

    c.gtk_grid_attach(grid, rowLabel("EFI BIOS (OVMF):"), 0, row, 1, 1);
    c.gtk_grid_attach(grid, bios_chooser, 1, row, 3, 1);
    row += 1;

    c.gtk_container_add(content, grid);

    _ = c.gtk_dialog_add_button(dialog, "Save", c.GTK_RESPONSE_OK);
    _ = c.gtk_dialog_add_button(dialog, "Cancel", c.GTK_RESPONSE_CANCEL);
    c.gtk_dialog_set_default_response(dialog, c.GTK_RESPONSE_OK);
    c.gtk_widget_show_all(dialog);

    defer c.gtk_widget_destroy(dialog);

    while (true) {
        const response = c.gtk_dialog_run(dialog);
        if (response != c.GTK_RESPONSE_OK) return;

        const qemu_path = chooserPath(a, qemu_chooser);
        const bios_path = chooserPath(a, bios_chooser);
        const mode: config.Mode = if (c.gtk_toggle_button_get_active(system_radio) != 0) .system else .appimage;

        if (mode == .appimage and qemu_path.len == 0) {
            messages.warning(parent, "Warning", "Select the QEMU AppImage path.");
            continue;
        }
        if (bios_path.len == 0) {
            messages.warning(parent, "Warning", "Select the EFI BIOS (OVMF) file.");
            continue;
        }

        // Apply the configuration in memory (new strings first, so the state
        // is not left broken if an allocation fails).
        const new_qemu = allocator.dupe(u8, qemu_path) catch {
            messages.errorDialog(parent, "Error", "Not enough memory to save the configuration.");
            return;
        };
        const new_bios = allocator.dupe(u8, bios_path) catch {
            allocator.free(new_qemu);
            messages.errorDialog(parent, "Error", "Not enough memory to save the configuration.");
            return;
        };
        cfg.mode = mode;
        allocator.free(cfg.qemu_path);
        allocator.free(cfg.bios_path);
        cfg.qemu_path = new_qemu;
        cfg.bios_path = new_bios;

        // Persist to ~/.config/ZigVMU/zigvmu.ini.
        if (cfg.save(allocator)) |_| {
            messages.info(parent, "Configuration", "Configuration saved to " ++ config.config_dirname ++ "/" ++ config.config_app_dirname ++ "/" ++ config.config_filename ++ ".");
        } else |_| {
            messages.warning(
                parent,
                "Warning",
                "Configuration applied for this session, but could not be written to " ++ config.config_dirname ++ "/" ++ config.config_app_dirname ++ "/" ++ config.config_filename ++ ".",
            );
        }
        return;
    }
}

fn chooserPath(allocator: std.mem.Allocator, chooser: gtk.Widget) []const u8 {
    const p = c.gtk_file_chooser_get_filename(chooser);
    if (p == null) return "";
    defer c.g_free(p);
    return allocator.dupe(u8, gtk.spanC(p)) catch "";
}

/// Pre-selects a file in the chooser. The chooser requires absolute paths,
/// so relative ones are resolved against the cwd.
fn setChooserFile(allocator: std.mem.Allocator, chooser: gtk.Widget, path: []const u8) void {
    const abs = absPath(allocator, path) catch return;
    defer allocator.free(abs);
    _ = c.gtk_file_chooser_set_filename(chooser, abs.ptr);
}

/// Converts a relative path to absolute using the current directory.
fn absPath(allocator: std.mem.Allocator, path: []const u8) ![:0]u8 {
    if (std.fs.path.isAbsolute(path)) return allocator.dupeZ(u8, path);
    const cwd = try std.process.currentPathAlloc(std.Io.Threaded.global_single_threaded.io(), allocator);
    defer allocator.free(cwd);
    return std.fs.path.joinZ(allocator, &.{ cwd, path });
}

fn rowLabel(text: [:0]const u8) gtk.Widget {
    const label = c.gtk_label_new(text);
    c.gtk_label_set_xalign(label, 0);
    c.gtk_widget_set_halign(label, c.GTK_ALIGN_START);
    return label;
}

fn onModeToggle(toggle: ?*c.GtkWidget, data: ?*anyopaque) callconv(.c) void {
    _ = toggle;
    const ctx: *ModeCtx = @ptrCast(@alignCast(data.?));
    const appimage_mode = c.gtk_toggle_button_get_active(ctx.appimage_radio) != 0;
    c.gtk_widget_set_sensitive(ctx.qemu_chooser, if (appimage_mode) 1 else 0);
}
