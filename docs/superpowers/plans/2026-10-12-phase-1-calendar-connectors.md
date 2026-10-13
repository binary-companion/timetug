# Phase 1: `calendar-connectors` repository Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the connector library out of `timetug` into its own public repository `binary-companion/calendar-connectors` with its history, release it as `1.0.0`, make every merge release automatically, and make `timetug` consume it by pinned release with bump pull requests.

**Architecture:** Three parts. Part A builds the new repository in a scratch clone (history extraction, repository files, version script, guards, workflows) and publishes it. Part B is one flip pull request in `timetug` (URL dependencies, pin contract, reworked guards and docs). Part C adds the `timetug-bot` loop (notify job, bump workflow) and proves it with a docs-only `1.0.1`.

**Tech Stack:** Swift 6.0 / SwiftPM, `git filter-repo` (through `uvx`), GitHub Actions, `gh`, bash, Python 3 with PyYAML 6.0.3, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-12-phase-1-calendar-connectors-design.md`. Parent: `docs/superpowers/specs/2026-10-09-windows-program-design.md` (sections 1 and 8).

## Global Constraints

- License of the new repository: MIT, holder "Binary Companion LLC". `timetug` stays Commons Clause.
- Library tags are plain `X.Y.Z` (no `v`); `v*` tags are the owner-only tags of the app repositories.
- Default branch of the library is `main`; of `timetug`, `master`.
- `CalendarApple`, `EventKitSource` and `AppleIntelligenceInference` stay in `timetug`. The library manifest has no platform conditions and no package dependencies.
- Every repository carries `.gitattributes` with `* text=auto eol=lf`.
- Workflows: every job declares its own `permissions:` (the org default token is read-only); every action is pinned by commit SHA with the tag in a comment; `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7`; `actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510 # v3`; no `pull_request_target`; no secret outside an environment, except `GITHUB_TOKEN` and the read-only `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` organization secrets.
- Environments: `publish` (default branch only, no reviewer, admin bypass off) creates tags and releases with the repository token; `bump` (default branch only, admin bypass off) holds the `timetug-bot` key. The bot is installed on the dependents only (`timetug`), is never a bypass actor and never merges.
- A push event never releases while the library has no `X.Y.Z` tag.
- Version labels: `semver:major`, `semver:minor`, `semver:patch`; highest wins; none means patch.
- `timetug` pins: local manifests `from: "X.Y.Z"`; `Apps/macOS/project.yml` `exactVersion`; no `path`, `branch` or `revision` for a shared library.
- Commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; pull request bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Pull requests are squash-merged by the owner; the agent never merges, publishes releases or approves environments. Never use bare `git stash`.
- Secrets never enter chat, logs or files in the repository. Values from files go into `gh secret set` by file redirection.

## Review Focus

1. **The extraction push runs `release.yml` with no tag.** It must stop with a notice and release nothing. Pinned by `test-next-version.sh` (exit 3 case) and by Task 6 step 5 (the first run is a skip, and no tag exists afterwards).
2. **A pull request with two version labels, none, or a mistyped one** (`semver:Major`, `semver-minor`). Highest valid wins; anything else is patch. Pinned by `test-next-version.sh`.
3. **A history extraction that silently drops a file or leaves old `v*` and `beta-*` tags behind.** Pinned by Task 1's tree-hash and tag checks.
4. **A local path override committed by mistake** (from `use-local-connectors.sh` or by hand). Pinned by `check-shared-pins.py` and its tests.
5. **A library release the app cannot build against.** The bump pull request's CI is the check; Task 13 proves the loop end to end.
6. **The code `1.0.0` ships differs from what `timetug` last built.** Pinned by Task 7's tree comparison before the in-repo copy is deleted, repeated before the owner merges (Task 10 step 5).
7. **`use-local-connectors.sh --restore` throws away an unrelated edit** to a manifest or `project.yml`. Pinned by backing up the exact files it changes and restoring only from that backup (Task 8).

## Deviations from the spec (decided while planning)

1. **No Actions allow-list entry for `actions/create-github-app-token`.** The organization policy already allows GitHub-owned actions; only the commit-SHA pin is needed and is recorded in `docs/development/action-pins.md` (spec sequence step 2).
2. **No Dependabot `swift` ecosystem in `timetug`.** It would raise a manifest `from:` floor above the exact pin and fail `check-shared-pins.py`. The `library-released` dispatch is the mechanism; a missed one is recovered by running the `Bump dependencies` workflow by hand (it has a `workflow_dispatch` input).
3. **No throwaway-tag experiment.** The tag ruleset does not block creation, so the release workflow is unaffected; the rulesets are applied after `1.0.0` exists (Task 6 step 6) and proved by a refused deletion (step 7).
4. **The extraction is pushed straight to `main` by the agent**, before any ruleset exists. The repository is new and has no consumers; everything after goes through pull requests. The report says so.
5. **The freeze check is a command run at flip time and again before merge**, not a CI job: once the in-repo copy is deleted CI has nothing to compare.
6. **The Microsoft read-only scope check moves to the library** with the code it reads (ADR 0017 stays in `timetug`). A library release that widened the scopes would reach the app only through a bump pull request, whose review is the owner's; the library's `AGENTS.md` names the rule.

---

## Part A: the new repository

Scratch locations used below (pick any new empty directory outside every checkout):

```bash
export WORK="$TMPDIR/phase1"            # created in Task 1
export LIB="$WORK/calendar-connectors"  # the extracted repository
export SRC="/Users/scottobryan/Source/timetug"  # the main checkout, only read
```

### Task 1: Extract the history

**Files:** none in `timetug`. Produces `$LIB` (not yet pushed).

**Interfaces:**
- Produces: `$LIB`, a git repository on branch `main` with the library at its root, `docs/api.md`, the library's design and plan documents under `docs/superpowers/`, no tags, no remote.

- [ ] **Step 1: Fresh clone and the path list**

```bash
mkdir -p "$WORK" && cd "$WORK"
git clone --no-local --branch master "$SRC" extract-src
cd extract-src
git remote remove origin
cat > "$WORK/paths.txt" <<'EOF'
Packages/CalendarConnectors/
docs/calendar-connectors-api.md
docs/superpowers/specs/2026-09-20-calendar-connectors-phase1-design.md
docs/superpowers/specs/2026-09-23-calendar-connectors-phase3-design.md
docs/superpowers/specs/2026-09-25-calendar-connectors-phase4-microsoft-design.md
docs/superpowers/specs/2026-09-27-calendar-connectors-phase5-caldav-design.md
docs/superpowers/plans/2026-09-20-calendar-connectors-phase1.md
docs/superpowers/plans/2026-09-23-calendar-connectors-phase3.md
docs/superpowers/plans/2026-09-25-calendar-connectors-phase4-microsoft.md
docs/superpowers/plans/2026-09-27-calendar-connectors-phase5-caldav.md
docs/superpowers/plans/2026-10-06-calendar-connectors-phase6-ical-link.md
EOF
git log --format=%H -- $(sed 's/^/ /' "$WORK/paths.txt" | tr -d '\n') | wc -l | tee "$WORK/expected-commits.txt"
```

Expected: a number N (21 or a little more, because documents add commits). Keep it.

- [ ] **Step 2: Rewrite**

```bash
uvx git-filter-repo --force \
  $(sed 's/^/--path /' "$WORK/paths.txt" | tr '\n' ' ') \
  --path-rename Packages/CalendarConnectors/: \
  --path-rename docs/calendar-connectors-api.md:docs/api.md \
  --message-callback 'return re.sub(rb"\(#([0-9]+)\)", rb"(binary-companion/timetug#\1)", message)'
git branch -m master main
git tag -l | xargs -r git tag -d
for b in $(git branch --format='%(refname:short)' | grep -v '^main$'); do git branch -D "$b"; done
cd "$WORK" && mv extract-src calendar-connectors
```

Expected: filter-repo reports "Completely finished"; `git -C "$LIB" tag -l` is empty; `git -C "$LIB" branch` lists only `main`.

- [ ] **Step 3: Verify nothing was lost**

```bash
cd "$LIB"
test "$(git rev-list --count HEAD)" = "$(cat "$WORK/expected-commits.txt")" && echo COUNT-OK
for d in Sources Tests; do
  a="$(git rev-parse HEAD:$d)"; b="$(git -C "$SRC" rev-parse origin/master:Packages/CalendarConnectors/$d)"
  [ "$a" = "$b" ] && echo "$d identical" || echo "$d DIFFERS"
done
git log --follow --format='%ad %s' --date=short -- Package.swift | tail -1
git log --oneline | head -3
ls
```

Expected: `COUNT-OK`; `Sources identical`; `Tests identical`; the first-commit line dated 2026-09-20; top-level has `Package.swift Sources Tests docs`. If `Sources` or `Tests` differ, the in-repo copy moved after the clone: re-run Task 1 from step 1.

- [ ] **Step 4: Commit nothing; record**

No commit. Write the three hashes you will compare again in Task 7 (`git rev-parse HEAD:Sources HEAD:Tests`) into your notes.

### Task 2: Repository files

**Files:**
- Create in `$LIB`: `LICENSE`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `SECURITY.md`, `CODEOWNERS`, `.gitattributes`, `.gitignore`, `.github/dependabot.yml`, `.github/pull_request_template.md`
- Modify in `$LIB`: `Package.swift`, `docs/api.md`

**Interfaces:**
- Produces: package identity `calendar-connectors` (derived by SwiftPM from the repository URL; dependents write `package: "calendar-connectors"`). The manifest's `name:` is changed to match for consistency.

- [ ] **Step 1: Package name and path references**

```bash
cd "$LIB"
sed -i '' 's/name: "CalendarConnectors",/name: "calendar-connectors",/' Package.swift
sed -i '' 's#Packages/CalendarConnectors/##g; s#Packages/CalendarConnectors#the repository root#g' docs/api.md
grep -rn 'Packages/CalendarConnectors' Package.swift Sources Tests docs/api.md | grep -v LiveTests | grep -v ICloudLiveSmoke || echo clean
```

Expected: `clean`. (The two live-test doc comments show `--package-path Packages/CalendarConnectors`; change them to drop the flag:)

```bash
sed -i '' 's# --package-path Packages/CalendarConnectors##' Tests/ICalSubscriptionTests/LiveTests.swift Tests/CalDAVCalendarTests/ICloudLiveSmokeTests.swift
swift build 2>&1 | tail -2
```

Expected: `Compiling`/`Build complete!`.

- [ ] **Step 2: Licence, ignore and attribute files**

`LICENSE`:

```text
MIT License

Copyright (c) 2026 Binary Companion LLC

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

`.gitattributes`: `* text=auto eol=lf`

`.gitignore`:

```text
.build/
.swiftpm/
build/
.DS_Store
.serena/
```

`CODEOWNERS`: `* @darkarena1`

`.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

`.github/pull_request_template.md`:

```markdown
## What and why

## Version

Add exactly one label before merging; a merge to `main` releases automatically.

- `semver:major`: a breaking change to `docs/api.md`
- `semver:minor`: new API
- `semver:patch`: fixes and documentation (the default when no label is set)
```

`SECURITY.md`: copy `"$SRC/SECURITY.md"` and run `sed -i '' 's#binary-companion/timetug#binary-companion/calendar-connectors#g'` on it; read it once and delete any sentence that is about the TimeTug app rather than the library.

