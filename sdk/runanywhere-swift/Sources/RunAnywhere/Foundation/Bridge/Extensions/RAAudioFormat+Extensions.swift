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
//  This extension preserves Codable conformance for JSON wire compatibility
//  with payloads that pre-date the proto canonical string form.
//


// MARK: - Codable (wire format = lowercase short name)
//
// Existing JSON payloads use lowercase short names ("pcm", "wav", …). The
// proto3 canonical string form would be uppercase `AUDIO_FORMAT_*`. We keep
// the wire format compatible via the codegen-generated `wireString` /
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
