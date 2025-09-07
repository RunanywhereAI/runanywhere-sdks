# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

### Before starting work
- Always in plan mode to make a plan refer to `thoughts/shared/plans/{descriptive_name}.md`.
- After get the plan, make sure you Write the plan to the appropriate file as mentioned in the guide that you referred to.
- If the task require external knowledge or certain package, also research to get latest knowledge (Use Task tool for research)
- Don't over plan it, always think MVP.
- Once you write the plan, firstly ask me to review it. Do not continue until I approve the plan.
### While implementing
- You should update the plan as you work - check `thoughts/shared/plans/{descriptive_name}.md` if you're running an already created plan via `thoughts/shared/plans/{descriptive_name}.md`
- After you complete tasks in the plan, you should update and append detailed descriptions of the changes you made, so following tasks can be easily hand over to other engineers.
- Always make sure that you're using structured types, never use strings directly so that we can keep things consistent and scalable and not make mistakes.
- Read files FULLY to understand the FULL context. Only use tools when the file is large and you are short on context.
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
- When fixing issues focus on SIMPLICITY, and following Clean SOLID principles, do not add complicated logic unless necessary!
- When looking up something: It's September 2025 FYI

## Swift specific rules:
- Use the latest Swift 6 APIs always.
- Do not use NSLock as it is outdated.

## Repository Overview

This repository contains cross-platform SDKs for the RunAnywhere on-device AI platform. The platform provides intelligent routing between on-device and cloud AI models to optimize for cost and privacy.

### SDK Implementations
- **Kotlin Multiplatform SDK** (`sdk/runanywhere-kotlin/`) - Cross-platform SDK supporting JVM, Android, and Native platforms
- **Android SDK** (`sdk/runanywhere-android/`) - Kotlin-based SDK for Android
- **iOS SDK** (`sdk/runanywhere-swift/`) - Swift Package Manager-based SDK for iOS/macOS/tvOS/watchOS

### Example Applications
- **Android Demo** (`examples/android/RunAnywhereAI/`) - Sample Android app demonstrating SDK usage
- **iOS Demo** (`examples/ios/RunAnywhereAI/`) - Sample iOS app demonstrating SDK usage
- **IntelliJ Plugin Demo** (`examples/intellij-plugin-demo/`) - IntelliJ/Android Studio plugin for voice features

## Common Development Commands

### Kotlin Multiplatform SDK Development

```bash
# Navigate to Kotlin SDK
cd sdk/runanywhere-kotlin/

# Build Commands (using scripts/sdk.sh)
./scripts/sdk.sh build            # Build all platforms (JVM and Android)
./scripts/sdk.sh build-all        # Same as 'build' - builds all targets
./scripts/sdk.sh build-all --clean # Clean before building (removes build directories)
./scripts/sdk.sh build-all --deep-clean # Deep clean including Gradle caches
./scripts/sdk.sh build-all --no-clean   # Build without any cleanup (default)

# Individual Platform Builds
./scripts/sdk.sh jvm              # Build JVM JAR only
./scripts/sdk.sh android          # Build Android AAR only
./scripts/sdk.sh common           # Compile common module only

# Testing
./scripts/sdk.sh test             # Run all tests
./scripts/sdk.sh test-jvm         # Run JVM tests
./scripts/sdk.sh test-android     # Run Android tests

# Publishing
./scripts/sdk.sh publish          # Publish to Maven Local (~/.m2/repository)
./scripts/sdk.sh publish-local    # Same as 'publish'

# Cleanup Options
./scripts/sdk.sh clean            # Clean build directories
./scripts/sdk.sh deep-clean       # Clean build dirs and Gradle caches

# Help and Info
./scripts/sdk.sh help             # Show all available commands
./scripts/sdk.sh --help           # Same as 'help'

# Direct Gradle Commands (Alternative)
./gradlew build                   # Build all targets
./gradlew jvmJar                  # Build JVM JAR
./gradlew assembleDebug           # Build Android Debug AAR
./gradlew assembleRelease         # Build Android Release AAR
./gradlew clean                   # Clean build directories
./gradlew publishToMavenLocal     # Publish to local Maven
```

#### Build Script Features

