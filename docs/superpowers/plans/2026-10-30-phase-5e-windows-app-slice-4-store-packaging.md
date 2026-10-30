# Phase 5e: Windows app slice 4 (Store packaging) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In `binary-companion/timetug-windows`, produce release-shaped packages: a Store variant and a website-ready variant of the MSIX, built with no development scaffolding (no `SELFTEST`, no `timetug-dev` execution alias, no throwaway certificate identity), with the Google and Microsoft OAuth client ids injected from the release environment, plus the manifests and placeholders phase 9 needs. Store submission itself stays phase 9.

**Architecture:** One codebase, three build flavours selected by MSBuild properties: `Dev` (today's CI package), `Store` (identity reserved in Partner Center, `STORE` constant, Microsoft re-signs) and `Direct` (identity `BinaryCompanion.TimeTug`, signed in CI later; build only, signing deferred). Release flavours are self-contained for the Windows App SDK runtime question the spike answers. OAuth ids reach release builds only through a generated source file written by the release job from environment secrets, never committed. A manual `windows-release.yml` workflow (default branch or a `vX.Y.Z` tag only, as `appstore.yml`) builds both architectures, uploads an unsigned `.msixupload`-shaped artifact, and does not submit.

**Tech Stack:** .NET 10, WinUI 3, Windows App SDK 2.5.1, MSBuild, PowerShell, GitHub Actions (`windows-latest`, `windows-11-arm`), Windows SDK `makeappx`/`signtool`, Windows App Certification Kit (WACK).

**Spec:** `docs/superpowers/specs/2026-10-16-phase-5-windows-app-core-design.md` (slice 4; Testing and CI) and `docs/superpowers/specs/2026-10-09-windows-program-design.md` section 6 (Distribution).

## Global Constraints

- Release flavours define neither `SELFTEST` nor any self-test entry point; an architecture/contract test fails the build if a release assembly contains the self-test runner.
- The `timetug-dev` execution alias, the `CN=TimeTug Development` publisher and the dev-oauth file read exist only in `Dev` builds.
- The Store and Direct flavours have different identities and therefore separate data (program design section 6); no code shares a data folder across them.
- Release builds read no `%LOCALAPPDATA%\TimeTug\dev-oauth.json`. PR and merge-to-main CI builds embed no OAuth ids. Ids are never printed, logged, committed or placed in artifact names.
- Secrets are only available to the `release` GitHub environment (owner approval required). No signing material or Partner Center credentials in pull-request jobs.
- The workflow accepts only the default branch or a tag matching `^v[0-9]+\.[0-9]+\.[0-9]+$` as its ref; suffixed tags build the flight variant (`-beta`), never the stable one.
- Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR bodies end `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Owner-only: release environment approval, Partner Center account and identity values, brand/publisher verification. Agents never invent identity values; placeholders are named `__PARTNER_CENTER_*__`.

## Review Focus

- A release package that still exposes a self-test switch or the dev alias (test: contract check over the built manifest and assemblies).
- OAuth ids leaking into logs, diagnostics ("Copy diagnostics") or artifacts (test: scan built output and the diagnostics payload for the injected sentinel in CI using a fake id).
- A release build with no ids injected silently showing a working Google/Microsoft button (test: provider unavailable with a clear Settings message, never a crash).
- Upgrading a Dev-installed copy to a release package on the same machine (different identity: both run side by side; single-instance arbitration must detect the other distribution and show the collision notice, per program design section 6 table).
- Version numbers: MSIX requires `Major.Minor.Build.0` with revision 0 for the Store; tag `v1.2.3` must map to `1.2.3.0` and be rejected otherwise.

---

### Task 0: Spike: runtime packaging choices

**Files:** `docs/spikes/2026-10-store-packaging.md`.

- [ ] **Step 1:** On a CI runner and the VM, answer: (a) can a `WindowsAppSDKSelfContained=true` MSIX be built and installed for x64 and ARM64, and what is the size difference against the framework-dependent package? (b) does the Store accept a framework-dependent package (the Windows App SDK framework package dependency resolves from the Store) and which is the recommended default for Store variant; (c) does `dotnet publish` produce a package whose manifest can drop the `uap5:ExecutionAlias` by a conditional in the csproj or a manifest transform; (d) what does WACK report for the dev package and for a release-shaped one (run `appcert.exe test` on the VM, record failures).
- [ ] **Step 2:** Record the decision and its cost; if self-contained is required, amend Task 2 before building. Merge as a docs-only PR "Spike: store packaging findings".

### Task 1: Build flavours and manifest variants

**Files:** `Directory.Build.props`, `src/TimeTug.App/TimeTug.App.csproj`, `src/TimeTug.App/Package.appxmanifest` (and `Package.Store.appxmanifest`, `Package.Direct.appxmanifest` if a transform is not workable), `src/TimeTug.Platform/BuildFlavour.cs`, tests.

**Interfaces:** `BuildFlavour` (Platform): `enum Flavour { Dev, Store, Direct }`, `static Flavour Current` from compile constants `STORE`/`DIRECT` (neither = Dev). `AppIdentity.DisplayName`, `AppIdentity.DataNamespace` (diagnostics only) read from it.

- [ ] **Step 1: Write the failing tests:** `BuildFlavour` resolves from constants (use a test seam); a contract check reads each manifest variant and asserts: Dev has the `timetug-dev` alias and `CN=TimeTug Development`; Store and Direct have no alias, no `runFullTrust` beyond what the Dev manifest already needs, and a publisher/name placeholder that matches `__PARTNER_CENTER_*__` (Store) or `CN=Binary Companion` (Direct, placeholder until signing exists).
- [ ] **Step 2:** Run (FAIL), implement flavour properties (`-p:Flavour=Store|Direct|Dev`, default Dev) setting `DefineConstants`, the manifest file and the package display name/logo set; keep Dev byte-identical in behaviour to today. Run (PASS) and verify the Dev package still installs on the VM and `--selftest` scenarios run.
- [ ] **Step 3: Commit** — `git commit -m "Build flavours: Dev, Store, Direct"`.

### Task 2: Release build script and no-development-scaffolding checks

**Files:** `scripts/release/build-release-msix.ps1`, `scripts/ci/check-release-package.ps1`, `tests/TimeTug.Architecture.Tests/*`.

**Interfaces:** `build-release-msix.ps1 -Flavour Store|Direct -Platform x64|ARM64 -Version 1.2.3 -OutputFolder <dir> [-Prerelease]` produces an unsigned package and an `*.msixupload`-shaped zip (x64 + ARM64 bundle step is Task 4); `check-release-package.ps1 -Package <path>` fails on any forbidden content.

- [ ] **Step 1: Write the failing tests/checks:** `check-release-package.ps1` asserts on an unpacked package: no assembly defines the self-test runner type (`TimeTug.App.SelfTest.*`), manifest has no alias and no dev publisher, version is `X.Y.Z.0`, both required icon scales are present, no `dev-oauth` reference in any string table. Wire a Pester/pytest test using a deliberately bad fixture package that must fail.
- [ ] **Step 2:** Implement the script (version validation: reject tags that are not `X.Y.Z`; suffix only via `-Prerelease` and then only the flight flavour name), run on both runners and the VM. Apply the Task 0 decision (self-contained or framework-dependent).
- [ ] **Step 3: Commit** — `git commit -m "Release build script and package checks"`.

### Task 3: OAuth id injection for release builds

**Files:** `scripts/release/write-oauth-ids.ps1`, `src/TimeTug.Platform/OAuth/ReleaseOAuthIds.cs` (generated at build, git-ignored), `src/TimeTug.Platform/OAuth/OAuthIdProvider.cs`, tests.

**Interfaces:** `IOAuthIdProvider.Get(Provider) → string?` with `DevFileOAuthIdProvider` (Dev only: reads `dev-oauth.json`) and `EmbeddedOAuthIdProvider` (Store/Direct: reads the generated class). `write-oauth-ids.ps1` reads `GOOGLE_OAUTH_CLIENT_ID` and `MICROSOFT_OAUTH_CLIENT_ID` from the environment and writes the file without echoing them; fails if either is unset when `-Require` is passed.

- [ ] **Step 1: Write the failing tests:** each provider returns null in a build with no ids and the Settings/welcome view models show the "sign-in unavailable in this build" state (copy approved: "Google sign-in isn't set up in this build.") instead of a button that fails; a sentinel id injected in a test build never appears in the diagnostics payload, logs or any file under the build output except the compiled assembly resource.
- [ ] **Step 2:** Implement; add the CI contract test using a fake sentinel id; confirm Dev builds still read `dev-oauth.json` and Release builds do not.
- [ ] **Step 3: Commit** — `git commit -m "Inject OAuth ids into release builds"`.

### Task 4: Release workflow and Store upload artifact

**Files:** `.github/workflows/windows-release.yml`, `docs/release.md`, `scripts/release/bundle-msixupload.ps1`.

- [ ] **Step 1:** Workflow `windows-release.yml`: `workflow_dispatch` plus `release: published`; ref rule as in Global Constraints; jobs `build-x64` and `build-arm64` on matching runners in the `release` environment (secrets: the two OAuth ids only), then a bundle job that makes the `.msixbundle`/`.msixupload` artifact (unsigned for Store) and uploads it as a workflow artifact; stable tags `vX.Y.Z` build `Store` with `STORE`; suffixed tags build the flight package. No Partner Center credentials and no submit step in this slice; a TODO-free note in `docs/release.md` says phase 9 adds the submit step.
- [ ] **Step 2:** Add a PR-safe dry run: the same workflow with `dry_run=true` on a pull request builds a Dev-signed flavour of Store with a fake sentinel id and runs `check-release-package.ps1` and WACK (as non-blocking report on ARM64 if it cannot run there); wire the dry-run job as a required check once stable (owner action, listed in the report).
- [ ] **Step 3:** Run the dry run on the PR, then dispatch the real workflow from `main` (owner approves the environment); verify the artifact and run `check-release-package.ps1` on it. Do not install the Store-flavoured package on the VM alongside Dev unless testing single-instance arbitration.
- [ ] **Step 4: Commit** — `git commit -m "Windows release workflow (Store package artifact)"`.

### Task 5: Single instance across distributions

**Files:** `src/TimeTug.Platform/AppInstanceService.cs`, tests, `docs/manual-tests/windows-checklist.md`, `docs/parity.md`.

- [ ] **Step 1: Write the failing tests:** with a fake of the other distribution's named mutex/instance key present, startup shows the collision notice ("TimeTug is already running from a different installation. Close it to use this copy.") and exits without starting the engine or touching the data; with only the same distribution's instance present, the existing redirect behaviour is unchanged.
- [ ] **Step 2:** Implement (named kernel object shared across flavours, distinct from the package-scoped `AppInstance` key), run unit tests and a VM scenario `cross-flavour-instance` that runs Dev and a locally-built Direct package together.
- [ ] **Step 3: Commit** — `git commit -m "Detect another TimeTug distribution"`.

### Task 6: Store listing inputs, checklist, parity, review and close

**Files:** `docs/store/` (listing text, privacy URL, capabilities justification, age-rating answers draft, screenshot shot list), `docs/manual-tests/windows-checklist.md`, `docs/parity.md`, `docs/development.md`.

- [ ] **Step 1:** Draft `docs/store/listing.md` (name, short and long description matching the Mac listing text and the provider list, keywords, support and privacy URLs from the website repo), `docs/store/capabilities.md` (why `runFullTrust`/capabilities are declared), and a screenshot shot list from scripted scenario data (no real calendars). Add owner checklist items: reserve the app name and identity in Partner Center (link), copy identity values into the manifest placeholders, approve the `release` environment for the first real run, install the release package from the artifact in a clean user profile, complete the first sign-in with real accounts.
- [ ] **Step 2:** Run the `deepseek-review` skill on the whole diff (never send secrets; verify findings), fix real defects with tests first; run the full self-test suite on both runners and the VM; confirm PR checks green.
- [ ] **Step 3:** Update `docs/parity.md`, `docs/development.md` (how to build each flavour, how to run the dry run), the program tracker owner items, and close: one PR "Store packaging" per task group is acceptable; squash-merge each when green.
- [ ] **Step 4: Commit** — `git commit -m "Store listing inputs and docs"`.
