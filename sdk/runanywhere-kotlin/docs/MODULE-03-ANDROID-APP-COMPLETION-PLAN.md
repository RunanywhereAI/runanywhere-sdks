# Module 3: Android App Completion Implementation Plan
**Priority**: 🟡 HIGH  
**Estimated Timeline**: 6-8 days  
**Dependencies**: Module 1 (LLM) for voice responses, Module 2 (STT) for voice transcription  
**Team Assignment**: 1 Senior Android Developer  

## Executive Summary

The Android app has solid architectural foundations with 2 production-ready features (Chat, Quiz) but needs completion of 3 remaining features (Voice Assistant, Settings, Storage). The focus is on implementing missing functionality rather than architectural changes, as the UI frameworks are already excellent.

**Current Status**: 65% complete with strong foundation  
**Target**: Full feature parity with iOS app across all 5 tabs  

---

## Current State Analysis

### ✅ Production-Ready Features
**Chat Interface**: Advanced implementation with analytics that exceeds iOS
- Real-time streaming generation ✅
- Thinking mode support ✅  
- Comprehensive performance analytics ✅
- Message threading and error handling ✅

**Quiz Generation**: Complete feature with smooth UX
- AI-powered quiz generation ✅
- Swipe-based True/False interface ✅
- Score calculation and results ✅
- JSON parsing with fallbacks ✅

### ⚠️ Partially Working Features
**Voice Assistant**: Excellent UI, service needs reliability improvements
- Complete Material 3 UI design ✅
- Microphone permissions and controls ✅
- Audio waveform visualization ✅
- Voice pipeline service framework ✅
- Audio capture reliability issues ❌
- Pipeline orchestration needs work ❌

**Model Management**: Outstanding UI, backend integration missing
- Framework categorization UI (exceeds iOS) ✅
- Model state visualization ✅
- Download progress components ✅
- Actual model downloading ❌
- SDK integration for model operations ❌

### ❌ Missing Features
**Settings Management**: Skeleton implementation only
**Storage Management**: Skeleton implementation only

---

## Phase 1: Voice Assistant Reliability (Day 1-3)
**Duration**: 2-3 days  
**Priority**: HIGH  
**Dependencies**: Module 2 (STT) must be 50%+ complete  

### Task 1.1: Audio Capture Service Improvements
**Files**: `app/src/main/java/com/runanywhere/runanywhereai/domain/services/AudioCaptureService.kt`

#### Current Issues
- Audio dropouts during capture
- Inconsistent audio format handling
- Buffer management problems

#### Implementation
```kotlin
class ImprovedAudioCaptureService(private val context: Context) {
    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private val audioFormat = AudioFormat.Builder()
        .setSampleRate(16000)
        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
        .build()
    
    private val bufferSize = AudioRecord.getMinBufferSize(
        16000,
        AudioFormat.CHANNEL_IN_MONO,
        AudioFormat.ENCODING_PCM_16BIT
    ) * 4 // Use larger buffer for stability
    
    fun startCapture(): Flow<ByteArray> = flow {
        ensureAudioPermission()
        
        audioRecord = AudioRecord.Builder()
            .setAudioSource(MediaRecorder.AudioSource.MIC)
            .setAudioFormat(audioFormat)
            .setBufferSizeInBytes(bufferSize)
            .build()
        
        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            throw IllegalStateException("Failed to initialize AudioRecord")
        }
        
        audioRecord?.startRecording()
        isRecording = true
        
        val audioBuffer = ByteArray(bufferSize / 4) // Read in smaller chunks
        
        while (isRecording) {
            val bytesRead = audioRecord?.read(audioBuffer, 0, audioBuffer.size) ?: 0
            
            if (bytesRead > 0) {
                // Convert to proper format and emit
                val processedAudio = processAudioBuffer(audioBuffer, bytesRead)
                emit(processedAudio)
            } else if (bytesRead == AudioRecord.ERROR_INVALID_OPERATION) {
                throw IllegalStateException("AudioRecord invalid operation")
            }
        }
    }.flowOn(Dispatchers.IO)
    
    private fun processAudioBuffer(buffer: ByteArray, bytesRead: Int): ByteArray {
        // Ensure buffer is properly sized and formatted
        val result = ByteArray(bytesRead)
        System.arraycopy(buffer, 0, result, 0, bytesRead)
        
        // Apply basic noise reduction/normalization if needed
        return result
    }
    
    fun stopCapture() {
        isRecording = false
        audioRecord?.apply {
            if (state == AudioRecord.STATE_INITIALIZED) {
                stop()
            }
            release()
        }
        audioRecord = null
    }
    
    private fun ensureAudioPermission() {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) 
            != PackageManager.PERMISSION_GRANTED) {
            throw SecurityException("Audio recording permission not granted")
        }
    }
}
```

### Task 1.2: Voice Pipeline Service Enhancement
**Files**: `app/src/main/java/com/runanywhere/runanywhereai/domain/services/VoicePipelineService.kt`

#### Current Issues
- State management confusion
- Error recovery not implemented
- Component integration fragile

