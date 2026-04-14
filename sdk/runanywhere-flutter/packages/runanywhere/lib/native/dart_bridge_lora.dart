/// DartBridge+LoRA
///
/// LoRA adapter bridge - manages C++ LoRA operations via FFI.
/// Mirrors Swift's CppBridge+LLM.swift LoRA section and
/// CppBridge+LoraRegistry.swift.
///
/// Two classes:
/// - [DartBridgeLora] - Runtime LoRA operations (load/remove/clear/info)
/// - [DartBridgeLoraRegistry] - Catalog registry (register/query adapters)
library dart_bridge_lora;

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_llm.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/types/lora_types.dart';

// =============================================================================
// FFI Struct: rac_lora_entry_t
// =============================================================================

/// Matches C struct rac_lora_entry_t from rac_lora_registry.h.
/// Field order MUST match the C struct exactly.
base class RacLoraEntryCStruct extends Struct {
  // char* id
  external Pointer<Utf8> id;

  // char* name
  external Pointer<Utf8> name;

  // char* description
  external Pointer<Utf8> description;

  // char* download_url
  external Pointer<Utf8> downloadUrl;

  // char* filename
  external Pointer<Utf8> filename;

  // char** compatible_model_ids
  external Pointer<Pointer<Utf8>> compatibleModelIds;

  // size_t compatible_model_count
  @IntPtr()
  external int compatibleModelCount;

  // int64_t file_size
  @Int64()
  external int fileSize;

  // float default_scale
  @Float()
  external double defaultScale;
}

// =============================================================================
// LoRA Runtime Operations (via LLM Component)
// =============================================================================

/// LoRA adapter bridge for runtime operations.
///
/// Uses the LLM component handle - LoRA ops are on the LLM component in C++.
/// Matches Swift CppBridge.LLM LoRA methods.
class DartBridgeLora {
  // MARK: - Singleton

  static final DartBridgeLora shared = DartBridgeLora._();

  DartBridgeLora._();

  final _logger = SDKLogger('DartBridge.LoRA');

  // MARK: - LoRA Adapter Management