The `scripts/sdk.sh` script provides:
- **Automatic cleanup options**: `--clean`, `--deep-clean`, `--no-clean` flags
- **Build verification**: Checks for successful JAR and AAR creation
- **Error handling**: Continues building other targets if one fails
- **Progress indicators**: Clear output showing build status
- **Flexible commands**: Support for multiple build scenarios

#### Build Output Locations

After a successful build:
- **JVM JAR**: `build/libs/RunAnywhereKotlinSDK-jvm-0.1.0.jar`
- **Android AAR**: `build/outputs/aar/RunAnywhereKotlinSDK-debug.aar`
- **Maven Local**: `~/.m2/repository/com/runanywhere/sdk/`

### Android SDK Development

```bash
# Navigate to Android SDK
cd sdk/runanywhere-android/

# Build the SDK
./gradlew build

# Run lint checks
./gradlew lint

# Run tests
./gradlew test

# Clean build
./gradlew clean

# Build release AAR
./gradlew assembleRelease
```

### iOS SDK Development

```bash
# Navigate to iOS SDK
cd sdk/runanywhere-swift/

# Build the SDK
swift build

# Run tests
swift test

# Run tests with coverage
swift test --enable-code-coverage

# Run SwiftLint
swiftlint

# Build for specific platform
xcodebuild build -scheme RunAnywhere -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Android Example App

```bash
# Navigate to Android example
cd examples/android/RunAnywhereAI/

# Build the app
./gradlew build

# Run lint
./gradlew :app:lint

# Install on device/emulator
./gradlew installDebug

# Run tests
./gradlew test
```

### iOS Example App

To get logs for sample app and sdk use this in another terminal:
```bash
log stream --predicate 'subsystem CONTAINS "com.runanywhere"' --info --debug
```

For physical device:
```bash
idevicesyslog | grep "com.runanywhere"
```

#### Quick Build & Run (Recommended)
```bash
# Navigate to iOS example
cd examples/ios/RunAnywhereAI/

# Build and run on simulator (handles dependencies automatically)
./scripts/build_and_run.sh simulator "iPhone 16 Pro" --build-sdk

# Build and run on connected device
./scripts/build_and_run.sh device

# Clean build artifacts
./scripts/clean_build_and_run.sh
```

#### Manual Setup
```bash
# Install CocoaPods dependencies (required for TensorFlow Lite and ZIPFoundation)
pod install

# Fix Xcode 16 sandbox issues (required after pod install)
./fix_pods_sandbox.sh

# After pod install, always open the .xcworkspace file
open RunAnywhereAI.xcworkspace

# Run SwiftLint
./swiftlint.sh

# Verify model download URLs
./scripts/verify_urls.sh
```

#### Known Issues - Xcode 16 Sandbox
**Error**: `Sandbox: rsync deny(1) file-write-create`
**Fix**: After `pod install`, run `./fix_pods_sandbox.sh`

### Pre-commit Hooks

```bash
# Run all pre-commit checks
pre-commit run --all-files

