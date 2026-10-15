#!/usr/bin/env bash
# Tests .github/workflows/bump-dependencies.yml: pins the shape of the workflow (triggers, the job `if`, the
# library and version plumbing, environment, token scope), runs its "Move the pin" step against the real
# scripts/ci/bump-pin.sh and resolved-version.py (so the step must use their current command lines) with a stub
# `gh api` for the timetug-shared tag's Package.resolved, then runs its "Open the pull request" step against stub
# `git` and `gh` and asserts which pull requests it opens and closes, for both libraries. The steps are
# extracted from the workflow and executed, so the real text is what is tested.
# BUMP_WORKFLOW points at another copy of the workflow (used to prove that mutated copies fail).
# PYTHON selects the interpreter that has PyYAML (default python3).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WORKFLOW="${BUMP_WORKFLOW:-$ROOT/.github/workflows/bump-dependencies.yml}"
PYTHON="${PYTHON:-python3}"
for tool in jq perl base64; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FAIL: $tool is required" >&2; exit 2; }
done
"$PYTHON" -c 'import yaml' 2>/dev/null || { echo "FAIL: PyYAML is required (pip install -r scripts/ci/requirements-test.txt)" >&2; exit 2; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- the shape of the workflow, then the two steps extracted ---
"$PYTHON" - "$WORKFLOW" "$T/open.sh" "$T/move.sh" <<'PY'
import re, sys, yaml
workflow, open_target, move_target = sys.argv[1:]
raw = open(workflow).read()
document = yaml.safe_load(raw)
def check(condition, message):
    if not condition:
        sys.exit(f'FAIL: {workflow}: {message}')
LIBRARIES = ['calendar-connectors', 'timetug-shared']
triggers = document.get(True, document.get('on'))
check(isinstance(triggers, dict) and set(triggers) == {'repository_dispatch', 'workflow_dispatch'},
      'the triggers must be exactly repository_dispatch and workflow_dispatch (never pull_request_target or push)')
check(triggers['repository_dispatch'] == {'types': ['library-released']},
      'repository_dispatch must react to exactly the event type library-released')
inputs = triggers['workflow_dispatch'].get('inputs', {})
check(set(inputs) == {'library', 'version'}, 'workflow_dispatch must take exactly the inputs library and version')
check(inputs['library'].get('type') == 'choice' and inputs['library'].get('options') == LIBRARIES
      and inputs['library'].get('required') is True,
      'the library input must be a required choice of exactly calendar-connectors and timetug-shared')
check(inputs['version'].get('required') is True, 'the version input must be required')
check(document.get('permissions') == {}, 'the workflow-level permissions must be {}')
check(document.get('concurrency') == {'group': "bump-${{ github.event.client_payload.library || inputs.library }}",
                                      'cancel-in-progress': False},
      'concurrency must be one group per library (bump-<library>) without cancelling')
check(list(document['jobs']) == ['bump'], 'the workflow must have exactly the job bump')
job = document['jobs']['bump']
condition = job.get('if')
check(condition == "github.event_name == 'workflow_dispatch' || "
                   "contains(fromJSON('[\"calendar-connectors\",\"timetug-shared\"]'), github.event.client_payload.library)",
      'the job must run only for a manual dispatch or for a payload library in the two-name allow-list')
# The `if` is a GitHub expression; evaluate the one shape allowed here for every payload that matters. GitHub's
# contains() compares strings without case, so a payload library that differs only in case passes the `if` and
# must be stopped by the step's own validation (tested below).
shape = re.fullmatch(r"github\.event_name == '(\w+)' \|\| contains\(fromJSON\('(\[[^']*\])'\), "
                     r"github\.event\.client_payload\.library\)", condition)
check(shape is not None, 'the job `if` is not the shape this harness can evaluate')
import json
allowed = [name.lower() for name in json.loads(shape.group(2))]
def runs(event_name, library):
    return event_name == shape.group(1) or (isinstance(library, str) and library.lower() in allowed)
for library in LIBRARIES:
    check(runs('repository_dispatch', library), f'a payload for {library} must run the job')
for library in ('other', '', 'timetug', 'calendar-connectors-evil', 'timetug-shared/x', None):
    check(not runs('repository_dispatch', library), f'a payload with library {library!r} must skip the job')
check(runs('workflow_dispatch', None), 'a manual dispatch must run the job')
check(job.get('environment') == 'bump', 'the job must use the bump environment (it holds the bot key)')
check(job.get('runs-on') == 'ubuntu-latest', 'the job must run on ubuntu-latest')
check(job.get('permissions') == {'contents': 'read'}, 'the job permissions must be exactly contents: read')
check(job.get('env') == {'LIBRARY': '${{ github.event.client_payload.library || inputs.library }}',
                         'VERSION': '${{ github.event.client_payload.version || inputs.version }}'},
      'the job env must be exactly LIBRARY and VERSION, each from the payload or the input')
check('continue-on-error' not in job, 'the job must not set continue-on-error')
steps = job['steps']
check(len(steps) == 4, 'the job must have exactly four steps: token, checkout, move, open')
token, checkout, move, open_pr = steps
check(token.get('id') == 'app' and token.get('uses') == 'actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510',
      'the first step must be the token step (id app) pinned to the reviewed create-github-app-token SHA')
check(token.get('with') == {'app-id': '${{ vars.BUMP_APP_ID }}',
                            'private-key': '${{ secrets.BUMP_APP_PRIVATE_KEY }}',
                            'owner': '${{ github.repository_owner }}',
                            'repositories': 'timetug',
                            'permission-contents': 'write',
                            'permission-pull-requests': 'write'},
      'the token step must be scoped to repositories: timetug with exactly permission-contents: write and '
      'permission-pull-requests: write')
check(checkout.get('uses') == 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1',
      'the checkout must be pinned to the reviewed actions/checkout SHA')
check(checkout.get('with') == {'ref': 'master', 'token': '${{ steps.app.outputs.token }}'},
      'the checkout must be ref: master with the app token (so the push is made by the bot)')
check(move.get('name') == 'Move the pin' and open_pr.get('name') == 'Open the pull request',
      'the last two steps must be "Move the pin" and "Open the pull request", in that order')
for step in (move, open_pr):
    check(step.get('env') == {'GH_TOKEN': '${{ steps.app.outputs.token }}'},
          f"the step {step['name']!r} env must be exactly GH_TOKEN (the app token)")
    check('${{' not in step['run'], f"the step {step['name']!r} must not contain ${{{{ }}}} (values reach it through env)")
    check('continue-on-error' not in step, f"the step {step['name']!r} must not set continue-on-error")
    check(not re.search(r'gh\s+pr\s+merge|--auto\b|--admin\b|--label|--add-label|/merge\b|gh\s+workflow\s+run', step['run']),
          f"the step {step['name']!r} must never merge, auto-merge, label or start workflows (a new bump is a patch by default)")
for line in raw.splitlines():
    uses = re.match(r'\s*(?:-\s*)?uses:\s*(\S+)(.*)', line)
    if uses:
        check(re.fullmatch(r'[\w./-]+@[0-9a-f]{40}', uses.group(1)) and re.match(r'\s*# v\d+\s*$', uses.group(2)),
              f'every action must be pinned by commit SHA with the tag in a comment: {line.strip()}')
check('refs/pull' not in raw and 'pull_request' not in raw, 'the workflow must not mention pull_request triggers')
open(open_target, 'w').write(open_pr['run'])
open(move_target, 'w').write(move['run'])
PY

# --- stubs ---
cat > "$T/bin/git" <<'SCRIPT'
#!/usr/bin/env bash
echo "git $*" >> "$CALLS"
case "$1" in
  diff) [ "${DIFF_CLEAN:-0}" = 1 ] && exit 0 || exit 1;;
  ls-remote) [ "${BRANCH_EXISTS:-0}" = 1 ] && exit 0 || exit 2;;
