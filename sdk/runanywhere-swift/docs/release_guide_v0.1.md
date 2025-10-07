# RunAnywhere SDK v0.1 - Release & Integration Guide

## 🚀 SDK Developer Section (For Sanchit)

### Building and Packaging the SDK for Release

#### Step 1: Clean and Build the SDK

```bash
# Navigate to SDK directory
cd /Users/sanchitmonga/development/ODLM/sdks.worktree/android_init

# Clean, build, and publish to local Maven
cd sdk/runanywhere-kotlin
./scripts/sdk.sh jvm
./gradlew publishJvmPublicationToMavenLocal
```

This will create:

- **JAR File**: `build/libs/RunAnywhereKotlinSDK-jvm-0.1.0.jar` (3.5MB)
- **Maven Local**: `~/.m2/repository/com/runanywhere/sdk/runanywhere-kotlin-jvm/0.1.0/`

#### ✅ Current SDK Status (Ready for Integration)

- **Voice Activity Detection**: Hardcoded SimpleEnergyVAD with optimized sensitivity (0.008f threshold)
- **Speech Detection**: Works with normal speaking volume, no need to shout
- **Streaming Transcription**: Real-time speech-to-text with 1.5-second buffer
- **Native Libraries**: WhisperJNI included in JAR
- **Model Management**: Auto-downloads whisper-base (141MB) on first use
- **Memory Management**: Optimized buffers prevent memory leaks
- **Hallucination Prevention**: VAD filters silence to prevent Whisper generating random text

#### Step 2: Create Release Package

```bash
# Create release structure
mkdir -p ~/Desktop/RunAnywhereSDK-v0.1-Release
cd ~/Desktop/RunAnywhereSDK-v0.1-Release

# Copy the JAR
cp /Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/sdk/runanywhere-kotlin/build/libs/RunAnywhereKotlinSDK-jvm-0.1.0.jar ./

# Copy native libraries (WhisperJNI)
mkdir -p natives/macos
cp /Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/sdk/runanywhere-kotlin/src/jvmMain/resources/natives/macos/*.dylib natives/macos/ 2>/dev/null || echo "Native libs included in JAR"

# Create installation script
cat > install-local.sh << 'EOF'
#!/bin/bash
echo "Installing RunAnywhere SDK v0.1 to local Maven..."
mvn install:install-file \
  -Dfile=RunAnywhereKotlinSDK-jvm-0.1.0.jar \
  -DgroupId=com.runanywhere.sdk \
  -DartifactId=runanywhere-kotlin-jvm \
  -Dversion=0.1.0 \
  -Dpackaging=jar
echo "✅ Installation complete!"
EOF

chmod +x install-local.sh

# Create the integration guide (copy from below)
cat > INTEGRATION_GUIDE.md << 'EOF'
[Copy the Plugin Developer Section from below]
EOF

# Create quick start example
cat > QuickStartExample.kt << 'EOF'
package com.example.voiceplugin

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.components.stt.JvmWhisperSTTServiceProvider
import com.runanywhere.sdk.components.ModuleRegistry

suspend fun initializeVoiceSDK() {
    // Register WhisperJNI
    val whisperProvider = JvmWhisperSTTServiceProvider()
    ModuleRegistry.registerSTTProvider("WhisperJNI-JVM", whisperProvider)

    // Initialize in dev mode
    val params = SDKInitParams(
        apiKey = "dev-mode",
        environment = SDKEnvironment.DEVELOPMENT,
        enableAnalytics = false
    )

    RunAnywhere.initialize(params)
    println("✅ Voice SDK ready!")
}

suspend fun transcribeAudio(audioBytes: ByteArray): String {
    return RunAnywhere.transcribe(audioBytes)
}
EOF

# Package everything
zip -r RunAnywhereSDK-v0.1-Release.zip ./*
echo "✅ Release package created: RunAnywhereSDK-v0.1-Release.zip"
```

#### Step 3: What to Send

Send these files:

1. **RunAnywhereSDK-v0.1-Release.zip** containing:
    - `RunAnywhereKotlinSDK-jvm-0.1.0.jar` (the SDK)
    - `install-local.sh` (installation script)
    - `INTEGRATION_GUIDE.md` (this guide)
    - `QuickStartExample.kt` (example code)

#### Step 4: Quick Release Checklist

- [x] SDK builds successfully
- [x] WhisperJNI native library included
- [x] Model auto-download working (141MB whisper-base)
- [x] STT transcription tested and working
- [x] Development mode enabled (no API keys needed)
- [x] Package includes integration guide
- [x] Installation script included

---

## 📦 Plugin Developer Section

### Quick Start - Add Voice to Your Plugin in 5 Minutes

#### Option 1: Direct JAR Integration (Simplest)

