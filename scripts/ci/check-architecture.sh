#!/usr/bin/env bash
# Checks the layering rules from docs/architecture.md that the compiler does not enforce on its own.
# Usage: scripts/ci/check-architecture.sh [repo-root]
# Prints one "path:line: message" per violation and exits 1 if there are any.
# Imports are matched at the start of a line (Swift style here); `import A; import B` on one line is not checked.
# To add a package, give it a line in allowed_deps and, if it needs them, import rules below.
set -euo pipefail
cd "${1:-$(dirname "$0")/../..}"
bad=0
report() { echo "$1: $2"; bad=$((bad + 1)); }
has() { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }

# imports <path...>: prints "file:line Module" for each Swift import (attributes and import kinds stripped).
imports() {
  local p existing=()
  for p in "$@"; do [ -e "$p" ] && existing+=("$p"); done
  [ ${#existing[@]} -gt 0 ] || return 0
  grep -rnE --include='*.swift' --exclude-dir=.build --exclude-dir=build '^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*import[[:space:]]' "${existing[@]}" |
    sed -E 's/^([^:]+:[0-9]+):[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\1 \6/' || true
}
# only <label> <allowed modules> <path...>: every import must be in the allowed list.
only() {
  local label="$1" allowed="$2" loc mod; shift 2
  while read -r loc mod; do
    has "$allowed" "$mod" || report "$loc" "$label may not import $mod (allowed: $allowed)"
  done < <(imports "$@")
}
# never <label> <forbidden modules> <path...>: no import may be in the forbidden list.
never() {
  local label="$1" forbidden="$2" loc mod; shift 2
  while read -r loc mod; do
    has "$forbidden" "$mod" && report "$loc" "$label may not import $mod"
  done < <(imports "$@")
  return 0
}

UI="AppKit SwiftUI UIKit WidgetKit"
P=Packages
# Everything the app and the packages know of the shared Rust engine, the connectors and the Core comes through
# one module, TimeTugKit, from timetug-shared 2.x (a released version, pinned: scripts/ci/check-shared-pins.py).
# The modules of the former Swift libraries no longer exist, so importing one is a leftover of the old layout.
# Their own layering rules are checked in the timetug-shared repository.
SHAREDURL=https://github.com/binary-companion/timetug-shared
RETIRED="TimeTugEngine TimeTugCore CalendarBridge CalendarCore GoogleCalendar MicrosoftCalendar CalDAVCalendar ICalSubscription CalendarOAuth"
never "$P (module removed in phase 6; use TimeTugKit)" "$RETIRED" $P
never "Apps (module removed in phase 6; use TimeTugKit)" "$RETIRED" Apps

# Source adapters speak TimeTugKit and contain no UI. They never see each other.
never EventKitSource "$UI CalendarApple AppleIntelligenceInference" $P/EventKitSource/Sources
never CalendarApple "SwiftUI UIKit WidgetKit EventKitSource AppleIntelligenceInference" $P/CalendarApple/Sources
never AppleIntelligenceInference "$UI EventKitSource CalendarApple" $P/AppleIntelligenceInference/Sources
# EventKit only in EventKitSource, Foundation Models only in the inference package; Sparkle only in the app target.
for d in $P/*; do
  [ "$d" = $P/EventKitSource ] || never "$d" EventKit "$d"
  [ "$d" = $P/AppleIntelligenceInference ] || never "$d" FoundationModels "$d"
done
never "Apps/macOS (use EventKitSource)" EventKit Apps
never "Apps/macOS (use AppleIntelligenceInference)" FoundationModels Apps
never "$P (Sparkle is app-only)" Sparkle $P
# Widgets read the snapshot; they never touch Sparkle and never link the engine (TimeTugKit).
never "Apps/macOS/Widgets and Shared" "Sparkle TimeTugKit" Apps/macOS/Widgets Apps/macOS/Shared

# Package dependencies are URL dependencies on the released library (scripts/ci/check-shared-pins.py checks the
# pin). Every package depends on timetug-shared and on nothing else; no package depends on another local package.
allowed_deps() {
  case "$1" in
    EventKitSource | CalendarApple | AppleIntelligenceInference) echo "$SHAREDURL" ;;
    *) return 1 ;;
  esac
}
# SwiftPM prefers Package@swift-X.Y.swift over Package.swift, so every Package*.swift under a package directory (at
# any depth, not .build or build, which hold other people's manifests) follows its package's rules.
manifests() {
  [ -d "$P" ] || return 0
  find "$P" \( -name .build -o -name build \) -prune -o \
    -name 'Package*.swift' \( -type f -o -type l \) -print | LC_ALL=C sort
}
while IFS= read -r manifest; do
  name="${manifest#$P/}"
  case "$name" in */*) name="${name%%/*}" ;; *) continue ;; esac   # a file directly in Packages/ is not a package manifest
  if ! allowed="$(allowed_deps "$name")"; then
    report "$manifest:1" "no rule for $P/$name in scripts/ci/check-architecture.sh; add its allowed dependencies (and update docs/architecture.md)"
    continue
  fi
  # Read the manifest as one line so a .package(...) wrapped across lines is still seen.
  while IFS= read -r dep; do
    line="$(grep -nF "\"$dep\"" "$manifest" | head -1 | cut -d: -f1)"
    has "$allowed" "$dep" || report "$manifest:${line:-1}" "$name may not depend on $dep (allowed: ${allowed:-none})"
  done < <(tr '\n' ' ' < "$manifest" | grep -oE '\.package\([^)]*\)' |
    sed -E 's/.*(path|url):[[:space:]]*"([^"]*)".*/\2/' || true)
done < <(manifests)

[ "$bad" = 0 ] || { echo "$bad architecture violation(s); the rules are in docs/architecture.md" >&2; exit 1; }
