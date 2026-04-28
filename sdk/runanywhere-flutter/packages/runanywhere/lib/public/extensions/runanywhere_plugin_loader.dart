// SPDX-License-Identifier: Apache-2.0
//
// Wave 2: PluginLoader namespace extension. Mirrors Swift's
// `RunAnywhere+PluginLoader.swift` for runtime plugin discovery.
// Flutter targets ship with statically-linked engines on iOS/Android,
// so the dynamic loader currently throws
// `SDKException.featureNotAvailable` — enabling a stable contract that
// the desktop FFI build can wire up later.

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';

/// Runtime plugin loader (parity with Swift `RunAnywhere.PluginLoader`).
///
/// Access via `RunAnywhereSDK.instance.pluginLoader`. The Flutter FFI
/// runtime currently does not expose `rac_registry_load_plugin`; the
/// methods below throw `SDKException.featureNotAvailable` so consumer
/// apps can opt into plugin discovery once the desktop loader lands.
class RunAnywherePluginLoader {
  RunAnywherePluginLoader._();
  static final RunAnywherePluginLoader _instance = RunAnywherePluginLoader._();
  static RunAnywherePluginLoader get shared => _instance;

  /// Compile-time plugin API version this build was built against.
  /// Returns 0 while the FFI loader is not wired.
  int get apiVersion => 0;

  /// Load a shared library at [path] and register the
  /// `rac_plugin_entry_<stem>` it exposes with the in-process plugin
  /// registry. Throws `SDKException.featureNotAvailable` on platforms
  /// without dynamic plugin loading (currently all Flutter targets).
  Future<void> load(String path) async {
    throw SDKException.featureNotAvailable('PluginLoader.load');
  }

  /// Unregister a previously-loaded plugin and `dlclose` its handle.
  Future<void> unload(String name) async {
    throw SDKException.featureNotAvailable('PluginLoader.unload');
  }

  /// Total number of plugins currently registered.
  int get registeredCount => 0;

  /// Snapshot of currently-registered plugin names.
  List<String> registeredNames() => const <String>[];
}
