import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Development configuration bridge
/// 
/// Wraps C++ rac_dev_config.h functions for development mode with Supabase backend.
/// Credentials are stored ONLY in C++ development_config.cpp (git-ignored).
class DartBridgeDevConfig {
  static final _logger = SDKLogger('DartBridge.DevConfig');
  
  /// Check if development config is available
  static bool get isAvailable {
    try {
      final lib = PlatformLoader.loadCommons();
      final isAvailable = lib.lookupFunction<Bool Function(), bool Function()>(
        'rac_dev_config_is_available',
      );
      return isAvailable();
    } catch (e) {
      _logger.debug('rac_dev_config_is_available not available: $e');
      return false;
    }
  }
  
  /// Get Supabase URL for development mode
  /// Returns null if not configured
  static String? get supabaseURL {
    if (!isAvailable) return null;
    
    try {
      final lib = PlatformLoader.loadCommons();
      final getUrl = lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'rac_dev_config_get_supabase_url',
      );
      
      final result = getUrl();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      _logger.debug('rac_dev_config_get_supabase_url not available: $e');
      return null;
    }
  }
  
  /// Get Supabase anon key for development mode
  /// Returns null if not configured
  static String? get supabaseKey {
    if (!isAvailable) return null;
    
    try {
      final lib = PlatformLoader.loadCommons();
      final getKey = lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'rac_dev_config_get_supabase_key',
      );
      
      final result = getKey();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      _logger.debug('rac_dev_config_get_supabase_key not available: $e');
      return null;
    }
  }
  
  /// Get build token for development mode
  /// Returns null if not configured
  static String? get buildToken {
    try {
      final lib = PlatformLoader.loadCommons();
      final hasBuildToken = lib.lookupFunction<Bool Function(), bool Function()>(
        'rac_dev_config_has_build_token',
      );
      
      if (!hasBuildToken()) return null;
      
      final getToken = lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'rac_dev_config_get_build_token',
      );
      
      final result = getToken();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      _logger.debug('rac_dev_config_get_build_token not available: $e');
      return null;
    }
  }
  
  /// Get Sentry DSN for crash reporting (optional)
  /// Returns null if not configured
  static String? get sentryDSN {
    try {
      final lib = PlatformLoader.loadCommons();
      final getDsn = lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'rac_dev_config_get_sentry_dsn',
      );
      
      final result = getDsn();
      if (result == nullptr) return null;
      return result.toDartString();
    } catch (e) {
      _logger.debug('rac_dev_config_get_sentry_dsn not available: $e');
      return null;
    }
  }
}
