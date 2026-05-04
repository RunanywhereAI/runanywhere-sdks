//
//  RunAnywhere+SpeakerDiarization.swift
//  RunAnywhere SDK
//
//  Public API for Speaker Diarization (B12, §8) — identifies which speaker
//  produced each chunk of an audio stream.
//
//  Status: TODO-stub facade. The C ABI exists in runanywhere-commons
//    (rac_speaker_diarization_init / _process / _destroy — see
//     `sdk/runanywhere-commons/include/rac/features/speaker_diarization/
//      rac_speaker_diarization.h`)
//  but:
//    1. `rac_speaker_diarization.cpp` is a stub returning
//       `RAC_ERROR_FEATURE_NOT_AVAILABLE`.
//    2. The header is NOT yet exposed through the Swift `CRACommons`
//       umbrella header (`Sources/RunAnywhere/CRACommons/include/CRACommons.h`),
//       so the symbols cannot be called from Swift until the header is added.
//
//  This facade therefore:
//    - `loadDiarizationModel(_:)` throws `SDKException.runtime(.featureNotAvailable, …)`.
//    - `diarize(audio:)` logs a warning via `os_log` and returns `[]`.
//    - `unloadDiarization()` is a no-op.
//
//  TODO(diarization): when the real C++ implementation lands, also
//  update `CRACommons/include/CRACommons.h` to `#include "rac_speaker_diarization.h"`
//  and ship the header. Then replace the bodies below with direct C ABI
//  calls (see the archived richer implementation in git history for
//  `DiarizationSession` scaffolding). The public surface below stays the
//  same.
//

import Foundation
import os

// MARK: - Public Types

/// One speaker segment returned by `RunAnywhere.diarize(audio:)`.
///
/// Represents a contiguous span of audio attributed to a single speaker.
public struct SpeakerSegment: Sendable, Hashable, Codable {

    /// Zero-based speaker index. Stable within a single diarization session
    /// (consecutive calls on the same handle), not across sessions.
    public let speaker: Int

    /// Segment start time in milliseconds from the beginning of the audio.
    public let startMs: Int

    /// Segment end time in milliseconds from the beginning of the audio.
    public let endMs: Int

    public init(speaker: Int, startMs: Int, endMs: Int) {
        self.speaker = speaker
        self.startMs = startMs
        self.endMs = endMs
    }
}

// MARK: - Public Facade

public extension RunAnywhere {

    /// Load the speaker-diarization model.
    ///
    /// - Parameter modelPath: Filesystem path to the diarization model.
    /// - Throws: `SDKException.runtime(.featureNotAvailable, _)` until
    ///   the native diarization implementation has been integrated
    ///   into commons and exposed through the Swift `CRACommons`
    ///   umbrella header.
    static func loadDiarizationModel(_ modelPath: String) async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        os_log("Speaker diarization not yet available in commons. modelPath=%{public}@",
               log: .default, type: .info, modelPath)
        throw SDKException.runtime(
            .featureNotAvailable,
            "Speaker diarization is not yet integrated in runanywhere-commons."
        )
    }

    /// True if a diarization session is loaded. Always `false` while the
    /// feature is stubbed.
    static var isDiarizationLoaded: Bool {
        get async { false }
    }

    /// Run speaker diarization on a buffer of PCM float samples (16 kHz mono).
    ///
    /// - Parameter audio: Raw IEEE-754 single-precision PCM samples as `Data`
    ///   (4 bytes per sample).
    /// - Returns: Array of `SpeakerSegment` ordered by `startMs`. Empty
    ///   array while the native diarization feature is not yet available
    ///   (a warning is logged so the gap is diagnosable).
    static func diarize(audio: Data) async throws -> [SpeakerSegment] {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        os_log("diarize: feature not yet available in commons (stub). Returning []. audioBytes=%d",
               log: .default, type: .info, audio.count)
        return []
    }

    /// Release the diarization session and free its resources.
    ///
    /// No-op while the feature is stubbed.
    static func unloadDiarization() async {
        // No resources to release while stubbed.
    }
}
