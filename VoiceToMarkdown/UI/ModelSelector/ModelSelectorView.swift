import SwiftUI

struct ModelSelectorView: View {
    @ObservedObject var downloader: ModelDownloader
    @ObservedObject private var backend = BackendSettings.shared
    @State private var availableModels: [String] = []
    @State private var backendError: String?

    private let fileManager = VTMDFileManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.title2.weight(.semibold))

            Toggle("Launch at login", isOn: $backend.launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)

            Toggle("Fix dictation transcription with LLM", isOn: $backend.fixTranscriptionWithLLM)
                .toggleStyle(.switch)
                .controlSize(.small)

            Divider()

            Text("Local LLM")
                .font(.title2.weight(.semibold))

            backendSection

            Divider()

            Text("Whisper Model")
                .font(.title2.weight(.semibold))

            whisperSection
        }
        .padding(20)
        .task { await loadModels() }
    }

    private var backendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenAI-compatible API (omlx, llama.cpp, LM Studio…)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField(BackendSettings.defaultBaseURL, text: $backend.localAPIBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("Refresh") { Task { await loadModels() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            HStack(spacing: 8) {
                Picker("Model", selection: $backend.localModel) {
                    Text("Auto (first available)").tag("")
                    ForEach(pickerModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                statusIndicator
            }
        }
    }

    // Keep a stale selection visible in the picker even if the server list changed
    private var pickerModels: [String] {
        if !backend.localModel.isEmpty && !availableModels.contains(backend.localModel) {
            return [backend.localModel] + availableModels
        }
        return availableModels
    }

    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(backendError == nil && !availableModels.isEmpty ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            if let backendError {
                Text(backendError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if !availableModels.isEmpty {
                Text("\(availableModels.count) models")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var whisperSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speech-to-text (whisper.cpp, runs on-device)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Picker("Whisper", selection: $backend.whisperModel) {
                    Text("Auto (first downloaded)").tag("")
                    ForEach(ModelSize.allCases) { size in
                        Text(whisperLabel(for: size)).tag(size.rawValue)
                    }
                }
                .labelsHidden()
                whisperStatusIndicator
            }
            whisperDownloadRow
        }
    }

    private func whisperLabel(for size: ModelSize) -> String {
        let name = "\(size.rawValue.capitalized) (\(size.approximateSize))"
        return fileManager.isModelDownloaded(size) ? "\(name) ✓" : name
    }

    /// The model a download would target: explicit selection, else the auto default.
    private var downloadTarget: ModelSize {
        ModelSize(rawValue: backend.whisperModel) ?? ModelSize.autoPreference[0]
    }

    private var whisperStatusIndicator: some View {
        HStack(spacing: 4) {
            let resolved = backend.resolvedWhisperModel(in: fileManager)
            Circle()
                .fill(resolved != nil ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(resolved.map { "using \($0.rawValue.capitalized)" } ?? "no model downloaded")
                .font(.caption2)
                .foregroundStyle(resolved != nil ? .secondary : Color.red)
        }
    }

    @ViewBuilder
    private var whisperDownloadRow: some View {
        if let progress = downloader.progress, let error = progress.error {
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        } else if let progress = downloader.progress, !progress.isComplete {
            HStack(spacing: 8) {
                ProgressView(value: progress.fraction)
                    .frame(width: 120)
                Text("\(progress.percentage)% of \(progress.modelSize.rawValue.capitalized)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Cancel", action: downloader.cancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } else if !fileManager.isModelDownloaded(downloadTarget) {
            Button("Download \(downloadTarget.rawValue.capitalized) (\(downloadTarget.approximateSize))") {
                Task { await downloader.download(downloadTarget) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(downloader.isDownloading)
        }
    }

    private func loadModels() async {
        guard let url = backend.baseURL else {
            backendError = "Invalid URL"
            availableModels = []
            return
        }
        do {
            availableModels = try await LocalLLMService(baseURL: url).listModels()
            backendError = nil
        } catch {
            availableModels = []
            backendError = error.localizedDescription
        }
    }
}
