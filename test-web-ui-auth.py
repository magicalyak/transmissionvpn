#!/usr/bin/env python3
"""Tests for the credentials the metrics server sends to Transmission.

With rpc-authentication-required on, Transmission answers 401 to an anonymous request
for the web UI as well as the RPC. The web UI check used a bare requests.get, so a
container with auth enabled reported web_ui_accessible=False and status=unhealthy
while the daemon, the RPC and the tunnel were all fine.

These pin that the web UI check sends the same credentials as the RPC session, and
where those credentials come from: TRANSMISSION_RPC_USERNAME/PASSWORD first, then the
base image's USER/PASS, and never USER on its own.

Run: python3 test-web-ui-auth.py
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


class FakeResponse:
    def __init__(self, status_code):
        self.status_code = status_code
        self.headers = {}

    def json(self):
        return {}


def fake_requests(calls):
    """A requests stand-in whose get() is 200 only when credentials are sent."""
    mod = types.ModuleType('requests')

    def get(url, **kwargs):
        calls.append(kwargs)
        return FakeResponse(200 if kwargs.get('auth') else 401)

    class Session:
        def __init__(self):
            self.auth = None
            self.headers = {}

        def post(self, *a, **k):
            return FakeResponse(401)

    mod.get = get
    mod.Session = Session
    return mod


def load(env):
    """Import the metrics server with a controlled environment."""
    keys = ('TRANSMISSION_RPC_USERNAME', 'TRANSMISSION_RPC_PASSWORD', 'USER', 'PASS')
    saved = {k: os.environ.get(k) for k in keys}
    for k in keys:
        os.environ.pop(k, None)
    os.environ.update(env)
    calls = []
    sys.modules['requests'] = fake_requests(calls)
    sys.modules.setdefault('psutil', types.ModuleType('psutil'))
    try:
        spec = importlib.util.spec_from_file_location("metrics_auth_under_test", SRC)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    return module, calls


def main():
    print("credential sources")
    mod, _ = load({'TRANSMISSION_RPC_USERNAME': 'tom', 'TRANSMISSION_RPC_PASSWORD': 'pw'})
    check("TRANSMISSION_RPC_* used", mod.rpc_auth(), ('tom', 'pw'))
    mod, _ = load({'USER': 'tom', 'PASS': 'pw'})
    check("falls back to USER/PASS", mod.rpc_auth(), ('tom', 'pw'))
    mod, _ = load({'USER': 'root'})
    check("USER alone is not a credential", mod.rpc_auth(), None)
    mod, _ = load({'TRANSMISSION_RPC_USERNAME': 'a', 'TRANSMISSION_RPC_PASSWORD': 'b',
                   'USER': 'c', 'PASS': 'd'})
    check("TRANSMISSION_RPC_* wins over USER/PASS", mod.rpc_auth(), ('a', 'b'))
    mod, _ = load({})
    check("no credentials -> None", mod.rpc_auth(), None)

    print("web UI check")
    mod, calls = load({'USER': 'tom', 'PASS': 'pw'})
    health = mod.get_transmission_health()
    check("web UI request carries auth", calls[0].get('auth') if calls else None, ('tom', 'pw'))
    check("authenticated web UI counts as accessible", health.get('web_ui_accessible'), True)
    mod, calls = load({})
    mod.get_transmission_health()
    check("no credentials -> anonymous request", calls[0].get('auth', 'missing') if calls else 'no call', None)

    print(f"\n{_passed} passed, {_failed} failed")
    return 1 if _failed else 0


if __name__ == '__main__':
    sys.exit(main())
