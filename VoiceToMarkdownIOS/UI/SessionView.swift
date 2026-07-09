import SwiftUI

/// In-session screen: editor filling the screen, control bar pinned to the
/// bottom, QuickLook preview in a sheet. Popping back stops the session
/// (files are already persisted; the list screen can restore it).
struct SessionView: View {
    @ObservedObject var controller: AgentSessionController
    @State private var showPreview = false
    @State private var showRawInput = false

    var body: some View {
        MarkdownEditorIOSView(
            text: $controller.document,
            onEdit: { controller.userDidEdit($0) },
            onSelectionChange: { controller.editorSelection = $0 }
        )
        .ignoresSafeArea(.container, edges: .bottom)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                RawTranscriptPane(controller: controller, isExpanded: $showRawInput)
                SessionControlBar(controller: controller) {
                    openPreview()
                }
            }
            .padding(.bottom, 8)
        }
        .navigationTitle(sessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPreview) {
            if let url = controller.session?.docPath {
                DocumentPreviewView(url: url)
            }
        }
        .onDisappear {
            Task { await controller.stopSession() }
        }
    }

    private func openPreview() {
        guard let session = controller.session else { return }
        // Make sure the file exists before QuickLook opens it.
        if !FileManager.default.fileExists(atPath: session.docPath.path) {
            controller.userDidEdit(controller.document)
        }
        showPreview = true
    }

    private var sessionTitle: String {
        guard let session = controller.session,
              let millis = Double(session.id) else { return "Session" }
        return Self.dateFormatter.string(from: Date(timeIntervalSince1970: millis / 1000))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
