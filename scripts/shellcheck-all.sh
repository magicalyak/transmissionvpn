#!/usr/bin/env bash
# Run ShellCheck across every shell script tracked in this repository.
#
# .github/workflows/shellcheck.yml runs exactly this script, so a local run and
# a CI run agree. The tree is clean at ShellCheck's default severity, so
# anything reported here is a regression rather than pre-existing debt.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "shellcheck not found. Install it with one of:" >&2
    echo "  brew install shellcheck" >&2
    echo "  pip install shellcheck-py" >&2
    exit 127
fi

# Tracked shell scripts: *.sh plus the extensionless s6 service scripts.
list_scripts() {
    git ls-files -- '*.sh' 'root_s6/*/run' 'root_s6/*/finish' | sort
}

count=$(list_scripts | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then
    echo "No shell scripts found - has the repository layout changed?" >&2
    exit 1
fi

# The findings are not stable across ShellCheck versions, so CI pins this one
# (see .github/workflows/shellcheck.yml). 0.9.0, which ships in the GitHub
# runner image, reports SC2002 - off by default from 0.10 on - and reports an
# indirectly-invoked function body as SC2317 where later versions use SC2329.
# A local run on a different version is still useful, but may not match CI.
EXPECTED_VERSION="0.11.0"
actual_version=$(shellcheck --version | awk '/^version:/ {print $2}')
if [ "$actual_version" != "$EXPECTED_VERSION" ]; then
    echo "Note: local ShellCheck is $actual_version; CI pins $EXPECTED_VERSION." >&2
    echo "      Findings may differ. Match CI with:" >&2
    echo "      pip install 'shellcheck-py==${EXPECTED_VERSION}.1'" >&2
fi

echo "ShellCheck $actual_version - checking $count shell scripts..."

# -x follows 'shellcheck source=' directives; without it, sourced files raise
# spurious SC1091. Severity is left at the default (style) on purpose.
list_scripts | tr '\n' '\0' | xargs -0 shellcheck -x

echo "ShellCheck: clean ($count scripts)."
