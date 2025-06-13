# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.6-r7] - 2024-12-19

### Added
- **Comprehensive Monitoring Stack**: Complete Prometheus + Grafana monitoring solution
- **Automated Troubleshooting**: `fix-prometheus-issues.sh` script for diagnosing monitoring problems
- **Enhanced Prometheus Configuration**: Fixed container networking and scraping targets
- **Grafana Provisioning**: Automatic datasource and dashboard configuration
- **Monitoring Documentation**: Complete setup guide with troubleshooting steps
- **Health Metrics Integration**: Improved internal health metrics collection
- **Network Connectivity Fixes**: Proper Docker container networking for metrics

### Fixed
- **Prometheus Scraping Issues**: Fixed `localhost` vs container name targeting
- **Metrics Collection**: Resolved `METRICS_ENABLED=false` causing empty metrics
- **Container Networking**: Fixed connectivity between Prometheus and TransmissionVPN containers
- **Health Check Accuracy**: Improved health check reliability and reporting
- **Documentation Accuracy**: Updated monitoring setup instructions

### Changed
- **Monitoring Architecture**: Streamlined built-in vs external metrics approach
- **Prometheus Targets**: Updated configuration to use proper container names
- **Docker Compose**: Enhanced monitoring stack with health checks and dependencies
- **Environment Variables**: Clarified metrics-related configuration options

### Technical Details
- Fixed Prometheus configuration to target `transmissionvpn:9099` instead of `localhost:9099`
- Added comprehensive troubleshooting script with automated diagnostics
- Enhanced Docker networking configuration for monitoring stack
- Improved Grafana provisioning with automatic Prometheus datasource setup
- Added health checks and dependency management to monitoring containers

## [4.0.6-r6] - 2024-12-18

### Added
- Workflow support and documentation fixes
- Versioning alignment improvements

## [4.0.6-r2] - 2024-12-17

### Added
- Second release with bug fixes and features

## [4.0.6-r1] - 2024-12-16

### Added
- First release based on Transmission 4.0.6 