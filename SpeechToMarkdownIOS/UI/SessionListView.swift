import FoundationModels
import SwiftUI

/// Landing screen: Apple Intelligence availability, new-session button, and
/// the on-disk session history (port of the macOS `SessionHistoryView` rows).
struct SessionListView: View {
    @ObservedObject var controller: AgentSessionController
    @State private var sessions: [SessionListing] = []
    @State private var showSession = false

    private var availability: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    var body: some View {
        NavigationStack {
            List {
                if case .unavailable(let reason) = availability {
                    Section {
                        availabilityBanner(reason)
                    }
                }

                if let error = controller.error {
                    Section {
                        Label {
                            Text(error).font(.callout)
                        } icon: {
                            Image(systemName: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Recent Sessions") {
                    if sessions.isEmpty {
                        Text("No sessions yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sessions) { listing in
                            sessionRow(listing)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteSession(listing)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Speech to MD")
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        await controller.startSession()
                        if controller.session != nil { showSession = true }
                    }
                } label: {
                    Label("New Session", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(availability != .available)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationDestination(isPresented: $showSession) {
                SessionView(controller: controller)
            }
            .onAppear {
                refreshSessions()
                #if DEBUG
                // Screenshot automation: simctl can't tap, so an explicit
                // launch argument drives navigation into the latest session.
                if CommandLine.arguments.contains("--screenshot-restore-latest"),
                   let latest = sessions.first, !showSession {
                    Task {
                        await controller.restoreSession(latest)
                        if controller.session != nil { showSession = true }
                    }
                }
                #endif
            }
        }
    }

    private func refreshSessions() {
        sessions = STMDFileManager.shared.listSessions()
    }

    private func deleteSession(_ listing: SessionListing) {
        Task {
            // The active session's files are still open for writing; stop it
            // first so we don't delete out from under an in-flight flush.
            if controller.session?.id == listing.id {
                await controller.stopSession()
            }
            do {
                try STMDFileManager.shared.deleteSession(listing)
                sessions.removeAll { $0.id == listing.id }
            } catch {
                self.controller.error = error.localizedDescription
            }
        }
    }

    private func sessionRow(_ listing: SessionListing) -> some View {
        Button {
            Task {
                await controller.restoreSession(listing)
                if controller.session != nil { showSession = true }
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.dateFormatter.string(from: listing.createdAt))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(listing.preview.isEmpty ? "Empty session" : listing.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(listing.format.rawValue.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(availability != .available)
    }

    private func availabilityBanner(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> some View {
        Label {
            Text(availabilityMessage(reason))
                .font(.callout)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func availabilityMessage(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence, which Speech to MD needs to format documents."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to use Speech to MD."
        case .modelNotReady:
            return "The Apple Intelligence model is still downloading — try again shortly."
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
