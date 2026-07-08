import SwiftUI

/// Minimal floating control: one mic button + session status. Draggable.
struct HUDBubbleView: View {
    @ObservedObject var viewModel: HUDViewModel
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero

    var body: some View {
        HStack(spacing: 8) {
            micButton
            stateLabel
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
    }

    private var micButton: some View {
        Button(action: handleMicTap) {
            Image(systemName: micIconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(micColor)
                .frame(width: 24, height: 24)
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

    private func handleMicTap() {
        switch viewModel.sessionState {
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
