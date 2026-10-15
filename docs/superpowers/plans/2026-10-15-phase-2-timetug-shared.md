# Phase 2: `timetug-shared` repository Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `TimeTugCore` and `CalendarBridge` into the public repository `binary-companion/timetug-shared` with their history, prove them green on macOS, Linux, Windows x64 and Windows ARM64, release `1.0.0`, make every merge release automatically, and make `timetug` consume it by pinned release with bump pull requests that carry the connector pin along.

**Architecture:** Three parts, the same shape as phase 1. Part A builds the new repository in a scratch clone (extraction, files, version script, guards, workflows, Windows bring-up) and publishes it. Part B is one flip pull request in `timetug` (URL dependency, generalized pin tooling, reworked guards and docs). Part C closes the chain: `timetug-shared` gets its own bump workflow and notify job, `calendar-connectors` also notifies `timetug-shared`, `timetug`'s bump workflow handles two libraries, then a drill proves the whole chain.

**Tech Stack:** Swift 6.0 / SwiftPM, `git filter-repo` (through `uvx`), GitHub Actions on `macos-26`, `ubuntu-latest` (swift:6.0 container), `windows-latest` and `windows-11-arm`, PowerShell 7, bash, Python 3 with PyYAML 6.0.3, `gh`, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-15-phase-2-timetug-shared-design.md` (approved by the owner 2026-10-15). Parent: `docs/superpowers/specs/2026-10-09-windows-program-design.md` (sections 1, 2 and 7). Precedent and templates: `docs/superpowers/plans/2026-10-12-phase-1-calendar-connectors.md` and the `binary-companion/calendar-connectors` repository (tag `1.0.4` or later).

## Global Constraints

- License of the new repository: MIT plus the Commons Clause, the same text as `timetug`'s `LICENSE` with the line `Software: timetug-shared` and holder "Binary Companion LLC".
- Library tags are plain `X.Y.Z` (no `v`); default branch `main`; `v*` tags belong to the app repositories.
- The manifest has no platform conditions (`.when(` is forbidden) and exactly one package dependency, `calendar-connectors`, by URL with a `from:` range; `Package.resolved` is committed.
- Every repository carries `.gitattributes` with `* text=auto eol=lf`.
- Workflows: every job declares its own `permissions:` (the organization default token is read-only); every action pinned by commit SHA with the tag in a comment: `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7`, `actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6`, `actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7`, `actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510 # v3`; only GitHub-owned actions and `google-github-actions/auth` are allowed by the organization policy, so **no third-party setup action** (Swift on Windows is installed by a script); no `pull_request_target`; no secret outside an environment except `GITHUB_TOKEN` and the read-only `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` organization secrets.
- Environments: `publish` (default branch only, no reviewer, admin bypass off) creates tags and releases with the repository token; `bump` (default branch only, admin bypass off) holds the `timetug-bot` key. The bot never merges.
- Version labels: `semver:major|minor|patch`; labels of every PR since the latest reachable tag count; highest wins; none means patch.
- `timetug` pins: local manifests `from: "X.Y.Z"`; `Apps/macOS/project.yml` `exactVersion`; no `path`, `branch` or `revision` for a shared library; nothing else in `project.yml` may name a shared library.
- The in-repo copies are frozen from extraction until the flip PR merges: no Core or Bridge change lands in `timetug` meanwhile.
- No behaviour change anywhere: `Sources` trees of `1.0.0` equal the in-repo ones (`Tests` likewise, except where a task states a documented difference).
- Commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; pull request bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. The agent never merges, publishes releases or approves environments. Never use bare `git stash`. Security settings (ruleset bypass actors, vulnerability reporting, required-check lists on existing rulesets) are the owner's; new repositories' protections are created by the agent as this plan lists.
- Secrets never enter chat, logs or files. Values from files go to `gh secret set` by redirection.

## Review Focus

1. **A Windows job that passes without running the tests** (PowerShell swallows a native exit code; an install step that succeeds but `swift` is not on `PATH` for the next step; a test target silently skipped). Pinned by Task 6's canary run (a deliberately failing test must turn the job red) and by a step that prints the executed test count and fails when it is lower than macOS's.
2. **`1.0.0` tagged while a Windows job is red or unrun.** `release.yml` does not wait for CI; the procedure (Task 7 step 6) requires all five jobs green on the tagged commit and the task review checks the run list.
3. **A bump PR that moves a pin backwards or skips a major** (`Package.resolved` revision for the wrong tag; `--at-least` lowering the connector pin; a major change applied by script). Pinned by the unit tests of `bump-resolved.py` and `bump-pin.sh` and by `--force-resolved-versions` in CI.
4. **Two bump PRs that touch the same `exactVersion` line** (connector release plus the `timetug-shared` bump that carries the connector pin). Pinned by the supersede rule and its harness test (Task 12).
5. **The pin check forgets a library** (the table has two entries; a manifest or `project.yml` entry for one passes while the other is a path override). Pinned by running every phase 1 protection test once per library (Task 9).
6. **A required check named `core-linux` is left in `timetug`'s `Protect master` after the job moves** and blocks every merge. Pinned by Task 10's explicit check of the live required-check list and an owner note.
7. **Extraction drops a file** (the benchmark script, `DedupBenchmark/main.swift`, a test support file) or leaves old `v*`/`beta-*` tags. Pinned by Task 1's path list, count and tree-hash checks.
8. **The Mac app builds against different Core code than before.** Pinned by Task 8's tree comparison before the in-repo copies are deleted.

## Deviations from the spec (decided while planning)

1. **Bump script writes `Package.resolved` by text edit, not by SwiftPM.** The bump workflow runs on `ubuntu-latest` without Swift; the script replaces `version` and `revision` of one pin and CI proves the result with `--force-resolved-versions`. The spec says "with a script"; this fixes the mechanism.
2. **`scripts/dev/use-local-connectors.sh` becomes a wrapper** around a new `scripts/dev/use-local-library.sh <library> <path>` that serves both libraries; the old name keeps working for the skill and docs.
3. **`Protect main` in the new repository keeps "require branches up to date" off**, like the library's. The owner's open decision about turning it on applies to both repositories at once; this plan does not decide it.

---

## Part A: the new repository

Scratch locations (new empty directories outside every checkout):

```bash
export WORK="$TMPDIR/phase2"                  # created in Task 1
export LIB="$WORK/timetug-shared"             # the extracted repository
export R=binary-companion/timetug-shared
fetch_cc() { gh api "repos/binary-companion/calendar-connectors/contents/$1?ref=main" --jq .content | base64 -d > "$1"; }
```

`fetch_cc <path>` (run inside `$LIB`, after `mkdir -p "$(dirname <path>)"`) copies a file from the library's `main`; every copied file is then edited exactly as its task says.

### Task 1: Extract the history

**Files:** none in `timetug`. Produces `$LIB` (not yet pushed).

**Interfaces:**
- Produces: `$LIB`, a git repository on branch `main` with `Sources/{TimeTugCore,CalendarBridge,DedupBenchmark}`, `Tests/{TimeTugCoreTests,CalendarBridgeTests}`, `scripts/benchmarks/run-dedup.sh`, no manifests, no tags, no remote; `$WORK/tree-hashes.txt` (lines `Sources <hash>`, `Tests <hash>`) and `$WORK/source-tree-hashes.txt`.

- [ ] **Step 1: Fresh clone, path list and expected count**

```bash
mkdir -p "$WORK" && cd "$WORK"
gh repo clone binary-companion/timetug extract-src -- --branch master
cd extract-src && git remote remove origin
cat > "$WORK/paths.txt" <<'EOF'
Packages/TimeTugCore/Sources/
Packages/TimeTugCore/Tests/
Packages/CalendarBridge/Sources/
Packages/CalendarBridge/Tests/
scripts/benchmarks/run-dedup.sh
EOF
# trees as they are before the rewrite, for the equality check in step 3
{
  echo "Core.Sources $(git rev-parse HEAD:Packages/TimeTugCore/Sources/TimeTugCore)"
  echo "Core.Tests $(git rev-parse HEAD:Packages/TimeTugCore/Tests/TimeTugCoreTests)"
  echo "Bridge.Sources $(git rev-parse HEAD:Packages/CalendarBridge/Sources/CalendarBridge)"
  echo "Bridge.Tests $(git rev-parse HEAD:Packages/CalendarBridge/Tests/CalendarBridgeTests)"
  echo "Benchmark $(git rev-parse HEAD:Packages/TimeTugCore/Sources/DedupBenchmark)"
} | tee "$WORK/source-tree-hashes.txt"
git log --format=%H -- $(tr '\n' ' ' < "$WORK/paths.txt") | wc -l | tee "$WORK/expected-commits.txt"
```

Expected: four hashes and a commit count N (about 55). Keep it. The brief's phase 1 experience: `git rev-list --count HEAD` after the rewrite can be larger by retained real merge commits; compare non-merge commits (step 3).

- [ ] **Step 2: Rewrite**

```bash
uvx git-filter-repo --force \
  $(sed 's/^/--path /' "$WORK/paths.txt" | tr '\n' ' ') \
  --path-rename Packages/TimeTugCore/Sources/:Sources/ \
  --path-rename Packages/TimeTugCore/Tests/:Tests/ \
  --path-rename Packages/CalendarBridge/Sources/:Sources/ \
  --path-rename Packages/CalendarBridge/Tests/:Tests/ \
  --message-callback 'return re.sub(rb"\(#([0-9]+)\)", rb"(binary-companion/timetug#\1)", message)'
git branch -m master main
git tag -l | xargs -r git tag -d
for b in $(git branch --format='%(refname:short)' | grep -v '^main$'); do git branch -D "$b"; done
cd "$WORK" && mv extract-src timetug-shared
```

Expected: "Completely finished"; no tags; one branch. Note the two package manifests are deliberately not carried (the new root manifest is written in Task 2); their history stays in `timetug`.

- [ ] **Step 3: Verify nothing was lost**

```bash
cd "$LIB"
ls Sources Tests scripts/benchmarks
git ls-files | grep -vE '^(Sources|Tests)/|^scripts/benchmarks/' || echo "only expected paths"
test "$(git rev-list --no-merges --count HEAD)" -ge "$(( $(cat "$WORK/expected-commits.txt") - 3 ))" && echo COUNT-PLAUSIBLE
git rev-list --no-merges --count HEAD; git rev-list --merges --count HEAD
git ls-files Sources/TimeTugCore | wc -l; git ls-files Sources/CalendarBridge | wc -l; git ls-files Sources/DedupBenchmark | wc -l
git log --follow --format='%ad %s' --date=short -- Sources/TimeTugCore/Store/CalendarStore.swift | tail -1
git log --oneline | grep -c '(binary-companion/timetug#'; git log --format=%B | grep -c '(#[0-9]' || true
```

Expected: `Sources` has `CalendarBridge DedupBenchmark TimeTugCore`, `Tests` has `CalendarBridgeTests TimeTugCoreTests`; only expected paths; the no-merge count within 3 of N (explain any difference in the report: commits that touched only the dropped manifests disappear); 19 files in Core, 2 in Bridge, 1 in the benchmark; the first-commit date 2026-09-18 for a Core file; zero bare `(#N)` left. Then write the post-rewrite hashes and head:

```bash
{ echo "Core.Sources $(git rev-parse HEAD:Sources/TimeTugCore)"; echo "Core.Tests $(git rev-parse HEAD:Tests/TimeTugCoreTests)";
  echo "Bridge.Sources $(git rev-parse HEAD:Sources/CalendarBridge)"; echo "Bridge.Tests $(git rev-parse HEAD:Tests/CalendarBridgeTests)";
  echo "Benchmark $(git rev-parse HEAD:Sources/DedupBenchmark)"; } | tee "$WORK/tree-hashes.txt"
git rev-parse HEAD > "$WORK/t1-head.txt"
```

Expected: the five hashes equal the five in `source-tree-hashes.txt`, line by line (both files compare the inner directories, so they are comparable). `Sources/TimeTugCore` has 19 files; with `DedupBenchmark/main.swift` that is the 20 Core source files of the spec. If any differs, the in-repo copy moved after the clone: re-run from step 1.

- [ ] **Step 4: Record**

No commit. The hashes are compared again in Task 8.

### Task 2: Repository files and the root manifest

**Files:**
- Create in `$LIB`: `Package.swift`, `Package.resolved` (generated), `LICENSE`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `SECURITY.md`, `CODEOWNERS`, `.gitattributes`, `.gitignore`, `.github/dependabot.yml`, `.github/pull_request_template.md`
- Modify in `$LIB`: `scripts/benchmarks/run-dedup.sh`

**Interfaces:**
- Produces: package identity `timetug-shared` (from the repository URL; the manifest `name:` matches); products `TimeTugCore`, `CalendarBridge`; executable `DedupBenchmark`.

- [ ] **Step 1: Manifest and resolved file**

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "timetug-shared",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TimeTugCore", targets: ["TimeTugCore"]),
        .library(name: "CalendarBridge", targets: ["CalendarBridge"]),
    ],
    dependencies: [.package(url: "https://github.com/binary-companion/calendar-connectors", from: "1.0.0")],
    targets: [
        .target(name: "TimeTugCore", dependencies: [.product(name: "CalendarCore", package: "calendar-connectors")]),
        .target(name: "CalendarBridge", dependencies: [
            "TimeTugCore",
            .product(name: "CalendarCore", package: "calendar-connectors"),
        ]),
        .executableTarget(name: "DedupBenchmark", dependencies: [
            "TimeTugCore", .product(name: "CalendarCore", package: "calendar-connectors"),
        ]),
        .testTarget(name: "TimeTugCoreTests", dependencies: [
            "TimeTugCore", .product(name: "CalendarCore", package: "calendar-connectors"),
        ]),
        .testTarget(name: "CalendarBridgeTests", dependencies: [
            "CalendarBridge", "TimeTugCore", .product(name: "CalendarCore", package: "calendar-connectors"),
        ]),
    ]
)
```

```bash
cd "$LIB" && swift package resolve && cat Package.resolved | head -20
swift build --build-tests 2>&1 | tail -3
swift test 2>&1 | tail -4
```

Expected: `Package.resolved` lists `calendar-connectors` at the newest `1.x` (write down the version: it is what the first release records); `Build complete!`; the test run reports Core (301 or more) and Bridge (13) tests passed. Core tests must match the numbers in the in-repo packages at the clone commit (compare with `swift test --package-path Packages/TimeTugCore` in the `timetug` checkout if in doubt).

- [ ] **Step 2: Licence, ignore, attributes, ownership**

`LICENSE`: copy `timetug`'s file and change the one line:

```bash
cd "$LIB"
gh api repos/binary-companion/timetug/contents/LICENSE --jq .content | base64 -d > LICENSE
grep -n '^Software:\|^License:\|Copyright' LICENSE
sed -i '' 's/^Software: TimeTug$/Software: timetug-shared/' LICENSE
grep -n '^Software:' LICENSE
```

Expected: `Software: timetug-shared`, `License: MIT`, and the copyright line with Binary Companion LLC (if the copied file names another holder, stop and report). Then:

`.gitattributes`: `* text=auto eol=lf`. `.gitignore`: `.build/`, `.swiftpm/`, `build/`, `.DS_Store`, `.serena/` (one per line; **not** `Package.resolved`). `CODEOWNERS`: `* @darkarena1`. `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
  - package-ecosystem: swift
    directory: /
    schedule:
      interval: weekly
