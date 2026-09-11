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

shellcheck --version | sed -n '2p'
echo "Checking $count shell scripts..."

# -x follows 'shellcheck source=' directives; without it, sourced files raise
# spurious SC1091. Severity is left at the default (style) on purpose.
list_scripts | tr '\n' '\0' | xargs -0 shellcheck -x

echo "ShellCheck: clean ($count scripts)."
