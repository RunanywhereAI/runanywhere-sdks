# Module 2: STT Component Implementation Plan
**Priority**: 🔴 CRITICAL
**Estimated Timeline**: 5-7 days
**Dependencies**: None (can run parallel with LLM module)
**Team Assignment**: 1 Senior Developer with Audio/JNI experience

## Executive Summary

The STT component has complete architecture but lacks Whisper engine integration. While interfaces are production-ready and perfectly aligned with iOS, all transcription methods return placeholder text. This module focuses on implementing WhisperKit integration with native whisper.cpp bindings.

**Current Status**: Architecture 100% complete, Whisper integration 0% complete
**Target**: Production STT with real-time transcription and streaming support

---

## Current State Analysis

### ✅ Architectural Excellence Achieved
- Perfect API alignment with iOS STTComponent
- Complete service provider pattern implementation
- Full event system integration (ComponentInitializationEvent, STTStreamEvent)
- Enhanced streaming with Flow-based architecture
- Comprehensive data models (STTInput, STTOutput, TimestampInfo)
- Language detection and alternative transcriptions support

### ❌ Critical Implementation Gap
```kotlin
// Current placeholder blocking all functionality
override suspend fun transcribe(audioData: FloatArray): TranscriptionResult {
    delay(100) // Simulate processing time
    return TranscriptionResult(
        transcript = "Android transcription placeholder", // ← PLACEHOLDER
        confidence = 0.95f,
        language = "en",
        segments = emptyList()
    )
}
```

### 🎯 Implementation Target
```kotlin
override suspend fun transcribe(audioData: FloatArray): TranscriptionResult {
    val result = WhisperJNI.transcribe(whisperContext, audioData)
    return result.toTranscriptionResult() // ← REAL WHISPER TRANSCRIPTION
}
```

---

## Phase 1: Whisper JNI Foundation (Day 1-2)
**Duration**: 1.5-2 days
**Priority**: CRITICAL

### Task 1.1: Native Whisper Integration Setup
**Location**: `native/whisper-jni/`

#### Step 1: JNI Interface Design (Day 1)
```cpp
// native/whisper-jni/src/main/cpp/whisper_jni.cpp
#include <jni.h>
#include "whisper.h"
#include <vector>
#include <string>

extern "C" {
    JNIEXPORT jlong JNICALL
    Java_com_runanywhere_sdk_whisper_WhisperJNI_initContext(JNIEnv *env, jobject thiz, jstring model_path) {
        const char *path = env->GetStringUTFChars(model_path, nullptr);

        struct whisper_context_params cparams = whisper_context_default_params();
        struct whisper_context *ctx = whisper_init_from_file_with_params(path, cparams);

        env->ReleaseStringUTFChars(model_path, path);
        return reinterpret_cast<jlong>(ctx);
    }

    JNIEXPORT jobject JNICALL
    Java_com_runanywhere_sdk_whisper_WhisperJNI_transcribe(JNIEnv *env, jobject thiz,
                                                           jlong ctx_ptr, jfloatArray audio_data) {
        struct whisper_context *ctx = reinterpret_cast<struct whisper_context*>(ctx_ptr);

        jsize length = env->GetArrayLength(audio_data);
        jfloat *audio = env->GetFloatArrayElements(audio_data, nullptr);

        // Whisper transcription
        struct whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        wparams.language = "en";
        wparams.translate = false;
        wparams.print_progress = false;
        wparams.print_timestamps = true;

        int result = whisper_full(ctx, wparams, audio, length);

        if (result != 0) {
            env->ReleaseFloatArrayElements(audio_data, audio, JNI_ABORT);
            return nullptr;
        }

        // Extract results
        const int n_segments = whisper_full_n_segments(ctx);
        std::string full_text;

        // Create Java result object
        jclass resultClass = env->FindClass("com/runanywhere/sdk/whisper/WhisperResult");
        jmethodID constructor = env->GetMethodID(resultClass, "<init>", "(Ljava/lang/String;F[Lcom/runanywhere/sdk/whisper/WhisperSegment;)V");

        // Build segments array
        jclass segmentClass = env->FindClass("com/runanywhere/sdk/whisper/WhisperSegment");
        jobjectArray segments = env->NewObjectArray(n_segments, segmentClass, nullptr);

        for (int i = 0; i < n_segments; ++i) {
            const char *text = whisper_full_get_segment_text(ctx, i);
            const int64_t t0 = whisper_full_get_segment_t0(ctx, i);
            const int64_t t1 = whisper_full_get_segment_t1(ctx, i);

            full_text += text;

            // Create segment object
            jstring segmentText = env->NewStringUTF(text);
            jmethodID segmentConstructor = env->GetMethodID(segmentClass, "<init>", "(Ljava/lang/String;JJ)V");
            jobject segment = env->NewObject(segmentClass, segmentConstructor, segmentText, t0, t1);
            env->SetObjectArrayElement(segments, i, segment);
        }

        jstring transcriptText = env->NewStringUTF(full_text.c_str());
        jobject result_obj = env->NewObject(resultClass, constructor, transcriptText, 0.95f, segments);

        env->ReleaseFloatArrayElements(audio_data, audio, JNI_ABORT);
        return result_obj;
    }

    JNIEXPORT void JNICALL
    Java_com_runanywhere_sdk_whisper_WhisperJNI_freeContext(JNIEnv *env, jobject thiz, jlong ctx_ptr) {
        struct whisper_context *ctx = reinterpret_cast<struct whisper_context*>(ctx_ptr);
        if (ctx) {
            whisper_free(ctx);
        }
    }
}
```

