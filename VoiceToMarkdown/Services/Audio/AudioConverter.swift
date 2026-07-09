import AVFoundation
import Foundation

final class AudioConverter {
    static func convertToWAV(input: URL, output: URL) async throws {
        let process = Process()
        process.executableURL = try resolveExecutable("ffmpeg")
        process.arguments = [
            "-y", "-i", input.path,
            "-ar", "16000",
            "-ac", "1",
            "-c:a", "pcm_s16le",
            output.path
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw AudioConverterError.conversionFailed(errorMsg)
        }
    }

    static func writePCMBuffersToWAV(_ buffers: [AVAudioPCMBuffer], to url: URL) throws {
        guard let first = buffers.first else { return }
        let file = try AVAudioFile(forWriting: url, settings: first.format.settings)
        for buffer in buffers {
            try file.write(from: buffer)
        }
    }

    /// Absolute path of the ffmpeg binary the app would run, nil when missing.
    static func resolvedFFmpegPath() -> String? {
        (try? resolveExecutable("ffmpeg"))?.path
    }

    private static func resolveExecutable(_ name: String) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !output.isEmpty else { throw AudioConverterError.dependencyMissing(name) }
        return URL(fileURLWithPath: output)
    }
}

enum AudioConverterError: Error, LocalizedError {
    case conversionFailed(String)
    case dependencyMissing(String)

    var errorDescription: String? {
        switch self {
        case .conversionFailed(let msg): return "ffmpeg conversion failed: \(msg)"
        case .dependencyMissing(let bin): return "Required binary not found: \(bin). Install via brew."
        }
    }
}
