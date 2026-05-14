//
//  RASTTConfiguration+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical STT proto types.
//
//  defaults() / validate() factories live in
//  Generated/RAConvenience.swift, emitted by
//  idl/codegen/generate_swift_convenience.py from the rac_default /
//  rac_min / rac_max annotations in idl/stt_options.proto.
//


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

// MARK: - RASTTOutput

extension RASTTOutput {
    public var detectedLanguageCode: RASTTLanguage { language }
}
