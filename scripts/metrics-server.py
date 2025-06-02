#!/usr/bin/env python3
"""
Prometheus metrics endpoint for transmissionvpn
Exposes health and performance metrics for monitoring integration
"""

import os
import re
import time
import json
import subprocess
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import logging

# Configuration
PORT = int(os.environ.get('METRICS_PORT', 8080))
CONTAINER_NAME = os.environ.get('CONTAINER_NAME', 'transmissionvpn')
METRICS_INTERVAL = int(os.environ.get('METRICS_INTERVAL', 30))
LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')

# Setup logging
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL.upper()),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('transmissionvpn-metrics')

class MetricsCollector:
    """Collects metrics from transmissionvpn container"""
    
    def __init__(self, container_name):
        self.container_name = container_name
        self.metrics = {}
        self.last_update = 0
        self.lock = threading.Lock()
        
    def run_docker_exec(self, command):
        """Execute command inside Docker container"""
        try:
            cmd = ['docker', 'exec', self.container_name] + command
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                return result.stdout.strip()
            else:
                logger.warning(f"Command failed: {' '.join(cmd)}, error: {result.stderr}")
                return None
        except subprocess.TimeoutExpired:
            logger.warning(f"Command timed out: {' '.join(command)}")
            return None
        except Exception as e:
            logger.error(f"Failed to execute command: {e}")
            return None
    
    def get_container_info(self):
        """Get basic container information"""
        try:
            # Check if container is running
            cmd = ['docker', 'ps', '--filter', f'name={self.container_name}', '--format', '{{.Status}}']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            
            if result.returncode == 0 and result.stdout.strip():
                status = result.stdout.strip()
                self.metrics['transmissionvpn_container_running'] = 1
                
                # Parse uptime from status
                if 'Up' in status:
                    # Extract uptime information
                    uptime_match = re.search(r'Up (\d+)', status)
                    if uptime_match:
                        self.metrics['transmissionvpn_container_uptime_seconds'] = int(uptime_match.group(1)) * 60
            else:
                self.metrics['transmissionvpn_container_running'] = 0
                
            # Get health status
            cmd = ['docker', 'inspect', self.container_name, '--format', '{{.State.Health.Status}}']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            
            if result.returncode == 0:
                health_status = result.stdout.strip()
                health_map = {
                    'healthy': 1,
                    'unhealthy': 0,
                    'starting': 2,
                    'none': 3
                }
                self.metrics['transmissionvpn_container_health'] = health_map.get(health_status, -1)
                
        except Exception as e:
            logger.error(f"Failed to get container info: {e}")
            self.metrics['transmissionvpn_container_running'] = 0
    
    def get_vpn_metrics(self):
        """Collect VPN-related metrics"""
        try:
            # Check VPN interface
            interfaces_output = self.run_docker_exec(['ip', 'link', 'show'])
            if interfaces_output:
                vpn_interface_up = 0
                if 'tun0' in interfaces_output and 'UP' in interfaces_output:
                    vpn_interface_up = 1
                elif 'wg0' in interfaces_output and 'UP' in interfaces_output:
                    vpn_interface_up = 1
                
                self.metrics['transmissionvpn_vpn_interface_up'] = vpn_interface_up
            
            # Get external IP (to verify VPN is working)
            external_ip = self.run_docker_exec(['curl', '-s', '--max-time', '5', 'ifconfig.me'])
            if external_ip:
                self.metrics['transmissionvpn_vpn_connectivity'] = 1
                # Store IP hash for change detection (privacy-friendly)
                ip_hash = hash(external_ip) % 1000000
                self.metrics['transmissionvpn_external_ip_hash'] = ip_hash
            else:
                self.metrics['transmissionvpn_vpn_connectivity'] = 0
            
            # VPN interface statistics
            for interface in ['tun0', 'wg0']:
                rx_bytes = self.run_docker_exec(['cat', f'/sys/class/net/{interface}/statistics/rx_bytes'])
                tx_bytes = self.run_docker_exec(['cat', f'/sys/class/net/{interface}/statistics/tx_bytes'])
                
                if rx_bytes and rx_bytes.isdigit():
                    self.metrics[f'transmissionvpn_vpn_{interface}_rx_bytes'] = int(rx_bytes)
                if tx_bytes and tx_bytes.isdigit():
                    self.metrics[f'transmissionvpn_vpn_{interface}_tx_bytes'] = int(tx_bytes)
                    
        except Exception as e:
            logger.error(f"Failed to get VPN metrics: {e}")
    
    def get_transmission_metrics(self):
        """Collect Transmission-related metrics"""
        try:
            # Check if Transmission web interface is responding
            web_check = self.run_docker_exec(['curl', '-s', '-f', 'http://localhost:9091/transmission/web/'])
            if web_check is not None:
                self.metrics['transmissionvpn_transmission_web_up'] = 1
            else:
                self.metrics['transmissionvpn_transmission_web_up'] = 0
            
            # Get Transmission session info
            session_info = self.run_docker_exec(['transmission-remote', 'localhost:9091', '-si'])
            if session_info:
                self.metrics['transmissionvpn_transmission_daemon_up'] = 1
                
                # Parse session info for metrics
                lines = session_info.split('\n')
                for line in lines:
                    line = line.strip()
                    
                    # Download/Upload speeds
                    if 'Current Speed' in line and 'Down:' in line:
                        # Extract download speed in KB/s
                        speed_match = re.search(r'Down:\s*([0-9.]+)', line)
                        if speed_match:
                            self.metrics['transmissionvpn_transmission_speed_down_kbps'] = float(speed_match.group(1))
                    
                    if 'Current Speed' in line and 'Up:' in line:
                        # Extract upload speed in KB/s
                        speed_match = re.search(r'Up:\s*([0-9.]+)', line)
                        if speed_match:
                            self.metrics['transmissionvpn_transmission_speed_up_kbps'] = float(speed_match.group(1))
            else:
                self.metrics['transmissionvpn_transmission_daemon_up'] = 0
            
            # Get torrent list
            torrent_list = self.run_docker_exec(['transmission-remote', 'localhost:9091', '-l'])
            if torrent_list:
                lines = torrent_list.split('\n')
                # Count torrents (exclude header and footer)
                torrent_count = max(0, len(lines) - 2)
                self.metrics['transmissionvpn_transmission_torrents_total'] = torrent_count
                
                # Count by status
                downloading = 0
                seeding = 0
                paused = 0
                
                for line in lines[1:-1]:  # Skip header and footer
                    if 'Downloading' in line or '%' in line:
                        downloading += 1
                    elif 'Seeding' in line or 'Idle' in line:
                        seeding += 1
                    elif 'Stopped' in line:
                        paused += 1
                
                self.metrics['transmissionvpn_transmission_torrents_downloading'] = downloading
                self.metrics['transmissionvpn_transmission_torrents_seeding'] = seeding
                self.metrics['transmissionvpn_transmission_torrents_paused'] = paused
                
        except Exception as e:
            logger.error(f"Failed to get Transmission metrics: {e}")
    
    def get_system_metrics(self):
        """Collect system metrics from container"""
        try:
            # Memory usage
            mem_info = self.run_docker_exec(['cat', '/proc/meminfo'])
            if mem_info:
                for line in mem_info.split('\n'):
                    if 'MemTotal:' in line:
                        mem_total = int(re.search(r'(\d+)', line).group(1)) * 1024  # Convert to bytes
                        self.metrics['transmissionvpn_memory_total_bytes'] = mem_total
                    elif 'MemAvailable:' in line:
                        mem_available = int(re.search(r'(\d+)', line).group(1)) * 1024
                        self.metrics['transmissionvpn_memory_available_bytes'] = mem_available
            
            # CPU usage (simplified)
            load_avg = self.run_docker_exec(['cat', '/proc/loadavg'])
            if load_avg:
                load_1min = float(load_avg.split()[0])
                self.metrics['transmissionvpn_cpu_load_1min'] = load_1min
            
            # Disk usage for important paths
            for path in ['/config', '/downloads', '/tmp']:
                disk_usage = self.run_docker_exec(['df', path])
                if disk_usage:
                    lines = disk_usage.strip().split('\n')
                    if len(lines) > 1:
                        parts = lines[1].split()
                        if len(parts) >= 5:
                            used_percent = int(parts[4].rstrip('%'))
                            path_safe = path.replace('/', '_')
                            self.metrics[f'transmissionvpn_disk_usage_percent{path_safe}'] = used_percent
                            
        except Exception as e:
            logger.error(f"Failed to get system metrics: {e}")
    
    def collect_all_metrics(self):
        """Collect all available metrics"""
        with self.lock:
            logger.debug("Collecting metrics...")
            self.metrics = {}
            
            self.get_container_info()
            
            # Only collect detailed metrics if container is running
            if self.metrics.get('transmissionvpn_container_running', 0) == 1:
                self.get_vpn_metrics()
                self.get_transmission_metrics()
                self.get_system_metrics()
            
            self.last_update = time.time()
            logger.debug(f"Collected {len(self.metrics)} metrics")
    
    def get_metrics(self):
        """Get current metrics with automatic refresh"""
        current_time = time.time()
        
        # Refresh metrics if they're stale
        if current_time - self.last_update > METRICS_INTERVAL:
            self.collect_all_metrics()
        
        with self.lock:
            return self.metrics.copy()

