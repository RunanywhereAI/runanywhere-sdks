//
//  HybridModel.swift
//  RunAnywhere
//
//  Public model / backend identity + transcribe-result types for the STT
//  hybrid router. Mirrors the Kotlin RACModel / Backend / TranscribeResult
//  shapes and the wire enums in idl/hybrid_router.proto.
//

import Foundation

// MARK: - Backend kind

/// Backend identity for a hybrid candidate. Wire values match
/// `HybridBackendKind` in hybrid_router.proto / `rac_hybrid_backend_kind_t`.
public enum HybridBackendKind: Int32, Sendable {
    case unspecified = 0
    case llamacpp = 1
    case openrouter = 2
    /// On-device speech (sherpa-onnx Whisper / Zipformer / Paraformer).
    case sherpa = 3
    /// Generic cloud speech (the "cloud" engine). The concrete HTTP
    /// provider (Sarvam first) is carried in the descriptor's `provider`
    /// field. Raw value 4 matches HYBRID_BACKEND_CLOUD on the wire.
    case cloud = 4
}

// MARK: - Model type

/// Whether a candidate runs on-device or in the cloud. Wire values match
/// `HybridModelType` / `rac_hybrid_model_type_t`.
public enum HybridModelType: Int32, Sendable {
    case offline = 1
    case online = 2
}

// MARK: - Model descriptor

/// One side of the hybrid pair. `id` is the resolution key:
///   * offline (`.sherpa`) — the model id the C model registry resolves so the
///     engine can load the model files.
///   * online (`.cloud`) — the registry id registered via
///     `Cloud.register(id:provider:model:apiKey:)`, which supplies the
///     provider, model string + credentials.
public struct HybridModel: Sendable {
    public let id: String
    public let modelType: HybridModelType
    public let backend: HybridBackendKind
    /// Concrete cloud provider when `backend == .cloud` (e.g. "sarvam"). Empty
    /// for non-cloud backends; marshalled into the descriptor's `provider`
    /// field (proto tag 4) so the cloud engine selects the HTTP backend.
    public let provider: String

    public init(
        id: String,
        modelType: HybridModelType,
        backend: HybridBackendKind,
        provider: String = ""
    ) {
        self.id = id
        self.modelType = modelType
        self.backend = backend
        self.provider = provider
    }

    /// Convenience for an on-device sherpa model.
    public static func offlineSherpa(_ id: String) -> HybridModel {
        HybridModel(id: id, modelType: .offline, backend: .sherpa)
    }

    /// Convenience for a cloud model (registered via `Cloud.register`).
    /// `provider` defaults to `Cloud.defaultProvider` ("sarvam") and is
    /// carried in the descriptor so the cloud engine picks the HTTP backend.
    public static func onlineCloud(
        _ id: String,
        provider: String = Cloud.defaultProvider
    ) -> HybridModel {
        HybridModel(id: id, modelType: .online, backend: .cloud, provider: provider)
    }

    /// Encode as `runanywhere.v1.HybridModelDescriptor` bytes for
    /// `rac_stt_hybrid_router_set_{offline,online}_service_proto`.
    func descriptorBytes() -> [UInt8] {
        var writer = ProtoWireWriter()
        writer.string(1, id)                    // string model_id = 1
        writer.enumValue(2, modelType.rawValue) // HybridModelType model_type = 2
        writer.enumValue(3, backend.rawValue)   // HybridBackendKind backend = 3
        writer.string(4, provider)              // string provider = 4 (cloud only; "" omitted)
        return writer.bytes
    }
}

// MARK: - Result types

/// One transcribe call's outcome through the hybrid STT router.
public struct HybridTranscribeResult: Sendable {
    /// Transcript text from the chosen backend.
    public let text: String
    /// BCP-47 language code reported by the backend (empty when none surfaced).
    public let detectedLanguage: String
    /// Which side ran, whether it was a fallback, and why the primary failed.
    public let routing: HybridRoutedMetadata

    public init(text: String, detectedLanguage: String, routing: HybridRoutedMetadata) {
        self.text = text
        self.detectedLanguage = detectedLanguage
        self.routing = routing
    }
}

/// Metadata describing the routing decision behind a `HybridTranscribeResult`.
/// Always populated, including on cascade/fallback scenarios.
public struct HybridRoutedMetadata: Sendable {
    /// Model id of the candidate that produced the result.
    public let chosenModelId: String
    /// True when the secondary served the request after the primary failed or
    /// scored below the cascade threshold.
    public let wasFallback: Bool
    /// Backends invoked (1 = primary only, 2 = primary then secondary).
    public let attemptCount: Int32
    /// Native `rac_result_t` from the primary when `wasFallback` and the
    /// fallback fired on an error; else 0.
    public let primaryErrorCode: Int32
    /// Human-readable reason the primary failed; else empty.
    public let primaryErrorMessage: String
    /// Final confidence of the chosen result. `.nan` when no quality signal.
    public let confidence: Float
    /// Primary's confidence captured before a confidence-based cascade.
    /// `.nan` when no confidence cascade occurred.
    public let primaryConfidence: Float

    public init(
        chosenModelId: String,
        wasFallback: Bool,
        attemptCount: Int32,
        primaryErrorCode: Int32,
        primaryErrorMessage: String,
        confidence: Float,
        primaryConfidence: Float
    ) {
        self.chosenModelId = chosenModelId
        self.wasFallback = wasFallback
        self.attemptCount = attemptCount
        self.primaryErrorCode = primaryErrorCode
        self.primaryErrorMessage = primaryErrorMessage
        self.confidence = confidence
        self.primaryConfidence = primaryConfidence
    }
}

// MARK: - Transcribe options

/// STT options carried through the router (mirror of the C `rac_stt_options_t`
/// knobs the router forwards). All optional with backend-default behaviour.
public struct HybridTranscribeOptions: Sendable {
    /// BCP-47 hint. Empty = backend auto-detect.
    public var language: String
    /// Sample-rate hint for raw PCM input. 0 = engine default (16000).
    public var sampleRate: Int32
    /// `rac_audio_format_enum_t`: 0=PCM, 1=WAV, 2=MP3, 3=OPUS, 4=AAC, 5=FLAC.
    /// 0 leaves the format unspecified.
    public var audioFormat: Int32

    public init(language: String = "", sampleRate: Int32 = 0, audioFormat: Int32 = 0) {
        self.language = language
        self.sampleRate = sampleRate
        self.audioFormat = audioFormat
    }
}
