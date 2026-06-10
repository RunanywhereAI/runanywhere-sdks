// SPDX-License-Identifier: Apache-2.0
//
// hybrid_model.dart — Public model / backend identity types for the STT hybrid
// router. Mirrors the Kotlin RACModel / Backend shapes
// (sdk/runanywhere-kotlin/.../public/hybrid) and the Swift HybridModel, plus the
// wire enums in idl/hybrid_router.proto. Transcribe options / result / routing
// metadata are the generated proto types (see note below).
//
// `provider` is DATA carried in config / on the descriptor — there is no
// per-provider Dart class. The generic cloud backend ("cloud") selects the
// concrete HTTP provider (Sarvam first) from this string.

import 'package:runanywhere/generated/hybrid_router.pbenum.dart'
    show HybridBackendKind, HybridModelType;

/// Default cloud STT provider when a caller omits one. Carried into the
/// descriptor's `provider` field + the create config so the cloud engine
/// selects the right HTTP backend.
const String kHybridDefaultCloudProvider = 'sarvam';

/// Whether a candidate runs on-device or in the cloud. Convenience mirror of
/// `ROUTER.OFFLINE` / `ROUTER.ONLINE` in the Kotlin SDK; wire values match
/// `HybridModelType` in hybrid_router.proto.
enum HybridModelKind {
  /// On-device backend (e.g. sherpa-onnx).
  offline(HybridModelType.HYBRID_MODEL_TYPE_OFFLINE),

  /// Cloud backend (the generic cloud engine).
  online(HybridModelType.HYBRID_MODEL_TYPE_ONLINE);

  const HybridModelKind(this.proto);

  /// The generated proto enum this maps to on the wire.
  final HybridModelType proto;
}

/// Identifies one of the two models a hybrid router dispatches between.
///
/// `id` is the resolution key:
///   * offline ([HybridBackend.sherpa]) — the model id the C model registry
///     resolves so the engine can load the model files.
///   * online ([HybridBackend.cloud]) — the registry id registered via
///     `BACKEND.cloud.register(id, model, apiKey)`, which supplies the
///     provider, model string + credentials.
class HybridModel {
  /// Build a model for one side of the pair. Prefer the [offlineSherpa] /
  /// [onlineCloud] factories so [kind] / [backend] stay correct by construction.
  const HybridModel({
    required this.id,
    required this.kind,
    required this.backend,
    this.provider = '',
  });

  /// Registry identifier shared with the SDK (model-registry id for offline,
  /// cloud-registry id for online).
  final String id;

  /// Whether this side runs on-device or in the cloud.
  final HybridModelKind kind;

  /// Backend identity for this candidate.
  final HybridBackend backend;

  /// Concrete cloud provider when [backend] == [HybridBackend.cloud] (e.g.
  /// "sarvam"). Empty for non-cloud backends; marshalled into the descriptor's
  /// `provider` field so the cloud engine selects the HTTP backend.
  final String provider;

  /// Convenience for an on-device sherpa model.
  static HybridModel offlineSherpa(String id) => HybridModel(
        id: id,
        kind: HybridModelKind.offline,
        backend: HybridBackend.sherpa,
      );

  /// Convenience for a cloud model (registered via `BACKEND.cloud.register`).
  /// [provider] defaults to [kHybridDefaultCloudProvider] ("sarvam") and is
  /// carried in the descriptor so the cloud engine picks the HTTP backend.
  static HybridModel onlineCloud(
    String id, {
    String provider = kHybridDefaultCloudProvider,
  }) =>
      HybridModel(
        id: id,
        kind: HybridModelKind.online,
        backend: HybridBackend.cloud,
        provider: provider,
      );
}

/// Backend identity for a hybrid candidate. Wire values match
/// `HybridBackendKind` in hybrid_router.proto / `rac_hybrid_backend_kind_t`.
/// Carries the engine name `rac_plugin_find_for_engine` pins on for service
/// creation.
enum HybridBackend {
  /// On-device speech (sherpa-onnx Whisper / Zipformer / Paraformer).
  sherpa(HybridBackendKind.HYBRID_BACKEND_SHERPA, 'sherpa'),

  /// Generic cloud speech (the "cloud" engine). The concrete HTTP provider
  /// (Sarvam first) is carried in the descriptor's `provider` field.
  cloud(HybridBackendKind.HYBRID_BACKEND_CLOUD, 'cloud');

  const HybridBackend(this.proto, this.engineHint);

  /// The generated proto enum this maps to on the wire.
  final HybridBackendKind proto;

  /// The plugin name `rac_plugin_find_for_engine` hard-pins for this backend.
  final String engineHint;
}

// Transcribe options / result / routing metadata are the generated proto types
// `HybridSttTranscribeOptions`, `HybridSttTranscribeResponse`, and
// `HybridRoutedMetadata` from `generated/hybrid_router.pb.dart` (re-exported via
// `runanywhere_protos.dart`). The hand-written duplicates were removed; the
// router ([HybridSttRouter.transcribe]) now builds and returns the generated
// types directly.
