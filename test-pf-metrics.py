#!/usr/bin/env python3
"""Tests for the forwarded-port observability in transmission-metrics-server.py.

These cover the failure mode fixed in v4.1.2-r4 and instrumented in r5: the PIA
forwarded port was firewalled off by the container's own kill switch, port-test
returned false for seven days, and the service reported healthy the entire time
because a closed port was classified as expected whenever the VPN was connected.

Run: python3 test-pf-metrics.py
"""
import importlib.util
import os
import sys
import tempfile
import time
import types

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


def load(**env):
    """Import the metrics server with a given environment.

    psutil and requests are stubbed: this exercises pure classification logic
    and never talks to Transmission.
    """
    for key in ('PIA_PORT_FORWARD', 'PF_STATE_FILE', 'PORT_TEST_INTERVAL'):
        os.environ.pop(key, None)
    os.environ.update(env)
    for mod in ('psutil', 'requests'):
        sys.modules.setdefault(mod, types.ModuleType(mod))
    spec = importlib.util.spec_from_file_location("metrics_server", SRC)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def classify(mod, port_test, vpn_connected, pf_state):
    """Call the classifier the metrics server actually uses, not a copy of it."""
    warnings, notices = mod.classify_port_state(
        port_test=port_test, vpn_connected=vpn_connected,
        pf_state=pf_state, pf_enabled=mod.PIA_PORT_FORWARD)
    status = 'degraded' if warnings else 'healthy'
    return status, warnings, notices


def main():
    state_path = os.path.join(tempfile.gettempdir(), 'pf_state_under_test')

    print("Reading the state file published by pia-pf-firewall.sh")
    mod = load(PIA_PORT_FORWARD='true', PF_STATE_FILE=state_path)
    with open(state_path, 'w') as fh:
        fh.write("port=46202\nrules_found=4\nrules_expected=4\n"
                 "rules_present=1\nupdated=1788896812\n")
    check("parses the published port", mod.read_pf_state().get('port'), 46202)
    check("parses rule state", mod.read_pf_state().get('rules_present'), 1)
    os.remove(state_path)
    check("absent file is not an error", mod.read_pf_state(), {})
    with open(state_path, 'w') as fh:
        fh.write("port=46202\nnot-a-pair\nrules_present=notanint\n")
    check("malformed lines are ignored", mod.read_pf_state(), {'port': 46202})
    os.remove(state_path)

    print("\nThe seven-day fault: PF on, VPN up, rules wiped, port closed")
    mod = load(PIA_PORT_FORWARD='true', PF_STATE_FILE=state_path)
    status, warnings, notices = classify(mod, False, True, {'rules_present': 0})
    check("reports degraded rather than healthy", status, 'degraded')
    check("names our own firewall as the cause", warnings, ['pf_rules_missing'])
    check("no longer filed as an expected notice", notices, [])

    print("\nNo port forwarding configured: previous leniency is preserved")
    mod = load(PIA_PORT_FORWARD='false', PF_STATE_FILE=state_path)
    status, warnings, notices = classify(mod, False, True, {})
    check("stays healthy with the VPN up", status, 'healthy')
    check("still an informational notice", notices, ['port_not_open_vpn_expected'])
    _status, warnings, _notices = classify(mod, False, False, {})
    check("still warns when the VPN is down", warnings, ['port_not_open_no_vpn'])

    print("\nPF on, our rules correct, port unreachable upstream")
    mod = load(PIA_PORT_FORWARD='true', PF_STATE_FILE=state_path)
    _status, warnings, _notices = classify(mod, False, True, {'rules_present': 1})
    check("blames upstream, not our firewall", warnings,
          ['pf_port_bound_but_unreachable'])

    print("\nHealthy port forwarding")
    status, warnings, _notices = classify(mod, True, True, {'rules_present': 1})
    check("no warnings", warnings, [])
    check("healthy", status, 'healthy')

    print("\nport-test is throttled (it hits an external checker)")
    mod = load(PIA_PORT_FORWARD='true', PF_STATE_FILE=state_path,
               PORT_TEST_INTERVAL='900')
    calls = {'n': 0}

    class FakeAPI:
        def _make_request(self, method):
            calls['n'] += 1
            return {'result': 'success', 'arguments': {'port-is-open': True}}

    api = FakeAPI()
    for _ in range(30):
        mod.get_port_test(api)
    check("30 metric polls cause 1 external probe", calls['n'], 1)
    mod._port_test_cache['checked_at'] = time.time() - 901
    mod.get_port_test(api)
    check("re-probes once the interval elapses", calls['n'], 2)

    print("\na negative result must not stick for the full interval")
    # Regression: the metrics server probes during startup, before
    # pia-port-forward.sh has set Transmission's peer port. Caching that
    # transient 'closed' for 900s reported a healthy port as degraded for
    # 15 minutes.
    mod = load(PIA_PORT_FORWARD='true', PF_STATE_FILE=state_path,
               PORT_TEST_INTERVAL='900', PORT_TEST_RETRY_INTERVAL='60')
    calls = {'n': 0, 'open': False}

    class FlakyAPI:
        def _make_request(self, method):
            calls['n'] += 1
            return {'result': 'success',
                    'arguments': {'port-is-open': calls['open']}}

    api = FlakyAPI()
    check("first probe reports closed", mod.get_port_test(api), False)
    check("closed result is cached briefly", mod.get_port_test(api), False)
    check("no extra probe inside the retry window", calls['n'], 1)

    # The port comes good, and 61s later the cache must notice.
    calls['open'] = True
    mod._port_test_cache['checked_at'] = time.time() - 61
    check("re-probes a failure after the retry interval",
          mod.get_port_test(api), True)

    # A success must NOT be re-probed on the short retry interval.
    calls['n'] = 0
    mod._port_test_cache['checked_at'] = time.time() - 61
    mod.get_port_test(api)
    check("a success is held for the full interval", calls['n'], 0)

    print("\nretry interval never exceeds the main interval")
    mod = load(PIA_PORT_FORWARD='true', PF_STATE_FILE=state_path,
               PORT_TEST_INTERVAL='30', PORT_TEST_RETRY_INTERVAL='600')
    calls = {'n': 0, 'open': False}
    api = FlakyAPI()
    mod.get_port_test(api)
    mod._port_test_cache['checked_at'] = time.time() - 31
    mod.get_port_test(api)
    check("clamped to PORT_TEST_INTERVAL when smaller", calls['n'], 2)

    print(f"\npassed={_passed} failed={_failed}")
    return 1 if _failed else 0


if __name__ == '__main__':
    sys.exit(main())
