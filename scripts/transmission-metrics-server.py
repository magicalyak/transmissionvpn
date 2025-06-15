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

# Global variables for metrics
transmission_stats = {}
session_stats = {}
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
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        pass

def metrics_updater():
    """Background thread to update metrics"""
    while True:
        update_metrics()
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