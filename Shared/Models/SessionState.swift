import Foundation

enum SessionState: String, Equatable {
    case idle
    case initializing
    case recording
    case processing
    case paused

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .initializing: return "Starting..."
        case .recording: return "Recording"
        case .processing: return "Processing"
        case .paused: return "Paused"
        }
    }

    var isActive: Bool {
        switch self {
        case .recording, .processing, .paused: return true
        default: return false
        }
    }

    var canRecord: Bool {
        self == .paused
    }

    var canPause: Bool {
        self == .recording
    }

    var canStop: Bool {
        isActive
    }
}
