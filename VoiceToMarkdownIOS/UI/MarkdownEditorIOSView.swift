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
        textView.keyboardDismissMode = .interactive
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Unlike the macOS editor, never gate on focus: on iOS the keyboard
        // keeps the view "editing" indefinitely (edit mode's select-text
        // gesture guarantees that state), which would freeze all streamed
        // agent output. Typing loops are already prevented by the equality
        // check — userDidEdit syncs the binding synchronously — so only IME
        // composition needs deferring.
        if textView.text != text, textView.markedTextRange == nil {
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

        init(onEdit: @escaping (String) -> Void, onSelectionChange: ((String?) -> Void)?) {
            self.onEdit = onEdit
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidChange(_ textView: UITextView) {
            onEdit(textView.text)
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
