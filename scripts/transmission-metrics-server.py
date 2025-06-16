#!/usr/bin/env python3
"""
Custom Transmission Metrics Server
Similar to nzbgetvpn metrics approach - lightweight Python server
"""

import os
import sys
import time
import json
import logging
import requests
import subprocess
import socket
import psutil
import platform
from datetime import datetime, timezone
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading

# Configuration from environment variables
TRANSMISSION_HOST = os.getenv('TRANSMISSION_HOST', '127.0.0.1')
TRANSMISSION_PORT = os.getenv('TRANSMISSION_PORT', '9091')
TRANSMISSION_USERNAME = os.getenv('TRANSMISSION_RPC_USERNAME', '')
TRANSMISSION_PASSWORD = os.getenv('TRANSMISSION_RPC_PASSWORD', '')
TRANSMISSION_URL = f"http://{TRANSMISSION_HOST}:{TRANSMISSION_PORT}/transmission/rpc"

METRICS_PORT = int(os.getenv('METRICS_PORT', '9099'))
METRICS_INTERVAL = int(os.getenv('METRICS_INTERVAL', '30'))
METRICS_ENABLED = os.getenv('METRICS_ENABLED', 'true').lower() == 'true'

# Global variables for metrics and health
transmission_stats = {}
session_stats = {}
health_data = {}
last_update = 0
start_time = time.time()

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class TransmissionAPI:
    def __init__(self):
        self.session_id = None
        self.session = requests.Session()
        if TRANSMISSION_USERNAME and TRANSMISSION_PASSWORD:
            self.session.auth = (TRANSMISSION_USERNAME, TRANSMISSION_PASSWORD)
    
    def _get_session_id(self):
        """Get session ID from Transmission"""
        try:
            response = self.session.post(TRANSMISSION_URL, json={"method": "session-get"})
            if response.status_code == 409:
                self.session_id = response.headers.get('X-Transmission-Session-Id')
                logger.info(f"Got session ID: {self.session_id}")
                return True
            return False
        except Exception as e:
            logger.error(f"Failed to get session ID: {e}")
            return False
    
    def _make_request(self, method, arguments=None):
        """Make RPC request to Transmission"""
        if not self.session_id:
            if not self._get_session_id():
                return None
        
        headers = {'X-Transmission-Session-Id': self.session_id}
        data = {"method": method}
        if arguments:
            data["arguments"] = arguments
        
        try:
            response = self.session.post(TRANSMISSION_URL, json=data, headers=headers)
            if response.status_code == 409:
                # Session ID expired, get new one
                if self._get_session_id():
                    headers['X-Transmission-Session-Id'] = self.session_id
                    response = self.session.post(TRANSMISSION_URL, json=data, headers=headers)
            
            if response.status_code == 200:
                return response.json()
            else:
                logger.error(f"Request failed: {response.status_code} - {response.text}")
                return None
        except Exception as e:
            logger.error(f"Request error: {e}")
            return None
    
    def get_session_stats(self):
        """Get session statistics"""
        return self._make_request("session-stats")
    
    def get_torrents(self):
        """Get torrent list with stats"""
        fields = [
            "id", "name", "status", "totalSize", "leftUntilDone",
            "rateDownload", "rateUpload", "uploadRatio", "percentDone",
            "eta", "error", "errorString", "peersConnected", "seeders",
            "leechers", "downloadedEver", "uploadedEver"
        ]
        return self._make_request("torrent-get", {"fields": fields})

