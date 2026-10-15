import subprocess, sys, tempfile, unittest
from collections import namedtuple
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'check-shared-pins.py'
ORG = 'https://github.com/binary-companion/'

# slug (repository), project.yml key, a valid pin, and a floor above that pin within the same major. The two
# libraries deliberately have different pins: a check that compared a floor with the wrong library's pin would
# disagree with these numbers.
Library = namedtuple('Library', 'slug key pin above')
CALENDAR_CONNECTORS = Library('calendar-connectors', 'CalendarConnectors', '1.2.0', '1.3.0')
TIMETUG_SHARED = Library('timetug-shared', 'TimeTugShared', '1.0.0', '1.1.0')
LIBRARIES = (CALENDAR_CONNECTORS, TIMETUG_SHARED)

MANIFEST = '''let package = Package(
    name: "%s",
    dependencies: [%s],
    targets: []
)
'''

def url(library):
    return ORG + library.slug

def released(library, floor='1.0.0'):
    return f'.package(url: "{url(library)}", from: "{floor}")'

def pinned(library, url_=None, pin=None, more=''):
    """The lines of a valid project.yml entry for `library`, optionally with another url or pin or extra lines."""
    return f'    url: {url_ or url(library)}\n    exactVersion: {pin or library.pin}\n{more}'

def project_yml(replace=None, extra=''):
    """A project.yml pinning both libraries. `replace` maps a slug to the body lines of that entry (None leaves
    the entry out); `extra` is appended after the packages (more package entries or localPackages)."""
    replace = replace or {}
    text = 'packages:\n'
    for library in LIBRARIES:
        body = replace.get(library.slug, pinned(library))
        if body is not None:
            text += f'  {library.key}:\n{body}'
    return text + extra

def make(root: Path, project=None, manifests=None, siblings=(), extra_manifests=None, symlinks=()):
    (root / 'Apps/macOS').mkdir(parents=True)
    (root / 'Apps/macOS/project.yml').write_text(project if project is not None else project_yml())
    for name in siblings:
        (root / 'Packages' / name).mkdir(parents=True)
    # A symlink under Packages/ to a real directory elsewhere: it must not count as a sibling.
    for name in symlinks:
        target = root / 'elsewhere' / name
        target.mkdir(parents=True)
        (root / 'Packages').mkdir(exist_ok=True)
        (root / 'Packages' / name).symlink_to(target, target_is_directory=True)
    default = {'TimeTugCore': ', '.join(released(library) for library in LIBRARIES)}
    for name, dependency in (manifests or default).items():
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

class Checks:
    def check(self, ok, needle=None, **kwargs):
        with tempfile.TemporaryDirectory() as tmp:
            make(Path(tmp), **kwargs)
            result = run(tmp)
        self.assertEqual(result.returncode == 0, ok, result.stderr + result.stdout)
        if needle:
            self.assertIn(needle, result.stderr)

