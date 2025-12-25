//
//  data_source.dart
//  RunAnywhere SDK
//
//  Base protocol for all data sources
//  Matches iOS DataSource.swift
//

import 'package:runanywhere/data/protocols/repository_entity.dart';

/// Information about local storage status
class DataSourceStorageInfo {
  final int? totalSpace;
  final int? availableSpace;
  final int? usedSpace;
  final int entityCount;
  final DateTime lastUpdated;

  DataSourceStorageInfo({
    this.totalSpace,
    this.availableSpace,
    this.usedSpace,
    required this.entityCount,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  @override
  String toString() {
    return 'DataSourceStorageInfo(entityCount: $entityCount, '
        'lastUpdated: $lastUpdated)';
  }
}

/// Errors that can occur in data sources
enum DataSourceError {
  notAvailable,
  configurationInvalid,
  networkUnavailable,
  authenticationFailed,
  storageUnavailable,
  entityNotFound,
  operationFailed;

  String get description {
    switch (this) {
      case DataSourceError.notAvailable:
        return 'Data source is not available';
      case DataSourceError.configurationInvalid:
        return 'Invalid configuration';
      case DataSourceError.networkUnavailable:
        return 'Network is unavailable';
      case DataSourceError.authenticationFailed:
        return 'Authentication failed';
      case DataSourceError.storageUnavailable:
        return 'Local storage is unavailable';
      case DataSourceError.entityNotFound:
        return 'Entity not found';
      case DataSourceError.operationFailed:
        return 'Operation failed';
    }
  }
}

/// Exception wrapping DataSourceError
class DataSourceException implements Exception {
  final DataSourceError error;
  final String? message;
  final Object? cause;

  const DataSourceException(
    this.error, {
    this.message,
    this.cause,
  });

  @override
  String toString() {
    final buffer = StringBuffer('DataSourceException(${error.description}');
    if (message != null) {
      buffer.write(': $message');
    }
    if (cause != null) {
      buffer.write(', cause: $cause');
    }
    buffer.write(')');
    return buffer.toString();
  }
}

/// Base protocol for all data sources
abstract class DataSource<E extends RepositoryEntity> {
  /// Check if the data source is available and healthy
  Future<bool> isAvailable();

  /// Validate the data source configuration
  Future<void> validateConfiguration();
}

/// Protocol for local data sources that store data locally
abstract class LocalDataSource<E extends RepositoryEntity>
    implements DataSource<E> {
  /// Load entity from local storage
  Future<E?> load(String id);

  /// Load all entities from local storage
  Future<List<E>> loadAll();

  /// Store entity in local storage
  Future<void> store(E entity);

  /// Remove entity from local storage
  Future<bool> remove(String id);

  /// Clear all data from local storage
  Future<int> clear();

  /// Get storage health information
  Future<DataSourceStorageInfo> getStorageInfo();
}

/// Protocol for remote data sources that fetch data from network APIs
abstract class RemoteDataSource<E extends RepositoryEntity>
    implements DataSource<E> {
  /// Fetch a single entity by identifier
  Future<E?> fetch(String id);

  /// Fetch multiple entities with optional filtering
  Future<List<E>> fetchAll(Map<String, dynamic>? filters);

  /// Save entity to remote source
  Future<E> save(E entity);

  /// Delete entity from remote source
  Future<void> delete(String id);

  /// Test network connectivity and authentication
  Future<bool> testConnection();

  /// Sync a batch of entities to the remote source
  /// Returns successfully synced entity IDs
  Future<List<String>> syncBatch(List<E> batch);
}