def get_system_info():
    """Get comprehensive system information"""
    try:
        # Get hostname and platform info
        hostname = socket.gethostname()
        platform_info = platform.uname()
        
        # Get uptime
        boot_time = psutil.boot_time()
        uptime_seconds = int(time.time() - boot_time)
        
        # Get load average (Unix-like systems)
        try:
            load_avg = os.getloadavg()
        except (OSError, AttributeError):
            load_avg = [0.0, 0.0, 0.0]
        
        # Get memory info
        memory = psutil.virtual_memory()
        swap = psutil.swap_memory()
        
        # Get disk usage for /downloads
        try:
            disk_usage = psutil.disk_usage('/downloads')
            disk_info = {
                'total_bytes': disk_usage.total,
                'used_bytes': disk_usage.used,
                'available_bytes': disk_usage.free,
                'usage_percent': round((disk_usage.used / disk_usage.total) * 100, 2)
            }
        except:
            disk_info = {}
        
        # Get CPU info
        cpu_info = {
            'count': psutil.cpu_count(),
            'usage_percent': psutil.cpu_percent(interval=1),
            'frequency': psutil.cpu_freq()._asdict() if psutil.cpu_freq() else {}
        }
        
        # Get network interfaces
        network_interfaces = {}
        for interface, addrs in psutil.net_if_addrs().items():
            if interface not in ['lo', 'docker0']:
                for addr in addrs:
                    if addr.family == socket.AF_INET:
                        network_interfaces[interface] = {
                            'ip': addr.address,
                            'netmask': addr.netmask
                        }
                        break
        
        return {
            'hostname': hostname,
            'platform': {
                'system': platform_info.system,
                'release': platform_info.release,
                'version': platform_info.version,
                'machine': platform_info.machine,
                'processor': platform_info.processor
            },
            'uptime_seconds': uptime_seconds,
            'boot_time': int(boot_time),
            'load_average': list(load_avg),
            'memory': {
                'total': memory.total,
                'available': memory.available,
                'used': memory.used,
                'free': memory.free,
                'percent': memory.percent,
                'buffers': getattr(memory, 'buffers', 0),
                'cached': getattr(memory, 'cached', 0)
            },
            'swap': {
                'total': swap.total,
                'used': swap.used,
                'free': swap.free,
                'percent': swap.percent
            },
            'disk': disk_info,
            'cpu': cpu_info,
            'network_interfaces': network_interfaces
        }
    except Exception as e:
        logger.error(f"Failed to get system info: {e}")
        return {}

def get_vpn_info():
    """Get comprehensive VPN interface information"""
    try:
        vpn_info = {
            'interface': None,
            'status': 'down',
            'ip_address': None,
            'external_ip': None,
            'connected': False,
            'dns_servers': [],
            'routes': [],
            'stats': {}
        }
        
        # Check for VPN interfaces
        for interface, addrs in psutil.net_if_addrs().items():
            if interface.startswith(('tun', 'wg', 'tap')):
                vpn_info['interface'] = interface
                
                # Check if interface is up
                if_stats = psutil.net_if_stats().get(interface)
                if if_stats and if_stats.isup:
                    vpn_info['status'] = 'up'
                    
                    # Get IP address
                    for addr in addrs:
                        if addr.family == socket.AF_INET:
                            vpn_info['ip_address'] = addr.address
                            vpn_info['connected'] = True
                            break
                    
                    # Get interface statistics
                    io_stats = psutil.net_io_counters(pernic=True).get(interface)
                    if io_stats:
                        vpn_info['stats'] = {
                            'bytes_sent': io_stats.bytes_sent,
                            'bytes_recv': io_stats.bytes_recv,
                            'packets_sent': io_stats.packets_sent,
                            'packets_recv': io_stats.packets_recv,
                            'errin': io_stats.errin,
                            'errout': io_stats.errout,
                            'dropin': io_stats.dropin,
                            'dropout': io_stats.dropout
                        }
                break
        
        # Get DNS servers
        try:
            with open('/etc/resolv.conf', 'r') as f:
                for line in f:
                    if line.startswith('nameserver'):
                        dns_server = line.split()[1]
                        vpn_info['dns_servers'].append(dns_server)
        except:
            pass
        
        # Get external IP
        try:
            result = subprocess.run(['curl', '-s', '--max-time', '10', 'ifconfig.me'], 
                                  capture_output=True, text=True, timeout=15)
            if result.returncode == 0 and result.stdout.strip():
                vpn_info['external_ip'] = result.stdout.strip()
        except:
            pass
        
        return vpn_info
    except Exception as e:
        logger.error(f"Failed to get VPN info: {e}")
        return {'interface': None, 'status': 'unknown', 'connected': False}

