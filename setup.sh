#!/bin/bash

# PXE Telemetry & Diagnostics System - Setup Script
# Complete system deployment and configuration

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="pxe_telemetry_diagnostics"
VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_section() {
    echo -e "${BLUE}[SECTION]${NC} $1"
    echo "=========================================="
}

# Check prerequisites
check_prerequisites() {
    log_section "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check for required tools
    for tool in docker git python3 pip3; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    # Check for Docker Compose (either V1 or V2)
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        missing_tools+=("docker-compose")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        log_info "Please start Docker and try again"
        exit 1
    fi
    
    # Check Docker Compose version (support both V1 and V2)
    local compose_version=""
    local compose_command=""
    
    if docker-compose --version &> /dev/null; then
        compose_command="docker-compose"
        compose_version=$(docker-compose --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log_info "Docker Compose V1 detected: $compose_version"
    elif docker compose version &> /dev/null; then
        compose_command="docker compose"
        compose_version=$(docker compose version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log_info "Docker Compose V2 detected: $compose_version"
    else
        log_error "Docker Compose not found. Please install Docker Compose V1 or V2."
        exit 1
    fi
    
    # Store the command for later use
    export COMPOSE_COMMAND="$compose_command"
    
    log_info "Prerequisites check passed"
}

# Setup development environment
setup_dev_environment() {
    log_section "Setting Up Development Environment"
    
    # Create necessary directories
    mkdir -p docker monitoring/grafana/provisioning
    
    # Create Docker files if they don't exist
    create_docker_files
    
    # Install Python dependencies
    log_info "Installing Python dependencies..."
    cd main_program
    pip3 install -r requirements.txt
    cd ..
    
    log_info "Development environment setup complete"
}

# Create Docker files
create_docker_files() {
    log_info "Creating Docker configuration files..."
    
    # Create docker directory
    mkdir -p docker
    
    # PXE Server Dockerfile
    cat > docker/pxe_server.Dockerfile << 'EOF'
FROM rockylinux:9

# Install system packages
RUN dnf update -y && \
    dnf install -y epel-release && \
    dnf install -y \
        wget \
        vim \
        htop \
        net-tools \
        bind-utils \
        tcpdump \
        iotop \
        sysstat \
        lsof \
        strace \
        gcc \
        make \
        python3 \
        python3-pip \
        python3-devel \
        openssl \
        ca-certificates \
        chrony \
        firewalld \
        dhcp-server \
        tftp-server \
        syslinux \
    && dnf clean all

# Install Foreman/Katello
RUN dnf install -y https://yum.theforeman.org/releases/3.0/el9/x86_64/foreman-release.rpm && \
    dnf install -y https://yum.theforeman.org/katello/3.0/katello/el9/x86_64/katello-repos-latest.rpm && \
    dnf install -y foreman-installer

# Configure services
RUN systemctl enable firewalld chronyd dhcpd tftp

# Create required directories
RUN mkdir -p /var/lib/tftpboot /var/lib/foreman-reports /opt/pxe /var/log/pxe

# Set up users
RUN useradd -r -s /bin/bash -d /opt/foreman foreman \
    && useradd -r -s /bin/bash -d /opt/pxe pxe \
    && groupadd tftp \
    && usermod -a -G tftp pxe

# Copy configuration files
COPY ansible/roles/system_setup/templates/* /tmp/templates/
COPY foreman/ /opt/foreman/

# Expose ports
EXPOSE 3000 67/udp 69/udp 53/udp 22

# Start script
COPY scripts/start_pxe_server.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/start_pxe_server.sh

CMD ["/usr/local/bin/start_pxe_server.sh"]
EOF

    # Main Program Dockerfile
    cat > docker/main_program.Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY main_program/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main_program/ .

# Create necessary directories
RUN mkdir -p /var/lib/foreman-reports /var/log/main_program

# Expose port
EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5000/api/v1/health || exit 1

CMD ["python", "app.py", "--host", "0.0.0.0", "--port", "5000"]
EOF

    # PXE Client Dockerfile
    cat > docker/pxe_client.Dockerfile << 'EOF'
FROM alpine:3.18

# Install diagnostic tools
RUN apk add --no-cache \
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

# Copy diagnostic scripts
COPY diagnostics/ /opt/diagnostics/
RUN chmod +x /opt/diagnostics/bin/*

# Create required directories
RUN mkdir -p /reports /var/log/diagnostics /tmp/upload

# Set up diagnostic service
RUN echo '#!/bin/sh' > /etc/init.d/diagnostics \
    && echo 'case "$1" in' >> /etc/init.d/diagnostics \
    && echo '    start)' >> /etc/init.d/diagnostics \
    && echo '        echo "Starting diagnostic system..."' >> /etc/init.d/diagnostics \
    && echo '        /opt/diagnostics/bin/run_diagnostics.sh' >> /etc/init.d/diagnostics \
    && echo '        ;;' >> /etc/init.d/diagnostics \
    && echo '    *)' >> /etc/init.d/diagnostics \
    && echo '        echo "Usage: $0 {start}"' >> /etc/init.d/diagnostics \
    && echo '        exit 1' >> /etc/init.d/diagnostics \
    && echo '        ;;' >> /etc/init.d/diagnostics \
    && echo 'esac' >> /etc/init.d/diagnostics \
    && chmod +x /etc/init.d/diagnostics

# Run diagnostics on startup
CMD ["/etc/init.d/diagnostics", "start"]
EOF

    log_info "Docker files created"
}

# Build and start services
deploy_services() {
    log_section "Deploying Services"
    
    log_info "Building Docker images..."
    
    # Use the detected Docker Compose command
    log_info "Using $COMPOSE_COMMAND..."
    $COMPOSE_COMMAND build
    
    log_info "Starting services..."
    $COMPOSE_COMMAND up -d
    
    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 30
    
    # Check service status
    log_info "Checking service status..."
    $COMPOSE_COMMAND ps
    
    log_info "Services deployed successfully"
}

# Configure Foreman
configure_foreman() {
    log_section "Configuring Foreman"
    
    log_info "Waiting for Foreman to be ready..."
    
    # Wait for Foreman web interface
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:3000/api/v2/status &> /dev/null; then
            log_info "Foreman is ready"
            break
        fi
        
        log_info "Waiting for Foreman... (attempt $attempt/$max_attempts)"
        sleep 10
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "Foreman failed to start within expected time"
        return 1
    fi
    
    # Get admin password
    local admin_password=$(docker exec pxe_server foreman-rake permissions:reset 2>/dev/null | grep 'Password:' | cut -d' ' -f2)
    
    if [ -n "$admin_password" ]; then
        log_info "Foreman admin password: $admin_password"
        echo "Foreman Admin: admin / $admin_password" > foreman_credentials.txt
        echo "Foreman URL: http://localhost:3000" >> foreman_credentials.txt
    else
        log_warn "Could not retrieve Foreman admin password"
    fi
    
    log_info "Foreman configuration complete"
}

# Build PXE image
build_pxe_image() {
    log_section "Building PXE Diagnostic Image"
    
    log_info "Building diagnostic boot image..."
    
    # Check if we're in a Docker environment
    if [ -f /.dockerenv ]; then
        log_warn "Running in Docker container, PXE image build may not work properly"
        log_info "Consider building the PXE image on the host system"
        return 0
    fi
    
    # Check if build script exists and is executable
    if [ -f "pxe_image/build_image.sh" ]; then
        chmod +x pxe_image/build_image.sh
        
        # Check if running as root (required for image building)
        if [ "$EUID" -eq 0 ]; then
            log_info "Building PXE image as root..."
            cd pxe_image
            ./build_image.sh
            cd ..
        else
            log_warn "PXE image build requires root privileges"
            log_info "Run 'sudo ./pxe_image/build_image.sh' to build the image"
        fi
    else
        log_warn "PXE image build script not found"
    fi
    
    log_info "PXE image build process initiated"
}

# Setup monitoring
setup_monitoring() {
    log_section "Setting Up Monitoring"
    
    log_info "Starting monitoring services..."
    $COMPOSE_COMMAND --profile monitoring up -d
    
    # Wait for Grafana
    log_info "Waiting for Grafana to be ready..."
    sleep 20
    
    if curl -s http://localhost:3001/api/health &> /dev/null; then
        log_info "Grafana is ready"
        echo "Grafana URL: http://localhost:3001" >> foreman_credentials.txt
        echo "Grafana Admin: admin / admin123" >> foreman_credentials.txt
    else
        log_warn "Grafana failed to start"
    fi
    
    log_info "Monitoring setup complete"
}

# Display system information
display_system_info() {
    log_section "System Information"
    
    echo "PXE Telemetry & Diagnostics System"
    echo "=================================="
    echo "Version: $VERSION"
    echo "Project Directory: $SCRIPT_DIR"
    echo ""
    echo "Service URLs:"
    echo "- Foreman Web Interface: http://localhost:3000"
    echo "- Main Program API: http://localhost:5000"
    echo "- Grafana Dashboard: http://localhost:3001"
    echo ""
    echo "Network Configuration:"
    echo "- PXE Network: 192.168.1.0/24"
    echo "- Gateway: 192.168.1.1"
    echo ""
    echo "Credentials saved to: foreman_credentials.txt"
    echo ""
    echo "Next Steps:"
    echo "1. Access Foreman web interface to configure PXE templates"
    echo "2. Build and upload PXE diagnostic image"
    echo "3. Test PXE boot with a target device"
    echo "4. Monitor diagnostic reports via the API"
    echo ""
    echo "Useful Commands:"
    echo "- View logs: $COMPOSE_COMMAND logs -f [service_name]"
    echo "- Stop services: $COMPOSE_COMMAND down"
    echo "- Restart services: $COMPOSE_COMMAND restart"
    echo "- Update services: $COMPOSE_COMMAND pull && $COMPOSE_COMMAND up -d"
}

# Main execution
main() {
    log_info "Starting PXE Telemetry & Diagnostics System Setup"
    log_info "Version: $VERSION"
    
    # Check prerequisites
    check_prerequisites
    
    # Setup development environment
    setup_dev_environment
    
    # Deploy services
    deploy_services
    
    # Configure Foreman
    configure_foreman
    
    # Build PXE image
    build_pxe_image
    
    # Setup monitoring (optional)
    if [ "$1" = "--with-monitoring" ]; then
        setup_monitoring
    fi
    
    # Display system information
    display_system_info
    
    log_info "Setup completed successfully!"
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --with-monitoring    Include Grafana monitoring setup"
        echo "  --help, -h          Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                  # Basic setup without monitoring"
        echo "  $0 --with-monitoring # Setup with monitoring"
        ;;
    *)
        main "$@"
        ;;
esac
