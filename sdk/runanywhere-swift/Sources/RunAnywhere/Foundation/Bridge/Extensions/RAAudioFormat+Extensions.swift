//
//  AudioTypes.swift
//  RunAnywhere SDK
//
//  Audio-related type definitions used across audio components (STT, TTS, VAD).
//
//  🟢 BRIDGE: Maps to C++ rac_audio_format_enum_t
//  C++ Source: include/rac/features/stt/rac_stt_types.h
//
//  GAP 01 Phase 2: `AudioFormat` is now a typealias for the proto3-generated
//  `RAAudioFormat` (idl/model_types.proto). The hand-written enum has been
//  removed; extensions below preserve the same public surface (fileExtension,
//  mimeType, toCFormat, init(from:)) and add Codable/Sendable conformance.
//

import CRACommons
import Foundation
import SwiftProtobuf

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
        var c = encoder.singleValueContainer()
        try c.encode(self.wireString)
    }
}

// MARK: - Public extensions (preserved from hand-written enum)

public extension RAAudioFormat {
    /// All known concrete cases, excluding `.unspecified` and `UNRECOGNIZED`.
    /// Convenient for UI pickers that previously used
    /// `AudioFormat.allCases` on the hand-written enum.
    static var knownCases: [RAAudioFormat] {
        [.pcm, .wav, .mp3, .opus, .aac, .flac, .ogg, .m4A, .pcmS16Le]
    }

    /// File extension for this format.
    var fileExtension: String { wireString }

    /// MIME type for this format.
    var mimeType: String {
        switch self {
        case .pcm:     return "audio/pcm"
        case .wav:     return "audio/wav"
        case .mp3:     return "audio/mpeg"
        case .opus:    return "audio/opus"
        case .aac:     return "audio/aac"
        case .flac:    return "audio/flac"
        case .ogg:     return "audio/ogg"
        case .m4A:     return "audio/mp4"
        case .pcmS16Le: return "audio/pcm"
        case .unspecified, .UNRECOGNIZED: return "application/octet-stream"
        }
    }

    // MARK: - C++ Bridge (rac_audio_format_enum_t)

    /// Convert Swift AudioFormat to C++ rac_audio_format_enum_t.
    func toCFormat() -> rac_audio_format_enum_t {
        switch self {
        case .pcm:  return RAC_AUDIO_FORMAT_PCM
        case .wav:  return RAC_AUDIO_FORMAT_WAV
        case .mp3:  return RAC_AUDIO_FORMAT_MP3
        case .opus: return RAC_AUDIO_FORMAT_OPUS
        case .aac:  return RAC_AUDIO_FORMAT_AAC
        case .flac: return RAC_AUDIO_FORMAT_FLAC
        default:    return RAC_AUDIO_FORMAT_PCM
        }
    }

    /// Initialize from C++ rac_audio_format_enum_t.
    init(from cFormat: rac_audio_format_enum_t) {
        switch cFormat {
        case RAC_AUDIO_FORMAT_PCM:  self = .pcm
        case RAC_AUDIO_FORMAT_WAV:  self = .wav
        case RAC_AUDIO_FORMAT_MP3:  self = .mp3
        case RAC_AUDIO_FORMAT_OPUS: self = .opus
        case RAC_AUDIO_FORMAT_AAC:  self = .aac
        case RAC_AUDIO_FORMAT_FLAC: self = .flac
        default:                    self = .pcm
        }
    }
}
