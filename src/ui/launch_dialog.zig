//! Virtual machine launch dialog with all the QEMU options.

const std = @import("std");
const gtk = @import("../bindings/gtk.zig");
const c = gtk.c;
const config = @import("../config.zig");
const system = @import("../system/mod.zig");
const qemu = @import("../qemu/mod.zig");
const messages = @import("messages.zig");

const arches = [_]qemu.command.Arch{
    .x86_64,
    .i386,
    .aarch64,
    .arm,
    .riscv64,
    .ppc64,
};

pub const Result = struct {
    opts: qemu.command.LaunchOptions,
    audio_backend: system.audio.Backend,
};

/// Opens the launch configuration dialog. Returns the launch options if the
/// user confirmed, or `null` if they cancelled. The result strings are
/// copies owned by the caller.
pub fn run(
    allocator: std.mem.Allocator,
    parent: gtk.Widget,
    cfg: *config.Config,
    preset_hda: ?[]const u8,
) !?Result {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const dialog = c.gtk_dialog_new();
    c.gtk_window_set_title(dialog, gtk.toC("ZigVMU - Advanced Configuration"));
    c.gtk_window_set_modal(dialog, 1);
    if (parent != null) c.gtk_window_set_transient_for(dialog, parent);
    c.gtk_window_set_default_size(dialog, 640, 440);
    c.gtk_window_set_position(dialog, c.GTK_WIN_POS_CENTER);

    const content = c.gtk_dialog_get_content_area(dialog);
    c.gtk_container_set_border_width(content, 12);

    const grid = c.gtk_grid_new();
    c.gtk_grid_set_row_spacing(grid, 10);
    c.gtk_grid_set_column_spacing(grid, 12);

    const hda_chooser = c.gtk_file_chooser_button_new("Select hard disk image", c.GTK_FILE_CHOOSER_ACTION_OPEN);
    if (preset_hda) |p| {
        _ = c.gtk_file_chooser_set_filename(hda_chooser, gtk.toC(p));
    } else {
        if (fileExists("hd.qcow2")) {
            _ = c.gtk_file_chooser_set_filename(hda_chooser, "hd.qcow2");
        }
    }

    const iso_chooser = c.gtk_file_chooser_button_new("Select ISO (CD-ROM)", c.GTK_FILE_CHOOSER_ACTION_OPEN);

    const ram_spin = c.gtk_spin_button_new(c.gtk_adjustment_new(2048, 64, 16384, 128, 512, 0), 0, 0);
    const cores_spin = c.gtk_spin_button_new(c.gtk_adjustment_new(2, 1, 32, 1, 2, 0), 0, 0);

    const arch_combo = c.gtk_combo_box_text_new();
    for (arches) |arch| c.gtk_combo_box_text_append_text(arch_combo, gtk.toC(arch.name()));
    c.gtk_combo_box_set_active(arch_combo, 0); // x86_64 by default

    const efi_check = c.gtk_check_button_new_with_label("Enable EFI (OVMF BIOS)");
    const cpu_host_check = c.gtk_check_button_new_with_label("Use CPU host (-cpu host)");
    const boot_cd_check = c.gtk_check_button_new_with_label("Boot from CD-ROM (-boot d)");
    c.gtk_toggle_button_set_active(boot_cd_check, 1);

    const phys_check = c.gtk_check_button_new_with_label("Use physical disk (RAW)");
    const phys_entry = c.gtk_entry_new();
    c.gtk_entry_set_placeholder_text(phys_entry, "e.g. /dev/sda");
    c.gtk_widget_set_sensitive(phys_entry, 0);
    gtk.signalConnect(phys_check, "toggled", onPhysToggle, phys_entry);

    const virtio_check = c.gtk_check_button_new_with_label("Enable VirtIO GPU (3D accel)");
    c.gtk_toggle_button_set_active(virtio_check, 1);

    const audio_combo = c.gtk_combo_box_text_new();
    c.gtk_combo_box_text_append_text(audio_combo, gtk.toC(qemu.command.AudioDevice.virtio_sound.label()));
    c.gtk_combo_box_text_append_text(audio_combo, gtk.toC(qemu.command.AudioDevice.intel_hda.label()));
    c.gtk_combo_box_text_append_text(audio_combo, gtk.toC(qemu.command.AudioDevice.ac97.label()));
    c.gtk_combo_box_text_append_text(audio_combo, gtk.toC(qemu.command.AudioDevice.none.label()));
    c.gtk_combo_box_set_active(audio_combo, 0);

    var row: c_int = 0;
    attachRow(grid, &row, rowLabel("Hard disk image (.qcow2):"), hda_chooser, 3);
    attachRow(grid, &row, rowLabel("ISO (CD-ROM) - optional:"), iso_chooser, 3);
    attachRow(grid, &row, rowLabel("RAM (MB):"), ram_spin, 3);
    attachRow(grid, &row, rowLabel("CPU cores:"), cores_spin, 3);
    attachRow(grid, &row, rowLabel("Architecture:"), arch_combo, 3);
    c.gtk_grid_attach(grid, efi_check, 1, row, 3, 1);
    row += 1;
    c.gtk_grid_attach(grid, cpu_host_check, 1, row, 3, 1);
    row += 1;
    c.gtk_grid_attach(grid, boot_cd_check, 1, row, 3, 1);
    row += 1;
    c.gtk_grid_attach(grid, phys_check, 0, row, 1, 1);
    c.gtk_grid_attach(grid, phys_entry, 1, row, 3, 1);
    row += 1;
    c.gtk_grid_attach(grid, virtio_check, 1, row, 3, 1);
    row += 1;
    attachRow(grid, &row, rowLabel("Audio Device:"), audio_combo, 3);
    // Space between the last row (Audio Device) and the action buttons.
    c.gtk_widget_set_margin_bottom(grid, 16);

    c.gtk_container_add(content, grid);

    _ = c.gtk_dialog_add_button(dialog, "Launch QEMU", c.GTK_RESPONSE_OK);
    _ = c.gtk_dialog_add_button(dialog, "Cancel", c.GTK_RESPONSE_CANCEL);
    c.gtk_dialog_set_default_response(dialog, c.GTK_RESPONSE_OK);
    c.gtk_widget_show_all(dialog);

    defer c.gtk_widget_destroy(dialog);

    while (true) {
        const response = c.gtk_dialog_run(dialog);
        if (response != c.GTK_RESPONSE_OK) return null;

        const hda_path = chooserPath(a, hda_chooser);
        const iso_path = chooserPath(a, iso_chooser);
        const phys_path = gtk.spanC(c.gtk_entry_get_text(phys_entry));

        var opts = qemu.command.LaunchOptions{
            .hda = hda_path,
            .iso = if (iso_path.len > 0) iso_path else null,
            .ram_mb = @intCast(@max(c.gtk_spin_button_get_value_as_int(ram_spin), 64)),
            .cores = @intCast(@max(c.gtk_spin_button_get_value_as_int(cores_spin), 1)),
            .efi = c.gtk_toggle_button_get_active(efi_check) != 0,
            .cpu_host = c.gtk_toggle_button_get_active(cpu_host_check) != 0,
            .boot_cd = c.gtk_toggle_button_get_active(boot_cd_check) != 0,
            .phys_disk = if (c.gtk_toggle_button_get_active(phys_check) != 0) phys_path else null,
            .virtio_gpu = c.gtk_toggle_button_get_active(virtio_check) != 0,
            .audio = audioFromIndex(c.gtk_combo_box_get_active(audio_combo)),
            .arch = arches[@intCast(@max(c.gtk_combo_box_get_active(arch_combo), 0))],
        };

        if (!try validate(a, dialog, cfg, &opts)) continue;

        const backend = system.audio.detect(a);
        if (opts.audio != .none and backend == .none) {
            messages.warning(dialog, "Warning", "No audio system detected.\nAudio will be disabled.");
            opts.audio = .none;
        }

        const bin = try cfg.qemuBinaryAlloc(a, opts.arch);
        defer a.free(bin);
        const argv = try qemu.command.build(a, bin, cfg.bios_path, backend, opts);
        const preview = try std.fmt.allocPrint(
            a,
            "The following command will be executed:\n\n{s}\n\nAudio: {s} (Host: {s})\n\nDo you want to continue?",
            .{ try joinArgv(a, argv), opts.audio.label(), backend.label() },
        );

        if (!messages.confirm(dialog, "Confirm Launch", preview)) continue;

        return .{
            .opts = try cloneOpts(allocator, opts),
            .audio_backend = backend,
        };
    }
}

