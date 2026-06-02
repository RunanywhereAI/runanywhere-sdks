// SPDX-License-Identifier: Apache-2.0
//
// hybrid_stt_router.dart — THIN Dart binding over the commons STT hybrid router
// (rac_stt_hybrid_router + its proto-byte ABI). Per-request dispatch between an
// on-device (offline, sherpa) STT service and a cloud (online, cloud) STT
// service.
//
// Division of labour — commons owns ALL routing: filter phase, rank/sort,
// confidence cascade, and primary→secondary fallback all live in
// rac_stt_hybrid_router.cpp. NONE of that logic is reimplemented here. This
// binding only:
//   1. creates the router handle,
//   2. creates the two STT services through the registry-routed creation path
//      (rac_plugin_route(TRANSCRIBE, hint="sherpa"/"cloud") →
//      stt_ops->create) and attaches them with their HybridModelDescriptor bytes,
//   3. registers any custom-filter predicates and installs the policy bytes,
//   4. drives the router's transcribe and decodes the response.
//
// Mirrors the Kotlin RACRouter.SttRouter + HybridRouterBridgeAdapter and the
// Swift HybridSTTRouter feature surface. All FFI lives in
// `lib/native/dart_bridge_hybrid_stt.dart` (canonical §15 type-discipline).
//
// Lifetime: the router does NOT own the underlying services. This object keeps
// each service in stable native storage for the router's lifetime, clears the
// router slots BEFORE destroying the services (avoiding the use-after-free
// called out in rac_stt_hybrid_router.h), and tears everything down in [close].

import 'dart:typed_data';

import 'package:runanywhere/generated/hybrid_router.pb.dart' as pb;
import 'package:runanywhere/native/dart_bridge_hybrid_stt.dart';
import 'package:runanywhere/native/types/basic_types.dart'
    show RacHandle, RAC_SUCCESS;
import 'package:runanywhere/public/hybrid/hybrid_cloud_backend.dart';
import 'package:runanywhere/public/hybrid/hybrid_model.dart';
import 'package:runanywhere/public/hybrid/hybrid_routing_policy.dart';

/// A hybrid STT router pairing one offline + one online speech service.
///
/// Usage:
/// ```dart
/// RunAnywhere.hybrid.registerCloud();                       // fold cloud plugin in
/// RunAnywhere.hybrid.cloud.register(                         // provider as data
///   id: 'saaras', provider: 'sarvam', model: 'saaras:v2.5', apiKey: '…');
/// RunAnywhere.hybrid.setDeviceStateProvider(myProvider);     // optional NETWORK/Battery
///
/// final router = RunAnywhere.hybrid.createSttRouter();
/// router.setPair(
///   offline: HybridModel.offlineSherpa('sherpa-onnx-whisper-tiny.en'),
///   online:  HybridModel.onlineCloud('saaras'),
///   policy:  const HybridRoutingPolicy(
///     hardFilters: [HybridFilter.network()],
///     cascade: HybridCascade.confidence(0.5),
///   ),
/// );
/// final result = router.transcribe(audioBytes,
///     options: const HybridTranscribeOptions(audioFormat: 1));
/// router.close();
/// ```
class HybridSttRouter {
  HybridSttRouter._(this._handle);

  final DartBridgeHybridStt _bridge = DartBridgeHybridStt.instance;

  RacHandle _handle;
  HybridServiceHandle? _offline;
  HybridServiceHandle? _online;
  List<String> _customFilterNames = const <String>[];
  bool _closed = false;

  /// Allocate a native router handle. Throws [StateError] on failure.
  /// Prefer `RunAnywhere.hybrid.createSttRouter()`.
  factory HybridSttRouter.create() =>
      HybridSttRouter._(DartBridgeHybridStt.instance.createRouter());