  /// Load a LoRA adapter and apply it to the current model.
  ///
  /// Context is recreated internally and KV cache is cleared.
  /// Throws on failure.
  void loadAdapter(String adapterPath, double scale) {
    final handle = DartBridgeLLM.shared.getHandle();

    final pathPtr = adapterPath.toNativeUtf8();
    try {
      final lib = PlatformLoader.loadCommons();
      final fn = lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Float),
          int Function(RacHandle, Pointer<Utf8>, double)>(
        'rac_llm_component_load_lora',
      );

      final result = fn(handle, pathPtr, scale);
      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to load LoRA adapter: ${RacResultCode.getMessage(result)}',
        );
      }
      _logger.info('LoRA adapter loaded: $adapterPath (scale=$scale)');
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Remove a specific LoRA adapter by path.
  ///
  /// KV cache is cleared automatically.
  /// Throws on failure.
  void removeAdapter(String adapterPath) {
    final handle = DartBridgeLLM.shared.getHandle();

    final pathPtr = adapterPath.toNativeUtf8();
    try {
      final lib = PlatformLoader.loadCommons();
      final fn = lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>)>(
        'rac_llm_component_remove_lora',
      );

      final result = fn(handle, pathPtr);
      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to remove LoRA adapter: ${RacResultCode.getMessage(result)}',
        );
      }
      _logger.info('LoRA adapter removed: $adapterPath');
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Remove all LoRA adapters.
  ///
  /// KV cache is cleared automatically.
  /// Throws on failure.
  void clearAdapters() {
    final handle = DartBridgeLLM.shared.getHandle();

    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<
        Int32 Function(RacHandle),
        int Function(RacHandle)>(
      'rac_llm_component_clear_lora',
    );

    final result = fn(handle);
    if (result != RAC_SUCCESS) {
      throw StateError(
        'Failed to clear LoRA adapters: ${RacResultCode.getMessage(result)}',
      );
    }
    _logger.info('All LoRA adapters cleared');
  }

  /// Get info about currently loaded LoRA adapters.
  ///
  /// Returns a list parsed from JSON: [{"path":"...", "scale":1.0, "applied":true}]
  List<LoRAAdapterInfo> getLoadedAdapters() {
    final handle = DartBridgeLLM.shared.getHandle();

    final outJsonPtr = calloc<Pointer<Utf8>>();
    try {
      final lib = PlatformLoader.loadCommons();
      final fn = lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Pointer<Utf8>>),
          int Function(RacHandle, Pointer<Pointer<Utf8>>)>(
        'rac_llm_component_get_lora_info',
      );

      final result = fn(handle, outJsonPtr);
      if (result != RAC_SUCCESS) {
        _logger.error('Failed to get LoRA info: $result');
        return [];
      }

      final jsonPtr = outJsonPtr.value;
      if (jsonPtr == nullptr) return [];

      final jsonStr = jsonPtr.toDartString();

      // Free the C-allocated JSON string
      final freeFn = lib.lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_free');
      freeFn(jsonPtr.cast());

      return _parseAdapterInfoJson(jsonStr);
    } finally {
      calloc.free(outJsonPtr);
    }
  }

  /// Check if the current backend supports LoRA adapters.
  LoraCompatibilityResult checkCompatibility(String loraPath) {
    final handle = DartBridgeLLM.shared.getHandle();

    final pathPtr = loraPath.toNativeUtf8();
    final outErrorPtr = calloc<Pointer<Utf8>>();
    try {
      final lib = PlatformLoader.loadCommons();
      final fn = lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Pointer<Utf8>>),
          int Function(RacHandle, Pointer<Utf8>, Pointer<Pointer<Utf8>>)>(
        'rac_llm_component_check_lora_compat',
      );

      final result = fn(handle, pathPtr, outErrorPtr);

      if (result == RAC_SUCCESS) {
        return const LoraCompatibilityResult(isCompatible: true);
      }

      // Read error message
      String? errorMsg;
      final errorPtr = outErrorPtr.value;
      if (errorPtr != nullptr) {
        errorMsg = errorPtr.toDartString();
        // Free the C-allocated error string
        final freeFn = lib.lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)>('rac_free');
        freeFn(errorPtr.cast());
      }

      return LoraCompatibilityResult(
        isCompatible: false,
        error: errorMsg,
      );
    } finally {
      calloc.free(pathPtr);
      calloc.free(outErrorPtr);
    }
  }

  // MARK: - Private Helpers

  List<LoRAAdapterInfo> _parseAdapterInfoJson(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list.map((item) {
        final map = item as Map<String, dynamic>;
        return LoRAAdapterInfo(
          path: (map['path'] as String?) ?? '',
          scale: ((map['scale'] as num?) ?? 1.0).toDouble(),
          applied: (map['applied'] as bool?) ?? false,
        );
      }).toList();
    } catch (e) {
      _logger.error('Failed to parse LoRA info JSON: $e');
      return [];
    }
  }
}

// =============================================================================
// LoRA Registry (Catalog Operations)
// =============================================================================

/// LoRA adapter registry bridge for catalog operations.
///
/// Uses the global C++ registry singleton via rac_register_lora / rac_get_lora_for_model.
/// Matches Swift CppBridge.LoraRegistry.
class DartBridgeLoraRegistry {
  // MARK: - Singleton

  static final DartBridgeLoraRegistry shared = DartBridgeLoraRegistry._();

  DartBridgeLoraRegistry._();

  final _logger = SDKLogger('DartBridge.LoRA.Registry');

  // MARK: - Registry Operations

  /// Register a LoRA adapter in the global registry.
  ///
  /// Entry is deep-copied internally by C++.
  /// Throws on failure.
  void register(LoraAdapterCatalogEntry entry) {
    final lib = PlatformLoader.loadCommons();

    final strdupFn = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)>('rac_strdup');

