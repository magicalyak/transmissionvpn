# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v4.1.2-r6] - 2026-09-08

### Fixed
- **A healthy forwarded port could report as `degraded` for 15 minutes after startup.** r5 cached the `port-test` result for the full `PORT_TEST_INTERVAL` regardless of outcome. The metrics server probes during startup, before `pia-port-forward.sh` has set Transmission's peer port, so it captured a transient "closed" and held it — producing `transmissionvpn_port_open 0`, `pf_port_bound_but_unreachable`, and `transmissionvpn_healthy 0` on a pod whose port was actually open. Caught on the live cluster immediately after the r5 rollout: the live `port-test` RPC returned `port-is-open: true` while the metric still read `0`. Failures are now re-probed after the new `PORT_TEST_RETRY_INTERVAL` (default 60s, clamped to never exceed `PORT_TEST_INTERVAL`); successes are still held for the full interval. A false `degraded` is far less harmful than the false `healthy` r5 fixed, but left alone it trains operators to ignore the alert, which defeats the purpose.

## [v4.1.2-r5] - 2026-09-08

Observability follow-up to r4. r4 made the forwarded port repair itself; this makes the failure visible while it is happening.

### Fixed
- **A closed peer port no longer reports as healthy when port forwarding is enabled.** `update_health_data()` classified a failed `port-test` as the informational notice `port_not_open_vpn_expected` whenever the VPN was connected, leaving overall status `healthy`. That is sound when the provider does not forward ports — most do not — but it is exactly what hid the r4 fault for seven days: `port-test` returned false the entire time and `transmissionvpn_healthy` stayed `1`. Leniency now applies only when `PIA_PORT_FORWARD` is not set. With it set, a closed port is a warning, and the firewall rule state distinguishes `pf_rules_missing` (the container is dropping inbound peers itself) from `pf_port_bound_but_unreachable` (rules correct, binding gone upstream).
- **`port-test` no longer runs every 30 seconds.** It asks Transmission to probe the peer port from outside, so every call hit an external checker on each `METRICS_INTERVAL` tick. It now runs on its own schedule via `PORT_TEST_INTERVAL`, defaulting to 900s to match the PIA keepalive — the rate at which the underlying state can actually change. Cached between runs.

### Added
- **Forwarded-port metrics**: `transmissionvpn_pf_enabled`, `transmissionvpn_pf_port`, `transmissionvpn_pf_rules_present`, `transmissionvpn_pf_rules_found`, and `transmissionvpn_pf_state_age_seconds`. `pf_rules_present` is the one to alert on — it is local, needs no external probe, and drops the moment a firewall rebuild removes the rules, roughly 15 minutes before the keepalive restores them. `pf_state_age_seconds` catches the case where the keepalive has died and the rule state is frozen at its last good value.
- **`pia-pf-firewall.sh` publishes its observed rule state** to `/tmp/pia_pf_state` on every apply and status check. The metrics server runs unprivileged (`s6-setuidgid abc`) and cannot inspect iptables itself, so the privileged callers publish for it. Written via a temp file and rename so readers never see a half-written file.
- **`test-pf-metrics.py`**: 15 assertions covering state-file parsing, the classification of the original seven-day fault, preservation of the previous lenient behaviour when port forwarding is off, and `port-test` throttling. It calls the real `classify_port_state()` rather than a copy, so it cannot drift from the shipped logic.

### Changed
- Peer-port reachability is deliberately **not** wired into the Docker `HEALTHCHECK` exit code. That drives the k3s liveness probe, and restarting draws a fresh PIA forwarded port — a restart cannot fix an unreachable port, so making it fatal would risk a crash-loop on a condition the restart does not address. It is exposed as metrics and health warnings instead.

## [v4.1.2-r4] - 2026-09-08

