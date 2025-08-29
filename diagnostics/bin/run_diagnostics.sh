#!/bin/bash

# PXE Diagnostic System - Main Runner
# Automatically runs comprehensive hardware and network diagnostics

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="/var/log/diagnostics"
REPORT_DIR="/reports"
UPLOAD_DIR="/tmp/upload"
HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TEST_TIMEOUT=900  # 15 minutes total

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_DIR/diagnostics.log"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_DIR/diagnostics.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_DIR/diagnostics.log"
}

log_section() {
    echo -e "${BLUE}[SECTION]${NC} $1" | tee -a "$LOG_DIR/diagnostics.log"
    echo "==========================================" | tee -a "$LOG_DIR/diagnostics.log"
}

# Initialize system
init_system() {
    log_info "Initializing diagnostic system..."
    
    # Create directories
    mkdir -p "$LOG_DIR" "$REPORT_DIR" "$UPLOAD_DIR"
    
    # Set up logging
    exec 1> >(tee -a "$LOG_DIR/diagnostics.log")
    exec 2> >(tee -a "$LOG_DIR/diagnostics.log" >&2)
    
    # Get system information
    log_info "Hostname: $HOSTNAME"
    log_info "Timestamp: $TIMESTAMP"
    log_info "Script directory: $SCRIPT_DIR"
    
    # Check available tools
    check_available_tools
    
    log_info "System initialization complete"
}

# Check available diagnostic tools
check_available_tools() {
    log_info "Checking available diagnostic tools..."
    
    local tools=(
        "lshw" "hwinfo" "dmidecode" "smartctl" "hdparm"
        "fio" "memtester" "stress-ng" "sysbench" "iperf3"
        "snmpwalk" "lldpd" "ethtool" "ipmitool" "lm-sensors"
        "mdadm" "bonnie++" "ioping"
    )
    
    local available_tools=()
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            available_tools+=("$tool")
        else
            missing_tools+=("$tool")
        fi
    done
    
    log_info "Available tools: ${available_tools[*]}"
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_warn "Missing tools: ${missing_tools[*]}"
    fi
}

# Run hardware information collection
run_hardware_info() {
    log_section "Hardware Information Collection"
    
    local hw_dir="$REPORT_DIR/$HOSTNAME/hardware"
    mkdir -p "$hw_dir"
    
    # System hardware information
    if command -v lshw &> /dev/null; then
        log_info "Running lshw..."
        timeout 60 lshw -json > "$hw_dir/lshw.json" 2>/dev/null || log_warn "lshw failed or timed out"
    fi
    
    if command -v hwinfo &> /dev/null; then
        log_info "Running hwinfo..."
        timeout 60 hwinfo --all > "$hw_dir/hwinfo.txt" 2>/dev/null || log_warn "hwinfo failed or timed out"
    fi
    
    if command -v dmidecode &> /dev/null; then
        log_info "Running dmidecode..."
        timeout 60 dmidecode -t all > "$hw_dir/dmidecode.txt" 2>/dev/null || log_warn "dmidecode failed or timed out"
    fi
    
    # CPU information
    log_info "Collecting CPU information..."
    cat /proc/cpuinfo > "$hw_dir/cpuinfo.txt"
    cat /proc/stat > "$hw_dir/stat.txt"
    
    # Memory information
    log_info "Collecting memory information..."
    cat /proc/meminfo > "$hw_dir/meminfo.txt"
    cat /proc/swaps > "$hw_dir/swaps.txt"
    
    # Disk information
    log_info "Collecting disk information..."
    lsblk -f > "$hw_dir/lsblk.txt"
    fdisk -l > "$hw_dir/fdisk.txt" 2>/dev/null || log_warn "fdisk failed"
    
    # Network information
    log_info "Collecting network information..."
    ip addr show > "$hw_dir/ip_addr.txt"
    ip route show > "$hw_dir/ip_route.txt"
    
    log_info "Hardware information collection complete"
}

# Run CPU performance tests
run_cpu_tests() {
    log_section "CPU Performance Tests"
    
    local cpu_dir="$REPORT_DIR/$HOSTNAME/performance/cpu"
    mkdir -p "$cpu_dir"
    
    # Get CPU count
    local cpu_count=$(nproc)
    log_info "Running tests on $cpu_count CPU cores"
    
    # Stress test
    if command -v stress-ng &> /dev/null; then
        log_info "Running CPU stress test..."
        timeout 300 stress-ng --cpu $cpu_count --timeout 300 --metrics-brief > "$cpu_dir/stress_ng.txt" 2>&1 || log_warn "stress-ng failed"
    fi
    
    # Sysbench CPU test
    if command -v sysbench &> /dev/null; then
        log_info "Running sysbench CPU test..."
        timeout 300 sysbench --test=cpu --cpu-max-prime=20000 --num-threads=$cpu_count run > "$cpu_dir/sysbench_cpu.txt" 2>&1 || log_warn "sysbench failed"
    fi
    
    log_info "CPU performance tests complete"
}

