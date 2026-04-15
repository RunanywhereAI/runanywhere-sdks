import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/io_client.dart';
import 'package:runanywhere_ai/core/models/proxy_settings.dart';
import 'package:runanywhere_ai/core/services/proxy_settings_service.dart';

class ExampleHttpResponse {
  final int statusCode;
  final String body;

  const ExampleHttpResponse({
    required this.statusCode,
    required this.body,
  });

  Map<String, dynamic> decodeJson() => jsonDecode(body) as Map<String, dynamic>;
}

class ExampleHttpService {
  static final ExampleHttpService shared = ExampleHttpService._internal();

  ExampleHttpService._internal();

  Future<ExampleHttpResponse> getJson(Uri uri) async {
    final client = await createScopedHttpClient(ProxyScope.general, uri);

    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      return ExampleHttpResponse(
        statusCode: response.statusCode,
        body: body,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> testProxy(ProxyScope scope, Uri uri) async {
    final client = await createScopedHttpClient(scope, uri);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      return response.statusCode >= 200 && response.statusCode < 300;
    } finally {
      client.close(force: true);
    }
  }

  Future<http.Client> createScopedHttpPackageClient(
    ProxyScope scope,
    Uri targetUri,
  ) async {
    final ioClient = await createScopedHttpClient(scope, targetUri);
    return IOClient(ioClient);
  }

  Future<HttpClient> createScopedHttpClient(
    ProxyScope scope,
    Uri targetUri,
  ) async {
    final settings = await ProxySettingsService.shared.load(scope);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);

    if (!settings.enabled ||
        !settings.isComplete ||
        !settings.scheme.isSupportedInExampleApp ||
        !_shouldUseProxy(settings, targetUri.host)) {
      client.findProxy = (_) => 'DIRECT';
      return client;
    }

    final proxyDirective = _proxyDirectiveForSettings(settings);
    if (proxyDirective == null) {
      client.findProxy = (_) => 'DIRECT';
      return client;
    }

    client.findProxy = (_) => proxyDirective;

    if (settings.username.isNotEmpty) {
      client.authenticateProxy =
          (String host, int port, String scheme, String? realm) async {
        client.addProxyCredentials(
          host,
          port,
          realm ?? '',
          HttpClientBasicCredentials(
            settings.username,
            settings.password,
          ),
        );
        return true;
      };
    }

    return client;
  }

  Future<bool> testGeneralProxy(Uri uri) async {
    final response = await getJson(uri);
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  bool _shouldUseProxy(ProxySettings settings, String host) {
    if (!settings.bypassLocal) {
      return true;
    }

    final normalized = host.toLowerCase();
    return normalized != 'localhost' &&
        normalized != '127.0.0.1' &&
        normalized != '::1';
  }

  static String? _proxyDirectiveForSettings(ProxySettings settings) {
    if (!settings.scheme.isSupportedInExampleApp ||
        settings.port == null ||
        settings.host.trim().isEmpty) {
      return null;
    }

    return switch (settings.scheme) {
      ProxyScheme.http ||
      ProxyScheme.https =>
        'PROXY ${settings.host.trim()}:${settings.port}',
      ProxyScheme.socks5 => null,
    };
  }

  @visibleForTesting
  static String? proxyDirectiveForTesting(ProxySettings settings) {
    return _proxyDirectiveForSettings(settings);
  }
}