#### Implementation
```kotlin
class EnhancedVoicePipelineService(
    private val context: Context,
    private val audioCaptureService: AudioCaptureService,
    private val ttsService: TextToSpeech
) {
    private val _sessionState = MutableStateFlow(VoiceSessionState.Idle)
    val sessionState: StateFlow<VoiceSessionState> = _sessionState.asStateFlow()
    
    private val _events = MutableSharedFlow<VoicePipelineEvent>()
    val events: SharedFlow<VoicePipelineEvent> = _events.asSharedFlow()
    
    private var currentSession: Job? = null
    private var audioJob: Job? = null
    
    suspend fun startVoiceSession() {
        // Cancel any existing session
        stopVoiceSession()
        
        currentSession = CoroutineScope(Dispatchers.Main).launch {
            try {
                updateState(VoiceSessionState.Listening)
                
                // Start audio capture
                audioJob = launch {
                    audioCaptureService.startCapture()
                        .catch { error ->
                            _events.emit(VoicePipelineEvent.Error(error))
                            updateState(VoiceSessionState.Error(error.message ?: "Audio capture failed"))
                        }
                        .collect { audioData ->
                            processAudioChunk(audioData)
                        }
                }
                
                // Monitor for session timeout
                launch {
                    delay(30000) // 30 second timeout
                    if (_sessionState.value == VoiceSessionState.Listening) {
                        _events.emit(VoicePipelineEvent.SessionTimeout)
                        stopVoiceSession()
                    }
                }
                
            } catch (e: Exception) {
                _events.emit(VoicePipelineEvent.Error(e))
                updateState(VoiceSessionState.Error(e.message ?: "Session failed"))
            }
        }
    }
    
    private suspend fun processAudioChunk(audioData: ByteArray) {
        try {
            // Convert audio format for SDK
            val floatAudio = convertToFloatArray(audioData)
            
            // Use VAD to detect speech
            val vadResult = RunAnywhere.processVAD(floatAudio)
            
            when (vadResult.activityType) {
                "SPEECH_START" -> {
                    _events.emit(VoicePipelineEvent.SpeechDetected)
                    updateState(VoiceSessionState.Recording)
                }
                
                "SPEECH_END" -> {
                    updateState(VoiceSessionState.Processing)
                    processTranscription(floatAudio)
                }
                
                "SILENCE" -> {
                    // Continue listening
                }
            }
            
        } catch (e: Exception) {
            _events.emit(VoicePipelineEvent.Error(e))
            logger.error("Audio processing error", e)
        }
    }
    
    private suspend fun processTranscription(audioData: FloatArray) {
        try {
            // Transcribe audio using SDK
            val transcript = RunAnywhere.transcribe(audioData.toByteArray())
            
            if (transcript.isNotEmpty() && transcript != "Transcription not yet implemented on Android") {
                _events.emit(VoicePipelineEvent.TranscriptionComplete(transcript))
                
                // Generate response
                updateState(VoiceSessionState.Generating)
                val response = RunAnywhere.generate(transcript)
                
                _events.emit(VoicePipelineEvent.ResponseGenerated(transcript, response))
                
                // Speak response
                updateState(VoiceSessionState.Speaking)
                synthesizeSpeech(response)
                
                // Return to listening
                updateState(VoiceSessionState.Listening)
                
            } else {
                _events.emit(VoicePipelineEvent.TranscriptionEmpty)
                updateState(VoiceSessionState.Listening)
            }
            
        } catch (e: Exception) {
            _events.emit(VoicePipelineEvent.Error(e))
            updateState(VoiceSessionState.Error(e.message ?: "Processing failed"))
        }
    }
    
    private fun synthesizeSpeech(text: String) {
        ttsService.speak(text, TextToSpeech.QUEUE_FLUSH, null, "voice_response")
    }
    
    private fun convertToFloatArray(audioData: ByteArray): FloatArray {
        val floatArray = FloatArray(audioData.size / 2)
        val byteBuffer = ByteBuffer.wrap(audioData).order(ByteOrder.LITTLE_ENDIAN)
        
        for (i in floatArray.indices) {
            floatArray[i] = byteBuffer.short.toFloat() / Short.MAX_VALUE
        }
        
        return floatArray
    }
    
    fun stopVoiceSession() {
        audioJob?.cancel()
        currentSession?.cancel()
        audioCaptureService.stopCapture()
        updateState(VoiceSessionState.Idle)
    }
    
    private fun updateState(newState: VoiceSessionState) {
        _sessionState.value = newState
    }
}
```

### Task 1.3: Error Recovery and Robustness
**Files**: `app/src/main/java/com/runanywhere/runanywhereai/presentation/voice/VoiceAssistantViewModel.kt`

```kotlin
class RobustVoiceAssistantViewModel(
    private val voicePipelineService: VoicePipelineService,
    private val applicationContext: Context
) : ViewModel() {
    
    private val _uiState = MutableStateFlow(VoiceAssistantUiState())
    val uiState: StateFlow<VoiceAssistantUiState> = _uiState.asStateFlow()
    
    private var retryAttempts = 0
    private val maxRetries = 3
    
    init {
        // Monitor pipeline events with error recovery
        viewModelScope.launch {
            voicePipelineService.events.collect { event ->
                handlePipelineEvent(event)
            }
        }
        
        // Monitor session state
        viewModelScope.launch {
            voicePipelineService.sessionState.collect { state ->
                updateUIState { copy(sessionState = state) }
            }
        }
    }
    
    private suspend fun handlePipelineEvent(event: VoicePipelineEvent) {
        when (event) {
            is VoicePipelineEvent.Error -> {
                handleError(event.error)
            }
            
            is VoicePipelineEvent.TranscriptionComplete -> {
                updateUIState { 
                    copy(
                        transcription = event.transcript,
                        conversationHistory = conversationHistory + 
                            ConversationTurn(event.transcript, null, System.currentTimeMillis())
                    )
                }
                retryAttempts = 0 // Reset on success
            }
            
            is VoicePipelineEvent.ResponseGenerated -> {
                updateUIState { 
                    copy(
                        lastResponse = event.response,
                        conversationHistory = conversationHistory.map { turn ->
                            if (turn.userMessage == event.transcript && turn.assistantResponse == null) {
                                turn.copy(assistantResponse = event.response)
                            } else turn
                        }
                    )
                }
            }
            
            is VoicePipelineEvent.SessionTimeout -> {
                updateUIState { copy(sessionState = VoiceSessionState.Idle) }
                showUserMessage("Voice session timed out")
            }
        }
    }
    
    private suspend fun handleError(error: Throwable) {
        when {
            error is SecurityException -> {
                updateUIState { copy(sessionState = VoiceSessionState.Error("Microphone permission required")) }
                requestMicrophonePermission()
            }
            
            error.message?.contains("AudioRecord") == true -> {
                if (retryAttempts < maxRetries) {
                    retryAttempts++
                    delay(1000 * retryAttempts) // Exponential backoff
                    startVoiceSession() // Retry
                } else {
                    updateUIState { copy(sessionState = VoiceSessionState.Error("Audio system unavailable")) }
                }
            }
            
            error.message?.contains("network") == true -> {
                updateUIState { copy(sessionState = VoiceSessionState.Error("Network connection required")) }
            }
            
            else -> {
                updateUIState { copy(sessionState = VoiceSessionState.Error(error.message ?: "Unknown error")) }
            }
        }
    }
    
    fun startVoiceSession() {
        viewModelScope.launch {
            try {
                voicePipelineService.startVoiceSession()
            } catch (e: Exception) {
                handleError(e)
            }
        }
    }
    
    fun stopVoiceSession() {
        voicePipelineService.stopVoiceSession()
        retryAttempts = 0
    }
    
    private fun updateUIState(update: VoiceAssistantUiState.() -> VoiceAssistantUiState) {
        _uiState.value = _uiState.value.update()
    }
}
```

