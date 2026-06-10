//
//  ModelTypes.swift
//  RunAnywhere SDK
//
//  Public types for model management. Thin wrappers over C++ types in
//  rac_model_types.h. Business logic (format support, capability checks)
//  lives in C++.
//
//  P3-T2: most of the per-enum switch tables that used to live here have
//  been replaced by calls into the C ABI exposed via CRACommons:
//    - `rac_model_format_wire_string`
//    - `rac_inference_framework_wire_string` / `_display_name` /
//      `_analytics_key` / `_from_string`
//    - `rac_model_category_requires_context_length`
//    - `rac_model_category_supports_thinking`
//    - `rac_archive_type_extension`
//    - `rac_archive_type_from_path`
//
//  Wire strings now match the proto enum names emitted by swift-protobuf
//  (e.g. `INFERENCE_FRAMEWORK_LLAMA_CPP`). The accompanying `from_string`
//  decoder accepts wire strings, analytics keys, and display names
//  case-insensitively, so legacy Codable inputs continue to round-trip.
//
//  Artifact / archive / expected-files helpers (RAModelInfo.make,
//  resolvedPrimaryModelPath, inferredArtifact, etc.) live in
//  `ModelTypes+Artifacts.swift` to keep this file below the SwiftLint
//  `file_length` threshold.
//

import CRACommons
import Foundation

// MARK: - Typealiases to proto-generated enums

public typealias ModelSource = RAModelSource
public typealias ModelFormat = RAModelFormat
public typealias ModelCategory = RAModelCategory
public typealias InferenceFramework = RAInferenceFramework
public typealias ArchiveType = RAArchiveType
public typealias ArchiveStructure = RAArchiveStructure

// MARK: - Internal helper for wrapping `rac_*_wire_string` style ABIs

/// Calls a C ABI of shape `rac_result_t fn(IN, const char** out)` and returns
/// the resulting null-terminated string, or `fallback` if the call fails or
/// returns NULL. Statically-allocated literal — caller must not free.
@inline(__always)
private func cWireString(
    _ fallback: String,
    _ block: (UnsafeMutablePointer<UnsafePointer<CChar>?>) -> rac_result_t
) -> String {
    var ptr: UnsafePointer<CChar>?
    guard block(&ptr) == RAC_SUCCESS, let raw = ptr else { return fallback }
    return String(cString: raw)
}

// MARK: - ModelSource
//
// Note: `SwiftProtobuf.Enum` already refines `Sendable`, so no extra
// `@unchecked Sendable` is required on the typealiased enums.
//
// `wireString` / `from(wireString:)` are codegen-generated in
// Generated/RAConvenience.swift from the `rac_wire_string` annotations in
// idl/model_types.proto.

extension RAModelSource: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RAModelSource.from(wireString: raw) ?? .unspecified
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wireString)
    }
}

// MARK: - ModelFormat

extension RAModelFormat: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RAModelFormat.fromWireString(raw) ?? .unknown
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wireString)
    }
}

public extension RAModelFormat {
    /// Canonical wire string. Returns the proto enum name
    /// (e.g. `MODEL_FORMAT_GGUF`) supplied by `rac_model_format_wire_string`.
    ///
    /// The proto enum (`RAModelFormat`) is value-aligned with the C++ binary's
    /// `rac_model_format_t`. We forward `rawValue` directly rather than via
    /// `ModelTypes+CppBridge.toC()` because the local `rac_model_types.h`
    /// header in CRACommons/include/ still uses pre-proto numeric ordering.
    var wireString: String {
        cWireString("MODEL_FORMAT_UNKNOWN") {
            rac_model_format_wire_string(rac_model_format_t(UInt32(self.rawValue)), $0)
        }
    }

    /// Parse a `RAModelFormat` from a wire string. Matches case-insensitively
    /// against the proto-name `wireString` emitted by `rac_model_format_wire_string`
    /// (e.g. `MODEL_FORMAT_GGUF`) AND the legacy short extension string from
    /// `rac_model_format_extension` (e.g. `gguf`, `onnx`, `mlmodel`). The
    /// legacy fallback preserves Codable round-trip for persisted model
    /// metadata that was written with the pre-IDL short names — see comment
    /// record `hotspot-swift-public-features-004`.
    static func fromWireString(_ raw: String) -> RAModelFormat? {
        let lowered = raw.lowercased()
        for format in RAModelFormat.allCases {
            if format.wireString.lowercased() == lowered { return format }
            if let extPtr = rac_model_format_extension(format.toC()),
               String(cString: extPtr).lowercased() == lowered {
                return format
            }
        }
        return nil
    }
}

