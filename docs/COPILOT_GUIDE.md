# 📘 **copilot_guide.md**
### _AI Autocomplete Guide for the Manjaro ARM Pi 5 Installer_

## 🧭 Purpose
This guide teaches GitHub Copilot how to correctly autocomplete, extend, and maintain the **Manjaro ARM Pi 5 Installer** and its **container wrapper**.  
Copilot should treat this document as the authoritative reference for:

- coding style  
- architecture patterns  
- error handling  
- TUI design  
- container execution  
- boot partition logic  
- ARM‑correct behavior  

---

# 🏗️ 1. Core Principles Copilot Must Follow

### ✔ Always assume:
- The installer **must run inside a Manjaro ARM container** unless explicitly overridden.
- The host system may be x86_64 and ABI‑incompatible.
- Boot partition population must use **multi‑strategy fallback**:
  1. Boot tarball  
  2. Full image extraction  
  3. Bootloader packages  

### ✔ All scripts must:
- use `set -euo pipefail`
- log clearly with timestamps
- avoid silent failures
- verify every critical step
- use modular functions
- return non‑zero on failure
- use `dialog` for TUI menus
- use container‑safe operations

### ✔ Xorg must use:
- **automatic KMS detection**
- **no forced BusID**
- **no Pi 4‑specific configs**

---

# 🧩 2. Patterns Copilot Should Use

### ✔ Logging
```bash
log() { printf "[%s] [%s] %s\n" "$(date '+%F %T')" "$1" "$2"; }
log INFO "Starting boot verification"
log ERROR "kernel8.img missing"
```

### ✔ Error Handling
```bash
if ! some_command; then
    log ERROR "some_command failed"
    return 1
fi
```

### ✔ TUI Menu
```bash
choice=$(dialog --menu "Network Settings" 20 60 10 \
    1 "Scan Wi-Fi" \
    2 "Enter Password" \
    3 "Connect" \
    4 "Test Internet" \
    5 "Back" \
    3>&1 1>&2 2>&3)
```

### ✔ Container Execution
```bash
docker run -it --rm --privileged \
  -v /dev:/dev \
  -v "$SCRIPT_DIR:/installer" \
  manjaroarm/base:latest \
  bash -c "cd /installer && bash manjaro-pi5-installer.sh"
```

### ✔ Host GLIBC Check
```bash
host_glibc=$(ldd --version | head -n1 | awk '{print $NF}')
required_glibc="2.39"

if [[ "$(printf '%s\n' "$required_glibc" "$host_glibc" | sort -V | head -n1)" != "$required_glibc" ]]; then
    dialog --msgbox "Host GLIBC too old. Use container wrapper." 12 60
    exit 1
fi
```

---

# 📦 3. Files Copilot Should Know Exist

### Installer
- `manjaro-pi5-installer-v2_6.sh`

### Container Wrapper
- `manjaro-pi5-container-wrapper.sh`

### Documentation
- `docs/boot-verification.md`
- `docs/network-tui.md`
- `docs/container-mode.md`

---

# 🔧 4. Tasks Copilot Should Autocomplete Correctly

### ✔ Boot Partition Logic
- detect missing kernel8.img  
- detect missing DTB  
- detect missing overlays  
- auto‑repair using fallback strategies  
- patch PARTUUID into cmdline.txt  

### ✔ Network TUI
- scan SSIDs  
- prompt for password  
- connect via nmcli  
- test connectivity  
- show status  

### ✔ Container Wrapper
- detect docker/podman  
- detect qemu-user-static-binfmt  
- mount installer directory  
- run installer inside ARM container  

### ✔ Host Compatibility
- detect GLIBC mismatch  
- warn user  
- redirect to container wrapper  

---

# 🚫 5. Things Copilot Should NOT Generate

- No forced Xorg BusID  
- No Pi 4 overlays  
- No direct chroot without ARM emulation  
- No mkinitcpio hooks assuming x86_64  
- No systemd commands outside container context  

---

# 🚀 6. Phase 3 Preparation
Copilot should be ready to help build:

- plugin‑driven architecture  
- modular boot strategies  
- advanced diagnostics  
- profile‑based installation modes  
- cyberdeck‑ready overlays  
- Pi 5 hardware abstraction layer  

---

# 🏁 7. Final Instruction to Copilot
> **When autocompleting any script in this repository, follow the patterns, rules, and architecture defined in this guide.  
> Prefer modular Bash, clear logging, container‑safe operations, and ARM‑correct behavior.  
> Never assume x86_64 compatibility.  
> Always prioritize reproducibility and correctness.**  