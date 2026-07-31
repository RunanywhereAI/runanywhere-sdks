//
//  AmbientAppIntents.swift
//  RunAnywhereAI
//
//  Action Button / Shortcuts entry points for the Ambient Memory Lab.
//
//  The start intent deliberately uses `openAppWhenRun`. iOS will not let a
//  background App Intent start `AVAudioEngine`, and a covert capture path is
//  not something this feature should offer even if it could: the user must see
//  the Lab, the preparation state, and the active recording indicator. The
//  Action Button is a faster way into the same explicit flow, not an exception
//  to it.
//

#if os(iOS)
import AppIntents
import Combine
import Foundation
import SwiftUI

// MARK: - Router

/// Bridges an intent invocation to the SwiftUI hierarchy.
///
/// The intent runs in the app process once `openAppWhenRun` brings it forward,
/// so it can flip this flag and let the root scene present the Lab.
@MainActor
final class AmbientRouter: ObservableObject {
    static let shared = AmbientRouter()

    /// Set when the Lab should be on screen.
    @Published var isPresented = false
    /// Set when the Lab should begin a session as soon as it appears.
    @Published var shouldAutoStart = false

    private init() {}

    func open(autoStart: Bool) {
        shouldAutoStart = autoStart
        isPresented = true
    }

    /// Consume the auto-start request so returning to the Lab later does not
    /// silently begin another recording.
    func consumeAutoStart() -> Bool {
        defer { shouldAutoStart = false }
        return shouldAutoStart
    }
}

// MARK: - Intents

struct StartAmbientMemoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Memory Lab"
    static var description = IntentDescription(
        "Opens RunAnywhere and starts an on-device ambient memory session.",
        categoryName: "Ambient"
    )

    /// Capture is only ever started from a visible screen, so the intent opens
    /// the app rather than trying to record in the background.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AmbientRouter.shared.open(autoStart: true)
        return .result()
    }
}

struct OpenAmbientMemoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Memory Lab"
    static var description = IntentDescription(
        "Opens the RunAnywhere Memory Lab without starting a recording.",
        categoryName: "Ambient"
    )

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AmbientRouter.shared.open(autoStart: false)
        return .result()
    }
}

// MARK: - Shortcuts

/// Published so the user can assign "Start Memory Lab" to the Action Button on
/// supported iPhones through Settings › Action Button › Shortcut.
struct AmbientAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartAmbientMemoryIntent(),
            phrases: [
                "Start \(.applicationName) Memory Lab",
                "Start remembering with \(.applicationName)",
            ],
            shortTitle: "Start Memory Lab",
            systemImageName: "brain.head.profile"
        )
        AppShortcut(
            intent: StopAmbientMemoryIntent(),
            phrases: [
                "Stop \(.applicationName) Memory Lab",
                "Stop remembering with \(.applicationName)",
            ],
            shortTitle: "Stop Memory Lab",
            systemImageName: "stop.circle"
        )
    }
}
#endif
