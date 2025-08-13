# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.6-r20] - 2025-08-13

### Added
- **Default DNS Servers**: Added default public DNS servers (8.8.8.8, 1.1.1.1) to prevent VPN connection issues from local DNS blocking
- **Enhanced Tools**: Added `jq` for JSON parsing and `bind-tools` for DNS debugging utilities
- **DNS Configuration**: NAME_SERVERS now defaults to public DNS to avoid local DNS filtering issues

### Enhanced
- **Base Image**: Updated to latest LinuxServer.io transmission base image
- **Dependencies**: Updated all Alpine packages to latest versions
- **Code Formatting**: Improved Dockerfile readability with multi-line package installation

### Fixed
- **VPN Connection Issues**: Resolved DNS blocking problems that prevented VPN connections when local DNS servers filter VPN hostnames
- **Container Health**: Fixed unhealthy container state caused by VPN failing to connect due to DNS resolution returning 0.0.0.0

## [4.0.6-r14] - 2024-01-XX

### Added
- **InfluxDB2 Monitoring Stack**: Complete InfluxDB2 integration with Telegraf and Grafana
- **Advanced Time-Series Analytics**: 365-day data retention with Flux query language
- **Comprehensive System Monitoring**: CPU, memory, disk, network, and Docker metrics
- **Beautiful Pre-built Dashboards**: Two modern Grafana dashboards with visualizations
- **Enhanced Health Endpoint**: Comprehensive system info similar to nzbgetvpn
- **Dual Monitoring Options**: Prometheus (simple) + InfluxDB2 (advanced) stacks
- **Platform Information**: Detailed OS and hardware information collection
- **VPN Interface Statistics**: Packet counters, DNS servers, and connection stats
- **Container Information**: Environment variables and configuration details
- **Session Statistics**: Current and cumulative transfer data

### Enhanced
- **Health Endpoint Response**: Now includes platform, CPU, network interfaces, VPN stats
- **Transmission Status**: Added version, port test, protocol settings (DHT, PEX, UTP)
- **System Monitoring**: Added psutil dependency for comprehensive metrics
- **Network Detection**: Automatic VPN interface identification
- **Memory Monitoring**: Breakdown including buffers and cached memory
- **Documentation**: Comprehensive monitoring guides with stack comparison

### Fixed
- **Variable Consistency**: Updated all TRANSMISSION_EXPORTER_* to METRICS_* variables
- **Monitoring Scripts**: Fixed references to old variable names
- **Error Handling**: Improved health endpoint error handling
- **Network Detection**: Enhanced VPN interface detection logic

## [4.0.6-r13] - 2024-01-XX

### Added
- **Enhanced Health Monitoring**: Comprehensive JSON health endpoint similar to nzbgetvpn
- **System Information Collection**: Hostname, uptime, load average, memory, disk usage
- **VPN Status Monitoring**: Interface detection, IP addresses, external IP verification
- **Transmission Health Checks**: Daemon status, web UI accessibility, RPC connectivity
- **Multiple Health Endpoints**: `/health` (JSON), `/health/simple` (text)
- **Issue Detection**: Automatic detection of critical issues and warnings

### Enhanced
- **Metrics Server**: Updated with comprehensive health data collection
- **Status Determination**: Intelligent status calculation (healthy/degraded/unhealthy/error)
- **Response Times**: Added response time measurement for health checks
- **External IP Detection**: Configurable external IP service

### Fixed
- **Health Check Logic**: Improved reliability of health status determination
- **Error Handling**: Better error handling in health data collection
- **Network Connectivity**: Enhanced external IP detection with timeout handling

## [4.0.6-r12] - 2024-01-XX

### Added
- **Built-in Custom Metrics Server**: Python-based metrics server replacing transmission-exporter
- **Enhanced Health Monitoring**: Comprehensive health checks with detailed status reporting
- **Prometheus Integration**: Native Prometheus metrics endpoint at `/metrics`
- **Health Endpoints**: JSON health data at `/health` and simple check at `/health/simple`
- **VPN Monitoring**: VPN interface detection and connectivity monitoring
- **System Metrics**: Disk usage, memory, and system health metrics

### Enhanced
- **Container Architecture**: Single container solution with built-in monitoring
- **Port Management**: Consolidated metrics on port 9099
- **Environment Variables**: Simplified configuration with METRICS_* variables
- **Documentation**: Updated monitoring setup guides