// MARK: - ModelCategory
//
// `wireString` / `from(wireString:)` are codegen-generated in
// Generated/RAConvenience.swift from the `rac_wire_string` annotations in
// idl/model_types.proto.

extension RAModelCategory: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RAModelCategory.from(wireString: raw) ?? .unspecified
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wireString)
    }
}

public extension RAModelCategory {
    /// Whether this category typically requires a context length.
    /// Delegates to `rac_model_category_requires_context_length`.
    var requiresContextLength: Bool {
        rac_model_category_requires_context_length(self.toC()) == RAC_TRUE
    }

    /// Whether this category typically supports thinking/reasoning.
    /// Delegates to `rac_model_category_supports_thinking`.
    var supportsThinking: Bool {
        rac_model_category_supports_thinking(self.toC()) == RAC_TRUE
    }
}

// MARK: - InferenceFramework

extension RAInferenceFramework: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let parsed = RAInferenceFramework(caseInsensitive: raw) {
            self = parsed
        } else {
            self = .unknown
        }
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wireString)
    }
}

public extension RAInferenceFramework {
    /// Canonical wire string. Returns the proto enum name
    /// (e.g. `INFERENCE_FRAMEWORK_LLAMA_CPP`) supplied by
    /// `rac_inference_framework_wire_string`.
    var wireString: String {
        cWireString("INFERENCE_FRAMEWORK_UNKNOWN") {
            rac_inference_framework_wire_string(self.toCFramework(), $0)
        }
    }

    /// Human-readable display name from `rac_inference_framework_display_name`.
    var displayName: String {
        cWireString("Unknown") {
            rac_inference_framework_display_name(self.toCFramework(), $0)
        }
    }

    /// Snake_case key for analytics/telemetry from
    /// `rac_inference_framework_analytics_key`.
    var analyticsKey: String {
        cWireString("unknown") {
            rac_inference_framework_analytics_key(self.toCFramework(), $0)
        }
    }

    /// Convert Swift InferenceFramework to C rac_inference_framework_t.
    /// Delegates to commons' `rac_inference_framework_from_proto`, which
    /// maps the proto enum int32 value (this enum's rawValue) to the C
    /// enum's legacy ordering.
    func toCFramework() -> rac_inference_framework_t {
        var out: rac_inference_framework_t = RAC_FRAMEWORK_UNKNOWN
        _ = rac_inference_framework_from_proto(Int32(self.rawValue), &out)
        return out
    }

    /// Create Swift InferenceFramework from C rac_inference_framework_t.
    /// Delegates to commons' `rac_inference_framework_to_proto`, which
    /// maps the C enum back to the proto enum int32 value.
    static func fromCFramework(_ cFramework: rac_inference_framework_t) -> RAInferenceFramework {
        var protoValue: Int32 = 0
        guard rac_inference_framework_to_proto(cFramework, &protoValue) == RAC_SUCCESS else {
            return .unknown
        }
        return RAInferenceFramework(rawValue: Int(protoValue)) ?? .unknown
    }

    /// Initialize from a string matching case-insensitively against wire names,
    /// display names, and analytics keys. Delegates to
    /// `rac_inference_framework_from_string`.
    init?(caseInsensitive string: String) {
        var cFramework: rac_inference_framework_t = RAC_FRAMEWORK_UNKNOWN
        guard rac_inference_framework_from_string(string, &cFramework) == RAC_SUCCESS else { return nil }
        self = RAInferenceFramework.fromCFramework(cFramework)
    }

    /// All known concrete cases (excludes `.UNRECOGNIZED` and `.unspecified`).
    static var knownCases: [RAInferenceFramework] {
        [
            .onnx, .sherpa, .llamaCpp, .foundationModels, .systemTts, .fluidAudio,
            .coreml, .mlx, .metalrt, .genie,
            .tflite, .executorch, .mediapipe, .mlc, .picoLlm,
            .piperTts, .swiftTransformers,
            .builtIn, .none, .unknown
        ]
    }

