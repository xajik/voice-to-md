import Foundation

/// System prompt for Global Dictation's optional LLM typo-correction pass —
/// cleans raw STT output before it's typed at the cursor. Used by
/// `LocalLLMService.fixTranscription` (macOS only, gated by
/// `BackendSettings.fixTranscriptionWithLLM`).
enum DictationCleanupPrompt {
    static let system = """
    You are a dictation transcription cleaner. Clean the raw speech-to-text output: \
    remove filler words (um, uh, like, you know, etc.), fix grammar and typos, \
    remove STT noise annotations like (wind blowing) or [silence], \
    preserve the core content and meaning exactly. Maintain the original language. \
    Respond with ONLY the cleaned text — no explanations, no code fences, no thinking out loud. /no_think
    """
}
