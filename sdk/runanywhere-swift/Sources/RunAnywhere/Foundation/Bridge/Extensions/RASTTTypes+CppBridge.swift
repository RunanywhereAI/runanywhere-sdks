//
//  RASTTTypes+CppBridge.swift
//  RunAnywhere SDK
//
//  C-bridge extensions on proto-generated RA* STT types.
//

import Foundation

// MARK: - RASTTOptions: C-bridge + convenience

public extension RASTTOptions {
    init(
        language: String = "en",
        detectLanguage: Bool = false,
        enablePunctuation: Bool = true,
        enableDiarization: Bool = false,
        maxSpeakers: Int = 0,
        enableTimestamps: Bool = true,
        vocabularyFilter: [String] = []
    ) {
        var options = RASTTOptions()
        // `language` is an optional BCP-47 string; leaving it unset asks the
        // backend to auto-detect.
        if !detectLanguage, !language.isEmpty {
            options.language = language
        }
        options.enablePunctuation = enablePunctuation
        options.enableDiarization = enableDiarization
        options.maxSpeakers = Int32(maxSpeakers)
        options.enableWordTimestamps = enableTimestamps
        options.vocabularyList = vocabularyFilter
        self = options
    }
}

// MARK: - RASTTOutput

extension RASTTOutput {
    public var timestamp: Date { Date() }
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
