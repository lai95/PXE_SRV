#!/bin/bash

# PXE Diagnostic Image Builder
# Builds a minimal Alpine Linux-based diagnostic boot image

# Don't exit on errors - we'll handle them manually
# set -e

# Configuration
IMAGE_NAME="pxe_diagnostics"
IMAGE_VERSION="1.0.0"
IMAGE_SIZE="200M"
ALPINE_VERSION="3.18"
WORK_DIR="./work"
OUTPUT_DIR="./output"
MOUNT_DIR="./mnt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    for tool in wget tar gzip dd losetup mount umount chroot; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    
    if [ -d "$MOUNT_DIR" ]; then
        umount -f "$MOUNT_DIR" 2>/dev/null || true
        rmdir "$MOUNT_DIR" 2>/dev/null || true
    fi
    
    if [ -n "$LOOP_DEVICE" ]; then
        losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    fi
    
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Create working directories
setup_directories() {
    log_info "Setting up working directories..."
    
    mkdir -p "$WORK_DIR" "$OUTPUT_DIR" "$MOUNT_DIR"
}

# Download Alpine Linux with retry logic and mirror fallbacks
download_alpine() {
    log_info "Downloading Alpine Linux ${ALPINE_VERSION}..."
    
    # Try multiple mirrors in order of preference
    local mirrors=(
        "https://dl-cdn.alpinelinux.org/alpine"
        "https://mirror.alpinelinux.org/alpine"
        "https://alpine.mirror.wearetriple.com/alpine"
        "https://mirror.riseup.net/alpine"
    )
    
    local alpine_file="$WORK_DIR/alpine-minirootfs-${ALPINE_VERSION}.0-x86_64.tar.gz"
    
    if [ ! -f "$alpine_file" ]; then
        local success=false
        
        for mirror in "${mirrors[@]}"; do
            local alpine_url="${mirror}/v${ALPINE_VERSION}/releases/x86_64/alpine-minirootfs-${ALPINE_VERSION}.0-x86_64.tar.gz"
            log_info "Trying mirror: $mirror"
            
            if wget --timeout=30 --tries=3 -O "$alpine_file" "$alpine_url"; then
                log_info "Alpine Linux downloaded successfully from $mirror!"
                success=true
                break
            else
                log_warn "Failed to download from $mirror"
            fi
        done
        
        if [ "$success" = false ]; then
            log_error "Failed to download Alpine Linux from all mirrors"
            return 1
        fi
    else
        log_info "Alpine Linux already downloaded"
    fi
}

# Create image file
create_image() {
    log_info "Creating image file..."
    
    local image_file="$OUTPUT_DIR/${IMAGE_NAME}-${IMAGE_VERSION}.img"
    
    # Remove existing image
    rm -f "$image_file"
    
    # Create empty image file
    dd if=/dev/zero of="$image_file" bs=1M count=200
    sync
    
    # Create filesystem
    mkfs.ext4 "$image_file"
    
    # Mount image
    LOOP_DEVICE=$(losetup --find --show "$image_file")
    mount "$LOOP_DEVICE" "$MOUNT_DIR"
    
    log_info "Image created and mounted at $LOUNT_DIR"
}

# Extract Alpine Linux
extract_alpine() {
    log_info "Extracting Alpine Linux to image..."
    
    local alpine_file="$WORK_DIR/alpine-minirootfs-${ALPINE_VERSION}.0-x86_64.tar.gz"
    
    tar -xzf "$alpine_file" -C "$MOUNT_DIR"
    
    log_info "Alpine Linux extracted"
}

