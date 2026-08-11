//
//  RAAudioFormat+Extensions.swift
//  RunAnywhere SDK
//
//  Audio-related type definitions used across audio components (STT, TTS, VAD).
//
//  🟢 BRIDGE: Maps to C++ rac_audio_format_enum_t
//  C++ Source: include/rac/features/stt/rac_stt_types.h
//
//  `RAAudioFormat` is the proto3-generated enum (idl/model_types.proto);
//  call sites reference it directly (no `AudioFormat` typealias is exported).
//  This extension provides Codable conformance using the annotated canonical
//  JSON wire names.
//


// MARK: - Codable (wire format = lowercase short name)
//
// The canonical JSON names are lowercase ("pcm", "wav", …), supplied by the
// codegen-generated `wireString` /
// `from(wireString:)` accessors (Generated/RAConvenience.swift) which are
// emitted from the `rac_wire_string` annotations in idl/model_types.proto.

extension RAAudioFormat: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RAAudioFormat.from(wireString: raw) ?? .unspecified
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wireString)
    }
}
