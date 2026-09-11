#!/usr/bin/env bash
# Cut a release tag for transmissionvpn.
#
#   scripts/release.sh v4.1.2-r9                 # opens $EDITOR for the message
#   scripts/release.sh v4.1.2-r9 -F notes.txt    # takes the message from a file
#
# This creates the annotated tag and stops. It deliberately does not push.
# Pushing a v* tag builds and publishes `latest` and `stable`, and Flux image
# automation rolls the result out to a live cluster, so that step stays a
# separate, deliberate command that a human types.
#
# It also never commits anything. Cut the release commit yourself first; a
# release script that runs `git add .` is how unrelated work ends up in a
# release.
set -euo pipefail

cd "$(dirname "$0")/.."

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

die() { echo -e "${RED}✖ $1${NC}" >&2; exit 1; }
note() { echo -e "${BLUE}$1${NC}"; }
ok() { echo -e "${GREEN}✔ $1${NC}"; }

usage() {
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-2}"
}

VERSION=""
MESSAGE_FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        -F|--file) MESSAGE_FILE="${2:-}"; shift 2 || die "-F needs a file" ;;
        -h|--help) usage 0 ;;
        -*) die "Unknown option: $1" ;;
        *) [ -z "$VERSION" ] || die "Unexpected argument: $1"; VERSION="$1"; shift ;;
    esac
done

[ -n "$VERSION" ] || usage 2

# Must match what .github/workflows/build-and-publish.yml triggers on, and what
# validate-tagging.yml expects: v4.1.2-r8, or v4.1.14 for a release without a
# build suffix.
if ! printf '%s' "$VERSION" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-r[0-9]+)?$'; then
    die "Version '$VERSION' is not vMAJOR.MINOR.PATCH[-rN], e.g. v4.1.2-r9"
fi

branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = "main" ] || die "On branch '$branch'. Releases are cut from main."

[ -z "$(git status --porcelain)" ] || {
    git status --short
    die "Working tree is not clean. Commit or stash first."
}

git tag -l | grep -qx "$VERSION" && die "Tag $VERSION already exists locally."

note "Fetching tags from origin..."
git fetch --quiet --tags origin
git tag -l | grep -qx "$VERSION" && die "Tag $VERSION already exists on origin."

if ! git diff --quiet HEAD origin/main 2>/dev/null; then
    die "main differs from origin/main. Push or pull first so the tag points at what CI will build."
fi

ok "Prerequisites passed"

SUBJECT="Release $VERSION: "
if [ -n "$MESSAGE_FILE" ]; then
    [ -f "$MESSAGE_FILE" ] || die "No such file: $MESSAGE_FILE"
    head -1 "$MESSAGE_FILE" | grep -q "^Release $VERSION: " \
        || die "First line of $MESSAGE_FILE must start with '$SUBJECT'"
    git tag -a "$VERSION" -F "$MESSAGE_FILE"
else
    # Seed the editor with the convention every recent release follows: a
    # subject line naming the version and what changed, then prose.
    template=$(mktemp)
    trap 'rm -f "$template"' EXIT
    cat > "$template" <<EOF
$SUBJECT

EOF
    cat >> "$template" <<'EOF'
# Write the release notes above.
#
# Line 1 is the subject: "Release <version>: what changed", lower case after
# the colon. Leave line 2 blank. Then explain what was wrong and what the
# change does about it - see: git tag -l --format='%(contents)' v4.1.2-r8
#
# Lines starting with # are ignored. An empty message aborts the release.
EOF
    "${EDITOR:-vi}" "$template"
    grep -v '^#' "$template" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$template.clean"
    [ -s "$template.clean" ] || die "Empty message, aborting."
    head -1 "$template.clean" | grep -q "^Release $VERSION: ." \
        || die "First line must be '$SUBJECT<summary>'"
    git tag -a "$VERSION" -F "$template.clean"
    rm -f "$template.clean"
fi

ok "Created annotated tag $VERSION"
echo
git tag -l --format='%(contents)' "$VERSION" | head -20
echo
echo -e "${YELLOW}Not pushed.${NC} Pushing this tag publishes latest/stable and rolls it to the cluster."
echo -e "When you are ready:"
echo -e "    ${BLUE}git push origin $VERSION${NC}"
echo
echo -e "To undo before pushing:"
echo -e "    ${BLUE}git tag -d $VERSION${NC}"
