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

// MARK: - Backend / engine identity

/// Plugin-registry engine name for a hybrid candidate — a free-form string
/// (`rac_plugin_find_for_engine`'s lookup key), not a closed enum.
/// `RAHybridBackendKind` was deleted outright (idl/hybrid_router.proto):
/// `HybridModelDescriptor.backend` + `.provider` were replaced by a single
/// `engine: string` field so a new backend name is not a proto change.
public typealias HybridBackendKind = String

public extension HybridBackendKind {
    static var unspecified: HybridBackendKind { "" }
    static var llamacpp: HybridBackendKind { "llamacpp" }
    /// On-device speech (sherpa-onnx Whisper / Zipformer / Paraformer).
    static var sherpa: HybridBackendKind { "sherpa" }
    /// Generic cloud speech (the "cloud" engine). The concrete HTTP
    /// provider (Sarvam first) is resolved by the cloud engine from its own
    /// config, not carried on the descriptor anymore.
    static var cloud: HybridBackendKind { "cloud" }
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
    /// `true` when the candidate runs on-device (offline), `false` for cloud
    /// (online). Marshalled into the descriptor's `is_on_device` field
    /// (idl/hybrid_router.proto renamed `is_local` -> `is_on_device`).
    public let isLocal: Bool
    /// Plugin-registry engine name (`rac_plugin_find_for_engine`'s lookup
    /// key): "sherpa", "llamacpp", "onnx", "qhexrt", "mlx", "cloud", or any
    /// name passed to `registerCloudProvider`. Empty lets the registry pick
    /// by priority.
    public let backend: HybridBackendKind

    public init(
        id: String,
        isLocal: Bool,
        backend: HybridBackendKind
    ) {
        self.id = id
        self.isLocal = isLocal
        self.backend = backend
    }

    /// Convenience for an on-device sherpa model.
    public static func offlineSherpa(_ id: String) -> HybridModel {
        HybridModel(id: id, isLocal: true, backend: .sherpa)
    }

    /// Convenience for a cloud model (registered via `Cloud.register`).
    /// The concrete HTTP provider (Sarvam first) is resolved by the cloud
    /// engine from the config the caller registered — it no longer rides on
    /// this descriptor (idl/hybrid_router.proto deleted `provider` outright).
    public static func onlineCloud(_ id: String) -> HybridModel {
        HybridModel(id: id, isLocal: false, backend: .cloud)
    }

    /// Encode as `runanywhere.v1.HybridModelDescriptor` bytes for
    /// `rac_stt_hybrid_router_set_{offline,online}_service_proto`, using the
    /// generated SwiftProtobuf message (canonical proto3 wire bytes the
    /// C++/JNI side parses).
    func descriptorBytes() throws -> [UInt8] {
        var descriptor = RAHybridModelDescriptor()
        descriptor.modelID = id
        descriptor.isOnDevice = isLocal
        descriptor.engine = backend
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