# Run specific checks
pre-commit run android-sdk-lint --all-files
pre-commit run ios-sdk-swiftlint --all-files
```

## Architecture Overview

### Kotlin Multiplatform SDK Architecture

The SDK uses Kotlin Multiplatform to share code across JVM, Android, and Native platforms:

1. **Common Module** (`commonMain/`) - Platform-agnostic business logic
   - Core services and interfaces
   - Data models and repositories
   - Network and authentication logic
   - Model management abstractions

2. **Platform-Specific Implementations**:
   - **JVM** (`jvmMain/`) - Desktop/IntelliJ plugin support
   - **Android** (`androidMain/`) - Android-specific implementations with Room DB
   - **Native** (`nativeMain/`) - Linux, macOS, Windows support

3. **Key Components**:
   - `RunAnywhere.kt` - Main SDK entry point (platform-specific implementations)
   - `Services.kt` - Service container and dependency injection
   - `STTComponent` - Speech-to-text with Whisper integration
   - `VADComponent` - Voice activity detection
   - `ModelManager` - Model downloading and lifecycle
   - `ConfigurationService` - Environment-specific configuration

### Design Patterns

1. **Repository Pattern**: Data access abstraction with platform-specific implementations
2. **Service Container**: Centralized dependency injection
3. **Event Bus**: Reactive communication between components
4. **Provider Pattern**: Platform-specific service providers (STT, VAD)

### Platform Requirements

**Kotlin Multiplatform SDK:**
- Kotlin: 2.1.21 (upgraded from 2.0.21 to fix compiler issues)
- Gradle: 8.11.1
- JVM Target: 17
- Android Min SDK: 24
- Android Target SDK: 36

**iOS SDK:**
- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- Swift: 5.9+
- Xcode: 15.0+

## Maven Coordinates

For IntelliJ/JetBrains plugin development:
```kotlin
dependencies {
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-jvm:0.1.0")
}
```

Location after local publish: `~/.m2/repository/com/runanywhere/sdk/`

## CI/CD Pipeline

GitHub Actions workflows are configured for automated testing and building:

- **Path-based triggers**: Workflows only run when relevant files change
- **Platform-specific runners**: Ubuntu for Android, macOS for iOS
- **Artifact uploads**: Build outputs and test results are preserved
- **Lint enforcement**: Lint errors fail the build

Workflows are located in `.github/workflows/`:
- `android-sdk.yml` - Android SDK CI
- `ios-sdk.yml` - iOS SDK CI
- `android-app.yml` - Android example app CI
- `ios-app.yml` - iOS example app CI

## Kotlin Multiplatform (KMP) SDK Best Practices

The Kotlin Multiplatform SDK has been aligned with iOS architecture patterns while leveraging Kotlin's strengths. These best practices ensure consistency, maintainability, and cross-platform compatibility.

### Architecture Patterns

#### Component-Based Architecture
Follow the iOS component pattern but adapted to KMP idioms:

```kotlin
// Base component with lifecycle management
abstract class BaseComponent<TService : Any>(
    protected val configuration: ComponentConfiguration,
    serviceContainer: ServiceContainer? = null
) : Component {

    // Component state tracking
    override var state: ComponentState = ComponentState.NOT_INITIALIZED
        protected set

    // Service creation (platform-specific via providers)
    protected abstract suspend fun createService(): TService

    // Lifecycle methods
    suspend fun initialize() { /* ... */ }
    override suspend fun cleanup() { /* ... */ }
    override suspend fun healthCheck(): ComponentHealth { /* ... */ }
}
```

#### Event-Driven Architecture
Use **Flow** instead of AsyncSequence for reactive streams:

```kotlin
// Central event bus with typed events
object EventBus {
    private val _componentEvents = MutableSharedFlow<ComponentEvent>()
    val componentEvents: SharedFlow<ComponentEvent> = _componentEvents.asSharedFlow()

    fun publish(event: ComponentEvent) {
        _componentEvents.tryEmit(event)
    }
}

// Usage: Listen to component state changes
EventBus.componentEvents
    .filterIsInstance<ComponentInitializationEvent.ComponentReady>()
    .collect { event ->
        println("Component ${event.component} is ready")
    }
```

#### Service Container Pattern
Centralized dependency injection with lazy initialization:

```kotlin
class ServiceContainer {
    companion object {
        val shared = ServiceContainer()
    }

    // Platform abstractions via expect/actual
    private val fileSystem by lazy { createFileSystem() }
    private val httpClient by lazy { createHttpClient() }

    // Service dependencies
    val modelManager: ModelManager by lazy {
        ModelManager(fileSystem, downloadService)
    }

    // Platform-specific initialization
    fun initialize(platformContext: PlatformContext) {
        platformContext.initialize()
    }
}
```

### Code Organization

#### commonMain Structure
Keep all business logic, interfaces, and data models in `commonMain/`:

```
commonMain/
├── components/          # Component implementations
│   ├── base/           # Base component classes
│   ├── stt/            # Speech-to-text components
│   └── vad/            # Voice activity detection
├── data/               # Data layer
│   ├── models/         # Data classes and enums
│   └── repositories/   # Repository interfaces
├── events/             # Event definitions
├── foundation/         # Core infrastructure
│   ├── ServiceContainer.kt
│   └── SDKLogger.kt
├── core/               # Plugin architecture
│   └── ModuleRegistry.kt
└── services/           # Service interfaces
    ├── configuration/
    ├── analytics/
    └── modelinfo/
