# Detailed Implementation Plan: Android/Kotlin Cross-Platform Parity
**Date**: October 8, 2025  
**Goal**: Achieve complete native parity between iOS and Android implementations  
**Timeline**: 4-5 weeks for full implementation  

## Executive Summary

This document provides a detailed, actionable implementation plan to bring the Android/Kotlin SDK and sample app to full feature parity with the iOS implementation. The plan is organized into 4 phases with specific tasks, success criteria, and validation steps.

**Current State**:
- iOS SDK: 100% complete, production-ready
- Kotlin SDK: ~75% complete, needs core service implementations
- iOS App: 100% complete, 5 full features
- Android App: ~65% complete, 2 features production-ready

**Target State**: Complete native experience parity across platforms

---

## Phase 1: SDK Critical Services Implementation 🔴
**Duration**: 8-10 days  
**Priority**: CRITICAL - Blocks core functionality  

### Task 1.1: LLM Generation Service Integration
**Files to Modify**:
- `src/commonMain/kotlin/com/runanywhere/sdk/generation/GenerationService.kt`
- `modules/runanywhere-llm-llamacpp/` (new module)
- `src/commonMain/kotlin/com/runanywhere/sdk/core/ModuleRegistry.kt`

**Current State**: Returns mock response "Generated response for: $prompt"

**Implementation Steps**:

#### Step 1: Create LLM Service Interface (Day 1)
```kotlin
// src/commonMain/kotlin/com/runanywhere/sdk/services/llm/LLMService.kt
interface LLMService {
    suspend fun initialize(modelPath: String): Boolean
    suspend fun generate(prompt: String, options: GenerationOptions): GenerationResult
    fun generateStream(prompt: String, options: GenerationOptions): Flow<GenerationToken>
    suspend fun cleanup()
    val isReady: Boolean
    val currentModel: String?
}

data class GenerationResult(
    val text: String,
    val tokensGenerated: Int,
    val generationTimeMs: Long,
    val metadata: Map<String, Any> = emptyMap()
)

data class GenerationToken(
    val token: String,
    val isComplete: Boolean,
    val metadata: Map<String, Any> = emptyMap()
)
```

#### Step 2: LLaMA.cpp JNI Integration (Day 1-2)
```kotlin
// native/llama-jni/src/main/kotlin/LlamaJNI.kt
object LlamaJNI {
    external fun initModel(modelPath: String): Long
    external fun generate(contextPtr: Long, prompt: String, maxTokens: Int): String
    external fun generateStream(contextPtr: Long, prompt: String, maxTokens: Int): LongArray
    external fun getStreamToken(tokenPtr: Long): String
    external fun isStreamComplete(tokenPtr: Long): Boolean
    external fun cleanup(contextPtr: Long)
    
    init {
        System.loadLibrary("llama-jni")
    }
}

// modules/runanywhere-llm-llamacpp/src/commonMain/kotlin/LlamaCppService.kt
class LlamaCppService : LLMService {
    private var contextPtr: Long = 0L
    
    override suspend fun initialize(modelPath: String): Boolean = withContext(Dispatchers.IO) {
        try {
            contextPtr = LlamaJNI.initModel(modelPath)
            contextPtr != 0L
        } catch (e: Exception) {
            logger.error("Failed to initialize LLaMA model", e)
            false
        }
    }
    
    override suspend fun generate(prompt: String, options: GenerationOptions): GenerationResult = 
        withContext(Dispatchers.IO) {
            val startTime = System.currentTimeMillis()
            val result = LlamaJNI.generate(contextPtr, prompt, options.maxTokens)
            val endTime = System.currentTimeMillis()
            
            GenerationResult(
                text = result,
                tokensGenerated = result.split(" ").size,
                generationTimeMs = endTime - startTime
            )
        }
    
    override fun generateStream(prompt: String, options: GenerationOptions): Flow<GenerationToken> = 
        flow {
            val tokenPtrs = LlamaJNI.generateStream(contextPtr, prompt, options.maxTokens)
            for (tokenPtr in tokenPtrs) {
                val token = LlamaJNI.getStreamToken(tokenPtr)
                val isComplete = LlamaJNI.isStreamComplete(tokenPtr)
                emit(GenerationToken(token, isComplete))
                if (isComplete) break
            }
        }.flowOn(Dispatchers.IO)
}
```

