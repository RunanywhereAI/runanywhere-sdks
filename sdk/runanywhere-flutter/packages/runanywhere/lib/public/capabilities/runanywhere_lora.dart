// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_lora.dart — LoRA capability surface (canonical §3 namespace).
// Mirrors Swift `RunAnywhere.LoRA` and Kotlin `RunAnywhere.lora` (G-A7).
//
// Canonical runtime and catalog surface:
//   apply / remove / list / state / checkCompatibility /
//   register / listCatalog / queryCatalog / getCatalogEntry /
//   markDownloadCompleted / adaptersForModel / allRegistered

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/lora_options.pb.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_lora.dart';

/// LoRA (Low-Rank Adaptation) capability surface.
///
/// Access via `RunAnywhere.lora`. Mirrors Swift
/// `RunAnywhere.LoRA` and Kotlin `RunAnywhere.lora`.
class RunAnywhereLoRACapability {
  RunAnywhereLoRACapability._();
  static final RunAnywhereLoRACapability _instance =
      RunAnywhereLoRACapability._();
  static RunAnywhereLoRACapability get shared => _instance;

  // --- Runtime adapter operations ----------------------------------------

  /// Apply one or more LoRA adapters to the current model.
  Future<LoRAApplyResult> apply(LoRAApplyRequest request) async {
    return DartBridgeLora.shared.apply(request);
  }

  /// Remove one or more LoRA adapters, or clear all adapters.
  Future<LoRAState> remove(LoRARemoveRequest request) async {
    return DartBridgeLora.shared.remove(request);
  }

  /// Currently loaded LoRA adapters.
  Future<LoRAState> list() async {
    return DartBridgeLora.shared.list();
  }

  /// LoRA service state reported by commons.
  Future<LoRAState> state() async {
    return DartBridgeLora.shared.state();
  }

  /// Whether the current backend supports the given adapter.
  Future<LoraCompatibilityResult> checkCompatibility(
    LoRAAdapterConfig config,
  ) async {
    return DartBridgeLora.shared.checkCompatibility(config);
  }

  // --- Catalog operations -----------------------------------------------

  /// Register a LoRA adapter in the global registry. Entry is
  /// deep-copied internally by C++.
  Future<LoraAdapterCatalogEntry> register(
    LoraAdapterCatalogEntry entry,
  ) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.register(entry);
  }

  /// Generated-proto LoRA catalog list surface.
  Future<LoraAdapterCatalogListResult> listCatalog([
    LoraAdapterCatalogListRequest? request,
  ]) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.listCatalog(
      request ?? LoraAdapterCatalogListRequest(),
    );
  }

  /// Generated-proto LoRA catalog query surface.
  Future<LoraAdapterCatalogListResult> queryCatalog(
    LoraAdapterCatalogQuery query,
  ) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.queryCatalog(query);
  }

  /// Generated-proto LoRA catalog get surface.
  Future<LoraAdapterCatalogGetResult> getCatalogEntry(
    LoraAdapterCatalogGetRequest request,
  ) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.getCatalogEntry(request);
  }

  /// Record native-owned download/import completion in the commons LoRA catalog.
  Future<LoraAdapterDownloadCompletedResult> markDownloadCompleted(
    LoraAdapterDownloadCompletedRequest request,
  ) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.markDownloadCompleted(request);
  }

  /// Record native-reported LoRA adapter import completion in commons.
  ///
  /// Mirrors Swift `RunAnywhere.lora.markImportCompleted(_:)`. Uses the
  /// generated download-completed message with `imported = true`, matching the
  /// IDL contract for platform file-picker/import completion.
  Future<LoraAdapterDownloadCompletedResult> markImportCompleted(
    LoraAdapterDownloadCompletedRequest request,
  ) async {
    final importRequest = request.deepCopy()..imported = true;
    if (importRequest.statusMessage.isEmpty) {
      importRequest.statusMessage = 'import completed';
    }
    return markDownloadCompleted(importRequest);
  }

  /// All registered LoRA adapters compatible with [modelId].
  Future<List<LoraAdapterCatalogEntry>> adaptersForModel(String modelId) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.getForModel(modelId);
  }

  /// All registered LoRA adapters.
  Future<List<LoraAdapterCatalogEntry>> allRegistered() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeLoraRegistry.shared.getAll();
  }
}