def get_transmission_health():
    """Get comprehensive Transmission health information"""
    try:
        health = {
            'web_ui_accessible': False,
            'rpc_accessible': False,
            'daemon_running': False,
            'response_time_ms': None,
            'version': '4.0.6-r14',
            'session_id': None,
            'port_test': None,
            'blocklist_enabled': False,
            'blocklist_size': 0,
            'queue_enabled': False,
            'speed_limit_enabled': False,
            'alt_speed_enabled': False,
            'encryption': None,
            'peer_port': None,
            'peer_port_random': False,
            'dht_enabled': False,
            'lpd_enabled': False,
            'pex_enabled': False,
            'utp_enabled': False
        }
        
        # Check if daemon process is running
        try:
            for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
                if 'transmission-daemon' in proc.info['name']:
                    health['daemon_running'] = True
                    break
        except:
            pass
        
        # Check web UI accessibility
        start_time = time.time()
        try:
            response = requests.get(f"http://{TRANSMISSION_HOST}:{TRANSMISSION_PORT}/transmission/web/", 
                                  timeout=5)
            if response.status_code == 200:
                health['web_ui_accessible'] = True
                health['response_time_ms'] = int((time.time() - start_time) * 1000)
        except:
            pass
        
        # Check RPC accessibility and get session info
        try:
            api = TransmissionAPI()
            session_response = api._make_request("session-get")
            if session_response and session_response.get('result') == 'success':
                health['rpc_accessible'] = True
                health['session_id'] = api.session_id
                
                session_data = session_response.get('arguments', {})
                health['version'] = session_data.get('version')
                health['blocklist_enabled'] = session_data.get('blocklist-enabled', False)
                health['blocklist_size'] = session_data.get('blocklist-size', 0)
                health['queue_enabled'] = session_data.get('queue-stalled-enabled', False)
                health['speed_limit_enabled'] = session_data.get('speed-limit-down-enabled', False)
                health['alt_speed_enabled'] = session_data.get('alt-speed-enabled', False)
                health['encryption'] = session_data.get('encryption')
                health['peer_port'] = session_data.get('peer-port')
                health['peer_port_random'] = session_data.get('peer-port-random-on-start', False)
                health['dht_enabled'] = session_data.get('dht-enabled', False)
                health['lpd_enabled'] = session_data.get('lpd-enabled', False)
                health['pex_enabled'] = session_data.get('pex-enabled', False)
                health['utp_enabled'] = session_data.get('utp-enabled', False)
                
                # Test port
                port_test_response = api._make_request("port-test")
                if port_test_response and port_test_response.get('result') == 'success':
                    health['port_test'] = port_test_response.get('arguments', {}).get('port-is-open', False)
        except:
            pass
        
        return health
    except Exception as e:
        logger.error(f"Failed to get Transmission health: {e}")
        return {'web_ui_accessible': False, 'rpc_accessible': False, 'daemon_running': False}

def get_container_info():
    """Get container-specific information"""
    try:
        container_info = {
            'id': None,
            'name': None,
            'image': None,
            'created': None,
            'started': None,
            'restart_count': 0,
            'environment': {},
            'mounts': [],
            'networks': [],
            'ports': []
        }
        
        # Try to get container info if running in Docker
        try:
            # Check if we're in a container
            with open('/proc/1/cgroup', 'r') as f:
                if 'docker' in f.read():
                    # Get container ID from hostname or cgroup
                    container_id = socket.gethostname()
                    container_info['id'] = container_id
                    container_info['name'] = container_id
        except:
            pass
        
        # Get environment variables related to the application
        for key, value in os.environ.items():
            if key.startswith(('TRANSMISSION_', 'VPN_', 'METRICS_', 'OPENVPN_', 'WIREGUARD_')):
                # Don't expose sensitive information
                if 'PASSWORD' in key or 'TOKEN' in key or 'SECRET' in key:
                    container_info['environment'][key] = '***REDACTED***'
                else:
                    container_info['environment'][key] = value
        
        return container_info
    except Exception as e:
        logger.error(f"Failed to get container info: {e}")
        return {}

