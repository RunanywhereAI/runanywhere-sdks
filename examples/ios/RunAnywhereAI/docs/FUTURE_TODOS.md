# Future TODOs

## Table of Contents
1. [SDK Context Management](#sdk-context-management) - **Priority: High** 🔄
2. [SDK Template/Prompt Format Support](#sdk-templateprompt-format-support) - **Priority: Medium**
3. [FluidAudio Model Download Integration](#fluidaudio-model-download-integration) - **Priority: Medium** 🎙️

---

## SDK Context Management

**Priority: High** 🔄

Currently the app manages its own conversation state and builds full prompts. This should be moved to SDK-managed context for better separation of concerns.

**Current State:**
- App uses `ChatMessage.buildConversationPrompt()` to create conversation history
- SDK receives a single prompt string with embedded conversation context
- No use of SDK's `Context` and `Message` types

**Target State:**
- App converts `ChatMessage` → SDK `Message` objects
- App builds SDK `Context` objects with proper message history
- SDK's `ContextManager.prepareContext()` handles conversation management
- Better support for context truncation, memory management, and different model context windows

**Technical Requirements:**
1. Fix SDK's `Message` type export so it's accessible as `RunAnywhereSDK.Message`
2. Add conversion method `ChatMessage.toSDKMessage()` → SDK `Message`
3. Update `ChatViewModel.buildContext()` to create proper SDK `Context` objects
4. Remove `ChatMessage.buildConversationPrompt()` method
5. Test context management works properly with SDK

**Files to Update:**
- `ChatViewModel.swift` - Use SDK Context instead of conversation prompts
- `ChatMessage.swift` - Add conversion to SDK Message types
- SDK: Fix Message type exports in module interface

**Benefits:**
- Cleaner separation of concerns
- SDK can optimize context handling
- Standardized conversation management across all SDK clients
- Better support for advanced features (context truncation, token counting, etc.)

---

## SDK Template/Prompt Format Support

**Priority: Medium**

Move template determination from LLMSwiftService to SDK level for better abstraction:

- Add `ChatTemplateType` enum to ModelInfo (chatML, alpaca, llama, mistral, gemma)
- Add `PromptFormat` enum for general prompt structures (instruction, completion, chat, few-shot)
- Implement template detection in ModelDiscoveryService
- Store template info in model metadata during registration
- Update LLMService protocol to accept template configuration
- Map SDK template types to framework-specific formats in adapters

**Benefits:** Centralized template logic, consistent across frameworks, better abstraction.

---

## FluidAudio Model Download Integration

**Priority: Medium** 🎙️

Integrate FluidAudio's speaker diarization model downloads into SDK's unified model management system.

**Current State:**
- FluidAudio downloads its own models (~100MB from HuggingFace)
- Stored in `~/Library/Application Support/FluidAudio/Models/`
- Separate from SDK's model management

**Target State:**
- Register FluidAudio models in SDK's `ModelRegistry`
- Use SDK's `DownloadManager` for unified progress tracking
- Store in SDK location: `Documents/RunAnywhere/Models/FluidAudio/`

**Implementation Phases:**

1. **Register Models** - Add FluidAudio models to ModelRegistry
2. **Download Strategy** - Create `FluidAudioDownloadStrategy` wrapping FluidAudio's downloader
3. **Storage Migration** - Move models to SDK's unified location
4. **Update Integration** - Modify `FluidAudioDiarization` to use SDK paths

**Files to Create:**
- `FluidAudioDownloadStrategy.swift` - Download strategy implementation
- `FluidAudioModelRegistry.swift` - Model registration
- `FluidAudioMigration.swift` - Storage migration logic

**Benefits:** Unified model management, consistent UX, single progress indicator, better error handling.
