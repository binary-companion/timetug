#if canImport(FoundationModels)
import Foundation
import FoundationModels
import TimeTugEngine

/// The model's answer, constrained to the three words the engine's answer parser accepts.
@available(macOS 26.0, *)
@Generable
struct DuplicateJudgement {
    @Guide(description: "same if both entries are one real-world appointment, different if they are separate, unsure if you cannot tell",
           .anyOf(["same", "different", "unsure"]))
    var answer: String
}

/// Apple's on-device model behind the engine's `TextGenerator` seam: one fresh session per request, temperature 0,
/// guided to a one-word answer. The engine builds the prompt and parses the answer.
@available(macOS 26.0, *)
struct AppleTextGenerator: TextGenerator {
    var availability: TextGeneratorAvailability {
        Self.availability(for: SystemLanguageModel.default.availability)
    }

    /// The energy-saver case does not exist on the Mac, so nothing is reported as temporarily unavailable.
    static func availability(for model: SystemLanguageModel.Availability) -> TextGeneratorAvailability {
        switch model {
        case .available: .available(AppleIntelligence.engine)
        case .unavailable(let reason): .unavailable(reason: String(describing: reason))
        }
    }

    func generate(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: prompt, generating: DuplicateJudgement.self, options: GenerationOptions(temperature: 0))
        return response.content.answer
    }
}
#endif
