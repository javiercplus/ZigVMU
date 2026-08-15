//! Virtual disk creation through `qemu-img`.

const std = @import("std");
const system = @import("../system/mod.zig");

pub const Unit = enum {
    g,
    m,
    t,

    pub fn label(self: Unit) []const u8 {
        return switch (self) {
            .g => "G",
            .m => "M",
            .t => "T",
        };
    }
};

pub const Format = enum {
    qcow2,
    raw,
    qed,
    vdi,
    vmdk,
    vpc,

    pub fn label(self: Format) []const u8 {
        return switch (self) {
            .qcow2 => "qcow2",
            .raw => "raw",
            .qed => "qed",
            .vdi => "vdi",
            .vmdk => "vmdk",
            .vpc => "vpc",
        };
    }
};

pub const DiskParams = struct {
    name: []const u8,
    size: u32,
    unit: Unit,
    format: Format,
};

/// Full size string, e.g. "30G".
pub fn fullSize(allocator: std.mem.Allocator, params: DiskParams) ![]u8 {
    return std.fmt.allocPrint(allocator, "{d}{s}", .{ params.size, params.unit.label() });
}

/// Creates a virtual disk by running `qemu-img create`. Returns an error if
/// the command fails.
pub fn create(
    allocator: std.mem.Allocator,
    qemu_path: []const u8,
    params: DiskParams,
) !void {
    const size = try fullSize(allocator, params);
    defer allocator.free(size);

    const argv = [_][]const u8{
        qemu_path,
        "qemu-img",
        "create",
        "-f",
        params.format.label(),
        params.name,
        size,
    };

    const code = try system.process.spawnAndWait(allocator, &argv);
    if (code != 0) return error.DiskCreationFailed;
}