esac
exit 0
SCRIPT
# `gh pr list --head X` matches the head branch name of every pull request, forks included, like the real one.
# `gh api` answers the timetug-shared tag's Package.resolved from canned JSON files ($RESOLVED/<ref>.json holds
# {"content": "<base64>"}) and applies the real --jq expression with jq; a ref without a file is a 404.
cat > "$T/bin/gh" <<'SCRIPT'
#!/usr/bin/env bash
echo "gh $*" >> "$CALLS"
case "$1 $2" in
  "pr list")
    head=""; expr="."; state=""
    args=("$@")
    for ((i = 0; i < ${#args[@]}; i++)); do
      [ "${args[i]}" = --head ] && head="${args[i+1]}"
      [ "${args[i]}" = --jq ] && expr="${args[i+1]}"
      [ "${args[i]}" = --state ] && state="${args[i+1]}"
    done
    # Closed and merged pull requests are not in the fixture; an explicit --state open is what the workflow
    # must ask for, so a lookup without it is an error here.
    [ "$state" = open ] || { echo "stub gh: pr list without --state open" >&2; exit 98; }
    jq -c --arg head "$head" 'map(select($head == "" or .headRefName == $head))' "$PRS" | jq -r "$expr";;
  "pr create")
    args=("$@")
    for ((i = 0; i < ${#args[@]}; i++)); do
      [ "${args[i]}" = --title ] && echo "${args[i+1]}" > "$CREATED.title"
      [ "${args[i]}" = --body-file ] && cp "${args[i+1]}" "$CREATED.body"
    done
    echo "https://github.com/binary-companion/timetug/pull/99";;
  "pr close")
    case " ${FAIL_CLOSE:-} " in *" $3 "*) echo "could not close $3" >&2; exit 1;; esac;;
  "release view") echo "release notes of $5";;
  "api repos/binary-companion/timetug-shared/contents/Package.resolved?ref="*)
    ref="${2#*ref=}"
    file="$RESOLVED/${ref//\//_}.json"
    [ -f "$file" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    expr="."; [ "$3" = --jq ] && expr="$4"
    jq -r "$expr" "$file";;
  *) echo "stub gh: unexpected call: $*" >&2; exit 99;;
esac
exit 0
SCRIPT
chmod +x "$T/bin/git" "$T/bin/gh"
no_forbidden_calls() { # after every run: the workflow never merges, labels or starts workflows
  if grep -Eq 'pr merge|--auto|--admin|--label|--add-label|pr edit|workflow run' "$T/calls"; then
    fail "a forbidden gh call was made: $(grep -E 'pr merge|--auto|--admin|--label|--add-label|pr edit|workflow run' "$T/calls")"
  fi
}

# --- the "Move the pin" step, in a tree with the real scripts and a project.yml with chosen pins ---
# pin_in <file> <project.yml key> prints the exactVersion of that entry; set_pin <file> <key> <version> sets it.
pin_in() { perl -0ne 'print $1 if m{^[ \t]+'"$2"':[ \t]*\n[ \t]+url:[^\n]*\n[ \t]+exactVersion:[ \t]*([0-9.]+)}m' "$1"; }
set_pin() {
  KEY="$2" NEW="$3" perl -0pi -e 's{(^[ \t]+\Q$ENV{KEY}\E:[ \t]*\n[ \t]+url:[^\n]*\n[ \t]+exactVersion:[ \t]*)[0-9.]+}{$1$ENV{NEW}}m' "$1"
}
CC=CalendarConnectors
TS=TimeTugShared
# A project.yml pinned at <connector> and <shared>; the real file supplies everything else.
fresh_tree() {
  rm -rf "$T/move" "$T/resolved"
  mkdir -p "$T/move/scripts/ci" "$T/move/Apps/macOS" "$T/resolved"
  cp "$ROOT/scripts/ci/bump-pin.sh" "$ROOT/scripts/ci/resolved-version.py" "$T/move/scripts/ci/"
  cp "$ROOT/Apps/macOS/project.yml" "$T/move/Apps/macOS/"
  set_pin "$T/move/Apps/macOS/project.yml" $CC "$1"
  set_pin "$T/move/Apps/macOS/project.yml" $TS "$2"
  [ "$(pin_in "$T/move/Apps/macOS/project.yml" $CC)" = "$1" ] || fail "fixture: connector pin is not $1"
  [ "$(pin_in "$T/move/Apps/macOS/project.yml" $TS)" = "$2" ] || fail "fixture: shared pin is not $2"
  cp "$T/move/Apps/macOS/project.yml" "$T/move.original"
}
untouched() { cmp -s "$T/move/Apps/macOS/project.yml" "$T/move.original"; }
cc_pin() { pin_in "$T/move/Apps/macOS/project.yml" $CC; }
ts_pin() { pin_in "$T/move/Apps/macOS/project.yml" $TS; }
# resolved <tag> <json of pins>: the Package.resolved the stub serves for ?ref=refs/tags/<tag>.
resolved() {
  local body
  body="$(printf '{"originHash":"x","pins":%s,"version":3}' "$2" | base64 | tr -d '\n')"
  printf '{"content":"%s"}' "$body" > "$T/resolved/refs_tags_$1.json"
}
cc_pins() { printf '[{"identity":"calendar-connectors","kind":"remoteSourceControl","location":"https://github.com/binary-companion/calendar-connectors","state":{"revision":"092808b0c444c26f793b924f76210589a28a359b","version":"%s"}}]' "$1"; }
# move <library> <version>: sets STATUS; output in $T/move.out, calls in $T/calls, GITHUB_ENV in $T/github_env.
move() {
  : > "$T/calls"; : > "$T/github_env"
  STATUS=0
  (cd "$T/move" && CALLS="$T/calls" RESOLVED="$T/resolved" LIBRARY="$1" VERSION="$2" GH_TOKEN=unused \
     GITHUB_ENV="$T/github_env" RUNNER_TEMP="$T" PATH="$T/bin:$PATH" bash "$T/move.sh") > "$T/move.out" 2>&1 || STATUS=$?
  no_forbidden_calls
}

# calendar-connectors: only that pin moves, nothing is read from timetug-shared, no RECORDED.
fresh_tree 1.0.2 1.0.0
move calendar-connectors 1.998.0
[ "$STATUS" = 0 ] || fail "moving calendar-connectors failed: $(cat "$T/move.out")"
[ "$(cc_pin)" = 1.998.0 ] || fail 'the Move the pin step did not move the calendar-connectors pin'
[ "$(ts_pin)" = 1.0.0 ] || fail 'the Move the pin step changed the timetug-shared pin for a connector release'
grep -q 'gh api' "$T/calls" && fail 'a connector release read the timetug-shared tag'
grep -q '^RECORDED=' "$T/github_env" && fail 'a connector release recorded a connector pin'

# (a) timetug-shared 1.0.0 whose Package.resolved pins the connector at 1.0.4 while the project pins 1.0.2:
# both pins move, and the tag is read as a tag (refs/tags/1.0.0), not as a possibly ambiguous name.
fresh_tree 1.0.2 0.9.0
resolved 1.0.0 "$(cc_pins 1.0.4)"
move timetug-shared 1.0.0
[ "$STATUS" = 0 ] || fail "(a) moving timetug-shared failed: $(cat "$T/move.out")"
[ "$(ts_pin)" = 1.0.0 ] || fail '(a) the timetug-shared pin did not move to 1.0.0'
[ "$(cc_pin)" = 1.0.4 ] || fail "(a) the connector pin is $(cc_pin), expected 1.0.4 (the version the tag resolves)"
grep -q 'gh api repos/binary-companion/timetug-shared/contents/Package.resolved?ref=refs/tags/1.0.0 ' "$T/calls" ||
  fail "(a) the tag's Package.resolved was not read from refs/tags/1.0.0: $(grep 'gh api' "$T/calls")"
grep -qx 'RECORDED=1.0.4' "$T/github_env" || fail "(a) RECORDED was not exported to the next step: $(cat "$T/github_env")"

# (b) the tag resolves a connector version below the project's pin: the connector pin is never lowered.
fresh_tree 1.0.2 0.9.0
resolved 1.0.0 "$(cc_pins 1.0.1)"
move timetug-shared 1.0.0
[ "$STATUS" = 0 ] || fail "(b) a lower recorded connector pin failed the step: $(cat "$T/move.out")"
[ "$(cc_pin)" = 1.0.2 ] || fail "(b) the connector pin was lowered to $(cc_pin)"
[ "$(ts_pin)" = 1.0.0 ] || fail '(b) the timetug-shared pin did not move'
# ... and with the same version the connector pin is left alone too.
fresh_tree 1.0.4 0.9.0
resolved 1.0.0 "$(cc_pins 1.0.4)"
move timetug-shared 1.0.0
[ "$STATUS" = 0 ] && [ "$(cc_pin)" = 1.0.4 ] && [ "$(ts_pin)" = 1.0.0 ] || fail '(b) an equal recorded connector pin changed something else'
# A numeric, not textual, comparison: recorded 1.0.10 is above 1.0.9.
fresh_tree 1.0.9 0.9.0
resolved 1.0.0 "$(cc_pins 1.0.10)"
move timetug-shared 1.0.0
[ "$STATUS" = 0 ] && [ "$(cc_pin)" = 1.0.10 ] || fail "(b) 1.0.10 was not treated as above 1.0.9 (pin is $(cc_pin))"

# The tag's Package.resolved is not there (404), has no connector pin, or pins it by branch or revision: the step
# fails loudly and nothing is moved (neither pin), never a silent skip of the connector move.
fresh_tree 1.0.2 0.9.0
move timetug-shared 1.0.0
[ "$STATUS" != 0 ] && untouched || fail 'a tag without Package.resolved did not fail the step with the file untouched'
grep -q '::error::' "$T/move.out" || fail 'a tag without Package.resolved failed without an ::error:: annotation'
fresh_tree 1.0.2 0.9.0
resolved 1.0.0 '[{"identity":"swift-log","state":{"revision":"abc","version":"1.5.0"}}]'
move timetug-shared 1.0.0
[ "$STATUS" != 0 ] && untouched || fail 'a Package.resolved without the connector pin did not fail the step with the file untouched'
grep -q '::error::' "$T/move.out" || fail 'a missing connector pin failed without an ::error:: annotation'
fresh_tree 1.0.2 0.9.0
resolved 1.0.0 '[{"identity":"calendar-connectors","state":{"branch":"main","revision":"abc"}}]'
move timetug-shared 1.0.0
[ "$STATUS" != 0 ] && untouched || fail 'a connector pin without a version did not fail the step with the file untouched'
fresh_tree 1.0.2 0.9.0
resolved 1.0.0 "$(cc_pins 1.0.4-rc1)"
move timetug-shared 1.0.0
[ "$STATUS" != 0 ] && untouched || fail 'a pre-release connector pin was accepted'
fresh_tree 1.0.2 0.9.0
printf '{"content":"%s"}' "$(printf 'not json' | base64 | tr -d '\n')" > "$T/resolved/refs_tags_1.0.0.json"
move timetug-shared 1.0.0
[ "$STATUS" != 0 ] && untouched || fail 'an unreadable Package.resolved was accepted'

# A downgrade of the library itself is refused and leaves the file; the same version is a no-op.
fresh_tree 1.0.2 1.0.5
resolved 1.0.4 "$(cc_pins 1.0.4)"
move timetug-shared 1.0.4
[ "$STATUS" != 0 ] && untouched || fail 'a downgrade of timetug-shared was accepted'
fresh_tree 1.0.4 1.0.0
resolved 1.0.0 "$(cc_pins 1.0.4)"
move timetug-shared 1.0.0
[ "$STATUS" = 0 ] && untouched || fail 'the version that is already pinned was not a no-op'

# A hostile or unknown library and a hostile or malformed version are refused by the step itself, before any
# API call, git call or file change; the message is the step's own.
fresh_tree 1.0.2 0.9.0
resolved 1.0.0 "$(cc_pins 1.0.4)"
for hostile in '' other Timetug-Shared 'timetug-shared ' 'timetug-shared/../x' 'timetug' 'calendar-connectors-evil' \
               '$(touch /tmp/x)' "timetug-shared
calendar-connectors"; do
  move "$hostile" 1.0.0
  [ "$STATUS" != 0 ] || fail "the library '$hostile' was accepted"
  untouched || fail "the library '$hostile' modified the file"
  grep -q 'gh api' "$T/calls" && fail "the library '$hostile' reached the API"
  grep -q '::error::' "$T/move.out" || fail "the library '$hostile' was refused without the step's own ::error::"
done
for hostile in '../../../repos/other/x' '1.0' 'v1.0.5' '1.0.5-rc1' '1.0.1234567890123' "1.0.0
1.0.1" '' '1.0.5 --jq .' '$(touch /tmp/x)' '99999999999999999999.0.0' '01.0.0' 'refs/tags/1.0.0'; do
  for library in calendar-connectors timetug-shared; do
    move "$library" "$hostile"
    [ "$STATUS" != 0 ] || fail "the version '$hostile' was accepted for $library"
    untouched || fail "the version '$hostile' modified the file for $library"
    grep -q 'gh api' "$T/calls" && fail "the version '$hostile' reached the API for $library"
    grep -q '::error::' "$T/move.out" || fail "the version '$hostile' was refused without the step's own ::error::"
  done
done

# --- the "Open the pull request" step against stub git and gh ---
pr() { printf '{"number":%s,"headRefName":"%s","isCrossRepository":%s}' "$1" "$2" "${3:-false}"; }
# run <library> <version> <extra pull requests as json objects, or empty>; the pull requests are in $PRS_JSON
# (a json list body); RECORDED may be set in the environment. Sets STATUS, CLOSED (sorted numbers) and CALLS.
run() {
  local library="$1" version="$2" extra="${3:-}"
  printf '[%s%s]\n' "$PRS_JSON" "${extra:+,$extra}" > "$T/prs.json"
  : > "$T/calls"; rm -f "$T/created.title" "$T/created.body"
  STATUS=0
  CALLS="$T/calls" PRS="$T/prs.json" CREATED="$T/created" RUNNER_TEMP="$T" LIBRARY="$library" VERSION="$version" \
    PATH="$T/bin:$PATH" bash "$T/open.sh" > "$T/out" 2>&1 || STATUS=$?
  CLOSED="$({ grep '^gh pr close ' "$T/calls" || true; } | awk '{print $4}' | sort -n | tr '\n' ' ' | sed 's/ $//')"
  no_forbidden_calls
}
called() { grep -q -- "$1" "$T/calls"; }

# The phase 1 matrix once per library, with no recorded connector pin: only that library's own older bump
# pull requests are superseded; the other library's are never touched.
matrix() {
  local library="$1" other="$2" P="bump/$1" O="bump/$2" saved
  PRS_JSON="$(pr 10 $P-1.0.2),$(pr 11 $P-1.0.9),$(pr 12 $P-1.0.10),$(pr 13 $P-1.0.3),\
$(pr 14 feature/other),$(pr 15 $P-1.0.3-rc1),$(pr 16 x$P-1.0.1),$(pr 17 $P-1.0.1 true),$(pr 18 $P-1.0.0),\
$(pr 19 $O-1.0.0),$(pr 20 $O-0.0.1)"
  saved="$PRS_JSON"

  # 1.0.3 with the same-repository 1.0.3 pull request open: nothing is created; 1.0.2 and 1.0.0 are superseded;
  # 1.0.9, 1.0.10, the equal 1.0.3, the rc, the unrelated, the prefixed-name, the cross-repository one and the
  # other library's are not.
  run "$library" 1.0.3
  [ "$STATUS" = 0 ] || fail "$library 1.0.3 with an open pull request exited $STATUS: $(cat "$T/out")"
  [ "$CLOSED" = "10 18" ] || fail "$library 1.0.3 closed '$CLOSED', expected '10 18'"
  called 'gh pr create' && fail "$library: an open same-repository pull request still got a new one"
  called 'git push' && fail "$library: an open same-repository pull request still got a push"
  called 'gh pr close 10 --comment Superseded by #13 --delete-branch' || fail "$library: close did not name the open pull request #13"

  # 1.0.10 compares numerically: 1.0.9, 1.0.3, 1.0.2 and 1.0.0 are lower; the equal 1.0.10 is not closed.
  run "$library" 1.0.10
  [ "$STATUS" = 0 ] || fail "$library 1.0.10 exited $STATUS: $(cat "$T/out")"
  [ "$CLOSED" = "10 11 13 18" ] || fail "$library 1.0.10 closed '$CLOSED', expected '10 11 13 18'"

  # 1.0.3 without its own pull request: the branch and the pull request are created, then the older ones closed.
  PRS_JSON="$(pr 10 $P-1.0.2),$(pr 11 $P-1.0.9),$(pr 14 feature/other),$(pr 15 $P-1.0.3-rc1),\
$(pr 16 x$P-1.0.1),$(pr 17 $P-1.0.1 true),$(pr 18 $P-1.0.0),$(pr 19 $O-1.0.0)"
  run "$library" 1.0.3
  [ "$STATUS" = 0 ] || fail "$library 1.0.3 without a pull request exited $STATUS: $(cat "$T/out")"
  called "git push origin $P-1.0.3" || fail "$library: branch was not pushed"
  called "gh pr create --base master --head $P-1.0.3" || fail "$library: pull request was not created"
  [ "$CLOSED" = "10 18" ] || fail "$library 1.0.3 (new) closed '$CLOSED', expected '10 18'"
  called 'Superseded by #99' || fail "$library: close did not name the new pull request #99"
  # What the pull request carries: branch, commit, bot identity, title, release notes; no label, no reviewer.
  called "git switch -c $P-1.0.3" || fail "$library: the branch was not created from the working tree"
  called "git commit -am Bump $library to 1.0.3" || fail "$library: the commit message is not 'Bump $library to 1.0.3'"
  called 'git config user.name timetug-bot\[bot\]' || fail "$library: the commit author name is not the bot"
  called 'git config user.email 342080999+timetug-bot\[bot\]@users.noreply.github.com' || fail "$library: the commit author email is not the bot"
  [ "$(cat "$T/created.title")" = "Bump $library to 1.0.3" ] || fail "$library: the title is '$(cat "$T/created.title")'"
  grep -q "release notes of binary-companion/$library" "$T/created.body" || fail "$library: the body lacks the release notes of the library"
  grep -q 'Opened by timetug-bot' "$T/created.body" || fail "$library: the body lacks the bot line"
  called "gh release view 1.0.3 --repo binary-companion/$library" || fail "$library: the notes were not read from the library"
  grep -E '^gh pr create' "$T/calls" | grep -Eq -- '--(label|reviewer|assignee|draft)' && fail "$library: the pull request was labelled, assigned or drafted"

  # (d) A fork's pull request with the new branch name must not count as the pull request for the branch.
  run "$library" 1.0.5 "$(pr 30 $P-1.0.5 true)"
  [ "$STATUS" = 0 ] || fail "$library: cross-repository head exited $STATUS: $(cat "$T/out")"
  called "git push origin $P-1.0.5" || fail "$library: a cross-repository pull request suppressed the push"
  called "gh pr create --base master --head $P-1.0.5" || fail "$library: a cross-repository pull request suppressed the create"
  [ "$CLOSED" = "10 18" ] || fail "$library 1.0.5 closed '$CLOSED', expected '10 18' (1.0.9 is higher)"

  # (d) A fork's pull request with a lower matching head is never closed, whatever its number.
  PRS_JSON="$saved"
  run "$library" 1.0.10 "$(pr 31 $P-1.0.4 true)"
  case " $CLOSED " in *" 31 "*|*" 17 "*) fail "$library: a cross-repository pull request was closed: '$CLOSED'";; esac

  # The branch exists on the remote but has no open pull request: open it from that branch, push nothing.
  PRS_JSON="$(pr 10 $P-1.0.2)"
  BRANCH_EXISTS=1 run "$library" 1.0.5
  [ "$STATUS" = 0 ] || fail "$library: existing branch exited $STATUS: $(cat "$T/out")"
  called 'git push' && fail "$library: an existing branch was pushed again"
  called "gh pr create --base master --head $P-1.0.5" || fail "$library: existing branch got no pull request"
  unset BRANCH_EXISTS

  # One failing close does not stop the others, and the step still fails.
  PRS_JSON="$saved"
  FAIL_CLOSE=10 run "$library" 1.0.10
  [ "$STATUS" != 0 ] || fail "$library: a failed close did not fail the step"
  [ "$CLOSED" = "10 11 13 18" ] || fail "$library: after a failed close the attempts were '$CLOSED', expected '10 11 13 18'"
  grep -q '::warning::could not close #10' "$T/out" || fail "$library: a failed close left no warning"
  unset FAIL_CLOSE

  # No change in the working tree: the step does nothing.
  DIFF_CLEAN=1 run "$library" 1.0.10
  [ "$STATUS" = 0 ] && [ -z "$CLOSED" ] || fail "$library: a clean tree opened or closed something"
  called 'gh pr' && fail "$library: a clean tree called gh pr"
  called 'git push' && fail "$library: a clean tree pushed"
  unset DIFF_CLEAN
}
unset RECORDED
matrix calendar-connectors timetug-shared
matrix timetug-shared calendar-connectors

