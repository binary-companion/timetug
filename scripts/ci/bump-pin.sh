#!/usr/bin/env bash
# Moves the calendar-connectors pin to a released version.
#
#   scripts/ci/bump-pin.sh <X.Y.Z> [repo-root]
#
# Always sets exactVersion for the library in Apps/macOS/project.yml. A `from:` floor in a
# Packages/*/Package*.swift manifest is a lower bound the code is known to need, so it is raised only when the
# new version is in a different major than the floor (scripts/ci/check-shared-pins.py requires the floor to be
# at most the pin within one major); on a same-major bump the floors stay. Refuses anything that is not X.Y.Z
# (a v prefix, a pre-release, shell metacharacters) before touching a file, and refuses to go backwards.
# Re-running the version that is already pinned succeeds and changes nothing.
set -euo pipefail

version="${1-}"
if [ -z "$version" ]; then
  echo "usage: bump-pin.sh X.Y.Z [repo-root]" >&2
  exit 2
fi
cd "${2:-$(dirname "$0")/../..}"

SEMVER='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
URL='https://github.com/binary-companion/calendar-connectors'
PROJECT=Apps/macOS/project.yml

if ! [[ "$version" =~ $SEMVER ]]; then
  echo "not X.Y.Z: $version" >&2
  exit 2
fi
[ -f "$PROJECT" ] || { echo "$PROJECT not found in $PWD" >&2; exit 2; }

# The pin as it stands: the exactVersion that follows the library's url inside the CalendarConnectors entry.
current="$(perl -0ne 'print $1 if m{^[ \t]+CalendarConnectors:[ \t]*\n[ \t]+url:[ \t]*\Q'"$URL"'\E[ \t]*\n[ \t]+exactVersion:[ \t]*([0-9.]+)[ \t]*$}m' "$PROJECT")"
if [ -z "$current" ]; then
  echo "$PROJECT has no CalendarConnectors pin with url $URL followed by exactVersion" >&2
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
  echo "refusing to move the pin back from $current to $version" >&2
  exit 2
fi

# The version reaches perl through the environment, never through the program text.
export BUMP_VERSION="$version" BUMP_MAJOR="$new_major"
perl -0pi -e '
  s{(^[ \t]+CalendarConnectors:[ \t]*\n[ \t]+url:[ \t]*\Q'"$URL"'\E[ \t]*\n[ \t]+exactVersion:[ \t]*)[0-9.]+}{$1$ENV{BUMP_VERSION}}m
' "$PROJECT"

shopt -s nullglob
for manifest in Packages/*/Package*.swift; do
  perl -0pi -e '
    s{(\.package\(\s*url:\s*"\Q'"$URL"'\E"\s*,\s*from:\s*")(\d+)(\.\d+\.\d+)(")}{
      $2 eq $ENV{BUMP_MAJOR} ? "$1$2$3$4" : "$1$ENV{BUMP_VERSION}$4"
    }ge
  ' "$manifest"
done

echo "calendar-connectors pinned at $version (was $current)"