#### Step 2: Kotlin JNI Interface (Day 1)
```kotlin
// native/whisper-jni/src/main/kotlin/WhisperJNI.kt
object WhisperJNI {
    external fun initContext(modelPath: String): Long
    external fun transcribe(contextPtr: Long, audioData: FloatArray): WhisperResult?
    external fun freeContext(contextPtr: Long)

    init {
        System.loadLibrary("whisper-jni")
    }
}

data class WhisperResult(
    val transcript: String,
    val confidence: Float,
    val segments: Array<WhisperSegment>
)

data class WhisperSegment(
    val text: String,
    val startTime: Long, // microseconds
    val endTime: Long    // microseconds
)
```

### Task 1.2: Build System Integration (Day 2)
**Files**: `native/whisper-jni/build.gradle.kts`

```kotlin
plugins {
    id("com.android.library")
    kotlin("android")
}

android {
    compileSdk = 34

    defaultConfig {
        minSdk = 24

        externalNativeBuild {
            cmake {
                cppFlags("-std=c++17")
                arguments("-DANDROID_ARM_NEON=TRUE")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
}
```

**Success Criteria**:
- [ ] WhisperJNI loads native library successfully
- [ ] Context initialization works with test model
- [ ] Basic transcription returns real results
- [ ] Memory cleanup works without leaks

---

## Phase 2: Service Implementation (Day 2-4)
**Duration**: 2-3 days
**Priority**: CRITICAL

### Task 2.1: WhisperSTTService Implementation
**Files**: `modules/runanywhere-whisperkit/src/androidMain/kotlin/AndroidWhisperKitService.kt`

