# Text-to-Speech (TTS) Implementation Comparison: iOS vs KMP

## Executive Summary

This document provides a comprehensive comparison between the Text-to-Speech (TTS) implementations in the iOS SDK (Swift) and the Kotlin Multiplatform (KMP) SDK. The analysis reveals significant architectural differences, platform-specific capabilities, and implementation gaps that need to be addressed for cross-platform parity.

## iOS Implementation

### TTSService Structure

**Location**: `sdk/runanywhere-swift/Sources/RunAnywhere/Components/TTS/TTSComponent.swift`

```swift
public protocol TTSService: AnyObject {
    func initialize() async throws
    func synthesize(text: String, options: TTSOptions) async throws -> Data
    func synthesizeStream(text: String, options: TTSOptions,
                         onChunk: @escaping (Data) -> Void) async throws
    func stop()
    var isSynthesizing: Bool { get }
    var availableVoices: [String] { get }
    func cleanup() async
}
```

**Key Features:**
- **Protocol-driven design** with clean service abstractions
- **AsyncSequence-based streaming** with callback handlers
- **Native iOS integration** using `AVSpeechSynthesizer`
- **Audio session management** for iOS/tvOS/watchOS
- **Event-driven architecture** integrated with voice pipeline

### Voice Management

```swift
public struct TTSOptions: Sendable {
    public let voice: String?         // Voice identifier
    public let language: String       // Language code (e.g., "en-US")
    public let rate: Float           // 0.0 to 2.0, 1.0 is normal
    public let pitch: Float          // 0.0 to 2.0, 1.0 is normal
    public let volume: Float         // 0.0 to 1.0
    public let audioFormat: AudioFormat
    public let sampleRate: Int
    public let useSSML: Bool
}
```

**Available Formats:**
```swift
public enum AudioFormat: String, Sendable {
    case wav = "wav"
    case mp3 = "mp3"
    case m4a = "m4a"
    case flac = "flac"
    case pcm = "pcm"
    case opus = "opus"
}
```

### Audio Generation

**SystemTTSService Implementation:**
```swift
public final class SystemTTSService: NSObject, TTSService {
    private let synthesizer = AVSpeechSynthesizer()

    public func synthesize(text: String, options: TTSOptions) async throws -> Data {
        let utterance = AVSpeechUtterance(string: text)

        // Configure voice
        if let speechVoice = AVSpeechSynthesisVoice(language: voiceLanguage) {
            utterance.voice = speechVoice
        }

        // Configure parameters
        utterance.rate = options.rate * AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = options.pitch
        utterance.volume = options.volume

        synthesizer.speak(utterance)
        return Data() // System TTS doesn't provide raw audio data
    }
}
```

### Streaming Support

**Progressive TTS Handler** (`StreamingTTSOperation.swift`):
```swift
public class StreamingTTSHandler {
    private var spokenText = ""
    private var pendingBuffer = ""
    private let sentenceDelimiters: CharacterSet = CharacterSet(charactersIn: ".!?")

    public func processToken(_ token: String, options: TTSOptions? = nil) async -> Bool {
        pendingBuffer += token
        let sentences = extractCompleteSentences()

        if !sentences.isEmpty {
            for sentence in sentences {
                await speakSentence(sentence, options: options)
            }
            return true
        }
        return false
    }
}
```

**Key Streaming Features:**
- **Sentence-by-sentence synthesis** during text generation
- **Intelligent buffering** with delimiter detection
- **Progressive playback** for real-time experience
- **Integration with voice pipeline** events

### Language Handling

**Supported Languages:**
- Voice discovery through `AVSpeechSynthesisVoice.speechVoices()`
- Platform-native voice support (Siri voices, system voices)
- Neural voice support with `useNeuralVoice` flag
- Language-specific voice selection

## KMP Implementation

### Common Interface

**Location**: `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/components/TTSComponent.kt`

```kotlin
interface TTSService {
    suspend fun initialize()
    suspend fun synthesize(text: String, options: TTSOptions): ByteArray
    suspend fun synthesizeStream(text: String, options: TTSOptions, onChunk: suspend (ByteArray) -> Unit)
    fun synthesizeStream(text: String, options: TTSOptions): Flow<ByteArray>
    fun stop()
    val isSynthesizing: Boolean
    val availableVoices: List<String>
    fun getAllVoices(): List<TTSVoice>
    suspend fun cleanup()
    suspend fun loadModel(modelInfo: ModelInfo)
    fun cancelCurrent()
}
```

**Key Features:**
- **Coroutines-based async** with `suspend` functions
- **Flow-based streaming** using Kotlin reactive streams
- **Rich voice metadata** with structured `TTSVoice` objects
- **Model loading support** for custom TTS models
- **Provider pattern** for extensibility

