# GitHub Actions pins

Resolved from each action's official GitHub tag ref on 2026-09-26 with `gh api repos/OWNER/REPO/git/ref/tags/TAG --jq '.object.sha'`. Workflow `uses` entries retain the selected tag as a comment. Dependabot's `github-actions` weekly updates remain configured in `.github/dependabot.yml`.

| Action | Selected tag | Verified commit |
|---|---|---|
| `actions/checkout` | `v7` | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/checkout` | `v4` | `11d5960a326750d5838078e36cf38b85af677262` |
| `actions/cache` | `v6` | `55cc8345863c7cc4c66a329aec7e433d2d1c52a9` |
| `actions/upload-artifact` | `v7` | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |
| `google-github-actions/auth` | `v3` | `7c6bc770dae815cd3e89ee6cdf493a5fab2cc093` |
| `actions/create-github-app-token` | `v3` | `64ab729a6294000f5aa4a4bc0b73d1f32bc45510` |

These are frozen commits, so release updates require an explicit pin change. The Google auth action runs only on the merge workflow, which signs in with Workload Identity Federation and holds no stored key. `actions/create-github-app-token` runs only in `bump-dependencies.yml`, inside the `bump` environment, to mint a short-lived `timetug-bot` token. `firebase-tools` is pinned in that workflow's `npx` line; bump it by hand. The PR website workflow has no deployment credentials.