```kotlin
class AndroidWhisperKitService(private val modelPath: String) : STTService {
    private var whisperContext: Long = 0L
    private var isInitialized = false

    override suspend fun initialize(): Boolean = withContext(Dispatchers.IO) {
        try {
            whisperContext = WhisperJNI.initContext(modelPath)
            isInitialized = whisperContext != 0L

            if (isInitialized) {
                logger.info("Whisper STT Service initialized successfully with model: $modelPath")
            } else {
                logger.error("Failed to initialize Whisper context")
            }

            isInitialized
        } catch (e: Exception) {
            logger.error("Exception during Whisper initialization", e)
            false
        }
    }

    override suspend fun transcribe(audioData: FloatArray): TranscriptionResult =
        withContext(Dispatchers.IO) {
            if (!isInitialized) {
                throw IllegalStateException("Whisper STT Service not initialized")
            }

            val startTime = System.currentTimeMillis()
            val whisperResult = WhisperJNI.transcribe(whisperContext, audioData)
                ?: throw RuntimeException("Whisper transcription failed")

            val endTime = System.currentTimeMillis()

            TranscriptionResult(
                transcript = whisperResult.transcript.trim(),
                confidence = whisperResult.confidence,
                language = detectLanguage(whisperResult.transcript),
                processingTimeMs = endTime - startTime,
                segments = whisperResult.segments.map { segment ->
                    TimestampInfo(
                        text = segment.text.trim(),
                        startTime = segment.startTime / 1000, // Convert to milliseconds
                        endTime = segment.endTime / 1000,
                        confidence = whisperResult.confidence
                    )
                }
            )
        }

    override suspend fun transcribeWithTimestamps(audioData: FloatArray): List<TimestampInfo> =
        withContext(Dispatchers.IO) {
            val result = transcribe(audioData)
            result.segments
        }

    override suspend fun detectLanguage(audioData: FloatArray): Map<String, Float> =
        withContext(Dispatchers.IO) {
            // For now, return English with high confidence
            // TODO: Implement actual language detection using Whisper
            mapOf("en" to 0.9f)
        }

    override suspend fun transcribeStream(
        audioStream: Flow<FloatArray>,
        onPartial: (String) -> Unit
    ): Flow<String> = flow {
        var accumulatedText = ""

        audioStream.collect { audioChunk ->
            try {
                val result = transcribe(audioChunk)
                val newText = result.transcript

                if (newText.isNotEmpty() && newText != accumulatedText) {
                    accumulatedText = newText
                    onPartial(newText)
                    emit(newText)
                }
            } catch (e: Exception) {
                logger.error("Error in streaming transcription", e)
                // Continue processing despite errors
            }
        }
    }.flowOn(Dispatchers.IO)

    override fun cleanup() {
        if (isInitialized) {
            WhisperJNI.freeContext(whisperContext)
            whisperContext = 0L
            isInitialized = false
            logger.info("Whisper STT Service cleaned up")
        }
    }

    override val isReady: Boolean get() = isInitialized
    override val currentModel: String? get() = if (isInitialized) modelPath else null

    private fun detectLanguage(text: String): String {
        // Simple language detection based on text characteristics
        // TODO: Use Whisper's built-in language detection
        return "en"
    }
}
```

### Task 2.2: JVM WhisperSTTService Implementation
**Files**: `modules/runanywhere-whisperkit/src/jvmMain/kotlin/JvmWhisperKitService.kt`

```kotlin
class JvmWhisperKitService(private val modelPath: String) : STTService {
    // Similar implementation to Android version
    // Same JNI bindings work for JVM platforms

    companion object {
        init {
            // Load platform-specific native library
            when {
                System.getProperty("os.name").contains("Mac") -> {
                    System.loadLibrary("whisper-jni-macos")
                }
                System.getProperty("os.name").contains("Linux") -> {
                    System.loadLibrary("whisper-jni-linux")
                }
                System.getProperty("os.name").contains("Windows") -> {
                    System.loadLibrary("whisper-jni-windows")
                }
                else -> {
                    throw UnsupportedOperationException("Unsupported platform for Whisper JNI")
                }
            }
        }
    }
}
```

### Task 2.3: WhisperKit Provider Implementation
**Files**: `modules/runanywhere-whisperkit/src/commonMain/kotlin/WhisperKitProvider.kt`

