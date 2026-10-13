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

def make(root: Path, project=PROJECT % (URL, '1.2.0'), manifests=None, siblings=(), extra_manifests=None):
    (root / 'Apps/macOS').mkdir(parents=True)
    (root / 'Apps/macOS/project.yml').write_text(project)
    for name in siblings:
        (root / 'Packages' / name).mkdir(parents=True)
    for name, dependency in (manifests or {'TimeTugCore': f'.package(url: "{URL}", from: "1.0.0")'}).items():
        d = root / 'Packages' / name
        d.mkdir(parents=True)
        (d / 'Package.swift').write_text(MANIFEST % (name, dependency))
    # Version-specific manifests (Package@swift-5.9.swift) that SwiftPM prefers over Package.swift.
    for relative, dependency in (extra_manifests or {}).items():
        path = root / 'Packages' / relative
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
