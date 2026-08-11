//
//  RASTTTypes+CppBridge.swift
//  RunAnywhere SDK
//
//  C-bridge extensions on proto-generated RA* STT types.
//

import Foundation

// MARK: - RASTTOptions: C-bridge + convenience

public extension RASTTOptions {
    // enableDiarization -> diarize, maxSpeakers -> speakersExpected (now
    // optional presence-tracked), vocabularyList deleted outright (no
    // replacement) — all idl/stt_options.proto renames/removals. No live
    // caller of this initializer exists; kept only so callers that
    // construct via named args at the old spelling still compile.
    init(
        language: String = "en",
        detectLanguage: Bool = false,
        enablePunctuation: Bool = true,
        diarize: Bool = false,
        speakersExpected: Int? = nil,
        enableTimestamps: Bool = true
    ) {
        var options = RASTTOptions()
        // `language` is an optional BCP-47 string; leaving it unset asks the
        // backend to auto-detect.
        if !detectLanguage, !language.isEmpty {
            options.language = language
        }
        options.enablePunctuation = enablePunctuation
        options.diarize = diarize
        if let speakersExpected { options.speakersExpected = Int32(speakersExpected) }
        options.enableWordTimestamps = enableTimestamps
        self = options
    }
}

// MARK: - RASTTOutput

extension RASTTOutput {
    public var timestamp: Date {
        Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0)
    }
}

// Post-Phase-6h, STT transcription arrives as proto bytes via
// `rac_stt_transcribe_lifecycle_proto` and decodes directly into `RASTTOutput`.
// The `init(from cOutput: rac_stt_output_t)` constructor that used to live here
// had zero live callers after that migration. Deleted per swift.md
// SWIFT-DUP-RACTYPES-CPPBRIDGE-DEAD. Same for `withCOptions` and the
// `RATranscriptionMetadata` convenience init.

// MARK: - RASTTPartialResult

public extension RASTTPartialResult {
    var transcript: String { text }
}