/// Frees a result returned by `run`.
pub fn freeResult(allocator: std.mem.Allocator, result: *const Result) void {
    allocator.free(result.opts.hda);
    if (result.opts.iso) |iso| allocator.free(iso);
    if (result.opts.phys_disk) |p| allocator.free(p);
}

/// Validates the options and shows errors/warnings. Returns `false` if the
/// launch should not continue.
fn validate(
    allocator: std.mem.Allocator,
    parent: gtk.Widget,
    cfg: *config.Config,
    opts: *const qemu.command.LaunchOptions,
) !bool {
    if (opts.iso) |iso| {
        if (iso.len > 0 and !fileExists(iso)) {
            messages.errorDialog(parent, "Error", try std.fmt.allocPrint(allocator, "ISO file not found:\n{s}", .{iso}));
            return false;
        }
    }

    if (opts.hda.len == 0 or !fileExists(opts.hda)) {
        messages.warning(
            parent,
            "Warning",
            try std.fmt.allocPrint(
                allocator,
                "Hard disk file '{s}' does not exist.\n\nYou can:\n- Create it with the 'Create Disk' button in the main window\n- Continue and it will fail\n- Select an existing disk file",
                .{opts.hda},
            ),
        );
    }

    if (opts.efi and !fileExists(cfg.bios_path)) {
        messages.errorDialog(parent, "Error", try std.fmt.allocPrint(allocator, "EFI BIOS file not found:\n{s}\n\nPlease check the path or download OVMF_X64.fd", .{cfg.bios_path}));
        return false;
    }

    if (opts.phys_disk) |path| {
        if (path.len == 0) {
            messages.errorDialog(parent, "Error", "You checked 'Use physical disk' but did not specify a path.\nExample: /dev/sda");
            return false;
        }
        if (!fileExists(path)) {
            messages.warning(parent, "Warning", try std.fmt.allocPrint(allocator, "Physical device '{s}' does not exist.\nPlease verify the path.", .{path}));
        }
        const ok = messages.question(
            parent,
            "Caution with physical disk",
            try std.fmt.allocPrint(
                allocator,
                "You are about to attach the device '{s}' to the virtual machine.\n\nMake sure it is NOT the host system disk and that no system is using it.\n\nDo you want to continue?",
                .{path},
            ),
        );
        if (!ok) return false;
    }

    if (cfg.mode == .appimage and opts.arch != .x86_64) {
        messages.warning(
            parent,
            "Warning",
            try std.fmt.allocPrint(
                allocator,
                "The QEMU AppImage only includes x86_64.\nTo run a {s} guest, use the system QEMU binaries (Configuration).",
                .{opts.arch.name()},
            ),
        );
    }

    return true;
}

