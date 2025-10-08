# RunAnywhereAI Android Sample App - Comprehensive Documentation

**Generated**: October 8, 2025
**App Version**: 1.0 (Debug)
**Target SDK**: Android 14 (API 35)
**Min SDK**: Android 7.0 (API 24)
**Build System**: Gradle 8.11.1 with Kotlin 2.1.21

---

## Table of Contents

1. [App Overview](#1-app-overview)
2. [UI/UX Structure](#2-uiux-structure)
3. [Feature Implementation](#3-feature-implementation)
4. [SDK Integration Points](#4-sdk-integration-points)
5. [Navigation Structure](#5-navigation-structure)
6. [Data Models](#6-data-models)
7. [UI Components & Design](#7-ui-components--design)
8. [Testing & Quality](#8-testing--quality)
9. [Dependencies](#9-dependencies)
10. [Build & Configuration](#10-build--configuration)
11. [Comparison with iOS App](#11-comparison-with-ios-app)

---

## 1. App Overview

### Purpose and Target Audience
The RunAnywhereAI Android sample app is a **comprehensive demonstration application** showcasing the RunAnywhere Kotlin Multiplatform (KMP) SDK's capabilities for **on-device AI**. It targets:
- Android developers evaluating on-device AI capabilities
- Teams building privacy-first AI applications
- Developers learning the RunAnywhere SDK integration patterns
- Beta testers and early adopters

### Android Version Requirements
- **Minimum SDK**: API 24 (Android 7.0 Nougat)
- **Target SDK**: API 35 (Android 14)
- **Compile SDK**: API 35
- **Recommended**: Android 10+ (API 29+) for optimal performance

### Key Features
1. **💬 Chat Interface** - Interactive chat with streaming AI responses
2. **🤖 Model Management** - Download, load, and manage AI models
3. **📝 Quiz Generator** - Generate interactive quizzes from text using structured outputs
4. **🎙️ Voice Assistant** - Complete voice AI pipeline (VAD, STT, LLM, TTS)
5. **⚙️ Settings** - Configuration and preferences management

### Overall Architecture Pattern
**MVVM (Model-View-ViewModel)** with **Jetpack Compose** for reactive UI:
- **Model**: Data classes in `domain/models` and `domain/model`
- **View**: Composable screens in `presentation/*/Screen.kt`
- **ViewModel**: State management in `presentation/*/ViewModel.kt`
- **Repository Pattern**: Data access through `ModelRepository`
- **Service Layer**: Domain services for audio, TTS, voice pipeline
- **No Dependency Injection**: Manual ViewModel creation (Hilt commented out)

---

## 2. UI/UX Structure

The app uses a **bottom navigation** pattern with 5 main screens, matching the iOS app's tab-based structure.

### Screen 1: Chat Screen

**File:** `/app/src/main/java/com/runanywhere/runanywhereai/presentation/chat/ChatScreen.kt` (126 lines)
**ViewModel:** `/app/src/main/java/com/runanywhere/runanywhereai/presentation/chat/ChatViewModel.kt` (504 lines)

**Purpose:** Primary interface for conversing with AI models using text generation

**UI Components:**
- `TopAppBar` - "Chat with AI" title
- `LazyColumn` - Scrollable message list with chat bubbles
- `MessageBubble` - User/Assistant message cards with color differentiation
- `OutlinedTextField` - Message input field
- `Button` - Send message action
- `CircularProgressIndicator` - Loading state (commented out)

**SDK Integration:**
- `RunAnywhere.generateStream(prompt)` - Streaming text generation (line 136)
- `RunAnywhere.generate(prompt)` - Non-streaming generation (line 257)
- Model status checking via `RunAnywhere.availableModels()` (line 474)

**User Flow:**
1. User enters message in text field
2. Taps "Send" button
3. User message appears in chat (blue bubble, right-aligned)
4. Assistant message bubble appears (gray, left-aligned)
5. Response streams in real-time, updating the assistant message
6. Supports thinking mode (`<think>...</think>` tags)
7. Analytics tracked for generation performance

**Status:** ⚠️ **Partial** - UI functional, but SDK streaming methods are placeholders

---

### Screen 2: Models Screen

**File:** `/app/src/main/java/com/runanywhere/ai/models/ui/ModelsScreen.kt` (690 lines)
**ViewModel:** `/app/src/main/java/com/runanywhere/ai/models/viewmodel/ModelManagementViewModel.kt` (211 lines)

**Purpose:** Comprehensive model management interface for discovering, downloading, loading, and managing AI models

**UI Components:**
- `TopAppBar` - Title with Add Model and Refresh actions
- `DeviceInfoCard` - Shows device specs (manufacturer, model, Android API, CPU cores)
- `CurrentModelCard` - Highlights currently loaded model with "Manage" button
- `FrameworkSection` - Expandable sections for each LLM framework
  - `LLAMACPP` - Computer icon, "Llama.cpp Models"
  - `ONNX_RUNTIME` - Memory icon, "ONNX Runtime"
  - `TENSORFLOW_LITE` - Android icon, "TensorFlow Lite"
  - `FOUNDATION_MODELS` - Phone icon, "Foundation Models"
  - `WHISPER_CPP` - Mic icon, "Whisper Models"
  - `CUSTOM` - Extension icon, "Custom Models"
- `ModelRow` - Individual model cards with:
  - Model name and badges (size, format, thinking support)
  - Download/Load/Delete action buttons
  - Download progress indicator
  - Checkmark for currently selected model
- `ModelDetailsDialog` - Full model information popup
- `AddModelDialog` - Custom model addition form
- `ExtendedFloatingActionButton` - "Storage" management shortcut

**SDK Integration:**
- `ModelRepository` wraps SDK model operations
- Model discovery and listing
- Model download with progress tracking
- Model loading/unloading
- Storage information queries

**User Flow:**
1. View device information at top
2. See currently loaded model (if any)
3. Browse frameworks by expanding sections
4. Tap model row to see details
5. Download model by tapping "Download" button
6. Monitor download progress with linear indicator
7. Load model by tapping "Load" button
8. Delete downloaded models with trash icon
9. Add custom models via "+" button in toolbar

**Status:** ✅ **Fully Functional** - Complete UI with robust model management

---

### Screen 3: Settings Screen

**File:** `/app/src/main/java/com/runanywhere/runanywhereai/presentation/settings/SettingsScreen.kt` (27 lines)
**ViewModel:** `/app/src/main/java/com/runanywhere/runanywhereai/presentation/settings/SettingsViewModel.kt` (34 lines)

**Purpose:** App configuration and preferences (placeholder)

**UI Components:**
- `Column` - Centered layout
- `Text` - "Settings" headline
- `Text` - "App settings and configuration coming soon" message

**SDK Integration:** None currently

**User Flow:**
1. Tap Settings tab
2. See placeholder message

**Status:** ❌ **Placeholder** - Not implemented, awaiting feature design

---

### Screen 4: Quiz Screen

**File:** `/app/src/main/java/com/runanywhere/runanywhereai/presentation/quiz/QuizScreen.kt` (700 lines)
**ViewModel:** `/app/src/main/java/com/runanywhere/runanywhereai/presentation/quiz/QuizViewModel.kt` (526 lines)

**Purpose:** Generate interactive True/False quizzes from text using AI-powered structured output generation

**UI Components:**

**Input View (`QuizInputView`):**
- `Card` - Instructions with quiz icon
- `OutlinedTextField` - Multi-line text input (200dp min height, 15 max lines)
- Character counter (12,000 char limit)
- Warning card if no model loaded
- `Button` - "Generate Quiz" with auto-awesome icon

**Generating View (`QuizGeneratingView`):**
- Rotating psychology icon animation
- "Generating Quiz..." text
- `CircularProgressIndicator`

**Quiz View (`QuizSwipeView`):**
- `LinearProgressIndicator` - Progress bar showing current question number
- `QuizCard` - Swipeable card with:
  - Question text (centered, headline style)
  - Swipe indicators (left for False, right for True)
  - Card rotation and scaling animations
  - Color changes based on swipe direction
- Drag gesture handling for True/False answers

**Results View (`QuizResultsView`):**
- Score card with:
  - "Quiz Complete!" title
  - Large score display (e.g., "8 / 10")
  - Percentage (e.g., "80%")
  - Time taken
- Incorrect questions review section
- "Retry Quiz" and "New Quiz" buttons

**SDK Integration:**
- `RunAnywhere.generate(prompt)` for quiz generation (line 90-92)
- Structured JSON parsing for quiz questions
- Model loading status check

**User Flow:**
1. Enter text content or topic in input field
2. Tap "Generate Quiz" button
3. View generation animation
4. Swipe cards left (False) or right (True)
5. Progress through all questions
6. View results with score and review incorrect answers
7. Retry same quiz or create new one

**Status:** ⚠️ **Partial** - Complete UI implementation, SDK method placeholder

---

### Screen 5: Voice Assistant Screen

**File:** `/app/src/main/java/com/runanywhere/runanywhereai/presentation/voice/VoiceAssistantScreen.kt` (480 lines)
**ViewModel:** `/app/src/main/java/com/runanywhere/runanywhereai/presentation/voice/VoiceAssistantViewModel.kt` (243 lines)

**Purpose:** Real-time voice conversation with AI using complete voice pipeline (VAD, STT, LLM, TTS)

**UI Components:**

**Top Bar:**
- `TopAppBar` - "Voice Assistant" title
- `StatusIndicator` - Animated colored dot (green/blue/yellow/cyan/red/gray)
- Status text (e.g., "Listening...", "Processing...", "Speaking...")
- Expand/collapse icon for model info

**Model Badges (expandable):**
- `ModelBadge` - LLM model (Psychology icon, primary color)
- `ModelBadge` - STT model (Mic icon, secondary color)
- `ModelBadge` - TTS voice (VolumeUp icon, tertiary color)

**Conversation Area:**
- `ConversationBubble` - User transcript (primary container, right-aligned)
- `ConversationBubble` - Assistant response (secondary container, left-aligned)
- Empty state with microphone icon and "Tap the microphone to start"
- Auto-scroll to newest messages

**Bottom Control Area:**
- Error message card (red, if any)
- `AudioWaveform` - Visual audio level indicator (fills based on input level)
- `MicrophoneButton` - Large FAB (80dp) with:
  - Dynamic icon (Mic/MicOff/MicNone/HourglassEmpty/VolumeUp)
  - Color changes based on state
  - Scaling animation when listening
  - Spring bounce animation
- Action buttons:
  - "Clear" - Clear conversation
  - "Push to Talk" - Toggle mode (future feature)

**SDK Integration:**
- `VoicePipelineService` - Voice pipeline orchestration (282 lines)
- `AudioCaptureService` - Audio recording (139 lines)
- `AndroidTTSService` - Text-to-speech output (143 lines)
- Permission handling for `RECORD_AUDIO`

**User Flow:**
1. Grant microphone permission if needed
2. Tap microphone button to start session
3. Status indicator turns blue (listening)
4. Audio waveform visualizes input
5. Speak your message
6. Status changes to yellow (processing)
7. User transcript appears
8. Status changes to cyan (speaking)
9. Assistant response appears
10. Tap button again to continue or "Clear" to reset

**Status:** ❌ **Not Functional** - Complete UI, but voice pipeline service crashes (known issue)

---

## 3. Feature Implementation

### Feature: Text Generation (Chat)

**Related Files:**
- **Screen:** `presentation/chat/ChatScreen.kt` (126 lines)
- **ViewModel:** `presentation/chat/ChatViewModel.kt` (504 lines)
- **Models:** `domain/model/ChatMessage.kt` (105 lines)

**SDK Integration Points:**
```kotlin
// Streaming generation (line 136)
RunAnywhere.generateStream(prompt)
    .collect { token ->
        // Update UI with each token
        fullResponse += token
    }

// Non-streaming generation (line 257)
val response = RunAnywhere.generate(prompt)
```

**How it Uses SDK:**
1. Check model loaded status via `availableModels()`
2. Send user prompt to SDK
3. Collect streaming tokens or wait for complete response
4. Handle thinking mode (`<think>...</think>` tags)
5. Track comprehensive analytics (time to first token, tokens/second, etc.)

**User Flow:**
1. User types message
2. Taps send
3. Message appears instantly
4. SDK generates response
5. Response streams into assistant bubble
6. Analytics calculated and attached to message

**Status:** ⚠️ **Partial Implementation**
- ✅ Complete UI with message bubbles
- ✅ Streaming state management
- ✅ Thinking mode parsing
- ✅ Comprehensive analytics tracking
- ❌ SDK methods return placeholders

---

### Feature: Model Management

**Related Files:**
- **Screen:** `ai/models/ui/ModelsScreen.kt` (690 lines)
- **ViewModel:** `ai/models/viewmodel/ModelManagementViewModel.kt` (211 lines)
- **Repository:** `ai/models/repository/ModelRepository.kt` (377 lines)
- **Models:** `ai/models/data/ModelInfo.kt`, `ModelFormat.kt`, `ModelState.kt`, etc.

**SDK Integration Points:**
- Model discovery and listing
- Download with progress tracking
- Model loading/switching
- Storage information queries
- Model deletion

**How it Uses SDK:**
Through `ModelRepository` which wraps SDK operations:
```kotlin
// Get available models
val models = repository.availableModels.collectAsState()

// Download model
repository.downloadModel(modelId).collect { progress ->
    // Update UI with download progress
}

// Load model
repository.loadModel(modelId)

// Delete model
repository.deleteModel(modelId)
```

**User Flow:**
1. Open Models screen
2. View device info and current model
3. Expand framework section (e.g., LlamaCpp)
4. Tap Download on desired model
5. Watch progress bar fill
6. Tap Load when download complete
7. Model becomes current and loads into memory
8. Use model in Chat or Quiz screens

**Status:** ✅ **Fully Functional**
- ✅ Complete model management UI
- ✅ Framework categorization
- ✅ Download progress tracking
- ✅ Model state management (downloading, loaded, available)
- ✅ Storage information
- ✅ Custom model addition (dialog ready)

---

### Feature: Quiz Generation (Structured Outputs)

**Related Files:**
- **Screen:** `presentation/quiz/QuizScreen.kt` (700 lines)
- **ViewModel:** `presentation/quiz/QuizViewModel.kt` (526 lines)

**SDK Integration Points:**
```kotlin
// Generate structured quiz from text (line 90)
val response = RunAnywhere.generate(prompt)
// Expected: JSON with quiz questions array
```

**How it Uses SDK:**
1. Takes user-provided text content
2. Sends to SDK with structured prompt
3. Expects JSON response with quiz questions
4. Parses into `QuizQuestion` data classes
5. Presents as swipeable cards

**User Flow:**
1. Paste article or enter topic (up to 12,000 chars)
2. Tap "Generate Quiz"
3. AI analyzes content
4. Generates True/False questions
5. Swipe right for True, left for False
6. Complete all questions
7. View score and review incorrect answers
8. Retry or create new quiz

**Status:** ⚠️ **Partial Implementation**
- ✅ Complete swipeable card UI
- ✅ Input validation and character counter
- ✅ Results screen with review
- ✅ Retry/New quiz workflows
- ❌ SDK method returns empty questions array

---

### Feature: Voice Assistant Pipeline

**Related Files:**
- **Screen:** `presentation/voice/VoiceAssistantScreen.kt` (480 lines)
- **ViewModel:** `presentation/voice/VoiceAssistantViewModel.kt` (243 lines)
- **Service:** `domain/services/VoicePipelineService.kt` (282 lines)
- **Service:** `domain/services/AudioCaptureService.kt` (139 lines)
- **Service:** `domain/services/AndroidTTSService.kt` (143 lines)

**SDK Integration Points:**
Voice pipeline orchestration:
1. **VAD** (Voice Activity Detection) - Detect speech start/end
2. **STT** (Speech-to-Text) - Transcribe audio to text
3. **LLM** - Generate response from transcript
4. **TTS** (Text-to-Speech) - Speak response

**How it Uses SDK:**
```kotlin
// Initialize voice pipeline
val pipeline = VoicePipelineService(
    audioCapture = AudioCaptureService(context),
    ttsService = AndroidTTSService(context)
)

// Start listening
pipeline.startListening()

// Events flow
pipeline.events.collect { event ->
    when (event) {
        is VoicePipelineEvent.TranscriptionUpdate -> updateTranscript()
        is VoicePipelineEvent.ResponseGenerated -> updateAssistant()
        is VoicePipelineEvent.SpeakingStarted -> showSpeaking()
    }
}
```

**User Flow:**
1. Grant microphone permission
2. Tap microphone button
3. Status: "Listening..."
4. Speak naturally
5. Audio waveform shows input
6. Status: "Processing..."
7. Transcript appears as user bubble
8. Status: "Speaking..."
9. Assistant response appears
10. Device speaks response aloud
11. Cycle continues for multi-turn conversation

**Status:** ❌ **Not Functional**
- ✅ Complete UI with all states
- ✅ Permission handling
- ✅ Audio visualization
- ✅ Model badges
- ✅ Conversation bubbles
- ❌ Voice pipeline service crashes on initialization
- ❌ Known issue documented in SAMPLE-APPS-TODOS.md

---

### Feature: Settings & Configuration

**Related Files:**
- **Screen:** `presentation/settings/SettingsScreen.kt` (27 lines)
- **ViewModel:** `presentation/settings/SettingsViewModel.kt` (34 lines)

**SDK Integration Points:** None

**Status:** ❌ **Placeholder Only**
- Simple centered text saying "coming soon"
- No settings implemented yet

---

## 4. SDK Integration Points

### SDK Initialization

**Location:** `RunAnywhereApplication.kt` (140 lines)

**Initialization Code:**
```kotlin
// Line 39-43
RunAnywhere.initialize(
    apiKey = "demo-api-key",
    baseURL = "https://api.runanywhere.ai",
    environment = SDKEnvironment.DEVELOPMENT
)
```

**Initialization Flow:**
1. App launched
2. `Application.onCreate()` triggers
3. SDK initialized asynchronously on IO dispatcher
4. Logs initialization time
5. Auto-adds demo model from URL
6. Auto-loads first available model

**Timing:**
- Runs in GlobalScope.launch (background)
- Doesn't block app startup
- Status trackable via `isSDKReady()` method

---

### Configuration Management

**Environment Handling:**
- Uses `SDKEnvironment.DEVELOPMENT` for demo mode
- Hardcoded API key (`"demo-api-key"`)
- Base URL set but not used in dev mode
- No prod/staging configurations in app

---

### API Key Handling

**Security:**
- ⚠️ Hardcoded in Application class
- No secure storage (e.g., EncryptedSharedPreferences)
- No BuildConfig variants for different keys
- Acceptable for demo app, not production-ready

---

### Model Management Integration

**Through ModelRepository:**
```kotlin
// Available models
val models: StateFlow<List<ModelInfo>> = repository.availableModels

// Download model
repository.downloadModel(modelId).collect { progress ->
    _downloadProgress.update { it + (modelId to progress) }
}

// Load model
repository.loadModel(modelId)

// Delete model
repository.deleteModel(modelId)

// Storage info
val storageInfo = repository.getStorageInfo()
```

**Repository Implementation:**
- Wraps SDK model operations
- Provides reactive Flows for UI updates
- Handles download progress tracking
- Manages model state transitions

---

### Text Generation Integration

**Streaming:**
```kotlin
RunAnywhere.generateStream(prompt)
    .collect { token ->
        fullResponse += token
        updateUI(fullResponse)
    }
```

**Non-Streaming:**
```kotlin
val response = RunAnywhere.generate(prompt)
updateUI(response)
```

**Analytics:**
Comprehensive tracking of:
- Time to first token
- Total generation time
- Tokens per second (real-time history)
- Thinking time vs response time
- Input/output token counts
- Completion status

---

### Voice Pipeline Integration

**Status:** ❌ Not functional (service crashes)

**Intended Integration:**
```kotlin
// Voice pipeline service
val pipeline = VoicePipelineService(...)

// Start session
pipeline.startSession()

// Collect events
pipeline.events.collect { event ->
    when (event) {
        is VoicePipelineEvent.AudioData -> processAudio()
        is VoicePipelineEvent.TranscriptionUpdate -> showTranscript()
        is VoicePipelineEvent.ResponseGenerated -> generateResponse()
        is VoicePipelineEvent.SpeakingStarted -> speakResponse()
    }
}
```

---

### Error Handling Patterns

**Global Error Handling:**
```kotlin
try {
    val response = RunAnywhere.generate(prompt)
    updateUI(response)
} catch (e: Exception) {
    Log.e("ChatViewModel", "Generation failed", e)
    showError("❌ Generation failed: ${e.message}")
}
```

**Model Loading Errors:**
```kotlin
if (!isModelLoaded) {
    return "❌ No model is loaded. Please select and load a model first."
}
```

**UI State Errors:**
```kotlin
data class ChatUiState(
    val error: Throwable? = null,
    // ... other fields
)

// Clear errors
fun clearError() {
    _uiState.value = _uiState.value.copy(error = null)
}
```

---

## 5. Navigation Structure

### Navigation Pattern
**Jetpack Compose Navigation** with bottom navigation bar

**File:** `presentation/navigation/AppNavigation.kt` (155 lines)

### Main Navigation Graph

```kotlin
NavHost(startDestination = NavigationRoute.CHAT) {
    composable(NavigationRoute.CHAT) { ChatScreen() }
    composable(NavigationRoute.MODELS) { ModelsScreen() }
    composable(NavigationRoute.SETTINGS) { SettingsScreen() }
    composable(NavigationRoute.QUIZ) { QuizScreen() }
    composable(NavigationRoute.VOICE) { VoiceAssistantScreen() }
}
```

### Bottom Navigation Structure

**5 Tabs (matching iOS exactly):**

1. **Chat** - `Icons.Filled.Chat`
2. **Models** - `Icons.Filled.Storage`
3. **Settings** - `Icons.Filled.Settings`
4. **Quiz** - `Icons.Filled.Quiz`
5. **Voice** - `Icons.Filled.Mic`

**Navigation Behavior:**
- `launchSingleTop = true` - Prevents duplicate destinations
- `restoreState = true` - Remembers scroll position and state
- `saveState = true` - Saves state when switching tabs
- `popUpTo(startDestination)` - Clears back stack to start

### Deep Linking Support
**Status:** ❌ Not implemented

**No Intent Filters** in AndroidManifest.xml for deep links

### State Management Across Screens

**ViewModel Scoping:**
- Each screen has its own ViewModel
- ViewModels survive configuration changes
- ViewModels cleared when tab is destroyed (not preserved during tab switches without manual setup)

**Data Sharing:**
- No shared ViewModel between screens
- Could add activity-scoped ViewModels for cross-screen data
- SDK state (loaded model) is global and accessible from any screen

---

## 6. Data Models

### App-Specific Models

#### ChatMessage
**File:** `domain/model/ChatMessage.kt` (105 lines)

```kotlin
data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val role: MessageRole,  // USER, ASSISTANT, SYSTEM
    val content: String,
    val thinkingContent: String? = null,
    val timestamp: Long = System.currentTimeMillis(),
    val analytics: MessageAnalytics? = null,
    val modelInfo: MessageModelInfo? = null
)
```

**Maps to SDK:** Direct representation of SDK message format

---

#### MessageAnalytics
**File:** `domain/model/ChatMessage.kt` (lines 41-77)

Comprehensive performance tracking:
```kotlin
data class MessageAnalytics(
    val messageId: String,
    val conversationId: String,
    val modelId: String,
    val modelName: String,
    val framework: String,
    val timestamp: Long,

    // Timing Metrics
    val timeToFirstToken: Long?,
    val totalGenerationTime: Long,
    val thinkingTime: Long?,
    val responseTime: Long?,

    // Token Metrics
    val inputTokens: Int,
    val outputTokens: Int,
    val thinkingTokens: Int?,
    val responseTokens: Int,
    val averageTokensPerSecond: Double,

    // Quality Metrics
    val messageLength: Int,
    val wasThinkingMode: Boolean,
    val wasInterrupted: Boolean,
    val retryCount: Int,
    val completionStatus: CompletionStatus,

    // Performance Indicators
    val tokensPerSecondHistory: List<Double>,
    val generationMode: GenerationMode,
    val contextWindowUsage: Double,
    val generationParameters: GenerationParameters
)
```

**Maps to SDK:** Enhanced version with Android-specific tracking

---

#### ModelInfo
**File:** `ai/models/data/ModelInfo.kt` (71 lines)

```kotlin
data class ModelInfo(
    val id: String,
    val name: String,
    val description: String,
    val version: String,
    val format: ModelFormat,  // GGUF, ONNX, TFLITE, COREML
    val category: ModelCategory,  // LLM, VISION, AUDIO, MULTIMODAL
    val downloadUrl: String?,
    val downloadSize: Long?,
    val localPath: String?,
    val state: ModelState,  // NOT_DOWNLOADED, DOWNLOADING, BUILT_IN, ERROR
    val preferredFramework: LLMFramework?,
    val supportedFrameworks: List<LLMFramework>,
    val supportsThinking: Boolean,
    val contextLength: Int?,
    val quantization: String?,
    val parametersCount: String?
)
```

**Maps to SDK:** Wraps SDK model metadata with UI-friendly properties

---

#### Quiz Models
**Files:** `presentation/quiz/QuizViewModel.kt` (lines 15-80)

```kotlin
data class QuizQuestion(
    val id: String = UUID.randomUUID().toString(),
    val question: String,
    val correctAnswer: Boolean,
    val explanation: String,
    val userAnswer: Boolean? = null
)

data class QuizSession(
    val id: String = UUID.randomUUID().toString(),
    val questions: List<QuizQuestion>,
    val sourceText: String,
    val startTime: Long = System.currentTimeMillis(),
    val endTime: Long? = null
)

data class QuizResults(
    val session: QuizSession,
    val totalTimeSpent: Double,
    val incorrectQuestions: List<QuizQuestion>
)
```

**Maps to SDK:** Structured output format expected from SDK JSON generation

---

### ViewModel State Objects

#### ChatUiState
```kotlin
data class ChatUiState(
    val messages: List<ChatMessage> = emptyList(),
    val isGenerating: Boolean = false,
    val isModelLoaded: Boolean = false,
    val loadedModelName: String? = null,
    val currentInput: String = "",
    val error: Throwable? = null,
    val useStreaming: Boolean = true,
    val currentConversation: Conversation? = null
)
```

---

#### QuizUiState
```kotlin
data class QuizUiState(
    val viewState: QuizViewState = QuizViewState.INPUT,
    val inputText: String = "",
    val currentQuestionIndex: Int = 0,
    val isModelLoaded: Boolean = false,
    val dragOffset: Float = 0f,
    val swipeDirection: SwipeDirection = SwipeDirection.NONE,
    val error: String? = null,
    val showGenerationProgress: Boolean = false,
    val generationText: String = ""
)
```

---

#### ModelManagementUiState
```kotlin
data class ModelManagementUiState(
    val selectedFramework: LLMFramework? = null,
    val expandedFramework: LLMFramework? = null,
    val selectedModel: ModelInfo? = null,
    val selectedModelForDetails: ModelInfo? = null,
    val downloadingModels: Set<String> = emptySet(),
    val loadingModel: String? = null,
    val isRefreshing: Boolean = false,
    val showAddModelDialog: Boolean = false,
    val message: String? = null,
    val error: String? = null
)
```

---

### Repository Pattern Usage

**ModelRepository** (`ai/models/repository/ModelRepository.kt`, 377 lines)

**Responsibilities:**
- Centralize model data access
- Provide reactive Flows for UI
- Abstract SDK operations
- Handle business logic

**Key Methods:**
```kotlin
val availableModels: StateFlow<List<ModelInfo>>
val currentModel: StateFlow<ModelInfo?>
val downloadProgress: StateFlow<Map<String, Float>>
val isLoading: StateFlow<Boolean>

suspend fun refreshModels()
suspend fun downloadModel(modelId: String): Flow<Float>
suspend fun loadModel(modelId: String)
suspend fun deleteModel(modelId: String)
suspend fun getStorageInfo(): StorageInfo
suspend fun clearCache()
```

---

### Persistence Layer

**Status:** ❌ Not implemented

**Room Database:**
- Dependency included: `androidx.room.runtime`, `androidx.room.ktx`
- Kapt processor commented out
- No Room entities or DAOs defined
- Could be used for:
  - Conversation history
  - Model cache metadata
  - User preferences
  - Analytics storage

**DataStore:**
- Not currently used
- Could replace SharedPreferences for settings

**SharedPreferences:**
- Not actively used in current codebase

---

## 7. UI Components & Design

### Material Design 3 Implementation

**Theme:** Material 3 with dynamic color support

**File:** `ui/theme/Theme.kt` (58 lines)

```kotlin
@Composable
fun RunAnywhereAITheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
)
```

**Dynamic Color:**
- ✅ Enabled on Android 12+ (API 31+)
- Adapts to user's wallpaper colors
- Falls back to default light/dark schemes on older Android

---

### Color Scheme

**File:** `ui/theme/Color.kt` (11 lines)

```kotlin
val Purple80 = Color(0xFFD0BCFF)
val PurpleGrey80 = Color(0xFFCCC2DC)
val Pink80 = Color(0xFFEFB8C8)

val Purple40 = Color(0xFF6650a4)
val PurpleGrey40 = Color(0xFF625b71)
val Pink40 = Color(0xFF7D5260)
```

**Usage:**
- Light theme uses Purple40, PurpleGrey40, Pink40
- Dark theme uses Purple80, PurpleGrey80, Pink80
- Material3 default color schemes applied

---

### Typography

**File:** `ui/theme/Type.kt` (34 lines)

```kotlin
val Typography = Typography(
    bodyLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.5.sp
    )
    // ... other text styles
)
```

---

### Custom Composables

#### MessageBubble
**File:** `presentation/chat/ChatScreen.kt` (lines 100-126)

**Features:**
- User messages: Blue background, right-aligned
- Assistant messages: Gray background, left-aligned
- Card elevation and rounded corners
- Max width constraint (280.dp)
- Padding for readability

---

#### ModelRow
**File:** `ai/models/ui/ModelsScreen.kt` (lines 443-585)

**Features:**
- Expandable model card
- Model name with weight-based emphasis
- Chip badges for size, format, thinking support
- Action button (Download/Load/Delete/Cancel)
- Download progress indicator
- Selected model highlight (blue border, primary container color)
- Click to show details dialog

---

#### QuizCard
**File:** `presentation/quiz/QuizScreen.kt` (lines 392-469)

**Features:**
- Swipeable with drag gestures
- Rotation animation based on drag offset
- Scale animation for depth effect
- Color transition (red for False, blue for True)
- Question text centered
- Swipe indicators (X and checkmark icons)

---

#### AudioWaveform
**File:** `presentation/voice/VoiceAssistantScreen.kt` (lines 400-424)

**Features:**
- Horizontal progress bar style
- Animated fill based on audio level
- Rounded corners
- Primary color with transparency
- Smooth transitions (100ms animation)

---

#### MicrophoneButton
**File:** `presentation/voice/VoiceAssistantScreen.kt` (lines 427-468)

**Features:**
- Large FAB (80.dp)
- Dynamic icon based on session state
- Color changes (error, primary, secondary, surface variant)
- Spring bounce animation when listening
- Scale animation (1.0 → 1.1 when active)

---

### Design System Consistency

**Component Library:**
- ✅ Material 3 components throughout
- ✅ Consistent spacing (4dp, 8dp, 12dp, 16dp, 24dp)
- ✅ Standard elevation (cards at 8.dp)
- ✅ Icon sizes (16.dp, 24.dp, 32.dp, 48.dp, 64.dp, 80.dp)

**Color Usage:**
- ✅ Semantic colors (primary, secondary, error, surface)
- ✅ Contrast-safe text colors (onPrimary, onSurface)
- ✅ Alpha transparency for disabled/subtle elements

**Typography:**
- ✅ Material 3 text styles (headline, title, body, label)
- ✅ Consistent font weights (Normal, Medium, SemiBold, Bold)

---

## 8. Testing & Quality

### Unit Tests

**File:** `app/src/test/java/com/runanywhere/runanywhereai/ExampleUnitTest.kt`

**Status:** ⚠️ Only example test present

```kotlin
@Test
fun addition_isCorrect() {
    assertEquals(4, 2 + 2)
}
```

**Missing Tests:**
- ❌ ViewModel logic tests
- ❌ Repository tests
- ❌ Model parsing tests
- ❌ Analytics calculation tests
- ❌ State machine tests (quiz, voice)

---

### Instrumented Tests

**File:** `app/src/androidTest/java/com/runanywhere/runanywhereai/ExampleInstrumentedTest.kt`

**Status:** ⚠️ Only example test present

```kotlin
@Test
fun useAppContext() {
    val appContext = InstrumentationRegistry.getInstrumentation().targetContext
    assertEquals("com.runanywhere.runanywhereai.debug", appContext.packageName)
}
```

**Missing Tests:**
- ❌ UI tests (Compose Testing)
- ❌ Navigation tests
- ❌ Integration tests
- ❌ Database tests (when Room is implemented)

---

### Test Coverage

**Estimated Coverage:** <5%

**Coverage Report:** Not generated

**Recommended:**
- Use JaCoCo for coverage reports
- Target 70%+ coverage for critical paths
- Focus on ViewModels and Repository first

---

### Code Quality Tools

**Detekt:**
```kotlin
// app/build.gradle.kts
plugins {
    alias(libs.plugins.detekt)
}

detekt {
    config.setFrom("${project.rootDir}/detekt.yml")
}
```

**Configuration Files:**
- `detekt.yml` (8,065 bytes)
- `detekt-config.yml` (2,532 bytes)

**Lint:**
```kotlin
lint {
    abortOnError = true
    checkDependencies = true
    warningsAsErrors = false
    baseline = file("lint-baseline.xml")
    lintConfig = file("lint.xml")
}
```

**Disabled Checks:**
- OldTargetApi
- ExpiredTargetSdkVersion
- NewApi

---

## 9. Dependencies

### SDK Dependencies

```kotlin
// Kotlin Multiplatform SDK (local project)
implementation(project(":sdk:runanywhere-kotlin"))
```

---

### AndroidX Libraries

```kotlin
// Core
implementation(libs.androidx.core.ktx)
implementation(libs.androidx.appcompat)
implementation(libs.androidx.lifecycle.runtime.ktx)
implementation(libs.androidx.lifecycle.viewmodel.compose)
implementation(libs.androidx.activity.compose)

// Compose
implementation(platform(libs.androidx.compose.bom))
implementation(libs.androidx.ui)
implementation(libs.androidx.ui.graphics)
implementation(libs.androidx.ui.tooling.preview)
implementation(libs.androidx.material3)
implementation(libs.androidx.material.icons.extended)

// Navigation
implementation(libs.androidx.navigation.compose)

// Background work
implementation(libs.androidx.work.runtime.ktx)

// Room (for future use)
implementation(libs.androidx.room.runtime)
implementation(libs.androidx.room.ktx)

// Security
implementation(libs.androidx.security.crypto)
```

---

### Kotlin Libraries

```kotlin
// Coroutines
implementation(libs.kotlinx.coroutines.core)
implementation(libs.kotlinx.coroutines.android)

// Serialization
implementation(libs.kotlinx.serialization.json)

// DateTime
implementation(libs.kotlinx.datetime)
```

---

### Networking

```kotlin
implementation(libs.okhttp)
implementation(libs.okhttp.logging)
implementation(libs.retrofit)
implementation(libs.retrofit.gson)
implementation(libs.gson)
```

---

### Audio/Voice

```kotlin
// STT & VAD
implementation(libs.whisper.jni)
implementation(libs.android.vad.webrtc)

// Download manager
implementation(libs.prdownloader)
```

---

### UI/UX

```kotlin
// Material Design
implementation(libs.material)

// Permissions
implementation(libs.accompanist.permissions)
```

---

### Utilities

```kotlin
implementation(libs.commons.io)
implementation(libs.timber)  // Logging
```

---

### Testing

```kotlin
testImplementation(libs.junit)
testImplementation(libs.kotlinx.coroutines.test)
testImplementation(libs.mockk)

androidTestImplementation(libs.androidx.junit)
androidTestImplementation(libs.androidx.espresso.core)
androidTestImplementation(platform(libs.androidx.compose.bom))
androidTestImplementation(libs.androidx.ui.test.junit4)

debugImplementation(libs.androidx.ui.tooling)
debugImplementation(libs.androidx.ui.test.manifest)
```

---

### Dependency Injection

**Status:** ❌ Commented out

```kotlin
// Hilt (commented out, awaiting configuration)
// implementation(libs.hilt.android)
// kapt(libs.hilt.android.compiler)
// implementation(libs.hilt.navigation.compose)
```

**Current Approach:**
- Manual ViewModel creation
- No DI framework
- Services created in ViewModels or Application

---

## 10. Build & Configuration

### Build Variants

#### Debug Build
```kotlin
debug {
    isDebuggable = true
    isMinifyEnabled = false
    isShrinkResources = false
    applicationIdSuffix = ".debug"
    versionNameSuffix = "-debug"
    buildConfigField("boolean", "DEBUG_MODE", "true")
    buildConfigField("String", "BUILD_TYPE", "\"debug\"")
}
```

**Outputs:** `com.runanywhere.runanywhereai.debug`

---

#### Release Build
```kotlin
release {
    isDebuggable = false
    isMinifyEnabled = true
    isShrinkResources = true
    proguardFiles(
        getDefaultProguardFile("proguard-android-optimize.txt"),
        "proguard-rules.pro"
    )
    buildConfigField("boolean", "DEBUG_MODE", "false")
    buildConfigField("String", "BUILD_TYPE", "\"release\"")
}
```

**Outputs:** `com.runanywhere.runanywhereai`

---

#### Benchmark Build
```kotlin
create("benchmark") {
    initWith(getByName("release"))
    matchingFallbacks += listOf("release")
    isDebuggable = false
    buildConfigField("boolean", "BENCHMARK_MODE", "true")
    applicationIdSuffix = ".benchmark"
    versionNameSuffix = "-benchmark"
}
```

**Outputs:** `com.runanywhere.runanywhereai.benchmark`

---

### Configuration Files

**Status:** ❌ None present

**Expected (from iOS):**
- `dev.json` - Development environment
- `staging.json` - Staging environment
- `prod.json` - Production environment

**Current:**
- Hardcoded values in `RunAnywhereApplication.kt`

---

### Environment Handling

**Environments:**
- `SDKEnvironment.DEVELOPMENT` (used)
- `SDKEnvironment.STAGING` (available)
- `SDKEnvironment.PRODUCTION` (available)

**Current Setup:**
```kotlin
RunAnywhere.initialize(
    apiKey = "demo-api-key",
    baseURL = "https://api.runanywhere.ai",
    environment = SDKEnvironment.DEVELOPMENT
)
```

---

### Application ID

**Package:** `com.runanywhere.runanywhereai`

**Variants:**
- Debug: `com.runanywhere.runanywhereai.debug`
- Release: `com.runanywhere.runanywhereai`
- Benchmark: `com.runanywhere.runanywhereai.benchmark`

---

### App Permissions

**AndroidManifest.xml:**
```xml
<!-- STT and LLM functionality -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />

<!-- Storage (legacy) -->
<uses-permission
    android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="28" />

<!-- Storage (Android 13+) -->
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
<uses-permission
    android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
```

**Runtime Permissions:**
- `RECORD_AUDIO` - Requested in Voice Assistant screen

---

### ProGuard/R8 Configuration

**Status:** Default configuration only

**File:** `proguard-rules.pro`

**Needs:**
- Keep rules for SDK classes
- Keep rules for model serialization
- Obfuscation exceptions

---

### Build Scripts

**build_and_install.sh:**
```bash
#!/bin/bash
./gradlew installDebug
```

**build-simple.sh:**
```bash
#!/bin/bash
./gradlew build
```

---

## 11. Comparison with iOS App

### Feature Parity Matrix

| Feature | iOS Status | Android Status | Notes |
|---------|-----------|----------------|-------|
| **Chat Interface** | ✅ Fully Working | ⚠️ Partial | UI complete, SDK placeholders |
| **Streaming Generation** | ✅ Fully Working | ⚠️ Partial | UI ready, SDK method placeholder |
| **Thinking Mode** | ✅ Fully Working | ⚠️ Partial | Parsing logic present, untested |
| **Model Management** | ✅ Fully Working | ✅ Fully Working | Complete implementation |
| **Model Download** | ✅ Fully Working | ✅ Fully Working | Progress tracking works |
| **Quiz Generation** | ✅ Fully Working | ⚠️ Partial | UI complete, SDK placeholder |
| **Swipeable Cards** | ✅ Fully Working | ✅ Fully Working | Android gestures work |
| **Voice Assistant** | ✅ Fully Working | ❌ Crashes | Service initialization fails |
| **VAD Pipeline** | ✅ Fully Working | ❌ Not Working | - |
| **STT Pipeline** | ✅ Fully Working | ❌ Not Working | - |
| **TTS Output** | ✅ Fully Working | ⚠️ Service Ready | AndroidTTSService exists but untested |
| **Settings Screen** | ✅ Fully Working | ❌ Placeholder | - |
| **Analytics Tracking** | ✅ Fully Working | ✅ Fully Working | Comprehensive metrics |
| **Conversation History** | ✅ Fully Working | ❌ Not Persisted | No Room DB implementation |
| **Message Markdown** | ✅ Fully Working | ❌ Not Implemented | Plain text only |
| **Code Highlighting** | ✅ Fully Working | ❌ Not Implemented | - |
| **Benchmark Tab** | ✅ Fully Working | ❌ Not Present | Android has no benchmark screen |

---

### Architecture Differences

| Aspect | iOS | Android |
|--------|-----|---------|
| **Language** | Swift | Kotlin |
| **UI Framework** | SwiftUI | Jetpack Compose |
| **State Management** | @StateObject, @Published | StateFlow, MutableStateFlow |
| **DI Framework** | Manual/ServiceContainer | None (Hilt commented out) |
| **Navigation** | NavigationStack | Compose Navigation |
| **Async** | async/await | Coroutines with suspend |
| **Persistence** | Not shown in doc | Room (declared but unused) |
| **SDK** | RunAnywhere Swift SDK | RunAnywhere KMP SDK |

---

### Code Organization Comparison

**iOS Structure:**
```
RunAnywhereAI/
├── Views/
│   ├── ChatView.swift
│   ├── ModelsView.swift
│   ├── QuizView.swift
│   └── VoiceAssistantView.swift
├── ViewModels/
│   ├── ChatViewModel.swift
│   └── QuizViewModel.swift
├── Models/
│   └── Message.swift
└── Services/
    └── ModelManager.swift
```

**Android Structure:**
```
com.runanywhere.runanywhereai/
├── presentation/
│   ├── chat/
│   │   ├── ChatScreen.kt
│   │   ├── ChatViewModel.kt
│   │   └── components/
│   ├── quiz/
│   ├── voice/
│   ├── settings/
│   └── navigation/
├── domain/
│   ├── models/
│   ├── model/
│   └── services/
└── ui/
    └── theme/
```

**Observations:**
- Android more modular (feature-based packages)
- iOS flatter structure
- Both follow MVVM pattern

---

### UI Component Comparison

| Component | iOS | Android |
|-----------|-----|---------|
| **Message Bubble** | Custom View | Card with Row layout |
| **Model List** | List with sections | LazyColumn with expandable cards |
| **Quiz Cards** | SwiftUI gestures | Compose pointerInput + drag |
| **Voice Button** | Button with states | FloatingActionButton with animation |
| **Navigation** | TabView | BottomNavigationBar |

---

### Known Issues (Android Specific)

1. **Voice Pipeline Crashes**
   - Service initialization fails
   - Documented in SAMPLE-APPS-TODOS.md
   - Blocks entire voice feature

2. **SDK Method Placeholders**
   - `RunAnywhere.generateStream()` returns `flowOf("Sample response")`
   - `RunAnywhere.generate()` returns `"Sample response"`
   - Blocks chat and quiz functionality

3. **No Dependency Injection**
   - Hilt commented out
   - Manual ViewModel creation
   - Harder to test

4. **No Persistence**
   - Room declared but unused
   - Conversation history lost on app close

5. **Settings Not Implemented**
   - Placeholder screen only
   - No configuration options

---

### Lines of Code Comparison

**Android App Total:** ~7,204 lines of Kotlin

**Major Files:**
- `ModelsScreen.kt`: 690 lines
- `QuizScreen.kt`: 700 lines
- `ChatViewModel.kt`: 504 lines
- `QuizViewModel.kt`: 526 lines
- `VoiceAssistantScreen.kt`: 480 lines
- `ModelRepository.kt`: 377 lines

**iOS App:** (Estimate from README, no exact count provided)

---

### Strengths of Android App

1. ✅ **Complete Model Management UI** - Best-in-class model browsing and download
2. ✅ **Framework Categorization** - Clear grouping by LlamaCpp, ONNX, etc.
3. ✅ **Comprehensive Quiz UI** - Beautiful swipeable cards with animations
4. ✅ **Analytics Tracking** - Detailed performance metrics
5. ✅ **Material Design 3** - Modern, adaptive design
6. ✅ **Device Info Display** - Helpful system information

---

### Weaknesses of Android App

1. ❌ **Voice Feature Broken** - Critical feature doesn't work
2. ❌ **SDK Placeholders** - Core SDK methods not implemented
3. ⚠️ **No Tests** - <5% test coverage
4. ⚠️ **No Persistence** - Data lost on app restart
5. ⚠️ **Settings Placeholder** - No configuration UI
6. ⚠️ **No Markdown Rendering** - Chat messages are plain text
7. ⚠️ **No Benchmark Screen** - Missing from iOS feature set

---

## Summary

The **RunAnywhereAI Android sample app** is an **impressively comprehensive demonstration** of the Kotlin Multiplatform SDK, with a **beautifully designed UI** that matches or exceeds the iOS app in visual polish. However, it suffers from **critical SDK integration gaps** that prevent core features from functioning.

### Overall Status: ⚠️ **Visual Prototype Stage**

**What Works:**
- ✅ Complete model management (download, load, delete)
- ✅ Beautiful swipeable quiz interface
- ✅ Analytics tracking infrastructure
- ✅ Navigation and state management
- ✅ Material Design 3 theming

**What Doesn't Work:**
- ❌ Chat generation (SDK placeholder)
- ❌ Quiz generation (SDK placeholder)
- ❌ Voice assistant (service crashes)
- ❌ Settings configuration
- ❌ Data persistence

**Recommendation:**
1. Implement KMP SDK methods: `generateStream()`, `generate()`
2. Fix voice pipeline service initialization crash
3. Add Room database for conversation history
4. Implement settings screen
5. Add unit and UI tests
6. Consider Markdown rendering for chat

**Architecture Rating:** ⭐⭐⭐⭐ (4/5)
- Excellent MVVM structure
- Clean separation of concerns
- Room for improvement in testing and DI

**UI/UX Rating:** ⭐⭐⭐⭐⭐ (5/5)
- Outstanding Material Design 3 implementation
- Smooth animations and gestures
- Intuitive navigation

**Functionality Rating:** ⭐⭐ (2/5)
- Beautiful shell, limited working features
- Needs SDK completion to be functional

---

**End of Documentation**
