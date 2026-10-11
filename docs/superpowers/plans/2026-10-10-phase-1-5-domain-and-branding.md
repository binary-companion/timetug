# Phase 1.5: Domain and Branding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax. Tasks marked **(owner)** need a person's sign-in, legal identity or a console that has no CLI; do not attempt them without the owner.

**Goal:** Every public TimeTug URL lives under `timetug.binarycompanion.com`; the old `timetug.obryan.cloud` answers a permanent 301 with the matching new URL; Google and Microsoft show Binary Companion branding with no interruption for signed-in users.

**Architecture:** TimeTug's website moves to Firebase Hosting in the `binary-companion` project (the Binary Companion Google account), with two sites: `timetug-site` (content at `timetug.binarycompanion.com`) and `timetug-redirect` (`timetug.obryan.cloud`, redirect-only). GitHub deploys with its OIDC identity through Workload Identity Federation, so no Firebase key is stored. `/appcast.xml` on the new domain answers 301 to the current feed, so a later phase 0 move only changes that one rule. Branding changes at Google, Microsoft and Apple follow once the new domain is live.

**Tech Stack:** Firebase Hosting (CLI and REST), Squarespace DNS, Node `node:test` for the site test, Azure CLI (`az`) for Entra, Google Search Console and the Google Auth Platform console.

**Spec:** `docs/superpowers/specs/2026-10-09-windows-program-design.md`, section 1.5. Tracker: `docs/superpowers/plans/2026-10-09-windows-program-tracker.md`.

## Facts established on 2026-10-10

