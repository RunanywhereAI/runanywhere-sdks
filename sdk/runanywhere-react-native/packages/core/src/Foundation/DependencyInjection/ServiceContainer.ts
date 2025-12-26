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
import { HardwareCapabilityManager } from '../../Capabilities/DeviceCapability/Services/HardwareCapabilityManager';
import { SDKLogger } from '../Logging/Logger/SDKLogger';
import { FileManager } from '../FileOperations/FileManager';
import { DownloadService } from '../../services/DownloadService';
import { SyncCoordinator } from '../../Data/Sync/SyncCoordinator';
import { ConfigurationService } from '../Configuration/ConfigurationService';
import { AnalyticsQueueManager } from '../../Infrastructure/Analytics/AnalyticsQueueManager';
import { ModelInfoService } from '../../Data/Services/ModelInfoService';
import { ModelInfoRepositoryImpl } from '../../Data/Repositories/ModelInfoRepository';
import type { ModelRegistry } from '../../Core/Protocols/Registry/ModelRegistry';
import { LLMCapability } from '../../Features/LLM/LLMCapability';
import { LLMConfigurationImpl } from '../../Features/LLM/LLMConfiguration';
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

  // ============================================================================
  // Capability Services (Matches iOS: simplified capabilities)
  // ============================================================================

  /**
   * LLM capability - handles all text generation operations
   * Matches iOS: private(set) lazy var llmCapability: LLMCapability
   */
  private _llmCapability?: LLMCapability;
  public get llmCapability(): LLMCapability {
    if (!this._llmCapability) {
      this._llmCapability = new LLMCapability(new LLMConfigurationImpl({}));
    }
    return this._llmCapability;
  }

  /**
   * Download service
   * Uses the native-backed singleton from services/DownloadService
   */
  public get downloadService(): typeof DownloadService {
    return DownloadService;
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
   * Model assignment service for server-side model catalog
   */
  private _modelAssignmentService?: import('../../Infrastructure/ModelManagement/Services/ModelAssignmentService').ModelAssignmentService;

  /**
   * Get or create the model assignment service
   * Matches iOS: var modelAssignmentService: ModelAssignmentService
   */
  public get modelAssignmentService():
    | import('../../Infrastructure/ModelManagement/Services/ModelAssignmentService').ModelAssignmentService
    | undefined {
    if (!this._modelAssignmentService && this._apiClient && this._environment) {
      const {
        ModelAssignmentService,
      } = require('../../Infrastructure/ModelManagement/Services/ModelAssignmentService');
      this._modelAssignmentService = new ModelAssignmentService(
        this._apiClient,
        this._environment
      );
    }
    return this._modelAssignmentService;
  }

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
    this._modelAssignmentService = undefined;
    // Reset core services
    this._modelRegistry = undefined;
    this._llmCapability = undefined;
    this._hardwareManager = undefined;
    this._fileManager = undefined;
    this._logger = undefined;
    // Reset the download service singleton state
    DownloadService.reset();
  }
}