#### Step 3: Update GenerationService (Day 3)
```kotlin
// src/commonMain/kotlin/com/runanywhere/sdk/generation/GenerationService.kt
class GenerationService(
    private val serviceContainer: ServiceContainer
) {
    suspend fun generate(prompt: String, options: GenerationOptions): GenerationResult {
        val llmProvider = ModuleRegistry.llmProvider(options.modelId)
            ?: throw SDKError.ComponentNotAvailable("No LLM provider for model: ${options.modelId}")
        
        val llmService = llmProvider.createLLMService()
        
        // Publish generation started event
        eventBus.publish(GenerationEvent.Started(prompt, options))
        
        return try {
            val result = llmService.generate(prompt, options)
            
            // Publish generation completed event
            eventBus.publish(GenerationEvent.Completed(result))
            
            result
        } catch (e: Exception) {
            // Publish generation failed event
            eventBus.publish(GenerationEvent.Failed(e))
            throw e
        }
    }
}
```

**Success Criteria**:
- [ ] LLM service initializes with real model
- [ ] Text generation returns actual LLM responses
- [ ] Streaming generation works with Flow
- [ ] Performance metrics are tracked
- [ ] Events are published correctly

### Task 1.2: Native Platform HTTP Client Implementation
**Files to Modify**:
- `src/nativeMain/kotlin/com/runanywhere/sdk/network/NativeHttpClient.kt`
- `src/nativeMain/kotlin/com/runanywhere/sdk/network/FileWriter.kt`

**Current State**: All methods return mock responses

**Implementation Steps**:

#### Step 1: Real HTTP Client Implementation (Day 4)
```kotlin
// src/nativeMain/kotlin/com/runanywhere/sdk/network/NativeHttpClient.kt
class NativeHttpClient : HttpClient {
    private val client = HttpClient(CIO) {
        install(ContentNegotiation) {
            json()
        }
        install(HttpTimeout) {
            requestTimeoutMillis = 30000
            connectTimeoutMillis = 10000
        }
    }
    
    override suspend fun get(url: String): String = withContext(Dispatchers.IO) {
        try {
            client.get(url).body()
        } catch (e: Exception) {
            throw NetworkError.RequestFailed("GET request failed: ${e.message}", e)
        }
    }
    
    override suspend fun post(url: String, body: String): String = withContext(Dispatchers.IO) {
        try {
            client.post(url) {
                contentType(ContentType.Application.Json)
                setBody(body)
            }.body()
        } catch (e: Exception) {
            throw NetworkError.RequestFailed("POST request failed: ${e.message}", e)
        }
    }
    
    override suspend fun downloadFile(url: String, destination: String, onProgress: (Float) -> Unit): Boolean {
        return try {
            val response = client.get(url)
            val contentLength = response.headers[HttpHeaders.ContentLength]?.toLongOrNull() ?: -1L
            var downloadedBytes = 0L
            
            response.body<ByteReadChannel>().copyTo(File(destination).outputStream()) { bytesRead ->
                downloadedBytes += bytesRead
                if (contentLength > 0) {
                    onProgress(downloadedBytes.toFloat() / contentLength)
                }
            }
            true
        } catch (e: Exception) {
            logger.error("File download failed", e)
            false
        }
    }
}

// src/nativeMain/kotlin/com/runanywhere/sdk/network/FileWriter.kt
class NativeFileWriter : FileWriter {
    override suspend fun writeFile(path: String, content: String) = withContext(Dispatchers.IO) {
        try {
            File(path).parentFile?.mkdirs()
            File(path).writeText(content)
        } catch (e: Exception) {
            throw FileSystemError.WriteFailed("Failed to write file: $path", e)
        }
    }
    
    override suspend fun readFile(path: String): String = withContext(Dispatchers.IO) {
        try {
            File(path).readText()
        } catch (e: Exception) {
            throw FileSystemError.ReadFailed("Failed to read file: $path", e)
        }
    }
}
```

**Success Criteria**:
- [ ] Real HTTP requests work on native platforms
- [ ] File downloads complete with progress tracking
- [ ] Production mode initialization succeeds
- [ ] Error handling works properly

