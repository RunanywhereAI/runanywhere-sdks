# Kotlin SDK - STT Pipeline MVP Implementation Plan

## Executive Summary

This document outlines the MVP implementation plan for the RunAnywhere Kotlin SDK, focusing **exclusively** on the Speech-to-Text (STT) pipeline with Voice Activity Detection (VAD). The first release targets **Android Studio IDE plugin** for voice-driven code completion and commands, with architecture designed for future expansion to Android apps.

## 1. MVP Scope Definition

### In Scope ✅
- **VAD Component**: WebRTC VAD for efficient voice activity detection
- **STT Component**: Whisper.cpp integration via JNI
- **Model Management**: Download, storage, lifecycle management for STT models
- **File Management**: Efficient file storage and caching system
- **Analytics**: Usage tracking, performance metrics, error reporting
- **Event System**: Real-time events for VAD and STT status
- **Android Studio Plugin**: Voice command interface for IDE

### Out of Scope (Deferred) ❌
- LLM Component
- TTS Component
- VLM Component
- Speaker Diarization
- Wake Word Detection
- Full Android app support (architecture prepared but not implemented)
- iOS/Desktop platforms

## 2. Target Use Case: Android Studio Voice Commands

### Primary Features
1. **Voice-to-Code**: Dictate code directly into the editor
2. **Voice Commands**: Execute IDE actions via voice ("run tests", "debug app", "find usages")
3. **Voice Search**: Search in project using natural language
4. **Voice Refactoring**: Trigger refactoring commands
5. **Continuous Dictation**: Real-time transcription with VAD

### User Experience Flow
```
1. User activates voice mode (hotkey/button)
2. VAD detects speech start
3. Audio captured and buffered
4. VAD detects speech end
5. STT processes audio chunk
6. Transcription returned to IDE
7. IDE processes command/inserts text
```

## 3. Simplified Architecture

### 3.1 Project Structure (MVP)

```
sdk/runanywhere-kotlin-stt/
├── core/                           # Core SDK module (JVM)
│   ├── src/main/kotlin/
│   │   ├── components/
│   │   │   ├── base/              # Component abstractions
│   │   │   ├── vad/               # VAD component
│   │   │   └── stt/               # STT component
│   │   ├── models/                # Model management
│   │   │   ├── ModelManager.kt
│   │   │   ├── ModelDownloader.kt
│   │   │   └── ModelStorage.kt
│   │   ├── files/                 # File management
│   │   │   ├── FileManager.kt
│   │   │   └── CacheManager.kt
│   │   ├── analytics/             # Analytics
│   │   │   ├── AnalyticsTracker.kt
│   │   │   └── PerformanceMonitor.kt
│   │   ├── events/                # Event system
│   │   │   ├── EventBus.kt
│   │   │   └── STTEvents.kt
│   │   └── public/                # Public API
│   │       └── RunAnywhereSTT.kt
│   └── resources/
│       └── native/                # Native libraries
│           ├── win/
│           ├── mac/
│           └── linux/
├── jni/                           # JNI module
│   ├── src/main/
│   │   ├── cpp/
│   │   │   ├── whisper-jni.cpp
│   │   │   └── webrtc-vad-jni.cpp
│   │   └── kotlin/
│   │       ├── WhisperJNI.kt
│   │       └── WebRTCVadJNI.kt
│   └── CMakeLists.txt
├── plugin/                        # IntelliJ Plugin module
│   ├── src/main/
│   │   ├── kotlin/
│   │   │   ├── RunAnywherePlugin.kt
│   │   │   ├── actions/          # IDE actions
│   │   │   │   ├── VoiceCommandAction.kt
│   │   │   │   └── VoiceDictationAction.kt
│   │   │   ├── services/         # Plugin services
│   │   │   │   ├── VoiceService.kt
│   │   │   │   └── TranscriptionService.kt
│   │   │   ├── ui/               # UI components
│   │   │   │   ├── VoiceToolWindow.kt
│   │   │   │   └── VoiceStatusBar.kt
│   │   │   └── settings/         # Plugin settings
│   │   │       └── VoiceSettings.kt
│   │   └── resources/
│   │       ├── META-INF/
│   │       │   └── plugin.xml
│   │       └── icons/
│   └── build.gradle.kts
└── build.gradle.kts
```

### 3.2 Core Components

