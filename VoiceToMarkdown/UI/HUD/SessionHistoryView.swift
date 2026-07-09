import SwiftUI

/// Quick-access list of past agent-mode sessions (read from disk via
/// `VTMDFileManager.listSessions()`); clicking a row restores it. Hosted in
/// an `NSPopover` anchored to the agent window's toolbar (see `AppDelegate`).
struct SessionHistoryView: View {
    @ObservedObject var viewModel: HUDViewModel
    /// Called after a session is restored, so the host can close the popover.
    var onSelect: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Sessions")
                .font(.headline)
                .padding(12)
            Divider()
            if viewModel.sessions.isEmpty {
                Text("No sessions yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.sessions) { session in
                            sessionRow(session)
                            if session.id != viewModel.sessions.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 320)
        .onAppear { viewModel.refreshSessions() }
    }

    private func sessionRow(_ session: SessionListing) -> some View {
        Button {
            viewModel.restoreSession(session)
            onSelect()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.dateFormatter.string(from: session.createdAt))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(session.preview.isEmpty ? "Empty session" : session.preview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(session.format.rawValue.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
