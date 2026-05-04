// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_plugin_loader.dart — Plugin Loader capability surface
// (canonical §12 namespace). Mirrors Swift `RunAnywhere.PluginLoader`
// and the RN/Web `RunAnywhere.pluginLoader.*` namespace.
//
// §15 type-discipline: all `dart:ffi` work lives in
// `lib/native/dart_bridge_plugin_loader.dart`; this capability calls
// into that bridge.

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge_plugin_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart' show RacResultCode;

/// Plugin Loader capability surface (canonical §12 namespace).
///
/// Access via `RunAnywhereSDK.instance.pluginLoader`.
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
  List<String> registeredNames() => DartBridgePluginLoader.registeredNames();

  /// Load a shared library at [path] and register the
  /// `rac_plugin_entry_<stem>` it exposes with the in-process plugin
  /// registry.
  Future<PluginInfo> load(String path) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    final result = DartBridgePluginLoader.loadPlugin(path);
    if (!result.success) {
      _throwForCode('rac_registry_load_plugin', result.resultCode);
    }
    return PluginInfo(name: result.name, path: path);
  }

  /// Unregister a previously-loaded plugin and `dlclose` its handle.
  Future<void> unload(String name) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    final rc = DartBridgePluginLoader.unloadPlugin(name);
    if (rc != 0) {
      _throwForCode('rac_registry_unload_plugin', rc);
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
