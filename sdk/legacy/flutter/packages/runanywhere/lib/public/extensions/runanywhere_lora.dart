/// RunAnywhere + LoRA
///
/// Public API for LoRA (Low-Rank Adaptation) adapter operations.
/// Mirrors Swift's RunAnywhere+LoRA.swift and Kotlin's RunAnywhere+LoRA.kt.
///
/// Provides:
/// - Runtime operations: load, remove, clear, query adapters
/// - Catalog operations: register, query adapter metadata
/// - Compatibility checking
library runanywhere_lora;

import 'package:runanywhere/native/dart_bridge_lora.dart';
import 'package:runanywhere/public/runanywhere.dart';
import 'package:runanywhere/public/types/lora_types.dart';

/// Extension providing static LoRA methods on RunAnywhere.
///
/// Usage:
/// ```dart
/// // Load a LoRA adapter
/// RunAnywhereLoRA.loadLoraAdapter(LoRAAdapterConfig(path: '/path/to/adapter.gguf'));
///
/// // Check loaded adapters
/// final adapters = RunAnywhereLoRA.getLoadedLoraAdapters();
///
/// // Remove all adapters
/// RunAnywhereLoRA.clearLoraAdapters();
/// ```
extension RunAnywhereLoRA on RunAnywhere {
  // MARK: - Runtime Operations

  /// Load and apply a LoRA adapter to the current model.
  ///
  /// Context is recreated internally and KV cache is cleared.
  /// Throws if SDK not initialized or load fails.
  static void loadLoraAdapter(LoRAAdapterConfig config) {
    if (!RunAnywhere.isSDKInitialized) {
      throw StateError('SDK not initialized');
    }
    DartBridgeLora.shared.loadAdapter(config.path, config.scale);
  }

  /// Remove a specific LoRA adapter by path.
  ///
  /// Throws if SDK not initialized or adapter not found.
  static void removeLoraAdapter(String path) {
    if (!RunAnywhere.isSDKInitialized) {
      throw StateError('SDK not initialized');
    }
    DartBridgeLora.shared.removeAdapter(path);
  }

  /// Remove all LoRA adapters.
  ///
  /// Throws if SDK not initialized.
  static void clearLoraAdapters() {
    if (!RunAnywhere.isSDKInitialized) {
      throw StateError('SDK not initialized');
    }
    DartBridgeLora.shared.clearAdapters();
  }

  /// Get info about currently loaded LoRA adapters.
  ///
  /// Returns empty list if SDK not initialized or no adapters loaded.
  static List<LoRAAdapterInfo> getLoadedLoraAdapters() {
    if (!RunAnywhere.isSDKInitialized) return [];
    return DartBridgeLora.shared.getLoadedAdapters();
  }

  /// Check if the current backend supports LoRA for the given adapter path.
  static LoraCompatibilityResult checkLoraCompatibility(String loraPath) {
    if (!RunAnywhere.isSDKInitialized) {
      return const LoraCompatibilityResult(
        isCompatible: false,
        error: 'SDK not initialized',
      );
    }
    return DartBridgeLora.shared.checkCompatibility(loraPath);
  }

  // MARK: - Catalog Operations

  /// Register a LoRA adapter in the global registry.
  ///
  /// Entry is deep-copied internally by C++.
  /// Throws if SDK not initialized or registration fails.
  static void registerLoraAdapter(LoraAdapterCatalogEntry entry) {
    if (!RunAnywhere.isSDKInitialized) {
      throw StateError('SDK not initialized');
    }
    DartBridgeLoraRegistry.shared.register(entry);
  }

  /// Get all registered LoRA adapters compatible with a model.
  static List<LoraAdapterCatalogEntry> loraAdaptersForModel(String modelId) {
    if (!RunAnywhere.isSDKInitialized) return [];
    return DartBridgeLoraRegistry.shared.getForModel(modelId);
  }

  /// Get all registered LoRA adapters.
  static List<LoraAdapterCatalogEntry> allRegisteredLoraAdapters() {
    if (!RunAnywhere.isSDKInitialized) return [];
    return DartBridgeLoraRegistry.shared.getAll();
  }
}