**Success Criteria**:
- [ ] Audio capture works reliably without dropouts
- [ ] Voice pipeline handles errors gracefully
- [ ] Session state management is clear and consistent
- [ ] Error recovery works for common failure modes
- [ ] Real-time voice conversation works end-to-end

---

## Phase 2: Settings Implementation (Day 3-5)
**Duration**: 2-3 days  
**Priority**: HIGH  

### Task 2.1: Settings Data Layer
**Files**: `app/src/main/java/com/runanywhere/runanywhereai/domain/model/AppSettings.kt`

```kotlin
@Serializable
data class AppSettings(
    val sdkSettings: SDKSettings = SDKSettings(),
    val voiceSettings: VoiceSettings = VoiceSettings(),
    val uiSettings: UISettings = UISettings(),
    val privacySettings: PrivacySettings = PrivacySettings()
)

@Serializable
data class SDKSettings(
    val defaultLLMModel: String = "llama-3.2-1b",
    val defaultSTTModel: String = "whisper-base",
    val maxTokens: Int = 1000,
    val temperature: Float = 0.7f,
    val topP: Float = 0.9f,
    val topK: Int = 40,
    val enableAnalytics: Boolean = true,
    val enableCostTracking: Boolean = true,
    val apiBaseUrl: String = "",
    val environment: String = "development"
)

@Serializable
data class VoiceSettings(
    val sttModel: String = "whisper-base",
    val llmModel: String = "llama-3.2-1b",
    val ttsVoice: String = "default",
    val speechRate: Float = 1.0f,
    val speechPitch: Float = 1.0f,
    val enableVAD: Boolean = true,
    val vadSensitivity: Float = 0.5f,
    val enableDiarization: Boolean = false,
    val voiceSessionTimeout: Int = 30 // seconds
)

@Serializable
data class UISettings(
    val enableStreamingAnimation: Boolean = true,
    val showDetailedAnalytics: Boolean = true,
    val enableHapticFeedback: Boolean = true,
    val themeMode: ThemeMode = ThemeMode.SYSTEM,
    val showModelBadges: Boolean = true,
    val enableDebugLogging: Boolean = false
)

@Serializable
data class PrivacySettings(
    val enableTelemetry: Boolean = true,
    val enableCrashReporting: Boolean = true,
    val enableUsageAnalytics: Boolean = true,
    val dataRetentionDays: Int = 30,
    val shareErrorReports: Boolean = true
)

enum class ThemeMode {
    LIGHT, DARK, SYSTEM
}
```

### Task 2.2: Settings Repository Implementation
**Files**: `app/src/main/java/com/runanywhere/runanywhereai/data/repositories/SettingsRepository.kt`