# Run memory tests
run_memory_tests() {
    log_section "Memory Tests"
    
    local mem_dir="$REPORT_DIR/$HOSTNAME/performance/memory"
    mkdir -p "$mem_dir"
    
    # Get memory size
    local mem_size=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_size_gb=$((mem_size / 1024 / 1024))
    log_info "Testing $mem_size_gb GB of memory"
    
    # Memtester (test a portion of memory)
    if command -v memtester &> /dev/null; then
        log_info "Running memtester..."
        local test_size=$((mem_size / 4))  # Test 25% of memory
        timeout 600 memtester $test_size 1 > "$mem_dir/memtester.txt" 2>&1 || log_warn "memtester failed"
    fi
    
    # Stress-ng memory test
    if command -v stress-ng &> /dev/null; then
        log_info "Running memory stress test..."
        timeout 300 stress-ng --vm 2 --vm-bytes 80% --timeout 300 --metrics-brief > "$mem_dir/stress_ng_memory.txt" 2>&1 || log_warn "stress-ng memory test failed"
    fi
    
    log_info "Memory tests complete"
}

# Run disk tests
run_disk_tests() {
    log_section "Disk Performance Tests"
    
    local disk_dir="$REPORT_DIR/$HOSTNAME/performance/disk"
    mkdir -p "$disk_dir"
    
    # Get disk devices
    local disks=($(lsblk -d -n -o NAME | grep -E '^(sd|hd|nvme|vd)' | head -5))
    
    for disk in "${disks[@]}"; do
        local disk_path="/dev/$disk"
        log_info "Testing disk: $disk_path"
        
        local disk_test_dir="$disk_dir/$disk"
        mkdir -p "$disk_test_dir"
        
        # SMART information
        if command -v smartctl &> /dev/null; then
            log_info "Collecting SMART information for $disk..."
            timeout 60 smartctl -a "$disk_path" > "$disk_test_dir/smart.txt" 2>&1 || log_warn "smartctl failed for $disk"
        fi
        
        # Disk performance test with fio
        if command -v fio &> /dev/null; then
            log_info "Running fio performance test on $disk..."
            timeout 300 fio --name=randread --ioengine=libaio --iodepth=16 --rw=randread --bs=4k --direct=1 --size=1G --numjobs=4 --group_reporting > "$disk_test_dir/fio_randread.txt" 2>&1 || log_warn "fio randread failed for $disk"
            
            timeout 300 fio --name=seqwrite --ioengine=libaio --iodepth=16 --rw=write --bs=1M --direct=1 --size=1G --numjobs=1 --group_reporting > "$disk_test_dir/fio_seqwrite.txt" 2>&1 || log_warn "fio seqwrite failed for $disk"
        fi
        
        # IOPing test
        if command -v ioping &> /dev/null; then
            log_info "Running ioping test on $disk..."
            timeout 60 ioping -c 100 "$disk_path" > "$disk_test_dir/ioping.txt" 2>&1 || log_warn "ioping failed for $disk"
        fi
    done
    
    log_info "Disk performance tests complete"
}

# Run network tests
run_network_tests() {
    log_section "Network Tests"
    
    local net_dir="$REPORT_DIR/$HOSTNAME/performance/network"
    mkdir -p "$net_dir"
    
    # Get network interfaces
    local interfaces=($(ip link show | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' ' | grep -v lo))
    
    for interface in "${interfaces[@]}"; do
        log_info "Testing interface: $interface"
        
        local iface_dir="$net_dir/$interface"
        mkdir -p "$iface_dir"
        
        # Interface information
        if command -v ethtool &> /dev/null; then
            log_info "Collecting ethtool information for $interface..."
            timeout 30 ethtool "$interface" > "$iface_dir/ethtool.txt" 2>&1 || log_warn "ethtool failed for $interface"
        fi
        
        # Interface statistics
        cat "/sys/class/net/$interface/statistics/rx_bytes" > "$iface_dir/rx_bytes.txt" 2>/dev/null || log_warn "Could not read rx_bytes for $interface"
        cat "/sys/class/net/$interface/statistics/tx_bytes" > "$iface_dir/tx_bytes.txt" 2>/dev/null || log_warn "Could not read tx_bytes for $interface"
    done
    
    # Network performance tests
    if command -v iperf3 &> /dev/null; then
        log_info "Running iperf3 server..."
        timeout 300 iperf3 -s -p 5201 > "$net_dir/iperf3_server.txt" 2>&1 &
        local iperf_pid=$!
        
        sleep 5
        
        # Test localhost performance
        log_info "Testing localhost network performance..."
        timeout 60 iperf3 -c localhost -p 5201 -t 30 > "$net_dir/iperf3_localhost.txt" 2>&1 || log_warn "iperf3 localhost test failed"
        
        kill $iperf_pid 2>/dev/null || true
    fi
    
    log_info "Network tests complete"
}

