/**
 * ServiceContainer.ts
 *
 * Service container for dependency injection
 * Centralized service management with lazy initialization
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/DependencyInjection/ServiceContainer.swift
 */

// Import actual services
import { RegistryService } from '../../Capabilities/Registry/Services/RegistryService';
import { ModelLoadingService } from '../../Capabilities/ModelLoading/Services/ModelLoadingService';
import { GenerationService } from '../../Capabilities/TextGeneration/Services/GenerationService';
import { StreamingService } from '../../Capabilities/TextGeneration/Services/StreamingService';
import { RoutingService } from '../../Capabilities/Routing/Services/RoutingService';
import { CostCalculator } from '../../Capabilities/Routing/Services/CostCalculator';
import { ResourceChecker } from '../../Capabilities/Routing/Services/ResourceChecker';
import { HardwareCapabilityManager } from '../../Capabilities/DeviceCapability/Services/HardwareCapabilityManager';
import { SDKLogger } from '../Logging/Logger/SDKLogger';
import { FileManager } from '../FileOperations/FileManager';
import { DownloadServiceImpl } from '../../Data/Network/Services/DownloadService';
import { SyncCoordinator } from '../../Data/Sync/SyncCoordinator';
import { ConfigurationService } from '../Configuration/ConfigurationService';
import { AnalyticsQueueManager } from '../../Infrastructure/Analytics/AnalyticsQueueManager';
import { ModelInfoService } from '../../Data/Services/ModelInfoService';
import { ModelInfoRepositoryImpl } from '../../Data/Repositories/ModelInfoRepository';
import type { ModelRegistry } from '../../Core/Protocols/Registry/ModelRegistry';
import type { MemoryManager } from '../../Core/Protocols/Memory/MemoryManager';
import type { DownloadService } from '../../Data/Network/Services/DownloadService';
import { AdapterRegistry } from './AdapterRegistry';
import {
  APIClient,
  type APIClientConfig,
  type AuthenticationProvider,
} from '../../Data/Network';
import type { SDKEnvironment } from '../../types';

/**
 * Service container for dependency injection
 * Provides lazy initialization of all SDK services
 */
export class ServiceContainer {
  /**
   * Shared instance (singleton)
   */
  public static shared: ServiceContainer = new ServiceContainer();

  // ============================================================================
  // Core Services
  // ============================================================================

  /**
   * Model registry
   */
  private _modelRegistry?: ModelRegistry;
  public get modelRegistry(): ModelRegistry {
    if (!this._modelRegistry) {
      this._modelRegistry = new RegistryService();
    }
    return this._modelRegistry;
  }

  /**
   * Single adapter registry for all frameworks (text and voice)
   */
  private _adapterRegistry?: AdapterRegistry;
  public get adapterRegistry(): AdapterRegistry {
    if (!this._adapterRegistry) {
      this._adapterRegistry = new AdapterRegistry();
    }
    return this._adapterRegistry;
  }

  // ============================================================================
  // Capability Services
  // ============================================================================

  /**
   * Model loading service
   */
  private _modelLoadingService?: ModelLoadingService;
  public get modelLoadingService(): ModelLoadingService {
    if (!this._modelLoadingService) {
      this._modelLoadingService = new ModelLoadingService(
        this.modelRegistry,
        this.memoryService,
        this.adapterRegistry
      );
    }
    return this._modelLoadingService;
  }

  /**
   * Routing service
   */
  private _routingService?: RoutingService;
  public get routingService(): RoutingService {
    if (!this._routingService) {
      const costCalculator = new CostCalculator();
      const resourceChecker = new ResourceChecker(this.hardwareManager);
      this._routingService = new RoutingService(
        costCalculator,
        resourceChecker
      );
    }
    return this._routingService;
  }

  /**
   * Generation service
   */
  private _generationService?: GenerationService;
  public get generationService(): GenerationService {
    if (!this._generationService) {
      this._generationService = new GenerationService(
        this.routingService,
        this.modelLoadingService
      );
    }
    return this._generationService;
  }

  /**
   * Streaming service
   */
  private _streamingService?: StreamingService;
  public get streamingService(): StreamingService {
    if (!this._streamingService) {
      this._streamingService = new StreamingService(
        this.generationService,
        this.modelLoadingService
      );
    }
    return this._streamingService;
  }

  /**
   * Download service
   */
  private _downloadService?: DownloadService;
  public get downloadService(): DownloadService {
    if (!this._downloadService) {
      this._downloadService = new DownloadServiceImpl();
    }
    return this._downloadService;
  }

  /**
   * Simplified file manager
   */
  private _fileManager?: FileManager;
  public get fileManager(): FileManager {
    if (!this._fileManager) {
      this._fileManager = new FileManager();
    }
    return this._fileManager;
  }

  // ============================================================================
  // Infrastructure
  // ============================================================================

  /**
   * Hardware manager
   */
  private _hardwareManager?: HardwareCapabilityManager;
  public get hardwareManager(): HardwareCapabilityManager {
    if (!this._hardwareManager) {
      this._hardwareManager = HardwareCapabilityManager.shared;
    }
    return this._hardwareManager;
  }

