#!/usr/bin/env bash
# Tests scripts/ci/bump-major-guard.sh in a throwaway tree whose project.yml pins TimeTugShared at 1.8.0 and
# CalendarConnectors at 1.2.0. The guard prints proceed or skip (exit 0), or exits 2 for a bad argument.
set -euo pipefail
cd "$(dirname "$0")/../../.."
G="$PWD/scripts/ci/bump-major-guard.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ORG=https://github.com/binary-companion
mkdir -p "$T/Apps/macOS"
printf 'packages:\n  TimeTugShared:\n    url: %s/timetug-shared\n    exactVersion: 1.8.0\n  CalendarConnectors:\n    url: %s/calendar-connectors\n    exactVersion: 1.2.0\n' "$ORG" "$ORG" > "$T/Apps/macOS/project.yml"

expect_out() { # library version expected-output
  local out
  out="$(cd "$T" && bash "$G" "$1" "$2")" || fail "$1 $2: exited non-zero"
  [ "$out" = "$3" ] || fail "$1 $2: expected '$3', got '$out'"
  echo "ok: $1 $2 -> $3"
}
expect_exit2() { # library version
  local status=0
  (cd "$T" && bash "$G" "$1" "$2") >/dev/null 2>"$T/err" || status=$?
  [ "$status" = 2 ] || fail "$1 $2: expected exit 2, got $status"
  [ -s "$T/err" ] || fail "$1 $2: expected a message on stderr"
  echo "ok: $1 $2 -> exit 2"
}

expect_out timetug-shared 1.8.1 proceed
expect_out timetug-shared 1.9.0 proceed
expect_out timetug-shared 2.0.0 skip
expect_out calendar-connectors 2.0.0 skip
expect_out calendar-connectors 1.3.0 proceed
expect_exit2 timetug-shared 2.0.0-alpha.1
expect_exit2 other-lib 1.0.0
echo "PASS: test-bump-major-guard (7 cases)"