#### VAD Component
```kotlin
interface VADComponent {
    suspend fun initialize(config: VADConfig)
    fun processAudioChunk(audio: FloatArray): VADResult
    suspend fun cleanup()
}

class WebRTCVADComponent : VADComponent {
    private val jni = WebRTCVadJNI()

    override suspend fun initialize(config: VADConfig) {
        jni.initialize(config.aggressiveness, config.sampleRate)
    }

    override fun processAudioChunk(audio: FloatArray): VADResult {
        val isSpeech = jni.isSpeech(audio)
        return VADResult(
            isSpeech = isSpeech,
            confidence = if (isSpeech) 0.9f else 0.1f,
            timestamp = System.currentTimeMillis()
        )
    }
}

data class VADConfig(
    val aggressiveness: Int = 2, // 0-3, higher = more aggressive
    val sampleRate: Int = 16000,
    val frameDuration: Int = 30, // ms
    val silenceThreshold: Int = 500 // ms of silence to stop
)
```

#### STT Component
```kotlin
interface STTComponent {
    suspend fun initialize(modelPath: String)
    suspend fun transcribe(audioData: ByteArray): TranscriptionResult
    fun transcribeStream(audioFlow: Flow<ByteArray>): Flow<TranscriptionUpdate>
    suspend fun cleanup()
}

class WhisperSTTComponent : STTComponent {
    private val jni = WhisperJNI()
    private var modelPtr: Long = 0

    override suspend fun initialize(modelPath: String) {
        modelPtr = withContext(Dispatchers.IO) {
            jni.loadModel(modelPath)
        }
    }

    override suspend fun transcribe(audioData: ByteArray): TranscriptionResult {
        return withContext(Dispatchers.IO) {
            val text = jni.transcribe(modelPtr, audioData, "en")
            TranscriptionResult(
                text = text,
                confidence = 0.95f,
                language = "en",
                duration = audioData.size / 32000.0 // 16kHz stereo
            )
        }
    }

    override fun transcribeStream(audioFlow: Flow<ByteArray>): Flow<TranscriptionUpdate> = flow {
        audioFlow.collect { chunk ->
            val partial = jni.transcribePartial(modelPtr, chunk)
            emit(TranscriptionUpdate(
                text = partial,
                isFinal = false,
                timestamp = System.currentTimeMillis()
            ))
        }
    }
}
```

### 3.3 Model Management

```kotlin
class ModelManager {
    private val storage = ModelStorage()
    private val downloader = ModelDownloader()
    private val loadedModels = mutableMapOf<String, ModelInfo>()

    suspend fun ensureModel(modelId: String): String {
        // Check if model exists locally
        storage.getModelPath(modelId)?.let { return it }

        // Download if needed
        return downloader.downloadModel(modelId) { progress ->
            EventBus.emit(ModelEvent.DownloadProgress(modelId, progress))
        }
    }

    suspend fun loadModel(modelId: String): ModelHandle {
        val path = ensureModel(modelId)
        return ModelHandle(modelId, path)
    }

    fun getAvailableModels(): List<ModelInfo> {
        return listOf(
            ModelInfo("whisper-tiny", "39MB", "Fastest, lower accuracy"),
            ModelInfo("whisper-base", "74MB", "Good balance"),
            ModelInfo("whisper-small", "244MB", "Better accuracy"),
            ModelInfo("whisper-medium", "769MB", "High accuracy")
        )
    }
}

class ModelDownloader {
    suspend fun downloadModel(
        modelId: String,
        onProgress: (Float) -> Unit
    ): String = withContext(Dispatchers.IO) {
        val url = getModelUrl(modelId)
        val destination = ModelStorage.getModelDestination(modelId)

        // Download with progress tracking
        downloadFile(url, destination, onProgress)

        return@withContext destination.absolutePath
    }

    private fun getModelUrl(modelId: String): String {
        return when (modelId) {
            "whisper-tiny" -> "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
            "whisper-base" -> "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
            "whisper-small" -> "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
            else -> throw IllegalArgumentException("Unknown model: $modelId")
        }
    }
}
```

### 3.4 Public API

