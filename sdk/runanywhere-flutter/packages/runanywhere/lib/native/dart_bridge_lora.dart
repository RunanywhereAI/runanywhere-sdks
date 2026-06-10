/// DartBridge+LoRA
///
/// LoRA adapter bridge - manages C++ LoRA operations via FFI.
/// Mirrors Swift's CppBridge+LLM.swift LoRA section and
/// CppBridge+LoraRegistry.swift.
///
/// Two classes:
/// - [DartBridgeLora] - Runtime LoRA operations (apply/remove/list/state)
/// - [DartBridgeLoraRegistry] - Catalog registry (register/query adapters)
library;

import 'dart:ffi';

import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/lora_options.pb.dart';
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';

// =============================================================================
// LoRA Runtime Operations (via LLM Component)
// =============================================================================

/// LoRA adapter bridge for runtime operations.
///
/// The lifecycle-aware C ABI resolves the active LLM component internally;
/// callers no longer thread an LLM component handle through these calls.
/// Matches Swift CppBridge.LLM LoRA methods.
class DartBridgeLora {
  // MARK: - Singleton

  static final DartBridgeLora shared = DartBridgeLora._();

  DartBridgeLora._();

  final _logger = SDKLogger('DartBridge.LoRA');

  // MARK: - LoRA Adapter Management

  /// Apply one or more LoRA adapters to the current model.
  LoRAApplyResult apply(LoRAApplyRequest request) {
    final fn = RacNative.bindings.rac_lora_apply_proto;
    if (fn == null) {
      throw UnsupportedError('rac_lora_apply_proto is unavailable');
    }
    final result = DartBridgeProtoUtils.callRequest<LoRAApplyResult>(
      request: request,
      invoke: fn,
      decode: LoRAApplyResult.fromBuffer,
      symbol: 'rac_lora_apply_proto',
    );
    _logger.info('LoRA apply completed: ${result.adapters.length} adapters');
    return result;
  }

  /// Remove one or more LoRA adapters, or clear all adapters.
  LoRAState remove(LoRARemoveRequest request) {
    final fn = RacNative.bindings.rac_lora_remove_proto;
    if (fn == null) {
      throw UnsupportedError('rac_lora_remove_proto is unavailable');
    }
    final result = DartBridgeProtoUtils.callRequest<LoRAState>(
      request: request,
      invoke: fn,
      decode: LoRAState.fromBuffer,
      symbol: 'rac_lora_remove_proto',
    );
    _logger.info('LoRA remove completed');
    return result;
  }

  /// Get info about all currently loaded LoRA adapters.
  LoRAState list([LoRAState? request]) {
    final fn = RacNative.bindings.rac_lora_list_proto;
    if (fn == null) {
      throw UnsupportedError('rac_lora_list_proto is unavailable');
    }
    return DartBridgeProtoUtils.callRequest<LoRAState>(
      request: request ?? LoRAState(),
      invoke: fn,
      decode: LoRAState.fromBuffer,
      symbol: 'rac_lora_list_proto',
    );
  }

  /// Get the LoRA service state reported by commons.
  LoRAState state([LoRAState? request]) {
    final fn = RacNative.bindings.rac_lora_state_proto;
    if (fn == null) {
      throw UnsupportedError('rac_lora_state_proto is unavailable');
    }
    return DartBridgeProtoUtils.callRequest<LoRAState>(
      request: request ?? LoRAState(),
      invoke: fn,
      decode: LoRAState.fromBuffer,
      symbol: 'rac_lora_state_proto',
    );
  }

  /// Check if the current backend supports a LoRA adapter.
  LoraCompatibilityResult checkCompatibility(LoRAAdapterConfig config) {
    final fn = RacNative.bindings.rac_lora_compatibility_proto;
    if (fn == null) {
      throw UnsupportedError('rac_lora_compatibility_proto is unavailable');
    }
    return DartBridgeProtoUtils.callRequest<LoraCompatibilityResult>(
      request: config,
      invoke: fn,
      decode: LoraCompatibilityResult.fromBuffer,
      symbol: 'rac_lora_compatibility_proto',
    );
  }
}

// =============================================================================
// LoRA Registry (Catalog Operations)
// =============================================================================

/// LoRA adapter registry bridge for catalog operations.
///
/// Uses the global C++ registry singleton via proto registration and native
/// catalog queries.
/// Matches Swift CppBridge.LoraRegistry.
class DartBridgeLoraRegistry {
  // MARK: - Singleton

  static final DartBridgeLoraRegistry shared = DartBridgeLoraRegistry._();

  DartBridgeLoraRegistry._();

  final _logger = SDKLogger('DartBridge.LoRA.Registry');
  static LoraAdapterCatalogEntry Function(LoraAdapterCatalogEntry)?
      _registerForTesting;
  static LoraAdapterCatalogListResult Function(
    LoraAdapterCatalogListRequest,
  )? _listCatalogForTesting;
  static LoraAdapterCatalogListResult Function(
    LoraAdapterCatalogQuery,
  )? _queryCatalogForTesting;
  static LoraAdapterCatalogGetResult Function(
    LoraAdapterCatalogGetRequest,
  )? _getCatalogEntryForTesting;
  static LoraAdapterDownloadCompletedResult Function(
    LoraAdapterDownloadCompletedRequest,
  )? _markDownloadCompletedForTesting;

  static void setRegisterProtoForTesting(
    LoraAdapterCatalogEntry Function(LoraAdapterCatalogEntry)? override,
  ) {
    _registerForTesting = override;
  }

  static void setListCatalogProtoForTesting(
    LoraAdapterCatalogListResult Function(LoraAdapterCatalogListRequest)?
        override,
  ) {
    _listCatalogForTesting = override;
  }

