#!/usr/bin/env python3
"""
Health Metrics Bridge for Single Container Setup
Exposes TransmissionVPN internal health metrics via HTTP endpoint
Runs on host, reads metrics from container
"""

import subprocess
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

# Configuration
PORT = 8080
CONTAINER_NAME = "transmission"

class HealthBridgeHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            self.serve_health_metrics()
        elif self.path == '/health':
            self.serve_health_status()
        else:
            self.send_response(404)
            self.end_headers()
    
    def serve_health_metrics(self):
        """Serve health metrics in Prometheus format"""
        try:
            # Get internal metrics from container
            cmd = f"docker exec {CONTAINER_NAME} cat /tmp/metrics.txt 2>/dev/null"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
            
            if result.returncode == 0 and result.stdout.strip():
                metrics_data = result.stdout
            else:
                # Fallback: generate basic metrics from healthcheck
                metrics_data = self.generate_basic_metrics()
            
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
            self.end_headers()
            self.wfile.write(metrics_data.encode())
            
        except Exception as e:
            print(f"Error serving metrics: {e}")
            self.send_response(503)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'# Health metrics temporarily unavailable\n')
    
    def serve_health_status(self):
        """Serve health status in JSON format"""
        try:
            # Run healthcheck
            cmd = f"docker exec {CONTAINER_NAME} /root/healthcheck.sh 2>/dev/null"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
            
            # Check container status
            container_cmd = f"docker ps --filter name={CONTAINER_NAME} --format '{{{{.Status}}}}'"
            container_result = subprocess.run(container_cmd, shell=True, capture_output=True, text=True, timeout=5)
            
            health_data = {
                "timestamp": int(time.time()),
                "container_running": 1 if container_result.returncode == 0 and "Up" in container_result.stdout else 0,
                "healthcheck_exit_code": result.returncode,
                "healthcheck_passed": 1 if result.returncode == 0 else 0,
                "status": "healthy" if result.returncode == 0 else "unhealthy"
            }
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(health_data, indent=2).encode())
            
        except Exception as e:
            print(f"Error serving health status: {e}")
            self.send_response(503)
            self.end_headers()
    
    def generate_basic_metrics(self):
        """Generate basic metrics if internal metrics file is not available"""
        metrics = []
        timestamp = int(time.time())
        
        try:
            # Check container status
            cmd = f"docker ps --filter name={CONTAINER_NAME} --format '{{{{.Status}}}}'"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
            container_running = 1 if result.returncode == 0 and "Up" in result.stdout else 0
            
            # Run healthcheck
            cmd = f"docker exec {CONTAINER_NAME} /root/healthcheck.sh 2>/dev/null"
            health_result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
            overall_health = 1 if health_result.returncode == 0 else 0
            
            # Check web UI
            cmd = f"docker exec {CONTAINER_NAME} curl -sf http://localhost:9091/transmission/web/ >/dev/null 2>&1"
            web_result = subprocess.run(cmd, shell=True, timeout=5)
            web_ui_up = 1 if web_result.returncode == 0 else 0
            
            # Check VPN interface
            cmd = f"docker exec {CONTAINER_NAME} ip link show 2>/dev/null | grep -E '(tun|wg|tap).*UP' || echo ''"
            vpn_result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
            vpn_connected = 1 if vpn_result.stdout.strip() else 0
            
            # Generate Prometheus format
            metrics.append("# HELP transmissionvpn_container_running Container is running")
            metrics.append("# TYPE transmissionvpn_container_running gauge")
            metrics.append(f"transmissionvpn_container_running {container_running} {timestamp}")
            
            metrics.append("# HELP transmissionvpn_overall_health_status Overall health status")
            metrics.append("# TYPE transmissionvpn_overall_health_status gauge")
            metrics.append(f"transmissionvpn_overall_health_status {overall_health} {timestamp}")
            
            metrics.append("# HELP transmissionvpn_web_ui_up Web UI is responding")
            metrics.append("# TYPE transmissionvpn_web_ui_up gauge")
            metrics.append(f"transmissionvpn_web_ui_up {web_ui_up} {timestamp}")
            
            metrics.append("# HELP transmissionvpn_vpn_connected VPN interface is up")
            metrics.append("# TYPE transmissionvpn_vpn_connected gauge")
            metrics.append(f"transmissionvpn_vpn_connected {vpn_connected} {timestamp}")
            
        except Exception as e:
            print(f"Error generating basic metrics: {e}")
            metrics.append("# Error generating metrics")
        
        return '\n'.join(metrics) + '\n'
    
    def log_message(self, format, *args):
        # Suppress default logging
        pass

def main():
    print(f"Starting TransmissionVPN Health Bridge on port {PORT}")
    print(f"Monitoring container: {CONTAINER_NAME}")
    print(f"Endpoints:")
    print(f"  http://localhost:{PORT}/metrics (Prometheus format)")
    print(f"  http://localhost:{PORT}/health (JSON status)")
    
    try:
        server = HTTPServer(('0.0.0.0', PORT), HealthBridgeHandler)
        print(f"Health bridge running at http://localhost:{PORT}")
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down health bridge")
    except Exception as e:
        print(f"Server error: {e}")

if __name__ == "__main__":
    main() 