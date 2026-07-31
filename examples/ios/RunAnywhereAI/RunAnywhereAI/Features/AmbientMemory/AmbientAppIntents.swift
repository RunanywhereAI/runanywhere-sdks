//
//  AmbientAppIntents.swift
//  RunAnywhereAI
//
//  Lightweight App Intents for Notes. Start opens the app (mic requires a
//  visible session). Stop lives in AmbientStopIntent.swift so the Live
//  Activity extension can share it.
//

#if os(iOS)
import AppIntents
import Combine
import Foundation
import SwiftUI

// MARK: - Router

/// Bridges an intent / deep link to the SwiftUI hierarchy.
@MainActor
final class AmbientRouter: ObservableObject {
    static let shared = AmbientRouter()

    @Published var isPresented = false
    @Published var shouldAutoStart = false

    private init() {}

    func open(autoStart: Bool) {
        shouldAutoStart = autoStart
        isPresented = true
    }

    func consumeAutoStart() -> Bool {
        defer { shouldAutoStart = false }
        return shouldAutoStart
    }
}

// MARK: - Intents

struct StartAmbientMemoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Note Recording"
    static var description = IntentDescription(
        "Opens RunAnywhere and starts an on-device note recording.",
        categoryName: "Notes"
    )

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AmbientRouter.shared.open(autoStart: true)
        return .result()
    }
}

struct OpenAmbientMemoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Notes"
    static var description = IntentDescription(
        "Opens RunAnywhere Notes without starting a recording.",
        categoryName: "Notes"
    )

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AmbientRouter.shared.open(autoStart: false)
        return .result()
    }
}
#endif
