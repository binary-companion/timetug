#!/usr/bin/env bash
# Points the local packages and the app at a checkout of one shared library (calendar-connectors or
# timetug-shared) while you work on both.
#
#   scripts/dev/use-local-library.sh <calendar-connectors|timetug-shared> <path-to-that-checkout>
#   scripts/dev/use-local-library.sh --restore [--force]
#
# (scripts/dev/use-local-connectors.sh is the same command for calendar-connectors.)
#
# The change is for your machine only: scripts/ci/check-shared-pins.py fails while it is in place, so it
# cannot be committed by mistake. The files it changes are copied to build/local-library-backup first, and
# once it has finished it records their SHA-256 hashes in build/local-library-backup/after.sha256.
#
#   * One library at a time: a second override (of either library) is refused while that backup exists, run
#     --restore first.
#   * --restore puts exactly those copies back and removes the backup. It refuses (exit 2, listing the files)
#     when any of them has changed since the override, so work done in them meanwhile is not lost silently;
#     review the files, or pass --force to restore the backup over them anyway.
set -euo pipefail
cd "$(dirname "$0")/../.."
BACKUP=build/local-library-backup
HASHES="$BACKUP/after.sha256"
# SwiftPM prefers Package@swift-X.Y.swift over Package.swift, so the version-specific manifests are redirected
# (and restored) together with the plain ones.
FILES=(Packages/*/Package*.swift Apps/macOS/project.yml)

usage() {
  echo "usage: $0 <calendar-connectors|timetug-shared> <path-to-that-checkout> | --restore [--force]" >&2
  exit 2
}

# The project.yml package key of a library (the same table as scripts/ci/check-shared-pins.py); empty when the
# argument is not a shared library.
key_of() {
  case "$1" in
    calendar-connectors) echo CalendarConnectors ;;
    timetug-shared) echo TimeTugShared ;;
  esac
}

# Prints the SHA-256 of one file: shasum on macOS and CI, sha256sum where that is what exists.
hash_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"
  else sha256sum "$1"
  fi | awk '{print $1}'
}

restore() {
  local force="$1" f want changed=() n_recorded n_backed_up
  [ -d "$BACKUP" ] || { echo "nothing to restore: no local override is in place" >&2; exit 2; }
  if [ "$force" != 1 ]; then
    [ -f "$HASHES" ] || {
      echo "refusing to restore: $HASHES is missing (the override did not finish), so changes since then" >&2
      echo "cannot be checked. Review the files, or pass --force to restore the backup anyway." >&2
      exit 2; }
    n_recorded="$(wc -l < "$HASHES")"
    n_backed_up="$(find "$BACKUP" -type f ! -path "$HASHES" | wc -l)"
    [ "$((n_recorded))" -eq "$((n_backed_up))" ] || {
      echo "refusing to restore: $HASHES does not match the files in $BACKUP. Pass --force to restore anyway." >&2
      exit 2; }
    while read -r want f; do
      if [ ! -f "$f" ]; then changed+=("$f (missing)")
      elif [ "$(hash_of "$f")" != "$want" ]; then changed+=("$f")
      fi
    done < "$HASHES"
    if [ "${#changed[@]}" -gt 0 ]; then
      echo "refusing to restore: these files changed since the override was applied:" >&2
      printf '  %s\n' "${changed[@]}" >&2
      echo "Review them (git diff), or pass --force to overwrite them with the backup in $BACKUP." >&2
      exit 2
    fi
  fi
  (cd "$BACKUP" && find . -type f ! -path ./after.sha256 -print0) | while IFS= read -r -d '' f; do
    mkdir -p "$(dirname "$f")"
    cp "$BACKUP/$f" "$f"
  done
  rm -rf "$BACKUP"
  echo "Restored the released pins."
}

override() {
  local library="$1" checkout="$2" key abs rel f m
  key="$(key_of "$library")"
  [ -n "$key" ] || { echo "unknown library: $library" >&2; usage; }
  [ ! -e "$BACKUP" ] || {
    echo "a local override is already in place ($BACKUP exists); run $0 --restore first" >&2; exit 2; }
  [ -f "$checkout/Package.swift" ] || { echo "no Package.swift in $checkout" >&2; exit 2; }
  abs="$(cd "$checkout" && pwd)"
  # SwiftPM derives a local package's identity from its directory name and the manifests refer to it as
  # "<library>", so the checkout must have that name (use a symlink if yours does not).
  [ "$(basename "$abs")" = "$library" ] || {
    echo "the checkout directory must be named $library (got $(basename "$abs"))" >&2; exit 2; }
  export LIBRARY="$library" KEY="$key"
  # Without the library's pin in project.yml the redirect below would silently do nothing there.
  perl -0ne 'exit(m{^[ \t]+\Q$ENV{KEY}\E:\n[ \t]+url: [^\n]*/\Q$ENV{LIBRARY}\E\n[ \t]+exactVersion: [0-9.]+}m ? 0 : 1)' \
    Apps/macOS/project.yml || {
    echo "Apps/macOS/project.yml has no $key pin with the url of $library; nothing to redirect" >&2; exit 2; }
  rel="$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$abs" Apps/macOS)"
  for f in "${FILES[@]}"; do mkdir -p "$BACKUP/$(dirname "$f")"; cp "$f" "$BACKUP/$f"; done
  export ABS="$abs" REL="$rel"
  for m in Packages/*/Package*.swift; do
    perl -0pi -e 's#\.package\(url: "https://github\.com/binary-companion/\Q$ENV{LIBRARY}\E", from: "[^"]*"\)#.package(path: "$ENV{ABS}")#g' "$m"
  done
  perl -0pi -e 's#(^[ \t]+\Q$ENV{KEY}\E:\n)[ \t]+url: [^\n]*/\Q$ENV{LIBRARY}\E\n[ \t]+exactVersion: [0-9.]+#${1}    path: $ENV{REL}#m' Apps/macOS/project.yml
  # Written last: its presence marks a finished override, and --restore compares against it.
  for f in "${FILES[@]}"; do printf '%s  %s\n' "$(hash_of "$f")" "$f"; done > "$HASHES"
  echo "Using $abs. Run with --restore before committing."
}

command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1 || {
  echo "need shasum or sha256sum" >&2; exit 2; }
# `--restore [--force]` also follows a library name, so the connectors wrapper can pass its arguments through.
if [ -n "$(key_of "${1:-}")" ] && [ "${2:-}" = --restore ]; then shift; fi
case "${1:-}" in
  --restore)
    case "${2:-}" in
      "") restore 0 ;;
      --force) [ "$#" -eq 2 ] || usage; restore 1 ;;
      *) usage ;;
    esac
    ;;
  "" | -*) usage ;;
  *) [ "$#" -eq 2 ] || usage; override "$1" "$2" ;;
esac
