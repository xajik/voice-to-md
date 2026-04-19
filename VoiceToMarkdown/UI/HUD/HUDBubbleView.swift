import SwiftUI

struct HUDBubbleView: View {
    @ObservedObject var viewModel: HUDViewModel
    @State private var offset: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 0) {
            topRow
            if viewModel.isExpanded {
                transcriptRow
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .frame(maxWidth: 340)
        .offset(offset)
        .gesture(dragGesture)
    }

    private var topRow: some View {
        HStack(spacing: 12) {
            micButton
            stateLabel
            Spacer()
            copyButtons
            expandButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var micButton: some View {
        Button(action: handleMicTap) {
            Image(systemName: micIconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(micColor)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    private var micIconName: String {
        switch viewModel.sessionState {
        case .recording: return "mic.fill"
        case .processing: return "waveform"
        case .paused: return "mic.slash.fill"
        default: return "mic"
        }
    }

    private var micColor: Color {
        switch viewModel.sessionState {
        case .recording: return .red
        case .processing: return .orange
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
    }

    private var copyButtons: some View {
        HStack(spacing: 6) {
            copyButton("STT", action: viewModel.copyTranscript)
            copyButton("MD", action: viewModel.copyMarkdown)
        }
    }

    private func copyButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private var expandButton: some View {
        Button(action: { withAnimation(.spring(duration: 0.2)) { viewModel.isExpanded.toggle() } }) {
            Image(systemName: viewModel.isExpanded ? "chevron.down" : "chevron.up")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var transcriptRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.transcript.isEmpty ? "Transcript will appear here..." : viewModel.transcript)
                        .font(.caption)
                        .foregroundStyle(viewModel.transcript.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("bottom")
                }
                .onChange(of: viewModel.transcript) { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .frame(height: 80)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: value.translation.width, height: value.translation.height)
            }
            .onEnded { value in
                offset = CGSize(width: value.translation.width, height: value.translation.height)
            }
    }

    private func handleMicTap() {
        switch viewModel.sessionState {
        case .idle, .stopped:
            viewModel.startSession()
        case .ready, .paused:
            viewModel.startRecording()
        case .recording:
            viewModel.pauseRecording()
        case .initializing, .processing:
            break
        }
    }
}
