import Foundation
import Testing
import TimeTugEngine
@testable import AppleIntelligenceInference
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The real model is never called here: only the availability mapping and the factory are checked.
struct AppleTextGeneratorTests {
    @Test func theEngineInfoIsTheOneTheAppHasAlwaysReported() {
        #expect(AppleIntelligence.engine.id == "apple-intelligence")
        #expect(AppleIntelligence.engine.displayName == "Apple Intelligence")
        #expect(AppleIntelligence.engine.isOnDevice)
    }

    @Test func aGeneratorExistsExactlyWhenTheOSHasTheModelAPI() {
        let generator = AppleIntelligence.makeTextGenerator()
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { #expect(generator != nil) } else { #expect(generator == nil) }
        #else
        #expect(generator == nil)
        #endif
    }

    #if canImport(FoundationModels)
    @Test func availableMapsToTheAppleEngine() {
        guard #available(macOS 26.0, *) else { return }
        #expect(AppleTextGenerator.availability(for: .available) == .available(AppleIntelligence.engine))
    }

    @Test func unavailableKeepsTheReasonAndIsNeverTemporary() {
        guard #available(macOS 26.0, *) else { return }
        let reason = SystemLanguageModel.Availability.UnavailableReason.deviceNotEligible
        #expect(AppleTextGenerator.availability(for: .unavailable(reason))
            == .unavailable(reason: String(describing: reason)))
    }
    #endif
}
