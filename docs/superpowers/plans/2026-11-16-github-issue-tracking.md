# GitHub Issue Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track feature progress in GitHub issues and two org projects (TimeTug, Libraries), with written rules, an agent skill, and Actions for mechanical status changes.

**Architecture:** Each tracked repo declares its projects in `.github/tracking.yml`. Reusable workflows in a new public `binary-companion/.github` repo read that file and apply the dedup and parent roll-up rules, using pure, unit-tested Python functions behind a thin `gh` GraphQL layer. Rules and the agent skill live in `timetug`. Agents own judgment; Actions own mechanical transitions.

**Tech Stack:** GitHub issues, sub-issues, org projects (v2), issue types, GitHub Actions reusable workflows, Python 3 with pytest, `gh` CLI/GraphQL.

**Spec:** `docs/superpowers/specs/2026-11-16-github-issue-tracking-design.md`

## Global Constraints

- Projects: `TimeTug` and `Libraries` in org `binary-companion`. Repos: timetug, timetug-shared, timetug-windows, homebrew-tap and the private manual-work repo → TimeTug; calendar-connectors → Libraries; website → none.
- Status values exactly: Backlog, Ready, In progress, In review, Done. Fields: Status, Agent. Issue type `Manual Task`; label `manual`.
- Parent status is derived only: In progress when any child is In progress; In review when every child that is not Done is In review (at least one); Done only when all children are Done. Agents never set it by hand.
- Dedup: add an issue to project P only if no ancestor issue is already in P.
- No credentials in any issue. Manual tickets live in the private repo, assigned to the owner, status Ready.
- `.github` repo is public: no secrets or internal structure in it.
- The default `GITHUB_TOKEN` cannot write org projects; the Actions use the org secret `APP_PRIVATE_KEY` and org variable `APP_ID` (a GitHub App, minted into a token with `actions/create-github-app-token`) (GitHub App).
- Tests are written first. Commit only when the owner asks. Branch and PR, never the owner's merge (see AGENTS.md).

## Review Focus

- `tracking.yml` missing, empty, or malformed → repo is untracked, never a crash. (Task 3)
- Parent with no children → roll-up returns no change. (Task 3)
- Grandparent chain: a child's ancestors include all levels; project membership at any level suppresses the add. (Task 3)
- A child reopened after Done → parent leaves Done on the next roll-up. (Task 3)
- A PR that closes several issues, or none → every linked issue handled, no error for none. (Task 4)
- Child in a repo with no `tracking.yml` (for example website): parent roll-up still counts it by its issue state, but it is never added to a project. (Task 3)

---

### Task 1: Dry run on #203 (we use the rules on this very ticket)

Projects and issue types do not exist yet, so this task does what is possible by hand and records what had to wait. It is the first use of the rules we are writing.

**Files:**
- Modify: issue binary-companion/timetug#203 (body, comments)
- Create: sub-issues of #203 in `binary-companion/timetug`, one per spec phase: phase 1 = Task 2, phase 2 = Task 6, phase 3 = Tasks 3-5, phase 4 = Task 7

**Interfaces:**
- Produces: issue numbers for the four phases and a "dry run findings" comment on #203 that Task 6 turns into rule changes.

- [ ] **Step 1: Rewrite #203's body** to the standard shape: Summary, Intent, Success criteria (checklist), Plan (link to the spec and this plan, plus a one-line list of the phase sub-issues), Dry-run note. Keep the original discussion points under a collapsed "Original request" details block.
- [ ] **Step 2: Create four issues in `binary-companion/timetug`** titled `Tracking: owner setup (projects, fields, issue type, manual-work repo, bot token)`, `Tracking: rules, agent skill and issue forms`, `Tracking: Actions (routing, dedup, roll-up, PR and CI transitions)`, `Tracking: migrate open work and retire progress docs` (titles in phase order: setup, rules, Actions, migration), each with a self-contained body (summary, what to do, success criteria, blocked-by notes) and label `enhancement`. Link each as a sub-issue of #203: `gh api -X POST repos/binary-companion/timetug/issues/203/sub_issues -F sub_issue_id=<id>` where `<id>` is the new issue's REST `id`, not its number.
- [ ] **Step 3: Record blockers** in each body ("Blocked by #N"): setup blocks Actions; rules block migration.
- [ ] **Step 4: Verify**: `gh api repos/binary-companion/timetug/issues/203/sub_issues --jq '.[].title'` lists all four.
- [ ] **Step 5: Post a "dry run findings" comment on #203** listing what could not be done by hand (no project, no Status field, no Agent field, no issue type, token lacks `project` scope), and append to it as we find more.

