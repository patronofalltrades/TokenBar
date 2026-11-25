import AppKit
import ServiceManagement
import SwiftUI

/// The Settings window content (DRD 5). Put it in a SwiftUI `Settings` scene.
struct SettingsView: View {
    /// Nil in tests and previews: the Leaderboard tab then shows the not set up state.
    var leaderboard: LeaderboardModel?

    /// TRD 5.1. The status line bridge (TRD-T13) reads this exact command. Do not change it here only.
    static let statusLineSnippet =
        #"{"statusLine": {"type": "command", "command": "~/Applications/TokenBar.app/Contents/MacOS/TokenBar --statusline"}}"#

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AlertSettings().tabItem { Label("Alerts", systemImage: "bell") }
            LeaderboardSettings(model: leaderboard).tabItem { Label("Leaderboard", systemImage: "person.3") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480)
        .tint(Theme.control)
        .fontDesign(.rounded)  // D60
    }
}

struct GeneralSettings: View {
    @AppStorage(SettingsKey.index) private var index: IndexChoice?
    @AppStorage(SettingsKey.roastsEnabled) private var roastsEnabled = true
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginFailed = false
    /// Starts as not connected, so that a render in tests does not read the real settings file. `.task` reads it.
    @State private var claudeStatus = ClaudeConnect.Status.notConnected
    @State private var connectError: String?

    var body: some View {
        Form {
            // DRD 2.5: one index only.
            Picker("Index", selection: $index) {
                ForEach(IndexChoice.allCases, id: \.self) { Text($0.title).tag(IndexChoice?.some($0)) }
            }
            .pickerStyle(.radioGroup)
            Toggle("Roasts", isOn: $roastsEnabled)
            Toggle("Launch at login", isOn: Binding(get: { loginStatus == .enabled }, set: { setLaunchAtLogin($0) }))
            if loginStatus == .requiresApproval {
                Text("Allow TokenBar in System Settings > General > Login Items.").font(.caption)
            }
            if loginFailed {
                Text("Could not change this setting. Open TokenBar from the app in Applications and try again.").font(.caption).foregroundStyle(Theme.secondary)
            }

            Section("Claude limits (optional)") {
                Text("Connect Claude Code to see your 5-hour and weekly Claude limits.")
                HStack {
                    Text(Self.statusText(claudeStatus, now: .now))
                    Spacer()
                    if claudeStatus == .notConnected {
                        Button("Connect") { update { try ClaudeConnect.connect() } }
                    } else {
                        Button("Disconnect") { update { try ClaudeConnect.disconnect() } }
                    }
                }
                if let connectError {
                    Text(connectError).font(.caption).foregroundStyle(Theme.ink)
                }
                Text("Your current Claude Code status line keeps working. Restart open Claude Code sessions. Claude Code runs it only in trusted folders and not when disableAllHooks is true.")
                    .font(.caption).foregroundStyle(Theme.secondary)
                DisclosureGroup("Show manual setup") {
                    HStack(alignment: .top) {
                        Text(SettingsView.statusLineSnippet)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(SettingsView.statusLineSnippet, forType: .string)
                        }
                        .accessibilityLabel("Copy status line")
                    }
                }
            }

            Section {
                Text("Tip: Hold ⌘ and drag TokenBar to the right to keep it visible.")
            }
        }
        .formStyle(.grouped)
        .task {
            // The bridge writes the limits file in a different process. Read the status again each 30 s.
            while !Task.isCancelled {
                claudeStatus = ClaudeConnect.status()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    static func statusText(_ status: ClaudeConnect.Status, now: Date) -> String {
        switch status {
        case .notConnected: "Not connected"
        case .connectedWaiting: "Connected. Waiting for the next Claude Code reply."
        case .connected(let updatedAt): "Connected · updated \(RelativeDateTimeFormatter().localizedString(for: updatedAt, relativeTo: now))"
        }
    }

    private func update(_ change: () throws -> Void) {
        do {
            try change()
            connectError = nil
        } catch {
            connectError = error.localizedDescription
        }
        claudeStatus = ClaudeConnect.status()
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginFailed = false
        } catch {
            loginFailed = true
        }
        loginStatus = SMAppService.mainApp.status
    }
}

/// DRD 5.1. Off by default. The consent text shows above the toggle.
struct LeaderboardSettings: View {
    static let consent = "TokenBar sends your handle, your cost this week, your output tokens this week and your total spend since install to the class server. Everyone who has the class code sees them. TokenBar sends nothing else."

