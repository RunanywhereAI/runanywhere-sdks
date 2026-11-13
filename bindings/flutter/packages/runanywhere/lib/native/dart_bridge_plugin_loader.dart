// SPDX-License-Identifier: Apache-2.0
//
// dart_bridge_plugin_loader.dart — FFI helpers for the
// `rac_registry_*` C ABI. Public capability code calls into this
// bridge so `lib/public/capabilities/runanywhere_plugin_loader.dart`
// stays free of `dart:ffi` imports (canonical §15 type-discipline).

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/plugin_loader.pb.dart' show PluginInfo;
import 'package:runanywhere/generated/ra_result_codes.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Result of loading a plugin: registered name + return code (0 ok).
class PluginLoadResult {
  PluginLoadResult({required this.name, required this.resultCode});
  final String name;
  final int resultCode;
  bool get success => resultCode == RacResultCodes.success;
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
      'rac_plugin_api_version',
    );
    return fn();
  }

  /// Total number of plugins currently registered.
  static int registeredCount() {
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<IntPtr Function(), int Function()>(
      'rac_registry_plugin_count',
    );
    return fn();
  }

  /// Snapshot of currently-registered plugin names.
  static List<String> registeredNames() {
    final lib = PlatformLoader.loadCommons();
    final fn = lib
        .lookupFunction<
          Int32 Function(Pointer<Pointer<Pointer<Utf8>>>, Pointer<IntPtr>),
          int Function(Pointer<Pointer<Pointer<Utf8>>>, Pointer<IntPtr>)
        >('rac_registry_list_plugins');
    final outNamesPtr = calloc<Pointer<Pointer<Utf8>>>();
    final outCountPtr = calloc<IntPtr>();
    try {
      final rc = fn(outNamesPtr, outCountPtr);
      if (rc != RacResultCodes.success) {
        _logger.warning(
          'rac_registry_list_plugins failed: ${RacResultCodes.message(rc)}',
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
      final freeFn = lib
          .lookupFunction<
            Void Function(Pointer<Pointer<Utf8>>, IntPtr),
            void Function(Pointer<Pointer<Utf8>>, int)
          >('rac_registry_free_plugin_list');
      freeFn(namesArray, count);
      return results;
    } finally {
      calloc.free(outNamesPtr);
      calloc.free(outCountPtr);
    }
  }

  /// Load a shared library and register its plugin entry-point.
  ///
  /// `rac_registry_load_plugin_named` normalizes DUPLICATE/BUSY to success and
  /// returns the exact registry key, which is what [unloadPlugin] accepts.
  static PluginLoadResult loadPlugin(String path) {
    final lib = PlatformLoader.loadCommons();
    final fn = lib
        .lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>),
          int Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>)
        >('rac_registry_load_plugin_named');
    final freeFn = lib
        .lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)
        >('rac_free');
    final pathPtr = path.toNativeUtf8();
    final outNamePtr = calloc<Pointer<Utf8>>();
    outNamePtr.value = nullptr;
    try {
      final rc = fn(pathPtr, outNamePtr);
      final namePtr = outNamePtr.value;
      final name = (rc == RacResultCodes.success && namePtr != nullptr)
          ? namePtr.toDartString()
          : '';
      if (namePtr != nullptr) {
        freeFn(namePtr);
      }
      return PluginLoadResult(name: name, resultCode: rc);
    } finally {
      calloc.free(pathPtr);
      calloc.free(outNamePtr);
    }
  }

  /// Unregister a previously-loaded plugin and `dlclose` its handle.
  static int unloadPlugin(String name) {
    final lib = PlatformLoader.loadCommons();
    final fn = lib
        .lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)
        >('rac_registry_unload_plugin');
    final namePtr = name.toNativeUtf8();
    try {
      return fn(namePtr);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Snapshot of all currently-loaded plugins as [PluginInfo].
  ///
  /// Mirrors Swift `CppBridge.PluginLoader.listLoaded()`. The C registry does
  /// not persist the original load path, so each entry returns the plugin
  /// name with an empty `path` (matching Swift behaviour).
  static List<PluginInfo> listLoaded() {
    return registeredNames()
        .map((name) => PluginInfo(name: name, path: ''))
        .toList(growable: false);
  }
}
