# Phase 1.5: Domain and Branding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax. Tasks marked **(owner)** need a person's sign-in, legal identity or a console that has no CLI; do not attempt them without the owner.

**Goal:** Every public TimeTug URL lives under `timetug.binarycompanion.com`; the old `timetug.obryan.cloud` answers a permanent 301 with the matching new URL; Google and Microsoft show Binary Companion branding with no interruption for signed-in users.

**Architecture:** Firebase Hosting serves the website from a new site (`timetug-site`) in the existing `timetug` project. The existing site `timetug` keeps `timetug.obryan.cloud` and becomes redirect-only, so the old domain never moves and has no downtime. `/appcast.xml` on the new domain answers 301 to the current feed, so a later phase 0 move only changes that one rule. Branding changes at Google, Microsoft and Apple follow once the new domain is live.

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

## Rulings

- **R1, spelling:** use `binarycompanion.com` everywhere. The only registered domain, the live apex site and the GitHub organization `binary-companion` all agree.
- **R2, which site moves:** the spec said to move `timetug.obryan.cloud` to a new redirect site. Instead the *new* domain gets a new site and the old domain stays where it is, converted to redirect-only. Same end state, but no live custom domain is detached and re-issued, so there is no outage window and no re-verification of the old domain. Cost if wrong: `timetug.web.app` also becomes a redirect; nothing references it.
- **R3, redirect rules:** Firebase redirects have no `:splat`; `/:path*` matches one segment only. The redirect site uses explicit rules for 1, 2 and 3 path segments plus a catch-all to the new root (tested in the hosting emulator on 2026-10-10: query strings are preserved).
- **R4, contacts:** use the one address known to exist, `sobryan@binarycompanion.com`, in the site and the consent screens. `support@` and `security@` aliases are an optional owner item; adding them later is a one-line change.
- **R5, legal wording:** privacy policy and terms say the app is made and operated by Binary Companion, LLC. The copyright footer stays "Scott O'Bryan" because `LICENSE` names that holder; the owner decides if that changes. Both pages' "Effective" dates are bumped. **(owner reviews the wording in the PR.)**

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

### Task 2: Create the new site and connect the domain

**Files:** none in the repository.

- [ ] **Step 1: Create the site.**

```bash
firebase hosting:sites:create timetug-site --project timetug
```

Expected: `Site timetug-site created`. If the ID is taken, use `timetug-home` and record it here.

- [ ] **Step 2: Deploy the current content to it** (so the domain serves a page the moment DNS and the certificate are ready). From a clean checkout of this plan's site branch (Task 3) or, if the site branch is not ready, from `master`:

```bash
cd site && firebase deploy --only hosting:timetug-site --project timetug
```

Expected: `https://timetug-site.web.app` answers 200.

- [ ] **Step 3: Add the custom domain through the Hosting REST API** (the CLI has no command for it) and print the DNS records Firebase wants. The token comes from `gcloud` in a command substitution and is never printed:

```bash
curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token --account darkarena@gmail.com)" \
  -H "Content-Type: application/json" \
  "https://firebasehosting.googleapis.com/v1beta1/projects/timetug/sites/timetug-site/customDomains?customDomainId=timetug.binarycompanion.com" \
  -d '{}'
```

Expected: a long-running operation whose `requiredDnsUpdates` lists a TXT (ownership) and A or AAAA records for `timetug.binarycompanion.com`.