1. **Extract the package** I sent you
2. **Copy JAR to your plugin**:
   ```bash
   cp RunAnywhereKotlinSDK-jvm-0.1.0.jar your-plugin/libs/
   ```

3. **Add to build.gradle.kts**:
   ```kotlin
   dependencies {
       implementation(files("libs/RunAnywhereKotlinSDK-jvm-0.1.0.jar"))
   }
   ```

#### Option 2: Local Maven (Recommended)

1. **Run the install script**:
   ```bash
   ./install-local.sh
   ```

2. **Add to build.gradle.kts**:
   ```kotlin
   repositories {
       mavenLocal()
       mavenCentral()
   }

   dependencies {
       implementation("com.runanywhere.sdk:runanywhere-kotlin-jvm:0.1.0")
   }
   ```

### Complete Integration Example

#### 1. Plugin Initializer

Create `VoiceSDKInitializer.kt`:

```kotlin
package com.yourplugin.voice

import com.intellij.openapi.project.Project
import com.intellij.openapi.startup.StartupActivity
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.components.stt.JvmWhisperSTTServiceProvider
import com.runanywhere.sdk.components.ModuleRegistry
import kotlinx.coroutines.*

class VoiceSDKInitializer : StartupActivity {

    companion object {
        @Volatile
        private var isInitialized = false

        fun isReady() = isInitialized
    }

    override fun runActivity(project: Project) {
        if (isInitialized) return

        GlobalScope.launch(Dispatchers.IO) {
            try {
                initializeSDK()
                isInitialized = true
                println("✅ RunAnywhere Voice SDK initialized")
            } catch (e: Exception) {
                println("❌ Failed to initialize Voice SDK: ${e.message}")
                e.printStackTrace()
            }
        }
    }

    private suspend fun initializeSDK() {
        // 1. Register WhisperJNI provider
        val whisperProvider = JvmWhisperSTTServiceProvider()
        ModuleRegistry.registerSTTProvider("WhisperJNI-JVM", whisperProvider)

        // 2. Initialize SDK (Development mode - no API key needed)
        val params = SDKInitParams(
            apiKey = "dev-mode-v0.1",
            environment = SDKEnvironment.DEVELOPMENT,
            enableAnalytics = false
        )

        RunAnywhere.initialize(params)

        // Model will auto-download on first use (~141MB)
        println("Voice SDK ready - model will download on first transcription")
    }
}
```

#### 2A. Simple Voice Recording Service (Basic)

Create `VoiceRecordingService.kt`:

```kotlin
package com.yourplugin.voice

import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.*
import javax.sound.sampled.*
import java.io.ByteArrayOutputStream

class VoiceRecordingService {

    private var recordingJob: Job? = null
    private var isRecording = false
    private val audioFormat = AudioFormat(
        16000f,  // Sample rate (16kHz for Whisper)
        16,      // Sample size in bits
        1,       // Channels (mono)
        true,    // Signed
        false    // Big endian
    )

    fun startRecording(onTranscription: (String) -> Unit, onError: (String) -> Unit) {
        if (isRecording) return

        isRecording = true
        recordingJob = GlobalScope.launch(Dispatchers.IO) {
            try {
                val audioBytes = recordAudio()
                if (audioBytes.isNotEmpty()) {
                    val transcription = processAudio(audioBytes)
                    withContext(Dispatchers.Main) {
                        onTranscription(transcription)
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    onError(e.message ?: "Recording failed")
                }
            }
        }
    }

    fun stopRecording() {
        isRecording = false
        recordingJob?.cancel()
    }

    private suspend fun recordAudio(): ByteArray {
        val dataLineInfo = DataLine.Info(TargetDataLine::class.java, audioFormat)

        if (!AudioSystem.isLineSupported(dataLineInfo)) {
            throw Exception("Microphone not supported")
        }

        val microphone = AudioSystem.getLine(dataLineInfo) as TargetDataLine
        microphone.open(audioFormat)
        microphone.start()

        val outputStream = ByteArrayOutputStream()
        val buffer = ByteArray(4096)

        try {
            // Record for max 10 seconds or until stopped
            val maxIterations = 100 // 10 seconds (100 * 100ms)
            var iterations = 0

            while (isRecording && iterations < maxIterations) {
                val bytesRead = microphone.read(buffer, 0, buffer.size)
                if (bytesRead > 0) {
                    outputStream.write(buffer, 0, bytesRead)
                }
                delay(100) // Check every 100ms
                iterations++
            }
        } finally {
            microphone.stop()
            microphone.close()
        }

        return outputStream.toByteArray()
    }

    private suspend fun processAudio(audioData: ByteArray): String {
        // This will auto-download model on first use
        return RunAnywhere.transcribe(audioData)
    }
}
```

