#!/bin/bash
# Plugin: Docker Configuration
# Phase: cyberpentester-security

# shellcheck disable=SC2034
PLUGIN_NAME="Docker"
PLUGIN_DESCRIPTION="Installs and configures Docker for containerized pentesting tools"
PLUGIN_PHASE="cyberpentester-security"
PLUGIN_DEPENDENCIES=()

# shellcheck disable=SC1091
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/../lib/log.sh" 2>/dev/null || true

plugin_check() {
    return 0
}

plugin_run() {
    local ROOT_MOUNT="$1"
    
    log_info "Installing and configuring Docker..."
    
    # Install Docker
    if ! systemd-nspawn -D "$ROOT_MOUNT" pacman -S --noconfirm docker docker-compose; then
        log_error "Failed to install Docker"
        return 1
    fi
    
    # Enable Docker service
    systemd-nspawn -D "$ROOT_MOUNT" systemctl enable docker.service
    
    # Configure Docker daemon
    mkdir -p "$ROOT_MOUNT/etc/docker"
    cat > "$ROOT_MOUNT/etc/docker/daemon.json" <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "userland-proxy": false,
  "experimental": false,
  "live-restore": true
}
EOF
    
    # Create docker group (user will be added by user plugin)
    systemd-nspawn -D "$ROOT_MOUNT" groupadd -f docker
    
    # Create Docker helper scripts
    log_info "Creating Docker helper scripts..."
    
    # Kali Linux container script
    cat > "$ROOT_MOUNT/usr/local/bin/docker-kali.sh" <<'EOF'
#!/bin/bash
# Launch Kali Linux Docker container with common pentesting tools

CONTAINER_NAME="kali-pentesting"

# Check if container exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Starting existing Kali container..."
    docker start -i "$CONTAINER_NAME"
else
    echo "Creating new Kali Linux container..."
    echo "This may take a while on first run..."
    docker run -it \
        --name "$CONTAINER_NAME" \
        --hostname kali-docker \
        --network host \
        --privileged \
        -v /dev:/dev \
        -v "$HOME/kali-shared:/root/shared" \
        kalilinux/kali-rolling /bin/bash
fi
EOF
    
    chmod +x "$ROOT_MOUNT/usr/local/bin/docker-kali.sh"
    
    # ParrotOS container script
    cat > "$ROOT_MOUNT/usr/local/bin/docker-parrot.sh" <<'EOF'
#!/bin/bash
# Launch ParrotOS Docker container

CONTAINER_NAME="parrot-pentesting"

# Check if container exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Starting existing ParrotOS container..."
    docker start -i "$CONTAINER_NAME"
else
    echo "Creating new ParrotOS container..."
    docker run -it \
        --name "$CONTAINER_NAME" \
        --hostname parrot-docker \
        --network host \
        --privileged \
        -v /dev:/dev \
        -v "$HOME/parrot-shared:/root/shared" \
        parrotsec/security /bin/bash
fi
EOF
    
    chmod +x "$ROOT_MOUNT/usr/local/bin/docker-parrot.sh"
    
    # Docker pentesting toolkit
    cat > "$ROOT_MOUNT/usr/local/bin/docker-pentesting-tools.sh" <<'EOF'
#!/bin/bash
# Quick access to pentesting tools via Docker

show_menu() {
    echo "Docker Pentesting Tools"
    echo "======================="
    echo "1. Kali Linux (full)"
    echo "2. ParrotOS Security"
    echo "3. Metasploit Framework"
    echo "4. Burp Suite (community)"
    echo "5. OWASP ZAP"
    echo "6. SQLMap"
    echo "7. Nmap (official)"
    echo "8. Wireshark"
    echo "9. Cleanup containers"
    echo "0. Exit"
    echo ""
}

run_tool() {
    case $1 in
        1)
            docker-kali.sh
            ;;
        2)
            docker-parrot.sh
            ;;
        3)
            docker run --rm -it \
                --network host \
                metasploitframework/metasploit-framework
            ;;
        4)
            echo "Burp Suite Community - visit http://localhost:8080"
            docker run --rm -p 8080:8080 \
                openjdk:11 java -jar /opt/burpsuite_community.jar
            ;;
        5)
            echo "OWASP ZAP - visit http://localhost:8080"
            docker run --rm -p 8080:8080 \
                owasp/zap2docker-stable zap-webswing.sh
            ;;
        6)
            docker run --rm -it \
                --network host \
                peterevans/sqlmap "$@"
            ;;
        7)
            docker run --rm -it \
                --network host \
                instrumentisto/nmap "$@"
            ;;
        8)
            docker run --rm -it \
                --network host \
                --privileged \
                -v /tmp/.X11-unix:/tmp/.X11-unix \
                -e DISPLAY="$DISPLAY" \
                linuxserver/wireshark
            ;;
        9)
            echo "Cleaning up stopped containers..."
            docker container prune -f
            echo "Cleaning up unused images..."
            docker image prune -f
            ;;
        0)
            exit 0
            ;;
        *)
            echo "Invalid option"
            ;;
    esac
}

if [[ $# -eq 0 ]]; then
    while true; do
        show_menu
        read -r -p "Select tool: " choice
        run_tool "$choice"
        echo ""
        read -r -p "Press Enter to continue..."
    done
else
    run_tool "$@"
fi
EOF
    
    chmod +x "$ROOT_MOUNT/usr/local/bin/docker-pentesting-tools.sh"
    
    # Create Docker reference guide
    cat > "$ROOT_MOUNT/usr/local/share/docker-pentesting-reference.txt" <<'EOF'
Docker Pentesting Reference
===========================

Quick Access Scripts:
  docker-kali.sh                   - Kali Linux container
  docker-parrot.sh                 - ParrotOS container
  docker-pentesting-tools.sh       - Interactive tool menu

Common Docker Commands:
  docker ps                        - List running containers
  docker ps -a                     - List all containers
  docker images                    - List images
  docker pull <image>              - Pull image
  docker run -it <image> /bin/bash - Run interactive container
  docker exec -it <container> bash - Attach to running container
  docker stop <container>          - Stop container
  docker rm <container>            - Remove container
  docker rmi <image>               - Remove image

Useful Pentesting Images:
  kalilinux/kali-rolling           - Kali Linux
  parrotsec/security               - ParrotOS
  metasploitframework/metasploit-framework
  owasp/zap2docker-stable          - OWASP ZAP
  peterevans/sqlmap                - SQLMap
  instrumentisto/nmap              - Nmap

Container Networking:
  --network host                   - Use host network (for wireless tools)
  --network bridge                 - Isolated network
  -p 8080:80                       - Port forward

Privileged Access (for hardware):
  --privileged                     - Full access
  -v /dev:/dev                     - Mount devices
  --cap-add=NET_ADMIN              - Network admin capability

Data Sharing:
  -v /path/host:/path/container    - Mount volume
  --volumes-from <container>       - Share volumes

Notes:
- Use --network host for WiFi/BLE pentesting tools
- Use --privileged for hardware access (RTL-SDR, WiFi adapters)
- Shared directories: ~/kali-shared, ~/parrot-shared
- Always ensure proper authorization before testing
EOF
    
    log_info "Docker configuration complete"
    log_info "Helper scripts: docker-kali.sh, docker-parrot.sh, docker-pentesting-tools.sh"
    log_info "User will be added to docker group by user plugin"
    
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    plugin_run "${1:-/mnt/root}"
fi
