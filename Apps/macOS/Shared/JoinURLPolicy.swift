import Foundation

/// Schemes a widget may open from calendar-supplied meeting data. A copy of the engine's join-URL policy (the widget
/// extension links no engine); `JoinURLPolicyParityTests` checks the two agree.
enum JoinURLPolicy {
    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil else { return false }
        switch scheme {
        case "http", "https": return true
        case "zoommtg":
            return host == "zoom.us" || host == "zoom.com" ||
                host.hasSuffix(".zoom.us") || host.hasSuffix(".zoom.com")
        default: return false
        }
    }
}
