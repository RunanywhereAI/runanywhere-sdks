# Voice Activity Detection (VAD) Component Architecture Comparison

## Overview

This document provides a comprehensive comparison between the Voice Activity Detection (VAD) component implementations in the iOS Swift SDK and the Kotlin Multiplatform SDK, analyzing their architectural differences, detection strategies, and platform-specific implementations.

## Architecture Overview

### iOS Swift SDK Architecture

The iOS VAD implementation follows a clean, protocol-oriented architecture:

#### Core Components
- **VADService Protocol** (`VADComponent.swift`): Base protocol defining VAD service interface
- **VADComponent** (`VADComponent.swift`): Main component implementing `BaseComponent<SimpleEnergyVAD>`
- **SimpleEnergyVAD** (`SimpleEnergyVAD.swift`): Concrete energy-based VAD implementation
- **VADHandler** (`VADHandler.swift`): Bridge handler for legacy compatibility

#### Configuration System
```swift
public struct VADConfiguration: ComponentConfiguration, ComponentInitParameters {
    public let energyThreshold: Float = 0.022
    public let sampleRate: Int = 16000
    public let frameLength: Float = 0.1
}
```

### Kotlin Multiplatform SDK Architecture

The Kotlin implementation uses a more complex architecture with platform abstraction:

#### Core Components
- **VADService Interface** (`VADModels.kt`): Protocol defining VAD service operations
- **VADComponent** (`VADComponent.kt`): Main component extending `BaseComponent<VADServiceWrapper>`
- **VADServiceProvider** (`VADServiceProvider.kt`): Platform abstraction layer using `expect/actual`
- **Platform Implementations**: WebRTC (Android), JVM Simple Energy (JVM), Simple Energy (Common)

#### Configuration System
```kotlin
data class VADConfiguration(
    val aggressiveness: Int = 2, // 0-3 scale
    val sampleRate: Int = 16000,
    val frameDuration: Int = 30, // ms
    val silenceThreshold: Int = 500, // ms
    val energyThreshold: Float = 0.5f,
    val useEnhancedModel: Boolean = false
)
```

## VAD Detection Algorithms and Strategies

### iOS: Energy-Based Detection

**Algorithm**: RMS (Root Mean Square) energy calculation with hysteresis
```swift
private func calculateAverageEnergy(of signal: [Float]) -> Float {
    var rmsEnergy: Float = 0.0
    vDSP_rmsqv(signal, 1, &rmsEnergy, vDSP_Length(signal.count))
    return rmsEnergy
}
```

**Key Features**:
- Uses Apple's Accelerate framework (`vDSP_rmsqv`) for optimized RMS calculation
- Hysteresis with configurable thresholds:
  - `voiceStartThreshold = 2` frames
  - `voiceEndThreshold = 10` frames
- Single energy threshold: `0.022` (default)
- Frame-based processing with 100ms windows

### Kotlin: Multi-Algorithm Approach

**Platform-Specific Strategies**:

#### Android: WebRTC VAD
- **Algorithm**: Google WebRTC GMM-based (Gaussian Mixture Model) VAD
- **Library**: `android-vad` (com.konovalov.vad.webrtc)
- **Modes**: Normal, Low Bitrate, Aggressive, Very Aggressive
- **Frame Support**: 10ms, 20ms, 30ms windows
- **Sample Rates**: 8kHz, 16kHz, 32kHz, 48kHz

```kotlin
val vadInstance = VadWebRTC(
    sampleRate = sampleRate,
    frameSize = frameSize,
    mode = mode,
    speechDurationMs = 50,
    silenceDurationMs = configuration.silenceThreshold
)
```

#### JVM: Simple Energy VAD
- **Algorithm**: RMS energy calculation with frame smoothing
- **Thresholds**: Configurable energy threshold with smoothing logic
- **State Tracking**: Consecutive speech/silence frame counting

#### Common: SimpleEnergyVAD
- **Algorithm**: Similar to iOS but without Accelerate framework optimization
- **Manual RMS**: `sqrt(sum / buffer.size)` calculation

## Audio Input Processing

### iOS Audio Processing

**Input Types**:
- `AVAudioPCMBuffer` (primary)
- `[Float]` audio samples (secondary)

