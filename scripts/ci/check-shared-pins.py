#!/usr/bin/env python3
"""Shared libraries are consumed by released version only (phase 1 spec).

Every `.package(...)` in every Package*.swift at any depth under Packages/ (SwiftPM prefers
Package@swift-X.Y.swift over Package.swift, so all of them are scanned; `.build` and `build` directories are
skipped) must be either `.package(url: "<library url>", from: "X.Y.Z")` or a `.package(path: "...")` that,
resolved from the manifest's own directory, is an existing sibling directory of Packages/ (spelled exactly,
not a symlink, and not the library itself); anything else fails. Swift comments are not stripped, so a
`.package(...)` inside a comment is checked like code and fails closed unless it is an allowed form.
Apps/macOS/project.yml must pin the library with exactly the keys `url` and `exactVersion` (XcodeGen lets
`path` win over a url, so any other key could hide a local override), and the pin must satisfy every
manifest's range (same major, not below). The file must not have a top-level `include:` (XcodeGen would read
packages from a file this check does not). Every other `packages:` entry must be an external dependency that
is not the library, or `path: ../../Packages/<Name>` for an existing sibling; every `localPackages:` entry must
be `../../Packages/<Name>` likewise (a second entry that reaches the library would defeat the pin: XcodeGen
emits a local package reference and SwiftPM resolves the checkout over exactVersion).
Usage: check-shared-pins.py [repo-root]
"""
import os
import re
import sys
from pathlib import Path

import yaml

LIBRARIES = {'calendar-connectors': 'CalendarConnectors'}  # repository slug -> project.yml package key
URL_PREFIX = 'https://github.com/binary-companion/'
ENTRY_KEYS = {'url', 'exactVersion'}
LIBRARY_NAMES = {name.lower() for slug, key in LIBRARIES.items() for name in (slug, key)}
PACKAGE_CALL = re.compile(r'\.package\s*\(([^)]*)\)')
SIBLING_PATH = re.compile(r'path:\s*"((?:\.\./)+)([^"/]+)"')
SKIPPED_DIRECTORIES = {'.build', 'build'}
PROJECT_SIBLING_PATH = re.compile(r'\.\./\.\./Packages/([^/]+)')
SEMVER = re.compile(r'^(\d+)\.(\d+)\.(\d+)$')

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
errors = []

def version(text):
    m = SEMVER.match(str(text))
    return tuple(int(x) for x in m.groups()) if m else None

pins = {}
project = yaml.safe_load((root / 'Apps/macOS/project.yml').read_text()) or {}
if 'include' in project:
    errors.append('Apps/macOS/project.yml: a top-level include: is not allowed; it could add packages from a '
                  'file this check does not read')
packages = project.get('packages')
if packages is not None and not isinstance(packages, dict):
    errors.append('Apps/macOS/project.yml: packages must be a mapping')
    packages = None
for slug, key in LIBRARIES.items():
    entry = (packages or {}).get(key)
    if entry is None:
        errors.append(f'Apps/macOS/project.yml: package {key} is missing')
        continue
    if not isinstance(entry, dict):
        errors.append(f'Apps/macOS/project.yml: {key} must be a mapping with url and exactVersion')
        continue
    extra = sorted(str(k) for k in set(entry) - ENTRY_KEYS)
    if extra:
        errors.append(f'Apps/macOS/project.yml: {key} has unexpected key(s) {", ".join(extra)}; '
                      'only url and exactVersion are allowed')
    if entry.get('url') != URL_PREFIX + slug:
        errors.append(f'Apps/macOS/project.yml: {key} must use url {URL_PREFIX}{slug} (no path, branch or revision)')
    pin = version(entry.get('exactVersion', ''))
    if pin is None:
        errors.append(f'Apps/macOS/project.yml: {key} needs exactVersion X.Y.Z')
    pins[slug] = pin

# Sibling names come from the directory listing, so the comparison is case-sensitive on every filesystem. A
# symlink may point anywhere, so it never counts as an existing sibling.
packages_dir = root / 'Packages'
siblings = ({d.name for d in packages_dir.iterdir() if d.is_dir() and not d.is_symlink()}
            if packages_dir.is_dir() else set())

def mentions_library(*values):
    text = ' '.join(str(v) for v in values).lower()
    return any(name in text for name in LIBRARY_NAMES)

def reaches_library(*values):
    """True when a value's last path segment is the library (url, github shorthand or path), as opposed to a
    third-party name that merely contains the library name."""
    for value in values:
        segment = re.split(r'[/:]', str(value).rstrip('/'))[-1].lower()
        if segment.removesuffix('.git') in LIBRARY_NAMES:
            return True
    return False