```

`.github/pull_request_template.md`: copy the library's (`fetch_cc .github/pull_request_template.md`). `SECURITY.md`: copy the library's and replace `calendar-connectors` with `timetug-shared`; read it once and delete any sentence that does not apply.

- [ ] **Step 3: README, AGENTS.md, CLAUDE.md, benchmark script**

`README.md`:

```markdown
# timetug-shared

The platform-neutral logic of [TimeTug](https://github.com/binary-companion/timetug): `TimeTugCore` (the calendar store, duplicate resolution, takeover scheduling, agenda and widget snapshot) and `CalendarBridge` (the adapter between the connector library and Core). Pure Swift on top of [calendar-connectors](https://github.com/binary-companion/calendar-connectors); it builds and is tested on macOS, Linux, Windows x64 and Windows ARM64.

## Use

```swift
.package(url: "https://github.com/binary-companion/timetug-shared", from: "1.0.0")
```

Products: `TimeTugCore`, `CalendarBridge`. Core never reads the clock: callers pass `now: Date`.

## Releases

Every merge to `main` publishes a version tag (`X.Y.Z`) and a GitHub release. The pull request's `semver:major`, `semver:minor` or `semver:patch` label chooses the bump; patch is the default. Release notes record the `calendar-connectors` version the code was built and tested with. Published tags are immutable.

## License

MIT with the Commons Clause (no selling the software). See [LICENSE](LICENSE).
```

`CLAUDE.md`: `See @AGENTS.md.`. `AGENTS.md` (then append the sections of `~/.agents/skills/add-code-indexing/templates/agents-section.md`, replacing the placeholders with `main` and "Swift; run `swift build --build-tests` first so sourcekit-lsp has an index"):

```markdown
# timetug-shared agent guide

## What this is

The portable logic shared by every TimeTug front end: `TimeTugCore` and `CalendarBridge` (and, in later phases, the engine and its C interface). It imports only Foundation, `CalendarCore` (from `calendar-connectors`) and its own modules, and builds on macOS, Linux and Windows. UI, Apple frameworks and platform adapters never live here.

## Repositories

- `calendar-connectors`: the connector library. This repository depends on it by version range and commits `Package.resolved`.
- `timetug-shared` (this repository): released as `X.Y.Z` tags.
- `timetug`: the Mac app; pins this repository exactly in `Apps/macOS/project.yml`.
- `timetug-windows` (later): the WinUI app.

Dependency direction: `calendar-connectors` <- `timetug-shared` <- the apps.

## Rules

- Core never reads the clock (`now: Date` is passed in); the architecture check enforces it. Test each behaviour with Swift Testing, failing test first.
- Allowed imports: Core `Foundation CalendarCore TimeTugCore Testing`; Bridge adds nothing else. `scripts/ci/check-architecture.sh` enforces it.
- `Package.resolved` is changed only by `scripts/ci/bump-resolved.py` (the bump workflow) or by `swift package update` in a reviewed pull request.

## Verify

`swift test` (macOS, Linux and Windows run in CI), `scripts/ci/check-architecture.sh`, `scripts/ci/check-repository-contracts.py`, the tests under `scripts/ci/tests` and `scripts/release/tests`.

## Release flow

Do not tag by hand. A merge to `main` runs `release.yml`: the `semver:*` labels pick the bump, the workflow tags and publishes, then notifies `timetug`, which opens a "Bump timetug-shared to X.Y.Z" pull request. The agent never merges or publishes; the owner does.
```

`scripts/benchmarks/run-dedup.sh` becomes:

```sh
#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
swift run -c release --package-path "$repo_dir" DedupBenchmark "$@"
```

- [ ] **Step 4: Check and commit**

```bash
cd "$LIB"
swift build 2>&1 | tail -2
chmod +x scripts/benchmarks/run-dedup.sh
git add -A && git commit -m "Add the root manifest, license and repository files

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected: `Build complete!`.

### Task 3: The version script and its tests

**Files:**
- Create in `$LIB`: `scripts/release/next-version.sh`, `scripts/release/tests/test-next-version.sh`, `scripts/release/tests/test-release-version-step.sh`

**Interfaces:**
- Produces: `scripts/release/next-version.sh --latest <X.Y.Z|""> --labels <comma list> [--override <X.Y.Z>]` (exit 0 version, 2 bad input, 3 no tag and no override).

- [ ] **Step 1: Copy and run**

```bash
cd "$LIB"
for f in scripts/release/next-version.sh scripts/release/tests/test-next-version.sh scripts/release/tests/test-release-version-step.sh; do
  mkdir -p "$(dirname "$f")"; fetch_cc "$f"; chmod +x "$f"
done
scripts/release/tests/test-next-version.sh
```

Expected: `PASS`. (These files are the library's own tested copies; they do not mention the library by name. If `test-release-version-step.sh` names `release.yml` jobs or the `notify` job's `repositories:` value, they are adjusted in Task 6, where the workflow is written.)

- [ ] **Step 2: Commit**

```bash
git add scripts/release && git commit -m "Add the version script and its tests (copied from calendar-connectors main)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 4: Guards (architecture and contracts)

**Files:**
- Create in `$LIB`: `scripts/ci/check-architecture.sh`, `scripts/ci/tests/test-check-architecture.sh`, `scripts/ci/check-repository-contracts.py`, `scripts/ci/tests/test_check_repository_contracts.py`, `scripts/ci/requirements-test.txt`, `scripts/ci/select-xcode.sh`

**Interfaces:**
- Produces: `check-architecture.sh [root]` (exit 1 with `path:line: message`), `check-repository-contracts.py [root]` (exit 1 with `FAIL:` lines on stderr).

- [ ] **Step 1: Architecture test first**

`scripts/ci/tests/test-check-architecture.sh` (bash, no PyYAML):

```bash
#!/usr/bin/env bash
# Tests check-architecture.sh: the repository passes, a fixture passes, each rule catches its violation.
set -euo pipefail
cd "$(dirname "$0")/../../.."
S="$PWD/scripts/ci/check-architecture.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
"$S" >/dev/null || { "$S" >&2; fail "the repository itself violates the rules"; }

mkdir -p "$T/Sources/TimeTugCore" "$T/Sources/CalendarBridge" "$T/Sources/DedupBenchmark" "$T/Tests/TimeTugCoreTests" "$T/Tests/CalendarBridgeTests"
printf '// swift-tools-version: 6.0\nlet package = Package(name: "x", dependencies: [.package(url: "https://github.com/binary-companion/calendar-connectors", from: "1.0.0")], targets: [])\n' > "$T/Package.swift"
printf '@preconcurrency import CalendarCore\nimport Foundation\nimport struct Foundation.Date\nfunc f(now: Date) -> Date { now }\n' > "$T/Sources/TimeTugCore/A.swift"
printf 'import CalendarCore\nimport Foundation\nimport TimeTugCore\n' > "$T/Sources/CalendarBridge/A.swift"
printf 'import Foundation\nimport TimeTugCore\n' > "$T/Sources/DedupBenchmark/main.swift"
printf 'import Testing\n@testable import TimeTugCore\n' > "$T/Tests/TimeTugCoreTests/T.swift"
printf 'import Testing\n@testable import CalendarBridge\n' > "$T/Tests/CalendarBridgeTests/T.swift"
out="$("$S" "$T")" || fail "clean fixture rejected: $out"

# expect <file> <content> <message substring>
expect() {
  local f="$T/$1" had=0 out
  [ -e "$f" ] && { had=1; cp "$f" "$f.orig"; }
  mkdir -p "$(dirname "$f")"; printf '%b' "$2" > "$f"
  if out="$("$S" "$T" 2>/dev/null)"; then fail "accepted $1 containing: $2"; fi
  case "$out" in *"$3"*) ;; *) fail "for $1 expected '$3' in: $out" ;; esac
  if [ "$had" = 1 ]; then mv "$f.orig" "$f"; else rm "$f"; fi
}
C=Sources/TimeTugCore/X.swift
expect "$C" 'import AppKit\n' "TimeTugCore may not import AppKit"
expect "$C" 'public import AppKit\n' "TimeTugCore may not import AppKit"
expect "$C" '@testable import CalendarBridge\n' "TimeTugCore may not import CalendarBridge"
expect "$C" 'import GoogleCalendar\n' "TimeTugCore may not import GoogleCalendar"
expect "$C" 'let t = Date()\n' "reads the clock"
expect "$C" 'if Date.now > x {}\n' "reads the clock"
expect "$C" 'let t = Date(timeIntervalSinceNow: 5)\n' "reads the clock"
expect Tests/TimeTugCoreTests/X.swift 'import EventKit\n' "TimeTugCore may not import EventKit"
expect Sources/CalendarBridge/X.swift 'import SwiftUI\n' "CalendarBridge may not import SwiftUI"
expect Sources/CalendarBridge/X.swift 'import CalendarOAuth\n' "CalendarBridge may not import CalendarOAuth"
expect Package.swift 'let package = Package(dependencies: [.package(url: "https://github.com/x/y", from: "1.0.0")])\n' \
  "may not depend on https://github.com/x/y"
