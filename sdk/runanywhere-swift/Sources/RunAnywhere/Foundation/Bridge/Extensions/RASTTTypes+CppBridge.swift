//
//  RASTTTypes+CppBridge.swift
//  RunAnywhere SDK
//
//  C-bridge extensions on proto-generated RA* STT types.
//

import Foundation

// MARK: - RASTTConfiguration

extension RASTTConfiguration {
    public var modelId: String? { modelID.isEmpty ? nil : modelID }
}

// MARK: - RASTTOptions: C-bridge + convenience

public extension RASTTOptions {
    var languageString: String {
        switch language {
        case .auto:    return "auto"
        case .en:      return "en"
        case .es:      return "es"
        case .fr:      return "fr"
        case .de:      return "de"
        case .zh:      return "zh"
        case .ja:      return "ja"
        case .ko:      return "ko"
        case .it:      return "it"
        case .pt:      return "pt"
        case .ar:      return "ar"
        case .ru:      return "ru"
        case .hi:      return "hi"
        default:       return "en"
        }
    }

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
        options.language = detectLanguage ? .auto : RASTTOptions.languageFromString(language)
        options.enablePunctuation = enablePunctuation
        options.enableDiarization = enableDiarization
        options.maxSpeakers = Int32(maxSpeakers)
        options.enableWordTimestamps = enableTimestamps
        options.vocabularyList = vocabularyFilter
        self = options
    }

    static func languageFromString(_ raw: String) -> RASTTLanguage {
        let base = raw.split(separator: "-").first.map(String.init)?.lowercased() ?? raw.lowercased()
        switch base {
        case "auto": return .auto
        case "en":   return .en
        case "es":   return .es
        case "fr":   return .fr
        case "de":   return .de
        case "zh":   return .zh
        case "ja":   return .ja
        case "ko":   return .ko
        case "it":   return .it
        case "pt":   return .pt
        case "ar":   return .ar
        case "ru":   return .ru
        case "hi":   return .hi
        default:     return .en
        }
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
