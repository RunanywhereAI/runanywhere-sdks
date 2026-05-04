// SPDX-License-Identifier: Apache-2.0
//
// Proto-backed model/component lifecycle public API.

import 'package:runanywhere/generated/model_types.pb.dart'
    show
        CurrentModelRequest,
        CurrentModelResult,
        ModelLoadRequest,
        ModelLoadResult,
        ModelUnloadRequest,
        ModelUnloadResult;
import 'package:runanywhere/generated/sdk_events.pb.dart'
    show ComponentLifecycleSnapshot;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';

/// Canonical generated-proto model/component lifecycle surface.
///
/// Calls the commons `rac_model_lifecycle_*_proto` ABI. Request/result/snapshot
/// types are generated from IDL; Flutter does not keep a parallel lifecycle DTO.
class RunAnywhereModelLifecycle {
  RunAnywhereModelLifecycle._();
  static final RunAnywhereModelLifecycle _instance =
      RunAnywhereModelLifecycle._();
  static RunAnywhereModelLifecycle get shared => _instance;

  /// Load a model through commons lifecycle routing.
  Future<ModelLoadResult> load(ModelLoadRequest request) {
    if (!SdkState.shared.isInitialized) {
      return Future.value(ModelLoadResult(
        success: false,
        modelId: request.modelId,
        category: request.category,
        framework: request.framework,
        errorMessage: 'SDK not initialized',
      ));
    }
    return DartBridge.modelLifecycle.load(request);
  }

  /// Unload model(s) through commons lifecycle routing.
  Future<ModelUnloadResult> unload(ModelUnloadRequest request) {
    if (!SdkState.shared.isInitialized) {
      return Future.value(ModelUnloadResult(
        success: false,
        errorMessage: 'SDK not initialized',
      ));
    }
    return DartBridge.modelLifecycle.unload(request);
  }

  /// Query the current loaded model matching the optional category/framework.
  Future<CurrentModelResult> current([CurrentModelRequest? request]) {
    if (!SdkState.shared.isInitialized) {
      return Future.value(CurrentModelResult());
    }
    return DartBridge.modelLifecycle.current(request ?? CurrentModelRequest());
  }

  /// Snapshot the live lifecycle state for a model-backed component.
  ComponentLifecycleSnapshot? componentSnapshot(SDKComponent component) {
    if (!SdkState.shared.isInitialized) return null;
    return DartBridge.modelLifecycle.componentSnapshot(component);
  }

  /// Reset commons lifecycle state. Primarily useful for tests.
  void reset() => DartBridge.modelLifecycle.reset();
}
