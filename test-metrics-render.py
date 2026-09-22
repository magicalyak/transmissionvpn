#!/usr/bin/env python3
"""Tests for the Prometheus exposition produced by transmission-metrics-server.py.

The point of these is the deprecation contract. transmissionvpn_port_forwarding_available
and transmissionvpn_vpn_supports_port_forwarding were both found to report something
other than what their names promise. Rather than redefine them in place - which would
silently change what a live series means - they were deprecated in v4.1.2-r5, kept
emitting their original values, and their HELP text promised removal in the first
release built on a new upstream Transmission version. That release is this one, so
they are gone.

These tests now pin their absence. Reintroducing either name, under its old meaning or
a new one, should fail here: the whole argument for deprecating rather than redefining
was that the name is unsalvageable.

Run: python3 test-metrics-render.py
"""
import importlib.util
import os
import sys
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


def load():
    for mod in ('psutil', 'requests'):
        sys.modules.setdefault(mod, types.ModuleType(mod))
    spec = importlib.util.spec_from_file_location("metrics_render_under_test", SRC)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def render(mod, port_test, vpn_connected):
    """Render the exposition with a controlled health snapshot."""
    mod.health_data.clear()
    mod.health_data.update({
        'status': 'healthy',
        'vpn': {'status': 'up', 'connected': vpn_connected},
        'transmission': {'port_test': port_test},
        'port_forwarding': {'enabled': True, 'port': 46202,
                            'rules_present': 1, 'rules_found': 4},
    })
    return mod.generate_prometheus_metrics()


def series(text, name):
    """Return the value of a single sample, or None if the series is absent."""
    for line in text.splitlines():
        if line.startswith(name + ' '):
            return line.split(' ', 1)[1]
    return None


def helptext(text, name):
    for line in text.splitlines():
        if line.startswith(f"# HELP {name} "):
            return line.split(' ', 3)[3]
    return None


def main():
    mod = load()

    print("Exposition is well formed")
    out = render(mod, port_test=True, vpn_connected=True)
    text = out if isinstance(out, str) else "\n".join(out)
    check("no blank lines inside the exposition",
          any(l.strip() == '' for l in text.splitlines()), False)
    names = [l.split(' ')[2] for l in text.splitlines() if l.startswith('# TYPE ')]
    check("every TYPE is declared once", len(names), len(set(names)))
    bad = [l for l in text.splitlines()
           if not l.startswith('#') and l.strip() and len(l.split(' ')) != 2]
    check("every sample is 'name value'", bad, [])

    print("\nThe deprecated metrics are gone")
    for name in ('transmissionvpn_port_forwarding_available',
                 'transmissionvpn_vpn_supports_port_forwarding'):
        check(f"{name} emits no sample", series(text, name), None)
        check(f"{name} declares no HELP", helptext(text, name), None)
        check(f"{name} appears nowhere in the exposition", name in text, False)

    print("\nRemoval did not disturb the metrics that replaced them")
    check("port_open still tracks port_test when open",
          series(text, 'transmissionvpn_port_open'), '1')

    closed = render(mod, port_test=False, vpn_connected=True)
    closed = closed if isinstance(closed, str) else "\n".join(closed)
    check("port_open follows port_test to 0",
          series(closed, 'transmissionvpn_port_open'), '0')

    down = render(mod, port_test=True, vpn_connected=False)
    down = down if isinstance(down, str) else "\n".join(down)
    check("pf_enabled still reports the real capability with the tunnel down",
          series(down, 'transmissionvpn_pf_enabled'), '1')

    print("\nThe replacements say what they mean")
    check("pf_enabled reflects configuration", series(text, 'transmissionvpn_pf_enabled'), '1')
    check("pf_rules_present reflects the firewall",
          series(text, 'transmissionvpn_pf_rules_present'), '1')

    print("\n" + "=" * 48)
    if _failed:
        print(f"passed={_passed} failed={_failed}")
        return 1
    print(f"passed={_passed} failed={_failed}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
