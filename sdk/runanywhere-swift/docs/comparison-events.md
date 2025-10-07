# Event System Comparison: iOS vs KMP

**Analysis Date**: September 2025
**Focus**: Event system architecture, reactive patterns, subscription mechanisms, and platform-specific handling differences between iOS and KMP implementations.

## iOS Implementation

### Event Architecture

#### Core Framework: Combine
- **Primary Pattern**: Publisher-Subscriber model using Apple's Combine framework
- **Event Bus Structure**: Centralized singleton with type-specific subjects
- **Thread Safety**: Built-in thread safety through Combine's operators

```swift
// EventBus.swift - iOS Implementation
public final class EventBus: @unchecked Sendable {
    public static let shared = EventBus()

    // Type-specific subjects for each event category
    private let initializationSubject = PassthroughSubject<SDKInitializationEvent, Never>()
    private let configurationSubject = PassthroughSubject<SDKConfigurationEvent, Never>()
    private let generationSubject = PassthroughSubject<SDKGenerationEvent, Never>()
    // ... other subjects

    // All events aggregator
    private let allEventsSubject = PassthroughSubject<any SDKEvent, Never>()
}
```

#### Reactive Streaming with AsyncSequence
- **Streaming Interface**: AsyncThrowingStream for token-level streaming
- **Backpressure Handling**: Built-in through AsyncSequence buffering
- **Error Propagation**: Type-safe error handling with throwing streams

```swift
// StreamingService.swift - iOS Streaming Implementation
public func generateStream(
    prompt: String,
    options: RunAnywhereGenerationOptions
) -> AsyncThrowingStream<String, Error> {
    return AsyncThrowingStream { continuation in
        Task {
            // Streaming implementation with automatic backpressure
            try await loadedModel.service.streamGenerate(
                prompt: effectivePrompt,
                options: resolvedOptions,
                onToken: { token in
                    continuation.yield(token) // Automatic buffering
                }
            )
        }
    }
}
```

### Event Types Hierarchy

#### Comprehensive Event Coverage
- **SDKInitializationEvent**: 5 variants (Started, ConfigurationLoaded, etc.)
- **SDKConfigurationEvent**: 14 variants including detailed config read events
- **SDKGenerationEvent**: 12 variants with session management and routing
- **SDKModelEvent**: 14 variants covering full model lifecycle
- **SDKVoiceEvent**: 16 variants for complete voice pipeline
- **SDKPerformanceEvent**: 4 variants for monitoring
- **SDKNetworkEvent**: 4 variants for connectivity
- **SDKStorageEvent**: 12 variants for storage operations
- **SDKFrameworkEvent**: 10 variants for framework management
- **SDKDeviceEvent**: 7 variants for device state
- **ComponentInitializationEvent**: 12 variants for component lifecycle

#### Voice Pipeline Events (ModularPipelineEvent)
```swift
public enum ModularPipelineEvent {
    // VAD events
    case vadSpeechStart, vadSpeechEnd
    case vadAudioLevel(Float)

    // STT events with Speaker Diarization
    case sttPartialTranscriptWithSpeaker(String, SpeakerInfo)
    case sttFinalTranscriptWithSpeaker(String, SpeakerInfo)
    case sttSpeakerChanged(from: SpeakerInfo?, to: SpeakerInfo)

    // LLM events
    case llmStreamToken(String)
    case llmPartialResponse(String)

    // TTS events
    case ttsAudioChunk(Data)
}
```

### Subscription Patterns

#### Publisher-Based Subscriptions
```swift
// Type-safe event subscriptions
EventBus.shared.generationEvents
    .sink { event in
        // Handle generation events
    }
    .store(in: &cancellables)

// Generic event filtering
EventBus.shared.allEvents
    .compactMap { $0 as? SDKModelEvent }
    .sink { modelEvent in
        // Handle model events
    }
```

#### Component-Specific Filtering
```swift
EventBus.shared.onComponent(
    .STT,
    handler: { event in
        // Handle STT component events
    }
)
```

## KMP Implementation

### Event Architecture

#### Core Framework: Kotlin Coroutines Flow
- **Primary Pattern**: Flow-based reactive streams with SharedFlow/StateFlow
- **Event Bus Structure**: Object-based singleton with MutableSharedFlow subjects
- **Thread Safety**: Coroutine context safety with structured concurrency

```kotlin
// EventBus.kt - KMP Implementation
object EventBus {
    // Type-specific flows for each event category
    private val _initializationEvents = MutableSharedFlow<SDKInitializationEvent>()
    val initializationEvents: SharedFlow<SDKInitializationEvent> = _initializationEvents.asSharedFlow()

    private val _configurationEvents = MutableSharedFlow<SDKConfigurationEvent>()
    val configurationEvents: SharedFlow<SDKConfigurationEvent> = _configurationEvents.asSharedFlow()

    // All events aggregator
    private val _allEvents = MutableSharedFlow<SDKEvent>()
    val allEvents: SharedFlow<SDKEvent> = _allEvents.asSharedFlow()
}
```

