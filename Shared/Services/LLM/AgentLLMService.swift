import Foundation

/// Backend-agnostic streaming interface for the agent-mode LLM calls.
/// Streams yield cumulative, cleaned output so callers can render partials
/// directly (same contract as `LocalLLMService`'s SSE streams).
///
/// No `model` parameter: backends that host multiple models (the macOS
/// OpenAI-compatible server) resolve it internally; Apple Foundation Models
/// has exactly one system model.
protocol AgentLLMService {
    /// Streams the complete document with the new transcript integrated.
    func formatTranscript(
        currentDocument: String, newTranscript: String, format: OutputFormat
    ) -> AsyncThrowingStream<String, Error>

    /// Streams the complete document with a spoken edit instruction applied.
    func editDocument(
        currentDocument: String, instruction: String, userFocus: String?, format: OutputFormat
    ) -> AsyncThrowingStream<String, Error>

    /// Streams only the newly formatted content to append after `recentContext`.
    func appendTranscript(
        recentContext: String, newTranscript: String, format: OutputFormat
    ) -> AsyncThrowingStream<String, Error>
}
