import SwiftUI
import AppKit

/// The multi-line note field (`.field.area`). A real text view, so it checks spelling and
/// grammar as you type like any Mac text field. ↩ submits, ⇧↩ adds a line, ⇥ takes the
/// editor's suggested kind, ⌥1–⌥5 set the kind, esc stops writing.
struct NoteField: View {
    @Binding var text: String
    var placeholder: String
    var label: String
    var minHeight: CGFloat = 64
    var maxHeight: CGFloat = 160
    /// Bump to put the caret in the field.
    var focusToken: Int = 0
    var onFocusChange: (Bool) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var onEscape: (() -> Void)? = nil
    /// Return true when ⇥ was used (to take a suggestion); otherwise focus moves on.
    var onTab: (() -> Bool)? = nil
    var onOptionDigit: ((Int) -> Void)? = nil

    @State private var focused = false
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        NoteTextViewRepresentable(text: $text, label: label, focusToken: focusToken, contentHeight: $contentHeight,
                                  onFocusChange: { focused = $0; onFocusChange($0) }, onSubmit: onSubmit, onEscape: onEscape, onTab: onTab, onOptionDigit: onOptionDigit)
            .frame(height: max(minHeight, min(maxHeight, contentHeight)))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).font(Gate.Font.body).foregroundStyle(Gate.Text.disabled)
                        .padding(.horizontal, 11).padding(.top, NoteTextMetrics.inset.height).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .background(GateFieldBackground(focused: focused))
    }
}

enum NoteTextMetrics {
    static let size: CGFloat = 13
    static var font: NSFont { .systemFont(ofSize: size) }
    /// CSS 13px/1.45: the leading beyond the font's own line height.
    static var extraLeading: CGFloat { max(0, size * 1.45 - (font.ascender - font.descender + font.leading)) }
    static var inset: NSSize { NSSize(width: 11, height: 9 + extraLeading / 2) }
}

final class NoteTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    var onOptionDigit: ((Int) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocusChange?(false) }
        return ok
    }
    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if mods == .option, let onOptionDigit, let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...5).contains(digit) {
            onOptionDigit(digit)
            return
        }
        super.keyDown(with: event)
    }
}

private struct NoteTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    var label: String
    var focusToken: Int
    @Binding var contentHeight: CGFloat
    var onFocusChange: (Bool) -> Void
    var onSubmit: () -> Void
    var onEscape: (() -> Void)?
    var onTab: (() -> Bool)?
    var onOptionDigit: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let container = NSTextContainer(containerSize: NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)

        let view = NoteTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 64), textContainer: container)
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isContinuousSpellCheckingEnabled = true
        view.isGrammarCheckingEnabled = true
        view.isAutomaticQuoteSubstitutionEnabled = true
        view.isAutomaticDashSubstitutionEnabled = true
        view.textContainerInset = NoteTextMetrics.inset
        view.font = NoteTextMetrics.font
        view.textColor = NSColor(Gate.Text.primary)
        view.insertionPointColor = NSColor(Gate.Text.primary)
        view.selectedTextAttributes = [.backgroundColor: NSColor(Gate.Surface.hover)]
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = NoteTextMetrics.extraLeading
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font: NoteTextMetrics.font, .foregroundColor: NSColor(Gate.Text.primary), .paragraphStyle: paragraph]
        view.string = text
        view.delegate = context.coordinator
        view.setAccessibilityLabel(label)
        view.onFocusChange = { focused in context.coordinator.parent.onFocusChange(focused) }
        view.onOptionDigit = onOptionDigit.map { _ in { digit in context.coordinator.parent.onOptionDigit?(digit) } }
        scroll.documentView = view
        context.coordinator.focusToken = focusToken
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NoteTextView else { return }
        if view.string != text {
            view.string = text
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        view.setAccessibilityLabel(label)
        view.onOptionDigit = onOptionDigit.map { _ in { digit in context.coordinator.parent.onOptionDigit?(digit) } }
        context.coordinator.measure(view)
        if focusToken != context.coordinator.focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async {
                guard let window = view.window, window.firstResponder !== view else { return }
                window.makeFirstResponder(view)
                view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextViewRepresentable
        var focusToken = 0
        init(_ parent: NoteTextViewRepresentable) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            measure(view)
        }

        func measure(_ view: NSTextView) {
            guard let layout = view.layoutManager, let container = view.textContainer else { return }
            layout.ensureLayout(for: container)
            let height = ceil(layout.usedRect(for: container).height + view.textContainerInset.height * 2)
            if abs(height - parent.contentHeight) > 0.5 {
                let binding = parent.$contentHeight
                DispatchQueue.main.async { binding.wrappedValue = height }
            }
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    view.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit()
                }
                return true
            case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                view.insertNewlineIgnoringFieldEditor(nil)
                return true
            case #selector(NSResponder.insertTab(_:)):
                if parent.onTab?() == true { return true }
                view.window?.selectNextKeyView(nil)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                view.window?.selectPreviousKeyView(nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                guard let onEscape = parent.onEscape else { return false }
                onEscape()
                return true
            default:
                return false
            }
        }
    }
}
