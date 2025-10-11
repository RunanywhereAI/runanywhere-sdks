# iOS Sample App - Comprehensive Documentation

## Table of Contents
1. [App Overview](#app-overview)
2. [UI/UX Structure](#uiux-structure)
3. [Feature Implementation](#feature-implementation)
4. [SDK Integration Points](#sdk-integration-points)
5. [Navigation Structure](#navigation-structure)
6. [Data Models](#data-models)
7. [UI Components & Design](#ui-components--design)
8. [Testing & Quality](#testing--quality)
9. [Dependencies](#dependencies)
10. [Build & Configuration](#build--configuration)
11. [File Structure](#file-structure)

---

## App Overview

### Purpose
RunAnywhere iOS Sample App is a comprehensive demonstration of the RunAnywhere SDK's on-device AI capabilities, showcasing text generation, voice AI workflows, model management, and structured output generation features.

### Target Audience
- Developers learning to integrate the RunAnywhere SDK
- Users wanting to experience on-device AI capabilities
- Developers exploring LLM integration patterns on iOS

### iOS Version Requirements
- **Minimum**: iOS 15.0
- **Recommended**: iOS 17.0+ for full feature support
- **Foundation Models**: iOS 26.0+ (experimental)
- **macOS Support**: macOS 12.0+ for development, macOS 26.0+ for Foundation Models

### Architecture Pattern
**MVVM (Model-View-ViewModel)** with the following characteristics:
- SwiftUI-based declarative UI
- ObservableObject ViewModels for state management
- Centralized service layer (ModelManager, ConversationStore, DeviceInfoService)
- Design System with consistent spacing, typography, and colors
- Reactive data flow with Combine framework
- Singleton pattern for shared services

### Key Features List
1. **Chat Interface** - Interactive AI conversations with streaming responses
2. **Model Management** - Browse, download, and manage AI models
3. **Storage Management** - Track storage usage and manage model cache
4. **Quiz Generator** - Generate educational quizzes using structured output
5. **Voice Assistant** - Real-time voice conversations (experimental)
6. **Settings** - Configure SDK behavior and generation parameters
7. **Analytics** - Track performance metrics and generation statistics

---

## UI/UX Structure

### Screen 1: Chat Interface
**File:** `/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/ChatInterfaceView.swift` (1328 lines)

**Purpose:** Primary chat interface for conversational AI interactions with streaming responses

**UI Elements:**
- Navigation bar with conversation list button (left) and model selection/details buttons (right)
- Model info bar showing currently loaded model (collapsible)
- ScrollView with message bubbles (user and assistant messages)
- Empty state view with brain icon and instructions
- Message input area with text field and send button
- Typing indicator animation during generation
- Message bubbles with markdown rendering and code highlighting
- Analytics display showing tokens/second, TTFT, and model info

**SDK Integration:**
- Uses `RunAnywhere.generate()` for text generation with streaming
- Streams responses via AsyncSequence
- Handles generation interruption with `RunAnywhere.cancelGeneration()`
- Model status checking via `RunAnywhere.currentModel`
- Analytics data from generation metadata

**User Flow:**
1. User opens chat tab
2. If no model loaded, prompted to select model
3. User types message in input field
4. Tap send button to generate response
5. Watch real-time streaming response with analytics
6. Can interrupt generation at any time
7. Access conversation history via list button
8. View detailed analytics via details button

**Platform Differences:**
- **iOS**: Uses NavigationView with inline title
- **macOS**: Custom toolbar, no NavigationView, larger window layout

**Status:** ✅ Fully functional with streaming, analytics, and conversation history

---

### Screen 2: Storage Management
**File:** `/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Storage/StorageView.swift` (542 lines)

**Purpose:** Manage downloaded models, track storage usage, and clear caches

**UI Elements:**
- Storage overview card with total/available/used storage
- Storage usage breakdown (models, cache, documents)
- Visual storage bar chart
- Downloaded models list with size, framework, and delete buttons
- Cache management section with clear cache button
- Refresh button to update storage info
- Warning indicators for low storage

**SDK Integration:**
- Uses `RunAnywhere.getStorageInfo()` for storage metrics
- Lists models via `RunAnywhere.listAvailableModels()`
- Deletes models via `RunAnywhere.deleteModel()`
- Clears cache via `RunAnywhere.clearCache()`

**User Flow:**
1. User opens storage tab
2. View storage breakdown and usage
3. See all downloaded models with sizes
4. Delete unwanted models to free space
5. Clear cache if needed
6. Refresh to see updated storage info

**Platform Differences:**
- **iOS**: List-based layout with sections
- **macOS**: Card-based layout with more spacing, no List

**Status:** ✅ Fully functional with real-time storage tracking

---

### Screen 3: Settings
**File:** `/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Settings/SimplifiedSettingsView.swift` (401 lines)

**Purpose:** Configure SDK behavior, generation parameters, and app preferences

**UI Elements:**
- SDK Configuration section:
  - Routing Policy picker (Automatic, Device Only, Prefer Device, Prefer Cloud)
- Generation Settings section:
  - Temperature slider (0.0 - 2.0)
  - Max Tokens stepper (500 - 20,000)
- API Configuration section:
  - API Key display (masked)
  - Change API Key button
- Analytics section:
  - Toggle for local logging
  - Export analytics button
- App Info section:
  - Version number
  - Build number
  - SDK version
  - Environment indicator (Dev/Prod)

**SDK Integration:**
- Routing policy applied per-request via `GenerationOptions`
- Default parameters stored in UserDefaults
- API key managed via KeychainService
- SDK environment from `RunAnywhere.getCurrentEnvironment()`

**User Flow:**
1. User opens settings tab
2. Adjust routing policy for device/cloud preference
3. Configure default temperature and token limits
4. View or change API key
5. Enable/disable analytics logging
6. View app and SDK version info

**Platform Differences:**
- **iOS**: Form-based layout with native pickers
- **macOS**: Custom card layout with segmented controls, wider spacing

**Status:** ✅ Fully functional with persistent settings

---

### Screen 4: Quiz Generator
**File:** `/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Quiz/QuizView.swift` (166 lines)

**Purpose:** Generate educational quizzes using AI with structured JSON output

**UI Elements:**
- Input view (`QuizInputView.swift` - 220 lines):
  - Topic text field
  - Difficulty picker (Easy, Medium, Hard)
  - Number of questions stepper
  - Generate button
  - Model selection button in toolbar
- Generation progress overlay (`GenerationProgressView.swift` - 108 lines):
  - Animated progress indicator
  - Generation status text
  - Cancel button
- Swipe view (`QuizSwipeView.swift` - 203 lines):
  - Tinder-style card swiping interface
  - Question cards with True/False options
  - Swipe right for True, left for False
  - Progress indicator (X of Y questions)
  - Card animation and gestures
- Results view (`QuizResultsView.swift` - 272 lines):
  - Score summary (correct/total)
  - Percentage and emoji feedback
  - Detailed question review with explanations
  - Time spent per question
  - Restart or new quiz buttons

**SDK Integration:**
- Uses `RunAnywhere.generateStructuredOutput()` with `QuizGeneration` type
- Implements `Generatable` protocol for JSON schema
- Schema validation for structured output
- JSON parsing with error handling

**User Flow:**
1. User opens quiz tab
2. Enter topic (e.g., "Swift Programming")
3. Select difficulty level
4. Choose number of questions
5. Tap generate - see progress overlay
6. Swipe through quiz cards (right=true, left=false)
7. View results with score and explanations
8. Review wrong answers
9. Start new quiz or restart

**Platform Differences:**
- **iOS**: Full NavigationView, larger card animations
- **macOS**: Custom toolbar, window-based layout

**Status:** ✅ Fully functional with structured output generation

**Sub-Components:**
- `QuizCardView.swift` (98 lines) - Individual quiz card with animations
- `QuizViewModel.swift` (545 lines) - State management, generation logic
- Supports cancellation during generation
- Real-time progress updates

---

### Screen 5: Voice Assistant (Experimental)
**File:** `/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Voice/VoiceAssistantView.swift` (555 lines)

**Purpose:** Real-time voice conversations with AI using speech-to-text, LLM, and text-to-speech

**UI Elements:**
- Model info section (collapsible):
  - LLM model badge (blue)
  - STT model badge (green)
  - TTS model badge (purple)
  - "Experimental Feature" warning
- Conversation area:
  - User transcript bubble
  - Assistant response bubble
  - Typing indicator during processing
- Voice control panel:
  - Large microphone button (tap to talk)
  - Stop button during listening
  - Status indicator (listening, processing, speaking)
  - Waveform animation during voice input
- Transcription mode button (switch to transcription-only view)

**SDK Integration:**
- Uses `ModularVoicePipeline` for full voice workflow
- WhisperKit integration for STT via `RunAnywhere.transcribe()`
- LLM generation via `RunAnywhere.generate()`
- System TTS for voice output via AVSpeechSynthesizer
- Audio capture via `AudioCapture` service
- VAD (Voice Activity Detection) for automatic speech detection

**User Flow:**
1. User opens voice tab
2. Grant microphone permission if needed
3. System initializes voice pipeline (STT model auto-loads)
4. Tap microphone button to start listening
5. Speak naturally - see live transcription
6. Speech detected and transcribed via Whisper
7. Transcription sent to LLM for response
8. Assistant speaks response using TTS
9. Full conversation history displayed
10. Can interrupt at any time

**Platform Differences:**
- **iOS**: Larger microphone button, better mobile UX
- **macOS**: Custom toolbar, window-based controls

**Status:** ⚠️ Experimental - STT and LLM working, TTS integration experimental

**Related Files:**
- `VoiceAssistantViewModel.swift` (397 lines) - Voice pipeline state management
- `TranscriptionView.swift` (558 lines) - Transcription-only mode
- `TranscriptionViewModel.swift` (359 lines) - Transcription state
- `FluidAudioIntegration.swift` (54 lines) - FluidAudio diarization integration
- `AudioCapture.swift` (290 lines) - Microphone capture service

---

### Screen 6: Model Management (Accessible via Chat)
**File:** `/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Models/SimplifiedModelsView.swift` (423 lines)

**Purpose:** Browse, download, and manage AI models from various frameworks

**UI Elements:**
- Device status section:
  - Device model name
  - Chip name (e.g., A17 Pro, M3)
  - Total/available memory
  - Neural Engine indicator
- Available frameworks section:
  - LLMSwift (llama.cpp/GGUF)
  - WhisperKit (Speech-to-Text)
  - Foundation Models (iOS 26+)
  - Framework expansion disclosure
- Models list (per framework):
  - Model name and size
  - Download status indicator
  - Download/Cancel/Load buttons
  - Progress bar during download
  - Delete button for downloaded models
- Add Model button (toolbar):
  - Opens URL-based model import sheet

**SDK Integration:**
- Lists frameworks via `RunAnywhere.getAvailableFrameworks()`
- Lists models via `RunAnywhere.listAvailableModels()`
- Downloads models via `RunAnywhere.downloadModel()`
- Loads models via `RunAnywhere.loadModel()`
- Deletes models via `RunAnywhere.deleteModel()`
- Model registration in development mode via `RunAnywhere.registerFrameworkAdapter()`

**User Flow:**
1. User taps model selection in chat
2. View available frameworks (LLMSwift, WhisperKit, Foundation)
3. Expand framework to see models
4. Check device compatibility (memory, chip)
5. Tap download for desired model
6. Monitor download progress
7. Once downloaded, tap Load
8. Model loads and becomes active
9. Return to chat to use model
10. Can delete models to free space

**Platform Differences:**
- Both iOS and macOS use NavigationView
- macOS has larger spacing and card-based layout

**Status:** ✅ Fully functional with real-time download progress

**Sub-Components:**
- `ModelSelectionSheet.swift` (554 lines) - Model picker sheet for chat
- `ModelListViewModel.swift` (134 lines) - Model list state management
- `ModelComponents.swift` (74 lines) - Reusable model UI components
- `AddModelFromURLView.swift` (199 lines) - Import models via URL

---

### Supporting Views

#### Conversation Management
**File:** `ChatInterfaceView.swift` (inline views)
- **ConversationListView**: Browse past conversations
- **ConversationBubble**: Individual conversation item
- **ChatDetailsView**: View conversation metadata and analytics

#### Model Selection
**File:** `ModelSelectionSheet.swift` (554 lines)
- Model picker sheet with framework grouping
- Shows model status (downloaded, available, loading)
- Memory requirement warnings
- Download size indicators

---

## Feature Implementation

### Feature 1: Text Generation (Chat)

**Feature Name:** Interactive AI Chat with Streaming

**Related View Files:**
- `ChatInterfaceView.swift` (1328 lines) - Main chat UI
- `MessageBubbleView.swift` (inline) - Message display

**Related ViewModel Files:**
- `ChatViewModel.swift` (1051 lines) - Chat state and generation logic

**SDK Integration Points:**
```swift
// Initialize SDK (in RunAnywhereAIApp.swift)
try RunAnywhere.initialize(
    apiKey: "dev",
    baseURL: "localhost",
    environment: .development
)

// Generate response with streaming
for try await update in RunAnywhere.generate(prompt, options: options) {
    // Handle streaming token
    currentMessage += update.delta
}

// Cancel generation
RunAnywhere.cancelGeneration()

// Get current model
let model = RunAnywhere.currentModel
```

**How It Uses SDK:**
1. Checks if model is loaded via `RunAnywhere.currentModel`
2. Builds prompt from conversation history
3. Creates `GenerationOptions` with temperature, max tokens
4. Calls `RunAnywhere.generate()` with streaming
5. Iterates async sequence for real-time updates
6. Updates UI on each token delta
7. Handles completion metadata (tokens, timing)
8. Supports cancellation during generation

**User Flow:**
1. User selects model (if not already loaded)
2. Types message in input field
3. Taps send button
4. ViewModel creates message object
5. Adds to conversation history
6. Calls SDK generate with streaming
7. UI updates in real-time as tokens arrive
8. Shows analytics (tokens/sec, TTFT)
9. Saves conversation to ConversationStore
10. Can start new message or conversation

**Status:** ✅ Fully Working - Streaming, analytics, history all functional

---

### Feature 2: Model Management

**Feature Name:** Download, Load, and Manage AI Models

**Related View Files:**
- `SimplifiedModelsView.swift` (423 lines) - Main models browser
- `ModelSelectionSheet.swift` (554 lines) - Model picker
- `AddModelFromURLView.swift` (199 lines) - URL import
- `ModelComponents.swift` (74 lines) - Reusable UI components

**Related ViewModel Files:**
- `ModelListViewModel.swift` (134 lines) - Model list state

**SDK Integration Points:**
```swift
// Register framework with models (in RunAnywhereAIApp.swift)
try await RunAnywhere.registerFrameworkAdapter(
    LLMSwiftAdapter(),
    models: [
        ModelRegistration(
            url: "https://huggingface.co/...",
            framework: .llamaCpp,
            id: "smollm2-360m-q8-0",
            name: "SmolLM2 360M Q8_0",
            memoryRequirement: 500_000_000
        )
    ]
)

// List available models
let models = try await RunAnywhere.listAvailableModels()

// Download model
try await RunAnywhere.downloadModel(modelId)

// Load model
try await RunAnywhere.loadModel(modelId)

// Unload model
try await RunAnywhere.unloadModel()

// Delete model
try await RunAnywhere.deleteModel(modelId)
```

**How It Uses SDK:**
1. App startup registers adapters (LLMSwift, WhisperKit, Foundation)
2. Provides custom model URLs in development mode
3. Lists available frameworks via `getAvailableFrameworks()`
4. Lists models per framework via `listAvailableModels()`
5. Downloads models on-demand with progress tracking
6. Loads models into memory when selected
7. Unloads models when switching or closing
8. Deletes models to free storage

**User Flow:**
1. User navigates to model selection
2. Views available frameworks
3. Expands framework to see models
4. Checks model size and memory requirements
5. Taps download for desired model
6. Monitors progress bar (0-100%)
7. Once downloaded, taps Load
8. Model loads (shows loading indicator)
9. Returns to chat with loaded model
10. Can unload or delete models as needed

**Status:** ✅ Fully Working - Download, load, unload, delete all functional

---

### Feature 3: Quiz Generation (Structured Output)

**Feature Name:** Generate Educational Quizzes with Structured JSON

**Related View Files:**
- `QuizView.swift` (166 lines) - Main quiz container
- `QuizInputView.swift` (220 lines) - Topic input
- `QuizSwipeView.swift` (203 lines) - Swipe cards
- `QuizResultsView.swift` (272 lines) - Results display
- `QuizCardView.swift` (98 lines) - Individual card
- `GenerationProgressView.swift` (108 lines) - Progress overlay

**Related ViewModel Files:**
- `QuizViewModel.swift` (545 lines) - Quiz generation and state

**SDK Integration Points:**
```swift
// Define structured output type
struct QuizGeneration: Codable, Generatable {
    let questions: [QuizQuestion]
    let topic: String
    let difficulty: String

    static var jsonSchema: String {
        // JSON schema definition
    }

    static var generationHints: GenerationHints? {
        GenerationHints(
            temperature: 0.7,
            maxTokens: 1500,
            systemRole: "educational quiz generator"
        )
    }
}

// Generate structured output
let quiz = try await RunAnywhere.generateStructuredOutput(
    type: QuizGeneration.self,
    prompt: "Generate \(count) \(difficulty) questions about \(topic)"
)
```

**How It Uses SDK:**
1. User inputs topic, difficulty, count
2. ViewModel builds prompt from inputs
3. Calls `generateStructuredOutput()` with `QuizGeneration` type
4. SDK validates against JSON schema
5. Returns parsed `QuizGeneration` object
6. ViewModel creates quiz session
7. UI displays swipeable cards
8. Tracks user answers and timing
9. Calculates score and results

**User Flow:**
1. User enters topic (e.g., "World History")
2. Selects difficulty (Easy/Medium/Hard)
3. Chooses question count (5-20)
4. Taps Generate Quiz
5. Sees progress overlay with status
6. Quiz cards appear after generation
7. Swipes right for True, left for False
8. Progress indicator shows X of Y
9. After all questions, views results
10. Sees score, time, explanations
11. Can restart or generate new quiz

**Status:** ✅ Fully Working - Structured output, swipe UI, results all functional

---

### Feature 4: Voice Assistant (Experimental)

**Feature Name:** Real-time Voice Conversations with AI

**Related View Files:**
- `VoiceAssistantView.swift` (555 lines) - Main voice UI
- `TranscriptionView.swift` (558 lines) - Transcription-only mode

**Related ViewModel Files:**
- `VoiceAssistantViewModel.swift` (397 lines) - Voice pipeline state
- `TranscriptionViewModel.swift` (359 lines) - Transcription state

**SDK Integration Points:**
```swift
// Create voice pipeline
let pipeline = ModularVoicePipeline(
    sttModelName: "whisper-base",
    llmService: currentLLMService,
    ttsService: systemTTS
)

// Start listening
await pipeline.startListening()

// Subscribe to transcription updates
for await transcript in pipeline.transcriptionStream {
    // Update UI with transcript
}

// Subscribe to assistant responses
for await response in pipeline.responseStream {
    // Update UI with response
    // Trigger TTS
}

// Stop pipeline
await pipeline.stop()
```

**How It Uses SDK:**
1. Requests microphone permission
2. Loads Whisper model for STT
3. Creates ModularVoicePipeline
4. User taps microphone to start
5. Captures audio via AudioCapture
6. Sends to WhisperKit via SDK
7. Transcription appears in real-time
8. Sends transcript to LLM via SDK
9. LLM generates response
10. TTS speaks response
11. Full conversation shown in UI

**User Flow:**
1. User opens Voice tab
2. Grants microphone permission
3. Views model info (STT, LLM, TTS)
4. Taps microphone button
5. Speaks naturally
6. Sees live transcription
7. Speech ends (VAD or manual stop)
8. Assistant processes (shows typing)
9. Hears spoken response
10. Sees text response in chat
11. Can interrupt or continue

**Status:** ⚠️ Experimental
- STT (WhisperKit) - ✅ Working
- LLM Generation - ✅ Working
- TTS Integration - ⚠️ Experimental
- Full Pipeline - ⚠️ In Testing

---

### Feature 5: Storage Management

**Feature Name:** Track and Manage Model Storage

**Related View Files:**
- `StorageView.swift` (542 lines) - Main storage UI

**Related ViewModel Files:**
- `StorageViewModel.swift` (73 lines) - Storage state

**SDK Integration Points:**
```swift
// Get storage info
let storageInfo = try await RunAnywhere.getStorageInfo()
// Returns: totalStorage, usedStorage, availableStorage, modelStorage

// List stored models
let models = try await RunAnywhere.listAvailableModels()
let downloadedModels = models.filter { $0.localPath != nil }

// Delete model
try await RunAnywhere.deleteModel(modelId)

// Clear cache
try await RunAnywhere.clearCache()
```

**How It Uses SDK:**
1. Loads storage info from SDK
2. Displays total/used/available
3. Shows breakdown by category
4. Lists downloaded models with sizes
5. Allows deletion of models
6. Allows clearing cache
7. Refreshes data on-demand

**User Flow:**
1. User opens Storage tab
2. Views storage breakdown
3. Sees all downloaded models
4. Taps delete on unwanted model
5. Confirms deletion
6. Storage updates automatically
7. Can clear cache if needed
8. Tap refresh for latest data

**Status:** ✅ Fully Working - All storage operations functional

---

### Feature 6: Settings & Configuration

**Feature Name:** Configure SDK and Generation Parameters

**Related View Files:**
- `SimplifiedSettingsView.swift` (401 lines) - Settings UI

**SDK Integration Points:**
```swift
// Get current environment
let env = RunAnywhere.getCurrentEnvironment()

// Settings are applied per-request via GenerationOptions:
let options = GenerationOptions(
    temperature: userDefaultTemperature,
    maxTokens: userDefaultMaxTokens,
    routingPolicy: userRoutingPolicy,
    stream: true
)

// API key management via KeychainService
KeychainService.shared.saveApiKey(apiKey)
```

**How It Uses SDK:**
1. Displays current environment (dev/prod)
2. Shows SDK version info
3. Allows routing policy selection
4. Stores default temperature/tokens in UserDefaults
5. Applied to each generation request
6. API key saved to Keychain
7. Analytics toggle for local logging

**User Flow:**
1. User opens Settings tab
2. Views current configuration
3. Adjusts routing policy
4. Sets default temperature
5. Sets default max tokens
6. Changes API key if needed
7. Toggles analytics logging
8. Settings persist across app launches

**Status:** ✅ Fully Working - All settings save and apply correctly

---

## SDK Integration Points

### Main Integration File
**File:** `/Users/sanchitmonga/development/ODLM/sdks.worktree/android_init/examples/ios/RunAnywhereAI/RunAnywhereAI/App/RunAnywhereAIApp.swift` (387 lines)

### SDK Initialization

Located in `RunAnywhereAIApp.swift` - `initializeSDK()` method (lines 66-139)

```swift
import RunAnywhere
import LLMSwift
import WhisperKitTranscription
import FluidAudioDiarization

// Determine environment
#if DEBUG
let environment = SDKEnvironment.development
#else
let environment = SDKEnvironment.production
#endif

// Initialize SDK
try RunAnywhere.initialize(
    apiKey: "dev",  // In dev mode, any string works
    baseURL: "localhost",  // Not used in dev
    environment: .development
)
```

**Initialization Flow:**
1. App launches → `RunAnywhereAIApp.swift` @main struct
2. Shows `InitializationLoadingView` during setup
3. Calls `initializeSDK()` in `.task` modifier
4. Determines environment (DEBUG = dev, RELEASE = prod)
5. Initializes RunAnywhere SDK
6. Registers framework adapters (LLMSwift, WhisperKit, Foundation)
7. Registers custom models in dev mode
8. Sets `isSDKInitialized = true`
9. Displays `ContentView` when ready
10. Shows `InitializationErrorView` if failure

**Initialization Time:** Logged as ~50-200ms (fast lazy initialization)

---

### Configuration Management

**Files:**
- `RunAnywhereAIApp.swift` - Environment-based config
- `SimplifiedSettingsView.swift` - User preferences
- `KeychainService.swift` (71 lines) - Secure API key storage

**Development Mode:**
```swift
// No API key required in dev mode
try RunAnywhere.initialize(
    apiKey: "dev",
    baseURL: "localhost",
    environment: .development
)

// Register adapters WITH custom models
await registerAdaptersForDevelopment()
```

**Production Mode:**
```swift
// Real API key required
let apiKey = KeychainService.shared.getApiKey() ?? "testing_api_key"
try RunAnywhere.initialize(
    apiKey: apiKey,
    baseURL: "https://api.runanywhere.ai",
    environment: .production
)

// Register adapters WITHOUT custom models
// Models come from backend console
await registerAdaptersForProduction()
```

**Configuration Options:**
- Routing Policy: `.automatic`, `.deviceOnly`, `.preferDevice`, `.preferCloud`
- Temperature: 0.0 - 2.0 (default 0.7)
- Max Tokens: 500 - 20,000 (default 10,000)
- Streaming: true/false
- System Role: Custom system prompts

---

### API Key Handling

**File:** `KeychainService.swift` (71 lines)

```swift
class KeychainService {
    static let shared = KeychainService()

    func saveApiKey(_ apiKey: String) throws {
        // Save to iOS Keychain
    }

    func getApiKey() -> String? {
        // Retrieve from Keychain
    }

    func deleteApiKey() throws {
        // Remove from Keychain
    }
}
```

**Security:**
- API keys stored in iOS Keychain (secure)
- Not stored in UserDefaults or plain text
- Masked in UI (shows "••••••••")
- Only accessed when needed for SDK init

---

### Model Management Integration

**Files:**
- `ModelManager.swift` (86 lines) - Model lifecycle service
- `ModelListViewModel.swift` (134 lines) - UI state

**Model Registration (Development Mode):**
```swift
// Register LLMSwift with custom GGUF models
try await RunAnywhere.registerFrameworkAdapter(
    LLMSwiftAdapter(),
    models: [
        // SmolLM2 360M - smallest and fastest
        ModelRegistration(
            url: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
            framework: .llamaCpp,
            id: "smollm2-360m-q8-0",
            name: "SmolLM2 360M Q8_0",
            memoryRequirement: 500_000_000
        ),
        // Qwen 2.5 0.5B
        ModelRegistration(
            url: "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
            framework: .llamaCpp,
            id: "qwen-2.5-0.5b-instruct-q6-k",
            name: "Qwen 2.5 0.5B Instruct Q6_K",
            memoryRequirement: 600_000_000
        ),
        // ... more models
    ],
    options: AdapterRegistrationOptions(
        validateModels: false,
        autoDownloadInDev: false,  // Lazy loading
        showProgress: true,
        fallbackToMockModels: true
    )
)

// Register WhisperKit with custom models
try await RunAnywhere.registerFrameworkAdapter(
    WhisperKitAdapter.shared,
    models: [
        ModelRegistration(
            url: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-tiny.en",
            framework: .whisperKit,
            id: "whisper-tiny",
            name: "Whisper Tiny",
            format: .mlmodel,
            memoryRequirement: 39_000_000
        ),
        ModelRegistration(
            url: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-base",
            framework: .whisperKit,
            id: "whisper-base",
            name: "Whisper Base",
            format: .mlmodel,
            memoryRequirement: 74_000_000
        )
    ]
)
```

**Registered Models in Development:**
1. **LLMSwift (llama.cpp/GGUF):**
   - SmolLM2 360M Q8_0 (~500MB)
   - Qwen 2.5 0.5B Q6_K (~600MB)
   - Llama 3.2 1B Q6_K (~1.2GB)
   - SmolLM2 1.7B Q6_K_L (~1.8GB)
   - Qwen 2.5 1.5B Q6_K (~1.6GB)
   - LiquidAI LFM2 350M Q4_K_M (~250MB)
   - LiquidAI LFM2 350M Q8_0 (~400MB)

2. **WhisperKit (Speech-to-Text):**
   - Whisper Tiny (~39MB)
   - Whisper Base (~74MB)

3. **Foundation Models (iOS 26+):**
   - System-provided models (no download required)

**Model Operations:**
```swift
// List available models
let models = try await RunAnywhere.listAvailableModels()

// Download model
try await RunAnywhere.downloadModel("smollm2-360m-q8-0")

// Load model
try await RunAnywhere.loadModel("smollm2-360m-q8-0")

// Get current model
let currentModel = RunAnywhere.currentModel

// Unload model
try await RunAnywhere.unloadModel()

// Delete model
try await RunAnywhere.deleteModel("smollm2-360m-q8-0")
```

---

### Text Generation Integration

**File:** `ChatViewModel.swift` (1051 lines)

**Streaming Generation:**
```swift
// Create generation options
let options = GenerationOptions(
    temperature: 0.7,
    maxTokens: 500,
    stream: true,
    routingPolicy: .deviceOnly
)

// Generate with streaming
var currentResponse = ""
for try await update in RunAnywhere.generate(prompt, options: options) {
    // Update.delta contains new tokens
    currentResponse += update.delta

    // Update UI in real-time
    await MainActor.run {
        self.currentMessage = currentResponse
    }

    // Handle metadata (tokens/sec, TTFT)
    if let metadata = update.metadata {
        self.tokensPerSecond = metadata.tokensPerSecond
        self.timeToFirstToken = metadata.timeToFirstToken
    }
}

// Handle completion
print("Generation complete. Total tokens: \(finalMetadata.totalTokens)")
```

**Non-Streaming Generation:**
```swift
let options = GenerationOptions(
    temperature: 0.7,
    maxTokens: 500,
    stream: false
)

let result = try await RunAnywhere.generate(prompt, options: options)
// result.text contains full response
// result.metadata contains analytics
```

**Cancellation:**
```swift
// Cancel ongoing generation
RunAnywhere.cancelGeneration()
```

---

### Voice Pipeline Integration

**Files:**
- `VoiceAssistantViewModel.swift` (397 lines)
- `TranscriptionViewModel.swift` (359 lines)
- `AudioCapture.swift` (290 lines)

**Voice Pipeline Setup:**
```swift
// Create modular voice pipeline
let pipeline = ModularVoicePipeline(
    sttModelName: "whisper-base",
    llmService: currentLLMService,
    ttsService: systemTTSService
)

// Start listening
await pipeline.startListening()

// Subscribe to transcription updates
Task {
    for await transcript in pipeline.transcriptionStream {
        await MainActor.run {
            self.currentTranscript = transcript
        }
    }
}

// Subscribe to LLM responses
Task {
    for await response in pipeline.responseStream {
        await MainActor.run {
            self.assistantResponse = response
        }
        // Trigger TTS
        await speakResponse(response)
    }
}

// Stop pipeline
await pipeline.stop()
```

**Speech-to-Text Only:**
```swift
// Transcription-only mode (no LLM or TTS)
let audioData = await captureAudioChunk()

for try await transcription in RunAnywhere.transcribe(audioData) {
    // Update transcript in real-time
    await MainActor.run {
        self.transcript += transcription.text
    }
}
```

---

### Error Handling Patterns

**Error Types:**
```swift
// SDK errors
do {
    try await RunAnywhere.loadModel(modelId)
} catch SDKError.modelNotFound {
    // Model not available
} catch SDKError.insufficientMemory {
    // Not enough RAM
} catch SDKError.downloadFailed(let reason) {
    // Download error
} catch {
    // Generic error
}
```

**UI Error Handling:**
```swift
@Published var errorMessage: String?

func handleError(_ error: Error) {
    await MainActor.run {
        self.errorMessage = error.localizedDescription
    }
}

// In View
.alert("Error", isPresented: $showError) {
    Button("OK") { }
} message: {
    Text(viewModel.errorMessage ?? "Unknown error")
}
```

**Retry Logic:**
```swift
// Retry initialization on failure
Button("Retry") {
    Task {
        await retryInitialization()
    }
}
```

---

## Navigation Structure

### Pattern: TabView with 5 Tabs

**File:** `ContentView.swift` (68 lines)

```swift
TabView(selection: $selectedTab) {
    // Tab 0: Chat
    ChatInterfaceView()
        .tabItem {
            Label("Chat", systemImage: "message")
        }
        .tag(0)

    // Tab 1: Storage
    StorageView()
        .tabItem {
            Label("Storage", systemImage: "externaldrive")
        }
        .tag(1)

    // Tab 2: Settings
    SimplifiedSettingsView()
        .tabItem {
            Label("Settings", systemImage: "gear")
        }
        .tag(2)

    // Tab 3: Quiz
    QuizView()
        .tabItem {
            Label("Quiz", systemImage: "questionmark.circle")
        }
        .tag(3)

    // Tab 4: Voice
    VoiceAssistantView()
        .tabItem {
            Label("Voice", systemImage: "mic")
        }
        .tag(4)
}
```

### Tab Structure

| Tab # | Name | Icon | Screen |
|-------|------|------|--------|
| 0 | Chat | message | ChatInterfaceView |
| 1 | Storage | externaldrive | StorageView |
| 2 | Settings | gear | SimplifiedSettingsView |
| 3 | Quiz | questionmark.circle | QuizView |
| 4 | Voice | mic | VoiceAssistantView |

### Deep Linking Support

**None currently implemented** - Could be added via:
- Universal Links
- Custom URL schemes
- UserActivity (Handoff)

### State Management Across Screens

**Shared State Objects:**
- `ModelManager.shared` - Global model state (ObservableObject)
- `ConversationStore.shared` - Global conversation history
- `DeviceInfoService.shared` - Device information
- `StorageViewModel` - Storage tracking

**Environment Objects:**
```swift
@main
struct RunAnywhereAIApp: App {
    @StateObject private var modelManager = ModelManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(modelManager)
        }
    }
}
```

**Cross-Tab Communication:**
- NotificationCenter for model loading events
- Shared singletons for global state
- @Published properties trigger UI updates across views

---

## Data Models

### App-Specific Models

**File:** `AppTypes.swift` (50 lines)

```swift
struct SystemDeviceInfo {
    let modelName: String          // "iPhone 15 Pro"
    let chipName: String            // "A17 Pro"
    let totalMemory: Int64          // Bytes
    let availableMemory: Int64      // Bytes
    let neuralEngineAvailable: Bool
    let osVersion: String           // "iOS 17.0"
    let appVersion: String          // "1.0.0"
}
```

### SDK Models (from RunAnywhere SDK)

**ModelInfo:**
```swift
public struct ModelInfo {
    public let id: String
    public let name: String
    public let framework: LLMFramework
    public let format: ModelFormat
    public let size: Int64
    public let memoryRequirement: Int64
    public let localPath: String?
    public let downloadURL: String?
}
```

**Message:**
```swift
public struct Message: Identifiable, Codable {
    public let id: UUID
    public let role: MessageRole  // .user, .assistant, .system
    public var content: String
    public let timestamp: Date
}
```

**Conversation:**
```swift
struct Conversation: Identifiable, Codable {
    let id: String
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [Message]
    var modelName: String?
    var frameworkName: String?
}
```

**GenerationOptions:**
```swift
public struct GenerationOptions {
    public var temperature: Double = 0.7
    public var maxTokens: Int = 500
    public var stream: Bool = true
    public var routingPolicy: RoutingPolicy = .automatic
    public var systemPrompt: String?
}
```

**LLMFramework (Enum):**
```swift
public enum LLMFramework: String, Codable {
    case llamaCpp = "llama.cpp"
    case whisperKit = "WhisperKit"
    case foundationModels = "Foundation Models"
}
```

### Analytics Models

**File:** `ChatViewModel.swift` (lines 13-99)

```swift
struct MessageAnalytics: Codable {
    let messageId: String
    let conversationId: String
    let modelId: String
    let modelName: String
    let framework: String
    let timestamp: Date

    // Timing
    let timeToFirstToken: TimeInterval?
    let totalGenerationTime: TimeInterval
    let thinkingTime: TimeInterval?
    let responseTime: TimeInterval?

    // Tokens
    let inputTokens: Int
    let outputTokens: Int
    let thinkingTokens: Int?
    let responseTokens: Int
    let averageTokensPerSecond: Double

    // Quality
    let messageLength: Int
    let wasThinkingMode: Bool
    let wasInterrupted: Bool
    let retryCount: Int
    let completionStatus: CompletionStatus

    enum CompletionStatus: String, Codable {
        case complete
        case interrupted
        case failed
        case timeout
    }
}

struct ConversationAnalytics: Codable {
    let conversationId: String
    let startTime: Date
    let endTime: Date?
    let messageCount: Int

    let averageTTFT: TimeInterval
    let averageGenerationSpeed: Double
    let totalTokensUsed: Int
    let modelsUsed: Set<String>

    let thinkingModeUsage: Double
    let completionRate: Double
    let averageMessageLength: Int
}
```

### Quiz Models

**File:** `QuizViewModel.swift` (lines 31-99)

```swift
struct QuizGeneration: Codable, Generatable {
    let questions: [QuizQuestion]
    let topic: String
    let difficulty: String

    static var jsonSchema: String { /* JSON schema */ }
    static var generationHints: GenerationHints? { /* hints */ }
}

struct QuizQuestion: Codable, Identifiable {
    let id: String
    let question: String
    let correctAnswer: Bool
    let explanation: String
}

struct QuizAnswer: Identifiable {
    let id = UUID()
    let questionId: String
    let userAnswer: Bool
    let isCorrect: Bool
    let timeSpent: TimeInterval
}

struct QuizSession {
    let id = UUID()
    let generatedQuiz: QuizGeneration
    var answers: [QuizAnswer]
    let startTime: Date
    var endTime: Date?

    var isComplete: Bool
    var score: Int
    var percentage: Double
}
```

### State Management Objects

**Persistence:**
- `ConversationStore` - Saves conversations to JSON files in Documents directory
- `KeychainService` - Saves API keys to iOS Keychain
- `UserDefaults` - Saves user preferences (temperature, max tokens, routing policy)

**In-Memory State:**
- `@StateObject` ViewModels for screen state
- `@Published` properties for reactive updates
- Singleton services (`ModelManager.shared`, `ConversationStore.shared`)

---

## UI Components & Design

### Design System

**Files:**
- `AppColors.swift` (94 lines) - Color palette
- `AppSpacing.swift` (116 lines) - Spacing constants
- `Typography.swift` (63 lines) - Text styles

### Colors (AppColors.swift)

```swift
// Semantic Colors
static let primaryAccent = Color.accentColor
static let primaryBlue = Color.blue
static let primaryGreen = Color.green
static let primaryRed = Color.red
static let primaryOrange = Color.orange

// Text Colors
static let textPrimary = Color.primary
static let textSecondary = Color.secondary
static let textWhite = Color.white

// Background Colors (platform-specific)
#if os(iOS)
static let backgroundPrimary = Color(.systemBackground)
static let backgroundSecondary = Color(.secondarySystemBackground)
static let backgroundGrouped = Color(.systemGroupedBackground)
#else
static let backgroundPrimary = Color(NSColor.windowBackgroundColor)
static let backgroundSecondary = Color(NSColor.controlBackgroundColor)
#endif

// Component Colors
static let cardBackground = backgroundSecondary
static let overlayLight = Color.black.opacity(0.3)
static let overlayDark = Color.black.opacity(0.7)
```

### Spacing (AppSpacing.swift)

```swift
// Base spacing scale
static let xxSmall: CGFloat = 2
static let xSmall: CGFloat = 4
static let small: CGFloat = 8
static let smallMedium: CGFloat = 10
static let medium: CGFloat = 12
static let padding15: CGFloat = 15
static let large: CGFloat = 16
static let xLarge: CGFloat = 20
static let xxLarge: CGFloat = 24
static let xxxLarge: CGFloat = 32

// Corner radius
static let cornerRadiusSmall: CGFloat = 8
static let cornerRadiusMedium: CGFloat = 12
static let cornerRadiusLarge: CGFloat = 16
static let cornerRadiusXLarge: CGFloat = 20

// Layout
static let maxContentWidth: CGFloat = 700
static let maxContentWidthLarge: CGFloat = 900
```

### Typography (Typography.swift)

```swift
// Headings
static let largeTitleBold = Font.largeTitle.bold()
static let title = Font.title
static let title2 = Font.title2
static let title2Semibold = Font.title2.weight(.semibold)
static let headline = Font.headline

// Body
static let body = Font.body
static let bodyMedium = Font.body.weight(.medium)
static let subheadline = Font.subheadline
static let callout = Font.callout

// Small
static let footnote = Font.footnote
static let caption = Font.caption
static let caption2 = Font.caption2

// Special
static let monospaced = Font.system(.body, design: .monospaced)
static let system60 = Font.system(size: 60)
```

### Reusable Components

**MessageBubbleView** (inline in ChatInterfaceView):
- User/assistant message bubbles
- Different colors per role
- Markdown rendering support
- Code syntax highlighting
- Timestamp display

**ModelBadge** (inline in VoiceAssistantView):
- Colored badge showing model info
- Icon, label, and value
- Used for STT/LLM/TTS indicators

**TypingIndicatorView** (inline in ChatInterfaceView):
- Animated dots during generation
- Bounce animation

**GenerationProgressView** (108 lines):
- Overlay during quiz generation
- Animated progress indicator
- Status text
- Cancel button

**QuizCardView** (98 lines):
- Swipeable card for quiz questions
- Gesture-based interaction
- Rotation and translation animations
- True/False indicators

**ConversationBubble** (inline in VoiceAssistantView):
- Voice chat message bubble
- Speaker label (You/Assistant)
- User vs assistant styling

### Platform-Specific Adaptations

**iOS-specific:**
- Uses `UIKit` types (UIColor, UIFont)
- NavigationView with inline title display
- List-based layouts
- Smaller spacing
- Tab bar at bottom

**macOS-specific:**
- Uses `AppKit` types (NSColor, NSFont)
- Custom toolbars instead of NavigationView
- Card-based layouts with more spacing
- Larger window constraints
- Window toolbar styling

**Conditional Compilation:**
```swift
#if os(iOS)
// iOS-specific code
#else
// macOS-specific code
#endif
```

---

## Testing & Quality

### Unit Tests

**File:** `RunAnywhereAITests/` directory
- Currently minimal test coverage
- Test target exists in Xcode project
- No significant unit tests written yet

**Status:** ❌ Unit tests not implemented

### UI Tests

**File:** `RunAnywhereAIUITests/RunAnywhereAIUITestsLaunchTests.swift`
- Launch test exists
- Tests app launches successfully
- No comprehensive UI tests

**Status:** ⚠️ Minimal UI tests (launch only)

### Test Coverage

**Overall Coverage:** ~5% (estimated)
- App initialization: ✅ Tested manually
- SDK integration: ✅ Tested via app usage
- UI flows: ⚠️ Manual testing only
- Edge cases: ❌ Not covered
- Error handling: ⚠️ Partially tested

### Code Quality Tools

**SwiftLint:**
- Configuration: `.swiftlint.yml` (2506 bytes)
- Script: `swiftlint.sh` (290 bytes)
- Enforces Swift style guidelines
- Can auto-fix violations with `--fix`

**Pre-commit Hooks:**
- Located in repository root
- Runs SwiftLint on commit
- Ensures code quality before merge

### Logging

**Unified Logging (os.log):**
```swift
import os

private let logger = Logger(
    subsystem: "com.runanywhere.RunAnywhereAI",
    category: "ChatViewModel"
)

logger.info("Generating response...")
logger.error("Generation failed: \(error)")
logger.debug("Token count: \(tokens)")
```

**Subsystems:**
- `com.runanywhere.RunAnywhereAI` - Main app
- Categories: ChatViewModel, VoiceAssistant, ModelManager, etc.

**Viewing Logs:**
```bash
# iOS Simulator
log stream --predicate 'subsystem CONTAINS "com.runanywhere"' --info --debug

# Physical Device
idevicesyslog | grep "com.runanywhere"
```

---

## Dependencies

### Package Dependencies (Swift Package Manager)

**From project.pbxproj:**

1. **RunAnywhere** - Core SDK
   - Local package: `../../sdk/runanywhere-swift/`
   - On-device AI platform SDK

2. **LLMSwift** - Language Model Integration
   - Local package: `../../sdk/llm-swift/`
   - llama.cpp wrapper for GGUF models

3. **WhisperKitTranscription** - Speech-to-Text
   - Local package: `../../sdk/whisperkit-transcription/`
   - WhisperKit wrapper for voice transcription

4. **FluidAudioDiarization** - Speaker Diarization
   - GitHub: FluidAudio package
   - Speaker identification in audio

5. **Transformers** - ML Transformers
   - For model processing

6. **ZIPFoundation** - ZIP Archive Handling
   - Model download and extraction

7. **ExecuTorch** - On-device ML Inference
   - Multiple backends: CoreML, MPS, XNNPACK
   - Kernels: custom, optimized, quantized

8. **LLM** (from LLMSwift)
   - Language model interface

### CocoaPods Dependencies

**Note:** App uses SPM primarily, but CocoaPods for some legacy dependencies

**Podfile dependencies** (if present):
- TensorFlow Lite (for ML models)
- WhisperKit (for STT)

### SDK Version

**RunAnywhere SDK:**
- Version: 0.1.0 (estimated from development)
- Framework: Custom Swift Package
- Location: `../../sdk/runanywhere-swift/`

### External Frameworks

**System Frameworks:**
- SwiftUI - UI framework
- UIKit/AppKit - Platform UI
- AVFoundation - Audio/video
- Combine - Reactive programming
- os - Unified logging

**Third-Party:**
- llama.cpp (via LLMSwift) - GGUF model inference
- WhisperKit - Speech-to-text
- FluidAudio - Audio processing
- ExecuTorch - ML backends

---

## Build & Configuration

### Build Schemes

**Schemes in Xcode:**
1. **RunAnywhereAI** - Main app scheme
2. **RunAnywhereAITests** - Unit test scheme
3. **RunAnywhereAIUITests** - UI test scheme

### Configuration Files

**Build Configurations:**
- Debug (Development)
- Release (Production)

**Environment Detection:**
```swift
#if DEBUG
let environment = SDKEnvironment.development
#else
let environment = SDKEnvironment.production
#endif
```

### Environment Handling

**Development (DEBUG):**
- API key: "dev" (any string works)
- Base URL: "localhost" (not used)
- Custom model registration
- Lazy model loading
- Verbose logging

**Production (RELEASE):**
- API key: From Keychain (required)
- Base URL: "https://api.runanywhere.ai"
- Models from backend console
- Minimal logging

### Bundle Identifier

**From Xcode Project:**
- `com.runanywhere.RunAnywhereAI` (likely)
- Check: Product > Scheme > Edit Scheme > Info tab

### App Capabilities

**Required Permissions:**
1. **Microphone** - For voice assistant
   - NSMicrophoneUsageDescription in Info.plist
   - Requested at runtime before voice features

2. **Network** - For model downloads
   - Outgoing connections allowed

**iOS Entitlements:**
- None required for basic features
- May need for iCloud, Push Notifications (future)

### Build Scripts

**Located in `scripts/` directory:**

1. **build_and_run.sh** - Build and run app
   ```bash
   ./scripts/build_and_run.sh simulator "iPhone 16 Pro"
   ./scripts/build_and_run.sh device
   ```

2. **clean_build_and_run.sh** - Clean before build

3. **verify_urls.sh** - Verify model download URLs

4. **fix_pods_sandbox.sh** - Fix Xcode 16 sandbox issues

### Build Process

**Automated Build:**
```bash
# Install dependencies
pod install

# Fix Xcode 16 issues
./fix_pods_sandbox.sh

# Build and run
./scripts/build_and_run.sh simulator "iPhone 16 Pro"
```

**Manual Build:**
```bash
# Open workspace
open RunAnywhereAI.xcworkspace

# Build in Xcode (Cmd+B)
# Run (Cmd+R)
```

### Xcode Version Requirements

- **Xcode**: 15.0+ (16.0+ recommended)
- **Swift**: 5.9+
- **macOS**: 12.0+ for development
- **iOS Deployment Target**: 15.0

### Known Issues

**Xcode 16 Sandbox:**
- Error: `Sandbox: rsync deny(1) file-write-create`
- Fix: Run `./fix_pods_sandbox.sh` after `pod install`

**Swift Macro Fingerprint:**
- LLMSwift uses macros
- May need: `defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES`

**CocoaPods Resources:**
- rsync → cp replacement needed for Xcode 16

---

## File Structure

### Root Directory
```
examples/ios/RunAnywhereAI/
├── README.md (281 lines)
├── IOS_SAMPLE_APP_DOCUMENTATION.md (this file)
├── RunAnywhereAI.xcodeproj/
├── RunAnywhereAI/ (main app code)
├── RunAnywhereAITests/
├── RunAnywhereAIUITests/
├── scripts/
├── docs/
├── .swiftlint.yml
├── .gitignore
└── swiftlint.sh
```

### App Structure (RunAnywhereAI/)

```
RunAnywhereAI/
├── App/
│   ├── RunAnywhereAIApp.swift (387 lines) - App entry point
│   └── ContentView.swift (68 lines) - Tab container
│
├── Core/
│   ├── DesignSystem/
│   │   ├── AppColors.swift (94 lines)
│   │   ├── AppSpacing.swift (116 lines)
│   │   └── Typography.swift (63 lines)
│   │
│   ├── Models/
│   │   └── AppTypes.swift (50 lines)
│   │
│   ├── Services/
│   │   ├── ModelManager.swift (86 lines)
│   │   ├── ConversationStore.swift (392 lines)
│   │   ├── KeychainService.swift (71 lines)
│   │   ├── DeviceInfoService.swift (138 lines)
│   │   ├── Audio/
│   │   │   └── AudioCapture.swift (290 lines)
│   │   └── Foundation/
│   │       └── FoundationModelsAdapter.swift (299 lines)
│   │
│   └── Utilities/
│       └── Constants.swift (40 lines)
│
├── Features/
│   ├── Chat/
│   │   ├── ChatInterfaceView.swift (1328 lines)
│   │   └── ChatViewModel.swift (1051 lines)
│   │
│   ├── Models/
│   │   ├── SimplifiedModelsView.swift (423 lines)
│   │   ├── ModelSelectionSheet.swift (554 lines)
│   │   ├── ModelListViewModel.swift (134 lines)
│   │   ├── ModelComponents.swift (74 lines)
│   │   └── AddModelFromURLView.swift (199 lines)
│   │
│   ├── Storage/
│   │   ├── StorageView.swift (542 lines)
│   │   └── StorageViewModel.swift (73 lines)
│   │
│   ├── Settings/
│   │   └── SimplifiedSettingsView.swift (401 lines)
│   │
│   ├── Quiz/
│   │   ├── QuizView.swift (166 lines)
│   │   ├── QuizInputView.swift (220 lines)
│   │   ├── QuizSwipeView.swift (203 lines)
│   │   ├── QuizResultsView.swift (272 lines)
│   │   ├── QuizCardView.swift (98 lines)
│   │   ├── QuizViewModel.swift (545 lines)
│   │   └── GenerationProgressView.swift (108 lines)
│   │
│   ├── Voice/
│   │   ├── VoiceAssistantView.swift (555 lines)
│   │   ├── VoiceAssistantViewModel.swift (397 lines)
│   │   ├── TranscriptionView.swift (558 lines)
│   │   ├── TranscriptionViewModel.swift (359 lines)
│   │   └── FluidAudioIntegration.swift (54 lines)
│   │
│   └── CommandAssistant/ (empty/unused)
│
├── Helpers/
│   └── AdaptiveLayout.swift (237 lines)
│
├── Utilities/
│   └── KeychainHelper.swift (75 lines)
│
├── Assets.xcassets/
│   ├── AppIcon.appiconset/
│   └── AccentColor.colorset/
│
└── Resources/
```

### Total File Count

**Swift Files:** 37 files
**Total Lines:** ~9,000+ lines of Swift code (excluding tests and build files)

### Key Files by Size

| File | Lines | Purpose |
|------|-------|---------|
| ChatInterfaceView.swift | 1328 | Main chat UI |
| ChatViewModel.swift | 1051 | Chat logic |
| StorageView.swift | 542 | Storage management UI |
| QuizViewModel.swift | 545 | Quiz generation logic |
| VoiceAssistantView.swift | 555 | Voice UI |
| TranscriptionView.swift | 558 | Transcription UI |
| ModelSelectionSheet.swift | 554 | Model picker |
| SimplifiedModelsView.swift | 423 | Model browser |
| SimplifiedSettingsView.swift | 401 | Settings UI |
| RunAnywhereAIApp.swift | 387 | App initialization |
| VoiceAssistantViewModel.swift | 397 | Voice logic |
| ConversationStore.swift | 392 | Conversation persistence |

---

## Summary

### App Architecture

**Pattern:** MVVM (Model-View-ViewModel)
- Views: SwiftUI declarative UI
- ViewModels: ObservableObject with @Published state
- Models: Swift structs and SDK types
- Services: Singletons for shared state

### Key Strengths

1. ✅ **Comprehensive SDK Integration** - Demonstrates all major SDK features
2. ✅ **Real Streaming Support** - Live token-by-token updates
3. ✅ **Advanced Analytics** - Detailed performance metrics
4. ✅ **Structured Output** - JSON schema-based generation (Quiz)
5. ✅ **Voice Pipeline** - Full STT → LLM → TTS workflow
6. ✅ **Model Management** - Download, load, unload, delete
7. ✅ **Storage Tracking** - Real-time storage monitoring
8. ✅ **Design System** - Consistent colors, spacing, typography
9. ✅ **Cross-Platform** - iOS and macOS support
10. ✅ **Development Mode** - Easy local testing without API key

### Areas for Improvement

1. ❌ **Unit Test Coverage** - Minimal tests written
2. ⚠️ **UI Test Coverage** - Only launch tests
3. ⚠️ **Documentation** - Inline comments sparse
4. ⚠️ **Error Recovery** - Some error paths incomplete
5. ⚠️ **Accessibility** - VoiceOver support not verified
6. ⚠️ **Localization** - English only
7. ⚠️ **Offline Mode** - Network handling basic

### Feature Matrix

| Feature | iOS Status | macOS Status | Notes |
|---------|-----------|--------------|-------|
| Chat with Streaming | ✅ Working | ✅ Working | Full feature parity |
| Model Management | ✅ Working | ✅ Working | Download, load, delete |
| Storage Management | ✅ Working | ✅ Working | Real-time tracking |
| Quiz Generator | ✅ Working | ✅ Working | Structured output |
| Voice Assistant | ⚠️ Experimental | ⚠️ Experimental | STT+LLM working |
| Settings | ✅ Working | ✅ Working | Persistent config |
| Analytics | ✅ Working | ✅ Working | Detailed metrics |
| Conversation History | ✅ Working | ✅ Working | JSON persistence |

---

## Comparison Readiness

This documentation provides:
- ✅ Complete screen-by-screen breakdown
- ✅ SDK integration code examples
- ✅ User flow descriptions
- ✅ Feature status indicators
- ✅ File paths with line counts
- ✅ Architecture patterns
- ✅ Data models
- ✅ Dependencies list
- ✅ Build configuration

**Ready for comparison with Android app.**
