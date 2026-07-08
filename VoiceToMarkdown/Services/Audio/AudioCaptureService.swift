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
    private let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    private var silenceTimer: Timer?
    private let silenceThreshold: Float = 0.01
    private let silenceDuration: TimeInterval = 5.0
    // Tap-thread only; used to dispatch to main just on silence transitions
    // instead of once per buffer (~12/s).
    private var isInSilence = false

    var isRunning: Bool { engine.isRunning }

    /// Resolves the microphone TCC state, prompting the user if undetermined.
    static func requestPermission() async -> Bool {
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
    }

    func start() throws {
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

    private func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        let sum = (0..<count).reduce(Float(0)) { acc, idx in acc + channelData[idx] * channelData[idx] }
        return sqrt(sum / Float(count))
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
