import Foundation

/// How Agent Mode interprets incoming voice input.
enum AgentMode: String, CaseIterable, Equatable {
    /// Integrate new content into the whole document (default).
    case format
    /// Treat input as an instruction to modify the document.
    case edit
    /// Format only the new input and append it to the document.
    case append

    var displayName: String {
        switch self {
        case .format: return "Format"
        case .edit: return "Edit"
        case .append: return "Append"
        }
    }

    var iconName: String {
        switch self {
        case .format: return "doc.text"
        case .edit: return "pencil"
        case .append: return "plus"
        }
    }
}
