//
//  RATTSConfiguration+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical TTS proto types.
//
//  defaults() / validate() factories live in
//  Generated/RAConvenience.swift, emitted by
//  idl/codegen/generate_swift_convenience.py from the rac_default
//  annotations in idl/tts_options.proto.
//

import Foundation

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
