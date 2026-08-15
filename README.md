# ZigVMU

A graphical **QEMU virtual machine launcher** written in **Zig** with a GTK3 interface.

## Features

- Virtual disk creation (qcow2, raw, qed, vdi, vmdk, vpc)
- VM configuration: RAM, CPU cores, EFI, VirtIO GPU, audio, networking
- AppImage or system QEMU binaries (`qemu-system-*`, `qemu-img`)
- Architectures: x86_64, i386, aarch64, arm, riscv64, ppc64
- Persistent config in `~/.config/ZigVMU/zigvmu.ini`

## Requirements

- Zig 0.16+
- GTK3 (dev libraries)
- QEMU (AppImage or system binaries) and OVMF at runtime

## Build & run

```sh
zig build
./zig-out/bin/zigvmu
```

## Configuration

Set the QEMU mode (AppImage/system), AppImage path and EFI firmware path from
the **Configuration** dialog. All options are also overridable via
`ZIGVMU_QEMU`, `ZIGVMU_BIOS` and `ZIGVMU_MODE`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License & authors

**WTFPL** (see [LICENSE](LICENSE)) — Author: **JavierC**.