| Fact | Evidence |
|---|---|
| The registered domain is **`binarycompanion.com`** (no "s"). `binarycompanions.com` is not registered (registry answers "No match"). The spec and tracker had the wrong spelling; corrected in this plan's PR. | `whois`, public DNS NXDOMAIN for the plural |
| Registrar and DNS host: Squarespace Domains. Created 2026-10-02, expires 2028-10-02, transfer and delete locks on. Name servers `NSC1`–`NSC4.SQUARESPACEDNS.COM`. | `whois`, `dig NS` |
| Apex records today: `A 199.36.158.100` (Firebase Hosting), `TXT hosting-site=binary-companion`, a `google-site-verification` TXT, SPF for Google, `MX smtp.google.com` (mail works). No records for `timetug.` or `www.` yet. | `dig` |
| The apex site `binary-companion` is a Firebase Hosting site in a project under the `obryan.cloud` Google Workspace (`scott@obryan.cloud`), not in the `timetug` project. It is titled "Binary Companion, LLC — Technical Consulting", lists `sobryan@binarycompanion.com` as contact, and links to `https://timetug.obryan.cloud`. | live page, `firebase hosting:sites:list --project timetug` shows only `timetug` |
| `timetug.obryan.cloud` is `CNAME timetug.web.app`; project `timetug` (number 591041424232) is owned by `darkarena@gmail.com`, which is signed in to `gcloud` and `firebase` on this Mac. `scott@obryan.cloud` is registered in `gcloud` but its token needs a fresh interactive sign-in. | CLI output |
| `/.well-known/microsoft-identity-association.json` does not exist on the apex yet (404). | `curl` |
| The Entra `TimeTug` registration (appId `f05c1d1f-55cb-4a2d-bf7e-65db87d23099`) has **no verified publisher**, empty marketing/privacy/terms/support URLs, publisher domain `darkarenagmail.onmicrosoft.com`, no owners listed; the signed-in `az` user (`darkarena@gmail.com`) is Global Administrator of the only tenant ("Default Directory", initial domain only). This contradicts the earlier assumption that the app was publisher-verified. | `az ad app show`, Graph `/organization` (2026-10-10) |
| Creating a Hosting site in project `timetug` returns 403 for the Owner while `validateOnly` passes; the same command works in project `binary-companion`. The console showed a "Firebase Terms and Conditions" dialog once (not accepted by the agent). Cause not found; avoided by hosting in `binary-companion` (R2). | CLI debug log, 2026-10-10 |
| The Google Cloud project `binary-companion` exists under `scott@obryan.cloud` (the apex site's project). | `gcloud projects list` |

## Rulings

- **R1, spelling:** use `binarycompanion.com` everywhere. The only registered domain, the live apex site and the GitHub organization `binary-companion` all agree.
- **R2, where the sites live (revised 2026-10-10):** the spec said to move `timetug.obryan.cloud` to a second site in project `timetug`. Creating any new Hosting site in `timetug` returns 403 (cause not found; the Owner has every permission), while sites create fine in project `binary-companion`. The owner chose to deploy TimeTug's website to Firebase in the `obryan.cloud` account. So both sites (`timetug-site`, `timetug-redirect`) live in `binary-companion`, and the old domain moves to `timetug-redirect` after the new domain is serving. Cost: a brief gap on `timetug.obryan.cloud` while it is detached from the old project and attached to the new site; ordering below keeps the old domain serving until then. Benefit: one project and one deploy credential (a federated identity, no key), and `FIREBASE_SERVICE_ACCOUNT_TIMETUG` can be deleted.
- **R3, redirect rules:** Firebase redirects have no `:splat`; `/:path*` matches one segment only. The redirect site uses explicit rules for 1, 2 and 3 path segments plus a catch-all to the new root (tested in the hosting emulator on 2026-10-10: query strings are preserved).
- **R4, contacts:** use the one address known to exist, `sobryan@binarycompanion.com`, in the site and the consent screens. `support@` and `security@` aliases are an optional owner item; adding them later is a one-line change.
- **R5, legal wording:** privacy policy and terms say the app is made and operated by Binary Companion, LLC. The copyright footer stays "Scott O'Bryan" because `LICENSE` names that holder; the owner decides if that changes. Both pages' "Effective" dates are bumped. **(owner reviews the wording in the PR.)**

- **R6, Microsoft tenant (owner decision 2026-10-10):** the existing Entra tenant ("Default Directory", created under `darkarena@gmail.com`) is Binary Companion's Microsoft identity. `binarycompanion.com` is added to it as a custom domain, a work user `sobryan@binarycompanion.com` is created in it, and the TimeTug app registration stays where it is (same client ID, redirect URIs and scopes). Why: publisher verification needs the Partner Center account's domain, the tenant's verified domain and the app's publisher domain to agree, and a new tenant would force a new app registration and a new client ID in every shipped copy. Cost if wrong: the domain is bound to this tenant; to give the company a separate Microsoft 365 tenant later, remove the domain here first (reversible, but only while no user or app depends on it).

## Global Constraints

- No secrets, passwords, tokens or Partner Center identifiers in the repository or in chat. Access tokens stay in the CLI token caches (`~/.config/gcloud`, `~/.azure`, `~/.config/configstore`).
- Old URLs keep working permanently as 301 redirects. Installed Mac copies use the GitHub Pages feed; do not touch it in this phase.
- Site changes deploy from `master` by the `hosting` environment workflow; the owner merges.
- Microsoft client ID, redirect URIs and scopes do not change. Google scopes do not change.

## Review Focus

1. A redirect rule that sends `/privacy` or `/terms` to the wrong path, or drops the query string.
2. `canonical`, `og:url` or `og:image` still pointing at `obryan.cloud` after the cutover (Google and Microsoft crawl these).
3. The privacy policy and homepage no longer linking to each other on the new domain (Google brand verification requires it).
4. `/.well-known/microsoft-identity-association.json` served with the wrong content type, or caught by a redirect rule.
5. The deploy workflow publishing the redirect rules to the content site (or the content to the redirect site).

## Access for Entra (advice to the owner)

Recommended: **you sign in with the Azure CLI in your own terminal; I work through that session.**

1. Install once: `brew install azure-cli`.
2. In a terminal tab, run `az login --tenant <your tenant id or domain>` and complete the browser sign-in and MFA yourself. The token lands in `~/.azure` on this Mac and never in chat. Use an account that is an **owner of the TimeTug app registration** or holds **Application Administrator** / **Cloud Application Administrator**; do not use Global Administrator unless that is the only account you have.
3. I start read-only: list the app registration and its current branding. Branding properties (homepage, terms and privacy URLs, logo) are plain Graph `PATCH` calls and I will make those.
4. **Publisher verification stays with you.** It needs your Partner Center sign-in (an account admin there) and cannot be done as an app-only call. I will prepare the association file and give you the exact values; you click through *Branding & properties > Add MPN ID to verify publisher*.
5. When the phase is done, `az logout`.

Not recommended: handing me a client secret, a password, or a long-lived service principal. If we ever want unattended Entra changes, the least-privilege shape is a service principal with `Application.ReadWrite.OwnedBy`, made owner of only this app registration.

For Google I use the `gcloud` and `firebase` sessions already on the Mac. One thing I need from you: sign in `scott@obryan.cloud` again so I can read the project that hosts the apex site:

```bash
gcloud auth login scott@obryan.cloud
firebase login:add scott@obryan.cloud
```

## Tasks

### Task 1: Correct the domain and record the facts (this PR)

**Files:** Modify the spec and the tracker; Create this plan.

- [x] Replace `binarycompanions.com` with `binarycompanion.com` in the spec and tracker; verify no occurrence of the plural remains in the repository.
- [x] Record the facts above, the rulings and the access advice in this plan.
- [x] Update the tracker's phase table, Now list and owner checklist for phase 1.5.
- [x] Update the memory note for the program.

### Task 2: Create the sites, federate the deploy and connect the domain

**Files:** none in the repository (cloud resources; recorded here).

- [x] **Step 1: Sites.** `firebase hosting:sites:create timetug-site --project binary-companion --account scott@obryan.cloud` and the same for `timetug-redirect` (2026-10-10).
- [x] **Step 2: Federated deploy identity.** Service account `timetug-deploy@binary-companion.iam.gserviceaccount.com` with `roles/firebasehosting.admin` and `roles/serviceusage.serviceUsageConsumer`; provider `timetug` in pool `github` (project number 948864622857) accepting `assertion.repository in ['darkarena1/timetug','binary-companion/timetug'] && assertion.environment == 'hosting'`; `roles/iam.workloadIdentityUser` bound for both repository names.
- [x] **Step 3: Content.** Manual deploy of the site branch to `timetug-site`: `cd site && firebase deploy --only hosting:timetug-site --project binary-companion --account scott@obryan.cloud`. `https://timetug-site.web.app` answers 200.
- [x] **Step 4: Domain.** `POST …/projects/binary-companion/sites/timetug-site/customDomains?customDomainId=timetug.binarycompanion.com`. Firebase asks for one record: `CNAME timetug.binarycompanion.com -> timetug-site.web.app`.
- [ ] **Step 5 (owner): add the record** at *Squarespace Domains > binarycompanion.com > DNS Settings > Add record*: type `CNAME`, host `timetug`, data `timetug-site.web.app`. Leave every other record alone.
- [ ] **Step 6: Verify.**

```bash
dig +short CNAME timetug.binarycompanion.com @8.8.8.8
curl -sI https://timetug.binarycompanion.com | head -5
```

Expected: `timetug-site.web.app.`, then `HTTP/2 200` once the certificate is issued (minutes to a few hours). The API's `hostState` and `cert.state` show progress.

### Task 3: Site changes (draft PR; merging is the cutover)

**Files:** Modify `site/firebase.json`, `site/public/index.html`, `site/public/privacy.html`, `site/public/terms.html`, `site/README.md`, `scripts/dev/verify.sh`, `.github/workflows/firebase-hosting-merge.yml`, `scripts/ci/tests/check-workflow-contracts.py`, `docs/release.md`, `docs/development/action-pins.md`, `AGENTS.md`; Create `site/legacy/404.html`, `site/tests/site.test.js`.

**Interfaces:** `site/firebase.json` becomes an array of two hosting entries in project `binary-companion`: `timetug-site` (content from `public`) and `timetug-redirect` (redirects only, from `legacy`). `.github/workflows/firebase-hosting-merge.yml` deploys both with the Firebase CLI after a federated sign-in; `scripts/ci/tests/check-workflow-contracts.py` gains a check against stored Firebase keys.

- [x] **Step 1: Test** `site/tests/site.test.js` (see the file; PR 79): redirect matching for 1 to 3 segments and the root fallback, appcast rule, canonical and `og:` tags, contacts, operator wording.

Run: `node --test site/tests/site.test.js`. Expected: FAIL (no `timetug-site` entry; pages still name `obryan.cloud`).

- [ ] **Step 2: Implement.**
  - `site/firebase.json`: turn `hosting` into an array. Entry 1: `"site": "timetug-site"`, `"public": "public"`, the existing `cleanUrls`, `trailingSlash`, `ignore` and `headers` unchanged, plus `"redirects": [{"source": "/appcast.xml", "destination": "https://darkarena1.github.io/timetug/appcast.xml", "type": 301}]`. Entry 2: `"site": "timetug"`, `"public": "legacy"`, and `redirects` in this order: `/` → `NEW/`, `/:a` → `NEW/:a`, `/:a/:b` → `NEW/:a/:b`, `/:a/:b/:c` → `NEW/:a/:b/:c`, `/**` → `NEW/`, all `"type": 301`.
  - `site/legacy/404.html`: a one-line page linking to `https://timetug.binarycompanion.com/` (Firebase needs a public directory; no request reaches it).
  - In the three pages: replace `https://timetug.obryan.cloud` with `https://timetug.binarycompanion.com`; replace `mailto:darkarena@gmail.com` and its visible text with `sobryan@binarycompanion.com`; change "made by Scott O'Bryan, an individual developer" to "made and operated by Binary Companion, LLC" (R5); bump the "Effective" dates to the merge date.
  - `site/README.md`: heading, hosting paragraph and manual deploy commands (`firebase deploy --only hosting:timetug-site`).
  - `scripts/dev/verify.sh` (line 60 area): add `run website-config-test node --test site/tests/site.test.js`.
- [ ] **Step 3: Run** `node --test site/tests/site.test.js site/tests/download.test.js` and `scripts/dev/verify.sh release-tools`. Expected: all pass.
- [ ] **Step 4: Check the workflow.** Read `.github/workflows/firebase-hosting-merge.yml`; the action deploys every hosting entry in `site/firebase.json`. Confirm in the first deployment log that both sites update, and that the `check-workflow-contracts.py` rules still pass.
- [ ] **Step 5: Commit, open the PR as a draft.** Mark it ready only after Task 2 Step 5 passes.

### Task 4: Cut over (owner merges the PR from Task 3)

- [x] Merge the PR. Owner merged PR 79 on 2026-10-10; run `38115187472` ran in the `hosting` environment, signed in without a key, and updated both sites. Verified: `/`, `/privacy`, `/terms`, `/img/social-preview.jpg` answer 200 with the Content-Security-Policy header, `/appcast.xml` answers 301 to the GitHub Pages feed, canonical and contact are on the new domain; `timetug-redirect.web.app` answers 301 for 1, 2 and 3 segments (query string kept) and the deeper-path fallback.
- [ ] **Move `timetug.obryan.cloud`** to `timetug-redirect`: remove it from site `timetug` in project `timetug` (console, signed in as `darkarena@gmail.com`), add it to `timetug-redirect` with the same API call as Task 2 Step 4, and update its DNS (the zone is at Google's name servers `ns-cloud-e*.googledomains.com`; locate who manages it before touching it). Expect a short gap until the certificate is issued; do it after the new domain is serving.
- [ ] After that: delete the obsolete `FIREBASE_SERVICE_ACCOUNT_TIMETUG` environment secret and the old project's service-account key `5be03ce9c4a9ec3eae392de55cad3a4dc04fa2de`.
- [ ] Verify every old URL: `for p in / /privacy /terms /appcast.xml /img/social-preview.jpg; do curl -sI https://timetug.obryan.cloud$p | grep -i -E "^HTTP|^location"; done`. Expected: `301` and the matching `https://timetug.binarycompanion.com...` location.
- [ ] Verify the new pages and headers: `curl -sI https://timetug.binarycompanion.com/privacy` shows 200 and the Content-Security-Policy header.
- [ ] In `binary-companion/website` (Task 8), change the TimeTug link in `public/index.html` from `https://timetug.obryan.cloud` to `https://timetug.binarycompanion.com`; the push to `main` deploys it.

### Task 5: Microsoft (Entra)

State on 2026-10-10: not publisher verified, no branding URLs (see Facts). Verification is therefore first-time, and there is no badge to lose.

- [x] **(owner)** `az login` (done 2026-10-10; Azure CLI 2.91.0).
- [x] Read the app registration (read-only; findings above).
- [x] (2026-10-10, after the cutover) Set branding through Graph and read it back; the logo went up as a 240x240 PNG with `curl --data-binary` because `az rest --body @file` corrupts binary bodies ("Stream content does not represent a valid image"). Command used: `az rest --method PATCH --url https://graph.microsoft.com/v1.0/applications/824b80ba-0339-4344-9d66-81f07e9f3fd4 --body '{"info":{"marketingUrl":"https://timetug.binarycompanion.com/","privacyStatementUrl":"https://timetug.binarycompanion.com/privacy","termsOfServiceUrl":"https://timetug.binarycompanion.com/terms","supportUrl":"https://timetug.binarycompanion.com/"}}'`, then the logo with `PUT /applications/{id}/logo` (`artwork/Branding/timetug-app-icon-1024.png`, resized). Read back with `az ad app show` and confirm.
- [x] Add `binarycompanion.com` to the tenant as a custom domain (`POST /domains`, 2026-10-10, after the owner accepted R6). Graph returned one TXT record to verify it: host `@`, value `MS=ms40905445`, TTL 3600. The MX record Graph also lists belongs to the optional Email service and is **not** added (the domain's mail stays on Google Workspace).
- [x] (2026-10-10: record added at Squarespace, `isVerified: true` from Graph.) Add that TXT record at Squarespace (Domains > binarycompanion.com > DNS Settings > Custom records), then `az rest --method POST --url https://graph.microsoft.com/v1.0/domains/binarycompanion.com/verify` and read back `isVerified`. Squarespace asks for a Google step-up sign-in as `scott@obryan.cloud` first **(owner completes it)**. Fallback if the tenant route is refused: host `/.well-known/microsoft-identity-association.json` (`{"associatedApplications":[{"applicationId":"f05c1d1f-55cb-4a2d-bf7e-65db87d23099"}]}`, content type `application/json`) in `site/public/.well-known/` and keep it out of the redirect rules.
- [x] (2026-10-10, owner approved) Created the work user `sobryan@binarycompanion.com` in the tenant. First sign-in forced a password change (owner did it; the initial-password file was then deleted). Roles: **Application Administrator** (enough for publisher verification) and, added the same day with the owner's go-ahead, **Global Administrator**, because Microsoft's partner program enrollment must be done by a Global Administrator. Remove Global Administrator after enrollment is Active and keep Application Administrator. Entra sign-in is separate from the mailbox: mail for the address stays on Google Workspace. The user performs the partner and publisher steps, because publisher verification requires the signed-in user to belong to both the tenant and the Partner Center account.
- [ ] **(owner)** Enroll Binary Companion in the Microsoft AI Cloud Partner Program (`https://partner.microsoft.com/dashboard/account/v3/enrollment/introduction/partnership`, choose Partner) signed in as that user; do **not** choose "Create work account" (it would create a new tenant, and the partner account must attach to this one). Complete business verification and complete Microsoft's business verification (a D-U-N-S number speeds it; this is the slow step, so it is started as soon as the user exists).
- [ ] **(owner)** In the portal: *Branding & properties*, set the publisher domain, then *Add MPN ID to verify publisher* with the **Partner Global Account (PGA) ID** from Partner Center *Account settings > Identifiers* (the location ID is not accepted). The tenant must be the one associated with the PGA, the publisher domain cannot be `*.onmicrosoft.com`, and the signing-in user must use Entra multifactor authentication and hold Application Administrator (Entra) and Account Admin or CPP Partner Admin (Partner Center).
- [ ] Verify: `az ad app show` shows `verifiedPublisher.displayName`; a fresh Microsoft sign-in shows the verified publisher and no "unverified" warning.

### Task 6: Google

- [x] Search Console: `binarycompanion.com` added as a **Domain** property under `darkarena@gmail.com` and verified (2026-10-11) with a TXT at `@`; the existing `google-site-verification` TXT stays. The record must stay or ownership is lost.
- [x] Added `binarycompanion.com` under *Google Auth Platform > Branding > Authorized domains*; `obryan.cloud` kept until approval.
- [x] Bundled edit saved, verified and published (2026-10-11, verification took under a minute and the console reported "Your branding has been verified and is being shown to users"): homepage `https://timetug.binarycompanion.com/`, privacy policy `…/privacy`, terms `…/terms`, developer contact `darkarena@gmail.com` plus `sobryan@binarycompanion.com`. The **user support email** stays `darkarena@gmail.com`: that field only offers addresses of the signed-in Google account, so a `binarycompanion.com` address needs a Google Workspace or Google Account for it first.
- [ ] Remove `obryan.cloud` from Authorized domains (approval has arrived; waits for the owner's go and for the old-domain redirect to be confirmed).

### Task 7: Apple and the repository

- [ ] **(owner)** App Store Connect: privacy policy, support and marketing URLs to the new domain (editable at any time).
- [ ] Update README, `SECURITY.md`, CODEOWNERS contacts and the release-notes link base to the new domain and contact; one PR.

### Task 8: Put the Binary Companion website under version control (added 2026-10-10)

The apex site had been deployed from the Firebase console, with no source repository. Its `index.html` and the three other files the owner supplied are byte-identical to what is live (6 files in the live version, 2 of them Firebase's reserved `/__/firebase/*`; the live version's `config` is empty).

- [x] Repository `binary-companion/website` (public, so the `production` environment's branch limit works on a free plan), created 2026-10-10. Layout: `public/` (site), `firebase.json` (site `binary-companion`, `public`), `.firebaserc`, `.gitattributes`, `README.md`, `.github/{workflows/deploy.yml,dependabot.yml,CODEOWNERS}`.
- [x] `firebase init` was not run; its output is two small files, written by hand and checked with `firebase deploy --only hosting --project binary-companion --dry-run` against the existing project ("Dry run complete").
- [x] Deployment without a stored key: Workload Identity Federation in project `binary-companion` (pool `github`, provider `website`, accepting only `repo == binary-companion/website` and `environment == production`), service account `website-deploy@binary-companion.iam.gserviceaccount.com` with `roles/firebasehosting.admin` and `roles/serviceusage.serviceUsageConsumer`. The `production` environment runs only from `main`. No secrets exist for this repository.
- [x] Verified 2026-10-10: the first push-to-deploy run succeeded (release `d14a2f4e…`, user `website-deploy@binary-companion.iam.gserviceaccount.com`); `https://binarycompanion.com` and `https://binary-companion.web.app` answer 200 and serve an `index.html` with the same SHA-256 as the supplied copy; stylesheet and both images answer 200.
- [ ] Phase 0 follow-ups for this repository: organization ruleset (owner-only merges to `main`), add it to the audit script, add the code-index workflow if wanted.
- [ ] **(owner)** If a different repository name is preferred (for example `binarycompanion.com`), rename it in GitHub; the Workload Identity condition names `binary-companion/website` and must be updated with it.

## Done when

Every old URL answers 301 with its new URL; Google shows the new branding as verified; the Microsoft consent prompt shows the new publisher domain with the verified badge; a fresh Google and Microsoft sign-in on the current Mac release succeeds; an existing signed-in account still refreshes.
