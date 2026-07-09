import SwiftUI
import UIKit

/// iOS mirror of the macOS `MarkdownNSTextView`: plain-text editor with
/// edit/selection callbacks feeding the agent (selection becomes `user_focus`
/// in edit mode).
struct MarkdownEditorIOSView: UIViewRepresentable {
    @Binding var text: String
    var onEdit: (String) -> Void
    var onSelectionChange: ((String?) -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.backgroundColor = .systemBackground
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text, !context.coordinator.isEditing {
            let selectedRange = textView.selectedRange
            textView.text = text
            let length = (textView.text as NSString).length
            if NSMaxRange(selectedRange) <= length {
                textView.selectedRange = selectedRange
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onEdit: onEdit, onSelectionChange: onSelectionChange)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onEdit: (String) -> Void
        var onSelectionChange: ((String?) -> Void)?
        var isEditing = false

        init(onEdit: @escaping (String) -> Void, onSelectionChange: ((String?) -> Void)?) {
            self.onEdit = onEdit
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
        }

        func textViewDidChange(_ textView: UITextView) {
            onEdit(textView.text)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            let full = textView.text as NSString
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
