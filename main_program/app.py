#!/usr/bin/env python3
"""
PXE Telemetry & Diagnostics System - Main Program
Central report processing and API server
"""

import os
import json
import logging
import argparse
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any

from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
from werkzeug.utils import secure_filename

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class DiagnosticReportProcessor:
    """Processes and manages diagnostic reports"""
    
    def __init__(self, reports_dir: str = "/var/lib/foreman-reports"):
        self.reports_dir = Path(reports_dir)
        self.reports_dir.mkdir(parents=True, exist_ok=True)
        
        # Ensure subdirectories exist
        (self.reports_dir / "processed").mkdir(exist_ok=True)
        (self.reports_dir / "failed").mkdir(exist_ok=True)
        (self.reports_dir / "archive").mkdir(exist_ok=True)
    
    def scan_reports(self) -> List[Dict[str, Any]]:
        """Scan for available reports"""
        reports = []
        
        for report_dir in self.reports_dir.glob("*"):
            if report_dir.is_dir() and not report_dir.name.startswith('.'):
                report_file = report_dir / "report.json"
                if report_file.exists():
                    try:
                        with open(report_file, 'r') as f:
                            report_data = json.load(f)
                            report_data['_path'] = str(report_dir)
                            report_data['_last_modified'] = report_file.stat().st_mtime
                            reports.append(report_data)
                    except (json.JSONDecodeError, IOError) as e:
                        logger.warning(f"Failed to read report {report_file}: {e}")
        
        # Sort by timestamp (newest first)
        reports.sort(key=lambda x: x.get('timestamp', ''), reverse=True)
        return reports
    
    def get_report(self, hostname: str) -> Optional[Dict[str, Any]]:
        """Get specific report by hostname"""
        report_dir = self.reports_dir / hostname
        report_file = report_dir / "report.json"
        
        if not report_file.exists():
            return None
        
        try:
            with open(report_file, 'r') as f:
                report_data = json.load(f)
                report_data['_path'] = str(report_dir)
                return report_data
        except (json.JSONDecodeError, IOError) as e:
            logger.error(f"Failed to read report {report_file}: {e}")
            return None
    
    def process_report(self, report_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process and analyze a diagnostic report"""
        processed = {
            'hostname': report_data.get('hostname', 'unknown'),
            'timestamp': report_data.get('timestamp', ''),
            'processed_at': datetime.utcnow().isoformat(),
            'analysis': {},
            'health_score': 0,
            'issues': [],
            'recommendations': []
        }
        
        # Analyze system information
        system_info = report_data.get('system_info', {})
        processed['analysis']['system'] = {
            'cpu_count': system_info.get('cpu_count', 0),
            'memory_gb': system_info.get('memory_gb', 0),
            'architecture': system_info.get('architecture', 'unknown'),
            'kernel': system_info.get('kernel', 'unknown')
        }
        
        # Check for performance issues
        performance_dir = Path(report_data.get('_path', '')) / "performance"
        if performance_dir.exists():
            processed['analysis']['performance'] = self._analyze_performance(performance_dir)
        
        # Calculate health score
        processed['health_score'] = self._calculate_health_score(processed['analysis'])
        
        # Generate recommendations
        processed['recommendations'] = self._generate_recommendations(processed['analysis'])
        
        return processed
    
    def _analyze_performance(self, perf_dir: Path) -> Dict[str, Any]:
        """Analyze performance test results"""
        analysis = {
            'cpu': {'status': 'unknown', 'score': 0},
            'memory': {'status': 'unknown', 'score': 0},
            'disk': {'status': 'unknown', 'score': 0},
            'network': {'status': 'unknown', 'score': 0}
        }
        
        # Analyze CPU tests
        cpu_dir = perf_dir / "cpu"
        if cpu_dir.exists():
            analysis['cpu'] = self._analyze_cpu_tests(cpu_dir)
        
        # Analyze memory tests
        mem_dir = perf_dir / "memory"
        if mem_dir.exists():
            analysis['memory'] = self._analyze_memory_tests(mem_dir)
        
        # Analyze disk tests
        disk_dir = perf_dir / "disk"
        if disk_dir.exists():
            analysis['disk'] = self._analyze_disk_tests(disk_dir)
        
        # Analyze network tests
        net_dir = perf_dir / "network"
        if net_dir.exists():
            analysis['network'] = self._analyze_network_tests(net_dir)
        
        return analysis
    
    def _analyze_cpu_tests(self, cpu_dir: Path) -> Dict[str, Any]:
        """Analyze CPU test results"""
        analysis = {'status': 'unknown', 'score': 0, 'details': {}}
        
        # Check sysbench results
        sysbench_file = cpu_dir / "sysbench_cpu.txt"
        if sysbench_file.exists():
            try:
                with open(sysbench_file, 'r') as f:
                    content = f.read()
                    # Extract execution time from sysbench output
                    if 'execution time' in content:
                        analysis['details']['sysbench'] = 'completed'
                        analysis['score'] += 25
                    else:
                        analysis['details']['sysbench'] = 'failed'
            except IOError:
                analysis['details']['sysbench'] = 'error'
        
        # Check stress-ng results
        stress_file = cpu_dir / "stress_ng.txt"
        if stress_file.exists():
            try:
                with open(stress_file, 'r') as f:
                    content = f.read()
                    if 'completed' in content:
                        analysis['details']['stress_ng'] = 'completed'
                        analysis['score'] += 25
                    else:
                        analysis['details']['stress_ng'] = 'failed'
            except IOError:
                analysis['details']['stress_ng'] = 'error'
        
        # Determine overall status
        if analysis['score'] >= 50:
            analysis['status'] = 'good'
        elif analysis['score'] >= 25:
            analysis['status'] = 'fair'
        else:
            analysis['status'] = 'poor'
        
        return analysis
    
    def _analyze_memory_tests(self, mem_dir: Path) -> Dict[str, Any]:
        """Analyze memory test results"""
        analysis = {'status': 'unknown', 'score': 0, 'details': {}}
        
        # Check memtester results
        memtester_file = mem_dir / "memtester.txt"
        if memtester_file.exists():
            try:
                with open(memtester_file, 'r') as f:
                    content = f.read()
                    if 'PASS' in content and 'FAIL' not in content:
                        analysis['details']['memtester'] = 'passed'
                        analysis['score'] += 50
                    else:
                        analysis['details']['memtester'] = 'failed'
            except IOError:
                analysis['details']['memtester'] = 'error'
        
        # Check stress-ng memory results
        stress_file = mem_dir / "stress_ng_memory.txt"
        if stress_file.exists():
            try:
                with open(stress_file, 'r') as f:
                    content = f.read()
                    if 'completed' in content:
                        analysis['details']['stress_ng'] = 'completed'
                        analysis['score'] += 50
                    else:
                        analysis['details']['stress_ng'] = 'failed'
            except IOError:
                analysis['details']['stress_ng'] = 'error'
        
        # Determine overall status
        if analysis['score'] >= 75:
            analysis['status'] = 'good'
        elif analysis['score'] >= 50:
            analysis['status'] = 'fair'
        else:
            analysis['status'] = 'poor'
        
        return analysis
    
    def _analyze_disk_tests(self, disk_dir: Path) -> Dict[str, Any]:
        """Analyze disk test results"""
        analysis = {'status': 'unknown', 'score': 0, 'details': {}}
        
        # Check each disk
        for disk_subdir in disk_dir.iterdir():
            if disk_subdir.is_dir():
                disk_name = disk_subdir.name
                analysis['details'][disk_name] = {}
                
                # Check SMART status
                smart_file = disk_subdir / "smart.txt"
                if smart_file.exists():
                    try:
                        with open(smart_file, 'r') as f:
                            content = f.read()
                            if 'SMART overall-health self-assessment test result: PASSED' in content:
                                analysis['details'][disk_name]['smart'] = 'passed'
                                analysis['score'] += 20
                            else:
                                analysis['details'][disk_name]['smart'] = 'failed'
                    except IOError:
                        analysis['details'][disk_name]['smart'] = 'error'
                
                # Check fio results
                fio_read_file = disk_subdir / "fio_randread.txt"
                if fio_read_file.exists():
                    try:
                        with open(fio_read_file, 'r') as f:
                            content = f.read()
                            if 'IOPS' in content:
                                analysis['details'][disk_name]['fio_read'] = 'completed'
                                analysis['score'] += 15
                            else:
                                analysis['details'][disk_name]['fio_read'] = 'failed'
                    except IOError:
                        analysis['details'][disk_name]['fio_read'] = 'error'
        
        # Determine overall status
        if analysis['score'] >= 50:
            analysis['status'] = 'good'
        elif analysis['score'] >= 25:
            analysis['status'] = 'fair'
        else:
            analysis['status'] = 'poor'
        
        return analysis
    
    def _analyze_network_tests(self, net_dir: Path) -> Dict[str, Any]:
        """Analyze network test results"""
        analysis = {'status': 'unknown', 'score': 0, 'details': {}}
        
        # Check iperf3 results
        iperf_file = net_dir / "iperf3_localhost.txt"
        if iperf_file.exists():
            try:
                with open(iperf_file, 'r') as f:
                    content = f.read()
                    if 'receiver' in content and 'sender' in content:
                        analysis['details']['iperf3'] = 'completed'
                        analysis['score'] += 50
                    else:
                        analysis['details']['iperf3'] = 'failed'
            except IOError:
                analysis['details']['iperf3'] = 'error'
        
        # Check interface information
        for iface_dir in net_dir.iterdir():
            if iface_dir.is_dir() and iface_dir.name != 'lo':
                ethtool_file = iface_dir / "ethtool.txt"
                if ethtool_file.exists():
                    analysis['details'][iface_dir.name] = 'configured'
                    analysis['score'] += 25
        
        # Determine overall status
        if analysis['score'] >= 75:
            analysis['status'] = 'good'
        elif analysis['score'] >= 50:
            analysis['status'] = 'fair'
        else:
            analysis['status'] = 'poor'
        
        return analysis
    
    def _calculate_health_score(self, analysis: Dict[str, Any]) -> int:
        """Calculate overall health score"""
        total_score = 0
        max_score = 0
        
        # System score (25 points)
        if 'system' in analysis:
            total_score += 25
            max_score += 25
        
        # Performance scores (75 points total)
        performance = analysis.get('performance', {})
        for component in ['cpu', 'memory', 'disk', 'network']:
            if component in performance:
                score = performance[component].get('score', 0)
                max_possible = 100
                total_score += (score / max_possible) * 18.75  # 75/4 = 18.75 per component
                max_score += 18.75
        
        if max_score == 0:
            return 0
        
        return int((total_score / max_score) * 100)
    
    def _generate_recommendations(self, analysis: Dict[str, Any]) -> List[str]:
        """Generate recommendations based on analysis"""
        recommendations = []
        
        performance = analysis.get('performance', {})
        
        # CPU recommendations
        cpu = performance.get('cpu', {})
        if cpu.get('status') == 'poor':
            recommendations.append("CPU performance is poor. Consider checking for thermal throttling or background processes.")
        
        # Memory recommendations
        memory = performance.get('memory', {})
        if memory.get('status') == 'poor':
            recommendations.append("Memory tests failed. Check for faulty RAM modules or memory configuration.")
        
        # Disk recommendations
        disk = performance.get('disk', {})
        if disk.get('status') == 'poor':
            recommendations.append("Disk performance is poor. Check SMART status and consider replacing failing drives.")
        
        # Network recommendations
        network = performance.get('network', {})
        if network.get('status') == 'poor':
            recommendations.append("Network performance is poor. Check cable connections and switch configuration.")
        
        # General recommendations
        if not recommendations:
            recommendations.append("System appears to be healthy. Continue monitoring for any changes.")
        
        return recommendations

# Initialize Flask app
app = Flask(__name__)
CORS(app)

# Initialize report processor
processor = DiagnosticReportProcessor()

@app.route('/api/v1/reports', methods=['GET'])
def list_reports():
    """List all available reports"""
    try:
        reports = processor.scan_reports()
        return jsonify({
            'status': 'success',
            'count': len(reports),
            'reports': reports
        })
    except Exception as e:
        logger.error(f"Failed to list reports: {e}")
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

@app.route('/api/v1/reports/<hostname>', methods=['GET'])
def get_report(hostname):
    """Get specific report by hostname"""
    try:
        report = processor.get_report(hostname)
        if report is None:
            return jsonify({
                'status': 'error',
                'message': f'Report not found for hostname: {hostname}'
            }), 404
        
        return jsonify({
            'status': 'success',
            'report': report
        })
    except Exception as e:
        logger.error(f"Failed to get report for {hostname}: {e}")
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

@app.route('/api/v1/reports/<hostname>/analyze', methods=['GET'])
def analyze_report(hostname):
    """Analyze and process a specific report"""
    try:
        report = processor.get_report(hostname)
        if report is None:
            return jsonify({
                'status': 'error',
                'message': f'Report not found for hostname: {hostname}'
            }), 404
        
        analysis = processor.process_report(report)
        return jsonify({
            'status': 'success',
            'analysis': analysis
        })
    except Exception as e:
        logger.error(f"Failed to analyze report for {hostname}: {e}")
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

@app.route('/api/v1/reports/upload', methods=['POST'])
def upload_report():
    """Upload a new diagnostic report"""
    try:
        if 'file' not in request.files:
            return jsonify({
                'status': 'error',
                'message': 'No file provided'
            }), 400
        
        file = request.files['file']
        if file.filename == '':
            return jsonify({
                'status': 'error',
                'message': 'No file selected'
            }), 400
        
        if file and file.filename.endswith('.tar.gz'):
            filename = secure_filename(file.filename)
            filepath = processor.reports_dir / filename
            
            file.save(str(filepath))
            
            # Extract the report
            import tarfile
            with tarfile.open(filepath, 'r:gz') as tar:
                tar.extractall(path=processor.reports_dir)
            
            # Remove the uploaded archive
            filepath.unlink()
            
            return jsonify({
                'status': 'success',
                'message': f'Report uploaded and extracted successfully: {filename}'
            })
        else:
            return jsonify({
                'status': 'error',
                'message': 'Invalid file format. Please upload a .tar.gz file'
            }), 400
    
    except Exception as e:
        logger.error(f"Failed to upload report: {e}")
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

@app.route('/api/v1/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'service': 'PXE Diagnostic Main Program'
    })

@app.route('/api/v1/stats', methods=['GET'])
def get_stats():
    """Get system statistics"""
    try:
        reports = processor.scan_reports()
        
        # Calculate statistics
        total_reports = len(reports)
        recent_reports = len([r for r in reports if 
                            datetime.fromisoformat(r.get('timestamp', '1970-01-01T00:00:00').replace('Z', '+00:00')) > 
                            datetime.utcnow() - timedelta(days=7)])
        
        # Count by status
        status_counts = {}
        for report in reports:
            status = report.get('test_results', {}).get('overall', 'unknown')
            status_counts[status] = status_counts.get(status, 0) + 1
        
        return jsonify({
            'status': 'success',
            'stats': {
                'total_reports': total_reports,
                'recent_reports_7d': recent_reports,
                'status_distribution': status_counts,
                'last_report': reports[0].get('timestamp') if reports else None
            }
        })
    except Exception as e:
        logger.error(f"Failed to get stats: {e}")
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='PXE Diagnostic Main Program')
    parser.add_argument('--host', default='0.0.0.0', help='Host to bind to')
    parser.add_argument('--port', type=int, default=5000, help='Port to bind to')
    parser.add_argument('--debug', action='store_true', help='Enable debug mode')
    parser.add_argument('--reports-dir', default='/var/lib/foreman-reports', help='Reports directory')
    
    args = parser.parse_args()
    
    # Update processor with custom reports directory
    processor = DiagnosticReportProcessor(args.reports_dir)
    
    logger.info(f"Starting PXE Diagnostic Main Program on {args.host}:{args.port}")
    logger.info(f"Reports directory: {args.reports_dir}")
    
    app.run(
        host=args.host,
        port=args.port,
        debug=args.debug
    )