```kotlin
interface SettingsRepository {
    suspend fun getSettings(): AppSettings
    suspend fun saveSettings(settings: AppSettings)
    suspend fun updateSDKSettings(sdkSettings: SDKSettings)
    suspend fun updateVoiceSettings(voiceSettings: VoiceSettings)
    fun getSettingsFlow(): Flow<AppSettings>
}

class SettingsRepositoryImpl(
    private val dataStore: DataStore<Preferences>,
    private val context: Context
) : SettingsRepository {
    
    private val gson = Gson()
    
    override suspend fun getSettings(): AppSettings {
        return dataStore.data.first().toAppSettings()
    }
    
    override suspend fun saveSettings(settings: AppSettings) {
        dataStore.edit { preferences ->
            // SDK Settings
            preferences[PreferencesKeys.SDK_DEFAULT_LLM_MODEL] = settings.sdkSettings.defaultLLMModel
            preferences[PreferencesKeys.SDK_DEFAULT_STT_MODEL] = settings.sdkSettings.defaultSTTModel
            preferences[PreferencesKeys.SDK_MAX_TOKENS] = settings.sdkSettings.maxTokens
            preferences[PreferencesKeys.SDK_TEMPERATURE] = settings.sdkSettings.temperature
            preferences[PreferencesKeys.SDK_TOP_P] = settings.sdkSettings.topP
            preferences[PreferencesKeys.SDK_TOP_K] = settings.sdkSettings.topK
            
            // Voice Settings
            preferences[PreferencesKeys.VOICE_STT_MODEL] = settings.voiceSettings.sttModel
            preferences[PreferencesKeys.VOICE_LLM_MODEL] = settings.voiceSettings.llmModel
            preferences[PreferencesKeys.VOICE_TTS_VOICE] = settings.voiceSettings.ttsVoice
            preferences[PreferencesKeys.VOICE_SPEECH_RATE] = settings.voiceSettings.speechRate
            preferences[PreferencesKeys.VOICE_ENABLE_VAD] = settings.voiceSettings.enableVAD
            
            // UI Settings
            preferences[PreferencesKeys.UI_ENABLE_STREAMING] = settings.uiSettings.enableStreamingAnimation
            preferences[PreferencesKeys.UI_SHOW_ANALYTICS] = settings.uiSettings.showDetailedAnalytics
            preferences[PreferencesKeys.UI_THEME_MODE] = settings.uiSettings.themeMode.name
            
            // Privacy Settings
            preferences[PreferencesKeys.PRIVACY_ENABLE_TELEMETRY] = settings.privacySettings.enableTelemetry
            preferences[PreferencesKeys.PRIVACY_ENABLE_ANALYTICS] = settings.privacySettings.enableUsageAnalytics
        }
        
        // Apply settings to SDK
        applySettingsToSDK(settings)
    }
    
    override fun getSettingsFlow(): Flow<AppSettings> {
        return dataStore.data.map { preferences ->
            preferences.toAppSettings()
        }
    }
    
    private suspend fun applySettingsToSDK(settings: AppSettings) {
        try {
            // Update SDK configuration in real-time
            val sdkConfig = mapOf(
                "defaultLLMModel" to settings.sdkSettings.defaultLLMModel,
                "defaultSTTModel" to settings.sdkSettings.defaultSTTModel,
                "maxTokens" to settings.sdkSettings.maxTokens,
                "temperature" to settings.sdkSettings.temperature,
                "topP" to settings.sdkSettings.topP,
                "topK" to settings.sdkSettings.topK
            )
            
            // Apply to SDK (this would need SDK support for runtime config updates)
            // RunAnywhere.updateConfiguration(sdkConfig)
            
        } catch (e: Exception) {
            logger.error("Failed to apply settings to SDK", e)
        }
    }
    
    private fun Preferences.toAppSettings(): AppSettings {
        return AppSettings(
            sdkSettings = SDKSettings(
                defaultLLMModel = this[PreferencesKeys.SDK_DEFAULT_LLM_MODEL] ?: "llama-3.2-1b",
                defaultSTTModel = this[PreferencesKeys.SDK_DEFAULT_STT_MODEL] ?: "whisper-base",
                maxTokens = this[PreferencesKeys.SDK_MAX_TOKENS] ?: 1000,
                temperature = this[PreferencesKeys.SDK_TEMPERATURE] ?: 0.7f,
                topP = this[PreferencesKeys.SDK_TOP_P] ?: 0.9f,
                topK = this[PreferencesKeys.SDK_TOP_K] ?: 40
            ),
            voiceSettings = VoiceSettings(
                sttModel = this[PreferencesKeys.VOICE_STT_MODEL] ?: "whisper-base",
                llmModel = this[PreferencesKeys.VOICE_LLM_MODEL] ?: "llama-3.2-1b",
                ttsVoice = this[PreferencesKeys.VOICE_TTS_VOICE] ?: "default",
                speechRate = this[PreferencesKeys.VOICE_SPEECH_RATE] ?: 1.0f,
                enableVAD = this[PreferencesKeys.VOICE_ENABLE_VAD] ?: true
            ),
            uiSettings = UISettings(
                enableStreamingAnimation = this[PreferencesKeys.UI_ENABLE_STREAMING] ?: true,
                showDetailedAnalytics = this[PreferencesKeys.UI_SHOW_ANALYTICS] ?: true,
                themeMode = ThemeMode.valueOf(this[PreferencesKeys.UI_THEME_MODE] ?: "SYSTEM")
            ),
            privacySettings = PrivacySettings(
                enableTelemetry = this[PreferencesKeys.PRIVACY_ENABLE_TELEMETRY] ?: true,
                enableUsageAnalytics = this[PreferencesKeys.PRIVACY_ENABLE_ANALYTICS] ?: true
            )
        )
    }
    
    object PreferencesKeys {
        val SDK_DEFAULT_LLM_MODEL = stringPreferencesKey("sdk_default_llm_model")
        val SDK_DEFAULT_STT_MODEL = stringPreferencesKey("sdk_default_stt_model")
        val SDK_MAX_TOKENS = intPreferencesKey("sdk_max_tokens")
        val SDK_TEMPERATURE = floatPreferencesKey("sdk_temperature")
        val SDK_TOP_P = floatPreferencesKey("sdk_top_p")
        val SDK_TOP_K = intPreferencesKey("sdk_top_k")
        
        val VOICE_STT_MODEL = stringPreferencesKey("voice_stt_model")
        val VOICE_LLM_MODEL = stringPreferencesKey("voice_llm_model")
        val VOICE_TTS_VOICE = stringPreferencesKey("voice_tts_voice")
        val VOICE_SPEECH_RATE = floatPreferencesKey("voice_speech_rate")
        val VOICE_ENABLE_VAD = booleanPreferencesKey("voice_enable_vad")
        
        val UI_ENABLE_STREAMING = booleanPreferencesKey("ui_enable_streaming")
        val UI_SHOW_ANALYTICS = booleanPreferencesKey("ui_show_analytics")
        val UI_THEME_MODE = stringPreferencesKey("ui_theme_mode")
        
        val PRIVACY_ENABLE_TELEMETRY = booleanPreferencesKey("privacy_enable_telemetry")
        val PRIVACY_ENABLE_ANALYTICS = booleanPreferencesKey("privacy_enable_analytics")
    }
}
```

### Task 2.3: Settings UI Implementation
**Files**: `app/src/main/java/com/runanywhere/runanywhereai/presentation/settings/SettingsScreen.kt`