### Task 1.3: Model Download Service Implementation
**Files to Modify**:
- `src/commonMain/kotlin/com/runanywhere/sdk/services/download/DownloadService.kt`
- `src/commonMain/kotlin/com/runanywhere/sdk/models/ModelLoadingService.kt`

**Current State**: Returns fake file paths

**Implementation Steps**:

#### Step 1: Real Download Implementation (Day 5)
```kotlin
// src/commonMain/kotlin/com/runanywhere/sdk/services/download/DownloadService.kt
class ModelDownloadService(
    private val httpClient: HttpClient,
    private val fileManager: FileManager
) : DownloadService {
    
    override suspend fun downloadModel(model: ModelInfo): Flow<DownloadProgress> = flow {
        val localPath = fileManager.getModelPath(model.id)
        
        emit(DownloadProgress.Started(model.id))
        
        try {
            val downloaded = httpClient.downloadFile(
                url = model.downloadURL ?: throw IllegalArgumentException("No download URL"),
                destination = localPath,
                onProgress = { progress ->
                    // Emit progress updates
                    emit(DownloadProgress.InProgress(model.id, progress))
                }
            )
            
            if (downloaded) {
                // Verify file integrity
                val isValid = verifyModelIntegrity(localPath, model.checksum)
                if (isValid) {
                    emit(DownloadProgress.Completed(model.id, localPath))
                } else {
                    fileManager.deleteFile(localPath)
                    emit(DownloadProgress.Failed(model.id, "Integrity check failed"))
                }
            } else {
                emit(DownloadProgress.Failed(model.id, "Download failed"))
            }
        } catch (e: Exception) {
            emit(DownloadProgress.Failed(model.id, e.message ?: "Unknown error"))
        }
    }.flowOn(Dispatchers.IO)
    
    private suspend fun verifyModelIntegrity(filePath: String, expectedChecksum: String?): Boolean {
        if (expectedChecksum == null) return true
        
        return try {
            val actualChecksum = calculateSHA256(filePath)
            actualChecksum == expectedChecksum
        } catch (e: Exception) {
            logger.error("Failed to verify model integrity", e)
            false
        }
    }
}

sealed class DownloadProgress {
    data class Started(val modelId: String) : DownloadProgress()
    data class InProgress(val modelId: String, val progress: Float) : DownloadProgress()
    data class Completed(val modelId: String, val localPath: String) : DownloadProgress()
    data class Failed(val modelId: String, val error: String) : DownloadProgress()
}
```

**Success Criteria**:
- [ ] Models download from real URLs
- [ ] Progress reporting works accurately
- [ ] File integrity verification passes
- [ ] Downloaded models can be loaded and used

### Task 1.4: Memory Management Implementation
**Files to Modify**:
- `src/commonMain/kotlin/com/runanywhere/sdk/memory/AllocationManager.kt`
- `src/commonMain/kotlin/com/runanywhere/sdk/memory/CacheEviction.kt`

**Current State**: Logs message but doesn't evict models

**Implementation Steps**:

