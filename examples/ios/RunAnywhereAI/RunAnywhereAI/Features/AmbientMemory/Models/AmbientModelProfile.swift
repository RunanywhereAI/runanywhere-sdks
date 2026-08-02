//
//  AmbientModelProfile.swift
//  RunAnywhereAI
//
//  Testable model profiles for the Ambient Memory Lab plus the device-aware
//  routing that picks one. Model ids come from `ModelCatalogBootstrap`; no
//  iPhone-family assumptions are hard-coded, because the same chip generation
//  ships with very different memory budgets.
//

import Foundation
import RunAnywhere
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Background Safety

extension RAInferenceFramework {
    /// Whether this framework can keep working once the app is backgrounded.
    ///
    /// MLX and Core ML are Metal. llama.cpp in this app also schedules Metal
    /// via ggml — iOS refuses those command buffers from a backgrounded
    /// process. Only ONNX/Sherpa-style CPU backends are safe for lock-screen
    /// work (ASR/VAD). Summarization always waits for the foreground anyway.
    var isBackgroundSafe: Bool {
        switch self {
        case .mlx, .coreml, .llamaCpp:
            return false
        default:
            return true
        }
    }
}

extension RAModelInfo {
    var isBackgroundSafe: Bool { framework.isBackgroundSafe }
}

// MARK: - Profile

/// A complete notes stack: what detects speech, what transcribes it, and what
/// summarizes it into a note.
struct AmbientModelProfile: Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String
    let summary: String
    let vadModelID: String
    /// Ordered ASR candidates, best first. Used only when a tester explicitly
    /// applies this profile in Developer — the main Notes UI never auto-fills
    /// from these lists.
    let asrCandidateIDs: [String]
    /// Suggested LLM candidates for the opt-in summarizer picker (never
    /// auto-applied). A GPU model is allowed because digesting is not always-on;
    /// it just gets deferred to the foreground.
    let digestCandidateIDs: [String]
    /// Lowest tier this profile is allowed to auto-select on.
    let minimumTier: HardwareTier
    /// Approximate resident footprint of the always-on stack, used to reject a
    /// profile that cannot fit in the memory currently available.
    let residentBudgetBytes: Int64

    static let allProfiles: [AmbientModelProfile] = [.compatibility, .quality, .highEnd]

    static func profile(id: String) -> AmbientModelProfile? {
        allProfiles.first { $0.id == id }
    }

    /// The ASR the tester should download when nothing usable is installed.
    var preferredASRModelID: String { asrCandidateIDs.first ?? "" }

    /// Smallest testable stack. Everything is serialized; use it to confirm the
    /// pipeline runs at all before judging quality. Digester stays unset until
    /// the user picks one.
    static let compatibility = AmbientModelProfile(
        id: "compatibility",
        displayName: "Compatibility",
        summary: "Whisper Tiny capture. Digester optional (LFM2 350M suggested).",
        vadModelID: "silero-vad",
        asrCandidateIDs: [
            "sherpa-onnx-whisper-tiny.en",
        ],
        digestCandidateIDs: [
            "lfm2-350m-q4_k_m",
            "qwen3-0.6b-q4_k_m",
            "mlx-lfm2-350m",
            "mlx-qwen3-0.6b-4bit",
        ],
        minimumTier: .lowEnd,
        residentBudgetBytes: 1_200_000_000
    )

    /// The dogfood default capture stack. Digester is never auto-selected —
    /// LFM2 / Qwen ids below are picker suggestions only.
    static let quality = AmbientModelProfile(
        id: "quality",
        displayName: "Quality",
        summary: "Parakeet TDT 0.6B capture. Digester optional (LFM2 350M suggested).",
        vadModelID: "silero-vad",
        asrCandidateIDs: [
            "sherpa-nemo-parakeet-tdt-0.6b-v3-int8",
            "sherpa-onnx-whisper-tiny.en",
        ],
        digestCandidateIDs: [
            "lfm2-350m-q4_k_m",
            "lfm2.5-1.2b-instruct-q4_k_m",
            "qwen3-1.7b-q4_k_m",
            "qwen3-0.6b-q4_k_m",
            "mlx-lfm2-350m",
            "mlx-qwen3-0.6b-4bit",
        ],
        minimumTier: .midRange,
        residentBudgetBytes: 2_600_000_000
    )

    /// Larger capture budget with Qwen3 4B as the suggested digester when the
    /// user opts in to summarizing.
    static let highEnd = AmbientModelProfile(
        id: "high-end",
        displayName: "High-end",
        summary: "Parakeet capture. Digester optional (Qwen3 4B suggested).",
        vadModelID: "silero-vad",
        asrCandidateIDs: AmbientModelProfile.quality.asrCandidateIDs,
        digestCandidateIDs: [
            // Best meeting-note pick at phone size (MeetMemo 2026 A/B).
            "qwen3-4b-instruct-2507-q4_k_m",
            // Speed-first long notes.
            "lfm2.5-1.2b-instruct-q4_k_m",
            // Quality A/Bs (llama.cpp only for long digests — avoid MLX).
            "qwen3-4b-q4_k_m",
            "phi-4-mini-instruct-q4_k_m",
            "llama-3.2-3b-instruct-q4_k_m",
            "gemma-4-e4b-it-q4_k_m",
            "bonsai-8b-q1_0",
            "qwen3-1.7b-q4_k_m",
        ] + AmbientModelProfile.quality.digestCandidateIDs,
        minimumTier: .highEnd,
        residentBudgetBytes: 3_200_000_000
    )
}

