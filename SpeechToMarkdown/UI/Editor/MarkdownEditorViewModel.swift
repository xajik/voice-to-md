import Combine
import Foundation
import SwiftUI

@MainActor
final class MarkdownEditorViewModel: ObservableObject {
    @Published var content = ""

    private let coordinator: SessionCoordinator
    private var cancellables = Set<AnyCancellable>()

    init(coordinator: SessionCoordinator) {
        self.coordinator = coordinator
        coordinator.$markdown
            .sink { [weak self] newValue in
                guard let self, self.content != newValue else { return }
                self.content = newValue
            }
            .store(in: &cancellables)
    }

    func userDidEdit(_ text: String) {
        content = text
        if let docPath = coordinator.session?.docPath {
            try? STMDFileManager.shared.writeMarkdown(text, to: docPath)
        }
    }

    func selectionDidChange(_ selected: String?) {
        coordinator.editorSelection = selected
    }
}
