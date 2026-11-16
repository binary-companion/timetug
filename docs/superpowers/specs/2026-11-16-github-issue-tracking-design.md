# Tracking work in GitHub issues and projects (design)

Status: draft for approval. Ticket: binary-companion/timetug#203. Related: binary-companion/website#4 (make the website repo private; separate, top level).

## Intent

Feature progress is tracked today in documents on branches. It is hard to see what is moving, what remains, what blocks what, and what needs the owner. This project makes GitHub issues and projects the place where progress lives, with written rules and skills so agents and humans create, plan, execute and close work the same way across all repositories, and with Actions doing the mechanical status changes so status stays honest.

We follow these rules while building them: this project is itself tracked as issues (a parent in `timetug` with a sub-issue per phase) as soon as the rules for doing so exist (phase 2). Until then, #203 and its phase sub-issues are the tracker.

## Goals

- At a glance: what is in flight, what remains, what is blocked, what waits on the owner.
- Every issue is readable and workable alone: a meaningful title, a human summary, intent, success criteria. An agent can pick up an issue or sub-issue without other context.
- Routing is data, not code, and lives in each repo. Adding a repository or a project is a small file in that repo.
- Status moves automatically where it is mechanical; agents handle judgment.
- Owner-only work is a first-class, private, step-by-step ticket.

## Non-goals and anti-goals

- Not replacing plan and spec documents. Large work keeps `docs/superpowers/specs` and `plans`; the issue carries the intent and the relevant slice and links the document. Small work needs no document.
- Progress documents (`docs/PROGRESS.md` style) are retired for tracking new work.
- No credentials in any issue, ever, including manual tickets.
- The `website` repository is in no project. Not tracked by this design beyond website#4.
- Anti-goal: a design where each repo carries its own copy of the logic and drifts.

## Repositories and projects

| Repository | Project |
|---|---|
| timetug, timetug-shared, timetug-windows, homebrew-tap, the new private manual-work repo | TimeTug |
| calendar-connectors | Libraries |
| website | none |

Each repo declares this in its own `.github/tracking.yml` (see Routing), not in workflow code. `timetug-shared` follows the same pattern as `calendar-connectors` in its relationship to the app: work only in the library is tracked in the library's tracker; app-visible features hang off a `timetug` parent with the library work as a sub-issue.

## Issue structure

