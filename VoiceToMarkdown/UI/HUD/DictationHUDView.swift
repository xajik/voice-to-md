import SwiftUI

/// Spotlight-style floating pill shown while the global dictation hotkey is active.
struct DictationHUDView: View {
    @ObservedObject var manager: GlobalDictationManager

    var body: some View {
        HStack(spacing: 14) {
            micIndicator
            VStack(alignment: .leading, spacing: 1) {
                Text(statusText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Text(manager.phase == .listening ? "Pause to finish, or press ⌘⌥] again" : "Typing at your cursor when done")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { manager.requestStop() }) {
                HStack(spacing: 5) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("⌘⌥]")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(manager.phase != .listening)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 420)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator, lineWidth: 0.5))
    }

    private var statusText: String {
        switch manager.phase {
        case .transcribing: return "Transcribing…"
        default: return "Listening…"
        }
    }

    private var micIndicator: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.18))
                .frame(width: 34, height: 34)
                .scaleEffect(1 + CGFloat(min(manager.level * 6, 0.8)))
                .animation(.easeOut(duration: 0.1), value: manager.level)
            if manager.phase == .transcribing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 40, height: 40)
    }
}
