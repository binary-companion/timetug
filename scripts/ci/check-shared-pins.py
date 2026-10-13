#!/usr/bin/env python3
"""Shared libraries are consumed by released version only (phase 1 spec).

Every Packages/*/Package.swift that names calendar-connectors must say
`.package(url: "<library url>", from: "X.Y.Z")`, Apps/macOS/project.yml must pin the same package with
`url` and `exactVersion`, and the pin must satisfy every manifest's range (same major, not below).
Usage: check-shared-pins.py [repo-root]
"""
import re
import sys
from pathlib import Path

import yaml

LIBRARIES = {'calendar-connectors': 'CalendarConnectors'}  # repository slug -> project.yml package key
URL_PREFIX = 'https://github.com/binary-companion/'
SEMVER = re.compile(r'^(\d+)\.(\d+)\.(\d+)$')

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
errors = []

def version(text):
    m = SEMVER.match(str(text))
    return tuple(int(x) for x in m.groups()) if m else None

pins = {}
project = yaml.safe_load((root / 'Apps/macOS/project.yml').read_text()) or {}
for slug, key in LIBRARIES.items():
    entry = (project.get('packages') or {}).get(key)
    if entry is None:
        errors.append(f'Apps/macOS/project.yml: package {key} is missing')
        continue
    if entry.get('url') != URL_PREFIX + slug:
        errors.append(f'Apps/macOS/project.yml: {key} must use url {URL_PREFIX}{slug} (no path, branch or revision)')
    pin = version(entry.get('exactVersion', ''))
    if pin is None:
        errors.append(f'Apps/macOS/project.yml: {key} needs exactVersion X.Y.Z')
    pins[slug] = pin

for manifest in sorted((root / 'Packages').glob('*/Package.swift')):
    rel = manifest.relative_to(root)
    text = ' '.join(manifest.read_text().split())
    for dependency in re.findall(r'\.package\([^)]*\)', text):
        for slug, key in LIBRARIES.items():
            if slug not in dependency and key not in dependency:
                continue
            m = re.fullmatch(r'\.package\(url: "%s", from: "([^"]+)"\)' % re.escape(URL_PREFIX + slug), dependency)
            floor = version(m.group(1)) if m else None
            if floor is None:
                errors.append(f'{rel}: {slug} must be .package(url: "{URL_PREFIX}{slug}", from: "X.Y.Z"), got {dependency}')
                continue
            pin = pins.get(slug)
            if pin is None:
                continue
            if pin[0] != floor[0]:
                errors.append(f'{rel}: pin {".".join(map(str, pin))} is in another major than from: {m.group(1)}')
            elif pin < floor:
                errors.append(f'{rel}: pin {".".join(map(str, pin))} is below from: {m.group(1)}')

if errors:
    for error in errors:
        print(f'FAIL: {error}', file=sys.stderr)
    sys.exit(1)
print('PASS: shared pins')