```kotlin
class WhisperKitProvider : STTServiceProvider {
    override suspend fun createSTTService(configuration: STTConfiguration): STTService {
        val modelPath = resolveModelPath(configuration.modelId)

        return when {
            isAndroid() -> AndroidWhisperKitService(modelPath)
            isJvm() -> JvmWhisperKitService(modelPath)
            else -> throw UnsupportedOperationException("Whisper not supported on this platform")
        }.also { service ->
            if (!service.initialize()) {
                throw SDKError.ComponentInitializationFailed("Failed to initialize Whisper STT service")
            }
        }
    }

    override fun canHandle(modelId: String?): Boolean {
        return modelId?.let {
            it.startsWith("whisper") ||
            it.contains("whisper") ||
            it.endsWith(".bin")
        } ?: true
    }

    override val name: String = "WhisperKit Provider"

    private fun resolveModelPath(modelId: String?): String {
        return when (modelId) {
            "whisper-base" -> "models/whisper-base.bin"
            "whisper-small" -> "models/whisper-small.bin"
            "whisper-medium" -> "models/whisper-medium.bin"
            "whisper-large" -> "models/whisper-large.bin"
            else -> "models/whisper-base.bin" // Default fallback
        }
    }

    private fun isAndroid(): Boolean =
        System.getProperty("java.vendor.url")?.contains("android") == true

    private fun isJvm(): Boolean = !isAndroid()
}
```

**Success Criteria**:
- [ ] WhisperSTTService initializes with real model
- [ ] Transcription returns real Whisper output
- [ ] Timestamps are accurate and properly formatted
- [ ] Language detection works for common languages
- [ ] Streaming transcription produces real-time results

---

## Phase 3: Model Management Integration (Day 4-5)
**Duration**: 1-2 days
**Priority**: HIGH

### Task 3.1: Whisper Model Download
**Files**: `src/commonMain/kotlin/com/runanywhere/sdk/models/WhisperModelManager.kt`

```kotlin
class WhisperModelManager(
    private val downloadService: DownloadService,
    private val fileManager: FileManager
) {
    private val baseUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    private val modelUrls = mapOf(
        "whisper-base" to "$baseUrl/ggml-base.bin",
        "whisper-small" to "$baseUrl/ggml-small.bin",
        "whisper-medium" to "$baseUrl/ggml-medium.bin",
        "whisper-large" to "$baseUrl/ggml-large.bin"
    )

    suspend fun downloadModel(modelId: String): Flow<DownloadProgress> = flow {
        val url = modelUrls[modelId]
            ?: throw IllegalArgumentException("Unknown Whisper model: $modelId")

        val localPath = fileManager.getModelPath("$modelId.bin")

        if (fileManager.exists(localPath)) {
            emit(DownloadProgress.Completed(modelId, localPath))
            return@flow
        }

        emit(DownloadProgress.Started(modelId))

        downloadService.downloadFile(url, localPath) { progress ->
            emit(DownloadProgress.InProgress(modelId, progress))
        }

        if (fileManager.exists(localPath)) {
            if (validateWhisperModel(localPath)) {
                emit(DownloadProgress.Completed(modelId, localPath))
            } else {
                fileManager.delete(localPath)
                emit(DownloadProgress.Failed(modelId, "Model validation failed"))
            }
        } else {
            emit(DownloadProgress.Failed(modelId, "Download failed"))
        }
    }

    private suspend fun validateWhisperModel(modelPath: String): Boolean {
        return try {
            val context = WhisperJNI.initContext(modelPath)
            if (context != 0L) {
                WhisperJNI.freeContext(context)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            logger.error("Model validation failed", e)
            false
        }
    }
}
```

### Task 3.2: Auto-Registration Module
**Files**: `modules/runanywhere-whisperkit/src/commonMain/kotlin/WhisperKitModule.kt`

```kotlin
object WhisperKitModule {
    fun register() {
        ModuleRegistry.registerSTTProvider(WhisperKitProvider())
        logger.info("WhisperKit provider registered successfully")
    }

    suspend fun ensureDefaultModel(): Boolean {
        val modelManager = WhisperModelManager(
            downloadService = ServiceContainer.shared.downloadService,
            fileManager = ServiceContainer.shared.fileManager
        )

        return try {
            modelManager.downloadModel("whisper-base").collect { progress ->
                when (progress) {
                    is DownloadProgress.Completed -> {
                        logger.info("Default Whisper model ready: ${progress.localPath}")
                        return@collect
                    }
                    is DownloadProgress.Failed -> {
                        logger.error("Failed to download default Whisper model: ${progress.error}")
                        throw RuntimeException(progress.error)
                    }
                    else -> {
                        // Continue downloading
                    }
                }
            }
            true
        } catch (e: Exception) {
            logger.error("Failed to ensure default Whisper model", e)
            false
        }
    }
}
```