### Removed
- **External transmission-exporter**: Replaced with built-in solution
- **Complex Multi-container Setup**: Simplified to single container architecture

### Fixed
- **Metrics Collection**: Resolved `METRICS_ENABLED=false` causing empty metrics
- **Port Conflicts**: Eliminated conflicts between different metrics solutions
- **Health Check Reliability**: Improved health check accuracy and performance

## [4.0.6-r11] - 2024-01-XX

### Added
- **Custom Metrics Server**: Lightweight Python server for Prometheus metrics
- **Health Monitoring**: Enhanced health checks with VPN and system monitoring
- **Prometheus Integration**: Native metrics endpoint for monitoring
- **Environment Configuration**: Comprehensive environment variable support

### Enhanced
- **Monitoring Architecture**: Transition from external to built-in metrics
- **Variable Naming**: Standardized METRICS_* variable naming convention
- **Documentation**: Comprehensive monitoring and setup documentation

### Deprecated
- **TRANSMISSION_EXPORTER_***: Variables deprecated in favor of METRICS_*
- **External Metrics Solutions**: Moving towards built-in monitoring

### Fixed
- **Metrics Reliability**: Improved metrics collection and reporting
- **Health Check Accuracy**: Enhanced health check logic and error handling

## [4.0.6-r10] - 2024-01-XX

### Added
- **Enhanced Monitoring**: Improved metrics collection and health monitoring
- **VPN Health Checks**: Comprehensive VPN connectivity monitoring
- **System Health**: Detailed system health reporting and metrics

### Enhanced
- **Health Check Scripts**: Improved reliability and error handling
- **Monitoring Integration**: Better integration with monitoring systems
- **Documentation**: Enhanced setup and troubleshooting guides

### Fixed
- **Health Check Issues**: Resolved various health check reliability problems
- **Metrics Collection**: Fixed metrics collection and reporting issues

## [4.0.6-r9] - 2024-01-XX

### Added
- **Monitoring Improvements**: Enhanced monitoring capabilities
- **Health Check Enhancements**: Improved health check functionality

### Fixed
- **Various Bug Fixes**: Multiple stability and reliability improvements

## [4.0.6-r8] - 2024-01-XX

### Added
- **Initial Monitoring**: Basic monitoring and health check functionality
- **Health Check Scripts**: Initial health check implementation

### Enhanced
- **Container Stability**: Improved container reliability and performance

---

## Migration Notes

### From v4.0.6-r13 to v4.0.6-r14
- **New Monitoring Options**: Choose between Prometheus (simple) or InfluxDB2 (advanced)
- **Enhanced Health Data**: More comprehensive system information available
- **No Breaking Changes**: Existing configurations continue to work

### From v4.0.6-r12 to v4.0.6-r13
- **Enhanced Health Endpoint**: More detailed health information available
- **Backward Compatible**: All existing functionality preserved

### From v4.0.6-r11 to v4.0.6-r12
- **Variable Migration**: Update TRANSMISSION_EXPORTER_* to METRICS_* variables
- **Port Changes**: Metrics now available on port 9099 by default
- **Configuration Update**: Review and update environment variables

### General Upgrade Process
1. Pull the latest image: `docker pull magicalyak/transmissionvpn:latest`
2. Stop existing container: `docker stop transmission`
3. Remove old container: `docker rm transmission`
4. Update environment variables if needed
5. Start new container with existing configuration

---

## Environment Variables

### Current Variables (v4.0.6-r14)
- `METRICS_ENABLED=true` - Enable built-in metrics server
- `METRICS_PORT=9099` - Metrics server port
- `METRICS_INTERVAL=30` - Metrics collection interval
- `HEALTH_CHECK_TIMEOUT=10` - Health check timeout
- `EXTERNAL_IP_SERVICE=ifconfig.me` - External IP detection service

### Deprecated Variables
- `TRANSMISSION_EXPORTER_ENABLED` → Use `METRICS_ENABLED`
- `TRANSMISSION_EXPORTER_PORT` → Use `METRICS_PORT`

---

For detailed information about specific releases, see the individual release notes files or the [GitHub Releases](https://github.com/magicalyak/transmissionvpn/releases) page.