/**
 * DataSource.ts
 *
 * Base protocols for data sources (local and remote)
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Protocols/DataSource.swift
 */

/**
 * Base protocol for all data sources
 */
export interface DataSource<_Entity> {
  /**
   * Check if the data source is available and healthy
   */
  isAvailable(): Promise<boolean>;

  /**
   * Validate the data source configuration
   */
  validateConfiguration(): Promise<void>;
}

/**
 * Protocol for remote data sources that fetch data from network APIs
 */
export interface RemoteDataSource<Entity> extends DataSource<Entity> {
  /**
   * Fetch a single entity by identifier
   */
  fetch(id: string): Promise<Entity | null>;

  /**
   * Fetch multiple entities with optional filtering
   */
  fetchAll(filters?: Record<string, unknown>): Promise<Entity[]>;

  /**
   * Save entity to remote source
   */
  save(entity: Entity): Promise<Entity>;

  /**
   * Delete entity from remote source
   */
  delete(id: string): Promise<void>;

  /**
   * Test network connectivity and authentication
   */
  testConnection(): Promise<boolean>;

  /**
   * Sync a batch of entities to the remote source
   * Returns successfully synced entity IDs
   */
  syncBatch(batch: Entity[]): Promise<string[]>;
}

/**
 * Protocol for local data sources that store data locally (database, file system, etc.)
 */
export interface LocalDataSource<Entity> extends DataSource<Entity> {
  /**
   * Load entity from local storage
   */
  load(id: string): Promise<Entity | null>;

  /**
   * Load all entities from local storage
   */
  loadAll(): Promise<Entity[]>;

  /**
   * Store entity in local storage
   */
  store(entity: Entity): Promise<void>;

  /**
   * Remove entity from local storage
   */
  remove(id: string): Promise<void>;

  /**
   * Clear all data from local storage
   */
  clear(): Promise<void>;

  /**
   * Get storage health information
   */
  getStorageInfo(): Promise<DataSourceStorageInfo>;
}

/**
 * Information about local storage status
 */
export interface DataSourceStorageInfo {
  totalSpace?: number;
  availableSpace?: number;
  usedSpace?: number;
  entityCount: number;
  lastUpdated: Date;
}

/**
 * Errors that can occur in data sources
 */
export class DataSourceError extends Error {
  constructor(
    message: string,
    public readonly code: DataSourceErrorCode,
    public readonly cause?: Error
  ) {
    super(message);
    this.name = 'DataSourceError';
  }

  static notAvailable(): DataSourceError {
    return new DataSourceError(
      'Data source is not available',
      DataSourceErrorCode.NotAvailable
    );
  }

  static configurationInvalid(message: string): DataSourceError {
    return new DataSourceError(
      `Invalid configuration: ${message}`,
      DataSourceErrorCode.ConfigurationInvalid
    );
  }

  static networkUnavailable(): DataSourceError {
    return new DataSourceError(
      'Network is unavailable',
      DataSourceErrorCode.NetworkUnavailable
    );
  }

  static authenticationFailed(): DataSourceError {
    return new DataSourceError(
      'Authentication failed',
      DataSourceErrorCode.AuthenticationFailed
    );
  }

  static storageUnavailable(): DataSourceError {
    return new DataSourceError(
      'Local storage is unavailable',
      DataSourceErrorCode.StorageUnavailable
    );
  }

  static entityNotFound(id: string): DataSourceError {
    return new DataSourceError(
      `Entity not found: ${id}`,
      DataSourceErrorCode.EntityNotFound
    );
  }

  static operationFailed(error: Error): DataSourceError {
    return new DataSourceError(
      `Operation failed: ${error.message}`,
      DataSourceErrorCode.OperationFailed,
      error
    );
  }
}

export enum DataSourceErrorCode {
  NotAvailable = 'NOT_AVAILABLE',
  ConfigurationInvalid = 'CONFIGURATION_INVALID',
  NetworkUnavailable = 'NETWORK_UNAVAILABLE',
  AuthenticationFailed = 'AUTHENTICATION_FAILED',
  StorageUnavailable = 'STORAGE_UNAVAILABLE',
  EntityNotFound = 'ENTITY_NOT_FOUND',
  OperationFailed = 'OPERATION_FAILED',
}

/**
 * Helper for remote operations with timeout
 */
export class RemoteOperationHelper {
  constructor(private readonly timeout: number = 10000) {}

  async withTimeout<R>(operation: () => Promise<R>): Promise<R> {
    return Promise.race([
      operation(),
      new Promise<R>((_, reject) =>
        setTimeout(
          () => reject(DataSourceError.networkUnavailable()),
          this.timeout
        )
      ),
    ]);
  }
}