def update_health_data():
    """Update comprehensive health data"""
    global health_data
    
    try:
        current_time = time.time()
        health_data = {
            'timestamp': int(current_time),
            'iso_timestamp': datetime.fromtimestamp(current_time, tz=timezone.utc).isoformat(),
            'status': 'healthy',
            'version': '4.0.6-r14',
            'service': 'transmissionvpn',
            'uptime_seconds': int(current_time - start_time),
            'system': get_system_info(),
            'vpn': get_vpn_info(),
            'transmission': get_transmission_health(),
            'container': get_container_info(),
            'metrics': {
                'torrents': transmission_stats.get('torrent_count', 0),
                'active_torrents': transmission_stats.get('active_torrents', 0),
                'downloading_torrents': transmission_stats.get('downloading_torrents', 0),
                'seeding_torrents': transmission_stats.get('seeding_torrents', 0),
                'paused_torrents': transmission_stats.get('paused_torrents', 0),
                'download_rate': transmission_stats.get('total_download_rate', 0),
                'upload_rate': transmission_stats.get('total_upload_rate', 0),
                'total_size': transmission_stats.get('total_size', 0),
                'total_downloaded': transmission_stats.get('total_downloaded', 0),
                'total_uploaded': transmission_stats.get('total_uploaded', 0),
                'last_update': last_update,
                'update_interval': METRICS_INTERVAL
            },
            'endpoints': {
                'metrics': f'http://localhost:{METRICS_PORT}/metrics',
                'health': f'http://localhost:{METRICS_PORT}/health',
                'health_simple': f'http://localhost:{METRICS_PORT}/health/simple'
            }
        }
        
        # Add session stats if available
        if session_stats:
            current_stats = session_stats.get('current-stats', {})
            cumulative_stats = session_stats.get('cumulative-stats', {})
            
            health_data['session'] = {
                'current': {
                    'downloaded_bytes': current_stats.get('downloadedBytes', 0),
                    'uploaded_bytes': current_stats.get('uploadedBytes', 0),
                    'files_added': current_stats.get('filesAdded', 0),
                    'session_count': current_stats.get('sessionCount', 0),
                    'seconds_active': current_stats.get('secondsActive', 0)
                },
                'cumulative': {
                    'downloaded_bytes': cumulative_stats.get('downloadedBytes', 0),
                    'uploaded_bytes': cumulative_stats.get('uploadedBytes', 0),
                    'files_added': cumulative_stats.get('filesAdded', 0),
                    'session_count': cumulative_stats.get('sessionCount', 0),
                    'seconds_active': cumulative_stats.get('secondsActive', 0)
                }
            }
        
        # Determine overall status
        issues = []
        warnings = []
        
        # Critical issues
        if not health_data['transmission']['daemon_running']:
            issues.append('transmission_daemon_down')
        if not health_data['transmission']['web_ui_accessible']:
            issues.append('web_ui_inaccessible')
        if not health_data['transmission']['rpc_accessible']:
            issues.append('rpc_inaccessible')
        
        # Warnings
        if not health_data['vpn']['connected']:
            warnings.append('vpn_disconnected')
        if health_data['system']['disk'].get('usage_percent', 0) > 90:
            warnings.append('disk_space_low')
        if health_data['system']['memory'].get('percent', 0) > 90:
            warnings.append('memory_usage_high')
        if health_data['transmission'].get('port_test') is False:
            warnings.append('port_not_open')
        
        # Set status based on issues
        if issues:
            health_data['status'] = 'unhealthy'
            health_data['issues'] = issues
        elif warnings:
            health_data['status'] = 'degraded'
            health_data['warnings'] = warnings
        else:
            health_data['status'] = 'healthy'
        
        logger.debug("Health data updated successfully")
        
    except Exception as e:
        logger.error(f"Failed to update health data: {e}")
        health_data = {
            'timestamp': int(time.time()),
            'status': 'error',
            'error': str(e),
            'service': 'transmissionvpn'
        }

