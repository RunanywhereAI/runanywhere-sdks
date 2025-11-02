# RunAnywhere Android SDK - Quick Start Guide

**Create a simple chat app in 5 minutes**

This guide shows you how to create a new Android app with a simple text chat interface using the RunAnywhere SDK.

---

## 🚀 TL;DR - Quick Copy-Paste

**1. Download BOTH SDK AARs:**

[Download RunAnywhereKotlinSDK-release.aar](https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/android/v0.1.3-alpha/RunAnywhereKotlinSDK-release.aar) (Core SDK - 4.0MB)

[Download runanywhere-llm-llamacpp-release.aar](https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/android/v0.1.3-alpha/runanywhere-llm-llamacpp-release.aar) (LLM Module - 2.1MB)

Or via command line:

```bash
curl -L -o RunAnywhereKotlinSDK-release.aar \
  https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/android/v0.1.3-alpha/RunAnywhereKotlinSDK-release.aar

curl -L -o runanywhere-llm-llamacpp-release.aar \
  https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/android/v0.1.3-alpha/runanywhere-llm-llamacpp-release.aar
```

**2. Add to your project:**

Place BOTH AAR files in `app/libs/`:

- `app/libs/RunAnywhereKotlinSDK-release.aar`
- `app/libs/runanywhere-llm-llamacpp-release.aar`

**3. Add to app `build.gradle.kts`:**

```kotlin
dependencies {
  // Core SDK
  implementation(files("libs/RunAnywhereKotlinSDK-release.aar"))

  // LLM Module (includes llama.cpp with 7 ARM64 CPU variants)
  implementation(files("libs/runanywhere-llm-llamacpp-release.aar"))

  // Required dependency
  implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
```

**4. That's it!** Scroll down for complete setup instructions.

**📦 What's Included:**

- **Core SDK** (4.0MB): Component architecture, model management, event system, analytics, prompt-based tool calling
- **LlamaCpp Module** (2.1MB): 7 optimized llama.cpp native libraries for ARM64
  - Variants: Baseline, fp16, dotprod, v8.4, i8mm, sve, i8mm+sve
  - Runtime CPU feature detection automatically selects best variant

**🆕 New in v0.1.3-alpha:**

- **Analytics Enhancements**: Real device & session context, host app metadata tracking, offline queue support
- **Time-to-First-Token Tracking**: Now tracks and reports time-to-first-token metrics for LLM generation
- **Privacy Protection**: Removed PII leaks in JVM DeviceInfoService (no more username in device model)
- **Bug Fixes**: Fixed analytics queue deadlock, initialization order issues, and JVM platform missing methods

**Previous releases:**

- v0.1.2-alpha: Device ID persistence fix, improved analytics reliability
- v0.1.1-alpha: Prompt-based tool calling, analytics improvements, JVM platform fixes

---

## Prerequisites

- Android Studio (latest version)
- JDK 17+
- Minimum Android SDK 24 (Android 7.0)

---

## Step 1: Add SDK Dependency

### Option A: Via JitPack (Recommended - No Authentication Required)

**⚠️ First build takes 2-3 minutes while JitPack builds the SDK. Subsequent syncs are instant.**

In your **project-level** `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
  repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
  repositories {
    google()
    mavenCentral()
    maven { url = uri("https://jitpack.io") }
  }
}
```

In your **app-level** `build.gradle.kts`:

```kotlin
android {
  namespace = "com.example.myapp"
  compileSdk = 36

  defaultConfig {
    applicationId = "com.example.myapp"
    minSdk = 24
    targetSdk = 36
    versionCode = 1
    versionName = "1.0"
  }

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }

  kotlinOptions {
    jvmTarget = "17"
  }
}

dependencies {
  // RunAnywhere SDK - Core (v0.1.3-alpha)
  implementation("com.github.RunanywhereAI.runanywhere-sdks:runanywhere-kotlin:android-v0.1.3-alpha")

  // RunAnywhere SDK - LLM Module (includes llama.cpp with 7 ARM64 CPU variants)
  implementation("com.github.RunanywhereAI.runanywhere-sdks:runanywhere-llm-llamacpp:android-v0.1.3-alpha")

  // Required: Kotlin Coroutines
  implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

  // Optional: Jetpack Compose (for UI in this quickstart)
  implementation(platform("androidx.compose:compose-bom:2024.02.00"))
  implementation("androidx.compose.ui:ui")
  implementation("androidx.compose.material3:material3")
  implementation("androidx.compose.ui:ui-tooling-preview")
  implementation("androidx.activity:activity-compose:1.8.2")
  implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")
}
```

