"""Checks security and coverage invariants that shell syntax validation cannot see."""
from pathlib import Path
import json
import os
import re
import sys
import yaml

# WORKFLOW_CONTRACTS_ROOT points at another tree (test-workflows.sh uses it to prove that mutated copies fail).
root = Path(os.environ.get('WORKFLOW_CONTRACTS_ROOT') or Path(__file__).resolve().parents[3])
workflows = {}
errors = []
for path in sorted((root / '.github/workflows').glob('*.yml')):
    document = yaml.safe_load(path.read_text())
    workflows[path.name] = document
    for name, job in document['jobs'].items():
        for step in job.get('steps', []):
            action = step.get('uses')
            if action and not re.fullmatch(r'[^@]+@[0-9a-f]{40}', action):
                errors.append(f'{path.name}/{name}: action is not pinned: {action}')

pr = workflows['firebase-hosting-pull-request.yml']
for name in ('ci.yml', 'firebase-hosting-pull-request.yml'):
    pr_text = (root / '.github/workflows' / name).read_text()
    # No secret reaches a PR-triggered workflow. (The Docker Hub pull token was the one exception while ci.yml ran
    # the Linux job; that job moved to timetug-shared, so the exception is gone.)
    allowed_secrets = set()
    used_secrets = set(re.findall(r'secrets\.([A-Za-z0-9_]+)', pr_text))
    if 'pull_request_target' in pr_text or used_secrets - allowed_secrets or 'firebaseServiceAccount' in pr_text:
        errors.append(f'{name}: PR-triggered workflow must not use pull_request_target or secrets')
if pr.get('permissions') != {'contents': 'read'}:
    errors.append('PR website workflow must have read-only contents permission')
if not any('verify.sh release-tools' in step.get('run', '') for job in pr['jobs'].values() for step in job['steps']):
    errors.append('PR website workflow does not validate the website')
pr_runs = '\n'.join(step.get('run', '') for job in pr['jobs'].values() for step in job['steps'])
if 'requirements-test.txt' not in pr_runs:
    errors.append('PR website workflow does not install pinned test prerequisites')
if 'build/verify-venv/bin:$PATH' not in pr_runs:
    errors.append('PR website workflow does not use pinned test prerequisites')

ci = workflows['ci.yml']
# Core's Linux portability job moved to binary-companion/timetug-shared with the package; a required check named
# core-linux would never report here again, so the job must not return without its package.
if 'core-linux' in ci['jobs']:
    errors.append('CI must not have a core-linux job: TimeTugCore is tested on Linux in timetug-shared')
# A workflow must not name a package directory that does not exist (the moved packages are gone from Packages/).
for name, document in workflows.items():
    for package in sorted(set(re.findall(r'\bPackages/([A-Za-z0-9_]+)', (root / '.github/workflows' / name).read_text()))):
        if not (root / 'Packages' / package).is_dir():
            errors.append(f'{name}: names Packages/{package}, which does not exist')
tooling = ci['jobs'].get('release-tooling')
if tooling is None:
    errors.append('CI missing release-tooling job')
else:
    runs = '\n'.join(step.get('run', '') for step in tooling['steps'])
    if 'scripts/dev/verify.sh release-tools' not in runs:
        errors.append('CI release-tooling job does not use verify.sh release-tools')
    if 'requirements-test.txt' not in runs:
        errors.append('CI release-tooling job does not install pinned prerequisites')
    if 'build/verify-venv/bin:$PATH' not in runs:
        errors.append('CI release-tooling job does not use pinned prerequisites')

# Secrets are only readable through a protected environment (spec section 8). There is no exception: the Docker Hub
# pull token moved with the Linux job to timetug-shared.
ALLOWED_OUTSIDE_ENVIRONMENT = {}
IGNORED_SECRETS = {'GITHUB_TOKEN'}
EXPECTED_ENVIRONMENTS = {
    'beta.yml': 'beta',
    'release.yml': 'release',
    'appstore.yml': 'appstore',
    'firebase-hosting-merge.yml': 'hosting',
    'bump-dependencies.yml': 'bump',
}
for file_name, document in workflows.items():
    allowed = ALLOWED_OUTSIDE_ENVIRONMENT.get(file_name, set())
    for job_name, job in document['jobs'].items():
        used = set(re.findall(r'secrets\.([A-Za-z0-9_]+)', yaml.safe_dump(job))) - IGNORED_SECRETS - allowed
        environment = job.get('environment')
        if used and not environment:
            errors.append(f'{file_name}/{job_name}: reads secrets.{sorted(used)[0]} but declares no environment')
        expected = EXPECTED_ENVIRONMENTS.get(file_name)
        if used and environment and expected and environment != expected:
            errors.append(f'{file_name}/{job_name}: environment is {environment!r}, expected {expected!r}')

# The website deploys with GitHub's OIDC identity through Workload Identity Federation, never a stored Firebase key.
# The federation provider accepts only tokens whose environment claim is `hosting` (phase 1.5 plan, Task 2).
hosting_path = root / '.github/workflows/firebase-hosting-merge.yml'
hosting_text = hosting_path.read_text()
hosting = workflows['firebase-hosting-merge.yml']
hosting_permissions = hosting.get('permissions') or {}
if hosting_permissions.get('id-token') != 'write' or hosting_permissions.get('contents') != 'read':
    errors.append('firebase-hosting-merge.yml must set permissions contents: read and id-token: write')
