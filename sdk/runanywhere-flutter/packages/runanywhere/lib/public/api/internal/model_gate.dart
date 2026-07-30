// SPDX-License-Identifier: Apache-2.0
//
// Shared auto-load gate. Generation verbs call this so a caller never has to
// download or load a model by hand: naming a model in the options is enough.

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
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
    // ModelLoadRequest carries no context/thread/GPU fields (model_types.proto);
    // those LoadOptions knobs have no commons load-time path yet.
    final result = await RunAnywhereModelLifecycle.shared.load(request);
    if (!result.success) {
      throw SDKException.modelLoadFailed(
        modelId,
        result.errorMessage.isNotEmpty
            ? result.errorMessage
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
    if (!result.success) {
      throw SDKException.invalidState(
        result.errorMessage.isNotEmpty
            ? result.errorMessage
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
    final present = info.hasIsDownloaded()
        ? info.isDownloaded
        : info.localPath.isNotEmpty;
    if (present) return;

    await for (final progress in RunAnywhereDownloads.shared.start(modelId)) {
      if (progress.state == DownloadState.DOWNLOAD_STATE_FAILED) {
        throw SDKException.downloadFailed(
          modelId,
          progress.errorMessage.isEmpty ? null : progress.errorMessage,
        );
      }
      if (progress.state == DownloadState.DOWNLOAD_STATE_CANCELLED) {
        throw SDKException.cancelled('Download cancelled for $modelId');
      }
    }
  }
}
