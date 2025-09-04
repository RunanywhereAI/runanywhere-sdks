# Android Sample App Implementation Plan
## Based on iOS RunAnywhereAI Sample App Architecture Analysis

### Table of Contents
1. [iOS Sample App Analysis Overview](#ios-sample-app-analysis-overview)
2. [Android Architecture Design](#android-architecture-design)
3. [Project Structure](#project-structure)
4. [Core Components Implementation](#core-components-implementation)
5. [Voice/STT Pipeline Implementation](#voicestt-pipeline-implementation)
6. [UI Components](#ui-components)
7. [Data Layer](#data-layer)
8. [Navigation Structure](#navigation-structure)
9. [Dependencies](#dependencies)
10. [Implementation Roadmap](#implementation-roadmap)

---

## iOS Sample App Analysis Overview

The iOS RunAnywhereAI sample application demonstrates a comprehensive AI platform with the following key characteristics:

### **Architecture Pattern**
- **MVVM with SwiftUI**: Clean separation of concerns with reactive UI
- **Event-driven Pipeline**: Modular voice pipeline with event-based communication
- **Singleton Services**: Shared managers for model handling and configuration
- **Modern Concurrency**: Async/await throughout with proper error handling

### **Key Features Identified**
1. **5-Tab Navigation**: Chat, Storage, Settings, Quiz, Voice
2. **Full Voice Assistant**: VAD → STT → LLM → TTS pipeline
3. **Transcription-Only Mode**: Simplified STT with speaker diarization
4. **Advanced Chat Interface**: Real-time streaming, thinking mode, analytics
5. **Model Management**: Dynamic loading, downloading, storage management
6. **Comprehensive Settings**: Routing policies, generation parameters, API config
7. **Analytics Integration**: Performance metrics, cost tracking
8. **Cross-platform Support**: iOS/macOS adaptive UI

### **Core Voice Pipeline Components**
- **Voice Activity Detection (VAD)**: Continuous listening with speech detection
- **Speech-to-Text (STT)**: WhisperKit integration with real-time transcription
- **Language Model (LLM)**: Local inference with streaming responses
- **Text-to-Speech (TTS)**: System voice integration
- **Speaker Diarization**: FluidAudio integration for speaker identification

---

## Android Architecture Design

### **Architecture Pattern**: MVVM + Repository + Clean Architecture
```
Presentation Layer (UI + ViewModels)
    ↓
Domain Layer (Use Cases + Models)
    ↓
Data Layer (Repositories + Data Sources)
```

### **Key Design Principles**
- **Single Activity Architecture**: MainActivity with Jetpack Compose Navigation
- **Dependency Injection**: Hilt for comprehensive DI
- **Repository Pattern**: Clean data access abstraction
- **Flow-based Reactive Programming**: StateFlow and SharedFlow for reactive UI
- **Coroutines**: Structured concurrency for async operations

---

## Project Structure

```
app/
├── src/
│   ├── main/
│   │   ├── java/com/runanywhere/android/
│   │   │   ├── RunAnywhereApplication.kt          // App initialization
│   │   │   ├── MainActivity.kt                    // Single activity container
│   │   │   │
│   │   │   ├── di/                                // Dependency Injection
│   │   │   │   ├── AppModule.kt
│   │   │   │   ├── NetworkModule.kt
│   │   │   │   ├── DatabaseModule.kt
│   │   │   │   └── AudioModule.kt
│   │   │   │
│   │   │   ├── presentation/                      // UI Layer
│   │   │   │   ├── navigation/
│   │   │   │   │   └── AppNavigation.kt
│   │   │   │   │
│   │   │   │   ├── chat/                         // Chat Interface
│   │   │   │   │   ├── ChatScreen.kt
│   │   │   │   │   ├── ChatViewModel.kt
│   │   │   │   │   └── components/
│   │   │   │   │       ├── MessageBubble.kt
│   │   │   │   │       ├── MessageInput.kt
│   │   │   │   │       ├── ThinkingMode.kt
│   │   │   │   │       └── AnalyticsChip.kt
│   │   │   │   │
│   │   │   │   ├── voice/                        // Voice Assistant
│   │   │   │   │   ├── VoiceAssistantScreen.kt
│   │   │   │   │   ├── VoiceAssistantViewModel.kt
│   │   │   │   │   ├── TranscriptionScreen.kt
│   │   │   │   │   ├── TranscriptionViewModel.kt
│   │   │   │   │   └── components/
│   │   │   │   │       ├── VoiceVisualizer.kt
│   │   │   │   │       ├── TranscriptDisplay.kt
│   │   │   │   │       ├── VoiceControls.kt
│   │   │   │   │       └── SpeakerBadge.kt
│   │   │   │   │
│   │   │   │   ├── storage/                      // Model Management
│   │   │   │   │   ├── StorageScreen.kt
│   │   │   │   │   ├── ModelListViewModel.kt
│   │   │   │   │   └── components/
│   │   │   │   │       ├── ModelCard.kt
│   │   │   │   │       └── DownloadProgress.kt
│   │   │   │   │
│   │   │   │   ├── settings/                     // Configuration
│   │   │   │   │   ├── SettingsScreen.kt
│   │   │   │   │   ├── SettingsViewModel.kt
│   │   │   │   │   └── components/
│   │   │   │   │       ├── ApiKeyInput.kt
│   │   │   │   │       ├── RoutingPolicySelector.kt
│   │   │   │   │       └── ParameterSlider.kt
│   │   │   │   │
│   │   │   │   ├── quiz/                         // Quiz Interface
│   │   │   │   │   ├── QuizScreen.kt
│   │   │   │   │   └── QuizViewModel.kt
│   │   │   │   │
│   │   │   │   └── common/                       // Shared Components
│   │   │   │       ├── LoadingIndicator.kt
│   │   │   │       ├── ErrorDisplay.kt
│   │   │   │       ├── PermissionHandler.kt
│   │   │   │       └── theme/
│   │   │   │           ├── Theme.kt
│   │   │   │           ├── Color.kt
│   │   │   │           └── Typography.kt
│   │   │   │
│   │   │   ├── domain/                           // Domain Layer
│   │   │   │   ├── models/                       // Domain Models
│   │   │   │   │   ├── ChatMessage.kt
│   │   │   │   │   ├── TranscriptSegment.kt
│   │   │   │   │   ├── VoiceAudioChunk.kt
│   │   │   │   │   ├── ModelInfo.kt
│   │   │   │   │   ├── SDKConfig.kt
│   │   │   │   │   └── Analytics.kt
│   │   │   │   │
│   │   │   │   ├── usecases/                     // Business Logic
│   │   │   │   │   ├── chat/
│   │   │   │   │   ├── voice/
│   │   │   │   │   ├── models/
│   │   │   │   │   └── settings/
│   │   │   │   │
│   │   │   │   └── repositories/                 // Repository Interfaces
│   │   │   │       ├── ChatRepository.kt
│   │   │   │       ├── VoiceRepository.kt
│   │   │   │       ├── ModelRepository.kt
│   │   │   │       └── SettingsRepository.kt
│   │   │   │
│   │   │   ├── data/                             // Data Layer
│   │   │   │   ├── repositories/                 // Repository Implementations
│   │   │   │   │   ├── ChatRepositoryImpl.kt
│   │   │   │   │   ├── VoiceRepositoryImpl.kt
│   │   │   │   │   ├── ModelRepositoryImpl.kt
│   │   │   │   │   └── SettingsRepositoryImpl.kt
│   │   │   │   │
│   │   │   │   ├── local/                        // Local Data Sources
│   │   │   │   │   ├── database/
│   │   │   │   │   │   ├── AppDatabase.kt
│   │   │   │   │   │   ├── entities/
│   │   │   │   │   │   └── dao/
│   │   │   │   │   ├── preferences/
│   │   │   │   │   └── keychain/
│   │   │   │   │
│   │   │   │   ├── remote/                       // Remote Data Sources
│   │   │   │   │   ├── api/
│   │   │   │   │   ├── dto/
│   │   │   │   │   └── interceptors/
│   │   │   │   │
│   │   │   │   └── services/                     // Core Services
│   │   │   │       ├── AudioCaptureService.kt
│   │   │   │       ├── VoicePipelineService.kt
│   │   │   │       ├── ModelManagerService.kt
│   │   │   │       ├── AnalyticsService.kt
│   │   │   │       └── KeychainService.kt
│   │   │   │
│   │   │   └── utils/                            // Utilities
│   │   │       ├── Constants.kt
│   │   │       ├── Extensions.kt
│   │   │       ├── AudioUtils.kt
│   │   │       └── PermissionUtils.kt
│   │   │
│   │   ├── res/                                  // Resources
│   │   │   ├── layout/
│   │   │   ├── values/
│   │   │   │   ├── colors.xml
│   │   │   │   ├── strings.xml
│   │   │   │   └── themes.xml
│   │   │   └── drawable/
│   │   │
│   │   └── AndroidManifest.xml
│   │
│   ├── test/                                     // Unit Tests
│   └── androidTest/                              // Integration Tests
│
└── build.gradle.kts                              // Dependencies
```

---

## Core Components Implementation

### **1. Application Class**

```kotlin
// RunAnywhereApplication.kt
@HiltAndroidApp
class RunAnywhereApplication : Application() {

    override fun onCreate() {
        super.onCreate()

        // Initialize SDK with framework adapters
        initializeSDK()

        // Setup logging and analytics
        setupLogging()
    }

    private fun initializeSDK() {
        lifecycleScope.launch(Dispatchers.IO) {
            try {
                RunAnywhereSDK.initialize(
                    context = this@RunAnywhereApplication,
                    config = SDKInitializationConfig(
                        frameworkAdapters = listOf(
                            WhisperCppAdapter(
                                modelPath = getWhisperModelPath(),
                                options = WhisperOptions(
                                    language = "auto",
                                    translate = false,
                                    enableVAD = true
                                )
                            ),
                            LlamaCppAdapter(
                                modelPath = getLlamaModelPath(),
                                options = LlamaOptions(
                                    contextSize = 2048,
                                    threads = Runtime.getRuntime().availableProcessors()
                                )
                            ),
                            VoiceActivityDetector(
                                sensitivity = VADSensitivity.MEDIUM,
                                minSpeechDuration = 250,
                                minSilenceDuration = 500
                            ),
                            SpeakerDiarizationAdapter(
                                threshold = 0.45f,
                                maxSpeakers = 8
                            )
                        ),
                        enableAnalytics = true,
                        enableCrashReporting = BuildConfig.DEBUG.not(),
                        logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.INFO
                    )
                )

                Log.i("RunAnywhereApp", "SDK initialized successfully")

            } catch (e: Exception) {
                Log.e("RunAnywhereApp", "Failed to initialize SDK", e)
                // Handle initialization failure gracefully
            }
        }
    }

    private fun setupLogging() {
        if (BuildConfig.DEBUG) {
            // Enable verbose logging for development
            RunAnywhereSDK.setLogLevel(LogLevel.VERBOSE)
        }
    }
}
```

### **2. Main Activity**

```kotlin
// MainActivity.kt
@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Setup edge-to-edge display
        enableEdgeToEdge()

        setContent {
            RunAnywhereTheme {
                MainAppContent()
            }
        }
    }

    @Compose
    private fun MainAppContent() {
        // Handle system bars
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background
        ) {
            AppNavigation()
        }
    }

    override fun onResume() {
        super.onResume()
        // Resume any active voice sessions if needed
    }

    override fun onPause() {
        super.onPause()
        // Pause voice sessions to save battery
    }
}
```

---

## Voice/STT Pipeline Implementation

### **1. Audio Capture Service**

```kotlin
// AudioCaptureService.kt
@Singleton
class AudioCaptureService @Inject constructor(
    private val context: Context
) {
    companion object {
        const val SAMPLE_RATE = 16000
        const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        const val BUFFER_SIZE_FACTOR = 2
    }

    private var audioRecord: AudioRecord? = null
    private var isCapturing = false
    private val _audioLevels = MutableSharedFlow<Float>()
    val audioLevels: SharedFlow<Float> = _audioLevels.asSharedFlow()

    fun startCapture(): Flow<VoiceAudioChunk> = flow {
        if (!hasAudioPermission()) {
            throw SecurityException("Audio recording permission required")
        }

        val bufferSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT
        ) * BUFFER_SIZE_FACTOR

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT,
            bufferSize
        )

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            throw IllegalStateException("AudioRecord initialization failed")
        }

        audioRecord?.startRecording()
        isCapturing = true

        val audioBuffer = ShortArray(bufferSize / 2)

        while (isCapturing) {
            val samplesRead = audioRecord?.read(audioBuffer, 0, audioBuffer.size) ?: 0

            if (samplesRead > 0) {
                // Calculate audio level for visualization
                val audioLevel = calculateAudioLevel(audioBuffer, samplesRead)
                _audioLevels.tryEmit(audioLevel)

                // Convert to float array for processing
                val floatData = audioBuffer.take(samplesRead)
                    .map { it.toFloat() / Short.MAX_VALUE }
                    .toFloatArray()

                emit(VoiceAudioChunk(
                    data = floatData,
                    sampleRate = SAMPLE_RATE,
                    timestamp = System.currentTimeMillis(),
                    channels = 1
                ))
            }

            // Small delay to prevent excessive CPU usage
            delay(10)
        }
    }.flowOn(Dispatchers.IO)

    fun stopCapture() {
        isCapturing = false
        audioRecord?.apply {
            if (recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                stop()
            }
            release()
        }
        audioRecord = null
    }

    private fun calculateAudioLevel(buffer: ShortArray, length: Int): Float {
        var sum = 0L
        for (i in 0 until length) {
            sum += (buffer[i] * buffer[i]).toLong()
        }
        val rms = sqrt(sum.toDouble() / length)
        return (rms / Short.MAX_VALUE).toFloat()
    }

    private fun hasAudioPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }
}
```

### **2. Modular Voice Pipeline**

```kotlin
// VoicePipelineService.kt
@Singleton
class VoicePipelineService @Inject constructor(
    private val audioCapture: AudioCaptureService,
    private val analyticsService: AnalyticsService
) {

    private val _pipelineEvents = MutableSharedFlow<VoicePipelineEvent>()
    val pipelineEvents: SharedFlow<VoicePipelineEvent> = _pipelineEvents.asSharedFlow()

    private var currentPipeline: ModularVoicePipeline? = null
    private var pipelineJob: Job? = null

    suspend fun initializePipeline(config: ModularPipelineConfig) {
        stopPipeline()

        currentPipeline = ModularVoicePipeline(
            config = config,
            eventCallback = { event ->
                _pipelineEvents.tryEmit(event)
                analyticsService.trackEvent(event)
            }
        )

        currentPipeline?.initialize()
    }

    suspend fun startPipeline() {
        val pipeline = currentPipeline ?: throw IllegalStateException("Pipeline not initialized")

        pipelineJob = CoroutineScope(Dispatchers.IO).launch {
            try {
                audioCapture.startCapture().collect { audioChunk ->
                    pipeline.processAudio(audioChunk)
                }
            } catch (e: Exception) {
                _pipelineEvents.emit(VoicePipelineEvent.Error(e.message ?: "Unknown error"))
            }
        }
    }

    fun stopPipeline() {
        pipelineJob?.cancel()
        pipelineJob = null
        audioCapture.stopCapture()
        currentPipeline?.cleanup()
    }

    suspend fun sendTextInput(text: String) {
        currentPipeline?.processTextInput(text)
    }
}

// ModularVoicePipeline.kt
class ModularVoicePipeline(
    private val config: ModularPipelineConfig,
    private val eventCallback: suspend (VoicePipelineEvent) -> Unit
) {
    private var vadComponent: VoiceActivityDetector? = null
    private var sttComponent: SpeechToTextEngine? = null
    private var llmComponent: LanguageModelEngine? = null
    private var ttsComponent: TextToSpeechEngine? = null
    private var speakerDiarization: SpeakerDiarizationEngine? = null

    private var isListening = false
    private var currentAudioBuffer = mutableListOf<Float>()

    suspend fun initialize() {
        // Initialize components based on config
        if (config.components.contains(PipelineComponent.VAD)) {
            vadComponent = VoiceActivityDetector(config.vadConfig)
        }

        if (config.components.contains(PipelineComponent.STT)) {
            sttComponent = SpeechToTextEngine(config.sttConfig)
        }

        if (config.components.contains(PipelineComponent.LLM)) {
            llmComponent = LanguageModelEngine(config.llmConfig)
        }

        if (config.components.contains(PipelineComponent.TTS)) {
            ttsComponent = TextToSpeechEngine(config.ttsConfig)
        }

        if (config.enableSpeakerDiarization) {
            speakerDiarization = SpeakerDiarizationEngine(config.speakerConfig)
        }
    }

    suspend fun processAudio(audioChunk: VoiceAudioChunk) {
        // VAD processing
        vadComponent?.let { vad ->
            val vadResult = vad.detectSpeech(audioChunk)

            when (vadResult.state) {
                VADState.SPEECH_START -> {
                    if (!isListening) {
                        isListening = true
                        currentAudioBuffer.clear()
                        eventCallback(VoicePipelineEvent.VADSpeechStart)
                    }
                }
                VADState.SPEECH_END -> {
                    if (isListening) {
                        isListening = false
                        processBufferedAudio()
                        eventCallback(VoicePipelineEvent.VADSpeechEnd)
                    }
                }
                VADState.SPEECH_CONTINUE -> {
                    // Continue collecting audio
                }
                VADState.SILENCE -> {
                    // Handle silence
                }
            }
        }

        // Collect audio during speech
        if (isListening) {
            currentAudioBuffer.addAll(audioChunk.data.toList())

            // Process partial transcription for real-time feedback
            if (currentAudioBuffer.size >= PARTIAL_TRANSCRIPTION_BUFFER_SIZE) {
                processPartialTranscription()
            }
        }
    }

    private suspend fun processBufferedAudio() {
        if (currentAudioBuffer.isEmpty()) return

        val audioData = currentAudioBuffer.toFloatArray()

        // STT processing
        sttComponent?.let { stt ->
            val transcriptionResult = stt.transcribe(audioData)

            var finalText = transcriptionResult.text
            var speaker: SpeakerInfo? = null

            // Speaker diarization if enabled
            speakerDiarization?.let { diarization ->
                val speakerResult = diarization.identifySpeaker(audioData)
                speaker = speakerResult.speaker
            }

            eventCallback(VoicePipelineEvent.STTFinalTranscript(
                text = finalText,
                confidence = transcriptionResult.confidence,
                speaker = speaker
            ))

            // LLM processing if text-based conversation
            if (config.components.contains(PipelineComponent.LLM)) {
                processLLMResponse(finalText)
            }
        }
    }

    private suspend fun processPartialTranscription() {
        val partialBuffer = currentAudioBuffer.takeLast(PARTIAL_TRANSCRIPTION_BUFFER_SIZE).toFloatArray()

        sttComponent?.let { stt ->
            val partialResult = stt.transcribePartial(partialBuffer)
            eventCallback(VoicePipelineEvent.STTPartialTranscript(
                text = partialResult.text,
                confidence = partialResult.confidence
            ))
        }
    }

    private suspend fun processLLMResponse(inputText: String) {
        llmComponent?.let { llm ->
            val response = llm.generateResponse(
                prompt = inputText,
                options = config.llmConfig.generationOptions
            )

            eventCallback(VoicePipelineEvent.LLMResponse(
                text = response.text,
                thinking = response.thinking
            ))

            // TTS if enabled
            if (config.components.contains(PipelineComponent.TTS)) {
                ttsComponent?.speak(response.text)
                eventCallback(VoicePipelineEvent.TTSStart(response.text))
            }
        }
    }

    suspend fun processTextInput(text: String) {
        processLLMResponse(text)
    }

    fun cleanup() {
        vadComponent?.cleanup()
        sttComponent?.cleanup()
        llmComponent?.cleanup()
        ttsComponent?.cleanup()
        speakerDiarization?.cleanup()
    }

    companion object {
        private const val PARTIAL_TRANSCRIPTION_BUFFER_SIZE = 8000 // 0.5 seconds at 16kHz
    }
}
```

### **3. Voice Pipeline Events**

```kotlin
// VoicePipelineEvent.kt
sealed class VoicePipelineEvent {
    object VADSpeechStart : VoicePipelineEvent()
    object VADSpeechEnd : VoicePipelineEvent()

    data class STTPartialTranscript(
        val text: String,
        val confidence: Float
    ) : VoicePipelineEvent()

    data class STTFinalTranscript(
        val text: String,
        val confidence: Float,
        val speaker: SpeakerInfo? = null
    ) : VoicePipelineEvent()

    data class LLMResponse(
        val text: String,
        val thinking: String? = null
    ) : VoicePipelineEvent()

    data class TTSStart(val text: String) : VoicePipelineEvent()
    object TTSComplete : VoicePipelineEvent()

    data class Error(val message: String) : VoicePipelineEvent()
}

// Pipeline Configuration
data class ModularPipelineConfig(
    val components: List<PipelineComponent>,
    val vadConfig: VADConfig = VADConfig(),
    val sttConfig: VoiceSTTConfig,
    val llmConfig: VoiceLLMConfig = VoiceLLMConfig(),
    val ttsConfig: VoiceTTSConfig = VoiceTTSConfig(),
    val enableSpeakerDiarization: Boolean = false,
    val speakerConfig: SpeakerDiarizationConfig = SpeakerDiarizationConfig()
)

enum class PipelineComponent {
    VAD, STT, LLM, TTS
}

// Session States
enum class SessionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    LISTENING,
    PROCESSING,
    SPEAKING,
    ERROR
}
```

---

## UI Components

### **1. Voice Assistant Screen**

```kotlin
// VoiceAssistantScreen.kt
@Compose
fun VoiceAssistantScreen(
    viewModel: VoiceAssistantViewModel = hiltViewModel()
) {
    val sessionState by viewModel.sessionState.collectAsState()
    val transcript by viewModel.transcript.collectAsState()
    val isListening by viewModel.isListening.collectAsState()
    val audioLevel by viewModel.audioLevel.collectAsState()
    val error by viewModel.error.collectAsState()

    LaunchedEffect(Unit) {
        viewModel.initializePipeline()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {
        // Header with session status
        VoiceAssistantHeader(
            sessionState = sessionState,
            modifier = Modifier.fillMaxWidth()
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Voice visualization
        VoiceVisualizerComponent(
            isListening = isListening,
            audioLevel = audioLevel,
            sessionState = sessionState,
            modifier = Modifier
                .fillMaxWidth()
                .height(200.dp)
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Transcript display
        TranscriptDisplay(
            segments = transcript,
            modifier = Modifier.weight(1f)
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Control buttons
        VoiceControlButtons(
            sessionState = sessionState,
            onStartSession = viewModel::startSession,
            onStopSession = viewModel::stopSession,
            onPauseListening = viewModel::pauseListening,
            onClearTranscript = viewModel::clearTranscript,
            modifier = Modifier.fillMaxWidth()
        )

        // Error display
        error?.let { errorMessage ->
            ErrorDisplay(
                message = errorMessage,
                onDismiss = viewModel::clearError,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

// VoiceAssistantViewModel.kt
@HiltViewModel
class VoiceAssistantViewModel @Inject constructor(
    private val voicePipelineService: VoicePipelineService,
    private val audioCapture: AudioCaptureService,
    private val analyticsService: AnalyticsService
) : ViewModel() {

    private val _sessionState = MutableStateFlow(SessionState.DISCONNECTED)
    val sessionState = _sessionState.asStateFlow()

    private val _transcript = MutableStateFlow<List<TranscriptSegment>>(emptyList())
    val transcript = _transcript.asStateFlow()

    private val _isListening = MutableStateFlow(false)
    val isListening = _isListening.asStateFlow()

    private val _audioLevel = MutableStateFlow(0f)
    val audioLevel = _audioLevel.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    private var currentPartialTranscript: String = ""

    init {
        observePipelineEvents()
        observeAudioLevels()
    }

    fun initializePipeline() {
        viewModelScope.launch {
            try {
                val config = ModularPipelineConfig(
                    components = listOf(
                        PipelineComponent.VAD,
                        PipelineComponent.STT,
                        PipelineComponent.LLM,
                        PipelineComponent.TTS
                    ),
                    sttConfig = VoiceSTTConfig(
                        modelId = "whisper-base",
                        language = "auto",
                        enableRealTime = true
                    ),
                    llmConfig = VoiceLLMConfig(
                        modelId = "default",
                        maxTokens = 150,
                        temperature = 0.7f
                    ),
                    enableSpeakerDiarization = true
                )

                voicePipelineService.initializePipeline(config)

            } catch (e: Exception) {
                _error.value = "Failed to initialize pipeline: ${e.message}"
            }
        }
    }

    fun startSession() {
        viewModelScope.launch {
            try {
                _sessionState.value = SessionState.CONNECTING
                voicePipelineService.startPipeline()
                _sessionState.value = SessionState.CONNECTED
                analyticsService.trackEvent("voice_session_started")

            } catch (e: Exception) {
                _sessionState.value = SessionState.ERROR
                _error.value = "Failed to start session: ${e.message}"
            }
        }
    }

    fun stopSession() {
        viewModelScope.launch {
            voicePipelineService.stopPipeline()
            _sessionState.value = SessionState.DISCONNECTED
            _isListening.value = false
            analyticsService.trackEvent("voice_session_stopped")
        }
    }

    fun pauseListening() {
        // Implementation depends on pipeline capabilities
        _isListening.value = false
    }

    fun clearTranscript() {
        _transcript.value = emptyList()
        currentPartialTranscript = ""
    }

    fun clearError() {
        _error.value = null
    }

    private fun observePipelineEvents() {
        viewModelScope.launch {
            voicePipelineService.pipelineEvents.collect { event ->
                when (event) {
                    is VoicePipelineEvent.VADSpeechStart -> {
                        _sessionState.value = SessionState.LISTENING
                        _isListening.value = true
                    }

                    is VoicePipelineEvent.VADSpeechEnd -> {
                        _sessionState.value = SessionState.PROCESSING
                        _isListening.value = false
                    }

                    is VoicePipelineEvent.STTPartialTranscript -> {
                        currentPartialTranscript = event.text
                        updateTranscriptWithPartial()
                    }

                    is VoicePipelineEvent.STTFinalTranscript -> {
                        addFinalTranscript(event.text, event.speaker)
                        currentPartialTranscript = ""
                    }

                    is VoicePipelineEvent.LLMResponse -> {
                        addAssistantResponse(event.text, event.thinking)
                        _sessionState.value = SessionState.CONNECTED
                    }

                    is VoicePipelineEvent.TTSStart -> {
                        _sessionState.value = SessionState.SPEAKING
                    }

                    is VoicePipelineEvent.TTSComplete -> {
                        _sessionState.value = SessionState.CONNECTED
                    }

                    is VoicePipelineEvent.Error -> {
                        _error.value = event.message
                        _sessionState.value = SessionState.ERROR
                    }
                }
            }
        }
    }

    private fun observeAudioLevels() {
        viewModelScope.launch {
            audioCapture.audioLevels.collect { level ->
                _audioLevel.value = level
            }
        }
    }

    private fun updateTranscriptWithPartial() {
        val currentTranscript = _transcript.value.toMutableList()

        // Update or add partial transcript segment
        if (currentTranscript.isNotEmpty() &&
            currentTranscript.last().type == TranscriptType.PARTIAL_USER) {
            // Update existing partial
            currentTranscript[currentTranscript.size - 1] = currentTranscript.last().copy(
                text = currentPartialTranscript
            )
        } else {
            // Add new partial
            currentTranscript.add(
                TranscriptSegment(
                    id = UUID.randomUUID().toString(),
                    text = currentPartialTranscript,
                    timestamp = System.currentTimeMillis(),
                    type = TranscriptType.PARTIAL_USER,
                    speaker = null
                )
            )
        }

        _transcript.value = currentTranscript
    }

    private fun addFinalTranscript(text: String, speaker: SpeakerInfo?) {
        val currentTranscript = _transcript.value.toMutableList()

        // Remove any partial transcript
        currentTranscript.removeAll { it.type == TranscriptType.PARTIAL_USER }

        // Add final transcript
        currentTranscript.add(
            TranscriptSegment(
                id = UUID.randomUUID().toString(),
                text = text,
                timestamp = System.currentTimeMillis(),
                type = TranscriptType.FINAL_USER,
                speaker = speaker
            )
        )

        _transcript.value = currentTranscript
    }

    private fun addAssistantResponse(text: String, thinking: String?) {
        val currentTranscript = _transcript.value.toMutableList()

        currentTranscript.add(
            TranscriptSegment(
                id = UUID.randomUUID().toString(),
                text = text,
                timestamp = System.currentTimeMillis(),
                type = TranscriptType.ASSISTANT,
                speaker = null,
                thinking = thinking
            )
        )

        _transcript.value = currentTranscript
    }
}
```

### **2. Transcription Screen**

```kotlin
// TranscriptionScreen.kt
@Compose
fun TranscriptionScreen(
    viewModel: TranscriptionViewModel = hiltViewModel()
) {
    val transcriptSegments by viewModel.transcriptSegments.collectAsState()
    val isRecording by viewModel.isRecording.collectAsState()
    val recordingDuration by viewModel.recordingDuration.collectAsState()
    val error by viewModel.error.collectAsState()

    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        // Header with recording status
        TranscriptionHeader(
            isRecording = isRecording,
            duration = recordingDuration,
            segmentCount = transcriptSegments.size,
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        )

        // Transcript display
        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(
                items = transcriptSegments,
                key = { it.id }
            ) { segment ->
                TranscriptSegmentItem(
                    segment = segment,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }

        // Control buttons
        TranscriptionControlButtons(
            isRecording = isRecording,
            hasTranscripts = transcriptSegments.isNotEmpty(),
            onStartRecording = viewModel::startRecording,
            onStopRecording = viewModel::stopRecording,
            onSaveTranscript = viewModel::saveTranscript,
            onClearTranscript = viewModel::clearTranscript,
            onExportTranscript = viewModel::exportTranscript,
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        )

        // Error display
        error?.let { errorMessage ->
            ErrorDisplay(
                message = errorMessage,
                onDismiss = viewModel::clearError,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp)
            )
        }
    }
}

// TranscriptionViewModel.kt
@HiltViewModel
class TranscriptionViewModel @Inject constructor(
    private val voicePipelineService: VoicePipelineService,
    private val analyticsService: AnalyticsService
) : ViewModel() {

    private val _transcriptSegments = MutableStateFlow<List<TranscriptSegment>>(emptyList())
    val transcriptSegments = _transcriptSegments.asStateFlow()

    private val _isRecording = MutableStateFlow(false)
    val isRecording = _isRecording.asStateFlow()

    private val _recordingDuration = MutableStateFlow(0L)
    val recordingDuration = _recordingDuration.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    private var recordingStartTime = 0L
    private var durationTimer: Job? = null

    init {
        initializePipeline()
        observePipelineEvents()
    }

    private fun initializePipeline() {
        viewModelScope.launch {
            try {
                val config = ModularPipelineConfig(
                    components = listOf(
                        PipelineComponent.VAD,
                        PipelineComponent.STT
                    ),
                    sttConfig = VoiceSTTConfig(
                        modelId = "whisper-base",
                        language = "auto",
                        enableRealTime = true
                    ),
                    enableSpeakerDiarization = true
                )

                voicePipelineService.initializePipeline(config)

            } catch (e: Exception) {
                _error.value = "Failed to initialize transcription: ${e.message}"
            }
        }
    }

    fun startRecording() {
        viewModelScope.launch {
            try {
                voicePipelineService.startPipeline()
                _isRecording.value = true
                recordingStartTime = System.currentTimeMillis()
                startDurationTimer()
                analyticsService.trackEvent("transcription_started")

            } catch (e: Exception) {
                _error.value = "Failed to start recording: ${e.message}"
            }
        }
    }

    fun stopRecording() {
        viewModelScope.launch {
            voicePipelineService.stopPipeline()
            _isRecording.value = false
            stopDurationTimer()

            val duration = _recordingDuration.value
            analyticsService.trackEvent("transcription_stopped", mapOf(
                "duration_seconds" to duration / 1000,
                "segments_count" to _transcriptSegments.value.size
            ))
        }
    }

    fun saveTranscript() {
        // Save to local storage
        viewModelScope.launch {
            try {
                val transcript = generateTranscriptText()
                // Save logic here
                analyticsService.trackEvent("transcript_saved")
            } catch (e: Exception) {
                _error.value = "Failed to save transcript: ${e.message}"
            }
        }
    }

    fun exportTranscript() {
        // Export transcript (share, email, etc.)
        viewModelScope.launch {
            try {
                val transcript = generateTranscriptText()
                // Export logic here
                analyticsService.trackEvent("transcript_exported")
            } catch (e: Exception) {
                _error.value = "Failed to export transcript: ${e.message}"
            }
        }
    }

    fun clearTranscript() {
        _transcriptSegments.value = emptyList()
        _recordingDuration.value = 0L
    }

    fun clearError() {
        _error.value = null
    }

    private fun startDurationTimer() {
        durationTimer = viewModelScope.launch {
            while (_isRecording.value) {
                _recordingDuration.value = System.currentTimeMillis() - recordingStartTime
                delay(1000) // Update every second
            }
        }
    }

    private fun stopDurationTimer() {
        durationTimer?.cancel()
        durationTimer = null
    }

    private fun observePipelineEvents() {
        viewModelScope.launch {
            voicePipelineService.pipelineEvents.collect { event ->
                when (event) {
                    is VoicePipelineEvent.STTPartialTranscript -> {
                        updatePartialTranscript(event.text)
                    }

                    is VoicePipelineEvent.STTFinalTranscript -> {
                        addFinalTranscript(event.text, event.speaker)
                    }

                    is VoicePipelineEvent.Error -> {
                        _error.value = event.message
                    }

                    else -> { /* Handle other events if needed */ }
                }
            }
        }
    }

    private fun updatePartialTranscript(text: String) {
        val currentSegments = _transcriptSegments.value.toMutableList()

        // Update or add partial segment
        if (currentSegments.isNotEmpty() &&
            currentSegments.last().type == TranscriptType.PARTIAL_USER) {
            currentSegments[currentSegments.size - 1] = currentSegments.last().copy(
                text = text
            )
        } else {
            currentSegments.add(
                TranscriptSegment(
                    id = UUID.randomUUID().toString(),
                    text = text,
                    timestamp = System.currentTimeMillis(),
                    type = TranscriptType.PARTIAL_USER,
                    speaker = null
                )
            )
        }

        _transcriptSegments.value = currentSegments
    }

    private fun addFinalTranscript(text: String, speaker: SpeakerInfo?) {
        val currentSegments = _transcriptSegments.value.toMutableList()

        // Remove partial segment
        currentSegments.removeAll { it.type == TranscriptType.PARTIAL_USER }

        // Add final segment
        currentSegments.add(
            TranscriptSegment(
                id = UUID.randomUUID().toString(),
                text = text,
                timestamp = System.currentTimeMillis(),
                type = TranscriptType.FINAL_USER,
                speaker = speaker
            )
        )

        _transcriptSegments.value = currentSegments
    }

    private fun generateTranscriptText(): String {
        return _transcriptSegments.value
            .filter { it.type != TranscriptType.PARTIAL_USER }
            .joinToString("\n\n") { segment ->
                val timestamp = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
                    .format(Date(segment.timestamp))
                val speaker = segment.speaker?.let { "[${it.name}] " } ?: ""
                "$timestamp - $speaker${segment.text}"
            }
    }
}
```

---

## Navigation Structure

### **App Navigation**

```kotlin
// AppNavigation.kt
@Compose
fun AppNavigation() {
    val navController = rememberNavController()

    Scaffold(
        bottomBar = {
            BottomNavigationBar(
                navController = navController,
                currentRoute = navController.currentBackStackEntryAsState().value?.destination?.route
            )
        }
    ) { paddingValues ->
        NavHost(
            navController = navController,
            startDestination = "chat",
            modifier = Modifier.padding(paddingValues)
        ) {
            composable("chat") {
                ChatScreen()
            }

            composable("voice") {
                VoiceAssistantScreen()
            }

            composable("transcription") {
                TranscriptionScreen()
            }

            composable("storage") {
                StorageScreen()
            }

            composable("settings") {
                SettingsScreen()
            }

            composable("quiz") {
                QuizScreen()
            }
        }
    }
}

@Compose
fun BottomNavigationBar(
    navController: NavController,
    currentRoute: String?
) {
    val items = listOf(
        BottomNavItem("chat", "Chat", Icons.Default.Chat),
        BottomNavItem("voice", "Voice", Icons.Default.Mic),
        BottomNavItem("storage", "Storage", Icons.Default.Storage),
        BottomNavItem("settings", "Settings", Icons.Default.Settings),
        BottomNavItem("quiz", "Quiz", Icons.Default.Quiz)
    )

    BottomNavigation(
        backgroundColor = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface
    ) {
        items.forEach { item ->
            BottomNavigationItem(
                icon = { Icon(item.icon, contentDescription = item.label) },
                label = { Text(item.label) },
                selected = currentRoute == item.route,
                onClick = {
                    navController.navigate(item.route) {
                        // Pop up to start destination to avoid building up a large stack
                        popUpTo(navController.graph.findStartDestination().id) {
                            saveState = true
                        }
                        // Avoid multiple copies of the same destination
                        launchSingleTop = true
                        // Restore state when reselecting a previously selected item
                        restoreState = true
                    }
                },
                selectedContentColor = MaterialTheme.colorScheme.primary,
                unselectedContentColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
            )
        }
    }
}

data class BottomNavItem(
    val route: String,
    val label: String,
    val icon: ImageVector
)
```

---

## Data Layer

### **Domain Models**

```kotlin
// TranscriptSegment.kt
data class TranscriptSegment(
    val id: String,
    val text: String,
    val timestamp: Long,
    val type: TranscriptType,
    val speaker: SpeakerInfo? = null,
    val confidence: Float = 1.0f,
    val thinking: String? = null
)

enum class TranscriptType {
    PARTIAL_USER,
    FINAL_USER,
    ASSISTANT
}

// SpeakerInfo.kt
data class SpeakerInfo(
    val id: String,
    val name: String,
    val confidence: Float,
    val color: Long // Color for UI display
)

// VoiceAudioChunk.kt
data class VoiceAudioChunk(
    val data: FloatArray,
    val sampleRate: Int,
    val timestamp: Long,
    val channels: Int = 1
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as VoiceAudioChunk
        return data.contentEquals(other.data) &&
               sampleRate == other.sampleRate &&
               timestamp == other.timestamp
    }

    override fun hashCode(): Int {
        var result = data.contentHashCode()
        result = 31 * result + sampleRate
        result = 31 * result + timestamp.hashCode()
        return result
    }
}

// ChatMessage.kt
data class ChatMessage(
    val id: String,
    val content: String,
    val timestamp: Long,
    val isFromUser: Boolean,
    val thinking: String? = null,
    val analytics: MessageAnalytics? = null
)

data class MessageAnalytics(
    val timeToFirstToken: Long? = null,
    val totalGenerationTime: Long,
    val averageTokensPerSecond: Double,
    val wasThinkingMode: Boolean = false,
    val completionStatus: CompletionStatus,
    val modelUsed: String
)

enum class CompletionStatus {
    SUCCESS, PARTIAL, FAILED, CANCELLED
}
```

### **Database Setup**

```kotlin
// AppDatabase.kt
@Database(
    entities = [
        ChatMessageEntity::class,
        TranscriptSegmentEntity::class,
        ModelInfoEntity::class
    ],
    version = 1,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun chatDao(): ChatDao
    abstract fun transcriptDao(): TranscriptDao
    abstract fun modelDao(): ModelDao
}

// Database Entities
@Entity(tableName = "chat_messages")
data class ChatMessageEntity(
    @PrimaryKey val id: String,
    val content: String,
    val timestamp: Long,
    val isFromUser: Boolean,
    val thinking: String? = null,
    val analytics: String? = null // JSON string
)

@Entity(tableName = "transcript_segments")
data class TranscriptSegmentEntity(
    @PrimaryKey val id: String,
    val text: String,
    val timestamp: Long,
    val type: String,
    val speakerId: String? = null,
    val speakerName: String? = null,
    val confidence: Float = 1.0f
)

@Entity(tableName = "model_info")
data class ModelInfoEntity(
    @PrimaryKey val id: String,
    val name: String,
    val type: String,
    val size: Long,
    val downloaded: Boolean,
    val path: String? = null
)
```

---

## Dependencies

### **build.gradle.kts (Module: app)**

```kotlin
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.hilt.android)
    alias(libs.plugins.kotlin.kapt)
    alias(libs.plugins.kotlin.parcelize)
}

android {
    namespace = "com.runanywhere.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.runanywhere.android"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    // Core Android
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)

    // Compose BOM
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)

    // Navigation
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.hilt.navigation.compose)

    // Architecture Components
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(libs.androidx.lifecycle.livedata.ktx)

    // Hilt Dependency Injection
    implementation(libs.hilt.android)
    kapt(libs.hilt.android.compiler)

    // Room Database
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    kapt(libs.androidx.room.compiler)

    // Networking
    implementation(libs.retrofit)
    implementation(libs.retrofit.converter.moshi)
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging.interceptor)

    // JSON Parsing
    implementation(libs.moshi.kotlin)
    kapt(libs.moshi.kotlin.codegen)

    // Audio Processing & AI
    implementation(libs.pytorch.android)
    implementation(libs.pytorch.android.lite)
    implementation(libs.tensorflow.lite)
    implementation(libs.tensorflow.lite.gpu)

    // Permissions
    implementation(libs.accompanist.permissions)

    // File I/O
    implementation(libs.androidx.documentfile)

    // Analytics & Crash Reporting
    implementation(libs.firebase.analytics)
    implementation(libs.firebase.crashlytics)

    // Security
    implementation(libs.androidx.security.crypto)

    // Testing
    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testImplementation(libs.coroutines.test)
    testImplementation(libs.androidx.arch.core.testing)

    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)

    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
```

### **libs.versions.toml**

```toml
[versions]
agp = "8.5.0"
kotlin = "2.0.0"
coreKtx = "1.13.1"
junit = "4.13.2"
junitVersion = "1.2.1"
espressoCore = "3.6.1"
lifecycleRuntimeKtx = "2.8.4"
activityCompose = "1.9.1"
composeBom = "2024.08.00"
hilt = "2.51.1"
room = "2.6.1"
retrofit = "2.11.0"
okhttp = "4.12.0"
moshi = "1.15.1"
navigation = "2.7.7"
pytorch = "1.12.2"
tensorflow = "2.13.0"
accompanist = "0.34.0"

[libraries]
androidx-core-ktx = { group = "androidx.core", name = "core-ktx", version.ref = "coreKtx" }
androidx-lifecycle-runtime-ktx = { group = "androidx.lifecycle", name = "lifecycle-runtime-ktx", version.ref = "lifecycleRuntimeKtx" }
androidx-activity-compose = { group = "androidx.activity", name = "activity-compose", version.ref = "activityCompose" }
androidx-compose-bom = { group = "androidx.compose", name = "compose-bom", version.ref = "composeBom" }
androidx-compose-ui = { group = "androidx.compose.ui", name = "ui" }
androidx-compose-ui-graphics = { group = "androidx.compose.ui", name = "ui-graphics" }
androidx-compose-ui-tooling = { group = "androidx.compose.ui", name = "ui-tooling" }
androidx-compose-ui-tooling-preview = { group = "androidx.compose.ui", name = "ui-tooling-preview" }
androidx-compose-ui-test-manifest = { group = "androidx.compose.ui", name = "ui-test-manifest" }
androidx-compose-ui-test-junit4 = { group = "androidx.compose.ui", name = "ui-test-junit4" }
androidx-compose-material3 = { group = "androidx.compose.material3", name = "material3" }
androidx-compose-material-icons-extended = { group = "androidx.compose.material", name = "material-icons-extended" }

# Navigation
androidx-navigation-compose = { group = "androidx.navigation", name = "navigation-compose", version.ref = "navigation" }
androidx-hilt-navigation-compose = { group = "androidx.hilt", name = "hilt-navigation-compose", version = "1.2.0" }

# Architecture Components
androidx-lifecycle-viewmodel-ktx = { group = "androidx.lifecycle", name = "lifecycle-viewmodel-ktx", version.ref = "lifecycleRuntimeKtx" }
androidx-lifecycle-viewmodel-compose = { group = "androidx.lifecycle", name = "lifecycle-viewmodel-compose", version.ref = "lifecycleRuntimeKtx" }
androidx-lifecycle-livedata-ktx = { group = "androidx.lifecycle", name = "lifecycle-livedata-ktx", version.ref = "lifecycleRuntimeKtx" }

# Hilt
hilt-android = { group = "com.google.dagger", name = "hilt-android", version.ref = "hilt" }
hilt-android-compiler = { group = "com.google.dagger", name = "hilt-android-compiler", version.ref = "hilt" }

# Room
androidx-room-runtime = { group = "androidx.room", name = "room-runtime", version.ref = "room" }
androidx-room-compiler = { group = "androidx.room", name = "room-compiler", version.ref = "room" }
androidx-room-ktx = { group = "androidx.room", name = "room-ktx", version.ref = "room" }

# Networking
retrofit = { group = "com.squareup.retrofit2", name = "retrofit", version.ref = "retrofit" }
retrofit-converter-moshi = { group = "com.squareup.retrofit2", name = "converter-moshi", version.ref = "retrofit" }
okhttp = { group = "com.squareup.okhttp3", name = "okhttp", version.ref = "okhttp" }
okhttp-logging-interceptor = { group = "com.squareup.okhttp3", name = "logging-interceptor", version.ref = "okhttp" }

# JSON
moshi-kotlin = { group = "com.squareup.moshi", name = "moshi-kotlin", version.ref = "moshi" }
moshi-kotlin-codegen = { group = "com.squareup.moshi", name = "moshi-kotlin-codegen", version.ref = "moshi" }

# AI & Audio Processing
pytorch-android = { group = "org.pytorch", name = "pytorch_android", version.ref = "pytorch" }
pytorch-android-lite = { group = "org.pytorch", name = "pytorch_android_lite", version.ref = "pytorch" }
tensorflow-lite = { group = "org.tensorflow", name = "tensorflow-lite", version.ref = "tensorflow" }
tensorflow-lite-gpu = { group = "org.tensorflow", name = "tensorflow-lite-gpu", version.ref = "tensorflow" }

# Permissions
accompanist-permissions = { group = "com.google.accompanist", name = "accompanist-permissions", version.ref = "accompanist" }

# Other Android Libraries
androidx-documentfile = { group = "androidx.documentfile", name = "documentfile", version = "1.0.1" }
androidx-security-crypto = { group = "androidx.security", name = "security-crypto", version = "1.1.0-alpha06" }

# Firebase
firebase-analytics = { group = "com.google.firebase", name = "firebase-analytics", version = "22.0.2" }
firebase-crashlytics = { group = "com.google.firebase", name = "firebase-crashlytics", version = "19.0.3" }

# Testing
junit = { group = "junit", name = "junit", version.ref = "junit" }
androidx-junit = { group = "androidx.test.ext", name = "junit", version.ref = "junitVersion" }
androidx-espresso-core = { group = "androidx.test.espresso", name = "espresso-core", version.ref = "espressoCore" }
mockk = { group = "io.mockk", name = "mockk", version = "1.13.12" }
coroutines-test = { group = "org.jetbrains.kotlinx", name = "kotlinx-coroutines-test", version = "1.8.1" }
androidx-arch-core-testing = { group = "androidx.arch.core", name = "core-testing", version = "2.2.0" }

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
kotlin-android = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
kotlin-compose = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
hilt-android = { id = "com.google.dagger.hilt.android", version.ref = "hilt" }
kotlin-kapt = { id = "org.jetbrains.kotlin.kapt", version.ref = "kotlin" }
kotlin-parcelize = { id = "org.jetbrains.kotlin.plugin.parcelize", version.ref = "kotlin" }
```

---

## Implementation Roadmap

### **Phase 1: Foundation Setup (Week 1-2)**
1. **Project Structure & Dependencies**
    - Set up Android project with proper module structure
    - Configure Hilt dependency injection
    - Set up Room database
    - Configure build scripts and dependencies

2. **Core Services Implementation**
    - Audio capture service with proper permissions
    - Basic SDK integration setup
    - Analytics service foundation
    - Keychain/secure storage service

### **Phase 2: STT Pipeline Core (Week 3-4)**
3. **Voice Pipeline Components**
    - Implement modular voice pipeline architecture
    - WhisperCpp integration for STT
    - Voice Activity Detection (VAD) implementation
    - Audio processing and format conversion

4. **Basic Transcription Screen**
    - Simple transcription UI with start/stop recording
    - Real-time transcript display
    - Basic error handling and permissions

### **Phase 3: Advanced Features (Week 5-6)**
5. **Voice Assistant Implementation**
    - Full conversational pipeline (VAD → STT → LLM → TTS)
    - Event-driven architecture matching iOS
    - Voice visualization and audio level feedback
    - Speaker diarization integration

6. **Chat Interface**
    - Message bubbles with thinking mode
    - Real-time streaming responses
    - Analytics integration and performance metrics
    - Copy/share functionality

### **Phase 4: Supporting Features (Week 7-8)**
7. **Model Management**
    - Model download and storage management
    - Dynamic model loading through SDK
    - Storage usage display and cleanup

8. **Settings & Configuration**
    - SDK configuration interface
    - Routing policies and generation parameters
    - API key management with secure storage

### **Phase 5: Polish & Testing (Week 9-10)**
9. **UI Polish & Animations**
    - Smooth transitions and micro-interactions
    - Error states and loading indicators
    - Accessibility improvements
    - Dark/light theme support

10. **Testing & Optimization**
    - Unit tests for ViewModels and services
    - Integration tests for pipeline components
    - Performance optimization
    - Memory usage optimization

### **Priority Implementation Order**

**High Priority (MVP)**
1. Audio capture with permissions
2. Basic STT pipeline
3. Simple transcription screen
4. SDK initialization and configuration

**Medium Priority (Core Features)**
1. Voice assistant with full pipeline
2. Chat interface with basic features
3. Model management basics
4. Settings screen

**Lower Priority (Polish)**
1. Advanced analytics and metrics
2. Speaker diarization
3. Export/import functionality
4. Advanced UI animations

---

## Key Implementation Notes

### **Architecture Decisions**
- **Single Activity**: Use Navigation Compose for all navigation
- **MVVM Pattern**: Strict separation with reactive streams
- **Repository Pattern**: Clean abstraction for data access
- **Event-Driven**: Pipeline events rather than callbacks for loose coupling

### **Performance Considerations**
- Use `Flow` and `StateFlow` for reactive programming
- Implement proper lifecycle awareness in ViewModels
- Use background processing for audio capture and AI inference
- Implement proper memory management for large audio buffers

### **Security**
- Store API keys in encrypted shared preferences
- Use proper audio permissions and handle gracefully
- Implement secure network communication
- Follow Android security best practices

### **Testing Strategy**
- Unit tests for business logic and ViewModels
- Integration tests for pipeline components
- UI tests for critical user flows
- Performance tests for audio processing

This comprehensive implementation plan provides a roadmap to create an Android sample app that fully mirrors the iOS RunAnywhereAI experience while following Android best practices and native patterns.
