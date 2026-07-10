import AVFoundation
import Foundation
import Speech

/// On-device streaming STT: composes the shared `AudioCaptureService`
/// (mic tap, RMS levels, 5 s silence signal) with iOS 26's SpeechAnalyzer.
///
/// Only **finalized** results reach `onFinalResult` — volatile results are
/// surfaced separately for live UI and must never enter the transcript buffer.
/// `pause()`/`stop()` tear the pipeline down completely (finalizing trailing
/// words on the way out); each `start()` builds a fresh analyzer.
final class SpeechTranscriptionService {
    /// Awaited by the results loop so results are applied in order — a
    /// finalized result is fully handled before the next one is read.
    var onFinalResult: ((String) async -> Void)?
    var onVolatileResult: ((String) async -> Void)?
    var onSilence: (() -> Void)?
    var onError: ((Error) -> Void)?
    /// Audio tap thread, ~12 Hz — forward of `AudioCaptureService.onLevel`.
    var onLevel: ((Float) -> Void)?

    private var audioService: AudioCaptureService?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    /// Resolved by `ensureAssets`; regional variants without their own model
    /// (e.g. en_SG) fall back to a same-language supported locale.
    private var resolvedLocale: Locale?

    var isRunning: Bool { audioService?.isRunning ?? false }

    /// Picks the transcription locale (exact match, else same language) and
    /// downloads its recognition model if not installed (network required on
    /// first run).
    func ensureAssets(preferring preferred: Locale = .current) async throws {
        let supported = await SpeechTranscriber.supportedLocales
        vtmdLog("STT", "Preferred locale: \(preferred.identifier(.bcp47)); supported: \(supported.map { $0.identifier(.bcp47) }.joined(separator: ", "))")
        guard !supported.isEmpty else {
            throw SpeechTranscriptionError.transcriptionUnavailable
        }
        guard let locale = Self.bestSupportedLocale(for: preferred, in: supported) else {
            throw SpeechTranscriptionError.localeNotSupported(preferred.identifier)
        }
        if locale.identifier(.bcp47) != preferred.identifier(.bcp47) {
            vtmdLog("STT", "Locale \(preferred.identifier) unsupported; falling back to \(locale.identifier(.bcp47))")
        }
        resolvedLocale = locale

        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) { return }

        let probe = SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: []
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
            try await request.downloadAndInstall()
        }
    }

    /// Exact BCP-47 match first, then any supported locale sharing the
    /// language code (en_SG → en-US), else nil.
    static func bestSupportedLocale(for preferred: Locale, in supported: [Locale]) -> Locale? {
        let target = preferred.identifier(.bcp47)
        if let exact = supported.first(where: { $0.identifier(.bcp47) == target }) {
            return exact
        }
        guard let language = preferred.language.languageCode?.identifier else { return nil }
        return supported.first(where: { $0.language.languageCode?.identifier == language })
    }

    func start() async throws {
        guard analyzer == nil else { return }
        guard let locale = resolvedLocale else {
            throw SpeechTranscriptionError.localeNotSupported(Locale.current.identifier)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechTranscriptionError.noCompatibleAudioFormat
        }

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        let audioService = AudioCaptureService(outputFormat: format)
        audioService.delegate = self
        audioService.onLevel = { [weak self] level in self?.onLevel?(level) }

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.inputBuilder = inputBuilder
        self.audioService = audioService

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    if result.isFinal {
                        await self?.onFinalResult?(text)
                    } else {
                        await self?.onVolatileResult?(text)
                    }
                }
            } catch {
                self?.onError?(error)
            }
        }

        try await analyzer.start(inputSequence: inputSequence)
        try audioService.start()
    }

    /// Forces any pending volatile hypothesis to become final right now,
    /// without ending the session — recording keeps running afterward.
    /// Used before a manual Send and after a silence timeout, since short
    /// utterances otherwise sit as volatile text and never reach the
    /// transcript buffer (only finalized results do).
    func finalizeNow() async {
        guard let analyzer else { return }
        do {
            try await analyzer.finalize(through: nil)
        } catch {
            vtmdLog("STT", "finalize(through:) failed: \(error.localizedDescription)")
        }
    }

    /// Stops capture and finalizes pending audio so trailing words still
    /// arrive via `onFinalResult` before this returns.
    func stop() async {
        audioService?.stop()
        audioService = nil
        inputBuilder?.finish()
        inputBuilder = nil
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        analyzer = nil
        transcriber = nil
        await resultsTask?.value
        resultsTask = nil
    }
}

extension SpeechTranscriptionService: AudioCaptureDelegate {
    func audioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer) {
        inputBuilder?.yield(AnalyzerInput(buffer: buffer))
    }

    func audioCaptureDidDetectSilence() {
        onSilence?()
    }

    func audioCaptureDidFail(_ error: Error) {
        onError?(error)
    }
}

enum SpeechTranscriptionError: Error, LocalizedError {
    case localeNotSupported(String)
    case noCompatibleAudioFormat
    case transcriptionUnavailable

    var errorDescription: String? {
        switch self {
        case .localeNotSupported(let identifier):
            return "On-device transcription doesn't support the \(identifier) locale."
        case .noCompatibleAudioFormat:
            return "No compatible audio format for on-device transcription."
        case .transcriptionUnavailable:
            return "On-device transcription isn't available on this device (no speech models)."
        }
    }
}
