import AppKit
import Foundation
import SwiftUI
import Testing
@testable import TokenBar

@MainActor
struct OnboardingTests {
    let defaults: UserDefaults

    init() {
        let suite = "OnboardingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func detectionChecksOnlyFolders() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let claude = tmp.appendingPathComponent("claude/projects")
        let codex = tmp.appendingPathComponent("codex")
        #expect(Onboarding.Detection.scan(claudeRoots: [claude], codexHome: codex) == .init(claudeCode: false, codex: false))
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        // Codex without `sessions` has no logs.
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        #expect(Onboarding.Detection.scan(claudeRoots: [tmp.appendingPathComponent("none"), claude], codexHome: codex)
            == .init(claudeCode: true, codex: false))
        try FileManager.default.createDirectory(at: codex.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        #expect(Onboarding.Detection.scan(claudeRoots: [claude], codexHome: codex) == .init(claudeCode: true, codex: true))
    }

    @Test func claudeLimitsStepOnlyWithClaudeCode() {
        #expect(Onboarding.steps(.init(claudeCode: true, codex: false)) == [.welcome, .barStyle, .claudeLimits, .menuBar, .finish])
        #expect(Onboarding.steps(.init(claudeCode: false, codex: true)) == [.welcome, .barStyle, .menuBar, .finish])
    }

    /// D40: the menu bar visibility step is mandatory.
    @Test(arguments: [false, true], [false, true])
    func menuBarStepIsAlwaysThere(claudeCode: Bool, codex: Bool) {
        let steps = Onboarding.steps(.init(claudeCode: claudeCode, codex: codex))
        #expect(steps.contains(.menuBar))
        #expect(steps.firstIndex(of: .barStyle)! < steps.firstIndex(of: .menuBar)!)
        #expect(steps.last == .finish)
    }

    @Test func neededUntilAValidStyleIsSaved() {
        #expect(Onboarding.isNeeded(defaults: defaults))
        defaults.set("loud", forKey: SettingsKey.barStyle)
        #expect(Onboarding.isNeeded(defaults: defaults))
        defaults.set("funny", forKey: SettingsKey.barStyle)
        #expect(!Onboarding.isNeeded(defaults: defaults))
    }

    @Test func finishSavesStyleAndRegisters() {
        var registered = 0
        Onboarding.finish(style: .serious, launchAtLogin: true, defaults: defaults) { registered += 1 }
        #expect(registered == 1)
        #expect(defaults.string(forKey: SettingsKey.barStyle) == "serious")
        #expect(defaults.object(forKey: SettingsKey.roastsEnabled) as? Bool == false)
        #expect(!Onboarding.isNeeded(defaults: defaults))
    }

    @Test func finishWithoutLoginItemDoesNotRegister() {
        var registered = 0
        Onboarding.finish(style: .funny, launchAtLogin: false, defaults: defaults) { registered += 1 }
        #expect(registered == 0)
        #expect(defaults.string(forKey: SettingsKey.barStyle) == "funny")
    }

    @Test func registerFailureIsQuiet() {
        struct Denied: Error {}
        Onboarding.finish(style: .funny, launchAtLogin: true, defaults: defaults) { throw Denied() }
        #expect(defaults.string(forKey: SettingsKey.barStyle) == "funny")
    }

    /// Set ONBOARDING_PNG_DIR to save each step as a PNG for a visual check.
    @Test func eachStepRenders() throws {
        let cases: [(String, Onboarding.Detection)] = [
            ("found", .init(claudeCode: true, codex: true)),
            ("none", .init(claudeCode: false, codex: false)),
        ]
        for (name, detection) in cases {
            for (i, step) in Onboarding.steps(detection).enumerated() {
                let view = OnboardingView(detection: detection, step: i, style: i == 0 ? nil : .funny)
                #expect(ImageRenderer(content: view).nsImage != nil)
                if let dir = ProcessInfo.processInfo.environment["ONBOARDING_PNG_DIR"] {
                    let host = NSHostingView(rootView: view)
                    host.frame.size = host.fittingSize
                    let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: dir).appendingPathComponent("onboarding-\(name)-\(i + 1)-\(step).png"))
                }
            }
        }
    }
}
