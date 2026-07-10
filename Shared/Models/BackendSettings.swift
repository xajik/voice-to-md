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
    /// Register the app as a login item. Persisted preference only —
    /// AppDelegate applies it via SMAppService. Defaults to on.
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    /// When enabled, dictation transcription is sent through the local LLM
    /// for cleanup before being injected at the cursor.
    @Published var fixTranscriptionWithLLM: Bool {
        didSet { defaults.set(fixTranscriptionWithLLM, forKey: Keys.fixTranscriptionWithLLM) }
    }
    /// Agent-mode output format rawValue; falls back to markdown.
    @Published var outputFormat: String {
        didSet { defaults.set(outputFormat, forKey: Keys.outputFormat) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if os(macOS)
        Self.migrateLegacyDefaultsIfNeeded(into: defaults)
        #endif
        localAPIBaseURL = defaults.string(forKey: Keys.localAPIBaseURL) ?? BackendSettings.defaultBaseURL
        localModel = defaults.string(forKey: Keys.localModel) ?? ""
        whisperModel = defaults.string(forKey: Keys.whisperModel) ?? ""
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? true
        fixTranscriptionWithLLM = defaults.object(forKey: Keys.fixTranscriptionWithLLM) as? Bool ?? false
        outputFormat = defaults.string(forKey: Keys.outputFormat) ?? OutputFormat.md.rawValue
    }

    var resolvedOutputFormat: OutputFormat {
        OutputFormat(rawValue: outputFormat) ?? .md
    }

    /// Explicit selection if downloaded, otherwise the first downloaded model by preference.
    func resolvedWhisperModel(in fileManager: STMDFileManager = .shared) -> ModelSize? {
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
        static let localAPIBaseURL = "stmd.localAPIBaseURL"
        static let localModel = "stmd.localModel"
        static let whisperModel = "stmd.whisperModel"
        static let launchAtLogin = "stmd.launchAtLogin"
        static let fixTranscriptionWithLLM = "stmd.fixTranscriptionWithLLM"
        static let outputFormat = "stmd.outputFormat"
    }

    /// One-time migration for pre-rebrand installs: the bundle-ID change gives
    /// the app a fresh UserDefaults domain, so settings from the old
    /// `com.vtmd.voicetomarkdown` domain would otherwise silently reset.
    /// Guarded by `stmd.migrated` so it only runs once even if the legacy
    /// domain never had these keys set.
    private static func migrateLegacyDefaultsIfNeeded(into defaults: UserDefaults) {
        let migratedFlagKey = "stmd.migrated"
        guard !defaults.bool(forKey: migratedFlagKey) else { return }
        defer { defaults.set(true, forKey: migratedFlagKey) }
        guard let legacyDefaults = UserDefaults(suiteName: "com.vtmd.voicetomarkdown") else { return }

        let keyPairs: [(legacy: String, new: String)] = [
            ("vtmd.localAPIBaseURL", Keys.localAPIBaseURL),
            ("vtmd.localModel", Keys.localModel),
            ("vtmd.whisperModel", Keys.whisperModel),
            ("vtmd.launchAtLogin", Keys.launchAtLogin),
            ("vtmd.fixTranscriptionWithLLM", Keys.fixTranscriptionWithLLM),
            ("vtmd.outputFormat", Keys.outputFormat)
        ]
        for pair in keyPairs {
            guard defaults.object(forKey: pair.new) == nil,
                  let value = legacyDefaults.object(forKey: pair.legacy) else { continue }
            defaults.set(value, forKey: pair.new)
        }
    }
}
