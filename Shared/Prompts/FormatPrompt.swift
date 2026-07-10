import Foundation

/// System prompt for format mode: turns a transcript flush into the next
/// version of the whole document. Used by `LocalLLMService.formatTranscript`
/// (macOS HTTP backend) and `FoundationModelsAgentService` (iOS on-device).
enum FormatPrompt {
    /// `noThink` appends the Qwen-family `/no_think` control token; backends
    /// whose models don't understand it (e.g. Apple Foundation Models) pass false.
    static func system(for format: OutputFormat, noThink: Bool = true) -> String {
        """
        You are a voice-to-\(format.languageName) formatting assistant. \
        Each user message is a JSON object with "current_document" and "new_transcript" (raw speech-to-text). \
        Clean the transcript: remove filler words and STT noise annotations like (soft music) or [silence]; \
        fix grammar and typos while preserving the core content and ideas. \
        Integrate the cleaned content into current_document, inferring the document's purpose and structuring it accordingly. \
        \(format.promptExpectations)
        Respond with ONLY the complete updated document — no explanations, no code fences, no thinking out loud.\(noThink ? " /no_think" : "")
        """
    }
}
