#!/usr/bin/env python3
"""Tests that transmissionvpn_vpn_connected reports a working tunnel, not an address.

On 2026-09-22 the PIA tunnel stopped passing traffic and stayed dead for 38 hours.
tun0 kept its address (10.25.18.69) the whole time, and the metrics server set
'connected' as soon as a tun/wg/tap interface had an IPv4 address, so
transmissionvpn_vpn_connected stayed 1 and transmissionvpn_healthy never moved.

'connected' now comes from vpn-monitor's tunnel probe, published to a state file,
and a missing or stale result counts as not connected. These tests fake the
interface table (psutil) and write the state file directly, so no network, no
container and no Transmission are involved.

Run: python3 test-tunnel-metrics.py
"""
import importlib.util
import os
import socket
import sys
import tempfile
import time
import types
from collections import namedtuple

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   'scripts', 'transmission-metrics-server.py')

_passed = 0
_failed = 0


def check(name, got, want):
    global _passed, _failed
    if got == want:
        print(f"  ok   {name}")
        _passed += 1
    else:
        print(f"  FAIL {name}: got {got!r} want {want!r}")
        _failed += 1


Addr = namedtuple('Addr', 'family address')
Stats = namedtuple('Stats', 'isup')
IO = namedtuple('IO', 'bytes_sent bytes_recv packets_sent packets_recv errin errout dropin dropout')


def fake_psutil(interfaces):
    """interfaces: {name: (isup, ipv4 or None)}"""
    mod = types.ModuleType('psutil')
    mod.net_if_addrs = lambda: {
        name: ([Addr(socket.AF_INET, ip)] if ip else [])
        for name, (_up, ip) in interfaces.items()
    }
    mod.net_if_stats = lambda: {name: Stats(up) for name, (up, _ip) in interfaces.items()}
    mod.net_io_counters = lambda pernic=False: {
        name: IO(0, 0, 0, 0, 0, 0, 0, 0) for name in interfaces
    }
    return mod


def load(state_file, interfaces, **env):
    sys.modules['psutil'] = fake_psutil(interfaces)
    sys.modules.setdefault('requests', types.ModuleType('requests'))
    os.environ['VPN_STATE_FILE'] = state_file
    os.environ.pop('VPN_STATE_MAX_AGE', None)
    os.environ.pop('VPN_CHECK_INTERVAL', None)
    os.environ.update(env)
    spec = importlib.util.spec_from_file_location("tunnel_metrics_under_test", SRC)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    # Everything that is not VPN state reports healthy, so any change in the
    # overall status comes from the tunnel alone.
    module.get_system_info = lambda: {'disk': {'usage_percent': 10},
                                      'memory': {'percent': 10}, 'cpu': {}}
    module.get_transmission_health = lambda: {'daemon_running': True,
                                              'web_ui_accessible': True,
                                              'rpc_accessible': True,
                                              'port_test': True}
    module.get_container_info = lambda: {}
    # get_vpn_info shells out to curl for the external IP.
    module.subprocess.run = lambda *a, **k: types.SimpleNamespace(returncode=1, stdout='')
    return module


def write_state(path, connected, age=0):
    with open(path, 'w') as fh:
        fh.write(f"connected={connected}\nupdated={int(time.time() - age)}\n"
                 "failures=0\nrestarts=2\nmax_restarts=3\n")


def series(text, name):
    for line in text.splitlines():
        if line.startswith(name + ' '):
            return line.split(' ', 1)[1]
    return None


def scrape(mod):
    mod.update_health_data()
    return mod.generate_prometheus_metrics()


def main():
    tmp = tempfile.mkdtemp()
    state = os.path.join(tmp, 'vpn_tunnel_state')
    tun_up = {'eth0': (True, '10.42.0.17'), 'tun0': (True, '10.25.18.69')}

    print("Interface up with an address, but no traffic (the 2026-09-22 outage)")
    mod = load(state, tun_up)
    write_state(state, 0)
    text = scrape(mod)
    check("vpn_connected is 0", series(text, 'transmissionvpn_vpn_connected'), '0')
    check("healthy is 0", series(text, 'transmissionvpn_healthy'), '0')
    check("interface_up still 1, so 'no tunnel' and 'dead tunnel' differ",
          series(text, 'transmissionvpn_vpn_interface_up'), '1')
    check("warning names the VPN", 'vpn_disconnected' in mod.health_data.get('warnings', []), True)
    check("restart attempts are exported",
          series(text, 'transmissionvpn_vpn_restart_attempts'), '2')

    print("Interface up and the probe passes")
    write_state(state, 1)
    text = scrape(mod)
    check("vpn_connected is 1", series(text, 'transmissionvpn_vpn_connected'), '1')
    check("healthy is 1", series(text, 'transmissionvpn_healthy'), '1')
    age = int(series(text, 'transmissionvpn_vpn_tunnel_check_age_seconds'))
    check("probe age is reported", 0 <= age <= 2, True)

    print("A passing result that has gone stale is not trusted")
    write_state(state, 1, age=600)
    text = scrape(mod)
    check("vpn_connected is 0", series(text, 'transmissionvpn_vpn_connected'), '0')
    check("healthy is 0", series(text, 'transmissionvpn_healthy'), '0')
    check("stale flag set", mod.health_data['vpn']['tunnel_check']['stale'], True)

    print("The stale threshold follows VPN_CHECK_INTERVAL")
    mod = load(state, tun_up, VPN_CHECK_INTERVAL='300')
    write_state(state, 1, age=600)
    text = scrape(mod)
    check("600s is fresh with a 300s interval",
          series(text, 'transmissionvpn_vpn_connected'), '1')

    print("No result yet (vpn-monitor has not finished a check)")
    mod = load(state, tun_up)
    os.remove(state)
    text = scrape(mod)
    check("vpn_connected is 0", series(text, 'transmissionvpn_vpn_connected'), '0')
    check("probe age is -1",
          series(text, 'transmissionvpn_vpn_tunnel_check_age_seconds'), '-1')

    print("A passing probe cannot make a missing interface connected")
    mod = load(state, {'eth0': (True, '10.42.0.17')})
    write_state(state, 1)
    text = scrape(mod)
    check("vpn_connected is 0", series(text, 'transmissionvpn_vpn_connected'), '0')
    check("interface_up is 0", series(text, 'transmissionvpn_vpn_interface_up'), '0')

    print("Port-forward classification with the tunnel down")
    closed = dict(port_test=False, pf_state={'rules_present': 1})
    warnings, _ = mod.classify_port_state(vpn_connected=False, pf_enabled=True, **closed)
    check("does not blame the PIA binding for a dead tunnel", warnings, [])
    warnings, _ = mod.classify_port_state(vpn_connected=True, pf_enabled=True, **closed)
    check("still blames the binding when the tunnel works", warnings,
          ['pf_port_bound_but_unreachable'])
    warnings, _ = mod.classify_port_state(port_test=False, vpn_connected=False,
                                          pf_state={'rules_present': 0}, pf_enabled=True)
    check("missing rules are still reported with the tunnel down", warnings,
          ['pf_rules_missing'])
    warnings, notices = mod.classify_port_state(port_test=False, vpn_connected=False,
                                                pf_state={}, pf_enabled=False)
    check("closed port without PF and a dead tunnel is a warning, not a notice",
          (warnings, notices), (['port_not_open_no_vpn'], []))

    print()
    print(f"passed={_passed} failed={_failed}")
    return 1 if _failed else 0


if __name__ == '__main__':
    sys.exit(main())