```kotlin
object RunAnywhereSTT {
    private lateinit var vadComponent: VADComponent
    private lateinit var sttComponent: STTComponent
    private val modelManager = ModelManager()
    private val analytics = AnalyticsTracker()

    // Initialization
    suspend fun initialize(config: STTConfig = STTConfig()) {
        // Initialize VAD
        vadComponent = WebRTCVADComponent()
        vadComponent.initialize(config.vadConfig)

        // Initialize STT
        sttComponent = WhisperSTTComponent()
        val modelPath = modelManager.ensureModel(config.modelId)
        sttComponent.initialize(modelPath)

        // Track initialization
        analytics.track("stt_initialized", mapOf(
            "model" to config.modelId,
            "vad_enabled" to config.enableVAD
        ))

        EventBus.emit(STTEvent.Initialized)
    }

    // Simple transcription
    suspend fun transcribe(audioData: ByteArray): String {
        val startTime = System.currentTimeMillis()

        val result = sttComponent.transcribe(audioData)

        analytics.track("transcription_completed", mapOf(
            "duration_ms" to (System.currentTimeMillis() - startTime),
            "audio_length_s" to (audioData.size / 32000.0),
            "text_length" to result.text.length
        ))

        return result.text
    }

    // Streaming transcription with VAD
    fun transcribeStream(audioStream: Flow<ByteArray>): Flow<TranscriptionEvent> = flow {
        var isInSpeech = false
        val audioBuffer = mutableListOf<ByteArray>()

        audioStream.collect { chunk ->
            // Convert to float array for VAD
            val floatAudio = chunk.toFloatArray()
            val vadResult = vadComponent.processAudioChunk(floatAudio)

            when {
                vadResult.isSpeech && !isInSpeech -> {
                    isInSpeech = true
                    audioBuffer.clear()
                    audioBuffer.add(chunk)
                    emit(TranscriptionEvent.SpeechStart)
                }
                vadResult.isSpeech && isInSpeech -> {
                    audioBuffer.add(chunk)
                    // Emit partial transcription
                    val partial = sttComponent.transcribe(audioBuffer.merge())
                    emit(TranscriptionEvent.PartialTranscription(partial.text))
                }
                !vadResult.isSpeech && isInSpeech -> {
                    isInSpeech = false
                    if (audioBuffer.isNotEmpty()) {
                        val finalAudio = audioBuffer.merge()
                        val result = sttComponent.transcribe(finalAudio)
                        emit(TranscriptionEvent.FinalTranscription(result.text))
                        emit(TranscriptionEvent.SpeechEnd)
                    }
                }
            }
        }
    }

    // Configuration
    data class STTConfig(
        val modelId: String = "whisper-base",
        val enableVAD: Boolean = true,
        val vadConfig: VADConfig = VADConfig(),
        val language: String = "en",
        val enableAnalytics: Boolean = true
    )
}

// Event types
sealed class TranscriptionEvent {
    object SpeechStart : TranscriptionEvent()
    object SpeechEnd : TranscriptionEvent()
    data class PartialTranscription(val text: String) : TranscriptionEvent()
    data class FinalTranscription(val text: String) : TranscriptionEvent()
    data class Error(val error: Throwable) : TranscriptionEvent()
}
```

## 4. Android Studio Plugin Implementation

### 4.1 Plugin Architecture

```kotlin
class RunAnywherePlugin : Plugin<Project> {
    override fun apply(project: Project) {
        // Register plugin services
        project.service<VoiceService>()
        project.service<TranscriptionService>()

        // Register actions
        val actionManager = ActionManager.getInstance()
        actionManager.registerAction("RunAnywhere.VoiceCommand", VoiceCommandAction())
        actionManager.registerAction("RunAnywhere.VoiceDictation", VoiceDictationAction())
    }
}
```

### 4.2 Voice Service

```kotlin
@Service
class VoiceService : Disposable {
    private val audioCapture = AudioCapture()
    private var isRecording = false

    init {
        // Initialize STT on service start
        runBlocking {
            RunAnywhereSTT.initialize(STTConfig(
                modelId = getModelPreference(),
                enableVAD = true
            ))
        }
    }

    fun startVoiceCapture(): Flow<TranscriptionEvent> {
        isRecording = true
        val audioStream = audioCapture.startCapture()
        return RunAnywhereSTT.transcribeStream(audioStream)
    }

    fun stopVoiceCapture() {
        isRecording = false
        audioCapture.stopCapture()
    }

    suspend fun transcribeAudioFile(file: File): String {
        val audioData = file.readBytes()
        return RunAnywhereSTT.transcribe(audioData)
    }

    override fun dispose() {
        if (isRecording) {
            stopVoiceCapture()
        }
    }
}
```

### 4.3 Voice Command Action

