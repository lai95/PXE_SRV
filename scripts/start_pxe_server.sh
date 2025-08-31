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
    
    if systemctl is-active --quiet $service_name; then
        log_info "$service_name is already running"
    else
        systemctl start $service_name
        if systemctl is-active --quiet $service_name; then
            log_info "$service_name started successfully"
        else
            log_error "Failed to start $service_name"
            return 1
        fi
    fi
}

# Function to enable a service
enable_service() {
    local service_name=$1
    log_info "Enabling $service_name..."
    systemctl enable $service_name
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
    systemctl status chronyd --no-pager -l
    echo "=========================================="
    systemctl status firewalld --no-pager -l
    echo "=========================================="
    systemctl status dhcpd --no-pager -l
    echo "=========================================="
    systemctl status tftp --no-pager -l
    echo "=========================================="
    
    log_info "PXE Server startup complete!"
    log_info "Services are running and ready for PXE boot requests."
    
    # Keep the container running
    log_info "Container is running. Press Ctrl+C to stop."
    while true; do
        sleep 30
        # Check if critical services are still running
        if ! systemctl is-active --quiet dhcpd || ! systemctl is-active --quiet tftp; then
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
