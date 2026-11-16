#!/usr/bin/env bash
# Tests scripts/ci/copy-licence-notices.sh against a fake SwiftPM artifacts tree: present -> copied, absent -> non-zero.
set -euo pipefail
cd "$(dirname "$0")/../../.."
S="$PWD/scripts/ci/copy-licence-notices.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# A derived-data folder shaped like Xcode's: Build/Products/Debug is BUILD_DIR, SourcePackages is beside Build.
mk() { # mk <name>: creates $T/<name> with a full tree and prints nothing
  local d="$T/$1"
  mkdir -p "$d/Build/Products/Debug/TimeTug.app/Contents/Resources" \
           "$d/SourcePackages/artifacts/timetug-shared/TimeTugEngineFFI/TimeTugEngineFFI.xcframework" \
           "$d/SourcePackages/checkouts/KeyboardShortcuts"
  echo engine-notices > "$d/SourcePackages/artifacts/timetug-shared/TimeTugEngineFFI/TimeTugEngineFFI.xcframework/THIRD-PARTY-NOTICES.md"
  echo engine-licence > "$d/SourcePackages/artifacts/timetug-shared/TimeTugEngineFFI/TimeTugEngineFFI.xcframework/LICENSE"
  echo ks-licence > "$d/SourcePackages/checkouts/KeyboardShortcuts/license"
}
run() { # run <name> [extra env...]
  local d="$T/$1"; shift
  env -i PATH="$PATH" BUILD_DIR="$d/Build/Products/Debug" TARGET_BUILD_DIR="$d/Build/Products/Debug" \
    UNLOCALIZED_RESOURCES_FOLDER_PATH=TimeTug.app/Contents/Resources SRCROOT="$T/src" "$@" bash "$S"
}
mkdir -p "$T/src"
OUT() { echo "$T/$1/Build/Products/Debug/TimeTug.app/Contents/Resources/Licenses"; }

mk ok
run ok >/dev/null 2>&1 || fail "present files should succeed"
[ "$(cat "$(OUT ok)/TimeTugEngine-THIRD-PARTY-NOTICES.md")" = engine-notices ] || fail "engine notices not copied"
[ "$(cat "$(OUT ok)/TimeTugEngine-LICENSE")" = engine-licence ] || fail "engine licence not copied"
[ "$(cat "$(OUT ok)/KeyboardShortcuts-LICENSE")" = ks-licence ] || fail "KeyboardShortcuts licence not copied"
run ok >/dev/null 2>&1 || fail "second run (idempotent) should succeed"

# Archive builds put BUILD_DIR deeper under Build/Intermediates.noindex.
mk arch
mkdir -p "$T/arch/Build/Intermediates.noindex/ArchiveIntermediates/TimeTug/BuildProductsPath/Release"
run arch BUILD_DIR="$T/arch/Build/Intermediates.noindex/ArchiveIntermediates/TimeTug/BuildProductsPath" >/dev/null 2>&1 \
  || fail "archive-shaped BUILD_DIR should succeed"

# Each missing source fails the build, naming the file.
for victim in \
  "SourcePackages/artifacts/timetug-shared/TimeTugEngineFFI/TimeTugEngineFFI.xcframework/THIRD-PARTY-NOTICES.md" \
  "SourcePackages/artifacts/timetug-shared/TimeTugEngineFFI/TimeTugEngineFFI.xcframework/LICENSE" \
  "SourcePackages/checkouts/KeyboardShortcuts/license"; do
  mk miss; rm -f "$T/miss/$victim"
  rc=0; out="$(run miss 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "missing $victim should fail"
  case "$out" in *"$(basename "$victim")"*) ;; *) fail "message for $victim should name the file: $out";; esac
  rm -rf "$T/miss"
done

# No artifacts folder at all.
mk none; rm -rf "$T/none/SourcePackages/artifacts"
rc=0; run none >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "no artifacts should fail"

# An empty file is as bad as an absent one.
mk empty; : > "$T/empty/SourcePackages/checkouts/KeyboardShortcuts/license"
rc=0; run empty >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "empty file should fail"

# A local library checkout (scripts/dev/use-local-library.sh): project.yml says path:, no artifacts folder.
mk local; rm -rf "$T/local/SourcePackages/artifacts"
mkdir -p "$T/src/Apps/macOS" "$T/lib/build/TimeTugEngineFFI.xcframework"
echo local-notices > "$T/lib/build/TimeTugEngineFFI.xcframework/THIRD-PARTY-NOTICES.md"
echo local-licence > "$T/lib/build/TimeTugEngineFFI.xcframework/LICENSE"
printf 'packages:\n  TimeTugShared:\n    path: ../../../lib\n  Other:\n    url: x\n' > "$T/src/Apps/macOS/project.yml"
mkdir -p "$T/src/Apps/macOS"
run local SRCROOT="$T/src/Apps/macOS" >/dev/null 2>&1 || fail "local checkout should succeed"
[ "$(cat "$(OUT local)/TimeTugEngine-LICENSE")" = local-licence ] || fail "local checkout licence not copied"

# An explicit override wins.
mk over; rm -rf "$T/over/SourcePackages/artifacts"
run over TIMETUG_ENGINE_XCFRAMEWORK="$T/lib/build/TimeTugEngineFFI.xcframework" >/dev/null 2>&1 || fail "override should succeed"
echo "ok"
