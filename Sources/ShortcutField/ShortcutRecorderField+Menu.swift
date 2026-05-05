import AppKit

extension ShortcutRecorderField {
    /// Builds the chevron-button menu used to pick a non-keyboard shortcut kind.
    /// Internal: also called by tests to verify menu contents.
    ///
    /// The menu lists all bindable kinds *except keyboard* (since keys can't be enumerated):
    /// Pinch, Rotate, Smart Magnify, Mouse, Scroll.
    static func makeShortcutMenu(target: AnyObject?) -> NSMenu {
        let root = NSMenu()

        // Section: Pinch
        let pinch = NSMenu()
        pinch.addItem(menuItem(for: .pinchIn, target: target))
        pinch.addItem(menuItem(for: .pinchOut, target: target))
        let pinchHeader = NSMenuItem(title: "Pinch", action: nil, keyEquivalent: "")
        pinchHeader.submenu = pinch
        root.addItem(pinchHeader)

        // Section: Rotate
        let rotate = NSMenu()
        rotate.addItem(menuItem(for: .rotateClockwise, target: target))
        rotate.addItem(menuItem(for: .rotateCounterClockwise, target: target))
        let rotateHeader = NSMenuItem(title: "Rotate", action: nil, keyEquivalent: "")
        rotateHeader.submenu = rotate
        root.addItem(rotateHeader)

        // Smart Magnify (no submenu)
        root.addItem(menuItem(for: .smartMagnify, target: target))

        // Section: Mouse
        // Bare Left Click (mouseButton number 0 with no modifiers) is reserved for UI
        // interaction by the recorder field, so we omit it here. Users who want a
        // modified Left Click (e.g. ⌃⇧Left Click) must record it live with modifiers held.
        let mouse = NSMenu()
        mouse.addItem(menuItem(for: .mouseButton(number: 1), target: target))
        mouse.addItem(menuItem(for: .mouseButton(number: 2), target: target))
        let mouseHeader = NSMenuItem(title: "Mouse", action: nil, keyEquivalent: "")
        mouseHeader.submenu = mouse
        root.addItem(mouseHeader)

        // Section: Scroll
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
        for kind: Shortcut.Kind, target: AnyObject?
    ) -> NSMenuItem {
        // Construct a temporary shortcut purely to reuse displayString — modifiers
        // are captured at click time from NSApp.currentEvent.
        let displayLabel = Shortcut(kind: kind, modifiers: []).displayString
        let item = NSMenuItem(
            title: displayLabel,
            action: #selector(ShortcutRecorderField.menuPicked(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.representedObject = KindBox(kind: kind)
        return item
    }

    fileprivate final class KindBox: NSObject {
        let kind: Shortcut.Kind
        init(kind: Shortcut.Kind) { self.kind = kind }
    }

    @objc func menuPicked(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? KindBox else { return }
        let modifiers = NSApp.currentEvent?.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.shift, .control, .option, .command]) ?? []
        handleMenuPickedKind(box.kind, modifiers: modifiers)
    }
}
