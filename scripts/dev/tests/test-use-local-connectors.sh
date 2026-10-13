#!/usr/bin/env bash
# Tests use-local-connectors.sh in a throwaway repo shaped like this one.
set -euo pipefail
cd "$(dirname "$0")/../../.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
g() { git -c user.name=t -c user.email=t@t "$@"; }
mkdir -p "$T/repo/scripts/dev" "$T/repo/scripts/ci" "$T/repo/Apps/macOS" "$T/calendar-connectors" "$T/other"
touch "$T/calendar-connectors/Package.swift" "$T/other/Package.swift"
cp scripts/dev/use-local-connectors.sh "$T/repo/scripts/dev/"
cp scripts/ci/check-shared-pins.py "$T/repo/scripts/ci/"
cp Apps/macOS/project.yml "$T/repo/Apps/macOS/"
for m in Packages/*/Package.swift; do mkdir -p "$T/repo/$(dirname "$m")"; cp "$m" "$T/repo/$m"; done
cd "$T/repo"
git init -q -b master; g add -A; g commit -qm base
python3 scripts/ci/check-shared-pins.py >/dev/null || fail "fixture should start clean"

scripts/dev/use-local-connectors.sh "$T/calendar-connectors" >/dev/null
grep -q "path: \"$T/calendar-connectors\"" Packages/TimeTugCore/Package.swift || fail "manifest not redirected"
grep -Eq 'path: .*calendar-connectors$' Apps/macOS/project.yml || fail "project.yml not redirected"
grep -q 'exactVersion: 2.10.0' Apps/macOS/project.yml || fail "another package's pin changed"
if python3 scripts/ci/check-shared-pins.py >/dev/null 2>&1; then fail "the contract accepted a local override"; fi

# An unrelated edit made while the override is in place is not what --restore brings back.
scripts/dev/use-local-connectors.sh --restore >/dev/null
[ -z "$(git status --porcelain)" ] || fail "restore left changes: $(git status --porcelain)"
python3 scripts/ci/check-shared-pins.py >/dev/null || fail "restored tree should pass"
if scripts/dev/use-local-connectors.sh --restore >/dev/null 2>&1; then fail "restore without an override succeeded"; fi
if scripts/dev/use-local-connectors.sh "$T/missing" >/dev/null 2>&1; then fail "accepted a missing checkout"; fi
if scripts/dev/use-local-connectors.sh "$T/other" >/dev/null 2>&1; then fail "accepted a checkout not named calendar-connectors"; fi
[ -z "$(git status --porcelain)" ] || fail "a refused call changed files"
echo PASS
