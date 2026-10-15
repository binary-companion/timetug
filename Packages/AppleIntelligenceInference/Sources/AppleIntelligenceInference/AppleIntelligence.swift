import Foundation
import TimeTugCore
import TimeTugEngine

/// The one entry point the app calls. The prompt, the answer parsing and the adjudication live in `TimeTugEngine`;
/// this package only gives the engine Apple's on-device model as a `TextGenerator`.
public enum AppleIntelligence {
    public static let engine = EngineInfo(id: "apple-intelligence", displayName: "Apple Intelligence", isOnDevice: true)

    /// nil when this SDK or OS has no on-device Apple model API. A non-nil generator can still report
    /// `.unavailable` (Apple Intelligence off, unsupported hardware, model not ready).
    public static func makeTextGenerator() -> (any TextGenerator)? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return AppleTextGenerator() }
        #endif
        return nil
    }
}
