# Voice Activity Detection (VAD) Comparison

## Overview

This document provides a comprehensive analysis of the Voice Activity Detection (VAD) implementations between the iOS Swift SDK and Kotlin Multiplatform (KMP) SDK. The comparison reveals significant architectural alignment, algorithm consistency, but some platform-specific differences.

## iOS Implementation

### VADService Architecture

The iOS VAD implementation follows a clean, protocol-based architecture:

**Key Components:**
- `VADService` protocol defines the core interface
- `VADComponent` acts as the main component wrapper following BaseComponent pattern
- `SimpleEnergyVAD` provides the concrete implementation
- `DefaultVADAdapter` handles service creation

**Protocol Definition:**
```swift
public protocol VADService: AnyObject {
    var energyThreshold: Float { get set }
    var sampleRate: Int { get }
    var frameLength: Float { get }
    var isSpeechActive: Bool { get }

    var onSpeechActivity: ((SpeechActivityEvent) -> Void)? { get set }
    var onAudioBuffer: ((Data) -> Void)? { get set }

    func initialize() async throws
    func start()
    func stop()
    func reset()
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer)
    func processAudioData(_ audioData: [Float]) -> Bool
}
```

### Detection Algorithm

**SimpleEnergyVAD Implementation:**
- **Algorithm**: RMS (Root Mean Square) energy-based detection
- **Energy Calculation**: Uses Apple's Accelerate framework `vDSP_rmsqv` for optimized RMS calculation
- **Hysteresis**: Prevents rapid on/off switching
  - Voice start threshold: 2 consecutive frames
  - Voice end threshold: 10 consecutive frames of silence

### Audio Level Processing

**RMS Energy Calculation:**
```swift
private func calculateAverageEnergy(of signal: [Float]) -> Float {
    guard !signal.isEmpty else { return 0.0 }

    var rmsEnergy: Float = 0.0
    vDSP_rmsqv(signal, 1, &rmsEnergy, vDSP_Length(signal.count))
    return rmsEnergy
}
```

### Silence Detection Thresholds

**Configuration Values:**
- **Default Energy Threshold**: 0.022
- **Sample Rate**: 16000 Hz
- **Frame Length**: 0.1 seconds (100ms = 1600 samples)
- **Voice Start Threshold**: 2 frames
- **Voice End Threshold**: 10 frames

### Integration with STT

- **Event-Driven**: Uses speech activity callbacks (`SpeechActivityEvent.started/ended`)
- **Stream Processing**: Supports `AsyncSequence` for continuous audio processing
- **Buffer Support**: Direct `AVAudioPCMBuffer` processing

## KMP Implementation

### Common Interface

The KMP implementation closely mirrors the iOS architecture:

**VADService Protocol:**
```kotlin
interface VADService {
    var energyThreshold: Float
    val sampleRate: Int
    val frameLength: Float
    val isSpeechActive: Boolean

    var onSpeechActivity: ((SpeechActivityEvent) -> Unit)?
    var onAudioBuffer: ((ByteArray) -> Unit)?

    suspend fun initialize(configuration: VADConfiguration)
    fun start()
    fun stop()
    fun reset()
    fun processAudioChunk(audioSamples: FloatArray): VADResult
    fun processAudioData(audioData: FloatArray): Boolean
    val isReady: Boolean
    val configuration: VADConfiguration?
    suspend fun cleanup()
}
```

### Component Structure

**VADComponent Architecture:**
- Extends `BaseComponent<VADServiceWrapper>`
- Uses `ModuleRegistry` for service provider discovery
- Supports stream processing with Kotlin `Flow`

### Detection Logic

**SimpleEnergyVAD Implementation:**
- **Algorithm**: Identical RMS energy-based detection
- **Manual RMS Calculation**: Since no Accelerate equivalent, uses manual calculation
- **Exact Hysteresis Values**: Same thresholds as iOS (2 start, 10 end)

