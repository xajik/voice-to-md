import AppKit
import SwiftUI

struct MarkdownEditorView: View {
    @ObservedObject var viewModel: MarkdownEditorViewModel

    var body: some View {
        MarkdownNSTextView(
            text: $viewModel.content,
            onEdit: { viewModel.userDidEdit($0) },
            onSelectionChange: { viewModel.selectionDidChange($0) }
        )
    }
}

struct MarkdownNSTextView: NSViewRepresentable {
    @Binding var text: String
    var onEdit: (String) -> Void
    var onSelectionChange: ((String?) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.allowsUndo = true
        textView.delegate = context.coordinator

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text, !context.coordinator.isEditing {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selectedRange)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onEdit: onEdit, onSelectionChange: onSelectionChange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onEdit: (String) -> Void
        var onSelectionChange: ((String?) -> Void)?
        var isEditing = false

        init(onEdit: @escaping (String) -> Void, onSelectionChange: ((String?) -> Void)?) {
            self.onEdit = onEdit
            self.onSelectionChange = onSelectionChange
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onEdit(textView.string)
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let full = textView.string as NSString
            // Streaming can replace the text and re-apply a stale range;
            // treat anything out of bounds as no selection.
            guard range.length > 0, NSMaxRange(range) <= full.length else {
                onSelectionChange?(nil)
                return
            }
            onSelectionChange?(full.substring(with: range))
        }
    }
}
