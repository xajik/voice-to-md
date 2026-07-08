import AVFoundation
import Carbon
import Foundation

enum DictationPhase {
    case idle
    case listening
    case transcribing
}

@MainActor
final class GlobalDictationManager: ObservableObject {
    @Published var lastError: String?
    @Published var phase: DictationPhase = .idle
    @Published var level: Float = 0

    private let hotkey = HotkeyMonitor()
    private let audio = AudioCaptureService()
    private var whisper: WhisperService?
    private var audioBuffers: [AVAudioPCMBuffer] = []

    private let defaultKeyCode: UInt32 = 0x1E // kVK_ANSI_RightBracket ']'
    private let defaultModifiers: UInt32 = UInt32(cmdKey | optionKey)

    func start(modelPath: URL) throws {
        whisper = WhisperService(modelPath: modelPath)
        audio.delegate = self
        audio.onLevel = { [weak self] rms in
            Task { @MainActor in self?.level = rms }
        }

        try hotkey.register(keyCode: defaultKeyCode, modifiers: defaultModifiers) { [weak self] in
            Task { @MainActor in self?.toggleRecording() }
        }
        vtmdLog("DICTATION", "Started with model \(modelPath.lastPathComponent)")
    }

    func stop() {
        hotkey.unregister()
        if phase == .listening { stopRecording() }
        phase = .idle
        vtmdLog("DICTATION", "Stopped")
    }

    /// Mouse-driven stop from the floating panel; same effect as the hotkey.
    func requestStop() {
        if phase == .listening { stopRecording() }
    }

    private func toggleRecording() {
        if phase == .listening {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        audioBuffers = []
        Task { @MainActor in
            guard await AudioCaptureService.requestPermission() else {
                vtmdLog("DICTATION", "Microphone permission denied")
                lastError = "Microphone access denied"
                phase = .idle
                return
            }
            do {
                try audio.start()
                phase = .listening
                vtmdLog("DICTATION", "Recording started")
            } catch {
                vtmdLog("DICTATION", "Recording start error: \(error.localizedDescription)")
                lastError = error.localizedDescription
                phase = .idle
            }
        }
    }

    private func stopRecording() {
        audio.stop()
        level = 0
        phase = .transcribing
        vtmdLog("DICTATION", "Recording stopped, \(audioBuffers.count) buffers captured")
        let captured = audioBuffers
        audioBuffers = []
        Task {
            await transcribeAndInject(buffers: captured)
            await MainActor.run { phase = .idle }
        }
    }

    private func transcribeAndInject(buffers: [AVAudioPCMBuffer]) async {
        guard let whisper, !buffers.isEmpty else { return }

        do {
            let tmpDir = FileManager.default.temporaryDirectory
            let wavURL = tmpDir.appendingPathComponent("vtmd_dictation.wav")
            try AudioConverter.writePCMBuffersToWAV(buffers, to: wavURL)

            if let text = try await whisper.transcribe(wavFile: wavURL) {
                vtmdLog("DICTATION", "Transcribed: \(text)")
                if KeystrokeInjector.hasAccessibilityPermission {
                    // Off-main: waits for hotkey modifiers to be released, then types
                    KeystrokeInjector.typeText(text + " ")
                    vtmdLog("DICTATION", "Injected \(text.count) chars")
                } else {
                    vtmdLog("DICTATION", "Accessibility permission missing — text not injected")
                    await MainActor.run {
                        lastError = "Accessibility permission required. Enable VoiceToMarkdown in System Settings → Privacy & Security → Accessibility."
                    }
                }
            }
            try? FileManager.default.removeItem(at: wavURL)
        } catch {
            vtmdLog("DICTATION", "Transcription error: \(error.localizedDescription)")
            await MainActor.run { lastError = error.localizedDescription }
        }
    }
}

extension GlobalDictationManager: AudioCaptureDelegate {
    nonisolated func audioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer) {
        Task { @MainActor in audioBuffers.append(buffer) }
    }

    nonisolated func audioCaptureDidDetectSilence() {
        Task { @MainActor in
            if phase == .listening { stopRecording() }
        }
    }

    nonisolated func audioCaptureDidFail(_ error: Error) {
        Task { @MainActor in lastError = error.localizedDescription }
    }
}