#### Step 1: Model Eviction Logic (Day 6)
```kotlin
// src/commonMain/kotlin/com/runanywhere/sdk/memory/AllocationManager.kt
class AllocationManager(
    private val memoryService: MemoryService,
    private val cacheEviction: CacheEviction
) {
    private val allocatedModels = mutableMapOf<String, AllocationInfo>()
    private val memoryThreshold = 0.85f // 85% memory usage threshold
    
    suspend fun allocateMemory(modelId: String, sizeBytes: Long): Boolean {
        // Check if we have enough memory
        val currentUsage = memoryService.getCurrentMemoryUsage()
        val totalMemory = memoryService.getTotalMemory()
        val projectedUsage = (currentUsage + sizeBytes).toFloat() / totalMemory
        
        if (projectedUsage > memoryThreshold) {
            // Try to free up memory by evicting models
            val freedMemory = evictModelsForSpace(sizeBytes)
            if (freedMemory < sizeBytes) {
                return false // Not enough memory even after eviction
            }
        }
        
        // Allocate memory for the model
        allocatedModels[modelId] = AllocationInfo(
            modelId = modelId,
            sizeBytes = sizeBytes,
            timestamp = System.currentTimeMillis(),
            accessCount = 1
        )
        
        return true
    }
    
    private suspend fun evictModelsForSpace(requiredBytes: Long): Long {
        var freedBytes = 0L
        val modelsToEvict = cacheEviction.selectModelsForEviction(
            allocatedModels.values.toList(),
            requiredBytes
        )
        
        for (modelId in modelsToEvict) {
            val allocInfo = allocatedModels[modelId]
            if (allocInfo != null) {
                // Evict the model
                evictModel(modelId)
                freedBytes += allocInfo.sizeBytes
                allocatedModels.remove(modelId)
                
                logger.info("Evicted model $modelId (${allocInfo.sizeBytes} bytes) due to memory pressure")
                
                if (freedBytes >= requiredBytes) break
            }
        }
        
        return freedBytes
    }
    
    private suspend fun evictModel(modelId: String) {
        // Signal components to unload this model
        eventBus.publish(MemoryEvent.ModelEvicted(modelId))
        
        // Give components time to cleanup
        delay(100)
        
        // Force garbage collection
        System.gc()
    }
}

// src/commonMain/kotlin/com/runanywhere/sdk/memory/CacheEviction.kt
class CacheEviction {
    fun selectModelsForEviction(
        allocatedModels: List<AllocationInfo>, 
        requiredBytes: Long
    ): List<String> {
        // Sort by LRU (least recently used)
        val sortedModels = allocatedModels.sortedBy { it.lastAccessTime }
        
        val modelsToEvict = mutableListOf<String>()
        var accumulatedBytes = 0L
        
        for (model in sortedModels) {
            modelsToEvict.add(model.modelId)
            accumulatedBytes += model.sizeBytes
            
            if (accumulatedBytes >= requiredBytes) break
        }
        
        return modelsToEvict
    }
}
```

**Success Criteria**:
- [ ] Memory pressure triggers model eviction
- [ ] LRU eviction strategy works correctly
- [ ] Models are properly unloaded from memory
- [ ] Memory usage stays within acceptable limits

---

## Phase 2: Android App Core Features 🟡
**Duration**: 6-8 days  
**Priority**: HIGH - Complete missing app functionality  

### Task 2.1: Voice Pipeline Reliability Improvements
**Files to Modify**:
- `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/domain/services/VoicePipelineService.kt`
- `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/voice/VoiceAssistantViewModel.kt`

**Current State**: UI complete, service partially functional

**Implementation Steps**:

#### Step 1: Audio Capture Improvements (Day 7)
```kotlin
// domain/services/AudioCaptureService.kt
class AudioCaptureService {
    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private val audioBuffer = ByteArray(4096)
    
    fun startCapture(): Flow<ByteArray> = flow {
        val sampleRate = 16000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        
        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            sampleRate,
            channelConfig,
            audioFormat,
            bufferSize
        ).also { record ->
            if (record.state == AudioRecord.STATE_INITIALIZED) {
                record.startRecording()
                isRecording = true
                
                while (isRecording) {
                    val bytesRead = record.read(audioBuffer, 0, audioBuffer.size)
                    if (bytesRead > 0) {
                        emit(audioBuffer.copyOf(bytesRead))
                    }
                }
            } else {
                throw IllegalStateException("Failed to initialize AudioRecord")
            }
        }
    }.flowOn(Dispatchers.IO)
    
    fun stopCapture() {
        isRecording = false
        audioRecord?.apply {
            stop()
            release()
        }
        audioRecord = null
    }
}
```

