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
    """Get system information"""
    try:
        # Get hostname
        hostname = socket.gethostname()
        
        # Get uptime
        with open('/proc/uptime', 'r') as f:
            uptime_seconds = float(f.readline().split()[0])
        
        # Get load average
        with open('/proc/loadavg', 'r') as f:
            load_avg = f.readline().split()[:3]
        
        # Get memory info
        memory_info = {}
        with open('/proc/meminfo', 'r') as f:
            for line in f:
                if line.startswith(('MemTotal:', 'MemAvailable:', 'MemFree:')):
                    key, value = line.split(':')
                    memory_info[key.strip()] = int(value.strip().split()[0]) * 1024  # Convert to bytes
        
        # Get disk usage for /downloads
        try:
            result = subprocess.run(['df', '/downloads'], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                if len(lines) > 1:
                    fields = lines[1].split()
                    disk_info = {
                        'total_bytes': int(fields[1]) * 1024,
                        'used_bytes': int(fields[2]) * 1024,
                        'available_bytes': int(fields[3]) * 1024,
                        'usage_percent': int(fields[4].rstrip('%'))
                    }
                else:
                    disk_info = {}
            else:
                disk_info = {}
        except:
            disk_info = {}
        
        return {
            'hostname': hostname,
            'uptime_seconds': int(uptime_seconds),
            'load_average': [float(x) for x in load_avg],
            'memory': memory_info,
            'disk': disk_info
        }
    except Exception as e:
        logger.error(f"Failed to get system info: {e}")
        return {}

def get_vpn_info():
    """Get VPN interface information"""
    try:
        vpn_info = {
            'interface': None,
            'status': 'down',
            'ip_address': None,
            'external_ip': None,
            'connected': False
        }
        
        # Check for VPN interfaces
        result = subprocess.run(['ip', 'link', 'show'], capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if 'tun0' in line and 'UP' in line:
                    vpn_info['interface'] = 'tun0'
                    vpn_info['status'] = 'up'
                    break
                elif 'wg0' in line and 'UP' in line:
                    vpn_info['interface'] = 'wg0'
                    vpn_info['status'] = 'up'
                    break
        
        # Get IP address if interface is up
        if vpn_info['interface']:
            result = subprocess.run(['ip', 'addr', 'show', vpn_info['interface']], 
                                  capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if 'inet ' in line and not line.strip().startswith('inet 127.'):
                        vpn_info['ip_address'] = line.split()[1].split('/')[0]
                        vpn_info['connected'] = True
                        break
        
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
    """Get Transmission health information"""
    try:
        health = {
            'web_ui_accessible': False,
            'rpc_accessible': False,
            'daemon_running': False,
            'response_time_ms': None,
            'version': None,
            'session_id': None
        }
        
        # Check if daemon process is running
        try:
            result = subprocess.run(['pgrep', '-f', 'transmission-daemon'], 
                                  capture_output=True, text=True, timeout=5)
            health['daemon_running'] = result.returncode == 0
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
        
        # Check RPC accessibility
        try:
            response = requests.post(TRANSMISSION_URL, json={"method": "session-get"}, timeout=5)
            if response.status_code in [200, 409]:
                health['rpc_accessible'] = True
                if response.status_code == 409:
                    health['session_id'] = response.headers.get('X-Transmission-Session-Id')
        except:
            pass
        
        return health
    except Exception as e:
        logger.error(f"Failed to get Transmission health: {e}")
        return {'web_ui_accessible': False, 'rpc_accessible': False, 'daemon_running': False}

def update_health_data():
    """Update comprehensive health data"""
    global health_data
    
    try:
        health_data = {
            'timestamp': int(time.time()),
            'status': 'healthy',
            'version': '4.0.6-r12',
            'system': get_system_info(),
            'vpn': get_vpn_info(),
            'transmission': get_transmission_health(),
            'metrics': {
                'torrents': transmission_stats.get('torrent_count', 0),
                'active_torrents': transmission_stats.get('active_torrents', 0),
                'download_rate': transmission_stats.get('total_download_rate', 0),
                'upload_rate': transmission_stats.get('total_upload_rate', 0),
                'last_update': last_update
            }
        }
        
        # Determine overall status
        issues = []
        if not health_data['transmission']['daemon_running']:
            issues.append('transmission_daemon_down')
        if not health_data['transmission']['web_ui_accessible']:
            issues.append('web_ui_inaccessible')
        if not health_data['vpn']['connected']:
            issues.append('vpn_disconnected')
        
        if issues:
            health_data['status'] = 'degraded' if health_data['transmission']['daemon_running'] else 'unhealthy'
            health_data['issues'] = issues
        
        logger.debug("Health data updated successfully")
        
    except Exception as e:
        logger.error(f"Failed to update health data: {e}")
        health_data = {
            'timestamp': int(time.time()),
            'status': 'error',
            'error': str(e)
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
    
    # Add help and type information
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