- [ ] **Step 4 (owner, or the agent through the owner's signed-in Squarespace session): add those records** at *Squarespace Domains > binarycompanion.com > DNS Settings*. Add only records for the `timetug` host; leave every apex and mail record alone.
- [ ] **Step 5: Verify.**

```bash
dig +short timetug.binarycompanion.com @8.8.8.8
curl -sI https://timetug.binarycompanion.com | head -5
```

Expected: the Firebase address, then `HTTP/2 200` once the certificate is issued (minutes to a few hours).

### Task 3: Site changes (draft PR; merging is the cutover)

**Files:** Modify `site/firebase.json`, `site/public/index.html`, `site/public/privacy.html`, `site/public/terms.html`, `site/README.md`, `scripts/dev/verify.sh`; Create `site/legacy/404.html`, `site/tests/site.test.js`.

**Interfaces:** `site/firebase.json` becomes an array of two hosting entries: `timetug-site` (content from `public`) and `timetug` (redirects only, from `legacy`).

- [ ] **Step 1: Write the failing test** `site/tests/site.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const config = JSON.parse(fs.readFileSync('site/firebase.json', 'utf8'));
const entries = Array.isArray(config.hosting) ? config.hosting : [config.hosting];
const NEW = 'https://timetug.binarycompanion.com';
const content = entries.find(entry => entry.site === 'timetug-site');
const legacy = entries.find(entry => entry.site === 'timetug');

function matches(source, requestPath) {
  if (source === '/**') return true;
  const want = source.split('/').filter(Boolean);
  const have = requestPath.split('/').filter(Boolean);
  return want.length === have.length && want.every(part => part.startsWith(':') || part === have[0 + want.indexOf(part)]);
}

function redirectFor(requestPath) {
  const rule = legacy.redirects.find(candidate => matches(candidate.source, requestPath));
  if (!rule) return null;
  let destination = rule.destination;
  const names = rule.source.split('/').filter(part => part.startsWith(':'));
  const values = requestPath.split('/').filter(Boolean);
  names.forEach((name, index) => { destination = destination.replace(name, values[index]); });
  return { type: rule.type, location: destination };
}

test('two hosting entries: content on timetug-site, redirects on timetug', () => {
  assert.ok(content && legacy);
  assert.equal(content.public, 'public');
  assert.equal(legacy.public, 'legacy');
  assert.equal(content.redirects?.some(rule => rule.source === '/**'), false);
});

test('every old URL answers 301 with the matching new URL', () => {
  const paths = ['/', '/privacy', '/terms', '/style.css', '/download.js', '/favicon.ico',
    '/img/social-preview.jpg', '/img/app-icon-256.png', '/appcast.xml',
    '/.well-known/microsoft-identity-association.json'];
  for (const requestPath of paths) {
    const result = redirectFor(requestPath);
    assert.ok(result, `no rule for ${requestPath}`);
    assert.equal(result.type, 301, requestPath);
    assert.equal(result.location, NEW + requestPath, requestPath);
  }
  assert.equal(redirectFor('/a/b/c/d/e').location, NEW + '/');
});

test('the content site answers /appcast.xml with a 301 to the current feed', () => {
  const rule = content.redirects.find(candidate => candidate.source === '/appcast.xml');
  assert.equal(rule.type, 301);
  assert.equal(rule.destination, 'https://darkarena1.github.io/timetug/appcast.xml');
});

test('pages name the new domain and no longer name the old one', () => {
  for (const name of ['index', 'privacy', 'terms']) {
    const html = fs.readFileSync(path.join('site/public', `${name}.html`), 'utf8');
    assert.equal(/obryan\.cloud/.test(html), false, `${name}.html still names obryan.cloud`);
    assert.ok(html.includes(`${NEW}/`) || html.includes(`${NEW}/${name}`), `${name}.html canonical`);
  }
});

test('privacy policy and homepage link to each other', () => {
  const home = fs.readFileSync('site/public/index.html', 'utf8');
  const privacy = fs.readFileSync('site/public/privacy.html', 'utf8');
  assert.match(home, /href="\/?privacy"/);
  assert.match(privacy, /href="\/"|href="\/index"|href="https:\/\/timetug\.binarycompanion\.com\/"/);
});

test('contacts use the Binary Companion address', () => {
  for (const name of ['index', 'privacy', 'terms']) {
    const html = fs.readFileSync(path.join('site/public', `${name}.html`), 'utf8');
    assert.equal(/darkarena@gmail\.com/.test(html), false, name);
    assert.ok(html.includes('sobryan@binarycompanion.com'), name);
  }
});
```

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

- [ ] Merge the PR. Expected: `Deploy to Firebase Hosting on merge` runs in the `hosting` environment and updates both sites.
- [ ] Verify every old URL: `for p in / /privacy /terms /appcast.xml /img/social-preview.jpg; do curl -sI https://timetug.obryan.cloud$p | grep -i -E "^HTTP|^location"; done`. Expected: `301` and the matching `https://timetug.binarycompanion.com...` location.
- [ ] Verify the new pages and headers: `curl -sI https://timetug.binarycompanion.com/privacy` shows 200 and the Content-Security-Policy header.
- [ ] **(owner, other site)** Change the link on the `binarycompanion.com` homepage from `https://timetug.obryan.cloud` to `https://timetug.binarycompanion.com` (that site is in the `obryan.cloud` Workspace Firebase project).

### Task 5: Microsoft (Entra)

- [ ] **(owner)** `az login`, as in "Access for Entra".
- [ ] Read the app registration: `az ad app list --display-name TimeTug --query "[].{id:id,appId:appId,publisher:publisherDomain,verified:verifiedPublisher}"`.
- [ ] Update branding through Graph (`PATCH /applications/{id}` with `info.marketingUrl`, `info.privacyStatementUrl`, `info.termsOfServiceUrl`, `info.supportUrl`), and the logo with `PUT /applications/{id}/logo`. These apply immediately; no review.
- [ ] **(owner)** Create the Binary Companion partner account in Partner Center using `sobryan@binarycompanion.com` (the publisher domain must match the account's email domain); a D-U-N-S number speeds verification.
- [ ] Host `https://binarycompanion.com/.well-known/microsoft-identity-association.json` with `{"associatedApplications":[{"applicationId":"<client id>"}]}` as `application/json`. That path is on the apex site in the `obryan.cloud` project, so it needs the `scott@obryan.cloud` sign-in above. If Microsoft accepts the subdomain as the publisher domain, host it in `site/public/.well-known/` instead and keep it out of the redirect rules.
- [ ] **(owner)** In the portal: *Branding & properties > Publisher domain > verify*, then *Add MPN ID to verify publisher* with the new partner ID.

### Task 6: Google

- [ ] **(owner)** In Search Console, add `binarycompanion.com` as a **Domain** property from the Google account that owns the `timetug` Cloud project (`darkarena@gmail.com`) and verify it with the TXT record Search Console gives (add it at Squarespace; the existing `google-site-verification` TXT stays).
- [ ] Add `binarycompanion.com` under *Google Auth Platform > Branding > Authorized domains*; keep `obryan.cloud` until approval.
- [ ] One bundled edit: homepage `https://timetug.binarycompanion.com/`, privacy policy `…/privacy`, terms `…/terms`, support and developer contact `sobryan@binarycompanion.com`. Then submit for verification.
- [ ] After approval: remove `obryan.cloud` from Authorized domains.

### Task 7: Apple and the repository

- [ ] **(owner)** App Store Connect: privacy policy, support and marketing URLs to the new domain (editable at any time).
- [ ] Update README, `SECURITY.md`, CODEOWNERS contacts and the release-notes link base to the new domain and contact; one PR.

## Done when

Every old URL answers 301 with its new URL; Google shows the new branding as verified; the Microsoft consent prompt shows the new publisher domain with the verified badge; a fresh Google and Microsoft sign-in on the current Mac release succeeds; an existing signed-in account still refreshes.
