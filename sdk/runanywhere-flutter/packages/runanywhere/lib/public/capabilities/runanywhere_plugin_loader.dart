// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_plugin_loader.dart — Plugin Loader capability surface
// (canonical §12 namespace). Mirrors Swift `RunAnywhere.PluginLoader`
// and the RN/Web `RunAnywhere.pluginLoader.*` namespace.
//
// §15 type-discipline: all `dart:ffi` work lives in
// `lib/native/dart_bridge_plugin_loader.dart`; this capability calls
// into that bridge.

import 'package:protobuf/protobuf.dart'
    show GeneratedMessageGenericExtensions;
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/plugin_loader.pb.dart' show PluginInfo;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_plugin_loader.dart';

export 'package:runanywhere/generated/plugin_loader.pb.dart' show PluginInfo;

/// Plugin Loader capability surface (canonical §12 namespace).
///
/// Access via `RunAnywhere.pluginLoader`.
class RunAnywherePluginLoaderCapability {
  RunAnywherePluginLoaderCapability._();
  static final RunAnywherePluginLoaderCapability _instance =
      RunAnywherePluginLoaderCapability._();
  static RunAnywherePluginLoaderCapability get shared => _instance;

  /// Compile-time plugin API version this build was built against.
  int get apiVersion => DartBridgePluginLoader.apiVersion();

  /// Total number of plugins currently registered.
  int get registeredCount => DartBridgePluginLoader.registeredCount();

  /// Snapshot of currently-registered plugin names.
  ///
  /// Mirrors Swift `RunAnywhere.pluginLoader.registeredNames()`.
  List<String> registeredNames() => DartBridgePluginLoader.registeredNames();

  /// Snapshot of all currently-loaded plugins.
  ///
  /// Mirrors Swift `RunAnywhere.pluginLoader.listLoaded()`. The C registry
  /// does not persist the original load path, so returned `PluginInfo` entries
  /// carry only the plugin name with an empty path.
  List<PluginInfo> listLoaded() => DartBridgePluginLoader.listLoaded();

  /// Load a shared library at [path] and register the
  /// `rac_plugin_entry_<stem>` it exposes with the in-process plugin
  /// registry.
  Future<PluginInfo> load(String path) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final result = DartBridgePluginLoader.loadPlugin(path);
    if (!result.success) {
      _throwForCode('load', path, result.resultCode);
    }
    return PluginInfo(name: result.name, path: path);
  }

  /// Unregister a previously-loaded plugin and `dlclose` its handle.
  Future<void> unload(String name) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final rc = DartBridgePluginLoader.unloadPlugin(name);
    if (rc != 0) {
      _throwForCode('unload', name, rc);
    }
  }

  /// Delegate plugin-error classification to the commons ABI
  /// (`rac_result_to_proto_error`) via [SDKException.fromResult], then enrich
  /// the message with the operation context. Mirrors Swift's `throwIfFailed`
  /// (RunAnywhere+PluginLoader.swift:149-156).
  static Never _throwForCode(String op, String context, int code) {
    final exception = SDKException.fromResult(code) ??
        SDKException.internalError(
          'Plugin loader reported failure without an error code',
        );
    final enriched = exception.error.deepCopy()
      ..message = '${exception.error.message} (pluginLoader.$op: $context)';
    throw SDKException(enriched, underlyingError: exception.underlyingError);
  }
}
