---
name: tracking-work-in-issues
description: Use when starting, planning, executing or finishing a feature or fix that should be tracked, when asked to create or refine a GitHub issue or sub-issue in any binary-companion TimeTug repository, when work needs the owner (a manual task), when updating an issue's status or Agent field, or when a merge leaves CI red.
---

# Tracking work in issues

Progress lives in GitHub issues and two org projects: **TimeTug** (project 1: `timetug`, `timetug-shared`, `timetug-windows`, `homebrew-tap`, `manual-configuration`) and **Libraries** (project 2: `calendar-connectors`). `website` is in neither. Each tracked repo names its projects in `.github/tracking.yml`; do not hard-code a repo-to-project mapping. Plan and spec documents stay in `docs/superpowers/` for large work; progress documents are not kept for new work.

## Where an issue goes

- One repo only: file it in that repo.
- Several repos or platforms: a parent in `timetug` (the product), with a sub-issue in each other repo where code changes. Library work (`timetug-shared`, `calendar-connectors`) that is only in the library is tracked in the library repo alone; an app-visible feature has a `timetug` parent with the library work as a sub-issue; if the app needs only a version bump, only the bump issue is in TimeTug.
- Create sub-issues with the REST API (`POST repos/{owner}/{repo}/issues/{n}/sub_issues`, field `sub_issue_id` is the issue's REST `id`, not its number) and blockers with `POST .../issues/{n}/dependencies/blocked_by` (`issue_id`). Set the issue type (Feature, Bug, Task) with `PATCH` field `type`.

## What an issue contains

A meaningful title and a body a person or a fresh agent can act on without opening a checked-in file:

- **Summary**: what and why, in plain words.
- **Success criteria**: a checklist. Tick items as they are met.
- **Plan**: the slice of the plan this issue needs (steps, files, commands). For large work, link the spec or plan document in addition; small work needs no document.
- **Blocked by** and **Context** (parent, related issues, relevant ADRs).

Agents may refine title, body and criteria while planning and executing. Post a short stage-summary comment at each stage (design done, execution started, review, done). **When an issue closes its body must describe the final state**, not the starting plan.

## Lifecycle and who moves what

Backlog, Ready, In progress, In review, Done (spelled exactly so in the projects). Anyone, or an outside reporter, can file into Backlog.

- **Design**: flesh out the issue until an agent could pick it up; create one sub-issue per phase in the repo where the code lives, with blockers; then set **Ready**. Agents set Ready.
- **In progress**: initial work is under way.
- **In review**: a PR is open and an agent is reviewing, waiting for CI or waiting for the owner.
- **Done**: merged. A PR that fixes an issue says `Fixes #N` (cross-repo: `Fixes owner/repo#N`).
- Work with no PR (settings, docs-only decisions): close the issue when its criteria are met; closing sets Done.
- Set the **Agent** field to the agent that did the work (primary agent on a parent). Set status with `gh project item-edit <number> --owner binary-companion --url <issue url> --field Status --value "In progress"`; `gh project field-list --format json` has control characters that break `jq`, so parse with a tolerant JSON reader.
- **Parents**: their status is derived from their children (In progress when any child is; In review when every child that is not Done is In review; Done only when all children are Done). Never set a parent's status by hand once the roll-up Action is live.
- **Red `master` after a merge**: file a new bug that references the issue or merge that caused it. Do not reopen the Done issue.

Actions (see `binary-companion/.github`) do the mechanical moves: add to the project, In review when a PR opens, Done when it merges, parent roll-up, and the failed-`master` bug. Agents own everything else.

## Creating issues

When asked to create an issue, ask only for what is missing, then file it with the sections above in the right repo and label (`bug` or `enhancement`). File it in Backlog; do not mark it Ready until the design step is done. Do not put credentials or internal infrastructure detail in public repos.

## Manual tasks (owner steps)

When progress needs the owner, create the issue in the private `binary-companion/manual-configuration` repo: label `manual`, issue type **Manual Task**, assigned to the owner, status **Ready**. The body has a one-line summary and numbered, step-by-step instructions with exact values and direct URLs, and success criteria. **Never include a credential.** Make it a sub-issue of the issue that needs it (no wrapper ticket); mark that issue blocked by it when work cannot continue. The owner tells you when it is done; verify, comment, and close it. Add the task to the TimeTug project and set Ready until the Actions do it.

## Credentials

Never print or paste a secret. The owner creates credentials in a browser and gives the agent a file path; copy it into a GitHub secret with `gh secret set NAME < file`, then tell the owner to delete the file.
