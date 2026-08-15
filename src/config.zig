//! Application constants and global configuration.
//!
//! The configuration is loaded from `~/.config/ZigVMU/zigvmu.ini` and can be
//! overridden with environment variables. The "Configuration" UI saves it
//! to that same file.

const std = @import("std");
const system = @import("system/mod.zig");
const qemu = @import("qemu/mod.zig");

pub const app_id = "es.zigvmu.Launcher";

/// Default path of the QEMU AppImage.
pub const default_qemu_path = "./QEMU-x86_64.AppImage";
/// Environment variable to override the QEMU path (AppImage mode).
pub const qemu_env = "ZIGVMU_QEMU";
/// Default path of the EFI firmware (OVMF).
pub const default_bios_path = "./OVMF_X64.fd";
/// Environment variable to override the EFI firmware path.
pub const bios_env = "ZIGVMU_BIOS";
/// Environment variable to force the mode ("appimage" or "system").
pub const mode_env = "ZIGVMU_MODE";

/// Persistent user configuration file:
/// `~/.config/ZigVMU/zigvmu.ini`.
pub const config_dirname = ".config";
pub const config_app_dirname = "ZigVMU";
pub const config_filename = "zigvmu.ini";

/// System binaries used when the mode is `system`.
pub const system_qemu_img_binary = "qemu-img";

/// QEMU execution mode.
pub const Mode = enum {
    appimage,
    system,

    pub fn label(self: Mode) []const u8 {
        return switch (self) {
            .appimage => "appimage",
            .system => "system",
        };
    }
};

pub const Config = struct {
    mode: Mode = .appimage,
    /// Path of the QEMU AppImage (only used in `appimage` mode).
    qemu_path: []const u8,
    /// Path of the EFI firmware (OVMF).
    bios_path: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Config {
        var cfg: Config = .{
            .mode = .appimage,
            .qemu_path = try allocator.dupe(u8, default_qemu_path),
            .bios_path = try allocator.dupe(u8, default_bios_path),
        };
        errdefer cfg.deinit(allocator);

        if (configPath(allocator)) |path| {
            defer allocator.free(path);
            if (try loadIni(allocator, path)) |ini| {
                defer ini.deinit(allocator);
                if (ini.mode) |m| cfg.mode = m;
                if (ini.qemu_path) |p| {
                    const np = try allocator.dupe(u8, p);
                    allocator.free(cfg.qemu_path);
                    cfg.qemu_path = np;
                }
                if (ini.bios_path) |b| {
                    const nb = try allocator.dupe(u8, b);
                    allocator.free(cfg.bios_path);
                    cfg.bios_path = nb;
                }
            }
        }

        // Environment variables take priority over the file.
        if (envMaybe(mode_env)) |m| {
            cfg.mode = if (std.mem.eql(u8, m, "system")) .system else .appimage;
        }
        if (envMaybe(qemu_env)) |p| {
            const np = try allocator.dupe(u8, p);
            allocator.free(cfg.qemu_path);
            cfg.qemu_path = np;
        }
        if (envMaybe(bios_env)) |b| {
            const nb = try allocator.dupe(u8, b);
            allocator.free(cfg.bios_path);
            cfg.bios_path = nb;
        }

        return cfg;
    }

    pub fn deinit(self: *const Config, allocator: std.mem.Allocator) void {
        allocator.free(self.qemu_path);
        allocator.free(self.bios_path);
    }

    /// Saves the configuration to `~/.config/ZigVMU/zigvmu.ini`.
    pub fn save(self: *const Config, allocator: std.mem.Allocator) !void {
        const io = std.Io.Threaded.global_single_threaded.io();

        const path = try configPathAlloc(allocator);
        defer allocator.free(path);

        if (configDirPath(allocator)) |dir| {
            defer allocator.free(dir);
            std.Io.Dir.createDirPath(.cwd(), io, dir) catch {};
        }

        const content = try std.fmt.allocPrint(
            allocator,
            "mode={s}\nqemu_path={s}\nbios_path={s}\n",
            .{ self.mode.label(), self.qemu_path, self.bios_path },
        );
        defer allocator.free(content);

        const file = try std.Io.Dir.createFile(.cwd(), io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, content);
    }

    /// Binary executed as QEMU (argv[0]) for the given architecture.
    /// In AppImage mode it is always the AppImage (x86_64 only); in system
    /// mode it is the system binary `qemu-system-<arch>`. Returns an
    /// allocated string; the caller must free it.
    pub fn qemuBinaryAlloc(self: *const Config, allocator: std.mem.Allocator, arch: qemu.command.Arch) ![]u8 {
        return switch (self.mode) {
            .appimage => allocator.dupe(u8, self.qemu_path),
            .system => std.fmt.allocPrint(allocator, "qemu-system-{s}", .{arch.name()}),
        };
    }

    /// `qemu-img` binary depending on the mode.
    pub fn qemuImgBinary(self: *const Config) []const u8 {
        return switch (self.mode) {
            .appimage => self.qemu_path,
            .system => system_qemu_img_binary,
        };
    }

    /// Checks whether the QEMU binary for the given architecture is
    /// available and executable.
    pub fn qemuAvailable(self: *const Config, allocator: std.mem.Allocator, arch: qemu.command.Arch) bool {
        return switch (self.mode) {
            .appimage => system.fs.fileExecutable(self.qemu_path),
            .system => blk: {
                const bin = std.fmt.allocPrint(allocator, "qemu-system-{s}", .{arch.name()}) catch break :blk false;
                defer allocator.free(bin);
                break :blk system.process.existsOnPath(allocator, bin);
            },
        };
    }

    /// Checks whether `qemu-img` is available and executable.
    pub fn qemuImgAvailable(self: *const Config, allocator: std.mem.Allocator) bool {
        return switch (self.mode) {
            .appimage => system.fs.fileExecutable(self.qemu_path),
            .system => system.process.existsOnPath(allocator, system_qemu_img_binary),
        };
    }
};

