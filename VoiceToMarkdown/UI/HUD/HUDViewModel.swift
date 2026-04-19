import Foundation
import SwiftUI

@MainActor
final class HUDViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var agentName = ""
    @Published var selectedModel: ModelSize = .base

    private let coordinator: SessionCoordinator

    var sessionState: SessionState { coordinator.session?.state ?? .idle }
    var transcript: String { coordinator.transcript }
    var errorMessage: String? { coordinator.error }

    init(coordinator: SessionCoordinator) {
        self.coordinator = coordinator
    }

    func startSession() {
        Task {
            await coordinator.startSession(agentName: agentName.isEmpty ? "claude" : agentName, modelSize: selectedModel)
        }
    }

    func startRecording() {
        coordinator.startRecording()
    }

    func pauseRecording() {
        coordinator.pauseRecording()
    }

    func stopSession() {
        Task { await coordinator.stopSession() }
    }

    func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(coordinator.transcript, forType: .string)
    }

    func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(coordinator.markdown, forType: .string)
    }
}
