import SwiftUI

struct ModelSelectorView: View {
    @ObservedObject var downloader: ModelDownloader
    @State private var customPath = ""
    @State private var showFilePicker = false

    private let fileManager = VTMDFileManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Whisper Models")
                .font(.title2.weight(.semibold))

            ForEach(ModelSize.allCases) { size in
                ModelRowView(
                    size: size,
                    isDownloaded: fileManager.isModelDownloaded(size),
                    progress: downloader.progress?.modelSize == size ? downloader.progress : nil,
                    isDownloading: downloader.isDownloading,
                    onDownload: { Task { await downloader.download(size) } },
                    onCancel: downloader.cancel
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Model Path")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("~/.vtmd/models/tts/custom.bin", text: $customPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Button("Browse") { showFilePicker = true }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result {
                customPath = url.path
            }
        }
    }
}

struct ModelRowView: View {
    let size: ModelSize
    let isDownloaded: Bool
    let progress: DownloadProgress?
    let isDownloading: Bool
    let onDownload: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(size.rawValue.capitalized)
                    .font(.body.weight(.medium))
                Text(size.approximateSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let progress, let error = progress.error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let progress, !progress.isComplete {
                HStack(spacing: 8) {
                    ProgressView(value: progress.fraction)
                        .frame(width: 80)
                    Text("\(progress.percentage)%")
                        .font(.caption.monospacedDigit())
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else if isDownloaded {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Download") { onDownload() }
                    .buttonStyle(.bordered)
                    .disabled(isDownloading)
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
