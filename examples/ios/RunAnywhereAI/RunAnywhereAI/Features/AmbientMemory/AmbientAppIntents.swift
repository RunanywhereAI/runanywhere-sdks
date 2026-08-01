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
    /// When set, Notes runs the offline fixture dogfood harness on appear.
    @Published var pendingDogfood: AmbientDogfoodRequest?

    private init() {}

    func open(autoStart: Bool) {
        shouldAutoStart = autoStart
        isPresented = true
    }

    func openDogfood(_ request: AmbientDogfoodRequest = .default) {
        pendingDogfood = request
        isPresented = true
    }

    func consumeAutoStart() -> Bool {
        defer { shouldAutoStart = false }
        return shouldAutoStart
    }

    func consumeDogfood() -> AmbientDogfoodRequest? {
        defer { pendingDogfood = nil }
        return pendingDogfood
    }
}

struct AmbientDogfoodRequest: Equatable, Sendable {
    var labelSpeakers: Bool
    var summarize: Bool

    static let `default` = AmbientDogfoodRequest(labelSpeakers: true, summarize: true)

    static func from(url: URL) -> AmbientDogfoodRequest {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func flag(_ name: String, default defaultValue: Bool) -> Bool {
            guard let raw = items.first(where: { $0.name == name })?.value?.lowercased() else {
                return defaultValue
            }
            return ["1", "true", "yes", "on"].contains(raw)
        }
        return AmbientDogfoodRequest(
            labelSpeakers: flag("speakers", default: true),
            summarize: flag("summarize", default: true)
        )
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

struct RunNotesLongformDogfoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Notes Longform Dogfood"
    static var description = IntentDescription(
        "Imports WAV/m4a fixtures from Documents/AmbientMemory/Fixtures and runs offline ASR, optional speakers, and structured digest.",
        categoryName: "Notes"
    )

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Label Speakers")
    var labelSpeakers: Bool

    @Parameter(title: "Summarize")
    var summarize: Bool

    init() {
        self.labelSpeakers = true
        self.summarize = true
    }

    init(labelSpeakers: Bool, summarize: Bool) {
        self.labelSpeakers = labelSpeakers
        self.summarize = summarize
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AmbientRouter.shared.openDogfood(
            AmbientDogfoodRequest(labelSpeakers: labelSpeakers, summarize: summarize)
        )
        return .result()
    }
}
#endif