### Fixed
- **PIA forwarded port was silently firewalled off, dropping all inbound BitTorrent peers while every log line reported success.** `pia-port-forward.sh` installed the `INPUT ACCEPT` rules for the forwarded port exactly once, with `2>/dev/null || true`, and then logged `"Added INPUT rules for port N"` unconditionally — a rule that was never installed still logged as added. The rules were never re-asserted afterwards: the keepalive loop re-bound the port at PIA every 900s but never touched iptables, and `pia-port-forward` is an s6-rc *oneshot*: it does re-run when the whole s6 stack starts (a new container), but `attempt_vpn_restart()` re-runs `/etc/cont-init.d/50-vpn-setup` directly, in place, without going through s6-rc — so on the path that actually rebuilds the chain the oneshot is not re-run and nothing restores the rules. Meanwhile `vpn-setup.sh` flushes the `INPUT` chain and is re-run in place by `vpn-monitor`'s `attempt_vpn_restart()` when `AUTO_RESTART_VPN=true`, rebuilding the chain without the forwarded port. Observed on a live deployment: `INPUT` policy `DROP` with 8751 dropped packets and no rule for the forwarded port, while Transmission listened on the port, PIA had it bound, and the keepalive logged `Port binding refreshed successfully` every 15 minutes; `port-test` returned `{"port-is-open":false}` and adding the rule by hand flipped it to `true` immediately.
- **The kill switch never restored the dynamic forwarded port.** `vpn-killswitch.sh`'s BitTorrent block keyed only off `$TRANSMISSION_PEER_PORT` and never read `/tmp/pia_forwarded_port`, so the port PIA actually issued was invisible to it; `emergency_killswitch()` did not restore it at all. Both rebuild paths now re-assert the rules as part of the rebuild.

### Added
- **`root/pia-pf-firewall.sh`** (`/usr/local/bin/pia-pf-firewall.sh`), a shared helper that owns port discovery and the rule spec for all four call sites (`pia-port-forward.sh`, `vpn-setup.sh`, both kill switch functions, and the service teardown). It prefers the live port in `/tmp/pia_forwarded_port` and falls back to `$TRANSMISSION_PEER_PORT`, installs rules idempotently with `iptables -C ... || iptables -I ...`, and **verifies each rule with `-C` after inserting it** — success is logged only when iptables confirms the rule is in the chain, otherwise a real `ERROR` is logged. Also usable directly: `pia-pf-firewall.sh [apply|remove|status|port]`.
- **Self-healing.** The keepalive loop re-asserts the rules every cycle, so a firewall rebuild now recovers within 15 minutes without a container restart. `vpn-setup.sh` and both kill switch paths restore them immediately as part of the rebuild.
- **`vpn-killswitch.sh status`** now reports whether the forwarded/peer port rules are actually present.
- **`test-killswitch.sh`** gained a forwarded/peer-port section: rules present on the VPN interface, absent (dropped) on `eth0`, Transmission `port-test` reachability, recovery after the rules are deleted, and idempotency of a repeated apply.

### Changed
- **The BitTorrent peer port is no longer `ACCEPT`ed on `eth0`.** `vpn-setup.sh` unconditionally added `INPUT -i eth0 ... -j ACCEPT` for `$TRANSMISSION_PEER_PORT`, which contradicted the kill switch's stated intent that peer traffic only cross the VPN interface: any peer able to route to the container's `eth0` address reached the client off-tunnel. The container refuses to start without a VPN client, so no non-VPN deployment of this image depended on it. The port is now `ACCEPT`ed on the VPN interface and explicitly `DROP`ped on `eth0`.
  - **Behaviour change:** if you set `LAN_NETWORK`, LAN hosts could previously reach the peer port over `eth0` via the blanket LAN `ACCEPT` rule. The new `eth0` DROP is inserted at the head of `INPUT` and takes precedence, so LAN peers can no longer connect to the peer port directly. Peer traffic through the tunnel is unaffected.
- **`TRANSMISSION_PEER_PORT` is documented as a firewall hint, not a Transmission setting.** It never set Transmission's peer port (that is `PEERPORT`, handled by `init-transmission-config`), and with `PIA_PORT_FORWARD=true` it should not be set at all — PIA issues a different port on every container start, so any static value is stale as soon as the container is recreated.

## [v4.1.2-r3] - 2026-07-30

### Fixed
- **Kill switch could get permanently stuck in its most restrictive state after a container restart within the same pod.** `vpn-setup.sh` added the `LAN_NETWORK` route with `ip route add`, which is not idempotent: on a restart, the pod's network namespace (and therefore the route from the prior run) persists, so the second `ip route add` failed with "File exists". Under `set -e` that aborted the script before the LAN/VPN `ACCEPT` rules and the final `/tmp/vpn_setup_complete` flag were written, leaving `vpn-monitor` waiting forever on "Waiting for initial VPN setup to complete..." and the OUTPUT chain stuck on loopback/DNS-block/established only — blocking all new outbound connections, not just non-VPN ones. Switched to `ip route replace`, which succeeds whether or not the route already exists.

## [v4.1.2-r2] - 2026-06-29

### Fixed
- **VPN health check no longer false-trips the kill switch under ICMP rate-limiting.** The connectivity probe now sends multiple ICMP packets (any reply counts as healthy) instead of a single packet with no retry, so normal ICMP loss to a rate-limiting host is no longer mistaken for a dead tunnel.

