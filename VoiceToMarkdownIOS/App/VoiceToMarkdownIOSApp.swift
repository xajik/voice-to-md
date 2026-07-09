import SwiftUI

@main
struct VoiceToMarkdownIOSApp: App {
    @StateObject private var controller = AgentSessionController()

    init() {
        try? VTMDFileManager.shared.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            SessionListView(controller: controller)
        }
    }
}
