import Foundation

/// Output format for agent-mode documents: drives the system prompt, the HUD
/// dropdown, and the session file extension. Prompt expectations for each
/// case live in `Shared/Prompts/OutputFormat+PromptExpectations.swift`.
enum OutputFormat: String, CaseIterable, Equatable {
    case txt
    case md
    case html

    var displayName: String {
        switch self {
        case .txt: return "Plain Text"
        case .md: return "Markdown"
        case .html: return "HTML"
        }
    }

    var fileExtension: String { rawValue }

    /// Used inside prompt sentences ("voice-to-… formatting assistant").
    var languageName: String {
        switch self {
        case .txt: return "plain text"
        case .md: return "markdown"
        case .html: return "HTML"
        }
    }
}
