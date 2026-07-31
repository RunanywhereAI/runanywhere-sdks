//
//  AmbientStopIntent.swift
//  RunAnywhereAI + RunAnywhereActivityExtension
//
//  Stopping an ambient session, reachable from Shortcuts, Siri, and the Live
//  Activity's Stop button.
//
//  Kept in its own file because the widget extension needs it too, and the
//  rest of the ambient intents pull in main-app SwiftUI state. Stopping is the
//  one ambient action that is safe to run outside the app: it tears capture
//  down rather than starting it, so it does not need `openAppWhenRun`.
//
//  TARGET MEMBERSHIP: RunAnywhereAI (main app) + RunAnywhereActivityExtension,
//  wired manually in the pbxproj like DictationActivityAttributes.swift.
//

#if os(iOS)
import AppIntents
import Foundation

struct StopAmbientMemoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Memory Lab"
    static var description = IntentDescription(
        "Stops the active ambient memory session and saves it.",
        categoryName: "Ambient"
    )

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        DarwinNotificationCenter.shared.post(
            name: SharedConstants.DarwinNotifications.ambientStopRequested
        )
        return .result(dialog: "Stopping the Memory Lab session.")
    }
}
#endif
