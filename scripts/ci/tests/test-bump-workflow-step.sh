#!/usr/bin/env bash
# Runs the "Move the pin" step of .github/workflows/bump-dependencies.yml against the real scripts/ci/bump-pin.sh
# (so the step must use the script's current command line), then its "Open the pull request" step against stub
# `git` and `gh`, and asserts which pull requests it opens and closes. BUMP_WORKFLOW points at another copy of
# the workflow (used to prove that mutated copies fail).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WORKFLOW="${BUMP_WORKFLOW:-$ROOT/.github/workflows/bump-dependencies.yml}"
for tool in python3 jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FAIL: $tool is required" >&2; exit 2; }
done
python3 -c 'import yaml' 2>/dev/null || { echo "FAIL: PyYAML is required (pip install -r scripts/ci/requirements-test.txt)" >&2; exit 2; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
python3 - "$WORKFLOW" "$T/step.sh" "$T/move.sh" <<'PY'
import sys, yaml
document = yaml.safe_load(open(sys.argv[1]))
for name, target in (('Open the pull request', sys.argv[2]), ('Move the pin', sys.argv[3])):
    steps = [step for job in document['jobs'].values() for step in job['steps'] if step.get('name') == name]
    assert len(steps) == 1, f'the workflow must have exactly one "{name}" step'
    open(target, 'w').write(steps[0]['run'])
PY
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
cat > "$T/bin/gh" <<'SCRIPT'
#!/usr/bin/env bash
echo "gh $*" >> "$CALLS"
case "$1 $2" in
  "pr list")
    head=""; expr="."
    args=("$@")
    for ((i = 0; i < ${#args[@]}; i++)); do
      [ "${args[i]}" = --head ] && head="${args[i+1]}"
      [ "${args[i]}" = --jq ] && expr="${args[i+1]}"
    done
    jq -c --arg head "$head" 'map(select($head == "" or .headRefName == $head))' "$PRS" | jq -r "$expr";;
  "pr create") echo "https://github.com/binary-companion/timetug/pull/99";;
  "pr close")
    case " ${FAIL_CLOSE:-} " in *" $3 "*) echo "could not close $3" >&2; exit 1;; esac;;
  "release view") echo "release notes";;
esac
exit 0
SCRIPT
chmod +x "$T/bin/git" "$T/bin/gh"
fail() { echo "FAIL: $*" >&2; exit 1; }
pr() { printf '{"number":%s,"headRefName":"%s","isCrossRepository":%s}' "$1" "$2" "${3:-false}"; }

# The "Move the pin" step runs in a checkout of the repository: here a tree holding the real bump-pin.sh and
# project.yml. It must move the CalendarConnectors pin, accept exactly what the script accepts, and leave the
# other library's pin alone. pin_in <file> <project.yml key> prints the exactVersion of that entry.
pin_in() { perl -0ne 'print $1 if m{^[ \t]+'"$2"':[ \t]*\n[ \t]+url:[^\n]*\n[ \t]+exactVersion:[ \t]*([0-9.]+)}m' "$1"; }
mkdir -p "$T/move/scripts/ci" "$T/move/Apps/macOS"
cp "$ROOT/scripts/ci/bump-pin.sh" "$T/move/scripts/ci/"
cp "$ROOT/Apps/macOS/project.yml" "$T/move/Apps/macOS/"
before_shared="$(pin_in "$T/move/Apps/macOS/project.yml" TimeTugShared)"
[ -n "$before_shared" ] || fail 'the real project.yml has no TimeTugShared pin'
MOVE_VERSION=1.998.0
(cd "$T/move" && VERSION="$MOVE_VERSION" PATH="$T/bin:$PATH" bash "$T/move.sh" > "$T/move.out" 2>&1) ||
  fail "the Move the pin step failed: $(cat "$T/move.out")"
[ "$(pin_in "$T/move/Apps/macOS/project.yml" CalendarConnectors)" = "$MOVE_VERSION" ] ||
  fail "the Move the pin step did not move the calendar-connectors pin to $MOVE_VERSION"
[ "$(pin_in "$T/move/Apps/macOS/project.yml" TimeTugShared)" = "$before_shared" ] ||
  fail 'the Move the pin step changed the timetug-shared pin'

