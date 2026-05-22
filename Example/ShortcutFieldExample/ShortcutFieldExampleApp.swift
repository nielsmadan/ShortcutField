import AppKit
import ShortcutField
import SwiftUI

@main
struct ShortcutFieldExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .suppressShortcutBeep()
                .onAppear {
                    // When launched directly (not via LaunchServices/open),
                    // the app needs an explicit activation policy to come
                    // to the foreground.
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                }
        }
    }
}
