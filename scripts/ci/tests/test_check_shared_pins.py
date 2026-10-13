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

def make(root: Path, project=PROJECT % (URL, '1.2.0'), manifests=None, siblings=()):
    (root / 'Apps/macOS').mkdir(parents=True)
    (root / 'Apps/macOS/project.yml').write_text(project)
    for name in siblings:
        (root / 'Packages' / name).mkdir(parents=True)
    for name, dependency in (manifests or {'TimeTugCore': f'.package(url: "{URL}", from: "1.0.0")'}).items():
        d = root / 'Packages' / name
        d.mkdir(parents=True)
        (d / 'Package.swift').write_text(MANIFEST % (name, dependency))

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