# (c) timetug-shared 1.0.0 carried the connector pin to 1.0.4 (RECORDED): the open connector bump pull requests
# for 1.0.4 and below are superseded, and so are older timetug-shared ones; nothing else is closed.
PRS_JSON="$(pr 40 bump/calendar-connectors-1.0.3),$(pr 41 bump/timetug-shared-0.9.0),$(pr 42 bump/calendar-connectors-1.0.4),\
$(pr 43 bump/calendar-connectors-1.0.5),$(pr 44 bump/timetug-shared-1.0.1),$(pr 45 bump/timetug-shared-1.0.0),\
$(pr 46 bump/calendar-connectors-1.0.3 true),$(pr 47 feature/other),$(pr 48 bump/calendar-connectors-1.0.10),\
$(pr 49 bump/calendar-connectors-1.0.4-rc1),$(pr 50 bump/calendar-connectors-0.9.9),$(pr 51 xbump/calendar-connectors-1.0.1)"
RECORDED=1.0.4 run timetug-shared 1.0.0
[ "$STATUS" = 0 ] || fail "(c) exited $STATUS: $(cat "$T/out")"
[ "$CLOSED" = "40 41 42 50" ] || fail "(c) closed '$CLOSED', expected '40 41 42 50' (the connector bumps up to 1.0.4 and the older timetug-shared one)"
called 'gh pr close 40 --comment Superseded by #45 --delete-branch' || fail '(c) the close did not name the open pull request #45'
called 'gh pr create' && fail '(c) an open same-repository pull request still got a new one'
# The same, with the new pull request created here.
PRS_JSON="$(pr 40 bump/calendar-connectors-1.0.3),$(pr 41 bump/timetug-shared-0.9.0),$(pr 43 bump/calendar-connectors-1.0.5)"
RECORDED=1.0.4 run timetug-shared 1.0.0
[ "$STATUS" = 0 ] && [ "$CLOSED" = "40 41" ] || fail "(c) with a new pull request closed '$CLOSED' (status $STATUS), expected '40 41'"
called 'Superseded by #99' || fail '(c) the close did not name the new pull request #99'
grep -q 'calendar-connectors 1.0.4' "$T/created.body" || fail '(c) the body does not say which connector version the tag resolves'
# A recorded version compares numerically: 1.0.10 recorded closes the 1.0.9 and 1.0.10 connector bumps.
PRS_JSON="$(pr 60 bump/calendar-connectors-1.0.9),$(pr 61 bump/calendar-connectors-1.0.10),$(pr 62 bump/calendar-connectors-1.0.11)"
RECORDED=1.0.10 run timetug-shared 1.0.0
[ "$STATUS" = 0 ] && [ "$CLOSED" = "60 61" ] || fail "(c) numeric recorded comparison closed '$CLOSED', expected '60 61'"
# Without a recorded pin (cannot happen after a successful Move step) no connector pull request is closed.
RECORDED= run timetug-shared 1.0.0
[ "$CLOSED" = "" ] || fail "(c) an empty RECORDED closed '$CLOSED'"
# A connector release never closes a timetug-shared pull request, and a RECORDED left in the environment does not
# make it close connector ones beyond its own library's rule.
PRS_JSON="$(pr 70 bump/timetug-shared-0.9.0),$(pr 71 bump/calendar-connectors-1.0.3),$(pr 72 bump/calendar-connectors-1.0.5)"
RECORDED=1.0.4 run calendar-connectors 1.0.4
[ "$STATUS" = 0 ] && [ "$CLOSED" = "71" ] || fail "a connector release closed '$CLOSED', expected only '71'"
echo PASS
