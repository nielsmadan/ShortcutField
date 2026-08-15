import AppKit

extension ContinuousShortcutRecorderField {
    /// Builds the chevron-button menu used to pick a continuous shortcut kind.
    static func makeContinuousShortcutMenu(target: AnyObject?, labelStyle: ShortcutLabelStyle = .text) -> NSMenu {
        let sections: [(title: String, kinds: [ContinuousShortcut.Kind])] = [
            ("Pinch", [.pinchIn, .pinchOut]),
            ("Rotate", [.rotateClockwise, .rotateCounterClockwise]),
            ("Scroll", [
                .scroll(direction: .up), .scroll(direction: .down),
                .scroll(direction: .left), .scroll(direction: .right),
            ]),
        ]

        let root = NSMenu()
        for section in sections {
            let submenu = NSMenu()
            for kind in section.kinds {
                submenu.addItem(menuItem(for: kind, target: target, labelStyle: labelStyle))
            }
            let header = NSMenuItem(title: section.title, action: nil, keyEquivalent: "")
            header.submenu = submenu
            root.addItem(header)
        }
        return root
    }

    private static func menuItem(
        for kind: ContinuousShortcut.Kind, target: AnyObject?, labelStyle: ShortcutLabelStyle
    ) -> NSMenuItem {
        // Modifiers are captured at click time from NSApp.currentEvent, not encoded here.
        let displayLabel = ContinuousShortcut(kind: kind, modifiers: []).displayString
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
        let modifiers = DiscreteShortcut.canonicalModifiers(NSApp.currentEvent?.modifierFlags ?? [])
        handleMenuPickedKind(box.kind, modifiers: modifiers)
    }
}
