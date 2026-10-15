#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/scripts/dev" "$T/repo/scripts/ci/tests" "$T/repo/scripts/release/tests" "$T/repo/site/tests" "$T/bin"
cp "$ROOT/scripts/dev/verify.sh" "$T/repo/scripts/dev/verify.sh"
cat > "$T/repo/scripts/dev/tests-placeholder" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
mkdir -p "$T/repo/scripts/dev/tests"
mv "$T/repo/scripts/dev/tests-placeholder" "$T/repo/scripts/dev/tests/test-verify.sh"
for name in swift xcodegen xcodebuild python3 node; do
  cat > "$T/bin/$name" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$VERIFY_CALLS"
if [[ "$(basename "$0")" == swift ]] &&
   [[ -n "${TIMETUG_LIVE_EVENTKIT:-}${TIMETUG_LIVE_GOOGLE:-}${TIMETUG_LIVE_MICROSOFT:-}" ]]; then
  printf 'LIVE_FLAGS_INHERITED\n' >> "$VERIFY_CALLS"
fi
SCRIPT
  chmod +x "$T/bin/$name"
done
cat > "$T/repo/scripts/ci/tests/test-dummy.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
cp "$T/repo/scripts/ci/tests/test-dummy.sh" "$T/repo/scripts/release/tests/test-dummy.sh"
cp "$T/repo/scripts/ci/tests/test-dummy.sh" "$T/repo/scripts/dev/tests/test-use-local-connectors.sh"
# Records that verify.sh ran it (the stubbed python3 and swift record their own calls).
cat > "$T/repo/scripts/dev/tests/test-use-local-library.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "ran test-use-local-library.sh" >> "$VERIFY_CALLS"
SCRIPT
cd "$T/repo"
git init -q
git config user.email test@example.com
git config user.name Test
printf 'base\n' > README.md
printf 'build/\n' > .gitignore
git add .
git commit -qm base
export VERIFY_CALLS="$T/calls" PATH="$T/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
run_mode() { : > "$VERIFY_CALLS"; scripts/dev/verify.sh "$@" >/dev/null; }
run_mode core
grep -q 'swift test --package-path Packages/AppleIntelligenceInference' "$VERIFY_CALLS" || fail 'inference omitted'
# TimeTugCore and CalendarBridge are tested in timetug-shared, the connector library in calendar-connectors.
for moved in Packages/TimeTugCore Packages/CalendarBridge Packages/CalendarConnectors; do
  if grep -q "$moved" "$VERIFY_CALLS"; then fail "$moved is tested from this repository"; fi
done
export TIMETUG_LIVE_EVENTKIT=1 TIMETUG_LIVE_GOOGLE=1 TIMETUG_LIVE_MICROSOFT=1
for mode in connectors all; do
  run_mode "$mode"
  for moved in Packages/TimeTugCore Packages/CalendarBridge Packages/CalendarConnectors; do
    if grep -q "$moved" "$VERIFY_CALLS"; then fail "mode $mode tests $moved from this repository"; fi
  done
done
# Every mode that runs the script tests runs the shared-library wrapper tests and the resolved-version tests.
for mode in release-tools all; do
  run_mode "$mode"
  grep -q 'ran test-use-local-library.sh' "$VERIFY_CALLS" || fail "mode $mode omitted test-use-local-library.sh"
  grep -q 'python3 -m unittest scripts/ci/tests/test_resolved_version.py' "$VERIFY_CALLS" ||
    fail "mode $mode omitted test_resolved_version.py"
done
run_mode core
if grep -q LIVE_FLAGS_INHERITED "$VERIFY_CALLS"; then fail 'live-test flags reached package tests'; fi
mkdir -p Apps/macOS
echo x > Apps/macOS/'file with spaces.swift'
run_mode affected
grep -q 'xcodegen generate' "$VERIFY_CALLS" || fail 'untracked app with spaces omitted'
if grep -q '^swift ' "$VERIFY_CALLS"; then fail 'app-only change ran packages'; fi
rm Apps/macOS/'file with spaces.swift'
mkdir -p docs
echo docs > docs/change.md
run_mode affected
grep -q 'python3 scripts/ci/check-repository-contracts.py' "$VERIFY_CALLS" || fail 'documentation check omitted'
grep -q 'python3 scripts/ci/check-shared-pins.py' "$VERIFY_CALLS" || fail 'shared pin check omitted'
if grep -q '^swift\|^xcodebuild' "$VERIFY_CALLS"; then fail 'documentation ran build'; fi
rm docs/change.md
# Editing a manifest or the project file can change which version the app resolves, so the pin check runs.
mkdir -p Packages/AppleIntelligenceInference Packages/CalendarApple Apps/macOS
for changed in Packages/AppleIntelligenceInference/Package.swift 'Packages/AppleIntelligenceInference/Package@swift-5.9.swift' \
  Packages/CalendarApple/Package.swift Apps/macOS/project.yml; do
  echo x > "$changed"
  run_mode affected
  grep -q 'python3 scripts/ci/check-shared-pins.py' "$VERIFY_CALLS" || fail "shared pin check omitted for $changed"
  rm "$changed"
done
mkdir -p Packages/CalendarApple/Sources/CalendarApple
echo model > Packages/CalendarApple/Sources/CalendarApple/'model with spaces.swift'
run_mode affected
grep -q 'swift test --package-path Packages/CalendarApple' "$VERIFY_CALLS" || fail 'adapter tests omitted'
grep -q 'xcodebuild ' "$VERIFY_CALLS" || fail 'adapter app dependent omitted'
# No local package depends on the adapters, so an adapter change must not select the inference package.
if grep -q 'Packages/AppleIntelligenceInference' "$VERIFY_CALLS"; then fail 'adapter change ran inference'; fi
rm Packages/CalendarApple/Sources/CalendarApple/'model with spaces.swift'
# The inference package (which depends on timetug-shared by URL) selects itself and the app, not the adapters.
mkdir -p Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference
echo x > Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/Engine.swift
run_mode affected
grep -q 'swift test --package-path Packages/AppleIntelligenceInference' "$VERIFY_CALLS" || fail 'inference tests omitted'
grep -q 'xcodebuild ' "$VERIFY_CALLS" || fail 'inference app dependent omitted'
for other in CalendarApple EventKitSource TimeTugCore CalendarBridge; do
  if grep -q "Packages/$other" "$VERIFY_CALLS"; then fail "inference change ran $other"; fi
done
rm Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/Engine.swift
mkdir -p .github/workflows
echo workflow > .github/workflows/new.yml
run_mode affected
grep -q 'node --test site/tests/download.test.js' "$VERIFY_CALLS" || fail 'workflow release-tools omitted'
if grep -q '^swift\|^xcodebuild' "$VERIFY_CALLS"; then fail 'workflow change ran build'; fi
rm .github/workflows/new.yml
run_mode affected
[ ! -s "$VERIFY_CALLS" ] || fail 'no-change run executed checks'
if scripts/dev/verify.sh affected --base missing-ref >/dev/null 2>&1; then fail 'missing base accepted'; fi
cat > "$T/bin/swift" <<'SCRIPT'
#!/usr/bin/env bash
exit 7
SCRIPT
chmod +x "$T/bin/swift"
if scripts/dev/verify.sh core >/dev/null 2>&1; then fail 'failed subprocess accepted'; fi
echo PASS
