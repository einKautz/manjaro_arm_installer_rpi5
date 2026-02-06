# Critical GLIBC/ABI Mismatch Issue - Manjaro Pi 5 Installer

## Problem Summary

The Manjaro Pi 5 installer fails on x86_64 hosts due to **ABI incompatibility** between:
- Host system libraries (older GLIBC 2.35-2.37, older OpenSSL, older systemd)
- ARM rootfs libraries (GLIBC 2.39, OpenSSL 3.4.0, systemd 257)

## Root Cause

When `systemd-nspawn` chroots into the ARM rootfs:
1. ARM binaries execute
2. They dynamically link against **host system libraries** (not rootfs libraries)
3. Host libraries are too old
4. Result: **Binary execution fails**

### Specific Failures

```
systemd-sysusers: /usr/lib/libc.so.6: version `GLIBC_2.39' not found
journalctl: /usr/lib/libc.so.6: version `GLIBC_2.38' not found
mkinitcpio: GLIBC version errors
depmod: /usr/lib/libc.so.6: version `GLIBC_2.38' not found
```

This cascades into:
- ❌ No initramfs generation
- ❌ No kernel8.img creation
- ❌ Incomplete boot partition
- ❌ Unbootable system

---

## Solution 1: Run in Manjaro ARM Container (RECOMMENDED)

This is the **only reliable cross-architecture solution**.

### Prerequisites

```bash
# On your x86_64 host
sudo pacman -S qemu-user-static-binfmt docker
sudo systemctl enable --now docker
```

### Steps

```bash
# 1. Pull Manjaro ARM base image
docker pull manjaroarm/base:latest

# 2. Run installer in container with device passthrough
docker run -it --privileged \
  -v /dev:/dev \
  -v $PWD:/installer \
  manjaroarm/base:latest \
  bash /installer/manjaro-pi5-installer-v2_5.sh
```

### Why This Works

Inside the container:
- ✅ ARM GLIBC 2.39 matches rootfs
- ✅ ARM systemd 257 matches rootfs
- ✅ ARM OpenSSL 3.4 matches rootfs
- ✅ All binaries execute correctly
- ✅ mkinitcpio generates initramfs
- ✅ kernel8.img is created
- ✅ Boot partition is complete

---

## Solution 2: Use Native ARM Host

Run the installer on:
- Another Raspberry Pi (any ARM64 model)
- ARM-based cloud instance (AWS Graviton, Oracle ARM, etc.)
- ARM Linux VM (QEMU with KVM on ARM host)

---

## Solution 3: Upgrade Host System (Partial Fix)

**Warning**: This only works if your host distro has the required package versions.

```bash
# Manjaro/Arch hosts
sudo pacman -Syu

# Check versions
ldd --version  # Should show GLIBC 2.39+
openssl version  # Should show 3.4.0+
```

**Limitations**: Still requires QEMU user emulation for ARM binaries.

---

## Implementation: Add Compatibility Check

Add this to the beginning of your installer script:

```bash
check_host_compatibility() {
    local required_glibc="2.39"
    local host_glibc
    host_glibc=$(ldd --version 2>/dev/null | head -n1 | awk '{print $NF}')
    
    if [[ "$(printf '%s\n' "$required_glibc" "$host_glibc" | sort -V | head -n1)" != "$required_glibc" ]]; then
        cat << 'EOF'
════════════════════════════════════════════════════════════════════
  HOST SYSTEM INCOMPATIBILITY DETECTED
════════════════════════════════════════════════════════════════════

Your host has GLIBC $host_glibc but ARM rootfs requires $required_glibc

This causes:
  ✗ systemd-sysusers crashes
  ✗ mkinitcpio fails
  ✗ kernel8.img is not created
  ✗ boot partition remains incomplete

SOLUTION: Run installer in Manjaro ARM container:

  sudo pacman -S qemu-user-static-binfmt docker
  docker pull manjaroarm/base:latest
  docker run -it --privileged \
    -v /dev:/dev \
    -v $PWD:/installer \
    manjaroarm/base:latest \
    bash /installer/manjaro-pi5-installer-v2_5.sh

════════════════════════════════════════════════════════════════════
EOF
        exit 1
    fi
    
    # Check for ARM emulation
    local host_arch
    host_arch=$(uname -m)
    if [[ "$host_arch" == "x86_64" ]]; then
        if [[ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
            echo "ERROR: ARM emulation not available"
            echo "Install: sudo pacman -S qemu-user-static-binfmt"
            exit 1
        fi
    fi
}

# Run at script start
check_host_compatibility
```

---

## Technical Details

### Why systemd-nspawn Doesn't Isolate Libraries

`systemd-nspawn` creates a chroot but does **not** provide full containerization:
- It chroots the filesystem (rootfs appears different)
- But dynamic linker still uses **host's ld-linux**
- Host's ld-linux loads **host's glibc**
- ARM binaries request symbols from **target glibc**
- Host glibc doesn't have those symbols
- **Result: Symbol not found errors**

### Docker/Podman Difference

Docker with QEMU user emulation:
- Uses `qemu-aarch64-static` to execute ARM binaries
- QEMU intercepts syscalls and translates them
- Dynamic linker runs **inside** the ARM rootfs
- Links against **ARM rootfs libraries**
- **Result: Everything works correctly**

---

## Verification After Installation

After running the installer (in container), verify:

```bash
# Check boot partition contents
ls -lh /tmp/manjaro-installer/root/boot/

# Should contain:
# - kernel8.img (Linux kernel)
# - bcm2712-rpi-5-b.dtb (Device tree)
# - config.txt (Boot config)
# - cmdline.txt (Kernel params)
# - overlays/ directory (DTB overlays)
# - *.dat, *.elf (Firmware files)
```

---

## Summary

| Method | Reliability | Speed | Setup Complexity |
|--------|-------------|-------|------------------|
| ARM Container | ✅ 100% | Fast | Medium (one-time Docker setup) |
| Native ARM Host | ✅ 100% | Fastest | None (if you have ARM hardware) |
| Upgraded x86_64 Host | ⚠️ 50% | Fast | Low (but may not work) |

**Recommendation**: Always use the ARM container method for cross-architecture builds.

---

## Additional Resources

- [systemd-nspawn documentation](https://www.freedesktop.org/software/systemd/man/systemd-nspawn.html)
- [QEMU user emulation](https://wiki.archlinux.org/title/QEMU#Chrooting_into_arm/arm64_environment_from_x86_64)
- [binfmt_misc](https://docs.kernel.org/admin-guide/binfmt-misc.html)
