import Foundation

enum ModelSize: String, CaseIterable, Identifiable, Codable {
    case tiny
    case base
    case small
    case medium
    case large

    var id: String { rawValue }

    var filename: String { "ggml-\(rawValue).bin" }

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
        let base = "https://huggingface.co/datasets/ggerganov/whisper.cpp/resolve/main/"
        return URL(string: base + filename)!
    }

    func localPath(in modelsDir: URL) -> URL {
        modelsDir.appendingPathComponent(filename)
    }
}