def update_metrics():
    """Update metrics from Transmission"""
    global transmission_stats, session_stats, last_update
    
    api = TransmissionAPI()
    
    try:
        # Get session stats
        stats_response = api.get_session_stats()
        if stats_response and stats_response.get('result') == 'success':
            session_stats = stats_response.get('arguments', {})
        
        # Get torrent stats
        torrents_response = api.get_torrents()
        if torrents_response and torrents_response.get('result') == 'success':
            torrents = torrents_response.get('arguments', {}).get('torrents', [])
            
            # Calculate aggregate stats
            transmission_stats = {
                'torrent_count': len(torrents),
                'active_torrents': len([t for t in torrents if t.get('status') in [4, 6]]),
                'downloading_torrents': len([t for t in torrents if t.get('status') == 4]),
                'seeding_torrents': len([t for t in torrents if t.get('status') == 6]),
                'paused_torrents': len([t for t in torrents if t.get('status') == 0]),
                'total_download_rate': sum(t.get('rateDownload', 0) for t in torrents),
                'total_upload_rate': sum(t.get('rateUpload', 0) for t in torrents),
                'total_size': sum(t.get('totalSize', 0) for t in torrents),
                'total_downloaded': sum(t.get('downloadedEver', 0) for t in torrents),
                'total_uploaded': sum(t.get('uploadedEver', 0) for t in torrents),
            }
        
        last_update = time.time()
        logger.info("Metrics updated successfully")
        
    except Exception as e:
        logger.error(f"Failed to update metrics: {e}")

