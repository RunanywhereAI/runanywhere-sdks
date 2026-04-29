// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_plugin_loader.dart — Plugin Loader capability surface
// (canonical §12 namespace). Mirrors Swift `RunAnywhere.PluginLoader`
// and the RN/Web `RunAnywhere.pluginLoader.*` namespace.
//
// Wired to the `rac_registry_*` C ABI. If commons returns
// `RAC_ERROR_FEATURE_NOT_AVAILABLE` (statically-linked engine bundle),
// the SDKException naturally propagates.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Plugin Loader capability surface (canonical §12 namespace).
///
/// Access via `RunAnywhereSDK.instance.pluginLoader`.
class RunAnywherePluginLoaderCapability {
  RunAnywherePluginLoaderCapability._();
  static final RunAnywherePluginLoaderCapability _instance =
      RunAnywherePluginLoaderCapability._();
  static RunAnywherePluginLoaderCapability get shared => _instance;

  static final _logger = SDKLogger('RunAnywhere.PluginLoader');

  /// Compile-time plugin API version this build was built against.
  int get apiVersion {
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<Uint32 Function(), int Function()>(
      'rac_registry_api_version',
    );
    return fn();
  }

  /// Total number of plugins currently registered.
  int get registeredCount {
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<IntPtr Function(), int Function()>(
      'rac_registry_registered_count',
    );
    return fn();
  }

  /// Snapshot of currently-registered plugin names.
  List<String> registeredNames() {
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<
        Int32 Function(Pointer<Pointer<Pointer<Utf8>>>, Pointer<IntPtr>),
        int Function(Pointer<Pointer<Pointer<Utf8>>>, Pointer<IntPtr>)>(
      'rac_registry_registered_names',
    );
    final outNamesPtr = calloc<Pointer<Pointer<Utf8>>>();
    final outCountPtr = calloc<IntPtr>();
    try {
      final rc = fn(outNamesPtr, outCountPtr);
      if (rc != RAC_SUCCESS) {
        _logger.warning(
          'rac_registry_registered_names failed: ${RacResultCode.getMessage(rc)}',
        );
        return const <String>[];
      }
      final namesArray = outNamesPtr.value;
      final count = outCountPtr.value;
      final results = <String>[];
      for (var i = 0; i < count; i++) {
        final namePtr = namesArray[i];
        if (namePtr != nullptr) {
          results.add(namePtr.toDartString());
        }
      }
      // Free the array (and its strings) if a free function exists.
      try {
        final freeFn = lib.lookupFunction<
            Void Function(Pointer<Pointer<Utf8>>, IntPtr),
            void Function(Pointer<Pointer<Utf8>>, int)>(
          'rac_registry_names_free',
        );
        freeFn(namesArray, count);
      } catch (_) {
        // Optional symbol — if missing we leak; harmless once-per-call.
      }
      return results;
    } finally {
      calloc.free(outNamesPtr);
      calloc.free(outCountPtr);
    }
  }

  /// Load a shared library at [path] and register the
  /// `rac_plugin_entry_<stem>` it exposes with the in-process plugin
  /// registry.
  Future<PluginInfo> load(String path) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>),
        int Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>)>(
      'rac_registry_load_plugin',
    );
    final pathPtr = path.toNativeUtf8();
    final outNamePtr = calloc<Pointer<Utf8>>();
    try {
      final rc = fn(pathPtr, outNamePtr);
      if (rc != RAC_SUCCESS) {
        _throwForCode('rac_registry_load_plugin', rc);
      }
      final namePtr = outNamePtr.value;
      final name = namePtr != nullptr ? namePtr.toDartString() : '';
      return PluginInfo(name: name, path: path);
    } finally {
      calloc.free(pathPtr);
      calloc.free(outNamePtr);
    }
  }

  /// Unregister a previously-loaded plugin and `dlclose` its handle.
  Future<void> unload(String name) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)>('rac_registry_unload_plugin');
    final namePtr = name.toNativeUtf8();
    try {
      final rc = fn(namePtr);
      if (rc != RAC_SUCCESS) {
        _throwForCode('rac_registry_unload_plugin', rc);
      }
    } finally {
      calloc.free(namePtr);
    }
  }

  static Never _throwForCode(String op, int code) {
    if (code == RacResultCode.errorFeatureNotAvailable ||
        code == RacResultCode.errorNotImplemented) {
      throw SDKException.featureNotAvailable('PluginLoader: $op');
    }
    throw SDKException.modelLoadFailed(
      op,
      RacResultCode.getMessage(code),
    );
  }
}

/// Plugin descriptor returned from `pluginLoader.load(...)`.
class PluginInfo {
  final String name;
  final String path;
  const PluginInfo({required this.name, required this.path});
}
