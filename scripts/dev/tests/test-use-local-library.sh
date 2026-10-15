#!/usr/bin/env bash
# Tests use-local-library.sh in a throwaway repo shaped like this one, once per shared library. Needs PyYAML on
# PATH (check-shared-pins.py reads project.yml).
set -euo pipefail
cd "$(dirname "$0")/../../.."
SRC="$PWD"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
g() { git -c user.name=t -c user.email=t@t "$@"; }
ORG=https://github.com/binary-companion
# Runs a command, keeping its exit status in $rc and its output in $out.
capture() { rc=0; out="$("$@" 2>&1)" || rc=$?; }

# $1 library slug, $2 its project.yml key, $3 the other library's slug, $4 the other key.
exercise() {
  local lib="$1" key="$2" other="$3" otherkey="$4"
  local R="$T/$lib-repo" W="$T/$lib-work"
  mkdir -p "$R/scripts/dev" "$R/scripts/ci" "$R/Apps/macOS" "$R/Packages/Alpha" "$R/Packages/Beta" \
           "$W/$lib" "$W/$other" "$W/other" "$W/second/$lib" "$W/missing-pin/$lib" "$W/unknown-library"
  touch "$W/$lib/Package.swift" "$W/$other/Package.swift" "$W/other/Package.swift" "$W/second/$lib/Package.swift" \
        "$W/missing-pin/$lib/Package.swift" "$W/unknown-library/Package.swift"
  cp "$SRC/scripts/dev/use-local-library.sh" "$R/scripts/dev/"
  cp "$SRC/scripts/ci/check-shared-pins.py" "$R/scripts/ci/"
  # The same shape as the real tree: both libraries pinned, another package pinned, a local package, and
  # manifests that depend on both libraries by URL (Package.swift and the version-specific variant SwiftPM
  # prefers) next to a local sibling dependency.
  printf 'packages:\n  Sparkle:\n    url: https://github.com/sparkle-project/Sparkle\n    exactVersion: 2.10.0\n  CalendarConnectors:\n    url: %s/calendar-connectors\n    exactVersion: 1.2.0\n  LocalBeta:\n    path: ../../Packages/Beta\n  TimeTugShared:\n    url: %s/timetug-shared\n    exactVersion: 1.0.0\n' "$ORG" "$ORG" > "$R/Apps/macOS/project.yml"
  local deps="[.package(url: \"$ORG/calendar-connectors\", from: \"1.0.0\"), .package(url: \"$ORG/timetug-shared\", from: \"1.0.0\"), .package(path: \"../Beta\")]"
  printf 'let package = Package(dependencies: %s)\n' "$deps" > "$R/Packages/Alpha/Package.swift"
  printf 'let package = Package(dependencies: %s)\n' "$deps" > "$R/Packages/Alpha/Package@swift-6.0.swift"
  printf 'let package = Package(dependencies: [.package(url: "%s/%s", from: "1.0.0")])\n' "$ORG" "$lib" > "$R/Packages/Beta/Package.swift"
  cd "$R"
  git init -q -b master; g add -A; g commit -qm base
  python3 scripts/ci/check-shared-pins.py >/dev/null || fail "$lib: fixture should start clean"

  local BACKUP=build/local-library-backup
  local USE=scripts/dev/use-local-library.sh
  local MANIFEST=Packages/Alpha/Package.swift VARIANT=Packages/Alpha/Package@swift-6.0.swift PROJECT=Apps/macOS/project.yml
  # Everything the override may touch, plus its backup, as "checksum size path" lines.
  snapshot() { find Packages Apps build -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do echo "$(cksum < "$f") $f"; done; }
  # The project file without this library's entry (its key line and the lines indented below it).
  without_entry() { perl -0pe 's/^([ \t]*)'"$key"':\n(?:\1[ \t]+[^\n]*\n)*//m'; }

  # --- Override and restore on a clean tree
  $USE "$lib" "$W/$lib" >/dev/null
  grep -q "path: \"$W/$lib\"" $MANIFEST || fail "$lib: manifest not redirected"
  grep -q "path: \"$W/$lib\"" $VARIANT || fail "$lib: version-specific manifest not redirected (SwiftPM prefers it)"
  grep -q "path: \"$W/$lib\"" Packages/Beta/Package.swift || fail "$lib: second manifest not redirected"
  if grep -q "$ORG/$lib\"" $MANIFEST $VARIANT Packages/Beta/Package.swift; then fail "$lib: a manifest still has the released url"; fi
  grep -q "$ORG/$other\", from: \"1.0.0\"" $MANIFEST || fail "$lib: the $other dependency was redirected too"
  grep -q "$ORG/$other\", from: \"1.0.0\"" $VARIANT || fail "$lib: the $other dependency was redirected in the variant too"
  grep -q 'path: "../Beta"' $MANIFEST || fail "$lib: a sibling path dependency changed"
  grep -Eq "path: .*/$lib\$" $PROJECT || fail "$lib: project.yml not redirected"
  [ -f $BACKUP/after.sha256 ] || fail "$lib: the override recorded no hashes"
  # Only this library's entry may differ from the committed project file (the other library and the other
  # packages keep their pins).
  git show HEAD:$PROJECT | grep -q "$key:" || fail "$lib: fixture has no $key entry"
  [ "$(git show HEAD:$PROJECT | without_entry)" = "$(without_entry < $PROJECT)" ] || fail "$lib: lines outside the $key entry changed"
  grep -q "$otherkey:" $PROJECT || fail "$lib: the $otherkey entry is gone"
  grep -q "url: $ORG/$other\$" $PROJECT || fail "$lib: the $otherkey entry lost its url"
  if python3 scripts/ci/check-shared-pins.py >/dev/null 2>&1; then fail "$lib: the contract accepted a local override"; fi
  $USE --restore >/dev/null
  [ -z "$(git status --porcelain)" ] || fail "$lib: restore left changes: $(git status --porcelain)"
  [ ! -e $BACKUP ] || fail "$lib: restore left the backup"
  python3 scripts/ci/check-shared-pins.py >/dev/null || fail "$lib: restored tree should pass"

  # --- Refusals change nothing and leave no backup
  capture $USE --restore; [ "$rc" = 2 ] || fail "$lib: restore without an override should exit 2 (got $rc)"
  capture $USE "$lib" --restore; [ "$rc" = 2 ] || fail "$lib: '<library> --restore' without an override should exit 2 (got $rc)"
  capture $USE "$lib" "$W/missing"; [ "$rc" = 2 ] || fail "$lib: accepted a missing checkout"
  capture $USE "$lib" "$W/other"; [ "$rc" = 2 ] || fail "$lib: accepted a checkout not named $lib"
  capture $USE "$lib" "$W/$other"; [ "$rc" = 2 ] || fail "$lib: accepted the $other checkout for $lib"
  capture $USE unknown-library "$W/$lib"; [ "$rc" = 2 ] || fail "$lib: accepted an unknown library"
  # Even with a checkout that carries the unknown name, the library must be reported as unknown.
  capture $USE unknown-library "$W/unknown-library"; [ "$rc" = 2 ] || fail "$lib: accepted an unknown library by name"
  case "$out" in *"unknown library"*usage*) ;; *) fail "$lib: an unknown library was not reported as such: $out" ;; esac
  capture $USE "$key" "$W/$lib"; [ "$rc" = 2 ] || fail "$lib: accepted the project.yml key as the library"
  capture $USE "$W/$lib"; [ "$rc" = 2 ] || fail "$lib: accepted a path without a library"
  case "$out" in *usage*) ;; *) fail "$lib: a path without a library did not print a usage message: $out" ;; esac
  capture $USE "$lib"; [ "$rc" = 2 ] || fail "$lib: accepted a library without a path"
  capture $USE; [ "$rc" = 2 ] || fail "$lib: accepted no arguments"
  capture $USE "$lib" "$W/$lib" extra; [ "$rc" = 2 ] || fail "$lib: accepted an extra argument"
  capture $USE "$lib" --force; [ "$rc" = 2 ] || fail "$lib: accepted --force as a path"
  capture $USE --force "$lib"; [ "$rc" = 2 ] || fail "$lib: accepted --force before the library"
  [ -z "$(git status --porcelain)" ] || fail "$lib: a refused call changed files"
  [ ! -e $BACKUP ] || fail "$lib: a refused call left a backup"

  # --- A project without this library's pin is refused before anything is touched
  git show HEAD:$PROJECT | without_entry > $PROJECT
  capture $USE "$lib" "$W/missing-pin/$lib"
  [ "$rc" = 2 ] || fail "$lib: a project without the $key pin should exit 2 (got $rc)"
  [ ! -e $BACKUP ] || fail "$lib: a refused call left a backup"
  grep -q "$ORG/$lib\", from" $MANIFEST || fail "$lib: a refused call changed a manifest"
  git checkout -q -- $PROJECT
  [ -z "$(git status --porcelain)" ] || fail "$lib: could not undo the pin removal: $(git status --porcelain)"

  # --- Uncommitted edits made BEFORE the override survive --restore byte for byte
  echo '// uncommitted note' >> $MANIFEST
  echo '# uncommitted note' >> $PROJECT
  cp $MANIFEST "$W/manifest.before"; cp $PROJECT "$W/project.before"
  $USE "$lib" "$W/$lib" >/dev/null
  $USE --restore >/dev/null
  cmp -s $MANIFEST "$W/manifest.before" || fail "$lib: restore lost an uncommitted manifest edit"
  cmp -s $PROJECT "$W/project.before" || fail "$lib: restore lost an uncommitted project.yml edit"
  [ "$(git status --porcelain | wc -l | tr -d ' ')" = 2 ] || fail "$lib: restore changed other files: $(git status --porcelain)"
  git checkout -q -- Packages Apps

  # --- A second override while one is in place is refused and changes nothing (for either library)
  $USE "$lib" "$W/$lib" >/dev/null
  snapshot > "$W/snapshot.before"
  capture $USE "$lib" "$W/second/$lib"
  [ "$rc" = 2 ] || fail "$lib: second override should exit 2 (got $rc)"
  case "$out" in *"--restore"*) ;; *) fail "$lib: second override did not say to run --restore: $out" ;; esac
  capture $USE "$lib" "$W/$lib"; [ "$rc" = 2 ] || fail "$lib: second override of the same checkout should exit 2 (got $rc)"
  capture $USE "$other" "$W/$other"; [ "$rc" = 2 ] || fail "$lib: an override of $other on top of $lib should exit 2 (got $rc)"
  snapshot > "$W/snapshot.after"
  cmp -s "$W/snapshot.before" "$W/snapshot.after" || fail "$lib: a refused second override changed the tree or the backup"
  $USE "$lib" --restore >/dev/null
  [ -z "$(git status --porcelain)" ] || fail "$lib: restore after a refused second override left changes"

  # --- An edit made DURING the override makes --restore refuse; --force restores the backup
  $USE "$lib" "$W/$lib" >/dev/null
  echo '# edited during the override' >> $PROJECT
  snapshot > "$W/snapshot.before"
  capture $USE --restore
  [ "$rc" = 2 ] || fail "$lib: restore over a changed file should exit 2 (got $rc)"
  case "$out" in *"$PROJECT"*) ;; *) fail "$lib: restore did not name the changed file: $out" ;; esac
  case "$out" in *"--force"*) ;; *) fail "$lib: restore did not mention --force: $out" ;; esac
  snapshot > "$W/snapshot.after"
  cmp -s "$W/snapshot.before" "$W/snapshot.after" || fail "$lib: a refused restore changed the tree or the backup"
  $USE --restore --force >/dev/null
  [ -z "$(git status --porcelain)" ] || fail "$lib: restore --force left changes: $(git status --porcelain)"
  [ ! -e $BACKUP ] || fail "$lib: restore --force left the backup"
  python3 scripts/ci/check-shared-pins.py >/dev/null || fail "$lib: force-restored tree should pass"

  # --- A manifest edited during the override is caught too (the version-specific one included)
  $USE "$lib" "$W/$lib" >/dev/null
  echo '// edited during the override' >> $VARIANT
  capture $USE --restore
  [ "$rc" = 2 ] || fail "$lib: restore over a changed variant manifest should exit 2 (got $rc)"
  case "$out" in *"$VARIANT"*) ;; *) fail "$lib: restore did not name the changed variant: $out" ;; esac
  $USE --restore --force >/dev/null
  [ -z "$(git status --porcelain)" ] || fail "$lib: restore --force left changes after a variant edit"

  # --- A backup left by an override that did not finish (no hashes) needs --force too
  $USE "$lib" "$W/$lib" >/dev/null
  rm $BACKUP/after.sha256
  capture $USE --restore; [ "$rc" = 2 ] || fail "$lib: restore without hashes should exit 2 (got $rc)"
  $USE --restore --force >/dev/null
  [ -z "$(git status --porcelain)" ] || fail "$lib: restore --force without hashes left changes"
  cd "$SRC"
}

exercise calendar-connectors CalendarConnectors timetug-shared TimeTugShared
exercise timetug-shared TimeTugShared calendar-connectors CalendarConnectors
echo PASS
