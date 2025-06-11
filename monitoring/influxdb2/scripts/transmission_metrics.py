#!/usr/bin/env python3
"""
Transmission metrics collector for InfluxDB2
Collects detailed metrics from Transmission RPC API
"""

import os
import time
import json
import requests
from datetime import datetime
from influxdb_client import InfluxDBClient
from influxdb_client.client.write_api import SYNCHRONOUS

# Configuration from environment variables
TRANSMISSION_HOST = os.getenv('TRANSMISSION_HOST', 'transmissionvpn')
TRANSMISSION_PORT = os.getenv('TRANSMISSION_PORT', '9091')
TRANSMISSION_USER = os.getenv('TRANSMISSION_USER', '')
TRANSMISSION_PASS = os.getenv('TRANSMISSION_PASS', '')

INFLUXDB_URL = os.getenv('INFLUXDB_URL', 'http://influxdb2:8086')
INFLUXDB_TOKEN = os.getenv('INFLUXDB_TOKEN')
INFLUXDB_ORG = os.getenv('INFLUXDB_ORG', 'transmissionvpn')
INFLUXDB_BUCKET = os.getenv('INFLUXDB_BUCKET', 'metrics')

class TransmissionMetrics:
    def __init__(self):
        self.session_id = None
        self.rpc_url = f"http://{TRANSMISSION_HOST}:{TRANSMISSION_PORT}/transmission/rpc"
        self.headers = {
            'Content-Type': 'application/json',
        }
        
        # Initialize InfluxDB client
        self.influx_client = InfluxDBClient(
            url=INFLUXDB_URL,
            token=INFLUXDB_TOKEN,
            org=INFLUXDB_ORG
        )
        self.write_api = self.influx_client.write_api(write_options=SYNCHRONOUS)

    def get_session_id(self):
        """Get X-Transmission-Session-Id from Transmission"""
        try:
            response = requests.post(self.rpc_url, json={}, headers=self.headers)
            if response.status_code == 409:
                self.session_id = response.headers.get('X-Transmission-Session-Id')
                self.headers['X-Transmission-Session-Id'] = self.session_id
                return True
            return False
        except Exception as e:
            print(f"Error getting session ID: {e}")
            return False

    def rpc_call(self, method, arguments=None):
        """Make RPC call to Transmission"""
        if not self.session_id:
            if not self.get_session_id():
                return None

        payload = {
            'method': method,
            'arguments': arguments or {}
        }

        try:
            response = requests.post(self.rpc_url, json=payload, headers=self.headers)
            
            if response.status_code == 409:
                # Session ID expired, get new one
                if self.get_session_id():
                    response = requests.post(self.rpc_url, json=payload, headers=self.headers)
                else:
                    return None

            if response.status_code == 200:
                return response.json()
            else:
                print(f"RPC call failed: {response.status_code}")
                return None

        except Exception as e:
            print(f"Error making RPC call: {e}")
            return None

    def collect_session_stats(self):
        """Collect session statistics"""
        result = self.rpc_call('session-stats')
        if not result or 'arguments' not in result:
            return []

        stats = result['arguments']
        timestamp = datetime.utcnow()
        
        points = []
        
        # Current session stats
        if 'current-stats' in stats:
            current = stats['current-stats']
            points.extend([
                f"transmission_session,type=current download_bytes={current.get('downloadedBytes', 0)}i {int(timestamp.timestamp() * 1000000000)}",
                f"transmission_session,type=current upload_bytes={current.get('uploadedBytes', 0)}i {int(timestamp.timestamp() * 1000000000)}",
                f"transmission_session,type=current files_added={current.get('filesAdded', 0)}i {int(timestamp.timestamp() * 1000000000)}",
                f"transmission_session,type=current session_count={current.get('sessionCount', 0)}i {int(timestamp.timestamp() * 1000000000)}",
                f"transmission_session,type=current seconds_active={current.get('secondsActive', 0)}i {int(timestamp.timestamp() * 1000000000)}"
            ])

        # Cumulative stats
        if 'cumulative-stats' in stats:
            cumulative = stats['cumulative-stats']
            points.extend([
                f"transmission_cumulative,type=total download_bytes={cumulative.get('downloadedBytes', 0)}i {int(timestamp.timestamp() * 1000000000)}",
                f"transmission_cumulative,type=total upload_bytes={cumulative.get('uploadedBytes', 0)}i {int(timestamp.timestamp() * 1000000000)}",
                f"transmission_cumulative,type=total files_added={cumulative.get('filesAdded', 0)}i {int(timestamp.timestamp() * 1000000000)}",
                f"transmission_cumulative,type=total session_count={cumulative.get('sessionCount', 0)}i {int(timestamp.timestamp() * 1000000000)}",
                f"transmission_cumulative,type=total seconds_active={cumulative.get('secondsActive', 0)}i {int(timestamp.timestamp() * 1000000000)}"
            ])

        return points

    def collect_session_info(self):
        """Collect session information"""
        result = self.rpc_call('session-get')
        if not result or 'arguments' not in result:
            return []

        session = result['arguments']
        timestamp = datetime.utcnow()
        
        points = []
        
        # Session configuration and status
        points.extend([
            f"transmission_config download_dir=\"{session.get('download-dir', '')}\" {int(timestamp.timestamp() * 1000000000)}",
            f"transmission_config download_queue_size={session.get('download-queue-size', 0)}i {int(timestamp.timestamp() * 1000000000)}",
            f"transmission_config seed_queue_size={session.get('seed-queue-size', 0)}i {int(timestamp.timestamp() * 1000000000)}",
            f"transmission_config speed_limit_down={session.get('speed-limit-down', 0)}i {int(timestamp.timestamp() * 1000000000)}",
            f"transmission_config speed_limit_up={session.get('speed-limit-up', 0)}i {int(timestamp.timestamp() * 1000000000)}",
            f"transmission_config alt_speed_down={session.get('alt-speed-down', 0)}i {int(timestamp.timestamp() * 1000000000)}",
            f"transmission_config alt_speed_up={session.get('alt-speed-up', 0)}i {int(timestamp.timestamp() * 1000000000)}",
            f"transmission_config peer_limit_global={session.get('peer-limit-global', 0)}i {int(timestamp.timestamp() * 1000000000)}",
            f"transmission_config peer_limit_per_torrent={session.get('peer-limit-per-torrent', 0)}i {int(timestamp.timestamp() * 1000000000)}"
        ])

        return points

    def collect_torrent_stats(self):
        """Collect torrent statistics"""
        result = self.rpc_call('torrent-get', {
            'fields': [
                'id', 'name', 'status', 'error', 'errorString',
                'downloadedEver', 'uploadedEver', 'sizeWhenDone',
                'rateDownload', 'rateUpload', 'eta', 'peersConnected',
                'percentDone', 'queuePosition'
            ]
        })
        
        if not result or 'arguments' not in result or 'torrents' not in result['arguments']:
            return []

        torrents = result['arguments']['torrents']
        timestamp = datetime.utcnow()
        
        points = []
        
        # Status counters
        status_counts = {}
        total_download_speed = 0
        total_upload_speed = 0
        total_size = 0
        total_downloaded = 0
        total_uploaded = 0
        
        for torrent in torrents:
            status = torrent.get('status', 0)
            status_counts[status] = status_counts.get(status, 0) + 1
            
            total_download_speed += torrent.get('rateDownload', 0)
            total_upload_speed += torrent.get('rateUpload', 0)
            total_size += torrent.get('sizeWhenDone', 0)
            total_downloaded += torrent.get('downloadedEver', 0)
            total_uploaded += torrent.get('uploadedEver', 0)

        # Add aggregate metrics
        points.extend([
            f"transmission_torrents total_count={len(torrents)}i {int(timestamp.timestamp() * 1000000000)}",
            f"transmission_speed download_rate={total_download_speed}i {int(timestamp.timestamp() * 1000000000)}",
            f"transmission_speed upload_rate={total_upload_speed}i {int(timestamp.timestamp() * 1000000000)}",
            f"transmission_size total_size={total_size}i {int(timestamp.timestamp() * 1000000000)}",
            f"transmission_size total_downloaded={total_downloaded}i {int(timestamp.timestamp() * 1000000000)}",
            f"transmission_size total_uploaded={total_uploaded}i {int(timestamp.timestamp() * 1000000000)}"
        ])

        # Status counts (0=stopped, 1=check-wait, 2=check, 3=download-wait, 4=download, 5=seed-wait, 6=seed)
        status_names = {
            0: 'stopped', 1: 'check_wait', 2: 'checking', 
            3: 'download_wait', 4: 'downloading', 5: 'seed_wait', 6: 'seeding'
        }
        
        for status_code, count in status_counts.items():
            status_name = status_names.get(status_code, f'status_{status_code}')
            points.append(f"transmission_status,status={status_name} count={count}i {int(timestamp.timestamp() * 1000000000)}")

        return points

    def run(self):
        """Main collection loop"""
        try:
            points = []
            
            # Collect all metrics
            points.extend(self.collect_session_stats())
            points.extend(self.collect_session_info())
            points.extend(self.collect_torrent_stats())
            
            if points:
                # Write to InfluxDB
                self.write_api.write(bucket=INFLUXDB_BUCKET, record=points)
                print(f"Successfully wrote {len(points)} metrics to InfluxDB")
            else:
                print("No metrics collected")
                
        except Exception as e:
            print(f"Error in metrics collection: {e}")
        finally:
            self.influx_client.close()

if __name__ == "__main__":
    collector = TransmissionMetrics()
    collector.run() 