### Changed
- **Default `HEALTH_CHECK_HOST` is now `1.1.1.1`** (Cloudflare) instead of `google.com`. Google anycast IPs aggressively rate-limit/drop ICMP from VPN exit IPs, which was the root cause of the kill switch repeatedly stopping Transmission on healthy tunnels. The env-var override is unchanged.
- **New `HEALTH_CHECK_HOST_FALLBACK` (default `9.9.9.9`).** Tried only when the primary host fails; a connectivity failure is recorded only when both hosts fail. Set it empty to disable the fallback.

## [v4.1.2-r1] - 2026-06-17

### Changed
- **Base image bumped to `lscr.io/linuxserver/transmission:4.1.2-r0-ls349`** (was `4.1.2-r0-ls348`). One upstream linuxserver baselayer rebuild worth of package/security updates; no Transmission version change (still 4.1.2).

### CI
- Bumped `aquasecurity/trivy-action` from `0.35.0` to `0.36.0`.

## [v4.1.2-r0] - 2026-06-10

### Changed
- **Base image bumped to `lscr.io/linuxserver/transmission:4.1.2-r0-ls348`** (was `4.1.1-r1-ls344`). Moves Transmission from 4.1.1 to the 4.1.2 bugfix release (20+ fixes) plus four upstream linuxserver baselayer rebuilds worth of package/security updates. No functional changes in this repo.

### Security
- Inherits upstream Transmission 4.1.2 hardening: rejects bencoded data containing invalid characters, and fixes a 4.1.0 crash triggered when a peer supplies a `reqq` value smaller than 32 in the LTEP handshake (remote DoS from a malicious peer).

## [v4.1.1-r5] - 2026-05-22

### Changed
- **Base image bumped to `lscr.io/linuxserver/transmission:4.1.1-r1-ls344`** (was `ls338`). Picks up six upstream linuxserver releases worth of package updates and security patches. No functional changes in this repo.

## [v4.1.1-r4] - 2026-05-03

### Fixed
- **iptables flush no longer wipes WireGuard / OpenVPN PostUp rules**: `vpn-setup.sh` now resets policies to ACCEPT and flushes `INPUT/FORWARD/OUTPUT/nat/mangle` *before* bringing the tunnel up, then re-applies the strict-DROP killswitch policies after. Previously the flush ran *after* `wg-quick up` / `openvpn`, which discarded any iptables rules installed by `PostUp =` hooks in user-supplied WireGuard configs (or `up` scripts in OpenVPN configs) — common in provider-supplied templates. The killswitch end-state is unchanged.

### Security
- **IPv6 killswitch added**: `vpn-setup.sh` now sets `ip6tables -P INPUT/OUTPUT/FORWARD DROP` with explicit ACCEPT for loopback and established/related connections only. Closes a real leak: if the host advertised an IPv6 default route, IPv6 traffic could egress on `eth0` outside the tunnel because no `ip6tables` rules were applied. Soft-fails on kernels without `CONFIG_IP6_NF_IPTABLES`.

## [v4.1.1-r3] - 2026-05-02

### Fixed
- **WireGuard DNS resolution**: `wg-quick` shells out to `resolvconf` when processing the `DNS = ...` line in WireGuard configs. Without `openresolv` installed that step failed, leaving the tunnel partially up and the killswitch blocking everything else, presenting as ping/DNS dead. Added `openresolv` to the Alpine package list so `wg-quick` can update `/etc/resolv.conf` properly.

### Documentation
- **Privoxy enable requirement**: Clarified in the README that the example `docker-compose.yml` publishes port `8118` but `ENABLE_PRIVOXY=yes` is also required to actually start the service.

## [v4.1.0-r9] - 2026-03-08

### Added
- **PIA Port Forward Finish Script**: Proper cleanup when the port forwarding service stops, including killing the keepalive process and removing firewall rules.
- **PIA Port Forwarding Documentation**: Added port forwarding section to VPN_PROVIDERS.md, added PIA port forwarding example to EXAMPLES.md.

### Fixed
- **Documentation**: Replaced deprecated `VPN_PROVIDER` variable with correct `VPN_CLIENT` and `VPN_CONFIG` in all examples and templates.

## [v4.1.0-r8] - 2026-03-08

