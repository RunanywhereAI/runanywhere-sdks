// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// `RunAnywhere` public VAD surface — load/unload/detect helpers on top
// of the canonical `loadVAD(_:modelPath:)` entry point.

import Foundation
import CRACommonsCore

@MainActor
public extension RunAnywhere {

    /// Currently-loaded VAD model as a full `ModelInfo`, resolved through
    /// `ModelCatalog`. Returns `nil` when no model is loaded or the id
    /// isn't registered with the catalog.
    static var currentVADModel: ModelInfo? {
        let id = SessionRegistry.currentVADModelId
        guard !id.isEmpty else { return nil }
        return ModelCatalog.model(id: id)
    }

    /// String-typed alias for code paths that only need the id. Kept to
    /// avoid churning every sample call site that already consumed the
    /// String variant. Prefer `currentVADModel?.id` for new code.
    static var currentVADModelId: String? {
        let id = SessionRegistry.currentVADModelId
        return id.isEmpty ? nil : id
    }

    /// True when a VAD model is loaded and ready.
    static var isVADReady: Bool { !SessionRegistry.currentVADModelId.isEmpty }

    /// Load a VAD model by id from the catalog.
    static func loadVADModel(_ modelId: String) async throws {
        guard let info = ModelCatalog.model(id: modelId) else {
            throw RunAnywhereError.invalidArgument(
                "VAD model not registered: \(modelId)")
        }
        var path: UnsafeMutablePointer<CChar>?
        defer { if let p = path { ra_file_string_free(p) } }
        let rc = info.framework.rawValue.withCString { fw in
            modelId.withCString { mid in
                ra_file_model_path(fw, mid, &path)
            }
        }
        guard rc == RA_OK, let raw = path else {
            throw RunAnywhereError.invalidArgument(
                "could not resolve VAD model path: \(modelId)")
        }
        let resolved = info.localPathString ?? String(cString: raw)
        let session = try VADSession(
            modelId: modelId,
            modelPath: resolved,
            format: info.framework.modelFormat)
        SessionRegistry.currentVAD = session
        SessionRegistry.currentVADModelId = modelId
    }

    /// Explicitly initialize the VAD session. No-op today — the session
    /// warms on first `loadVADModel` call. Exposed for API parity with
    /// the main branch.
    static func initializeVAD() async throws {
        guard !SessionRegistry.currentVADModelId.isEmpty else {
            throw RunAnywhereError.backendUnavailable("no VAD model loaded")
        }
    }

    /// Simple RMS-based voice detection over a single audio buffer.
    /// Suitable for UI meters; real voice detection happens inside the
    /// STT pipeline via the loaded VAD session. Throws when no VAD model
    /// has been loaded yet.
    static func detectSpeech(in audio: [Float]) throws -> Bool {
        guard !SessionRegistry.currentVADModelId.isEmpty else {
            throw RunAnywhereError.backendUnavailable("no VAD model loaded")
        }
        guard !audio.isEmpty else { return false }
        var sum: Float = 0
        for s in audio { sum += s * s }
        let rms = (sum / Float(audio.count)).squareRoot()
        return rms > 0.01
    }

    /// Older signature with explicit sample rate + async return. Kept for
    /// call sites that haven't migrated to `detectSpeech(in:)`.
    static func detectSpeech(audio: [Float], sampleRateHz: Int = 16_000) async -> Bool {
        guard !audio.isEmpty else { return false }
        var sum: Float = 0
        for s in audio { sum += s * s }
        let rms = (sum / Float(audio.count)).squareRoot()
        _ = sampleRateHz
        return rms > 0.01
    }
}