def library_reference(*values):
    return 'points at the shared library' if reaches_library(*values) else 'names the shared library'

def check_project_path(where, path):
    """`where` names the entry for messages; `path` must be ../../Packages/<Name> for an existing sibling."""
    sibling = PROJECT_SIBLING_PATH.fullmatch(str(path))
    if not sibling or sibling.group(1) not in siblings or sibling.group(1).lower() in LIBRARY_NAMES:
        errors.append(f'Apps/macOS/project.yml: {where} path {path} must be ../../Packages/<Name> for an '
                      'existing sibling directory of Packages/ (spelled exactly, and not the library)')

# Every project.yml entry other than the pinned key must stay away from the library: a second entry that
# reaches it (path, url or github shorthand) defeats the pin.
for name, entry in (packages or {}).items():
    if name in LIBRARIES.values():
        continue
    if not isinstance(entry, dict):
        errors.append(f'Apps/macOS/project.yml: package {name} must be a mapping with url or path')
        continue
    if mentions_library(*entry.values()):
        pinned = ', '.join(sorted(LIBRARIES.values()))
        errors.append(f'Apps/macOS/project.yml: package {name} {library_reference(*entry.values())}; only the '
                      f'pinned {pinned} entry (url and exactVersion) may')
    elif 'path' in entry:
        check_project_path(f'package {name}', entry['path'])

local_packages = project.get('localPackages')
if local_packages is not None and not isinstance(local_packages, list):
    errors.append('Apps/macOS/project.yml: localPackages must be a list of ../../Packages/<Name> paths')
for item in (local_packages if isinstance(local_packages, list) else ()):
    values = list(item.values()) if isinstance(item, dict) else [item]
    path = item.get('path') if isinstance(item, dict) else item
    if mentions_library(*values):
        errors.append(f'Apps/macOS/project.yml: localPackages entry {item} {library_reference(*values)}; '
                      'only the pinned package entry (url and exactVersion) may')
    elif path is None:
        errors.append(f'Apps/macOS/project.yml: localPackages entry {item} needs a path')
    else:
        check_project_path('localPackages entry', path)

def manifests_under(directory):
    """Every Package*.swift at any depth, without following symlinks and without .build/build directories."""
    found = []
    for current, dirs, files in os.walk(directory):
        dirs[:] = sorted(d for d in dirs if d not in SKIPPED_DIRECTORIES)
        found.extend(Path(current, f) for f in files if f.startswith('Package') and f.endswith('.swift'))
    return sorted(found)

def sibling_name(manifest, body):
    """The sibling directory of Packages/ that `path:` names, resolved from the manifest's directory."""
    match = SIBLING_PATH.fullmatch(body)
    if not match or match.group(2) in ('.', '..'):
        return None
    target = Path(os.path.normpath(manifest.parent / (match.group(1) + match.group(2))))
    return target.name if target.parent == packages_dir else None

for manifest in manifests_under(packages_dir) if packages_dir.is_dir() else ():
    rel = manifest.relative_to(root)
    for inner in PACKAGE_CALL.findall(manifest.read_text()):
        body = inner.strip()
        dependency = '.package(%s)' % ' '.join(body.split())
        released = None
        for slug in LIBRARIES:
            released = re.fullmatch(r'url:\s*"%s"\s*,\s*from:\s*"([^"]+)"' % re.escape(URL_PREFIX + slug), body)
            if released:
                break
        if released:
            floor = version(released.group(1))
            if floor is None:
                errors.append(f'{rel}: {slug} needs from: "X.Y.Z", got {dependency}')
                continue
            pin = pins.get(slug)
            if pin is None:
                continue
            if pin[0] != floor[0]:
                errors.append(f'{rel}: pin {".".join(map(str, pin))} is in another major than from: {released.group(1)}')
            elif pin < floor:
                errors.append(f'{rel}: pin {".".join(map(str, pin))} is below from: {released.group(1)}')
            continue
        sibling = sibling_name(manifest, body)
        if sibling in siblings and sibling.lower() not in LIBRARY_NAMES:
            continue
        errors.append(f'{rel}: dependency {dependency} is not allowed; use '
                      f'.package(url: "{URL_PREFIX}<library>", from: "X.Y.Z") for a shared library or '
                      '.package(path: "../<Name>") for a sibling directory of Packages/')

if errors:
    for error in errors:
        print(f'FAIL: {error}', file=sys.stderr)
    sys.exit(1)
print('PASS: shared pins')
