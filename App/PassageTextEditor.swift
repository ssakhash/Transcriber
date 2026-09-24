import AppKit
import SwiftUI
import TranscriberKit

// NSTextView keeps the focused editor's wrapping and height in sync during split-view resizing.
struct PassageTextEditor: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WrappingTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        let view = WrappingTextView(frame: .zero, textContainer: container)
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.drawsBackground = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.textContainerInset = .zero
        view.allowsUndo = true
        view.isContinuousSpellCheckingEnabled = true
        view.isAutomaticSpellingCorrectionEnabled = false
        view.font = .preferredFont(forTextStyle: .title3)
        view.textColor = .labelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font: view.font!, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        view.string = text
        view.setAccessibilityLabel(accessibilityLabel)
        return view
    }

    func updateNSView(_ view: WrappingTextView, context: Context) {
        context.coordinator.parent = self
        if view.string != text {
            let selection = view.selectedRange()
            view.string = text
            view.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            view.invalidateIntrinsicContentSize()
        }
        view.setAccessibilityLabel(accessibilityLabel)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WrappingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: nsView.measuredHeight(for: width))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PassageTextEditor
        init(_ parent: PassageTextEditor) { self.parent = parent }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            guard let replacementString else { return true }
            let cleaned = TextPolicy.clean(replacementString)
            guard cleaned != replacementString else { return true }
            // Normalize before AppKit records the edit so undo retains the correct character ranges.
            textView.insertText(cleaned, replacementRange: affectedCharRange)
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? WrappingTextView else { return }
            parent.text = TextPolicy.clean(view.string)
            view.invalidateIntrinsicContentSize()
        }
    }
}

final class WrappingTextView: NSTextView {
    func measuredHeight(for width: CGFloat) -> CGFloat {
        guard let textContainer, let layoutManager else { return 24 }
        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let lineHeight = layoutManager.defaultLineHeight(for: font ?? .preferredFont(forTextStyle: .title3))
        let textBottom = layoutManager.usedRect(for: textContainer).maxY
        let insertionLineBottom = layoutManager.extraLineFragmentRect.maxY
        return ceil(max(lineHeight, textBottom, insertionLineBottom))
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(for: max(1, bounds.width)))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { invalidateIntrinsicContentSize() }
    }

    override func insertTab(_ sender: Any?) { window?.selectNextKeyView(self) }
    override func insertBacktab(_ sender: Any?) { window?.selectPreviousKeyView(self) }
}
