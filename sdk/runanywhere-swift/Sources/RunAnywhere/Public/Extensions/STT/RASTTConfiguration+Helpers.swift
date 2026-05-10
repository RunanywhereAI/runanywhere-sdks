//
//  RASTTConfiguration+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical STT proto types.
//

import CRACommons
import Foundation

// MARK: - RASTTLanguage
//
// Forward map (`bcp47Code`) is sourced from the codegen-generated
// `wireString` accessor (see idl/stt_options.proto rac_wire_string
// annotations + Generated/RAConvenience.swift). The reverse map
// (`fromBcp47`) stays in Swift because the convenience post-processor only
// emits forward enum→string accessors today; promoting it would require a
// reverse-map emitter in idl/codegen/generate_swift_convenience.py, which
// is deferred until a second modality needs the same shape.

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

    /// BCP-47 base language code (e.g. "en", "zh"). Empty for unspecified
    /// or unrecognized values. Backed by `rac_wire_string` annotations in
    /// idl/stt_options.proto via the generated `wireString` accessor.
    public var bcp47Code: String { wireString }
}

// MARK: - RASTTConfiguration

extension RASTTConfiguration {
    /// Canonical defaults sourced from C++ commons (P2-T14).
    public static func defaults() -> RASTTConfiguration {
        var outBuffer = rac_proto_buffer_t()
        defer { rac_proto_buffer_free(&outBuffer) }
        guard rac_stt_configuration_defaults_proto(&outBuffer) == RAC_SUCCESS,
              let data = outBuffer.data, outBuffer.size > 0,
              let proto = try? RASTTConfiguration(
                serializedBytes: Data(bytes: data, count: outBuffer.size)
              )
        else {
            return RASTTConfiguration()
        }
        return proto
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