```

#### Platform-Specific Structure
Use `expect/actual` **only** for platform-specific implementations:

```kotlin
// commonMain - Interface only
expect class PlatformContext {
    fun initialize()
}

expect fun createFileSystem(): FileSystem
expect fun createHttpClient(): HttpClient

// androidMain - Android implementation
actual class PlatformContext(private val context: Context) {
    actual fun initialize() {
        // Android-specific setup
    }
}

actual fun createFileSystem(): FileSystem = AndroidFileSystem()
```

#### Module Separation Principles

**Core SDK vs Feature Modules:**
- Core SDK (`commonMain`): Essential services, base components
- Feature modules: Optional capabilities (WhisperKit, external AI providers)
- Plugin architecture: `ModuleRegistry` for runtime registration

```kotlin
// Plugin registration pattern
object ModuleRegistry {
    fun registerSTT(provider: STTServiceProvider) {
        sttProviders.add(provider)
    }

    fun sttProvider(modelId: String? = null): STTServiceProvider? {
        return sttProviders.firstOrNull { it.canHandle(modelId) }
    }
}

// External module registration
// In WhisperKit module:
ModuleRegistry.shared.registerSTT(WhisperSTTProvider())
```

### API Design

#### Kotlin Idioms for iOS Patterns

**Flow for Reactive Streams:**
```kotlin
// Instead of AsyncSequence, use Flow
fun transcribeStream(audioFlow: Flow<ByteArray>): Flow<TranscriptionUpdate> {
    return audioFlow.map { audioData ->
        // Process audio chunk
        TranscriptionUpdate(text = processAudio(audioData), isFinal = false)
    }
}
```

**Coroutines for Async Operations:**
```kotlin
// Instead of async/await, use suspend functions
suspend fun loadModel(modelId: String): ModelLoadResult {
    return withContext(Dispatchers.IO) {
        modelRepository.loadModel(modelId)
    }
}
```

#### Structured Error Handling

Use **sealed classes** for type-safe error handling:

```kotlin
sealed class SDKError : Exception() {
    data class InvalidApiKey(override val message: String) : SDKError()
    data class NetworkError(override val cause: Throwable?) : SDKError()
    data class ComponentNotReady(override val message: String) : SDKError()
    data class InvalidState(override val message: String) : SDKError()

    // Result wrapper for operations
    sealed class Result<out T> {
        data class Success<T>(val value: T) : Result<T>()
        data class Failure(val error: SDKError) : Result<Nothing>()
    }
}
```

#### Strong Typing with Data Classes

**Always use structured types instead of strings:**
```kotlin
// Component configuration
data class STTConfiguration(
    val modelId: String,
    val language: Language = Language.EN,
    val enableVAD: Boolean = true,
    val audioFormat: AudioFormat = AudioFormat.PCM_16BIT
) : ComponentConfiguration {
    override fun validate() {
        require(modelId.isNotBlank()) { "Model ID cannot be blank" }
    }
}

// Enum for type safety
enum class Language(val code: String) {
    EN("en"), ES("es"), FR("fr"), DE("de"), JA("ja")
}

enum class AudioFormat { PCM_16BIT, PCM_24BIT, FLAC, MP3 }
```

### Integration Patterns

#### ModuleRegistry for Plugin Architecture

**Provider Pattern with Type Safety:**
```kotlin
interface STTServiceProvider {
    suspend fun createSTTService(configuration: STTConfiguration): STTService
    fun canHandle(modelId: String?): Boolean
    val name: String
}

// Registration in app initialization:
ModuleRegistry.registerSTT(WhisperSTTProvider())
ModuleRegistry.registerLLM(LlamaProvider())
```

#### EventBus for Component Communication

**Centralized Event System:**
```kotlin
// Component publishes events
eventBus.publish(ComponentInitializationEvent.ComponentReady(
    component = SDKComponent.STT,
    modelId = "whisper-base"
))

// Other components subscribe to events
EventBus.componentEvents
    .filterIsInstance<ComponentInitializationEvent.ComponentReady>()
    .filter { it.component == SDKComponent.STT }
    .collect { handleSTTReady(it) }
```

#### Provider Pattern for Extensibility

**Service Creation with Fallbacks:**
```kotlin
class STTComponent(configuration: STTConfiguration) : BaseComponent<STTService>(configuration) {

