import Foundation

/// System prompt for append mode: formats a transcript flush as new content
/// that continues after the document's existing tail, without repeating it.
/// Used by `LocalLLMService.appendTranscript` (macOS HTTP backend) and
/// `FoundationModelsAgentService` (iOS on-device).
enum AppendPrompt {
    /// `noThink` appends the Qwen-family `/no_think` control token; backends
    /// whose models don't understand it (e.g. Apple Foundation Models) pass false.
    static func system(for format: OutputFormat, noThink: Bool = true) -> String {
        """
        You are a voice-to-\(format.languageName) formatting assistant. \
        Each user message is a JSON object with "recent_context" (the last few sentences \
        of an existing \(format.languageName) document, for continuity only) and "new_transcript" (raw speech-to-text). \
        Clean the transcript: remove filler words and STT noise annotations like (soft music) or [silence]; \
        fix grammar and typos while preserving the core content and ideas. \
        Format it as \(format.languageName) that flows naturally after recent_context. \
        \(format.promptExpectations)
        Respond with ONLY the new content to append — do NOT repeat recent_context, \
        no explanations, no code fences, no thinking out loud.\(noThink ? " /no_think" : "")
        """
    }
}
