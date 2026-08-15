//! Dialog to create a virtual disk with `qemu-img`.

const std = @import("std");
const gtk = @import("../bindings/gtk.zig");
const c = gtk.c;
const config = @import("../config.zig");
const system = @import("../system/mod.zig");
const qemu = @import("../qemu/mod.zig");
const messages = @import("messages.zig");
const progress = @import("progress.zig");

const formats = [_]qemu.disk.Format{
    .qcow2,
    .raw,
    .qed,
    .vdi,
    .vmdk,
    .vpc,
};

const DiskWork = struct {
    qemu_path: []const u8,
    params: qemu.disk.DiskParams,
};

/// Opens the creation dialog. Returns the disk parameters if the disk was
/// created successfully, or `null` if it was cancelled. The `name` string of
/// the result is a copy owned by the caller.
pub fn run(
    allocator: std.mem.Allocator,
    parent: gtk.Widget,
    cfg: *config.Config,
) !?qemu.disk.DiskParams {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const dialog = c.gtk_dialog_new();
    c.gtk_window_set_title(dialog, gtk.toC("Create Virtual Disk"));
    c.gtk_window_set_modal(dialog, 1);
    if (parent != null) c.gtk_window_set_transient_for(dialog, parent);
    c.gtk_window_set_default_size(dialog, 520, 260);
    c.gtk_window_set_position(dialog, c.GTK_WIN_POS_CENTER);

    const content = c.gtk_dialog_get_content_area(dialog);
    c.gtk_container_set_border_width(content, 12);

    const name_entry = c.gtk_entry_new();
    c.gtk_entry_set_text(name_entry, "hd.qcow2");

    const folder_chooser = c.gtk_file_chooser_button_new("Select folder", c.GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER);
    if (std.process.currentPathAlloc(std.Io.Threaded.global_single_threaded.io(), a)) |dir| {
        defer a.free(dir);
        _ = c.gtk_file_chooser_set_filename(folder_chooser, gtk.toC(dir));
    } else |_| {}

    const size_spin = c.gtk_spin_button_new(c.gtk_adjustment_new(30, 1, 1024, 10, 50, 0), 0, 0);

    const unit_combo = c.gtk_combo_box_text_new();
    c.gtk_combo_box_text_append_text(unit_combo, gtk.toC(qemu.disk.Unit.g.label()));
    c.gtk_combo_box_text_append_text(unit_combo, gtk.toC(qemu.disk.Unit.m.label()));
    c.gtk_combo_box_text_append_text(unit_combo, gtk.toC(qemu.disk.Unit.t.label()));
    c.gtk_combo_box_set_active(unit_combo, 0);

    const format_combo = c.gtk_combo_box_text_new();
    for (formats) |f| c.gtk_combo_box_text_append_text(format_combo, gtk.toC(f.label()));
    c.gtk_combo_box_set_active(format_combo, 0);

    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(grid, 10);
    c.gtk_grid_set_column_spacing(grid, 12);
    c.gtk_grid_attach(grid, rowLabel("Disk name (e.g. hd.qcow2):"), 0, 0, 1, 1);
    c.gtk_grid_attach(grid, name_entry, 1, 0, 3, 1);
    c.gtk_grid_attach(grid, rowLabel("Location:"), 0, 1, 1, 1);
    c.gtk_grid_attach(grid, folder_chooser, 1, 1, 3, 1);
    c.gtk_grid_attach(grid, rowLabel("Disk size:"), 0, 2, 1, 1);
    c.gtk_grid_attach(grid, size_spin, 1, 2, 1, 1);
    c.gtk_grid_attach(grid, unit_combo, 2, 2, 1, 1);
    c.gtk_grid_attach(grid, rowLabel("Format:"), 0, 3, 1, 1);
    c.gtk_grid_attach(grid, format_combo, 1, 3, 3, 1);

    c.gtk_container_add(content, grid);

    _ = c.gtk_dialog_add_button(dialog, "Create Disk", c.GTK_RESPONSE_OK);
    _ = c.gtk_dialog_add_button(dialog, "Cancel", c.GTK_RESPONSE_CANCEL);
    c.gtk_dialog_set_default_response(dialog, c.GTK_RESPONSE_OK);
    c.gtk_widget_show_all(dialog);

    defer c.gtk_widget_destroy(dialog);

    while (true) {
        const response = c.gtk_dialog_run(dialog);
        if (response != c.GTK_RESPONSE_OK) return null;

        const name = gtk.spanC(c.gtk_entry_get_text(name_entry));
        if (name.len == 0) {
            messages.errorDialog(parent, "Error", "Disk name cannot be empty.");
            continue;
        }

        const folder_p = c.gtk_file_chooser_get_filename(folder_chooser);
        defer if (folder_p != null) c.g_free(folder_p);
        const folder = if (folder_p != null) gtk.spanC(folder_p) else "";

        const full_path = if (std.fs.path.isAbsolute(name))
            name
        else if (folder.len > 0)
            try std.fs.path.join(a, &.{ folder, name })
        else
            name;

        const size: u32 = @intCast(@max(c.gtk_spin_button_get_value_as_int(size_spin), 1));
        const unit = unitFromIndex(c.gtk_combo_box_get_active(unit_combo));
        const format = formats[@intCast(@max(c.gtk_combo_box_get_active(format_combo), 0))];

        if (system.fs.fileExists(full_path)) {
            const overwrite = messages.question(
                parent,
                "File Exists",
                try std.fmt.allocPrint(a, "The file '{s}' already exists.\n\nDo you want to overwrite it?", .{full_path}),
            );
            if (!overwrite) continue;
        }

        const params = qemu.disk.DiskParams{
            .name = try a.dupe(u8, full_path),
            .size = size,
            .unit = unit,
            .format = format,
        };
        const full = try qemu.disk.fullSize(a, params);
        defer a.free(full);

        const confirm = messages.question(
            parent,
            "Confirm Disk Creation",
            try std.fmt.allocPrint(a, "Create virtual disk with these parameters?\n\n- Name: {s}\n- Size: {s}\n- Format: {s}", .{ full_path, full, params.format.label() }),
        );
        if (!confirm) continue;

        if (!cfg.qemuImgAvailable(allocator)) {
            messages.errorDialog(
                parent,
                "Error",
                "qemu-img not found or not executable.\n\nOpen 'Configuration' to set the AppImage path or switch to the system QEMU binaries.",
            );
            continue;
        }

        const disk_work = try a.create(DiskWork);
        disk_work.* = .{
            .qemu_path = try a.dupe(u8, cfg.qemuImgBinary()),
            .params = params,
        };
        const work = progress.Work{
            .runFn = diskWorker,
            .ctx = disk_work,
        };
        const outcome = try progress.run(parent, "Creating Virtual Disk", work);

        switch (outcome) {
            .success => return .{ .name = try allocator.dupe(u8, full_path), .size = size, .unit = unit, .format = format },
            .failure => messages.errorDialog(
                parent,
                "Error",
                "Failed to create virtual disk.\n\nPlease check:\n- Disk space\n- Write permissions\n- QEMU AppImage functionality",
            ),
        }
    }
}

fn diskWorker(ctx: *anyopaque) anyerror!void {
    const work: *DiskWork = @ptrCast(@alignCast(ctx));
    try qemu.disk.create(std.heap.page_allocator, work.qemu_path, work.params);
}

fn unitFromIndex(index: c_int) qemu.disk.Unit {
    return switch (index) {
        1 => .m,
        2 => .t,
        else => .g,
    };
}

fn rowLabel(text: [:0]const u8) gtk.Widget {
    const label = c.gtk_label_new(text);
    c.gtk_label_set_xalign(label, 0);
    c.gtk_widget_set_halign(label, c.GTK_ALIGN_START);
    return label;
}