//! Host audio system detection (PipeWire, PulseAudio, ALSA).

const std = @import("std");
const process = @import("process.zig");

pub const Backend = enum {
    pipewire,
    pulseaudio,
    alsa,
    none,

    pub fn label(self: Backend) []const u8 {
        return switch (self) {
            .pipewire => "PipeWire",
            .pulseaudio => "PulseAudio",
            .alsa => "ALSA",
            .none => "none",
        };
    }
};

/// Detects the available audio backend, with the same logic as the original
/// launcher: PipeWire first, then PulseAudio and finally ALSA.
pub fn detect(allocator: std.mem.Allocator) Backend {
    if (outputContains(allocator, &.{ "pactl", "info" }, "PipeWire")) return .pipewire;
    if (commandSucceeds(allocator, &.{ "pactl", "info" })) return .pulseaudio;
    if (commandSucceeds(allocator, &.{ "aplay", "-l" })) return .alsa;
    return .none;
}

fn commandSucceeds(allocator: std.mem.Allocator, argv: []const []const u8) bool {
    const res = process.runCollect(allocator, argv, 64 * 1024) catch return false;
    defer allocator.free(res.stdout);
    defer allocator.free(res.stderr);
    return process.exitCode(res.term) == 0;
}

fn outputContains(allocator: std.mem.Allocator, argv: []const []const u8, needle: []const u8) bool {
    const res = process.runCollect(allocator, argv, 64 * 1024) catch return false;
    defer allocator.free(res.stdout);
    defer allocator.free(res.stderr);
    if (process.exitCode(res.term) != 0) return false;
    return std.mem.indexOf(u8, res.stdout, needle) != null;
}