```kotlin
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val settings by viewModel.settings.collectAsState()
    val availableModels by viewModel.availableModels.collectAsState()
    val uiState by viewModel.uiState.collectAsState()
    
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // SDK Configuration Section
        item {
            SettingsSection(
                title = "AI Model Configuration",
                icon = Icons.Default.Psychology,
                description = "Configure AI models and generation parameters"
            ) {
                ModelSelectionSetting(
                    title = "Default LLM Model",
                    subtitle = "Model used for text generation",
                    selectedModel = settings.sdkSettings.defaultLLMModel,
                    availableModels = availableModels.llmModels,
                    onModelSelected = viewModel::updateDefaultLLMModel
                )
                
                ModelSelectionSetting(
                    title = "Default STT Model", 
                    subtitle = "Model used for speech recognition",
                    selectedModel = settings.sdkSettings.defaultSTTModel,
                    availableModels = availableModels.sttModels,
                    onModelSelected = viewModel::updateDefaultSTTModel
                )
                
                SliderSetting(
                    title = "Temperature",
                    subtitle = "Controls randomness in generation (0.0 = deterministic, 2.0 = very random)",
                    value = settings.sdkSettings.temperature,
                    valueRange = 0f..2f,
                    steps = 19, // 0.1 increments
                    onValueChange = viewModel::updateTemperature,
                    valueFormatter = { "%.1f".format(it) }
                )
                
                SliderSetting(
                    title = "Max Tokens",
                    subtitle = "Maximum length of generated responses",
                    value = settings.sdkSettings.maxTokens.toFloat(),
                    valueRange = 100f..4000f,
                    steps = 39, // 100 token increments
                    onValueChange = { viewModel.updateMaxTokens(it.toInt()) },
                    valueFormatter = { "${it.toInt()} tokens" }
                )
                
                SliderSetting(
                    title = "Top-P",
                    subtitle = "Controls diversity via nucleus sampling",
                    value = settings.sdkSettings.topP,
                    valueRange = 0.1f..1.0f,
                    steps = 17, // 0.05 increments
                    onValueChange = viewModel::updateTopP,
                    valueFormatter = { "%.2f".format(it) }
                )
            }
        }
        
        // Voice Configuration Section
        item {
            SettingsSection(
                title = "Voice Assistant",
                icon = Icons.Default.RecordVoiceOver,
                description = "Configure voice interaction settings"
            ) {
                ModelSelectionSetting(
                    title = "Speech-to-Text Model",
                    subtitle = "Model for voice recognition",
                    selectedModel = settings.voiceSettings.sttModel,
                    availableModels = availableModels.sttModels,
                    onModelSelected = viewModel::updateVoiceSTTModel
                )
                
                ModelSelectionSetting(
                    title = "Voice LLM Model",
                    subtitle = "Model for voice conversation responses",
                    selectedModel = settings.voiceSettings.llmModel,
                    availableModels = availableModels.llmModels,
                    onModelSelected = viewModel::updateVoiceLLMModel
                )
                
                SwitchSetting(
                    title = "Voice Activity Detection",
                    subtitle = "Automatically detect when you start and stop speaking",
                    checked = settings.voiceSettings.enableVAD,
                    onCheckedChange = viewModel::updateVADEnabled
                )
                
                SliderSetting(
                    title = "Speech Rate",
                    subtitle = "Speed of text-to-speech output",
                    value = settings.voiceSettings.speechRate,
                    valueRange = 0.5f..2f,
                    steps = 14, // 0.1 increments
                    onValueChange = viewModel::updateSpeechRate,
                    valueFormatter = { "${(it * 100).toInt()}%" }
                )
            }
        }
        
        // User Interface Section
        item {
            SettingsSection(
                title = "User Interface",
                icon = Icons.Default.Palette,
                description = "Customize app appearance and behavior"
            ) {
                DropdownSetting(
                    title = "Theme",
                    subtitle = "App color scheme",
                    selectedValue = settings.uiSettings.themeMode.name,
                    options = ThemeMode.values().map { 
                        it.name to when(it) {
                            ThemeMode.LIGHT -> "Light"
                            ThemeMode.DARK -> "Dark" 
                            ThemeMode.SYSTEM -> "Follow System"
                        }
                    },
                    onValueSelected = { themeName ->
                        viewModel.updateThemeMode(ThemeMode.valueOf(themeName))
                    }
                )
                
                SwitchSetting(
                    title = "Streaming Animation",
                    subtitle = "Show real-time typing animation for AI responses",
                    checked = settings.uiSettings.enableStreamingAnimation,
                    onCheckedChange = viewModel::updateStreamingAnimation
                )
                
                SwitchSetting(
                    title = "Detailed Analytics",
                    subtitle = "Show performance metrics and timing information",
                    checked = settings.uiSettings.showDetailedAnalytics,
                    onCheckedChange = viewModel::updateShowAnalytics
                )
                
                SwitchSetting(
                    title = "Haptic Feedback",
                    subtitle = "Vibration feedback for interactions",
                    checked = settings.uiSettings.enableHapticFeedback,
                    onCheckedChange = viewModel::updateHapticFeedback
                )
            }
        }
        
        // Privacy & Data Section
        item {
            SettingsSection(
                title = "Privacy & Data",
                icon = Icons.Default.PrivacyTip,
                description = "Control data collection and sharing"
            ) {
                SwitchSetting(
                    title = "Usage Analytics",
                    subtitle = "Help improve the app by sharing anonymous usage data",
                    checked = settings.privacySettings.enableUsageAnalytics,
                    onCheckedChange = viewModel::updateAnalyticsEnabled
                )
                
                SwitchSetting(
                    title = "Error Reporting",
                    subtitle = "Automatically report crashes and errors",
                    checked = settings.privacySettings.enableCrashReporting,
                    onCheckedChange = viewModel::updateCrashReporting
                )
                
                SwitchSetting(
                    title = "Performance Telemetry",
                    subtitle = "Share performance metrics to help optimize the service",
                    checked = settings.privacySettings.enableTelemetry,
                    onCheckedChange = viewModel::updateTelemetryEnabled
                )
                
                SliderSetting(
                    title = "Data Retention",
                    subtitle = "How long to keep local conversation data",
                    value = settings.privacySettings.dataRetentionDays.toFloat(),
                    valueRange = 1f..90f,
                    steps = 88, // 1 day increments
                    onValueChange = { viewModel.updateDataRetention(it.toInt()) },
                    valueFormatter = { "${it.toInt()} days" }
                )
            }
        }
        
        // Actions Section
        item {
            SettingsSection(
                title = "Data Management",
                icon = Icons.Default.Storage,
                description = "Manage app data and cache"
            ) {
                ActionSetting(
                    title = "Clear Conversation History",
                    subtitle = "Delete all stored conversations",
                    actionText = "Clear",
                    onClick = { viewModel.clearConversationHistory() },
                    isDestructive = true
                )
                
                ActionSetting(
                    title = "Clear Model Cache",
                    subtitle = "Free up space by removing downloaded models",
                    actionText = "Clear",
                    onClick = { viewModel.clearModelCache() }
                )
                
                ActionSetting(
                    title = "Reset to Defaults",
                    subtitle = "Restore all settings to default values",
                    actionText = "Reset",
                    onClick = { viewModel.resetToDefaults() },
                    isDestructive = true
                )
            }
        }
    }
}
```

