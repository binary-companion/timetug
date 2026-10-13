#!/usr/bin/env bash
# Points the local packages and the app at a calendar-connectors checkout while you work on both.
#
#   scripts/dev/use-local-connectors.sh <path-to-calendar-connectors-checkout>
#   scripts/dev/use-local-connectors.sh --restore
#
# The change is for your machine only: scripts/ci/check-shared-pins.py fails while it is in place, so it
# cannot be committed by mistake. The files it changes are copied to build/local-connectors-backup first;
# --restore puts exactly those copies back and removes the backup.
set -euo pipefail
cd "$(dirname "$0")/../.."
BACKUP=build/local-connectors-backup
FILES=(Packages/*/Package.swift Apps/macOS/project.yml)
case "${1:-}" in
  --restore)
    [ -d "$BACKUP" ] || { echo "nothing to restore: no local override is in place" >&2; exit 2; }
    cp -R "$BACKUP"/. .
    rm -rf "$BACKUP"
    echo "Restored the released pins."
    ;;
  "" | -*)
    echo "usage: $0 <path-to-calendar-connectors-checkout> | --restore" >&2
    exit 2
    ;;
  *)
    [ -f "$1/Package.swift" ] || { echo "no Package.swift in $1" >&2; exit 2; }
    ABS="$(cd "$1" && pwd)"
    # SwiftPM derives a local package's identity from its directory name and the manifests refer to it as
    # "calendar-connectors", so the checkout must have that name (use a symlink if yours does not).
    [ "$(basename "$ABS")" = calendar-connectors ] || {
      echo "the checkout directory must be named calendar-connectors (got $(basename "$ABS"))" >&2; exit 2; }
    REL="$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$ABS" Apps/macOS)"
    if [ ! -d "$BACKUP" ]; then
      for f in "${FILES[@]}"; do mkdir -p "$BACKUP/$(dirname "$f")"; cp "$f" "$BACKUP/$f"; done
    fi
    export ABS REL
    for m in Packages/*/Package.swift; do
      perl -0pi -e 's#\.package\(url: "https://github\.com/binary-companion/calendar-connectors", from: "[^"]*"\)#.package(path: "$ENV{ABS}")#g' "$m"
    done
    perl -0pi -e 's#(CalendarConnectors:\n)[ \t]+url: [^\n]*calendar-connectors\n[ \t]+exactVersion: [0-9.]+#${1}    path: $ENV{REL}#' Apps/macOS/project.yml
    echo "Using $ABS. Run with --restore before committing."
    ;;
esac
