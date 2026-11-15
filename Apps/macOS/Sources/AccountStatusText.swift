import TimeTugKit

enum AccountStatusText {
    static func make(_ status: SourceStatus?) -> String {
        switch status {
        case .ok?: "Connected"
        case .authExpired?: "Sign in again"
        case .needsPermission?: "Calendar access is off"
        case .failing?: "Can't reach this calendar right now"
        case nil: "Connecting…"
        // A status a later engine version adds: the safe words are the generic failure.
        @unknown default: "Can't reach this calendar right now"
        }
    }
}
