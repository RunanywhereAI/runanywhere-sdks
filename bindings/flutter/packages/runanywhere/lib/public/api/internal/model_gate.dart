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
import 'package:runanywhere/public/api/types/options.dart' show LoadOptions;
import 'package:runanywhere/public/capabilities/runanywhere_downloads.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';

final SDKLogger _modelGateLogger = SDKLogger('ModelGate');

/// [LoadOptions] fields `ModelLoadRequest` (`model_types.proto`) has no wire
/// path for yet. Only `framework` reaches commons at load time;
/// `contextLength`, `threads`, and `useGpu` are accepted for cross-SDK API
/// parity but are dropped below this call until the native load ABI grows
/// placement fields (tracked as a follow-up — see PR #605 review follow-up
/// issue 8).
///
/// Exposed (not private) so `model_gate_test.dart` can assert on it directly
/// without driving the full native load path.
List<String> ignoredLoadOptionKnobs(LoadOptions? options) => <String>[
  if (options?.contextLength != null) 'contextLength',
  if (options?.threads != null) 'threads',
  if (options?.useGpu != null) 'useGpu',
];

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
    final framework = options?.framework;
    if (framework != null) {
      request.framework = framework;
    }
    final ignored = ignoredLoadOptionKnobs(options);
    if (ignored.isNotEmpty) {
      _modelGateLogger.warning(
        'LoadOptions ${ignored.join(", ")} are not carried by the commons load ABI yet',
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
