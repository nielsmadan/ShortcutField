import AppKit

extension ContinuousShortcutRecorderField {
    /// Builds the chevron-button menu used to pick a continuous shortcut kind.
    static func makeContinuousShortcutMenu(target: AnyObject?, labelStyle: ShortcutLabelStyle = .text) -> NSMenu {
        let root = NSMenu()

        let pinch = NSMenu()
        pinch.addItem(menuItem(for: .pinchIn, target: target, labelStyle: labelStyle))
        pinch.addItem(menuItem(for: .pinchOut, target: target, labelStyle: labelStyle))
        let pinchHeader = NSMenuItem(title: "Pinch", action: nil, keyEquivalent: "")
        pinchHeader.submenu = pinch
        root.addItem(pinchHeader)

        let rotate = NSMenu()
        rotate.addItem(menuItem(for: .rotateClockwise, target: target, labelStyle: labelStyle))
        rotate.addItem(menuItem(for: .rotateCounterClockwise, target: target, labelStyle: labelStyle))
        let rotateHeader = NSMenuItem(title: "Rotate", action: nil, keyEquivalent: "")
        rotateHeader.submenu = rotate
        root.addItem(rotateHeader)

        let scroll = NSMenu()
        scroll.addItem(menuItem(for: .scroll(direction: .up), target: target, labelStyle: labelStyle))
        scroll.addItem(menuItem(for: .scroll(direction: .down), target: target, labelStyle: labelStyle))
        scroll.addItem(menuItem(for: .scroll(direction: .left), target: target, labelStyle: labelStyle))
        scroll.addItem(menuItem(for: .scroll(direction: .right), target: target, labelStyle: labelStyle))
        let scrollHeader = NSMenuItem(title: "Scroll", action: nil, keyEquivalent: "")
        scrollHeader.submenu = scroll
        root.addItem(scrollHeader)

        return root
    }

    private static func menuItem(
        for kind: ContinuousShortcut.Kind, target: AnyObject?, labelStyle: ShortcutLabelStyle
    ) -> NSMenuItem {
        // Modifiers are captured at click time from NSApp.currentEvent, not encoded here.
        let displayLabel = DiscreteShortcut.Step(kind: kind.asDiscreteKind, modifiers: []).displayString
        let item = NSMenuItem(
            title: displayLabel,
            action: #selector(ContinuousShortcutRecorderField.menuPicked(_:)),
            keyEquivalent: ""
        )
        // In compact style, show the SF Symbol alongside the text label so the picker
        // matches the field.
        if labelStyle == .compact, let symbolName = kind.asDiscreteKind.symbolName {
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: displayLabel)
        }
        item.target = target
        item.representedObject = KindBox(kind: kind)
        return item
    }

    fileprivate final class KindBox: NSObject {
        let kind: ContinuousShortcut.Kind
        init(kind: ContinuousShortcut.Kind) { self.kind = kind }
    }

    @objc func menuPicked(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? KindBox else { return }
        let modifiers = NSApp.currentEvent?.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command]) ?? []
        handleMenuPickedKind(box.kind, modifiers: modifiers)
    }
}