  /// Bind the offline + online models, install the [policy], and register any
  /// custom-filter predicates. Replaces any previous pairing.
  ///
  /// [offline] must be an [HybridModelKind.offline] model and [online] an
  /// [HybridModelKind.online] model; otherwise an [ArgumentError] is thrown.
  void setPair({
    required HybridModel offline,
    required HybridModel online,
    HybridRoutingPolicy policy = const HybridRoutingPolicy(),
  }) {
    _ensureOpen();
    if (offline.kind != HybridModelKind.offline) {
      throw ArgumentError.value(
          offline.kind, 'offline', 'must be HybridModelKind.offline');
    }
    if (online.kind != HybridModelKind.online) {
      throw ArgumentError.value(
          online.kind, 'online', 'must be HybridModelKind.online');
    }

    // Build both services up-front so a failure on the online side doesn't
    // leave a half-attached router.
    final offlineService = _createService(offline);
    final HybridServiceHandle onlineService;
    try {
      onlineService = _createService(online);
    } catch (_) {
      _bridge.destroyService(offlineService);
      rethrow;
    }

    // Detach + destroy any previously attached services before swapping in the
    // new pair (clear router slots first — see header UAF note), and retire the
    // previous policy's custom-filter predicates.
    _clearAndDestroyServices();
    _unregisterCustomFilters();

    final rcOff = _bridge.setOfflineService(
        _handle, offlineService, _descriptorBytes(offline));
    if (rcOff != RAC_SUCCESS) {
      _bridge
        ..destroyService(offlineService)
        ..destroyService(onlineService);
      throw StateError('set_offline_service_proto failed (rc=$rcOff)');
    }
    final rcOn = _bridge.setOnlineService(
        _handle, onlineService, _descriptorBytes(online));
    if (rcOn != RAC_SUCCESS) {
      _bridge
        ..setOfflineService(_handle, null, Uint8List(0))
        ..destroyService(offlineService)
        ..destroyService(onlineService);
      throw StateError('set_online_service_proto failed (rc=$rcOn)');
    }

    // Register custom-filter predicates with commons BEFORE installing the
    // policy bytes so the router can resolve each HybridFilter.custom name the
    // first time it filters. The router owns the eval — Dart only supplies the
    // named predicate.
    final customs = policy.customFilters;
    for (final filter in customs) {
      _bridge.registerCustomFilter(filter.name, filter.check);
    }
    final customNames = customs.map((f) => f.name).toList(growable: false);

    final rcPolicy = _bridge.setPolicy(_handle, policy.toProtoBytes());
    if (rcPolicy != RAC_SUCCESS) {
      for (final name in customNames) {
        _bridge.unregisterCustomFilter(name);
      }
      _bridge
        ..setOfflineService(_handle, null, Uint8List(0))
        ..setOnlineService(_handle, null, Uint8List(0))
        ..destroyService(offlineService)
        ..destroyService(onlineService);
      throw StateError('set_policy_proto failed (rc=$rcPolicy)');
    }

    _offline = offlineService;
    _online = onlineService;
    _customFilterNames = customNames;
  }

  /// Run one transcribe request through the router. The router applies the
  /// installed policy (filters → rank → invoke → fallback) in commons and
  /// returns the chosen backend's result plus the routing decision.
  ///
  /// [audioBytes] is file-encoded audio (wav/mp3/flac/...) OR raw PCM; each
  /// engine decodes per its own expectations. Throws [HybridTranscribeException]
  /// when the backend reports a non-zero rc, [StateError] on native failure.
  HybridTranscribeResult transcribe(
    Uint8List audioBytes, {
    HybridTranscribeOptions options = const HybridTranscribeOptions(),
  }) {
    _ensureOpen();
    if (_offline == null || _online == null) {
      throw StateError('setPair() must be called before transcribe()');
    }

    // Pure pass-through: commons owns the entire routing decision. Dart marshals
    // the request and decodes the response; it does NOT pre-filter candidates
    // or toggle slots. HybridRoutingContext is empty on the wire (device-state
    // lives behind the vtable); it is still emitted for a stable wire shape.
    final request = pb.HybridSttTranscribeRequest(
      audioBytes: audioBytes,
      context: pb.HybridRoutingContext(),
      options: pb.HybridSttTranscribeOptions(
        language: options.language,
        sampleRate: options.sampleRate,
        audioFormat: options.audioFormat,
      ),
    );

    final responseBytes = _bridge.transcribe(_handle, request.writeToBuffer());
    return _decodeResponse(responseBytes);
  }