**RMS Energy Calculation:**
```kotlin
private fun calculateAverageEnergy(signal: FloatArray): Float {
    if (signal.isEmpty()) return 0.0f

    var sum = 0.0f
    for (sample in signal) {
        sum += sample * sample
    }

    return sqrt(sum / signal.size)
}
```

## Platform-Specific Implementations

### Android

**WebRTCVADService Features:**
- **Algorithm**: Google WebRTC GMM-based VAD (more sophisticated than energy-based)
- **Library**: Uses `android-vad` library with `VadWebRTC`
- **Modes**: Supports AGGRESSIVE, FAST, NORMAL, VERY_AGGRESSIVE
- **Frame Sizes**: Adaptive frame sizing based on sample rate (80-1440 samples)
- **Robustness**: More accurate than energy-based detection

**Configuration Mapping:**
- Sample rates: 8K, 16K, 32K, 48K Hz
- Frame durations: Automatically mapped to valid WebRTC frame sizes
- Speech/Silence duration: 50ms speech minimum, 500ms silence

**WebRTC Advantages:**
- Better noise resistance
- More accurate speech detection
- Handles various acoustic conditions
- Production-ready algorithm

### JVM

**SimpleEnergyVAD Implementation:**
- **Algorithm**: Identical to iOS SimpleEnergyVAD
- **Fallback Strategy**: Uses same energy-based approach when WebRTC unavailable
- **Cross-Platform**: Ensures consistent behavior across desktop platforms

## Gaps and Misalignments

### Algorithm Differences

1. **Android vs iOS/JVM Disparity:**
   - Android uses sophisticated WebRTC GMM-based VAD
   - iOS/JVM use simple energy-based detection
   - Results in different detection accuracy and behavior

2. **Confidence Scoring:**
   - iOS: Returns energy level as confidence indicator
   - Android WebRTC: Fixed confidence values (0.85 speech, 0.15 silence)
   - JVM: Calculated confidence based on energy level

### Sensitivity Disparities

1. **Threshold Interpretation:**
   - Energy-based: Direct RMS threshold comparison (0.022)
   - WebRTC: Internal algorithm thresholds (not directly configurable)

2. **Hysteresis Behavior:**
   - iOS/JVM: Manual frame counting (2 start, 10 end)
   - Android: WebRTC internal hysteresis (50ms speech, 500ms silence)

### Performance Gaps

1. **Processing Efficiency:**
   - iOS: Hardware-accelerated RMS with Accelerate framework
   - Android: Optimized WebRTC native implementation
   - JVM: Software-only RMS calculation (potentially slower)

2. **Memory Usage:**
   - iOS: Efficient with AVAudioPCMBuffer
   - Android: FloatArray conversion overhead
   - JVM: Direct FloatArray processing

### Configuration Differences

1. **Frame Size Constraints:**
   - iOS/JVM: Flexible frame length (any duration)
   - Android: Fixed WebRTC frame sizes (must match supported values)

2. **Sample Rate Support:**
   - iOS/JVM: Any sample rate up to 48kHz
   - Android: Limited to WebRTC supported rates (8K, 16K, 32K, 48K)

## Recommendations to Address Gaps

### Algorithm Alignment

1. **Standardize Detection Algorithms:**
   ```kotlin
   // Option 1: Unified WebRTC approach
   // Implement WebRTC VAD for iOS/JVM platforms
   // Pros: Better accuracy, consistent behavior
   // Cons: Additional native dependencies

   // Option 2: Enhanced Energy VAD
   // Improve SimpleEnergyVAD with spectral features
   // Pros: Lightweight, cross-platform
   // Cons: Still less accurate than WebRTC
   ```

2. **Multi-Algorithm Support:**
   ```kotlin
   enum class VADAlgorithm {
       ENERGY_BASED,    // Simple RMS energy
       WEBRTC_GMM,      // WebRTC Gaussian Mixture Model
       SPECTRAL,        // Spectral-based features
       HYBRID           // Combination approach
   }

   data class VADConfiguration(
       val algorithm: VADAlgorithm = VADAlgorithm.WEBRTC_GMM,
       val energyThreshold: Float = 0.022f,
       val aggressiveness: Int = 2  // WebRTC aggressiveness level
   )
   ```