class MetricsHandler(BaseHTTPRequestHandler):
    """HTTP handler for metrics endpoint"""
    
    def __init__(self, *args, collector=None, **kwargs):
        self.collector = collector
        super().__init__(*args, **kwargs)
    
    def do_GET(self):
        """Handle GET requests"""
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/metrics':
            self.serve_metrics()
        elif parsed_path.path == '/health':
            self.serve_health()
        elif parsed_path.path == '/':
            self.serve_index()
        else:
            self.send_error(404, "Not Found")
    
    def serve_metrics(self):
        """Serve Prometheus-formatted metrics"""
        try:
            metrics = self.collector.get_metrics()
            
            # Generate Prometheus format
            output = []
            output.append("# HELP transmissionvpn metrics for transmissionvpn container")
            output.append("# TYPE transmissionvpn_info gauge")
            
            for metric_name, value in metrics.items():
                # Add help text for known metrics
                if metric_name not in [m.split()[3] for m in output if m.startswith('# TYPE')]:
                    output.append(f"# TYPE {metric_name} gauge")
                
                output.append(f"{metric_name} {value}")
            
            response = '\n'.join(output) + '\n'
            
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
            self.send_header('Content-Length', str(len(response.encode())))
            self.end_headers()
            self.wfile.write(response.encode())
            
        except Exception as e:
            logger.error(f"Error serving metrics: {e}")
            self.send_error(500, "Internal Server Error")
    
    def serve_health(self):
        """Serve health check endpoint"""
        try:
            # Simple health check
            health_status = {
                "status": "healthy",
                "timestamp": int(time.time()),
                "container": CONTAINER_NAME
            }
            
            response = json.dumps(health_status)
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(response.encode())))
            self.end_headers()
            self.wfile.write(response.encode())
            
        except Exception as e:
            logger.error(f"Error serving health: {e}")
            self.send_error(500, "Internal Server Error")
    
    def serve_index(self):
        """Serve index page with links"""
        html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>TransmissionVPN Metrics</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 40px; }
                .endpoint { margin: 20px 0; }
                .endpoint a { text-decoration: none; color: #0066cc; }
                .endpoint a:hover { text-decoration: underline; }
                .description { color: #666; margin-left: 20px; }
            </style>
        </head>
        <body>
            <h1>TransmissionVPN Metrics Server</h1>
            <p>Container: <strong>{container}</strong></p>
            <p>Available endpoints:</p>
            
            <div class="endpoint">
                <a href="/metrics">/metrics</a>
                <div class="description">Prometheus-formatted metrics</div>
            </div>
            
            <div class="endpoint">
                <a href="/health">/health</a>
                <div class="description">Health check endpoint (JSON)</div>
            </div>
            
            <p>Last updated: {timestamp}</p>
        </body>
        </html>
        """.format(
            container=CONTAINER_NAME,
            timestamp=time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())
        )
        
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(html.encode())))
        self.end_headers()
        self.wfile.write(html.encode())
    
    def log_message(self, format, *args):
        """Override to use our logger"""
        logger.info(format % args)

def create_handler_class(collector):
    """Create handler class with collector instance"""
    def handler(*args, **kwargs):
        MetricsHandler(*args, collector=collector, **kwargs)
    return handler

def main():
    """Main function"""
    logger.info(f"Starting TransmissionVPN metrics server on port {PORT}")
    logger.info(f"Container: {CONTAINER_NAME}")
    logger.info(f"Metrics refresh interval: {METRICS_INTERVAL}s")
    
    # Initialize metrics collector
    collector = MetricsCollector(CONTAINER_NAME)
    
    # Collect initial metrics
    collector.collect_all_metrics()
    
    # Start metrics collection thread
    def metrics_loop():
        while True:
            try:
                time.sleep(METRICS_INTERVAL)
                collector.collect_all_metrics()
            except KeyboardInterrupt:
                break
            except Exception as e:
                logger.error(f"Error in metrics loop: {e}")
                time.sleep(5)  # Wait before retrying
    
    metrics_thread = threading.Thread(target=metrics_loop, daemon=True)
    metrics_thread.start()
    
    # Start HTTP server
    try:
        handler_class = create_handler_class(collector)
        server = HTTPServer(('0.0.0.0', PORT), handler_class)
        logger.info(f"Metrics server running at http://0.0.0.0:{PORT}")
        logger.info("Endpoints: /metrics (Prometheus), /health (JSON), / (HTML)")
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down metrics server")
    except Exception as e:
        logger.error(f"Server error: {e}")

if __name__ == '__main__':
    main() 