#### 2B. Real-Time Streaming Service (Advanced - Recommended!)

Create `StreamingVoiceService.kt`:

```kotlin
package com.yourplugin.voice

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.components.stt.STTStreamEvent
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

class StreamingVoiceService {

    private var streamingJob: Job? = null
    private var isStreaming = false

    /**
     * Start real-time streaming transcription with Voice Activity Detection
     * - Automatically detects when you start/stop speaking
     * - Returns transcriptions as they happen
     * - Much more responsive than batch recording
     */
    fun startStreamingTranscription(
        onTranscription: (String) -> Unit,
        onError: (String) -> Unit
    ) {
        if (isStreaming) return

        isStreaming = true
        streamingJob = GlobalScope.launch(Dispatchers.IO) {
            try {
                RunAnywhere.startStreamingTranscription(chunkSizeMs = 500)
                    .collect { event ->
                        when (event) {
                            is STTStreamEvent.FinalTranscription -> {
                                if (event.result.transcript.isNotBlank()) {
                                    withContext(Dispatchers.Main) {
                                        onTranscription(event.result.transcript)
                                    }
                                }
                            }
                            is STTStreamEvent.Error -> {
                                withContext(Dispatchers.Main) {
                                    onError(event.error.message ?: "Streaming error")
                                }
                            }
                            else -> {
                                // Handle other events like SpeechStarted, SpeechEnded if needed
                            }
                        }
                    }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    onError(e.message ?: "Streaming failed")
                }
            }
        }
    }

    fun stopStreamingTranscription() {
        isStreaming = false
        streamingJob?.cancel()
        RunAnywhere.stopStreamingTranscription()
    }

    fun isActive() = isStreaming
}
```

#### 3. UI Action for Voice Input (Streaming Version)

Create `VoiceInputAction.kt`:

```kotlin
package com.yourplugin.voice.actions

import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.fileEditor.FileEditorManager
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.Messages
import com.yourplugin.voice.StreamingVoiceService
import com.yourplugin.voice.VoiceSDKInitializer
import com.intellij.icons.AllIcons

class VoiceInputAction : AnAction(
    "🎤 Voice Input",
    "Real-time speech-to-text with Voice Activity Detection",
    AllIcons.Actions.Execute
) {

    private val streamingService = StreamingVoiceService()

    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return

        if (!VoiceSDKInitializer.isReady()) {
            Messages.showWarningDialog(
                project,
                "Voice SDK is still initializing. Please try again in a few seconds.",
                "SDK Not Ready"
            )
            return
        }

        if (!streamingService.isActive()) {
            startStreamingTranscription(project)
        } else {
            stopStreamingTranscription(project)
        }
    }

    private fun startStreamingTranscription(project: Project) {
        // Show a non-blocking notification that streaming started
        Messages.showInfoMessage(
            project,
            "🎤 Listening... The microphone is now active.\n" +
                    "Just speak naturally - transcription will appear automatically when you finish speaking.\n" +
                    "Click the action again to stop.",
            "Voice Streaming Started"
        )

        streamingService.startStreamingTranscription(
            onTranscription = { text ->
                // Insert each transcription as it comes in
                insertTextInEditor(project, text + " ")
            },
            onError = { error ->
                Messages.showErrorDialog(project,
                    "Voice streaming error: $error\n\nTry restarting the streaming.",
                    "Streaming Error")
                stopStreamingTranscription(project)
            }
        )
    }

    private fun stopStreamingTranscription(project: Project) {
        streamingService.stopStreamingTranscription()

        Messages.showInfoMessage(
            project,
            "🔇 Voice streaming stopped.",
            "Streaming Stopped"
        )
    }

    private fun insertTextInEditor(project: Project, text: String) {
        val editor = FileEditorManager.getInstance(project).selectedTextEditor
        if (editor != null) {
            val document = editor.document
            val caretModel = editor.caretModel
            val offset = caretModel.offset

            com.intellij.openapi.application.ApplicationManager.getApplication().runWriteAction {
                document.insertString(offset, text)
                caretModel.moveToOffset(offset + text.length)
            }
        } else {
            // If no editor is open, show the transcription in a dialog
            Messages.showInfoMessage(project, "Transcription: $text", "Voice Input")
        }
    }

    override fun update(e: AnActionEvent) {
        super.update(e)

        // Update action text based on streaming state
        val presentation = e.presentation
        if (streamingService.isActive()) {
            presentation.text = "🔇 Stop Voice Input"
            presentation.description = "Stop real-time speech transcription"
        } else {
            presentation.text = "🎤 Start Voice Input"
            presentation.description = "Start real-time speech-to-text with Voice Activity Detection"
        }
    }
}
```

#### 4. Register in plugin.xml

