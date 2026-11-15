import XCTest
@testable import TimeTug

final class ThirdPartyNoticesTests: XCTestCase {
    private func makeResources(files: [String: String]) throws -> URL {
        let resources = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let licenses = resources.appendingPathComponent("Licenses")
        try FileManager.default.createDirectory(at: licenses, withIntermediateDirectories: true)
        for (name, text) in files { try text.write(to: licenses.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        addTeardownBlock { try? FileManager.default.removeItem(at: resources) }
        return resources
    }

    func testCombinedTextHasEveryFileUnderItsHeading() throws {
        let resources = try makeResources(files: [
            "TimeTugEngine-THIRD-PARTY-NOTICES.md": "crates", "TimeTugEngine-LICENSE": "engine", "KeyboardShortcuts-LICENSE": "keys",
        ])
        let text = try XCTUnwrap(ThirdPartyNotices.text(resourceURL: resources))
        for part in ["crates", "engine", "keys", "KeyboardShortcuts", "TimeTug engine"] {
            XCTAssertTrue(text.contains(part), part)
        }
    }

    func testAMissingFileMakesTheTextNil() throws {
        let resources = try makeResources(files: ["TimeTugEngine-LICENSE": "engine"])
        XCTAssertNil(ThirdPartyNotices.text(resourceURL: resources))
        XCTAssertNil(ThirdPartyNotices.text(resourceURL: nil))
    }

    /// The build phase (scripts/ci/copy-licence-notices.sh) puts these in the app; the test host is the app.
    func testTheBuiltAppCarriesTheNotices() throws {
        let directory = try XCTUnwrap(ThirdPartyNotices.directory(resourceURL: Bundle.main.resourceURL))
        for name in ThirdPartyNotices.fileNames {
            let url = directory.appendingPathComponent(name)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            XCTAssertGreaterThan(size, 500, "\(name) is missing or nearly empty in the app bundle")
        }
        let notices = try XCTUnwrap(ThirdPartyNotices.text(resourceURL: Bundle.main.resourceURL))
        XCTAssertTrue(notices.contains("Mozilla Public License"), "the UniFFI MPL-2.0 notice must be reachable")
        XCTAssertTrue(notices.contains("Sindre Sorhus"), "the KeyboardShortcuts MIT notice must be reachable")
    }
}
