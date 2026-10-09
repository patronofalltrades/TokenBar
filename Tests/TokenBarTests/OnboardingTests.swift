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
        #expect(Onboarding.steps(.init(claudeCode: true, codex: false)) == [.welcome, .index, .claudeLimits, .menuBar, .finish])
        #expect(Onboarding.steps(.init(claudeCode: false, codex: true)) == [.welcome, .index, .menuBar, .finish])
    }

    /// D40: the menu bar visibility step is mandatory.
    @Test(arguments: [false, true], [false, true])
    func menuBarStepIsAlwaysThere(claudeCode: Bool, codex: Bool) {
        let steps = Onboarding.steps(.init(claudeCode: claudeCode, codex: codex))
        #expect(steps.contains(.menuBar))
        #expect(steps.firstIndex(of: .index)! < steps.firstIndex(of: .menuBar)!)
        #expect(steps.last == .finish)
    }

    @Test func neededUntilAValidIndexIsSaved() {
        #expect(Onboarding.isNeeded(defaults: defaults))
        defaults.set("numbers", forKey: SettingsKey.index)
        #expect(Onboarding.isNeeded(defaults: defaults))
        defaults.set("water", forKey: SettingsKey.index)
        #expect(!Onboarding.isNeeded(defaults: defaults))
    }

    /// D41: a Serious user picks again. A Funny user keeps the café index.
    @Test func oldBarStyleDecidesIfOnboardingShows() {
        defaults.set("serious", forKey: "barStyle")
        #expect(Onboarding.isNeeded(defaults: defaults))
        defaults.set("funny", forKey: "barStyle")
        defaults.removeObject(forKey: SettingsKey.index)
        #expect(!Onboarding.isNeeded(defaults: defaults))
    }

    @Test(arguments: IndexChoice.allCases)
    func finishSavesEachChoiceAndRegisters(choice: IndexChoice) {
        var registered = 0
        Onboarding.finish(index: choice, launchAtLogin: true, defaults: defaults) { registered += 1 }
        #expect(registered == 1)
        #expect(IndexChoice.saved(in: defaults) == choice)
        #expect(defaults.object(forKey: SettingsKey.roastsEnabled) == nil)
        #expect(!Onboarding.isNeeded(defaults: defaults))
    }

    @Test func finishWithoutLoginItemDoesNotRegister() {
        var registered = 0
        Onboarding.finish(index: .cafe, launchAtLogin: false, defaults: defaults) { registered += 1 }
        #expect(registered == 0)
        #expect(defaults.string(forKey: SettingsKey.index) == "cafe")
    }

    @Test func registerFailureIsQuiet() {
        struct Denied: Error {}
        Onboarding.finish(index: .cafe, launchAtLogin: true, defaults: defaults) { throw Denied() }
        #expect(defaults.string(forKey: SettingsKey.index) == "cafe")
    }

    /// Step 2 shows the real menu bar image of each choice, at the real width.
    @Test func eachChoiceHasAMenuBarPreview() {
        let previews = IndexChoice.allCases.map(Onboarding.preview)
        #expect(IndexChoice.allCases.map(MenuBarLabel.width) == [52, 68, 52])
        #expect(previews.map(\.sample) == ["3.4", "0.04%", "22 L"])
        for (choice, p) in zip(IndexChoice.allCases, previews) {
            #expect(MenuBarLabel.image(symbol: choice.rawValue, text: p.sample, width: MenuBarLabel.width(choice)).size.width == MenuBarLabel.width(choice))
        }
    }

    /// IES-212: the descriptions. "IESE" comes from the data file only (D25).
    @Test func choiceDescriptions() throws {
        #expect(IndexChoice.allCases.map { Onboarding.preview($0).detail } == [
            "How many cafés con leche at the IESE cafeteria your tokens cost today.",
            "How much of your MBA tuition your AI has burned. Spoiler: not much. Yet.",
            "How many liters of water your AI drank today. We used the scary estimate.",
        ])
        #expect(Onboarding.preview(.cafe).detail == (try CafeData.shipped()).pickerDescription)
        #expect(IndexChoice.allCases.allSatisfy { !Onboarding.preview($0).detail.contains("Roasts") })
    }

    /// The real window shows the whole step, with the Continue button, at each step.
    /// Set ONBOARDING_PNG_DIR to save the window of step 2 as a PNG.
    @Test func windowFitsEachStep() throws {
        let detection = Onboarding.Detection(claudeCode: true, codex: true)
        let window = Onboarding.makeWindow(OnboardingView(detection: detection))
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = try #require(window.contentViewController as? NSHostingController<OnboardingView>)
        for i in Onboarding.steps(detection).indices {
            let view = OnboardingView(detection: detection, step: i, choice: .water)
            host.rootView = view
            RunLoop.main.run(until: .now.addingTimeInterval(0.2))  // SwiftUI sends the new size on the next pass
            let needed = NSHostingView(rootView: view).fittingSize.height
            #expect(window.contentLayoutRect.height >= needed - 0.5, "step \(i + 1): \(window.contentLayoutRect.height) < \(needed)")
            if i == 1, let dir = ProcessInfo.processInfo.environment["ONBOARDING_PNG_DIR"] {
                let step2 = Onboarding.makeWindow(view)
                step2.isReleasedWhenClosed = false
                defer { step2.close() }
                let view = try #require(step2.contentView?.superview)  // with the title bar
                let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent("onboarding-window-step2.png"))
            }
        }
    }

    /// Set ONBOARDING_PNG_DIR to save each step as a PNG for a visual check.
    @Test func eachStepRenders() throws {
        let cases: [(String, Onboarding.Detection)] = [
            ("found", .init(claudeCode: true, codex: true)),
            ("none", .init(claudeCode: false, codex: false)),
        ]
        for (name, detection) in cases {
            for (i, step) in Onboarding.steps(detection).enumerated() {
                let view = OnboardingView(detection: detection, step: i, choice: i == 0 ? nil : .water)
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
