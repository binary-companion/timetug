# TimeTug for Windows: program tracker

This is the saved progress for the Windows program. It is updated at the end of every working session and committed with that session's work, so any later session (or agent) can resume from it.

**Spec:** [`docs/superpowers/specs/2026-10-09-windows-program-design.md`](../specs/2026-10-09-windows-program-design.md) (approved 2026-10-09).

## How to resume

1. Read the spec once, then this file.
2. Go to **Now**. The first unchecked item is the next thing to do. Items marked **(owner)** are for the owner; agents never do them (publishing releases, approving deployments, merging, console changes in Google, Microsoft, Apple or GitHub settings, entering credentials).
3. Before starting a phase, check that its spec and plan exist (links in the phase table). A phase without a plan gets one first: a short phase spec (brainstorming), then a plan (writing-plans), both linked here.
4. When you finish an item: check it, add a line to the **Session log**, and commit this file with the work.
5. When a phase's last item is done, set its status to `done` and add its PR links.

Status values: `not started`, `planning`, `in progress`, `blocked` (say on what), `done`.

## Phases

| Phase | Status | Spec | Plan | PRs |
|---|---|---|---|---|
| S Spike: Swift on Windows | done; approach A confirmed 2026-10-09 | spec section 9 | [plan](2026-10-09-windows-spike-s.md) | [findings](../../spikes/2026-10-09-swift-on-windows.md) |
| A Secrets into environments (standalone, Mac repo) | done except one check: the `release` environment is verified by the 2.1.0 release run | spec section 8 | [plan](2026-10-09-phase-a-secrets-into-environments.md) | PR 75 |
| 1.5 Domain and branding | in progress: site, redirects, Google and Entra branding done; waiting on the Microsoft Partner Program vetting, then publisher verification | spec section 1.5 | [plan](2026-10-10-phase-1-5-domain-and-branding.md) | PRs 78, 79 |
| 0 Organization move and hardening | in progress: transfers, controls and audit done (2026-10-11); the Mac release carrying the new feed URL is the last item | spec sections 1 and 8 | n/a | PRs 88 to 91 |
| 1 `calendar-connectors` repository | in progress: library published as 1.0.0 (2026-10-13), flip merged (PR 97, 2026-10-13); `timetug-bot` loop and drill remain | spec section 1, [phase spec](../specs/2026-10-12-phase-1-calendar-connectors-design.md) | [plan](2026-10-12-phase-1-calendar-connectors.md) | PR 97 |
| 2 `timetug-shared` repository | not started | spec section 1 | to write | |
| 3 Engine | not started | spec section 2 | to write | |
| 4 C interface and NuGet | not started | spec section 2 | to write | |
| 5 Windows app core | not started | spec sections 3 and 4 | to write | |
| 6 WAM sign-in | not started | spec section 4.5 | to write | |
| 7 Widgets | not started | spec section 4 | to write | |
| 8 On-device AI | not started | spec section 5 | to write | |
| 9 Store 1.0 | not started | spec section 6 | to write | |
| Deferred: signed website download | not started | spec section 6 | trigger not met | |

Order: S first. A and 1.5 can run alongside S. Phase 0 needs the 1.5 domain live. Phases 1 to 5 are sequential; 6, 7 and 8 follow 5 in any order; 9 needs 5, 6 and 7.

## Now

