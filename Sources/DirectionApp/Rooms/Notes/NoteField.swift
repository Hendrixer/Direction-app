import SwiftUI
import AppKit
import DirectionCore

/// The multi-line note field (`.field.area`). A real text view, so it checks spelling and
/// grammar as you type like any Mac text field. ↩ submits, ⇧↩ adds a line, ⇥ takes the
/// editor's suggested kind, ⌥1–⌥5 set the kind, esc stops writing. "@" opens the library at the
/// caret (techniques.md › The library), and the film's scenes, setups and takes (notes.md › Naming
/// footage); a name picked from it shows in the director's color.
struct NoteField: View {
    @Binding var text: String
    var placeholder: String
    var label: String
    /// The film's scenes, setups and takes, named after "@" as Dailies shows them.
    var footage: [FootageName] = []
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
        NoteTextViewRepresentable(text: $text, label: label, footage: footage, focusToken: focusToken, contentHeight: $contentHeight,
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
    var footage: [FootageName]
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
        context.coordinator.highlight(view)
        view.setAccessibilityLabel(label)
        view.onFocusChange = { focused in
            if !focused { context.coordinator.closeMention() }
            context.coordinator.parent.onFocusChange(focused)
        }
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
            context.coordinator.highlight(view)
        } else if footage != context.coordinator.shownFootage { context.coordinator.highlight(view) }
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
            highlight(view)
            updateMention(view)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, mention != nil else { return }
            updateMention(view)
        }

        // MARK: "@"

        var mention: (range: NSRange, query: String)?
        var items: [LibraryEntry] = []
        var selected = 0
        var popover: NSPopover?
        weak var textView: NSTextView?

        /// Opens, narrows or closes the library at the "@" before the caret.
        func updateMention(_ view: NSTextView) {
            textView = view
            let library = LibraryModel.shared
            if library.entries.isEmpty { library.load() }
            let sel = view.selectedRange()
            guard view.window?.firstResponder === view, sel.length == 0, let t = MentionToken.find(view.string, caret: sel.location) else { closeMention(); return }
            let found = Array(library.search(t.query, footage: parent.footage).prefix(6)), q = t.query.lowercased().trimmingCharacters(in: .whitespaces)
            // A whole name written and a space after it: done.
            if found.isEmpty || (t.query.hasSuffix(" ") && found.contains { $0.name.lowercased() == q }) { closeMention(); return }
            if mention?.range.location != t.range.location { selected = 0 }
            mention = t; items = found; selected = min(selected, found.count - 1)
            showMention(view, at: t.range)
        }

        func showMention(_ view: NSTextView, at range: NSRange) {
            let content = MentionList(items: items, selected: selected) { [weak self] e in self?.pickMention(e) }
            if let popover, popover.isShown, let host = popover.contentViewController as? NSHostingController<MentionList> { host.rootView = content; return }
            guard let layout = view.layoutManager, let container = view.textContainer else { return }
            var rect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil), in: container)
            rect.origin.x += view.textContainerOrigin.x; rect.origin.y += view.textContainerOrigin.y
            let p = NSPopover()
            p.contentViewController = NSHostingController(rootView: content)
            p.behavior = .applicationDefined; p.animates = false
            p.show(relativeTo: rect, of: view, preferredEdge: .maxY)
            popover = p
            // Typing carries on in the note.
            view.window?.makeFirstResponder(view)
        }

        func closeMention() {
            popover?.close(); popover = nil; mention = nil; items = []
        }

        func pickMention(_ e: LibraryEntry) {
            guard let view = textView, let m = mention else { return }
            closeMention()
            view.insertText("@\(e.name) ", replacementRange: m.range)
        }

        /// The footage names last highlighted, so new ones light up as Dailies changes.
        var shownFootage: [FootageName] = []

        /// Names from the library and the film's footage in the note, in the director's color.
        func highlight(_ view: NSTextView) {
            guard let layout = view.layoutManager else { return }
            let s = view.string as NSString, all = NSRange(location: 0, length: s.length)
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
            shownFootage = parent.footage
            guard s.contains("@") else { return }
            for name in LibraryModel.shared.entries.map(\.name) + parent.footage.map(\.name) {
                var from = 0
                while from < s.length {
                    let r = s.range(of: "@" + name, options: .caseInsensitive, range: NSRange(location: from, length: s.length - from))
                    guard r.location != NSNotFound else { break }
                    layout.addTemporaryAttribute(.foregroundColor, value: NSColor(Gate.Voice.director), forCharacterRange: r)
                    from = r.location + r.length
                }
            }
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
            // While the library is open at "@", the arrows move through it and ↩ or ⇥ picks.
            if mention != nil, !items.isEmpty {
                switch selector {
                case #selector(NSResponder.moveDown(_:)): selected = min(items.count - 1, selected + 1); showMention(view, at: mention!.range); return true
                case #selector(NSResponder.moveUp(_:)): selected = max(0, selected - 1); showMention(view, at: mention!.range); return true
                case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)): pickMention(items[selected]); return true
                case #selector(NSResponder.cancelOperation(_:)): closeMention(); return true
                default: break
                }
            }
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
