// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_lora.dart — LoRA (Low-Rank Adaptation) adapter helpers.
// Mirrors Swift `RunAnywhere+LoRA.swift` and Kotlin `RunAnywhere+LoRA.kt`.

import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge_lora.dart';
import 'package:runanywhere/generated/lora_options.pb.dart';

/// Static helpers for managing LoRA adapters.
///
/// Usage:
/// ```dart
/// RunAnywhereLoRA.loadLoraAdapter(
///   LoRAAdapterConfig(path: '/path/to/adapter.gguf'),
/// );
/// final adapters = RunAnywhereLoRA.getLoadedLoraAdapters();
/// RunAnywhereLoRA.clearLoraAdapters();
/// ```
class RunAnywhereLoRA {
  RunAnywhereLoRA._();

  // -- Runtime operations ---------------------------------------------------

  /// Load and apply a LoRA adapter to the current model. Context is
  /// recreated internally and the KV cache is cleared.
  static void loadLoraAdapter(LoRAAdapterConfig config) {
    if (!SdkState.shared.isInitialized) {
      throw StateError('SDK not initialized');
    }
    DartBridgeLora.shared.loadAdapter(config.adapterPath, config.scale);
  }

  /// Remove a specific LoRA adapter by path.
  static void removeLoraAdapter(String path) {
    if (!SdkState.shared.isInitialized) {
      throw StateError('SDK not initialized');
    }
    DartBridgeLora.shared.removeAdapter(path);
  }

  /// Remove all LoRA adapters.
  static void clearLoraAdapters() {
    if (!SdkState.shared.isInitialized) {
      throw StateError('SDK not initialized');
    }
    DartBridgeLora.shared.clearAdapters();
  }

  /// Info on currently-loaded LoRA adapters; empty if none loaded.
  static List<LoRAAdapterInfo> getLoadedLoraAdapters() {
    if (!SdkState.shared.isInitialized) return [];
    return DartBridgeLora.shared.getLoadedAdapters();
  }

  /// Whether the current backend supports the given LoRA adapter.
  static LoraCompatibilityResult checkLoraCompatibility(String loraPath) {
    if (!SdkState.shared.isInitialized) {
      return LoraCompatibilityResult(
        isCompatible: false,
        errorMessage: 'SDK not initialized',
      );
    }
    return DartBridgeLora.shared.checkCompatibility(loraPath);
  }

  // -- Catalog operations ---------------------------------------------------

  /// Register a LoRA adapter in the global registry. Entry is
  /// deep-copied internally by C++.
  static void registerLoraAdapter(LoraAdapterCatalogEntry entry) {
    if (!SdkState.shared.isInitialized) {
      throw StateError('SDK not initialized');
    }
    DartBridgeLoraRegistry.shared.register(entry);
  }

  /// All registered LoRA adapters compatible with a specific model.
  static List<LoraAdapterCatalogEntry> loraAdaptersForModel(String modelId) {
    if (!SdkState.shared.isInitialized) return [];
    return DartBridgeLoraRegistry.shared.getForModel(modelId);
  }

  /// All registered LoRA adapters.
  static List<LoraAdapterCatalogEntry> allRegisteredLoraAdapters() {
    if (!SdkState.shared.isInitialized) return [];
    return DartBridgeLoraRegistry.shared.getAll();
  }
}
