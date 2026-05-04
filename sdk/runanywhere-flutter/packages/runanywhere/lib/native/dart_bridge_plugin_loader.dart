// SPDX-License-Identifier: Apache-2.0
//
// dart_bridge_plugin_loader.dart — FFI helpers for the
// `rac_registry_*` C ABI. Public capability code calls into this
// bridge so `lib/public/capabilities/runanywhere_plugin_loader.dart`
// stays free of `dart:ffi` imports (canonical §15 type-discipline).

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// Result of loading a plugin: registered name + return code (0 ok).
class PluginLoadResult {
  PluginLoadResult({required this.name, required this.resultCode});
  final String name;
  final int resultCode;
  bool get success => resultCode == RAC_SUCCESS;
}

/// FFI bridge to the `rac_registry_*` C ABI. Owns all `dart:ffi`
/// usage so the public capability layer can stay opaque.
class DartBridgePluginLoader {
  DartBridgePluginLoader._();

  static final _logger = SDKLogger('DartBridge.PluginLoader');

  /// Compile-time plugin API version this build was built against.
  static int apiVersion() {
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<Uint32 Function(), int Function()>(
      'rac_registry_api_version',
    );
    return fn();
  }

  /// Total number of plugins currently registered.
  static int registeredCount() {
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<IntPtr Function(), int Function()>(
      'rac_registry_registered_count',
    );
    return fn();
  }

  /// Snapshot of currently-registered plugin names.
  static List<String> registeredNames() {
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

  /// Load a shared library and register its plugin entry-point.
  static PluginLoadResult loadPlugin(String path) {
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
      final namePtr = outNamePtr.value;
      final name = (rc == RAC_SUCCESS && namePtr != nullptr)
          ? namePtr.toDartString()
          : '';
      return PluginLoadResult(name: name, resultCode: rc);
    } finally {
      calloc.free(pathPtr);
      calloc.free(outNamePtr);
    }
  }

  /// Unregister a previously-loaded plugin and `dlclose` its handle.
  static int unloadPlugin(String name) {
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)>('rac_registry_unload_plugin');
    final namePtr = name.toNativeUtf8();
    try {
      return fn(namePtr);
    } finally {
      calloc.free(namePtr);
    }
  }
}
