//
//  HybridModel.swift
//  RunAnywhere
//
//  Public model / backend identity + transcribe-result types for the STT
//  hybrid router. Mirrors the Kotlin RACModel / Backend / TranscribeResult
//  shapes and the wire enums in idl/hybrid_router.proto.
//

import Foundation
import SwiftProtobuf

// MARK: - Backend kind

/// Backend identity for a hybrid candidate. The generated proto enum
/// (`RAHybridBackendKind` from hybrid_router.proto / `rac_hybrid_backend_kind_t`)
/// is the source of truth; this binding exposes its cases under the SDK's
/// ergonomic names.
public typealias HybridBackendKind = RAHybridBackendKind

public extension HybridBackendKind {
    static var unspecified: HybridBackendKind { .hybridBackendUnspecified }
    static var llamacpp: HybridBackendKind { .hybridBackendLlamacpp }
    static var openrouter: HybridBackendKind { .hybridBackendOpenrouter }
    /// On-device speech (sherpa-onnx Whisper / Zipformer / Paraformer).
    static var sherpa: HybridBackendKind { .hybridBackendSherpa }
    /// Generic cloud speech (the "cloud" engine). The concrete HTTP
    /// provider (Sarvam first) is carried in the descriptor's `provider`
    /// field. Wire value 4 matches HYBRID_BACKEND_CLOUD.
    static var cloud: HybridBackendKind { .hybridBackendCloud }
}

// MARK: - Model type

/// Whether a candidate runs on-device or in the cloud. Backed by the generated
/// `RAHybridModelType` (wire values match `rac_hybrid_model_type_t`).
public typealias HybridModelType = RAHybridModelType

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
    /// `rac_stt_hybrid_router_set_{offline,online}_service_proto`, using the
    /// generated SwiftProtobuf message (canonical proto3 wire bytes the
    /// C++/JNI side parses).
    func descriptorBytes() throws -> [UInt8] {
        var descriptor = RAHybridModelDescriptor()
        descriptor.modelID = id
        descriptor.modelType = modelType
        descriptor.backend = backend
        descriptor.provider = provider
        return try [UInt8](descriptor.serializedData())
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
/// Always populated, including on cascade/fallback scenarios. Backed by the
/// generated `RAHybridRoutedMetadata` (`chosenModelID`, `wasFallback`,
/// `attemptCount`, `primaryErrorCode`, `primaryErrorMessage`, `confidence`,
/// `primaryConfidence`).
public typealias HybridRoutedMetadata = RAHybridRoutedMetadata

// MARK: - Transcribe options

/// STT options carried through the router (mirror of the C `rac_stt_options_t`
/// knobs the router forwards). All optional with backend-default behaviour.
/// Backed by the generated `RAHybridSttTranscribeOptions` (`language`,
/// `sampleRate`, `audioFormat`).
public typealias HybridTranscribeOptions = RAHybridSttTranscribeOptions
