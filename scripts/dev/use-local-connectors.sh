#!/usr/bin/env bash
# Points the local packages and the app at a calendar-connectors checkout while you work on both.
#
#   scripts/dev/use-local-connectors.sh <path-to-calendar-connectors-checkout>
#   scripts/dev/use-local-connectors.sh --restore [--force]
#
# The change is for your machine only: scripts/ci/check-shared-pins.py fails while it is in place, so it
# cannot be committed by mistake. The files it changes are copied to build/local-connectors-backup first, and
# once it has finished it records their SHA-256 hashes in build/local-connectors-backup/after.sha256.
#
#   * A second override is refused while that backup exists: run --restore first.
#   * --restore puts exactly those copies back and removes the backup. It refuses (exit 2, listing the files)
#     when any of them has changed since the override, so work done in them meanwhile is not lost silently;
#     review the files, or pass --force to restore the backup over them anyway.
set -euo pipefail
cd "$(dirname "$0")/../.."
BACKUP=build/local-connectors-backup
HASHES="$BACKUP/after.sha256"
FILES=(Packages/*/Package.swift Apps/macOS/project.yml)

usage() { echo "usage: $0 <path-to-calendar-connectors-checkout> | --restore [--force]" >&2; exit 2; }

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
  local checkout="$1" abs rel f m
  [ ! -e "$BACKUP" ] || {
    echo "a local override is already in place ($BACKUP exists); run $0 --restore first" >&2; exit 2; }
  [ -f "$checkout/Package.swift" ] || { echo "no Package.swift in $checkout" >&2; exit 2; }
  abs="$(cd "$checkout" && pwd)"
  # SwiftPM derives a local package's identity from its directory name and the manifests refer to it as
  # "calendar-connectors", so the checkout must have that name (use a symlink if yours does not).
  [ "$(basename "$abs")" = calendar-connectors ] || {
    echo "the checkout directory must be named calendar-connectors (got $(basename "$abs"))" >&2; exit 2; }
  rel="$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$abs" Apps/macOS)"
  for f in "${FILES[@]}"; do mkdir -p "$BACKUP/$(dirname "$f")"; cp "$f" "$BACKUP/$f"; done
  export ABS="$abs" REL="$rel"
  for m in Packages/*/Package.swift; do
    perl -0pi -e 's#\.package\(url: "https://github\.com/binary-companion/calendar-connectors", from: "[^"]*"\)#.package(path: "$ENV{ABS}")#g' "$m"
  done
  perl -0pi -e 's#(CalendarConnectors:\n)[ \t]+url: [^\n]*calendar-connectors\n[ \t]+exactVersion: [0-9.]+#${1}    path: $ENV{REL}#' Apps/macOS/project.yml
  # Written last: its presence marks a finished override, and --restore compares against it.
  for f in "${FILES[@]}"; do printf '%s  %s\n' "$(hash_of "$f")" "$f"; done > "$HASHES"
  echo "Using $abs. Run with --restore before committing."
}

command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1 || {
  echo "need shasum or sha256sum" >&2; exit 2; }
case "${1:-}" in
  --restore)
    case "${2:-}" in
      "") restore 0 ;;
      --force) [ "$#" -eq 2 ] || usage; restore 1 ;;
      *) usage ;;
    esac
    ;;
  "" | -*) usage ;;
  *) [ "$#" -eq 1 ] || usage; override "$1" ;;
esac
