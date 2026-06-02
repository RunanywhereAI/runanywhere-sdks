// SPDX-License-Identifier: Apache-2.0
//
// hybrid_model.dart — Public model / backend identity + transcribe-result
// types for the STT hybrid router. Mirrors the Kotlin RACModel / Backend /
// TranscribeResult shapes (sdk/runanywhere-kotlin/.../public/hybrid) and the
// Swift HybridModel / HybridTranscribeResult, plus the wire enums in
// idl/hybrid_router.proto.
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
/// Carries the engine hint `rac_plugin_route` pins on for service creation.
enum HybridBackend {
  /// On-device speech (sherpa-onnx Whisper / Zipformer / Paraformer).
  sherpa(HybridBackendKind.HYBRID_BACKEND_SHERPA, 'sherpa'),

  /// Generic cloud speech (the "cloud" engine). The concrete HTTP provider
  /// (Sarvam first) is carried in the descriptor's `provider` field.
  cloud(HybridBackendKind.HYBRID_BACKEND_CLOUD, 'cloud');

  const HybridBackend(this.proto, this.engineHint);

  /// The generated proto enum this maps to on the wire.
  final HybridBackendKind proto;

  /// The plugin name `rac_plugin_route` hard-pins for this backend.
  final String engineHint;
}

/// STT options carried through the router (mirror of the C `rac_stt_options_t`
/// knobs the router forwards). All optional with backend-default behaviour.
class HybridTranscribeOptions {
  /// Build transcription options for one hybrid request.
  const HybridTranscribeOptions({
    this.language = '',
    this.sampleRate = 0,
    this.audioFormat = 0,
  });

  /// BCP-47 hint. Empty = backend auto-detect.
  final String language;

  /// Sample-rate hint for raw PCM input. 0 = engine default (16000).
  final int sampleRate;

  /// `rac_audio_format_enum_t`: 0=PCM, 1=WAV, 2=MP3, 3=OPUS, 4=AAC, 5=FLAC.
  /// 0 leaves the format unspecified.
  final int audioFormat;
}

/// One transcribe call's outcome through the hybrid STT router.
class HybridTranscribeResult {
  /// Build the public result decoded from a HybridSttTranscribeResponse.
  const HybridTranscribeResult({
    required this.text,
    required this.detectedLanguage,
    required this.routing,
  });

  /// Transcript text from the chosen backend.
  final String text;

  /// BCP-47 language code reported by the backend (empty when none surfaced).
  final String detectedLanguage;

  /// Which side ran, whether it was a fallback, and why the primary failed.
  final HybridRoutedMetadata routing;
}

/// Metadata describing the routing decision behind a [HybridTranscribeResult].
/// Always populated, including on cascade/fallback scenarios.
class HybridRoutedMetadata {
  /// Build routing metadata decoded from HybridRoutedMetadata bytes.
  const HybridRoutedMetadata({
    required this.chosenModelId,
    required this.wasFallback,
    required this.attemptCount,
    this.primaryErrorCode = 0,
    this.primaryErrorMessage = '',
    this.confidence = double.nan,
    this.primaryConfidence = double.nan,
  });

  /// Model id of the candidate that produced the result.
  final String chosenModelId;

  /// True when the secondary served the request after the primary failed or
  /// scored below the cascade threshold.
  final bool wasFallback;

  /// Backends invoked (1 = primary only, 2 = primary then secondary).
  final int attemptCount;

  /// Native `rac_result_t` from the primary when [wasFallback] and the fallback
  /// fired on an error; else 0.
  final int primaryErrorCode;

  /// Human-readable reason the primary failed; else empty.
  final String primaryErrorMessage;

  /// Final confidence of the chosen result. NaN when no quality signal.
  final double confidence;

  /// Primary's confidence captured before a confidence-based cascade. NaN when
  /// no confidence cascade occurred.
  final double primaryConfidence;
}