**Success Criteria**:
- [ ] Whisper models download automatically
- [ ] Model validation works before use
- [ ] Provider registration happens automatically
- [ ] Default model is available after SDK initialization

---

## Phase 4: Advanced Features & Integration (Day 5-7)
**Duration**: 2-3 days
**Priority**: MEDIUM

### Task 4.1: Enhanced Streaming Implementation
```kotlin
// Enhanced streaming with VAD integration
class StreamingSTTService(
    private val whisperService: WhisperSTTService,
    private val vadService: VADService
) {
    fun transcribeStreamWithVAD(
        audioStream: Flow<ByteArray>
    ): Flow<STTStreamEvent> = flow {
        var audioBuffer = mutableListOf<Float>()
        var lastTranscript = ""

        audioStream.collect { audioData ->
            val floatData = audioData.toFloatArray()
            val vadResult = vadService.processAudio(floatData)

            when (vadResult.activityType) {
                SpeechActivityType.SPEECH_START -> {
                    emit(STTStreamEvent.SpeechStarted)
                    audioBuffer.clear()
                    audioBuffer.addAll(floatData.toList())
                }

                SpeechActivityType.SPEECH_ACTIVE -> {
                    audioBuffer.addAll(floatData.toList())

                    // Transcribe accumulated audio
                    if (audioBuffer.size > 16000) { // 1 second at 16kHz
                        val result = whisperService.transcribe(audioBuffer.toFloatArray())
                        if (result.transcript != lastTranscript) {
                            lastTranscript = result.transcript
                            emit(STTStreamEvent.PartialTranscript(result.transcript))
                        }
                    }
                }

                SpeechActivityType.SPEECH_END -> {
                    if (audioBuffer.isNotEmpty()) {
                        val finalResult = whisperService.transcribe(audioBuffer.toFloatArray())
                        emit(STTStreamEvent.FinalTranscript(finalResult))
                        audioBuffer.clear()
                        lastTranscript = ""
                    }
                    emit(STTStreamEvent.SpeechEnded)
                }

                else -> {
                    // Continue collecting audio during silence
                }
            }
        }
    }
}
```

### Task 4.2: Language Detection Enhancement
```kotlin
// Enhanced language detection using Whisper's built-in capabilities
class WhisperLanguageDetector(private val whisperService: WhisperSTTService) {
    suspend fun detectLanguage(audioData: FloatArray): LanguageDetectionResult {
        // Use Whisper's language detection feature
        val supportedLanguages = listOf("en", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh")
        val probabilities = mutableMapOf<String, Float>()

        // For now, implement simple heuristic
        // TODO: Use Whisper's actual language detection API
        val transcript = whisperService.transcribe(audioData).transcript

        supportedLanguages.forEach { lang ->
            probabilities[lang] = calculateLanguageProbability(transcript, lang)
        }

        val detectedLanguage = probabilities.maxByOrNull { it.value }?.key ?: "en"

        return LanguageDetectionResult(
            detectedLanguage = detectedLanguage,
            confidence = probabilities[detectedLanguage] ?: 0.5f,
            allProbabilities = probabilities
        )
    }

    private fun calculateLanguageProbability(text: String, language: String): Float {
        // Simple heuristic-based language detection
        // TODO: Replace with actual Whisper language detection
        return when (language) {
            "en" -> if (text.matches(Regex(".*[a-zA-Z].*"))) 0.8f else 0.2f
            else -> 0.1f
        }
    }
}
```

