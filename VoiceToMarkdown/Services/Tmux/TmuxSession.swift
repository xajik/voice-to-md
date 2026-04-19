import Foundation

struct TmuxSession {
    let name: String

    func spawn(command: String, workDir: String, env: [String: String]) async throws {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in env {
            environment[key] = value
        }

        try await run(
            arguments: ["new-session", "-d", "-s", name, "-c", workDir, "--"] + command.components(separatedBy: " "),
            environment: environment
        )
    }

    func paste(_ content: String, bufferName: String = "vtmd-buf") async throws {
        try await run(arguments: ["set-buffer", "-b", bufferName, "--", content])
        try await run(arguments: ["paste-buffer", "-t", name, "-b", bufferName])
        try await run(arguments: ["delete-buffer", "-b", bufferName])
    }

    func sendKeys(_ keys: String) async throws {
        try await run(arguments: ["send-keys", "-t", name, keys, ""])
    }

    func kill() async throws {
        try? await run(arguments: ["kill-session", "-t", name])
    }

    func isAlive() async -> Bool {
        (try? await run(arguments: ["has-session", "-t", name])) != nil
    }

    @discardableResult
    private func run(arguments: [String], environment: [String: String]? = nil) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmux")
        process.arguments = arguments

        if let environment {
            process.environment = environment
        } else {
            var env = ProcessInfo.processInfo.environment
            if env["PATH"] == nil || !env["PATH"]!.contains("/usr/local/bin") {
                env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:\(env["PATH"] ?? "")"
            }
            process.environment = env
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } else {
                    let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(throwing: TmuxError.commandFailed(proc.terminationStatus, err))
                }
            }
        }
    }
}

enum TmuxError: Error, LocalizedError {
    case commandFailed(Int32, String)
    case sessionNotFound(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let code, let msg): return "tmux exited \(code): \(msg)"
        case .sessionNotFound(let name): return "tmux session not found: \(name)"
        }
    }
}
