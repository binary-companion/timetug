import Foundation
import TimeTugKit

/// The host's HTTP for the engine: one ephemeral `URLSession` that sends what it is given and returns what comes back.
///
/// The obligations are in `docs/host-http-contract.md` of calendar-connectors:
/// - any HTTP answer, including 4xx and 5xx, is a response; only a transport failure throws (`HostError.Network`), and a
///   cancelled request throws `HostError.Cancelled`;
/// - no URL cache, no cookies, nothing on disk (the feed link and the bearer tokens are credentials);
/// - redirects are **not** followed: the 3xx answer is the response, so the library checks where it points before it
///   sends credentials there;
/// - method, headers, body and address go through unchanged (no `Prefer` merging, no query re-encoding), and nothing
///   about a request is logged or put into an error.
public final class URLSessionHTTPTransport: HttpTransport, Sendable {
    /// `HttpRequest` carries no timeout, so the session sets finite ones: 60 seconds without data, five minutes for a
    /// whole response (calendar feeds can be large).
    static var sessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        return configuration
    }

    private let session: URLSession

    public convenience init() {
        self.init(configuration: Self.sessionConfiguration)
    }

    init(configuration: URLSessionConfiguration) {
        session = URLSession(configuration: configuration, delegate: RedirectRefusingDelegate(), delegateQueue: nil)
    }

    deinit { session.finishTasksAndInvalidate() }

    public func send(request: HttpRequest) async throws -> HttpResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw HostError.Network(detail: "not an HTTP response") }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields { headers["\(key)"] = "\(value)" }
            return HttpResponse(status: Int64(http.statusCode), headers: headers, body: data)
        } catch is CancellationError {
            throw HostError.Cancelled
        } catch let error as URLError {
            if error.code == .cancelled { throw HostError.Cancelled }
            // `localizedDescription` names no address; the failing URL stays in `userInfo`, which is not passed on.
            throw HostError.Network(detail: error.localizedDescription)
        }
    }
}

/// Declines every redirect, so the task finishes with the 3xx response.
private final class RedirectRefusingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