### Fixed
- **PIA Port Forwarding BusyBox Compatibility**: Gateway detection used `grep -oP` (Perl regex) which is not available in BusyBox/Alpine. Replaced with `awk` for compatible parsing.
- **PIA Port Forwarding DNS Race**: Token API request failed because DNS was not yet configured when the port forwarding script started. Added DNS readiness check with retries before making API calls.
- **PIA Token API URL**: Updated from deprecated `/api/client/v2/token` endpoint to current `/gtoken/generateToken`.
- **PIA Token URL Encoding**: Tokens containing `+` characters were corrupted in URL query parameters. Switched to `--data-urlencode` for all PIA API calls.
- **PIA Gateway Certificate**: Simplified gateway API calls to use `-k` (skip verify) since the gateway is on the trusted VPN interface, fixing `--connect-to` cert verification failures.
- **Transmission RPC Auth for Port Config**: Session ID retrieval and port configuration now include RPC authentication credentials, fixing 400/401 errors when `TRANSMISSION_RPC_AUTHENTICATION_REQUIRED` is enabled.
- **PIA Forwarded Port Firewall**: Automatically add INPUT iptables rules for the PIA forwarded port on the VPN interface so inbound peer connections can reach Transmission.

## [v4.1.0-r7] - 2026-03-08

### Fixed
- **VPN Monitor Crash After 2.5 Minutes**: The monitor script used `local` variables inside the main loop (outside any function), which is a bash error. With `set -e`, this crashed the script after 5 consecutive healthy checks (~2.5 minutes), triggering the finish script's kill switch which killed the VPN connection. Removed invalid `local` declarations from the main monitoring loop.

## [v4.1.0-r6] - 2026-03-08

### Fixed
- **VPN Monitor Finish Script Kill Switch**: The s6 finish script applied a blanket DROP-all kill switch when the monitor service restarted, which blocked OpenVPN from maintaining its connection. The finish script now preserves VPN server and tun interface exceptions, matching the main kill switch behavior.

## [v4.1.0-r5] - 2026-03-08

### Fixed
- **VPN Kill Switch Deadlock**: Kill switch now exempts VPN server traffic so OpenVPN/WireGuard can reconnect after a mid-session drop. Previously, the kill switch blocked all outbound traffic including VPN server connections, preventing reconnection and requiring manual pod restart.

## [v4.1.0-r4] - 2026-03-07

### Fixed
- **VPN Monitor Race Condition**: Added configurable initial delay (VPN_INITIAL_DELAY, default 15s) after VPN setup completes before health checks begin. Prevents the monitor from declaring failure and enforcing the kill switch before OpenVPN routes are fully propagated, which would then block the working VPN connection.

## [v4.1.0-r1] - 2026-02-15

### Updated
- **Base Image**: Updated to LinuxServer Transmission 4.1.0-r0-ls329 (from 4.0.6-r5-ls323)

### Upstream Changes (Transmission 4.1.0)
- Major Transmission version bump from 4.0.6 to 4.1.0

## [v4.0.17] - 2026-01-07

### Fixed
- **VPN Kill Switch Deadlock**: Fixed ip rule/route commands failing on container restart due to "File exists" errors. With set -e enabled, these failures caused the vpn-setup.sh script to exit before adding VPN server exception rules, resulting in a kill switch deadlock where the VPN couldn't connect.

### Updated
- **Base Image**: Updated to LinuxServer Transmission 4.0.6-r5-ls323 (from ls322)

## [4.0.6-r23] - 2025-09-20

### Added
- **Enhanced VPN Kill Switch**: Implemented strict iptables rules with default DROP policies on all chains
- **DNS Leak Prevention**: Block all DNS queries (port 53) on non-VPN interfaces
- **Active VPN Monitoring Service**: Continuous health checks with configurable intervals
- **Auto-Recovery**: Optional automatic VPN restart on failure (AUTO_RESTART_VPN)
- **External IP Verification**: Monitor for IP leaks by checking external IP
- **DNS Resolution Testing**: Verify DNS is working through VPN
- **Kill Switch Test Script**: Automated verification tool (test-killswitch.sh)
- **Emergency Kill Switch**: Immediate traffic blocking when VPN fails
- **VPN Monitor Finish Script**: Proper cleanup when service stops

### Enhanced
- **VPN Monitor Service**: Now supports environment variables for configuration
  - VPN_CHECK_INTERVAL: Configurable check frequency (default: 30s)
  - VPN_MAX_FAILURES: Failures before action (default: 3)
  - CHECK_DNS: Enable/disable DNS testing (default: true)
  - CHECK_EXTERNAL_IP: Enable/disable IP verification (default: true)
- **Security Posture**: Multiple layers of protection against IP leaks
- **BitTorrent Port Handling**: Ensure peer ports only work through VPN
- **Documentation**: Added comprehensive security documentation

### Fixed
- **Kill Switch Reliability**: Ensured no traffic leaks even during VPN reconnection
- **DNS Leak Prevention**: Fixed potential DNS leaks during VPN establishment
- **Transmission Protection**: Stops immediately when VPN fails

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