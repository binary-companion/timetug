#!/usr/bin/env bash
# Tests check-architecture.sh: a clean fixture passes and each rule catches its violation. (The real repository
# is checked by the architecture job itself; during the phase 6 cutover its sources still import the old modules.)
set -euo pipefail
cd "$(dirname "$0")/../../.."
S="$PWD/scripts/ci/check-architecture.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

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
SHARED=https://github.com/binary-companion/timetug-shared
LIB=https://github.com/binary-companion/calendar-connectors   # retired in phase 6
pkg EventKitSource "$SHARED"
pkg CalendarApple "$SHARED"
pkg AppleIntelligenceInference "$SHARED"
printf 'import FoundationModels\nimport TimeTugKit\n' > "$T/Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/B.swift"
printf 'import EventKit\nimport TimeTugKit\n' > "$T/Packages/EventKitSource/Sources/EventKitSource/B.swift"
printf 'import AppKit\nimport TimeTugKit\n' > "$T/Packages/CalendarApple/Sources/CalendarApple/B.swift"
mkdir -p "$T/Apps/macOS/Sources" "$T/Apps/macOS/Widgets" "$T/Apps/macOS/Shared"
printf 'import Sparkle\nimport SwiftUI\nimport TimeTugKit\n' > "$T/Apps/macOS/Sources/App.swift"
printf 'import WidgetKit\nimport Foundation\n' > "$T/Apps/macOS/Widgets/W.swift"

out="$("$S" "$T")" || fail "clean fixture rejected: $out"

# SwiftPM prefers Package@swift-X.Y.swift over Package.swift, so clean version-specific manifests (also nested ones)
# must pass, and build output (.build, build), which holds other people's manifests, is not scanned.
for name in EventKitSource CalendarApple AppleIntelligenceInference; do
  cp "$T/Packages/$name/Package.swift" "$T/Packages/$name/Package@swift-6.0.swift"
done
mkdir -p "$T/Packages/EventKitSource/.build/checkouts/Dep" "$T/Packages/EventKitSource/build"
printf 'let package = Package(dependencies: [.package(url: "https://example.com/dep", from: "1.0.0"), .package(path: "../Other")])\n' \
  > "$T/Packages/EventKitSource/.build/checkouts/Dep/Package.swift"
