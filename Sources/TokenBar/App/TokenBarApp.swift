import SwiftUI

/// Owns the one store and makes one `DisplaySnapshot` after each refresh (TRD-T29).
/// The label and the popover only read `snapshot`, so a render never moves the roast or writes settings.
@MainActor @Observable
final class AppModel {
    /// Nil until the first refresh completes. The cold scan can take some seconds.
    private(set) var snapshot: DisplaySnapshot?

    private let store = UsageStore(providers: [ClaudeCodeProvider(), CodexProvider()])
    // The JSON files ship in the app bundle, and tests decode them. A failure is a packaging error.
    private let builder = DisplayBuilder(prices: try! .shipped(), cafe: try! .shipped())
    private var roasts = RoastSelector(roasts: try! Roast.shipped())
    private let tuition = TuitionTotal(defaults: .standard)

    /// Refreshes every 60 s (TRD 7) and builds the snapshot one time after each refresh.
    init() {
        Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
            }
        }
    }

    func refresh() async {
        await store.refresh()
        let snapshot = builder.build(snapshots: store.snapshots, errors: store.errors, lastRefresh: store.lastRefresh,
                                     now: Date(), roasts: &roasts, tuition: tuition)
        self.snapshot = snapshot
        LimitAlerts().refreshed(snapshot)
    }
}

struct TokenBarApp: App {
    private let model = AppModel()

    init() {
        // `swift run` has no Info.plist, so LSUIElement has no effect there. The accessory policy hides the Dock icon.
        NSApplication.shared.setActivationPolicy(.accessory)
        // The task runs after launch, so the window can come to the front. Refresh shows the new bar style at once.
        let model = model
        Task { Onboarding.showIfNeeded { Task { await model.refresh() } } }
    }

    var body: some Scene {
        MenuBarExtra {
            AppPopover(model: model)
        } label: {
            if let snapshot = model.snapshot {
                MenuBarLabel(snapshot: snapshot)
            } else {
                // The same width as the label, so the item does not move after the first scan.
                Image(nsImage: MenuBarLabel.image(symbol: "circle.dashed", text: ""))
            }
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView() }
    }
}

/// `openSettings` is an environment value, so a view must read it.
private struct AppPopover: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let snapshot = model.snapshot {
            PopoverView(snapshot: snapshot, actions: PopoverActions(
                refresh: { Task { await model.refresh() } },
                openSettings: {
                    // An accessory app is not active, so the Settings window opens behind other windows.
                    NSApplication.shared.activate()
                    openSettings()
                }))
        } else {
            ProgressView("Reading your logs…").padding(16).frame(width: 320)
        }
    }
}
