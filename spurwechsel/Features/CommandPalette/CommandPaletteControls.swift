import AppKit
import SwiftUI

struct CommandPalettePrimaryButtonStyle: ButtonStyle {
    let theme: SpurTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.accentForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.accent.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.accent.opacity(0.9), lineWidth: 1)
            )
    }
}

struct CommandPaletteSecondaryButtonStyle: ButtonStyle {
    let theme: SpurTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.panelMuted.opacity(configuration.isPressed ? 0.88 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
    }
}

struct CommandBarSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isFocused: Bool
    let focusRequestID: Int
    let onSubmit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    func makeNSView(context: Context) -> CommandBarSearchTextField {
        let field = CommandBarSearchTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isBezeled = false
        field.font = .systemFont(ofSize: 16, weight: .medium)
        field.placeholderString = placeholder
        field.stringValue = text
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("commandbar.search")
        return field
    }

    func updateNSView(_ nsView: CommandBarSearchTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        context.coordinator.parent = self
        nsView.setAccessibilityIdentifier("commandbar.search")
        nsView.applyFocusRequest(id: focusRequestID, isFocused: isFocused)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandBarSearchField

        init(parent: CommandBarSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else {
                return
            }
            if parent.text != textField.stringValue {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onMoveUp()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onMoveDown()
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

final class CommandBarSearchTextField: NSTextField {
    private var focusRequestID: Int?
    private var fulfilledFocusRequestID: Int?
    private var scheduledFocusRequestID: Int?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let focusRequestID else {
            return
        }
        focusIfNeeded(requestID: focusRequestID)
    }

    func applyFocusRequest(id: Int, isFocused: Bool) {
        guard isFocused else {
            focusRequestID = nil
            fulfilledFocusRequestID = nil
            scheduledFocusRequestID = nil
            return
        }

        if let latestFocusRequestID = focusRequestID, id < latestFocusRequestID {
            return
        }

        focusRequestID = id
        if let window, window.firstResponder !== currentEditor() {
            fulfilledFocusRequestID = nil
        }
        focusIfNeeded(requestID: id)
    }

    private func focusIfNeeded(requestID: Int) {
        guard focusRequestID == requestID,
              fulfilledFocusRequestID != requestID,
              scheduledFocusRequestID != requestID
        else {
            return
        }

        scheduledFocusRequestID = requestID
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            guard self.focusRequestID == requestID else {
                return
            }
            self.scheduledFocusRequestID = nil
            guard let window = self.window else {
                return
            }
            if window.firstResponder === self.currentEditor() || window.makeFirstResponder(self) {
                self.fulfilledFocusRequestID = requestID
            }
        }
    }
}

struct CommandPaletteConfirmationKeyCapture: NSViewRepresentable {
    let focusRequestID: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    func makeNSView(context _: Context) -> ConfirmationKeyCaptureView {
        ConfirmationKeyCaptureView()
    }

    func updateNSView(_ nsView: ConfirmationKeyCaptureView, context _: Context) {
        nsView.onConfirm = onConfirm
        nsView.onCancel = onCancel
        nsView.applyFocusRequest(id: focusRequestID)
    }
}

final class ConfirmationKeyCaptureView: NSView {
    var onConfirm: () -> Void = {}
    var onCancel: () -> Void = {}

    private var lastFocusRequestID: Int?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onConfirm()
        case 53:
            onCancel()
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }

    func applyFocusRequest(id: Int) {
        guard lastFocusRequestID != id else {
            return
        }
        lastFocusRequestID = id
        focusIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfNeeded()
    }

    private func focusIfNeeded() {
        guard lastFocusRequestID != nil else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else {
                return
            }
            if window.firstResponder !== self {
                _ = window.makeFirstResponder(self)
            }
        }
    }
}
