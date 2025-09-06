# RunAnywhere Kotlin SDK - Complete Guide & Integration

## 📋 Table of Contents
- [Quick Start](#-quick-start)
- [Plugin Features](#-plugin-features)
- [SDK Integration Guide](#-sdk-integration-guide)
- [Step-by-Step Integration](#-step-by-step-integration)
- [How to Use Demo Plugin](#-how-to-use-the-demo-plugin)
- [Available Actions](#-available-actions)
- [Keyboard Shortcuts](#️-keyboard-shortcuts)
- [Manual Installation](#-manual-installation)
- [Development Guide](#-development-guide)
- [Troubleshooting](#-troubleshooting)

## 🚀 Quick Start

### Option 1: Install and Run in Android Studio
```bash
# Navigate to SDK directory
cd sdk/runanywhere-kotlin

# Build and run in Android Studio (opens automatically)
./scripts/sdk.sh run-plugin-as

# Or just build the plugin (creates ZIP file)
./scripts/sdk.sh plugin-as
```

### Option 2: Install and Run in IntelliJ IDEA
```bash
# Build and run in IntelliJ IDEA
./scripts/sdk.sh run-plugin

# Or just build the plugin
./scripts/sdk.sh plugin
```

## 🎯 Plugin Features

### What Does This Plugin Do?

The **RunAnywhere Voice Commands** plugin integrates our RunAnywhere SDK into IntelliJ IDEA and Android Studio, enabling:

1. **Voice-to-Code Dictation** - Speak naturally and have your words converted to code
2. **Voice IDE Commands** - Control IntelliJ/Android Studio with voice commands
3. **On-Device AI Processing** - Whisper models run locally for privacy and speed
4. **Real-time Transcription** - Voice Activity Detection (VAD) for seamless dictation
5. **SDK Integration Testing** - Verify SDK components are working correctly

### Core Components

- **STT (Speech-to-Text)**: Powered by Whisper models for accurate transcription
- **VAD (Voice Activity Detection)**: Automatically detects when you're speaking
- **Model Manager**: Handles downloading and loading AI models
- **Analytics**: Tracks usage and performance metrics

---

## 🔧 SDK Integration Guide

### For Plugin Developers: Integrating RunAnywhere SDK into Your Own Plugin

This section explains how to integrate the RunAnywhere Kotlin SDK into your own JetBrains plugin project.

#### Quick Integration Steps

##### 1. Publish SDK to Local Maven
```bash
# Navigate to SDK directory
cd sdk/runanywhere-kotlin

# Build and publish SDK
./scripts/sdk.sh publish-jvm
```

##### 2. Add SDK Dependency to Your Plugin
In your plugin's `build.gradle.kts`:

```kotlin
repositories {
    mavenLocal()  // ⚠️ IMPORTANT: Add this line
    mavenCentral()
}

dependencies {
    // RunAnywhere SDK
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-jvm:0.1.0")

    // Required dependencies
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.0")
}
```

##### 3. Initialize SDK in Your Plugin
```kotlin
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch

class YourPlugin : StartupActivity {
    override fun runActivity(project: Project) {
        GlobalScope.launch {
            try {
                // Initialize SDK in development mode
                RunAnywhere.initialize(
                    apiKey = "dev-api-key",
                    baseURL = "https://api.runanywhere.ai",
                    environment = SDKEnvironment.DEVELOPMENT
                )
                println("✅ RunAnywhere SDK initialized successfully")
            } catch (e: Exception) {
                println("❌ SDK initialization failed: ${e.message}")
            }
        }
    }
}
```

##### 4. Use SDK Features
```kotlin
// Example: Use voice transcription
val audioData: ByteArray = captureAudio() // Your audio capture implementation
val transcription = RunAnywhere.transcribe(audioData)
println("Transcription: $transcription")

// Example: Get available models
val models = RunAnywhere.fetchAvailableModels()
println("Available models: ${models.map { it.name }}")
```

#### Distribution Package

For sharing the SDK with other developers, create a distribution package:

```bash
# Build and package SDK for distribution
./scripts/sdk.sh publish-jvm

# Files will be available at:
# ~/.m2/repository/com/runanywhere/sdk/RunAnywhereKotlinSDK-jvm/0.1.0/
# - RunAnywhereKotlinSDK-jvm-0.1.0.jar (Main SDK)
# - RunAnywhereKotlinSDK-jvm-0.1.0-sources.jar (Source code)
# - RunAnywhereKotlinSDK-jvm-0.1.0.pom (Maven metadata)
```

#### Maven Coordinates
```kotlin
implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-jvm:0.1.0")
```

#### Key SDK Features Available for Integration
- **Voice-to-Text**: Real-time speech recognition using Whisper Base model
- **Model Management**: Automatic model downloading and loading
- **Development Mode**: Mock services for easy testing
- **Event System**: Listen to SDK initialization and model events
- **Privacy-First**: All processing happens on-device

---

## 📝 Step-by-Step Integration

### Detailed Integration Instructions

For complete step-by-step instructions with code examples, see our comprehensive integration guide:

**📁 Distribution Package Location**: `dist/runanywhere-kotlin-sdk-0.1.0/SDK_INTEGRATION_GUIDE.md`

This guide includes:
- ✅ Two integration methods (Maven + Direct JAR)
- ✅ Complete code examples for plugin setup
- ✅ Event handling and advanced features
- ✅ Troubleshooting common issues
- ✅ Verification checklist
- ✅ Best practices and tips

### Sharing SDK with Other Developers

To share the SDK with other developers:

1. **Create Distribution Package:**
   ```bash
   # Build and create distribution
   ./scripts/sdk.sh publish-jvm
   mkdir -p dist/runanywhere-kotlin-sdk-0.1.0
   cp ~/.m2/repository/com/runanywhere/sdk/RunAnywhereKotlinSDK-jvm/0.1.0/* dist/runanywhere-kotlin-sdk-0.1.0/
   ```

2. **Package Contents:**
   - `RunAnywhereKotlinSDK-jvm-0.1.0.jar` - Main SDK
   - `RunAnywhereKotlinSDK-jvm-0.1.0-sources.jar` - Source code
   - `RunAnywhereKotlinSDK-jvm-0.1.0.pom` - Maven metadata
   - `SDK_INTEGRATION_GUIDE.md` - Complete integration guide

3. **Developer Instructions:**
   - Provide the distribution package
   - Point them to the integration guide
   - They can install locally or use JAR directly

### Integration Options Summary

| Method | Best For | Setup Complexity |
|--------|----------|------------------|
| **Local Maven** | Development teams | Low |
| **Direct JAR** | Simple projects | Very Low |
| **Remote Repository** | Production distribution | Medium |

---

## 📖 How to Use the Demo Plugin

### Step 1: Install the Plugin

Follow the Quick Start commands above to build and install the plugin.

### Step 2: Access Plugin Actions

Once installed and after restarting your IDE, you can access the plugin in multiple ways:

#### From the Tools Menu:
1. Open Android Studio or IntelliJ IDEA
2. Go to **Tools** menu in the menu bar
3. You'll see three new options:
   - **Test RunAnywhere SDK** - Tests SDK integration
   - **Voice Command** - Activates voice command mode
   - **Toggle Voice Dictation** - Enables/disables voice dictation

#### From the Edit Menu:
1. Go to **Edit** menu
2. Find **Toggle Voice Dictation** at the bottom

#### Using Keyboard Shortcuts:
See the [Keyboard Shortcuts](#️-keyboard-shortcuts) section below.

### Step 3: Test the SDK Integration

1. **Click** Tools → Test RunAnywhere SDK (or press `Cmd+Shift+T` on Mac / `Ctrl+Shift+T` on Windows/Linux)
2. **Wait** for the SDK to initialize
3. **View** the results dialog showing:
   - ✅ SDK Initialization status
   - 📦 SDK Version (0.1.0)
   - 🎯 Environment (Development)
   - Available components (STT, VAD, Model Loading, Analytics)

### Step 4: Use Voice Features

#### Voice Commands:
1. **Click** Tools → Voice Command (or press `Cmd+Shift+V`)
2. **Allow** microphone access if prompted
3. **Speak** your command clearly
4. **Watch** as the IDE executes your voice command

#### Voice Dictation:
1. **Place** your cursor where you want to insert text
2. **Click** Edit → Toggle Voice Dictation (or press `Cmd+Shift+D`)
3. **Start speaking** - your words will be transcribed in real-time
4. **Toggle off** when done to stop dictation

## 🎮 Available Actions

### 1. Test RunAnywhere SDK
- **Location**: Tools Menu → Test RunAnywhere SDK
- **Shortcut**: `Cmd+Shift+T` (Mac) / `Ctrl+Shift+T` (Windows/Linux)
- **Purpose**: Validates SDK integration and shows component status
- **What it does**:
  - Initializes the RunAnywhere SDK
  - Tests connection to SDK services
  - Verifies STT component availability
  - Shows detailed status report

### 2. Voice Command
- **Location**: Tools Menu → Voice Command
- **Shortcut**: `Cmd+Shift+V` (Mac) / `Ctrl+Shift+V` (Windows/Linux)
- **Purpose**: Execute IDE actions using voice commands
- **Examples**:
  - "Open file MainActivity"
  - "Run project"
  - "Find usages"
  - "Refactor rename"

### 3. Toggle Voice Dictation
- **Location**: Edit Menu → Toggle Voice Dictation
- **Shortcut**: `Cmd+Shift+D` (Mac) / `Ctrl+Shift+D` (Windows/Linux)
- **Purpose**: Enable/disable continuous voice-to-text mode
- **Use cases**:
  - Writing comments and documentation
  - Entering string literals
  - Quick code prototyping
  - Natural language programming

## ⌨️ Keyboard Shortcuts

| Action | Mac | Windows/Linux | Description |
|--------|-----|---------------|-------------|
| Test SDK | `Cmd+Shift+T` | `Ctrl+Shift+T` | Test RunAnywhere SDK integration |
| Voice Command | `Cmd+Shift+V` | `Ctrl+Shift+V` | Activate voice command input |
| Voice Dictation | `Cmd+Shift+D` | `Ctrl+Shift+D` | Toggle voice dictation mode |

## 📦 Manual Installation

If you prefer to install manually:

1. **Build the plugin:**
   ```bash
   ./scripts/sdk.sh plugin-as  # For Android Studio
   # OR
   ./scripts/sdk.sh plugin     # For IntelliJ IDEA
   ```

2. **Install in your IDE:**
   - Open Android Studio/IntelliJ IDEA
   - Go to `File` → `Settings` → `Plugins`
   - Click gear icon ⚙️ → `Install Plugin from Disk`
   - Select: `examples/intellij-plugin-demo/plugin/build/distributions/runanywhere-voice-1.0.0.zip`
   - Restart IDE

## 🧪 Verifying Installation

### Check Plugin is Installed:
1. **Open** Settings/Preferences (Cmd+, on Mac / Ctrl+Alt+S on Windows)
2. **Navigate** to Plugins → Installed
3. **Search** for "RunAnywhere"
4. **Verify** "RunAnywhere Voice Commands" appears with version 1.0.0

### Check Menu Items:
1. **Open** Tools menu - should see new RunAnywhere actions
2. **Open** Edit menu - should see Toggle Voice Dictation at bottom
3. **Right-click** in editor - voice options in context menu (if enabled)

### Test Basic Functionality:
1. **Press** `Cmd+Shift+T` to test SDK
2. **Verify** success dialog appears
3. **Try** voice command with `Cmd+Shift+V`
4. **Test** dictation with `Cmd+Shift+D`

## 🛠️ All Available Commands

```bash
# Core SDK Commands
./scripts/sdk.sh jvm           # Build JVM SDK only
./scripts/sdk.sh clean          # Clean all build artifacts

# Plugin Commands
./scripts/sdk.sh plugin         # Build for IntelliJ IDEA
./scripts/sdk.sh plugin-as      # Build for Android Studio
./scripts/sdk.sh run-plugin     # Build & run IntelliJ IDEA
./scripts/sdk.sh run-plugin-as  # Build & run Android Studio

# Other Commands
./scripts/sdk.sh help           # Show all commands
./scripts/sdk.sh info           # Show SDK info
```

## 📁 Project Structure

```
sdk/runanywhere-kotlin/
├── scripts/
│   ├── sdk.sh           # Main build script
│   └── detect-ide.sh    # Auto-detects installed IDEs
├── src/
│   ├── commonMain/      # Shared code
│   ├── jvmMain/         # JVM-specific code
│   └── androidMain/     # Android-specific code
└── build/
    └── libs/            # Built JARs

examples/intellij-plugin-demo/
└── plugin/
    ├── src/             # Plugin source code
    └── build/
        └── distributions/  # Plugin ZIP files
```

## 🔧 Troubleshooting

### Plugin doesn't appear in Tools menu
- **Restart** the IDE after installation (required!)
- **Check** Settings → Plugins → Installed tab for "RunAnywhere Voice Commands"
- **Verify** plugin is enabled (checkbox is checked)
- **Try** File → Invalidate Caches and Restart

### Keyboard shortcuts not working
- **Check** Settings → Keymap → search for "RunAnywhere"
- **Verify** no conflicts with existing shortcuts
- **Reset** to defaults if needed

### Voice features not responding
- **Check** microphone permissions in system settings
- **Verify** SDK initialized successfully (use Test SDK action)
- **Ensure** no other apps are using the microphone
- **Check** IDE console for error messages

### SDK initialization fails
- **Verify** you have internet connection (for initial model downloads)
- **Check** you have sufficient disk space (models require ~500MB)
- **Ensure** no firewall is blocking connections
- **Try** running with `--debug` flag for detailed logs

### Build fails
```bash
# Clean everything and rebuild
./scripts/sdk.sh clean
./scripts/sdk.sh jvm
./scripts/sdk.sh plugin-as
```

### Can't find script
```bash
# Make sure you're in the SDK directory
cd sdk/runanywhere-kotlin
ls scripts/  # Should show sdk.sh and detect-ide.sh
```

### Plugin compatibility error
- The plugin auto-detects your IDE version
- If you see version mismatch, update the script:
```bash
./scripts/sdk.sh info  # Check detected versions
./scripts/sdk.sh plugin-as  # Rebuilds with correct version
```

## 💡 Tips

- The script automatically detects your installed IDE version
- The plugin works in both Android Studio and IntelliJ IDEA
- SDK is published to local Maven (~/.m2/repository)
- Plugin ZIP is created in: `examples/intellij-plugin-demo/plugin/build/distributions/`

## 🔍 Plugin Architecture

### How It Works

```
┌─────────────────┐
│   User Voice    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Microphone     │
│   Capture       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  VAD Service    │ ◄── Voice Activity Detection
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  STT Service    │ ◄── Whisper Model (On-device)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Transcription   │
│    Service      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  IDE Action     │ ◄── Execute command or insert text
└─────────────────┘
```

### Services

1. **VoiceService** (Application-level)
   - Manages microphone access
   - Handles audio capture
   - Coordinates with VAD

2. **TranscriptionService** (Project-level)
   - Processes audio to text
   - Manages Whisper models
   - Handles multi-language support

3. **RunAnywhere SDK**
   - Core AI functionality
   - Model management
   - Performance optimization

## 📝 Development Guide

### Adding New Voice Commands

1. **Create** new action class in `plugin/src/main/kotlin/com/runanywhere/plugin/actions/`
2. **Extend** `AnAction` and implement `actionPerformed`
3. **Register** in `plugin.xml` under `<actions>` section
4. **Add** keyboard shortcut if needed
5. **Build** and test: `./scripts/sdk.sh run-plugin-as`

Example:
```kotlin
class MyVoiceAction : AnAction("My Voice Action") {
    override fun actionPerformed(e: AnActionEvent) {
        // Your voice action logic here
    }
}
```

### Adding New SDK Features

1. **Implement** feature in `sdk/runanywhere-kotlin/src/commonMain/`
2. **Add** platform-specific code if needed:
   - JVM: `src/jvmMain/`
   - Android: `src/androidMain/`
3. **Build** SDK: `./scripts/sdk.sh jvm`
4. **Test** in plugin: `./scripts/sdk.sh run-plugin-as`
5. **Verify** with Test SDK action

### Modifying the Plugin

**Key Files:**
```
examples/intellij-plugin-demo/plugin/
├── src/main/kotlin/com/runanywhere/plugin/
│   ├── actions/
│   │   ├── SDKTestAction.kt      # SDK integration test
│   │   ├── VoiceCommandAction.kt  # Voice command handler
│   │   └── VoiceDictationAction.kt # Dictation toggle
│   ├── services/
│   │   ├── VoiceService.kt        # Voice capture service
│   │   └── TranscriptionService.kt # STT service wrapper
│   └── ui/
│       └── VoiceToolWindowFactory.kt # Tool window UI
└── src/main/resources/
    └── META-INF/
        └── plugin.xml              # Plugin configuration
```

### Testing Voice Features

1. **Enable debug logging:**
```kotlin
RunAnywhere.setDebugMode(true)
```

2. **Monitor console output:**
```bash
tail -f ~/Library/Logs/IntelliJIdea*/idea.log  # Mac
tail -f ~/.IntelliJIdea*/system/log/idea.log  # Linux
```

3. **Test with mock audio:**
```kotlin
// In test mode, use pre-recorded audio
val testAudio = loadTestAudioFile("test_voice_command.wav")
voiceService.processAudio(testAudio)
```

### SDK Maven Coordinates
```kotlin
dependencies {
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-jvm:0.1.0")
}
```

## 🚦 Current Status

### ✅ Working Features
- SDK integration and initialization
- Plugin installation in Android Studio & IntelliJ
- Test SDK action with status dialog
- Basic action framework
- Keyboard shortcuts

### 🚧 In Development
- Voice command execution
- Real-time voice dictation
- Whisper model downloading
- VAD integration
- Custom voice commands

### 📅 Coming Soon
- Multi-language support
- Custom wake words
- Voice macros
- Cloud model fallback
- Voice training

## 📚 Additional Resources

- **SDK Documentation**: See `/sdk/runanywhere-kotlin/README.md`
- **API Reference**: Coming soon
- **Voice Command List**: See `docs/voice-commands.md` (when available)
- **Model Information**: Whisper models documentation

## 💡 Pro Tips

1. **Performance**: First model load takes ~30 seconds, subsequent loads are instant
2. **Privacy**: All voice processing happens on-device, no data leaves your machine
3. **Accuracy**: Speak clearly and at normal pace for best results
4. **Languages**: Currently supports English, more languages coming soon
5. **Custom Commands**: You can add your own voice commands by extending the plugin

---

**Need Help?**
- Run `./scripts/sdk.sh help` for all build options
- Check IDE logs for detailed error messages
- File issues at: `github.com/runanywhere/sdk-issues`

**Version Info:**
- Plugin Version: 1.0.0
- SDK Version: 0.1.0
- Supported IDEs: IntelliJ IDEA 2023.3+, Android Studio 2023.1+