class LibraryPins(Checks):
    """Every protection, for the library in `lib`; subclassed once per shared library so that none of them
    exists for one library only. `self.dep` is the library's released form, `self.manifest` a manifest that
    depends on it (the other library is left out so a failure can only come from this one)."""
    lib = None

    @property
    def url(self):
        return url(self.lib)

    def own(self, body):
        """A project.yml whose entry for this library has the given body lines."""
        return project_yml({self.lib.slug: body})

    def alone(self, dependency):
        return {'TimeTugCore': dependency}

    def test_released_pin_inside_every_range_passes(self):
        self.check(True)

    def test_unrelated_local_path_dependencies_are_fine(self):
        self.check(True, manifests={'CalendarBridge': '.package(path: "../TimeTugCore")',
                                    'TimeTugCore': released(self.lib)})

    def test_path_dependency_on_the_library_fails(self):
        for name in (self.lib.key, self.lib.slug):
            with self.subTest(name=name):
                self.check(False, 'Packages/TimeTugCore/Package.swift',
                           manifests=self.alone(f'.package(path: "../{name}")'))

    def test_branch_dependency_fails(self):
        self.check(False, 'from:', manifests=self.alone(f'.package(url: "{self.url}", branch: "main")'))

    def test_revision_dependency_fails(self):
        self.check(False, 'Packages/TimeTugCore/Package.swift',
                   manifests=self.alone(f'.package(url: "{self.url}", revision: "abc123")'))

    def test_exact_dependency_fails(self):
        self.check(False, 'Packages/TimeTugCore/Package.swift',
                   manifests=self.alone(f'.package(url: "{self.url}", exact: "{self.lib.pin}")'))

    def test_a_from_that_is_not_a_version_fails(self):
        self.check(False, f'{self.lib.slug} needs from: "X.Y.Z"',
                   manifests=self.alone(f'.package(url: "{self.url}", from: "1.0")'))

    def test_project_path_fails(self):
        self.check(False, f'{self.lib.key} must use url', project=self.own(f'    path: ../../../{self.lib.slug}\n'))

    def test_project_without_exact_version_fails(self):
        self.check(False, f'{self.lib.key} needs exactVersion X.Y.Z',
                   project=self.own(f'    url: {self.url}\n    from: 1.0.0\n'))

    def test_project_with_a_two_part_exact_version_fails(self):
        self.check(False, f'{self.lib.key} needs exactVersion X.Y.Z', project=self.own(pinned(self.lib, pin='1.0')))

    def test_project_with_a_prerelease_exact_version_fails(self):
        self.check(False, f'{self.lib.key} needs exactVersion X.Y.Z',
                   project=self.own(pinned(self.lib, pin='1.0.0-beta')))

    def test_project_without_the_entry_fails(self):
        self.check(False, f'package {self.lib.key} is missing', project=project_yml({self.lib.slug: None}))

    def test_project_entry_that_is_not_a_mapping_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            others = ''.join(f'  {l.key}:\n{pinned(l)}' for l in LIBRARIES if l != self.lib)
            make(Path(tmp), project=f'packages:\n{others}  {self.lib.key}: {self.url}\n')
            result = run(tmp)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f'{self.lib.key} must be a mapping', result.stderr)

    def test_project_url_of_another_repository_fails(self):
        self.check(False, f'{self.lib.key} must use url',
                   project=self.own(pinned(self.lib, url_='https://github.com/someone/' + self.lib.slug)))

    def test_project_url_with_a_git_suffix_fails(self):
        self.check(False, f'{self.lib.key} must use url', project=self.own(pinned(self.lib, url_=self.url + '.git')))

    def test_project_url_of_the_other_library_fails(self):
        other = next(l for l in LIBRARIES if l != self.lib)
        self.check(False, f'{self.lib.key} must use url', project=self.own(pinned(self.lib, url_=url(other))))

    def test_pin_below_a_floor_fails(self):
        self.check(False, f'the {self.lib.slug} pin {self.lib.pin} is below',
                   manifests=self.alone(released(self.lib, self.lib.above)))

    def test_pin_in_another_major_fails(self):
        self.check(False, f'the {self.lib.slug} pin 2.0.0 is in another major',
                   project=self.own(pinned(self.lib, pin='2.0.0')), manifests=self.alone(released(self.lib)))

    def test_floor_equal_to_the_pin_passes(self):
        self.check(True, manifests=self.alone(released(self.lib, self.lib.pin)))

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
        for name in (self.lib.slug, self.lib.key):
            with self.subTest(name=name):
                self.check(False, 'Packages/TimeTugCore/Package.swift', siblings=[name],
                           manifests={'TimeTugCore': f'.package(path: "../{name}")'})

    def test_path_outside_packages_to_the_library_fails(self):
        for name in (self.lib.slug, self.lib.key):
            with self.subTest(name=name):
                self.check(False, 'Packages/TimeTugCore/Package.swift',
                           manifests={'TimeTugCore': f'.package(path: "../../../{name}")'})

    def test_sibling_directory_named_like_the_library_is_not_a_valid_sibling(self):
        # Both spellings of the library's name, as manifest path and as project.yml entry.
        for name in (self.lib.slug, self.lib.key):
            with self.subTest(name=name):
                self.check(False, 'Packages/TimeTugCore/Package.swift', siblings=[name],
                           manifests={'TimeTugCore': f'.package(path: "../{name}")'})
                self.check(False, 'Local', siblings=[name],
                           project=project_yml(extra=f'  Local:\n    path: ../../Packages/{name}\n'))

    def test_multi_line_released_form_passes(self):
        self.check(True, manifests=self.alone(f'.package(\n        url: "{self.url}",\n        from: "1.0.0"\n    )'))

    def test_multi_line_sibling_path_passes(self):
        self.check(True, siblings=['Shared'], manifests={'TimeTugCore': '.package(\n        path: "../Shared"\n    )'})

    def test_multi_line_form_that_is_not_allowed_fails(self):
        self.check(False, 'Packages/TimeTugCore/Package.swift',
                   manifests=self.alone(f'.package(\n        url: "{self.url}",\n        branch: "main"\n    )'))

    # Any other project.yml entry that reaches the library defeats the pin: XcodeGen emits a local package
    # reference and SwiftPM resolves the checkout over exactVersion.
    def test_second_package_key_with_path_to_the_library_fails(self):
        self.check(False, 'CCLocal',
                   project=project_yml(extra=f'  CCLocal:\n    path: ../../../{self.lib.slug}\n'))

    def test_second_package_key_with_a_path_to_the_library_key_spelling_fails(self):
        self.check(False, 'CCLocal',
                   project=project_yml(extra=f'  CCLocal:\n    path: ../../../{self.lib.key}\n'))

    def test_second_package_key_with_the_library_url_fails(self):
        self.check(False, 'Whatever', project=project_yml(
            extra='  Whatever:\n    url: ' + ORG + self.lib.slug.title() + '.git\n    exactVersion: 1.2.0\n'))

    def test_second_package_key_with_the_exact_library_url_fails(self):
        self.check(False, 'points at the shared library', project=project_yml(
            extra=f'  Whatever:\n    url: {self.url}\n    exactVersion: {self.lib.pin}\n'))

    def test_second_package_key_with_github_shorthand_for_the_library_fails(self):
        self.check(False, 'Shorthand', project=project_yml(
            extra=f'  Shorthand:\n    github: binary-companion/{self.lib.slug}\n    exactVersion: 1.2.0\n'))

    def test_local_packages_entry_pointing_at_the_library_fails(self):
        self.check(False, 'localPackages',
                   project=project_yml(extra=f'localPackages:\n  - ../../../{self.lib.slug}\n'))

    def test_local_packages_entry_for_the_library_inside_packages_fails(self):
        for name in (self.lib.slug, self.lib.key):
            with self.subTest(name=name):
                self.check(False, 'localPackages', siblings=[name],
                           project=project_yml(extra=f'localPackages:\n  - ../../Packages/{name}\n'))

    def test_local_packages_entry_that_merely_contains_the_library_name_fails(self):
        # An existing sibling is normally fine; one whose name contains the library's is rejected like a
        # second package key naming it.
        name = self.lib.slug + '-extras'
        self.check(False, 'localPackages', siblings=[name],
                   project=project_yml(extra=f'localPackages:\n  - ../../Packages/{name}\n'))

    def test_local_packages_mapping_entry_pointing_at_the_library_fails(self):
        self.check(False, 'localPackages',
                   project=project_yml(extra=f'localPackages:\n  - path: ../../../{self.lib.slug}\n'))

    def test_local_packages_entry_outside_packages_fails(self):
        self.check(False, 'localPackages', project=project_yml(extra='localPackages:\n  - ../Elsewhere\n'))

    def test_local_packages_entry_for_an_existing_sibling_passes(self):
        self.check(True, siblings=['Shared'], project=project_yml(extra='localPackages:\n  - ../../Packages/Shared\n'))

    def test_second_package_key_with_a_sibling_path_passes(self):
        self.check(True, siblings=['Shared'], project=project_yml(extra='  Shared:\n    path: ../../Packages/Shared\n'))

    def test_second_package_key_with_an_external_url_passes(self):
        self.check(True, project=project_yml(
            extra='  Sparkle:\n    url: https://github.com/sparkle-project/Sparkle\n    exactVersion: 2.10.0\n'))

    def test_second_package_key_with_a_missing_sibling_path_fails(self):
        self.check(False, 'Missing', project=project_yml(extra='  Missing:\n    path: ../../Packages/Missing\n'))

    def test_second_package_key_with_a_case_variant_sibling_path_fails(self):
        self.check(False, 'Shared', siblings=['Shared'],
                   project=project_yml(extra='  Shared:\n    path: ../../Packages/shared\n'))

    def test_second_package_key_with_a_path_outside_packages_fails(self):
        self.check(False, 'Elsewhere', project=project_yml(extra='  Elsewhere:\n    path: ../../../Elsewhere\n'))

    def test_second_package_key_that_is_not_a_mapping_fails(self):
        self.check(False, 'Odd', project=project_yml(extra=f'  Odd: ../../../{self.lib.slug}\n'))

    # SwiftPM prefers Package@swift-X.Y.swift over Package.swift, so every Package*.swift is scanned.
    def test_version_specific_manifest_with_a_path_to_the_library_fails(self):
        self.check(False, 'Package@swift-5.9.swift',
                   extra_manifests={'TimeTugCore/Package@swift-5.9.swift':
                                    f'.package(path: "../../../{self.lib.slug}")'})

    def test_clean_version_specific_manifest_passes(self):
        self.check(True, extra_manifests={'TimeTugCore/Package@swift-5.9.swift': released(self.lib)})

    def test_version_specific_manifest_with_a_floor_above_the_pin_fails(self):
        self.check(False, 'below', extra_manifests={'TimeTugCore/Package@swift-5.9.swift':
                                                    released(self.lib, self.lib.above)})

    # XcodeGen `include:` can add packages from a file this check does not read.
    def test_top_level_include_key_fails(self):
        self.check(False, 'include', project=project_yml(extra='include:\n  - extra.yml\n'))

    # A symlink under Packages/ may point anywhere, so it is not an existing sibling directory.
    def test_symlinked_sibling_in_a_manifest_fails(self):
        self.check(False, 'Packages/TimeTugCore/Package.swift', symlinks=['Shared'],
                   manifests={'TimeTugCore': '.package(path: "../Shared")'})

    def test_symlinked_sibling_in_the_project_fails(self):
        self.check(False, 'Shared', symlinks=['Shared'],
                   project=project_yml(extra='  Shared:\n    path: ../../Packages/Shared\n'))

    def test_symlinked_sibling_in_local_packages_fails(self):
        self.check(False, 'localPackages', symlinks=['Shared'],
                   project=project_yml(extra='localPackages:\n  - ../../Packages/Shared\n'))

    # Manifests are found at any depth under Packages/ (except .build and build directories).
    def test_nested_manifest_with_a_path_to_the_library_fails(self):
        self.check(False, 'Packages/TimeTugCore/Tests/Fixture/Package.swift',
                   extra_manifests={'TimeTugCore/Tests/Fixture/Package.swift':
                                    f'.package(path: "../../../../../{self.lib.slug}")'})

    def test_nested_manifest_with_a_branch_dependency_fails(self):
        self.check(False, 'Packages/TimeTugCore/Sub/Package@swift-5.9.swift',
                   extra_manifests={'TimeTugCore/Sub/Package@swift-5.9.swift':
                                    f'.package(url: "{self.url}", branch: "main")'})

    def test_nested_manifest_with_a_floor_above_the_pin_fails(self):
        self.check(False, 'below', extra_manifests={'TimeTugCore/Sub/Package.swift':
                                                    released(self.lib, self.lib.above)})

    def test_clean_nested_manifest_passes(self):
        self.check(True, extra_manifests={'TimeTugCore/Sub/Package.swift': released(self.lib)})

    def test_nested_manifest_path_is_resolved_from_its_own_directory(self):
        self.check(True, siblings=['Shared'],
                   extra_manifests={'TimeTugCore/Tests/Fixture/Package.swift': '.package(path: "../../../Shared")'})

    def test_nested_manifest_path_to_a_missing_sibling_fails(self):
        self.check(False, 'Packages/TimeTugCore/Tests/Fixture/Package.swift',
                   extra_manifests={'TimeTugCore/Tests/Fixture/Package.swift': '.package(path: "../../../Missing")'})

    def test_manifests_under_build_directories_are_skipped(self):
        bad = f'.package(path: "../../../../{self.lib.slug}")'
        self.check(True, extra_manifests={'TimeTugCore/.build/checkouts/Dep/Package.swift': bad,
                                          'TimeTugCore/build/Dep/Package.swift': bad})

    # A trailing slash is a different url from the pinned one; it is never accepted as the library.
    def test_pinned_project_url_with_a_trailing_slash_fails(self):
        self.check(False, 'must use url', project=self.own(pinned(self.lib, url_=self.url + '/')))

    def test_manifest_url_with_a_trailing_slash_fails(self):
        self.check(False, 'Packages/TimeTugCore/Package.swift',
                   manifests=self.alone(f'.package(url: "{self.url}/", from: "1.0.0")'))

    def test_second_package_key_with_a_trailing_slash_library_url_fails(self):
        self.check(False, 'Slashed', project=project_yml(
            extra=f'  Slashed:\n    url: {self.url}/\n    exactVersion: 1.2.0\n'))

    # Wording: an entry that reaches the library "points at" it; a third-party name that merely contains the
    # library name "names" it (it is rejected either way).
    def test_entry_that_reaches_the_library_says_points_at(self):
        self.check(False, 'points at the shared library', project=project_yml(
            extra=f'  Fork:\n    url: https://github.com/someone/{self.lib.slug}.git\n    exactVersion: 1.2.0\n'))

    def test_third_party_name_containing_the_library_name_says_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            make(Path(tmp), project=project_yml(
                extra=f'  Extras:\n    url: https://github.com/someone/{self.lib.slug}-extras\n'
                      '    exactVersion: 1.0.0\n'))
            result = run(tmp)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('names the shared library', result.stderr)
        self.assertNotIn('points at', result.stderr)

    # XcodeGen gives `path` precedence over `url`, so an entry with any key besides url and exactVersion can hide
    # a local override behind an otherwise valid pin. One subtest per extra key.
    def test_project_entry_with_any_extra_key_fails(self):
        keys = {'path': f'../../../{self.lib.slug}', 'branch': 'main', 'revision': 'abc123', 'from': '1.0.0',
                'version': '1.2.0', 'minimumVersion': '1.0.0', 'majorVersion': '1', 'group': 'Libraries'}
        for key, value in keys.items():
            with self.subTest(key=key):
                self.check(False, f'{self.lib.key} has unexpected key(s) {key};',
                           project=self.own(pinned(self.lib, more=f'    {key}: {value}\n')))

    # Dependencies a substring deny-list would let through; each must fail.
    def test_disguised_dependencies_fail(self):
        slug = self.lib.slug
        disguised = {
            'hyphen_and_case_variant_path': f'.package(path: "../../../{slug.title()}")',
            'unrelated_absolute_path': '.package(path: "/Users/me/Source/cc")',
            'name_without_hyphen': f'.package(path: "../{slug.replace("-", "")}")',
            'short_name': f'.package(path: "../{slug.split("-")[-1]}")',
            'case_variant_url': '.package(url: "%s", from: "1.0.0")' % self.url.replace(slug, slug.title()),
        }
        for name, dependency in disguised.items():
            with self.subTest(name=name):
                self.check(False, dependency, manifests=self.alone(dependency))


