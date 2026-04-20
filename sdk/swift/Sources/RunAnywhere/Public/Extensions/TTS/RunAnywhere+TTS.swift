// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// `RunAnywhere` public TTS surface — model-id-only `loadTTSModel`,
// `speak`/`stopSpeaking`, and voice-id accessors on top of the
// canonical `loadTTS(_:modelPath:)` entry point.

import Foundation
import CRACommonsCore

/// Audio format discriminator for `TTSSpeakResult.format`.
public enum TTSAudioFormat: String, Sendable {
    case pcm, wav, mp3, flac
}

public struct TTSSpeakResult: Sendable {
    public let audioData: Data
    public let sampleRateHz: Int
    public let durationSeconds: Double
    public let format: TTSAudioFormat
    public let metadata: TTSMetadata
    /// Alias used by sample UI code paths.
    public var duration: Double { durationSeconds }
    /// Size in bytes of the rendered audio payload.
    public var audioSizeBytes: Int { audioData.count }
    public init(audioData: Data, sampleRateHz: Int, durationSeconds: Double,
                format: TTSAudioFormat = .pcm,
                metadata: TTSMetadata = TTSMetadata()) {
        self.audioData = audioData
        self.sampleRateHz = sampleRateHz
        self.durationSeconds = durationSeconds
        self.format = format
        self.metadata = metadata
    }
}

@MainActor
public extension RunAnywhere {

    /// Currently-loaded TTS voice id, or nil.
    static var currentTTSVoiceId: String? {
        let id = SessionRegistry.currentTTSVoiceId
        return id.isEmpty ? nil : id
    }

    /// Load a TTS model/voice by id from the catalog.
    static func loadTTSModel(_ modelId: String) async throws {
        guard let info = ModelCatalog.model(id: modelId) else {
            throw RunAnywhereError.invalidArgument(
                "TTS model not registered: \(modelId)")
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
                "could not resolve TTS model path: \(modelId)")
        }
        let resolved = info.localPathString ?? String(cString: raw)
        try loadTTS(modelId, modelPath: resolved, format: info.framework.modelFormat)
        SessionRegistry.currentTTSVoiceId = modelId
    }

    /// Unload the current TTS voice.
    static func unloadTTSVoice() async {
        SessionRegistry.currentTTS = nil
        SessionRegistry.currentTTSVoiceId = ""
    }

    /// Synthesize `text` and return a convenience result struct bundling
    /// the PCM, sample rate, and duration. Calls the underlying
    /// `synthesize(_:options:)` entry point.
    static func speak(_ text: String, options: TTSOptions = .init())
        async throws -> TTSSpeakResult
    {
        let result = try await synthesize(text, options: options)
        let seconds = result.sampleRateHz > 0
            ? Double(result.pcm.count) / Double(result.sampleRateHz)
            : 0
        return TTSSpeakResult(
            audioData: Data(bytes: result.pcm,
                              count: result.pcm.count * MemoryLayout<Float>.size),
            sampleRateHz: result.sampleRateHz,
            durationSeconds: seconds)
    }

    /// Stop any in-flight TTS playback. Best-effort — v2 streams synth
    /// results; this is a hook sample apps can call from UI cancel buttons.
    static func stopSpeaking() async {
        // No persistent playback state held by the SDK; the sample's
        // `AudioPlaybackManager` owns the queue and handles actual stop.
    }
}
