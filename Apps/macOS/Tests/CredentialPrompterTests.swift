import TimeTugKit
import XCTest
@testable import TimeTug

/// Polls `condition` on the main actor for up to two seconds.
@MainActor
func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
    for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertTrue(condition(), "timed out waiting", file: file, line: line)
}

@MainActor
final class CredentialPrompterTests: XCTestCase {
    private let fields = [
        CredentialField(key: "username", label: "Apple ID", isSecret: false),
        CredentialField(key: "password", label: "App-specific password", isSecret: true),
    ]

    func testPromptShowsThePreparedRequestAndReturnsWhatWasSubmitted() async throws {
        let prompter = CredentialPrompter()
        let help = CredentialHelp(text: "Use an app-specific password.", linkTitle: "Create one", url: URL(string: "https://account.apple.com"))
        await prompter.prepare(title: "iCloud account", help: help, values: ["username": "me@icloud.test", "password": "never shown"], error: "Try again.")
        let answer = Task { try await prompter.prompt(fields) }
        try await waitUntil { prompter.request != nil }
        let request = try XCTUnwrap(prompter.request)
        XCTAssertEqual(request.title, "iCloud account")
        XCTAssertEqual(request.fields, fields)
        XCTAssertEqual(request.help, help)
        XCTAssertEqual(request.values, ["username": "me@icloud.test"])   // a secret is never prefilled
        XCTAssertEqual(request.error, "Try again.")
        prompter.submit(["username": "me@icloud.test", "password": "app-pass"])
        let values = try await answer.value
        XCTAssertEqual(values, ["username": "me@icloud.test", "password": "app-pass"])
        XCTAssertNil(prompter.request)
        XCTAssertEqual(prompter.submittedNonSecretValues, ["username": "me@icloud.test"])
        let reported = await prompter.lastNonSecretValues()
        XCTAssertEqual(reported, ["username": "me@icloud.test"])
    }

    func testCancelEndsThePromptWithCancellation() async throws {
        let prompter = CredentialPrompter()
        let answer = Task { try await prompter.prompt(fields) }
        try await waitUntil { prompter.request != nil }
        prompter.cancel()
        do {
            _ = try await answer.value
            XCTFail("expected a cancellation")
        } catch {
            XCTAssertEqual(error as? HostError, HostError.Cancelled)
        }
        XCTAssertNil(prompter.request)
        XCTAssertNil(prompter.submittedNonSecretValues)
    }

    func testCancellingTheWaitingTaskClosesTheSheet() async throws {
        let prompter = CredentialPrompter()
        let answer = Task { try await prompter.prompt(fields) }
        try await waitUntil { prompter.request != nil }
        answer.cancel()
        do {
            _ = try await answer.value
            XCTFail("expected a cancellation")
        } catch {
            XCTAssertEqual(error as? HostError, HostError.Cancelled)
        }
        try await waitUntil { prompter.request == nil }
    }

    func testPrepareForgetsTheLastSubmission() async throws {
        let prompter = CredentialPrompter()
        let answer = Task { try await prompter.prompt(fields) }
        try await waitUntil { prompter.request != nil }
        prompter.submit(["username": "a", "password": "b"])
        _ = try await answer.value
        let submitted = await prompter.lastNonSecretValues()
        XCTAssertNotNil(submitted)
        await prompter.prepare(title: "Again", help: nil)
        let afterPrepare = await prompter.lastNonSecretValues()
        XCTAssertNil(afterPrepare)
    }

    func testSignInNeedsEveryField() {
        XCTAssertFalse(CredentialSheet.isComplete(["username": "me"], fields: fields))
        XCTAssertFalse(CredentialSheet.isComplete(["username": "  ", "password": "p"], fields: fields))
        XCTAssertTrue(CredentialSheet.isComplete(["username": "me", "password": "p"], fields: fields))
    }
}
