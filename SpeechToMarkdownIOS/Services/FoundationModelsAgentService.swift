import Foundation
import FoundationModels

/// Agent-mode LLM backend on Apple's on-device Foundation Models.
///
/// A fresh `LanguageModelSession` is created per request: sessions accumulate
/// their transcript into the context window, and every agent flush is already
/// self-contained (the payload carries the current document), so one-shot
/// sessions keep token usage bounded to instructions + prompt + response.
final class FoundationModelsAgentService: AgentLLMService {

    static var availability: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    /// Loads model resources ahead of the first flush to cut its latency.
    func prewarm(format: OutputFormat) {
        LanguageModelSession(instructions: FormatPrompt.system(for: format, noThink: false))
            .prewarm()
    }

    func formatTranscript(
        currentDocument: String, newTranscript: String, format: OutputFormat
    ) -> AsyncThrowingStream<String, Error> {
        stream(
            instructions: FormatPrompt.system(for: format, noThink: false),
            prompt: LocalLLMService.formatUserPayload(
                currentDocument: currentDocument, newTranscript: newTranscript
            )
        )
    }

    func editDocument(
        currentDocument: String, instruction: String, userFocus: String?, format: OutputFormat
    ) -> AsyncThrowingStream<String, Error> {
        stream(
            instructions: EditPrompt.system(for: format, noThink: false),
            prompt: LocalLLMService.editUserPayload(
                currentDocument: currentDocument, instruction: instruction, userFocus: userFocus
            )
        )
    }

    func appendTranscript(
        recentContext: String, newTranscript: String, format: OutputFormat
    ) -> AsyncThrowingStream<String, Error> {
        stream(
            instructions: AppendPrompt.system(for: format, noThink: false),
            prompt: LocalLLMService.appendUserPayload(
                recentContext: recentContext, newTranscript: newTranscript
            )
        )
    }

    /// Yields cumulative, cleaned output — the same contract as the macOS SSE
    /// streams, so orchestrator code can render partials directly.
    private func stream(instructions: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let responseStream = session.streamResponse(
                        to: prompt,
                        options: GenerationOptions(temperature: 0.2)
                    )
                    var latest = ""
                    for try await snapshot in responseStream {
                        try Task.checkCancellation()
                        latest = LocalLLMService.cleanOutput(snapshot.content)
                        continuation.yield(latest)
                    }
                    continuation.yield(latest)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.friendlyError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func friendlyError(_ error: Error) -> Error {
        guard let generationError = error as? LanguageModelSession.GenerationError else { return error }
        switch generationError {
        case .exceededContextWindowSize:
            return FoundationModelsError.documentTooLarge
        case .guardrailViolation:
            return FoundationModelsError.guardrailViolation
        default:
            return error
        }
    }
}

enum FoundationModelsError: Error, LocalizedError {
    case documentTooLarge
    case guardrailViolation

    var errorDescription: String? {
        switch self {
        case .documentTooLarge:
            return "Document too large for the on-device model — switch to Append mode."
        case .guardrailViolation:
            return "The on-device model declined this content (safety guardrails)."
        }
    }
}
