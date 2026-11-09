import AppKit
@testable import ShortcutField
import SwiftUI
import Testing

@MainActor
@Suite(.serialized)
struct ShortcutRecorderViewTests {
    @MainActor
    final class Model: ObservableObject {
        @Published var shortcut: DiscreteShortcut?
        @Published var disabled = false
    }

    private struct Harness: View {
        @ObservedObject var model: Model

        var body: some View {
            ShortcutRecorderView($model.shortcut)
                .disabled(model.disabled)
        }
    }

    @Test func disablingTheView_endsRecording() throws {
        let model = Model()
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Harness(model: model))
        window.orderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        let field = try #require(window.contentView.flatMap(firstRecorder))
        field.startRecording()
        defer { field.endRecording() }

        model.disabled = true
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()

        #expect(!field.isEnabled)
        #expect(!field.isRecording)
    }

    private func firstRecorder(in root: NSView) -> ShortcutRecorderField? {
        if let field = root as? ShortcutRecorderField {
            return field
        }
        return root.subviews.lazy.compactMap { firstRecorder(in: $0) }.first
    }
}
