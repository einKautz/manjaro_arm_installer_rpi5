#!/bin/bash
# Plugin: Security Hardening
# Phase: cyberpentester-security

# shellcheck disable=SC2034
PLUGIN_NAME="Security Hardening"
PLUGIN_DESCRIPTION="Applies security hardening for cyberdeck operation"
PLUGIN_PHASE="cyberpentester-security"
PLUGIN_DEPENDENCIES=()

# shellcheck disable=SC1091
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/../lib/log.sh" 2>/dev/null || true

plugin_check() {
    return 0
}

plugin_run() {
    local ROOT_MOUNT="$1"
    
    log_info "Applying security hardening..."
    
    # Install security packages
    if ! systemd-nspawn -D "$ROOT_MOUNT" pacman -S --noconfirm ufw fail2ban; then
        log_error "Failed to install security packages"
        return 1
    fi
    
    # Configure UFW firewall
    log_info "Configuring UFW firewall..."
    
    # Enable UFW service
    systemd-nspawn -D "$ROOT_MOUNT" systemctl enable ufw.service
    
    # Create UFW configuration script to run on first boot
    cat > "$ROOT_MOUNT/usr/local/bin/configure-firewall.sh" <<'EOF'
#!/bin/bash
# Configure UFW firewall

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow ssh

# Allow mDNS for network discovery
ufw allow 5353/udp

# Enable firewall
ufw --force enable

echo "Firewall configured and enabled"
EOF
    
    chmod +x "$ROOT_MOUNT/usr/local/bin/configure-firewall.sh"
    
    # Configure Fail2Ban
    log_info "Configuring Fail2Ban..."
    
    cat > "$ROOT_MOUNT/etc/fail2ban/jail.local" <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_mw)s

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF
    
    # Enable Fail2Ban
    systemd-nspawn -D "$ROOT_MOUNT" systemctl enable fail2ban.service
    
    # Configure SSH hardening
    log_info "Hardening SSH configuration..."
    
    if [[ -f "$ROOT_MOUNT/etc/ssh/sshd_config" ]]; then
        # Backup original
        cp "$ROOT_MOUNT/etc/ssh/sshd_config" "$ROOT_MOUNT/etc/ssh/sshd_config.bak"
        
        # Apply hardening
        cat >> "$ROOT_MOUNT/etc/ssh/sshd_config" <<'EOF'

# Security Hardening
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/ssh/sftp-server

# Disable weak ciphers and algorithms
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256
EOF
    fi
    
    # Configure MAC randomization for privacy
    log_info "Configuring MAC randomization..."
    
    mkdir -p "$ROOT_MOUNT/etc/NetworkManager/conf.d"
    cat > "$ROOT_MOUNT/etc/NetworkManager/conf.d/wifi-mac-randomization.conf" <<'EOF'
[device]
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=random
ethernet.cloned-mac-address=random
EOF
    
    # Configure sysctl hardening
    log_info "Applying sysctl hardening..."
    
    cat > "$ROOT_MOUNT/etc/sysctl.d/99-security-hardening.conf" <<'EOF'
# IP Forwarding (disabled by default, enable for pentesting if needed)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Ignore source routed packets
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Log martian packets
net.ipv4.conf.all.log_martians = 1

# Ignore ICMP ping requests (optional - commented out for debugging)
# net.ipv4.icmp_echo_ignore_all = 1

# Protect against time-wait assassination
net.ipv4.tcp_rfc1337 = 1

# Kernel hardening
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1

# Disable magic SysRq key
kernel.sysrq = 0
EOF
    
    # Create security notes
    cat > "$ROOT_MOUNT/root/SECURITY_NOTES.txt" <<'EOF'
Security Hardening Applied
==========================

Firewall (UFW):
- Default deny incoming, allow outgoing
- SSH allowed (port 22)
- Configure with: sudo ufw status

Fail2Ban:
- Enabled for SSH brute force protection
- Ban time: 1 hour
- Max retries: 5 within 10 minutes

SSH Hardening:
- Root login disabled
- Weak ciphers disabled
- Strong key exchange algorithms enforced
- Configuration: /etc/ssh/sshd_config

MAC Randomization:
- WiFi MAC randomized for privacy
- Ethernet MAC randomized
- Configuration: /etc/NetworkManager/conf.d/wifi-mac-randomization.conf

For Pentesting:
- Enable IP forwarding if needed: sysctl -w net.ipv4.ip_forward=1
- Disable MAC randomization if needed: nmcli connection modify <conn> 802-11-wireless.cloned-mac-address ""
- Adjust firewall rules as needed: ufw allow <port>/<protocol>

Remember:
- Use these tools responsibly and legally
- Always obtain proper authorization before testing
- Follow responsible disclosure practices
EOF
    
    log_info "Security hardening complete"
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    plugin_run "${1:-/mnt/root}"
fi
