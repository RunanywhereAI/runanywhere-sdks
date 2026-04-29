//
//  TTSHelpers.swift
//  RunAnywhere SDK
//
//  SDK-unique helper types for TTS that are NOT covered by any proto
//  schema in `idl/tts_options.proto`. Per CANONICAL_API §5 / §15:
//    - Proto-overlapping types (TTSOptions/Output/SpeakResult/VoiceInfo)
//      live in `Generated/tts_options.pb.swift` as `RATTSOptions`,
//      `RATTSOutput`, `RATTSSpeakResult`, `RATTSVoiceInfo`, etc.
//    - SDK-unique state wrappers (audio playback session, builder
//      patterns) live HERE so the public surface stays proto-anchored.
//
//  As with LLM/Diffusion, the wrappers in `TTSTypes.swift` are held in
//  place during the v2 cross-SDK parity migration because they expose
//  `withCOptions()` / `init(from cOutput:)` C bridge methods. Once the
//  bridge is rewritten against the proto types directly, the
//  proto-overlap part of `TTSTypes.swift` will be deleted and the
//  helpers below will move into the public root.
//

import Foundation

// MARK: - TTSAudioChunk
//
// Canonical stream element type for `synthesizeStream` (CANONICAL_API §5).
// Pending proto adoption: once `idl/tts_options.proto` gains a `TTSAudioChunk`
// message, this hand-rolled struct will be replaced by the generated type.
//
/// A single audio chunk yielded by `RunAnywhere.synthesizeStream`.
public struct TTSAudioChunk: Sendable {
    /// Raw PCM audio data (Float32, interleaved) for this chunk.
    public let audioData: Data
    /// Sample rate in Hz (e.g. 22050 or 44100).
    public let sampleRate: Int
    /// Whether this is the final chunk in the stream.
    public let isFinal: Bool

    public init(audioData: Data, sampleRate: Int, isFinal: Bool) {
        self.audioData = audioData
        self.sampleRate = sampleRate
        self.isFinal = isFinal
    }
}