- [ ] **Step 3: README and agent files**

`README.md`:

```markdown
# calendar-connectors

A portable Swift library that reads and writes calendars through Google, Microsoft Graph, CalDAV (including iCloud) and iCalendar links, with one event model and no third-party dependencies. It builds on macOS and Linux and has been built on Windows ARM64.

## Products

`CalendarCore` (model, connector and source protocols, stores, recurrence), `CalendarOAuth` (PKCE and refresh), `GoogleCalendar`, `MicrosoftCalendar`, `ICalendar`, `CalDAVCalendar`, `ICalSubscription`, `CalendarTestSupport`.

## Use

```swift
.package(url: "https://github.com/binary-companion/calendar-connectors", from: "1.0.0")
```

The host supplies what is platform specific by implementing the library's seams: `CredentialStore` (secure storage), `SHA256Hashing`, and the OAuth redirect interaction (browser or sign-in sheet). The contract is [docs/api.md](docs/api.md). [TimeTug](https://github.com/binary-companion/timetug) is the reference host: its `CalendarApple` package implements the seams with Keychain, CryptoKit and a loopback listener.

## Releases

Every merge to `main` publishes a version tag (`X.Y.Z`) and a GitHub release. The pull request's `semver:major`, `semver:minor` or `semver:patch` label chooses the bump; patch is the default. Published tags are immutable.

## License

MIT. See [LICENSE](LICENSE).
```

`CLAUDE.md`: `See @AGENTS.md.`

`AGENTS.md`:

```markdown
# calendar-connectors agent guide

## What this is

The portable calendar connector library used by TimeTug (Mac now, Windows next). It imports nothing from TimeTug and nothing Apple-only, has no package dependencies, and builds on Linux. Platform adapters (Keychain, Network.framework loopback, EventKit, Windows Credential Locker) live in the apps, never here.

## Repositories

- `calendar-connectors` (this repository): the library. Released as `X.Y.Z` tags.
- `timetug-shared` (phase 2): TimeTugCore, CalendarBridge, the engine. Depends on this library by version range.
- `timetug`: the Mac app and the product website. Pins this library exactly in `Apps/macOS/project.yml`.
- `timetug-windows` (later): the WinUI app.

Dependency direction: `calendar-connectors` <- `timetug-shared` <- the apps; `timetug` also depends on this library directly.

## Boundaries

- Allowed imports: Foundation, FoundationNetworking, FoundationXML, Testing and this package's own modules. `scripts/ci/check-architecture.sh` enforces it.
- A new product needs a line in `Package.swift`, tests, and an entry in `docs/api.md`.
- Microsoft sign-in requests read-only scopes (`scripts/ci/check-repository-contracts.py` pins them); widening them is a deliberate, reviewed change.

## Verify

`swift test` (macOS), the Linux container job in CI, `scripts/ci/check-architecture.sh`, `scripts/release/tests/test-next-version.sh`.

## Release flow

Do not tag by hand. Merging a pull request to `main` runs `release.yml`: the `semver:*` label picks the bump, the workflow tags and publishes, and `timetug` receives a "Bump calendar-connectors to X.Y.Z" pull request. Breaking changes to `docs/api.md` need `semver:major`. The agent never merges or publishes; the owner does.
```

Then append the code-index sections: `cat ~/.agents/skills/add-code-indexing/templates/agents-section.md >> AGENTS.md` and replace `__DEFAULT_BRANCH__` with `main` and the language notes with "Swift; run `swift build --build-tests` first so sourcekit-lsp has an index" (edit the appended text by hand).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add repository files: MIT license, README, agent guide, templates

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 3: The version script (TDD)

**Files:**
- Create in `$LIB`: `scripts/release/next-version.sh`, `scripts/release/tests/test-next-version.sh`

**Interfaces:**
- Produces: `scripts/release/next-version.sh --latest <X.Y.Z|""> --labels <comma list> [--override <X.Y.Z>]` printing `X.Y.Z`; exit 0 ok, 2 bad input, 3 no tag and no override.

- [ ] **Step 1: Write the failing test**

`scripts/release/tests/test-next-version.sh`:

```bash
#!/usr/bin/env bash
# Tests scripts/release/next-version.sh.
set -euo pipefail
cd "$(dirname "$0")/../../.."
S=scripts/release/next-version.sh
fail() { echo "FAIL: $*" >&2; exit 1; }
# expect <exit code> <stdout> <args...>
expect() {
  local want_code="$1" want_out="$2" out code=0; shift 2
  out="$("$S" "$@" 2>/dev/null)" || code=$?
  [ "$code" = "$want_code" ] || fail "$*: exit $code, wanted $want_code"
  [ "$out" = "$want_out" ] || fail "$*: printed '$out', wanted '$want_out'"
}
expect 0 1.0.1 --latest 1.0.0 --labels ""
expect 0 1.0.1 --latest 1.0.0 --labels "bug,docs"
expect 0 1.1.0 --latest 1.0.7 --labels "semver:minor"
expect 0 2.0.0 --latest 1.4.9 --labels "semver:major"
expect 0 2.0.0 --latest 1.4.9 --labels "semver:patch,semver:minor,semver:major"
expect 0 1.5.0 --latest 1.4.9 --labels "semver:patch,semver:minor"
expect 0 1.0.1 --latest 1.0.0 --labels "semver:Major,semver-minor,semver:"
expect 0 1.4.10 --latest 1.4.9 --labels ""
expect 0 3.0.0 --latest 1.0.0 --labels "semver:major" --override 3.0.0
expect 0 1.0.0 --latest "" --labels "" --override 1.0.0
expect 3 "" --latest "" --labels "semver:major"
expect 2 "" --latest 01.2.3 --labels ""
expect 2 "" --latest 1.2 --labels ""
expect 2 "" --latest 1.0.0 --labels "" --override v1.0.1
expect 2 "" --latest 1.0.0 --labels "" --bogus x
echo PASS
```

- [ ] **Step 2: Run it to see it fail**

Run: `chmod +x scripts/release/tests/test-next-version.sh && scripts/release/tests/test-next-version.sh`
Expected: FAIL (the script does not exist: `No such file or directory`, reported as `exit 127`).

- [ ] **Step 3: Implement**

`scripts/release/next-version.sh`:

```bash
#!/usr/bin/env bash
# Prints the version a push to main should release.
#
#   next-version.sh --latest <X.Y.Z or ""> --labels <comma-separated PR labels> [--override <X.Y.Z>]
#
# Exit codes: 0 printed a version; 2 bad usage or malformed input; 3 no tag exists and no override
# was given (the extraction push: nothing is released until the first version is dispatched by hand).
set -euo pipefail
set -f
latest="" labels="" override=""
while [ $# -gt 0 ]; do
  case "$1" in
    --latest) latest="${2-}"; shift 2 ;;
    --labels) labels="${2-}"; shift 2 ;;
    --override) override="${2-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
semver='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
if [ -n "$override" ]; then
  [[ "$override" =~ $semver ]] || { echo "override is not X.Y.Z: $override" >&2; exit 2; }
  echo "$override"
  exit 0
fi
if [ -z "$latest" ]; then
  echo "no version tag exists; dispatch the workflow with a version" >&2
  exit 3
fi
[[ "$latest" =~ $semver ]] || { echo "latest tag is not X.Y.Z: $latest" >&2; exit 2; }
major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"
bump=patch
for label in ${labels//,/ }; do
  case "$label" in
    semver:major) bump=major ;;
    semver:minor) [ "$bump" = major ] || bump=minor ;;
  esac
done
case "$bump" in
  major) echo "$((major + 1)).0.0" ;;
  minor) echo "$major.$((minor + 1)).0" ;;
  patch) echo "$major.$minor.$((patch + 1))" ;;
esac
```

- [ ] **Step 4: Run it to see it pass**

Run: `chmod +x scripts/release/next-version.sh && scripts/release/tests/test-next-version.sh`
Expected: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/release && git commit -m "Add the version script and its tests

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 4: Guards (architecture and contracts)

**Files:**
- Create in `$LIB`: `scripts/ci/check-architecture.sh`, `scripts/ci/tests/test-check-architecture.sh`, `scripts/ci/check-repository-contracts.py`, `scripts/ci/tests/test_check_repository_contracts.py`, `scripts/ci/requirements-test.txt`, `scripts/ci/select-xcode.sh`

**Interfaces:**
- Produces: `check-architecture.sh [root]` (exit 1 with `path:line: message`); `check-repository-contracts.py [root]` (exit 1 with `FAIL:` lines).

- [ ] **Step 1: Write the architecture test first**

`scripts/ci/tests/test-check-architecture.sh`:

```bash
#!/usr/bin/env bash
# Tests check-architecture.sh: the repository passes, a fixture passes, each rule catches its violation.
set -euo pipefail
cd "$(dirname "$0")/../../.."
S="$PWD/scripts/ci/check-architecture.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
"$S" >/dev/null || { "$S" >&2; fail "the repository itself violates the rules"; }

mkdir -p "$T/Sources/CalendarCore" "$T/Sources/GoogleCalendar" "$T/Tests/CalendarCoreTests"
printf '// swift-tools-version: 6.0\nlet package = Package(name: "x", targets: [])\n' > "$T/Package.swift"
printf '#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\nimport Foundation\n' > "$T/Sources/CalendarCore/A.swift"
printf '@preconcurrency import CalendarCore\nimport struct Foundation.Date\n' > "$T/Sources/GoogleCalendar/A.swift"
printf 'import Testing\n@testable import CalendarCore\n' > "$T/Tests/CalendarCoreTests/T.swift"
out="$("$S" "$T")" || fail "clean fixture rejected: $out"

expect() { # expect <file> <content> <message substring>
  local f="$T/$1" had=0 out
  [ -e "$f" ] && { had=1; cp "$f" "$f.orig"; }
  mkdir -p "$(dirname "$f")"; printf '%b' "$2" > "$f"
  if out="$("$S" "$T" 2>/dev/null)"; then fail "accepted $1 containing: $2"; fi
  case "$out" in *"$3"*) ;; *) fail "for $1 expected '$3' in: $out" ;; esac
  if [ "$had" = 1 ]; then mv "$f.orig" "$f"; else rm "$f"; fi
}
expect Sources/CalendarCore/X.swift 'import AppKit\n' "may not import AppKit"
expect Sources/CalendarCore/X.swift 'import Security\n' "may not import Security"
expect Sources/GoogleCalendar/X.swift 'import TimeTugCore\n' "may not import TimeTugCore"
expect Sources/GoogleCalendar/X.swift 'import XMLCoder\n' "may not import XMLCoder"
expect Tests/CalendarCoreTests/X.swift 'import CryptoKit\n' "may not import CryptoKit"
expect Package.swift 'let package = Package(dependencies: [.package(url: "https://github.com/x/y", from: "1.0.0")])\n' \
  "has package dependencies"
echo PASS
```

Run: `chmod +x scripts/ci/tests/test-check-architecture.sh && scripts/ci/tests/test-check-architecture.sh` — Expected: FAIL (script missing).

- [ ] **Step 2: Implement `check-architecture.sh`**

