# Service Container & DI Comparison

## Executive Summary

This document provides a comprehensive comparison between the iOS and Kotlin Multiplatform (KMP) service container implementations for the RunAnywhere SDK. Both implementations share a similar architectural philosophy but differ significantly in their approach to dependency injection, service scoping, and lifecycle management.

## iOS Implementation

### Container Structure

The iOS ServiceContainer follows a **singleton pattern** with lazy initialization:

```swift
public class ServiceContainer {
    public static let shared: ServiceContainer = ServiceContainer()

    // Core services with lazy initialization
    private(set) lazy var modelRegistry: ModelRegistry = {
        RegistryService()
    }()

    private(set) lazy var generationService: GenerationService = {
        GenerationService(
            routingService: routingService,
            modelLoadingService: modelLoadingService
        )
    }()
}
```

**Key architectural features:**
- **Singleton pattern**: Global shared instance
- **Lazy initialization**: Services created on first access
- **Dependency graph**: Clear service dependencies through constructors
- **Memory management**: Careful cleanup with optional service references

### Service Registration

#### Core Services (Built-in)
```swift
// Services registered automatically at container initialization
- modelRegistry: ModelRegistry (RegistryService)
- adapterRegistry: AdapterRegistry (internal)
- modelLoadingService: ModelLoadingService
- generationService: GenerationService
- streamingService: StreamingService
- voiceCapabilityService: VoiceCapabilityService
- downloadService: AlamofireDownloadService
- fileManager: SimplifiedFileManager
- storageAnalyzer: StorageAnalyzer
- routingService: RoutingService
- hardwareManager: HardwareCapabilityManager
- memoryService: MemoryManager
- logger: SDKLogger
- databaseManager: DatabaseManager
```

#### Dynamic Services (Environment-dependent)
```swift
// Async properties for data services
public var configurationService: ConfigurationServiceProtocol { get async }
public var telemetryService: TelemetryService { get async }
public var modelInfoService: ModelInfoService { get async }
public var deviceInfoService: DeviceInfoService { get async }
```

#### External Module Registration
```swift
// Through ModuleRegistry (separate from ServiceContainer)
ModuleRegistry.shared.registerSTT(WhisperSTTProvider())
ModuleRegistry.shared.registerLLM(LlamaProvider())
ModuleRegistry.shared.registerSpeakerDiarization(FluidAudioProvider())
```

### Resolution Mechanism

1. **Direct Property Access**: Core services accessed through lazy properties
2. **Async Resolution**: Data services resolved asynchronously with dependency injection
3. **ModuleRegistry Lookup**: External services resolved through provider pattern

```swift
// Core service access
let modelManager = serviceContainer.modelLoadingService

// Async service access
let configService = await serviceContainer.configurationService

// External service access
let sttProvider = ModuleRegistry.shared.sttProvider(for: modelId)
```

### Lifecycle Management

#### ServiceLifecycle Class
```swift
public class ServiceLifecycle {
    private var services: [String: LifecycleAware] = [:]
    private var startedServices: Set<String> = []

    public func startAll() async throws { ... }
    public func stopAll() async throws { ... }
    public func restart(_ name: String) async throws { ... }
}
```

#### Bootstrap Process (8-step initialization)
```swift
public func bootstrap(with params: SDKInitParams, authService: AuthenticationService, apiClient: APIClient) async throws -> ConfigurationData {
    // Step 1: Network services configuration
    // Step 2: Device information collection & sync
    // Step 3: Configuration service initialization
    // Step 4: Model catalog sync
    // Step 5: Model registry initialization
    // Step 6: Memory management configuration
    // Step 7: Voice services initialization (optional)
    // Step 8: Analytics initialization
}
```

### Scoping

- **Singleton Scope**: All services are singletons within the container
- **Lazy Scope**: Services created on first access
- **Async Scope**: Data services with async initialization
- **Optional Scope**: Some services (like voice) are optional and may fail gracefully

## KMP Implementation

### Common Implementation

The KMP ServiceContainer uses a similar singleton pattern but with expect/actual for platform-specific implementations:

```kotlin
class ServiceContainer {
    companion object {
        val shared = ServiceContainer()
    }

    // Platform abstractions
    internal val fileSystem by lazy { createFileSystem() }
    private val httpClient by lazy { createHttpClient() }
    private val secureStorage by lazy { createSecureStorage() }
}
```