```kotlin
class VoiceCommandAction : AnAction("Voice Command", "Execute IDE command using voice", AllIcons.Actions.Execute) {

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return
        val voiceService = project.service<VoiceService>()

        // Show voice input dialog
        val dialog = VoiceInputDialog(project)
        dialog.show()

        // Start voice capture
        ApplicationManager.getApplication().executeOnPooledThread {
            runBlocking {
                voiceService.startVoiceCapture().collect { event ->
                    when (event) {
                        is TranscriptionEvent.SpeechStart -> {
                            dialog.updateStatus("Listening...")
                        }
                        is TranscriptionEvent.PartialTranscription -> {
                            dialog.updateTranscription(event.text)
                        }
                        is TranscriptionEvent.FinalTranscription -> {
                            dialog.updateTranscription(event.text)
                            processCommand(project, event.text)
                            dialog.close()
                        }
                        is TranscriptionEvent.Error -> {
                            dialog.showError(event.error.message)
                        }
                    }
                }
            }
        }
    }

    private fun processCommand(project: Project, command: String) {
        val commandProcessor = CommandProcessor(project)

        when {
            command.contains("run test", ignoreCase = true) -> {
                commandProcessor.runTests()
            }
            command.contains("debug", ignoreCase = true) -> {
                commandProcessor.startDebug()
            }
            command.contains("find usages", ignoreCase = true) -> {
                commandProcessor.findUsages()
            }
            command.contains("refactor", ignoreCase = true) -> {
                commandProcessor.showRefactorMenu()
            }
            else -> {
                // Insert as text if no command matched
                insertTextAtCaret(project, command)
            }
        }
    }
}
```

### 4.4 Voice Dictation Mode

```kotlin
class VoiceDictationAction : ToggleAction("Voice Dictation", "Toggle voice dictation mode", AllIcons.Actions.StartDebugger) {
    private var isDictating = false
    private var dictationJob: Job? = null

    override fun isSelected(e: AnActionEvent): Boolean = isDictating

    override fun setSelected(e: AnActionEvent, state: Boolean) {
        val project = e.project ?: return
        val editor = e.getData(CommonDataKeys.EDITOR) ?: return

        isDictating = state

        if (state) {
            startDictation(project, editor)
        } else {
            stopDictation()
        }
    }

    private fun startDictation(project: Project, editor: Editor) {
        val voiceService = project.service<VoiceService>()

        dictationJob = GlobalScope.launch {
            voiceService.startVoiceCapture().collect { event ->
                when (event) {
                    is TranscriptionEvent.FinalTranscription -> {
                        ApplicationManager.getApplication().invokeLater {
                            WriteCommandAction.runWriteCommandAction(project) {
                                val document = editor.document
                                val caretOffset = editor.caretModel.offset
                                document.insertString(caretOffset, event.text + " ")
                                editor.caretModel.moveToOffset(caretOffset + event.text.length + 1)
                            }
                        }
                    }
                    is TranscriptionEvent.PartialTranscription -> {
                        // Show partial text in status bar
                        StatusBar.Info.set(event.text, project)
                    }
                }
            }
        }
    }

    private fun stopDictation() {
        dictationJob?.cancel()
        dictationJob = null
    }
}
```

## 5. Analytics Implementation

```kotlin
class AnalyticsTracker {
    private val events = mutableListOf<AnalyticsEvent>()
    private val sessionId = UUID.randomUUID().toString()

    fun track(eventName: String, properties: Map<String, Any> = emptyMap()) {
        val event = AnalyticsEvent(
            name = eventName,
            properties = properties + mapOf(
                "session_id" to sessionId,
                "timestamp" to System.currentTimeMillis(),
                "platform" to "intellij",
                "sdk_version" to SDK_VERSION
            )
        )

        events.add(event)

        // Send to backend if online
        if (shouldSendEvents()) {
            sendEvents()
        }
    }

    fun trackPerformance(operation: String, duration: Long) {
        track("performance_metric", mapOf(
            "operation" to operation,
            "duration_ms" to duration
        ))
    }

    fun trackError(error: Throwable) {
        track("error_occurred", mapOf(
            "error_type" to error::class.simpleName,
            "error_message" to error.message,
            "stack_trace" to error.stackTraceToString().take(500)
        ))
    }

    private fun sendEvents() {
        // Send to analytics backend
        // This can be batched and sent periodically
    }
}
```

## 6. File Management

