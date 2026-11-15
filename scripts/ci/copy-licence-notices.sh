#!/usr/bin/env bash
# Xcode build phase of both app targets: puts the licence notices of what the app links into the bundle's
# Contents/Resources/Licenses/ and fails the build when a source file is absent (Rust phase 6, Task 9 step 5a;
# docs/licensing.md of timetug-shared).
#
#   TimeTugEngine-THIRD-PARTY-NOTICES.md  every crate in the statically linked engine (UniFFI is MPL-2.0)
#   TimeTugEngine-LICENSE                 the engine package's licence
#   KeyboardShortcuts-LICENSE             KeyboardShortcuts' MIT notice
#
# Reads from the SwiftPM folder of the same build: SourcePackages sits beside Build/ in the derived data folder
# (so it works for -derivedDataPath build/DerivedData and build/DerivedData-store, for archives and for Xcode's own
# derived data). Environment: Xcode's BUILD_DIR, TARGET_BUILD_DIR, UNLOCALIZED_RESOURCES_FOLDER_PATH and SRCROOT.
# Overrides: SOURCE_PACKAGES_DIR (a -clonedSourcePackagesDirPath), TIMETUG_ENGINE_XCFRAMEWORK (an XCFramework folder).
# With scripts/dev/use-local-library.sh the engine is a local path in project.yml and has no artifacts folder; that
# checkout's build/TimeTugEngineFFI.xcframework is used then.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

: "${TARGET_BUILD_DIR:?must be set by Xcode}"
: "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?must be set by Xcode}"
dest="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Licenses"

packages="${SOURCE_PACKAGES_DIR:-}"
if [ -z "$packages" ]; then
  build_dir="${BUILD_DIR:-$TARGET_BUILD_DIR}"
  case "$build_dir" in
    */Build/*) packages="${build_dir%%/Build/*}/SourcePackages";;
    *) die "cannot locate SourcePackages from BUILD_DIR=$build_dir (set SOURCE_PACKAGES_DIR)";;
  esac
fi

xcframework="${TIMETUG_ENGINE_XCFRAMEWORK:-}"
if [ -z "$xcframework" ] && [ -d "$packages/artifacts" ]; then
  xcframework="$(find "$packages/artifacts" -type d -name TimeTugEngineFFI.xcframework -print -quit)"
fi
if [ -z "$xcframework" ] && [ -f "${SRCROOT:-.}/project.yml" ]; then
  # use-local-library.sh turns the TimeTugShared entry into `path: <relative>`.
  rel="$(awk '/^  TimeTugShared:/ {f=1; next} f && /^  [^ ]/ {f=0} f && $1=="path:" {print $2; exit}' "${SRCROOT:-.}/project.yml")"
  if [ -n "$rel" ]; then xcframework="$(cd "${SRCROOT:-.}" && cd "$rel" 2>/dev/null && pwd)/build/TimeTugEngineFFI.xcframework"; fi
fi
[ -n "$xcframework" ] && [ -d "$xcframework" ] \
  || die "TimeTugEngineFFI.xcframework not found under $packages/artifacts (resolve packages first)"

keyboard="$packages/checkouts/KeyboardShortcuts"
mkdir -p "$dest"
copy() { # copy <source> <destination name>
  [ -s "$1" ] || die "licence notice missing or empty: $1"
  cp -f "$1" "$dest/$2"
}
copy "$xcframework/THIRD-PARTY-NOTICES.md" TimeTugEngine-THIRD-PARTY-NOTICES.md
copy "$xcframework/LICENSE" TimeTugEngine-LICENSE
if [ -s "$keyboard/license" ]; then copy "$keyboard/license" KeyboardShortcuts-LICENSE
elif [ -s "$keyboard/LICENSE" ]; then copy "$keyboard/LICENSE" KeyboardShortcuts-LICENSE
else die "licence notice missing or empty: $keyboard/license"; fi
echo "Licence notices copied to $dest"
