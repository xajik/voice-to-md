import SwiftUI

/// iOS port of the macOS raw-input disclosure: a tappable bar with a word
/// count that expands into a scrollable pane showing the full raw STT log
/// (all finalized text for the session, plus the live volatile tail).
struct RawTranscriptPane: View {
    @ObservedObject var controller: AgentSessionController
    @Binding var isExpanded: Bool

    private let paneHeight: CGFloat = 160

    var body: some View {
        VStack(spacing: 0) {
            bar
            if isExpanded {
                transcriptPane
                    .frame(height: paneHeight)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator, lineWidth: 0.5))
        .padding(.horizontal, 12)
    }

    private var bar: some View {
        HStack(spacing: 6) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Raw input")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            if !controller.volatileText.isEmpty {
                Text(controller.volatileText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else if !controller.transcript.isEmpty {
                Text("\(TranscriptBuffer.wordCount(in: controller.transcript)) words")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        }
    }

    private var transcriptPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(controller.transcript.isEmpty && controller.volatileText.isEmpty
                         ? "Raw speech-to-text will appear here…"
                         : controller.transcript)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(controller.transcript.isEmpty
                                         ? Color.secondary.opacity(0.5)
                                         : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    if !controller.volatileText.isEmpty {
                        Text(controller.volatileText)
                            .font(.system(.caption, design: .monospaced).italic())
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .id("rawEnd")
            }
            .onChange(of: controller.transcript) {
                proxy.scrollTo("rawEnd", anchor: .bottom)
            }
            .onChange(of: controller.volatileText) {
                proxy.scrollTo("rawEnd", anchor: .bottom)
            }
        }
    }
}
