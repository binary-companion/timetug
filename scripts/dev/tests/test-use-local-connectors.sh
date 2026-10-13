#!/usr/bin/env bash
# Tests use-local-connectors.sh in a throwaway repo shaped like this one.
set -euo pipefail
cd "$(dirname "$0")/../../.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
g() { git -c user.name=t -c user.email=t@t "$@"; }
mkdir -p "$T/repo/scripts/dev" "$T/repo/scripts/ci" "$T/repo/Apps/macOS" "$T/calendar-connectors" "$T/other"
mkdir -p "$T/second/calendar-connectors"
touch "$T/calendar-connectors/Package.swift" "$T/other/Package.swift" "$T/second/calendar-connectors/Package.swift"
cp scripts/dev/use-local-connectors.sh "$T/repo/scripts/dev/"
cp scripts/ci/check-shared-pins.py "$T/repo/scripts/ci/"
cp Apps/macOS/project.yml "$T/repo/Apps/macOS/"
for m in Packages/*/Package.swift; do mkdir -p "$T/repo/$(dirname "$m")"; cp "$m" "$T/repo/$m"; done
cd "$T/repo"
git init -q -b master; g add -A; g commit -qm base
python3 scripts/ci/check-shared-pins.py >/dev/null || fail "fixture should start clean"

BACKUP=build/local-connectors-backup
USE=scripts/dev/use-local-connectors.sh
MANIFEST=Packages/TimeTugCore/Package.swift
PROJECT=Apps/macOS/project.yml
# Everything the override may touch, plus its backup, as "checksum size path" lines.
snapshot() { find Packages Apps build -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do echo "$(cksum < "$f") $f"; done; }
# Runs a command, keeping its exit status in $rc and its output in $out.
capture() { rc=0; out="$("$@" 2>&1)" || rc=$?; }
# The project file without the CalendarConnectors entry (its key line and the lines indented below it).
without_entry() { perl -0pe 's/^([ \t]*)CalendarConnectors:\n(?:\1[ \t]+[^\n]*\n)*//m'; }

# --- Override and restore on a clean tree
$USE "$T/calendar-connectors" >/dev/null
grep -q "path: \"$T/calendar-connectors\"" $MANIFEST || fail "manifest not redirected"
grep -Eq 'path: .*calendar-connectors$' $PROJECT || fail "project.yml not redirected"
[ -f $BACKUP/after.sha256 ] || fail "the override recorded no hashes"
# Only the CalendarConnectors entry may differ from the committed project file (other packages keep their pins).
git show HEAD:$PROJECT | grep -q 'CalendarConnectors:' || fail "fixture has no CalendarConnectors entry"
[ "$(git show HEAD:$PROJECT | without_entry)" = "$(without_entry < $PROJECT)" ] || fail "lines outside the CalendarConnectors entry changed"
if python3 scripts/ci/check-shared-pins.py >/dev/null 2>&1; then fail "the contract accepted a local override"; fi
$USE --restore >/dev/null
[ -z "$(git status --porcelain)" ] || fail "restore left changes: $(git status --porcelain)"
[ ! -e $BACKUP ] || fail "restore left the backup"
python3 scripts/ci/check-shared-pins.py >/dev/null || fail "restored tree should pass"
capture $USE --restore; [ "$rc" = 2 ] || fail "restore without an override should exit 2 (got $rc)"
capture $USE "$T/missing"; [ "$rc" = 2 ] || fail "accepted a missing checkout"
capture $USE "$T/other"; [ "$rc" = 2 ] || fail "accepted a checkout not named calendar-connectors"
[ -z "$(git status --porcelain)" ] || fail "a refused call changed files"
[ ! -e $BACKUP ] || fail "a refused call left a backup"

# --- Uncommitted edits made BEFORE the override survive --restore byte for byte
echo '// uncommitted note' >> $MANIFEST
echo '# uncommitted note' >> $PROJECT
cp $MANIFEST "$T/manifest.before"; cp $PROJECT "$T/project.before"
$USE "$T/calendar-connectors" >/dev/null
$USE --restore >/dev/null
cmp -s $MANIFEST "$T/manifest.before" || fail "restore lost an uncommitted manifest edit"
cmp -s $PROJECT "$T/project.before" || fail "restore lost an uncommitted project.yml edit"
[ "$(git status --porcelain | wc -l | tr -d ' ')" = 2 ] || fail "restore changed other files: $(git status --porcelain)"
git checkout -q -- Packages Apps

# --- A second override while one is in place is refused and changes nothing
$USE "$T/calendar-connectors" >/dev/null
snapshot > "$T/snapshot.before"
capture $USE "$T/second/calendar-connectors"
[ "$rc" = 2 ] || fail "second override should exit 2 (got $rc)"
case "$out" in *"--restore"*) ;; *) fail "second override did not say to run --restore: $out" ;; esac
capture $USE "$T/calendar-connectors"; [ "$rc" = 2 ] || fail "second override of the same checkout should exit 2 (got $rc)"
snapshot > "$T/snapshot.after"
cmp -s "$T/snapshot.before" "$T/snapshot.after" || fail "a refused second override changed the tree or the backup"
$USE --restore >/dev/null
[ -z "$(git status --porcelain)" ] || fail "restore after a refused second override left changes"

# --- An edit made DURING the override makes --restore refuse; --force restores the backup
$USE "$T/calendar-connectors" >/dev/null
echo '# edited during the override' >> $PROJECT
snapshot > "$T/snapshot.before"
capture $USE --restore
[ "$rc" = 2 ] || fail "restore over a changed file should exit 2 (got $rc)"
case "$out" in *"$PROJECT"*) ;; *) fail "restore did not name the changed file: $out" ;; esac
case "$out" in *"--force"*) ;; *) fail "restore did not mention --force: $out" ;; esac
snapshot > "$T/snapshot.after"
cmp -s "$T/snapshot.before" "$T/snapshot.after" || fail "a refused restore changed the tree or the backup"
$USE --restore --force >/dev/null
[ -z "$(git status --porcelain)" ] || fail "restore --force left changes: $(git status --porcelain)"
[ ! -e $BACKUP ] || fail "restore --force left the backup"
python3 scripts/ci/check-shared-pins.py >/dev/null || fail "force-restored tree should pass"

# --- A backup left by an override that did not finish (no hashes) needs --force too
$USE "$T/calendar-connectors" >/dev/null
rm $BACKUP/after.sha256
capture $USE --restore; [ "$rc" = 2 ] || fail "restore without hashes should exit 2 (got $rc)"
$USE --restore --force >/dev/null
[ -z "$(git status --porcelain)" ] || fail "restore --force without hashes left changes"
echo PASS