  static void setQueryCatalogProtoForTesting(
    LoraAdapterCatalogListResult Function(LoraAdapterCatalogQuery)? override,
  ) {
    _queryCatalogForTesting = override;
  }

  static void setGetCatalogEntryProtoForTesting(
    LoraAdapterCatalogGetResult Function(LoraAdapterCatalogGetRequest)?
        override,
  ) {
    _getCatalogEntryForTesting = override;
  }

  static void setMarkDownloadCompletedProtoForTesting(
    LoraAdapterDownloadCompletedResult Function(
      LoraAdapterDownloadCompletedRequest,
    )? override,
  ) {
    _markDownloadCompletedForTesting = override;
  }

  // MARK: - Registry Operations

  /// Register a LoRA adapter in the global registry.
  ///
  /// Entry is deep-copied internally by C++.
  /// Throws on failure.
  LoraAdapterCatalogEntry register(LoraAdapterCatalogEntry entry) {
    final override = _registerForTesting;
    if (override != null) {
      return override(entry);
    }

    final fn = RacNative.bindings.rac_lora_register_proto;
    if (fn == null) {
      throw UnsupportedError('rac_lora_register_proto is unavailable');
    }
    final result =
        DartBridgeProtoUtils.callRequestWithHandle<LoraAdapterCatalogEntry>(
      handle: _registryHandle('rac_lora_register_proto'),
      request: entry,
      invoke: fn,
      decode: LoraAdapterCatalogEntry.fromBuffer,
      symbol: 'rac_lora_register_proto',
    );
    _logger.info('LoRA adapter registered: ${result.id}');
    return result;
  }

  /// List registered LoRA adapters through the generated catalog ABI.
  LoraAdapterCatalogListResult listCatalog(
    LoraAdapterCatalogListRequest request,
  ) {
    final override = _listCatalogForTesting;
    if (override != null) {
      return override(request);
    }

    final fn = RacNative.bindings.rac_lora_catalog_list_proto;
    if (fn == null) {
      throw UnsupportedError('rac_lora_catalog_list_proto is unavailable');
    }
    return DartBridgeProtoUtils.callRequestWithHandle<
        LoraAdapterCatalogListResult>(
      handle: _registryHandle('rac_lora_catalog_list_proto'),
      request: request,
      invoke: fn,
      decode: LoraAdapterCatalogListResult.fromBuffer,
      symbol: 'rac_lora_catalog_list_proto',
    );
  }

  /// Query registered LoRA adapters through the generated catalog ABI.
  LoraAdapterCatalogListResult queryCatalog(LoraAdapterCatalogQuery query) {
    final override = _queryCatalogForTesting;
    if (override != null) {
      return override(query);
    }

    final fn = RacNative.bindings.rac_lora_catalog_query_proto;
    if (fn == null) {
      throw UnsupportedError('rac_lora_catalog_query_proto is unavailable');
    }
    return DartBridgeProtoUtils.callRequestWithHandle<
        LoraAdapterCatalogListResult>(
      handle: _registryHandle('rac_lora_catalog_query_proto'),
      request: query,
      invoke: fn,
      decode: LoraAdapterCatalogListResult.fromBuffer,
      symbol: 'rac_lora_catalog_query_proto',
    );
  }

  /// Fetch a single LoRA catalog entry by generated request.
  LoraAdapterCatalogGetResult getCatalogEntry(
    LoraAdapterCatalogGetRequest request,
  ) {
    final override = _getCatalogEntryForTesting;
    if (override != null) {
      return override(request);
    }

    final fn = RacNative.bindings.rac_lora_catalog_get_proto;
    if (fn == null) {
      throw UnsupportedError('rac_lora_catalog_get_proto is unavailable');
    }
    return DartBridgeProtoUtils.callRequestWithHandle<
        LoraAdapterCatalogGetResult>(
      handle: _registryHandle('rac_lora_catalog_get_proto'),
      request: request,
      invoke: fn,
      decode: LoraAdapterCatalogGetResult.fromBuffer,
      symbol: 'rac_lora_catalog_get_proto',
    );
  }

  /// Record native-owned LoRA download/import completion in commons catalog
  /// state. Download bytes, permissions, and file handles stay native-owned.
  LoraAdapterDownloadCompletedResult markDownloadCompleted(
    LoraAdapterDownloadCompletedRequest request,
  ) {
    final override = _markDownloadCompletedForTesting;
    if (override != null) {
      return override(request);
    }

    final fn =
        RacNative.bindings.rac_lora_catalog_mark_download_completed_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_lora_catalog_mark_download_completed_proto is unavailable',
      );
    }
    return DartBridgeProtoUtils.callRequestWithHandle<
        LoraAdapterDownloadCompletedResult>(
      handle: _registryHandle('rac_lora_catalog_mark_download_completed_proto'),
      request: request,
      invoke: fn,
      decode: LoraAdapterDownloadCompletedResult.fromBuffer,
      symbol: 'rac_lora_catalog_mark_download_completed_proto',
    );
  }

  /// Get all registered LoRA adapters compatible with a model.
  List<LoraAdapterCatalogEntry> getForModel(String modelId) {
    return queryCatalog(
      LoraAdapterCatalogQuery(modelId: modelId),
    ).entries.toList(growable: false);
  }

  /// Get all registered LoRA adapters.
  List<LoraAdapterCatalogEntry> getAll() {
    return listCatalog(
      LoraAdapterCatalogListRequest(),
    ).entries.toList(growable: false);
  }

  // MARK: - Private Helpers

  Pointer<Void> _registryHandle(String symbol) {
    final registry = RacNative.bindings.rac_get_lora_registry?.call();
    if (registry == null || registry == nullptr) {
      throw UnsupportedError('$symbol is unavailable');
    }
    return registry;
  }
}