### Task 4.3: Android App Integration
**Files**: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/`

```kotlin
// Application.kt - Auto-register Whisper provider
class RunAnywhereApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        lifecycleScope.launch {
            // Register STT provider
            WhisperKitModule.register()

            // Ensure default model is available
            val modelReady = WhisperKitModule.ensureDefaultModel()
            if (!modelReady) {
                logger.warning("Default Whisper model not available")
            }

            // Initialize SDK
            RunAnywhere.initialize(API_KEY, BASE_URL, SDKEnvironment.DEVELOPMENT)
        }
    }
}

// Update VoiceAssistantViewModel to use real STT
class VoiceAssistantViewModel : ViewModel() {
    private fun processAudioChunk(audioData: ByteArray) {
        viewModelScope.launch {
            try {
                val transcriptResult = RunAnywhere.transcribe(audioData)

                if (transcriptResult.isNotEmpty()) {
                    _uiState.value = _uiState.value.copy(
                        transcription = transcriptResult,
                        sessionState = VoiceSessionState.Processing
                    )

                    // Process with LLM
                    val response = RunAnywhere.generate(transcriptResult)

                    _uiState.value = _uiState.value.copy(
                        lastResponse = response,
                        sessionState = VoiceSessionState.Speaking
                    )
                }
            } catch (e: Exception) {
                logger.error("Voice processing error", e)
                _uiState.value = _uiState.value.copy(
                    sessionState = VoiceSessionState.Error(e.message ?: "Unknown error")
                )
            }
        }
    }
}
```

**Success Criteria**:
- [ ] Advanced streaming works with VAD integration
- [ ] Language detection produces accurate results
- [ ] Android app voice assistant uses real STT
- [ ] Real-time transcription appears in UI
- [ ] End-to-end voice pipeline works

---

## Risk Assessment & Mitigation

### High Risk Items 🔴
1. **JNI Integration Complexity**: Native library integration may be challenging
   - **Mitigation**: Start with existing whisper.cpp examples, incremental development
   - **Fallback**: Cloud-based STT service as temporary solution

2. **Model Size and Performance**: Whisper models are large (>100MB)
   - **Mitigation**: Start with base model, implement model caching
   - **Optimization**: Model compression and quantization

3. **Audio Format Compatibility**: Audio format conversion issues
   - **Mitigation**: Test with standard formats, implement proper conversion
   - **Validation**: Audio format validation before processing

### Medium Risk Items 🟡
1. **Platform-Specific Audio Issues**: Different audio handling across platforms
   - **Mitigation**: Platform-specific testing and validation
   - **Documentation**: Clear audio format requirements

2. **Real-time Performance**: Streaming transcription may have latency
   - **Mitigation**: Profile and optimize audio processing pipeline
   - **Fallback**: Batch processing for non-real-time use cases

---

## Success Metrics

### Functional Metrics ✅
- [ ] Real Whisper transcription (not placeholder) in all methods
- [ ] Streaming transcription produces real-time results
- [ ] Model loading succeeds for Whisper models
- [ ] Timestamps are accurate to within 100ms
- [ ] Language detection works for major languages

### Performance Metrics 📊
- **Model Loading**: < 5 seconds for base model
- **Transcription Speed**: > 2x real-time (process 2 seconds of audio in 1 second)
- **Memory Usage**: < 500MB RAM for base model
- **Latency**: < 1 second for short audio clips (< 10 seconds)

### Integration Metrics 🔗
- [ ] Android app voice assistant works with real STT
- [ ] SDK transcription methods return real results
- [ ] Component events are published correctly
- [ ] Provider registration works automatically

---

## Module Dependencies

### This Module Enables:
- **Module 4: Voice Pipeline** (needs real STT for voice assistant)
- **Module 6: Android App Completion** (needs working transcription)
- **Module 7: Speaker Diarization** (can build on STT foundation)

### Parallel Execution:
- Can run completely parallel with **Module 1: LLM Component**
- Independent of other modules until integration phase

This STT implementation plan provides real transcription capabilities that are essential for voice-based features and Android app completion.
