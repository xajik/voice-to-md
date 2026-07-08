import Foundation

enum ModelSize: String, CaseIterable, Identifiable, Codable {
    case tiny
    case base
    case small
    case medium
    case large

    var id: String { rawValue }

    /// Fallback order when no explicit model is selected: balanced first.
    static let autoPreference: [ModelSize] = [.base, .small, .tiny, .medium, .large]

    var filename: String {
        // whisper.cpp only publishes v3 for the large model
        self == .large ? "ggml-large-v3.bin" : "ggml-\(rawValue).bin"
    }

    var approximateSize: String {
        switch self {
        case .tiny: return "~75 MB"
        case .base: return "~150 MB"
        case .small: return "~500 MB"
        case .medium: return "~1.5 GB"
        case .large: return "~3.2 GB"
        }
    }

    var huggingFaceURL: URL {
        let base = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"
        return URL(string: base + filename)!
    }

    func localPath(in modelsDir: URL) -> URL {
        modelsDir.appendingPathComponent(filename)
    }
}
