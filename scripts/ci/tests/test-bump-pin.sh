#!/usr/bin/env bash
# Tests scripts/ci/bump-pin.sh in throwaway trees. Needs PyYAML on PATH (check-shared-pins.py reads project.yml).
set -euo pipefail
cd "$(dirname "$0")/../../.."
ROOT="$PWD"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
S="$ROOT/scripts/ci/bump-pin.sh"
CHECK="$ROOT/scripts/ci/check-shared-pins.py"
ORG=https://github.com/binary-companion

# A fixture mirrors the real tree: both library entries in project.yml exactly as in Apps/macOS/project.yml, a
# third package pinned the same way (Sparkle), a local package entry, and manifests that depend on both
# libraries by URL (Package.swift and a Package@swift-X.Y.swift variant, which SwiftPM prefers and the contract
# scans) next to local .package(path:) dependencies. Both pins start at 1.0.0 and both floors at 1.0.0.
make_fixture() {
  local dir="$1" cc="$ORG/calendar-connectors" ts="$ORG/timetug-shared"
  mkdir -p "$dir/Apps/macOS" "$dir/Packages/A" "$dir/Packages/B"
  printf 'packages:\n  TimeTugShared:\n    url: %s\n    exactVersion: 1.0.0\n  Sparkle:\n    url: https://github.com/sparkle-project/Sparkle\n    exactVersion: 2.10.0\n  LocalB:\n    path: ../../Packages/B\n  CalendarConnectors:\n    url: %s\n    exactVersion: 1.0.0\n' "$ts" "$cc" > "$dir/Apps/macOS/project.yml"
  printf 'let package = Package(dependencies: [.package(url: "%s", from: "1.0.0"), .package(url: "%s", from: "1.0.0"), .package(path: "../B")])\n' "$cc" "$ts" > "$dir/Packages/A/Package.swift"
  printf 'let package = Package(dependencies: [.package(url: "%s", from: "1.0.0"), .package(url: "%s", from: "1.0.0"), .package(path: "../B")])\n' "$cc" "$ts" > "$dir/Packages/A/Package@swift-6.0.swift"
  printf 'let package = Package(dependencies: [.package(url: "%s", from: "1.0.0"), .package(url: "%s", from: "1.0.0")])\n' "$cc" "$ts" > "$dir/Packages/B/Package.swift"
}
snapshot() { (cd "$1" && find Apps Packages -type f | LC_ALL=C sort | xargs cat | cksum); }
# What a library's pin and floors look like in a tree, for asserting that the other library stayed put.
pin_of() { perl -0ne 'print $1 if m{^[ \t]+'"$2"':[ \t]*\n[ \t]+url:[^\n]*\n[ \t]+exactVersion:[ \t]*([0-9.]+)}m' "$1/Apps/macOS/project.yml"; }
floors_of() { grep -rho "$ORG/$2\", from: \"[0-9.]*\"" "$1/Packages" | LC_ALL=C sort | uniq -c | tr -s ' ' | tr '\n' ';'; }

