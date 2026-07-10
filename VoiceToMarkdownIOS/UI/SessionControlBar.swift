import SwiftUI

/// iOS port of the macOS `HUDBubbleView` semantics: send, mic, status |
/// mode switcher + format picker | preview | clear session.
struct SessionControlBar: View {
    @ObservedObject var controller: AgentSessionController
    var onPreview: () -> Void
    @State private var showResetConfirmation = false

    private var sessionState: SessionState {
        if controller.isProcessing { return .processing }
        return controller.session?.state ?? .idle
    }

    private var canSend: Bool {
        controller.session?.state == .recording && !controller.isProcessing
    }

    private var canPreview: Bool {
        controller.session != nil
    }

    var body: some View {
        VStack(spacing: 6) {
            if let error = controller.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                sendButton
                micButton
                stateLabel
                Spacer()
                formatPicker
                previewButton
                trashButton
            }
            modeSwitcher
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        .padding(.horizontal, 12)
        .confirmationDialog(
            "Clear Session",
            isPresented: $showResetConfirmation
        ) {
            Button("Clear All", role: .destructive) {
                Task { await controller.resetSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear all recorded audio, transcript, and markdown content.")
        }
    }

    private var sendButton: some View {
        Button(action: { controller.flushNow() }) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.5))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    private var micButton: some View {
        Button(action: handleMicTap) {
            Image(systemName: micIconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(micColor)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    private var micIconName: String {
        switch sessionState {
        case .recording: return "mic.fill"
        case .processing: return "waveform"
        case .paused: return "mic.slash.fill"
        default: return "mic"
        }
    }

    private var micColor: Color {
        switch sessionState {
        case .recording: return .red
        case .processing: return .orange
        case .initializing: return .yellow
        default: return .secondary
        }
    }

    private var stateLabel: some View {
        Text(sessionState.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private var modeSwitcher: some View {
        Picker("Mode", selection: $controller.mode) {
            ForEach(AgentMode.allCases, id: \.self) { mode in
                Label(mode.displayName, systemImage: mode.iconName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var formatPicker: some View {
        Menu {
            Picker("Output Format", selection: $controller.outputFormat) {
                ForEach(OutputFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
        } label: {
            Text(controller.outputFormat.rawValue.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(.quaternary, in: Capsule())
        }
    }

    private var previewButton: some View {
        Button(action: onPreview) {
            Image(systemName: "eye")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(canPreview ? Color.secondary : Color.secondary.opacity(0.4))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!canPreview)
    }

    private var trashButton: some View {
        Button(action: { showResetConfirmation = true }) {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    private func handleMicTap() {
        switch sessionState {
        case .idle:
            Task { await controller.startSession() }
        case .paused:
            controller.startRecording()
        case .recording:
            controller.pauseRecording()
        case .initializing, .processing:
            break
        }
    }
}