expect Package.swift 'let package = Package(dependencies: [.package(path: "../CalendarConnectors")])\n' \
  "may not depend on ../CalendarConnectors"
expect Package.swift 'let package = Package(platforms: [], targets: [.target(name: "x", condition: .when(platforms: [.macOS]))])\n' \
  "platform conditions (.when)"
printf 'let t = Date() // architecture-check: allow (wall clock for logging only)\n' > "$T/$C"
"$S" "$T" >/dev/null || fail "allow marker ignored"
echo PASS
```

Run `chmod +x … && scripts/ci/tests/test-check-architecture.sh` — Expected: FAIL (script missing).

- [ ] **Step 2: Implement `check-architecture.sh`**

```bash
#!/usr/bin/env bash
# Layering rules the compiler does not enforce. Usage: scripts/ci/check-architecture.sh [repo-root]
# Prints "path:line: message" per violation and exits 1 if there are any.
set -euo pipefail
cd "${1:-$(dirname "$0")/../..}"
bad=0
report() { echo "$1: $2"; bad=$((bad + 1)); }
has() { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }

PREFIX='(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+|(public|package|internal|fileprivate|private)[[:space:]]+)*'
imports() {
  local p existing=()
  for p in "$@"; do [ -e "$p" ] && existing+=("$p"); done
  [ ${#existing[@]} -gt 0 ] || return 0
  grep -rnE --include='*.swift' "^[[:space:]]*${PREFIX}import[[:space:]]" "${existing[@]}" |
    sed -E "s/^([^:]+:[0-9]+):[[:space:]]*${PREFIX}import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\1 \7/" || true
}
only() {
  local label="$1" allowed="$2" loc mod; shift 2
  while read -r loc mod; do
    has "$allowed" "$mod" || report "$loc" "$label may not import $mod (allowed: $allowed)"
  done < <(imports "$@")
}

# Core is platform-neutral and builds on Linux and Windows: Foundation and the connector model only.
only TimeTugCore "Foundation CalendarCore TimeTugCore Testing" Sources/TimeTugCore Tests/TimeTugCoreTests
# The bridge is minimal glue between Core and the library.
only CalendarBridge "Foundation TimeTugCore CalendarCore CalendarBridge Testing" Sources/CalendarBridge Tests/CalendarBridgeTests
only DedupBenchmark "Foundation CalendarCore TimeTugCore" Sources/DedupBenchmark

# Time is passed in: Core never reads the clock. Mark a justified exception with "architecture-check: allow".
if [ -d Sources/TimeTugCore ]; then
  while IFS= read -r hit; do
    report "$(echo "$hit" | cut -d: -f1,2)" "TimeTugCore reads the clock (Date()/Date.now); pass now: Date in instead"
  done < <(grep -rn --include='*.swift' 'Date' Sources/TimeTugCore | grep -v 'architecture-check: allow' |
    sed -E -e 's#^([^:]+:[0-9]+:)[[:space:]]*//.*#\1#' -e 's#[[:space:]]//.*##' |
    grep -E '^[^:]+:[0-9]+:(.*[^A-Za-z0-9_])?Date(\(\)|\.now([^A-Za-z0-9_]|$)|\(timeIntervalSinceNow)' || true)
fi

# One package dependency, the connector library by URL; no platform conditions.
if [ -f Package.swift ]; then
  LIBURL=https://github.com/binary-companion/calendar-connectors
  while IFS= read -r dep; do
    line="$(grep -nF "\"$dep\"" Package.swift | head -1 | cut -d: -f1)"
    [ "$dep" = "$LIBURL" ] || report "Package.swift:${line:-1}" "timetug-shared may not depend on $dep (allowed: $LIBURL)"
  done < <(tr '\n' ' ' < Package.swift | grep -oE '\.package\([^)]*\)' |
    sed -E 's/.*(path|url):[[:space:]]*"([^"]*)".*/\2/' || true)
  grep -n '\.when' Package.swift | grep -v '^[0-9]*:[[:space:]]*//' | while IFS=: read -r n _; do
    echo "Package.swift:$n: platform conditions (.when) are not allowed"
  done > "${TMPDIR:-/tmp}/arch-when.$$" || true
  if [ -s "${TMPDIR:-/tmp}/arch-when.$$" ]; then
    cat "${TMPDIR:-/tmp}/arch-when.$$"; bad=$((bad + $(wc -l < "${TMPDIR:-/tmp}/arch-when.$$")))
  fi
  rm -f "${TMPDIR:-/tmp}/arch-when.$$"
fi

[ "$bad" = 0 ] || { echo "$bad architecture violation(s)" >&2; exit 1; }
```

- [ ] **Step 3: Run it to see it pass**

Run: `chmod +x scripts/ci/check-architecture.sh && scripts/ci/tests/test-check-architecture.sh`
Expected: `PASS`; `scripts/ci/check-architecture.sh` on the real tree prints nothing.

- [ ] **Step 4: Contracts guard (copy, then trim to this repository)**

```bash
cd "$LIB"
for f in scripts/ci/check-repository-contracts.py scripts/ci/tests/test_check_repository_contracts.py scripts/ci/requirements-test.txt scripts/ci/select-xcode.sh; do
  mkdir -p "$(dirname "$f")"; fetch_cc "$f"
done
chmod +x scripts/ci/select-xcode.sh
```

Edit `check-repository-contracts.py`: delete the library-specific sections (the manifest target-line checks, the Microsoft scope and write-capability checks, the Google capability checks and the `PORTABLE` import loop over library target names). Keep the workflow rules block (no `pull_request_target`, secrets only inside environments except the allowed three, whole-context and `secrets: inherit` forms, composite actions, required `ci.yml` and `release.yml`). Add one rule in place of the deleted import loop: every Swift file under `Sources/TimeTugCore` and `Sources/CalendarBridge` has no import of `AppKit SwiftUI UIKit EventKit WidgetKit FoundationModels Security CryptoKit Network Combine` (same import regex as the workflow guard's sibling in the library, including attributes, access levels and kind keywords). In `test_check_repository_contracts.py` delete the tests of the removed sections, keep every workflow-rule test unchanged, and replace the fixture's `Sources/CalendarCore` and Microsoft/Google files with `Sources/TimeTugCore/A.swift` (`import Foundation`) and `Sources/CalendarBridge/A.swift`; add two tests: an `import AppKit` in `Sources/TimeTugCore` fails with `Apple/UI import`, an `@preconcurrency import SwiftUI` in `Sources/CalendarBridge` fails likewise.

```bash
uv run --with PyYAML==6.0.3 python -m unittest discover -s scripts/ci/tests -p 'test_*.py' 2>&1 | tail -3
uv run --with PyYAML==6.0.3 python scripts/ci/check-repository-contracts.py
```

Expected: `OK`, then `PASS: repository contracts` (the workflows do not exist yet: the existence requirement for `ci.yml` and `release.yml` is satisfied in Task 6, so run the real-tree check again there; in this task it may report them missing — that is the only allowed failure).

Fix the header comment of `select-xcode.sh` if it names the app. Do not edit the guard logic beyond this trimming.

- [ ] **Step 5: Commit**

```bash
git add scripts/ci && git commit -m "Add the architecture and repository-contract checks

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 5: Windows toolchain probe and install script

**Files:**
- Create in `$LIB`: `scripts/ci/install-swift-windows.ps1`, `scripts/ci/swift-windows-version.txt`
- Create (temporary, deleted at the end of this task): `.github/workflows/windows-probe.yml`

**Interfaces:**
- Produces: `scripts/ci/install-swift-windows.ps1` — installs the Swift toolchain pinned in `swift-windows-version.txt` on `windows-latest` and `windows-11-arm`, verifies its SHA-256, exports `PATH`, `SDKROOT` and any other variables the toolchain needs through `$GITHUB_PATH`/`$GITHUB_ENV`, and finishes with `swift --version` and a one-file compile check. Exit non-zero on any failure.

Third-party setup actions are not allowed, and nothing is known about the runners' Swift or winget availability. This task therefore starts with a probe on the real runners and records its findings; the script is written from them.

- [ ] **Step 0: Create the repository and push `main`**

The Windows runners are only reachable from GitHub, so the repository is created now (Task 7 step 1 then only adds its settings). Nothing can be released yet: there is no workflow and no tag.

```bash
gh repo create "$R" --public --description "Portable core logic of TimeTug: TimeTugCore and CalendarBridge" --homepage "https://timetug.binarycompanion.com"
cd "$LIB" && git remote add origin "https://github.com/$R.git" && git push -u origin main
```

- [ ] **Step 1: Probe workflow**

`.github/workflows/windows-probe.yml` (temporary; it lives only on branches named `probe/**`, never on `main`; a push event runs it from the branch, which a `workflow_dispatch` workflow could not do before it exists on the default branch):

```yaml
name: Windows probe
on:
  push:
    branches: ['probe/**']
permissions:
  contents: read
jobs:
  probe:
    strategy:
      matrix:
        os: [windows-latest, windows-11-arm]
    runs-on: ${{ matrix.os }}
    steps:
      - shell: pwsh
        run: |
          $PSVersionTable.PSVersion
          [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
          Get-Command swift -ErrorAction SilentlyContinue | Format-List
          Get-Command winget -ErrorAction SilentlyContinue | Format-List
          Get-Command cl, link, clang -ErrorAction SilentlyContinue | Format-Table Name, Source
          Get-ChildItem 'C:\Program Files\Microsoft Visual Studio' -ErrorAction SilentlyContinue | Select-Object Name
          Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\Include' -ErrorAction SilentlyContinue | Select-Object Name
          git --version; python --version
```

- [ ] **Step 2: Decide the install route**

Run the probe: commit the workflow on a branch `probe/windows` and push it (`git switch -c probe/windows && git add -A && git commit -m probe && git push origin probe/windows`); the push starts both jobs; read both logs. Choose, in this order, the first route that works on **both** runners:
1. `winget install --id Swift.Toolchain --version <v> --silent --accept-package-agreements --accept-source-agreements` (Spike S used it on a VM);
2. direct download of the installer from `download.swift.org` for the pinned version and architecture, `Get-FileHash -Algorithm SHA256` compared with the pinned value, silent install (`/quiet`);
3. fail the task and report: no third-party action may be added.
Record the exact commands, the versions, the install duration and what the runner image already provides (Visual Studio Build Tools, Windows SDK) in the report. `swift-windows-version.txt` holds the pinned version (start from `6.4.0`, the version of Spike S, unless the probe shows a newer stable release is the only one installable) and, for route 2, one line per architecture `x64 <sha256>` / `arm64 <sha256>` obtained from the first download and cross-checked against the checksum or signature file swift.org publishes next to the installer, if any (say so in the report).

- [ ] **Step 3: Write the script and prove it on a hello package**

`scripts/ci/install-swift-windows.ps1` follows the recorded route. Required behaviour, each with a message on failure: read the pinned version; detect the architecture; install (retrying three times with 15 and 30 second pauses); verify the hash for route 2; locate the toolchain bin and runtime directories and append them to `$env:GITHUB_PATH`; export `SDKROOT` and any variable `swift build` needed in the probe to `$env:GITHUB_ENV`; run `swift --version` and compile a one-line program with `swiftc`; `exit 1` on any non-zero exit code (`$LASTEXITCODE` is checked after every native command; the script uses `$ErrorActionPreference = 'Stop'`). It prints the toolchain's version and the architecture last.

Prove it: add a `hello` job to the probe workflow that runs the script, then in a following step (a new step, so the exported environment is visible) runs `swift --version` and builds and runs a one-target package created with `swift package init --type executable`. Run it on both runners; both must pass.

- [ ] **Step 4: Canary (Review Focus 1)**

In the same probe job add a final pair of steps: create a package with one Swift Testing test that fails, run `swift test` in a step with `continue-on-error: false` and confirm the **job is red**; then a package with one passing test and confirm the log shows the executed test count. Record both run URLs in the report. This demonstrates that the shell wrapper propagates failures.

- [ ] **Step 5: Remove the probe and commit on `main`**

Iterate on the script on the `probe/windows` branch (each push re-runs the probe). When both jobs are green and the canary behaves, bring only the two script files back to `main`:

```bash
git switch main
git checkout probe/windows -- scripts/ci/install-swift-windows.ps1 scripts/ci/swift-windows-version.txt
git push origin --delete probe/windows
git add scripts/ci/install-swift-windows.ps1 scripts/ci/swift-windows-version.txt
git commit -m "Add the Windows Swift install script and the pinned toolchain version

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 6: Workflows and the code index

**Files:**
- Create in `$LIB`: `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `.github/workflows/index.yml`, `.qindexignore`, `scripts/dev/qindex.py`

**Interfaces:**
- Produces: required job ids `macos`, `linux`, `windows-x64`, `windows-arm64`, `architecture`; workflow `Release` with job `publish` (output `version`) and job `notify`.

- [ ] **Step 1: `ci.yml`**

Start from the library's file and add the two Windows jobs:

```bash
mkdir -p .github/workflows && fetch_cc .github/workflows/ci.yml
```

Edit: change the header comment to list the five jobs; replace every `swift test` in `macos` and the container command in `linux` with `swift test --force-resolved-versions` (so a stale `Package.resolved` fails); in `architecture` keep the steps (`scripts/ci/tests/test-check-architecture.sh`, `scripts/release/tests/test-next-version.sh`, `PYTHON=... scripts/release/tests/test-release-version-step.sh`, unit tests) and add the bump script tests created in Task 13 later. Add:

```yaml
  windows-x64:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
      - name: Install Swift
        shell: pwsh
        run: scripts/ci/install-swift-windows.ps1
      - name: Test
        shell: pwsh
        run: |
          swift test --force-resolved-versions 2>&1 | Tee-Object -FilePath test.log
          if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
          $count = (Select-String -Path test.log -Pattern 'Test run with (\d+) tests').Matches |
            ForEach-Object { [int]$_.Groups[1].Value } | Measure-Object -Sum
          Write-Host "Executed tests: $($count.Sum)"
          if ($count.Sum -lt 280) { Write-Error 'fewer tests ran than on macOS'; exit 1 }

  windows-arm64:
    runs-on: windows-11-arm
    steps:
      # identical steps to windows-x64
```

The threshold `280` is a floor: about 90 % of the macOS count (Core 301 plus Bridge 13 = 314 today, counted from Swift Testing's `Test run with N tests` summary lines). Re-derive it from the count printed in Task 2 step 1 and say so in a comment, so a silently skipped target turns the job red. If the summary line differs on Windows, adapt the pattern to the real log; the failure mode to prevent is "zero tests ran".

- [ ] **Step 2: `release.yml`**

```bash
fetch_cc .github/workflows/release.yml
```

Edit: header comment "Releases the library" becomes "Releases timetug-shared"; in `notify`, `repositories: timetug` stays and the loop `for dependent in timetug` stays, but the payload becomes `client_payload[library]=timetug-shared` (replace the `calendar-connectors` string). After the `Create the tag and the release` step add a step that records the connector version:

```yaml
      - name: Record the connector version in the release notes
        if: steps.version.outputs.version != ''
        env:
          GH_TOKEN: ${{ github.token }}
          VERSION: ${{ steps.version.outputs.version }}
        run: |
          set -euo pipefail
          cc="$(python3 scripts/ci/resolved-version.py Package.resolved calendar-connectors)"
          body="$(gh release view "$VERSION" --json body --jq .body)"
          printf '%s\n\nBuilt and tested with calendar-connectors %s.\n' "$body" "$cc" > "$RUNNER_TEMP/notes.md"
          gh release edit "$VERSION" --notes-file "$RUNNER_TEMP/notes.md"
```

`scripts/ci/resolved-version.py <file> <identity>` prints the `version` of the pin with that identity and exits 1 if absent (written in Task 13, with tests; until then `release.yml` is not exercised, so write the script now as a stub that is replaced in Task 13 only if that task finds it wrong: implement it fully here, it is 15 lines).

`scripts/ci/resolved-version.py`:

```python
#!/usr/bin/env python3
"""Prints the resolved version of one pin of a Package.resolved file. Usage: resolved-version.py FILE IDENTITY"""
import json
import sys

path, identity = sys.argv[1], sys.argv[2]
with open(path) as handle:
    data = json.load(handle)
for pin in data.get("pins", []):
    if pin.get("identity") == identity:
        print(pin["state"]["version"])
        sys.exit(0)
print(f"no pin {identity} in {path}", file=sys.stderr)
sys.exit(1)
```

Add a unit test `scripts/ci/tests/test_resolved_version.py` (found pin; missing pin exits 1; v2 and v3 file shapes) — test first.

- [ ] **Step 3: Code index**

```bash
mkdir -p scripts/dev
cp ~/.agents/skills/index/scripts/qindex.py scripts/dev/qindex.py
sed 's/__DEFAULT_BRANCH__/main/g' ~/.agents/skills/add-code-indexing/templates/index.yml > .github/workflows/index.yml
cp ~/.agents/skills/add-code-indexing/templates/qindexignore .qindexignore
printf 'docs/superpowers/plans/\n' >> .qindexignore
cmp scripts/dev/qindex.py ~/.agents/skills/index/scripts/qindex.py && echo script-identical
```

The template pins `actions/checkout`, `actions/cache` and `actions/upload-artifact` by tag; replace those three `uses:` lines with the SHA pins from Global Constraints (library's `index.yml` shows the exact form). `grep -n 'uses:' .github/workflows/*.yml` must show only 40-hex refs.

- [ ] **Step 4: Local checks and commit**

```bash
uv run --with PyYAML==6.0.3 python -m unittest discover -s scripts/ci/tests -p 'test_*.py' 2>&1 | tail -2
uv run --with PyYAML==6.0.3 python scripts/ci/check-repository-contracts.py
for f in .github/workflows/*.yml; do python3 -c "import yaml,sys; yaml.safe_load(open('$f'))" && echo "$f ok"; done
actionlint 2>/dev/null || echo "actionlint not installed"
git add -A && git commit -m "Add CI, release and code index workflows

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected: `OK`; `PASS: repository contracts`; three `ok` lines.

### Task 7: Publish, bring up Windows, release 1.0.0, protect

**Files:** none (GitHub settings and the first pushes).

**Interfaces:**
- Consumes: Tasks 1 to 6.
- Produces: `binary-companion/timetug-shared` with tag `1.0.0`, rulesets, environments `publish` and `bump`, labels.

Creating the repository and its protections is the agent's job here, as for `calendar-connectors`. Nothing is merged or approved.

- [ ] **Step 1: Push the workflows and set the repository up**

The repository exists since Task 5 step 0.

```bash
cd "$LIB" && git push origin main
gh api -X PATCH "repos/$R" -F has_wiki=false -F has_projects=false -F delete_branch_on_merge=true -F allow_auto_merge=true --jq '.full_name'
for l in semver:major semver:minor semver:patch; do gh label create "$l" --repo "$R" --color BFD4F2 2>/dev/null || true; done
```

Expected: the push succeeds (it starts CI and the first Release run); `binary-companion/timetug-shared`.

- [ ] **Step 2: Environments and Docker Hub secret visibility**

```bash
for env in publish bump; do
  gh api -X PUT "repos/$R/environments/$env" --input - <<'JSON'
{"can_admins_bypass": false, "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
  gh api -X POST "repos/$R/environments/$env/deployment-branch-policies" -f name=main -f type=branch --jq .name
done
ID="$(gh api "repos/$R" --jq .id)"
for s in DOCKERHUB_USERNAME DOCKERHUB_TOKEN; do
  gh api -X PUT "orgs/binary-companion/actions/secrets/$s/repositories/$ID" && echo "$s visible to $R"
done
```

Expected: `main` twice, two `visible to` lines. A 403/404 on the PUT means the token lacks `admin:org`: the owner adds the repository to both secrets in the organization settings; the `linux` job pulls anonymously meanwhile.

- [ ] **Step 3: Windows bring-up and the rest of CI on `main`**

The first push started CI. Watch it:

```bash
RUN="$(gh run list --repo "$R" --workflow CI --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$RUN" --repo "$R" --exit-status || true
gh run view "$RUN" --repo "$R" --json jobs --jq '.jobs[]|[.name,.conclusion]|@tsv'
```

Expected: `macos`, `linux` and `architecture` succeed. `windows-x64` and `windows-arm64` may fail on the first runs: **this is the phase's real risk** (x64 was never run; Foundation differences). For each failure read the log, fix the cause in `$LIB`, push to `main` (no rulesets exist yet and there are no consumers) and re-run, until all five jobs are green on one commit. Allowed fixes: install script, workflow, test skips with a stated reason (`.enabled(if:)` or `#if os(Windows)` on a single test with a comment naming the cause), and source changes that are needed for Windows only if they change no behaviour on macOS (the macOS and Linux jobs must stay green). A source change is called out in the report and in Task 8's tree comparison. If a failure is not understood after three attempts, stop and report (do not skip tests to get green).

- [ ] **Step 4: The extraction push released nothing**

```bash
gh run list --repo "$R" --workflow Release --limit 1 --json conclusion,status --jq '.[0]'
git ls-remote --tags origin
```

Expected: the Release run succeeded (notice: no tag yet), and no tags exist.

- [ ] **Step 5: Release 1.0.0 (only with five green jobs on the tagged commit)**

```bash
HEAD_SHA="$(git rev-parse origin/main)"
gh run list --repo "$R" --workflow CI --commit "$HEAD_SHA" --json name,conclusion,status --limit 1 --jq '.[0]'
gh api "repos/$R/commits/$HEAD_SHA/check-runs" --jq '.check_runs[]|[.name,.conclusion]|@tsv' | sort
gh workflow run release.yml --repo "$R" --ref main -f version=1.0.0
sleep 5
RUN="$(gh run list --repo "$R" --workflow Release --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$RUN" --repo "$R" --exit-status
git fetch --tags -q && git tag -l && gh release view 1.0.0 --repo "$R" --json tagName,isDraft,isPrerelease,body --jq .
git rev-parse 1.0.0:Sources/TimeTugCore 1.0.0:Tests/TimeTugCoreTests 1.0.0:Sources/CalendarBridge 1.0.0:Tests/CalendarBridgeTests
```

Expected: the check list shows `macos`, `linux`, `windows-x64`, `windows-arm64`, `architecture` all `success` on `HEAD_SHA` **before** the dispatch (if not, stop); tag `1.0.0`; the release is not a draft and not a prerelease; its body ends with "Built and tested with calendar-connectors X.Y.Z"; the four tree hashes equal `$WORK/tree-hashes.txt` unless Step 3 changed a source file (then record which and why). The `notify` job of this run is expected to be red: the `bump` environment of the new repository holds no key yet (the owner deleted the key file; Task 14 step 2 stores it). Note it in the report and do not re-run; the dispatch it would have sent (`library=timetug-shared`) matches no handler in `timetug` until Task 12 and would be ignored anyway.

- [ ] **Step 6: Rulesets**

```bash
cat > "$WORK/ruleset-main.json" <<'JSON'
{"name":"Protect main","target":"branch","enforcement":"active",
 "conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},
 "bypass_actors":[],
 "rules":[
  {"type":"deletion"},{"type":"non_fast_forward"},
  {"type":"pull_request","parameters":{"required_approving_review_count":0,"dismiss_stale_reviews_on_push":true,
    "require_code_owner_review":false,"require_last_push_approval":false,"required_review_thread_resolution":false,
    "allowed_merge_methods":["squash","merge","rebase"]}},
  {"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,"do_not_enforce_on_create":false,
    "required_status_checks":[{"context":"macos"},{"context":"linux"},{"context":"windows-x64"},{"context":"windows-arm64"},{"context":"architecture"}]}}]}
JSON
cat > "$WORK/ruleset-tags.json" <<'JSON'
{"name":"Protect version tags","target":"tag","enforcement":"active",
 "conditions":{"ref_name":{"include":["refs/tags/*"],"exclude":[]}},
 "bypass_actors":[],
 "rules":[{"type":"update"},{"type":"deletion"},{"type":"non_fast_forward"}]}
JSON
for f in main tags; do gh api -X POST "repos/$R/rulesets" --input "$WORK/ruleset-$f.json" --jq '"\(.id) \(.name)"'; done
```

- [ ] **Step 7: Prove the controls**

```bash
git commit --allow-empty -qm probe && git push origin HEAD:main 2>&1 | tail -2; git reset -q --hard origin/main
gh api -X DELETE "repos/$R/git/refs/tags/1.0.0" 2>&1 | head -2
(cd /Users/scottobryan/Source/timetug && scripts/security/audit-github.sh --strict binary-companion timetug-shared 2>&1 | tail -8)
```

Expected: the push is rejected (`GH013`); the tag deletion is refused; the audit ends `0 failed, 0 skipped`. If the tag deletion **succeeds**, re-run Release with `version=1.0.0` (main has not moved), fix the ruleset and repeat. (`timetug-shared` is already in the audit script's `TAG_RULESET_REPOS` list.)

---

## Part B: the flip pull request in `timetug`

Work in a worktree on a fresh branch from `origin/master`:

```bash
git fetch -q origin && git switch -c claude/phase-2-flip origin/master
```

### Task 8: Switch to the released package

**Files:**
- Modify: `Packages/AppleIntelligenceInference/Package.swift`, `Apps/macOS/project.yml`
- Delete: `Packages/TimeTugCore/`, `Packages/CalendarBridge/`, `scripts/benchmarks/run-dedup.sh`

**Interfaces:**
- Consumes: tag `1.0.0` of `timetug-shared`.
- Produces: dependency `.package(url: "https://github.com/binary-companion/timetug-shared", from: "1.0.0")`, product references `package: "timetug-shared"`; `project.yml` package key `TimeTugShared` with `url` and `exactVersion: 1.0.0`.

- [ ] **Step 1: The freeze check**

Clone the tag and compare tree hashes by path:

```bash
D="$(mktemp -d)" && git clone -q --depth 1 --branch 1.0.0 https://github.com/binary-companion/timetug-shared "$D/ts"
for t in "Sources/TimeTugCore Packages/TimeTugCore/Sources/TimeTugCore" \
         "Tests/TimeTugCoreTests Packages/TimeTugCore/Tests/TimeTugCoreTests" \
         "Sources/CalendarBridge Packages/CalendarBridge/Sources/CalendarBridge" \
         "Tests/CalendarBridgeTests Packages/CalendarBridge/Tests/CalendarBridgeTests" \
         "Sources/DedupBenchmark Packages/TimeTugCore/Sources/DedupBenchmark"; do
  set -- $t
  a="$(git -C "$D/ts" rev-parse HEAD:$1)"; b="$(git rev-parse origin/master:$2)"
  [ "$a" = "$b" ] && echo "$1: identical" || echo "$1: DIFFERS"
done
```

Expected: five `identical`. A `DIFFERS` is allowed only for a path the report of Task 7 step 3 named (a Windows-only fix); otherwise a change landed in the in-repo copy after extraction: port it to `timetug-shared` through a pull request there, release, and use the new version below instead of `1.0.0`.

- [ ] **Step 2: Manifest and project.yml**

`Packages/AppleIntelligenceInference/Package.swift`: replace `.package(path: "../TimeTugCore")` with `.package(url: "https://github.com/binary-companion/timetug-shared", from: "1.0.0")` and every `.product(name: "TimeTugCore", package: "TimeTugCore")` with `.product(name: "TimeTugCore", package: "timetug-shared")`.

`Apps/macOS/project.yml`: replace the two entries

```yaml
  TimeTugCore:
    path: ../../Packages/TimeTugCore
  CalendarBridge:
    path: ../../Packages/CalendarBridge
```

with

```yaml
  TimeTugShared:
    url: https://github.com/binary-companion/timetug-shared
    exactVersion: 1.0.0
```

and change every `- package: TimeTugCore` and `- package: CalendarBridge` in the target dependency lists to `- package: TimeTugShared` (the `product:` lines keep `TimeTugCore` / `CalendarBridge`).

```bash
git grep -n 'package: TimeTugCore\|package: CalendarBridge' -- Apps Packages || echo none
git rm -rq Packages/TimeTugCore Packages/CalendarBridge scripts/benchmarks/run-dedup.sh
```

- [ ] **Step 3: Build and test against the release**

```bash
swift test --package-path Packages/AppleIntelligenceInference 2>&1 | tail -3
swift test --package-path Packages/EventKitSource 2>&1 | tail -3
swift test --package-path Packages/CalendarApple 2>&1 | tail -3
xcodegen generate --spec Apps/macOS/project.yml
xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | tail -5
git status --short | grep -v '^D  Packages/\(TimeTugCore\|CalendarBridge\)/\|^D  scripts/benchmarks'
```

Expected: suites pass; `** TEST SUCCEEDED **` (307 tests, as before); the last command lists only the manifest and `project.yml`. If SwiftPM reports an unknown package, check the manifest `name:` of the released tag.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "Consume timetug-shared 1.0.0 by released version

TimeTugCore and CalendarBridge moved to binary-companion/timetug-shared with
their history. AppleIntelligenceInference depends on it by URL with a 1.0.0
floor and the app pins exactVersion 1.0.0. No source changes: the Sources
trees of the released tag equal the ones removed here.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 9: Generalize the pin tooling to two libraries (TDD)

**Files:**
- Modify: `scripts/ci/check-shared-pins.py`, `scripts/ci/tests/test_check_shared_pins.py`, `scripts/ci/bump-pin.sh`, `scripts/ci/tests/test-bump-pin.sh`
- Create: `scripts/dev/use-local-library.sh`, `scripts/dev/tests/test-use-local-library.sh`, `scripts/ci/resolved-version.py`, `scripts/ci/tests/test_resolved_version.py`
- Modify: `scripts/dev/use-local-connectors.sh` (becomes a wrapper), `scripts/dev/tests/test-use-local-connectors.sh`

**Interfaces:**
- Produces: `check-shared-pins.py [root]` — enforces every phase 1 rule for each of `calendar-connectors` (key `CalendarConnectors`) and `timetug-shared` (key `TimeTugShared`); `bump-pin.sh [--at-least] <library> <X.Y.Z> [repo-root]`; `use-local-library.sh <calendar-connectors|timetug-shared> <path> | --restore [--force]`; `resolved-version.py FILE IDENTITY` (the file from Task 6).

- [ ] **Step 1: Failing tests for the pin check**

In `test_check_shared_pins.py` every fixture's `project.yml` gains a `TimeTugShared` entry with `url: https://github.com/binary-companion/timetug-shared` and `exactVersion: 1.0.0`. Then add (each must fail on the current script):
- a project without the `TimeTugShared` entry fails naming `TimeTugShared`;
- a `TimeTugShared` entry with `path:` added, with `branch:`, with a wrong url, with `exactVersion: 1.0`, each fails;
- a second key `Whatever` with url `https://github.com/binary-companion/Timetug-Shared.git` fails ("names the shared library") and with path `../../../timetug-shared` fails;
- a manifest `.package(path: "../../../timetug-shared")` fails; `.package(url: ".../timetug-shared", from: "1.0.0")` passes; a floor above the `TimeTugShared` pin fails; a pin in another major fails — each repeated for the existing library so the protections are proven per library;
- a sibling directory named `timetug-shared` or `TimeTugShared` under `Packages/` is not a valid sibling;
- `localPackages` entry pointing at either library fails.

Run: `uv run --with PyYAML==6.0.3 python -m unittest scripts/ci/tests/test_check_shared_pins.py` — Expected: the new tests FAIL, the old ones pass.

- [ ] **Step 2: Implement**

In `check-shared-pins.py` change the table to

```python
LIBRARIES = {  # repository slug -> project.yml package key
    'calendar-connectors': 'CalendarConnectors',
    'timetug-shared': 'TimeTugShared',
}
```

The rest of the file is already written over `LIBRARIES` and `LIBRARY_NAMES`; fix the three places that assume one library: the `released` loop at the manifest scan keeps the matching `slug` (initialise `matched = None`, set it inside the loop, use it after), the messages that say "the library" name the library, and the docstring lists both. Re-run the unit tests until green; the old tests keep passing.

- [ ] **Step 3: `bump-pin.sh` for a library argument, with `--at-least` (test first)**

Extend `scripts/ci/tests/test-bump-pin.sh`: the fixture project has both entries; cases: `bump-pin.sh timetug-shared 1.2.3` moves only the `TimeTugShared` pin (the connector pin and Sparkle untouched), floors of the other library untouched; `bump-pin.sh calendar-connectors 1.0.1` as before; `bump-pin.sh 1.0.1` (a bare version) is refused with a usage message; unknown library refused; `--at-least calendar-connectors 1.0.0` when the pin is `1.0.2` exits 0 and changes nothing; `--at-least calendar-connectors 1.0.5` raises to `1.0.5`; `--at-least` never lowers; a major bump of one library raises that library's floors only; `check-shared-pins.py` passes on every result. See the new cases fail, then edit `bump-pin.sh`: parse `[--at-least] <library> <version>`; derive `URL=https://github.com/binary-companion/$library` and the project key from the table (`calendar-connectors`→`CalendarConnectors`, `timetug-shared`→`TimeTugShared`, anything else exit 2); in the downgrade branch exit 0 quietly when `--at-least` was given and the current pin is at least the version; keep every other rule. Print `<library> pinned at <version> (was <current>)`.

- [ ] **Step 4: `use-local-library.sh` and the wrapper (test first)**

`scripts/dev/tests/test-use-local-library.sh` is `test-use-local-connectors.sh` parameterized by library: for each of the two libraries build the throwaway repo, run `use-local-library.sh <library> "$T/<library>"` with a checkout directory named exactly `<library>`, assert the manifests and `project.yml` entry are redirected, `check-shared-pins.py` fails, `--restore` is clean; refusals (wrong directory name, missing directory, unknown library, second override, `--restore` with edits) as in the existing test. Then create `scripts/dev/use-local-library.sh` from `use-local-connectors.sh`: take the library as first argument, derive the manifest URL pattern and the `project.yml` key from the table, use the backup directory `build/local-library-backup`, otherwise the same logic (hash guard, `--force`). Replace `use-local-connectors.sh` with a three-line wrapper: `exec "$(dirname "$0")/use-local-library.sh" calendar-connectors "$@"` (and `--restore` passes through). The existing `test-use-local-connectors.sh` must still pass unchanged (the backup path assertion, if any, follows the new directory).

- [ ] **Step 5: `resolved-version.py` (copied) and run everything**

```bash
gh api "repos/binary-companion/timetug-shared/contents/scripts/ci/resolved-version.py?ref=1.0.0" --jq .content | base64 -d > scripts/ci/resolved-version.py
gh api "repos/binary-companion/timetug-shared/contents/scripts/ci/tests/test_resolved_version.py?ref=1.0.0" --jq .content | base64 -d > scripts/ci/tests/test_resolved_version.py
chmod +x scripts/ci/resolved-version.py
uv run --with PyYAML==6.0.3 python -m unittest scripts/ci/tests/test_check_shared_pins.py scripts/ci/tests/test_resolved_version.py 2>&1 | tail -3
scripts/ci/tests/test-bump-pin.sh; scripts/dev/tests/test-use-local-library.sh; scripts/dev/tests/test-use-local-connectors.sh
python3 scripts/ci/check-shared-pins.py
```

Expected: all pass (the real tree after Task 8 has both entries; `python3` needs PyYAML on PATH — use a venv).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Generalize the pin tooling to two shared libraries

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 10: Rework the guards that named the moved packages

**Files:**
- Modify: `scripts/ci/check-architecture.sh`, `scripts/ci/tests/test-check-architecture.sh`, `scripts/ci/check-repository-contracts.py`, `scripts/dev/verify.sh`, `scripts/dev/tests/test-verify.sh`, `scripts/dev/tests/test-affected-tests.sh`, `.github/workflows/ci.yml`, `scripts/dev/affected-tests.sh` (only if a hard-coded name appears)

**Interfaces:**
- Consumes: Task 8 manifests, Task 9 tooling.

- [ ] **Step 1: Architecture test first (must fail against the old script)**

In `scripts/ci/tests/test-check-architecture.sh`: the `pkg` helper accepts URL dependencies (as in the phase 1 flip); delete the fixture packages `TimeTugCore` and `CalendarBridge` and every `expect` line that targets `Packages/TimeTugCore` or `Packages/CalendarBridge`; the remaining fixtures are `EventKitSource` (`LIB`), `CalendarApple` (`LIB`) and `AppleIntelligenceInference` (`SHARED LIB`) where `LIB=https://github.com/binary-companion/calendar-connectors` and `SHARED=https://github.com/binary-companion/timetug-shared`; add `expect Packages/AppleIntelligenceInference/Package.swift 'let package = Package(dependencies: [.package(path: "../TimeTugCore")])\n' "may not depend on ../TimeTugCore"` and the same for an unknown URL. Run — Expected: FAIL.

- [ ] **Step 2: `check-architecture.sh`**

Remove the `only TimeTugCore …` and `only CalendarBridge …` rules and the Core clock-rule block (they live in `timetug-shared` now); add `SHAREDURL=https://github.com/binary-companion/timetug-shared` beside `LIBURL`; `allowed_deps`:

```bash
allowed_deps() {
  case "$1" in
    EventKitSource | CalendarApple) echo "$LIBURL" ;;
    AppleIntelligenceInference) echo "$SHAREDURL $LIBURL" ;;
    *) return 1 ;;
  esac
}
```

Keep the Foundation Models, Sparkle, Widgets and Apps rules. `never` lists that name `TimeTugCore CalendarBridge` stay (adapters still must not import them). Run the test — Expected: `PASS`.

- [ ] **Step 3: Repository contracts, `verify.sh`, `ci.yml`, wrapper tests**

`check-repository-contracts.py`: the Core import loop reads `Packages/TimeTugCore/Sources` — delete that loop and the `EventKitSource` checks stay. `verify.sh`: remove `Packages/TimeTugCore/*|Packages/CalendarBridge/*` from the `affected` mapping (the `AppleIntelligenceInference` line keeps setting `WANT_CORE=1; WANT_APP=1`, and manifest or `project.yml` edits still set `WANT_CONTRACTS=1`), remove `run_pkg core Packages/TimeTugCore` and `run_pkg bridge Packages/CalendarBridge` and their `skip_check` names; keep `inference`. `test-verify.sh` and `test-affected-tests.sh`: replace the Core and Bridge cases with `AppleIntelligenceInference`, `CalendarApple` and a manifest case (the fixture copies the real manifests; local dependencies are `.package(path:)` entries only, so no package depends on another locally any more). `ci.yml`: header comment lists the remaining jobs; in `core` delete the `Test TimeTugCore` and `Test CalendarBridge` steps; delete the whole `core-linux` job and its mention in the header and in comments (Core is tested on Linux in its own repository). Check the live required-check list so nothing required disappears:

```bash
gh api repos/binary-companion/timetug/rules/branches/master --jq '[.[]|select(.type=="required_status_checks")|.parameters.required_status_checks[].context]'
```

Expected: no `core-linux` in the list (the owner's pending item to add it is dropped by this phase; if it was added meanwhile, stop and tell the owner to remove it before merging the flip PR).

- [ ] **Step 4: Run the affected checks and commit**

```bash
scripts/ci/tests/test-check-architecture.sh; scripts/dev/tests/test-verify.sh; scripts/dev/tests/test-affected-tests.sh
scripts/ci/tests/test-workflows.sh; python3 scripts/ci/check-repository-contracts.py; python3 scripts/ci/check-shared-pins.py
git add -A && git commit -m "Rework the guards for packages that live in timetug-shared

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected: every command prints `PASS` (PyYAML on PATH).

### Task 11: Documents, ADR, tracker, and the flip pull request

**Files:**
- Modify: `AGENTS.md`, `CONTRIBUTING.md`, `README.md`, `docs/architecture.md`, `docs/development.md`, `docs/development/runbooks/operations.md`, `.github/pull_request_template.md`, `docs/decisions/0001-swift-and-native-stack.md` and `0002-core-source-app-boundaries.md` (cross-reference lines only), `.agents/skills/working-across-timetug-repos/SKILL.md`, `docs/superpowers/plans/2026-10-09-windows-program-tracker.md`
- Create: `docs/decisions/0020-timetug-shared-repository.md`

- [ ] **Step 1: Find and rewrite references**

```bash
git grep -n -E 'Packages/(TimeTugCore|CalendarBridge)|core-linux|run-dedup' -- . ':!docs/superpowers/plans' ':!docs/superpowers/specs' ':!docs/reviews' ':!docs/decisions'
```

Rewrite each hit: a path to a moved package becomes a pointer to `https://github.com/binary-companion/timetug-shared` (`Sources/TimeTugCore/...`, `Sources/CalendarBridge/...`); `AGENTS.md` Boundaries: the Core bullet says Core lives in `timetug-shared` (rules unchanged: pass `now: Date`, no Apple imports, test first), the Repositories section lists `timetug-shared` as live, and the interim-rule wording covers both libraries (use `use-local-library.sh`); `docs/development.md` and the operations runbook: package tests for Core and Bridge run in `timetug-shared`; the dedup benchmark is run from a `timetug-shared` checkout (`scripts/benchmarks/run-dedup.sh`). The skill `working-across-timetug-repos` gets a short section "A change in Core or Bridge": library PR in `timetug-shared`, label, automatic release, bump PR in `timetug` that also raises the connector pin; local override with `use-local-library.sh timetug-shared <path>`; do not tell the reader the chain is live for `timetug-shared` bump PRs until Task 15 has proven it (use the word "planned" for that sentence only, and the tracker lists it).

- [ ] **Step 2: ADR and tracker**

`docs/decisions/0020-timetug-shared-repository.md`: Context (the Windows program needs the portable logic in a repository the Windows app can depend on), Decision (the two packages moved with history to `binary-companion/timetug-shared`, MIT plus Commons Clause; the Mac app pins it; Windows CI there), Consequences (a Core change is a pull request in another repository plus a bump pull request; local override script), links to the phase 2 spec and ADR 0012. Tracker: phase 2 row `in progress: spec (PR 106), repository published as 1.0.0 (date), flip PR open`, plan link, session log line, owner checklist items (add the repository to the `timetug-bot` installation; merge the flip PR; the Docker Hub secret visibility if the API denied it).

- [ ] **Step 3: Full verification, push, pull request**

```bash
scripts/dev/verify.sh all 2>&1 | tail -12
git add -A && git commit -m "Point the documents at timetug-shared; add ADR 0020 and the tracker update

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git push -u origin claude/phase-2-flip
gh pr create --repo binary-companion/timetug --base master --head claude/phase-2-flip \
  --title "Consume timetug-shared 1.0.0 from its own repository" --body-file <(cat <<'EOF'
## What

Phase 2 of the Windows program. `TimeTugCore` and `CalendarBridge` now live in https://github.com/binary-companion/timetug-shared (history preserved, released as 1.0.0, tested on macOS, Linux, Windows x64 and Windows ARM64). This pull request makes `timetug` consume it by released version.

## Verification

`scripts/dev/verify.sh all` passed locally; CI runs against the released package. The `Sources` and `Tests` trees of the package are identical to the ones removed here (checked by tree hash; any difference is listed below).

## Not here

The bump loop for `timetug-shared` (its workflow, the notify job and the generalized `bump-dependencies.yml`) follows in separate pull requests.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)
```

Before the owner merges: `git fetch origin` and repeat Task 8 step 1 against `origin/master`; if the in-repo copy changed, port the change first. Stop for the owner's review and merge.

---

## Part C: the automatic chain

### Task 12: `timetug`'s bump workflow for two libraries (TDD)

**Files:**
- Modify: `.github/workflows/bump-dependencies.yml`, `scripts/ci/tests/test-bump-workflow-step.sh`, `scripts/ci/tests/check-workflow-contracts.py`

**Interfaces:**
- Consumes: `bump-pin.sh [--at-least] <library> <X.Y.Z>`, `resolved-version.py`.
- Produces: `repository_dispatch` `library-released` with `client_payload.library` in {`calendar-connectors`, `timetug-shared`}; branches `bump/<library>-X.Y.Z`; titles `Bump <library> to X.Y.Z`.

- [ ] **Step 1: Failing harness cases**

Extend `test-bump-workflow-step.sh` (it extracts the real step and runs it with stub `git`/`gh`): parameterize by `LIBRARY`; new cases — (a) library `timetug-shared`, version `1.0.0`, with the stub returning a `Package.resolved` whose `calendar-connectors` pin is `1.0.4` while the project pins `1.0.2` → the commit contains both pins moved and the PR title is `Bump timetug-shared to 1.0.0`; (b) recorded version below the current pin (`1.0.1` vs `1.0.2`) → the connector pin is not lowered; (c) open PRs `bump/calendar-connectors-1.0.3` and `bump/timetug-shared-0.9.0` with new `timetug-shared 1.0.0` that raised the connector pin to `1.0.4` → the connector PR (≤ 1.0.4) and the older `timetug-shared` PR are closed with `Superseded by #N`, nothing else; (d) cross-repo head names never close anything (existing); (e) payload `library=other` → the job `if` skips (assert on the YAML). See them fail.

- [ ] **Step 2: Implement**

In the workflow: `on.repository_dispatch.types: [library-released]`; `workflow_dispatch` inputs `library` (type choice: `calendar-connectors`, `timetug-shared`) and `version`; job `if: github.event_name == 'workflow_dispatch' || contains(fromJSON('["calendar-connectors","timetug-shared"]'), github.event.client_payload.library)`; `env: LIBRARY: ${{ github.event.client_payload.library || inputs.library }}` and `VERSION` as before; `concurrency.group: bump-${{ github.event.client_payload.library || inputs.library }}`; the move step becomes

```yaml
      - name: Move the pin
        run: |
          set -euo pipefail
          scripts/ci/bump-pin.sh "$LIBRARY" "$VERSION"
          if [ "$LIBRARY" = timetug-shared ]; then
            gh api "repos/binary-companion/timetug-shared/contents/Package.resolved?ref=$VERSION" --jq .content | base64 -d > "$RUNNER_TEMP/shared.resolved"
            recorded="$(scripts/ci/resolved-version.py "$RUNNER_TEMP/shared.resolved" calendar-connectors)"
            scripts/ci/bump-pin.sh --at-least calendar-connectors "$recorded"
          fi
        env:
          GH_TOKEN: ${{ steps.app.outputs.token }}
```

(The step also writes `echo "RECORDED=$recorded" >> "$GITHUB_ENV"`, so the supersede step knows the raised connector pin.) Branch `bump/$LIBRARY-$VERSION`; commit and title `Bump $LIBRARY to $VERSION`; release notes from `gh release view "$VERSION" --repo "binary-companion/$LIBRARY"`; supersede step: close same-repository open PRs whose head is exactly `bump/$LIBRARY-<lower version>`, and, when `LIBRARY=timetug-shared` and `RECORDED` is set, also `bump/calendar-connectors-<v>` with `v <= RECORDED`; each close independent as today. In `check-workflow-contracts.py` keep `'bump-dependencies.yml': 'bump'` and add assertions: the token step still has exactly the two `permission-*` inputs, no merge calls, trigger types `[library-released]`.

- [ ] **Step 3: Run and commit**

```bash
scripts/ci/tests/test-bump-workflow-step.sh; scripts/ci/tests/test-workflows.sh; scripts/ci/tests/test-bump-pin.sh
actionlint .github/workflows/bump-dependencies.yml 2>/dev/null || true
git add -A && git commit -m "Open bump pull requests for timetug-shared as well, carrying the connector pin

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected: all `PASS`; open a pull request (`claude/phase-2-bump-workflow`), not merged by the agent.

### Task 13: `timetug-shared`'s bump workflow and `Package.resolved` script (TDD)

**Files:**
- Create in `$LIB` (branch `claude/bump-workflow` from `origin/main`, pull request): `scripts/ci/bump-resolved.py`, `scripts/ci/tests/test_bump_resolved.py`, `scripts/ci/tests/test-bump-workflow-step.sh`, `.github/workflows/bump-dependencies.yml`
- Modify: `.github/workflows/ci.yml` (run the new tests), `.github/workflows/release.yml` only if the notify payload needs it (it does not), `scripts/ci/tests/check-workflow-contracts` equivalent: `scripts/ci/check-repository-contracts.py` already requires environments for secrets

**Interfaces:**
- Produces: `bump-resolved.py <slug> <X.Y.Z> <40-hex-revision> [file]`; workflow `Bump dependencies` reacting to `library-released` with `library == calendar-connectors`.

- [ ] **Step 1: Failing unit tests**

`test_bump_resolved.py` uses a fixture shaped like a real SwiftPM `Package.resolved` (version 3, two spaces before and after the colon as SwiftPM writes it: `"identity" : "calendar-connectors"`), with one pin `calendar-connectors` at `1.0.1` and a revision; and a `Package.swift` fixture with `from: "1.0.0"`. Cases: moving to `1.0.4` with a new revision changes exactly the `revision` and `version` text of that pin and nothing else (byte-for-byte equal outside those two values); same version again is a no-op with exit 0; a lower version exits 2 and leaves the file; a major change (`2.0.0` while the floor is `1.0.0`) exits 2 with "needs a manual change"; a malformed version, a revision that is not 40 lowercase hex characters, an unknown slug, and a missing file each exit 2 with the file untouched; `originHash` and the other pins are unchanged. See them fail (script missing).

- [ ] **Step 2: Implement `bump-resolved.py`**

```python
#!/usr/bin/env python3
"""Moves one pin of Package.resolved to a released version. Usage: bump-resolved.py SLUG X.Y.Z REVISION [FILE]

Edits the text of the pin's `revision` and `version` values only (SwiftPM's own formatting and `originHash`
stay as they are; CI proves the result with `swift test --force-resolved-versions`). Refuses a downgrade and a
change of major relative to the `from:` floor in Package.swift next to FILE.
"""
import re
import sys
from pathlib import Path

SEMVER = re.compile(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
REVISION = re.compile(r'^[0-9a-f]{40}$')


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(2)


def as_tuple(text):
    return tuple(int(part) for part in text.split('.'))


def main(argv):
    if len(argv) not in (4, 5):
        fail('usage: bump-resolved.py SLUG X.Y.Z REVISION [FILE]')
    slug, version, revision = argv[1:4]
    path = Path(argv[4] if len(argv) == 5 else 'Package.resolved')
    if not SEMVER.match(version):
        fail(f'not X.Y.Z: {version}')
    if not REVISION.match(revision):
        fail(f'not a 40-character lowercase hex revision: {revision}')
    if not path.is_file():
        fail(f'{path} not found')
    text = path.read_text()
    pin = re.search(r'\{[^{}]*"identity"\s*:\s*"%s"[^{}]*\{[^{}]*\}[^{}]*\}' % re.escape(slug), text, re.S)
    if not pin:
        fail(f'no pin {slug} in {path}')
    block = pin.group(0)
    current = re.search(r'"version"\s*:\s*"([^"]+)"', block)
    if not current or not SEMVER.match(current.group(1)):
        fail(f'pin {slug} has no X.Y.Z version')
    if as_tuple(version) < as_tuple(current.group(1)):
        fail(f'refusing to move {slug} back from {current.group(1)} to {version}')
    manifest = path.parent / 'Package.swift'
    if manifest.is_file():
        floor = re.search(r'url:\s*"[^"]*/%s"\s*,\s*from:\s*"(\d+)\.' % re.escape(slug), manifest.read_text())
        if floor and int(floor.group(1)) != as_tuple(version)[0]:
            fail(f'{slug} {version} is in another major than from: {floor.group(1)}.x; this needs a manual change')
    new_block = re.sub(r'("revision"\s*:\s*")[0-9a-f]+(")', r'\g<1>%s\g<2>' % revision, block)
    new_block = re.sub(r'("version"\s*:\s*")[^"]+(")', r'\g<1>%s\g<2>' % version, new_block)
    path.write_text(text.replace(block, new_block, 1))
    print(f'{slug} resolved at {version} (was {current.group(1)})')


main(sys.argv)
```

Run the unit tests — Expected: `OK`.

- [ ] **Step 3: The workflow (harness first)**

`scripts/ci/tests/test-bump-workflow-step.sh` is the copy of `timetug`'s harness (`gh api repos/binary-companion/timetug/contents/scripts/ci/tests/test-bump-workflow-step.sh --jq .content | base64 -d`) adapted: library fixed at `calendar-connectors`, no `--at-least`, the step under test is this repository's `Move the pin` plus `Open the pull request` steps. Cases: new connector version → `bump-resolved.py` called with the tag's revision (stub `gh api repos/binary-companion/calendar-connectors/git/ref/tags/1.0.5` returning a lightweight tag and, for an annotated tag, the dereference through `git/tags/<sha>`); idempotence cases and the supersede cases of `timetug`'s harness for `bump/calendar-connectors-*`; cross-repo heads ignored. See it fail, then write `.github/workflows/bump-dependencies.yml` as `timetug`'s file with: `repositories: timetug-shared` on the token step; trigger `library-released`; job `if` on `client_payload.library == 'calendar-connectors'` (and `workflow_dispatch` input `version`); checkout `ref: main`; the move step

```yaml
      - name: Move the pin
        env:
          GH_TOKEN: ${{ steps.app.outputs.token }}
        run: |
          set -euo pipefail
          ref="$(gh api "repos/binary-companion/calendar-connectors/git/ref/tags/$VERSION" --jq '.object|[.type,.sha]|@tsv')"
          type="${ref%%$'\t'*}"; sha="${ref##*$'\t'}"
          if [ "$type" = tag ]; then sha="$(gh api "repos/binary-companion/calendar-connectors/git/tags/$sha" --jq .object.sha)"; fi
          python3 scripts/ci/bump-resolved.py calendar-connectors "$VERSION" "$sha"
```

then the open-PR and supersede steps as in `timetug` with branch/title `Bump calendar-connectors to $VERSION` and `--base main`. Environment `bump` (exists), per-job `permissions: contents: read`, token `permission-contents: write` + `permission-pull-requests: write`, commit identity `timetug-bot[bot]` / `342080999+timetug-bot[bot]@users.noreply.github.com`.

- [ ] **Step 4: Wire into CI, test, open the pull request**

Add the new unit tests and harness to the `architecture` job of `ci.yml`; run everything locally (unit tests with PyYAML, harness, `actionlint`); commit; push the branch; `gh pr create --repo $R --base main --title "Add the bump workflow and the Package.resolved script"` with label `semver:patch`, body ending with the 🤖 line. Not merged by the agent. Merging it releases `1.0.1` and starts the first notify (see Task 14).

### Task 14: Notify lists, installation, secrets (owner step first)

**Files:** in `calendar-connectors` (branch `claude/notify-timetug-shared`): `.github/workflows/release.yml`, `scripts/release/tests/test-release-version-step.sh`.

- [ ] **Step 1 (owner): install the bot on `timetug-shared`.** Organization settings > GitHub Apps > `timetug-bot` > Configure > repository access: add `timetug-shared`. The agent cannot do this.

- [ ] **Step 2 (agent): secrets.** After the owner confirms, store the variable and secret in `timetug-shared`'s `bump` environment from the owner's key file (a new key file only if the owner generated one; otherwise the same key the library repositories use, provided as a path — never ask for the value in chat):

```bash
gh variable set BUMP_APP_ID --env bump --repo $R --body "$APP_ID"
gh secret set BUMP_APP_PRIVATE_KEY --env bump --repo $R < "$KEY_FILE"
gh variable list --env bump --repo $R; gh secret list --env bump --repo $R
```

Expected: the variable and the secret are listed (names only).

- [ ] **Step 3: Library notify list (test first).** In `test-release-version-step.sh` the notify assertions pin `repositories: timetug` and the loop `for dependent in timetug`; change them to expect `timetug,timetug-shared` and `for dependent in timetug timetug-shared` and see them fail on the current workflow; then edit `release.yml` (`repositories: timetug,timetug-shared`, the loop) and add an assertion that the payload `library` stays `calendar-connectors`. Pull request with label `semver:patch`; the pull request body says that merging it must wait until Steps 1 and 2 are done, because the first dispatch to `timetug-shared` would otherwise fail with 404.

### Task 15: The drill

- [ ] **Step 1:** Merge order (owner): the Task 13 pull request in `timetug-shared`, the Task 12 pull request in `timetug`, then the Task 14 library pull request.
- [ ] **Step 2:** The library's release run publishes a version and `notify` dispatches to both repositories. Expected within a few minutes: a pull request "Bump calendar-connectors to X.Y.Z" in `timetug` and another in `timetug-shared` (`gh pr list --repo $R --search "Bump calendar-connectors"`), each with CI running by itself and the `timetug-shared` one green on all five jobs (`macos`, `linux`, `windows-x64`, `windows-arm64`, `architecture`).
- [ ] **Step 3 (owner):** merge the `timetug-shared` bump pull request. Expected: its release workflow publishes `1.0.2` or later with the line "Built and tested with calendar-connectors X.Y.Z" in the notes, and `timetug` receives "Bump timetug-shared to 1.0.x" whose diff moves `TimeTugShared` and, if needed, the `CalendarConnectors` pin to at least X.Y.Z, and which closed the older "Bump calendar-connectors" pull request in `timetug` as superseded. CI on it is green (`core`, `app`, `dmg`, `architecture`, plus whatever the owner requires).
- [ ] **Step 4:** If any link failed, fix it (Task 12 to 14) and repeat with a new docs-only library change; each repeat makes a new patch version.

### Task 16: `calendar-connectors` gets the Windows jobs

**Files:** in `calendar-connectors` (pull request): `.github/workflows/ci.yml`, `scripts/ci/install-swift-windows.ps1`, `scripts/ci/swift-windows-version.txt`

- [ ] **Step 1:** Copy the install script and version file from `timetug-shared` (`gh api repos/binary-companion/timetug-shared/contents/<path>?ref=main`), add the `windows-x64` and `windows-arm64` jobs with the same steps (no resolved file in that repository; plain `swift test`), the same test-count guard with the library's own threshold (measured from its macOS run). Run on a branch; fix Windows failures in the library through the same bring-up loop as Task 7 step 3 (Foundation differences such as XML, networking and file-system paths are the likely causes: skip with a stated reason, never silently).
- [ ] **Step 2:** When both jobs are green, open the pull request (`semver:patch`); the owner merges, then (owner) adds `windows-x64` and `windows-arm64` to the library's `Protect main` required checks. Library and `timetug-shared` now satisfy program design section 7.

### Task 17: Skill, instructions, tracker

**Files:** in `timetug`: `.agents/skills/working-across-timetug-repos/SKILL.md`, `AGENTS.md`, `docs/architecture.md`, tracker; in `timetug-shared`: `AGENTS.md`.

- [ ] **Step 1:** Remove the "planned" wording the flip PR left (Task 11): the skill and `AGENTS.md` state, in present tense and verified by Task 15, that a library release opens bump pull requests in `timetug-shared` and `timetug`, that a `timetug-shared` bump also carries the connector pin, and how to recover a missed dispatch (`gh workflow run "Bump dependencies" -f library=timetug-shared -f version=X.Y.Z` in `timetug`; the same workflow name with `-f version=` in `timetug-shared`).
- [ ] **Step 2:** Tracker: phase 2 `done` with the pull request links; session log; owner checklist items (required checks on `timetug-shared` verified; Windows jobs required on the library; the `core-linux` note closed).
- [ ] **Step 3:** Verify (`scripts/dev/verify.sh affected`, `python3 scripts/ci/check-repository-contracts.py`), commit, open the pull request; the owner merges. Phase 2 is done when: `timetug-shared` is public with `1.0.0` and a passing strict audit, `timetug` builds from the released tag, the Task 15 drill produced both bump pull requests unaided, and the tracker says so.
