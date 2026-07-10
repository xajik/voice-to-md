import SwiftUI

@main
struct SpeechToMarkdownIOSApp: App {
    @StateObject private var controller = AgentSessionController()

    init() {
        try? STMDFileManager.shared.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            SessionListView(controller: controller)
        }
    }
}