    let model: LeaderboardModel?
    @AppStorage(SettingsKey.leaderboardEnabled) private var enabled = false
    @AppStorage(SettingsKey.leaderboardCode) private var code = ""
    @AppStorage(SettingsKey.leaderboardHandle) private var handle = ""
    @State private var leaving = false

    private var configured: Bool { model?.isConfigured ?? false }
    private var ready: Bool { LeaderboardRules.isValidCode(code) && LeaderboardRules.isValidHandle(handle) }

    var body: some View {
        Form {
            if !configured {
                Text("The class leaderboard is not set up yet.").foregroundStyle(Theme.secondary)
            }
            Text(Self.consent).font(.caption).foregroundStyle(Theme.secondary)
            Toggle("Join a class leaderboard", isOn: $enabled)
                .disabled(!configured || !ready)
            HStack {
                TextField("Class code", text: $code, prompt: Text("cafe-k3m9-x7q2"))
                Button("Make a code") { code = LeaderboardRules.makeCode() }
            }
            .disabled(!configured)
            TextField("Handle", text: $handle, prompt: Text("2 to 20 letters, digits, _ or -"))
                .disabled(!configured)
            if !code.isEmpty, !LeaderboardRules.isValidCode(code) {
                Text("A class code has 8 to 40 characters: a to z, 0 to 9 and -.").font(.caption).foregroundStyle(Theme.secondary)
            }
            if !handle.isEmpty, !LeaderboardRules.isValidHandle(handle) {
                Text("A handle has 2 to 20 characters: letters, digits, _ and -.").font(.caption).foregroundStyle(Theme.secondary)
            }
            if let problem = model?.state.problem {
                Text(problem).font(.caption).foregroundStyle(Theme.ink)
            }
            Button("Leave class and delete my data", role: .destructive) {
                leaving = true
                Task {
                    await model?.leave()
                    leaving = false
                }
            }
            .disabled(!configured || leaving || (code.isEmpty && handle.isEmpty))
            if model?.leaveFailed == true {
                Text("TokenBar could not reach the server. Your data stays until you try again.").font(.caption).foregroundStyle(Theme.ink)
            }
        }
        .formStyle(.grouped)
        // The toggle cannot stay on without a valid code and handle.
        .onChange(of: ready) { _, valid in if !valid { enabled = false } }
    }
}

struct AlertSettings: View {
    @AppStorage(SettingsKey.alert95Enabled) private var alert95Enabled = true
    @AppStorage(SettingsKey.alertLimitEnabled) private var alertLimitEnabled = true

    var body: some View {
        Form {
            Toggle("Alert at 95% of a limit", isOn: $alert95Enabled)
            Toggle("Alert when a limit is reached", isOn: $alertLimitEnabled)
        }
        .formStyle(.grouped)
    }
}

struct AboutSettings: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

    var body: some View {
        Form {
            LabeledContent("Version", value: version)
            LabeledContent("License", value: "MIT")
            // Moved from the popover footer (D46).
            LabeledContent("Prices verified", value: (try? PriceTable.shipped().lastVerified) ?? "Unknown")
            Link("TokenBar on GitHub", destination: Links.repository)
            Link("Send feedback", destination: Links.feedback)
            Text("TokenBar is not affiliated with any business school, Anthropic, OpenAI or xAI.")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
        }
        .formStyle(.grouped)
    }
}