**Audio Buffer Conversion**:
```swift
private func convertBufferToFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float] {
    guard let channelData = buffer.floatChannelData else { return [] }
    let frameLength = Int(buffer.frameLength)
    let samples = channelData.pointee
    return Array(UnsafeBufferPointer(start: samples, count: frameLength))
}
```

**Processing Flow**:
1. AVAudioPCMBuffer → Float array conversion
2. RMS energy calculation using Accelerate
3. Threshold comparison with hysteresis
4. Speech activity event dispatch

### Kotlin Audio Processing

**Input Types**:
- `FloatArray` (primary for all platforms)
- `ByteArray` (with conversion utilities)

**Platform-Specific Processing**:

#### Android (WebRTC)
```kotlin
val isSpeech = vadInstance!!.isSpeech(audioSamples) // Direct WebRTC processing
```

#### JVM/Common
```kotlin
private fun calculateEnergy(audioData: FloatArray): Float {
    var sum = 0.0
    for (sample in audioData) {
        sum += sample * sample
    }
    return sqrt(sum / audioData.size).toFloat()
}
```

## Threshold Configuration and Tuning

### iOS Configuration

**Single Threshold Model**:
- `energyThreshold: Float = 0.022`
- Runtime threshold updates supported
- Hysteresis parameters are hardcoded:
  ```swift
  private let voiceStartThreshold = 2  // frames
  private let voiceEndThreshold = 10   // frames
  ```

### Kotlin Configuration

**Multi-Parameter Model**:
- `energyThreshold: Float = 0.5f` (for energy-based VADs)
- `aggressiveness: Int = 2` (for WebRTC VAD, 0-3 scale)
- `silenceThreshold: Int = 500` (ms of silence to end speech)
- `frameDuration: Int = 30` (ms frame duration)

**Adaptive Thresholds**:
```kotlin
// WebRTC VAD - automatic threshold adaptation
speechDurationMs = 50,
silenceDurationMs = configuration.silenceThreshold

// JVM VAD - configurable smoothing parameters
minSpeechFrames = 3,
maxSilenceFrames = 10
```

## Real-time Detection Patterns

### iOS Real-time Processing

**Event-Driven Architecture**:
```swift
public var onSpeechActivity: ((SpeechActivityEvent) -> Void)?
public enum SpeechActivityEvent: String, Sendable {
    case started = "started"
    case ended = "ended"
}
```

**Async Stream Processing**:
```swift
public func processAudioStream<S: AsyncSequence>(_ stream: S) -> AsyncThrowingStream<VADOutput, Error>
where S.Element == AVAudioPCMBuffer
```

### Kotlin Real-time Processing

**Flow-Based Architecture**:
```kotlin
fun streamProcess(audioStream: Flow<FloatArray>): Flow<VADOutput>

fun detectSpeechSegments(
    audioStream: Flow<FloatArray>,
    onSpeechStart: () -> Unit = {},
    onSpeechEnd: () -> Unit = {}
): Flow<VADOutput>
```

**State Management**:
```kotlin
var isInSpeech = false
var silenceFrames = 0
val silenceFramesThreshold = vadConfiguration.silenceThreshold / vadConfiguration.frameDuration
```

## Integration with STT Components

### iOS Integration

**Loose Coupling**:
- VADComponent is independent
- Integration through shared audio buffers
- Event-driven communication via callbacks

```swift
public func setSpeechActivityCallback(_ callback: @escaping (SpeechActivityEvent) -> Void) {
    service?.onSpeechActivity = callback
}
```

### Kotlin Integration

**Component Registry Pattern**:
```kotlin
val provider = ModuleRegistry.vadProvider(vadConfiguration.modelId)
    ?: throw SDKError.ComponentNotInitialized("No VAD service provider registered")
```

**Tight Integration**:
- Components registered through ModuleRegistry
- Shared configuration and lifecycle management
- Flow-based data streaming between components

## State Management for Voice Detection

### iOS State Management

**Simple State Tracking**:
```swift
private var isActive = false
private var isCurrentlySpeaking = false
private var consecutiveSilentFrames = 0
private var consecutiveVoiceFrames = 0
```

**Thread Safety**:
- `@MainActor` annotation on VADComponent
- DispatchQueue.main.async for callback dispatch

### Kotlin State Management

