#!/usr/bin/env python3
"""Focused repository invariants; package tests remain the compiler authority."""
from pathlib import Path
import plistlib
import sys
import yaml

root = Path(__file__).resolve().parents[2]
errors = []

def require(condition, message):
    if not condition:
        errors.append(message)

def read(path):
    file = root / path
    require(file.is_file(), f'missing documented path: {path}')
    return file.read_text() if file.is_file() else ''

for path in ('docs/architecture.md', 'docs/development.md', 'docs/release.md',
             'docs/manual-tests/macos-checklist.md', 'site/README.md',
             'scripts/dev/verify.sh', 'Apps/macOS/project.yml'):
    read(path)

# The engine enables the providers through EngineConfig (TimeTugKit); the app passes the system calendar and the
# OAuth clients of the build.
config = read('Apps/macOS/Sources/AppConnectors.swift')
for field in ('googleClient: google', 'microsoftClient: microsoft', 'systemCalendar: true'):
    require(field in config, f'engine config field missing: {field}')
# The Microsoft scope and Google/Microsoft write-capability checks moved with the library
# (binary-companion/calendar-connectors, scripts/ci/check-repository-contracts.py).
eventkit = 'Packages/EventKitSource/Sources/EventKitSource'
source = read(f'{eventkit}/EventKitSource.swift')
require('canWrite: true' in source, 'EventKitSource write capability changed')
require('EventKitSource: SystemCalendarSource' in source, 'EventKitSource system calendar conformance absent')
require('public func create(draft: EventDraft' in read(f'{eventkit}/EventKitSource+Write.swift'),
        'EventKitSource write implementation absent')

# XcodeGen is the source of truth for generated plist properties. A target's properties are its template's plus its own.
project = yaml.safe_load(read('Apps/macOS/project.yml'))
for target, path in (('TimeTug', 'Apps/macOS/Sources/Info.plist'),
                     ('TimeTugWidgets', 'Apps/macOS/Widgets/Info.plist'),
                     ('TimeTug-AppStore', 'Apps/macOS/AppStore/Info.plist'),
                     ('TimeTugWidgets-AppStore', 'Apps/macOS/AppStore/Widgets-Info.plist')):
    definition = project['targets'][target]
    props = {}
    for template in definition.get('templates', []):
        props.update(project['targetTemplates'][template].get('info', {}).get('properties', {}))
    props.update(definition['info'].get('properties', {}))
    with (root / path).open('rb') as stream:
        plist = plistlib.load(stream)
    for key, value in props.items():
        require(plist.get(key) == value, f'{path} differs from project.yml: {key}')

if errors:
    for error in errors:
        print(f'FAIL: {error}', file=sys.stderr)
    sys.exit(1)
print('PASS: repository contracts')
