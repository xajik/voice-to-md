import Foundation

final class WhisperService {
    let modelPath: URL

    private static let blankAudioMarker = "[BLANK_AUDIO]"

    init(modelPath: URL) {
        self.modelPath = modelPath
    }

    func transcribe(wavFile: URL) async throws -> String? {
        let binary = try await resolveWhisperBinary()
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

        return cleaned.isEmpty ? nil : cleaned
    }

    static func checkAvailability() async -> Bool {
        do {
            _ = try await resolveWhisperBinary()
            return true
        } catch {
            return false
        }
    }

    private func resolveWhisperBinary() async throws -> URL {
        try await Self.resolveWhisperBinary()
    }

    private static func resolveWhisperBinary() async throws -> URL {
        for name in ["whisper-cli", "whisper-cpp"] {
            if let url = try? await which(name) {
                return url
            }
        }
        throw WhisperError.binaryNotFound
    }

    private static func which(_ name: String) async throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw WhisperError.binaryNotFound }
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { throw WhisperError.binaryNotFound }
        return URL(fileURLWithPath: path)
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
