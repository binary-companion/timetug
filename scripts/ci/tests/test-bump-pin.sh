#!/usr/bin/env bash
# Tests scripts/ci/bump-pin.sh in throwaway trees. Needs PyYAML on PATH (check-shared-pins.py reads project.yml).
set -euo pipefail
cd "$(dirname "$0")/../../.."
ROOT="$PWD"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
S="$ROOT/scripts/ci/bump-pin.sh"
CHECK="$ROOT/scripts/ci/check-shared-pins.py"
URL=https://github.com/binary-companion/calendar-connectors

# A fixture mirrors the real tree: the library entry in project.yml exactly as in Apps/macOS/project.yml, a
# second package pinned the same way (Sparkle), a local package entry, and manifests that depend on the library
# by URL (Package.swift and a Package@swift-X.Y.swift variant, which SwiftPM prefers and the contract scans)
# next to local .package(path:) dependencies.
make_fixture() {
  local dir="$1"
  mkdir -p "$dir/Apps/macOS" "$dir/Packages/A" "$dir/Packages/B"
  printf 'packages:\n  Sparkle:\n    url: https://github.com/sparkle-project/Sparkle\n    exactVersion: 2.10.0\n  LocalB:\n    path: ../../Packages/B\n  CalendarConnectors:\n    url: %s\n    exactVersion: 1.0.0\n' "$URL" > "$dir/Apps/macOS/project.yml"
  printf 'let package = Package(dependencies: [.package(url: "%s", from: "1.0.0"), .package(path: "../B")])\n' "$URL" > "$dir/Packages/A/Package.swift"
  printf 'let package = Package(dependencies: [.package(url: "%s", from: "1.0.0"), .package(path: "../B")])\n' "$URL" > "$dir/Packages/A/Package@swift-6.0.swift"
  printf 'let package = Package(dependencies: [.package(url: "%s", from: "1.0.0")])\n' "$URL" > "$dir/Packages/B/Package.swift"
}
snapshot() { (cd "$1" && find Apps Packages -type f | LC_ALL=C sort | xargs cat | cksum); }

F="$T/same-major"
make_fixture "$F"
python3 "$CHECK" "$F" >/dev/null || fail "the fixture should start clean"

# Same-major bump: the pin moves, the floors stay (they are lower bounds the code is known to need).
"$S" 1.2.3 "$F" >/dev/null
grep -q '^    exactVersion: 1.2.3$' "$F/Apps/macOS/project.yml" || fail "project.yml not bumped"
grep -q '^    exactVersion: 2.10.0$' "$F/Apps/macOS/project.yml" || fail "another package's pin changed"
grep -q 'path: ../../Packages/B' "$F/Apps/macOS/project.yml" || fail "local package entry changed in project.yml"
for m in Packages/A/Package.swift Packages/A/Package@swift-6.0.swift Packages/B/Package.swift; do
  grep -q 'from: "1.0.0")' "$F/$m" || fail "$m: a same-major bump must leave the floor alone"
  if grep -q '1\.2\.3' "$F/$m"; then fail "$m: floor raised on a same-major bump"; fi
done
grep -q 'path: "../B"' "$F/Packages/A/Package.swift" || fail "local path dependency changed"
python3 "$CHECK" "$F" >/dev/null || fail "same-major result violates the pin contract"

# Same version again succeeds and changes nothing; anything else leaves the tree untouched.
before="$(snapshot "$F")"
"$S" 1.2.3 "$F" >/dev/null || fail "re-running the same version should succeed"
[ "$(snapshot "$F")" = "$before" ] || fail "re-running the same version changed files"
if "$S" 1.2.2 "$F" >/dev/null 2>&1; then fail "downgrade accepted"; fi
if "$S" 0.9.0 "$F" >/dev/null 2>&1; then fail "move back to another major accepted"; fi
if "$S" v1.3.0 "$F" >/dev/null 2>&1; then fail "v-prefixed version accepted"; fi
if "$S" "1.3.0; touch $T/pwned" "$F" >/dev/null 2>&1; then fail "shell metacharacters accepted"; fi
if "$S" "1.3.0\$(touch $T/pwned)" "$F" >/dev/null 2>&1; then fail "command substitution accepted"; fi
if "$S" "1.3.0
2.0.0" "$F" >/dev/null 2>&1; then fail "multi-line version accepted"; fi
if "$S" 1.3 "$F" >/dev/null 2>&1; then fail "two-part version accepted"; fi
if "$S" 1.3.0-beta "$F" >/dev/null 2>&1; then fail "pre-release version accepted"; fi
if "$S" 01.3.0 "$F" >/dev/null 2>&1; then fail "leading zero accepted"; fi
if "$S" "" "$F" >/dev/null 2>&1; then fail "empty version accepted"; fi
if "$S" >/dev/null 2>&1; then fail "missing version accepted"; fi
[ ! -e "$T/pwned" ] || fail "a version argument was executed"
[ "$(snapshot "$F")" = "$before" ] || fail "a rejected version changed files"

# A later minor bump compares numerically (1.10.0 is above 1.2.3) and still leaves the floors alone.
"$S" 1.10.0 "$F" >/dev/null
grep -q '^    exactVersion: 1.10.0$' "$F/Apps/macOS/project.yml" || fail "1.10.0 sorts below 1.2.3 (version order must be numeric)"
python3 "$CHECK" "$F" >/dev/null || fail "1.10.0 result violates the pin contract"

# Major bump: the floors would sit in another major than the pin, which the contract rejects, so they follow.
"$S" 2.0.0 "$F" >/dev/null
grep -q '^    exactVersion: 2.0.0$' "$F/Apps/macOS/project.yml" || fail "major bump not applied"
grep -q '^    exactVersion: 2.10.0$' "$F/Apps/macOS/project.yml" || fail "another package's pin changed on the major bump"
for m in Packages/A/Package.swift Packages/A/Package@swift-6.0.swift Packages/B/Package.swift; do
  grep -q 'from: "2.0.0")' "$F/$m" || fail "$m: floor not raised on a major bump"
done
grep -q 'path: "../B"' "$F/Packages/A/Package.swift" || fail "local path dependency changed on the major bump"
python3 "$CHECK" "$F" >/dev/null || fail "major-bump result violates the pin contract"

# A tree without the library pin is an error, and no manifest is touched.
N="$T/no-pin"
make_fixture "$N"
printf 'packages:\n  Sparkle:\n    url: https://github.com/sparkle-project/Sparkle\n    exactVersion: 2.10.0\n' > "$N/Apps/macOS/project.yml"
before="$(snapshot "$N")"
if "$S" 1.0.1 "$N" >/dev/null 2>&1; then fail "a tree without the library pin was accepted"; fi
[ "$(snapshot "$N")" = "$before" ] || fail "a tree without the library pin was modified"

echo PASS
