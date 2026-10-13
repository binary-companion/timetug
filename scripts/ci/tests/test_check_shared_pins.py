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

def make(root: Path, project=PROJECT % (URL, '1.2.0'), manifests=None):
    (root / 'Apps/macOS').mkdir(parents=True)
    (root / 'Apps/macOS/project.yml').write_text(project)
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

if __name__ == '__main__':
    unittest.main()
