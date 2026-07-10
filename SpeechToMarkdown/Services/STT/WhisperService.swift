import Foundation

final class WhisperService {
    let modelPath: URL

    private static let blankAudioMarker = "[BLANK_AUDIO]"

    init(modelPath: URL) {
        self.modelPath = modelPath
    }

    func transcribe(wavFile: URL) async throws -> String? {
        let binary = try Self.resolveWhisperBinary()
        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "-m", modelPath.path,
            "-f", wavFile.path,
            "-nt",
            "--output-txt"
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if output.contains(Self.blankAudioMarker) {
            return nil
        }

        let cleaned = output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !cleaned.isEmpty else { return nil }
        if Self.isNoiseOnly(cleaned) {
            stmdLog("WHISPER", "Skipped noise-only chunk: \(cleaned)")
            return nil
        }
        return cleaned
    }

    private static let noiseAnnotationRegex = try? NSRegularExpression(pattern: #"\[[^\]]*\]|\([^)]*\)"#)

    /// True when the transcript is only whisper noise annotations like
    /// "(wind blowing)", "[silence]", "(mouse clicking)" — no actual speech.
    static func isNoiseOnly(_ text: String) -> Bool {
        guard let regex = noiseAnnotationRegex else { return false }
        let range = NSRange(text.startIndex..., in: text)
        let stripped = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func checkAvailability() async -> Bool {
        await resolvedBinaryPath() != nil
    }

    /// Absolute path of the whisper binary the app would run, nil when missing.
    static func resolvedBinaryPath() async -> String? {
        (try? resolveWhisperBinary())?.path
    }

    private static func resolveWhisperBinary() throws -> URL {
        guard let url = ExecutableResolver.resolve("whisper-cli", "whisper-cpp") else {
            throw WhisperError.binaryNotFound
        }
        return url
    }
}

enum WhisperError: Error, LocalizedError {
    case binaryNotFound
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "whisper-cli not found. Install via: brew install whisper-cpp"
        case .transcriptionFailed(let msg):
            return "Transcription failed: \(msg)"
        }
    }
}
