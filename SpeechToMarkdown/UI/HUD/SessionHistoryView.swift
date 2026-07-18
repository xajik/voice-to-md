import SwiftUI

/// Quick-access list of past agent-mode sessions (read from disk via
/// `STMDFileManager.listSessions()`); clicking a row restores it. Hosted in
/// an `NSPopover` anchored to the agent window's toolbar (see `AppDelegate`).
struct SessionHistoryView: View {
    @ObservedObject var viewModel: HUDViewModel
    /// Called after a session is restored, so the host can close the popover.
    var onSelect: () -> Void = {}
    @State private var pendingDelete: SessionListing?

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
                            SessionHistoryRow(
                                session: session,
                                onRestore: {
                                    viewModel.restoreSession(session)
                                    onSelect()
                                },
                                onDelete: { pendingDelete = session }
                            )
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
        .confirmationDialog(
            "Delete Session",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { listing in
            Button("Delete", role: .destructive) { viewModel.deleteSession(listing) }
            Button("Cancel", role: .cancel) {}
        } message: { listing in
            Text("Delete the session from \(SessionHistoryRow.dateFormatter.string(from: listing.createdAt))? This cannot be undone.")
        }
    }
}

private struct SessionHistoryRow: View {
    let session: SessionListing
    let onRestore: () -> Void
    let onDelete: () -> Void
    @State private var isHoveringButton = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onRestore) {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(isHoveringButton ? .primary : .tertiary)
            }
            .buttonStyle(.plain)
            .help("Delete session")
            .onHover { isHoveringButton = $0 }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
