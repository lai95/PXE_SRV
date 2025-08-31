#!/bin/bash

# PXE Server Startup Script
# This script starts all required services for the PXE server

set -e

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

# Function to start a service
start_service() {
    local service_name=$1
    log_info "Starting $service_name..."
    
    # In Docker container, we need to start services manually
    case $service_name in
        chronyd)
            if [ -f /usr/sbin/chronyd ]; then
                /usr/sbin/chronyd -d &
                log_info "chronyd started in background"
            fi
            ;;
        firewalld)
            if [ -f /usr/sbin/firewalld ]; then
                /usr/sbin/firewalld --nofork --nopid &
                log_info "firewalld started in background"
            fi
            ;;
        dhcpd)
            if [ -f /usr/sbin/dhcpd ]; then
                # Kill existing dhcpd process if running
                pkill -f dhcpd 2>/dev/null || true
                # Remove PID file if it exists
                rm -f /var/run/dhcpd.pid
                sleep 2
                /usr/sbin/dhcpd -f -d &
                log_info "dhcpd started in background"
            fi
            ;;
        tftp)
            if [ -f /usr/sbin/in.tftpd ]; then
                # Kill existing tftp process if running
                pkill -f tftpd 2>/dev/null || true
                # Remove PID file if it exists
                rm -f /var/run/in.tftpd.pid
                sleep 2
                # Start TFTP with explicit PID file
                /usr/sbin/in.tftpd -s /var/lib/tftpboot -l -p /var/run/in.tftpd.pid &
                # Wait a moment for PID file to be created
                sleep 1
                if [ -f /var/run/in.tftpd.pid ]; then
                    log_info "tftp started in background (PID: $(cat /var/run/in.tftpd.pid))"
                else
                    log_warn "tftp started but PID file not created"
                fi
            fi
            ;;
        *)
            log_warn "Service $service_name not configured for Docker"
            ;;
    esac
}

# Function to enable a service (no-op in Docker)
enable_service() {
    local service_name=$1
    log_info "Service $service_name will be started manually in Docker"
}

# Function to configure DHCP
configure_dhcp() {
    log_info "Configuring DHCP server..."
    
    # Create DHCP configuration
    cat > /etc/dhcp/dhcpd.conf << 'EOF'
# DHCP Server Configuration for PXE
default-lease-time 600;
max-lease-time 7200;

# PXE Network Configuration
subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    option routers 192.168.1.1;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
    option broadcast-address 192.168.1.255;
    
    # PXE Boot Configuration
    filename "pxelinux.0";
    next-server 192.168.1.2;
    
    # Allow booting
    allow booting;
    allow bootp;
}
EOF
    
    log_info "DHCP configuration created"
}

# Function to setup TFTP directory
setup_tftp() {
    log_info "Setting up TFTP directory..."
    
    # Ensure TFTP directory exists with proper permissions
    mkdir -p /var/lib/tftpboot
    chmod 755 /var/lib/tftpboot
    chown root:root /var/lib/tftpboot
    
    # Create basic PXE structure
    mkdir -p /var/lib/tftpboot/pxelinux.cfg
    chmod 755 /var/lib/tftpboot/pxelinux.cfg
    
    log_info "TFTP directory setup complete"
}

# Main startup sequence
main() {
    log_info "Starting PXE Server..."
    
    # Configure services first
    configure_dhcp
    setup_tftp
    
    # Start essential services
    start_service chronyd
    start_service dhcpd
    start_service tftp
    
    # Enable services for future boots
    enable_service chronyd
    enable_service firewalld
    enable_service dhcpd
    enable_service tftp
    
    # Configure firewall rules (skip in Docker to avoid DBUS issues)
    log_info "Firewall configuration skipped in Docker container"
    log_info "Ports will be managed by Docker port mappings"
    
    # Start Foreman services if available
    if command -v foreman-installer &> /dev/null; then
        log_info "Foreman installer found, starting Foreman services..."
        
        # Check if Foreman is already configured
        if [ -f "/etc/foreman/foreman.yml" ]; then
            log_info "Foreman is already configured, starting services..."
            start_service foreman
            start_service httpd
            start_service postgresql
        else
            log_info "Foreman not configured yet. Run foreman-installer to configure."
        fi
    else
        log_info "Foreman installer not found. Install Foreman first."
    fi
    
    # Display service status
    log_info "Service Status:"
    echo "=========================================="
    # Use basic commands available in minimal images
    if [ -f /proc/1/comm ]; then
        for proc in /proc/*/comm; do
            if grep -q chronyd "$proc" 2>/dev/null; then
                echo "chronyd is running"
                break
            fi
        done
    else
        echo "chronyd status unknown"
    fi
    echo "=========================================="
    echo "firewalld not running (disabled in Docker)"
    echo "=========================================="
    if [ -f /var/run/dhcpd.pid ]; then
        echo "dhcpd is running (PID: $(cat /var/run/dhcpd.pid))"
    else
        echo "dhcpd not running"
    fi
    echo "=========================================="
    if [ -f /var/run/in.tftpd.pid ]; then
        echo "tftp is running (PID: $(cat /var/run/in.tftpd.pid))"
    else
        echo "tftp not running"
    fi
    echo "=========================================="
    
    log_info "PXE Server startup complete!"
    log_info "Services are running and ready for PXE boot requests."
    
    # Keep the container running
    log_info "Container is running. Press Ctrl+C to stop."
    while true; do
        sleep 30
        # Check if critical services are still running using PID files
        dhcpd_running=false
        tftp_running=false
        
        # Check DHCP
        if [ -f /var/run/dhcpd.pid ]; then
            if kill -0 $(cat /var/run/dhcpd.pid) 2>/dev/null; then
                dhcpd_running=true
            else
                # PID file exists but process is dead, remove it
                rm -f /var/run/dhcpd.pid
            fi
        fi
        
        # Check TFTP
        if [ -f /var/run/in.tftpd.pid ]; then
            if kill -0 $(cat /var/run/in.tftpd.pid) 2>/dev/null; then
                tftp_running=true
            else
                # PID file exists but process is dead, remove it
                rm -f /var/run/in.tftpd.pid
            fi
        fi
        
        if [ "$dhcpd_running" = false ] || [ "$tftp_running" = false ]; then
            log_error "Critical services stopped. Restarting..."
            # Kill existing processes before restarting
            pkill -f dhcpd 2>/dev/null || true
            pkill -f tftpd 2>/dev/null || true
            # Remove stale PID files
            rm -f /var/run/dhcpd.pid /var/run/in.tftpd.pid
            sleep 2
            start_service dhcpd
            start_service tftp
        fi
    done
}

# Handle signals
trap 'log_info "Shutting down PXE Server..."; exit 0' SIGTERM SIGINT

# Run main function
main "$@"
