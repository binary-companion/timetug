#!/usr/bin/env bash
# Moves the pin of one shared library (calendar-connectors or timetug-shared) to a released version.
#
#   scripts/ci/bump-pin.sh [--at-least] <calendar-connectors|timetug-shared> <X.Y.Z> [repo-root]
#
# Always sets exactVersion for that library's entry (CalendarConnectors, TimeTugShared) in
# Apps/macOS/project.yml; the other library's pin and floors are never touched. A `from:` floor of the library
# in a Packages/*/Package*.swift manifest is a lower bound the code is known to need, so it is raised only when
# the new version is in a different major than the floor (scripts/ci/check-shared-pins.py requires the floor to
# be at most the pin within one major); on a same-major bump the floors stay. Refuses anything that is not
# X.Y.Z (a v prefix, a pre-release, shell metacharacters) before touching a file, and refuses to go backwards.
# Re-running the version that is already pinned succeeds and changes nothing.
#
# --at-least turns "refuse to go backwards" into "do nothing": when the pin is already at or above the version
# the script exits 0 without changing a file, otherwise it raises the pin as usual. It never lowers a pin.
set -euo pipefail

usage() {
  echo "usage: bump-pin.sh [--at-least] <calendar-connectors|timetug-shared> X.Y.Z [repo-root]" >&2
  exit 2
}

at_least=0
if [ "${1-}" = "--at-least" ]; then at_least=1; shift; fi
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || usage
library="$1"
version="$2"

# The library's project.yml key; anything else is refused (a bare version lands here too).
case "$library" in
  calendar-connectors) KEY=CalendarConnectors ;;
  timetug-shared) KEY=TimeTugShared ;;
  *) echo "unknown library: $library" >&2; usage ;;
esac
cd "${3:-$(dirname "$0")/../..}"

SEMVER='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
URL="https://github.com/binary-companion/$library"
PROJECT=Apps/macOS/project.yml

if ! [[ "$version" =~ $SEMVER ]]; then
  echo "not X.Y.Z: $version" >&2
  exit 2
fi
[ -f "$PROJECT" ] || { echo "$PROJECT not found in $PWD" >&2; exit 2; }

# Both values reach perl through the environment, never through the program text. $KEY and $URL come from the
# table above, never from the arguments.
export BUMP_KEY="$KEY" BUMP_URL="$URL"

# The pin as it stands: the exactVersion that follows the library's url inside its entry.
current="$(perl -0ne 'print $1 if m{^[ \t]+\Q$ENV{BUMP_KEY}\E:[ \t]*\n[ \t]+url:[ \t]*\Q$ENV{BUMP_URL}\E[ \t]*\n[ \t]+exactVersion:[ \t]*([0-9.]+)[ \t]*$}m' "$PROJECT")"
if [ -z "$current" ]; then
  echo "$PROJECT has no $KEY pin with url $URL followed by exactVersion" >&2
  exit 2
fi
if ! [[ "$current" =~ $SEMVER ]]; then
  echo "current pin is not X.Y.Z: $current" >&2
  exit 2
fi

# Numeric comparison, field by field (1.10.0 is above 1.2.3; sort -V is not portable to every host).
IFS=. read -r cur_major cur_minor cur_patch <<<"$current"
IFS=. read -r new_major new_minor new_patch <<<"$version"
if   (( new_major != cur_major )); then older=$(( new_major < cur_major ))
elif (( new_minor != cur_minor )); then older=$(( new_minor < cur_minor ))
else older=$(( new_patch < cur_patch ))
fi
if (( older )); then
  if (( at_least )); then
    echo "$library already at $current (at least $version); nothing to do"
    exit 0
  fi
  echo "refusing to move the pin back from $current to $version" >&2
  exit 2
fi

export BUMP_VERSION="$version" BUMP_MAJOR="$new_major"
perl -0pi -e '
  s{(^[ \t]+\Q$ENV{BUMP_KEY}\E:[ \t]*\n[ \t]+url:[ \t]*\Q$ENV{BUMP_URL}\E[ \t]*\n[ \t]+exactVersion:[ \t]*)[0-9.]+}{$1$ENV{BUMP_VERSION}}m
' "$PROJECT"

shopt -s nullglob
for manifest in Packages/*/Package*.swift; do
  perl -0pi -e '
    s{(\.package\(\s*url:\s*"\Q$ENV{BUMP_URL}\E"\s*,\s*from:\s*")(\d+)(\.\d+\.\d+)(")}{
      $2 eq $ENV{BUMP_MAJOR} ? "$1$2$3$4" : "$1$ENV{BUMP_VERSION}$4"
    }ge
  ' "$manifest"
done

echo "$library pinned at $version (was $current)"
