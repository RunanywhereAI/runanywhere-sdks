// SPDX-License-Identifier: Apache-2.0
//
// Shared auto-load gate. Generation verbs call this so a caller never has to
// download or load a model by hand: naming a model in the options is enough.

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/download_service.pb.dart'
    show DownloadState;
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show ModelCategory;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/public/api/types/options.dart'
    show AcceleratorPolicy, LoadOptions;
import 'package:runanywhere/public/capabilities/runanywhere_downloads.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';

final SDKLogger _modelGateLogger = SDKLogger('ModelGate');

/// [LoadOptions] fields `ModelLoadRequest` (`model_types.proto`) has no wire
/// path for yet. `threads` was retired from the load ABI (reserved tag 7);
/// every other placement knob — `contextLength`, `accelerator`/`useGpu`, and
/// `backendPreferences`/`framework` — is carried by the request in [load].
///
/// Exposed (not private) so `model_gate_load_options_test.dart` can assert on
/// it directly without driving the full native load path.
List<String> ignoredLoadOptionKnobs(LoadOptions? options) => <String>[
  if (options?.threads != null) 'threads',
];

/// Map the public [AcceleratorPolicy] enum onto the generated
/// `ModelLoadRequest.accelerator_policy` values.
model_pb.AcceleratorPolicy _toPbAccelerator(AcceleratorPolicy policy) {
  switch (policy) {
    case AcceleratorPolicy.auto:
      return model_pb.AcceleratorPolicy.ACCELERATOR_POLICY_AUTO;
    case AcceleratorPolicy.cpu:
      return model_pb.AcceleratorPolicy.ACCELERATOR_POLICY_CPU;
    case AcceleratorPolicy.gpu:
      return model_pb.AcceleratorPolicy.ACCELERATOR_POLICY_GPU;
    case AcceleratorPolicy.npu:
      return model_pb.AcceleratorPolicy.ACCELERATOR_POLICY_NPU;
  }
}

/// Auto-load coordinator shared by every generation verb.
abstract final class ModelGate {
  /// Make [modelId] resident under [category], downloading it when absent.
  ///
  /// A null [modelId] leaves whatever is already loaded in place; commons
  /// surfaces a structured error if nothing is.
  ///
  /// Throws [SDKException] when the model is unknown, cannot be fetched, or
  /// fails to load.
  static Future<void> ensureLoaded({
    required String? modelId,
    required ModelCategory category,
    LoadOptions? options,
    bool downloadIfNeeded = true,
  }) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    if (modelId == null || modelId.isEmpty) {
      return;
    }
    await DartBridge.ensureServicesReady();

    final current = await RunAnywhereModelLifecycle.shared.current(
      model_pb.CurrentModelRequest(category: category),
    );
    if (current.found && current.modelId == modelId) {
      return;
    }

    if (downloadIfNeeded) {
      await _downloadIfAbsent(modelId);
    }
    await load(modelId: modelId, category: category, options: options);
  }

  /// Load [modelId] under [category] through commons lifecycle routing.
  ///
  /// Throws [SDKException] when the load fails.
  static Future<void> load({
    required String modelId,
    required ModelCategory category,
    LoadOptions? options,
  }) async {
    final request = model_pb.ModelLoadRequest(
      modelId: modelId,
      category: category,
      forceReload: true,
      validateAvailability: true,
    );
    final opts = options;
    if (opts != null) {
      final contextLength = opts.contextLength;
      if (contextLength != null) {
        request.contextLength = contextLength;
      }
      final accelerator = opts.resolvedAccelerator;
      if (accelerator != null) {
        request.acceleratorPolicy = _toPbAccelerator(accelerator);
      }
      final preferences = opts.resolvedBackendPreferences;
      if (preferences.isNotEmpty) {
        // Keep the single-pin compatibility field aligned with the ranked list
        // so callers that only read `request.framework` still see the winner.
        request.framework = preferences.first.backend;
        request.backendPreferences
            .addAll(preferences.map((preference) => preference.backend));
      }
    }
    final ignored = ignoredLoadOptionKnobs(options);
    if (ignored.isNotEmpty) {
      _modelGateLogger.warning(
        'LoadOptions ${ignored.join(", ")} is not carried by the commons load '
        'ABI (retired at ModelLoadRequest reserved tag 7)',
      );
    }
    final result = await RunAnywhereModelLifecycle.shared.load(request);
    if (result.hasError()) {
      throw SDKException.modelLoadFailed(
        modelId,
        result.error.message.isNotEmpty
            ? result.error.message
            : 'Model lifecycle load failed',
      );
    }
  }

  /// Unload whatever is loaded under [category]. No-op when nothing is.
  ///
  /// Throws [SDKException] when the unload fails.
  static Future<void> unload(ModelCategory category) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final current = await RunAnywhereModelLifecycle.shared.current(
      model_pb.CurrentModelRequest(category: category),
    );
    if (!current.found || current.modelId.isEmpty) {
      return;
    }
    final result = await RunAnywhereModelLifecycle.shared.unload(
      model_pb.ModelUnloadRequest(
        modelId: current.modelId,
        category: category,
      ),
    );
    if (result.hasError()) {
      throw SDKException.invalidState(
        result.error.message.isNotEmpty
            ? result.error.message
            : 'Model lifecycle unload failed',
      );
    }
  }

  /// Model id currently loaded under [category], or null.
  static Future<String?> currentId(ModelCategory category) async {
    if (!DartBridge.isInitialized) return null;
    final current = await RunAnywhereModelLifecycle.shared.current(
      model_pb.CurrentModelRequest(category: category),
    );
    if (!current.found || current.modelId.isEmpty) return null;
    return current.modelId;
  }

  static Future<void> _downloadIfAbsent(String modelId) async {
    final model = await RunAnywhereModels.shared.getModel(
      model_pb.ModelGetRequest(modelId: modelId),
    );
    if (!model.found) {
      throw SDKException.modelNotFound(modelId);
    }
    final info = model.model;
    final present = info.localPath.isNotEmpty;
    if (present) return;

    await for (final progress in RunAnywhereDownloads.shared.start(modelId)) {
      if (progress.state == DownloadState.DOWNLOAD_STATE_FAILED) {
        throw SDKException.downloadFailed(
          modelId,
          progress.hasError() ? progress.error.message : null,
        );
      }
      if (progress.state == DownloadState.DOWNLOAD_STATE_CANCELLED) {
        throw SDKException.cancelled('Download cancelled for $modelId');
      }
    }
  }
}