### Task 2: Owner setup (phase 1; manual tasks)

**Files:**
- Create: manual tickets in `binary-companion/manual-configuration` (label `manual`, type Manual Task, assigned to the owner, Ready), each a sub-issue of the issue that needs it, with no wrapper ticket.

**Interfaces:**
- Produces: projects `TimeTug` and `Libraries` with Status and Agent fields; issue type `Manual Task`; private repo `binary-companion/<manual-work-repo>`; org secret `APP_PRIVATE_KEY` and org variable `APP_ID` (a GitHub App, minted into a token with `actions/create-github-app-token`); a token with `project` scope for `gh`.

- [ ] **Step 1: File one manual ticket per item**, each with numbered step-by-step instructions, exact field names and options, and direct URLs (never credentials): (a) run `gh auth refresh -s project` (the ticket says exactly this); (b) create org projects TimeTug and Libraries with Status options Backlog, Ready, In progress, In review, Done and a text field Agent; (c) create the org issue type Manual Task; (d) create the private repo and choose its name; (e) create the GitHub App with org project write and store it as org secret `APP_PRIVATE_KEY` and org variable `APP_ID` (a GitHub App, minted into a token with `actions/create-github-app-token`); (f) create the public `binary-companion/.github` repo.
- [ ] **Step 2: Mark each ticket Ready and assign to the owner** once Task 1's findings are folded in. Status is set on the project item when the project exists; until then use the `manual` label plus the issue's open state.
- [ ] **Step 2b: File the manual task to turn on the built-in Auto-archive items workflow in both projects** (filter `is:closed updated:<@today-14d`); project workflows are not configurable through the API. The roll-up reads children from the issue's sub-issue list, not project items, so archived children still count as Done (add a test in Task 3).
- [ ] **Step 3: Verify after the owner reports done:** `gh project list --owner binary-companion` shows both projects, and `gh api orgs/binary-companion/issue-types` lists Manual Task.

### Task 3: Pure tracking logic with tests (in `binary-companion/.github`)

**Files:**
- Create: `scripts/tracking/logic.py`, `scripts/tracking/tests/test_logic.py`

**Interfaces:**
- Produces:
  - `parse_tracking(text: str) -> list[str]`: project refs (`org/name`) from `tracking.yml` text; returns `[]` for empty, missing key, or malformed input.
  - `projects_to_add(repo_projects: list[str], ancestor_project_sets: list[set[str]]) -> list[str]`: those in `repo_projects` not present in any ancestor's set.
  - `rollup_status(child_statuses: list[str]) -> str | None`: `"In progress"`, `"In review"`, `"Done"`, or `None` for no change/no children. Child status `None` (untracked) is treated by its issue state: closed counts as `"Done"`, open as not started.

- [ ] **Step 1: Write the failing tests** with these assertions: `parse_tracking("projects: [binary-companion/libraries]") == ["binary-companion/libraries"]`; `parse_tracking("") == []`; `parse_tracking("::: not yaml") == []`; `projects_to_add(["a/timetug"], []) == ["a/timetug"]`; `projects_to_add(["a/timetug"], [{"a/timetug"}]) == []`; `projects_to_add(["a/libraries"], [{"a/timetug"}]) == ["a/libraries"]`; a grandparent set suppresses the add; `rollup_status([]) is None`; `["In progress","Backlog"] -> "In progress"`; `["In review","Done"] -> "In review"`; `["In review","Backlog"] -> None`; `["Done","Done"] -> "Done"`; `["Done","In progress"] -> "In progress"`; a reopened child (`["Done", "Backlog"]`) -> `None` (parent leaves Done to its prior non-Done status).
- [ ] **Step 2: Run** `python3 -m pytest scripts/tracking/tests -q`; expect failures for undefined functions.
- [ ] **Step 3: Implement** the three functions in `logic.py`, standard library plus `yaml` for parsing.
- [ ] **Step 4: Run the tests**; expect all pass.

### Task 4: Reusable workflows and caller template (in `binary-companion/.github`)

**Files:**
- Create: `.github/workflows/tracking-add.yml`, `tracking-pr.yml`, `tracking-rollup.yml`, `tracking-ci-bug.yml` (all `workflow_call`), `scripts/tracking/gh_api.py`, `scripts/tracking/cli.py`, `scripts/tracking/tests/test_cli.py`, `docs/caller-template.yml`