**Success Criteria**:
- [ ] All settings persist correctly across app restarts
- [ ] Settings changes take effect immediately
- [ ] SDK configuration updates in real-time
- [ ] Model selection affects app behavior
- [ ] Privacy controls work as expected

---

## Phase 3: Storage Management Implementation (Day 5-7)
**Duration**: 2-3 days  
**Priority**: MEDIUM  

### Task 3.1: Storage Analysis Service
**Files**: `app/src/main/java/com/runanywhere/runanywhereai/domain/services/StorageAnalysisService.kt`

```kotlin
class StorageAnalysisService(private val context: Context) {
    
    fun getStorageInfo(): StorageInfo {
        val internalStorage = getInternalStorageInfo()
        val externalStorage = getExternalStorageInfo()
        val appStorage = getAppStorageInfo()
        
        return StorageInfo(
            internal = internalStorage,
            external = externalStorage,
            app = appStorage,
            totalSpace = internalStorage.totalBytes + (externalStorage?.totalBytes ?: 0),
            availableSpace = internalStorage.availableBytes + (externalStorage?.availableBytes ?: 0)
        )
    }
    
    private fun getInternalStorageInfo(): StorageDetails {
        val internalDir = context.filesDir
        val statFs = StatFs(internalDir.path)
        
        val blockSize = statFs.blockSizeLong
        val totalBlocks = statFs.blockCountLong
        val availableBlocks = statFs.availableBlocksLong
        
        return StorageDetails(
            path = internalDir.path,
            totalBytes = totalBlocks * blockSize,
            availableBytes = availableBlocks * blockSize,
            usedBytes = (totalBlocks - availableBlocks) * blockSize
        )
    }
    
    private fun getExternalStorageInfo(): StorageDetails? {
        return if (Environment.getExternalStorageState() == Environment.MEDIA_MOUNTED) {
            val externalDir = context.getExternalFilesDir(null) ?: return null
            val statFs = StatFs(externalDir.path)
            
            val blockSize = statFs.blockSizeLong
            val totalBlocks = statFs.blockCountLong
            val availableBlocks = statFs.availableBlocksLong
            
            StorageDetails(
                path = externalDir.path,
                totalBytes = totalBlocks * blockSize,
                availableBytes = availableBlocks * blockSize,
                usedBytes = (totalBlocks - availableBlocks) * blockSize
            )
        } else null
    }
    
    private fun getAppStorageInfo(): AppStorageDetails {
        val cacheSize = calculateDirectorySize(context.cacheDir)
        val dataSize = calculateDirectorySize(context.filesDir)
        val databaseSize = getDatabaseSize()
        val modelsSize = getModelsSize()
        
        return AppStorageDetails(
            totalAppSize = cacheSize + dataSize + databaseSize,
            cacheSize = cacheSize,
            dataSize = dataSize,
            databaseSize = databaseSize,
            modelsSize = modelsSize,
            breakdown = getStorageBreakdown()
        )
    }
    
    fun getModelInventory(): List<ModelStorageInfo> {
        val modelDir = File(context.filesDir, "models")
        if (!modelDir.exists()) return emptyList()
        
        return modelDir.listFiles()?.mapNotNull { file ->
            if (file.isFile) {
                val modelInfo = analyzeModelFile(file)
                ModelStorageInfo(
                    modelId = file.nameWithoutExtension,
                    fileName = file.name,
                    filePath = file.absolutePath,
                    sizeBytes = file.length(),
                    lastModified = file.lastModified(),
                    modelType = modelInfo.type,
                    isActive = modelInfo.isCurrentlyLoaded,
                    downloadDate = Date(file.lastModified()),
                    checksum = calculateFileChecksum(file)
                )
            } else null
        }?.sortedByDescending { it.lastModified } ?: emptyList()
    }
    
    suspend fun cleanupCache(): CleanupResult {
        return withContext(Dispatchers.IO) {
            var cleanedBytes = 0L
            val errors = mutableListOf<String>()
            
            try {
                // Clear app cache
                val cacheDeleted = deleteDirectoryContents(context.cacheDir)
                cleanedBytes += cacheDeleted
                
                // Clear temporary files
                val tempDir = File(context.filesDir, "temp")
                if (tempDir.exists()) {
                    val tempDeleted = deleteDirectoryContents(tempDir)
                    cleanedBytes += tempDeleted
                }
                
                // Clear old conversation exports
                val exportDir = File(context.filesDir, "exports")
                if (exportDir.exists()) {
                    val exportDeleted = deleteOldFiles(exportDir, maxAgeMs = 7 * 24 * 60 * 60 * 1000) // 7 days
                    cleanedBytes += exportDeleted
                }
                
            } catch (e: Exception) {
                errors.add("Cache cleanup failed: ${e.message}")
            }
            
            CleanupResult(
                bytesFreed = cleanedBytes,
                errors = errors
            )
        }
    }
    
    suspend fun deleteModel(modelId: String): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val modelFile = File(context.filesDir, "models/$modelId.bin")
                if (modelFile.exists()) {
                    modelFile.delete()
                } else {
                    // Try alternative extensions
                    val alternatives = listOf(".gguf", ".onnx", ".tflite")
                    alternatives.any { ext ->
                        File(context.filesDir, "models/$modelId$ext").let { file ->
                            if (file.exists()) {
                                file.delete()
                            } else false
                        }
                    }
                }
            } catch (e: Exception) {
                logger.error("Failed to delete model: $modelId", e)
                false
            }
        }
    }
    
    private fun calculateDirectorySize(directory: File): Long {
        if (!directory.exists()) return 0L
        
        return directory.walkTopDown()
            .filter { it.isFile }
            .sumOf { it.length() }
    }
    
    private fun analyzeModelFile(file: File): ModelFileInfo {
        val extension = file.extension.lowercase()
        val isCurrentlyLoaded = checkIfModelIsLoaded(file.nameWithoutExtension)
        
        val type = when {
            extension == "bin" || extension == "gguf" -> ModelType.LLM
            extension.contains("whisper") -> ModelType.STT
            extension == "onnx" -> ModelType.NEURAL_NETWORK
            extension == "tflite" -> ModelType.TENSORFLOW_LITE
            else -> ModelType.UNKNOWN
        }
        
        return ModelFileInfo(type, isCurrentlyLoaded)
    }
    
    private fun checkIfModelIsLoaded(modelId: String): Boolean {
        // This would check with the SDK if the model is currently loaded
        // For now, return false as a placeholder
        return false
    }
}

data class StorageInfo(
    val internal: StorageDetails,
    val external: StorageDetails?,
    val app: AppStorageDetails,
    val totalSpace: Long,
    val availableSpace: Long
) {
    val usedSpace: Long get() = totalSpace - availableSpace
    val usagePercentage: Float get() = (usedSpace.toFloat() / totalSpace) * 100
}

data class ModelStorageInfo(
    val modelId: String,
    val fileName: String,
    val filePath: String,
    val sizeBytes: Long,
    val lastModified: Long,
    val modelType: ModelType,
    val isActive: Boolean,
    val downloadDate: Date,
    val checksum: String?
)

enum class ModelType {
    LLM, STT, TTS, NEURAL_NETWORK, TENSORFLOW_LITE, UNKNOWN
}
```