```kotlin
class FileManager {
    private val baseDir = File(System.getProperty("user.home"), ".runanywhere")
    private val modelsDir = File(baseDir, "models")
    private val cacheDir = File(baseDir, "cache")
    private val tempDir = File(baseDir, "temp")

    init {
        modelsDir.mkdirs()
        cacheDir.mkdirs()
        tempDir.mkdirs()
    }

    fun getModelPath(modelId: String): File {
        return File(modelsDir, "$modelId.bin")
    }

    fun getCachePath(key: String): File {
        return File(cacheDir, key.hashCode().toString())
    }

    fun createTempFile(prefix: String, suffix: String): File {
        return File.createTempFile(prefix, suffix, tempDir)
    }

    fun cleanupOldFiles(maxAge: Long = 7 * 24 * 60 * 60 * 1000) {
        val cutoff = System.currentTimeMillis() - maxAge

        tempDir.walkTopDown().forEach { file ->
            if (file.isFile && file.lastModified() < cutoff) {
                file.delete()
            }
        }
    }

    fun getStorageInfo(): StorageInfo {
        return StorageInfo(
            totalSpace = baseDir.totalSpace,
            usedSpace = baseDir.walkTopDown().sumOf { it.length() },
            modelCount = modelsDir.listFiles()?.size ?: 0,
            cacheSize = cacheDir.walkTopDown().sumOf { it.length() }
        )
    }
}

data class StorageInfo(
    val totalSpace: Long,
    val usedSpace: Long,
    val modelCount: Int,
    val cacheSize: Long
)
```

## 7. JNI Integration

### 7.1 Whisper JNI

```kotlin
class WhisperJNI {
    companion object {
        init {
            // Load native library from resources
            NativeLoader.loadLibrary("whisper-jni")
        }
    }

    external fun loadModel(modelPath: String): Long
    external fun transcribe(modelPtr: Long, audioData: ByteArray, language: String): String
    external fun transcribePartial(modelPtr: Long, audioData: ByteArray): String
    external fun unloadModel(modelPtr: Long)
    external fun getModelInfo(modelPtr: Long): String
}
```

### 7.2 WebRTC VAD JNI

```kotlin
class WebRTCVadJNI {
    companion object {
        init {
            NativeLoader.loadLibrary("webrtc-vad-jni")
        }
    }

    external fun initialize(aggressiveness: Int, sampleRate: Int): Long
    external fun isSpeech(vadPtr: Long, audio: FloatArray): Boolean
    external fun reset(vadPtr: Long)
    external fun destroy(vadPtr: Long)
}
```

### 7.3 Native Library Loader

```kotlin
object NativeLoader {
    private val loadedLibraries = mutableSetOf<String>()

    fun loadLibrary(libName: String) {
        if (libName in loadedLibraries) return

        val os = System.getProperty("os.name").lowercase()
        val arch = System.getProperty("os.arch").lowercase()

        val libFileName = when {
            os.contains("win") -> "$libName.dll"
            os.contains("mac") -> "lib$libName.dylib"
            else -> "lib$libName.so"
        }

        val resourcePath = "/native/$os-$arch/$libFileName"
        val resource = NativeLoader::class.java.getResourceAsStream(resourcePath)
            ?: throw UnsatisfiedLinkError("Native library not found: $resourcePath")

        val tempFile = File.createTempFile(libName, libFileName)
        tempFile.deleteOnExit()

        resource.use { input ->
            tempFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }

        System.load(tempFile.absolutePath)
        loadedLibraries.add(libName)
    }
}
```

## 8. Implementation Timeline (6 weeks)

### Week 1: Core Foundation
- [x] Project structure setup
- [x] Core abstractions (Component interfaces)
- [x] Event system implementation
- [x] Basic file management

### Week 2: JNI Integration
- [ ] Whisper.cpp JNI wrapper
- [ ] WebRTC VAD JNI wrapper
- [ ] Native library loading system
- [ ] Cross-platform library packaging

### Week 3: STT Components
- [ ] VAD component implementation
- [ ] STT component implementation
- [ ] Model management system
- [ ] Model downloading with progress

### Week 4: IntelliJ Plugin Base
- [ ] Plugin project setup
- [ ] Basic plugin services
- [ ] Audio capture integration
- [ ] Settings and configuration UI

### Week 5: Plugin Features
- [ ] Voice command action
- [ ] Voice dictation mode
- [ ] Command processing
- [ ] UI components (status bar, tool window)

### Week 6: Polish & Testing
- [ ] Analytics integration
- [ ] Error handling and recovery
- [ ] Performance optimization
- [ ] Documentation and examples
- [ ] Publishing to JetBrains Marketplace

## 9. Testing Strategy

