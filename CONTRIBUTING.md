# Contributing to ZigVMU

Thanks for considering contributing. This document covers how to build, what
the project layout is, and the conventions to follow.

## Building

Requirements:

- **Zig** 0.16 or higher
- **GTK3** development libraries (`pkg-config` must find `gtk+-3.0`)
- **QEMU** (AppImage or system binaries) and **OVMF** only needed at runtime

```sh
zig build
./zig-out/bin/zigvmu
```

Format your code before submitting:

```sh
zig fmt src
```

## Project layout

- `src/main.zig` — entry point.
- `src/app.zig` — GtkApplication setup and global CSS.
- `src/config.zig` — configuration loading/saving (`~/.config/ZigVMU/zigvmu.ini`).
- `src/bindings/gtk.zig` — the only module that calls C directly.
- `c/gtk_shim.h` — minimal GTK3 declarations; add new GTK functions here.
- `src/system/` — process execution, audio detection, filesystem helpers.
- `src/qemu/` — QEMU command building and disk creation.
- `src/ui/` — GTK windows and dialogs.
- `launcher` — the original bash/yad launcher, kept as a reference.

## Conventions

- All code, comments and doc comments must be in **English**.
- GTK access happens only through `src/bindings/gtk.zig` and `c/gtk_shim.h`.
  When a GTK function is missing, add its declaration to the shim (opaque
  `GtkWidget *`-based types) instead of importing full GTK headers.
- Child processes must be spawned through `src/system/process.zig`
  (`ioHost`, `runCollect`, `spawnAndWait`) so they inherit the real
  environment. Never use `std.Io.Threaded` directly for spawning.
- Strings returned to the caller are allocated copies; document ownership in
  the doc comment and free them at the call site.
- Keep changes focused. Format with `zig fmt src` and verify with `zig build`
  before submitting.

## Reporting issues

Include:

- Zig version (`zig version`) and OS/desktop environment.
- Whether you are using AppImage or system QEMU mode.
- The exact error message, or the terminal output.
- Steps to reproduce.

## Pull requests

1. Base your branch on `main`.
2. Make one logical change per PR.
3. Verify `zig fmt` and `zig build` pass.
4. Reference the issue you are fixing, if any.
