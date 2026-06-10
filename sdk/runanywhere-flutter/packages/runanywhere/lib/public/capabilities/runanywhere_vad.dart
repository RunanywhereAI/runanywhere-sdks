// SPDX-License-Identifier: Apache-2.0
//
// VAD capability backed by commons model lifecycle and lifecycle-owned
// generated-proto frame processing.

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/component_types.pbenum.dart'
    show ComponentLifecycleState;
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/sdk_events.pb.dart'
    show ComponentLifecycleSnapshot;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/generated/vad_options.pb.dart'
    show
        VADAudioEncoding,
        VADAudioSource,
        VADOptions,
        VADProcessRequest,
        VADResult;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_vad.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';

/// Voice Activity Detection (VAD) capability surface.
///
/// Access via `RunAnywhere.vad`. Model load/current/unload state is
/// owned by commons lifecycle; one-shot frame processing uses the
/// lifecycle-owned generated-proto commons ABI.
class RunAnywhereVAD {
  RunAnywhereVAD._();

  static final RunAnywhereVAD _instance = RunAnywhereVAD._();
  static RunAnywhereVAD get shared => _instance;

  final _logger = SDKLogger('RunAnywhere.VAD');



  /// Detect voice activity from PCM16 bytes.
  Future<VADResult> detectVoiceActivity(
    Uint8List audio, [
    VADOptions? options,
  ]) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return _processAudioData(
      audio,
      options ?? VADOptions(),
      VADAudioEncoding.VAD_AUDIO_ENCODING_PCM_S16_LE,
    );
  }




  /// Reset VAD state.
  void reset() {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    if (!isModelLoaded) {
      // No-op when no VAD model is loaded through lifecycle.
      return;
    }
    DartBridgeVAD.shared.resetLifecycleProto();
  }


  /// Stream VAD results from a continuous audio byte stream.
  ///
  /// Mirrors Swift's `RunAnywhere.streamVAD(audio:)`. The canonical Flutter
  /// VAD surface is `detectVoiceActivity(...)` / `streamVAD(...)` / `reset()`.
  /// Per-event callback setters were intentionally removed (see Swift's
  /// public VAD surface in `RunAnywhere+VAD.swift`); subscribe to this
  /// stream instead of registering a speech-activity callback.
  Stream<VADResult> streamVAD(Stream<Uint8List> audio) async* {
    await for (final chunk in audio) {
      yield await detectVoiceActivity(chunk);
    }
  }

  /// True when commons lifecycle has a ready VAD model.
  bool get isModelLoaded {
    final snapshot = _lifecycleSnapshot;
    return snapshot != null &&
        snapshot.state ==
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
        snapshot.modelId.isNotEmpty;
  }

  /// Currently-loaded VAD model id, or null.
  String? get currentModelId {
    final snapshot = _lifecycleSnapshot;
    if (snapshot == null ||
        snapshot.state !=
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY ||
        snapshot.modelId.isEmpty) {
      return null;
    }
    return snapshot.modelId;
  }

  /// Currently-loaded VAD model info, or null.
  Future<ModelInfo?> currentModel() async {
    final current = await RunAnywhereModelLifecycle.shared.current(
      model_pb.CurrentModelRequest(
        category: _vadCategory,
        includeModelMetadata: true,
      ),
    );
    if (!current.found || current.modelId.isEmpty || !current.hasModel()) {
      return null;
    }
    return current.model;
  }

  /// Load a VAD model by id through commons lifecycle routing.
  Future<void> loadModel(String modelId) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    await DartBridge.ensureServicesReady();

    _logger.info('Loading VAD model: $modelId');
    final result = await RunAnywhereModelLifecycle.shared.load(
      model_pb.ModelLoadRequest(
        modelId: modelId,
        category: _vadCategory,
        forceReload: true,
        validateAvailability: true,
      ),
    );
    if (!result.success) {
      throw SDKException.modelLoadFailed(
        modelId,
        result.errorMessage.isNotEmpty
            ? result.errorMessage
            : 'VAD lifecycle load failed',
      );
    }
    _logger.info('VAD model loaded: $modelId');
  }

  /// Unload the currently-loaded VAD model through commons lifecycle routing.
  Future<void> unloadModel() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final modelId = currentModelId ??
        (await RunAnywhereModelLifecycle.shared.current(
          model_pb.CurrentModelRequest(category: _vadCategory),
        ))
            .modelId;
    if (modelId.isEmpty) return;

    final result = await RunAnywhereModelLifecycle.shared.unload(
      model_pb.ModelUnloadRequest(
        modelId: modelId,
        category: _vadCategory,
      ),
    );
    if (!result.success) {
      throw SDKException.invalidState(
        result.errorMessage.isNotEmpty
            ? result.errorMessage
            : 'VAD lifecycle unload failed',
      );
    }
  }


  Future<VADResult> _processAudioData(
    Uint8List audio,
    VADOptions options,
    VADAudioEncoding encoding,
  ) async {
    final modelId = await _requireLoadedModelId();
    final request = VADProcessRequest(
      audio: VADAudioSource(
        audioData: audio,
        encoding: encoding,
        sampleRate: 16000,
        channels: 1,
      ),
      options: options,
      metadata: <String, String>{'model_id': modelId}.entries,
    );
    return DartBridgeVAD.shared.processLifecycleProto(request);
  }

  Future<String> _requireLoadedModelId() async {
    final snapshotModelId = currentModelId;
    if (snapshotModelId != null) {
      return snapshotModelId;
    }
    final current = await RunAnywhereModelLifecycle.shared.current(
      model_pb.CurrentModelRequest(category: _vadCategory),
    );
    if (current.found && current.modelId.isNotEmpty) {
      return current.modelId;
    }
    throw SDKException.componentNotReady(
      'No VAD model loaded through commons lifecycle. Call loadVADModel() first.',
    );
  }

  ComponentLifecycleSnapshot? get _lifecycleSnapshot =>
      RunAnywhereModelLifecycle.shared.componentSnapshot(
        SDKComponent.SDK_COMPONENT_VAD,
      );

  static const _vadCategory =
      model_pb.ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;
}
