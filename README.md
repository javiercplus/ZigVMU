# ZigVMU

**QEMU Virtual Machine Launcher**

ZigVMU is a graphical launcher for QEMU written in Zig, providing an easy-to-use GTK3 interface to configure and launch virtual machines. It supports:

- **Virtual disk creation** (qcow2, raw, qed, vdi, vmdk, vpc)
- **Advanced VM configuration** (RAM, CPU, EFI, VirtIO GPU, audio, networking, etc.)
- **AppImage or system binaries mode** (qemu-system-x86_64, qemu-img)
- **Architecture selection** (x86_64, i386, aarch64, arm, riscv64, ppc64)
- **Persistent configuration** saved to `~/.config/ZigVMU/zigvmu.ini`

## Requirements

- **Zig** 0.16 or higher
- **GTK3** (development libraries)
- **QEMU** (AppImage or system binaries)
- **OVMF** (EFI firmware)

## Installation

1. Clone the repository:
   ```sh
   git clone https://github.com/JavierC/zigvmu.git
   cd zigvmu
   ```

2. Build the project:
   ```sh
   zig build
   ```

3. Run the launcher:
   ```sh
   ./zig-out/bin/zigvmu
   ```

## Usage

### Main Window

When you open the launcher, you'll see three options:

- **Launch VM**: Opens the advanced dialog to configure and launch a virtual machine.
- **Create Disk**: Creates a new virtual disk using `qemu-img`.
- **Configuration**: Configures the mode (AppImage or system binaries), QEMU AppImage path, and EFI firmware path.

### Advanced Launch Dialog

In the launch dialog, you can configure:

- **Hard disk image**: Select the virtual hard disk.
- **ISO (CD-ROM)**: Select an ISO to boot from.
- **RAM (MB)**: Memory allocation.
- **CPU cores**: Number of CPU cores.
- **Architecture**: Virtual machine architecture (x86_64, i386, aarch64, etc.).
- **Additional options**: EFI, CPU host passthrough, boot from CD-ROM, physical disk, VirtIO GPU, audio device.

### Configuration Dialog

In the configuration dialog, you can:

- Switch between **AppImage mode** (uses the QEMU AppImage) and **system mode** (uses `qemu-system-x86_64` and `qemu-img` from PATH).
- Select the **QEMU AppImage path** (only in AppImage mode).
- Select the **EFI firmware (OVMF) path**.

Changes are automatically saved to `~/.config/ZigVMU/zigvmu.ini`.

## License

This project is licensed under the **WTFPL** (Do What The Fuck You Want To Public License).

## Authorship

**JavierC**

## Credits

- Based on the original QEMU launcher.
- Uses GTK3 for the graphical interface.
- Written in **Zig** (a modern and safe programming language).

## Support

If you encounter any issues or have suggestions, open an issue in the repository.

---