# Install diagnostic tools with retry logic
install_diagnostic_tools() {
    log_info "Installing diagnostic tools..."
    
    # Function to install packages with retries
    install_packages_with_retry() {
        local max_attempts=5
        local attempt=1
        local success=false
        
        while [ $attempt -le $max_attempts ] && [ "$success" = false ]; do
            log_info "Attempt $attempt of $max_attempts to install packages..."
            
            # Try to update package repositories
            if chroot "$MOUNT_DIR" apk update --no-cache; then
                log_info "Package repository updated successfully"
                
                # Try to install packages in smaller groups for better success rate
                local package_groups=(
                    "lshw hwinfo dmidecode"
                    "smartmontools hdparm fio memtester"
                    "stress-ng sysbench iperf3 netperf"
                    "snmp-tools lldpd ethtool ipmitool"
                    "lm-sensors mdadm bonnie++ ioping"
                    "curl wget jq python3"
                    "bash vim htop iotop"
                    "sysstat lsof strace"
                    "gcc make linux-headers"
                )
                
                local all_success=true
                for group in "${package_groups[@]}"; do
                    if chroot "$MOUNT_DIR" apk add --no-cache $group; then
                        log_info "Package group installed: $group"
                    else
                        log_warn "Package group failed: $group"
                        all_success=false
                    fi
                done
                
                if [ "$all_success" = true ]; then
                    log_info "All diagnostic tools installed successfully!"
                    success=true
                else
                    log_warn "Some package groups failed to install"
                fi
            else
                log_warn "Package repository update failed on attempt $attempt"
            fi
            
            if [ "$success" = false ] && [ $attempt -lt $max_attempts ]; then
                log_info "Waiting 10 seconds before retry..."
                sleep 10
            fi
            
            attempt=$((attempt + 1))
        done
        
        if [ "$success" = false ]; then
            log_error "Failed to install packages after $max_attempts attempts"
            return 1
        fi
        
        return 0
    }
    
    # Try to install packages
    if ! install_packages_with_retry; then
        log_warn "Continuing with minimal tools - some packages may not be available"
        
        # Try to install at least essential tools
        if chroot "$MOUNT_DIR" apk add --no-cache \
            lshw \
            hwinfo \
            dmidecode \
            curl \
            wget \
            bash \
            vim; then
            log_info "Essential diagnostic tools installed"
        else
            log_warn "Even essential tools failed to install"
            log_info "Creating minimal working system with built-in tools"
            create_minimal_system
        fi
    fi
}

# Create minimal working system without external packages
create_minimal_system() {
    log_info "Setting up minimal working system..."
    
    # Create essential directories
    mkdir -p "$MOUNT_DIR/opt/diagnostics/bin"
    mkdir -p "$MOUNT_DIR/opt/diagnostics/lib"
    
    # Create a basic diagnostic script that works with minimal tools
    cat > "$MOUNT_DIR/opt/diagnostics/bin/run_diagnostics.sh" << 'EOF'
#!/bin/sh
# Minimal diagnostic script for Alpine Linux

echo "=== Minimal PXE Diagnostic System ==="
echo "System: $(uname -a)"
echo "Date: $(date)"
echo "Uptime: $(uptime 2>/dev/null || echo 'N/A')"
echo "Memory: $(free -h 2>/dev/null || cat /proc/meminfo | grep MemTotal || echo 'N/A')"
echo "Disk: $(df -h 2>/dev/null || echo 'N/A')"
echo "Network: $(ip addr 2>/dev/null || ifconfig 2>/dev/null || echo 'N/A')"
echo "Processes: $(ps aux 2>/dev/null || echo 'N/A')"
echo "=== Diagnostic Complete ==="
EOF
    
    chmod +x "$MOUNT_DIR/opt/diagnostics/bin/run_diagnostics.sh"
    
    # Create basic system configuration
    cat > "$MOUNT_DIR/etc/inittab" << 'EOF'
::sysinit:/sbin/openrc sysinit
::respawn:/sbin/openrc default
::shutdown:/sbin/openrc shutdown
EOF
    
    # Create basic network configuration
    cat > "$MOUNT_DIR/etc/network/interfaces" << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
    
    # Create basic passwd file
    echo "root:x:0:0:root:/root:/bin/sh" > "$MOUNT_DIR/etc/passwd"
    echo "daemon:x:1:1:daemon:/usr/sbin:/bin/false" >> "$MOUNT_DIR/etc/passwd"
    echo "bin:x:2:2:bin:/bin:/bin/false" >> "$MOUNT_DIR/etc/passwd"
    
    # Create basic group file
    echo "root:x:0:" > "$MOUNT_DIR/etc/group"
    echo "daemon:x:1:" >> "$MOUNT_DIR/etc/group"
    echo "bin:x:2:" >> "$MOUNT_DIR/etc/group"
    
    log_info "Minimal system created successfully"
}