### Component Design

```kotlin
class TTSComponent(private val ttsConfiguration: TTSConfiguration) : BaseComponent<TTSService>(ttsConfiguration) {
    private val _isSynthesizing = MutableStateFlow(false)
    val isSynthesizing: StateFlow<Boolean> = _isSynthesizing.asStateFlow()

    private var streamingTTSHandler: StreamingTTSHandler? = null
    private val ssmlProcessor = DefaultSSMLProcessor()

    override suspend fun createService(): TTSService {
        val provider = ModuleRegistry.ttsProvider(ttsConfiguration.modelId)
        return if (provider != null) {
            TTSServiceAdapter(provider)
        } else {
            DefaultTTSService()
        }
    }
}
```

### Voice Management

**Rich Voice Objects:**
```kotlin
@Serializable
data class TTSVoice(
    val id: String,
    val name: String,
    val language: String,
    val gender: TTSGender,
    val style: TTSStyle = TTSStyle.NEUTRAL
)

enum class TTSGender { MALE, FEMALE, NEUTRAL }

enum class TTSStyle {
    NEUTRAL, CHEERFUL, SAD, ANGRY, FEARFUL,
    FRIENDLY, HOPEFUL, SHOUTING, WHISPERING,
    NEWSCAST, CUSTOMER_SERVICE
}
```

**Advanced Options:**
```kotlin
@Serializable
data class TTSOptions(
    val voiceId: String? = null,
    val voice: TTSVoice = TTSVoice.DEFAULT,
    val language: String = "en-US",
    val rate: Float = 1.0f,
    val pitch: Float = 1.0f,
    val volume: Float = 1.0f,
    val audioFormat: AudioFormat = AudioFormat.PCM,
    val sampleRate: Int = 16000,
    val useSSML: Boolean = false,
    val outputFormat: TTSOutputFormat? = null  // Backward compatibility
)
```

### Platform-Specific Implementations

#### Android
**Status: MISSING** - No Android-specific TTS implementation found
**Expected Location**: `src/androidMain/kotlin/com/runanywhere/sdk/components/tts/AndroidTTSService.kt`

**Expected Implementation:**
```kotlin
// Missing: Android TextToSpeech integration
actual class AndroidTTSService(private val context: Context) : TTSService {
    private var textToSpeech: TextToSpeech? = null

    override suspend fun initialize() {
        // Initialize Android TextToSpeech engine
    }

    override suspend fun synthesize(text: String, options: TTSOptions): ByteArray {
        // Use Android TTS API
    }
}
```

#### JVM
**Location**: `sdk/runanywhere-kotlin/src/jvmMain/kotlin/com/runanywhere/sdk/components/tts/JvmTTSService.kt`

```kotlin
class JvmTTSService : TTSService {
    override suspend fun synthesize(text: String, options: TTSOptions): ByteArray {
        return when {
            isMacOS() -> synthesizeWithMacOSSay(text, voice, options.rate, options.pitch, options.volume)
            isWindows() -> synthesizeWithWindowsSAPI(text, voice, options.rate, options.pitch, options.volume)
            isLinux() -> synthesizeWithLinuxTTS(text, voice, options.rate, options.pitch, options.volume)
            else -> generateSilentAudio(text.length)
        }
    }
}
```

**Platform Support:**
- **macOS**: Uses system `say` command with WAV output
- **Windows**: SAPI integration (not implemented - returns silent audio)
- **Linux**: eSpeak and Festival TTS engines
- **Fallback**: Generates silent audio with realistic duration

### Audio Format Support

```kotlin
enum class AudioFormat {
    PCM, WAV, MP3, AAC, FLAC, OPUS
}

enum class TTSOutputFormat {
    PCM_8KHZ, PCM_16KHZ, PCM_24KHZ, PCM_48KHZ, MP3, OGG_VORBIS, OPUS
}
```

### Streaming Implementation

**StreamingTTSHandler (KMP equivalent):**
```kotlin
class StreamingTTSHandler(private val ttsService: TTSService) {
    private var spokenText = ""
    private var pendingBuffer = ""
    private val sentenceDelimiters = setOf('.', '!', '?')

    suspend fun processToken(token: String, options: TTSOptions? = null): Boolean {
        pendingBuffer += token
        val sentences = extractCompleteSentences()

        return if (sentences.isNotEmpty()) {
            for (sentence in sentences) {
                speakSentence(sentence, options ?: TTSOptions())
            }
            true
        } else false
    }

    fun processTokenFlow(token: String, options: TTSOptions): Flow<ByteArray> = flow {
        pendingBuffer += token
        val sentences = extractCompleteSentences()

        for (sentence in sentences) {
            if (sentence.length >= minSentenceLength) {
                val audioData = ttsService.synthesize(sentence, options)
                if (audioData.isNotEmpty()) {
                    emit(audioData)
                }
                spokenText += sentence
            }
        }
    }
}
```

