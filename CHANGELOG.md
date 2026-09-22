# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v4.1.2-r9] - 2026-09-22

Correctness release for the health check, and a round of removing things that looked live and were not. The two headline fixes in this release were silently broken for every user who did not work around them by hand: a default that the r2 notes said had changed but never did, and a DNS check that could not fail.

**Upgrade note.** Two defaults change behaviour on containers that never overrode them. `HEALTH_CHECK_HOST` now really is `1.1.1.1` rather than `google.com`, which is what v4.1.2-r2 announced; if you pinned the value yourself to work around that, the pin is now redundant but harmless. The DNS check now actually resolves something, so a container with genuinely broken DNS that has been reporting healthy will start reporting unhealthy - that is the check doing its job for the first time, not a regression. Set `DNS_CHECK_HOST=` empty to turn it off deliberately.

### Fixed
- **The `HEALTH_CHECK_HOST` default announced in r2 never shipped.** v4.1.2-r2 (#35) said "Default `HEALTH_CHECK_HOST` is now `1.1.1.1` instead of `google.com`", fixing a kill switch that repeatedly stopped Transmission on perfectly healthy tunnels because Google anycast rate-limits ICMP from VPN exit IPs. It changed the fallback in `healthcheck.sh` to `${HEALTH_CHECK_HOST:-1.1.1.1}` and left `ENV HEALTH_CHECK_HOST=...google.com` in the Dockerfile. An `ENV` is always set, so the fallback never applied and every user who did not override the variable kept the exact default the release notes claimed had been fixed - for six releases. The cluster deployment this image is developed against carries a comment noting the image "still ships google.com despite release notes" and pins the value by hand, which is how it was found. The Dockerfile now matches what was announced. (#48)
- **The DNS check had been passing unconditionally since it was written.** `check_dns()` resolved `HEALTH_CHECK_HOST`, which is an IP address by design, and `getent hosts` hands a literal address straight back without consulting a resolver at all. The check therefore succeeded with DNS completely dead. Verified in the shipped image: `getent hosts 192.0.2.1` exits 0 and echoes the address even though TEST-NET-1 has no PTR record, while `getent hosts nonexistent.invalid` exits 2. This is a check that can mark the container unhealthy and stop Transmission, so a silent always-pass is worse than not having the check at all. DNS now has its own target, `DNS_CHECK_HOST` (default `one.one.one.one`), which must be a name; an address in it is reported as unusable rather than quietly treated as a pass. Keeping the two probes separate also stops a DNS outage from failing the connectivity probe as well, which used to make the two failures indistinguishable in the logs. (#48)
- **A private `HEALTH_CHECK_HOST` guaranteed a false failure.** A LAN address is not routed through the tunnel, so the connectivity probe fails however healthy the VPN is. The probe now substitutes `1.1.1.1` and warns why. This logic had been written in `root/healthcheck-wrapper.sh`, which the Dockerfile never copied into the image, so it had never once executed. (#48)
- **`scripts/clean-docker-tags.sh` captured its own progress messages as tag names.** `get_docker_hub_tags()` printed "Fetching page 1..." to stdout from inside the function whose stdout the caller was capturing. Progress now goes to stderr, and both array builds read line by line instead of relying on word splitting. (#47)

### Deprecated
- **`transmissionvpn_port_forwarding_available` and `transmissionvpn_vpn_supports_port_forwarding`.** Neither reports what its name promises. The first computes the same expression as `transmissionvpn_port_open` - the port-test result - so it advertises port-forwarding availability and delivers external reachability. The second reads as a static provider capability but ANDs live VPN state with the live port test, so it reads `0` on a provider that does support forwarding whenever the tunnel happens to be down. Both were left alone in r5 to avoid changing semantics under existing dashboards; that rationale did not survive checking, since neither appears in README's metric table, in either Grafana dashboard under `monitoring/`, or in the Prometheus alerts that consume this endpoint. They are deprecated rather than removed or redefined: removal would drop a series without warning for anyone scraping a public image, and redefinition is worse than removal because the series keeps reporting while its meaning shifts underneath, which looks like a real state transition and can fire an alert. **Both still emit exactly the values they did before** - only the HELP text changes, so the deprecation is visible from the endpoint itself. Use `transmissionvpn_port_open` for reachability and the `transmissionvpn_pf_*` metrics added in r5, which are documented and are what the alerts already use. (#44)

### Removed
- **`root/healthcheck-wrapper.sh`**, which shipped nowhere. The Dockerfile copies only `root/healthcheck.sh`, and nothing in the repository referenced the wrapper; it `exec`s `/root/healthcheck.sh`, so it was plainly written to run inside the image, but no build ever put it there. Deleting it changes no runtime behaviour because none of it ever ran. The one useful behaviour it carried - overriding a LAN `HEALTH_CHECK_HOST` - was moved into `healthcheck.sh` where it actually executes (above). Same class of problem as the `healthcheck-smart.sh` references cleared in #41. (#46)

### Changed
- **`scripts/release.sh` rewritten to match how releases are actually cut.** It had `VERSION="v4.0.6-r15"` hardcoded, twelve releases stale, and every recent release was cut by hand instead. Worse than stale: it ran `git add .` and committed whatever happened to be in the tree under a fixed message listing features from an old release, and its tag annotation was a block of fixed marketing text that would have been wrong for any new release. It also demanded a running Docker daemon while never building anything, since the build happens in GitHub Actions. It now takes the version as an argument, validates it against the pattern `build-and-publish.yml` triggers on, insists on a clean tree on `main` that matches `origin`, and creates an annotated tag following the `Release <version>: <summary>` convention. It commits nothing, and it does not push - pushing a `v*` tag publishes `latest`/`stable` and Flux rolls it to a live cluster, so that stays a separate command a human types. It prints both the push command and how to undo. (#46)
- **README's health-check table now describes the variables the health check reads.** It documented `CHECK_DNS` and `CHECK_EXTERNAL_IP`, neither of which `root/healthcheck.sh` reads, while omitting `CHECK_DNS_LEAK` and `CHECK_IP_LEAK`, which it does. The two inert variables remain set in the Dockerfile for now rather than being removed silently in a patch release. (#48)
- **README's `NAME_SERVERS` default corrected** from "(auto)" to the `8.8.8.8,1.1.1.1` the Dockerfile actually sets, since the new DNS troubleshooting entry depends on that being a known value. (#45)

### Added
- **`docs/TROUBLESHOOTING.md` entries for the two failures both recent reporters hit.** Issues #33 and #36 each ticked "I have checked the troubleshooting guide", and for both the guide genuinely had nothing: there was no entry for `127.0.0.11` and none for "Waiting for initial VPN setup to complete...". The DNS entry explains why an address the user never configured appears in the error - Docker's embedded resolver does not listen on port 53, NAT rules in the container's own netns redirect `127.0.0.11:53` to the port it does listen on, and the `iptables -t nat -F` that `vpn-setup.sh` runs before starting the tunnel removes that redirect. Its main point is diagnostic: on a successful start the container rewrites `resolv.conf` to `NAME_SERVERS` and never consults `127.0.0.11` again, so seeing this error at all means the tunnel never came up. The DNS message is a symptom; the VPN failure is the fault. It also documents the consequence that has no error message - this container cannot resolve other containers by name, deliberately, because routing lookups through Docker's resolver would send them out via the host and outside the tunnel - and gives the two workarounds that do not reintroduce that leak. The stalled-setup entry covers r8's behaviour and states plainly that a dark web UI after upgrading to r7 is the intended fail-closed response to a pre-existing config fault rather than a regression, including the relative bind-mount trap from #36 where `./config` resolves against the compose file's directory and a wrong mount presents as an *empty* directory rather than a missing one. (#45)
- **ShellCheck is enforced in CI.** `CONTRIBUTING.md` has always asked contributors to follow ShellCheck's recommendations and nothing checked it. `scripts/shellcheck-all.sh` and a workflow that runs exactly that script are now in place, so a local run and a CI run agree. Getting there meant declaring `# shellcheck shell=bash` on the s6 scripts, whose `#!/command/with-contenv bash` shebang ShellCheck cannot parse, and clearing the 43 findings that surfaced once it could - 20 of them mechanical `SC2155` splits, each checked individually for a right-hand side that could newly surface a non-zero status under `set -e`. Two sites are deliberate and carry documented disables instead of fixes: the `ls $ovpn_config` calls in `vpn-monitor` expand a glob held in a variable, so quoting them would break VPN reconnection when `VPN_CONFIG` is a pattern. The gate pins `shellcheck-py==0.11.0.1`, because without a pin it passes or fails on a runner-image bump rather than on the change under review; the script reports the version it used and warns when it differs from the pin. It also lists untracked files, so a script that has just been written is checked on the run before it is committed rather than being silently skipped exactly when it has the most to say. (#47)
- **`test-healthcheck-probe-targets.sh`**: 26 assertions over the probe-target logic, extracting the functions from the shipped script rather than copying them, and stubbing `getent` so nothing resolves and no network is touched. Mutation-tested against both health-check defects. (#48)
- **`test-metrics-render.py`**: 16 assertions that pin the values the deprecated metrics emit, so a later cleanup cannot quietly change them instead of removing them, and that check the exposition is well formed. (#44)
- **`root/vpn-setup.sh` now records why its EXIT trap is load-bearing.** `S6_BEHAVIOUR_IF_STAGE2_FAILS` is set neither in this Dockerfile nor in `lscr.io/linuxserver/transmission:4.1.2-r0-ls349` - confirmed by reading the base image config straight from the registry - and only the value `2` stops the container, so a failing `cont-init` script is not fatal here. s6 will not stop a container whose VPN setup aborted, which makes that trap the only thing standing between a failed setup and an unprotected container. It should not be removed as redundant. (#45)

## [v4.1.2-r8] - 2026-09-11

Diagnostics follow-up to r7. r7 made a failed VPN setup fail closed and made its log readable; this makes the container say so without being asked.

### Changed
- **`vpn-monitor` no longer waits on VPN setup in silence.** When `vpn-setup.sh` aborts, `/tmp/vpn_setup_complete` is never written and the monitor waits forever — previously repeating `Waiting for initial VPN setup to complete...` every five seconds, indefinitely, with no indication that anything was wrong or where to look. Issues #33 and #36 are both pages of exactly that line, and in both cases the answer was sitting in `/tmp/vpn-setup.log` the whole time. After `VPN_SETUP_WAIT_WARN_SECONDS` (default 150s, just past the two sequential 60s timeouts inside `vpn-setup.sh`) the monitor now warns once, prints the last 25 lines of `/tmp/vpn-setup.log` inline, states that the container is fail-closed, and drops the poll message from every 5s to every 60s so the real error is not buried. The wait itself is unchanged — it still waits rather than exiting, since exiting would only have s6 restart it into the same state.

### Added
- **`test-vpn-monitor-wait.sh`**: 9 assertions over `wait_for_vpn_setup()` — silence when setup is already complete, no warning for a normal startup, the warning firing exactly once past the threshold, the `vpn-setup.log` contents being surfaced, the backoff from 5s to 60s polling, and the missing-log case. Like `test-vpn-setup-failclosed.sh` it extracts the function from the shipped script rather than copying it, and shadows `sleep`, so it runs instantly and needs no container.

## [v4.1.2-r7] - 2026-09-11

Triage release. Everything here came out of working the two open issues (#33, #36), both of which had gone months without a reply. Neither reporter could see why their container had failed, and it turned out they were right not to be able to: the script that knows is the one whose output was being thrown away.

### Fixed
- **A failed VPN setup left the container with no kill switch at all.** `vpn-setup.sh` resets the firewall to ACCEPT and flushes it before starting the tunnel, so PostUp/up hooks survive and the handshake can get out. Every `exit 1` between that flush and the strict policies further down — a `VPN_CONFIG` that does not resolve, rejected credentials, a tunnel that never gets an IP — therefore left `INPUT/OUTPUT/FORWARD` on ACCEPT with empty chains, while Transmission was already up and listening. No VPN, and nothing stopping traffic either. Confirmed in the wild in #36, where a bind mount pointed at the wrong host directory: the abort happened in the OpenVPN config check, and the reporter could ping `8.8.8.8` straight off `eth0`. An EXIT trap now locks the firewall down to loopback-only on any non-zero exit, removes a stale `/tmp/vpn_setup_complete` left by a previous successful run, and preserves the original exit code. This deliberately takes the web UI down with it — a container that failed to build its kill switch should not look reachable — while `docker logs` and `docker exec` still work, so the error remains readable.
- **`vpn-setup.sh` diagnostics never reached `docker logs`.** The script redirected its own output to `/tmp/vpn-setup.log` with `exec &> ...` and only then set up `exec > >(tee -a ...)`. Each `tee` therefore started with the log file already installed as its own stdout, so it wrote the data back into the file rather than to the console, and nothing after line 19 ever reached the container's stdout. Every diagnostic the script prints was invisible from outside the container - including the `set -e` abort message that says *why* setup failed - leaving `/tmp/vpn-setup.log` (truncated on every run) as the only copy. This is why users hitting a failed VPN setup reported that the logs gave them nothing to go on (#33, #36). The file is now truncated up front and the tee attaches to the still-connected console fds.
- **"VPN_CONFIG not found" gave no way to tell a typo from a wrong bind mount.** `/config` comes from a host directory named by a relative path in `docker-compose.yml`, and relative volume paths resolve against the compose file's directory rather than the working directory; `01-ensure-vpn-config-dirs.sh` then creates `/config/openvpn` and `/config/wireguard` when absent, so a mount pointing somewhere unexpected presents as an *empty* directory rather than a missing one. The error now lists what the container actually sees in that directory, names the bind mount as the likely cause, and gives the `docker inspect` command to compare host and container paths. Applies to all four config-resolution failures, OpenVPN and WireGuard alike.
- **The example `docker-compose.yml` pointed its health check at a script that is not in the image.** It set `test: ["CMD", "/root/healthcheck-smart.sh"]`; that script and `/root/healthcheck-fixed.sh` were added in `59d37f8` and removed again in `feab90a`, but the compose file, `HEALTHCHECK_OPTIONS.md`, `README.md` and two scripts under `scripts/` were never updated. Only `/root/healthcheck.sh` is installed (`Dockerfile:158`). Anyone copying the example got a health check that failed on every run, reporting the container `unhealthy` regardless of its actual state. The compose example now relies on the image's own `HEALTHCHECK`, which has a more appropriate 2 minute start period, and every remaining reference points at a script that exists.

### Changed
- **`HEALTHCHECK_OPTIONS.md` rewritten** around the one health check the image actually ships, with its real exit codes (0-6), the environment variables it honours, and worked examples for relaxing it to Transmission-only or disabling it. It previously presented three options, two of which had not existed for some time, and recommended one of the missing ones.
- **`.env.sample` health check section corrected.** It documented `VPN_HEALTH_REQUIRED` and `VPN_GRACE_PERIOD`, which nothing in the image reads - they belonged to the removed smart health check - and suggested `HEALTH_CHECK_HOST=google.com`, which contradicts the v4.1.2-r2 fix that moved the default off Google anycast precisely because it rate-limits ICMP from VPN exit IPs.

### Added
- **`test-vpn-setup-failclosed.sh`**: 17 assertions covering the lockdown rules, exit-code preservation, stale-flag removal, the success path leaving the firewall untouched, and the content of the missing-config report. It extracts the two functions from the shipped `root/vpn-setup.sh` rather than copying them, so it cannot drift, and stubs `iptables`/`ip6tables` — no container, privileges or network required.

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