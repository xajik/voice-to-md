import AVFoundation
import Foundation

/// Native macOS text-to-speech (AVSpeechSynthesizer, system default voice).
/// Reads a single utterance at a time; starting a new one cancels the current.
@MainActor
final class SpeechSynthesisService: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private(set) var isSpeaking = false
    /// Fires when speech ends, whether it finished naturally or was stopped.
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Selection wins over the document; empty (after trimming) means nothing to read.
    nonisolated static func textToSpeak(selection: String?, document: String) -> String? {
        let text = selection ?? document
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        currentUtterance = utterance
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    // A superseded utterance's didCancel arrives async — only the current
    // utterance may flip state, or a rapid stop→speak would end the new one.
    private func speechDidEnd(_ utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else { return }
        currentUtterance = nil
        isSpeaking = false
        onFinish?()
    }
}

extension SpeechSynthesisService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speechDidEnd(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speechDidEnd(utterance) }
    }
}
