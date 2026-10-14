import subprocess, sys, tempfile, textwrap, unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'check-shared-pins.py'
URL = 'https://github.com/binary-companion/calendar-connectors'

PROJECT = '''packages:
  CalendarConnectors:
    url: %s
    exactVersion: %s
'''
MANIFEST = '''let package = Package(
    name: "%s",
    dependencies: [%s],
    targets: []
)
'''

def make(root: Path, project=PROJECT % (URL, '1.2.0'), manifests=None, siblings=(), extra_manifests=None,
         symlinks=()):
    (root / 'Apps/macOS').mkdir(parents=True)
    (root / 'Apps/macOS/project.yml').write_text(project)
    for name in siblings:
        (root / 'Packages' / name).mkdir(parents=True)
    # A symlink under Packages/ to a real directory elsewhere: it must not count as a sibling.
    for name in symlinks:
        target = root / 'elsewhere' / name
        target.mkdir(parents=True)
        (root / 'Packages').mkdir(exist_ok=True)
        (root / 'Packages' / name).symlink_to(target, target_is_directory=True)
    for name, dependency in (manifests or {'TimeTugCore': f'.package(url: "{URL}", from: "1.0.0")'}).items():
        d = root / 'Packages' / name
        d.mkdir(parents=True)
        (d / 'Package.swift').write_text(MANIFEST % (name, dependency))
    # Version-specific manifests (Package@swift-5.9.swift) that SwiftPM prefers over Package.swift.
    for relative, dependency in (extra_manifests or {}).items():
        path = root / 'Packages' / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(MANIFEST % (path.parent.name, dependency))

def run(root):
    return subprocess.run([sys.executable, str(SCRIPT), str(root)], capture_output=True, text=True)

