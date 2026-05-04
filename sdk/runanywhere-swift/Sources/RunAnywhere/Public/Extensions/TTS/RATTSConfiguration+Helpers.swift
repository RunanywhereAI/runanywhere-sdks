//
//  RATTSConfiguration+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical TTS proto types.
//

import Foundation

// MARK: - RATTSConfiguration

extension RATTSConfiguration {
    public static func defaults(
        modelId: String = "",
        voice: String = "default",
        languageCode: String = "en-US"
    ) -> RATTSConfiguration {
        var c = RATTSConfiguration()
        c.modelID = modelId
        c.voice = voice
        c.languageCode = languageCode
        c.speakingRate = 1.0
        c.pitch = 1.0
        c.volume = 1.0
        c.audioFormat = .pcm
        c.sampleRate = 22_050
        c.enableNeuralVoice = true
        c.enableSsml = false
        return c
    }

    public func validate() throws {
        if speakingRate != 0 {
            guard (0.5...2.0).contains(speakingRate) else {
                throw SDKException.validationFailed(
                    "Speaking rate must be in 0.5...2.0 (got \(speakingRate))"
                )
            }
        }
        if pitch != 0 {
            guard (0.5...2.0).contains(pitch) else {
                throw SDKException.validationFailed(
                    "Pitch must be in 0.5...2.0 (got \(pitch))"
                )
            }
        }
        if volume != 0 {
            guard (0.0...1.0).contains(volume) else {
                throw SDKException.validationFailed(
                    "Volume must be in 0.0...1.0 (got \(volume))"
                )
            }
        }
    }
}

// MARK: - RATTSOptions

extension RATTSOptions {
    public static func defaults() -> RATTSOptions {
        var o = RATTSOptions()
        o.speakingRate = 1.0
        o.pitch = 1.0
        o.volume = 1.0
        o.enableSsml = false
        return o
    }
}

// MARK: - RATTSPhonemeTimestamp

extension RATTSPhonemeTimestamp {
    public init(phoneme: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.init()
        self.phoneme = phoneme
        self.startMs = Int64(startTime * 1000)
        self.endMs = Int64(endTime * 1000)
    }

    public var startTime: TimeInterval { TimeInterval(startMs) / 1000.0 }
    public var endTime: TimeInterval { TimeInterval(endMs) / 1000.0 }
    public var duration: TimeInterval { max(0, endTime - startTime) }
}

// MARK: - RATTSSynthesisMetadata

extension RATTSSynthesisMetadata {
    public var processingTime: TimeInterval { TimeInterval(processingTimeMs) / 1000.0 }
    public var audioDuration: TimeInterval { TimeInterval(audioDurationMs) / 1000.0 }
}

// MARK: - RATTSOutput

extension RATTSOutput {
    public var duration: TimeInterval { TimeInterval(durationMs) / 1000.0 }
    public var timestamp: Date {
        Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0)
    }
}
