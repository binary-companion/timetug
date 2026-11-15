import Foundation
import TimeTugKit
import XCTest
@testable import TimeTug

/// The widget extension carries a copy of the join-URL scheme allow-list (it must not link the engine). The copy must
/// give the engine's answer (`joinUrlIsAllowed`) for every URL.
final class JoinURLPolicyParityTests: XCTestCase {
    private let urls = [
        "https://meet.google.com/abc-defg-hij", "http://example.com/join", "HTTPS://Example.COM/x",
        "https://teams.microsoft.com/l/meetup-join/abc", "https://zoom.us/j/123456789",
        "zoommtg://zoom.us/join?confno=123", "zoommtg://us02web.zoom.us/join?confno=123", "zoommtg://ZOOM.US/join",
        "zoommtg://zoom.com/join", "zoommtg://us02web.zoom.com/join", "zoommtg://evil.example.com/join",
        "zoommtg://notzoom.us/join", "zoommtg://zoom.us.evil.com/join", "zoommtg:///join", "zoommtg:join",
        "https://user@example.com/x", "https://user:pass@example.com/x", "https://:pass@example.com/x",
        "https:///path", "https:path", "file:///etc/passwd", "javascript:alert(1)", "data:text/html,hi",
        "ftp://example.com/x", "tel:+15555550100", "mailto:a@example.com", "tg://resolve?domain=x",
        "facetime://someone", "msteams://teams.microsoft.com/l/x", "webex://meet/abc", "slack://channel?id=1",
        "custom-scheme://host/path", "//example.com/x", "/relative/path", "example.com/x", "",
    ]

    func testCopyAgreesWithTheEngineOnEveryURL() {
        for text in urls {
            guard let url = URL(string: text) else { continue }   // not a URL: neither side can be asked
            XCTAssertEqual(JoinURLPolicy.isAllowed(url), joinUrlIsAllowed(url: url), "disagree on \(text)")
        }
    }

    func testTheListExercisesBothAnswers() {
        let parsed = urls.compactMap(URL.init(string:))
        XCTAssertTrue(parsed.contains { joinUrlIsAllowed(url: $0) })
        XCTAssertTrue(parsed.contains { !joinUrlIsAllowed(url: $0) })
        XCTAssertGreaterThan(parsed.count, 20)
    }
}
