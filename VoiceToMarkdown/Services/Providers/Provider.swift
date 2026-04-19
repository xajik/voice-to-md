import Foundation

protocol Provider {
    var name: String { get }
    var supportsVoiceHooks: Bool { get }

    func setup(workDir: String, hooksPort: Int, agentID: String, taskID: String) throws
    func setupVoice(workDir: String, hooksPort: Int) throws
    func env(hooksPort: Int) -> [String: String]
    func extraArgs() -> [String]
}

extension Provider {
    func env(hooksPort: Int) -> [String: String] { [:] }
    func extraArgs() -> [String] { [] }
}

enum ProviderError: Error, LocalizedError {
    case notSupported(String)

    var errorDescription: String? {
        switch self {
        case .notSupported(let feature):
            return "Provider does not support: \(feature)"
        }
    }
}

func writeJSON(to path: String, object: [String: Any]) throws {
    let dir = (path as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}
