const std = @import("std");

const gtk_pkg = "gtk+-3.0";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zigvmu",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.link_libc = true;
    exe.root_module.addIncludePath(b.path("c"));
    linkPkgConfig(exe.root_module, b, gtk_pkg);

    b.installArtifact(exe);
}

/// Links a system library by resolving flags and include paths through
/// pkg-config, in a deterministic way.
fn linkPkgConfig(mod: *std.Build.Module, b: *std.Build, pkg: []const u8) void {
    const cflags = b.run(&.{ "pkg-config", "--cflags", pkg });
    var it = std.mem.tokenizeAny(u8, cflags, " \n");
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-I")) {
            mod.addIncludePath(.{ .cwd_relative = tok[2..] });
        } else if (std.mem.startsWith(u8, tok, "-D")) {
            if (std.mem.indexOfScalar(u8, tok[2..], '=')) |eq| {
                mod.addCMacro(tok[2 .. 2 + eq], tok[2 + eq + 1 ..]);
            } else {
                mod.addCMacro(tok[2..], "1");
            }
        }
    }

    const libs = b.run(&.{ "pkg-config", "--libs", pkg });
    var lit = std.mem.tokenizeAny(u8, libs, " \n");
    while (lit.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-l")) {
            mod.linkSystemLibrary(tok[2..], .{ .use_pkg_config = .no });
        } else if (std.mem.startsWith(u8, tok, "-L")) {
            mod.addLibraryPath(.{ .cwd_relative = tok[2..] });
        }
    }
}