**Key architectural features:**
- **Singleton pattern**: Global shared instance
- **Expect/Actual pattern**: Platform-specific implementations
- **Lazy initialization**: Services created on first access
- **Simple dependency graph**: Less complex than iOS implementation

### Service Registration

#### Core Services (Built-in)
```kotlin
// Services registered automatically
val modelInfoRepository: ModelInfoRepository by lazy { ModelInfoRepositoryImpl() }
val modelInfoService: ModelInfoService by lazy { ModelInfoService(...) }
val vadComponent: VADComponent by lazy { VADComponent(VADConfiguration()) }
val sttComponent: STTComponent by lazy { STTComponent(STTConfiguration(...)) }
val authenticationService: AuthenticationService by lazy { AuthenticationService(...) }
val validationService: ValidationService by lazy { ValidationService(fileSystem) }
val downloadService: DownloadService by lazy { SimpleDownloadService(fileSystem) }
val modelManager: ModelManager by lazy { ModelManager(fileSystem, downloadService) }
val generationService: GenerationService by lazy { GenerationService() }
val streamingService: StreamingService by lazy { StreamingService() }
val memoryService: MemoryService by lazy { MemoryService() }
val syncCoordinator: SyncCoordinator by lazy { SyncCoordinator() }
```

#### Platform-Specific Services
```kotlin
// Platform-specific through expect/actual
val telemetryRepository: TelemetryRepository by lazy { createTelemetryRepository() }

// Android implementation
actual fun createTelemetryRepository(): TelemetryRepository {
    val database = InMemoryDatabase.getInstance()
    val networkService = NetworkServiceFactory.create(...)
    return TelemetryRepositoryImpl(database, networkService)
}

// JVM implementation
actual fun createTelemetryRepository(): TelemetryRepository {
    return TelemetryRepositoryImpl()
}
```

#### External Module Registration
```kotlin
// Through ModuleRegistry (similar to iOS)
ModuleRegistry.registerSTT(WhisperSTTProvider())
ModuleRegistry.registerVAD(SimpleEnergyVADProvider())
ModuleRegistry.registerLLM(LlamaProvider())
```

### Resolution Mechanism

1. **Direct Property Access**: All services accessed through lazy properties
2. **Platform Resolution**: Platform-specific services through expect/actual
3. **ModuleRegistry Lookup**: External services through provider pattern

```kotlin
// Direct service access
val modelManager = ServiceContainer.shared.modelManager

// Platform-specific service access
val telemetryRepo = ServiceContainer.shared.telemetryRepository

// External service access
val sttProvider = ModuleRegistry.sttProvider(modelId)
```

### Lifecycle Management

#### Bootstrap Process (8-step initialization matching iOS)
```kotlin
suspend fun bootstrap(params: SDKInitParams): ConfigurationData {
    // Step 1: Platform initialization & device info collection
    // Step 2: Configuration loading
    // Step 3: Authentication service initialization
    // Step 4: Model repository sync
    // Step 5: Analytics service setup
    // Step 6: Component initialization
    // Step 7: Cache warmup
    // Step 8: Health check
}
```

#### Component Initialization
```kotlin
private suspend fun initializeComponents() {
    vadComponent.initialize()
    if (ModuleRegistry.hasSTT) {
        sttComponent.initialize()
    }
}
```

### Platform-Specific Implementations

#### Android
- **Context-aware initialization**: `PlatformContext(context: Context)`
- **Database integration**: Room database support (currently using InMemoryDatabase)
- **Android-specific services**: Storage and network services

#### JVM
- **Working directory management**: System property-based configuration
- **Simplified services**: Reduced platform-specific dependencies
- **Desktop support**: File system and basic networking

## Gaps and Misalignments

### 1. Service Coverage Differences

| Service Type | iOS Implementation | KMP Implementation | Gap |
|--------------|-------------------|-------------------|-----|
| **AdapterRegistry** | ✅ Comprehensive framework adapter registry | ❌ Missing | **MAJOR GAP** |
| **Hardware Manager** | ✅ HardwareCapabilityManager | ❌ Missing | **MAJOR GAP** |
| **Storage Analyzer** | ✅ DefaultStorageAnalyzer | ❌ Missing | **MAJOR GAP** |
| **Routing Service** | ✅ RoutingService with cost calculation | ❌ Missing | **MAJOR GAP** |
| **Database Manager** | ✅ DatabaseManager with GRDB | ✅ InMemoryDatabase (simplified) | **PARTIAL GAP** |
| **Voice Capability** | ✅ VoiceCapabilityService | ❌ Missing | **MAJOR GAP** |
| **Analytics Queue** | ✅ AnalyticsQueueManager | ❌ Missing | **MODERATE GAP** |
| **Keychain Manager** | ✅ KeychainManager | ✅ SecureStorage (abstracted) | **ALIGNED** |