/// Raw values read from the INI file.
const IniValues = struct {
    mode: ?Mode = null,
    qemu_path: ?[]const u8 = null,
    bios_path: ?[]const u8 = null,

    fn deinit(self: *const IniValues, allocator: std.mem.Allocator) void {
        if (self.qemu_path) |p| allocator.free(p);
        if (self.bios_path) |b| allocator.free(b);
    }
};

/// Reads and parses the INI. Returns `null` if the file does not exist or
/// cannot be read. The result contains allocated copies.
fn loadIni(allocator: std.mem.Allocator, path: []const u8) !?IniValues {
    const io = std.Io.Threaded.global_single_threaded.io();
    const data = std.Io.Dir.readFileAlloc(.cwd(), io, path, allocator, .limited(64 * 1024)) catch return null;
    defer allocator.free(data);

    var result: IniValues = .{};
    errdefer result.deinit(allocator);

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#' or line[0] == ';') continue;

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");
        if (value.len == 0) continue;

        if (std.mem.eql(u8, key, "mode")) {
            if (std.mem.eql(u8, value, "system")) result.mode = .system;
        } else if (std.mem.eql(u8, key, "qemu_path")) {
            if (result.qemu_path) |prev| allocator.free(prev);
            result.qemu_path = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "bios_path")) {
            if (result.bios_path) |prev| allocator.free(prev);
            result.bios_path = try allocator.dupe(u8, value);
        }
    }
    return result;
}

/// Full path of the configuration file, or `null` if there is no HOME.
fn configPath(allocator: std.mem.Allocator) ?[]u8 {
    return configPathAlloc(allocator) catch null;
}

fn configPathAlloc(allocator: std.mem.Allocator) ![]u8 {
    const home = homeDir() orelse return allocator.dupe(u8, config_filename);
    return std.fs.path.join(allocator, &.{ home, config_dirname, config_app_dirname, config_filename });
}

/// Configuration directory (`~/.config/ZigVMU`), or `null` if there is no HOME.
fn configDirPath(allocator: std.mem.Allocator) ?[]u8 {
    const home = homeDir() orelse return null;
    return std.fs.path.join(allocator, &.{ home, config_dirname, config_app_dirname }) catch null;
}

fn homeDir() ?[]const u8 {
    const h = std.c.getenv("HOME") orelse return null;
    const span = std.mem.span(h);
    if (span.len == 0) return null;
    return span;
}

fn envMaybe(name: [*:0]const u8) ?[]const u8 {
    const v = std.c.getenv(name) orelse return null;
    const s = std.mem.span(v);
    if (s.len == 0) return null;
    return s;
}
