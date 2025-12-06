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
import { MemoryService } from '../../Capabilities/Memory/Services/MemoryService';
import { AllocationManager } from '../../Capabilities/Memory/Services/AllocationManager';
import { PressureHandler } from '../../Capabilities/Memory/Services/PressureHandler';
import { CacheEviction } from '../../Capabilities/Memory/Services/CacheEviction';
import { SDKLogger } from '../Logging/Logger/SDKLogger';
import { FileManager } from '../FileOperations/FileManager';
import { DownloadServiceImpl } from '../../Data/Network/Services/DownloadService';
import { SyncCoordinator } from '../../Data/Sync/SyncCoordinator';
import { ConfigurationService } from '../Configuration/ConfigurationService';
import { AnalyticsQueueManager } from '../Analytics/AnalyticsQueueManager';
import { ModelInfoService } from '../../Data/Services/ModelInfoService';
import { ModelInfoRepositoryImpl } from '../../Data/Repositories/ModelInfoRepository';
import type { ModelRegistry } from '../../Core/Protocols/Registry/ModelRegistry';
import type { MemoryManager } from '../../Core/Protocols/Memory/MemoryManager';
import type { DownloadService } from '../../Data/Network/Services/DownloadService';
import { AdapterRegistry } from './AdapterRegistry';

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
      this._routingService = new RoutingService(costCalculator, resourceChecker);
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
   * Voice capability service
   */
  private _voiceCapabilityService?: any;
  public get voiceCapabilityService(): any {
    if (!this._voiceCapabilityService) {
      // VoiceCapabilityService - to be implemented
      this._voiceCapabilityService = {
        initialize: async () => {},
      };
    }
    return this._voiceCapabilityService;
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

  /**
   * Storage analyzer for storage operations
   */
  private _storageAnalyzer?: any;
  public get storageAnalyzer(): any {
    if (!this._storageAnalyzer) {
      // StorageAnalyzer - to be implemented
      this._storageAnalyzer = {
        analyze: async () => ({}),
      };
    }
    return this._storageAnalyzer;
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
   */
  private _memoryService?: MemoryManager;
  public get memoryService(): MemoryManager {
    if (!this._memoryService) {
      const allocationManager = new AllocationManager();
      const pressureHandler = new PressureHandler();
      const cacheEviction = new CacheEviction();
      this._memoryService = new MemoryService(
        allocationManager,
        pressureHandler,
        cacheEviction
      );
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
   * Database manager
   */
  private _databaseManager?: any;
  private get databaseManager(): any {
    if (!this._databaseManager) {
      // DatabaseManager - to be implemented (would use SQLite or similar)
      this._databaseManager = {
        initialize: async () => {},
      };
    }
    return this._databaseManager;
  }

  /**
   * Network service (environment-based: mock or real)
   */
  public networkService?: any;

  /**
   * Authentication service
   */
  public authenticationService?: any;

  /**
   * API client for sync operations
   */
  private apiClient?: any;

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
   * Telemetry service
   */
  private _telemetryService?: any;
  public async getTelemetryService(): Promise<any> {
    if (!this._telemetryService) {
      // TelemetryService - to be implemented
      this._telemetryService = {
        record: async (event: any) => {},
      };
    }
    return this._telemetryService;
  }

  /**
   * Model info service
   */
  private _modelInfoService?: ModelInfoService;
  public async getModelInfoService(): Promise<ModelInfoService> {
    if (!this._modelInfoService) {
      const repository = new ModelInfoRepositoryImpl();
      const syncCoordinator = await this.getSyncCoordinator();
      this._modelInfoService = new ModelInfoService(repository, syncCoordinator);
    }
    return this._modelInfoService;
  }

  /**
   * Device info service
   */
  private _deviceInfoService?: any;
  public async getDeviceInfoService(): Promise<any> {
    if (!this._deviceInfoService) {
      // DeviceInfoService - to be implemented
      this._deviceInfoService = {
        loadCurrentDeviceInfo: async () => null,
        syncToCloud: async () => {},
        getDeviceInfoSummary: async () => '',
      };
    }
    return this._deviceInfoService;
  }

  /**
   * Analytics queue manager - centralized queue for all analytics
   */
  public get analyticsQueueManager(): AnalyticsQueueManager {
    return AnalyticsQueueManager.shared;
  }

  /**
   * Generation analytics service
   */
  private _generationAnalytics?: any;
  public async getGenerationAnalytics(): Promise<any> {
    if (!this._generationAnalytics) {
      // GenerationAnalyticsService - to be implemented
      this._generationAnalytics = {
        record: async (event: any) => {},
      };
    }
    return this._generationAnalytics;
  }

  /**
   * STT Analytics Service
   */
  private _sttAnalytics?: any;
  public async getSTTAnalytics(): Promise<any> {
    if (!this._sttAnalytics) {
      // STTAnalyticsService - to be implemented
      this._sttAnalytics = {
        record: async (event: any) => {},
      };
    }
    return this._sttAnalytics;
  }

  /**
   * Voice Analytics Service
   */
  private _voiceAnalytics?: any;
  public async getVoiceAnalytics(): Promise<any> {
    if (!this._voiceAnalytics) {
      // VoiceAnalyticsService - to be implemented
      this._voiceAnalytics = {
        record: async (event: any) => {},
      };
    }
    return this._voiceAnalytics;
  }

  /**
   * TTS Analytics Service
   */
  private _ttsAnalytics?: any;
  public async getTTSAnalytics(): Promise<any> {
    if (!this._ttsAnalytics) {
      // TTSAnalyticsService - to be implemented
      this._ttsAnalytics = {
        record: async (event: any) => {},
      };
    }
    return this._ttsAnalytics;
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
   * Reset service container state (for testing)
   */
  public reset(): void {
    this.authenticationService = undefined;
    this.apiClient = undefined;
    this.networkService = undefined;
    this._syncCoordinator = undefined;
    this._configurationService = undefined;
    this._telemetryService = undefined;
    this._modelInfoService = undefined;
    this._deviceInfoService = undefined;
    this._generationAnalytics = undefined;
    this._sttAnalytics = undefined;
    this._voiceAnalytics = undefined;
    this._ttsAnalytics = undefined;
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
