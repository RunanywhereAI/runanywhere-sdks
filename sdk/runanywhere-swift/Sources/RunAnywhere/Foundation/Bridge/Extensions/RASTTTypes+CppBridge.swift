//
//  RASTTTypes+CppBridge.swift
//  RunAnywhere SDK
//
//  C-bridge extensions on proto-generated RA* STT types.
//

import CRACommons
import Foundation

// MARK: - RASTTConfiguration: ComponentConfiguration

extension RASTTConfiguration: ComponentConfiguration {
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
        var o = RASTTOptions()
        o.language = detectLanguage ? .auto : RASTTOptions.languageFromString(language)
        o.enablePunctuation = enablePunctuation
        o.enableDiarization = enableDiarization
        o.maxSpeakers = Int32(maxSpeakers)
        o.enableWordTimestamps = enableTimestamps
        o.vocabularyList = vocabularyFilter
        self = o
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

    func withCOptions<T>(_ body: (UnsafePointer<rac_stt_options_t>) throws -> T) rethrows -> T {
        var cOptions = rac_stt_options_t()
        cOptions.detect_language = (language == .auto) ? RAC_TRUE : RAC_FALSE
        cOptions.enable_punctuation = enablePunctuation ? RAC_TRUE : RAC_FALSE
        cOptions.enable_diarization = enableDiarization ? RAC_TRUE : RAC_FALSE
        cOptions.max_speakers = maxSpeakers
        cOptions.enable_timestamps = enableWordTimestamps ? RAC_TRUE : RAC_FALSE
        cOptions.audio_format = RAC_AUDIO_FORMAT_PCM
        cOptions.sample_rate = 16000
        return try languageString.withCString { langPtr in
            cOptions.language = langPtr
            return try body(&cOptions)
        }
    }
}

// MARK: - RASTTOutput: ComponentOutput

extension RASTTOutput: ComponentOutput {
    public var timestamp: Date { Date() }
}

public extension RASTTOutput {
    init(from cOutput: rac_stt_output_t) {
        var words: [RAWordTimestamp] = []
        if cOutput.num_word_timestamps > 0, let cWords = cOutput.word_timestamps {
            words = (0..<Int(cOutput.num_word_timestamps)).compactMap { i in
                let w = cWords[i]
                guard let txt = w.text else { return nil }
                var wt = RAWordTimestamp()
                wt.word = String(cString: txt)
                wt.startMs = Int64(w.start_ms)
                wt.endMs = Int64(w.end_ms)
                wt.confidence = w.confidence
                return wt
            }
        }

        var alts: [RATranscriptionAlternative] = []
        if cOutput.num_alternatives > 0, let cAlts = cOutput.alternatives {
            alts = (0..<Int(cOutput.num_alternatives)).compactMap { i in
                let a = cAlts[i]
                guard let txt = a.text else { return nil }
                var alt = RATranscriptionAlternative()
                alt.text = String(cString: txt)
                alt.confidence = a.confidence
                return alt
            }
        }

        var meta = RATranscriptionMetadata()
        meta.modelID = cOutput.metadata.model_id.map { String(cString: $0) } ?? ""
        meta.processingTimeMs = cOutput.metadata.processing_time_ms
        meta.audioLengthMs = cOutput.metadata.audio_length_ms
        if meta.audioLengthMs > 0 {
            meta.realTimeFactor = Float(meta.processingTimeMs) / Float(meta.audioLengthMs)
        }

        var o = RASTTOutput()
        o.text = cOutput.text.map { String(cString: $0) } ?? ""
        o.confidence = cOutput.confidence
        o.words = words
        o.alternatives = alts
        o.metadata = meta
        if let lang = cOutput.detected_language.map({ String(cString: $0) }) {
            o.language = RASTTOptions.languageFromString(lang)
        }
        self = o
    }
}

// MARK: - RATranscriptionMetadata: C-bridge

public extension RATranscriptionMetadata {
    init(modelId: String, processingTime: TimeInterval, audioLength: TimeInterval) {
        var m = RATranscriptionMetadata()
        m.modelID = modelId
        m.processingTimeMs = Int64(processingTime * 1000)
        m.audioLengthMs = Int64(audioLength * 1000)
        m.realTimeFactor = audioLength > 0 ? Float(processingTime / audioLength) : 0
        self = m
    }
}

// MARK: - RASTTPartialResult

public extension RASTTPartialResult {
    var transcript: String { text }
}
