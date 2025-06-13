#!/usr/bin/env python3
"""
Health Metrics Server for TransmissionVPN
Exposes VPN and container health metrics in Prometheus format
"""

import os
import time
import subprocess
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse
import threading

# Configuration
PORT = int(os.environ.get('HEALTH_METRICS_PORT', 8080))
TRANSMISSION_CONTAINER = os.environ.get('TRANSMISSION_CONTAINER', 'transmission')
SCRAPE_INTERVAL = int(os.environ.get('HEALTH_SCRAPE_INTERVAL', 30))

class HealthMetrics:
    def __init__(self):
        self.metrics = {}
        self.last_update = 0
        self.lock = threading.Lock()
    
    def run_docker_command(self, cmd):
        """Execute docker command and return output"""
        try:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
            return result.stdout.strip() if result.returncode == 0 else None
        except Exception:
            return None
    
    def check_container_status(self):
        """Check if TransmissionVPN container is running"""
        cmd = f"docker ps --filter name={TRANSMISSION_CONTAINER} --format '{{{{.Status}}}}'"
        status = self.run_docker_command(cmd)
        
        if status and "Up" in status:
            self.metrics['transmissionvpn_container_running'] = 1
            # Extract uptime if possible
            if "Up" in status:
                self.metrics['transmissionvpn_container_healthy'] = 1
        else:
            self.metrics['transmissionvpn_container_running'] = 0
            self.metrics['transmissionvpn_container_healthy'] = 0
    
    def check_vpn_status(self):
        """Check VPN interface status"""
        # Check for VPN interfaces in container
        cmd = f"docker exec {TRANSMISSION_CONTAINER} ip link show 2>/dev/null | grep -E '(tun|wg|tap)' || echo ''"
        vpn_interfaces = self.run_docker_command(cmd)
        
        if vpn_interfaces:
            self.metrics['transmissionvpn_vpn_interface_up'] = 1
            # Check if interface is actually UP
            cmd = f"docker exec {TRANSMISSION_CONTAINER} ip link show | grep -E '(tun|wg|tap).*UP' || echo ''"
            vpn_up = self.run_docker_command(cmd)
            self.metrics['transmissionvpn_vpn_connected'] = 1 if vpn_up else 0
        else:
            self.metrics['transmissionvpn_vpn_interface_up'] = 0
            self.metrics['transmissionvpn_vpn_connected'] = 0
    
    def check_transmission_web(self):
        """Check if Transmission web UI is responding"""
        cmd = f"docker exec {TRANSMISSION_CONTAINER} curl -sf http://localhost:9091/transmission/web/ >/dev/null 2>&1 && echo 'ok' || echo 'fail'"
        result = self.run_docker_command(cmd)
        self.metrics['transmissionvpn_web_ui_up'] = 1 if result == 'ok' else 0
    
    def check_external_ip(self):
        """Check external IP to verify VPN is working"""
        cmd = f"docker exec {TRANSMISSION_CONTAINER} curl -sf --max-time 5 ifconfig.me 2>/dev/null || echo ''"
        external_ip = self.run_docker_command(cmd)
        
        if external_ip:
            self.metrics['transmissionvpn_external_ip_reachable'] = 1
            # Store IP hash for change detection (privacy)
            ip_hash = hash(external_ip) % 10000
            self.metrics['transmissionvpn_external_ip_hash'] = ip_hash
        else:
            self.metrics['transmissionvpn_external_ip_reachable'] = 0
    
    def check_disk_space(self):
        """Check available disk space in downloads directory"""
        cmd = f"docker exec {TRANSMISSION_CONTAINER} df /downloads 2>/dev/null | tail -1 | awk '{{print $4}}' || echo '0'"
        available_kb = self.run_docker_command(cmd)
        
        if available_kb and available_kb.isdigit():
            # Convert KB to bytes
            self.metrics['transmissionvpn_disk_available_bytes'] = int(available_kb) * 1024
            
            # Get usage percentage
            cmd = f"docker exec {TRANSMISSION_CONTAINER} df /downloads 2>/dev/null | tail -1 | awk '{{print $5}}' | sed 's/%//' || echo '0'"
            usage_percent = self.run_docker_command(cmd)
            if usage_percent and usage_percent.isdigit():
                self.metrics['transmissionvpn_disk_usage_percent'] = int(usage_percent)
    
    def collect_all_metrics(self):
        """Collect all health metrics"""
        with self.lock:
            try:
                self.check_container_status()
                self.check_vpn_status()
                self.check_transmission_web()
                self.check_external_ip()
                self.check_disk_space()
                self.last_update = time.time()
                print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Metrics updated")
            except Exception as e:
                print(f"Error collecting metrics: {e}")
    
    def get_prometheus_metrics(self):
        """Return metrics in Prometheus format"""
        with self.lock:
            lines = []
            lines.append("# HELP transmissionvpn_container_running Container is running (1=yes, 0=no)")
            lines.append("# TYPE transmissionvpn_container_running gauge")
            lines.append(f"transmissionvpn_container_running {self.metrics.get('transmissionvpn_container_running', 0)}")
            
            lines.append("# HELP transmissionvpn_container_healthy Container is healthy (1=yes, 0=no)")
            lines.append("# TYPE transmissionvpn_container_healthy gauge")
            lines.append(f"transmissionvpn_container_healthy {self.metrics.get('transmissionvpn_container_healthy', 0)}")
            
            lines.append("# HELP transmissionvpn_vpn_interface_up VPN interface exists (1=yes, 0=no)")
            lines.append("# TYPE transmissionvpn_vpn_interface_up gauge")
            lines.append(f"transmissionvpn_vpn_interface_up {self.metrics.get('transmissionvpn_vpn_interface_up', 0)}")
            
            lines.append("# HELP transmissionvpn_vpn_connected VPN is connected (1=yes, 0=no)")
            lines.append("# TYPE transmissionvpn_vpn_connected gauge")
            lines.append(f"transmissionvpn_vpn_connected {self.metrics.get('transmissionvpn_vpn_connected', 0)}")
            
            lines.append("# HELP transmissionvpn_web_ui_up Web UI is responding (1=yes, 0=no)")
            lines.append("# TYPE transmissionvpn_web_ui_up gauge")
            lines.append(f"transmissionvpn_web_ui_up {self.metrics.get('transmissionvpn_web_ui_up', 0)}")
            
            lines.append("# HELP transmissionvpn_external_ip_reachable Can reach external IP check service (1=yes, 0=no)")
            lines.append("# TYPE transmissionvpn_external_ip_reachable gauge")
            lines.append(f"transmissionvpn_external_ip_reachable {self.metrics.get('transmissionvpn_external_ip_reachable', 0)}")
            
            if 'transmissionvpn_external_ip_hash' in self.metrics:
                lines.append("# HELP transmissionvpn_external_ip_hash Hash of external IP for change detection")
                lines.append("# TYPE transmissionvpn_external_ip_hash gauge")
                lines.append(f"transmissionvpn_external_ip_hash {self.metrics.get('transmissionvpn_external_ip_hash', 0)}")
            
            if 'transmissionvpn_disk_available_bytes' in self.metrics:
                lines.append("# HELP transmissionvpn_disk_available_bytes Available disk space in bytes")
                lines.append("# TYPE transmissionvpn_disk_available_bytes gauge")
                lines.append(f"transmissionvpn_disk_available_bytes {self.metrics.get('transmissionvpn_disk_available_bytes', 0)}")
            
            if 'transmissionvpn_disk_usage_percent' in self.metrics:
                lines.append("# HELP transmissionvpn_disk_usage_percent Disk usage percentage")
                lines.append("# TYPE transmissionvpn_disk_usage_percent gauge")
                lines.append(f"transmissionvpn_disk_usage_percent {self.metrics.get('transmissionvpn_disk_usage_percent', 0)}")
            
            lines.append(f"# Last updated: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(self.last_update))}")
            
            return '\n'.join(lines) + '\n'

class MetricsHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, health_metrics=None, **kwargs):
        self.health_metrics = health_metrics
        super().__init__(*args, **kwargs)
    
    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
            self.end_headers()
            
            metrics_data = self.health_metrics.get_prometheus_metrics()
            self.wfile.write(metrics_data.encode())
        
        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            health_data = {
                "status": "healthy",
                "timestamp": int(time.time()),
                "last_metrics_update": self.health_metrics.last_update
            }
            self.wfile.write(json.dumps(health_data).encode())
        
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        # Suppress default logging
        pass

def create_handler_class(health_metrics):
    def handler(*args, **kwargs):
        MetricsHandler(*args, health_metrics=health_metrics, **kwargs)
    return handler

def main():
    print(f"Starting TransmissionVPN Health Metrics Server on port {PORT}")
    print(f"Monitoring container: {TRANSMISSION_CONTAINER}")
    print(f"Scrape interval: {SCRAPE_INTERVAL}s")
    
    # Initialize metrics collector
    health_metrics = HealthMetrics()
    
    # Collect initial metrics
    health_metrics.collect_all_metrics()
    
    # Start metrics collection thread
    def metrics_loop():
        while True:
            try:
                time.sleep(SCRAPE_INTERVAL)
                health_metrics.collect_all_metrics()
            except KeyboardInterrupt:
                break
            except Exception as e:
                print(f"Error in metrics loop: {e}")
                time.sleep(5)
    
    metrics_thread = threading.Thread(target=metrics_loop, daemon=True)
    metrics_thread.start()
    
    # Start HTTP server
    try:
        handler_class = create_handler_class(health_metrics)
        server = HTTPServer(('0.0.0.0', PORT), handler_class)
        print(f"Health metrics available at:")
        print(f"  http://localhost:{PORT}/metrics (Prometheus format)")
        print(f"  http://localhost:{PORT}/health (JSON status)")
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down health metrics server")
    except Exception as e:
        print(f"Server error: {e}")

if __name__ == "__main__":
    main() 