```bash
#!/usr/bin/env bash
# The library imports nothing from TimeTug and nothing Apple-only, and has no package dependencies,
# so it builds on Linux and Windows. Usage: scripts/ci/check-architecture.sh [repo-root]
# Prints one "path:line: message" per violation and exits 1 if there are any.
set -euo pipefail
cd "${1:-$(dirname "$0")/../..}"
bad=0
report() { echo "$1: $2"; bad=$((bad + 1)); }
has() { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }

MODULES="$(ls Sources 2>/dev/null | tr '\n' ' ')"
ALLOWED="Foundation FoundationNetworking FoundationXML Testing $MODULES"
while read -r loc mod; do
  [ -n "${mod:-}" ] || continue
  has "$ALLOWED" "$mod" || report "$loc" "the library may not import $mod (allowed: $ALLOWED)"
done < <(grep -rnE --include='*.swift' '^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*import[[:space:]]' Sources Tests 2>/dev/null |
  sed -E 's/^([^:]+:[0-9]+):[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\1 \6/' || true)

if line="$(grep -n '\.package(' Package.swift | head -1)" && [ -n "$line" ]; then
  report "Package.swift:${line%%:*}" "the library has package dependencies (it must have none)"
fi

[ "$bad" = 0 ] || { echo "$bad architecture violation(s)" >&2; exit 1; }
```

- [ ] **Step 3: Run it to see it pass**

Run: `chmod +x scripts/ci/check-architecture.sh && scripts/ci/tests/test-check-architecture.sh`
Expected: `PASS`.

- [ ] **Step 4: Contracts test first**

`scripts/ci/requirements-test.txt`: `PyYAML==6.0.3`. `scripts/ci/select-xcode.sh`: copy `"$SRC/scripts/ci/select-xcode.sh"` unchanged.

`scripts/ci/tests/test_check_repository_contracts.py`:

```python
import subprocess, sys, tempfile, unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'check-repository-contracts.py'
GOOD_SCOPES = '''let scopes = ["Calendars.Read", "Calendars.Read.Shared", "MailboxSettings.Read"]\n'''
GOOD_SOURCE = 'canWrite: true, canEditAttendees: true\n'
CI = '''name: CI
on: [pull_request]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo "${{ secrets.GITHUB_TOKEN }}${{ secrets.DOCKERHUB_TOKEN }}"
'''

def make(root: Path, **overrides):
    files = {
        'Package.swift': '.target(name: "CalendarCore")\n.target(name: "CalendarOAuth", dependencies: ["CalendarCore"])\n'
                         '.target(name: "GoogleCalendar", dependencies: ["CalendarCore", "CalendarOAuth"])\n'
                         '.target(name: "MicrosoftCalendar", dependencies: ["CalendarCore", "CalendarOAuth"])\n',
        'Sources/CalendarCore/A.swift': 'import Foundation\n',
        'Sources/MicrosoftCalendar/MicrosoftConnectorKind.swift': GOOD_SCOPES,
        'Sources/MicrosoftCalendar/MicrosoftCalendarSource.swift': GOOD_SOURCE,
        'Sources/MicrosoftCalendar/MicrosoftCalendarSource+Write.swift': 'extension MicrosoftCalendarSource: WritableCalendarSource {}\n',
        'Sources/GoogleCalendar/GoogleCalendarSource.swift': 'canWrite: true\n',
        'Sources/GoogleCalendar/GoogleCalendarSource+Write.swift': 'extension GoogleCalendarSource: WritableCalendarSource {}\n',
        '.github/workflows/ci.yml': CI,
    }
    files.update(overrides)
    for name, text in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

def run(root):
    return subprocess.run([sys.executable, str(SCRIPT), str(root)], capture_output=True, text=True)

class Contracts(unittest.TestCase):
    def check(self, expect_ok, needle=None, **overrides):
        with tempfile.TemporaryDirectory() as tmp:
            make(Path(tmp), **overrides)
            result = run(tmp)
        self.assertEqual(result.returncode == 0, expect_ok, result.stderr + result.stdout)
        if needle:
            self.assertIn(needle, result.stderr)

    def test_clean_fixture_passes(self):
        self.check(True)

    def test_apple_import_in_portable_source_fails(self):
        self.check(False, 'Apple/UI import', **{'Sources/CalendarCore/B.swift': 'import AppKit\n'})

    def test_microsoft_write_scope_fails(self):
        self.check(False, 'Calendars.ReadWrite', **{
            'Sources/MicrosoftCalendar/MicrosoftConnectorKind.swift': GOOD_SCOPES + '"Calendars.ReadWrite"\n'})

    def test_pull_request_target_fails(self):
        self.check(False, 'pull_request_target', **{
            '.github/workflows/ci.yml': CI.replace('[pull_request]', '[pull_request_target]')})

    def test_secret_outside_an_environment_fails(self):
        self.check(False, 'SIGNING_KEY', **{
            '.github/workflows/ci.yml': CI.replace('DOCKERHUB_TOKEN', 'SIGNING_KEY')})

    def test_secret_inside_an_environment_passes(self):
        self.check(True, **{
            '.github/workflows/ci.yml': CI.replace('    runs-on: ubuntu-latest', '    environment: publish\n    runs-on: ubuntu-latest')
                                            .replace('DOCKERHUB_TOKEN', 'SIGNING_KEY')})

if __name__ == '__main__':
    unittest.main()
```

Run: `python3 -m unittest scripts/ci/tests/test_check_repository_contracts.py` (use `uv run --with PyYAML==6.0.3 python -m unittest ...` if PyYAML is missing) — Expected: errors (script missing).

- [ ] **Step 5: Implement `check-repository-contracts.py`**

```python
#!/usr/bin/env python3
"""Library invariants that the compiler does not enforce. Usage: check-repository-contracts.py [root]"""
import json
import re
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
errors = []

def require(condition, message):
    if not condition:
        errors.append(message)

def read(path):
    file = root / path
    require(file.is_file(), f'missing documented path: {path}')
    return file.read_text() if file.is_file() else ''

manifest = read('Package.swift')
for line in (
    '.target(name: "CalendarCore")',
    '.target(name: "CalendarOAuth", dependencies: ["CalendarCore"])',
    '.target(name: "GoogleCalendar", dependencies: ["CalendarCore", "CalendarOAuth"])',
    '.target(name: "MicrosoftCalendar", dependencies: ["CalendarCore", "CalendarOAuth"])',
):
    require(line in manifest, f'manifest dependency changed: {line}')

PORTABLE = ('CalendarCore', 'CalendarOAuth', 'GoogleCalendar', 'MicrosoftCalendar', 'CalendarTestSupport')
FORBIDDEN = {'AppKit', 'SwiftUI', 'EventKit', 'WidgetKit', 'FoundationModels'}
for file in (root / 'Sources').rglob('*.swift'):
    if file.parts[-2] not in PORTABLE:
        continue
    for match in re.finditer(r'^\s*import\s+(\w+)', file.read_text(), re.M):
        require(match.group(1) not in FORBIDDEN,
                f'Apple/UI import in portable source: {file.relative_to(root)}')

scopes = read('Sources/MicrosoftCalendar/MicrosoftConnectorKind.swift')
for scope in ('Calendars.Read', 'Calendars.Read.Shared', 'MailboxSettings.Read'):
    require(f'"{scope}"' in scopes, f'intended Microsoft scope absent: {scope}')
for scope in ('Calendars.ReadWrite', 'Calendars.ReadWrite.Shared'):
    require(f'"{scope}"' not in scopes, f'Microsoft scope must stay read-only (ADR 0017 in timetug): {scope}')
source = read('Sources/MicrosoftCalendar/MicrosoftCalendarSource.swift')
require('canWrite: true' in source and 'canEditAttendees: true' in source, 'Microsoft write capabilities changed')
require('extension MicrosoftCalendarSource: WritableCalendarSource' in
        read('Sources/MicrosoftCalendar/MicrosoftCalendarSource+Write.swift'),
        'Microsoft write protocol implementation absent')
require('canWrite: true' in read('Sources/GoogleCalendar/GoogleCalendarSource.swift'), 'Google write capability changed')
require('extension GoogleCalendarSource: WritableCalendarSource' in
        read('Sources/GoogleCalendar/GoogleCalendarSource+Write.swift'), 'Google write protocol implementation absent')

# Workflows: untrusted code never meets secrets (program design, section 8).
ALLOWED_ANYWHERE = {'GITHUB_TOKEN', 'DOCKERHUB_USERNAME', 'DOCKERHUB_TOKEN'}
for workflow in sorted((root / '.github' / 'workflows').glob('*.y*ml')):
    data = yaml.safe_load(workflow.read_text()) or {}
    triggers = data.get(True, data.get('on')) or {}
    names = triggers if isinstance(triggers, (list, dict)) else [triggers]
    require('pull_request_target' not in names, f'{workflow.name}: pull_request_target is banned')
    for job_id, job in (data.get('jobs') or {}).items():
        used = set(re.findall(r'secrets\.([A-Za-z0-9_]+)', json.dumps(job)))
        for secret in sorted(used - ALLOWED_ANYWHERE):
            require('environment' in job,
                    f'{workflow.name}: job {job_id} uses secret {secret} outside an environment')

if errors:
    for error in errors:
        print(f'FAIL: {error}', file=sys.stderr)
    sys.exit(1)
print('PASS: repository contracts')
```

- [ ] **Step 6: Run to see it pass**

Run: `python3 -m unittest scripts/ci/tests/test_check_repository_contracts.py` (PyYAML required)
Expected: `Ran 6 tests ... OK`. Then `python3 scripts/ci/check-repository-contracts.py` on the real tree: the workflows do not exist yet, so only `PASS` or missing-directory behaviour matters; if `.github/workflows` is absent the glob is empty and it passes. Fix any real finding it reports against the extracted sources before continuing.

- [ ] **Step 7: Commit**

```bash
git add scripts/ci && git commit -m "Add the library's architecture and contract checks

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 5: Workflows and the code index

**Files:**
- Create in `$LIB`: `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `.github/workflows/index.yml`, `scripts/dev/qindex.py`, `.qindexignore`

**Interfaces:**
- Produces: job ids `macos`, `linux`, `architecture` (the required checks); workflow `Release` with a `publish` job (output `version`).

- [ ] **Step 1: `ci.yml`**

```yaml
# Continuous integration for the library. Runs on pull requests and on every push to main.
#   macos         swift test on the whole package.
#   linux         swift test in the swift:6.0 container: proves the library stays portable.
#   architecture  portability rules, repository contracts and the tests of the release script.
name: CI

on:
  push:
    branches: [main]
  pull_request:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  macos:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
      - name: Select newest Xcode
        run: scripts/ci/select-xcode.sh
      - name: Test
        run: swift test

  linux:
    runs-on: ubuntu-latest
    env:
      DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
      DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
      - name: Log in to Docker Hub
        if: env.DOCKERHUB_USERNAME != '' && env.DOCKERHUB_TOKEN != ''
        run: |
          for attempt in 1 2 3; do
            echo "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin && exit 0
            sleep $((attempt * 15))
          done
          echo "::warning::Docker Hub login failed; pulling anonymously."
      - name: Pull the Swift image
        run: |
          for attempt in 1 2 3; do
            docker pull swift:6.0 && exit 0
            sleep $((attempt * 15))
          done
          exit 1
      - name: Test
        run: |
          docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/work" -w /work swift:6.0 swift test

  architecture:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
      - name: Install pinned test prerequisites
        run: |
          python3 -m venv build/venv
          build/venv/bin/python -m pip install -r scripts/ci/requirements-test.txt
      - name: Architecture rules
        run: scripts/ci/check-architecture.sh
      - name: Repository contracts
        run: build/venv/bin/python scripts/ci/check-repository-contracts.py
      - name: Tests of the checks and of the release script
        run: |
          scripts/ci/tests/test-check-architecture.sh
          scripts/release/tests/test-next-version.sh
          build/venv/bin/python -m unittest discover -s scripts/ci/tests -p 'test_*.py'
```

