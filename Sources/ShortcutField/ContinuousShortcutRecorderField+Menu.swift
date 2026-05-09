import AppKit

extension ContinuousShortcutRecorderField {
    /// Builds the chevron-button menu used to pick a continuous shortcut kind.
    /// Internal: also called by tests to verify menu contents.
    ///
    /// The menu lists Pinch, Rotate, and Scroll. Smart Magnify and discrete kinds
    /// (key, mouseButton) are excluded — they're not valid for ContinuousShortcut.
    static func makeContinuousShortcutMenu(target: AnyObject?) -> NSMenu {
        let root = NSMenu()

        let pinch = NSMenu()
        pinch.addItem(menuItem(for: .pinchIn, target: target))
        pinch.addItem(menuItem(for: .pinchOut, target: target))
        let pinchHeader = NSMenuItem(title: "Pinch", action: nil, keyEquivalent: "")
        pinchHeader.submenu = pinch
        root.addItem(pinchHeader)

        let rotate = NSMenu()
        rotate.addItem(menuItem(for: .rotateClockwise, target: target))
        rotate.addItem(menuItem(for: .rotateCounterClockwise, target: target))
        let rotateHeader = NSMenuItem(title: "Rotate", action: nil, keyEquivalent: "")
        rotateHeader.submenu = rotate
        root.addItem(rotateHeader)

        let scroll = NSMenu()
        scroll.addItem(menuItem(for: .scroll(direction: .up), target: target))
        scroll.addItem(menuItem(for: .scroll(direction: .down), target: target))
        scroll.addItem(menuItem(for: .scroll(direction: .left), target: target))
        scroll.addItem(menuItem(for: .scroll(direction: .right), target: target))
        let scrollHeader = NSMenuItem(title: "Scroll", action: nil, keyEquivalent: "")
        scrollHeader.submenu = scroll
        root.addItem(scrollHeader)

        return root
    }

    private static func menuItem(
        for kind: ContinuousShortcut.Kind, target: AnyObject?
    ) -> NSMenuItem {
        // Modifiers are captured at click time from NSApp.currentEvent, not encoded here.
        let displayLabel = Shortcut.Step(kind: kind.asShortcutKind, modifiers: []).displayString
        let item = NSMenuItem(
            title: displayLabel,
            action: #selector(ContinuousShortcutRecorderField.menuPicked(_:)),
            keyEquivalent: ""
        )
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