### Unit Tests
```kotlin
class VADComponentTest {
    @Test
    fun `test speech detection`() = runTest {
        val vad = WebRTCVADComponent()
        vad.initialize(VADConfig())

        val speechAudio = loadTestAudio("speech.wav")
        val result = vad.processAudioChunk(speechAudio)

        assertTrue(result.isSpeech)
        assertTrue(result.confidence > 0.8f)
    }
}

class STTComponentTest {
    @Test
    fun `test transcription accuracy`() = runTest {
        val stt = WhisperSTTComponent()
        stt.initialize("whisper-base")

        val audio = loadTestAudio("hello_world.wav")
        val result = stt.transcribe(audio)

        assertEquals("hello world", result.text.lowercase())
    }
}
```

### Integration Tests
```kotlin
class VoicePipelineTest {
    @Test
    fun `test end-to-end voice pipeline`() = runTest {
        RunAnywhereSTT.initialize()

        val audioStream = flowOf(
            loadTestAudio("speech_with_silence_1.wav"),
            loadTestAudio("speech_with_silence_2.wav")
        )

        val events = RunAnywhereSTT.transcribeStream(audioStream).toList()

        assertTrue(events.any { it is TranscriptionEvent.SpeechStart })
        assertTrue(events.any { it is TranscriptionEvent.FinalTranscription })
    }
}
```

## 10. Performance Requirements

### Latency Targets
- VAD decision: < 10ms per frame
- STT first token: < 500ms
- Full transcription: < 2s for 10s audio
- Model loading: < 5s for base model

### Resource Usage
- Memory: < 500MB for base model
- CPU: < 30% during active transcription
- Disk: < 1GB for all models and cache

## 11. Distribution & Deployment

### JetBrains Marketplace
```xml
<!-- plugin.xml -->
<idea-plugin>
    <id>com.runanywhere.stt</id>
    <name>RunAnywhere Voice Commands</name>
    <vendor>RunAnywhere</vendor>
    <version>1.0.0</version>

    <description><![CDATA[
        Voice commands and dictation for IntelliJ IDEA.
        Powered by on-device Whisper AI models.
    ]]></description>

    <depends>com.intellij.modules.platform</depends>

    <extensions defaultExtensionNs="com.intellij">
        <applicationService serviceImplementation="com.runanywhere.plugin.VoiceService"/>
        <projectService serviceImplementation="com.runanywhere.plugin.TranscriptionService"/>
    </extensions>

    <actions>
        <action id="RunAnywhere.VoiceCommand"
                class="com.runanywhere.plugin.VoiceCommandAction"
                text="Voice Command"
                icon="AllIcons.Actions.Execute">
            <keyboard-shortcut first-keystroke="ctrl shift V" keymap="$default"/>
        </action>
    </actions>
</idea-plugin>
```

### Gradle Build Configuration
```kotlin
// plugin/build.gradle.kts
plugins {
    id("org.jetbrains.intellij") version "1.17.0"
    kotlin("jvm") version "1.9.22"
}

intellij {
    version = "2023.3"
    type = "IC"
    plugins = listOf("java")
}

dependencies {
    implementation(project(":core"))
    implementation(project(":jni"))
}

tasks {
    patchPluginXml {
        sinceBuild = "233"
        untilBuild = "241.*"
    }

    buildPlugin {
        archiveFileName = "runanywhere-voice-${version}.zip"
    }

    publishPlugin {
        token = System.getenv("JETBRAINS_TOKEN")
    }
}
```

## 12. Future Expansion Path

### Phase 2: Android App Support (Deferred)
- Android-specific audio capture
- Background service for continuous listening
- Android UI components
- Play Store distribution

### Phase 3: Additional Components (Deferred)
- LLM integration for command understanding
- TTS for voice feedback
- Wake word detection
- Speaker diarization

### Phase 4: Platform Expansion (Deferred)
- VS Code extension
- Eclipse plugin
- Desktop standalone app
- Web assembly support

## 13. Success Metrics

### Launch Metrics (First Month)
- 1,000+ plugin downloads
- 100+ daily active users
- < 1% crash rate
- 4+ star rating

### Performance Metrics
- 95%+ transcription accuracy
- < 500ms average latency
- < 5% CPU usage idle
- 99%+ uptime

### User Engagement
- 10+ voice commands per session
- 50%+ weekly retention
- 20%+ feature adoption (dictation mode)

## Conclusion

This MVP focuses on delivering a robust, performant STT pipeline for Android Studio, providing immediate value to developers through voice commands and dictation. The architecture is designed for easy expansion to support additional platforms and components in future phases, while keeping the initial scope manageable and achievable within 6 weeks.