- [x] **(owner)** Confirm the Sparkle key in the login keychain is the one the app trusts. Confirmed 2026-10-09: `generate_keys -p` prints the key in `SUPublicEDKey`.
- [x] **(owner)** Export a backup of the Sparkle private key into the password manager. Done 2026-10-09 (1Password); the exported file must be deleted from the Mac.
- [x] **(owner)** Prepare the Windows VM for Spike S (plan Task 1). Done 2026-10-09: the agent installed the tools itself through `prlctl exec`.
- [x] Spike S, plan Tasks 2 to 5. Done 2026-10-09; findings in `docs/spikes/2026-10-09-swift-on-windows.md`.
- [x] **(owner)** Review the Spike S findings and decide on approach A. Decided: approach A, 2026-10-09.
- [x] Apply the spike's six recommendations to the spec. Done in the approach A decision PR.
- [x] Write the plan for phase A. Written 2026-10-09.
- [x] Phase A code tasks 1 to 3 done (contract test, `environment:` lines, docs); PR open.
- [x] **(owner)** Squash-merged the phase A PR (PR 75, 2026-10-10).
- [x] Beta run `38096181528` failed because the `MACOS_PROVISIONING_PROFILE_BASE64` copy in `beta` and `release` was damaged (the file in Downloads contains U+FFFD replacement bytes and does not decode). Both environment copies deleted 2026-10-10 so the repository-level copy applies; run re-queued. **(owner)** Download a fresh Developer ID profile from the developer portal as a binary file; the agent checks it with `security cms -D` before setting it in `beta` and `release`. Resolved 2026-10-11: a fresh profile was set on `beta` and `release`, and the beta runs since then passed.
- [ ] Verify `release` (next release), `appstore` (trial upload, `ref=master`) and `hosting` (next `site/` change); then, with the owner's go, delete the repository-level copies and the old Firebase key (plan Task 5). Update 2026-10-12: the repository-level copies are already deleted; the 2.1.0 release run is the `release` verification.
- [x] **(owner)** Add one DNS record at Squarespace (Domains > binarycompanion.com > DNS Settings): type `CNAME`, host `timetug`, data `timetug-site.web.app`. Then the agent checks the certificate, you mark PR 79 ready and merge (cutover), and the agent moves `timetug.obryan.cloud` to `timetug-redirect`. Done: `timetug.binarycompanion.com` serves the site, and `timetug.obryan.cloud` 301-redirects to it (checked 2026-10-12).
- [x] **(owner)** Fresh Developer ID provisioning profile (binary download) for `beta` and `release`. Done 2026-10-11.
- [ ] The Microsoft app has no verified publisher and no branding URLs (measured 2026-10-10); Task 5 in the phase 1.5 plan covers it. Owner chose the existing tenant (R6). `binarycompanion.com` is added to it and awaits one TXT record at Squarespace (value in plan Task 5). **(owner)** completes the Squarespace Google step-up sign-in; then the agent verifies the domain and creates `sobryan@binarycompanion.com`, and the owner starts the Partner Center account as that user.

## Owner checklist by phase

Agents keep this list current; the owner checks items off (or tells an agent to).

### A Secrets into environments
- [ ] Locate or recreate each value (see **Where each secret comes from** at the end of this file).
- [ ] Create the `beta` environment (deployment branch `master` only, no reviewer) and enter the beta signing values there.
- [ ] Enter the release values into `release`; turn off admin bypass on `release` (not needed on `appstore`, which has no reviewer). Details: phase A plan, Task 4.
- [x] Repository-level copies deleted 2026-10-11 on the owner's go (every value was already in `release`, `beta` or `appstore`; the Developer ID provisioning profile was re-downloaded and set on `release` and `beta`). Only the read-only `DOCKERHUB_*` pair remains at repository level. Still to watch: the first beta and release runs that resolve everything from environments.