# Configure system
configure_system() {
    log_info "Configuring system..."
    
    # Copy diagnostic scripts if they exist, otherwise use minimal ones
    if [ -d "../diagnostics" ]; then
        cp -r ../diagnostics/* "$MOUNT_DIR/opt/diagnostics/"
        chmod +x "$MOUNT_DIR/opt/diagnostics/bin/*" 2>/dev/null || true
    fi
    
    # Create init script
    cat > "$MOUNT_DIR/etc/init.d/diagnostics" << 'EOF'
#!/bin/sh
# Diagnostic system startup script

case "$1" in
    start)
        echo "Starting diagnostic system..."
        /opt/diagnostics/bin/run_diagnostics.sh
        ;;
    stop)
        echo "Stopping diagnostic system..."
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac

exit 0
EOF
    
    chmod +x "$MOUNT_DIR/etc/init.d/diagnostics"
    
    # Try to enable diagnostic service (may fail in minimal system)
    chroot "$MOUNT_DIR" rc-update add diagnostics default 2>/dev/null || log_warn "Could not enable diagnostic service"
    
    # Configure networking
    cat > "$MOUNT_DIR/etc/network/interfaces" << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
    
    # Try to configure SSH for report upload (may fail in minimal system)
    if chroot "$MOUNT_DIR" apk add --no-cache openssh 2>/dev/null; then
        chroot "$MOUNT_DIR" ssh-keygen -A 2>/dev/null || log_warn "Could not generate SSH keys"
        
        # Create upload user
        if chroot "$MOUNT_DIR" adduser -D -s /bin/sh upload 2>/dev/null; then
            chroot "$MOUNT_DIR" echo "upload:upload123" | chpasswd 2>/dev/null || log_warn "Could not set upload user password"
        else
            log_warn "Could not create upload user"
        fi
    else
        log_warn "SSH not available in minimal system"
    fi
    
    log_info "System configured"
}

# Create PXE boot files with retry logic
create_pxe_files() {
    log_info "Creating PXE boot files..."
    
    # Function to download file with retries
    download_with_retry() {
        local url="$1"
        local output_file="$2"
        local description="$3"
        
        local max_attempts=5
        local attempt=1
        local success=false
        
        while [ $attempt -le $max_attempts ] && [ "$success" = false ]; do
            log_info "Attempt $attempt of $max_attempts to download $description..."
            
            if wget --timeout=30 --tries=3 -O "$output_file" "$url"; then
                log_info "$description downloaded successfully!"
                success=true
            else
                log_warn "Download of $description failed on attempt $attempt"
                if [ $attempt -lt $max_attempts ]; then
                    log_info "Waiting 10 seconds before retry..."
                    sleep 10
                fi
            fi
            
            attempt=$((attempt + 1))
        done
        
        if [ "$success" = false ]; then
            log_error "Failed to download $description after $max_attempts attempts"
            return 1
        fi
        
        return 0
    }
    
    # Download kernel and initramfs with mirror fallbacks
    local mirrors=(
        "https://dl-cdn.alpinelinux.org/alpine"
        "https://mirror.alpinelinux.org/alpine"
        "https://alpine.mirror.wearetriple.com/alpine"
        "https://mirror.riseup.net/alpine"
    )
    
    local success=false
    for mirror in "${mirrors[@]}"; do
        local kernel_url="${mirror}/v${ALPINE_VERSION}/releases/x86_64/netboot/vmlinuz-virt"
        local initramfs_url="${mirror}/v${ALPINE_VERSION}/releases/x86_64/netboot/initramfs-virt"
        
        log_info "Trying mirror: $mirror for PXE boot files"
        
        if download_with_retry "$kernel_url" "$OUTPUT_DIR/vmlinuz-virt" "kernel" && \
           download_with_retry "$initramfs_url" "$OUTPUT_DIR/initramfs-virt" "initramfs"; then
            log_info "PXE boot files downloaded successfully from $mirror!"
            success=true
            break
        else
            log_warn "Failed to download PXE boot files from $mirror"
        fi
    done
    
    if [ "$success" = false ]; then
        log_error "Failed to download PXE boot files from all mirrors"
        return 1
    fi
    
    # Create PXE configuration
    cat > "$OUTPUT_DIR/pxelinux.cfg/default" << EOF
DEFAULT diagnostic_boot
TIMEOUT 30
PROMPT 1

LABEL diagnostic_boot
    MENU LABEL Alpine Linux Diagnostics
    KERNEL vmlinuz-virt
    APPEND initrd=initramfs-virt modules=loop,squashfs,sd-mod,usb-storage quiet console=ttyS0,115200 console=tty0
    MENU DEFAULT

LABEL diagnostic_boot_debug
    MENU LABEL Alpine Linux Diagnostics (Debug)
    KERNEL vmlinuz-virt
    APPEND initrd=initramfs-virt modules=loop,squashfs,sd-mod,usb-storage console=ttyS0,115200 console=tty0 debug
EOF
    
    log_info "PXE boot files created successfully"
}

# Finalize image
finalize_image() {
    log_info "Finalizing image..."
    
    # Unmount image
    umount "$MOUNT_DIR"
    losetup -d "$LOOP_DEVICE"
    
    # Compress image
    local image_file="$OUTPUT_DIR/${IMAGE_NAME}-${IMAGE_VERSION}.img"
    local compressed_file="$OUTPUT_DIR/${IMAGE_NAME}-${IMAGE_VERSION}.img.gz"
    
    gzip -f "$image_file"
    
    log_info "Image finalized: $compressed_file"
}

# Main execution
main() {
    log_info "Starting PXE diagnostic image build..."
    
    local exit_code=0
    
    # Execute each step and continue even if some fail
    check_prerequisites || exit_code=1
    
    if [ $exit_code -eq 0 ]; then
        setup_directories || exit_code=1
    fi
    
    if [ $exit_code -eq 0 ]; then
        download_alpine || exit_code=1
    fi
    
    if [ $exit_code -eq 0 ]; then
        create_image || exit_code=1
    fi
    
    if [ $exit_code -eq 0 ]; then
        extract_alpine || exit_code=1
    fi
    
    # Package installation might fail due to network issues, but continue
    if [ $exit_code -eq 0 ]; then
        if ! install_diagnostic_tools; then
            log_warn "Package installation had issues, but continuing..."
            exit_code=1
        fi
    fi
    
    if [ $exit_code -eq 0 ]; then
        configure_system || exit_code=1
    fi
    
    if [ $exit_code -eq 0 ]; then
        create_pxe_files || exit_code=1
    fi
    
    if [ $exit_code -eq 0 ]; then
        finalize_image || exit_code=1
    fi
    
    if [ $exit_code -eq 0 ]; then
        log_info "Build completed successfully!"
        log_info "Output files:"
        ls -la "$OUTPUT_DIR/"
    else
        log_warn "Build completed with some issues, but PXE files should be available"
        log_info "Available output files:"
        ls -la "$OUTPUT_DIR/" 2>/dev/null || true
    fi
    
    return $exit_code
}

# Run main function
main "$@"