### Task 3.2: Storage UI Implementation
**Files**: `app/src/main/java/com/runanywhere/runanywhereai/presentation/storage/StorageScreen.kt`

```kotlin
@Composable
fun StorageScreen(
    viewModel: StorageViewModel = hiltViewModel()
) {
    val storageInfo by viewModel.storageInfo.collectAsState()
    val modelInventory by viewModel.modelInventory.collectAsState()
    val uiState by viewModel.uiState.collectAsState()
    
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Storage Overview Section
        item {
            StorageOverviewCard(
                storageInfo = storageInfo,
                onCleanupCache = viewModel::cleanupCache
            )
        }
        
        // Device Information Section
        item {
            DeviceInfoCard()
        }
        
        // Model Inventory Section
        item {
            ModelInventorySection(
                models = modelInventory,
                onDeleteModel = viewModel::deleteModel,
                onModelDetails = viewModel::showModelDetails
            )
        }
        
        // Storage Breakdown Section
        item {
            StorageBreakdownCard(storageInfo.app)
        }
    }
    
    // Handle UI states
    when {
        uiState.isCleaningUp -> {
            CleanupProgressDialog(
                onDismiss = { /* Handle cleanup completion */ }
            )
        }
        
        uiState.cleanupResult != null -> {
            CleanupResultDialog(
                result = uiState.cleanupResult,
                onDismiss = viewModel::dismissCleanupResult
            )
        }
    }
}

@Composable
private fun StorageOverviewCard(
    storageInfo: StorageInfo,
    onCleanupCache: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = "Storage Overview",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
            
            // Storage usage visualization
            StorageUsageBar(
                usedBytes = storageInfo.usedSpace,
                totalBytes = storageInfo.totalSpace,
                modifier = Modifier.fillMaxWidth()
            )
            
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                StorageInfoItem(
                    label = "Used",
                    value = formatBytes(storageInfo.usedSpace),
                    color = MaterialTheme.colorScheme.primary
                )
                
                StorageInfoItem(
                    label = "Available", 
                    value = formatBytes(storageInfo.availableSpace),
                    color = MaterialTheme.colorScheme.outline
                )
                
                StorageInfoItem(
                    label = "Total",
                    value = formatBytes(storageInfo.totalSpace),
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
            
            // App storage breakdown
            AppStorageBreakdown(storageInfo.app)
            
            // Cleanup action
            OutlinedButton(
                onClick = onCleanupCache,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.CleaningServices, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Clean Up Cache")
            }
        }
    }
}

@Composable
private fun ModelInventorySection(
    models: List<ModelStorageInfo>,
    onDeleteModel: (String) -> Unit,
    onModelDetails: (ModelStorageInfo) -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Downloaded Models",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )
                
                Text(
                    text = "${models.size} models",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            
            Spacer(modifier = Modifier.height(12.dp))
            
            if (models.isEmpty()) {
                EmptyStateMessage(
                    icon = Icons.Default.ModelTraining,
                    message = "No models downloaded yet",
                    subMessage = "Models will appear here after downloading"
                )
            } else {
                models.forEach { model ->
                    ModelInventoryItem(
                        model = model,
                        onDelete = { onDeleteModel(model.modelId) },
                        onShowDetails = { onModelDetails(model) }
                    )
                    
                    if (model != models.last()) {
                        Divider(modifier = Modifier.padding(vertical = 8.dp))
                    }
                }
            }
        }
    }
}
```