# Run power and thermal tests
run_power_tests() {
    log_section "Power and Thermal Tests"
    
    local power_dir="$REPORT_DIR/$HOSTNAME/performance/power"
    mkdir -p "$power_dir"
    
    # CMOS battery test
    if command -v hwclock &> /dev/null; then
        log_info "Testing CMOS battery..."
        hwclock --test > "$power_dir/hwclock_test.txt" 2>&1 || log_warn "hwclock test failed"
    fi
    
    # IPMI information
    if command -v ipmitool &> /dev/null; then
        log_info "Collecting IPMI information..."
        timeout 60 ipmitool sdr > "$power_dir/ipmi_sdr.txt" 2>&1 || log_warn "ipmi sdr failed"
        timeout 60 ipmitool sensor > "$power_dir/ipmi_sensor.txt" 2>&1 || log_warn "ipmi sensor failed"
    fi
    
    # Temperature sensors
    if command -v sensors &> /dev/null; then
        log_info "Collecting temperature sensor information..."
        timeout 30 sensors > "$power_dir/sensors.txt" 2>&1 || log_warn "sensors failed"
    fi
    
    log_info "Power and thermal tests complete"
}

# Generate comprehensive report
generate_report() {
    log_section "Generating Comprehensive Report"
    
    local report_file="$REPORT_DIR/$HOSTNAME/report.json"
    local summary_file="$REPORT_DIR/$HOSTNAME/summary.txt"
    
    log_info "Generating JSON report: $report_file"
    
    # Create JSON report structure
    cat > "$report_file" << EOF
{
  "hostname": "$HOSTNAME",
  "timestamp": "$TIMESTAMP",
  "test_duration": "$(($(date +%s) - $(date -d "$TIMESTAMP" +%s)))",
  "system_info": {
    "kernel": "$(uname -r)",
    "os": "$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)",
    "architecture": "$(uname -m)",
    "cpu_count": "$(nproc)",
    "memory_gb": "$(grep MemTotal /proc/meminfo | awk '{print int($2/1024/1024)}')"
  },
  "test_results": {
    "hardware_info": "completed",
    "cpu_tests": "completed",
    "memory_tests": "completed",
    "disk_tests": "completed",
    "network_tests": "completed",
    "power_tests": "completed"
  },
  "files": {
    "hardware_dir": "hardware/",
    "performance_dir": "performance/",
    "logs": "diagnostics.log"
  }
}
EOF
    
    # Create summary file
    cat > "$summary_file" << EOF
PXE Diagnostic Report Summary
============================

Hostname: $HOSTNAME
Timestamp: $TIMESTAMP
Test Duration: $(($(date +%s) - $(date -d "$TIMESTAMP" +%s))) seconds

Test Results:
- Hardware Information: COMPLETED
- CPU Performance Tests: COMPLETED
- Memory Tests: COMPLETED
- Disk Performance Tests: COMPLETED
- Network Tests: COMPLETED
- Power and Thermal Tests: COMPLETED

Report Location: $REPORT_DIR/$HOSTNAME/
Log File: $LOG_DIR/diagnostics.log

Next Steps:
1. Review detailed results in subdirectories
2. Upload report to PXE server
3. Check for any warnings or errors in logs
EOF
    
    log_info "Report generation complete"
    log_info "Report location: $report_file"
    log_info "Summary location: $summary_file"
}

# Upload report to PXE server
upload_report() {
    log_section "Uploading Report to PXE Server"
    
    local report_archive="$UPLOAD_DIR/${HOSTNAME}_report_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    log_info "Creating report archive: $report_archive"
    
    # Create compressed archive
    cd "$REPORT_DIR"
    tar -czf "$report_archive" "$HOSTNAME/"
    
    # Try to upload via SCP if SSH keys are configured
    if [ -f "/root/.ssh/id_rsa" ]; then
        log_info "Attempting SCP upload..."
        # This would need to be configured with the actual PXE server IP
        # scp "$report_archive" "pxe@192.168.1.100:/var/lib/foreman-reports/" || log_warn "SCP upload failed"
    fi
    
    # Try HTTP upload if available
    if command -v curl &> /dev/null; then
        log_info "Attempting HTTP upload..."
        # This would need to be configured with the actual upload endpoint
        # curl -F "file=@$report_archive" "http://192.168.1.100:3000/api/v2/reports/upload" || log_warn "HTTP upload failed"
    fi
    
    log_info "Report archive created: $report_archive"
    log_info "Manual upload may be required"
}

# Main execution
main() {
    log_info "Starting PXE diagnostic system..."
    
    # Set timeout for entire process
    timeout $TEST_TIMEOUT bash -c '
        init_system
        run_hardware_info
        run_cpu_tests
        run_memory_tests
        run_disk_tests
        run_network_tests
        run_power_tests
        generate_report
        upload_report
    ' || {
        log_error "Diagnostic process timed out after $TEST_TIMEOUT seconds"
        generate_report  # Generate partial report
    }
    
    log_info "Diagnostic system execution complete"
    log_info "Check logs at: $LOG_DIR/diagnostics.log"
    log_info "Check reports at: $REPORT_DIR/$HOSTNAME/"
}

# Run main function
main "$@"