#### Reactive Streaming with Flow
- **Streaming Interface**: Flow<T> for reactive data streams
- **Backpressure Handling**: Manual configuration needed (buffer, conflate, etc.)
- **Error Propagation**: Exception handling within Flow context

```kotlin
// StreamingService.kt - KMP Streaming Implementation
fun stream(
    prompt: String,
    options: GenerationOptions
): Flow<GenerationChunk> = flow {
    // Mock implementation - needs actual LLM service integration
    val mockResponse = "This is a streaming response..."
    val words = mockResponse.split(" ")

    for ((index, word) in words.withIndex()) {
        emit(GenerationChunk(text = "$word ", isComplete = index == words.lastIndex))
        delay(50) // Simulate streaming
    }
}
```

### Common Implementation (Cross-Platform)

#### Event Types Coverage
All event types are implemented in commonMain with exact iOS parity:
- **Sealed Classes**: Type-safe event hierarchies
- **Base Interface**: `SDKEvent` with timestamp and eventType
- **Event Categories**: Same 11 main categories as iOS

```kotlin
// SDKEvent.kt - KMP Event Types
sealed class SDKInitializationEvent : BaseSDKEvent(SDKEventType.INITIALIZATION) {
    object Started : SDKInitializationEvent()
    data class ConfigurationLoaded(val source: String) : SDKInitializationEvent()
    object ServicesBootstrapped : SDKInitializationEvent()
    object Completed : SDKInitializationEvent()
    data class Failed(val error: Throwable) : SDKInitializationEvent()
}
```

#### Component Architecture Integration
```kotlin
// BaseComponent.kt - Event integration
abstract class BaseComponent<TService : Any> : Component {
    protected val eventBus = EventBus

    override suspend fun initialize() {
        eventBus.publish(ComponentInitializationEvent.ComponentInitializing(
            component = componentType.name,
            modelId = parameters.modelId
        ))
        // ... initialization logic
    }
}
```

### Platform-Specific Implementations

#### Android Platform
- **StateFlow Integration**: For UI state management compatibility
- **LiveData Bridge**: Potential integration with Android Architecture Components
- **Memory Management**: Android-specific lifecycle awareness

```kotlin
// AndroidAudioSession.kt - Android-specific reactive patterns
class AndroidAudioSession {
    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording.asStateFlow()

    private val _isConfigured = MutableStateFlow(false)
    val isConfigured: StateFlow<Boolean> = _isConfigured.asStateFlow()
}
```

#### JVM Platform
- **Desktop Event Handling**: Different threading model considerations
- **Plugin Architecture**: IntelliJ/JetBrains plugin event integration patterns

```kotlin
// JVM-specific implementations focus on thread safety
// and desktop application lifecycle management
```

## Gaps and Misalignments

### 1. Event Type Differences

#### Missing in KMP:
- **Device Events Subject**: iOS has dedicated deviceEvents publisher, KMP routes through allEvents
- **Bootstrap Events**: KMP has `SDKBootstrapEvent` but not integrated into main EventBus
- **Legacy Event Support**: KMP has speaker diarization events as separate flow

#### Inconsistent Implementations:
- **Event Publishing**: iOS uses `tryEmit()` vs KMP uses `tryEmit()` - consistent but different error handling
- **Generic Event Publishing**: iOS has switch-based dispatch, KMP has when-based dispatch

### 2. Subscription Mechanism Disparities

#### iOS Advantages:
- **Built-in Backpressure**: AsyncSequence handles backpressure automatically
- **Type Erasure**: `AnyPublisher` provides clean type erasure
- **Memory Management**: Automatic cleanup with Combine's lifecycle

#### KMP Limitations:
- **Manual Backpressure**: Need explicit buffer/conflate configuration
- **Scope Management**: Require explicit CoroutineScope for subscriptions
- **No Built-in Type Erasure**: Flow types are exposed

```kotlin
// KMP subscription requires explicit scope management
fun EventBus.onGeneration(
    scope: CoroutineScope,
    handler: (SDKGenerationEvent) -> Unit
): Job {
    return scope.launch {
        generationEvents.collect { event ->
            handler(event)
        }
    }
}
```

### 3. Reactive Pattern Disparities

#### Streaming Architecture:
- **iOS**: `AsyncThrowingStream<String, Error>` with automatic continuation management
- **KMP**: `Flow<GenerationChunk>` with manual emission and delay simulation

#### State Management:
- **iOS**: `@Published` properties with automatic UI binding
- **KMP**: `StateFlow/MutableStateFlow` requiring explicit collection

### 4. Platform-Specific Event Handling

#### iOS Strengths:
- **Combine Integration**: Native iOS reactive framework integration
- **SwiftUI Binding**: Direct `@Published` property binding to UI
- **Memory Safety**: Automatic cleanup with weak references