if 'secrets.' in hosting_text.replace('secrets.GITHUB_TOKEN', '') or 'firebaseServiceAccount' in hosting_text:
    errors.append('firebase-hosting-merge.yml must not read secrets or a Firebase service account key')
for job_name, job in hosting['jobs'].items():
    if job.get('environment') != 'hosting':
        errors.append(f'firebase-hosting-merge.yml/{job_name}: must declare environment: hosting')
    auth = [step for step in job['steps'] if str(step.get('uses', '')).startswith('google-github-actions/auth@')]
    if not auth or not {'workload_identity_provider', 'service_account'} <= set(auth[0].get('with', {})):
        errors.append(f'firebase-hosting-merge.yml/{job_name}: must sign in with google-github-actions/auth and Workload Identity Federation')

# The dependency bump workflow opens (and supersedes) pull requests but never merges one. Its app token carries
# only the two permissions it needs, whatever the installation itself holds.
bump = workflows['bump-dependencies.yml']
bump_triggers = bump.get('on', bump.get(True)) or {}
if (bump_triggers.get('repository_dispatch') or {}).get('types') != ['library-released']:
    errors.append('bump-dependencies.yml: repository_dispatch types must be exactly [library-released]')
for job_name, job in bump['jobs'].items():
    token_steps = [step for step in job['steps'] if str(step.get('uses', '')).startswith('actions/create-github-app-token@')]
    if len(token_steps) != 1:
        errors.append(f'bump-dependencies.yml/{job_name}: must create exactly one app token')
        continue
    token_inputs = {key for key in token_steps[0].get('with', {}) if key.startswith('permission-')}
    if token_inputs != {'permission-contents', 'permission-pull-requests'}:
        errors.append(f'bump-dependencies.yml/{job_name}: app token must request exactly permission-contents and '
                      f'permission-pull-requests, got {sorted(token_inputs)}')
    elif (token_steps[0]['with']['permission-contents'], token_steps[0]['with']['permission-pull-requests']) != ('write', 'write'):
        errors.append(f'bump-dependencies.yml/{job_name}: app token permissions must both be write')
bump_runs = '\n'.join(step.get('run', '') for job in bump['jobs'].values() for step in job['steps'])
if re.search(r'gh\s+pr\s+merge|--auto\b|\bmerge\b', bump_runs):
    errors.append('bump-dependencies.yml: must never merge a pull request (no gh pr merge, --auto or merge)')
# Two libraries release into this repository; the workflow accepts exactly these and nothing else, in the manual
# input, in the job `if` and (through the same expression) in the concurrency group and the step's environment.
BUMP_LIBRARIES = ['calendar-connectors', 'timetug-shared']
dispatch_inputs = (bump_triggers.get('workflow_dispatch') or {}).get('inputs') or {}
if set(dispatch_inputs) != {'library', 'version'}:
    errors.append(f'bump-dependencies.yml: workflow_dispatch inputs must be exactly library and version, got {sorted(dispatch_inputs)}')
elif (dispatch_inputs['library'].get('type') != 'choice' or dispatch_inputs['library'].get('options') != BUMP_LIBRARIES):
    errors.append(f'bump-dependencies.yml: the library input must be a choice of exactly {BUMP_LIBRARIES}')
PAYLOAD_LIBRARY = 'github.event.client_payload.library'
for job_name, job in bump['jobs'].items():
    condition = str(job.get('if', ''))
    allow_list = re.fullmatch(
        r"github\.event_name == 'workflow_dispatch' \|\| contains\(fromJSON\('(\[[^']*\])'\), "
        + re.escape(PAYLOAD_LIBRARY) + r"\)", condition)
    if allow_list is None or json.loads(allow_list.group(1)) != BUMP_LIBRARIES:
        errors.append(f'bump-dependencies.yml/{job_name}: the job `if` must be a manual dispatch or a payload library in '
                      f'exactly {BUMP_LIBRARIES}, got {condition!r}')
    expected_env = {'LIBRARY': '${{ %s || inputs.library }}' % PAYLOAD_LIBRARY,
                    'VERSION': '${{ github.event.client_payload.version || inputs.version }}'}
    if job.get('env') != expected_env:
        errors.append(f'bump-dependencies.yml/{job_name}: the job env must be exactly LIBRARY and VERSION from the payload or the input')
    for token_step in (step for step in job['steps'] if str(step.get('uses', '')).startswith('actions/create-github-app-token@')):
        if token_step.get('with', {}).get('repositories') != 'timetug':
            errors.append(f'bump-dependencies.yml/{job_name}: the app token must be scoped to repositories: timetug')
    checks_input = [step for step in job['steps'] if step.get('name') == 'Move the pin']
    move_run = checks_input[0].get('run', '') if len(checks_input) == 1 else ''
    if 'calendar-connectors|timetug-shared)' not in move_run or '${{' in move_run:
        errors.append(f'bump-dependencies.yml/{job_name}: the Move the pin step must check LIBRARY against the two-name '
                      'allow-list itself and receive its values through env')
if (bump.get('concurrency') or {}).get('group') != 'bump-${{ %s || inputs.library }}' % PAYLOAD_LIBRARY:
    errors.append('bump-dependencies.yml: concurrency group must be bump-<library> (one queue per library)')

if errors:
    for error in errors:
        print(f'FAIL: {error}', file=sys.stderr)
    sys.exit(1)
print('PASS: workflow contracts')
