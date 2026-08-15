import AppKit
import SwiftUI

// MARK: - Symbol / abbreviation mapping

public extension DiscreteShortcut.Kind {
    /// SF Symbol name representing this kind, or `nil` for kinds that have no clean
    /// icon (keys, and mouse clicks — no per-button symbol exists).
    ///
    /// Gesture symbols are best-fit rather than literal (e.g. pinch maps to the
    /// diagonal zoom arrows). All names are available on the macOS 13 floor.
    var symbolName: String? {
        switch self {
        case .rotateClockwise: "arrow.clockwise"
        case .rotateCounterClockwise: "arrow.counterclockwise"
        case .pinchIn: "arrow.down.right.and.arrow.up.left"
        case .pinchOut: "arrow.up.left.and.arrow.down.right"
        case .smartMagnify: "plus.magnifyingglass"
        case let .scroll(direction):
            switch direction {
            case .up: "arrow.up"
            case .down: "arrow.down"
            case .left: "arrow.left"
            case .right: "arrow.right"
            }
        case .key, .mouseButton: nil
        }
    }
}

extension DiscreteShortcut.Kind {
    /// A compact text form and its full-text meaning, for kinds that have no icon
    /// but whose text label is long — currently the mouse clicks (`LMB`/`RMB`/
    /// `MMB`, `Mouse4…`). `nil` for kinds rendered as an icon or already compact.
    var compactLabel: (short: String, label: String)? {
        guard case let .mouseButton(number) = self else { return nil }
        let short = switch number {
        case 0: "LMB"
        case 1: "RMB"
        case 2: "MMB"
        default: "Mouse\(number + 1)"
        }
        return (short, displayLabel)
    }

    func displayElement(style: ShortcutLabelStyle) -> ShortcutDisplayElement {
        guard style == .compact else { return .text(displayLabel) }
        if let symbolName {
            return .symbol(name: symbolName, label: displayLabel)
        }
        if let compactLabel {
            return .abbreviation(short: compactLabel.short, label: compactLabel.label)
        }
        return .text(displayLabel)
    }
}

// MARK: - Segmented display model

/// One piece of a rendered shortcut label.
///
/// A shortcut renders as a sequence of these. Icons and abbreviations each carry
/// their full-text `label` so a compact legend can still reveal the meaning on
/// hover (see ``ShortcutLabel``) and expose it to accessibility.
public enum ShortcutDisplayElement: Sendable, Equatable, Hashable {
    /// Plain text: a modifier prefix (e.g. `⌘`), a key name, an inter-step space,
    /// or any kind rendered in ``ShortcutLabelStyle/text`` style.
    case text(String)
    /// An SF Symbol icon plus its full-text meaning (for tooltip / accessibility).
    case symbol(name: String, label: String)
    /// A compact abbreviation (e.g. `LMB`) plus its full-text meaning.
    case abbreviation(short: String, label: String)
}

public extension DiscreteShortcut.Step {
    /// Break this step into renderable elements for the given style.
    ///
    /// The modifier prefix leads. When the kind renders as text it merges with the
    /// prefix into one element (so `⌘K` stays tight); an icon or abbreviation
    /// follows the prefix as its own element.
    func displayElements(style: ShortcutLabelStyle) -> [ShortcutDisplayElement] {
        let prefix = modifiers.symbolicRepresentation
        switch kind.displayElement(style: style) {
        case let .text(label):
            return [.text(prefix + label)]
        case let kindElement:
            return prefix.isEmpty ? [kindElement] : [.text(prefix), kindElement]
        }
    }
}

public extension DiscreteShortcut {
    /// Break the full (possibly multi-step) shortcut into renderable elements.
    /// Steps are separated by a `.text(" ")` element, matching `displayString`.
    func displayElements(style: ShortcutLabelStyle) -> [ShortcutDisplayElement] {
        steps.enumerated().flatMap { index, step in
            (index == 0 ? [] : [ShortcutDisplayElement.text(" ")]) + step.displayElements(style: style)
        }
    }
}

public extension ContinuousShortcut {
    /// Break the shortcut into renderable elements. Same format as a single-step
    /// ``DiscreteShortcut``.
    func displayElements(style: ShortcutLabelStyle) -> [ShortcutDisplayElement] {
        asDiscreteStep.displayElements(style: style)
    }
}

public extension Shortcut {
    /// Break the shortcut into renderable elements, forwarding to the wrapped value.
    func displayElements(style: ShortcutLabelStyle) -> [ShortcutDisplayElement] {
        switch self {
        case let .discrete(shortcut): shortcut.displayElements(style: style)
        case let .continuous(shortcut): shortcut.displayElements(style: style)
        }
    }
}

