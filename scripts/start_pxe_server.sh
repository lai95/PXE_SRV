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
                /usr/sbin/dhcpd -f -d &
                log_info "dhcpd started in background"
            fi
            ;;
        tftp)
            if [ -f /usr/sbin/in.tftpd ]; then
                /usr/sbin/in.tftpd -s /var/lib/tftpboot -l &
                log_info "tftp started in background"
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

# Main startup sequence
main() {
    log_info "Starting PXE Server..."
    
    # Start essential services
    start_service chronyd
    start_service firewalld
    start_service dhcpd
    start_service tftp
    
    # Enable services for future boots
    enable_service chronyd
    enable_service firewalld
    enable_service dhcpd
    enable_service tftp
    
    # Configure firewall rules
    log_info "Configuring firewall..."
    firewall-cmd --permanent --add-service=dhcp
    firewall-cmd --permanent --add-service=tftp
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --reload
    
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
    ps aux | grep chronyd | grep -v grep || echo "chronyd not running"
    echo "=========================================="
    ps aux | grep firewalld | grep -v grep || echo "firewalld not running"
    echo "=========================================="
    ps aux | grep dhcpd | grep -v grep || echo "dhcpd not running"
    echo "=========================================="
    ps aux | grep tftpd | grep -v grep || echo "tftp not running"
    echo "=========================================="
    
    log_info "PXE Server startup complete!"
    log_info "Services are running and ready for PXE boot requests."
    
    # Keep the container running
    log_info "Container is running. Press Ctrl+C to stop."
    while true; do
        sleep 30
        # Check if critical services are still running
        if ! pgrep -f dhcpd > /dev/null || ! pgrep -f tftpd > /dev/null; then
            log_error "Critical services stopped. Restarting..."
            start_service dhcpd
            start_service tftp
        fi
    done
}

# Handle signals
trap 'log_info "Shutting down PXE Server..."; exit 0' SIGTERM SIGINT

# Run main function
main "$@"
