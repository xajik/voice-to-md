import AVFoundation
import Foundation

protocol AudioCaptureDelegate: AnyObject {
    func audioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer)
    func audioCaptureDidDetectSilence()
    func audioCaptureDidFail(_ error: Error)
}

final class AudioCaptureService {
    weak var delegate: AudioCaptureDelegate?
    /// Called on the audio tap thread with the RMS level of each buffer (~12 Hz).
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat

    /// Defaults to 16 kHz mono (whisper's input format); iOS callers pass the
    /// speech transcriber's preferred format instead.
    init(outputFormat: AVAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!) {
        self.format = outputFormat
    }
    private var silenceTimer: Timer?
    private let silenceThreshold: Float = 0.01
    private let silenceDuration: TimeInterval = 5.0
    // Tap-thread only; used to dispatch to main just on silence transitions
    // instead of once per buffer (~12/s).
    private var isInSilence = false

    var isRunning: Bool { engine.isRunning }

    /// Resolves the microphone permission state, prompting the user if undetermined.
    static func requestPermission() async -> Bool {
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        default:
            return false
        }
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
        #endif
    }

    func start() throws {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw AudioError.converterCreationFailed
        }

        isInSilence = false
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer, converter: converter)
        }

        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        silenceTimer?.invalidate()
        silenceTimer = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func processBuffer(_ inputBuffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(format.sampleRate * Double(inputBuffer.frameLength) / inputBuffer.format.sampleRate)
        ) else { return }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let error {
            delegate?.audioCaptureDidFail(error)
            return
        }

        let rms = computeRMS(outputBuffer)
        onLevel?(rms)
        let silent = rms < silenceThreshold
        if silent != isInSilence {
            isInSilence = silent
            if silent {
                scheduleSilenceDetection()
            } else {
                cancelSilenceDetection()
            }
        }

        delegate?.audioCaptureDidReceiveBuffer(outputBuffer)
    }

    // Handles both float and int16 output formats — the iOS speech
    // transcriber's preferred format is Int16, where floatChannelData is nil
    // (returning 0 there would read as permanent silence).
    private func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        if let floatData = buffer.floatChannelData?[0] {
            let sum = (0..<count).reduce(Float(0)) { acc, idx in acc + floatData[idx] * floatData[idx] }
            return sqrt(sum / Float(count))
        }
        if let intData = buffer.int16ChannelData?[0] {
            let sum = (0..<count).reduce(Float(0)) { acc, idx in
                let sample = Float(intData[idx]) / Float(Int16.max)
                return acc + sample * sample
            }
            return sqrt(sum / Float(count))
        }
        return 0
    }

    // Called from the audio tap thread; timers need a running run loop,
    // so scheduling/cancelling always hops to main.
    private func scheduleSilenceDetection() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.silenceTimer == nil else { return }
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: self.silenceDuration, repeats: false) { [weak self] _ in
                self?.silenceTimer = nil
                self?.delegate?.audioCaptureDidDetectSilence()
            }
        }
    }

    private func cancelSilenceDetection() {
        DispatchQueue.main.async { [weak self] in
            self?.silenceTimer?.invalidate()
            self?.silenceTimer = nil
        }
    }
}

enum AudioError: Error {
    case converterCreationFailed
    case permissionDenied
}