class SharedPins(unittest.TestCase):
    def check(self, ok, needle=None, **kwargs):
        with tempfile.TemporaryDirectory() as tmp:
            make(Path(tmp), **kwargs)
            result = run(tmp)
        self.assertEqual(result.returncode == 0, ok, result.stderr + result.stdout)
        if needle:
            self.assertIn(needle, result.stderr)

    def test_released_pin_inside_every_range_passes(self):
        self.check(True)

    def test_unrelated_local_path_dependencies_are_fine(self):
        self.check(True, manifests={'CalendarBridge': '.package(path: "../TimeTugCore")',
                                    'TimeTugCore': f'.package(url: "{URL}", from: "1.0.0")'})

    def test_path_dependency_on_the_library_fails(self):
        self.check(False, 'Packages/TimeTugCore/Package.swift',
                   manifests={'TimeTugCore': '.package(path: "/Users/me/calendar-connectors")'.replace(
                       '/Users/me/calendar-connectors', '../CalendarConnectors')})

    def test_branch_dependency_fails(self):
        self.check(False, 'from:', manifests={'TimeTugCore': f'.package(url: "{URL}", branch: "main")'})

    def test_project_path_fails(self):
        self.check(False, 'url', project='packages:\n  CalendarConnectors:\n    path: ../../../calendar-connectors\n')

    def test_project_without_exact_version_fails(self):
        self.check(False, 'exactVersion',
                   project='packages:\n  CalendarConnectors:\n    url: %s\n    from: 1.0.0\n' % URL)

    def test_pin_below_a_floor_fails(self):
        self.check(False, 'below',
                   manifests={'TimeTugCore': f'.package(url: "{URL}", from: "1.3.0")'})

    def test_pin_in_another_major_fails(self):
        self.check(False, 'major', project=PROJECT % (URL, '2.0.0'))

    # Every .package(...) must be the released form or a path to an existing sibling spelled exactly.
    def test_path_to_an_existing_sibling_passes(self):
        self.check(True, siblings=['Shared'], manifests={'TimeTugCore': '.package(path: "../Shared")'})

    def test_sibling_path_is_case_sensitive(self):
        self.check(False, 'Packages/TimeTugCore/Package.swift', siblings=['Shared'],
                   manifests={'TimeTugCore': '.package(path: "../shared")'})

    def test_path_outside_packages_fails(self):
        self.check(False, 'Packages/TimeTugCore/Package.swift',
                   manifests={'TimeTugCore': '.package(path: "../../Other")'})

    def test_path_to_a_missing_sibling_fails(self):
        self.check(False, 'Packages/TimeTugCore/Package.swift',
                   manifests={'TimeTugCore': '.package(path: "../Missing")'})

    def test_sibling_that_is_the_library_itself_fails(self):
        self.check(False, 'Packages/TimeTugCore/Package.swift', siblings=['calendar-connectors'],
                   manifests={'TimeTugCore': '.package(path: "../calendar-connectors")'})

    def test_multi_line_released_form_passes(self):
        self.check(True, manifests={'TimeTugCore': f'.package(\n        url: "{URL}",\n        from: "1.0.0"\n    )'})

    def test_multi_line_sibling_path_passes(self):
        self.check(True, siblings=['Shared'], manifests={'TimeTugCore': '.package(\n        path: "../Shared"\n    )'})

    def test_multi_line_form_that_is_not_allowed_fails(self):
        self.check(False, 'Packages/TimeTugCore/Package.swift',
                   manifests={'TimeTugCore': f'.package(\n        url: "{URL}",\n        branch: "main"\n    )'})


    # Any other project.yml entry that reaches the library defeats the pin: XcodeGen emits a local package
    # reference and SwiftPM resolves the checkout over exactVersion.
    def test_second_package_key_with_path_to_the_library_fails(self):
        self.check(False, 'CCLocal', project=PROJECT % (URL, '1.2.0') +
                   '  CCLocal:\n    path: ../../../calendar-connectors\n')

    def test_second_package_key_with_the_library_url_fails(self):
        self.check(False, 'Whatever', project=PROJECT % (URL, '1.2.0') +
                   '  Whatever:\n    url: https://github.com/binary-companion/Calendar-Connectors.git\n'
                   '    exactVersion: 1.2.0\n')

    def test_second_package_key_with_github_shorthand_for_the_library_fails(self):
        self.check(False, 'Shorthand', project=PROJECT % (URL, '1.2.0') +
                   '  Shorthand:\n    github: binary-companion/calendar-connectors\n    exactVersion: 1.2.0\n')

    def test_local_packages_entry_pointing_at_the_library_fails(self):
        self.check(False, 'localPackages', project=PROJECT % (URL, '1.2.0') +
                   'localPackages:\n  - ../../../calendar-connectors\n')

    def test_local_packages_mapping_entry_pointing_at_the_library_fails(self):
        self.check(False, 'localPackages', project=PROJECT % (URL, '1.2.0') +
                   'localPackages:\n  - path: ../../../calendar-connectors\n')

    def test_local_packages_entry_outside_packages_fails(self):
        self.check(False, 'localPackages', project=PROJECT % (URL, '1.2.0') + 'localPackages:\n  - ../Elsewhere\n')

    def test_local_packages_entry_for_an_existing_sibling_passes(self):
        self.check(True, siblings=['Shared'],
                   project=PROJECT % (URL, '1.2.0') + 'localPackages:\n  - ../../Packages/Shared\n')

    def test_second_package_key_with_a_sibling_path_passes(self):
        self.check(True, siblings=['Shared'], project=PROJECT % (URL, '1.2.0') +
                   '  Shared:\n    path: ../../Packages/Shared\n')

    def test_second_package_key_with_an_external_url_passes(self):
        self.check(True, project=PROJECT % (URL, '1.2.0') +
                   '  Sparkle:\n    url: https://github.com/sparkle-project/Sparkle\n    exactVersion: 2.10.0\n')

    def test_second_package_key_with_a_missing_sibling_path_fails(self):
        self.check(False, 'Missing', project=PROJECT % (URL, '1.2.0') +
                   '  Missing:\n    path: ../../Packages/Missing\n')

    def test_second_package_key_with_a_case_variant_sibling_path_fails(self):
        self.check(False, 'Shared', siblings=['Shared'], project=PROJECT % (URL, '1.2.0') +
                   '  Shared:\n    path: ../../Packages/shared\n')

    def test_second_package_key_with_a_path_outside_packages_fails(self):
        self.check(False, 'Elsewhere', project=PROJECT % (URL, '1.2.0') +
                   '  Elsewhere:\n    path: ../../../Elsewhere\n')

    def test_second_package_key_that_is_not_a_mapping_fails(self):
        self.check(False, 'Odd', project=PROJECT % (URL, '1.2.0') + '  Odd: ../../../calendar-connectors\n')

    # SwiftPM prefers Package@swift-X.Y.swift over Package.swift, so every Package*.swift is scanned.
    def test_version_specific_manifest_with_a_path_to_the_library_fails(self):
        self.check(False, 'Package@swift-5.9.swift',
                   extra_manifests={'TimeTugCore/Package@swift-5.9.swift':
                                    '.package(path: "../../../calendar-connectors")'})

    def test_clean_version_specific_manifest_passes(self):
        self.check(True, extra_manifests={'TimeTugCore/Package@swift-5.9.swift':
                                          f'.package(url: "{URL}", from: "1.0.0")'})

    def test_version_specific_manifest_with_a_floor_above_the_pin_fails(self):
        self.check(False, 'below', extra_manifests={'TimeTugCore/Package@swift-5.9.swift':
                                                    f'.package(url: "{URL}", from: "1.3.0")'})

    # XcodeGen `include:` can add packages from a file this check does not read.
    def test_top_level_include_key_fails(self):
        self.check(False, 'include', project=PROJECT % (URL, '1.2.0') + 'include:\n  - extra.yml\n')

    # A symlink under Packages/ may point anywhere, so it is not an existing sibling directory.
    def test_symlinked_sibling_in_a_manifest_fails(self):
        self.check(False, 'Packages/TimeTugCore/Package.swift', symlinks=['Shared'],
                   manifests={'TimeTugCore': '.package(path: "../Shared")'})

    def test_symlinked_sibling_in_the_project_fails(self):
        self.check(False, 'Shared', symlinks=['Shared'],
                   project=PROJECT % (URL, '1.2.0') + '  Shared:\n    path: ../../Packages/Shared\n')

    def test_symlinked_sibling_in_local_packages_fails(self):
        self.check(False, 'localPackages', symlinks=['Shared'],
                   project=PROJECT % (URL, '1.2.0') + 'localPackages:\n  - ../../Packages/Shared\n')

    # Manifests are found at any depth under Packages/ (except .build and build directories).
    def test_nested_manifest_with_a_path_to_the_library_fails(self):
        self.check(False, 'Packages/TimeTugCore/Tests/Fixture/Package.swift',
                   extra_manifests={'TimeTugCore/Tests/Fixture/Package.swift':
                                    '.package(path: "../../../../../calendar-connectors")'})

    def test_nested_manifest_with_a_branch_dependency_fails(self):
        self.check(False, 'Packages/TimeTugCore/Sub/Package@swift-5.9.swift',
                   extra_manifests={'TimeTugCore/Sub/Package@swift-5.9.swift':
                                    f'.package(url: "{URL}", branch: "main")'})

    def test_nested_manifest_with_a_floor_above_the_pin_fails(self):
        self.check(False, 'below', extra_manifests={'TimeTugCore/Sub/Package.swift':
                                                    f'.package(url: "{URL}", from: "1.3.0")'})

    def test_clean_nested_manifest_passes(self):
        self.check(True, extra_manifests={'TimeTugCore/Sub/Package.swift': f'.package(url: "{URL}", from: "1.0.0")'})

    def test_nested_manifest_path_is_resolved_from_its_own_directory(self):
        self.check(True, siblings=['Shared'],
                   extra_manifests={'TimeTugCore/Tests/Fixture/Package.swift': '.package(path: "../../../Shared")'})

    def test_nested_manifest_path_to_a_missing_sibling_fails(self):
        self.check(False, 'Packages/TimeTugCore/Tests/Fixture/Package.swift',
                   extra_manifests={'TimeTugCore/Tests/Fixture/Package.swift': '.package(path: "../../../Missing")'})

    def test_manifests_under_build_directories_are_skipped(self):
        bad = '.package(path: "../../../../calendar-connectors")'
        self.check(True, extra_manifests={'TimeTugCore/.build/checkouts/Dep/Package.swift': bad,
                                          'TimeTugCore/build/Dep/Package.swift': bad})

    # A trailing slash is a different url from the pinned one; it is never accepted as the library.
    def test_pinned_project_url_with_a_trailing_slash_fails(self):
        self.check(False, 'must use url', project=PROJECT % (URL + '/', '1.2.0'))

    def test_manifest_url_with_a_trailing_slash_fails(self):
        self.check(False, 'Packages/TimeTugCore/Package.swift',
                   manifests={'TimeTugCore': f'.package(url: "{URL}/", from: "1.0.0")'})

    def test_second_package_key_with_a_trailing_slash_library_url_fails(self):
        self.check(False, 'Slashed', project=PROJECT % (URL, '1.2.0') +
                   f'  Slashed:\n    url: {URL}/\n    exactVersion: 1.2.0\n')

    # Wording: an entry that reaches the library "points at" it; a third-party name that merely contains the
    # library name "names" it (it is rejected either way).
    def test_entry_that_reaches_the_library_says_points_at(self):
        self.check(False, 'points at the shared library', project=PROJECT % (URL, '1.2.0') +
                   '  Fork:\n    url: https://github.com/someone/calendar-connectors.git\n    exactVersion: 1.2.0\n')

    def test_third_party_name_containing_the_library_name_says_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            make(Path(tmp), project=PROJECT % (URL, '1.2.0') +
                 '  Extras:\n    url: https://github.com/someone/calendar-connectors-extras\n    exactVersion: 1.0.0\n')
            result = run(tmp)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('names the shared library', result.stderr)
        self.assertNotIn('points at', result.stderr)