# The whole phase 1 behaviour, once per library: $1 library slug, $2 its project.yml key, $3 the other slug and
# $4 the other key (whose pin and floors must never move).
exercise() {
  local lib="$1" key="$2" other="$3" otherkey="$4" F N
  F="$T/$lib-same-major"
  make_fixture "$F"
  python3 "$CHECK" "$F" >/dev/null || fail "$lib: the fixture should start clean"
  local other_pin other_floors
  other_pin="$(pin_of "$F" "$otherkey")"; other_floors="$(floors_of "$F" "$other")"
  [ -n "$other_pin" ] && [ -n "$other_floors" ] || fail "$lib: the fixture has no $other pin or floors"
  # Everything of the other library and the unrelated entries stays as it was after every bump of this one.
  other_unchanged() {
    [ "$(pin_of "$F" "$otherkey")" = "$other_pin" ] || fail "$lib $1: the $other pin changed"
    [ "$(floors_of "$F" "$other")" = "$other_floors" ] || fail "$lib $1: the $other floors changed"
    grep -q '^    exactVersion: 2.10.0$' "$F/Apps/macOS/project.yml" || fail "$lib $1: another package's pin changed"
    grep -q 'path: ../../Packages/B' "$F/Apps/macOS/project.yml" || fail "$lib $1: local package entry changed in project.yml"
    grep -q 'path: "../B"' "$F/Packages/A/Package.swift" || fail "$lib $1: local path dependency changed"
  }

  # Same-major bump: the pin moves, the floors stay (they are lower bounds the code is known to need).
  "$S" "$lib" 1.2.3 "$F" >/dev/null
  [ "$(pin_of "$F" "$key")" = 1.2.3 ] || fail "$lib: project.yml not bumped"
  for m in Packages/A/Package.swift Packages/A/Package@swift-6.0.swift Packages/B/Package.swift; do
    grep -q "$ORG/$lib\", from: \"1.0.0\")" "$F/$m" || fail "$lib $m: a same-major bump must leave the floor alone"
    if grep -q '1\.2\.3' "$F/$m"; then fail "$lib $m: floor raised on a same-major bump"; fi
  done
  other_unchanged "same-major bump"
  python3 "$CHECK" "$F" >/dev/null || fail "$lib: same-major result violates the pin contract"

  # Same version again succeeds and changes nothing; anything else leaves the tree untouched.
  local before
  before="$(snapshot "$F")"
  "$S" "$lib" 1.2.3 "$F" >/dev/null || fail "$lib: re-running the same version should succeed"
  [ "$(snapshot "$F")" = "$before" ] || fail "$lib: re-running the same version changed files"
  if "$S" "$lib" 1.2.2 "$F" >/dev/null 2>&1; then fail "$lib: downgrade accepted"; fi
  if "$S" "$lib" 0.9.0 "$F" >/dev/null 2>&1; then fail "$lib: move back to another major accepted"; fi
  if "$S" "$lib" v1.3.0 "$F" >/dev/null 2>&1; then fail "$lib: v-prefixed version accepted"; fi
  if "$S" "$lib" "1.3.0; touch $T/pwned" "$F" >/dev/null 2>&1; then fail "$lib: shell metacharacters accepted"; fi
  if "$S" "$lib" "1.3.0\$(touch $T/pwned)" "$F" >/dev/null 2>&1; then fail "$lib: command substitution accepted"; fi
  if "$S" "$lib" "1.3.0
2.0.0" "$F" >/dev/null 2>&1; then fail "$lib: multi-line version accepted"; fi
  if "$S" "$lib" 1.3 "$F" >/dev/null 2>&1; then fail "$lib: two-part version accepted"; fi
  if "$S" "$lib" 1.3.0-beta "$F" >/dev/null 2>&1; then fail "$lib: pre-release version accepted"; fi
  if "$S" "$lib" 01.3.0 "$F" >/dev/null 2>&1; then fail "$lib: leading zero accepted"; fi
  if "$S" "$lib" "" "$F" >/dev/null 2>&1; then fail "$lib: empty version accepted"; fi
  if "$S" "$lib" >/dev/null 2>&1; then fail "$lib: missing version accepted"; fi
  [ ! -e "$T/pwned" ] || fail "$lib: a version argument was executed"
  [ "$(snapshot "$F")" = "$before" ] || fail "$lib: a rejected version changed files"

  # --at-least: never lowers, exits 0 and changes nothing when the pin is already there, raises otherwise.
  "$S" --at-least "$lib" 1.0.0 "$F" >/dev/null || fail "$lib: --at-least below the pin should exit 0"
  "$S" --at-least "$lib" 1.2.3 "$F" >/dev/null || fail "$lib: --at-least at the pin should exit 0"
  "$S" --at-least "$lib" 0.5.0 "$F" >/dev/null || fail "$lib: --at-least in an older major should exit 0"
  [ "$(snapshot "$F")" = "$before" ] || fail "$lib: --at-least with a lower version changed files"
  "$S" --at-least "$lib" 1.2.5 "$F" >/dev/null || fail "$lib: --at-least above the pin should succeed"
  [ "$(pin_of "$F" "$key")" = 1.2.5 ] || fail "$lib: --at-least did not raise the pin"
  other_unchanged "--at-least raise"
  python3 "$CHECK" "$F" >/dev/null || fail "$lib: --at-least result violates the pin contract"
  before="$(snapshot "$F")"
  if "$S" "$lib" 1.2.4 "$F" >/dev/null 2>&1; then fail "$lib: plain bump below the pin accepted after --at-least"; fi
  [ "$(snapshot "$F")" = "$before" ] || fail "$lib: a refused downgrade changed files"

  # A later minor bump compares numerically (1.10.0 is above 1.2.5) and still leaves the floors alone.
  "$S" "$lib" 1.10.0 "$F" >/dev/null
  [ "$(pin_of "$F" "$key")" = 1.10.0 ] || fail "$lib: 1.10.0 sorts below 1.2.5 (version order must be numeric)"
  "$S" --at-least "$lib" 1.9.0 "$F" >/dev/null
  [ "$(pin_of "$F" "$key")" = 1.10.0 ] || fail "$lib: --at-least 1.9.0 lowered 1.10.0 (version order must be numeric)"
  python3 "$CHECK" "$F" >/dev/null || fail "$lib: 1.10.0 result violates the pin contract"
  other_unchanged "1.10.0 bump"

  # Major bump: this library's floors would sit in another major than its pin, which the contract rejects, so
  # they follow; the other library's floors are in a major of their own pin and stay.
  "$S" "$lib" 2.0.0 "$F" >/dev/null
  [ "$(pin_of "$F" "$key")" = 2.0.0 ] || fail "$lib: major bump not applied"
  for m in Packages/A/Package.swift Packages/A/Package@swift-6.0.swift Packages/B/Package.swift; do
    grep -q "$ORG/$lib\", from: \"2.0.0\")" "$F/$m" || fail "$lib $m: floor not raised on a major bump"
  done
  other_unchanged "major bump"
  python3 "$CHECK" "$F" >/dev/null || fail "$lib: major-bump result violates the pin contract"

  # A tree without this library's pin is an error, and no manifest is touched.
  N="$T/$lib-no-pin"
  make_fixture "$N"
  perl -0pi -e 's/^  '"$key"':\n(?:    [^\n]*\n)+//m' "$N/Apps/macOS/project.yml"
  if grep -q "$key:" "$N/Apps/macOS/project.yml"; then fail "$lib: fixture still has the pin"; fi
  before="$(snapshot "$N")"
  if "$S" "$lib" 1.0.1 "$N" >/dev/null 2>&1; then fail "$lib: a tree without the library pin was accepted"; fi
  if "$S" --at-least "$lib" 1.0.1 "$N" >/dev/null 2>&1; then fail "$lib: --at-least on a tree without the pin was accepted"; fi
  [ "$(snapshot "$N")" = "$before" ] || fail "$lib: a tree without the library pin was modified"
}

