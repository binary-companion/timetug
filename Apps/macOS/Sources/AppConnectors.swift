import Foundation
import TimeTugKit

/// What the engine is told about this build. Connector kinds are no longer registered by the host: the engine owns
/// them, and the config turns the optional ones on. A kind whose client is absent (a build without an OAuth client id)
/// is listed by the engine as unconfigured, as the Accounts pane always showed it.
enum AppConnectors {
    /// Days of an iCal link kept before today and after it (unchanged from the Swift engine).
    static let icalDaysBack: UInt32 = 3
    static let icalDaysAhead: UInt32 = 7

    static func makeConfig(
        dataDirectory: URL, google: GoogleClient?, microsoft: MicrosoftClient?, textGeneration: Bool,
        timeZone: String = TimeZone.current.identifier
    ) -> EngineConfig {
        EngineConfig(
            dataDirectory: dataDirectory.path, platform: .macos, googleClient: google, microsoftClient: microsoft,
            textGeneration: textGeneration, externalTokens: false, systemCalendar: true, timeZone: timeZone,
            icalDaysBack: icalDaysBack, icalDaysAhead: icalDaysAhead)
    }
}
