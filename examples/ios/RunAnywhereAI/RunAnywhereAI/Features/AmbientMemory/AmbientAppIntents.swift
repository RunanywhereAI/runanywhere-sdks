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
    /// Minimal full-screen cover for digest-pending recovery (no Notes chrome /
    /// TextFields — those were in the scene-update stacks of 0x8BADF00D kills).
    @Published var isDigestPendingCoverPresented = false
    /// When set, Notes runs the offline fixture dogfood harness on appear.
    @Published var pendingDogfood: AmbientDogfoodRequest?

    private init() {}

    func open(autoStart: Bool) {
        shouldAutoStart = autoStart
        isPresented = true
    }

    func openDogfood(_ request: AmbientDogfoodRequest = .default) {
        pendingDogfood = request
        if request.digestPendingOnly {
            isDigestPendingCoverPresented = true
        } else {
            isPresented = true
        }
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
    /// Skip ASR/diarization — only Summarize notes that already have a transcript
    /// but no digest (recovery after a digest watchdog crash).
    var digestPendingOnly: Bool
    /// Only re-run the reduce pass over saved map chunks (no ASR / no map).
    var remergeOnly: Bool
    /// Optional digester override (`digestModel=`). Useful to force LFM2 after
    /// a 4B scene-watchdog kill without re-picking in the UI.
    var digestModelID: String?
    /// Cap digest source length (`maxChars=`). Omit for full-transcript digests.
    var digestMaxChars: Int?
    /// Force rewrite even when a (possibly capped) digest already exists.
    var rewriteDigest: Bool

    static let `default` = AmbientDogfoodRequest(
        labelSpeakers: true,
        summarize: true,
        digestPendingOnly: false,
        remergeOnly: false,
        digestModelID: nil,
        digestMaxChars: nil,
        rewriteDigest: false
    )

    static func from(url: URL) -> AmbientDogfoodRequest {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func flag(_ name: String, default defaultValue: Bool) -> Bool {
            guard let raw = items.first(where: { $0.name == name })?.value?.lowercased() else {
                return defaultValue
            }
            return ["1", "true", "yes", "on"].contains(raw)
        }
        let mode = items.first(where: { $0.name == "mode" })?.value?.lowercased()
        let remergeOnly = mode == "remerge" || flag("remerge", default: false)
        let digestPendingOnly = remergeOnly
            || mode == "digestpending"
            || mode == "digestfull"
            || flag("digestPending", default: false)
        let digestModel = items.first(where: { $0.name == "digestModel" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let maxChars = items.first(where: { $0.name == "maxChars" })?.value.flatMap(Int.init)
        let full = mode == "digestfull" || flag("full", default: false)
        return AmbientDogfoodRequest(
            labelSpeakers: flag("speakers", default: !digestPendingOnly),
            summarize: flag("summarize", default: true),
            digestPendingOnly: digestPendingOnly,
            remergeOnly: remergeOnly,
            digestModelID: (digestModel?.isEmpty == false) ? digestModel : nil,
            digestMaxChars: full ? nil : maxChars.flatMap { $0 > 0 ? $0 : nil },
            rewriteDigest: full || flag("rewrite", default: false)
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
            AmbientDogfoodRequest(
                labelSpeakers: labelSpeakers,
                summarize: summarize,
                digestPendingOnly: false,
                remergeOnly: false,
                digestModelID: nil,
                digestMaxChars: nil,
                rewriteDigest: false
            )
        )
        return .result()
    }
}
#endif