    final registerFn = lib.lookupFunction<
        Int32 Function(Pointer<RacLoraEntryCStruct>),
        int Function(Pointer<RacLoraEntryCStruct>)>('rac_register_lora');

    // Allocate C struct on Dart heap
    final entryPtr = calloc<RacLoraEntryCStruct>();

    // Temporary Dart strings for conversion
    final idDart = entry.id.toNativeUtf8();
    final nameDart = entry.name.toNativeUtf8();
    final descDart = entry.description.toNativeUtf8();
    final urlDart = entry.downloadUrl.toNativeUtf8();
    final filenameDart = entry.filename.toNativeUtf8();

    // Allocate compatible model IDs array
    final compatCount = entry.compatibleModelIds.length;
    final compatArrayPtr = calloc<Pointer<Utf8>>(compatCount);
    final compatDartPtrs = <Pointer<Utf8>>[];

    try {
      // Fill string fields using strdup (C heap allocation)
      entryPtr.ref.id = strdupFn(idDart);
      entryPtr.ref.name = strdupFn(nameDart);
      entryPtr.ref.description = strdupFn(descDart);
      entryPtr.ref.downloadUrl = strdupFn(urlDart);
      entryPtr.ref.filename = strdupFn(filenameDart);

      // Fill compatible model IDs
      for (int i = 0; i < compatCount; i++) {
        final dartPtr = entry.compatibleModelIds[i].toNativeUtf8();
        compatDartPtrs.add(dartPtr);
        compatArrayPtr[i] = strdupFn(dartPtr);
      }
      entryPtr.ref.compatibleModelIds = compatArrayPtr;
      entryPtr.ref.compatibleModelCount = compatCount;
      entryPtr.ref.fileSize = entry.fileSize;
      entryPtr.ref.defaultScale = entry.defaultScale;

      final result = registerFn(entryPtr);
      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to register LoRA adapter "${entry.id}": ${RacResultCode.getMessage(result)}',
        );
      }
      _logger.info('LoRA adapter registered: ${entry.id}');
    } finally {
      // Free Dart-allocated temporary strings
      calloc.free(idDart);
      calloc.free(nameDart);
      calloc.free(descDart);
      calloc.free(urlDart);
      calloc.free(filenameDart);
      for (final ptr in compatDartPtrs) {
        calloc.free(ptr);
      }

      // Free the C struct fields (strdup'd strings) via rac_lora_entry_free
      // But we used calloc for the struct itself, so we need to free the
      // strdup'd strings individually. C deep-copied on register, so the
      // strdup'd pointers in the struct need to be freed.
      final cFreeFn = lib.lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('free');

      // Free strdup'd strings inside the struct
      if (entryPtr.ref.id != nullptr) cFreeFn(entryPtr.ref.id.cast());
      if (entryPtr.ref.name != nullptr) cFreeFn(entryPtr.ref.name.cast());
      if (entryPtr.ref.description != nullptr) {
        cFreeFn(entryPtr.ref.description.cast());
      }
      if (entryPtr.ref.downloadUrl != nullptr) {
        cFreeFn(entryPtr.ref.downloadUrl.cast());
      }
      if (entryPtr.ref.filename != nullptr) {
        cFreeFn(entryPtr.ref.filename.cast());
      }
      // Free strdup'd compatible model IDs
      for (int i = 0; i < compatCount; i++) {
        if (compatArrayPtr[i] != nullptr) {
          cFreeFn(compatArrayPtr[i].cast());
        }
      }
      calloc.free(compatArrayPtr);
      calloc.free(entryPtr);
    }
  }

  /// Get all registered LoRA adapters compatible with a model.
  List<LoraAdapterCatalogEntry> getForModel(String modelId) {
    final lib = PlatformLoader.loadCommons();

    final modelIdPtr = modelId.toNativeUtf8();
    final outEntriesPtr = calloc<Pointer<Pointer<RacLoraEntryCStruct>>>();
    final outCountPtr = calloc<IntPtr>();

    try {
      final fn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>,
              Pointer<Pointer<Pointer<RacLoraEntryCStruct>>>, Pointer<IntPtr>),
          int Function(
              Pointer<Utf8>,
              Pointer<Pointer<Pointer<RacLoraEntryCStruct>>>,
              Pointer<IntPtr>)>('rac_get_lora_for_model');

      final result = fn(modelIdPtr, outEntriesPtr, outCountPtr);
      if (result != RAC_SUCCESS) {
        _logger.error('Failed to get LoRA adapters for model $modelId');
        return [];
      }

      return _readEntryArray(lib, outEntriesPtr.value, outCountPtr.value);
    } finally {
      calloc.free(modelIdPtr);
      calloc.free(outEntriesPtr);
      calloc.free(outCountPtr);
    }
  }

  /// Get all registered LoRA adapters.
  List<LoraAdapterCatalogEntry> getAll() {
    final lib = PlatformLoader.loadCommons();

    // Use the registry handle to call get_all
    final getRegistryFn = lib.lookupFunction<
        Pointer<Void> Function(),
        Pointer<Void> Function()>('rac_get_lora_registry');

    final registry = getRegistryFn();
    if (registry == nullptr) return [];

    final outEntriesPtr = calloc<Pointer<Pointer<RacLoraEntryCStruct>>>();
    final outCountPtr = calloc<IntPtr>();

    try {
      final fn = lib.lookupFunction<
          Int32 Function(Pointer<Void>,
              Pointer<Pointer<Pointer<RacLoraEntryCStruct>>>, Pointer<IntPtr>),
          int Function(
              Pointer<Void>,
              Pointer<Pointer<Pointer<RacLoraEntryCStruct>>>,
              Pointer<IntPtr>)>('rac_lora_registry_get_all');

      final result = fn(registry, outEntriesPtr, outCountPtr);
      if (result != RAC_SUCCESS) {
        _logger.error('Failed to get all LoRA adapters');
        return [];
      }

      return _readEntryArray(lib, outEntriesPtr.value, outCountPtr.value);
    } finally {
      calloc.free(outEntriesPtr);
      calloc.free(outCountPtr);
    }
  }

  // MARK: - Private Helpers

  /// Read an array of rac_lora_entry_t* pointers and convert to Dart.
  List<LoraAdapterCatalogEntry> _readEntryArray(
    DynamicLibrary lib,
    Pointer<Pointer<RacLoraEntryCStruct>> entriesPtr,
    int count,
  ) {
    if (entriesPtr == nullptr || count <= 0) return [];

    final freeFn = lib.lookupFunction<
        Void Function(Pointer<Pointer<RacLoraEntryCStruct>>, IntPtr),
        void Function(
            Pointer<Pointer<RacLoraEntryCStruct>>, int)>('rac_lora_entry_array_free');

    try {
      final results = <LoraAdapterCatalogEntry>[];
      for (int i = 0; i < count; i++) {
        final entryPtr = entriesPtr[i];
        if (entryPtr == nullptr) continue;

        final entry = entryPtr.ref;

        // Read compatible model IDs
        final compatIds = <String>[];
        if (entry.compatibleModelIds != nullptr) {
          for (int j = 0; j < entry.compatibleModelCount; j++) {
            final idPtr = entry.compatibleModelIds[j];
            if (idPtr != nullptr) {
              compatIds.add(idPtr.toDartString());
            }
          }
        }

        results.add(LoraAdapterCatalogEntry(
          id: entry.id != nullptr ? entry.id.toDartString() : '',
          name: entry.name != nullptr ? entry.name.toDartString() : '',
          description: entry.description != nullptr
              ? entry.description.toDartString()
              : '',
          downloadUrl: entry.downloadUrl != nullptr
              ? entry.downloadUrl.toDartString()
              : '',
          filename: entry.filename != nullptr
              ? entry.filename.toDartString()
              : '',
          compatibleModelIds: compatIds,
          fileSize: entry.fileSize,
          defaultScale: entry.defaultScale,
        ));
      }
      return results;
    } finally {
      freeFn(entriesPtr, count);
    }
  }
}
