import Combine
import Foundation
import SwiftUI

@MainActor
final class HUDViewModel: ObservableObject {
    private let coordinator: SessionCoordinator
    private var cancellables = Set<AnyCancellable>()
    @Published var sessions: [SessionListing] = []

    var sessionState: SessionState {
        if coordinator.isProcessing { return .processing }
        return coordinator.session?.state ?? .idle
    }
    /// Raw recording state, ignoring in-flight LLM processing. Recording and
    /// processing run in parallel, so the mic control keys off this while the
    /// status label shows `sessionState`.
    var recordingState: SessionState {
        coordinator.session?.state ?? .idle
    }
    var transcript: String { coordinator.transcript }
    var errorMessage: String? { coordinator.error }
    var mode: AgentMode {
        get { coordinator.mode }
        set { coordinator.mode = newValue }
    }
    var outputFormat: OutputFormat {
        get { coordinator.outputFormat }
        set { coordinator.outputFormat = newValue }
    }
    var canSend: Bool {
        coordinator.session?.state == .recording && !coordinator.isProcessing
    }
    var canPreview: Bool {
        coordinator.session != nil
    }
    var isSpeaking: Bool { coordinator.isSpeaking }
    var canSpeak: Bool {
        SpeechSynthesisService.textToSpeak(
            selection: coordinator.editorSelection,
            document: coordinator.markdown
        ) != nil
    }

    init(coordinator: SessionCoordinator) {
        self.coordinator = coordinator
        // Re-render when the coordinator's published state changes; the
        // computed properties above read straight from the coordinator.
        // Both objects are @MainActor, so no queue hop is needed.
        coordinator.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func startSession() {
        guard let size = BackendSettings.shared.resolvedWhisperModel() else {
            coordinator.error = "No Whisper model downloaded. Pick one in Settings."
            return
        }
        Task {
            await coordinator.startSession(modelSize: size)
        }
    }

    func newSession() {
        guard let size = BackendSettings.shared.resolvedWhisperModel() else {
            coordinator.error = "No Whisper model downloaded. Pick one in Settings."
            return
        }
        Task {
            await coordinator.startNewSession(modelSize: size)
        }
    }

    func startRecording() {
        coordinator.startRecording()
    }

    func sendNow() {
        coordinator.flushNow()
    }

    func pauseRecording() {
        coordinator.pauseRecording()
    }

    func stopSession() {
        Task { await coordinator.stopSession() }
    }

    func resetSession() {
        Task { await coordinator.resetSession() }
    }

    func openPreview() {
        coordinator.openPreview()
    }

    func toggleSpeech() {
        coordinator.toggleSpeech()
    }

    func refreshSessions() {
        sessions = STMDFileManager.shared.listSessions()
    }

    func restoreSession(_ listing: SessionListing) {
        Task { await coordinator.restoreSession(listing) }
    }
}
