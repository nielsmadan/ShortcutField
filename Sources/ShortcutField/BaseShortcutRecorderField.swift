import AppKit

/// Implementation detail. Not intended for external use or subclassing.
///
/// Shared `NSSearchField` plumbing for the two concrete recorder fields,
/// ``ShortcutRecorderField`` and ``ContinuousShortcutRecorderField``: cell
/// class, intrinsic sizing, key-view eligibility, event-monitor storage, and
/// the click hit-test. Recording lifecycle, delegate callbacks, and event
/// handling differ between the two and stay in the subclasses.
///
/// This type is `public` only because Swift requires a public class's
/// superclass to also be public. It is `public` (not `open`), so external
/// code cannot subclass it, and its existence and shape are not part of the
/// package's API contract — refer to ``ShortcutRecorderField`` /
/// ``ContinuousShortcutRecorderField`` directly.
public class BaseShortcutRecorderField: NSSearchField {
    override public class var cellClass: AnyClass? {
        get { CenteredSearchFieldCell.self }
        set { super.cellClass = newValue }
    }

    /// Minimum intrinsic width. SwiftUI's `.frame(width:)` overrides this; the
    /// floor only matters when no explicit frame is set. Defaults to 160.
    public var minimumWidth: CGFloat = 160 {
        didSet { invalidateIntrinsicContentSize() }
    }

    /// The text color for the shortcut display. Nil uses the system default.
    public var fieldTextColor: NSColor? {
        didSet {
            textColor = fieldTextColor
            // In `.compact` style the color is baked into the attributed value, so a
            // plain `textColor` change wouldn't repaint it — re-render to pick it up.
            refreshDisplay()
        }
    }

    /// How the recorded shortcut is rendered in the field. Defaults to `.text`.
    /// In `.compact` style, gestures/scroll show SF Symbols and mouse clicks show
    /// short abbreviations, with the full text meaning surfaced as the field's
    /// tooltip. Changing it mid-recording is ignored until recording finalizes.
    public var labelStyle: ShortcutLabelStyle = .text {
        didSet {
            guard labelStyle != oldValue else { return }
            refreshDisplay()
        }
    }

    /// Re-render the committed shortcut using the current `labelStyle`. Overridden
    /// by each concrete field (which no-ops while recording, so an in-progress live
    /// preview isn't clobbered); the base implementation does nothing.
    func refreshDisplay() {}

    /// Font used to size inline symbol attachments; falls back to the system font.
    var displayFont: NSFont { font ?? .systemFont(ofSize: NSFont.systemFontSize) }

    /// Stamp the field's `alignment` onto an attributed value. Unlike `stringValue`,
    /// an attributed string carries its own paragraph style and ignores the control's
    /// alignment, so the icon/text would otherwise render left-aligned.
    func aligned(_ attributed: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        // Our paragraph style replaces the cell's default, so restore tail truncation
        // that the plain-string path would otherwise get for free on overflow.
        paragraph.lineBreakMode = .byTruncatingTail
        mutable.addAttribute(
            .paragraphStyle, value: paragraph, range: NSRange(location: 0, length: mutable.length)
        )
        return mutable
    }

    var bezeledHeight: CGFloat = 0
    nonisolated(unsafe) var eventMonitor: Any?
    var cancelButton: NSButtonCell?
    var canBecomeKey = false
    var isStartingRecording = false
    var gestures = GestureAccumulator()

    override public var canBecomeKeyView: Bool { canBecomeKey }

    override public var intrinsicContentSize: NSSize {
        NSSize(width: minimumWidth, height: bezeledHeight)
    }

    deinit {
        ShortcutRecordingState.endOnDeinit(for: self)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }

        canBecomeKey = false
        DispatchQueue.main.async { [weak self] in
            self?.canBecomeKey = true
        }
    }

    /// Captures the field's natural bezeled height. Subclasses call this once
    /// from `setup()`. Resolved here so `super` refers to `NSSearchField` rather
    /// than this class's `intrinsicContentSize` override.
    func captureBezeledHeight() {
        bezeledHeight = super.intrinsicContentSize.height
    }

    /// Relinquishes first-responder so further input flows to the host UI after
    /// recording finalizes or is cancelled — without this, the now-idle field
    /// keeps key focus.
    func blur() {
        window?.makeFirstResponder(nil)
    }

    /// Whether `event`'s location falls within the field's bounds (plus a small
    /// margin) — distinguishes clicks targeting the recorder from clicks
    /// elsewhere in the window.
    func isInsideField(_ event: NSEvent) -> Bool {
        let clickMargin: CGFloat = 3.0
        let point = convert(event.locationInWindow, from: nil)
        return bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(point)
    }
}