# XcodeGen gives `path` precedence over `url`, so an entry with any key besides url and exactVersion can hide a
# local override behind an otherwise valid pin. One test per extra key.
EXTRA_KEYS = {'path': '../../../calendar-connectors', 'branch': 'main', 'revision': 'abc123', 'from': '1.0.0',
              'version': '1.2.0', 'minimumVersion': '1.0.0', 'majorVersion': '1', 'group': 'Libraries'}

def project_with_extra_key(key):
    def test(self):
        self.check(False, f'unexpected key(s) {key};',
                   project=PROJECT % (URL, '1.2.0') + f'    {key}: {EXTRA_KEYS[key]}\n')
    return test

# Dependencies the old substring deny-list let through; each must now fail.
DISGUISED = {
    'hyphen_and_case_variant_path': '.package(path: "../../../Calendar-Connectors")',
    'unrelated_absolute_path': '.package(path: "/Users/me/Source/cc")',
    'name_without_hyphen': '.package(path: "../calendarconnectors")',
    'short_name': '.package(path: "../connectors")',
    'case_variant_url': '.package(url: "%s", from: "1.0.0")' % URL.replace('calendar-connectors', 'Calendar-Connectors'),
}

def disguised_dependency(dependency):
    def test(self):
        self.check(False, dependency, manifests={'TimeTugCore': dependency})
    return test

for _key in EXTRA_KEYS:
    setattr(SharedPins, f'test_project_entry_with_extra_{_key}_key_fails', project_with_extra_key(_key))
for _name, _dependency in DISGUISED.items():
    setattr(SharedPins, f'test_disguised_{_name}_fails', disguised_dependency(_dependency))

if __name__ == '__main__':
    unittest.main()
