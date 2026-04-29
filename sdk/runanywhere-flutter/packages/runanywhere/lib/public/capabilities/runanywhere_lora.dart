// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_lora.dart — LoRA capability surface (canonical §3 namespace).
// Mirrors Swift `RunAnywhere.LoRA` and Kotlin `RunAnywhere.lora` (G-A7).
//
// Eight-method spec required by canonical API:
//   load / remove / clear / getLoaded / checkCompatibility /
//   register / adaptersForModel / allRegistered

import 'package:fixnum/fixnum.dart';

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/generated/lora_options.pb.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge_lora.dart';

/// LoRA (Low-Rank Adaptation) capability surface.
///
/// Access via `RunAnywhereSDK.instance.lora`. Mirrors Swift
/// `RunAnywhere.LoRA` and Kotlin `RunAnywhere.lora`.
class RunAnywhereLoRACapability {
  RunAnywhereLoRACapability._();
  static final RunAnywhereLoRACapability _instance =
      RunAnywhereLoRACapability._();
  static RunAnywhereLoRACapability get shared => _instance;

  // --- Runtime adapter operations ----------------------------------------

  /// Load and apply a LoRA adapter to the current model. Context is
  /// recreated internally and the KV cache is cleared.
  Future<LoRAAdapterInfo> load(LoRAAdapterConfig config) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    DartBridgeLora.shared.loadAdapter(config.adapterPath, config.scale);
    return LoRAAdapterInfo(
      adapterPath: config.adapterPath,
      scale: config.scale,
      applied: true,
    );
  }

  /// Remove a specific LoRA adapter by id (path).
  Future<void> remove(String adapterId) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    DartBridgeLora.shared.removeAdapter(adapterId);
  }

  /// Remove all LoRA adapters.
  Future<void> clear() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    DartBridgeLora.shared.clearAdapters();
  }

  /// Currently-loaded LoRA adapters; empty when none.
  Future<List<LoRAAdapterInfo>> getLoaded() async {
    if (!SdkState.shared.isInitialized) return const [];
    return DartBridgeLora.shared.getLoadedAdapters();
  }

  /// Whether the current backend supports the given adapter for [modelId].
  Future<LoRACompatibilityResult> checkCompatibility(
    String adapterId,
    String modelId,
  ) async {
    if (!SdkState.shared.isInitialized) {
      return const LoRACompatibilityResult(
        isCompatible: false,
        errorMessage: 'SDK not initialized',
      );
    }
    final raw = DartBridgeLora.shared.checkCompatibility(adapterId);
    return LoRACompatibilityResult(
      isCompatible: raw.isCompatible,
      errorMessage: raw.errorMessage,
    );
  }

  // --- Catalog operations -----------------------------------------------

  /// Register a LoRA adapter in the global registry. Entry is
  /// deep-copied internally by C++.
  Future<void> register(LoRAAdapterConfig config) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    DartBridgeLoraRegistry.shared.register(
      LoraAdapterCatalogEntry(
        id: config.adapterPath,
        name: config.adapterPath,
        description: '',
        url: '',
        filename: config.adapterPath,
        compatibleModels: const <String>[],
        sizeBytes: Int64.ZERO,
      ),
    );
  }

  /// All registered LoRA adapters compatible with [modelId].
  Future<List<LoRAAdapterInfo>> adaptersForModel(String modelId) async {
    if (!SdkState.shared.isInitialized) return const [];
    final entries = DartBridgeLoraRegistry.shared.getForModel(modelId);
    return entries
        .map((e) => LoRAAdapterInfo(
              adapterPath: e.filename.isNotEmpty ? e.filename : e.id,
              scale: 1.0,
              applied: false,
            ))
        .toList();
  }

  /// All registered LoRA adapters.
  Future<List<LoRAAdapterInfo>> allRegistered() async {
    if (!SdkState.shared.isInitialized) return const [];
    final entries = DartBridgeLoraRegistry.shared.getAll();
    return entries
        .map((e) => LoRAAdapterInfo(
              adapterPath: e.filename.isNotEmpty ? e.filename : e.id,
              scale: 1.0,
              applied: false,
            ))
        .toList();
  }
}

/// Compatibility result re-exported alongside proto types.
class LoRACompatibilityResult {
  final bool isCompatible;
  final String errorMessage;
  const LoRACompatibilityResult({
    required this.isCompatible,
    this.errorMessage = '',
  });
}