PREFIX=bump/calendar-connectors
BASE_PRS="$(pr 10 $PREFIX-1.0.2),$(pr 11 $PREFIX-1.0.9),$(pr 12 $PREFIX-1.0.10),$(pr 13 $PREFIX-1.0.3),\
$(pr 14 feature/other),$(pr 15 $PREFIX-1.0.3-rc1),$(pr 16 xbump/calendar-connectors-1.0.1),\
$(pr 17 $PREFIX-1.0.1 true),$(pr 18 $PREFIX-1.0.0)"
# run <version> <extra pull requests as json objects, or empty>; sets STATUS, CLOSED (sorted numbers) and CALLS.
run() {
  local version="$1" extra="${2:-}"
  printf '[%s%s]\n' "$BASE_PRS" "${extra:+,$extra}" > "$T/prs.json"
  : > "$T/calls"
  STATUS=0
  CALLS="$T/calls" PRS="$T/prs.json" RUNNER_TEMP="$T" VERSION="$version" PATH="$T/bin:$PATH" \
    bash "$T/step.sh" > "$T/out" 2>&1 || STATUS=$?
  CLOSED="$({ grep '^gh pr close ' "$T/calls" || true; } | awk '{print $4}' | sort -n | tr '\n' ' ' | sed 's/ $//')"
}
called() { grep -q -- "$1" "$T/calls"; }

# 1.0.3 with the same-repository 1.0.3 pull request open: nothing is created; 1.0.2 and 1.0.0 are superseded;
# 1.0.9, 1.0.10, the equal 1.0.3, the rc, the unrelated, the prefixed-name and the cross-repository one are not.
run 1.0.3
[ "$STATUS" = 0 ] || fail "1.0.3 with an open pull request exited $STATUS: $(cat "$T/out")"
[ "$CLOSED" = "10 18" ] || fail "1.0.3 closed '$CLOSED', expected '10 18'"
called 'gh pr create' && fail 'an open same-repository pull request still got a new one'
called 'git push' && fail 'an open same-repository pull request still got a push'
called 'gh pr close 10 --comment Superseded by #13 --delete-branch' || fail 'close did not name the open pull request #13'

# 1.0.10 compares numerically: 1.0.9, 1.0.3, 1.0.2 and 1.0.0 are lower; the equal 1.0.10 is not closed.
run 1.0.10
[ "$STATUS" = 0 ] || fail "1.0.10 exited $STATUS: $(cat "$T/out")"
[ "$CLOSED" = "10 11 13 18" ] || fail "1.0.10 closed '$CLOSED', expected '10 11 13 18'"

# 1.0.3 without its own pull request: the branch and the pull request are created, then the older ones closed.
BASE_SAVE="$BASE_PRS"
BASE_PRS="$(pr 10 $PREFIX-1.0.2),$(pr 11 $PREFIX-1.0.9),$(pr 14 feature/other),$(pr 15 $PREFIX-1.0.3-rc1),\
$(pr 16 xbump/calendar-connectors-1.0.1),$(pr 17 $PREFIX-1.0.1 true),$(pr 18 $PREFIX-1.0.0)"
run 1.0.3
[ "$STATUS" = 0 ] || fail "1.0.3 without a pull request exited $STATUS: $(cat "$T/out")"
called 'git push origin bump/calendar-connectors-1.0.3' || fail 'branch was not pushed'
called 'gh pr create --base master --head bump/calendar-connectors-1.0.3' || fail 'pull request was not created'
[ "$CLOSED" = "10 18" ] || fail "1.0.3 (new) closed '$CLOSED', expected '10 18'"
called 'Superseded by #99' || fail 'close did not name the new pull request #99'

# A fork's pull request with the new branch name must not count as the pull request for the branch.
run 1.0.5 "$(pr 30 $PREFIX-1.0.5 true)"
[ "$STATUS" = 0 ] || fail "cross-repository head exited $STATUS: $(cat "$T/out")"
called 'git push origin bump/calendar-connectors-1.0.5' || fail 'a cross-repository pull request suppressed the push'
called 'gh pr create --base master --head bump/calendar-connectors-1.0.5' || fail 'a cross-repository pull request suppressed the create'
[ "$CLOSED" = "10 18" ] || fail "1.0.5 closed '$CLOSED', expected '10 18' (1.0.9 is higher)"

# The branch exists on the remote but has no open pull request: open it from that branch, push nothing.
BRANCH_EXISTS=1 run 1.0.5
[ "$STATUS" = 0 ] || fail "existing branch exited $STATUS: $(cat "$T/out")"
called 'git push' && fail 'an existing branch was pushed again'
called 'gh pr create --base master --head bump/calendar-connectors-1.0.5' || fail 'existing branch got no pull request'
unset BRANCH_EXISTS

# One failing close does not stop the others, and the step still fails.
BASE_PRS="$BASE_SAVE"
FAIL_CLOSE=10 run 1.0.10
[ "$STATUS" != 0 ] || fail 'a failed close did not fail the step'
[ "$CLOSED" = "10 11 13 18" ] || fail "after a failed close the attempts were '$CLOSED', expected '10 11 13 18'"
grep -q '::warning::could not close #10' "$T/out" || fail 'a failed close left no warning'
unset FAIL_CLOSE

# No change in the working tree: the step does nothing.
DIFF_CLEAN=1 run 1.0.10
[ "$STATUS" = 0 ] && [ -z "$CLOSED" ] || fail 'a clean tree opened or closed something'
called 'gh pr' && fail 'a clean tree called gh pr'
echo PASS