#### Step 2: Pipeline Orchestration (Day 8)
```kotlin
// domain/services/VoicePipelineService.kt
class VoicePipelineService(
    private val audioCaptureService: AudioCaptureService,
    private val vadComponent: VADComponent,
    private val sttComponent: STTComponent,
    private val llmComponent: LLMComponent,
    private val ttsService: TextToSpeech
) {
    private val _sessionState = MutableStateFlow(VoiceSessionState.Idle)
    val sessionState: StateFlow<VoiceSessionState> = _sessionState.asStateFlow()
    
    private val _events = MutableSharedFlow<VoicePipelineEvent>()
    val events: SharedFlow<VoicePipelineEvent> = _events.asSharedFlow()
    
    suspend fun startSession() {
        try {
            updateState(VoiceSessionState.Listening)
            
            audioCaptureService.startCapture()
                .map { audioData -> processAudioChunk(audioData) }
                .collect { event ->
                    _events.emit(event)
                    handlePipelineEvent(event)
                }
        } catch (e: Exception) {
            updateState(VoiceSessionState.Error(e.message ?: "Unknown error"))
            _events.emit(VoicePipelineEvent.Error(e))
        }
    }
    
    private suspend fun processAudioChunk(audioData: ByteArray): VoicePipelineEvent {
        // VAD processing
        val vadResult = vadComponent.processAudio(audioData)
        
        return when (vadResult.activityType) {
            SpeechActivityType.SPEECH_START -> {
                VoicePipelineEvent.SpeechDetected
            }
            SpeechActivityType.SPEECH_END -> {
                val transcript = sttComponent.transcribe(vadResult.audioBuffer)
                if (transcript.isNotEmpty()) {
                    processTranscription(transcript)
                } else {
                    VoicePipelineEvent.TranscriptionEmpty
                }
            }
            SpeechActivityType.SILENCE -> {
                VoicePipelineEvent.Silence
            }
        }
    }
    
    private suspend fun processTranscription(transcript: String): VoicePipelineEvent {
        updateState(VoiceSessionState.Processing)
        
        return try {
            val response = llmComponent.generate(transcript)
            updateState(VoiceSessionState.Speaking)
            
            synthesizeSpeech(response)
            
            VoicePipelineEvent.ResponseGenerated(transcript, response)
        } catch (e: Exception) {
            VoicePipelineEvent.Error(e)
        }
    }
    
    private fun synthesizeSpeech(text: String) {
        ttsService.speak(text, TextToSpeech.QUEUE_FLUSH, null, "response_${System.currentTimeMillis()}")
    }
    
    private fun updateState(newState: VoiceSessionState) {
        _sessionState.value = newState
    }
}
```

**Success Criteria**:
- [ ] Audio capture works reliably without dropouts
- [ ] VAD accurately detects speech start/end
- [ ] STT transcription quality is good
- [ ] LLM responses are generated correctly
- [ ] TTS output is clear and timely
- [ ] Pipeline handles errors gracefully

### Task 2.2: Settings Feature Implementation
**Files to Modify**:
- `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/settings/`

**Current State**: Skeleton UI only

**Implementation Steps**:

#### Step 1: Settings Data Models (Day 9)
```kotlin
// domain/model/AppSettings.kt
data class AppSettings(
    val sdkSettings: SDKSettings = SDKSettings(),
    val voiceSettings: VoiceSettings = VoiceSettings(),
    val uiSettings: UISettings = UISettings(),
    val privacySettings: PrivacySettings = PrivacySettings()
)

data class SDKSettings(
    val defaultModel: String = "llama-3.2-1b",
    val maxTokens: Int = 1000,
    val temperature: Float = 0.7f,
    val topP: Float = 0.9f,
    val topK: Int = 40,
    val enableAnalytics: Boolean = true,
    val enableCostTracking: Boolean = true
)

data class VoiceSettings(
    val sttModel: String = "whisper-base",
    val ttsVoice: String = "default",
    val speechRate: Float = 1.0f,
    val speechPitch: Float = 1.0f,
    val enableVAD: Boolean = true,
    val vadSensitivity: Float = 0.5f,
    val enableDiarization: Boolean = false
)

data class UISettings(
    val enableStreamingAnimation: Boolean = true,
    val showDetailedAnalytics: Boolean = true,
    val enableHapticFeedback: Boolean = true,
    val themeMode: ThemeMode = ThemeMode.SYSTEM
)

data class PrivacySettings(
    val enableTelemetry: Boolean = true,
    val enableCrashReporting: Boolean = true,
    val enableUsageAnalytics: Boolean = true,
    val dataRetentionDays: Int = 30
)

enum class ThemeMode {
    LIGHT, DARK, SYSTEM
}
```