### 2. Lifecycle Management Gaps

| Aspect | iOS | KMP | Gap |
|--------|-----|-----|-----|
| **ServiceLifecycle** | ✅ Dedicated ServiceLifecycle class | ❌ Manual component lifecycle | **MAJOR GAP** |
| **LifecycleAware Protocol** | ✅ start()/stop() protocol | ❌ No standard lifecycle interface | **MAJOR GAP** |
| **Graceful Shutdown** | ✅ Reverse order shutdown | ✅ Basic cleanup() | **MODERATE GAP** |
| **Service Dependencies** | ✅ Complex dependency graph | ✅ Simple dependencies | **MODERATE GAP** |

### 3. Scoping and Resolution Gaps

| Feature | iOS | KMP | Gap |
|---------|-----|-----|-----|
| **Async Services** | ✅ `get async` for data services | ❌ All synchronous lazy | **MAJOR GAP** |
| **Memory Management** | ✅ Weak references, cleanup | ✅ Basic cleanup | **MODERATE GAP** |
| **Service Factory** | ✅ NetworkServiceFactory pattern | ✅ Basic factory functions | **MINOR GAP** |
| **Environment Switching** | ✅ Environment-based service creation | ✅ Basic environment support | **MINOR GAP** |

### 4. Platform Integration Gaps

| Platform Feature | iOS | KMP | Gap |
|------------------|-----|-----|-----|
| **Database Integration** | ✅ Full GRDB integration | ✅ Room (placeholder) | **MODERATE GAP** |
| **Network Service** | ✅ Alamofire integration | ✅ Platform HTTP clients | **MINOR GAP** |
| **File Management** | ✅ SimplifiedFileManager | ✅ Platform file systems | **ALIGNED** |
| **Secure Storage** | ✅ Keychain integration | ✅ Platform secure storage | **ALIGNED** |

### 5. Module Registration Gaps

| Feature | iOS | KMP | Gap |
|---------|-----|-----|-----|
| **Provider Types** | STT, LLM, SpeakerDiarization, VLM, WakeWord | STT, VAD, LLM, TTS, VLM, WakeWord, SpeakerDiarization | **KMP HAS MORE** |
| **MainActor Threading** | ✅ `@MainActor` for thread safety | ❌ No thread safety | **MODERATE GAP** |
| **Auto-Registration** | ✅ AutoRegisteringModule protocol | ✅ AutoRegisteringModule interface | **ALIGNED** |

## Recommendations to Address Gaps

### 1. Service Container Alignment

#### Add Missing Core Services to KMP
```kotlin
// Add to ServiceContainer.kt
val adapterRegistry: AdapterRegistry by lazy { AdapterRegistry() }
val hardwareManager: HardwareManager by lazy { createHardwareManager() }
val storageAnalyzer: StorageAnalyzer by lazy { DefaultStorageAnalyzer(fileSystem, modelRegistry) }
val routingService: RoutingService by lazy {
    RoutingService(costCalculator = CostCalculator(), resourceChecker = ResourceChecker(hardwareManager))
}
val voiceCapabilityService: VoiceCapabilityService by lazy { VoiceCapabilityService() }
val analyticsQueueManager: AnalyticsQueueManager by lazy { AnalyticsQueueManager.shared }
```

#### Implement AdapterRegistry
```kotlin
// New file: AdapterRegistry.kt
class AdapterRegistry {
    private var adapters: MutableMap<LLMFramework, UnifiedFrameworkAdapter> = mutableMapOf()

    fun register(adapter: UnifiedFrameworkAdapter) { ... }
    fun getAdapter(for: LLMFramework): UnifiedFrameworkAdapter? { ... }
    fun findBestAdapter(for: ModelInfo): UnifiedFrameworkAdapter? { ... }
}
```

### 2. Lifecycle Management Enhancement