## Voice Options Comparison

| Feature | iOS | KMP |
|---------|-----|-----|
| **Voice Selection** | String-based identifiers | Rich `TTSVoice` objects |
| **Gender Support** | Implicit from voice | Explicit `TTSGender` enum |
| **Style Support** | None | Rich emotional styles (12+ options) |
| **Language Support** | System voices | Structured language codes |
| **Neural Voices** | `useNeuralVoice` flag | Not explicitly supported |
| **Voice Discovery** | `availableVoices: [String]` | `getAllVoices(): List<TTSVoice>` |

### iOS Voice System
- Relies on system-provided voices (`AVSpeechSynthesisVoice`)
- Simple string-based selection
- Automatic language detection
- Neural voice enhancement available

### KMP Voice System
- Rich metadata with gender and style information
- Structured voice objects with serialization support
- Extensible style system for emotional expression
- Platform-agnostic voice representation

## Audio Format Comparison

| Format | iOS Support | KMP Support | Notes |
|--------|-------------|-------------|-------|
| **PCM** | ✅ | ✅ | Primary format |
| **WAV** | ✅ | ✅ | Cross-platform |
| **MP3** | ✅ | ✅ | Compressed audio |
| **AAC** | ✅ | ✅ | Apple preferred |
| **FLAC** | ✅ | ✅ | Lossless compression |
| **Opus** | ✅ | ✅ | Web standard |
| **M4A** | ✅ | ❌ | iOS specific |
| **OGG Vorbis** | ❌ | ✅ | KMP specific |

### Sample Rate Support
- **iOS**: Configurable via `TTSOptions.sampleRate` (typically 16kHz, 44.1kHz)
- **KMP**: Fixed per format, configurable via `TTSOutputFormat` enum (8kHz to 48kHz)

## Streaming Capabilities Comparison

| Capability | iOS | KMP | Notes |
|------------|-----|-----|-------|
| **Progressive Synthesis** | ✅ Sentence-based | ✅ Sentence-based | Both support real-time |
| **Buffer Management** | ✅ Intelligent | ✅ Character-based | iOS more sophisticated |
| **Delimiter Detection** | ✅ CharacterSet | ✅ Character array | Similar functionality |
| **Streaming API** | Callback-based | Flow-based | Platform idioms |
| **Chunk Processing** | Event-driven | Reactive streams | Different patterns |
| **Pipeline Integration** | ✅ Full integration | ❌ Basic support | iOS more mature |

### iOS Streaming Strengths
- Tight integration with voice pipeline events
- Sophisticated sentence boundary detection
- Event-driven coordination with other components
- Real-time playback during text generation

### KMP Streaming Strengths
- Flow-based reactive programming model
- Both callback and Flow APIs for flexibility
- Clean separation of concerns
- Platform-agnostic streaming interface

## Gaps and Misalignments

### Critical Gaps

#### 1. Android Platform Implementation
**Status**: MISSING
**Impact**: HIGH
- No Android `TextToSpeech` integration
- Missing Android-specific voice discovery
- No Android audio session management

#### 2. Windows SAPI Integration
**Status**: INCOMPLETE
**Impact**: MEDIUM
- JVM service returns silent audio on Windows
- No COM interop for Windows SAPI
- Missing Windows voice enumeration

#### 3. Raw Audio Data Access
**Status**: iOS LIMITATION
**Impact**: MEDIUM
- iOS `SystemTTSService` returns empty `Data()`
- Cannot process raw audio in iOS pipeline
- Limits audio processing capabilities

### Feature Misalignments

#### 1. Voice Style System
- **iOS**: No emotional style support
- **KMP**: Rich style system with 12+ options
- **Gap**: iOS could benefit from style support

#### 2. SSML Processing
- **iOS**: Basic SSML flag, limited parsing
- **KMP**: Enhanced processor with validation
- **Gap**: iOS needs improved SSML support

#### 3. Model Loading
- **iOS**: No custom model support
- **KMP**: Built-in model loading interface
- **Gap**: iOS lacks extensibility for custom models

#### 4. Event Integration
- **iOS**: Comprehensive pipeline events
- **KMP**: Basic `StateFlow` state tracking
- **Gap**: KMP needs richer event system

### Audio Processing Gaps

#### 1. Duration Estimation
- **iOS**: Calculation from audio data
- **KMP**: Estimation based on text length and format
- **Gap**: KMP needs improved duration calculation

#### 2. Phoneme Timestamps
- **iOS**: Support for phoneme timing (interface defined)
- **KMP**: Phoneme support in metadata structure
- **Gap**: Neither implementation provides actual phoneme data

