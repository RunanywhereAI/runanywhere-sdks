// SPDX-License-Identifier: Apache-2.0
//
// sdk_state.dart — package-internal Dart-side flags that do not belong
// in the C++ commons state.
//
// FLT-SDK-INIT-MOVE: trimmed to a single one-shot discovery flag. The
// canonical SDK state (initialized / environment / params / registered
// models) lives in commons (`rac_state_*` / `rac_sdk_*`). Dart reads
// it through `DartBridge`/`DartBridgeState` and does NOT mirror it.

/// Tiny package-internal Dart cache flags.
///
/// Anything cross-platform (initialization, environment, params) lives
/// in commons; Dart reads it through the bridges. Only Dart-only
/// scheduling flags belong here.
class SdkState {
  SdkState._();

  /// Shared instance.
  static final SdkState shared = SdkState._();

  /// Whether the lazy filesystem discovery pass has run yet. Used by
  /// `RunAnywhereModels.available()` to gate the one-shot rescan after
  /// the app has had a chance to register its models.
  bool hasRunDiscovery = false;

  /// Reset all Dart-side flags. Called from `RunAnywhereSDK.reset()`
  /// and tests.
  void reset() {
    hasRunDiscovery = false;
  }
}