**Success Criteria**:
- [ ] Storage analysis shows accurate information
- [ ] Model inventory displays all downloaded models
- [ ] Cache cleanup frees up space
- [ ] Model deletion works correctly
- [ ] Storage visualization is clear and informative

---

## Phase 4: Model Management Backend Integration (Day 7-8)
**Duration**: 1-2 days  
**Priority**: MEDIUM  

### Task 4.1: Connect Model UI to SDK
**Files**: `app/src/main/java/com/runanywhere/runanywhereai/presentation/models/ModelManagementViewModel.kt`

```kotlin
class ModelManagementViewModel(
    private val modelRepository: ModelRepository,
    private val settingsRepository: SettingsRepository
) : ViewModel() {
    
    private val _uiState = MutableStateFlow(ModelManagementUiState())
    val uiState: StateFlow<ModelManagementUiState> = _uiState.asStateFlow()
    
    init {
        loadModels()
        observeDownloadProgress()
    }
    
    private fun loadModels() {
        viewModelScope.launch {
            try {
                updateState { copy(isLoading = true) }
                
                // Get available models from SDK
                val availableModels = RunAnywhere.availableModels()
                val downloadedModels = getDownloadedModels()
                
                val modelCategories = categorizeModels(availableModels, downloadedModels)
                
                updateState { 
                    copy(
                        isLoading = false,
                        modelCategories = modelCategories,
                        currentModel = getCurrentModel()
                    )
                }
                
            } catch (e: Exception) {
                updateState { 
                    copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load models"
                    )
                }
            }
        }
    }
    
    fun downloadModel(modelId: String) {
        viewModelScope.launch {
            try {
                // Start download through SDK
                RunAnywhere.downloadModel(modelId).collect { progress ->
                    updateDownloadProgress(modelId, progress)
                }
                
                // Refresh model list after download
                loadModels()
                
            } catch (e: Exception) {
                updateState { 
                    copy(error = "Download failed: ${e.message}")
                }
            }
        }
    }
    
    fun loadModel(modelId: String) {
        viewModelScope.launch {
            try {
                updateState { copy(isLoading = true) }
                
                val success = RunAnywhere.loadModel(modelId)
                
                if (success) {
                    // Update current model
                    updateState { 
                        copy(
                            isLoading = false,
                            currentModel = modelId
                        )
                    }
                    
                    // Update default model in settings
                    val currentSettings = settingsRepository.getSettings()
                    settingsRepository.saveSettings(
                        currentSettings.copy(
                            sdkSettings = currentSettings.sdkSettings.copy(
                                defaultLLMModel = modelId
                            )
                        )
                    )
                    
                } else {
                    updateState { 
                        copy(
                            isLoading = false,
                            error = "Failed to load model: $modelId"
                        )
                    }
                }
                
            } catch (e: Exception) {
                updateState { 
                    copy(
                        isLoading = false,
                        error = "Model loading error: ${e.message}"
                    )
                }
            }
        }
    }
    
    private fun observeDownloadProgress() {
        viewModelScope.launch {
            // This would observe SDK download progress events
            // For now, we'll implement a placeholder
            
            // RunAnywhere.downloadEvents.collect { event ->
            //     when (event) {
            //         is DownloadStarted -> updateDownloadProgress(event.modelId, 0f)
            //         is DownloadProgress -> updateDownloadProgress(event.modelId, event.progress)
            //         is DownloadCompleted -> {
            //             updateDownloadProgress(event.modelId, 1f)
            //             loadModels() // Refresh
            //         }
            //         is DownloadFailed -> {
            //             updateState { copy(error = "Download failed: ${event.error}") }
            //         }
            //     }
            // }
        }
    }
    
    private fun updateDownloadProgress(modelId: String, progress: Float) {
        updateState { 
            copy(
                downloadProgress = downloadProgress.toMutableMap().apply {
                    put(modelId, progress)
                }
            )
        }
    }
    
    private suspend fun getCurrentModel(): String? {
        return try {
            RunAnywhere.currentModel?.id
        } catch (e: Exception) {
            null
        }
    }
    
    private fun updateState(update: ModelManagementUiState.() -> ModelManagementUiState) {
        _uiState.value = _uiState.value.update()
    }
}
```

**Success Criteria**:
- [ ] Model downloads work from UI
- [ ] Download progress is accurate and real-time
- [ ] Model loading changes the active model
- [ ] Settings update to reflect model changes
- [ ] Error handling works for failed operations

---

## Success Metrics & Validation

### Functional Validation ✅
- [ ] Voice assistant works reliably end-to-end
- [ ] Settings persist and affect app behavior
- [ ] Storage management provides accurate information
- [ ] Model downloads work from UI
- [ ] All 5 tabs are fully functional

### User Experience Validation ✅
- [ ] Voice conversations feel natural and responsive
- [ ] Settings changes take effect immediately
- [ ] Storage cleanup frees up meaningful space
- [ ] Model management is intuitive
- [ ] Error messages are helpful and actionable

### Performance Validation ✅
- [ ] Voice pipeline latency < 3 seconds end-to-end
- [ ] Settings changes apply without noticeable delay
- [ ] Storage analysis completes quickly
- [ ] Model downloads show accurate progress
- [ ] App remains responsive during background operations

---

## Risk Assessment

### High Risk 🔴
1. **Voice Pipeline Complexity**: Audio processing has many failure modes
   - **Mitigation**: Comprehensive error handling, incremental improvement
   
2. **Real-time Settings Updates**: SDK may not support runtime configuration
   - **Mitigation**: Implement app restart prompt for critical changes

### Medium Risk 🟡
1. **Storage Calculations**: Platform differences in storage APIs
   - **Mitigation**: Test on multiple devices, graceful fallbacks

2. **Model Download Integration**: SDK integration may be incomplete
   - **Mitigation**: Mock functionality until SDK is ready

This Android app completion plan builds on the strong foundation to deliver a production-ready 5-feature app with full iOS parity.