#!/usr/bin/env bash
# Tests check-architecture.sh: the real repo passes, a clean fixture passes, and each rule catches its violation.
set -euo pipefail
cd "$(dirname "$0")/../../.."
S="$PWD/scripts/ci/check-architecture.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

"$S" >/dev/null || { "$S" >&2; fail "the repository itself violates the architecture rules"; }

# A minimal repo shaped like this one that follows every rule.
pkg() { # pkg <name> <dependencies: ../Local paths or https URLs...>
  local name="$1" deps="" d; shift
  for d in "$@"; do
    case "$d" in
      http*) deps="$deps.package(url: \"$d\", from: \"1.0.0\"), " ;;
      *) deps="$deps.package(path: \"$d\"), " ;;
    esac
  done
  mkdir -p "$T/Packages/$name/Sources/$name" "$T/Packages/$name/Tests/${name}Tests"
  printf '// swift-tools-version: 6.0\nlet package = Package(name: "%s", dependencies: [%s])\n' "$name" "$deps" \
    > "$T/Packages/$name/Package.swift"
  printf 'import Foundation\n' > "$T/Packages/$name/Sources/$name/A.swift"
}
LIB=https://github.com/binary-companion/calendar-connectors
SHARED=https://github.com/binary-companion/timetug-shared
pkg EventKitSource "$LIB"
pkg CalendarApple "$LIB"
pkg AppleIntelligenceInference "$SHARED" "$LIB"
printf 'import FoundationModels\nimport TimeTugCore\n' > "$T/Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/B.swift"
printf 'import EventKit\n' > "$T/Packages/EventKitSource/Sources/EventKitSource/B.swift"
printf 'import AppKit\nimport CalendarOAuth\n' > "$T/Packages/CalendarApple/Sources/CalendarApple/B.swift"
mkdir -p "$T/Apps/macOS/Sources" "$T/Apps/macOS/Widgets" "$T/Apps/macOS/Shared"
printf 'import Sparkle\nimport EventKit\nimport SwiftUI\n' > "$T/Apps/macOS/Sources/App.swift"
printf 'import WidgetKit\nimport TimeTugCore\n' > "$T/Apps/macOS/Widgets/W.swift"

out="$("$S" "$T")" || fail "clean fixture rejected: $out"

# expect <file> <content> <message substring>: writing <content> to <file> must make the check fail with the message.
expect() {
  local f="$T/$1" had=0 out
  [ -e "$f" ] && { had=1; cp "$f" "$f.orig"; }
  mkdir -p "$(dirname "$f")"; printf '%b' "$2" > "$f"
  if out="$("$S" "$T" 2>/dev/null)"; then fail "accepted $1 containing: $2"; fi
  case "$out" in *"$3"*) ;; *) fail "for $1 expected '$3' in: $out" ;; esac
  case "$out" in "Packages/"*|"Apps/"*) ;; *) fail "violation is not reported as path:line: $out" ;; esac
  if [ "$had" = 1 ]; then mv "$f.orig" "$f"; else rm "$f"; fi
}
expect Packages/EventKitSource/Sources/EventKitSource/X.swift 'import AppKit\n' "EventKitSource may not import AppKit"
expect Packages/EventKitSource/Sources/EventKitSource/X.swift 'import TimeTugCore\n' "EventKitSource may not import TimeTugCore"
expect Packages/CalendarApple/Sources/CalendarApple/X.swift 'import SwiftUI\n' "CalendarApple may not import SwiftUI"
expect Packages/CalendarApple/Sources/CalendarApple/X.swift 'import Sparkle\n' "Sparkle is app-only) may not import Sparkle"
expect Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/X.swift 'import CalendarBridge\n' \
  "AppleIntelligenceInference may not import CalendarBridge"
expect Apps/macOS/Sources/X.swift 'import FoundationModels\n' "FoundationModels"
expect Apps/macOS/Widgets/X.swift 'import EventKit\n' "may not import EventKit"
expect Apps/macOS/Shared/X.swift 'import Sparkle\n' "may not import Sparkle"
# Package dependencies: the allow-lists are exact (EventKitSource and CalendarApple: the library; only
# AppleIntelligenceInference may also use timetug-shared), and a path dependency on a moved package is refused.
expect Packages/AppleIntelligenceInference/Package.swift 'let package = Package(dependencies: [.package(path: "../TimeTugCore")])\n' \
  "may not depend on ../TimeTugCore"
expect Packages/AppleIntelligenceInference/Package.swift 'let package = Package(dependencies: [.package(path: "../CalendarBridge")])\n' \
  "may not depend on ../CalendarBridge"
expect Packages/AppleIntelligenceInference/Package.swift \
  'let package = Package(dependencies: [.package(url: "https://github.com/x/y", from: "1.0.0")])\n' \
  "may not depend on https://github.com/x/y"
expect Packages/AppleIntelligenceInference/Package.swift 'let package = Package(\n  dependencies: [\n    .package(\n      path: "../TimeTugCore"\n    ),\n  ]\n)\n' \
  "Package.swift:4: AppleIntelligenceInference may not depend on ../TimeTugCore"
for adapter in EventKitSource CalendarApple; do
  expect "Packages/$adapter/Package.swift" \
    'let package = Package(dependencies: [.package(url: "'$SHARED'", from: "1.0.0")])\n' \
    "$adapter may not depend on $SHARED"
  expect "Packages/$adapter/Package.swift" 'let package = Package(dependencies: [.package(path: "../TimeTugCore")])\n' \
    "$adapter may not depend on ../TimeTugCore"
done
expect Packages/NewThing/Package.swift 'let package = Package()\n' "no rule for Packages/NewThing"

echo "PASS"
