import SwiftUI

/// Minimal floating control: mic button + session status + agent-mode toggles. Draggable.
struct HUDBubbleView: View {
    @ObservedObject var viewModel: HUDViewModel
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var showResetConfirmation = false

    var body: some View {
        HStack(spacing: 8) {
            sendButton
            micButton
            stateLabel
            Divider()
                .frame(height: 20)
            modeSwitcher
            formatPicker
            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)
            previewButton
            voiceButton
            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)
            trashButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    offset = CGSize(
                        width: dragStart.width + value.translation.width,
                        height: dragStart.height + value.translation.height
                    )
                }
                .onEnded { _ in dragStart = offset }
        )
        .confirmationDialog(
            "Clear Session",
            isPresented: $showResetConfirmation
        ) {
            Button("Clear All", role: .destructive) {
                viewModel.resetSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear all recorded audio, transcript, and markdown content.")
        }
    }

    private var sendButton: some View {
        Button(action: { viewModel.sendNow() }) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(viewModel.canSend ? Color.accentColor : Color.secondary.opacity(0.5))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSend)
        .keyboardShortcut(.return, modifiers: .command)
        .help("Send (⌘↩)")
    }

    private var micButton: some View {
        Button(action: handleMicTap) {
            Image(systemName: micIconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(micColor)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(micHelp)
    }

    private var trashButton: some View {
        Button(action: { showResetConfirmation = true }) {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help("Clear session")
    }

    // The mic reflects the raw recording state, not the processing overlay:
    // recording continues while the LLM formats, so pause/resume must stay
    // available. The status label still shows "Processing" via sessionState.
    private var micHelp: String {
        switch viewModel.recordingState {
        case .idle: return "Start"
        case .recording: return "Pause"
        case .paused: return "Resume"
        default: return "Busy"
        }
    }

    private var micIconName: String {
        switch viewModel.recordingState {
        case .recording: return "mic.fill"
        case .paused: return "mic.slash.fill"
        default: return "mic"
        }
    }

    private var micColor: Color {
        switch viewModel.recordingState {
        case .recording: return .red
        case .initializing: return .yellow
        default: return .secondary
        }
    }

    private var stateLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.sessionState.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .help("Status")
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(AgentMode.allCases, id: \.self) { mode in
                modeButton(mode)
            }
        }
    }

    private var formatPicker: some View {
        Menu {
            Picker("Output Format", selection: Binding(
                get: { viewModel.outputFormat },
                set: { viewModel.outputFormat = $0 }
            )) {
                ForEach(OutputFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(viewModel.outputFormat.rawValue.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Output format")
    }

    private var previewButton: some View {
        Button(action: { viewModel.openPreview() }) {
            Image(systemName: "eye")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(viewModel.canPreview ? Color.secondary : Color.secondary.opacity(0.4))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canPreview)
        .help("Preview in default app")
    }

    private var voiceButton: some View {
        Button(action: { viewModel.toggleSpeech() }) {
            Image(systemName: viewModel.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(voiceColor)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSpeak)
        .help(viewModel.isSpeaking ? "Stop reading" : "Read aloud (selection or document)")
    }

    private var voiceColor: Color {
        if viewModel.isSpeaking { return .accentColor }
        return viewModel.canSpeak ? Color.secondary : Color.secondary.opacity(0.4)
    }

    private func modeButton(_ mode: AgentMode) -> some View {
        let isActive = viewModel.mode == mode
        return Button {
            viewModel.mode = mode
        } label: {
            Image(systemName: mode.iconName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    isActive ? Color.accentColor.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .help(mode.displayName)
    }

    private func handleMicTap() {
        switch viewModel.recordingState {
        case .idle:
            viewModel.startSession()
        case .paused:
            viewModel.startRecording()
        case .recording:
            viewModel.pauseRecording()
        case .initializing, .processing:
            break
        }
    }
}
