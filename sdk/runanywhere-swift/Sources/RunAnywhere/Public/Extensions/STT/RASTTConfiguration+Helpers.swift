//
//  RASTTConfiguration+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical STT proto types.
//

import Foundation

// MARK: - RASTTLanguage

extension RASTTLanguage {
    /// Map a BCP-47 language string (e.g. "en-US", "zh-Hans") to the canonical enum.
    public static func fromBcp47(_ raw: String) -> RASTTLanguage {
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
        default:     return .unspecified
        }
    }

    public var bcp47Code: String {
        switch self {
        case .unspecified, .UNRECOGNIZED: return ""
        case .auto: return "auto"
        case .en:   return "en"
        case .es:   return "es"
        case .fr:   return "fr"
        case .de:   return "de"
        case .zh:   return "zh"
        case .ja:   return "ja"
        case .ko:   return "ko"
        case .it:   return "it"
        case .pt:   return "pt"
        case .ar:   return "ar"
        case .ru:   return "ru"
        case .hi:   return "hi"
        }
    }
}

// MARK: - RASTTConfiguration

extension RASTTConfiguration {
    public static func defaults(
        modelId: String = "",
        language: RASTTLanguage = .en,
        sampleRate: Int32 = 16_000,
        enableVad: Bool = false
    ) -> RASTTConfiguration {
        var c = RASTTConfiguration()
        c.modelID = modelId
        c.language = language
        c.sampleRate = sampleRate
        c.enableVad = enableVad
        return c
    }

    public func validate() throws {
        guard sampleRate > 0 && sampleRate <= 48_000 else {
            throw SDKException.validationFailed(
                "Sample rate must be between 1 and 48000 Hz (got \(sampleRate))"
            )
        }
    }
}

// MARK: - RASTTOptions

extension RASTTOptions {
    public static func defaults(language: RASTTLanguage = .en) -> RASTTOptions {
        var o = RASTTOptions()
        o.language = language
        o.enablePunctuation = true
        o.enableDiarization = false
        o.enableWordTimestamps = true
        o.maxSpeakers = 0
        o.beamSize = 0
        return o
    }
}

// MARK: - RASTTOutput

extension RASTTOutput {
    public var detectedLanguageCode: RASTTLanguage { language }
}

// MARK: - RAWordTimestamp

extension RAWordTimestamp {
    public init(word: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float) {
        self.init()
        self.word = word
        self.startMs = Int64(startTime * 1000)
        self.endMs = Int64(endTime * 1000)
        self.confidence = confidence
    }

    public var startTime: TimeInterval { TimeInterval(startMs) / 1000.0 }
    public var endTime: TimeInterval { TimeInterval(endMs) / 1000.0 }
    public var duration: TimeInterval { max(0, endTime - startTime) }
}

// MARK: - RATranscriptionMetadata

extension RATranscriptionMetadata {
    public var realTimeFactorComputed: Double {
        guard audioLengthMs > 0 else { return 0 }
        return Double(processingTimeMs) / Double(audioLengthMs)
    }

    public var processingTime: TimeInterval { TimeInterval(processingTimeMs) / 1000.0 }
    public var audioLength: TimeInterval { TimeInterval(audioLengthMs) / 1000.0 }
}

// MARK: - RATranscriptionAlternative

extension RATranscriptionAlternative {
    public init(text: String, confidence: Float) {
        self.init()
        self.text = text
        self.confidence = confidence
    }
}