### Sensitivity Standardization

1. **Unified Threshold System:**
   ```kotlin
   data class VADSensitivityConfig(
       val energyThreshold: Float = 0.022f,
       val confidenceThreshold: Float = 0.5f,
       val voiceStartFrames: Int = 2,
       val voiceEndFrames: Int = 10,
       val minimumSpeechDurationMs: Int = 100,
       val minimumSilenceDurationMs: Int = 500
   )
   ```

2. **Adaptive Thresholding:**
   ```kotlin
   interface AdaptiveVAD : VADService {
       fun updateThresholdBasedOnNoise(noiseLevel: Float)
       fun calibrateForEnvironment(backgroundSamples: FloatArray)
       val recommendedThreshold: Float
   }
   ```

### Performance Optimizations

1. **Hardware Acceleration:**
   ```kotlin
   // iOS: Continue using Accelerate framework
   // Android: Leverage NNAPI or GPU compute when available
   // JVM: Implement SIMD optimizations where possible

   interface AcceleratedVAD {
       val supportsHardwareAcceleration: Boolean
       fun enableHardwareAcceleration(): Boolean
   }
   ```

2. **Memory Optimization:**
   ```kotlin
   class OptimizedVADBuffer {
       private val ringBuffer: FloatArray
       private var writeIndex: Int = 0

       fun processInPlace(samples: FloatArray): VADResult {
           // Process without additional allocations
           // Reuse internal buffers
       }
   }
   ```

### Configuration Standardization

1. **Unified Configuration:**
   ```kotlin
   data class UnifiedVADConfiguration(
       // Core parameters
       val sampleRate: Int = 16000,
       val frameLength: Float = 0.1f,

       // Algorithm selection
       val preferredAlgorithm: VADAlgorithm = VADAlgorithm.WEBRTC_GMM,
       val fallbackAlgorithm: VADAlgorithm = VADAlgorithm.ENERGY_BASED,

       // Sensitivity settings
       val sensitivity: VADSensitivityConfig = VADSensitivityConfig(),

       // Performance settings
       val enableHardwareAcceleration: Boolean = true,
       val bufferOptimization: Boolean = true
   )
   ```

2. **Platform Capability Detection:**
   ```kotlin
   object VADCapabilities {
       fun getAvailableAlgorithms(): List<VADAlgorithm>
       fun getOptimalConfiguration(environment: AudioEnvironment): VADConfiguration
       fun supportsRealTimeProcessing(): Boolean
   }
   ```

### Implementation Roadmap

**Phase 1: Immediate Fixes**
1. Align SimpleEnergyVAD implementations exactly
2. Standardize confidence calculation methods
3. Implement consistent callback behavior

**Phase 2: Algorithm Enhancement**
1. Port WebRTC VAD to iOS/JVM platforms
2. Implement adaptive thresholding
3. Add noise level detection and compensation

**Phase 3: Advanced Features**
1. Multi-algorithm support with automatic selection
2. Hardware acceleration optimization
3. Real-time performance monitoring and adjustment

**Phase 4: Quality Assurance**
1. Comprehensive cross-platform testing suite
2. Acoustic environment benchmarking
3. Performance regression testing

This roadmap ensures gradual improvement while maintaining backward compatibility and platform-specific optimizations.

## Conclusion

The VAD implementations show strong architectural alignment between iOS and KMP SDKs, with the core SimpleEnergyVAD algorithm being nearly identical. However, Android's WebRTC implementation provides significantly better accuracy at the cost of some complexity. The main gaps are in algorithm consistency, configuration flexibility, and performance optimization. The recommended approach is to gradually migrate all platforms to WebRTC-based VAD while maintaining the existing energy-based VAD as a fallback option.