#### Step 2: Settings Repository (Day 9)
```kotlin
// domain/repositories/SettingsRepository.kt
interface SettingsRepository {
    suspend fun getSettings(): AppSettings
    suspend fun saveSettings(settings: AppSettings)
    suspend fun updateSDKSettings(sdkSettings: SDKSettings)
    suspend fun updateVoiceSettings(voiceSettings: VoiceSettings)
    fun getSettingsFlow(): Flow<AppSettings>
}

// data/repositories/SettingsRepositoryImpl.kt
class SettingsRepositoryImpl(
    private val dataStore: DataStore<Preferences>
) : SettingsRepository {
    
    override suspend fun getSettings(): AppSettings {
        return dataStore.data.first().toAppSettings()
    }
    
    override suspend fun saveSettings(settings: AppSettings) {
        dataStore.edit { preferences ->
            preferences[SDK_DEFAULT_MODEL] = settings.sdkSettings.defaultModel
            preferences[SDK_MAX_TOKENS] = settings.sdkSettings.maxTokens
            preferences[SDK_TEMPERATURE] = settings.sdkSettings.temperature
            // ... save all settings
        }
    }
    
    override fun getSettingsFlow(): Flow<AppSettings> {
        return dataStore.data.map { preferences ->
            preferences.toAppSettings()
        }
    }
    
    private fun Preferences.toAppSettings(): AppSettings {
        return AppSettings(
            sdkSettings = SDKSettings(
                defaultModel = this[SDK_DEFAULT_MODEL] ?: "llama-3.2-1b",
                maxTokens = this[SDK_MAX_TOKENS] ?: 1000,
                temperature = this[SDK_TEMPERATURE] ?: 0.7f,
                // ... map all settings
            ),
            // ... map other setting categories
        )
    }
    
    companion object {
        private val SDK_DEFAULT_MODEL = stringPreferencesKey("sdk_default_model")
        private val SDK_MAX_TOKENS = intPreferencesKey("sdk_max_tokens")
        private val SDK_TEMPERATURE = floatPreferencesKey("sdk_temperature")
        // ... define all setting keys
    }
}
```

#### Step 3: Settings UI Implementation (Day 10)
```kotlin
// presentation/settings/SettingsScreen.kt
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val settings by viewModel.settings.collectAsState()
    val uiState by viewModel.uiState.collectAsState()
    
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // SDK Settings Section
        item {
            SettingsSection(
                title = "SDK Configuration",
                icon = Icons.Default.Settings
            ) {
                ModelSelectionSetting(
                    selectedModel = settings.sdkSettings.defaultModel,
                    onModelSelected = viewModel::updateDefaultModel
                )
                
                SliderSetting(
                    title = "Temperature",
                    value = settings.sdkSettings.temperature,
                    valueRange = 0f..2f,
                    onValueChange = viewModel::updateTemperature
                )
                
                SliderSetting(
                    title = "Max Tokens",
                    value = settings.sdkSettings.maxTokens.toFloat(),
                    valueRange = 100f..4000f,
                    onValueChange = { viewModel.updateMaxTokens(it.toInt()) }
                )
            }
        }
        
        // Voice Settings Section
        item {
            SettingsSection(
                title = "Voice Configuration",
                icon = Icons.Default.Mic
            ) {
                ModelSelectionSetting(
                    title = "STT Model",
                    selectedModel = settings.voiceSettings.sttModel,
                    onModelSelected = viewModel::updateSTTModel
                )
                
                SwitchSetting(
                    title = "Enable VAD",
                    description = "Voice Activity Detection",
                    checked = settings.voiceSettings.enableVAD,
                    onCheckedChange = viewModel::updateVADEnabled
                )
                
                SliderSetting(
                    title = "Speech Rate",
                    value = settings.voiceSettings.speechRate,
                    valueRange = 0.5f..2f,
                    onValueChange = viewModel::updateSpeechRate
                )
            }
        }
        
        // Privacy Settings Section
        item {
            SettingsSection(
                title = "Privacy & Data",
                icon = Icons.Default.Security
            ) {
                SwitchSetting(
                    title = "Enable Telemetry",
                    description = "Help improve the app by sharing usage data",
                    checked = settings.privacySettings.enableTelemetry,
                    onCheckedChange = viewModel::updateTelemetryEnabled
                )
                
                SwitchSetting(
                    title = "Analytics",
                    description = "Share performance analytics",
                    checked = settings.privacySettings.enableUsageAnalytics,
                    onCheckedChange = viewModel::updateAnalyticsEnabled
                )
            }
        }
    }
}
```

