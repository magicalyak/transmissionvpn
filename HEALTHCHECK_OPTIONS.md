# TransmissionVPN Healthcheck

The image ships **one** healthcheck, `/root/healthcheck.sh`, and wires it up itself in the
Dockerfile:

```dockerfile
HEALTHCHECK --interval=1m --timeout=10s --start-period=2m --retries=3 \
  CMD /root/healthcheck.sh
```

You do **not** need a `healthcheck:` block in your `docker-compose.yml`. If you don't
define one, you get the above.

> **If you are copying an older compose file:** earlier versions of this repo documented
> `/root/healthcheck-smart.sh` and `/root/healthcheck-fixed.sh`. Those scripts no longer
> exist in the image. A `healthcheck:` block pointing at either one fails on every run, so
> the container reports `unhealthy` forever regardless of its actual state. Remove the
> block, or point it at `/root/healthcheck.sh`.

## What it checks

In order, stopping at the first failure that determines the exit code:

1. **Transmission** is responding on its RPC port.
2. **VPN interface** exists and is up (read from `/tmp/vpn_interface_name`).
3. **VPN connectivity** — ICMP to `HEALTH_CHECK_HOST`, then `HEALTH_CHECK_HOST_FALLBACK`.
   A failure is recorded only when *both* hosts fail, so one host rate-limiting ICMP
   cannot mark the container unhealthy on its own.
4. **DNS resolution** through the tunnel.
5. **IP leak** and **DNS leak** detection — both opt-in, off by default.

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | All checks passed |
| `1` | Transmission is down |
| `2` | VPN interface is down |
| `3` | VPN interface is missing |
| `4` | VPN connectivity failed (both probe hosts) |
| `5` | DNS resolution failed |
| `6` | IP leak detected |

Docker only distinguishes zero from non-zero, so all of these show as `unhealthy`. The
specific code is useful when running the script by hand.

### Behaviour

- **VPN up + Transmission up** → healthy
- **VPN down** → unhealthy immediately; there is no grace period
- **Transmission down** → unhealthy

The `--start-period=2m` in the Dockerfile is what covers startup: failures during the
first two minutes do not count against the retry budget, which is enough for the tunnel to
come up. Once past that, a VPN failure marks the container unhealthy on the next check.

## Configuration

All optional, all read from the environment:

| Variable | Default | Effect |
|----------|---------|--------|
| `HEALTH_CHECK_HOST` | `1.1.1.1` | Primary ICMP probe target |
| `HEALTH_CHECK_HOST_FALLBACK` | `9.9.9.9` | Secondary probe; set empty to disable |
| `CHECK_IP_LEAK` | `false` | Compare external IP against the tunnel |
| `CHECK_DNS_LEAK` | `false` | Check resolvers in use |
| `METRICS_ENABLED` | `false` | Write metrics to `/tmp/metrics.txt` |

Avoid Google anycast addresses (`8.8.8.8`) as `HEALTH_CHECK_HOST`: they aggressively
rate-limit ICMP from VPN exit IPs, which used to false-fail this check.

```yaml
environment:
  - HEALTH_CHECK_HOST=1.1.1.1
  - HEALTH_CHECK_HOST_FALLBACK=9.9.9.9
  - CHECK_IP_LEAK=true
  - METRICS_ENABLED=true
```

## Relaxing or replacing it

**Transmission-only** — never unhealthy because of the VPN. Useful in development, but note
that it will report healthy while the tunnel is down:

```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -fsS http://localhost:9091/transmission/web/ >/dev/null || exit 1"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

**Off entirely:**

```yaml
healthcheck:
  disable: true
```

**Longer startup window** — keep the built-in check but give a slow provider more room:

```yaml
healthcheck:
  test: ["CMD", "/root/healthcheck.sh"]
  interval: 1m
  timeout: 10s
  retries: 3
  start_period: 5m
```

## Testing

```bash
# Run it by hand and see the specific exit code
docker exec transmissionvpn /root/healthcheck.sh; echo "Exit code: $?"

# Why it failed
docker exec transmissionvpn tail -20 /tmp/healthcheck.log

# Current status
docker ps --format "table {{.Names}}\t{{.Status}}"
```

If the healthcheck fails at startup and never recovers, the VPN itself is the more likely
problem — check `docker exec transmissionvpn cat /tmp/vpn-setup.log`, which records why
`vpn-setup.sh` did or did not finish. That file is truncated on every container start, so
read it from the run you are actually debugging.
