//! Builds the QEMU command line from structured options.
//! Replicates the logic of the original launcher.

const std = @import("std");
const system = @import("../system/mod.zig");

pub const AudioDevice = enum {
    virtio_sound,
    intel_hda,
    ac97,
    none,

    pub fn label(self: AudioDevice) []const u8 {
        return switch (self) {
            .virtio_sound => "virtio-sound",
            .intel_hda => "intel-hda",
            .ac97 => "AC97",
            .none => "none",
        };
    }
};

/// Virtual machine architecture. In `system` mode it determines the QEMU
/// binary used (`qemu-system-<arch>`).
pub const Arch = enum {
    x86_64,
    i386,
    aarch64,
    arm,
    riscv64,
    ppc64,

    pub fn name(self: Arch) []const u8 {
        return switch (self) {
            .x86_64 => "x86_64",
            .i386 => "i386",
            .aarch64 => "aarch64",
            .arm => "arm",
            .riscv64 => "riscv64",
            .ppc64 => "ppc64",
        };
    }
};

pub const LaunchOptions = struct {
    hda: []const u8,
    iso: ?[]const u8 = null,
    ram_mb: u32 = 2048,
    cores: u32 = 2,
    efi: bool = false,
    cpu_host: bool = false,
    boot_cd: bool = true,
    phys_disk: ?[]const u8 = null,
    virtio_gpu: bool = true,
    audio: AudioDevice = .virtio_sound,
    arch: Arch = .x86_64,
};

/// Builds the QEMU argv. Every string in the result is an allocated copy;
/// the caller must release them with `freeArgv`.
pub fn build(
    allocator: std.mem.Allocator,
    qemu_path: []const u8,
    bios_path: []const u8,
    audio_backend: system.audio.Backend,
    opts: LaunchOptions,
) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer freeArgv(allocator, list.items);

    try list.append(allocator, try allocator.dupe(u8, qemu_path));
    try list.append(allocator, try allocator.dupe(u8, "-enable-kvm"));

    const ram = try std.fmt.allocPrint(allocator, "{d}", .{opts.ram_mb});
    try list.append(allocator, try allocator.dupe(u8, "-m"));
    try list.append(allocator, ram);
    const cores = try std.fmt.allocPrint(allocator, "{d}", .{opts.cores});
    try list.append(allocator, try allocator.dupe(u8, "-smp"));
    try list.append(allocator, cores);

    if (opts.virtio_gpu) {
        try list.append(allocator, try allocator.dupe(u8, "-device"));
        try list.append(allocator, try allocator.dupe(u8, "virtio-vga-gl"));
        try list.append(allocator, try allocator.dupe(u8, "-display"));
        try list.append(allocator, try allocator.dupe(u8, "gtk,gl=on"));
    } else {
        try list.append(allocator, try allocator.dupe(u8, "-vga"));
        try list.append(allocator, try allocator.dupe(u8, "std"));
        try list.append(allocator, try allocator.dupe(u8, "-display"));
        try list.append(allocator, try allocator.dupe(u8, "gtk"));
    }

    appendAudio(&list, allocator, opts.audio, audio_backend) catch |err| return err;

    try list.append(allocator, try allocator.dupe(u8, "-hda"));
    try list.append(allocator, try allocator.dupe(u8, opts.hda));

    if (opts.iso) |iso| {
        try list.append(allocator, try allocator.dupe(u8, "-cdrom"));
        try list.append(allocator, try allocator.dupe(u8, iso));
    }

    if (opts.boot_cd) {
        try list.append(allocator, try allocator.dupe(u8, "-boot"));
        try list.append(allocator, try allocator.dupe(u8, "d"));
    }

    if (opts.efi) {
        try list.append(allocator, try allocator.dupe(u8, "-bios"));
        try list.append(allocator, try allocator.dupe(u8, bios_path));
    }

    if (opts.cpu_host) {
        try list.append(allocator, try allocator.dupe(u8, "-cpu"));
        try list.append(allocator, try allocator.dupe(u8, "host"));
    }

    if (opts.phys_disk) |path| {
        const drive = try std.fmt.allocPrint(allocator, "file={s},format=raw,media=disk,cache=none", .{path});
        try list.append(allocator, try allocator.dupe(u8, "-drive"));
        try list.append(allocator, drive);
    }

    try list.append(allocator, try allocator.dupe(u8, "-netdev"));
    try list.append(allocator, try allocator.dupe(u8, "user,id=net0"));
    try list.append(allocator, try allocator.dupe(u8, "-device"));
    try list.append(allocator, try allocator.dupe(u8, "virtio-net-pci,netdev=net0"));

    return list.toOwnedSlice(allocator);
}

/// Frees an argv built by `build`.
pub fn freeArgv(allocator: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |arg| allocator.free(arg);
    allocator.free(argv);
}

fn appendAudio(
    list: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    device: AudioDevice,
    backend: system.audio.Backend,
) !void {
    const pa = backend == .pipewire or backend == .pulseaudio;
    switch (device) {
        .intel_hda => {
            try list.append(allocator, try allocator.dupe(u8, "-device"));
            try list.append(allocator, try allocator.dupe(u8, "intel-hda"));
            try list.append(allocator, try allocator.dupe(u8, "-device"));
            try list.append(allocator, try allocator.dupe(u8, "hda-duplex"));
            try list.append(allocator, try allocator.dupe(u8, "-audiodev"));
            try list.append(allocator, try allocator.dupe(u8, if (pa) "pa,id=audio0" else "alsa,id=audio0"));
        },
        .ac97 => {
            try list.append(allocator, try allocator.dupe(u8, "-device"));
            try list.append(allocator, try allocator.dupe(u8, "AC97"));
            try list.append(allocator, try allocator.dupe(u8, "-audiodev"));
            try list.append(allocator, try allocator.dupe(u8, if (pa) "pa,id=audio0" else "alsa,id=audio0"));
        },
        .virtio_sound => {
            try list.append(allocator, try allocator.dupe(u8, "-device"));
            try list.append(allocator, try allocator.dupe(u8, "virtio-sound-pci,audiodev=audio0"));
            try list.append(allocator, try allocator.dupe(u8, "-audiodev"));
            try list.append(allocator, try allocator.dupe(u8, if (pa) "pa,id=audio0" else "alsa,id=audio0"));
        },
        .none => {},
    }
}