### 1.5 Domain and branding
- [x] Confirm ownership of `binarycompanion.com` and DNS access. Verified 2026-10-10: registered at Squarespace Domains, DNS at Squarespace, expires 2028-10-02 (the spec's earlier spelling with an "s" was wrong).
- [ ] Add the `timetug` DNS records at Squarespace (plan Task 2) and sign `scott@obryan.cloud` in to `gcloud` and `firebase`.
- [x] Verify `binarycompanion.com` in Google Search Console as an owner of the OAuth project (done 2026-10-11 from `darkarena@gmail.com`).
- [ ] Enroll Binary Companion in the Microsoft AI Cloud Partner Program as `sobryan@binarycompanion.com` (sign in with it; do not use "Create work account"); get a D-U-N-S number if Binary Companion has none; business verification is the slow step. Then give the agent the Partner Global Account ID (not the location ID).
- [x] Microsoft Entra: choose the tenant (existing "Default Directory"; ruling R6, 2026-10-10).
- [x] Microsoft Entra: `binarycompanion.com` verified on the tenant (2026-10-10, TXT at Squarespace).
- [x] Microsoft Entra: work user `sobryan@binarycompanion.com` created 2026-10-10 (password changed by the owner at first sign-in; roles Application Administrator and, for enrollment, Global Administrator, to be removed once enrollment is Active).
- [x] Microsoft Entra: update homepage, terms and privacy URLs and the logo (done 2026-10-10 after the cutover; read back with Graph).
- [ ] Microsoft Entra: verify the publisher domain, then re-run publisher verification with the Binary Companion partner ID.
- [x] Google: bundled brand edit saved, verified and published 2026-10-11 (new URLs live on the consent screen).
- [x] Google: `obryan.cloud` removed from Authorized domains (2026-10-11); only `binarycompanion.com` remains.
- [x] App Store Connect: privacy, support and marketing URLs updated, and the macOS 1.0 listing text drafted and saved (2026-10-11). Still the owner's before submission: screenshots, build, age rating, App Privacy answers, content rights, pricing, review contact, EU trader status.

### 0 Organization move
- [ ] Publish the Mac release that carries the new feed URL; wait for users to take it (watch the appcast download counts).
- [x] 2FA requirement, no member repository creation, Actions allow-list and SHA pinning done by the owner 2026-10-11 (the owner removed SMS from their account first, which the secure-methods option requires). `audit-github.sh --strict` passed with 0 failed, 0 skipped.
- [x] Docker Hub (done 2026-10-11): `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` are now organization secrets on `binary-companion`, visible to `timetug` only (a fresh read-only token from the Binary Companion Docker Hub account, validated against `auth.docker.io` before it was stored). The repository-level copies are deleted, and a `core-linux` re-run logged in and pulled the Swift image from them. Owner: revoke the old Docker Hub token. When `timetug-shared` and `calendar-connectors` run Linux CI, add them to the secrets' repository list.
- [x] Transferred 2026-10-11: `darkarena1/timetug` and `binary-companion-llc/homebrew-tap` to `binary-companion`. Rulesets, the five environments with their secrets, the repository-level Docker Hub secrets and Pages (now `https://binary-companion.github.io/timetug/`) came across intact; git and web URLs redirect. Before the transfer `darkarena1/darkarena1.github.io` was created and verified (hourly appcast mirror) so copies that ask `https://darkarena1.github.io/timetug/appcast.xml` keep updating. The Workload Identity provider already trusted `binary-companion/timetug`. Ruling: the transfer ran before the Mac release carrying the new feed URL because the mirror makes that order safe; the release (next item) is still owed.
- [x] After the transfer PR merges: confirm `https://timetug.binarycompanion.com/appcast.xml` redirects to `binary-companion.github.io/timetug/appcast.xml` (the `hosting` deploy), the mirror's next run shows no change, and the `tap` CI passes under `binary-companion/tap`. Checked 2026-10-12: the appcast path answers 301 to `binary-companion.github.io/timetug/appcast.xml`, the mirror's hourly runs succeed, and the tap's CI and `Bump casks` pass on `main` (tap PRs 2 to 4: SHA-pinned checkout, the audit authenticated with the workflow token, license holder Binary Companion LLC).
- [ ] Audit script written (2026-10-11): `scripts/security/audit-github.sh [--strict] binary-companion website darkarena1/timetug` (it moves to the organization's `.github` repository, as spec section 8 says, once that exists after the transfer). It must pass with `--strict` after `gh auth refresh -s admin:org`. Last run: fails because (1) organization 2FA is not required, (2) members can create repositories, (3) `darkarena1/timetug` still has repository-level secrets (the environment copies exist; delete the repository copies after the owner verifies `release`, `appstore` and `hosting`); the Actions policy check is skipped without `admin:org`. `appstore` admin bypass was turned off on 2026-10-11.

### 1 `calendar-connectors` repository
- [ ] **(owner)** Create the `timetug-bot` GitHub App and install it on the dependent repositories (today `timetug` only), plan Task 11: repository permissions Contents: Read and write, Pull requests: Read and write, Metadata: Read-only and nothing else; webhook inactive; installable on this account only; then give the agent the App ID and the path of the `.pem` key.
- [x] **(owner)** Reviewed and merged the flip pull request (PR 97, 2026-10-13): the app consumes the released library and the in-repo copy is gone.

### Later phases
- Phase 4: create the Binary Companion nuget.org account and configure trusted publishing for `TimeTug.Engine`.
- Phase 6: add the WAM broker redirect URI to the Entra app registration.
- Phase 8: choose the real-hardware check (spec section 5, layer 3).
- Phase 9: Store listing, IARC rating, screenshots; create the tester flight group.

## Waiting on

| Item | Since | Unblocks |
|---|---|---|
| | | |

## Open questions

- None yet.

## Session log

Append one line per session: date, what was done, what is next.

- 2026-10-09: Program spec written, reviewed (DeepSeek: 14 findings, all real, fixed) and approved. Read-only security audit of `darkarena1/timetug` and `binary-companion` (findings in spec section 8). Sparkle key found in the login keychain (item created 2026-09-20); public-key match not yet confirmed. Next: owner prepares the VM, then Spike S.
- 2026-10-09: Checked master's #69 (App Store manual runs accept only `master` or a `vX.Y.Z` tag). It matches the spec; the Windows stable workflow copies the rule. `appstore` has no required reviewer; the owner accepted that (can be added later), recorded in spec section 8.
- 2026-10-09 (later): Spike S done. All three packages pass on Windows 11 ARM64 (98, 299, 13 tests; 0 failures); the Swift DLL exports the four C functions and a .NET 10 host calls them with an off-thread callback; runtime 57.4 MB minimal (ICU is 36 MB); Foundation probe all PASS. Merged PR 71 (Docker Hub login for `core-linux`); amended the secrets rule for read-only CI tokens. Next: owner decides on approach A, then phase A (secrets into environments) and 1.5 can start.
- 2026-10-09 (later still): Owner chose approach A. Spec updated with the six Spike S recommendations (`.gitattributes`, `--show-bin-path`, parsed-JSON fixtures, proxy note, runtime size and x64 risks). Sparkle public key confirmed by the owner. Next: phase A plan, then phase 1.5.

- 2026-10-10: Phase A: environments `beta`/`hosting` created, `release` admin bypass off; all values entered by the agent from local files (Developer ID certificate exported by the owner; notary key `L57LKGZZZ4`, App Store key `RGSA38Z6TF`); code PR with the contract test, `environment:` lines and docs. Next: owner merges, then verification runs and deletion of repository-level copies.
- 2026-10-10 (evening): PR 75 merged. The first `Beta` run from the environment failed at signing: the provisioning profile copied into `beta` and `release` came from a damaged download. Both environment copies were deleted (the repository-level copy still applies) and the run re-queued. Lesson: decode every file-derived value locally before setting it. The domain is `binarycompanion.com` (no "s"); the phase 1.5 plan is written (`2026-10-10-phase-1-5-domain-and-branding.md`), and the old domain stays on the existing site and becomes redirect-only (ruling R2).
- 2026-10-10 (night): Beta from the `beta` environment passed end to end (signing, EdDSA from the environment's Sparkle key, publish, appcast) using the repository-level profile. PR 78 merged; site PR 79 opened as a draft. Entra read-only: the app has no verified publisher and no branding URLs. Firebase site creation is blocked by an unaccepted terms dialog (owner's call).
- 2026-10-10 (night, later): Owner supplied the Binary Companion website source (the apex site was deployed from the console and had no repository). Created `binary-companion/website` (public), key-free Firebase deploy through Workload Identity Federation in project `binary-companion`, `production` environment limited to `main`. Phase 1.5 plan Task 8.
- 2026-10-11: Owner chose to host TimeTug's website in Firebase under the `obryan.cloud` account. Sites `timetug-site` and `timetug-redirect` created in project `binary-companion`; federated deploy identity `timetug-deploy` (provider `timetug`); PR 79 rewritten to deploy key-free; `timetug-site` deployed manually and domain `timetug.binarycompanion.com` added (needs one CNAME). `binary-companion/website` deployed key-free (first run green, both URLs unchanged).
- 2026-10-10 (night, later): Owner approved the existing Entra tenant as Binary Companion's Microsoft identity (R6). `binarycompanion.com` added to the tenant as an unverified custom domain; its verification TXT is recorded in plan Task 5 and needs adding at Squarespace (blocked on the Google step-up sign-in). HTTPS on `timetug.binarycompanion.com` is serving; certificate still propagating at some edges. PR 79 merged by the owner; first key-free deploy from `hosting` succeeded and the new pages, headers and redirect rules were verified. Entra branding URLs and logo set. Still open: move `timetug.obryan.cloud` to `timetug-redirect`, merge `binary-companion/website` PR 1, delete the obsolete Firebase key and secret.
- 2026-10-11: Google done at the owner's go: `binarycompanion.com` verified in Search Console (TXT at `@`, keep it), Authorized domains now list both domains, and the bundled brand edit (home, privacy, terms URLs; developer contact `sobryan@binarycompanion.com` added) verified and published. User support email stays `darkarena@gmail.com` (the field only offers the signed-in account's addresses). Remaining for Google: remove `obryan.cloud` from Authorized domains after the old-domain redirect works.
- 2026-10-11 (later): App Store Connect listing text and URLs entered and saved (not submitted). Home page lists all supported providers (Apple Calendar, Google, Microsoft, iCloud/CalDAV, iCal links) to match the app and the privacy policy.
- 2026-10-11 (cleanup): `timetug.obryan.cloud` now redirects (all five URLs verified 301); the obsolete `FIREBASE_SERVICE_ACCOUNT_TIMETUG` secret is deleted from the `hosting` environment and the repository, and old key `5be03ce9…` is deleted. The unexplained second key `4de92d1f…` on `github-action-1376589039@timetug` was deleted at the owner's go. Google Authorized domains then had `obryan.cloud` removed; Task 6 is complete.
- 2026-10-11 (decisions): Owner: no Mac App Store distribution in the EU for now (website and Homebrew only); a real business address comes later, when there is something to sell. Privacy policy no longer calls Google Calendar beta. Auto-merge and Auto-fix are on for this repository's PRs at the owner's request. Contact PR: README, SECURITY.md, CODE_OF_CONDUCT.md.
- 2026-10-11 (phase 0 follow-ups): `binary-companion/website` has the `Protect main` ruleset and auto-merge; the audit script exists and found the items above; Restrict updates is not applied anywhere because it blocks auto-merge (ruling in plan Task 8). `timetug-bot` GitHub App not created: it is needed only when `timetug-shared` and `calendar-connectors` exist, and its creation and private key are the owner's. Org 2FA and the other organization settings (spec section 8) remain the owner's. EU Mac App Store storefronts excluded (148 regions) at the owner's decision.
- 2026-10-11 (org move): Owner enabled the organization controls (2FA, no member repo creation, Actions allow-list with SHA pinning); `audit-github.sh --strict binary-companion website darkarena1/timetug` then failed only on the 11 repository-level secrets. A freshly downloaded Developer ID profile (the Oct 7 file was corrupt) was set on `release` and `beta` by file copy, then the 11 repository-level secrets were deleted on the owner's go; the strict audit passed (0 failed, 0 skipped). The appcast mirror `darkarena1/darkarena1.github.io` was created and verified, then `timetug` and `homebrew-tap` were transferred to `binary-companion`. This PR repoints references, `SUFeedURL` (now `https://timetug.binarycompanion.com/appcast.xml`) and the Firebase appcast redirect. Support contact for the Google consent screen is `sobryan@binarycompanion.com` (owner's choice; the console field needs that address on the signed-in account).
- 2026-10-11 (support email, Docker Hub): The Google consent screen's support email is now the group `support@binarycompanion.com` (created by the owner in the Workspace admin console, because the dropdown lists only primary addresses and `sobryan@` is an alias); branding re-verified and published. `scott@obryan.cloud` accepted its ownership invitation on project `timetug`. Docker Hub secrets moved to the organization as described above; the audit script no longer allows any repository-level secret.
- 2026-10-12: Owner merged the tap PRs (2 pinned `actions/checkout`, 3 authenticated the cask audit after a rate-limit failure, 4 set the license holder to Binary Companion LLC); `support@binarycompanion.com` confirmed to reach the owner. Found master CI red on a loopback test race (`correctStateAccessDeniedIsDelivered` sent before `authorize` armed); fixed with a helper that waits for `openURL`, 12 clean local runs. Fixed the stale `binary-companion-llc` tap references. Next: owner merges that PR, the agent drafts `v2.1.0`, the owner publishes and approves `release`; then phase 1 planning.
- 2026-10-12 (phase 1 design): Owner approved the design in chat: MIT license, `CalendarApple` stays in `timetug` (program design table amended), plain `X.Y.Z` library tags, library releases from `main` with the `timetug-bot` token for dispatch only. Phase spec written. Mac release: waiting for a beta from `b1e9021` (includes #92, connector transport cache removal) to soak before drafting `v2.1.0`. Next: owner reviews the phase spec, then the plan.
- 2026-10-13 (phase 1): Extracted the connector library with its history (23 commits) to `binary-companion/calendar-connectors` (public, MIT, holder Binary Companion LLC) and released `1.0.0` (commit `c75f3e0`); `Sources` is byte-identical to the in-repo copy and `Tests` differs by two doc-comment lines. Rulesets `Protect main` (required checks macos, linux, architecture) and `Protect version tags` are active, the `publish` environment exists, and the strict audit passed (0 failed, 0 skipped); CI is green on the library's `main` and its first Release run released nothing, as designed. The flip pull request in this repository consumes `1.0.0` by released version and removes the in-repo copy. Next: the owner reviews and merges the flip PR and creates the `timetug-bot` GitHub App; then the notify job and bump workflow, the drill and the cross-repo skill.
- 2026-10-13 (phase 1 hardening): PR 97 (the flip) merged. An interim whole-work review is done; hardening pull requests are open (library PR 1 and this repository's pin-hardening PR: second-entry and `Package@swift-*.swift` bypasses closed, `verify.sh affected` runs the pin check for manifest and `project.yml` edits, dangling doc links fixed). Remaining: the owner creates `timetug-bot`, then Part C of the plan (the bump loop, the drill and the cross-repository skill).
- 2026-10-13 (phase 1 bump loop): The library's Release workflow published `1.0.1`, the first tag created under the active `Protect version tags` ruleset. PR 98 (this repository's pin hardening) and library PR 1 are merged. The timetug half of the bump loop is built in PR 99: `scripts/ci/bump-pin.sh` (always moves `exactVersion`, raises `from:` floors only on a major bump) and `.github/workflows/bump-dependencies.yml` (idempotent, `bump` environment, never merges). Still waiting on the owner to create the `timetug-bot` GitHub App; then the `bump` environments and secrets, the library's `notify` job, and the drill.

## Where each secret comes from

GitHub never shows a secret's value again, so each value is re-entered from its source with `gh secret set NAME --env <environment> < file` in the owner's own terminal (or the GitHub UI). Values never go into chat or files in the repository. Keep the repository-level copy until the environment copy has signed a beta and a release.

| Secret | Source | If it cannot be found |
|---|---|---|
| `SPARKLE_PRIVATE_KEY` | Login keychain item (service `https://sparkle-project.org`, account `ed25519`, created 2026-09-20); export with Sparkle's `generate_keys -x <file>` | Must not be recreated: installed apps trust only this key's public half (`SUPublicEDKey` in `Apps/macOS/project.yml`). Recover the GitHub copy with a one-time, `release`-gated workflow that encrypts it to an `age` public key the owner holds and uploads only the ciphertext |
| `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD` | Developer ID Application certificate, exported from Keychain Access as `.p12` | Issue a new Developer ID certificate in the Apple developer portal (same Team ID, so updates and the keychain group keep working) |
| `MACOS_PROVISIONING_PROFILE_BASE64` | Developer ID provisioning profile from the developer portal, downloaded as a binary file. Before setting, check it: `security cms -D -i FILE >/dev/null` must succeed and `com.apple.application-identifier` must be `<team>.com.timetug.app`. The copy in `~/Downloads/TimeTug_Developer_ID.provisionprofile` is damaged (U+FFFD bytes, 2026-10-07) and must not be used | Download again (regenerate it if the certificate changed) |
| `NOTARY_API_KEY_P8_BASE64`, `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID` | App Store Connect API key (the `.p8` downloads once) | Revoke and create a new key |
| `APPLE_TEAM_ID` | Developer portal, Membership | Look it up (not sensitive) |
| `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET` | `~/.config/timetug/google-oauth.xcconfig` and the Google Cloud console | Add a new client secret in the console; signed-in users are unaffected |
| `MICROSOFT_OAUTH_CLIENT_ID` | `~/.config/timetug/microsoft-oauth.xcconfig` and the Entra app registration | Read it from the registration |
| `FIREBASE_SERVICE_ACCOUNT_TIMETUG` | Deleted 2026-10-11. Was obsolete after PR 79: the website deploys through Workload Identity Federation and the `hosting` environment holds no secret. Delete it, and the old project's key `5be03ce9c4a9…`, once the cutover is verified | Nothing to recover |
| `appstore` environment values | Already in the `appstore` environment | Nothing to move |