**📦 What's Included:**

- **Core SDK:** Component architecture, model management, event system
- **LlamaCpp Module:** 7 optimized llama.cpp native libraries for ARM64 (~50MB total)
  - Baseline, fp16, dotprod, v8.4, i8mm, sve, i8mm+sve variants
  - Runtime CPU feature detection selects best variant automatically

**🔖 Latest Release:** `android-v0.1.3-alpha`

**📄 Release Notes:** [GitHub Release](https://github.com/RunanywhereAI/runanywhere-sdks/releases/tag/android-v0.1.3-alpha)

---

## Step 2: Android Manifest Setup

In `AndroidManifest.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

  <!-- Required Permissions -->
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
          android:maxSdkVersion="28" />

  <application
          android:name=".MyApplication"
          android:largeHeap="true"
          android:label="@string/app_name"
          android:theme="@style/Theme.MyApp">

    <activity
            android:name=".MainActivity"
            android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
      </intent-filter>
    </activity>
  </application>
</manifest>
```

**Key Points:**
- `android:name=".MyApplication"` - Custom Application class (created in Step 3)
- `android:largeHeap="true"` - Recommended for running AI models

---

## Step 3: Initialize SDK in Application Class

Create `MyApplication.kt`:

```kotlin
package com.example.myapp

import android.app.Application
import android.util.Log
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.public.extensions.addModelFromURL
import com.runanywhere.sdk.llm.llamacpp.LlamaCppServiceProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch

class MyApplication : Application() {

  override fun onCreate() {
    super.onCreate()

    // Initialize SDK asynchronously
    GlobalScope.launch(Dispatchers.IO) {
      initializeSDK()
    }
  }

  private suspend fun initializeSDK() {
    try {
      // Step 1: Initialize SDK
      RunAnywhere.initialize(
        context = this@MyApplication,
        apiKey = "dev",  // Any string works in dev mode
        environment = SDKEnvironment.DEVELOPMENT
      )

      // Step 2: Register LLM Service Provider
      LlamaCppServiceProvider.register()

      // Step 3: Register Models
      registerModels()

      // Step 4: Scan for previously downloaded models
      RunAnywhere.scanForDownloadedModels()

      Log.i("MyApp", "SDK initialized successfully")

    } catch (e: Exception) {
      Log.e("MyApp", "SDK initialization failed: ${e.message}")
    }
  }

  private suspend fun registerModels() {
    // Smallest model - great for testing (119 MB)
    addModelFromURL(
      url = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
      name = "SmolLM2 360M Q8_0",
      type = "LLM"
    )

    // Medium-sized model - better quality (374 MB)
    addModelFromURL(
      url = "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
      name = "Qwen 2.5 0.5B Instruct Q6_K",
      type = "LLM"
    )

    // Add more models as needed
  }
}
```

**What This Does:**
1. Initializes the SDK (lightweight, no network calls)
2. Registers the LLM service provider (enables text generation)
3. Registers available models (adds them to the model registry)
4. Scans for any previously downloaded models

---

## Step 4: Model Management (Download & Load)

### Get Available Models

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.listAvailableModels

suspend fun getModels(): List<ModelInfo> {
  return listAvailableModels()
}
```

### Download a Model

```kotlin
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch

fun downloadModel(modelId: String) {
  viewModelScope.launch {
    RunAnywhere.downloadModel(modelId).collect { progress ->
      // progress is Float from 0.0 to 1.0
      val percentage = (progress * 100).toInt()
      Log.d("Download", "Progress: $percentage%")

      // Update UI with progress
      _downloadProgress.value = percentage
    }
    Log.d("Download", "Model downloaded successfully")
  }
}
```

### Load a Model

```kotlin
suspend fun loadModel(modelId: String): Boolean {
  return try {
    val success = RunAnywhere.loadModel(modelId)
    if (success) {
      Log.d("Model", "Model loaded successfully")
    }
    success
  } catch (e: Exception) {
    Log.e("Model", "Failed to load model: ${e.message}")
    false
  }
}
```

**Note:** Only one model can be loaded at a time. Loading a new model automatically unloads the previous one.

---

## Step 5: Text Generation (Chat)

### Simple One-Shot Chat

```kotlin
import com.runanywhere.sdk.public.RunAnywhere

suspend fun chat(prompt: String): String {
  return RunAnywhere.generate(prompt)
}

// Usage:
viewModelScope.launch {
  val response = chat("What is the capital of France?")
  Log.d("Chat", "Response: $response")
}
```

### Streaming Chat (Real-time Token Generation)

```kotlin
import kotlinx.coroutines.flow.Flow

fun chatStreaming(prompt: String): Flow<String> {
  return RunAnywhere.generateStream(prompt)
}

// Usage:
viewModelScope.launch {
  var fullResponse = ""
  chatStreaming("Tell me a story").collect { token ->
    fullResponse += token
    // Update UI with each token
    _chatMessage.value = fullResponse
  }
}
```

---

## Step 6: Simple Chat UI with Jetpack Compose

Create a basic chat screen:

```kotlin
package com.example.myapp

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

// Simple Message Data Class
data class ChatMessage(
  val text: String,
  val isUser: Boolean
)

// ViewModel
class ChatViewModel : ViewModel() {

  private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
  val messages: StateFlow<List<ChatMessage>> = _messages

  private val _isLoading = MutableStateFlow(false)
  val isLoading: StateFlow<Boolean> = _isLoading

  fun sendMessage(text: String) {
    // Add user message
    _messages.value += ChatMessage(text, isUser = true)

    viewModelScope.launch {
      _isLoading.value = true

      // Generate response with streaming
      var assistantResponse = ""
      RunAnywhere.generateStream(text).collect { token ->
        assistantResponse += token

        // Update assistant message in real-time
        val currentMessages = _messages.value.toMutableList()
        if (currentMessages.lastOrNull()?.isUser == false) {
          currentMessages[currentMessages.lastIndex] =
            ChatMessage(assistantResponse, isUser = false)
        } else {
          currentMessages.add(ChatMessage(assistantResponse, isUser = false))
        }
        _messages.value = currentMessages
      }

      _isLoading.value = false
    }
  }
}

// Composable UI
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(viewModel: ChatViewModel) {
  val messages by viewModel.messages.collectAsState()
  val isLoading by viewModel.isLoading.collectAsState()
  var inputText by remember { mutableStateOf("") }

  Scaffold(
    topBar = {
      TopAppBar(title = { Text("AI Chat") })
    }
  ) { padding ->
    Column(
      modifier = Modifier
        .fillMaxSize()
        .padding(padding)
    ) {
      // Messages List
      LazyColumn(
        modifier = Modifier.weight(1f),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
      ) {
        items(messages) { message ->
          MessageBubble(message)
        }
      }

      // Input Field
      Row(
        modifier = Modifier
          .fillMaxWidth()
          .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
      ) {
        TextField(
          value = inputText,
          onValueChange = { inputText = it },
          modifier = Modifier.weight(1f),
          placeholder = { Text("Type a message...") },
          enabled = !isLoading
        )

        Button(
          onClick = {
            if (inputText.isNotBlank()) {
              viewModel.sendMessage(inputText)
              inputText = ""
            }
          },
          enabled = !isLoading && inputText.isNotBlank()
        ) {
          Text("Send")
        }
      }
    }
  }
}

@Composable
fun MessageBubble(message: ChatMessage) {
  Card(
    modifier = Modifier.fillMaxWidth(),
    colors = CardDefaults.cardColors(
      containerColor = if (message.isUser)
        MaterialTheme.colorScheme.primaryContainer
      else
        MaterialTheme.colorScheme.secondaryContainer
    )
  ) {
    Text(
      text = message.text,
      modifier = Modifier.padding(12.dp)
    )
  }
}
```

---

## Complete Workflow

### 1. App Startup
```
Application.onCreate()
  ↓
SDK Initialize (lightweight)
  ↓
Register LLM Provider
  ↓
Register Models
  ↓
Scan for Downloaded Models
```

### 2. Model Download & Load
```
User selects model
  ↓
Download with progress tracking
  ↓
Load model into memory
  ↓
Ready for inference
```

### 3. Chat Interaction
```
User types message
  ↓
Send to SDK (generateStream)
  ↓
Receive tokens in real-time
  ↓
Update UI with streaming response
```

---

## Available Models

Here are recommended models sorted by size:

| Model | Size | Quality | Use Case |
|-------|------|---------|----------|
| SmolLM2 360M Q8_0 | 119 MB | Basic | Testing, simple Q&A |
| LiquidAI LFM2 350M Q4_K_M | 210 MB | Basic | Quick responses |
| Qwen 2.5 0.5B Instruct Q6_K | 374 MB | Good | General chat |
| Llama 3.2 1B Instruct Q6_K | 815 MB | Better | Quality conversations |
| Qwen 2.5 1.5B Instruct Q6_K | 1.2 GB | Best | High-quality chat |

**Recommendation:** Start with **SmolLM2 360M Q8_0** for quick testing, then upgrade to **Qwen 2.5 0.5B** for production.

---

## Model Registration URLs

Copy-paste these into your `registerModels()` function:

```kotlin
// SmolLM2 360M (119 MB) - Fastest, smallest
addModelFromURL(
  url = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
  name = "SmolLM2 360M Q8_0",
  type = "LLM"
)

// Qwen 2.5 0.5B (374 MB) - Good balance
addModelFromURL(
  url = "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
  name = "Qwen 2.5 0.5B Instruct Q6_K",
  type = "LLM"
)

// Llama 3.2 1B (815 MB) - Better quality
addModelFromURL(
  url = "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q6_K_L.gguf",
  name = "Llama 3.2 1B Instruct Q6_K",
  type = "LLM"
)

// Qwen 2.5 1.5B (1.2 GB) - Best quality
addModelFromURL(
  url = "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q6_k.gguf",
  name = "Qwen 2.5 1.5B Instruct Q6_K",
  type = "LLM"
)
```

---

## Troubleshooting

### Model download fails
- Check internet connection
- Ensure `INTERNET` permission in manifest
- Verify HuggingFace URL is accessible

### Model load fails
- Ensure model is fully downloaded
- Check available device memory (models need RAM to load)
- Try unloading other apps

### Generation is slow
- Normal for on-device inference
- Try a smaller model (SmolLM2 360M)
- Ensure `android:largeHeap="true"` in manifest

### App crashes during generation
- Reduce model size
- Enable `android:largeHeap="true"`
- Close other apps to free memory

---

## Next Steps

1. **Download a model** in your UI (show progress bar)
2. **Add model selection** (dropdown or list)
3. **Implement chat history** (persist conversations)
4. **Add system prompts** (customize AI behavior)
5. **Error handling** (network errors, out of memory)

---

## API Reference

### Core SDK APIs

```kotlin
// Initialization
RunAnywhere.initialize(
  context: Context,
  apiKey: String,
  environment: SDKEnvironment
)

// Model Management
suspend fun downloadModel(modelId: String): Flow<Float>
suspend fun loadModel(modelId: String): Boolean
suspend fun unloadModel()
suspend fun availableModels(): List<ModelInfo>
suspend fun listAvailableModels(): List<ModelInfo>

// Text Generation
suspend fun generate(prompt: String): String
fun generateStream(prompt: String): Flow<String>
suspend fun chat(prompt: String): String

// Service Provider Registration
LlamaCppServiceProvider.register()

// Model Registration
suspend fun addModelFromURL(url: String, name: String, type: String)
```

---

## Summary

**5-Minute Setup:**
1. Add JitPack dependency
2. Update AndroidManifest (permissions + Application class)
3. Create Application class with SDK init
4. Register models in `registerModels()`
5. Create simple chat UI

**Runtime Flow:**
1. Download a model (with progress tracking)
2. Load the model
3. Send messages with `generateStream()`
4. Display responses in real-time

**That's it!** You now have a working on-device AI chat app.

---

## Support

- GitHub Issues: https://github.com/RunAnywhere/sdks/issues
- Documentation: See `CLAUDE.md` and `README.md` in the SDK repository
