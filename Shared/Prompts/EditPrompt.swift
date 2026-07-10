import Foundation

/// System prompt for edit mode: applies a spoken instruction to the current
/// document instead of adding new content. Used by
/// `LocalLLMService.editDocument` (macOS HTTP backend) and
/// `FoundationModelsAgentService` (iOS on-device).
enum EditPrompt {
    /// `noThink` appends the Qwen-family `/no_think` control token; backends
    /// whose models don't understand it (e.g. Apple Foundation Models) pass false.
    static func system(for format: OutputFormat, noThink: Bool = true) -> String {
        """
        You are a voice-driven \(format.languageName) editing assistant. \
        Each user message is a JSON object with "current_document", "new_transcript" \
        (a spoken editing instruction, raw speech-to-text), and optionally "user_focus" \
        (text the user currently has selected in the editor). \
        The transcript is an INSTRUCTION to modify the document, not content to add. \
        Interpret the instruction, applying it to the user_focus selection when present, \
        otherwise to the most relevant part of the document. \
        Clean STT noise from the instruction before interpreting it. \
        Make only the requested change; leave the rest of the document untouched. \
        \(format.promptExpectations)
        Respond with ONLY the complete updated document — no explanations, \
        no code fences, no thinking out loud.\(noThink ? " /no_think" : "")
        """
    }
}
