import AppKit

/// NSSearchFieldCell subclass that vertically centers text when the bezel
/// is disabled.
class CenteredSearchFieldCell: NSSearchFieldCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: centeredFrame(cellFrame), in: controlView)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView,
                       editor textObj: NSText, delegate: Any?, event: NSEvent?)
    {
        super.edit(withFrame: centeredFrame(rect), in: controlView, editor: textObj,
                   delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView,
                         editor textObj: NSText, delegate: Any?,
                         start selStart: Int, length selLength: Int)
    {
        super.select(withFrame: centeredFrame(rect), in: controlView, editor: textObj,
                     delegate: delegate, start: selStart, length: selLength)
    }

    private func centeredFrame(_ frame: NSRect) -> NSRect {
        guard !isBezeled else { return frame }
        let minimumHeight = cellSize(forBounds: frame).height
        var adjusted = frame
        adjusted.origin.y += (frame.height - minimumHeight) / 2
        adjusted.size.height = minimumHeight
        return adjusted
    }
}
