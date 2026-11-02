import SwiftUI
import UIKit

/// The search field's text input, on UIKit for the two things SwiftUI's field cannot do:
/// finish a typed host inline with the rest selected, and select the whole address the
/// moment the field takes focus.
///
/// `text` holds what the user typed, never the selected completion, so the suggestions
/// follow the typing. Return hands `onSubmit` the field's full text, completion included.
/// Typing replaces the completion, Delete removes it, and moving the caret accepts it.
struct AddressTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var completion: DomainCompletion
    /// Select the text already in the field the first time it takes focus.
    var selectsCarriedText: Bool
    var onSubmit: (String) -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.font = UIFont.preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UIColor(Palette.textPrimary)
        field.autocapitalizationType = .none
        field.returnKeyType = .search
        field.accessibilityIdentifier = "search.field"
        field.accessibilityLabel = String(localized: "Search")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.text = text
        field.addTarget(
            context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        context.coordinator.selectsCarriedText = selectsCarriedText
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.typedText(in: field) != text {
            coordinator.completionSuffix = ""
            field.text = text
        }
        if isFocused, !field.isFirstResponder {
            coordinator.focus(field)
        } else if !isFocused, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 120, height: uiView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AddressTextField
        /// The completion currently sitting selected at the end of the field.
        var completionSuffix = ""
        var selectsCarriedText = false
        /// Whether the last change removed text: a deletion never earns a new completion.
        private var lastEditDeleted = false
        /// True while the field is being edited by us, so its selection callbacks are ours.
        private var applying = false

        init(_ parent: AddressTextField) {
            self.parent = parent
        }

        /// What the user typed: the field's text without the selected completion.
        func typedText(in field: UITextField) -> String {
            let full = field.text ?? ""
            guard !completionSuffix.isEmpty, full.hasSuffix(completionSuffix),
                let range = field.selectedTextRange, !range.isEmpty
            else { return full }
            return String(full.dropLast(completionSuffix.count))
        }

        /// Takes focus once the field is in a window, then selects the carried address.
        func focus(_ field: UITextField) {
            guard field.window != nil else {
                Task { @MainActor [weak self, weak field] in
                    guard let self, let field, self.parent.isFocused, field.window != nil else { return }
                    self.focus(field)
                }
                return
            }
            guard field.becomeFirstResponder() else { return }
            selectCarriedTextIfNeeded(field)
        }

        private func selectCarriedTextIfNeeded(_ field: UITextField) {
            guard selectsCarriedText, !(field.text ?? "").isEmpty else { return }
            selectsCarriedText = false
            field.selectedTextRange = field.textRange(
                from: field.beginningOfDocument, to: field.endOfDocument)
        }

        @objc func editingChanged(_ field: UITextField) {
            completionSuffix = ""
            var full = field.text ?? ""
            let caretAtEnd =
                field.selectedTextRange.map { $0.isEmpty && $0.end == field.endOfDocument } ?? false
            if !lastEditDeleted, field.markedTextRange == nil, caretAtEnd,
                let suffix = parent.completion.suffix(for: full)
            {
                applying = true
                let typedLength = (full as NSString).length
                full += suffix
                field.text = full
                if let start = field.position(from: field.beginningOfDocument, offset: typedLength) {
                    field.selectedTextRange = field.textRange(from: start, to: field.endOfDocument)
                }
                completionSuffix = suffix
                applying = false
            }
            let typed = typedText(in: field)
            if parent.text != typed { parent.text = typed }
        }

        func textField(
            _ field: UITextField, shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            lastEditDeleted = string.isEmpty
            return true
        }

        /// Moving the caret off the completion keeps it as typed text.
        func textFieldDidChangeSelection(_ field: UITextField) {
            guard !applying, !completionSuffix.isEmpty else { return }
            if let range = field.selectedTextRange, !range.isEmpty, range.end == field.endOfDocument {
                return
            }
            completionSuffix = ""
            let full = field.text ?? ""
            Task { @MainActor [weak self] in
                guard let self, self.parent.text != full else { return }
                self.parent.text = full
            }
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            setFocus(true)
            // The caret lands after the field takes focus; the selection goes on top of it.
            if selectsCarriedText {
                Task { @MainActor [weak self, weak field] in
                    guard let self, let field else { return }
                    self.selectCarriedTextIfNeeded(field)
                }
            }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            setFocus(false)
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            completionSuffix = ""
            parent.onSubmit(field.text ?? "")
            return true
        }

        /// The binding changes off the current update pass, which may be what called us.
        private func setFocus(_ focused: Bool) {
            Task { @MainActor [weak self] in
                guard let self, self.parent.isFocused != focused else { return }
                self.parent.isFocused = focused
            }
        }
    }
}