**Component State Pattern**:
```kotlin
enum class ComponentState {
    NOT_INITIALIZED, INITIALIZING, READY, PROCESSING, ERROR, CLEANING_UP
}
```

**Coroutine-Safe**:
- Suspend functions for initialization/cleanup
- Flow-based processing with coroutine context
- Thread-safe state transitions

## Platform-Specific Audio Handling

### iOS Platform Features

**AVFoundation Integration**:
- Native `AVAudioPCMBuffer` support
- Accelerate framework optimization
- Core Audio format handling

**iOS-Specific Optimizations**:
- `vDSP_rmsqv` for vectorized RMS calculation
- Metal Performance Shaders potential (unused)
- Native audio session management

### Android Platform Features

**WebRTC Integration**:
```kotlin
// Sophisticated VAD using Google's WebRTC library
val vadInstance = VadWebRTC(
    sampleRate = SampleRate.SAMPLE_RATE_16K,
    frameSize = FrameSize.FRAME_SIZE_320,
    mode = Mode.AGGRESSIVE
)
```

**Android-Specific Features**:
- Native WebRTC VAD with GMM algorithms
- Hardware-accelerated audio processing potential
- MediaRecorder integration support

### JVM Platform Features

**Pure Kotlin Implementation**:
- No native dependencies
- Cross-platform compatibility
- Simplified energy-based detection

## Performance Considerations

### iOS Performance

**Optimizations**:
- Accelerate framework for SIMD operations
- Native memory management with UnsafeBufferPointer
- Minimal object allocation in processing loop

**Performance Characteristics**:
- Low latency: ~100ms frame processing
- Memory efficient: Direct buffer manipulation
- CPU efficient: Vectorized operations

### Kotlin Performance

**Platform-Specific Performance**:

#### Android
- **Pros**: Native WebRTC implementation, hardware optimization potential
- **Cons**: JNI overhead for native calls

#### JVM
- **Pros**: JIT compilation optimization, garbage collection tuning
- **Cons**: No SIMD operations, higher memory allocation

**Memory Management**:
```kotlin
// Efficient array processing without copying
fun processAudioChunk(audioSamples: FloatArray): VADResult

// Stream processing with Flow (backpressure handling)
fun streamProcess(audioStream: Flow<FloatArray>): Flow<VADOutput>
```

## Comparison Summary

| Aspect | iOS Swift | Kotlin Multiplatform |
|--------|-----------|----------------------|
| **Architecture** | Protocol-oriented, single implementation | Multi-platform with expect/actual pattern |
| **VAD Algorithm** | Energy-based (RMS with Accelerate) | Platform-specific (WebRTC on Android, Energy on JVM) |
| **Configuration** | Simple (3 parameters) | Complex (6+ parameters) |
| **Real-time Processing** | AsyncSequence/Callback | Kotlin Flow |
| **Platform Optimization** | Accelerate framework (iOS) | WebRTC native (Android), Pure Kotlin (JVM) |
| **State Management** | Simple boolean flags | Component state machine |
| **Audio Input** | AVAudioPCMBuffer + Float arrays | FloatArray primary |
| **Integration Pattern** | Event-driven callbacks | Registry-based dependency injection |
| **Threading Model** | MainActor + DispatchQueue | Coroutines with Dispatchers |
| **Memory Efficiency** | High (UnsafeBufferPointer) | Medium (GC overhead) |
| **Algorithm Sophistication** | Medium (energy + hysteresis) | High (WebRTC GMM on Android) |

## Recommendations

### For iOS Development
1. **Maintain simplicity** of current energy-based approach
2. **Consider** adding configurable hysteresis parameters
3. **Explore** Metal Performance Shaders for further optimization
4. **Add** support for multiple VAD strategies (similar to Kotlin's approach)

### For Kotlin Development
1. **Standardize** interface between platform implementations
2. **Add** energy-based fallback for all platforms
3. **Optimize** JVM implementation with native libraries if needed
4. **Consider** adding iOS-style simplicity option for basic use cases

### Cross-Platform Considerations
1. **Align** default threshold values between platforms
2. **Standardize** frame duration and sample rate defaults
3. **Create** unified configuration mapping between platforms
4. **Implement** similar hysteresis logic across all implementations
