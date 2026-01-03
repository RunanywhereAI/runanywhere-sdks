import 'dart:async';
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../foundation/logging/sdk_logger.dart';
import 'ffi_types.dart';
import 'platform_loader.dart';

/// HTTP bridge for C++ HTTP configuration.
/// Matches Swift's `CppBridge+HTTP.swift`.
class DartBridgeHTTP {
  DartBridgeHTTP._();

  static final _logger = SDKLogger('DartBridge.HTTP');
  static final DartBridgeHTTP instance = DartBridgeHTTP._();

  String? _baseURL;
  String? _apiKey;
  Map<String, String> _defaultHeaders = {};

  /// Configure HTTP settings
  Future<void> configure({
    String? apiKey,
    String? baseURL,
    Map<String, String>? defaultHeaders,
  }) async {
    _apiKey = apiKey;
    _baseURL = baseURL;
    if (defaultHeaders != null) {
      _defaultHeaders = Map.from(defaultHeaders);
    }

    try {
      final lib = PlatformLoader.load();
      final configureFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
          int Function(Pointer<Utf8>, Pointer<Utf8>)>('rac_http_configure');

      final basePtr = (baseURL ?? '').toNativeUtf8();
      final keyPtr = (apiKey ?? '').toNativeUtf8();

      try {
        final result = configureFn(basePtr, keyPtr);
        if (result != RacResultCode.success) {
          _logger.warning('HTTP configure failed', metadata: {'code': result});
        }
      } finally {
        calloc.free(basePtr);
        calloc.free(keyPtr);
      }
    } catch (e) {
      _logger.debug('rac_http_configure not available: $e');
    }
  }

  /// Set base URL
  void setBaseURL(String url) {
    _baseURL = url;
    _updateConfig();
  }

  /// Get base URL
  String? get baseURL => _baseURL;

  /// Set API key
  void setApiKey(String key) {
    _apiKey = key;
    _updateConfig();
  }

  /// Add default header
  void addHeader(String key, String value) {
    _defaultHeaders[key] = value;
  }

  /// Remove default header
  void removeHeader(String key) {
    _defaultHeaders.remove(key);
  }

  /// Get all default headers
  Map<String, String> get headers => Map.unmodifiable(_defaultHeaders);

  void _updateConfig() {
    configure(apiKey: _apiKey, baseURL: _baseURL);
  }
}