// MARK: - AppKit attributed rendering

public extension DiscreteShortcut.Step {
    /// Attributed representation for AppKit text views. Icon elements become inline
    /// SF Symbol image attachments; text and abbreviations become text runs.
    @MainActor
    func attributedDisplayString(style: ShortcutLabelStyle, font: NSFont, color: NSColor?) -> NSAttributedString {
        shortcutAttributedString(from: displayElements(style: style), font: font, color: color)
    }
}

public extension DiscreteShortcut {
    /// Attributed representation of the full shortcut for AppKit text views.
    @MainActor
    func attributedDisplayString(style: ShortcutLabelStyle, font: NSFont, color: NSColor?) -> NSAttributedString {
        shortcutAttributedString(from: displayElements(style: style), font: font, color: color)
    }
}

public extension ContinuousShortcut {
    /// Attributed representation for AppKit text views.
    @MainActor
    func attributedDisplayString(style: ShortcutLabelStyle, font: NSFont, color: NSColor?) -> NSAttributedString {
        shortcutAttributedString(from: displayElements(style: style), font: font, color: color)
    }
}

public extension Shortcut {
    /// Attributed representation for AppKit text views.
    @MainActor
    func attributedDisplayString(style: ShortcutLabelStyle, font: NSFont, color: NSColor?) -> NSAttributedString {
        shortcutAttributedString(from: displayElements(style: style), font: font, color: color)
    }
}

/// Build an attributed string from display elements, resolving symbols to inline
/// image attachments. Falls back to the text label if a symbol is unavailable.
///
/// `@MainActor`: constructs AppKit image/text objects, which must be main-thread-confined.
@MainActor
func shortcutAttributedString(from elements: [ShortcutDisplayElement], font: NSFont,
                              color: NSColor?) -> NSAttributedString
{
    let resolvedColor = color ?? .labelColor
    let textAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: resolvedColor]
    let result = NSMutableAttributedString()
    for element in elements {
        switch element {
        case let .text(string):
            result.append(NSAttributedString(string: string, attributes: textAttributes))
        case let .abbreviation(short, _):
            result.append(NSAttributedString(string: short, attributes: textAttributes))
        case let .symbol(name, label):
            if let attachment = symbolAttachmentString(name: name, label: label, font: font, color: resolvedColor) {
                result.append(attachment)
            } else {
                result.append(NSAttributedString(string: label, attributes: textAttributes))
            }
        }
    }
    return result
}

@MainActor
private func symbolAttachmentString(name: String, label: String, font: NSFont, color: NSColor) -> NSAttributedString? {
    let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
        .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
    guard
        let image = NSImage(systemSymbolName: name, accessibilityDescription: label)?
        .withSymbolConfiguration(configuration)
    else {
        return nil
    }
    let attachment = NSTextAttachment()
    attachment.image = image
    // Vertically center the glyph around the font's cap height so it sits on the
    // text baseline rather than the descender.
    let yOffset = (font.capHeight - image.size.height) / 2
    attachment.bounds = CGRect(x: 0, y: yOffset, width: image.size.width, height: image.size.height)
    return NSAttributedString(attachment: attachment)
}

// MARK: - SwiftUI Text convenience

public extension DiscreteShortcut.Step {
    /// A `Text` combining icon and text runs. Convenient for read-only display;
    /// for per-icon hover tooltips use ``ShortcutLabel`` (a `Text` cannot carry
    /// per-run help).
    func displayText(style: ShortcutLabelStyle) -> Text {
        text(from: displayElements(style: style))
    }
}

public extension DiscreteShortcut {
    /// A `Text` combining icon and text runs for the full shortcut.
    func displayText(style: ShortcutLabelStyle) -> Text {
        text(from: displayElements(style: style))
    }
}

public extension ContinuousShortcut {
    /// A `Text` combining icon and text runs.
    func displayText(style: ShortcutLabelStyle) -> Text {
        text(from: displayElements(style: style))
    }
}

public extension Shortcut {
    /// A `Text` combining icon and text runs.
    func displayText(style: ShortcutLabelStyle) -> Text {
        text(from: displayElements(style: style))
    }
}

private func text(from elements: [ShortcutDisplayElement]) -> Text {
    elements.reduce(Text(verbatim: "")) { partial, element in
        switch element {
        case let .text(string): partial + Text(verbatim: string)
        case let .abbreviation(short, _): partial + Text(verbatim: short)
        case let .symbol(name, _): partial + Text(Image(systemName: name))
        }
    }
}