// MARK: - Capture Performance Policy

/// Which post-ASR model (if any) stays resident between Label / Summarize passes.
/// Never coresident with ASR, and never both at once (jetsam policy).
enum AmbientWarmKeepTarget: String, CaseIterable, Sendable {
    case none
    case diarization
    case digester

    var displayName: String {
        switch self {
        case .none: return "Unload after use"
        case .diarization: return "Keep Sortformer warm"
        case .digester: return "Keep digester warm"
        }
    }
}

/// Live-capture speed knobs for Notes (Developer / dogfood).
struct AmbientCapturePerformanceSettings: Equatable, Sendable {
    var vadMode: RAAmbientVADMode = .silero
    var warmKeep: AmbientWarmKeepTarget = .none
    /// When RAM allows, run Sortformer on the live PCM tee during capture.
    var streamDiarDuringCapture: Bool = false

    /// Sortformer (~492 MB) + ASR headroom required before streaming diarization.
    static let streamingDiarizationHeadroomBytes: Int64 = 1_800_000_000

    private enum Key {
        static let vadMode = "ambient.vadMode"
        static let warmKeep = "ambient.warmKeep"
        static let streamDiar = "ambient.streamDiarDuringCapture"
    }

    static func load(from defaults: UserDefaults = .standard) -> AmbientCapturePerformanceSettings {
        var settings = AmbientCapturePerformanceSettings()
        if let raw = defaults.string(forKey: Key.vadMode),
           let mode = RAAmbientVADMode(rawValue: raw) {
            settings.vadMode = mode
        }
        if let raw = defaults.string(forKey: Key.warmKeep),
           let keep = AmbientWarmKeepTarget(rawValue: raw) {
            settings.warmKeep = keep
        }
        settings.streamDiarDuringCapture = defaults.bool(forKey: Key.streamDiar)
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(vadMode.rawValue, forKey: Key.vadMode)
        defaults.set(warmKeep.rawValue, forKey: Key.warmKeep)
        defaults.set(streamDiarDuringCapture, forKey: Key.streamDiar)
    }

    /// Whether the device can host ASR + Sortformer together for live diarization.
    func canStreamDiarization(
        availableMemoryBytes: Int64,
        tier: HardwareTier
    ) -> Bool {
        streamDiarDuringCapture
            && tier >= .highEnd
            && availableMemoryBytes >= Self.streamingDiarizationHeadroomBytes
    }
}

// MARK: - Resolved Selection

/// The concrete model ids a session will run — whatever the user picked (and
/// optionally seeded from an explicit Developer profile apply).
struct AmbientModelSelection: Sendable, Equatable {
    var profileID: String
    var vadModelID: String
    var asrModelID: String
    var digestModelID: String?
    /// False when the ASR runs on the GPU; capture is still allowed so limits
    /// can be tested, but the UI warns that lock-screen transcription may stall.
    var isASRBackgroundSafe: Bool = true
    /// False when the digest model runs on the GPU, which means its work has to
    /// wait for the foreground.
    var isDigestBackgroundSafe: Bool = true

