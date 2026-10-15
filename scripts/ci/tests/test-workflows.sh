#!/usr/bin/env bash
# Loads every .github/workflows/*.yml and runs `bash -n` on each `run:` block.
# Includes a negative check proving that a broken workflow is rejected.
set -euo pipefail
cd "$(dirname "$0")/../../.."
if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "FAIL: PyYAML is required (pip install -r scripts/ci/requirements-test.txt)" >&2
  exit 2
fi
CHECK="$(mktemp)"; TMP="$(mktemp -d)"
trap 'rm -f "$CHECK"; rm -rf "$TMP"' EXIT
cat > "$CHECK" <<'PY'
import re, subprocess, sys, yaml
bad = 0
for path in sys.argv[1:]:
    try:
        doc = yaml.safe_load(open(path))
    except Exception as e:
        print(f"FAIL {path}: yaml error: {e}"); bad += 1; continue
    jobs = doc.get("jobs") if isinstance(doc, dict) else None
    if not jobs:
        print(f"FAIL {path}: no jobs"); bad += 1; continue
    for jname, job in jobs.items():
        for i, step in enumerate(job.get("steps", [])):
            run = step.get("run")
            if run is None:
                continue
            script = re.sub(r"\$\{\{.*?\}\}", "EXPR", run, flags=re.S)
            r = subprocess.run(["bash", "-n"], input=script, text=True, capture_output=True)
            if r.returncode:
                print(f"FAIL {path} job {jname} step {step.get('name', i)}: {r.stderr.strip()}"); bad += 1
sys.exit(1 if bad else 0)
PY
python3 "$CHECK" .github/workflows/*.yml || { echo "FAIL: workflows invalid" >&2; exit 1; }
# Negative checks: a broken run block and broken yaml must both be rejected.
printf 'jobs:\n  j:\n    steps:\n      - run: |\n          if then fi (\n' > "$TMP/bad-run.yml"
printf 'jobs: [unclosed\n' > "$TMP/bad-yaml.yml"
python3 "$CHECK" "$TMP/bad-run.yml" >/dev/null && { echo "FAIL: broken run block accepted" >&2; exit 1; }
python3 "$CHECK" "$TMP/bad-yaml.yml" >/dev/null && { echo "FAIL: broken yaml accepted" >&2; exit 1; }
# The OAuth secrets belong to the privileged build workflows only, never to PR CI.
for w in beta release; do
  for s in GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET MICROSOFT_OAUTH_CLIENT_ID; do
    grep -q "secrets\.$s" ".github/workflows/$w.yml" || { echo "FAIL: $w.yml does not reference secrets.$s" >&2; exit 1; }
  done
done
if grep -q "GOOGLE_OAUTH\|MICROSOFT_OAUTH" .github/workflows/ci.yml; then echo "FAIL: ci.yml must not reference the OAuth secrets" >&2; exit 1; fi
python3 scripts/ci/tests/check-workflow-contracts.py
# The contracts of the bump workflow must reject each way of widening it: a tree whose copy is mutated fails.
mkdir -p "$TMP/contracts/.github" "$TMP/contracts/Packages"
cp -R .github/workflows "$TMP/contracts/.github/workflows"
for package in Packages/*/; do mkdir -p "$TMP/contracts/$package"; done
BUMP="$TMP/contracts/.github/workflows/bump-dependencies.yml"
cp "$BUMP" "$TMP/bump.orig"
contracts_reject() { # contracts_reject <what the mutated workflow does> <text to replace> <replacement>
  cp "$TMP/bump.orig" "$BUMP"
  python3 -c '
import sys
path, old, new = sys.argv[1:]
text = open(path).read()
assert old in text, "mutation target not found: " + old
open(path, "w").write(text.replace(old, new, 1))
' "$BUMP" "$2" "$3"
  if WORKFLOW_CONTRACTS_ROOT="$TMP/contracts" python3 scripts/ci/tests/check-workflow-contracts.py >/dev/null 2>&1; then
    echo "FAIL: contracts accepted a bump workflow that $1" >&2; exit 1
  fi
}
WORKFLOW_CONTRACTS_ROOT="$TMP/contracts" python3 scripts/ci/tests/check-workflow-contracts.py >/dev/null ||
  { echo "FAIL: contracts rejected an unmodified copy of the workflows" >&2; exit 1; }
contracts_reject 'reacts to another event type' 'types: [library-released]' 'types: [library-released, other]'
contracts_reject 'is scoped to another repository' 'repositories: timetug
' 'repositories: timetug,timetug-shared
'
contracts_reject 'asks for another token permission' 'permission-pull-requests: write' 'permission-pull-requests: write
          permission-workflows: write'
contracts_reject 'accepts a third library from the payload' '"timetug-shared"]' '"timetug-shared","other"]'
contracts_reject 'accepts any payload library' "|| contains(fromJSON('[\"calendar-connectors\",\"timetug-shared\"]'), github.event.client_payload.library)" "|| true"
contracts_reject 'offers a third library by hand' '          - timetug-shared' '          - timetug-shared
          - other'
contracts_reject 'merges' 'git push origin "$branch"' 'git push origin "$branch"; gh pr merge "$branch" --squash'
contracts_reject 'shares one queue between the libraries' 'group: bump-${{ github.event.client_payload.library || inputs.library }}' 'group: bump-all'
contracts_reject 'does not check the library itself' 'calendar-connectors|timetug-shared) ;;' '*) ;;'
echo "PASS"