- [ ] **Step 2: `release.yml`** (the `notify` job arrives in Task 12)

```yaml
# Releases the library. Every push to main publishes the next X.Y.Z tag and a GitHub release.
# The bump comes from the merged pull request's semver:* label (patch by default). Nothing is
# released while the repository has no X.Y.Z tag; the first version is dispatched by hand.
name: Release

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      version:
        description: "X.Y.Z to publish. Needed for the first release and for recovery."
        required: false
        type: string

concurrency:
  group: release
  cancel-in-progress: false

permissions: {}

jobs:
  publish:
    runs-on: ubuntu-latest
    environment: publish
    permissions:
      contents: write
      pull-requests: read
    outputs:
      version: ${{ steps.version.outputs.version }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
        with:
          fetch-depth: 0
      - name: Compute the version
        id: version
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          SHA: ${{ github.sha }}
          OVERRIDE: ${{ inputs.version }}
        run: |
          set -euo pipefail
          latest="$(git tag --list '[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
          labels=""
          if [ -z "$OVERRIDE" ]; then
            labels="$(gh api "repos/$REPO/commits/$SHA/pulls" --jq '[.[].labels[].name] | join(",")')"
          fi
          status=0
          version="$(scripts/release/next-version.sh --latest "$latest" --labels "$labels" --override "$OVERRIDE")" || status=$?
          case "$status" in
            0) echo "version=$version" >> "$GITHUB_OUTPUT"
               echo "Releasing $version (latest: ${latest:-none}; labels: ${labels:-none})" ;;
            3) echo "::notice::No X.Y.Z tag exists yet; nothing is released until the first version is dispatched by hand."
               echo "version=" >> "$GITHUB_OUTPUT" ;;
            *) exit "$status" ;;
          esac
      - name: Create the tag and the release
        if: steps.version.outputs.version != ''
        env:
          GH_TOKEN: ${{ github.token }}
          VERSION: ${{ steps.version.outputs.version }}
          SHA: ${{ github.sha }}
        run: gh release create "$VERSION" --target "$SHA" --title "$VERSION" --generate-notes
```

- [ ] **Step 3: Code index**

```bash
cd "$LIB"
mkdir -p scripts/dev
cp ~/.agents/skills/index/scripts/qindex.py scripts/dev/qindex.py
sed 's/__DEFAULT_BRANCH__/main/g' ~/.agents/skills/add-code-indexing/templates/index.yml > .github/workflows/index.yml
cp ~/.agents/skills/add-code-indexing/templates/qindexignore .qindexignore
printf 'docs/superpowers/plans/\n' >> .qindexignore
cmp scripts/dev/qindex.py ~/.agents/skills/index/scripts/qindex.py && echo script-identical
```

Expected: `script-identical`. Read `.github/workflows/index.yml` once: it must declare `permissions: contents: read, actions: read` and pin its actions by SHA (the template does; if it names an action that is not GitHub-owned or `google-github-actions/auth`, the org allow-list will refuse it: stop and tell the owner).

- [ ] **Step 4: Local checks and commit**

