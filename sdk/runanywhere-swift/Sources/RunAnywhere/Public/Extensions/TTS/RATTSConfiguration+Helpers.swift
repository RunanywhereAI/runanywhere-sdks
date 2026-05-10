//
//  RATTSConfiguration+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical TTS proto types.
//

import CRACommons
import Foundation

// MARK: - RATTSConfiguration

extension RATTSConfiguration {
    /// Canonical defaults sourced from C++ commons (P2-T14).
    public static func defaults(
        modelId: String = "",
        voice: String = "default",
        languageCode: String = "en-US"
    ) -> RATTSConfiguration {
        var outBuffer = rac_proto_buffer_t()
        defer { rac_proto_buffer_free(&outBuffer) }
        guard rac_tts_configuration_defaults_proto(&outBuffer) == RAC_SUCCESS,
              let data = outBuffer.data, outBuffer.size > 0,
              var proto = try? RATTSConfiguration(
                serializedBytes: Data(bytes: data, count: outBuffer.size)
              )
        else {
            return RATTSConfiguration()
        }
        proto.modelID = modelId
        proto.voice = voice
        proto.languageCode = languageCode
        return proto
    }
}

// MARK: - RATTSOptions

extension RATTSOptions {
    public static func defaults() -> RATTSOptions {
        var o = RATTSOptions()
        o.languageCode = "en-US"
        o.speakingRate = 1.0
        o.pitch = 1.0
        o.volume = 1.0
        o.enableSsml = false
        o.audioFormat = .pcm
        o.sampleRate = 22_050
        return o
    }
}

// MARK: - RATTSOutput

extension RATTSOutput {
    public var duration: TimeInterval { TimeInterval(durationMs) / 1000.0 }
}

// MARK: - RATTSSpeakResult

extension RATTSSpeakResult {
    public init(output: RATTSOutput) {
        self.init()
        self.audioFormat = output.audioFormat
        self.sampleRate = output.sampleRate
        self.durationMs = output.durationMs
        self.audioSizeBytes = output.audioSizeBytes > 0 ? output.audioSizeBytes : Int64(output.audioData.count)
        if output.hasMetadata {
            self.metadata = output.metadata
        }
        self.timestampMs = output.timestampMs
    }

    public var duration: TimeInterval { TimeInterval(durationMs) / 1000.0 }
}
