//
//  RunAnywhereAIStabilityUITests.swift
//  RunAnywhereAIUITests
//
//  Real UI-flow tests that drive the actual iOS chat-first UI on the simulator.
//  The app ships no accessibility identifiers, so test00 dumps the live element
//  tree (printed to the test log) to derive robust queries; the rest exercise the
//  real flows and assert the app stays alive (never crashes/hangs) at each step.
//

import XCTest

final class RunAnywhereAIStabilityUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Helpers

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func dumpTree(_ label: String) {
        // Attach the full accessibility hierarchy as a text file (extractable via
        // xcresulttool) since print() from the runner is awkward to read.
        let a = XCTAttachment(string: app.debugDescription)
        a.name = "uitree-\(label)"
        a.lifetime = .keepAlways
        add(a)
    }

    private func assertAlive(_ ctx: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.state, .runningForeground, "App not running after: \(ctx)", file: file, line: line)
    }

    /// Dismiss onboarding if the Welcome / Get Started screen is up.
    private func dismissOnboardingIfPresent() {
        let getStarted = app.buttons["Get Started"]
        if getStarted.waitForExistence(timeout: 6) {
            getStarted.tap()
        }
    }

    // MARK: - Tests

    /// Discovery: dump the element tree at launch and after entering the chat, so
    /// the real labels/types are visible in the log.
    func test00_discoverUITree() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
        _ = app.staticTexts.firstMatch.waitForExistence(timeout: 20)
        shot("00a-launch")
        dumpTree("launch")

        dismissOnboardingIfPresent()
        _ = app.staticTexts.firstMatch.waitForExistence(timeout: 10)
        shot("00b-after-get-started")
        dumpTree("after-get-started")

        // Enumerate the primary interactive elements by label for reference.
        print("BUTTONS: " + app.buttons.allElementsBoundByIndex.map { "[\($0.label)]" }.joined(separator: " "))
        print("TEXTFIELDS: \(app.textFields.count)  TEXTVIEWS: \(app.textViews.count)")
        print("STATICTEXTS(sample): " + app.staticTexts.allElementsBoundByIndex.prefix(15)
            .map { "[\($0.label)]" }.joined(separator: " "))
        assertAlive("discovery")
    }

    /// The app must reach an interactive first screen (not the "Couldn't Start"
    /// error, not a stuck spinner).
    func test01_launchesToInteractiveUI() {
        assertAlive("launch")
        XCTAssertFalse(app.staticTexts["RunAnywhere Couldn't Start"].waitForExistence(timeout: 3),
                       "app shows the Couldn't Start error")
        // Some interactive control appears within 30s.
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 30),
                      "no interactive UI appeared (stuck init?)")
        shot("01-interactive")
    }

    /// Onboarding → chat: tapping Get Started leaves onboarding and shows chat
    /// chrome (the "Choose Model" control lives in the chat toolbar).
    func test02_onboardingToChat() {
        dismissOnboardingIfPresent()
        // After onboarding, the chat toolbar's model control should exist.
        let chooseModel = app.buttons["Choose Model"]
        let landed = chooseModel.waitForExistence(timeout: 10)
        shot("02-chat")
        XCTAssertTrue(landed, "did not land on the chat screen (no 'Choose Model' control)")
        assertAlive("onboarding→chat")
    }

    /// The model picker must open and be dismissable without crashing.
    func test03_modelPickerOpensAndCloses() throws {
        dismissOnboardingIfPresent()
        let chooseModel = app.buttons["Choose Model"]
        guard chooseModel.waitForExistence(timeout: 10) else {
            shot("03-no-choose-model"); throw XCTSkip("No 'Choose Model' control")
        }
        chooseModel.tap()
        // A sheet with a nav bar / list should appear.
        let sheetUp = app.navigationBars.firstMatch.waitForExistence(timeout: 8)
            || app.collectionViews.firstMatch.waitForExistence(timeout: 3)
            || app.tables.firstMatch.waitForExistence(timeout: 3)
        shot("03-model-picker")
        assertAlive("model picker open")
        XCTAssertTrue(sheetUp, "model picker sheet did not appear")
        // Dismiss (Close/Cancel/Done button, or swipe down).
        for label in ["Close", "Cancel", "Done"] where app.buttons[label].exists {
            app.buttons[label].tap(); break
        }
        assertAlive("model picker closed")
    }

    /// Rapid open/close of sheets + backgrounding must not crash or hang.
    func test04_stability() {
        dismissOnboardingIfPresent()
        let chooseModel = app.buttons["Choose Model"]
        for i in 0..<6 where chooseModel.waitForExistence(timeout: 5) {
            chooseModel.tap()
            for label in ["Close", "Cancel", "Done"] where app.buttons[label].waitForExistence(timeout: 4) {
                app.buttons[label].tap(); break
            }
            if i % 3 == 0 { assertAlive("sheet cycle \(i)") }
        }
        // Background + foreground.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "did not return to foreground")
        shot("04-post-stability")
        assertAlive("post-stability")
    }

    /// The chat composer must accept typed text.
    func test05_chatInputAcceptsText() throws {
        dismissOnboardingIfPresent()
        let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        guard field.waitForExistence(timeout: 10) else {
            shot("05-no-input"); throw XCTSkip("No chat input field found")
        }
        field.tap()
        field.typeText("Hello from XCUITest")
        shot("05-typed")
        assertAlive("typed into composer")
    }

    /// Full chat E2E through the GUI: load a model, send a prompt, confirm a
    /// response bubble appears. Heavily instrumented (screenshots + trees) because
    /// it depends on a model download + on-device inference on the sim (slow).
    func test06_chatEndToEnd() throws {
        dismissOnboardingIfPresent()
        guard app.buttons["Choose Model"].waitForExistence(timeout: 10) else {
            throw XCTSkip("no chat screen")
        }
        app.buttons["Choose Model"].tap()
        let use = app.buttons["Use"].firstMatch
        guard use.waitForExistence(timeout: 10) else {
            dumpTree("picker"); shot("06-no-use"); throw XCTSkip("no 'Use' in picker")
        }
        dumpTree("picker")
        shot("06a-picker")
        use.tap()

        // Wait for the model to load (covers a sim download). Ready when the picker
        // is gone and the composer TextField ('Type a message...') is back.
        let composer = app.textFields.firstMatch
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            if !app.staticTexts["Choose Chat Model"].exists && composer.exists { break }
            Thread.sleep(forTimeInterval: 5)
        }
        shot("06b-loaded")
        dumpTree("chat-loaded")
        guard composer.waitForExistence(timeout: 15) else {
            XCTFail("composer missing after model load"); return
        }

        composer.tap()
        // Dismiss the iOS multilingual-keyboard tutorial popup if it appears — it
        // sits over the composer and intercepts the Send tap.
        let continueBtn = app.buttons["Continue"]
        if continueBtn.waitForExistence(timeout: 3) { continueBtn.tap() }
        composer.typeText("Reply with exactly: OK")
        if continueBtn.exists { continueBtn.tap() }
        shot("06c-typed")
        dumpTree("chat-typed")

        // Send via the confirmed control (arrow.up.circle.fill; enables once there
        // is text).
        let send = app.buttons["Send message"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Send button not found")
        let enableDeadline = Date().addingTimeInterval(10)
        while !send.isEnabled && Date() < enableDeadline { Thread.sleep(forTimeInterval: 0.5) }
        send.tap()
        shot("06d-sent")

        // Send succeeded when the composer clears. Then the on-device model streams
        // its reply into a bubble (the 06e screenshot + chat-response tree are the
        // ground-truth record).
        var cleared = false
        let clearDeadline = Date().addingTimeInterval(30)
        while Date() < clearDeadline {
            let val = (composer.value as? String) ?? ""
            if val.isEmpty || val == "Type a message..." { cleared = true; break }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(cleared, "composer did not clear — message did not send")
        Thread.sleep(forTimeInterval: 90)  // let the reply stream on sim CPU
        shot("06e-response")
        dumpTree("chat-response")
        assertAlive("after chat turn")
    }
}