exercise calendar-connectors CalendarConnectors timetug-shared TimeTugShared
exercise timetug-shared TimeTugShared calendar-connectors CalendarConnectors

# The message says which library moved and from where.
M="$T/message"
make_fixture "$M"
out="$("$S" timetug-shared 1.2.3 "$M")"
[ "$out" = "timetug-shared pinned at 1.2.3 (was 1.0.0)" ] || fail "unexpected message: $out"

# One command line moves one library: the other's pin stays at its own number (they are independent versions).
M2="$T/independent"
make_fixture "$M2"
"$S" calendar-connectors 1.0.4 "$M2" >/dev/null
"$S" timetug-shared 1.0.1 "$M2" >/dev/null
[ "$(pin_of "$M2" CalendarConnectors)" = 1.0.4 ] || fail "calendar-connectors pin wrong after both bumps"
[ "$(pin_of "$M2" TimeTugShared)" = 1.0.1 ] || fail "timetug-shared pin wrong after both bumps"
python3 "$CHECK" "$M2" >/dev/null || fail "two independent bumps violate the pin contract"

# Calls that do not name a library, or name an unknown one, are refused with a usage message and touch nothing.
U="$T/usage"
make_fixture "$U"
# A pin whose url merely looks like a library's: an unknown library name must never be looked up as a key.
printf '  imposter:\n    url: %s/imposter\n    exactVersion: 1.0.0\n' "$ORG" >> "$U/Apps/macOS/project.yml"
before="$(snapshot "$U")"
rc=0; out="$("$S" 1.0.1 "$U" 2>&1)" || rc=$?
[ "$rc" = 2 ] || fail "a bare version should exit 2 (got $rc)"
case "$out" in *usage*) ;; *) fail "a bare version did not print a usage message: $out" ;; esac
rc=0; out="$("$S" 1.0.1 2>&1)" || rc=$?
[ "$rc" = 2 ] || fail "a bare version without a root should exit 2 (got $rc)"
rc=0; out="$("$S" --at-least 1.0.1 "$U" 2>&1)" || rc=$?
[ "$rc" = 2 ] || fail "--at-least with a bare version should exit 2 (got $rc)"
case "$out" in *usage*) ;; *) fail "--at-least with a bare version did not print a usage message: $out" ;; esac
for bad in unknown-library imposter Timetug-Shared TimeTugShared CalendarConnectors calendar-connectors/ ../timetug-shared; do
  rc=0; out="$("$S" "$bad" 1.0.1 "$U" 2>&1)" || rc=$?
  [ "$rc" = 2 ] || fail "library '$bad' should exit 2 (got $rc)"
  case "$out" in *"unknown library"*usage*) ;; *) fail "library '$bad' was not reported as unknown: $out" ;; esac
  rc=0; out="$("$S" --at-least "$bad" 1.0.1 "$U" 2>&1)" || rc=$?
  [ "$rc" = 2 ] || fail "--at-least library '$bad' should exit 2 (got $rc)"
  case "$out" in *"unknown library"*usage*) ;; *) fail "--at-least library '$bad' was not reported as unknown: $out" ;; esac
done
rc=0; "$S" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "no arguments should exit 2 (got $rc)"
rc=0; "$S" --at-least >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "--at-least alone should exit 2 (got $rc)"
rc=0; out="$("$S" --bogus calendar-connectors 1.0.1 "$U" 2>&1)" || rc=$?
[ "$rc" = 2 ] || fail "an unknown option should exit 2 (got $rc)"
[ "$(snapshot "$U")" = "$before" ] || fail "a refused call changed files"

echo PASS