    // MARK: - Pre-IDL case-name aliases
    //
    // The hand-written `InferenceFramework` enum used `.systemTTS` (UK-TLA
    // camel-case). Proto conversion normalizes to `.systemTts`. Aliases below
    // keep every existing call site compiling with zero edits.

    static var systemTTS: RAInferenceFramework { .systemTts }
    static var picoLLM: RAInferenceFramework { .picoLlm }
    static var piperTTS: RAInferenceFramework { .piperTts }
    static var execuTorch: RAInferenceFramework { .executorch }
    static var mediaPipe: RAInferenceFramework { .mediapipe }
}

extension RAThinkingTagPattern: Codable {
    // `defaultPattern` lives in `RALLMTypes+CppBridge.swift` (canonical
    // C-bridge extension). Codable conformance stays here next to the other
    // model-type Codable extensions so RAModelInfo persists cleanly to JSON.

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        openTag = try container.decodeIfPresent(String.self, forKey: .openTag) ?? ""
        closeTag = try container.decodeIfPresent(String.self, forKey: .closeTag) ?? ""
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(openTag, forKey: .openTag)
        try container.encode(closeTag, forKey: .closeTag)
    }

    private enum CodingKeys: String, CodingKey {
        case openTag
        case closeTag
    }
}

// MARK: - ArchiveType

extension RAArchiveType: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RAArchiveType.fromWireString(raw) ?? .unspecified
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wireString)
    }
}

public extension RAArchiveType {
    /// Canonical proto wire string (e.g. `ARCHIVE_TYPE_ZIP`). The proto enum
    /// has no `rac_archive_type_wire_string` ABI, so the name is built from the
    /// value to stay aligned with `idl/model_types.proto`'s `ARCHIVE_TYPE_*`.
    var wireString: String {
        switch self {
        case .unspecified: return "ARCHIVE_TYPE_UNSPECIFIED"
        case .zip:         return "ARCHIVE_TYPE_ZIP"
        case .tarBz2:      return "ARCHIVE_TYPE_TAR_BZ2"
        case .tarGz:       return "ARCHIVE_TYPE_TAR_GZ"
        case .tarXz:       return "ARCHIVE_TYPE_TAR_XZ"
        default:           return "ARCHIVE_TYPE_UNSPECIFIED"
        }
    }

    /// Parse a `RAArchiveType` from a wire string. Matches case-insensitively
    /// against the canonical proto-name `wireString` (e.g. `ARCHIVE_TYPE_ZIP`)
    /// AND the legacy short extension from `rac_archive_type_extension`
    /// (e.g. `zip`, `tar.bz2`, `tbz2`). The legacy fallback preserves Codable
    /// round-trip for persisted model metadata written with the pre-IDL short
    /// names, mirroring `RAModelFormat.fromWireString`.
    static func fromWireString(_ raw: String) -> RAArchiveType? {
        let lowered = raw.lowercased()
        switch lowered {
        case "tbz2": return .tarBz2
        case "tgz":  return .tarGz
        case "txz":  return .tarXz
        default:     break
        }
        for type in RAArchiveType.allCases {
            if type.wireString.lowercased() == lowered { return type }
            if !type.fileExtension.isEmpty,
               type.fileExtension.lowercased() == lowered {
                return type
            }
        }
        return nil
    }

    /// File extension used in URLs, sourced from
    /// `rac_archive_type_extension` (e.g. "zip", "tar.bz2").
    var fileExtension: String {
        guard let raw = rac_archive_type_extension(self.toC()) else { return "" }
        return String(cString: raw)
    }

    /// Short uppercase form used in UI labels (e.g. "ZIP", "TAR.BZ2").
    var displayName: String { fileExtension.uppercased() }

    /// Detect archive type from URL suffix via `rac_archive_type_from_path`.
    static func from(url: URL) -> RAArchiveType? {
        var cType: rac_archive_type_t = RAC_ARCHIVE_TYPE_NONE
        guard rac_archive_type_from_path(url.path, &cType) == RAC_TRUE,
              let resolved = RAArchiveType(from: cType) else { return nil }
        return resolved
    }
}

// MARK: - ArchiveStructure
//
// `wireString` / `from(wireString:)` are codegen-generated in
// Generated/RAConvenience.swift from the `rac_wire_string` annotations in
// idl/model_types.proto.

extension RAArchiveStructure: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RAArchiveStructure.from(wireString: raw) ?? .unspecified
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wireString)
    }
}
