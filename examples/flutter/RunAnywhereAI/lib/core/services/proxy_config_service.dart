import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages HTTP proxy configuration and provides proxy-aware HTTP clients.
class ProxyConfigService {
  static final ProxyConfigService shared = ProxyConfigService._();
  ProxyConfigService._();

  bool _enabled = false;
  String _host = '';
  int _port = 8080;

  bool get enabled => _enabled;
  String get host => _host;
  int get port => _port;

  /// Load proxy settings from SharedPreferences.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(PreferenceKeys.proxyEnabled) ?? false;
    _host = prefs.getString(PreferenceKeys.proxyHost) ?? '';
    _port = prefs.getInt(PreferenceKeys.proxyPort) ?? 8080;
    // Apply immediately after loading so proxy is active from app start
    applyToServices();
  }

  /// Save proxy settings and immediately apply to running services.
  Future<void> save({
    required bool enabled,
    required String host,
    required int port,
  }) async {
    _enabled = enabled;
    _host = host;
    _port = port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PreferenceKeys.proxyEnabled, enabled);
    await prefs.setString(PreferenceKeys.proxyHost, host);
    await prefs.setInt(PreferenceKeys.proxyPort, port);
    applyToServices();
  }

  /// Inject the current proxy configuration into SDK network services.
  void applyToServices() {
    ModelDownloadService.shared.clientFactory = getHttpClient;
    HTTPService.shared.setHttpClient(getHttpClient());
    if (_enabled && _host.isNotEmpty) {
      debugPrint('🌐 Proxy enabled: $_host:$_port');
    }
  }

  /// Returns an [http.Client] configured with the current proxy settings.
  /// Falls back to a plain [http.Client] if proxy is disabled or misconfigured.
  http.Client getHttpClient() {
    if (!_enabled || _host.isEmpty) {
      return http.Client();
    }
    final inner = HttpClient();
    inner.findProxy = (uri) => 'PROXY $_host:$_port';
    inner.badCertificateCallback = (cert, host, port) => true;
    return IOClient(inner);
  }
}