def generate_prometheus_metrics():
    """Generate Prometheus format metrics"""
    metrics = []
    
    # Transmission torrent metrics
    metrics.append("# HELP transmission_torrent_count Total number of torrents")
    metrics.append("# TYPE transmission_torrent_count gauge")
    metrics.append(f"transmission_torrent_count {transmission_stats.get('torrent_count', 0)}")
    
    metrics.append("# HELP transmission_active_torrents Number of active torrents")
    metrics.append("# TYPE transmission_active_torrents gauge")
    metrics.append(f"transmission_active_torrents {transmission_stats.get('active_torrents', 0)}")
    
    metrics.append("# HELP transmission_downloading_torrents Number of downloading torrents")
    metrics.append("# TYPE transmission_downloading_torrents gauge")
    metrics.append(f"transmission_downloading_torrents {transmission_stats.get('downloading_torrents', 0)}")
    
    metrics.append("# HELP transmission_seeding_torrents Number of seeding torrents")
    metrics.append("# TYPE transmission_seeding_torrents gauge")
    metrics.append(f"transmission_seeding_torrents {transmission_stats.get('seeding_torrents', 0)}")
    
    metrics.append("# HELP transmission_download_rate_bytes_per_second Current download rate")
    metrics.append("# TYPE transmission_download_rate_bytes_per_second gauge")
    metrics.append(f"transmission_download_rate_bytes_per_second {transmission_stats.get('total_download_rate', 0)}")
    
    metrics.append("# HELP transmission_upload_rate_bytes_per_second Current upload rate")
    metrics.append("# TYPE transmission_upload_rate_bytes_per_second gauge")
    metrics.append(f"transmission_upload_rate_bytes_per_second {transmission_stats.get('total_upload_rate', 0)}")
    
    # Session stats
    if session_stats:
        current_stats = session_stats.get('current-stats', {})
        
        metrics.append("# HELP transmission_session_downloaded_bytes Session downloaded bytes")
        metrics.append("# TYPE transmission_session_downloaded_bytes counter")
        metrics.append(f"transmission_session_downloaded_bytes {current_stats.get('downloadedBytes', 0)}")
        
        metrics.append("# HELP transmission_session_uploaded_bytes Session uploaded bytes")
        metrics.append("# TYPE transmission_session_uploaded_bytes counter")
        metrics.append(f"transmission_session_uploaded_bytes {current_stats.get('uploadedBytes', 0)}")
    
    # TransmissionVPN system metrics (for Grafana dashboard compatibility)
    if health_data:
        # Container/Service status
        metrics.append("# HELP transmissionvpn_container_running Container is running")
        metrics.append("# TYPE transmissionvpn_container_running gauge")
        container_running = 1 if health_data.get('transmission', {}).get('daemon_running', False) else 0
        metrics.append(f"transmissionvpn_container_running {container_running}")
        
        # VPN connection status
        metrics.append("# HELP transmissionvpn_vpn_connected VPN is connected")
        metrics.append("# TYPE transmissionvpn_vpn_connected gauge")
        vpn_connected = 1 if health_data.get('vpn', {}).get('connected', False) else 0
        metrics.append(f"transmissionvpn_vpn_connected {vpn_connected}")
        
        # Web UI status
        metrics.append("# HELP transmissionvpn_web_ui_up Web UI is accessible")
        metrics.append("# TYPE transmissionvpn_web_ui_up gauge")
        web_ui_up = 1 if health_data.get('transmission', {}).get('web_ui_accessible', False) else 0
        metrics.append(f"transmissionvpn_web_ui_up {web_ui_up}")
        
        # System metrics
        system_data = health_data.get('system', {})
        
        # Disk usage
        metrics.append("# HELP transmissionvpn_disk_usage_percent Disk usage percentage")
        metrics.append("# TYPE transmissionvpn_disk_usage_percent gauge")
        disk_usage = system_data.get('disk', {}).get('usage_percent', 0)
        metrics.append(f"transmissionvpn_disk_usage_percent {disk_usage}")
        
        # Memory usage
        metrics.append("# HELP transmissionvpn_memory_usage_percent Memory usage percentage")
        metrics.append("# TYPE transmissionvpn_memory_usage_percent gauge")
        memory_usage = system_data.get('memory', {}).get('percent', 0)
        metrics.append(f"transmissionvpn_memory_usage_percent {memory_usage}")
        
        # CPU usage
        metrics.append("# HELP transmissionvpn_cpu_usage_percent CPU usage percentage")
        metrics.append("# TYPE transmissionvpn_cpu_usage_percent gauge")
        cpu_usage = system_data.get('cpu', {}).get('usage_percent', 0)
        metrics.append(f"transmissionvpn_cpu_usage_percent {cpu_usage}")
        
        # VPN interface status
        metrics.append("# HELP transmissionvpn_vpn_interface_up VPN interface is up")
        metrics.append("# TYPE transmissionvpn_vpn_interface_up gauge")
        vpn_interface_up = 1 if health_data.get('vpn', {}).get('status') == 'up' else 0
        metrics.append(f"transmissionvpn_vpn_interface_up {vpn_interface_up}")
        
        # Port test status
        metrics.append("# HELP transmissionvpn_port_open Peer port is open")
        metrics.append("# TYPE transmissionvpn_port_open gauge")
        port_open = 1 if health_data.get('transmission', {}).get('port_test', False) else 0
        metrics.append(f"transmissionvpn_port_open {port_open}")
        
        # Overall health status
        metrics.append("# HELP transmissionvpn_healthy Overall service health")
        metrics.append("# TYPE transmissionvpn_healthy gauge")
        healthy = 1 if health_data.get('status') == 'healthy' else 0
        metrics.append(f"transmissionvpn_healthy {healthy}")
    
    # Add last update timestamp
    metrics.append("# HELP transmission_metrics_last_update_timestamp Last time metrics were updated")
    metrics.append("# TYPE transmission_metrics_last_update_timestamp gauge")
    metrics.append(f"transmission_metrics_last_update_timestamp {last_update}")
    
    return "\n".join(metrics) + "\n"

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.end_headers()
            self.wfile.write(generate_prometheus_metrics().encode('utf-8'))
        elif self.path == '/health':
            # Update health data before serving
            update_health_data()
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(health_data, indent=2).encode('utf-8'))
        elif self.path == '/health/simple':
            # Simple health check for basic monitoring
            transmission_health = get_transmission_health()
            if transmission_health['web_ui_accessible'] and transmission_health['daemon_running']:
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'OK')
            else:
                self.send_response(503)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'Service Unavailable')
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        pass

def metrics_updater():
    """Background thread to update metrics"""
    while True:
        update_metrics()
        update_health_data()
        time.sleep(METRICS_INTERVAL)

def main():
    if not METRICS_ENABLED:
        logger.info("Metrics disabled, exiting")
        return
    
    logger.info(f"Starting Transmission Metrics Server on port {METRICS_PORT}")
    logger.info(f"Transmission URL: {TRANSMISSION_URL}")
    
    # Start metrics updater thread
    updater_thread = threading.Thread(target=metrics_updater, daemon=True)
    updater_thread.start()
    
    # Initial metrics update
    update_metrics()
    
    # Start HTTP server
    server = HTTPServer(('0.0.0.0', METRICS_PORT), MetricsHandler)
    logger.info(f"Metrics server started on http://0.0.0.0:{METRICS_PORT}/metrics")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down metrics server")
        server.shutdown()

if __name__ == '__main__':
    main() 