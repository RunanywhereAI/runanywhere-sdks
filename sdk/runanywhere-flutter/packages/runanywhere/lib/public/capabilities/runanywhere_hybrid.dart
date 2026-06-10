// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_hybrid.dart — Hybrid STT router capability surface. Mirrors the
// Kotlin `RACRouter` static entry points (RACRouter.stt.init,
// RACRouter.setDeviceStateProvider, BACKEND.CLOUD) and the Swift HybridSTTRouter
// / CloudSTT / HybridDeviceState statics, exposed under `RunAnywhere.hybrid`.
//
// THIN — all routing logic is in commons. This capability only vends the
// router factory, the cloud-backend registry, the device-state installer, and
// cloud plugin registration. FFI lives in
// `lib/native/dart_bridge_hybrid_stt.dart`.

import 'package:runanywhere/native/dart_bridge_hybrid_stt.dart';
import 'package:runanywhere/public/hybrid/hybrid_cloud_backend.dart';
import 'package:runanywhere/public/hybrid/hybrid_device_state.dart';
import 'package:runanywhere/public/hybrid/hybrid_stt_router.dart';

/// Hybrid router capability surface (per-request offline ↔ cloud dispatch).
///
/// Access via `RunAnywhere.hybrid`. Only STT is wired today (offline sherpa ↔
/// cloud, e.g. the Sarvam provider).
class RunAnywhereHybrid {
  RunAnywhereHybrid._();

  static final RunAnywhereHybrid _instance = RunAnywhereHybrid._();

  /// Shared instance backing `RunAnywhere.hybrid`.
  static RunAnywhereHybrid get shared => _instance;

  /// The cloud-STT backend registry (provider-as-data credential/model table +
  /// cloud plugin registration). See [CloudBackend].
  CloudBackend get cloud => CloudBackend.instance;

  /// Register the cloud engine with the commons plugin registry so it is
  /// routable for the online side. Idempotent; called implicitly by
  /// `cloud.register(...)`, exposed here for callers that register the plugin
  /// before any model entry. Returns true when the plugin is (or became)
  /// registered; false when the native symbol is unavailable in this build.
  bool registerCloud() => CloudBackend.instance.ensurePluginRegistered();

  /// Unregister the cloud engine from the commons registry.
  void unregisterCloud() => DartBridgeHybridStt.instance.unregisterCloud();

  /// Register the host device-state provider so the router's NETWORK / Battery
  /// filters see live values on every request. Pass `null` to unregister and
  /// fall back to the commons optimistic default. Mirrors Kotlin
  /// `RACRouter.setDeviceStateProvider`.
  bool setDeviceStateProvider(HybridDeviceStateProvider? provider) =>
      HybridDeviceState.instance.setProvider(provider);

  /// Create a fresh STT hybrid router. Caller owns it and MUST call
  /// [HybridSttRouter.close] when done. Mirrors Kotlin `RACRouter.stt.init(...)`
  /// / Swift `HybridSTTRouter()`.
  HybridSttRouter createSttRouter() => HybridSttRouter.create();
}
