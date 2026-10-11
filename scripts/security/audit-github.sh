#!/usr/bin/env bash
# Audit the GitHub controls from the Windows program spec, section 8.
#
#   scripts/security/audit-github.sh [--strict] [ORG] [REPO | OWNER/REPO ...]
#
# Needs an authenticated `gh`. Checks that need the `admin:org` scope are reported as SKIP, not
# PASS, when the token cannot read them; `--strict` turns every SKIP into a failure so the
# owner's final run (with a refreshed token) must prove them. Exit 0 only when nothing FAILed.
#
# Repositories default to every repository in the organization. A repository named in the
# TAG_RULESET_REPOS list below must also have an active release-tag ruleset.
set -uo pipefail

STRICT=0
ARGS=()
for a in "$@"; do
  if [ "$a" = "--strict" ]; then STRICT=1; else ARGS+=("$a"); fi
done
ORG="${ARGS[0]:-binary-companion}"
REPOS=("${ARGS[@]:1}")

# Repositories that ship signed releases and so need a `v*` tag ruleset.
TAG_RULESET_REPOS=" timetug timetug-windows timetug-shared calendar-connectors "
# Secret names that may live at repository level (read-only public-data credentials, spec section 8).
ALLOWED_REPO_SECRETS=" DOCKERHUB_USERNAME DOCKERHUB_TOKEN "

fails=0
skips=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
skip() { printf 'SKIP  %s\n' "$1"; skips=$((skips + 1)); }

# api PATH [JQ]: prints the value; returns non-zero when the call fails (no permission, not found).
api() { gh api "$1" --jq "${2:-.}" 2>/dev/null; }

echo "== Organization $ORG"
org_json=$(gh api "orgs/$ORG" 2>/dev/null) || { echo "cannot read organization $ORG"; exit 2; }
field() { printf '%s' "$org_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$1'))"; }

[ "$(field two_factor_requirement_enabled)" = "True" ] \
  && pass "two-factor authentication is required" || fail "two-factor authentication is not required"
[ "$(field members_can_create_repositories)" = "False" ] \
  && pass "members cannot create repositories" || fail "members can create repositories"
[ "$(field default_repository_permission)" = "read" ] \
  && pass "base permission is read" || fail "base permission is $(field default_repository_permission), expected read"

admins=$(api "orgs/$ORG/members?role=admin" '[.[].login]|sort|join(",")') || admins=""
members=$(api "orgs/$ORG/members" '[.[].login]|sort|join(",")') || members=""
if [ -n "$members" ]; then
  if [ "$members" = "$admins" ] && [ "${members#*,}" = "$members" ]; then
    pass "the owner ($members) is the only member and admin"
  else
    fail "members ($members) are not just the owner-admin ($admins)"
  fi
else
  skip "could not list organization members"
fi

if perms=$(api "orgs/$ORG/actions/permissions"); then
  allowed=$(printf '%s' "$perms" | python3 -c "import json,sys; print(json.load(sys.stdin).get('allowed_actions'))")
  [ "$allowed" = "selected" ] && pass "Actions limited to an allow-list" || fail "Actions policy is '$allowed', expected 'selected'"
  sha=$(printf '%s' "$perms" | python3 -c "import json,sys; print(json.load(sys.stdin).get('sha_pinning_required'))")
  [ "$sha" = "True" ] && pass "Actions SHA pinning is required" || fail "Actions SHA pinning is not required"
else
  skip "Actions policy (needs the admin:org scope: gh auth refresh -s admin:org)"
fi

if [ ${#REPOS[@]} -eq 0 ]; then
  while IFS= read -r r; do [ -n "$r" ] && REPOS+=("$r"); done < <(api "orgs/$ORG/repos?per_page=100" '.[].name')
fi

for repo in "${REPOS[@]}"; do
  case "$repo" in */*) full="$repo"; repo="${repo##*/}" ;; *) full="$ORG/$repo" ;; esac
  echo "== $full"
  branch=$(api "repos/$full" '.default_branch') || { fail "cannot read $full"; continue; }

  collabs=$(api "repos/$full/collaborators?affiliation=outside" '[.[].login]|join(",")') || collabs="?"
  if [ "$collabs" = "?" ]; then skip "outside collaborators"
  elif [ -z "$collabs" ]; then pass "no outside collaborators"
  else fail "outside collaborators: $collabs"; fi

  rulesets=$(api "repos/$full/rulesets" '.[].id') || rulesets=""
  have_branch=0
  have_tag=0
  for id in $rulesets; do
    detail=$(gh api "repos/$full/rulesets/$id" 2>/dev/null) || continue
    summary=$(printf '%s' "$detail" | python3 -c "
import json,sys
d=json.load(sys.stdin)
rules={r['type'] for r in d['rules']}
inc=d.get('conditions',{}).get('ref_name',{}).get('include',[])
print(d['target'], d['enforcement'], ','.join(sorted(rules)), '|'.join(inc))")
    target=$(printf '%s' "$summary" | cut -d' ' -f1)
    enforcement=$(printf '%s' "$summary" | cut -d' ' -f2)
    rules=$(printf '%s' "$summary" | cut -d' ' -f3)
    [ "$enforcement" = "active" ] || continue
    if [ "$target" = "branch" ] && printf '%s' "$rules" | grep -q "pull_request" \
       && printf '%s' "$rules" | grep -q "deletion" && printf '%s' "$rules" | grep -q "non_fast_forward"; then
      have_branch=1
    fi
    if [ "$target" = "tag" ] && printf '%s' "$rules" | grep -q "update" && printf '%s' "$rules" | grep -q "deletion"; then
      have_tag=1
    fi
  done
  [ $have_branch -eq 1 ] && pass "default branch ($branch): pull request required, no force push, no deletion" \
    || fail "default branch ($branch) lacks an active ruleset with pull_request, deletion and non_fast_forward"
  case "$TAG_RULESET_REPOS" in
    *" $repo "*)
      [ $have_tag -eq 1 ] && pass "release tags are protected by a ruleset" || fail "no active release-tag ruleset" ;;
  esac

  if secrets=$(api "repos/$full/actions/secrets" '.secrets[].name'); then
    bad=""
    for s in $secrets; do
      case "$ALLOWED_REPO_SECRETS" in *" $s "*) ;; *) bad="$bad $s" ;; esac
    done
    [ -z "$bad" ] && pass "no repository-level secrets beyond the read-only allow-list" \
      || fail "repository-level secrets:$bad (move them into an environment)"
  else
    skip "repository secrets (needs repository admin)"
  fi

  for env in $(api "repos/$full/environments" '.environments[].name'); do
    case "$env" in
      release|appstore|store-windows)
        e=$(gh api "repos/$full/environments/$env" 2>/dev/null) || { skip "environment $env"; continue; }
        verdict=$(printf '%s' "$e" | python3 -c "
import json,sys
d=json.load(sys.stdin)
reviewers=any(r['type']=='required_reviewers' for r in d.get('protection_rules',[]))
print('admin-bypass' if d.get('can_admins_bypass') else 'no-bypass', 'reviewer' if reviewers else 'no-reviewer')")
        case "$verdict" in
          *admin-bypass*) fail "environment $env allows admin bypass" ;;
          *) pass "environment $env: admin bypass is off ($verdict)" ;;
        esac ;;
    esac
  done
done

echo
echo "result: $fails failed, $skips skipped"
if [ "$fails" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$skips" -gt 0 ]; then echo "strict: skipped checks count as failures"; exit 1; fi
exit 0