1. A single-platform or single-repo item is one issue in the repo with the code.
2. Anything that touches other repos is a parent issue plus a sub-issue per other repo.
3. A feature spanning platforms (for example Windows and Mac) has its parent in `timetug`, with sub-issues in `timetug-windows` and so on.
4. Parents are never in a repo only to hold children: the parent is where the intent and success criteria live; sub-issues hold the repo-specific slice of the plan, blockers (via GitHub's "blocked by" relations) and their own success criteria.
5. A change to a library plus only a version bump elsewhere: the library issue is the work; only the bump issue appears in the TimeTug project.
6. Agents may refine title, body and success criteria during planning and execution, and post a summary comment at each stage.

## Lifecycle

Backlog → (design: flesh out, create phase sub-issues in the repos where code lives, mark blockers) → Ready → In progress → In review → Done.

- Backlog: created by a human, an agent or from outside (the public issue forms).
- Ready: requirements are complete enough for an agent; sub-issues exist; blockers noted.
- In progress: initial work under way.
- In review: a PR is open and an agent is reviewing, waiting for CI, or waiting for the owner.
- Done: merged. A red CI after merge is a new bug issue that references the issue or merge that caused it; the original stays Done.

Parent status is derived and set only by the roll-up Action: In progress when any child is In progress; In review when every child that is not Done is In review (at least one); Done only when all children are Done. Agents never set a parent's status by hand.

## Project fields

- Status: Backlog, Ready, In progress, In review, Done.
- Agent: the primary agent for a parent; the agent that did the work for a sub-issue. Set by the agent.
- Type (issue type): Bug, Feature, Task, plus an org issue type **Manual Task**.

## Manual tasks

When a ticket needs the owner, the agent creates an issue in the private manual-work repo, assigned to the owner, status Ready, label `manual`, type Manual Task. The description has numbered step-by-step instructions, exact values and direct links (never credentials). It is a sub-issue of the issue that needs it, added directly with no separate tracking ticket (cross-repo sub-issues show under the parent), and it blocks that issue when the work cannot proceed without it. A phase or grouping issue exists only where there is agent work in it; an owner step with no agent work goes directly under the issue it unblocks, never under a wrapper issue (the dry run's #207 was one, kept as a record). Because the repo is private, the steps may describe internal structure.

## Automation (the mix)

Agents own judgment: body and criteria, sub-issues, blocker relations, the Agent field, stage-summary comments, and the Backlog → Ready decision. Actions own mechanical transitions:

- Add to project on issue open, per the repo's `tracking.yml`: add the issue to each listed project it is not already in. GitHub's built-in "Auto-add sub-issues" also adds a child to its parent's project, so a cross-repo child can be in two projects (for example a `calendar-connectors` child of a `timetug` parent is in Libraries and TimeTug). This was tested on 2026-11-16 and is accepted: every status write goes to all of an issue's project items so they never disagree, and the roll-up reads each child's status from the parent's project.
- PR opened or marked ready → In review on its linked issues; PR merged → Done on its linked issues ("Fixes #N").
- Parent roll-up when a child's status changes.
- Failed CI on `master` → a bug issue referencing the merge.

The mix needs a token the default `GITHUB_TOKEN` cannot provide (org project write). Phase 1 includes a bot token or GitHub App, held as an org secret.

## Approaches considered

- A. Per-repo copies of forms, rules and workflows. Rejected: six copies drift; roll-up logic duplicated.
- **B. Central source (chosen).** Public `binary-companion/.github` repo holds org-default issue forms and reusable workflows. Each repo has a short caller workflow and its own `.github/tracking.yml` naming its projects. Canonical rules and the agent skill live in `timetug`; other repos' `AGENTS.md` point to them.
- C. Built-in project workflows only. Rejected: no roll-up, no sub-issue dedup.

## Routing: each repository declares its own projects

Each tracked repo carries `.github/tracking.yml` (name is a builder's call):

```yaml
# timetug, timetug-shared, timetug-windows, homebrew-tap, the manual-work repo
projects: [binary-companion/timetug]
```

```yaml
# calendar-connectors
projects: [binary-companion/libraries]
```

A repo with no file, or an empty list, is not tracked (`website` has none). A repo may list several projects. The reusable workflows in `.github` read the calling repo's own file, so there is no central routing data and no per-repo special case in code. The file is versioned and reviewed in a PR. A check in the caller workflow validates that each listed project exists and that the bot token can write to it.

Same-project children are project items too (they carry their own status); the built-in sub-issue auto-add puts a child in its parent's project and `tracking.yml` puts it in its own repo's projects, so a `calendar-connectors` child under a `timetug` parent is in both. A new repo adopts tracking by adding its caller workflow and this file; nothing central changes. A new project is just a new entry in the repos that use it.

Considered and not chosen: GitHub's native repo-to-project link as the source of truth. It has no config file, but it is not in git (no review or diff) and conflates "linked for visibility" with "track here".

## Phases (each a sub-issue of #203, in the repo where the work lands)

1. Owner setup (manual tasks): `gh auth refresh -s project`; create the projects and fields; the Manual Task issue type; the private manual-work repo; the bot token or GitHub App and org secret; confirm the website repo is handled by website#4. The first manual tickets are filed in `timetug` as sub-issues of #203, since the private repo does not exist yet; move them afterwards.
2. Rules and templates: the skill and `AGENTS.md` sections in `timetug`; issue forms in `.github` including a phase sub-issue form and a manual task form; labels (`manual` and others); pointers from the other repos' `AGENTS.md`; update the PR template to require "Fixes #N". Docs say progress docs are retired for new work.
3. Actions: reusable workflows in `.github`, caller workflow and `tracking.yml` per repo, tests for the file validation, dedup and roll-up logic (written first).
4. Migration: put open work on issues and stop updating progress docs.

## Constraints

- Public repos' reusable workflows may be called from private ones only if the workflow repo allows it; the `.github` repo must be public for default community health files, so no secrets or internal structure in it.
- Issue content in public repos is public: internal details belong only in manual tickets.
- The default `GITHUB_TOKEN` cannot write org projects.

## Left to the builder

- Exact name and schema of `tracking.yml`, workflow file layout, and the language for workflow helpers.
- Label set beyond `manual`, and exact form wording.
- How the roll-up Action walks sub-issue relations (GraphQL) and handles the cross-repo cases.
- Whether Ready is set by agents via the CLI or by a label.
