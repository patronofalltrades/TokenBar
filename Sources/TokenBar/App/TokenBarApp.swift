import SwiftUI

/// Owns the one store and makes one `DisplaySnapshot` after each refresh (TRD-T29).
/// The label and the popover only read `snapshot`, so a render never moves the roast or writes settings.
@MainActor @Observable
final class AppModel {
    /// Nil until the first refresh completes. The cold scan can take some seconds.
    private(set) var snapshot: DisplaySnapshot?

    private let store = UsageStore(providers: [ClaudeCodeProvider(), CodexProvider()])
    // The JSON files ship in the app bundle, and tests decode them. A failure is a packaging error.
    private let builder = DisplayBuilder(prices: try! .shipped(), cafe: try! .shipped(), water: try! .shipped())
    private var roasts = RoastSelector(roasts: try! Roast.shipped())
    private let tuition = TuitionTotal(defaults: .standard)
    private var shown = DisplaySettings()
    private var watcher: FileWatcher?
    private var pending: Set<ProviderID> = []
    private var scheduled: Set<ProviderID> = []
    private static let minimumGap: TimeInterval = 5

    /// Refreshes 1.5 to 6.5 s after a log change (IES-225), and every 60 s as a fallback (TRD 7).
    /// Builds the snapshot one time after each refresh.
    /// A change of the index or the roasts setting builds it again at once, from the last data (IES-224).
    init() {
        Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
            }
        }
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                guard let self else { return }
                // The builder also writes settings. Those writes do not change `DisplaySettings`, so no loop.
                if DisplaySettings() != shown, store.lastRefresh != nil { build() }
            }
        }
        // The bridge writes the Claude limits file in this folder. Make it, so the watcher can include it.
        let limits = ClaudeCodeLimits.defaultFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: limits, withIntermediateDirectories: true)
        let codex = CodexProvider.defaultHome.appending(path: "sessions").path
        watcher = FileWatcher(paths: ClaudeCodeProvider.defaultRoots() + [URL(fileURLWithPath: codex), limits]) { [weak self] paths in
            // Read only the provider of the changed files.
            self?.logsChanged(Set(paths.map { $0.hasPrefix(codex) ? ProviderID.codex : .claudeCode }))
        }
    }

    /// At most one refresh for changes each 5 s: Claude Code writes often while it works.
    /// A change during a refresh starts one more refresh after it, so the last write always shows.
    private func logsChanged(_ ids: Set<ProviderID>) {
        let new = ids.subtracting(scheduled)
        guard !new.isEmpty else { return }
        let start = scheduled.isEmpty
        scheduled.formUnion(new)
        guard start else { return }
        let wait = max(0, Self.minimumGap - Date().timeIntervalSince(store.lastRefresh ?? .distantPast))
        Task {
            try? await Task.sleep(for: .seconds(wait))
            let ids = scheduled
            scheduled = []
            if store.isRefreshing { pending.formUnion(ids) } else { await refresh(only: ids) }
        }
    }

    func refresh(only ids: Set<ProviderID>? = nil) async {
        await store.refresh(only: ids)
        build()
        if let snapshot { LimitAlerts().refreshed(snapshot) }
        if !pending.isEmpty {
            let ids = pending
            pending = []
            await refresh(only: ids)
        }
    }

    private func build() {
        shown = DisplaySettings()
        snapshot = builder.build(snapshots: store.snapshots, errors: store.errors, lastRefresh: store.lastRefresh,
                                 now: Date(), roasts: &roasts, tuition: tuition)
    }
}

struct TokenBarApp: App {
    private let model = AppModel()

    init() {
        // `swift run` has no Info.plist, so LSUIElement has no effect there. The accessory policy hides the Dock icon.
        NSApplication.shared.setActivationPolicy(.accessory)
        // The task runs after launch, so the window can come to the front. Refresh shows the new index at once.
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
            ProgressView("Reading your logs…").padding(16).frame(width: 320).onPaper()
        }
    }
}
