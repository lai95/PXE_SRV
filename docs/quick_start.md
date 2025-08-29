# Quick Start Guide - PXE Telemetry & Diagnostics System

This guide will help you get the PXE Telemetry & Diagnostics System up and running in under 30 minutes.

## 🚀 Prerequisites

Before you begin, ensure you have the following installed:

- **Docker** (version 20.10+)
- **Docker Compose** (version 1.28.0+)
- **Git** (for cloning the repository)
- **Python 3.8+** and **pip3** (for local development)

### Quick Prerequisites Check

```bash
# Check Docker
docker --version
docker-compose --version

# Check Python
python3 --version
pip3 --version

# Check Git
git --version
```

## 📥 Installation

### 1. Clone the Repository

```bash
git clone <repository-url>
cd pxe_server
```

### 2. Run the Setup Script

```bash
# Make the script executable
chmod +x setup.sh

# Run basic setup
./setup.sh

# Or run with monitoring (includes Grafana)
./setup.sh --with-monitoring
```

The setup script will:
- Check prerequisites
- Create Docker configuration files
- Build and start all services
- Configure Foreman/Katello
- Set up the diagnostic system
- Display access information

## 🌐 Accessing the System

After successful setup, you can access:

- **Foreman Web Interface**: http://localhost:3000
- **Main Program API**: http://localhost:5000
- **Grafana Dashboard**: http://localhost:3001 (if monitoring enabled)

### Default Credentials

- **Foreman**: admin / (password displayed during setup)
- **Grafana**: admin / admin123

Credentials are saved to `foreman_credentials.txt` in your project directory.

## 🔧 First-Time Configuration

### 1. Configure Foreman PXE Templates

1. Access Foreman at http://localhost:3000
2. Log in with admin credentials
3. Navigate to **Hosts** → **Provisioning Templates**
4. Create a new PXE template for diagnostics:

```bash
# Example PXE template content
DEFAULT diagnostic_boot
TIMEOUT 30
PROMPT 1

LABEL diagnostic_boot
    MENU LABEL PXE Diagnostics
    KERNEL vmlinuz-virt
    APPEND initrd=initramfs-virt modules=loop,squashfs,sd-mod,usb-storage quiet console=ttyS0,115200 console=tty0
    MENU DEFAULT
```

### 2. Upload PXE Boot Files

1. Copy the generated PXE files to `/var/lib/tftpboot/`:
   - `vmlinuz-virt` (kernel)
   - `initramfs-virt` (initial ramdisk)
   - `pxelinux.cfg/default` (PXE configuration)

2. Set proper permissions:
```bash
sudo chown -R tftp:tftp /var/lib/tftpboot/
sudo chmod -R 755 /var/lib/tftpboot/
```

### 3. Configure DHCP

1. In Foreman, go to **Infrastructure** → **Subnets**
2. Create or edit your PXE subnet
3. Ensure DHCP is enabled and configured for PXE boot

## 🧪 Testing the System

### 1. Test PXE Boot

1. Configure a test device to boot from network
2. Ensure it's on the same network as your PXE server
3. Boot the device - it should automatically:
   - Download the diagnostic image
   - Run comprehensive hardware tests
   - Generate a diagnostic report
   - Upload results to the server

### 2. Monitor Diagnostic Progress

```bash
# View PXE server logs
docker-compose logs -f pxe_server

# View main program logs
docker-compose logs -f main_program

# Check for uploaded reports
docker exec pxe_server ls -la /var/lib/foreman-reports/
```

### 3. View Diagnostic Reports

```bash
# List all reports via API
curl http://localhost:5000/api/v1/reports

# Get specific report
curl http://localhost:5000/api/v1/reports/test-client

# Analyze a report
curl http://localhost:5000/api/v1/reports/test-client/analyze
```

## 📊 Understanding the Results

### Report Structure

Each diagnostic report contains:

```
/reports/<hostname>/
├── report.json              # Summary report
├── summary.txt              # Human-readable summary
├── hardware/                # Hardware information
│   ├── lshw.json           # System hardware details
│   ├── dmidecode.txt       # BIOS/DMI information
│   ├── cpuinfo.txt         # CPU details
│   └── meminfo.txt         # Memory information
└── performance/             # Performance test results
    ├── cpu/                 # CPU tests
    ├── memory/              # Memory tests
    ├── disk/                # Disk performance
    └── network/             # Network tests
```

### Health Score

Reports include a health score (0-100) based on:
- **System Information** (25 points)
- **CPU Performance** (18.75 points)
- **Memory Health** (18.75 points)
- **Disk Performance** (18.75 points)
- **Network Performance** (18.75 points)

## 🛠️ Troubleshooting

### Common Issues

#### 1. Services Not Starting

```bash
# Check service status
docker-compose ps

# View detailed logs
docker-compose logs [service_name]

# Restart services
docker-compose restart
```

#### 2. PXE Boot Fails

```bash
# Check TFTP service
docker exec pxe_server systemctl status tftp

# Verify PXE files exist
docker exec pxe_server ls -la /var/lib/tftpboot/

# Check DHCP configuration
docker exec pxe_server systemctl status dhcpd
```

#### 3. Reports Not Uploading

```bash
# Check upload directory permissions
docker exec pxe_server ls -la /var/lib/foreman-reports/

# Verify network connectivity
docker exec pxe_server ping -c 3 8.8.8.8

# Check diagnostic logs
docker exec pxe_client cat /var/log/diagnostics/diagnostics.log
```

### Getting Help

1. **Check the logs**: Use `docker-compose logs` to view service logs
2. **Review configuration**: Verify all configuration files are correct
3. **Check network**: Ensure proper network configuration and firewall rules
4. **Consult documentation**: See the full documentation in the `docs/` directory

## 🔄 Maintenance

### Regular Tasks

```bash
# Update services
docker-compose pull
docker-compose up -d

# Backup reports
docker exec pxe_server tar -czf /tmp/reports_backup.tar.gz /var/lib/foreman-reports/

# Clean old logs
docker exec pxe_server find /var/log -name "*.log" -mtime +30 -delete

# Monitor disk usage
docker exec pxe_server df -h
```

### Performance Tuning

- **Memory**: Ensure at least 8GB RAM for the PXE server
- **Storage**: Use SSD storage for better performance
- **Network**: Ensure gigabit network connectivity
- **Concurrent Tests**: Limit concurrent PXE boots based on server capacity

## 📈 Next Steps

After getting the basic system running:

1. **Customize Tests**: Modify diagnostic scripts in `diagnostics/` directory
2. **Add Monitoring**: Set up Grafana dashboards for historical analysis
3. **Scale Up**: Deploy to production with proper security and backup
4. **Integration**: Connect with existing monitoring and ticketing systems
5. **Automation**: Set up automated testing schedules via Foreman

## 📚 Additional Resources

- [Full Documentation](docs/)
- [API Reference](docs/api_reference.md)
- [Troubleshooting Guide](docs/troubleshooting.md)
- [Performance Tuning](docs/performance_tuning.md)
- [Security Best Practices](docs/security.md)

---

**Need Help?** Create an issue in the repository or check the troubleshooting guide for common solutions.