**Success Criteria**:
- [ ] All settings persist correctly
- [ ] SDK configuration updates in real-time
- [ ] Voice settings affect pipeline behavior
- [ ] Privacy settings control data collection
- [ ] UI is intuitive and responsive

### Task 2.3: Storage Management Implementation
**Files to Modify**:
- `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/presentation/storage/`

**Implementation Steps** (Day 11-12):

#### Storage Analysis Implementation
```kotlin
// domain/services/StorageAnalysisService.kt
class StorageAnalysisService(
    private val context: Context
) {
    fun getStorageInfo(): StorageInfo {
        val statsManager = context.getSystemService(Context.STORAGE_STATS_SERVICE) as StorageStatsManager
        val storageManager = context.getSystemService(Context.STORAGE_SERVICE) as StorageManager
        
        val totalBytes = getTotalSpace()
        val availableBytes = getAvailableSpace()
        val usedBytes = totalBytes - availableBytes
        
        return StorageInfo(
            totalSpace = totalBytes,
            availableSpace = availableBytes,
            usedSpace = usedBytes,
            appStorage = getAppStorageUsage(),
            modelStorage = getModelStorageUsage(),
            cacheStorage = getCacheStorageUsage()
        )
    }
    
    fun getModelInventory(): List<ModelStorageInfo> {
        // Scan model directory for downloaded models
        val modelDir = File(context.filesDir, "models")
        if (!modelDir.exists()) return emptyList()
        
        return modelDir.listFiles()?.mapNotNull { file ->
            if (file.isFile && file.name.endsWith(".bin")) {
                ModelStorageInfo(
                    modelId = file.nameWithoutExtension,
                    fileName = file.name,
                    sizeBytes = file.length(),
                    lastModified = file.lastModified(),
                    path = file.absolutePath
                )
            } else null
        } ?: emptyList()
    }
    
    suspend fun cleanupCache(): Long {
        val cacheDir = context.cacheDir
        return recursiveDelete(cacheDir)
    }
    
    suspend fun deleteModel(modelId: String): Boolean {
        val modelFile = File(context.filesDir, "models/$modelId.bin")
        return modelFile.delete()
    }
}
```

**Success Criteria**:
- [ ] Accurate storage usage display
- [ ] Model inventory shows all downloaded models
- [ ] Cache cleanup frees up space
- [ ] Model deletion works correctly

---

## Phase 3: Advanced Features Implementation 🟢
**Duration**: 6-8 days  
**Priority**: MEDIUM - Advanced functionality  

### Task 3.1: Speaker Diarization Component
**Files to Create**:
- `src/commonMain/kotlin/com/runanywhere/sdk/components/diarization/`
- `modules/runanywhere-speaker-diarization/`

**Implementation Steps** (Day 13-15):

#### Speaker Diarization Service Interface
```kotlin
// components/diarization/SpeakerDiarizationService.kt
interface SpeakerDiarizationService {
    suspend fun initialize(): Boolean
    suspend fun processAudio(audioData: ByteArray): DiarizationResult
    suspend fun createSpeakerProfile(speakerId: String, audioSamples: List<ByteArray>): SpeakerProfile
    suspend fun identifySpeaker(audioData: ByteArray): SpeakerIdentification
    fun cleanup()
}

data class DiarizationResult(
    val segments: List<SpeechSegment>,
    val speakers: List<SpeakerInfo>,
    val confidence: Float
)

data class SpeechSegment(
    val startTime: Long,
    val endTime: Long,
    val speakerId: String,
    val confidence: Float,
    val text: String? = null
)

data class SpeakerInfo(
    val id: String,
    val name: String? = null,
    val confidence: Float,
    val embedding: FloatArray
)
```

### Task 3.2: Structured Output Generation
**Files to Modify**:
- `src/commonMain/kotlin/com/runanywhere/sdk/generation/StructuredGenerationService.kt`

**Implementation Steps** (Day 16-17):

