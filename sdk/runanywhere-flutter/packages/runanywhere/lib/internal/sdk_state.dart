// SPDX-License-Identifier: Apache-2.0
//
// sdk_state.dart — package-internal mutable lifecycle state for the
// v4 SDK. Shared by `RunAnywhereSDK` (lifecycle) and every capability
// class under `lib/public/capabilities/`. NOT exported from the
// public barrel (`lib/runanywhere.dart`) — consumers that reach into
// this are explicitly opting out of the public API contract.
//
// Phase C of the v2 close-out moved this state off the static
// `RunAnywhere` god-class. One singleton, one source of truth.

import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/public/configuration/sdk_environment.dart';

/// Package-internal SDK lifecycle state.
///
/// Single mutable singleton shared across the lifecycle entry point
/// and every capability class. Do NOT import outside the package.
class SdkState {
  SdkState._();

  /// Shared instance.
  static final SdkState shared = SdkState._();

  /// True after [initialize] succeeds.
  bool isInitialized = false;

  /// Whether lazy one-shot discovery has run yet.
  bool hasRunDiscovery = false;

  /// Arguments passed to the last successful `initialize`.
  SDKInitParams? initParams;

  /// Active SDK environment (development / staging / production).
  SDKEnvironment? currentEnvironment;

  /// Models registered by the app at startup (pre-download).
  final List<ModelInfo> registeredModels = [];

  /// Reset all state. Used by `RunAnywhereSDK.reset()` and tests.
  void reset() {
    isInitialized = false;
    hasRunDiscovery = false;
    initParams = null;
    currentEnvironment = null;
    registeredModels.clear();
  }
}
