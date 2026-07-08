import Foundation

/// UserDefaults-backed model configuration shared by the coordinator and settings UI.
final class BackendSettings: ObservableObject {
    static let shared = BackendSettings()

    @Published var localAPIBaseURL: String {
        didSet { defaults.set(localAPIBaseURL, forKey: Keys.localAPIBaseURL) }
    }
    /// Empty string means auto-pick the first model returned by /models.
    @Published var localModel: String {
        didSet { defaults.set(localModel, forKey: Keys.localModel) }
    }
    /// Whisper model rawValue; empty string means auto-pick the first downloaded model.
    @Published var whisperModel: String {
        didSet { defaults.set(whisperModel, forKey: Keys.whisperModel) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        localAPIBaseURL = defaults.string(forKey: Keys.localAPIBaseURL) ?? BackendSettings.defaultBaseURL
        localModel = defaults.string(forKey: Keys.localModel) ?? ""
        whisperModel = defaults.string(forKey: Keys.whisperModel) ?? ""
    }

    /// Explicit selection if downloaded, otherwise the first downloaded model by preference.
    func resolvedWhisperModel(in fileManager: VTMDFileManager = .shared) -> ModelSize? {
        if let size = ModelSize(rawValue: whisperModel), fileManager.isModelDownloaded(size) {
            return size
        }
        return ModelSize.autoPreference.first { fileManager.isModelDownloaded($0) }
    }

    static let defaultBaseURL = "http://127.0.0.1:8000/v1"

    var baseURL: URL? {
        URL(string: localAPIBaseURL.trimmingCharacters(in: .whitespaces))
    }

    private enum Keys {
        static let localAPIBaseURL = "vtmd.localAPIBaseURL"
        static let localModel = "vtmd.localModel"
        static let whisperModel = "vtmd.whisperModel"
    }
}
