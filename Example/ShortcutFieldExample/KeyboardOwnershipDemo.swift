import AppKit
import Combine
import ShortcutField
import SwiftUI

struct KeyboardOwnershipDemo: View {
    @StateObject private var ownership = DemoOwnership()
    @State private var query = ""
    @State private var fires = 0
    @State private var recorded: DiscreteShortcut?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Input Ownership").font(.title)
            Text("Add an owner or press ⌘K. Native editing stays available while shortcuts pause in this window.")
            HStack {
                Button("Add Owner") { ownership.acquire() }
                Button("Release One") { ownership.releaseOne() }
                    .disabled(ownership.tokens.isEmpty)
                Button("Release All") { ownership.releaseAll() }
                    .disabled(ownership.tokens.isEmpty)
                Text("Owners: \(ownership.tokens.count)")
            }
            TextField("Native text input", text: $query)
                .textFieldStyle(.roundedBorder)
            Text("Shortcut fires: \(fires)")
                .accessibilityIdentifier("ownership-fire-count")
            Text("Try ⌃J, Escape, or ⌘B ⌘C. Open another window with File → New Window to check independent input.")
            HStack {
                Text("Recorder")
                ShortcutRecorderView($recorded)
                    .frame(width: 260)
            }
            Text("The recorder remains usable while ownership is active. Click it and record Tab, ⇧Tab, or ⌘K ⌘C.")
            Spacer()
        }
        .padding(28)
        .background(DemoWindowReader(ownership: ownership))
        .onShortcut("ctrl+j", scope: .window) { fires += 1 }
        .onShortcut("escape", scope: .window) { fires += 1 }
        .onShortcut("cmd+b cmd+c", scope: .window) { fires += 1 }
        .onShortcut("cmd+k", scope: .window) { ownership.acquire() }
        .onDisappear { ownership.releaseAll() }
    }
}

@MainActor
private final class DemoOwnership: ObservableObject {
    weak var window: NSWindow?
    @Published var tokens: [ShortcutKeyboardOwnership] = []

    func acquire() {
        guard let window else { return }
        tokens.append(ShortcutEventDispatcher.shared.acquireKeyboardOwnership(for: window))
    }

    func releaseOne() {
        tokens.popLast()?.release()
    }

    func releaseAll() {
        tokens.forEach { $0.release() }
        tokens = []
    }
}

private struct DemoWindowReader: NSViewRepresentable {
    let ownership: DemoOwnership

    func makeNSView(context _: Context) -> NSView {
        WindowView(ownership: ownership)
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class WindowView: NSView {
        let ownership: DemoOwnership

        init(ownership: DemoOwnership) {
            self.ownership = ownership
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            ownership.window = window
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}
