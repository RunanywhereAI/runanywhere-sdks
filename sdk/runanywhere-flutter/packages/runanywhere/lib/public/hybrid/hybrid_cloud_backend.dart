// SPDX-License-Identifier: Apache-2.0
//
// hybrid_cloud_backend.dart — generic cloud-STT backend registration +
// credential/model registry. Mirrors the Kotlin `BACKEND.CLOUD` object
// (sdk/runanywhere-kotlin/.../public/hybrid/Backend.kt) and the Swift
// `CloudSTT` enum.
//
// `register()` folds the cloud engine plugin into the commons plugin
// registry via `rac_backend_cloud_register()` (the exact mirror of the
// on-device backend's register). Once registered the unified "cloud" plugin
// serves RAC_PRIMITIVE_TRANSCRIBE and is routable via
// `rac_plugin_route(TRANSCRIBE, hint="cloud")`, which is how the hybrid
// router creates the online STT service.
//
// The concrete HTTP provider (Sarvam first) is DATA carried in each registered
// model entry (`provider`) and threaded into the create config's `"provider"`
// field — there is NO provider-specific Dart class.

import 'dart:convert';

import 'package:runanywhere/generated/hybrid_router.pb.dart'
    show CloudSttBackendConfig;
import 'package:runanywhere/native/dart_bridge_hybrid_stt.dart';
import 'package:runanywhere/public/hybrid/hybrid_model.dart'
    show kHybridDefaultCloudProvider;

/// Serialize a generated [CloudSttBackendConfig] into the `config_json` string
/// the routed "cloud" plugin's `create` expects. Carries `provider` so the
/// engine selects the right HTTP backend. Commons injects a default provider
/// too, but we pass it explicitly so the routed engine never has to guess
/// (mirrors Kotlin/Swift).
///
/// The keys are the snake_case wire names the cloud_stt engine parses
/// (`api_key`, `language_code`, `base_url`, `timeout_ms`) — NOT the proto-JSON
/// camelCase names — so a plain `writeToJson()` cannot be used here. Optional
/// fields are omitted when unset so the provider falls back to its defaults.
String cloudSttConfigJson(CloudSttBackendConfig config) {
  final json = <String, Object>{
    'provider': config.provider,
    'api_key': config.apiKey,
    'model': config.model,
  };
  if (config.hasLanguageCode()) {
    json['language_code'] = config.languageCode;
  }
  if (config.hasBaseUrl()) {
    json['base_url'] = config.baseUrl;
  }
  if (config.hasTimeoutMs()) {
    json['timeout_ms'] = config.timeoutMs;
  }
  return jsonEncode(json);
}

/// Generic cloud speech-to-text backend. Fronts one or more HTTP STT providers
/// (Sarvam first); the provider is data carried in each registered model entry.
///
/// Acts as both the plugin-registration entry point and the in-process
/// credential + model + provider registry. Access via
/// `RunAnywhere.hybrid.cloud`.
///
/// ```dart
/// RunAnywhere.hybrid.cloud.register(
///   id: 'saarika',
///   model: 'saarika:v2.5',
///   apiKey: '…',
///   provider: 'sarvam',
///   languageCode: 'en-IN',
/// );
/// ```
class CloudBackend {
  CloudBackend._();

  /// Shared instance backing `RunAnywhere.hybrid.cloud`.
  static final CloudBackend instance = CloudBackend._();

  /// Default cloud provider when a registration omits `provider`.
  static const String defaultProvider = kHybridDefaultCloudProvider;

  final Map<String, CloudSttBackendConfig> _registry =
      <String, CloudSttBackendConfig>{};
  bool _pluginRegistered = false;

  /// Register the cloud engine with the commons plugin registry exactly
  /// once per process (idempotent). Mirrors the on-device backend's register —
  /// the engine must be routable before the hybrid router can create the online
  /// side via `rac_plugin_route(TRANSCRIBE, hint="cloud")`. Tolerant of the
  /// native already-registered code so repeated calls are safe.
  ///
  /// Returns true when the plugin is registered (or already was). Returns false
  /// when the `rac_backend_cloud_register` symbol is unavailable in this
  /// build (e.g. cloud engine not linked into the loaded native library).
  bool ensurePluginRegistered() {
    if (_pluginRegistered) {
      return true;
    }
    final rc = DartBridgeHybridStt.instance.registerCloud();
    // Null = symbol missing; any non-null rc means the call ran (the bridge
    // already treats ALREADY_REGISTERED as success and logs other codes).
    _pluginRegistered = rc != null;
    return _pluginRegistered;
  }

  /// Register a cloud STT model under [id]. Once registered, callers refer to it
  /// by [id] alone from `HybridModel.onlineCloud(id)`. The registry is in-memory
  /// and lives for the process lifetime unless removed via [unregister] /
  /// [clear].
  ///
  /// Fires the one-time plugin registration at the same bootstrap point the app
  /// registers credentials (symmetric to the on-device backend's register).
  void register({
    required String id,
    required String model,
    required String apiKey,
    String provider = defaultProvider,
    String? languageCode,
    String? baseUrl,
    int? timeoutMs,
  }) {
    if (id.isEmpty) {
      throw ArgumentError('Cloud registry id must be non-empty');
    }
    if (model.isEmpty) {
      throw ArgumentError('Cloud model string must be non-empty');
    }
    if (apiKey.isEmpty) {
      throw ArgumentError('Cloud apiKey must be non-empty');
    }
    if (provider.isEmpty) {
      throw ArgumentError('Cloud provider must be non-empty');
    }
    ensurePluginRegistered();
    _registry[id] = CloudSttBackendConfig(
      provider: provider,
      model: model,
      apiKey: apiKey,
      languageCode: languageCode,
      baseUrl: baseUrl,
      timeoutMs: timeoutMs,
    );
  }

  /// Look up the registered config for a model by id.
  CloudSttBackendConfig? lookup(String id) => _registry[id];

  /// True iff a model is registered under [id].
  bool isRegistered(String id) => _registry.containsKey(id);

  /// Remove a registration. Returns true when an entry was removed.
  bool unregister(String id) => _registry.remove(id) != null;

  /// Drop every registration (does not unregister the engine plugin).
  void clear() => _registry.clear();
}