#### Add ServiceLifecycle to KMP
```kotlin
// New file: ServiceLifecycle.kt
interface LifecycleAware {
    suspend fun start()
    suspend fun stop()
}

class ServiceLifecycle {
    private val services = mutableMapOf<String, LifecycleAware>()
    private val startedServices = mutableSetOf<String>()

    fun register(service: LifecycleAware, name: String) { ... }
    suspend fun startAll() { ... }
    suspend fun stopAll() { ... }
}
```

#### Integrate with ServiceContainer
```kotlin
class ServiceContainer {
    val serviceLifecycle: ServiceLifecycle by lazy { ServiceLifecycle() }

    suspend fun cleanup() {
        serviceLifecycle.stopAll()
        // existing cleanup...
    }
}
```

### 3. Async Service Resolution

#### Add Async Service Support
```kotlin
// Modify ServiceContainer.kt
class ServiceContainer {
    private var _configurationService: ConfigurationService? = null
    val configurationService: ConfigurationService
        get() = runBlocking {
            if (_configurationService == null) {
                _configurationService = createConfigurationService()
            }
            _configurationService!!
        }

    suspend fun getConfigurationServiceAsync(): ConfigurationService {
        if (_configurationService == null) {
            _configurationService = createConfigurationService()
        }
        return _configurationService!!
    }
}
```

### 4. Platform-Specific Enhancements

#### Android Platform
```kotlin
// Enhanced Android implementation
actual class PlatformContext(private val context: Context) {
    actual fun initialize() {
        AndroidPlatformContext.initialize(context)
        // Initialize Android-specific services
        DatabaseManager.initialize(context)
        HardwareManager.initialize(context)
    }
}
```

#### JVM Platform
```kotlin
// Enhanced JVM implementation
actual class PlatformContext(
    private val workingDirectory: String = System.getProperty("user.dir")
) {
    actual fun initialize() {
        System.setProperty("runanywhere.workdir", workingDirectory)
        // Initialize JVM-specific services
        HardwareManager.initialize()
        DatabaseManager.initialize(workingDirectory)
    }
}
```

### 5. Thread Safety Improvements

#### Add Thread Safety to ModuleRegistry
```kotlin
object ModuleRegistry {
    private val mutex = Mutex()

    suspend fun registerSTT(provider: STTServiceProvider) {
        mutex.withLock {
            sttProviders.add(provider)
            logger.info("Registered STT provider: ${provider.name}")
        }
    }

    suspend fun sttProvider(modelId: String? = null): STTServiceProvider? {
        return mutex.withLock {
            if (modelId != null) {
                sttProviders.firstOrNull { it.canHandle(modelId) }
            } else {
                sttProviders.firstOrNull()
            }
        }
    }
}
```

### 6. Memory Management Enhancement

#### Add Weak Reference Support
```kotlin
// Add to ServiceContainer.kt
class ServiceContainer {
    // Use WeakReference where appropriate
    private var _configurationServiceRef: WeakReference<ConfigurationService>? = null

    val configurationService: ConfigurationService
        get() {
            _configurationServiceRef?.get()?.let { return it }
            val service = createConfigurationService()
            _configurationServiceRef = WeakReference(service)
            return service
        }
}
```

## Implementation Priority

### Phase 1 (Critical - Immediate)
1. **AdapterRegistry**: Essential for framework management
2. **ServiceLifecycle**: Critical for proper service management
3. **HardwareManager**: Required for routing decisions
4. **RoutingService**: Core to the platform's value proposition

### Phase 2 (Important - Short term)
1. **VoiceCapabilityService**: For voice feature parity
2. **StorageAnalyzer**: For storage management
3. **Async Service Resolution**: For better lifecycle management
4. **Thread Safety**: For production reliability

### Phase 3 (Enhancement - Medium term)
1. **AnalyticsQueueManager**: For better analytics
2. **Enhanced Database Integration**: For full Room support
3. **Memory Management**: For optimization
4. **Platform-specific Enhancements**: For better platform integration

## Conclusion

While both service containers share a similar architectural philosophy, the iOS implementation is significantly more mature and comprehensive. The KMP implementation requires substantial enhancement to achieve feature parity, particularly in:

1. **Core Service Coverage**: Missing critical services like AdapterRegistry, HardwareManager, RoutingService
2. **Lifecycle Management**: Lacking structured lifecycle management
3. **Async Resolution**: Missing async service resolution patterns
4. **Thread Safety**: Insufficient concurrency protection

The recommended implementation approach should prioritize the critical gaps first, ensuring that core functionality is aligned before addressing enhancement features. The modular architecture allows for incremental implementation without breaking existing functionality.