    /// IDs are chosen; the view model still requires the files to be on disk
    /// before Record is enabled.
    var canStartCapture: Bool {
        !vadModelID.isEmpty && !asrModelID.isEmpty
    }

    var supportsDigest: Bool { digestModelID != nil }
}

// MARK: - Device Conditions

/// Live device state that gates which profile is safe to run right now.
struct AmbientDeviceConditions: Sendable, Equatable {
    var tier: HardwareTier
    var availableMemoryBytes: Int64
    var thermalState: ProcessInfo.ThermalState
    var isLowPowerModeEnabled: Bool
    var batteryLevel: Float

    /// Summarizing is suspended while the device is hot or the user asked for
    /// maximum battery life. Capture and transcription keep running so the
    /// note stays useful.
    var shouldSuspendDerivedWork: Bool {
        thermalState == .serious || thermalState == .critical || isLowPowerModeEnabled
    }

    /// Capture itself stops only at critical thermals.
    var shouldStopCapture: Bool {
        thermalState == .critical
    }

    var thermalDescription: String {
        switch thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Resolver

/// Maps device conditions plus the live catalog onto a concrete selection.
/// Pure and synchronous so it can be unit tested without the SDK.
struct AmbientModelProfileResolver {

    /// Highest profile the device can currently sustain.
    func recommendedProfile(
        for conditions: AmbientDeviceConditions,
        available models: [RAModelInfo]
    ) -> AmbientModelProfile {
        let candidates = AmbientModelProfile.allProfiles
            .filter { $0.minimumTier <= conditions.tier }
            .filter { $0.residentBudgetBytes <= max(conditions.availableMemoryBytes, 0) }
            .filter { resolve(profile: $0, available: models).canStartCapture }

        // Under thermal pressure or Low Power Mode, deliberately step down to
        // the lightest viable stack rather than the best one.
        if conditions.shouldSuspendDerivedWork {
            return candidates.first ?? .compatibility
        }
        return candidates.last ?? .compatibility
    }

    /// Bind a profile to real catalog ids for capture roles only. Digester is
    /// never filled here — Summarize stays an explicit user pick. Any ASR
    /// framework is accepted for dogfooding; `isASRBackgroundSafe` flags risk.
    func resolve(profile: AmbientModelProfile, available models: [RAModelInfo]) -> AmbientModelSelection {
        let byID = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func firstAvailable(_ ids: [String]) -> RAModelInfo? {
            ids.lazy.compactMap { byID[$0] }.first
        }

        let vad = firstAvailable([profile.vadModelID])
        let asr = firstAvailable(profile.asrCandidateIDs)

        return AmbientModelSelection(
            profileID: profile.id,
            vadModelID: vad?.id ?? "",
            asrModelID: asr?.id ?? "",
            digestModelID: nil,
            isASRBackgroundSafe: asr?.isBackgroundSafe ?? true,
            isDigestBackgroundSafe: true
        )
    }

    /// First suggested digester still registered in the catalog — for picker
    /// hints only, never written into selection automatically.
    func suggestedDigestID(for profile: AmbientModelProfile, available models: [RAModelInfo]) -> String? {
        let byID = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return profile.digestCandidateIDs.first { byID[$0] != nil }
    }

    /// Read current conditions from the device. Battery monitoring is enabled
    /// on demand; the level is `-1` when the platform will not report it.
    @MainActor
    func currentConditions(deviceInfo: SystemDeviceInfo?) -> AmbientDeviceConditions {
        let processInfo = ProcessInfo.processInfo
        #if canImport(UIKit) && !os(macOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        #else
        let batteryLevel: Float = -1
        #endif

        return AmbientDeviceConditions(
            tier: HardwareTierResolver().resolve(from: deviceInfo),
            availableMemoryBytes: deviceInfo?.availableMemory ?? 0,
            thermalState: processInfo.thermalState,
            isLowPowerModeEnabled: processInfo.isLowPowerModeEnabled,
            batteryLevel: batteryLevel
        )
    }
}
