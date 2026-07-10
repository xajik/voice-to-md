import SwiftUI

/// Expandable bottom pane in the agent window showing the raw STT stream.
struct RawTranscriptView: View {
    @ObservedObject var viewModel: HUDViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(viewModel.transcript.isEmpty ? "Raw speech-to-text will appear here…" : viewModel.transcript)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(viewModel.transcript.isEmpty ? Color.secondary.opacity(0.5) : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
                    .id("rawEnd")
            }
            .onChange(of: viewModel.transcript) { _ in
                proxy.scrollTo("rawEnd", anchor: .bottom)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }
}
