import AppKit
import ServiceManagement
import SwiftUI

/// First-run onboarding (PRD-US-18, DRD 4). A window, because the app has no Dock icon and no main window.
/// The window shows at each launch until the user selects an index and clicks Done.
@MainActor enum Onboarding {
    enum Step: Equatable { case welcome, index, claudeLimits, menuBar, finish }

    /// DRD 4.1. Checks only that the log folders exist. It never reads a log.
    struct Detection: Equatable {
        var claudeCode: Bool
        var codex: Bool

        /// The same folders that the providers read.
        static func scan(claudeRoots: [URL] = ClaudeCodeProvider.defaultRoots(),
                         codexHome: URL = CodexProvider.defaultHome) -> Detection {
            let fm = FileManager.default
            return Detection(claudeCode: claudeRoots.contains { fm.fileExists(atPath: $0.path) },
                             codex: fm.fileExists(atPath: codexHome.appendingPathComponent("sessions").path))
        }
    }

    /// The Claude limits step shows only when Claude Code is on this Mac.
    /// The menu bar step is always in the list (D40). It has no Skip button.
    static func steps(_ found: Detection) -> [Step] {
        [.welcome, .index] + (found.claudeCode ? [.claudeLimits] : []) + [.menuBar, .finish]
    }

    /// DRD 2.5: no default index. Onboarding is necessary until the user selects one.
    static func isNeeded(defaults: UserDefaults = .standard) -> Bool {
        IndexChoice.saved(in: defaults) == nil
    }

    /// Writes the index. Turns on launch at login if the toggle is on (PRD-US-19).
    /// A login item failure is quiet, as in Settings. Settings shows the real state.
    static func finish(index: IndexChoice, launchAtLogin: Bool, defaults: UserDefaults = .standard,
                       register: () throws -> Void = { try SMAppService.mainApp.register() }) {
        defaults.set(index.rawValue, forKey: SettingsKey.index)
        if launchAtLogin { try? register() }
    }

    /// The menu bar preview of each index choice in step 2 (DRD 4.5).
    /// The café text comes from `cafe-units.json`, because it names the school (D25).
    static func preview(_ choice: IndexChoice) -> (sample: String, detail: String) {
        switch choice {
        case .cafe: ("3.4", (try? CafeData.shipped().pickerDescription) ?? "")
        case .tuition: ("0.04%", "How much of your MBA tuition your AI has burned. Spoiler: not much. Yet.")
        case .water: ("22 L", "How many liters of water your AI drank today. We used the scary estimate.")
        }
    }

    private static var window: NSWindow?

    /// The window has the height of the tallest step at the current text size, so the Continue button always shows.
    static func makeWindow(_ view: OnboardingView) -> NSWindow {
        let height = steps(view.detection).indices.map {
            NSHostingView(rootView: OnboardingView(detection: view.detection, step: $0, choice: .cafe)).fittingSize.height
        }.max() ?? 0
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to TokenBar"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 440, height: height))
        return window
    }

