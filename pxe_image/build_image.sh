#!/bin/bash

# PXE Diagnostic Image Builder
# Builds a minimal Alpine Linux-based diagnostic boot image

set -e

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

# Download Alpine Linux
download_alpine() {
    log_info "Downloading Alpine Linux ${ALPINE_VERSION}..."
    
    local alpine_url="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/x86_64/alpine-minirootfs-${ALPINE_VERSION}.0-x86_64.tar.gz"
    local alpine_file="$WORK_DIR/alpine-minirootfs-${ALPINE_VERSION}.0-x86_64.tar.gz"
    
    if [ ! -f "$alpine_file" ]; then
        wget -O "$alpine_file" "$alpine_url"
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

# Install diagnostic tools
install_diagnostic_tools() {
    log_info "Installing diagnostic tools..."
    
    # Create package cache directory
    mkdir -p "$MOUNT_DIR/var/cache/apk"
    
    # Copy package database
    cp -r "$MOUNT_DIR/etc/apk" "$MOUNT_DIR/var/cache/apk/"
    
    # Install packages
    chroot "$MOUNT_DIR" apk update
    chroot "$MOUNT_DIR" apk add --no-cache \
        lshw \
        hwinfo \
        dmidecode \
        smartmontools \
        hdparm \
        fio \
        memtester \
        stress-ng \
        sysbench \
        iperf3 \
        netperf \
        snmp-tools \
        lldpd \
        ethtool \
        ipmitool \
        lm-sensors \
        mdadm \
        bonnie++ \
        ioping \
        curl \
        wget \
        jq \
        python3 \
        bash \
        vim \
        htop \
        iotop \
        sysstat \
        lsof \
        strace \
        gcc \
        make \
        linux-headers
    
    log_info "Diagnostic tools installed"
}

# Configure system
configure_system() {
    log_info "Configuring system..."
    
    # Copy diagnostic scripts
    cp -r ../diagnostics/* "$MOUNT_DIR/opt/diagnostics/"
    chmod +x "$MOUNT_DIR/opt/diagnostics/bin/*"
    
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
    
    # Enable diagnostic service
    chroot "$MOUNT_DIR" rc-update add diagnostics default
    
    # Configure networking
    cat > "$MOUNT_DIR/etc/network/interfaces" << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
    
    # Configure SSH for report upload
    chroot "$MOUNT_DIR" apk add --no-cache openssh
    chroot "$MOUNT_DIR" ssh-keygen -A
    
    # Create upload user
    chroot "$MOUNT_DIR" adduser -D -s /bin/bash upload
    chroot "$MOUNT_DIR" echo "upload:upload123" | chpasswd
    
    log_info "System configured"
}

# Create PXE boot files
create_pxe_files() {
    log_info "Creating PXE boot files..."
    
    # Download kernel and initramfs
    local kernel_url="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/x86_64/netboot/vmlinuz-virt"
    local initramfs_url="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/x86_64/netboot/initramfs-virt"
    
    wget -O "$OUTPUT_DIR/vmlinuz-virt" "$kernel_url"
    wget -O "$OUTPUT_DIR/initramfs-virt" "$initramfs_url"
    
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
    
    log_info "PXE boot files created"
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
    
    check_prerequisites
    setup_directories
    download_alpine
    create_image
    extract_alpine
    install_diagnostic_tools
    configure_system
    create_pxe_files
    finalize_image
    
    log_info "Build completed successfully!"
    log_info "Output files:"
    ls -la "$OUTPUT_DIR/"
}

# Run main function
main "$@"
