import SwiftUI

@main
struct TokenBarApp: App {
    init() {
        // A SwiftPM binary has no Info.plist, so LSUIElement has no effect.
        // Use the accessory policy to hide the Dock icon. TRD-T10 adds LSUIElement to the app bundle.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("TokenBar", systemImage: "cup.and.saucer") {
            Text("TokenBar")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