```bash
python3 -m unittest discover -s scripts/ci/tests -p 'test_*.py' 2>&1 | tail -2   # needs PyYAML
python3 scripts/ci/check-repository-contracts.py
swift test 2>&1 | tail -3
git add -A && git commit -m "Add CI, release and code index workflows

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected: `OK`; `PASS: repository contracts`; the Swift run ends with `Test run with N tests ... passed`.

### Task 6: Publish, protect, release 1.0.0

**Files:** none (GitHub settings and the first push).

**Interfaces:**
- Consumes: Tasks 1 to 5.
- Produces: `binary-companion/calendar-connectors` with tag `1.0.0`, rulesets, `publish` environment, labels.

Owner-visible actions in this task are the agent's: creating a repository in the organization and its settings (as for `binary-companion/website`). Nothing is merged or approved.

- [ ] **Step 1: Create and push**

```bash
R=binary-companion/calendar-connectors
gh repo create "$R" --public --description "Portable Swift library for Google, Microsoft, CalDAV/iCloud and iCalendar calendars" --homepage "https://timetug.binarycompanion.com"
cd "$LIB" && git remote add origin "https://github.com/$R.git" && git push -u origin main
gh api -X PATCH "repos/$R" -F has_wiki=false -F has_projects=false -F delete_branch_on_merge=true -F allow_auto_merge=true --jq '.full_name'
for l in semver:major semver:minor semver:patch; do gh label create "$l" --repo "$R" --color BFD4F2 2>/dev/null || true; done
```

Expected: the push succeeds; `binary-companion/calendar-connectors`.

- [ ] **Step 2: Environment and Docker Hub secrets**

```bash
gh api -X PUT "repos/$R/environments/publish" --input - <<'JSON'
{"can_admins_bypass": false, "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
gh api -X POST "repos/$R/environments/publish/deployment-branch-policies" -f name=main -f type=branch --jq .name
ID="$(gh api "repos/$R" --jq .id)"
for s in DOCKERHUB_USERNAME DOCKERHUB_TOKEN; do
  gh api -X PUT "orgs/binary-companion/actions/secrets/$s/repositories/$ID" && echo "$s visible to $R"
done
```

Expected: `main`; two `visible to` lines. If the two `PUT` calls return 403 or 404 the token lacks `admin:org`: the owner adds the repository to each of the two secrets under Organization settings > Secrets and variables > Actions (a UI step). Meanwhile the `linux` job pulls anonymously; it already degrades with a warning.

- [ ] **Step 3: Watch the first CI run (it started on the push)**

```bash
RUN="$(gh run list --repo "$R" --workflow CI --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$RUN" --repo "$R" --exit-status
```

Expected: `macos`, `linux`, `architecture` all succeed. A failure here is a real defect in Tasks 1 to 5: fix it in `$LIB`, push to `main` (the repository has no ruleset yet and no consumers), and re-run this step.

- [ ] **Step 4: The extraction push did not release**

```bash
gh run list --repo "$R" --workflow Release --limit 1 --json conclusion,status --jq '.[0]'
git ls-remote --tags origin
```

Expected: the Release run is `success` (its version step printed the "nothing is released" notice) and `git ls-remote --tags` prints nothing. If a tag exists, stop: the guard failed (Review Focus 1).

- [ ] **Step 5: Release 1.0.0**

```bash
gh workflow run release.yml --repo "$R" --ref main -f version=1.0.0
sleep 5
RUN="$(gh run list --repo "$R" --workflow Release --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$RUN" --repo "$R" --exit-status
git fetch --tags -q && git tag -l && gh release view 1.0.0 --repo "$R" --json tagName,isDraft,isPrerelease --jq .
git rev-parse 1.0.0:Sources 1.0.0:Tests
```

Expected: tag `1.0.0`; the release is not a draft and not a prerelease; the two tree hashes equal the ones from Task 1 step 4.

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
    "required_status_checks":[{"context":"macos"},{"context":"linux"},{"context":"architecture"}]}}]}
JSON
cat > "$WORK/ruleset-tags.json" <<'JSON'
{"name":"Protect version tags","target":"tag","enforcement":"active",
 "conditions":{"ref_name":{"include":["refs/tags/*"],"exclude":[]}},
 "bypass_actors":[],
 "rules":[{"type":"update"},{"type":"deletion"},{"type":"non_fast_forward"}]}
JSON
for f in main tags; do gh api -X POST "repos/$R/rulesets" --input "$WORK/ruleset-$f.json" --jq '"\(.id) \(.name)"'; done
```

Expected: two `<id> <name>` lines.

- [ ] **Step 7: Prove the controls**

```bash
git push origin HEAD:main 2>&1 | tail -2                       # a direct push is refused now
gh api -X DELETE "repos/$R/git/refs/tags/1.0.0" 2>&1 | head -2  # tag deletion is refused
scripts/security/audit-github.sh --strict binary-companion "$R" 2>&1 | tail -8   # run from the timetug checkout
```

Expected: the push is rejected (`GH013` repository rule violations); the delete returns an error (`Repository rule violations found`); the audit ends with 0 failed, 0 skipped. If the audit reports the repository-level secrets or the `publish` environment, fix and re-run. If the tag deletion *succeeds*, the tag ruleset is not enforcing: re-run the Release workflow with `version=1.0.0` (main has not moved, so it recreates the same tag at the same commit), fix the ruleset, and repeat this step.

- [ ] **Step 8: Record**

Add to the tracker's session log (in the flip branch, Task 10): "`calendar-connectors` created, `1.0.0` released, rulesets and `publish` environment in place, audit 0 failed."

---

## Part B: the flip pull request in `timetug`

Work in this worktree on a fresh branch from `origin/master`:

```bash
git fetch -q origin && git switch -c claude/phase-1-flip origin/master
```

### Task 7: Switch to the released library

**Files:**
- Modify: `Packages/{TimeTugCore,CalendarBridge,CalendarApple,EventKitSource,AppleIntelligenceInference}/Package.swift`, `Apps/macOS/project.yml`
- Delete: `Packages/CalendarConnectors/`

**Interfaces:**
- Consumes: tag `1.0.0` of `binary-companion/calendar-connectors`.
- Produces: dependency spelling `.package(url: "https://github.com/binary-companion/calendar-connectors", from: "1.0.0")` and product references `package: "calendar-connectors"`; `project.yml` package key `CalendarConnectors` with `url` and `exactVersion: 1.0.0`.

- [ ] **Step 1: The freeze check**

```bash
for d in Sources Tests; do
  [ "$(git rev-parse origin/master:Packages/CalendarConnectors/$d)" = "$(git -C "$LIB" rev-parse 1.0.0:$d)" ] \
    && echo "$d: identical" || echo "$d: DIFFERS"
done
```

Expected: both identical. If either differs, a library change merged after Task 1: port it into `$LIB` through a pull request there, release it, and use that version below instead of `1.0.0` (replace the version everywhere in this Part).

- [ ] **Step 2: Manifests**

```bash
URL='https://github.com/binary-companion/calendar-connectors'
for p in TimeTugCore CalendarBridge CalendarApple EventKitSource AppleIntelligenceInference; do
  sed -i '' -e "s#\.package(path: \"\.\./CalendarConnectors\")#.package(url: \"$URL\", from: \"1.0.0\")#" \
            -e 's#package: "CalendarConnectors"#package: "calendar-connectors"#g' "Packages/$p/Package.swift"
done
git diff --stat
grep -n 'CalendarConnectors' Packages/*/Package.swift | grep -v '^Packages/CalendarConnectors/' || echo none
```

Expected: 5 files changed; `none`.

- [ ] **Step 3: `project.yml` and the in-repo copy**

Replace in `Apps/macOS/project.yml`:

```yaml
  CalendarConnectors:
    path: ../../Packages/CalendarConnectors
```

with:

```yaml
  CalendarConnectors:
    url: https://github.com/binary-companion/calendar-connectors
    exactVersion: 1.0.0
```

```bash
git rm -rq Packages/CalendarConnectors
git status --short | head
```

- [ ] **Step 4: Build and test against the release**

```bash
swift test --package-path Packages/TimeTugCore 2>&1 | tail -3
swift test --package-path Packages/CalendarBridge 2>&1 | tail -3
swift test --package-path Packages/CalendarApple 2>&1 | tail -3
swift test --package-path Packages/EventKitSource 2>&1 | tail -3
swift test --package-path Packages/AppleIntelligenceInference 2>&1 | tail -3
xcodegen generate --spec Apps/macOS/project.yml
xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | tail -5
git status --short | grep -v '^D  Packages/CalendarConnectors/'
```

Expected: every package run ends with its suite passed; `** TEST SUCCEEDED **`; the last command lists only the five manifests and `Apps/macOS/project.yml` as modified (if XcodeGen rewrote any other checked-in file, inspect its `git diff` before committing). If SwiftPM reports `unknown package 'calendar-connectors'` or a name mismatch, the library manifest name from Task 2 step 1 did not reach `1.0.0`: check `git -C "$LIB" show 1.0.0:Package.swift | head -6`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Consume calendar-connectors 1.0.0 by released version

The library moved to binary-companion/calendar-connectors with its history.
The five local packages depend on it by URL with a 1.0.0 floor and the app
pins exactVersion 1.0.0. No source changes: the library's Sources and Tests
trees are identical to the ones removed here.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 8: The pin contract and the local override (TDD)

**Files:**
- Create: `scripts/ci/check-shared-pins.py`, `scripts/ci/tests/test_check_shared_pins.py`, `scripts/ci/tests/test-check-shared-pins.sh`, `scripts/dev/use-local-connectors.sh`, `scripts/dev/tests/test-use-local-connectors.sh`
- Modify: `scripts/dev/verify.sh` (`run_contracts`)

**Interfaces:**
- Produces: `check-shared-pins.py [root]` (exit 1 with `FAIL:` lines); `use-local-connectors.sh <path-to-checkout> | --restore`.

- [ ] **Step 1: Failing test for the pin check**

`scripts/ci/tests/test_check_shared_pins.py`:

```python
import subprocess, sys, tempfile, textwrap, unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'check-shared-pins.py'
URL = 'https://github.com/binary-companion/calendar-connectors'

PROJECT = '''packages:
  CalendarConnectors:
    url: %s
    exactVersion: %s
'''
MANIFEST = '''let package = Package(
    name: "%s",
    dependencies: [%s],
    targets: []
)
'''

def make(root: Path, project=PROJECT % (URL, '1.2.0'), manifests=None):
    (root / 'Apps/macOS').mkdir(parents=True)
    (root / 'Apps/macOS/project.yml').write_text(project)
    for name, dependency in (manifests or {'TimeTugCore': f'.package(url: "{URL}", from: "1.0.0")'}).items():
        d = root / 'Packages' / name
        d.mkdir(parents=True)
        (d / 'Package.swift').write_text(MANIFEST % (name, dependency))

def run(root):
    return subprocess.run([sys.executable, str(SCRIPT), str(root)], capture_output=True, text=True)

class SharedPins(unittest.TestCase):
    def check(self, ok, needle=None, **kwargs):
        with tempfile.TemporaryDirectory() as tmp:
            make(Path(tmp), **kwargs)
            result = run(tmp)
        self.assertEqual(result.returncode == 0, ok, result.stderr + result.stdout)
        if needle:
            self.assertIn(needle, result.stderr)

    def test_released_pin_inside_every_range_passes(self):
        self.check(True)

    def test_unrelated_local_path_dependencies_are_fine(self):
        self.check(True, manifests={'CalendarBridge': '.package(path: "../TimeTugCore")',
                                    'TimeTugCore': f'.package(url: "{URL}", from: "1.0.0")'})

    def test_path_dependency_on_the_library_fails(self):
        self.check(False, 'Packages/TimeTugCore/Package.swift',
                   manifests={'TimeTugCore': '.package(path: "/Users/me/calendar-connectors")'.replace(
                       '/Users/me/calendar-connectors', '../CalendarConnectors')})

    def test_branch_dependency_fails(self):
        self.check(False, 'from:', manifests={'TimeTugCore': f'.package(url: "{URL}", branch: "main")'})

    def test_project_path_fails(self):
        self.check(False, 'url', project='packages:\n  CalendarConnectors:\n    path: ../../../calendar-connectors\n')

    def test_project_without_exact_version_fails(self):
        self.check(False, 'exactVersion',
                   project='packages:\n  CalendarConnectors:\n    url: %s\n    from: 1.0.0\n' % URL)

    def test_pin_below_a_floor_fails(self):
        self.check(False, 'below',
                   manifests={'TimeTugCore': f'.package(url: "{URL}", from: "1.3.0")'})

    def test_pin_in_another_major_fails(self):
        self.check(False, 'major', project=PROJECT % (URL, '2.0.0'))

if __name__ == '__main__':
    unittest.main()
```

`scripts/ci/tests/test-check-shared-pins.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 -m unittest scripts/ci/tests/test_check_shared_pins.py
python3 scripts/ci/check-shared-pins.py
```

Run: `python3 -m unittest scripts/ci/tests/test_check_shared_pins.py` — Expected: errors (script missing).

- [ ] **Step 2: Implement**

`scripts/ci/check-shared-pins.py`:

```python
#!/usr/bin/env python3
"""Shared libraries are consumed by released version only (phase 1 spec).

Every Packages/*/Package.swift that names calendar-connectors must say
`.package(url: "<library url>", from: "X.Y.Z")`, Apps/macOS/project.yml must pin the same package with
`url` and `exactVersion`, and the pin must satisfy every manifest's range (same major, not below).
Usage: check-shared-pins.py [repo-root]
"""
import re
import sys
from pathlib import Path

import yaml

LIBRARIES = {'calendar-connectors': 'CalendarConnectors'}  # repository slug -> project.yml package key
URL_PREFIX = 'https://github.com/binary-companion/'
SEMVER = re.compile(r'^(\d+)\.(\d+)\.(\d+)$')

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
errors = []

def version(text):
    m = SEMVER.match(str(text))
    return tuple(int(x) for x in m.groups()) if m else None

pins = {}
project = yaml.safe_load((root / 'Apps/macOS/project.yml').read_text()) or {}
for slug, key in LIBRARIES.items():
    entry = (project.get('packages') or {}).get(key)
    if entry is None:
        errors.append(f'Apps/macOS/project.yml: package {key} is missing')
        continue
    if entry.get('url') != URL_PREFIX + slug:
        errors.append(f'Apps/macOS/project.yml: {key} must use url {URL_PREFIX}{slug} (no path, branch or revision)')
    pin = version(entry.get('exactVersion', ''))
    if pin is None:
        errors.append(f'Apps/macOS/project.yml: {key} needs exactVersion X.Y.Z')
    pins[slug] = pin

for manifest in sorted((root / 'Packages').glob('*/Package.swift')):
    rel = manifest.relative_to(root)
    text = ' '.join(manifest.read_text().split())
    for dependency in re.findall(r'\.package\([^)]*\)', text):
        for slug, key in LIBRARIES.items():
            if slug not in dependency and key not in dependency:
                continue
            m = re.fullmatch(r'\.package\(url: "%s", from: "([^"]+)"\)' % re.escape(URL_PREFIX + slug), dependency)
            floor = version(m.group(1)) if m else None
            if floor is None:
                errors.append(f'{rel}: {slug} must be .package(url: "{URL_PREFIX}{slug}", from: "X.Y.Z"), got {dependency}')
                continue
            pin = pins.get(slug)
            if pin is None:
                continue
            if pin[0] != floor[0]:
                errors.append(f'{rel}: pin {".".join(map(str, pin))} is in another major than from: {m.group(1)}')
            elif pin < floor:
                errors.append(f'{rel}: pin {".".join(map(str, pin))} is below from: {m.group(1)}')

if errors:
    for error in errors:
        print(f'FAIL: {error}', file=sys.stderr)
    sys.exit(1)
print('PASS: shared pins')
```

- [ ] **Step 3: Run**

Run: `chmod +x scripts/ci/tests/test-check-shared-pins.sh && scripts/ci/tests/test-check-shared-pins.sh`
Expected: `Ran 8 tests ... OK`, then `PASS: shared pins` for the real tree (PyYAML needed; `uv run --with PyYAML==6.0.3` works).

- [ ] **Step 4: Failing test for the local override**

`scripts/dev/tests/test-use-local-connectors.sh`:

```bash
#!/usr/bin/env bash
# Tests use-local-connectors.sh in a throwaway repo shaped like this one.
set -euo pipefail
cd "$(dirname "$0")/../../.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
g() { git -c user.name=t -c user.email=t@t "$@"; }
mkdir -p "$T/repo/scripts/dev" "$T/repo/scripts/ci" "$T/repo/Apps/macOS" "$T/calendar-connectors" "$T/other"
touch "$T/calendar-connectors/Package.swift" "$T/other/Package.swift"
cp scripts/dev/use-local-connectors.sh "$T/repo/scripts/dev/"
cp scripts/ci/check-shared-pins.py "$T/repo/scripts/ci/"
cp Apps/macOS/project.yml "$T/repo/Apps/macOS/"
for m in Packages/*/Package.swift; do mkdir -p "$T/repo/$(dirname "$m")"; cp "$m" "$T/repo/$m"; done
cd "$T/repo"
git init -q -b master; g add -A; g commit -qm base
python3 scripts/ci/check-shared-pins.py >/dev/null || fail "fixture should start clean"

scripts/dev/use-local-connectors.sh "$T/calendar-connectors" >/dev/null
grep -q "path: \"$T/calendar-connectors\"" Packages/TimeTugCore/Package.swift || fail "manifest not redirected"
grep -Eq 'path: .*calendar-connectors$' Apps/macOS/project.yml || fail "project.yml not redirected"
grep -q 'exactVersion: 2.10.0' Apps/macOS/project.yml || fail "another package's pin changed"
if python3 scripts/ci/check-shared-pins.py >/dev/null 2>&1; then fail "the contract accepted a local override"; fi

# An unrelated edit made while the override is in place is not what --restore brings back.
scripts/dev/use-local-connectors.sh --restore >/dev/null
[ -z "$(git status --porcelain)" ] || fail "restore left changes: $(git status --porcelain)"
python3 scripts/ci/check-shared-pins.py >/dev/null || fail "restored tree should pass"
if scripts/dev/use-local-connectors.sh --restore >/dev/null 2>&1; then fail "restore without an override succeeded"; fi
if scripts/dev/use-local-connectors.sh "$T/missing" >/dev/null 2>&1; then fail "accepted a missing checkout"; fi
if scripts/dev/use-local-connectors.sh "$T/other" >/dev/null 2>&1; then fail "accepted a checkout not named calendar-connectors"; fi
[ -z "$(git status --porcelain)" ] || fail "a refused call changed files"
echo PASS
```

Run: `chmod +x scripts/dev/tests/test-use-local-connectors.sh && scripts/dev/tests/test-use-local-connectors.sh` — Expected: FAIL (script missing).

- [ ] **Step 5: Implement**

`scripts/dev/use-local-connectors.sh`:

```bash
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
```

- [ ] **Step 6: Run, wire into `verify.sh`, commit**

Run: `chmod +x scripts/dev/use-local-connectors.sh && scripts/dev/tests/test-use-local-connectors.sh` — Expected: `PASS`.

In `scripts/dev/verify.sh` replace

```bash
run_contracts() { need python3; run repository-contracts python3 scripts/ci/check-repository-contracts.py; }
```

with

```bash
run_contracts() {
  need python3
  run repository-contracts python3 scripts/ci/check-repository-contracts.py
  run shared-pins python3 scripts/ci/check-shared-pins.py
}
```

In the same function's neighbour `run_release`, add the override test to the suite loop: change `for test in scripts/ci/tests/test-*.sh scripts/release/tests/test-*.sh; do` to `for test in scripts/ci/tests/test-*.sh scripts/release/tests/test-*.sh scripts/dev/tests/test-use-local-connectors.sh; do`. In `scripts/dev/tests/test-verify.sh`, add after the line that copies `test-dummy.sh` into `scripts/release/tests`: `cp "$T/repo/scripts/ci/tests/test-dummy.sh" "$T/repo/scripts/dev/tests/test-use-local-connectors.sh"`.

`scripts/dev/tests/test-verify.sh` must then expect the second call: change its documentation-check assertion to also require `grep -q 'python3 scripts/ci/check-shared-pins.py' "$VERIFY_CALLS"` (add one line after the `check-repository-contracts.py` assertion). Run `scripts/dev/tests/test-verify.sh` — Expected `PASS`.

```bash
git add -A && git commit -m "Check that shared libraries are pinned to releases; add the local override

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 9: Rework the guards that named the library path

**Files:**
- Modify: `scripts/ci/check-architecture.sh`, `scripts/ci/tests/test-check-architecture.sh`, `scripts/ci/check-repository-contracts.py`, `scripts/dev/verify.sh`, `scripts/dev/tests/test-verify.sh`, `scripts/dev/tests/test-affected-tests.sh`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: Task 7 manifests (URL dependencies), Task 8 `check-shared-pins.py`.

- [ ] **Step 1: Update the architecture test first (it must fail against the old script)**

In `scripts/ci/tests/test-check-architecture.sh`:

1. In `pkg()`, make a dependency that starts with `http` a URL dependency:

```bash
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
```

2. Delete the lines that create the library fixture: `pkg CalendarConnectors`, the `mkdir -p ... CalendarConnectors/Sources/CalendarCore ...CalendarOAuth` line, and the two `printf ... > "$T/Packages/CalendarConnectors/Sources/..."` statements.
3. Change the package lines to:

```bash
pkg TimeTugCore "$LIB"
pkg CalendarBridge ../TimeTugCore "$LIB"
pkg EventKitSource "$LIB"
pkg CalendarApple "$LIB"
pkg AppleIntelligenceInference ../TimeTugCore "$LIB"
```

4. Delete the three `expect Packages/CalendarConnectors/...` lines and the `expect Packages/CalendarConnectors/Package.swift ...` line. Replace the `import CalendarOAuth` expectation for Core (it stays) and add:

```bash
expect Packages/TimeTugCore/Package.swift 'let package = Package(dependencies: [.package(path: "../CalendarConnectors")])\n' \
  "TimeTugCore may not depend on ../CalendarConnectors"
expect Packages/TimeTugCore/Package.swift \
  'let package = Package(dependencies: [.package(url: "https://github.com/x/y", from: "1.0.0")])\n' \
  "TimeTugCore may not depend on https://github.com/x/y"
```

Run: `scripts/ci/tests/test-check-architecture.sh` — Expected: FAIL (the old script still has `only CalendarConnectors` and `../CalendarConnectors` rules; the fixture's URL dependency is rejected).

- [ ] **Step 2: Update `check-architecture.sh`**

Remove these lines:

```bash
LIB="$(ls Packages/CalendarConnectors/Sources 2>/dev/null | tr '\n' ' ')"
```

```bash
# The connector library imports nothing from TimeTug and nothing Apple-only (it builds on Linux).
only CalendarConnectors "Foundation FoundationNetworking FoundationXML Testing $LIB" $P/CalendarConnectors/Sources $P/CalendarConnectors/Tests
```

Add after `P=Packages`:

```bash
# The connector library lives in its own repository and is consumed by released version (scripts/ci/check-shared-pins.py).
LIBURL=https://github.com/binary-companion/calendar-connectors
```

Replace the `allowed_deps` function with:

```bash
allowed_deps() {
  case "$1" in
    TimeTugCore | EventKitSource | CalendarApple) echo "$LIBURL" ;;
    CalendarBridge | AppleIntelligenceInference) echo "../TimeTugCore $LIBURL" ;;
    *) return 1 ;;
  esac
}
```

Change the comment above the loop to `# Package dependencies point toward Core and the released connector library (by URL; scripts/ci/check-shared-pins.py checks the pin).` Run `scripts/ci/tests/test-check-architecture.sh && scripts/ci/check-architecture.sh` — Expected: `PASS`, then no output and exit 0.

