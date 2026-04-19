import Foundation

enum SessionState: String, Equatable {
    case idle
    case initializing
    case ready
    case recording
    case processing
    case paused
    case stopped

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .initializing: return "Initializing..."
        case .ready: return "Ready"
        case .recording: return "Recording"
        case .processing: return "Processing"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        }
    }

    var isActive: Bool {
        switch self {
        case .recording, .processing, .paused: return true
        default: return false
        }
    }

    var canRecord: Bool {
        self == .ready || self == .paused
    }

    var canPause: Bool {
        self == .recording
    }

    var canStop: Bool {
        isActive || self == .ready
    }
}