    override suspend fun createService(): STTService {
        // Try external providers first
        val provider = ModuleRegistry.sttProvider(configuration.modelId)

        return provider?.createSTTService(configuration)
            ?: throw SDKError.ComponentNotAvailable("No STT provider available for model: ${configuration.modelId}")
    }
}
```

### Performance Best Practices

#### Memory Management

**Component Lifecycle:**
```kotlin
abstract class BaseComponent<TService : Any> {

    override suspend fun cleanup() {
        // Proper resource cleanup
        performCleanup()
        service = null
        serviceContainer = null // Allow GC
        currentStage = null
    }

    protected open suspend fun performCleanup() {
        // Override for component-specific cleanup
    }
}
```

**Service Container Memory Management:**
```kotlin
class ServiceContainer {
    // Use lazy initialization to avoid memory pressure
    val modelManager: ModelManager by lazy {
        ModelManager(fileSystem, downloadService)
    }

    suspend fun cleanup() {
        // Cleanup components in reverse dependency order
        sttComponent.cleanup()
        vadComponent.cleanup()
    }
}
```

#### Platform-Specific Optimizations

**Android optimizations in `androidMain`:**
```kotlin
actual fun createFileSystem(): FileSystem = AndroidFileSystem().apply {
    // Configure for Android-specific optimizations
    enableFileWatcher = false // Reduce battery usage
    cacheStrategy = CacheStrategy.MEMORY_FIRST
}
```

**JVM optimizations in `jvmMain`:**
```kotlin
actual fun createHttpClient(): HttpClient = HttpClient {
    engine {
        // JVM-specific HTTP client configuration
        threadsCount = 4
        pipelining = true
    }
}
```

### Testing Patterns

#### Component Testing
```kotlin
class STTComponentTest {
    @Test
    fun `should initialize successfully with valid configuration`() = runTest {
        val config = STTConfiguration(modelId = "whisper-base")
        val component = STTComponent(config)

        component.initialize()

        assertEquals(ComponentState.READY, component.state)
        assertTrue(component.isReady)
    }

    @Test
    fun `should emit events during initialization`() = runTest {
        val events = mutableListOf<ComponentEvent>()
        val job = launch {
            EventBus.componentEvents.collect { events.add(it) }
        }

        val component = STTComponent(STTConfiguration(modelId = "whisper-base"))
        component.initialize()

        assertTrue(events.any { it is ComponentInitializationEvent.ComponentReady })
        job.cancel()
    }
}
```

#### Mock Providers for Testing
```kotlin
class MockSTTProvider : STTServiceProvider {
    override val name = "MockSTT"

    override suspend fun createSTTService(configuration: STTConfiguration): STTService {
        return MockSTTService()
    }

    override fun canHandle(modelId: String?): Boolean = true
}

// In test setup:
ModuleRegistry.clear()
ModuleRegistry.registerSTT(MockSTTProvider())
```

### Common Patterns Summary

1. **Business Logic in commonMain**: Keep all core logic platform-agnostic
2. **expect/actual for Platform APIs**: Only use for truly platform-specific code
3. **Flow over AsyncSequence**: Use Kotlin's reactive streams
4. **Coroutines over async/await**: Leverage structured concurrency
5. **Sealed Classes for Errors**: Type-safe error handling
6. **Data Classes for Models**: Strong typing throughout
7. **ModuleRegistry for Plugins**: Extensible architecture
8. **EventBus for Communication**: Decoupled component communication
9. **Service Container for DI**: Centralized dependency management
10. **Component Lifecycle**: Proper initialization and cleanup

These patterns ensure the Kotlin Multiplatform SDK maintains architectural consistency with the iOS implementation while leveraging Kotlin's strengths for cross-platform development.

## Development Notes

- The Kotlin Multiplatform SDK is the primary SDK implementation
- Use `./scripts/sdk.sh` for all SDK operations - it handles configuration and build complexity
- Configuration files (`dev.json`, `staging.json`, `prod.json`) are git-ignored - use example files as templates
- Both SDKs focus on privacy-first, on-device AI with intelligent routing
- Cost optimization is a key feature with real-time tracking
- Pre-commit hooks are configured for code quality enforcement