**Interfaces:**
- Consumes: Task 3's three functions; secret the GitHub App credentials (`APP_ID`, `APP_PRIVATE_KEY`).
- Produces: `cli.py add|pr|rollup|ci-bug` entry points called by the workflows; `gh_api.py` exposing `project_ids(refs)`, `ancestors(issue)`, `children(issue)`, `set_status(item, status)` over GraphQL.

- [ ] **Step 1: Write failing tests** for `cli.py` using a fake `gh_api` module: `add` on an issue with a parent already in the project calls no add; a PR body with `Fixes #1, Fixes #2` sets both to the target status; a PR with no closing keyword does nothing and exits 0; `rollup` on an issue with no parent does nothing.
- [ ] **Step 2: Run to confirm failure**, then implement `cli.py` and `gh_api.py` (GraphQL via `gh api graphql`).
- [ ] **Step 3: Write the four reusable workflows**: `tracking-add` on `issues: opened` reads `.github/tracking.yml` from the calling repo and runs `add`; `tracking-pr` sets In review on PR opened/ready-for-review and Done on merged; `tracking-rollup` runs on a child's status change and its project item changes; `tracking-ci-bug` files a bug referencing the merge on a failed `master` CI.
- [ ] **Step 4: Write `docs/caller-template.yml`**, the caller each repo copies (the only per-repo logic).
- [ ] **Step 5: Run** `python3 -m pytest scripts/tracking/tests -q` and `actionlint`; expect pass.

### Task 5: Per-repo files and callers

**Files:**
- Create in each of timetug, timetug-shared, timetug-windows, homebrew-tap and the manual-work repo: `.github/tracking.yml` (`projects: [binary-companion/timetug]`) and `.github/workflows/tracking.yml` (from the template). In calendar-connectors: `projects: [binary-companion/libraries]`. Do not add to website.

**Interfaces:**
- Consumes: the template from Task 4; the reusable workflows.

- [ ] **Step 1: Add the files** in each repo as a branch and PR, one PR per repo.
- [ ] **Step 2: Verify the dedup path end to end** by opening a test parent in `timetug` and a child in `calendar-connectors`: parent in TimeTug only, child in Libraries only; then close both.
- [ ] **Step 2b: Test the built-in "Auto-add sub-issues to project" workflow** (enabled on both projects; the dry run showed it adds every sub-issue, #203 findings item 4): confirm what it does for a same-project child and a cross-project child, then decide keep or disable, and encode the decision in the dedup logic and the rules.
- [ ] **Step 3: Verify roll-up**: set the child In progress, then In review, then Done, and confirm the parent follows.

### Task 6: Rules, skill and issue forms (in `timetug`, plus pointers)

**Files:**
- Create: `.agents/skills/tracking-work-in-issues/SKILL.md`, issue forms for a phase sub-issue and a manual task in `binary-companion/.github`
- Modify: `AGENTS.md` (a "Tracking work" section), `.github/pull_request_template.md` (require "Fixes #N"), `docs/development.md` or equivalent, each other repo's `AGENTS.md` (a pointer)

**Interfaces:**
- Consumes: Task 1's dry-run findings; Task 5's working behavior.

- [ ] **Step 1: Write the skill** covering: when to file against which repo, parent and sub-issue structure, the standard issue body shape, stage-summary comments, how agents create issues, the Backlog → Ready design step, manual task creation, which transitions are automatic and which the agent owns, never setting parent status.
- [ ] **Step 2: Fold every dry-run finding into the rules** and replace "manual workaround" lines with the real flow.
- [ ] **Step 3: Update `AGENTS.md`, the PR template and the other repos' pointers.**
- [ ] **Step 4: Run** `scripts/dev/verify.sh release-tools`; expect pass.

### Task 7: Migration

**Files:**
- Modify: `docs/PROGRESS.md` (note that new work is tracked in issues), open plan docs as needed

- [ ] **Step 1: Create issues for open work** (#202, #169 and any in-flight plan items) following the rules, in the right repos, and let the Actions place them on the projects.
- [ ] **Step 2: Mark `PROGRESS.md`** as historical for tracking and point to the TimeTug project.
- [ ] **Step 3: Close #203** only when all four phase sub-issues are Done; confirm the roll-up marks it Done itself.