    /// Opens the window in front of other apps. `onFinish` runs after Done.
    static func showIfNeeded(onFinish: @escaping @MainActor () -> Void) {
        guard isNeeded(), Self.window == nil else { return }
        let window = makeWindow(OnboardingView(detection: .scan()) { index, launchAtLogin in
            finish(index: index, launchAtLogin: launchAtLogin)
            Self.window?.close()
            Self.window = nil
            onFinish()
        })
        window.isReleasedWhenClosed = false
        window.center()
        Self.window = window
        // An accessory app is not active, so the window opens behind other windows without this.
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

struct OnboardingView: View {
    let detection: Onboarding.Detection
    let done: @MainActor (IndexChoice, Bool) -> Void
    @State private var index: Int
    @State private var choice: IndexChoice?
    @State private var launchAtLogin = true
    @State private var connected = false
    @State private var connectError: String?

    /// `step` and `choice` are for previews and tests.
    init(detection: Onboarding.Detection, step: Int = 0, choice: IndexChoice? = nil,
         done: @escaping @MainActor (IndexChoice, Bool) -> Void = { _, _ in }) {
        self.detection = detection
        self.done = done
        _index = State(initialValue: step)
        _choice = State(initialValue: choice)
    }

    private var steps: [Onboarding.Step] { Onboarding.steps(detection) }
    private var step: Onboarding.Step { steps[index] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch step {
            case .welcome: welcome
            case .index: indexChoice
            case .claudeLimits: claudeLimits
            case .menuBar: menuBar
            case .finish: finish
            }
            Spacer(minLength: 0)
            HStack {
                Text("Step \(index + 1) of \(steps.count)").font(.caption).foregroundStyle(Theme.secondary)
                Spacer()
                if index > 0 { Button("Back") { index -= 1 }.buttonStyle(ThemeButtonStyle(filled: false)) }
                if step == .finish {
                    Button("Done") { if let choice { done(choice, launchAtLogin) } }
                        .buttonStyle(ThemeButtonStyle())
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(step == .claudeLimits && !connected ? "Skip" : "Continue") { index += 1 }
                        .buttonStyle(ThemeButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(step == .index && choice == nil)
                }
            }
        }
        .padding(24)
        .frame(width: 440, alignment: .topLeading)
        .frame(minHeight: 340, alignment: .top)
        .onPaper()
        .symbolRenderingMode(.hierarchical)
    }

    // DRD 4.6: humor in the welcome line only.
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to TokenBar").font(.title2.bold())
            Text("Your AI spending is now a case study. You are the protagonist.")
            VStack(alignment: .leading, spacing: 6) {
                found("Claude Code", detection.claudeCode)
                found("Codex", detection.codex)
            }
            if !detection.claudeCode && !detection.codex {
                Text("TokenBar found no Claude Code or Codex logs on this Mac. If you use one of them, run it one time. TokenBar checks again every minute.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("TokenBar cannot see web chat, such as claude.ai or ChatGPT. It sees only Claude Code and Codex on this Mac.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Your data stays on this Mac. TokenBar reads token counts, not your prompts.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }

    private func found(_ name: String, _ isFound: Bool) -> some View {
        Label(isFound ? "\(name): found" : "\(name): not found",
              systemImage: isFound ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(isFound ? Theme.ink : Theme.secondary)
    }

    // DRD 4.5. Each option shows the real menu bar image.
    private var indexChoice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick your index").font(.title2.bold())
            ForEach(IndexChoice.allCases, id: \.self) { value in
                let preview = Onboarding.preview(value)
                option(value, sample: preview.sample, detail: preview.detail)
            }
            Text("TokenBar shows one index. Warnings always show the real number. You can change the index or turn off roasts later in Settings.")
                .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func option(_ value: IndexChoice, sample: String, detail: String) -> some View {
        let selected = choice == value
        return Button { choice = value } label: {
            HStack(spacing: 12) {
                // The same image as the real menu bar item.
                Image(nsImage: MenuBarLabel.image(symbol: value.rawValue, text: sample, width: MenuBarLabel.width(value)))
                    .frame(width: MenuBarLabel.tuitionWidth, alignment: .leading)  // aligns the three titles
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.track, in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(value.title).font(.headline)
                    Text(detail).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
            }
            .padding(8)
            .contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Theme.ink : Theme.rule, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var claudeLimits: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("See your Claude limits (optional)").font(.title2.bold())
            Text("TokenBar can show your 5-hour and weekly Claude limits. For this, it connects to the Claude Code status line.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Connect") {
                    do {
                        try ClaudeConnect.connect()
                        connected = true
                        connectError = nil
                    } catch {
                        connectError = error.localizedDescription
                    }
                }
                .disabled(connected)
                if connected { Label("Connected", systemImage: "checkmark.circle.fill") }
            }
            if let connectError {
                Text(connectError).font(.caption).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            Text("Your current Claude Code status line keeps working. Restart open Claude Code sessions. You can connect or disconnect later in Settings.")
                .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // DRD 2.3 and D40.
    private var menuBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keep TokenBar visible").font(.title2.bold())
            Text("TokenBar lives in the menu bar, at the top right of your screen.")
                .fixedSize(horizontal: false, vertical: true)
            Text("When the menu bar is full, macOS hides the icons near the notch first. It does not warn you. An open app with many menus pushes icons out too.")
                .fixedSize(horizontal: false, vertical: true)
            Label("Hold ⌘ and drag TokenBar to the right, toward the clock.", systemImage: "command")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // DRD 4.4.
    private var finish: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You are all set").font(.title2.bold())
            Text("Click TokenBar in the menu bar to see your usage.")
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Open TokenBar at login", isOn: $launchAtLogin)
            Text("You can change all of this later in Settings.").font(.caption).foregroundStyle(Theme.secondary)
        }
    }
}

#Preview("Welcome") { OnboardingView(detection: .init(claudeCode: true, codex: false)) }
#Preview("Index") { OnboardingView(detection: .init(claudeCode: true, codex: true), step: 1, choice: .water) }