  /**
   * Memory service (implements MemoryManager protocol)
   * Stub implementation - native memory management is handled by the platform
   */
  private _memoryService?: MemoryManager;
  public get memoryService(): MemoryManager {
    if (!this._memoryService) {
      // Stub implementation - memory management is delegated to native layer
      this._memoryService = {
        registerLoadedModel: () => {},
        unregisterModel: () => {},
        getCurrentMemoryUsage: () => 0,
        getAvailableMemory: () => 2_000_000_000, // 2GB default
        hasAvailableMemory: () => true,
        canAllocate: async () => true,
        handleMemoryPressure: async () => {},
        setMemoryThreshold: () => {},
        getLoadedModels: () => [],
        requestMemory: async () => true,
        isHealthy: () => true,
      };
    }
    return this._memoryService;
  }

  /**
   * Get memory service (public alias)
   */
  public get memory(): MemoryManager {
    return this.memoryService;
  }

  /**
   * Logger
   */
  private _logger?: SDKLogger;
  public get logger(): SDKLogger {
    if (!this._logger) {
      this._logger = new SDKLogger();
    }
    return this._logger;
  }

  /**
   * Network service (environment-based: mock or real)
   * NOTE: Type will be refined when NetworkService is implemented
   */
  public networkService?: unknown;

  /**
   * Authentication service
   * Implements AuthenticationProvider interface for APIClient token injection
   */
  public authenticationService?: AuthenticationProvider;

  /**
   * API client for sync operations
   *
   * Main HTTP client for all SDK API calls.
   * Initialized during SDK initialization with base URL and API key.
   *
   * Matches iOS: public var apiClient: APIClient?
   */
  private _apiClient?: APIClient;

  /**
   * Get the API client
   */
  public get apiClient(): APIClient | undefined {
    return this._apiClient;
  }

  /**
   * Current SDK environment
   */
  private _environment?: SDKEnvironment;

  /**
   * Sync coordinator for centralized sync management
   */
  private _syncCoordinator?: SyncCoordinator;
  public async getSyncCoordinator(): Promise<SyncCoordinator | null> {
    if (!this._syncCoordinator) {
      this._syncCoordinator = new SyncCoordinator(false);
    }
    return this._syncCoordinator;
  }

  // ============================================================================
  // Data Services
  // ============================================================================

  /**
   * Configuration service
   */
  private _configurationService?: ConfigurationService;
  public async getConfigurationService(): Promise<ConfigurationService> {
    if (!this._configurationService) {
      this._configurationService = new ConfigurationService();
    }
    return this._configurationService;
  }

  /**
   * Model info service
   */
  private _modelInfoService?: ModelInfoService;
  public async getModelInfoService(): Promise<ModelInfoService> {
    if (!this._modelInfoService) {
      const repository = new ModelInfoRepositoryImpl();
      const syncCoordinator = await this.getSyncCoordinator();
      this._modelInfoService = new ModelInfoService(
        repository,
        syncCoordinator
      );
    }
    return this._modelInfoService;
  }

  /**
   * Analytics queue manager - centralized queue for all analytics
   */
  public get analyticsQueueManager(): AnalyticsQueueManager {
    return AnalyticsQueueManager.shared;
  }

  // ============================================================================
  // Initialization
  // ============================================================================

  /**
   * Initialize service container
   */
  public constructor() {
    // Container is ready for lazy initialization
  }

  /**
   * Initialize the API client with SDK configuration
   *
   * This should be called during SDK initialization to set up the API client
   * with the proper base URL and API key from the init options.
   *
   * Matches iOS: ServiceContainer setup during RunAnywhere.initialize()
   *
   * @param config - API client configuration (baseURL, apiKey)
   * @param environment - SDK environment for endpoint selection
   * @param authProvider - Optional authentication provider for token injection
   */
  public initializeAPIClient(
    config: { baseURL: string; apiKey: string; timeout?: number },
    environment: SDKEnvironment,
    authProvider?: AuthenticationProvider
  ): void {
    this._environment = environment;

    const apiClientConfig: APIClientConfig = {
      baseURL: config.baseURL,
      apiKey: config.apiKey,
      timeout: config.timeout,
      authProvider,
    };

    this._apiClient = new APIClient(apiClientConfig);

    // If auth provider is provided, also store it for later use
    if (authProvider) {
      this.authenticationService = authProvider;
    }

    // Wire API client to analytics queue manager
    this.analyticsQueueManager.setAPIClient(this._apiClient, environment);
  }

  /**
   * Set the authentication provider on the API client
   *
   * Call this after authentication completes to enable authenticated requests.
   * Matches iOS pattern of wiring AuthenticationService to APIClient.
   *
   * @param authProvider - Authentication provider implementing getAccessToken()
   */
  public setAuthenticationProvider(authProvider: AuthenticationProvider): void {
    this.authenticationService = authProvider;
    if (this._apiClient) {
      this._apiClient.setAuthenticationProvider(authProvider);
    }
  }

  /**
   * Reset service container state (for testing)
   */
  public reset(): void {
    this.authenticationService = undefined;
    this._apiClient = undefined;
    this._environment = undefined;
    this.networkService = undefined;
    this._syncCoordinator = undefined;
    this._configurationService = undefined;
    this._modelInfoService = undefined;
    // Reset core services
    this._modelRegistry = undefined;
    this._modelLoadingService = undefined;
    this._generationService = undefined;
    this._streamingService = undefined;
    this._routingService = undefined;
    this._memoryService = undefined;
    this._hardwareManager = undefined;
    this._fileManager = undefined;
    this._downloadService = undefined;
    this._logger = undefined;
  }
}
