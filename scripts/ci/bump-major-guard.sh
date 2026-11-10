#!/usr/bin/env bash
# Decides whether a library release may be bumped in the Mac app.
#
#   scripts/ci/bump-major-guard.sh <calendar-connectors|timetug-shared> <X.Y.Z>     (run from the repository root)
#
# Prints `skip` when the new major version is greater than the major version pinned in Apps/macOS/project.yml
# (the Mac app adopts a new major only in phase 6 of the Rust program), otherwise `proceed`. Exits 2 with a
# message on stderr for a bad library or version. The argument rules and the pin lookup are the ones in
# bump-pin.sh (same key mapping, same X.Y.Z expression, same exactVersion-after-url match).
set -euo pipefail

usage() {
  echo "usage: bump-major-guard.sh <calendar-connectors|timetug-shared> X.Y.Z" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
library="$1"
version="$2"

case "$library" in
  calendar-connectors) KEY=CalendarConnectors ;;
  timetug-shared) KEY=TimeTugShared ;;
  *) echo "unknown library: $library" >&2; usage ;;
esac

SEMVER='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
URL="https://github.com/binary-companion/$library"
PROJECT=Apps/macOS/project.yml

if ! [[ "$version" =~ $SEMVER ]]; then
  echo "not X.Y.Z: $version" >&2
  exit 2
fi
[ -f "$PROJECT" ] || { echo "$PROJECT not found in $PWD" >&2; exit 2; }

export BUMP_KEY="$KEY" BUMP_URL="$URL"
current="$(perl -0ne 'print $1 if m{^[ \t]+\Q$ENV{BUMP_KEY}\E:[ \t]*\n[ \t]+url:[ \t]*\Q$ENV{BUMP_URL}\E[ \t]*\n[ \t]+exactVersion:[ \t]*([0-9.]+)[ \t]*$}m' "$PROJECT")"
if [ -z "$current" ]; then
  echo "$PROJECT has no $KEY pin with url $URL followed by exactVersion" >&2
  exit 2
fi
if ! [[ "$current" =~ $SEMVER ]]; then
  echo "current pin is not X.Y.Z: $current" >&2
  exit 2
fi

cur_major="${current%%.*}"
new_major="${version%%.*}"
if (( new_major > cur_major )); then echo skip; else echo proceed; fi
