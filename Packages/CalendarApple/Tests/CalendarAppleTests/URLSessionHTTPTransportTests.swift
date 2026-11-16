import Foundation
import Testing
import TimeTugKit
@testable import CalendarApple

/// Answers `/start` on `redirect.test` with a 302 to `/end` and anything else with 200 "arrived".
final class RedirectingProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "redirect.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        if url.path == "/start" {
            let target = URL(string: "https://redirect.test/end")!
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            // A client that declines the redirect gets this response as the task's result.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("arrived".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

/// Records the last request it saw and answers per the host name: `ok.test` 200 (with a `Retry-After` header and the
/// body "ok"), `teapot.test` 418, `offline.test` a connection failure, `cancel.test` a cancelled request.
final class RecordingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?
    private static let lock = NSLock()
    override class func canInit(with request: URLRequest) -> Bool {
        ["ok.test", "teapot.test", "offline.test", "cancel.test"].contains(request.url?.host ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                collected.append(buffer, count: count)
            }
            body = collected
        }
        Self.lock.withLock { Self.lastRequest = request; Self.lastBody = body }
        let url = request.url!
        switch url.host {
        case "offline.test": client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case "cancel.test": client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
        default:
            let status = url.host == "teapot.test" ? 418 : 200
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Retry-After": "7", "ETag": "\"abc\""])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("ok".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private func transport(_ protocolClass: AnyClass) -> URLSessionHTTPTransport {
    let configuration = URLSessionHTTPTransport.sessionConfiguration
    configuration.protocolClasses = [protocolClass]
    return URLSessionHTTPTransport(configuration: configuration)
}

private func header(_ response: HttpResponse, _ name: String) -> String? {
    response.headers.first { $0.key.lowercased() == name.lowercased() }?.value
}

@Suite(.serialized) struct URLSessionHTTPTransportTests {
    @Test func theSessionKeepsNoCacheAndNoCookiesAndNothingOnDisk() {
        let configuration = URLSessionHTTPTransport.sessionConfiguration
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.timeoutIntervalForRequest.isFinite)
        #expect(configuration.timeoutIntervalForResource < 7 * 24 * 3600)
    }

    @Test func aRequestIgnoresTheLocalCache() async throws {
        _ = try await transport(RecordingProtocol.self)
            .send(request: HttpRequest(url: URL(string: "https://ok.test/a")!, method: "GET", headers: [:], body: nil))
        #expect(RecordingProtocol.lastRequest?.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func doesNotFollowRedirects() async throws {
        let response = try await transport(RedirectingProtocol.self)
            .send(request: HttpRequest(url: URL(string: "https://redirect.test/start")!, method: "GET", headers: [:], body: nil))
        #expect(response.status == 302)
        #expect(header(response, "location") == "https://redirect.test/end")
    }

    @Test func aFollowedTargetIsStillReachableByAnExplicitRequest() async throws {
        let response = try await transport(RedirectingProtocol.self)
            .send(request: HttpRequest(url: URL(string: "https://redirect.test/end")!, method: "GET", headers: [:], body: nil))
        #expect(response.status == 200)
        #expect(String(decoding: response.body, as: UTF8.self) == "arrived")
    }

    @Test func clientErrorsAreOrdinaryResponsesWithTheirHeaders() async throws {
        let response = try await transport(RecordingProtocol.self)
            .send(request: HttpRequest(url: URL(string: "https://teapot.test/x")!, method: "GET", headers: [:], body: nil))
        #expect(response.status == 418)
        #expect(header(response, "retry-after") == "7")
        #expect(header(response, "etag") == "\"abc\"")
    }

    @Test func passesMethodHeadersBodyAndAddressThroughUnchanged() async throws {
        let url = URL(string: "https://ok.test/v1.0/me/calendarView/delta?$select=id,start&$top=50&startDateTime=2026-11-01T00:00:00Z")!
        let prefer = #"IdType="ImmutableId", outlook.timezone="Pacific Standard Time", outlook.body-content-type="text""#
        let body = Data("grant_type=refresh_token&code=a%2Bb".utf8)
        _ = try await transport(RecordingProtocol.self).send(request: HttpRequest(
            url: url, method: "PROPFIND",
            headers: ["Prefer": prefer, "Authorization": "Bearer t0k", "Depth": "1", "If-Match": "W/\"1\""], body: body))
        let seen = try #require(RecordingProtocol.lastRequest)
        #expect(seen.httpMethod == "PROPFIND")
        #expect(seen.url?.absoluteString == url.absoluteString)
        #expect(seen.value(forHTTPHeaderField: "Prefer") == prefer)
        #expect(seen.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
        #expect(seen.value(forHTTPHeaderField: "Depth") == "1")
        #expect(seen.value(forHTTPHeaderField: "If-Match") == "W/\"1\"")
        #expect(RecordingProtocol.lastBody == body)
    }

    @Test func aCancelledRequestIsHostErrorCancelled() async throws {
        await #expect(throws: HostError.Cancelled) {
            _ = try await transport(RecordingProtocol.self)
                .send(request: HttpRequest(url: URL(string: "https://cancel.test/")!, method: "GET", headers: [:], body: nil))
        }
    }

    @Test func aTaskCancelledBeforeTheRequestIsHostErrorCancelled() async throws {
        let transport = transport(RecordingProtocol.self)
        let task = Task {
            try await transport.send(request: HttpRequest(url: URL(string: "https://ok.test/")!, method: "GET", headers: [:], body: nil))
        }
        task.cancel()
        do { _ = try await task.value } catch let error as HostError { #expect(error == .Cancelled) }
    }

    @Test func aTransportFailureIsHostErrorNetwork() async throws {
        do {
            _ = try await transport(RecordingProtocol.self)
                .send(request: HttpRequest(url: URL(string: "https://offline.test/secret-path?token=abc")!, method: "GET", headers: [:], body: nil))
            Issue.record("expected a failure")
        } catch let error as HostError {
            guard case .Network(let detail) = error else { Issue.record("expected Network, got \(error)"); return }
            #expect(!detail.contains("secret-path") && !detail.contains("token=abc"))
        }
    }
}