cp "$T/Packages/EventKitSource/.build/checkouts/Dep/Package.swift" "$T/Packages/EventKitSource/build/Package.swift"
out="$("$S" "$T")" || fail "clean versioned manifests rejected: $out"
rm -rf "$T/Packages/EventKitSource/.build" "$T/Packages/EventKitSource/build" "$T"/Packages/*/Package@swift-6.0.swift

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
expect Packages/EventKitSource/Sources/EventKitSource/X.swift 'import CalendarApple\n' "EventKitSource may not import CalendarApple"
expect Packages/CalendarApple/Sources/CalendarApple/X.swift 'import SwiftUI\n' "CalendarApple may not import SwiftUI"
expect Packages/CalendarApple/Sources/CalendarApple/X.swift 'import Sparkle\n' "Sparkle is app-only) may not import Sparkle"
expect Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/X.swift 'import EventKitSource\n' \
  "AppleIntelligenceInference may not import EventKitSource"
# FoundationModels only in AppleIntelligenceInference, EventKit only in EventKitSource.
expect Apps/macOS/Sources/X.swift 'import FoundationModels\n' "FoundationModels"
expect Packages/CalendarApple/Sources/CalendarApple/X.swift 'import FoundationModels\n' "may not import FoundationModels"
expect Apps/macOS/Sources/X.swift 'import EventKit\n' "may not import EventKit"
expect Packages/CalendarApple/Sources/CalendarApple/X.swift 'import EventKit\n' "may not import EventKit"
expect Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/X.swift 'import EventKit\n' "may not import EventKit"
# The widgets do not link the engine: no TimeTugKit, no EventKit, no Sparkle.
expect Apps/macOS/Widgets/X.swift 'import TimeTugKit\n' "may not import TimeTugKit"
expect Apps/macOS/Shared/X.swift 'import TimeTugKit\n' "may not import TimeTugKit"
expect Apps/macOS/Widgets/X.swift 'import EventKit\n' "may not import EventKit"
expect Apps/macOS/Shared/X.swift 'import Sparkle\n' "may not import Sparkle"
# The modules of the two former libraries are gone since phase 6 (timetug-shared 2.x ships TimeTugKit only):
# forbidden in every package and in the app, including the forms `@testable import` and `import struct M.Type`.
for module in TimeTugEngine TimeTugCore CalendarBridge CalendarCore GoogleCalendar MicrosoftCalendar CalDAVCalendar \
              ICalSubscription CalendarOAuth; do
  expect Apps/macOS/Sources/X.swift "import $module\n" "may not import $module"
  expect Apps/macOS/Widgets/X.swift "import $module\n" "may not import $module"
  expect Packages/EventKitSource/Sources/EventKitSource/X.swift "import $module\n" "may not import $module"
  expect Packages/CalendarApple/Sources/CalendarApple/X.swift "import $module\n" "may not import $module"
  expect Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/X.swift "@testable import $module\n" "may not import $module"
  expect Packages/CalendarApple/Tests/CalendarAppleTests/X.swift "import struct $module.Thing\n" "may not import $module"
done
# TimeTugKit itself is fine in the app and in every package.
for f in Apps/macOS/Sources/Y.swift Packages/EventKitSource/Sources/EventKitSource/Y.swift \
         Packages/CalendarApple/Sources/CalendarApple/Y.swift Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/Y.swift; do
  mkdir -p "$(dirname "$T/$f")"; printf 'import TimeTugKit\n' > "$T/$f"
  out="$("$S" "$T")" || fail "import TimeTugKit rejected in $f: $out"
  rm "$T/$f"
done
# Package dependencies: the allow-list is exact (every package depends on timetug-shared and nothing else),
# the retired connector library is refused, and a path dependency on a moved package is refused.
for pkgname in EventKitSource CalendarApple AppleIntelligenceInference; do
  expect "Packages/$pkgname/Package.swift" 'let package = Package(dependencies: [.package(url: "'$LIB'", from: "1.0.0")])\n' \
    "$pkgname may not depend on $LIB"
done
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
  expect "Packages/$adapter/Package.swift" 'let package = Package(dependencies: [.package(path: "../TimeTugCore")])\n' \
    "$adapter may not depend on ../TimeTugCore"
done
expect Packages/NewThing/Package.swift 'let package = Package()\n' "no rule for Packages/NewThing"
# Version-specific manifests (which SwiftPM prefers) follow the same rules, and the violation names the file it is in.
V='let package = Package(dependencies: [.package(path: "../CalendarApple")])\n'
expect Packages/EventKitSource/Package@swift-6.0.swift "$V" \
  "Packages/EventKitSource/Package@swift-6.0.swift:1: EventKitSource may not depend on ../CalendarApple"
expect Packages/CalendarApple/Package@swift-5.9.swift \
  'let package = Package(dependencies: [.package(url: "https://github.com/x/y", from: "1.0.0")])\n' \
  "Packages/CalendarApple/Package@swift-5.9.swift:1: CalendarApple may not depend on https://github.com/x/y"
expect Packages/EventKitSource/Package@swift-6.0.swift \
  'let package = Package(dependencies: [.package(url: "'$LIB'", from: "1.0.0")])\n' \
  "Packages/EventKitSource/Package@swift-6.0.swift:1: EventKitSource may not depend on $LIB"
expect Packages/AppleIntelligenceInference/Package@swift-6.0.swift \
  'let package = Package(\n  dependencies: [\n    .package(\n      path: "../TimeTugCore"\n    ),\n  ]\n)\n' \
  "Packages/AppleIntelligenceInference/Package@swift-6.0.swift:4: AppleIntelligenceInference may not depend on ../TimeTugCore"
expect Packages/EventKitSource/Tests/Fixture/Package.swift "$V" \
  "Packages/EventKitSource/Tests/Fixture/Package.swift:1: EventKitSource may not depend on ../CalendarApple"
expect Packages/EventKitSource/Tests/Fixture/Package@swift-6.0.swift "$V" \
  "Packages/EventKitSource/Tests/Fixture/Package@swift-6.0.swift:1: EventKitSource may not depend on ../CalendarApple"
expect Packages/NewThing/Package@swift-6.0.swift 'let package = Package()\n' \
  "Packages/NewThing/Package@swift-6.0.swift:1: no rule for Packages/NewThing"

echo "PASS"
