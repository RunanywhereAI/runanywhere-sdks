import 'dart:async';

import 'data_source_storage_info.dart';

/// Base protocol for all data sources
/// Matches iOS DataSource from DataSource.swift
abstract class DataSource<Entity> {
  /// Check if the data source is available and healthy
  Future<bool> isAvailable();

  /// Validate the data source configuration
  Future<void> validateConfiguration();
}

/// Protocol for remote data sources that fetch data from network APIs
/// Matches iOS RemoteDataSource from DataSource.swift
abstract class RemoteDataSource<Entity> extends DataSource<Entity> {
  /// Fetch a single entity by identifier
  Future<Entity?> fetch(String id);

  /// Fetch multiple entities with optional filtering
  Future<List<Entity>> fetchAll({Map<String, dynamic>? filter});

  /// Save entity to remote source
  Future<Entity> save(Entity entity);

  /// Delete entity from remote source
  Future<void> delete(String id);

  /// Test network connectivity and authentication
  Future<bool> testConnection();

  /// Sync a batch of entities to the remote source
  /// Returns successfully synced entity IDs
  Future<List<String>> syncBatch(List<Entity> batch);
}

/// Protocol for local data sources that store data locally (database, file system, etc.)
/// Matches iOS LocalDataSource from DataSource.swift
abstract class LocalDataSource<Entity> extends DataSource<Entity> {
  /// Load entity from local storage
  Future<Entity?> load(String id);

  /// Load all entities from local storage
  Future<List<Entity>> loadAll();

  /// Store entity in local storage
  Future<void> store(Entity entity);

  /// Remove entity from local storage
  Future<void> remove(String id);

  /// Clear all data from local storage
  Future<void> clear();

  /// Get storage health information
  Future<DataSourceStorageInfo> getStorageInfo();
}

/// Helper for remote operations with timeout
/// Matches iOS RemoteOperationHelper from DataSource.swift
class RemoteOperationHelper {
  final Duration timeout;

  const RemoteOperationHelper({this.timeout = const Duration(seconds: 10)});

  /// Execute an operation with timeout
  Future<R> withTimeout<R>(Future<R> Function() operation) async {
    return await operation().timeout(
      timeout,
      onTimeout: () => throw const DataSourceNetworkUnavailableError(),
    );
  }
}

/// Errors that can occur in data sources
/// Matches iOS DataSourceError from DataSource.swift
abstract class DataSourceError implements Exception {
  const DataSourceError();

  String get message;

  @override
  String toString() => 'DataSourceError: $message';
}

class DataSourceNotAvailableError extends DataSourceError {
  const DataSourceNotAvailableError();

  @override
  String get message => 'Data source is not available';
}

class DataSourceConfigurationInvalidError extends DataSourceError {
  final String reason;
  const DataSourceConfigurationInvalidError(this.reason);

  @override
  String get message => 'Invalid configuration: $reason';
}

class DataSourceNetworkUnavailableError extends DataSourceError {
  const DataSourceNetworkUnavailableError();

  @override
  String get message => 'Network is unavailable';
}

class DataSourceAuthenticationFailedError extends DataSourceError {
  const DataSourceAuthenticationFailedError();

  @override
  String get message => 'Authentication failed';
}

class DataSourceStorageUnavailableError extends DataSourceError {
  const DataSourceStorageUnavailableError();

  @override
  String get message => 'Local storage is unavailable';
}

class DataSourceEntityNotFoundError extends DataSourceError {
  final String entityId;
  const DataSourceEntityNotFoundError(this.entityId);

  @override
  String get message => 'Entity not found: $entityId';
}

class DataSourceOperationFailedError extends DataSourceError {
  final Object error;
  const DataSourceOperationFailedError(this.error);

  @override
  String get message => 'Operation failed: $error';
}