```xml
<idea-plugin>
    <id>com.yourcompany.voice-enhanced-plugin</id>
    <name>Your Plugin with Voice</name>
    <version>1.0.0</version>
    <vendor>Your Company</vendor>

    <depends>com.intellij.modules.platform</depends>

    <extensions defaultExtensionNs="com.intellij">
        <!-- Initialize Voice SDK on startup -->
        <postStartupActivity
            implementation="com.yourplugin.voice.VoiceSDKInitializer"/>
    </extensions>

    <actions>
        <!-- Voice Input Action -->
        <action id="VoiceInputAction"
                class="com.yourplugin.voice.actions.VoiceInputAction"
                text="Voice Input"
                description="Transcribe speech to text">
            <!-- Add to Tools menu -->
            <add-to-group group-id="ToolsMenu" anchor="last"/>
            <!-- Add to editor popup menu -->
            <add-to-group group-id="EditorPopupMenu" anchor="last"/>
            <!-- Keyboard shortcut -->
            <keyboard-shortcut keymap="$default" first-keystroke="ctrl shift V"/>
        </action>
    </actions>
</idea-plugin>
```

### Testing Your Integration

#### Test Code

```kotlin
// Simple test in a scratch file
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    // Generate test audio (1 second of silence)
    val testAudio = ByteArray(32000) { 0 }

    try {
        val result = RunAnywhere.transcribe(testAudio)
        println("Transcription: $result")
    } catch (e: Exception) {
        println("Error: ${e.message}")
    }
}
```

### What Happens on First Run

1. **SDK Initialization**: ~2 seconds
2. **First Transcription**:
    - Model downloads automatically (~141MB)
    - Takes ~30-60 seconds first time only
    - Saves to `~/.runanywhere/models/ggml-base.bin`
3. **Subsequent Transcriptions**: ~100-200ms

### Troubleshooting

| Issue                             | Solution                             |
|-----------------------------------|--------------------------------------|
| "SDK not initialized"             | Wait 2-3 seconds after plugin starts |
| "Model download failed"           | Check internet connection, retry     |
| "Transcription returns mock data" | Normal in dev mode if model fails    |
| "No audio recorded"               | Check macOS microphone permissions   |
| "Native library error"            | Restart IDE, check JAR integrity     |

### Important Notes for v0.1

- **Development Mode Only**: No API keys required
- **Local Processing**: Everything runs on device
- **Auto Download**: Model downloads on first use (141MB)
- **macOS Only**: Windows/Linux support coming in v0.2
- **Mock Fallback**: Returns mock transcription if model fails

### Performance Expectations

- **Initialization**: 2-3 seconds
- **Model Download**: 30-60 seconds (first time only)
- **Streaming Response Time**: 200-500ms after you stop speaking
- **Voice Detection**: Works with normal speaking volume (0.008f sensitivity)
- **Memory Usage**: ~250MB when active
- **CPU Usage**: Low during listening, moderate during transcription
- **GPU**: Uses Metal acceleration on Apple Silicon
- **Microphone**: Automatically starts listening, no need to hold buttons

---

## 📊 Release Notes

### v0.1.0 (Current - Updated Sept 2025)

- ✅ **Real-time streaming transcription** with Voice Activity Detection
- ✅ **Optimized sensitivity** - works with normal speaking volume
- ✅ **Automatic speech detection** - no button holding required
- ✅ **Hallucination prevention** - VAD filters silence
- ✅ Offline speech-to-text with Whisper-base (141MB)
- ✅ Auto model management and download
- ✅ Development mode (no API keys required)
- ✅ macOS support (Intel & Apple Silicon)
- ✅ Memory management and buffer optimization

### Known Limitations

- macOS only (Windows/Linux in v0.2)
- Single model (whisper-base, 141MB)
- English only
- No streaming (batch processing only)
- 10-second recording limit

### Coming in v0.2

- Windows & Linux support
- Multiple model sizes (tiny: 39MB, small: 244MB)
- Streaming transcription
- Multiple languages
- Production API integration

---

## 🆘 Support

### For Integration Issues

1. Check the troubleshooting section
2. Enable debug logging: `System.setProperty("runanywhere.debug", "true")`
3. Contact: Sanchit on Discord/Slack

### Quick Debug Checklist

- [ ] JAR added to dependencies?
- [ ] SDK initializer registered in plugin.xml?
- [ ] Microphone permissions granted?
- [ ] Model downloaded? Check `~/.runanywhere/models/`
- [ ] Using macOS? (Windows/Linux not supported yet)

---

## 🎉 Success Metrics

Your integration is successful when:

1. Plugin starts without errors
2. Voice action appears in Tools menu
3. First recording triggers model download
4. Transcription returns actual text (not mock)
5. Subsequent recordings work instantly

---

*Happy coding! 🚀*