#### 3. Real-time Processing
- **iOS**: Direct playback through `AVSpeechSynthesizer`
- **KMP**: Byte array output requires separate playback
- **Gap**: KMP lacks integrated playback system

## Recommendations to Address Gaps

### High Priority

#### 1. Implement Android TTS Service
```kotlin
// android/kotlin/com/runanywhere/sdk/components/tts/AndroidTTSService.kt
actual class AndroidTTSService(private val context: Context) : TTSService {
    private var textToSpeech: TextToSpeech? = null

    override suspend fun initialize() {
        textToSpeech = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                initializationComplete()
            }
        }
    }

    override suspend fun synthesize(text: String, options: TTSOptions): ByteArray {
        return withContext(Dispatchers.IO) {
            val utteranceId = UUID.randomUUID().toString()
            val bundle = Bundle().apply {
                putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
            }

            textToSpeech?.synthesizeToFile(text, bundle, outputFile, utteranceId)
            // Return audio file as ByteArray
        }
    }
}
```

#### 2. Complete Windows SAPI Integration
```kotlin
// Windows COM interop or JNI integration needed
class WindowsSAPIService : TTSService {
    private external fun initializeWindowsSAPI(): Boolean
    private external fun synthesizeWithSAPI(text: String, voice: String, rate: Float, pitch: Float): ByteArray

    companion object {
        init {
            System.loadLibrary("windowstts")
        }
    }
}
```

#### 3. iOS Raw Audio Data Support
**Option 1**: Alternative TTS Engine
```swift
// Use third-party TTS engine that provides audio data
import NeuralVoice // Hypothetical

class NeuralTTSService: TTSService {
    func synthesize(text: String, options: TTSOptions) async throws -> Data {
        return try await NeuralVoice.synthesize(text: text, voice: options.voice)
    }
}
```

**Option 2**: Audio Capture
```swift
// Capture system audio during synthesis
class CapturingTTSService: TTSService {
    private let audioEngine = AVAudioEngine()

    func synthesize(text: String, options: TTSOptions) async throws -> Data {
        // Setup audio tap to capture synthesizer output
        // This requires more complex audio routing
    }
}
```

### Medium Priority

#### 4. Voice Standardization
```kotlin
// Common voice representation across platforms
data class UnifiedVoice(
    val id: String,
    val name: String,
    val language: String,
    val gender: VoiceGender,
    val style: VoiceStyle? = null,
    val isNeural: Boolean = false,
    val platformSpecific: Map<String, Any> = emptyMap()
)
```

#### 5. Enhanced Event System for KMP
```kotlin
// Event system matching iOS pipeline integration
sealed class TTSEvent {
    object Started : TTSEvent()
    object Completed : TTSEvent()
    data class Progress(val progress: Float) : TTSEvent()
    data class Error(val error: Throwable) : TTSEvent()
}

class TTSComponent {
    private val _events = MutableSharedFlow<TTSEvent>()
    val events: SharedFlow<TTSEvent> = _events.asSharedFlow()
}
```

#### 6. SSML Enhancement for iOS
```swift
// Enhanced SSML processing
class SSMLProcessor {
    func parse(_ ssml: String) -> ParsedSSML
    func validate(_ ssml: String) -> ValidationResult
    func extractPlainText(_ ssml: String) -> String
}
```

### Low Priority

#### 7. Audio Pipeline Alignment
- Standardize audio format handling across platforms
- Common duration estimation algorithms
- Unified sample rate conversion

#### 8. Testing Framework
- Shared mock TTS implementations
- Common test scenarios for both platforms
- Cross-platform validation suite

## Implementation Timeline

### Phase 1: Critical Gaps (2-3 weeks)
1. Android TTS service implementation
2. Windows SAPI integration
3. Basic event system for KMP

### Phase 2: Feature Alignment (2-3 weeks)
1. Voice standardization
2. Enhanced SSML processing
3. Audio format alignment

### Phase 3: Advanced Features (3-4 weeks)
1. iOS raw audio data support
2. Advanced streaming optimizations
3. Comprehensive testing framework

## Conclusion

The TTS implementations show complementary strengths:

- **iOS**: Mature integration with native platform capabilities and sophisticated voice pipeline
- **KMP**: Modern reactive architecture with rich metadata system and cross-platform design

Key gaps to address:
1. **Android implementation** - Critical missing functionality
2. **Windows integration** - Platform completeness
3. **iOS raw audio access** - Feature parity
4. **Event system alignment** - Architectural consistency

The KMP implementation demonstrates excellent architectural design with room for platform-specific enhancements, while the iOS implementation shows mature integration patterns that could inform the KMP event system design.