  /// Detach + destroy both services, unregister custom filters, and destroy the
  /// router handle. Idempotent.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _unregisterCustomFilters();
    _clearAndDestroyServices();
    _bridge.destroyRouter(_handle);
    _handle = RacHandle.fromAddress(0);
  }

  // --- Internals -----------------------------------------------------------

  HybridServiceHandle _createService(HybridModel model) {
    final String? configJson;
    if (model.backend == HybridBackend.cloud) {
      final entry = CloudBackend.instance.lookup(model.id);
      if (entry == null) {
        throw StateError(
          "Cloud model id '${model.id}' not registered. Call "
          'RunAnywhere.hybrid.cloud.register(id, model, apiKey) at app startup.',
        );
      }
      configJson = entry.toConfigJson();
      // Cloud engine takes everything via config_json; no model path.
      return _bridge.createService(
        engineHint: model.backend.engineHint,
        modelIdOrPath: '',
        configJson: configJson,
      );
    }
    // Offline (sherpa): the model-registry path-resolution lives in commons;
    // the create routes through the same plugin registry (hint "sherpa").
    return _bridge.createService(
      engineHint: model.backend.engineHint,
      modelIdOrPath: model.id,
    );
  }

  Uint8List _descriptorBytes(HybridModel model) {
    final descriptor = pb.HybridModelDescriptor(
      modelId: model.id,
      modelType: model.kind.proto,
      backend: model.backend.proto,
      provider: model.provider,
    );
    return descriptor.writeToBuffer();
  }

  void _clearAndDestroyServices() {
    // Slot-clearing must precede service destruction (router holds raw
    // pointers — see rac_stt_hybrid_router.h UAF note).
    if (_handle != RacHandle.fromAddress(0)) {
      _bridge
        ..setOfflineService(_handle, null, Uint8List(0))
        ..setOnlineService(_handle, null, Uint8List(0));
    }
    _bridge
      ..destroyService(_offline)
      ..destroyService(_online);
    _offline = null;
    _online = null;
  }

  void _unregisterCustomFilters() {
    for (final name in _customFilterNames) {
      _bridge.unregisterCustomFilter(name);
    }
    _customFilterNames = const <String>[];
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('HybridSttRouter is closed');
    }
  }

  HybridTranscribeResult _decodeResponse(Uint8List bytes) {
    final response = pb.HybridSttTranscribeResponse.fromBuffer(bytes);
    if (response.rc != 0) {
      throw HybridTranscribeException(
        response.rc,
        response.errorMsg.isEmpty
            ? 'Hybrid STT transcribe failed (rc=${response.rc})'
            : response.errorMsg,
      );
    }
    final routing = response.routing;
    return HybridTranscribeResult(
      text: response.text,
      detectedLanguage: response.detectedLanguage,
      routing: HybridRoutedMetadata(
        chosenModelId: routing.chosenModelId,
        wasFallback: routing.wasFallback,
        attemptCount: routing.attemptCount,
        primaryErrorCode: routing.primaryErrorCode,
        primaryErrorMessage: routing.primaryErrorMessage,
        // Default to NaN when the engine surfaced no quality signal (the field
        // is then absent on the wire).
        confidence: routing.hasConfidence() ? routing.confidence : double.nan,
        primaryConfidence: routing.hasPrimaryConfidence()
            ? routing.primaryConfidence
            : double.nan,
      ),
    );
  }
}

/// Thrown by [HybridSttRouter.transcribe] when the chosen backend reports a
/// non-zero native rc. Carries the rc + the human-readable error message from
/// the HybridSttTranscribeResponse.
class HybridTranscribeException implements Exception {
  /// Build a transcribe exception.
  const HybridTranscribeException(this.code, this.message);

  /// Native `rac_result_t` from the failing backend.
  final int code;

  /// Human-readable failure reason.
  final String message;

  @override
  String toString() => 'HybridTranscribeException(code=$code): $message';
}