#### Android Strengths:
- **Lifecycle Awareness**: Integration with Android Architecture Components
- **StateFlow UI Binding**: Compose compatibility
- **Configuration Changes**: Automatic state preservation

#### JVM Considerations:
- **Thread Safety**: Desktop threading model differences
- **Plugin Architecture**: IntelliJ-specific event patterns

## Recommendations to Address Gaps

### 1. Event Standardization

#### Implement Missing Publishers
```kotlin
// Add device events subject to EventBus
private val _deviceEvents = MutableSharedFlow<SDKDeviceEvent>()
val deviceEvents: SharedFlow<SDKDeviceEvent> = _deviceEvents.asSharedFlow()

// Integrate bootstrap events into main flow
private val _bootstrapEvents = MutableSharedFlow<SDKBootstrapEvent>()
val bootstrapEvents: SharedFlow<SDKBootstrapEvent> = _bootstrapEvents.asSharedFlow()
```

#### Standardize Event Publishing
```kotlin
// Create unified event publishing interface
interface EventPublisher {
    fun publish(event: SDKEvent)
    fun <T : SDKEvent> publishTyped(event: T)
}
```

### 2. Backpressure Handling Enhancement

#### Add Flow Configuration Options
```kotlin
// Enhanced streaming with backpressure configuration
fun streamWithBackpressure(
    prompt: String,
    options: GenerationOptions,
    bufferSize: Int = 64
): Flow<GenerationChunk> = flow {
    // Implementation with buffer configuration
}.buffer(bufferSize)

// Conflated flow for UI updates
fun streamForUI(
    prompt: String,
    options: GenerationOptions
): Flow<GenerationChunk> = stream(prompt, options).conflate()
```

### 3. Subscription Pattern Alignment

#### Create Combine-like Extensions
```kotlin
// iOS-style subscription extensions
inline fun <reified T : SDKEvent> EventBus.sink(
    scope: CoroutineScope,
    crossinline handler: (T) -> Unit
): Job = on<T>(scope, handler)

// Type-erased publisher equivalent
class AnyEventPublisher<T : SDKEvent>(
    private val flow: SharedFlow<T>
) {
    fun collect(scope: CoroutineScope, handler: (T) -> Unit): Job {
        return scope.launch { flow.collect(handler) }
    }
}
```

### 4. Platform-Specific Optimizations

#### Android Integration
```kotlin
// LiveData bridge for legacy Android components
fun <T : SDKEvent> SharedFlow<T>.asLiveData(): LiveData<T> {
    return this.asLiveData(Dispatchers.Main)
}

// StateFlow integration for Compose
fun <T : SDKEvent> SharedFlow<T>.collectAsState(
    initial: T? = null
): State<T?> = collectAsState(initial)
```

#### iOS Integration Improvements
```swift
// Enhanced memory management
extension EventBus {
    func weakSink<T: SDKEvent>(
        _ eventType: T.Type,
        target: AnyObject,
        handler: @escaping (T) -> Void
    ) -> AnyCancellable {
        return on(eventType) { [weak target] event in
            guard target != nil else { return }
            handler(event)
        }
    }
}
```

### 5. Testing and Debugging Support

#### Event Debugging Tools
```kotlin
// Debug event flow for development
object EventDebugger {
    fun enableEventLogging() {
        EventBus.allEvents
            .onEach { event ->
                println("Event: ${event::class.simpleName} at ${event.timestamp}")
            }
            .launchIn(GlobalScope)
    }
}
```

#### Mock Event Generation
```kotlin
// Test utilities for event system
object EventTestUtils {
    fun publishMockEvents(events: List<SDKEvent>) {
        events.forEach { EventBus.publishSDKEvent(it) }
    }

    fun awaitEvent<T : SDKEvent>(
        type: KClass<T>,
        timeout: Duration = 5.seconds
    ): T = runBlocking {
        withTimeout(timeout) {
            EventBus.allEvents.filterIsInstance<T>().first()
        }
    }
}
```

## Summary

The event systems in both iOS and KMP implementations are architecturally similar, with both using centralized event buses and type-safe event hierarchies. The main differences lie in the underlying reactive frameworks (Combine vs. Coroutines Flow) and platform-specific optimizations.

**Key Strengths:**
- **iOS**: Superior built-in backpressure handling, automatic memory management, SwiftUI integration
- **KMP**: Cross-platform consistency, flexible coroutine integration, explicit control over reactive streams

**Critical Gaps to Address:**
1. Standardize missing device events publisher in KMP
2. Enhance backpressure handling configuration in KMP
3. Create iOS-style subscription convenience methods for KMP
4. Improve platform-specific integrations (LiveData for Android, enhanced Combine patterns for iOS)

**Implementation Priority:**
1. **High**: Event type standardization and missing publishers
2. **Medium**: Backpressure handling improvements and subscription pattern alignment
3. **Low**: Platform-specific optimizations and debugging tools

The event system comparison reveals a solid foundation with room for enhancement to achieve full feature parity and optimal platform integration.