#### Structured Output Implementation
```kotlin
// generation/StructuredGenerationService.kt
interface Generatable {
    fun getJsonSchema(): String
}

class StructuredGenerationService(
    private val generationService: GenerationService
) {
    suspend fun <T : Generatable> generateStructured(
        type: T,
        prompt: String,
        options: GenerationOptions? = null
    ): T {
        val schema = type.getJsonSchema()
        val structuredPrompt = buildStructuredPrompt(prompt, schema)
        
        val result = generationService.generate(structuredPrompt, options)
        
        return parseStructuredResult(result, type::class)
    }
    
    private fun buildStructuredPrompt(prompt: String, schema: String): String {
        return """
            $prompt
            
            Please respond with valid JSON that matches this schema:
            $schema
            
            Response:
        """.trimIndent()
    }
    
    private fun <T : Generatable> parseStructuredResult(result: String, clazz: KClass<T>): T {
        val jsonStart = result.indexOf("{")
        val jsonEnd = result.lastIndexOf("}") + 1
        
        if (jsonStart == -1 || jsonEnd <= jsonStart) {
            throw IllegalArgumentException("No valid JSON found in response")
        }
        
        val jsonString = result.substring(jsonStart, jsonEnd)
        return Json.decodeFromString(clazz.serializer(), jsonString)
    }
}
```

---

## Phase 4: Polish & Production Readiness 🔵
**Duration**: 4-5 days  
**Priority**: LOW - Quality improvements  

### Task 4.1: Performance Optimization
- Memory usage optimization
- Battery usage improvements
- Rendering performance
- Model loading speed

### Task 4.2: Testing & Validation
- Unit test coverage
- Integration testing
- Performance benchmarking
- Cross-platform validation

### Task 4.3: Documentation & Examples
- API documentation updates
- Usage examples
- Migration guides
- Best practices

---

## Android Development Setup Guide

### Prerequisites
1. **Android Studio**: Latest stable version (Hedgehog or newer)
2. **JDK**: Version 17 or higher
3. **Android SDK**: API level 24+ (Android 7.0)
4. **Kotlin**: 2.1.21 (managed by Gradle)

### Environment Setup

#### Step 1: Clone and Build
```bash
# Clone repository
git clone <repository-url>
cd sdks

# Build Kotlin SDK
cd sdk/runanywhere-kotlin
./scripts/sdk.sh build

# Publish to local Maven
./scripts/sdk.sh publish-local
```

#### Step 2: Android Emulator Setup
```bash
# Create AVD with recommended specs
avdmanager create avd \
  --name "RunAnywhere_Test" \
  --package "system-images;android-34;google_apis;x86_64" \
  --device "pixel_7_pro"

# Start emulator
emulator -avd RunAnywhere_Test -no-snapshot-save
```

#### Step 3: Open Android Project
```bash
# Open Android Studio
cd examples/android/RunAnywhereAI
# Open this directory in Android Studio
```

#### Step 4: Configuration
1. Create `local.properties` with SDK path
2. Ensure Gradle sync completes successfully
3. Run on emulator or device

### Testing Environment
- **Emulator**: Pixel 7 Pro (API 34) for testing
- **Physical Device**: Any Android 7.0+ device
- **Audio Testing**: Use physical device for voice features

### Validation Checklist
- [ ] App launches successfully
- [ ] Chat feature works with real responses
- [ ] Quiz generation functions properly
- [ ] Voice pipeline captures audio
- [ ] Model management displays correctly
- [ ] Settings persist between app restarts

---

## Success Metrics & Validation

### SDK Validation ✅
- [ ] All iOS APIs have working Kotlin equivalents
- [ ] Generation returns real LLM responses (not mocks)
- [ ] Memory management handles pressure correctly
- [ ] Model downloads work with progress tracking
- [ ] Native platforms support production use
- [ ] Event system publishes all component events

### App Validation ✅
- [ ] All 5 tabs functional on both platforms
- [ ] Voice assistant works reliably
- [ ] Settings affect SDK behavior
- [ ] Storage management provides useful info
- [ ] Model downloads work from UI
- [ ] User experience feels native

### Performance Validation ✅
- [ ] App startup time < 3 seconds
- [ ] Voice pipeline latency < 1 second
- [ ] Memory usage stable during long sessions
- [ ] Battery usage reasonable
- [ ] Model loading time acceptable

This implementation plan provides the detailed roadmap to achieve complete iOS-Android parity. Each task includes specific file modifications, code examples, and success criteria to ensure systematic progress toward the goal.