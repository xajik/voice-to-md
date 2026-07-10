import AVFoundation
import SwiftUI

/// One row in the Doctor section: a named health check with its outcome.
struct DoctorCheck: Identifiable {
    enum Status {
        case checking, ok, warning, failed
    }

    let id: String
    let name: String
    var status: Status = .checking
    var detail: String = ""
}

/// Settings section that verifies the external tools and permissions the app
/// relies on, using the same resolution logic as the runtime pipeline.
struct DoctorView: View {
    @State private var checks: [DoctorCheck] = []
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Verifies dependencies and permissions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Run Checks") { Task { await runChecks() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRunning)
            }
            ForEach(checks) { check in
                HStack(spacing: 6) {
                    statusIcon(check.status)
                    Text(check.name)
                        .font(.caption)
                    Spacer()
                    Text(check.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(check.detail)
                }
            }
        }
        .task { await runChecks() }
    }

    @ViewBuilder
    private func statusIcon(_ status: DoctorCheck.Status) -> some View {
        switch status {
        case .checking:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 14, height: 14)
        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func runChecks() async {
        isRunning = true
        defer { isRunning = false }

        checks = [
            DoctorCheck(id: "whisper", name: "whisper-cli"),
            DoctorCheck(id: "ffmpeg", name: "ffmpeg"),
            DoctorCheck(id: "model", name: "Whisper model"),
            DoctorCheck(id: "llm", name: "Local LLM server"),
            DoctorCheck(id: "mic", name: "Microphone access"),
            DoctorCheck(id: "ax", name: "Accessibility access")
        ]

        if let path = await WhisperService.resolvedBinaryPath() {
            set("whisper", .ok, path)
        } else {
            set("whisper", .failed, "brew install whisper-cpp")
        }

        if let path = AudioConverter.resolvedFFmpegPath() {
            set("ffmpeg", .ok, path)
        } else {
            set("ffmpeg", .failed, "brew install ffmpeg")
        }

        if let model = BackendSettings.shared.resolvedWhisperModel() {
            set("model", .ok, "using \(model.rawValue.capitalized)")
        } else {
            set("model", .failed, "download one in Whisper Model above")
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            set("mic", .ok, "granted")
        case .notDetermined:
            set("mic", .warning, "asked on first recording")
        default:
            set("mic", .failed, "System Settings → Privacy & Security → Microphone")
        }

        if KeystrokeInjector.hasAccessibilityPermission {
            set("ax", .ok, "granted")
        } else {
            set("ax", .failed, "System Settings → Accessibility, then restart the app")
        }

        // Last: the only check that hits the network.
        if let url = BackendSettings.shared.baseURL {
            do {
                let models = try await LocalLLMService(baseURL: url).listModels()
                if models.isEmpty {
                    set("llm", .warning, "server up, no models loaded")
                } else {
                    set("llm", .ok, "\(models.count) models at \(url.absoluteString)")
                }
            } catch {
                set("llm", .warning, "unreachable — needed for Agent Mode only")
            }
        } else {
            set("llm", .failed, "invalid base URL")
        }
    }

    private func set(_ id: String, _ status: DoctorCheck.Status, _ detail: String) {
        guard let idx = checks.firstIndex(where: { $0.id == id }) else { return }
        checks[idx].status = status
        checks[idx].detail = detail
    }
}