- [ ] **Step 3: `check-repository-contracts.py`**

Replace everything from the comment `# Check explicit package target dependency declarations;` down to (not including) the comment `# XcodeGen is the source of truth for generated plist properties.` with:

```python
# Core is portable: no Apple or UI imports. (The connector library enforces the same for itself in its own repository.)
for file in (root / 'Packages' / 'TimeTugCore' / 'Sources').rglob('*.swift'):
    for match in re.finditer(r'^\s*import\s+(\w+)', file.read_text(), re.M):
        forbidden = {'AppKit', 'SwiftUI', 'EventKit', 'WidgetKit', 'FoundationModels'}
        require(match.group(1) not in forbidden, f'Apple/UI import in portable source: {file.relative_to(root)}')

registry = read('Apps/macOS/Sources/AppConnectors.swift')
for kind in ('EventKitConnectorKind', 'GoogleConnectorKind', 'MicrosoftConnectorKind'):
    require(f'registry.register({kind}' in registry, f'provider not registered: {kind}')
# The Microsoft scope and Google/Microsoft write-capability checks moved with the library
# (binary-companion/calendar-connectors, scripts/ci/check-repository-contracts.py).
eventkit = 'Packages/EventKitSource/Sources/EventKitSource'
require('canWrite: true' in read(f'{eventkit}/EventKitSource.swift'), 'EventKitSource write capability changed')
require('extension EventKitSource: WritableCalendarSource' in read(f'{eventkit}/EventKitSource+Write.swift'),
        'EventKitSource write protocol implementation absent')

```

Run `python3 scripts/ci/check-repository-contracts.py` — Expected: `PASS: repository contracts`.

- [ ] **Step 4: `verify.sh`, `ci.yml`, the wrapper tests**

`scripts/dev/verify.sh`: in the `affected` case replace `Packages/CalendarConnectors/*|Packages/CalendarApple/*|Packages/EventKitSource/*)` with `Packages/CalendarApple/*|Packages/EventKitSource/*)`; delete `[[ "$WANT_CONNECTORS" == 1 || "$WANT_CORE" == 1 ]] || skip_check connectors`; delete `run_pkg connectors Packages/CalendarConnectors` from the `WANT_CONNECTORS` block and `[[ "$WANT_CONNECTORS" == 1 ]] || run_pkg connectors Packages/CalendarConnectors` from the `WANT_CORE` block. The `connectors` mode name stays (it now tests the Apple adapters).

`scripts/dev/tests/test-verify.sh`: replace the assertion `[ "$(grep -c 'swift test --package-path Packages/CalendarConnectors' ...` with:

```bash
if grep -q 'Packages/CalendarConnectors' "$VERIFY_CALLS"; then fail 'the library is tested from this repository'; fi
```

and replace the block that creates `Packages/CalendarConnectors/Sources/CalendarCore/'model with spaces.swift'` (its `mkdir`, `echo`, `run_mode affected`, the two `grep` assertions and the `rm`) with the same block on `Packages/CalendarApple/Sources/CalendarApple` (`'model with spaces.swift'`), asserting `swift test --package-path Packages/CalendarApple` and `xcodebuild `.

`scripts/dev/tests/test-affected-tests.sh`: replace the four-line case `check "the library reaches everything, dependencies first" ...` (it ends with `Packages/CalendarConnectors/Package.swift`) with:

```bash
check "an adapter reaches the app only" "$(lines $ARCH "$(st CalendarApple)" "$APP")" Packages/CalendarApple/Sources/A.swift
```

(The fixture copies the real manifests. After Task 7 the library is a URL dependency, and `affected-tests.sh` reads local dependencies from `.package(path: ...)` entries only, so no package depends on it locally and a change to an adapter reaches that package and the app.)

`.github/workflows/ci.yml`:

- Header comment: `core` line becomes `Swift Testing suites for Packages/TimeTugCore, Packages/CalendarBridge, Packages/CalendarApple, Packages/EventKitSource and Packages/AppleIntelligenceInference (macOS). The connector library is tested in its own repository.`; the `core-linux` line becomes `Runs the Core tests on Linux to prove Core stays portable (it resolves the released connector library). Required for merges.`
- Delete the `core` step `Test CalendarConnectors`.
- In `core-linux`, rename the last step `Test TimeTugCore` and change its command to `sh -c 'swift test --package-path Packages/TimeTugCore'`.
- In the `architecture` job's `Test the checks` step, add `scripts/ci/tests/test-check-shared-pins.sh` is **not** run there (it needs PyYAML); it runs in `release-tooling` through `verify.sh release-tools`, because `run_release` already runs every `scripts/ci/tests/test-*.sh`.

- [ ] **Step 5: Run the affected local checks**

```bash
scripts/ci/tests/test-check-architecture.sh
scripts/dev/tests/test-verify.sh
scripts/dev/tests/test-affected-tests.sh
scripts/ci/tests/test-workflows.sh
python3 scripts/ci/check-repository-contracts.py
python3 scripts/ci/check-shared-pins.py
```

Expected: each prints `PASS`. `test-workflows.sh` may complain about the `ci.yml` edits (it checks workflow contracts); fix its finding in the workflow, not in the test.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Rework the guards for a library that lives in its own repository

Architecture rules, repository contracts, the verify and affected-test
wrappers and CI no longer name Packages/CalendarConnectors. The library's
own rules run in its repository; here the five packages may depend on it
by URL only, and check-shared-pins.py keeps the pins on releases.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 10: Documents, moved documents, tracker; open the flip PR

**Files:**
- Modify: `AGENTS.md`, `docs/architecture.md`, `docs/development.md`, `docs/development/runbooks/operations.md`, `.agents/skills/running-live-calendar-tests/SKILL.md`, `docs/decisions/0012-calendar-connector-library.md`, `docs/superpowers/plans/2026-10-09-windows-program-tracker.md`
- Delete: the eleven documents listed in Task 1's `paths.txt` (all but the `Packages/` line), including `docs/calendar-connectors-api.md`.

- [ ] **Step 1: Remove the moved documents and find dangling links**

```bash
sed -n '2,$p' "$WORK/paths.txt" | xargs git rm -q
git grep -n -E 'calendar-connectors-api\.md|calendar-connectors-phase(1|3|4-microsoft|5-caldav|6-ical-link)' -- . ':!docs/superpowers' | cut -c1-160
```

For each hit outside `docs/superpowers/`, replace the link target with `https://github.com/binary-companion/calendar-connectors/blob/main/docs/api.md` (for the API contract) or delete the sentence if it only cited a plan. Re-run the grep: Expected: no output. Links from the remaining `docs/superpowers/` documents (the phase 2 and 2.5 documents, the program spec) may stay: they are historical.

