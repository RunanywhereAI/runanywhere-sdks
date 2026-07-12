//
//  RATTSTypes+CppBridge.swift
//  RunAnywhere SDK
//
//  C-bridge extensions on proto-generated RA* TTS types.
//


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
        var options = RATTSOptions()
        options.voice = voice
        options.languageCode = language
        options.speakingRate = rate
        options.pitch = pitch
        options.volume = volume
        options.audioFormat = audioFormat
        options.enableSsml = useSSML
        options.sampleRate = Int32(sampleRate)
        self = options
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

}

// MARK: - RATTSOutput

public extension RATTSOutput {
    var format: RAAudioFormat { audioFormat }
}

// Post-Phase-6h, TTS synthesis arrives as proto bytes via
// `rac_tts_synthesize_lifecycle_proto` and decodes directly into `RATTSOutput`.
// `withCOptions`, `RATTSOutput.init(from cOutput:)`, the
// `RATTSSynthesisMetadata(processingTime:)` convenience init, and the
// `RATTSSpeakResult(from output:)` repack were orphaned after that migration.
// Deleted per swift.md SWIFT-DUP-RACTYPES-CPPBRIDGE-DEAD.
