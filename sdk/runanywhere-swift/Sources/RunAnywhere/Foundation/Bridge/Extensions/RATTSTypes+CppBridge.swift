//
//  RATTSTypes+CppBridge.swift
//  RunAnywhere SDK
//
//  C-bridge extensions on proto-generated RA* TTS types.
//

import CRACommons
import Foundation

// MARK: - RATTSConfiguration: ComponentConfiguration

extension RATTSConfiguration: ComponentConfiguration {
    public var modelId: String? { modelID.isEmpty ? nil : modelID }
}

// MARK: - RATTSOptions: C-bridge + convenience

public extension RATTSOptions {
    init(
        voice: String = "",
        language: String = "",
        rate: Float = 1.0,
        pitch: Float = 1.0,
        volume: Float = 1.0,
        audioFormat: RAAudioFormat = .pcm,
        sampleRate: Int = 22050,
        useSSML: Bool = false
    ) {
        var o = RATTSOptions()
        o.voice = voice
        o.languageCode = language
        o.speakingRate = rate
        o.pitch = pitch
        o.volume = volume
        o.audioFormat = audioFormat
        o.enableSsml = useSSML
        self = o
    }

    var rate: Float {
        get { speakingRate }
        set { speakingRate = newValue }
    }

    var language: String {
        get { languageCode }
        set { languageCode = newValue }
    }

    var useSSML: Bool {
        get { enableSsml }
        set { enableSsml = newValue }
    }

    func withCOptions<T>(_ body: (UnsafePointer<rac_tts_options_t>) throws -> T) rethrows -> T {
        var cOptions = rac_tts_options_t()
        cOptions.rate = speakingRate == 0 ? 1.0 : speakingRate
        cOptions.pitch = pitch == 0 ? 1.0 : pitch
        cOptions.volume = volume == 0 ? 1.0 : volume
        cOptions.audio_format = audioFormat.toCFormat()
        cOptions.sample_rate = 22050
        cOptions.use_ssml = enableSsml ? RAC_TRUE : RAC_FALSE
        return try languageCode.withCString { langPtr in
            cOptions.language = langPtr
            if voice.isEmpty {
                cOptions.voice = nil
                return try body(&cOptions)
            } else {
                return try voice.withCString { voicePtr in
                    cOptions.voice = voicePtr
                    return try body(&cOptions)
                }
            }
        }
    }
}

// MARK: - RATTSOutput: ComponentOutput

extension RATTSOutput: ComponentOutput { }

public extension RATTSOutput {
    var format: RAAudioFormat { audioFormat }

    init(from cOutput: rac_tts_output_t) {
        let audioData: Data
        if cOutput.audio_size > 0, let ptr = cOutput.audio_data {
            audioData = Data(bytes: ptr, count: cOutput.audio_size)
        } else {
            audioData = Data()
        }

        var phonemes: [RATTSPhonemeTimestamp] = []
        if cOutput.num_phoneme_timestamps > 0, let cPh = cOutput.phoneme_timestamps {
            for i in 0..<Int(cOutput.num_phoneme_timestamps) {
                let p = cPh[i]
                guard let sym = p.phoneme else { continue }
                var pt = RATTSPhonemeTimestamp()
                pt.phoneme = String(cString: sym)
                pt.startMs = p.start_time_ms
                pt.endMs = p.end_time_ms
                phonemes.append(pt)
            }
        }

        var meta = RATTSSynthesisMetadata()
        meta.processingTimeMs = cOutput.metadata.processing_time_ms
        meta.characterCount = cOutput.metadata.character_count

        var o = RATTSOutput()
        o.audioData = audioData
        o.audioFormat = RAAudioFormat(from: cOutput.format)
        o.durationMs = cOutput.duration_ms
        o.phonemeTimestamps = phonemes
        o.metadata = meta
        o.timestampMs = cOutput.timestamp_ms
        self = o
    }
}

// MARK: - RATTSSynthesisMetadata: C-bridge

public extension RATTSSynthesisMetadata {
    init(processingTime: TimeInterval) {
        var m = RATTSSynthesisMetadata()
        m.processingTimeMs = Int64(processingTime * 1000)
        self = m
    }
}

// MARK: - RATTSSpeakResult

public extension RATTSSpeakResult {
    init(from output: RATTSOutput) {
        var r = RATTSSpeakResult()
        r.durationMs = output.durationMs
        r.audioSizeBytes = Int64(output.audioData.count)
        r.metadata = output.metadata
        self = r
    }
}
