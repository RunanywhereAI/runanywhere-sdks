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


// MARK: - RASTTOutput

extension RASTTOutput {
    /// BCP-47 code of the language the backend detected, or nil when the
    /// backend did not report one.
    public var detectedLanguageCode: String? { hasLanguage ? language : nil }
}
