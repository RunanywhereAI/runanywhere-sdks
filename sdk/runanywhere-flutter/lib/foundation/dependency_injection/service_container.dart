import 'dart:async';
import '../../capabilities/registry/registry_service.dart';
import '../../capabilities/model_loading/model_loading_service.dart';
import '../../capabilities/text_generation/generation_service.dart';
import '../../capabilities/streaming/streaming_service.dart';
import '../../capabilities/voice/voice_capability_service.dart';
import '../../capabilities/routing/routing_service.dart';
import '../../capabilities/memory/memory_service.dart';
import '../../capabilities/memory/allocation_manager.dart';
import '../../capabilities/memory/pressure_handler.dart';
import '../../capabilities/memory/cache_eviction.dart';
import '../../capabilities/download/download_service.dart';
import '../../capabilities/analytics/analytics_service.dart';
import '../../foundation/logging/sdk_logger.dart';
import '../../public/configuration/sdk_environment.dart';
import '../../core/service_registry/unified_service_registry.dart';
import '../../core/protocols/frameworks/unified_framework_adapter.dart';
import '../../core/models/model/model_registration.dart';

/// Service container for dependency injection
/// Matches iOS ServiceContainer from Foundation/DependencyInjection/ServiceContainer.swift
class ServiceContainer {
  /// Shared instance
  static final ServiceContainer shared = ServiceContainer._();

  ServiceContainer._();

  // Core services (lazy initialization)
  RegistryService? _modelRegistry;
  ModelLoadingService? _modelLoadingService;
  GenerationService? _generationService;
  StreamingService? _streamingService;
  VoiceCapabilityService? _voiceCapabilityService;
  RoutingService? _routingService;
  MemoryService? _memoryService;
  DownloadService? _downloadService;
  AnalyticsService? _analyticsService;
  HardwareCapabilityManager? _hardwareManager;
  SDKLogger? _logger;

  /// Single adapter registry for all frameworks (text and voice)
  /// Matches iOS adapterRegistry pattern
  final UnifiedServiceRegistry _adapterRegistry = UnifiedServiceRegistry();

  /// Public access to adapter registry
  UnifiedServiceRegistry get adapterRegistry => _adapterRegistry;

  // Internal state
  SDKInitParams? _initParams;

  /// Model registry
  RegistryService get modelRegistry {
    return _modelRegistry ??= RegistryService();
  }

  /// Model loading service
  ModelLoadingService get modelLoadingService {
    return _modelLoadingService ??= ModelLoadingService(
      registry: modelRegistry,
      adapterRegistry: _adapterRegistry,
      memoryService: memoryService,
    );
  }

  /// Generation service
  GenerationService get generationService {
    return _generationService ??= GenerationService(
      routingService: routingService,
      modelLoadingService: modelLoadingService,
    );
  }

  /// Streaming service
  StreamingService get streamingService {
    return _streamingService ??= StreamingService(
      generationService: generationService,
      modelLoadingService: modelLoadingService,
    );
  }

  /// Voice capability service
  VoiceCapabilityService get voiceCapabilityService {
    return _voiceCapabilityService ??= VoiceCapabilityService();
  }

  /// Routing service
  RoutingService get routingService {
    return _routingService ??= RoutingService(
      costCalculator: CostCalculator(),
      resourceChecker: ResourceChecker(hardwareManager: hardwareManager),
    );
  }

  /// Memory service
  MemoryService get memoryService {
    return _memoryService ??= MemoryService(
      allocationManager: AllocationManager(),
      pressureHandler: PressureHandler(),
      cacheEviction: CacheEviction(),
    );
  }

  /// Download service
  DownloadService get downloadService {
    return _downloadService ??= DownloadService(
      modelRegistry: modelRegistry,
    );
  }

  /// Analytics service
  AnalyticsService get analyticsService {
    return _analyticsService ??= AnalyticsService(
      initParams: _initParams,
    );
  }

  /// Hardware manager
  HardwareCapabilityManager get hardwareManager {
    return _hardwareManager ??= HardwareCapabilityManager.shared;
  }

  /// Logger
  SDKLogger get logger {
    return _logger ??= SDKLogger();
  }

  /// Setup local services (no network calls)
  Future<void> setupLocalServices({
    required String apiKey,
    required Uri baseURL,
    required SDKEnvironment environment,
  }) async {
    // Store init params for analytics
    _initParams = SDKInitParams(
      apiKey: apiKey,
      baseURL: baseURL,
      environment: environment,
    );

    // Initialize local services only
    // Network services are initialized lazily on first API call
    await modelRegistry.initialize(apiKey: apiKey);
  }

  /// Initialize network services
  Future<void> initializeNetworkServices({
    required String apiKey,
    required Uri baseURL,
  }) async {
    // Initialize network services for production mode
  }

  /// Register a framework adapter with optional priority
  /// Higher priority adapters are preferred when multiple can handle the same model
  /// Matches iOS RunAnywhere.registerFrameworkAdapter pattern
  void registerFrameworkAdapter(UnifiedFrameworkAdapter adapter,
      {int priority = 100}) {
    _adapterRegistry.register(adapter, priority: priority);

    // Call adapter's onRegistration callback
    adapter.onRegistration();

    // Register download strategy if adapter provides one
    final downloadStrategy = adapter.getDownloadStrategy();
    if (downloadStrategy != null) {
      downloadService.registerStrategy(downloadStrategy);
      logger.info(
          'Registered download strategy for ${adapter.framework.displayName}');
    }

    // Register any models provided by the adapter
    final providedModels = adapter.getProvidedModels();
    for (final model in providedModels) {
      modelRegistry.registerModel(model);
    }

    logger
        .info('Registered framework adapter: ${adapter.framework.displayName}');
  }

  /// Register a framework adapter with models
  /// Matches iOS RunAnywhere.registerFramework pattern
  Future<void> registerFramework(
    UnifiedFrameworkAdapter adapter, {
    List<ModelRegistration>? models,
    int priority = 100,
  }) async {
    // Register the adapter
    registerFrameworkAdapter(adapter, priority: priority);

    // Register provided models
    if (models != null) {
      for (final registration in models) {
        final modelInfo = registration.toModelInfo();
        modelRegistry.registerModel(modelInfo);
        logger.info('Registered model: ${modelInfo.name} (${modelInfo.id})');
      }
    }
  }

  /// Reset all services (for testing)
  void reset() {
    _modelRegistry = null;
    _modelLoadingService = null;
    _generationService = null;
    _streamingService = null;
    _voiceCapabilityService = null;
    _routingService = null;
    _memoryService = null;
    _hardwareManager = null;
    _logger = null;
    _initParams = null;
  }
}

/// Hardware capability manager placeholder
class HardwareCapabilityManager {
  static final HardwareCapabilityManager shared = HardwareCapabilityManager._();
  HardwareCapabilityManager._();
}

/// Placeholder classes for routing
class CostCalculator {}

class ResourceChecker {
  final HardwareCapabilityManager hardwareManager;
  ResourceChecker({required this.hardwareManager});
}
