# PXE Telemetry & Diagnostics System

A comprehensive PXE-bootable Linux diagnostics image managed via a Rocky Linux PXE server running Foreman/Katello for automated hardware testing and telemetry collection.

## 🎯 Overview

This system replaces manual hardware inspection and LAN port testing with an automated, repeatable, and standardized diagnostics suite that:

- Provides one-shot, automated diagnostics across hardware and network subsystems
- Runs performance and stress tests (CPU, RAM, disks, NICs, CMOS battery, RAID, thermals)
- Collects telemetry from switches and IPMI (SNMP/LLDP/IPMI)
- Auto-generates structured reports (JSON/CSV + raw logs)
- Integrates with Foreman/Katello for central control and job scheduling
- Uploads reports automatically to central Main Program API or file repository

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   PXE Server    │    │  PXE Client      │    │  Main Program   │
│                 │    │                  │    │                 │
│ Rocky Linux 9.x │◄──►│ Diagnostic Image │───►│ Report Ingestion│
│ Foreman/Katello │    │ Auto-run Suite   │    │ Dashboard/API   │
│ PXE Provisioning│    │ Hardware Tests   │    │ Alert System    │
│ Report Storage  │    │ Network Tests    │    │ Control Policies│
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 📁 Project Structure

```
pxe_server/
├── ansible/                 # Ansible playbooks for server setup
├── foreman/                 # Foreman/Katello configuration
├── pxe_image/              # PXE boot image build scripts
├── diagnostics/            # Diagnostic tools and scripts
├── main_program/           # Central report processing system
├── docs/                   # Documentation and guides
├── scripts/                # Utility scripts
└── docker-compose.yml      # Development environment
```

## 🚀 Quick Start

### Prerequisites

- Rocky Linux 9.x server (or VM)
- Minimum 8GB RAM, 100GB storage
- Network access for package installation
- Root/sudo access

### 1. Server Setup

```bash
# Clone the repository
git clone <repository-url>
cd pxe_server

# Run the Ansible playbook for server setup
ansible-playbook ansible/setup_pxe_server.yml
```

### 2. Build PXE Image

```bash
# Build the diagnostic boot image
cd pxe_image
./build_image.sh
```

### 3. Configure Foreman

```bash
# Access Foreman web interface
# http://your-server-ip:3000
# Default credentials: admin / changeme
```

### 4. Test PXE Boot

```bash
# Boot a test device via PXE
# The diagnostic suite will run automatically
# Reports will be uploaded to the server
```

## 🔧 Key Components

### PXE Server (Rocky Linux + Foreman/Katello)
- Automated provisioning and PXE image distribution
- Report storage and management
- Job scheduling and test profile selection

### PXE Diagnostic Image
- Alpine Linux-based minimal image (< 200MB)
- Comprehensive hardware testing tools
- Automated test execution and report generation
- Network upload capabilities

### Diagnostic Suite
- **Hardware**: lshw, hwinfo, dmidecode, smartctl, hdparm
- **Performance**: stress-ng, sysbench, fio, memtester
- **Network**: iperf3, snmpwalk, lldpd, ethtool
- **Power**: ipmitool, hwclock, dmidecode

### Main Program
- Report ingestion and parsing
- JSON/CSV processing
- Dashboard and alerting system
- Integration with Foreman for control policies

## 📊 Report Format

Reports are generated in both raw log format and structured JSON:

```json
{
  "hostname": "srv123",
  "timestamp": "2024-01-15T10:30:00Z",
  "cpu": {
    "sysbench_score": 14500,
    "stress_test": "PASS",
    "cores": 16,
    "model": "Intel Xeon E5-2680"
  },
  "memory": {
    "size_gb": 32,
    "errors": 0,
    "memtester_result": "PASS"
  },
  "disk": [
    {
      "device": "/dev/sda",
      "fio_iops": 55000,
      "smart_health": "OK",
      "size_gb": 1000
    }
  ],
  "network": {
    "iperf_mbps": 940,
    "errors": 0,
    "interfaces": ["eth0", "eth1"]
  },
  "cmos_battery": {
    "status": "OK",
    "hwclock_drift_sec": 0.2
  }
}
```

## 🎮 User Stories

- **Engineer**: Boot device → collect full diagnostics with zero manual work
- **Manager**: View standardized health reports for all tested devices
- **Developer**: Parse structured JSON/CSV into main program for automation

## 📈 Success Metrics

- Boot-to-report < 15 minutes typical
- ≥ 95% hardware models tested successfully
- Reports ingested with zero manual steps
- Reports visible in Foreman GUI and main program

## 🔮 Future Extensions

- Baseline performance thresholds for pass/fail scoring
- Firmware version collection (BIOS, RAID)
- Vendor-specific modules (Dell OMSA, HPE iLO CLI)
- Grafana dashboards for history/trends
- Integration with CI/CD pipelines

## 📚 Documentation

- [Server Setup Guide](docs/server_setup.md)
- [PXE Image Building](docs/pxe_image_building.md)
- [Foreman Configuration](docs/foreman_config.md)
- [Diagnostic Tools Reference](docs/diagnostic_tools.md)
- [API Documentation](docs/api_reference.md)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

For issues and questions:
- Create an issue in the repository
- Check the [FAQ](docs/faq.md)
- Review the [troubleshooting guide](docs/troubleshooting.md)