fn cloneOpts(allocator: std.mem.Allocator, opts: qemu.command.LaunchOptions) !qemu.command.LaunchOptions {
    return .{
        .hda = try allocator.dupe(u8, opts.hda),
        .iso = if (opts.iso) |iso| try allocator.dupe(u8, iso) else null,
        .ram_mb = opts.ram_mb,
        .cores = opts.cores,
        .efi = opts.efi,
        .cpu_host = opts.cpu_host,
        .boot_cd = opts.boot_cd,
        .phys_disk = if (opts.phys_disk) |p| try allocator.dupe(u8, p) else null,
        .virtio_gpu = opts.virtio_gpu,
        .audio = opts.audio,
        .arch = opts.arch,
    };
}

fn joinArgv(allocator: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
    return std.mem.join(allocator, " ", argv);
}

fn audioFromIndex(index: c_int) qemu.command.AudioDevice {
    return switch (index) {
        1 => .intel_hda,
        2 => .ac97,
        3 => .none,
        else => .virtio_sound,
    };
}

fn chooserPath(allocator: std.mem.Allocator, chooser: gtk.Widget) []const u8 {
    const p = c.gtk_file_chooser_get_filename(chooser);
    if (p == null) return "";
    defer c.g_free(p);
    return allocator.dupe(u8, gtk.spanC(p)) catch "";
}

fn fileExists(path: []const u8) bool {
    return system.fs.fileExists(path);
}

fn attachRow(grid: gtk.Widget, row: *c_int, label: gtk.Widget, widget: gtk.Widget, span: c_int) void {
    c.gtk_grid_attach(grid, label, 0, row.*, 1, 1);
    c.gtk_grid_attach(grid, widget, 1, row.*, span, 1);
    row.* += 1;
}

fn rowLabel(text: [:0]const u8) gtk.Widget {
    const label = c.gtk_label_new(text);
    c.gtk_label_set_xalign(label, 0);
    c.gtk_widget_set_halign(label, c.GTK_ALIGN_START);
    return label;
}

fn onPhysToggle(toggle: ?*c.GtkWidget, data: ?*anyopaque) callconv(.c) void {
    const entry: gtk.Widget = @ptrCast(@alignCast(data.?));
    c.gtk_widget_set_sensitive(entry, c.gtk_toggle_button_get_active(toggle));
}