class CalendarConnectorsPins(LibraryPins, unittest.TestCase):
    lib = CALENDAR_CONNECTORS


class TimeTugSharedPins(LibraryPins, unittest.TestCase):
    lib = TIMETUG_SHARED


class BothLibraries(Checks, unittest.TestCase):
    """The rules that involve both libraries at once: each is checked against its own pin and its own url."""

    def test_both_entries_missing_fails_naming_both(self):
        with tempfile.TemporaryDirectory() as tmp:
            make(Path(tmp), project='packages:\n  Sparkle:\n    url: https://github.com/sparkle-project/Sparkle\n'
                                    '    exactVersion: 2.10.0\n')
            result = run(tmp)
        self.assertNotEqual(result.returncode, 0)
        for library in LIBRARIES:
            self.assertIn(f'package {library.key} is missing', result.stderr)

    def test_a_manifest_depending_on_both_libraries_passes(self):
        self.check(True, manifests={'TimeTugCore': released(CALENDAR_CONNECTORS) + ', ' + released(TIMETUG_SHARED)})

    def test_each_floor_is_compared_with_its_own_pin(self):
        # calendar-connectors is pinned at 1.2.0 and timetug-shared at 1.0.0: a floor of 1.1.0 is fine for the
        # first and above the pin of the second.
        self.check(True, manifests={'TimeTugCore': released(CALENDAR_CONNECTORS, '1.1.0')})
        self.check(False, f'the timetug-shared pin 1.0.0 is below',
                   manifests={'TimeTugCore': released(TIMETUG_SHARED, '1.1.0')})
        self.check(False, f'the timetug-shared pin 1.0.0 is below',
                   manifests={'TimeTugCore': released(CALENDAR_CONNECTORS, '1.1.0') + ', ' +
                              released(TIMETUG_SHARED, '1.1.0')})
        self.check(False, f'the calendar-connectors pin 1.2.0 is below',
                   manifests={'TimeTugCore': released(CALENDAR_CONNECTORS, '1.3.0') + ', ' +
                              released(TIMETUG_SHARED, '1.0.0')})

    def test_each_floor_is_compared_with_the_major_of_its_own_pin(self):
        project = project_yml({'calendar-connectors': pinned(CALENDAR_CONNECTORS, pin='2.0.0')})
        self.check(True, project=project, manifests={
            'TimeTugCore': released(CALENDAR_CONNECTORS, '2.0.0') + ', ' + released(TIMETUG_SHARED, '1.0.0')})
        self.check(False, 'the calendar-connectors pin 2.0.0 is in another major', project=project, manifests={
            'TimeTugCore': released(CALENDAR_CONNECTORS, '1.0.0') + ', ' + released(TIMETUG_SHARED, '1.0.0')})
        self.check(False, 'the timetug-shared pin 1.0.0 is in another major', project=project, manifests={
            'TimeTugCore': released(CALENDAR_CONNECTORS, '2.0.0') + ', ' + released(TIMETUG_SHARED, '2.0.0')})

    def test_a_bad_dependency_after_a_good_one_is_still_found(self):
        self.check(False, 'branch', manifests={
            'TimeTugCore': released(TIMETUG_SHARED) + f', .package(url: "{url(CALENDAR_CONNECTORS)}", branch: "main")'})
        self.check(False, 'branch', manifests={
            'TimeTugCore': released(CALENDAR_CONNECTORS) + f', .package(url: "{url(TIMETUG_SHARED)}", branch: "main")'})

    def test_each_library_may_use_a_local_package_next_to_the_other(self):
        self.check(True, siblings=['Shared'], project=project_yml(extra='  Shared:\n    path: ../../Packages/Shared\n'),
                   manifests={'TimeTugCore': released(CALENDAR_CONNECTORS) + ', ' + released(TIMETUG_SHARED) +
                              ', .package(path: "../Shared")'})

    def test_a_second_key_cannot_carry_the_other_library_as_a_local_path(self):
        for library in LIBRARIES:
            with self.subTest(library=library.slug):
                self.check(False, 'Second', project=project_yml(
                    extra=f'  Second:\n    path: ../../../{library.slug}\n'))


if __name__ == '__main__':
    unittest.main()
