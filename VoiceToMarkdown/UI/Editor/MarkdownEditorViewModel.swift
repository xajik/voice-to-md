import Foundation
import SwiftUI

@MainActor
final class MarkdownEditorViewModel: ObservableObject {
    @Published var content = ""

    private let coordinator: SessionCoordinator
    private var isUserEditing = false

    init(coordinator: SessionCoordinator) {
        self.coordinator = coordinator
    }

    func onCoordinatorMarkdownChange(_ newValue: String) {
        guard !isUserEditing else { return }
        if content != newValue {
            content = newValue
        }
    }

    func userDidEdit(_ text: String) {
        isUserEditing = true
        content = text
        if let mdPath = coordinator.session?.mdPath {
            try? VTMDFileManager.shared.writeMarkdown(text, to: mdPath)
        }
        isUserEditing = false
    }
}
