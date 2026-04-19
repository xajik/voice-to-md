import Foundation

final class ProviderRegistry {
    static let shared = ProviderRegistry()

    private let providers: [String: () -> any Provider]

    private init() {
        providers = [
            "claude-code": { ClaudeCodeProvider() },
            "claude": { ClaudeCodeProvider() },
            "gemini": { GeminiProvider() },
            "opencode": { OpenCodeProvider() },
            "codex": { CodexProvider() }
        ]
    }

    func detect(from command: String, override: String? = nil) -> any Provider {
        if let override {
            return providers[override.lowercased()]?() ?? ClaudeCodeProvider()
        }

        let binary = command.components(separatedBy: " ").first ?? command
        let binaryName = URL(fileURLWithPath: binary).lastPathComponent.lowercased()
        if let factory = providers[binaryName] {
            return factory()
        }

        return ClaudeCodeProvider()
    }

    var supportedAgents: [String] {
        Array(providers.keys).sorted()
    }
}