- [ ] **Step 2: Rewrite the references**

`AGENTS.md` line 8: replace its first sentence, `` `Packages/CalendarConnectors` is portable and dependency-free.``, with:

```markdown
The connector library is its own repository, [binary-companion/calendar-connectors](https://github.com/binary-companion/calendar-connectors), consumed by released version (`Apps/macOS/project.yml` pins it with `exactVersion`; the local packages say `from:`); to change it, use the `working-across-timetug-repos` skill. It is portable and dependency-free.
```

(the rest of the line stays). Add this section before `## Verify`:

```markdown
## Repositories

- `calendar-connectors`: the connector library (MIT). Tags `X.Y.Z`, released automatically on every merge to `main`.
- `timetug-shared` (phase 2) and `timetug-windows` (later) join it per the [program design](docs/superpowers/specs/2026-10-09-windows-program-design.md).
- `timetug` (this repository): the Mac app, the Apple adapters and the product website.

A library release sends this repository a "Bump calendar-connectors to X.Y.Z" pull request (opened by `timetug-bot`, merged by the owner). Never edit the pin by hand except through `scripts/ci/bump-pin.sh`; never commit the output of `scripts/dev/use-local-connectors.sh`.
```

`docs/architecture.md`:

- line 11: replace the opening ``` `Packages/CalendarConnectors`: portable calendar connector library (ADR 0012), no external dependencies.``` with ``The [calendar-connectors](https://github.com/binary-companion/calendar-connectors) repository: the portable calendar connector library (ADR 0012), no external dependencies, consumed by released version.``
- line 21: replace `Inside CalendarConnectors:` with `Inside the library:`.
- line 29: replace ``in `Packages/CalendarConnectors` (except Apple Calendar,`` with ``in the `calendar-connectors` repository (a library pull request, then the automatic bump pull request here; except Apple Calendar,``.

`docs/development/runbooks/operations.md`:

- line 11: replace the opening ``- `Packages/CalendarConnectors`: portable connector library (ADR 0012), no external dependencies,`` with ``- `calendar-connectors` (its own repository, consumed by released version; ADR 0012): portable connector library, no external dependencies,``.
- line 34: replace the whole line with ``- Connector library tests run in its own repository (`swift test` there). To exercise a local library change in the app, use `scripts/dev/use-local-connectors.sh`.``

`docs/development.md` line 9: replace ``The `core` mode tests Core, CalendarConnectors, Bridge and inference. `connectors` tests CalendarConnectors, CalendarApple and EventKitSource.`` with ``The `core` mode tests Core, Bridge and inference. `connectors` tests CalendarApple and EventKitSource. The connector library is tested in its own repository.``

`.agents/skills/running-live-calendar-tests/SKILL.md` line 15: replace the cell ``TIMETUG_LIVE_ICLOUD=1 swift test --package-path Packages/CalendarConnectors --filter iCloudLiveSmoke`` with ``TIMETUG_LIVE_ICLOUD=1 swift test --filter iCloudLiveSmoke`` and add after it, inside the same cell, ``(run in a checkout of `binary-companion/calendar-connectors`)``.

`docs/decisions/0012-calendar-connector-library.md`: append

```markdown

## Update 2026-10-12

The library was extracted to [binary-companion/calendar-connectors](https://github.com/binary-companion/calendar-connectors) with its history and released as `1.0.0`. `timetug` consumes it by released version; platform adapters (`CalendarApple`, `EventKitSource`) stay here. See [the phase 1 spec](../superpowers/specs/2026-10-12-phase-1-calendar-connectors-design.md).
```

Then find what is left:

```bash
git grep -n 'Packages/CalendarConnectors' -- . ':!docs/superpowers' ':!docs/decisions'
```

Expected: no output. Fix any hit the same way (a path to the in-repo library becomes a pointer to the repository). Hits under `docs/superpowers/` and `docs/decisions/` are historical records and stay.

- [ ] **Step 3: Tracker**

In `docs/superpowers/plans/2026-10-09-windows-program-tracker.md`: set the phase 1 row to `in progress: [plan](2026-10-12-phase-1-calendar-connectors.md); library published as 1.0.0 (2026-10-12), flip pull request open` with the plan link in the Plan column; add a session log line `2026-10-12 (phase 1): ...` stating the repository, `1.0.0`, the rulesets and `publish` environment, the audit result, and that the flip PR and the `timetug-bot` loop remain; add the owner checklist item `- [ ] **(owner)** Create the \`timetug-bot\` GitHub App (plan Task 11).`.

- [ ] **Step 4: Full local verification**

```bash
scripts/dev/verify.sh all 2>&1 | tail -12
```

Expected: `failed=0`, exit code 0 (this includes the app tests and takes several minutes).

- [ ] **Step 5: Commit, push, open the pull request**

```bash
git add -A && git commit -m "Point the documents at the library repository and remove the moved ones

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git push -u origin claude/phase-1-flip
gh pr create --repo binary-companion/timetug --base master --head claude/phase-1-flip \
  --title "Consume calendar-connectors 1.0.0 from its own repository" \
  --body "$(cat <<'EOF'
## What

Phase 1 of the Windows program. The connector library now lives in https://github.com/binary-companion/calendar-connectors (history preserved, MIT, released as 1.0.0). This pull request makes `timetug` consume it by released version.

- Five local packages: `.package(url: ..., from: "1.0.0")`; `project.yml`: `exactVersion: 1.0.0`.
- `Packages/CalendarConnectors` is removed. Its `Sources` and `Tests` trees are byte-identical to the released ones (verified by tree hash).
- New contract `scripts/ci/check-shared-pins.py`; `scripts/dev/use-local-connectors.sh` for working on both repositories.
- Guards, wrapper scripts, CI and documents no longer name the old path; the library's moved documents are removed here.

## Not here

The `timetug-bot` loop (notify job and `bump-dependencies.yml`) comes after the owner creates the GitHub App.

## Verification

`scripts/dev/verify.sh all` passes locally; CI runs `core`, `app`, `dmg`, `architecture` and `core-linux` against the released library. Beta will build from this on merge.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Then bind it with `mcp__ccd_pr__get_status` / `bind_pr` if it is not already bound. Before the owner merges, re-run the Task 7 step 1 freeze check against a fresh `git fetch origin`: if `origin/master:Packages/CalendarConnectors/{Sources,Tests}` changed since, port that change to the library through a pull request there, release it, and move this branch's pin to the new version before merging. **Stop for the owner's review and merge.** The in-repo library is gone only after the merge; until then `master` is unchanged and the app is releasable.

---

## Part C: the automatic loop

### Task 11: Create `timetug-bot` (owner)

Owner steps (organization settings; the agent cannot do these):

- [ ] **Step 1: Create the app.** `https://github.com/organizations/binary-companion/settings/apps/new`. Name `timetug-bot`. Homepage `https://github.com/binary-companion`. Uncheck "Active" under Webhook. Repository permissions: **Contents: Read and write**, **Pull requests: Read and write**, **Metadata: Read-only**; nothing else. "Where can this GitHub App be installed": **Only on this account**.
- [ ] **Step 2: Key.** On the app page, "Generate a private key"; save the `.pem` file somewhere outside every repository. Note the **App ID** (shown at the top of the page).
- [ ] **Step 3: Install.** "Install App" > the organization > "Only select repositories" > `timetug` only.
- [ ] **Step 4: Tell the agent** the App ID and the path of the `.pem` file.

The Actions allow-list already permits `actions/*` (GitHub-owned), so `actions/create-github-app-token` needs no allow-list change; pins are enforced by the org policy and used below.

### Task 12: The bump loop (TDD)

**Files:**
- Create in `timetug`: `scripts/ci/bump-pin.sh`, `scripts/ci/tests/test-bump-pin.sh`, `.github/workflows/bump-dependencies.yml`
- Modify in `$LIB`: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `check-shared-pins.py` (Task 8); the `publish` job output `version` (Task 5).
- Produces: `bump-pin.sh <X.Y.Z> [repo-root]`; `repository_dispatch` event type `library-released` with `client_payload` `{"library": "calendar-connectors", "version": "X.Y.Z"}`; environment `bump` in both repositories.

- [ ] **Step 1: Failing test**

`scripts/ci/tests/test-bump-pin.sh`:

```bash
#!/usr/bin/env bash
# Tests bump-pin.sh in a throwaway tree.
set -euo pipefail
cd "$(dirname "$0")/../../.."
ROOT="$PWD"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
URL=https://github.com/binary-companion/calendar-connectors
mkdir -p "$T/Apps/macOS" "$T/Packages/A" "$T/Packages/B" "$T/scripts/ci"
cp scripts/ci/check-shared-pins.py "$T/scripts/ci/"
printf 'packages:\n  Sparkle:\n    url: https://github.com/sparkle-project/Sparkle\n    exactVersion: 2.10.0\n  CalendarConnectors:\n    url: %s\n    exactVersion: 1.0.0\n' "$URL" > "$T/Apps/macOS/project.yml"
printf 'let package = Package(dependencies: [.package(url: "%s", from: "1.0.0"), .package(path: "../B")])\n' "$URL" > "$T/Packages/A/Package.swift"
printf 'let package = Package(dependencies: [.package(url: "%s", from: "1.0.0")])\n' "$URL" > "$T/Packages/B/Package.swift"

S="$ROOT/scripts/ci/bump-pin.sh"
"$S" 1.2.3 "$T" >/dev/null
grep -q 'exactVersion: 1.2.3' "$T/Apps/macOS/project.yml" || fail "project.yml not bumped"
grep -q 'exactVersion: 2.10.0' "$T/Apps/macOS/project.yml" || fail "another package's pin changed"
grep -q "from: \"1.2.3\")" "$T/Packages/A/Package.swift" || fail "manifest A floor not raised"
grep -q 'path: "../B"' "$T/Packages/A/Package.swift" || fail "local path dependency changed"
grep -q "from: \"1.2.3\")" "$T/Packages/B/Package.swift" || fail "manifest B floor not raised"
python3 "$T/scripts/ci/check-shared-pins.py" "$T" >/dev/null || fail "result violates the pin contract"
"$S" 1.2.3 "$T" >/dev/null || fail "re-running the same version should succeed"
if "$S" 1.2.2 "$T" >/dev/null 2>&1; then fail "downgrade accepted"; fi
if "$S" v1.3.0 "$T" >/dev/null 2>&1; then fail "v-prefixed version accepted"; fi
if "$S" "1.3.0; rm -rf /" "$T" >/dev/null 2>&1; then fail "shell metacharacters accepted"; fi
"$S" 2.0.0 "$T" >/dev/null
grep -q 'exactVersion: 2.0.0' "$T/Apps/macOS/project.yml" || fail "major bump not applied"
echo PASS
```

Run: `chmod +x scripts/ci/tests/test-bump-pin.sh && scripts/ci/tests/test-bump-pin.sh` — Expected: FAIL (script missing).

- [ ] **Step 2: Implement**

`scripts/ci/bump-pin.sh`:

```bash
#!/usr/bin/env bash
# Moves the calendar-connectors pin to a released version.
#
#   scripts/ci/bump-pin.sh <X.Y.Z> [repo-root]
#
# Sets exactVersion in Apps/macOS/project.yml and the `from:` floor in every Packages/*/Package.swift
# that depends on the library. Refuses anything that is not X.Y.Z and refuses to go backwards.
set -euo pipefail
version="${1:?usage: bump-pin.sh X.Y.Z [repo-root]}"
cd "${2:-$(dirname "$0")/../..}"
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo "not X.Y.Z: $version" >&2; exit 2; }
current="$(perl -0ne 'print $1 if /CalendarConnectors:\n\s+url: [^\n]*calendar-connectors\n\s+exactVersion: ([0-9.]+)/' Apps/macOS/project.yml)"
[ -n "$current" ] || { echo "Apps/macOS/project.yml has no calendar-connectors pin" >&2; exit 2; }
if [ "$(printf '%s\n%s\n' "$current" "$version" | sort -V | head -1)" != "$current" ]; then
  echo "refusing to move the pin back from $current to $version" >&2
  exit 2
fi
perl -0pi -e "s#(CalendarConnectors:\n\s+url: [^\n]*calendar-connectors\n\s+exactVersion: )[0-9.]+#\${1}$version#" Apps/macOS/project.yml
for m in Packages/*/Package.swift; do
  perl -0pi -e "s#(\.package\(url: \"https://github\.com/binary-companion/calendar-connectors\", from: \")[0-9.]+(\"\))#\${1}$version\${2}#g" "$m"
done
echo "calendar-connectors pinned at $version (was $current)"
```

Run: `chmod +x scripts/ci/bump-pin.sh && scripts/ci/tests/test-bump-pin.sh` — Expected: `PASS`. Then `python3 scripts/ci/check-shared-pins.py` (real tree) — Expected `PASS: shared pins`.

- [ ] **Step 3: The workflow in `timetug`**

`.github/workflows/bump-dependencies.yml`:

```yaml
# Opens "Bump calendar-connectors to X.Y.Z" when the library releases (repository_dispatch from its
# release workflow), or on demand. The pull request is opened with a timetug-bot token so its CI runs;
# the bot cannot merge. The version is validated by scripts/ci/bump-pin.sh before it touches a file.
name: Bump dependencies

on:
  repository_dispatch:
    types: [library-released]
  workflow_dispatch:
    inputs:
      version:
        description: "calendar-connectors version (X.Y.Z)"
        required: true
        type: string

concurrency:
  group: bump-calendar-connectors
  cancel-in-progress: false

permissions: {}

jobs:
  bump:
    if: github.event_name == 'workflow_dispatch' || github.event.client_payload.library == 'calendar-connectors'
    runs-on: ubuntu-latest
    environment: bump
    permissions:
      contents: read
    env:
      VERSION: ${{ github.event.client_payload.version || inputs.version }}
    steps:
      - id: app
        uses: actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510 # v3
        with:
          app-id: ${{ vars.BUMP_APP_ID }}
          private-key: ${{ secrets.BUMP_APP_PRIVATE_KEY }}
          owner: ${{ github.repository_owner }}
          repositories: timetug
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
        with:
          ref: master
          token: ${{ steps.app.outputs.token }}
      - name: Move the pin
        run: scripts/ci/bump-pin.sh "$VERSION"
      - name: Open the pull request
        env:
          GH_TOKEN: ${{ steps.app.outputs.token }}
        run: |
          set -euo pipefail
          if git diff --quiet; then echo "Already at $VERSION; nothing to do."; exit 0; fi
          branch="bump/calendar-connectors-$VERSION"
          git config user.name "timetug-bot"
          git config user.email "timetug-bot@users.noreply.github.com"
          git switch -c "$branch"
          git commit -am "Bump calendar-connectors to $VERSION"
          git push origin "$branch"
          {
            echo "Moves the pinned connector library to $VERSION. CI on this pull request proves the app still builds and passes its tests."
            echo
            echo "## Release notes"
            gh release view "$VERSION" --repo binary-companion/calendar-connectors --json body --jq .body
            echo
            echo "🤖 Opened by timetug-bot"
          } > "$RUNNER_TEMP/body.md"
          gh pr create --base master --head "$branch" \
            --title "Bump calendar-connectors to $VERSION" --body-file "$RUNNER_TEMP/body.md"
```

- [ ] **Step 3a: Record the pin and the environment expectation**

In `docs/development/action-pins.md` add the table row `` | `actions/create-github-app-token` | `v3` | `64ab729a6294000f5aa4a4bc0b73d1f32bc45510` | ``. In `scripts/ci/tests/check-workflow-contracts.py` add `'bump-dependencies.yml': 'bump',` to `EXPECTED_ENVIRONMENTS`. Run `scripts/ci/tests/test-workflows.sh` — Expected: `PASS: workflow contracts` (every action is pinned by a 40-hex commit, and the job that reads `BUMP_APP_PRIVATE_KEY` declares `environment: bump`).

- [ ] **Step 4: Environments and secrets (agent, after Task 11)**

```bash
for r in timetug calendar-connectors; do
  gh api -X PUT "repos/binary-companion/$r/environments/bump" --input - <<JSON
{"can_admins_bypass": false, "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
done
gh api -X POST repos/binary-companion/timetug/environments/bump/deployment-branch-policies -f name=master -f type=branch --jq .name
gh api -X POST repos/binary-companion/calendar-connectors/environments/bump/deployment-branch-policies -f name=main -f type=branch --jq .name
for r in timetug calendar-connectors; do
  gh variable set BUMP_APP_ID --env bump --repo "binary-companion/$r" --body "$APP_ID"
  gh secret set BUMP_APP_PRIVATE_KEY --env bump --repo "binary-companion/$r" < "$KEY_FILE"
done
```

`$APP_ID` and `$KEY_FILE` are what the owner gave in Task 11 step 4. Never print the key or echo it. Expected: `master`, `main`, and no errors.

- [ ] **Step 5: The `notify` job in the library**

Add to `$LIB/.github/workflows/release.yml` after `publish` (on a branch `claude/notify-dependents` in `$LIB`, pushed as a pull request to `calendar-connectors`; the owner merges it):

```yaml
  notify:
    needs: publish
    if: needs.publish.outputs.version != ''
    runs-on: ubuntu-latest
    environment: bump
    permissions:
      contents: read
    steps:
      - id: app
        uses: actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510 # v3
        with:
          app-id: ${{ vars.BUMP_APP_ID }}
          private-key: ${{ secrets.BUMP_APP_PRIVATE_KEY }}
          owner: ${{ github.repository_owner }}
          repositories: timetug
      - name: Tell the dependents
        env:
          GH_TOKEN: ${{ steps.app.outputs.token }}
          VERSION: ${{ needs.publish.outputs.version }}
        run: |
          for dependent in timetug; do
            gh api "repos/binary-companion/$dependent/dispatches" \
              -f event_type=library-released \
              -f "client_payload[library]=calendar-connectors" \
              -f "client_payload[version]=$VERSION"
          done
```

Also add `scripts/ci/check-repository-contracts.py` coverage: the `bump` environment satisfies the secrets rule (job has `environment`).

- [ ] **Step 6: Commit and open pull requests**

In `timetug` (branch `claude/phase-1-bump-loop` from the merged flip): `git add -A && git commit -m "Open bump pull requests when calendar-connectors releases ..." && git push` and `gh pr create` (title "Bump calendar-connectors automatically on release"; body as the other pull requests, with the 🤖 footer). In `$LIB`: branch, commit, push, `gh pr create --repo binary-companion/calendar-connectors` with the `semver:patch` label. Both are the owner's to merge. Run locally first: `scripts/ci/tests/test-bump-pin.sh`, `scripts/ci/tests/test-workflows.sh`, `python3 scripts/ci/check-repository-contracts.py`.

### Task 13: The drill

- [ ] **Step 1:** In `$LIB`, a docs-only change on a branch: add one sentence to the README ("Releases are published automatically; see `docs/api.md` for the contract."), open a pull request with **no** label, let CI pass, ask the owner to merge.
- [ ] **Step 2:** Watch: `gh run list --repo binary-companion/calendar-connectors --workflow Release --limit 1`. Expected: `publish` and `notify` succeed; `gh release view 1.0.1 --repo binary-companion/calendar-connectors` exists.
- [ ] **Step 3:** In `timetug`: `gh pr list --repo binary-companion/timetug --search "Bump calendar-connectors to 1.0.1"`. Expected: one open pull request from branch `bump/calendar-connectors-1.0.1`, authored by `timetug-bot`, with the release notes in its body, and its checks (`core`, `app`, `dmg`, `architecture`, `core-linux`) green without anyone touching it.
- [ ] **Step 4:** Ask the owner to merge it. After the merge, `git grep -n 'exactVersion: 1.0.1' Apps/macOS/project.yml` on `master` and a `Beta` run on that commit.
- [ ] **Step 5:** If any link of the chain failed, fix it (Task 12) and repeat the drill with a new docs-only change; each repeat makes a new patch version, which is acceptable.

### Task 14: Cross-repository skill, instructions, tracker

**Files:**
- Create in `timetug`: `.agents/skills/working-across-timetug-repos/SKILL.md` (and the symlink `.claude/skills/working-across-timetug-repos` the other project skills use; check with `ls -l .claude/skills`)
- Modify: `docs/superpowers/plans/2026-10-09-windows-program-tracker.md`

- [ ] **Step 1: Skill**

```markdown
---
name: working-across-timetug-repos
description: Use when a change spans TimeTug repositories (the connector library and the Mac app), when the connector library must change, or when testing unreleased library code in the app, or when a "Bump calendar-connectors" pull request appears.
---

# Working across the TimeTug repositories

The connector library is `binary-companion/calendar-connectors`; `timetug` pins a released version of it.

## Change the library

1. Work in a checkout of `calendar-connectors`. Branch, change, `swift test`, `scripts/ci/check-architecture.sh`.
2. To try it in the app before it is released: in `timetug`, `scripts/dev/use-local-connectors.sh <path to the checkout>`, build and test, then `scripts/dev/use-local-connectors.sh --restore`. `scripts/ci/check-shared-pins.py` fails while the override is in place, so it cannot be committed.
3. Open the library pull request with one label: `semver:major` (breaking `docs/api.md`), `semver:minor` (new API) or `semver:patch`. The owner merges; the release is automatic.
4. `timetug-bot` opens "Bump calendar-connectors to X.Y.Z" in `timetug`. CI there proves the app. The owner merges it. If a library change needs app code in the same step, push that code to the bump pull request's branch.

## Rules

- Never tag or release the library by hand, and never edit `exactVersion` or a `from:` floor by hand (`scripts/ci/bump-pin.sh <X.Y.Z>` does both).
- Platform adapters (`CalendarApple`, `EventKitSource`) stay in `timetug`; they implement the library's seams.
- Library tests that need real accounts run from the library checkout (see `running-live-calendar-tests`).
```

- [ ] **Step 2: Tracker and instructions**

Tracker: phase 1 row `done` with the pull request links; tick the `timetug-bot` and drill items; session log line. Check that `AGENTS.md` in `timetug` links the skill (Task 10 did) and that `$LIB/AGENTS.md` names it.

- [ ] **Step 3: Verify and commit**

```bash
scripts/dev/verify.sh affected 2>&1 | tail -5
git add -A && git commit -m "Add the cross-repository skill and close phase 1 in the tracker

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Open the pull request; the owner merges. Phase 1 is done when: the library repository is public with `1.0.0` and the audit passes, `timetug` builds from the released tag, the drill produced a green bump pull request unaided, and the tracker says so.
