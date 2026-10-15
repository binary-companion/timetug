"""Checks security and coverage invariants that shell syntax validation cannot see."""
from pathlib import Path
import re
import sys
import yaml

root = Path(__file__).resolve().parents[3]
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
    # The one exception (docs/superpowers/specs/2026-10-09-windows-program-design.md, section 8): ci.yml may read the
    # read-only Docker Hub pull token, which fork PRs never receive. Every other secret stays out of PR workflows.
    allowed_secrets = {'DOCKERHUB_USERNAME', 'DOCKERHUB_TOKEN'} if name == 'ci.yml' else set()
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

# Secrets are only readable through a protected environment (spec section 8). The Docker Hub pull token is the one
# amended exception, and only in ci.yml.
ALLOWED_OUTSIDE_ENVIRONMENT = {'ci.yml': {'DOCKERHUB_USERNAME', 'DOCKERHUB_TOKEN'}}
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

if errors:
    for error in errors:
        print(f'FAIL: {error}', file=sys.stderr)
    sys.exit(1)
print('PASS: workflow contracts')
