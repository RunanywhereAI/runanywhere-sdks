import '../../core/protocols/frameworks/unified_framework_adapter.dart';
import '../../capabilities/text_generation/services/generation_service.dart';
import '../../capabilities/model_loading/services/model_loading_service.dart';
import '../../capabilities/voice/services/voice_capability_service.dart';
import '../../capabilities/text_generation/services/streaming_service.dart';
import '../../core/service_registry/unified_service_registry.dart';
import '../../core/protocols/registry/model_registry.dart' as protocol;
import '../../core/protocols/registry/model_registry_impl.dart';
import '../../data/services/authentication_service.dart';
import '../../data/network/services/api_client.dart';
import '../../data/network/services/api_client_impl.dart';
import '../logging/logger/sdk_logger.dart';
import '../../public/models/configuration/sdk_init_params.dart';

/// Service Container for dependency injection
/// Similar to Swift SDK's ServiceContainer
class ServiceContainer {
  static final ServiceContainer shared = ServiceContainer._();
  ServiceContainer._();

  final _logger = SDKLogger(category: 'ServiceContainer');

  // Core Services
  late final UnifiedServiceRegistry _serviceRegistry = UnifiedServiceRegistry();
  late final protocol.ModelRegistry _modelRegistry = ModelRegistryImpl();

  // Capability Services
  late final GenerationService _generationService = GenerationService(
    serviceRegistry: _serviceRegistry,
  );

  late final ModelLoadingService _modelLoadingService = ModelLoadingService(
    modelRegistry: _modelRegistry,
    serviceRegistry: _serviceRegistry,
  );

  late final VoiceCapabilityService _voiceCapabilityService =
      VoiceCapabilityService(serviceRegistry: _serviceRegistry);

  late final StreamingService _streamingService = StreamingService(
    generationService: _generationService,
  );

  // Network Services (lazy initialization)
  AuthenticationService? _authenticationService;
  APIClient? _apiClient;

  // Getters
  GenerationService get generationService => _generationService;
  ModelLoadingService get modelLoadingService => _modelLoadingService;
  VoiceCapabilityService get voiceCapabilityService => _voiceCapabilityService;
  StreamingService get streamingService => _streamingService;
  UnifiedServiceRegistry get serviceRegistry => _serviceRegistry;
  protocol.ModelRegistry get modelRegistry => _modelRegistry;
  AuthenticationService? get authenticationService => _authenticationService;
  APIClient? get apiClient => _apiClient;

  /// Setup local services (no network calls)
  Future<void> setupLocalServices(SDKInitParams params) async {
    _logger.info('Setting up local services...');

    // Initialize local services only
    // Network services will be initialized lazily when needed

    _logger.info('✅ Local services setup completed');
  }

  /// Initialize network services
  Future<void> initializeNetworkServices(SDKInitParams params) async {
    _logger.info('Initializing network services...');

    _apiClient ??= APIClientImpl(
      baseURL: params.baseURL,
      apiKey: params.apiKey,
    );

    _authenticationService ??= AuthenticationService(apiClient: _apiClient!);

    _logger.info('✅ Network services initialized');
  }

  /// Register a framework adapter
  void registerAdapter(UnifiedFrameworkAdapter adapter, {int priority = 100}) {
    _serviceRegistry.registerAdapter(adapter, priority: priority);
  }

  /// Reset the service container (for testing)
  void reset() {
    _authenticationService = null;
    _apiClient = null;
    _logger.info('Service container reset');
  }
}
