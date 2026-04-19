import AVFoundation
import Carbon
import Foundation

@MainActor
final class GlobalDictationManager: ObservableObject {
    @Published var isRecording = false
    @Published var lastError: String?

    private let hotkey = HotkeyMonitor()
    private let audio = AudioCaptureService()
    private var whisper: WhisperService?
    private var audioBuffers: [AVAudioPCMBuffer] = []

    private let defaultKeyCode: UInt32 = 0x23 // ']' key
    private let defaultModifiers: UInt32 = UInt32(cmdKey | optionKey)

    func start(modelPath: URL) throws {
        whisper = WhisperService(modelPath: modelPath)
        audio.delegate = self

        try hotkey.register(keyCode: defaultKeyCode, modifiers: defaultModifiers) { [weak self] in
            Task { @MainActor in self?.toggleRecording() }
        }
        vtmdLog("DICTATION", "Started with model \(modelPath.lastPathComponent)")
    }

    func stop() {
        hotkey.unregister()
        if isRecording { stopRecording() }
        vtmdLog("DICTATION", "Stopped")
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        audioBuffers = []
        do {
            try audio.start()
            isRecording = true
            vtmdLog("DICTATION", "Recording started")
        } catch {
            vtmdLog("DICTATION", "Recording start error: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    private func stopRecording() {
        audio.stop()
        isRecording = false
        vtmdLog("DICTATION", "Recording stopped, \(audioBuffers.count) buffers captured")
        let captured = audioBuffers
        audioBuffers = []
        Task { await transcribeAndInject(buffers: captured) }
    }

    private func transcribeAndInject(buffers: [AVAudioPCMBuffer]) async {
        guard let whisper, !buffers.isEmpty else { return }

        do {
            let tmpDir = FileManager.default.temporaryDirectory
            let wavURL = tmpDir.appendingPathComponent("vtmd_dictation.wav")
            try AudioConverter.writePCMBuffersToWAV(buffers, to: wavURL)

            if let text = try await whisper.transcribe(wavFile: wavURL) {
                vtmdLog("DICTATION", "Transcribed: \(text)")
                await MainActor.run { KeystrokeInjector.typeText(text + " ") }
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
            if isRecording { stopRecording() }
        }
    }

    nonisolated func audioCaptureDidFail(_ error: Error) {
        Task { @MainActor in lastError = error.localizedDescription }
    }
}
