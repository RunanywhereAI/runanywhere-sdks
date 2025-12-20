import 'dart:typed_data';

import 'api_endpoint.dart';

/// Protocol defining the network service interface.
///
/// Matches iOS `NetworkService` protocol.
/// Allows for environment-based implementations (real vs mock).
abstract class NetworkService {
  /// Perform a POST request with typed payload and response.
  Future<T> post<T>(
    APIEndpoint endpoint,
    Object payload, {
    required bool requiresAuth,
    required T Function(Map<String, dynamic>) fromJson,
  });

  /// Perform a GET request with typed response.
  Future<T> get<T>(
    APIEndpoint endpoint, {
    required bool requiresAuth,
    required T Function(Map<String, dynamic>) fromJson,
  });

  /// Perform a raw POST request (returns raw bytes).
  Future<Uint8List> postRaw(
    APIEndpoint endpoint,
    Uint8List payload, {
    required bool requiresAuth,
  });

  /// Perform a raw GET request (returns raw bytes).
  Future<Uint8List> getRaw(
    APIEndpoint endpoint, {
    required bool requiresAuth,
  });

  /// Perform a POST with custom path (for parameterized endpoints).
  Future<T> postWithPath<T>(
    String path,
    Object payload, {
    required bool requiresAuth,
    required T Function(Map<String, dynamic>) fromJson,
  });

  /// Perform a GET with custom path (for parameterized endpoints).
  Future<T> getWithPath<T>(
    String path, {
    required bool requiresAuth,
    required T Function(Map<String, dynamic>) fromJson,
  });
}
