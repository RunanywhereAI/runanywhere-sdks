# React Native SDK Core Feasibility Analysis

## Overview

The React Native SDK at `sdk/runanywhere-react-native/` uses **Nitrogen/NitroModules (JSI-based)** for high-performance native bindings. It has a hybrid architecture with C++ for AI operations and Swift/Kotlin for platform utilities.

**SDK Statistics**:
- **Language**: TypeScript + C++ + Swift + Kotlin
- **Estimated Lines**: ~15,000 TS, ~500 C++, ~600 Swift/Kotlin
- **JSI Bridge**: Already implemented (Nitrogen-generated)
- **Portable Logic**: ~70%
- **Platform-Specific**: ~30%

---

## Current SDK Architecture

### Key Insight: Nitrogen/JSI is Already C++

The React Native SDK uses **Nitrogen** to generate JSI bindings. The main AI operations are already in C++ (`HybridRunAnywhere.cpp`), bridging to the same C API as Flutter.

### Directory Structure

```
src/
├── index.ts                       # Main SDK exports
├── Public/
│   ├── RunAnywhere.ts            # Main SDK singleton
│   ├── Errors/SDKError.ts
│   └── Events/EventBus.ts        # NativeEventEmitter wrapper
├── Core/
│   ├── ModuleRegistry.ts         # Plugin registry (TS)
│   ├── Components/BaseComponent.ts
│   └── Models/, Protocols/
├── components/                    # AI components (TS orchestration)
│   ├── LLM/, STT/, TTS/, VAD/
│   └── VoiceAgent/
├── Capabilities/                  # Cross-cutting capabilities
│   ├── Memory/, Routing/
│   └── TextGeneration/
├── Foundation/                    # Infrastructure (TS)
│   ├── DependencyInjection/
│   └── Logging/
├── native/                        # Native module access
│   └── NativeRunAnywhere.ts
├── specs/                         # Nitrogen spec files (TS interfaces)
│   ├── RunAnywhere.nitro.ts      # → Generates C++ bridge
│   ├── RunAnywhereFileSystem.nitro.ts → Swift/Kotlin
│   └── RunAnywhereDeviceInfo.nitro.ts → Swift/Kotlin
└── services/, Data/, Providers/

cpp/
├── HybridRunAnywhere.hpp          # C++ JSI hybrid object (main AI)
├── HybridRunAnywhere.cpp          # Implementation
└── include/
    └── runanywhere_bridge.h       # C API header

ios/
├── HybridRunAnywhereFileSystem.swift   # FileSystem (Swift)
├── HybridRunAnywhereDeviceInfo.swift   # DeviceInfo (Swift)
└── AudioDecoder.m                      # Audio conversion (ObjC)

android/
└── src/main/java/com/margelo/nitro/runanywhere/
    ├── HybridRunAnywhereFileSystem.kt  # FileSystem (Kotlin)
    └── HybridRunAnywhereDeviceInfo.kt  # DeviceInfo (Kotlin)
```

### Nitrogen Architecture

```
TypeScript Spec (.nitro.ts) → Nitrogen CLI → Generated Bindings
                                              ├── C++ bridges
                                              ├── Swift bindings
                                              └── Kotlin bindings
```

**RunAnywhere.nitro.ts** (iOS: C++, Android: C++):
```typescript
export interface RunAnywhere extends HybridObject<{ ios: 'c++'; android: 'c++' }> {
  createBackend(name: string): Promise<boolean>;
  loadTextModel(path: string, config?: string): Promise<boolean>;
  generate(prompt: string, options?: string): Promise<string>;
  generateStream(prompt: string, options: string, callback: (token: string, done: boolean) => void): Promise<void>;
  // ... more methods
}
```

**RunAnywhereFileSystem.nitro.ts** (iOS: Swift, Android: Kotlin):
```typescript
export interface RunAnywhereFileSystem extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  getModelsDirectory(): Promise<string>;
  downloadModel(modelId: string, url: string, callback?: (progress: number) => void): Promise<string>;
  // ... more methods
}
```

---

## Component Analysis Table

| Component / Module | Location | Move to Core? | Current Status | Proposed Core API | FFI Frequency | Est. Effort |
|-------------------|----------|---------------|----------------|-------------------|---------------|-------------|
| **RunAnywhere (TS)** | `src/Public/RunAnywhere.ts` | HYBRID | TS wrapper | Entry point stays | LOW | S |
| **HybridRunAnywhere.cpp** | `cpp/HybridRunAnywhere.cpp` | **ALREADY C++** | Calls C API | Expand C API | LOW | - |
| **ModuleRegistry** | `src/Core/ModuleRegistry.ts` | YES | TypeScript | `ra_module_*()` | LOW | M |
| **ServiceContainer** | `src/Foundation/DependencyInjection/ServiceContainer.ts` | YES | TypeScript | `ra_service_*()` | LOW | M |
| **EventBus** | `src/Public/Events/EventBus.ts` | HYBRID | NativeEventEmitter | `ra_event_*()` | LOW | M |
| **LLMComponent** | `src/components/LLM/LLMComponent.ts` | YES | TS orchestration | `ra_llm_component_*()` | LOW | M |
| **STTComponent** | `src/components/STT/STTComponent.ts` | YES | TS orchestration | `ra_stt_component_*()` | LOW | M |
| **TTSComponent** | `src/components/TTS/TTSComponent.ts` | YES | TS orchestration | `ra_tts_component_*()` | LOW | M |
| **VADComponent** | `src/components/VAD/VADComponent.ts` | YES | TS orchestration | `ra_vad_component_*()` | LOW | S |
| **VoiceAgentComponent** | `src/components/VoiceAgent/` | YES | TS orchestration | `ra_voice_agent_*()` | LOW | L |
| **MemoryService** | `src/Capabilities/Memory/` | YES | TypeScript | `ra_memory_*()` | LOW | M |
| **RoutingService** | `src/Capabilities/Routing/` | YES | TypeScript | `ra_routing_*()` | LOW | M |
| **GenerationService** | `src/Capabilities/TextGeneration/` | YES | TypeScript | Part of LLM API | LOW | M |
| **HybridRunAnywhereFileSystem** | `ios/`, `android/` | NO | Swift/Kotlin | Platform I/O | LOW | - |
| **HybridRunAnywhereDeviceInfo** | `ios/`, `android/` | NO | Swift/Kotlin | Platform info | LOW | - |
| **AudioDecoder** | `ios/AudioDecoder.m` | NO | Obj-C | Platform audio | LOW | - |
| **Nitrogen specs** | `src/specs/` | GENERATE | Interface defs | N/A | N/A | - |

---

## Detailed Component Analysis

### 1. HybridRunAnywhere.cpp - The Existing C++ Bridge

**Location**: `cpp/HybridRunAnywhere.cpp`

**Current Implementation** (from `HybridRunAnywhere.hpp`):
```cpp
class HybridRunAnywhere : public HybridRunAnywhereSpec {
private:
  ra_backend_handle backend_;        // LlamaCpp for LLM
  ra_backend_handle onnxBackend_;    // ONNX for STT/TTS
  std::mutex backendMutex_, modelMutex_;
  bool isInitialized_;

public:
  // Backend lifecycle
  std::shared_ptr<Promise<bool>> createBackend(const std::string& name);
  std::shared_ptr<Promise<bool>> initialize(const std::string& configJson);

  // LLM operations
  std::shared_ptr<Promise<bool>> loadTextModel(const std::string& path, ...);
  std::shared_ptr<Promise<std::string>> generate(const std::string& prompt, ...);
  void generateStream(const std::string& prompt, ..., Function callback);

  // STT operations
  std::shared_ptr<Promise<bool>> loadSTTModel(const std::string& path, ...);
  std::shared_ptr<Promise<std::string>> transcribe(const std::string& audioBase64, ...);
};
```

**Assessment**: This already calls the C API (`ra_*` functions). The pattern is identical to Flutter's NativeBackend but using JSI instead of dart:ffi.

---

### 2. RunAnywhere.ts - The TypeScript Wrapper

**Location**: `src/Public/RunAnywhere.ts` (1,400+ lines)

**Current Architecture**:
```typescript
const RunAnywhere = {
  // Initialize (calls HybridRunAnywhere.cpp)
  async initialize(options: SDKInitOptions): Promise<void> {
    const native = requireNativeModule();
    await native.createBackend('llamacpp');
    await native.initialize(JSON.stringify(options));
    // Register providers
    LlamaCppProvider.register();
    ONNXProvider.register();
  },

  // Text generation (calls C++ via JSI)
  async generate(prompt: string, options?: GenerationOptions): Promise<GenerationResult> {
    const native = requireNativeModule();
    const result = await native.generate(prompt, JSON.stringify(options));
    return JSON.parse(result);
  },

  // Streaming (callback to C++)
  generateStream(prompt: string, options: GenerationOptions, onToken: (token: string) => void): void {
    const native = requireNativeModule();
    native.generateStream(prompt, JSON.stringify(options), (token, done) => {
      if (!done) onToken(token);
    });
  }
};
```

**What Should Move to Core**:
- Provider registration logic
- Options validation
- Result parsing
- Analytics tracking

**What Stays in TypeScript**:
- React Native interface
- Promise/callback ergonomics
- TypeScript types

---

### 3. ModuleRegistry.ts

**Location**: `src/Core/ModuleRegistry.ts`

**Current Implementation**:
```typescript
class ModuleRegistry {
  private static instance: ModuleRegistry;
  private sttProviders: STTServiceProvider[] = [];
  private llmProviders: LLMServiceProvider[] = [];
  private ttsProviders: TTSServiceProvider[] = [];

  registerSTT(provider: STTServiceProvider): void {
    this.sttProviders.push(provider);
  }

  sttProvider(modelId?: string): STTServiceProvider | null {
    return this.sttProviders.find(p => p.canHandle(modelId)) ?? null;
  }
}
```

**Assessment**: Identical to iOS/KMP/Flutter - should move to core.

---

### 4. EventBus.ts - NativeEventEmitter Wrapper

**Location**: `src/Public/Events/EventBus.ts` (468 lines)

**Current Implementation**:
```typescript
class EventBus {
  private emitter: NativeEventEmitter;
  private subscriptions: Map<string, EmitterSubscription[]> = new Map();

  onGeneration(handler: (event: SDKGenerationEvent) => void): UnsubscribeFn {
    return this.subscribe(NativeEventNames.SDK_GENERATION, handler);
  }

  publish(eventType: string, event: SDKEvent): void {
    // For JS-only events (native events come via NativeEventEmitter)
    this.notify(eventType, event);
  }
}
```

**What Should Move to Core**:
- Event type definitions
- Event routing logic
- Analytics integration

**What Stays in TypeScript**:
- NativeEventEmitter subscription
- React Native event bridge

---

### 5. Platform-Specific HybridObjects

#### HybridRunAnywhereFileSystem (Swift/Kotlin)

**iOS** (`ios/HybridRunAnywhereFileSystem.swift`):
```swift
class HybridRunAnywhereFileSystem: HybridRunAnywhereFileSystemSpec {
  func downloadModel(modelId: String, url: String, callback: ((Double) -> Void)?) async throws -> String {
    // Uses URLSession for download
    // Progress callback via callback parameter
    // Returns local path
  }
}
```

**Android** (`android/.../HybridRunAnywhereFileSystem.kt`):
```kotlin
class HybridRunAnywhereFileSystem : HybridRunAnywhereFileSystemSpec {
  suspend fun downloadModel(modelId: String, url: String, callback: ((Double) -> Unit)?): String {
    // Uses HttpURLConnection with retry
    // Auto-extracts archives
    // Returns local path
  }
}
```

**Assessment**: These stay platform-specific. Core provides orchestration logic, platform provides I/O.

#### AudioDecoder (iOS Only)

**Location**: `ios/AudioDecoder.m`

**Purpose**: Converts M4A/WAV/AAC → 16kHz mono PCM for Whisper

**Assessment**: Stays in iOS wrapper - uses AVAudioConverter.

---

## Migration Strategy for React Native

### Current State
```
┌─────────────────────┐
│   React Native TS   │
│   Components        │
│   (orchestration)   │
└─────────┬───────────┘
          │ Nitrogen/JSI
┌─────────┴───────────┐
│  HybridRunAnywhere  │
│       (C++)         │
└─────────┬───────────┘
          │ C API
┌─────────┴───────────┐
│   Native Backends   │
│   (LlamaCpp, ONNX)  │
└─────────────────────┘
```

### Target State
```
┌─────────────────────┐
│   React Native TS   │
│   (thin wrapper)    │
└─────────┬───────────┘
          │ Nitrogen/JSI
┌─────────┴───────────────────┐
│   Extended HybridObjects    │
│   ├── HybridSTTComponent    │
│   ├── HybridLLMComponent    │
│   ├── HybridModuleRegistry  │
│   └── HybridRunAnywhere     │
└─────────┬───────────────────┘
          │ C++ calls
┌─────────┴───────────────────┐
│   RunAnywhere Core (C++)    │
│   (shared with iOS/KMP/     │
│    Flutter)                 │
└─────────────────────────────┘
```

### Migration Steps

1. **Phase 1**: Extend C++ core with component APIs
   - Add component state machines to core
   - Add module registry to core
   - Update `HybridRunAnywhere.cpp` to call new core APIs

2. **Phase 2**: Add new Nitrogen specs for components
   ```typescript
   // New: RunAnywhereComponents.nitro.ts
   export interface STTComponent extends HybridObject<{ ios: 'c++'; android: 'c++' }> {
     initialize(config: STTConfiguration): Promise<void>;
     transcribe(audio: string, options?: string): Promise<STTResult>;
     getState(): Promise<ComponentState>;
   }
   ```

3. **Phase 3**: Simplify TypeScript components
   - Remove orchestration logic from TS
   - Components become thin wrappers over JSI

4. **Phase 4**: Move services to core
   - MemoryService → core
   - RoutingService → core
   - ModuleRegistry → core

---

## Nitrogen/JSI Considerations

### Streaming Callbacks

**Current Pattern** (TypeScript → C++):
```typescript
native.generateStream(prompt, options, (token: string, done: boolean) => {
  if (!done) onToken(token);
});
```

**C++ Side**:
```cpp
void generateStream(..., Function callback) {
  // Streaming callback from LlamaCpp
  while (generating) {
    auto token = getNextToken();
    callback(token, false);  // Per-token FFI crossing
  }
  callback("", true);
}
```

**Issue**: Per-token FFI crossing is expensive.

**Solution**: Batch tokens in C++:
```cpp
void generateStream(..., Function callback) {
  std::vector<std::string> batch;
  while (generating) {
    batch.push_back(getNextToken());
    if (batch.size() >= 10 || timeSinceLastCallback > 50ms) {
      callback(joinTokens(batch), false);
      batch.clear();
    }
  }
  callback(joinTokens(batch), true);
}
```

### Memory Management

**Current**: Nitrogen handles memory for HybridObjects

**Consideration**: When adding more HybridObjects (components), ensure proper cleanup on React Native unmount.

---

## Summary

### Already in C++ (Core)

| Component | Status |
|-----------|--------|
| LLM inference | ✅ Via HybridRunAnywhere → ra_text_* |
| STT inference | ✅ Via HybridRunAnywhere → ra_stt_* |
| TTS inference | ✅ Via HybridRunAnywhere → ra_tts_* |

### Move to Core (YES)

| Component | Effort | Priority |
|-----------|--------|----------|
| ModuleRegistry | M | 1 |
| Component state machines | M | 2 |
| MemoryService | M | 3 |
| RoutingService | M | 4 |
| EventBus (core logic) | M | 5 |
| ServiceContainer | M | 6 |

### Keep in TypeScript/Platform (NO)

| Component | Reason |
|-----------|--------|
| RunAnywhere.ts | React Native interface |
| EventBus (subscription) | NativeEventEmitter |
| HybridRunAnywhereFileSystem | Platform I/O (URLSession, HttpURLConnection) |
| HybridRunAnywhereDeviceInfo | Platform APIs |
| AudioDecoder | AVAudioConverter (iOS-specific) |

---

## Effort Estimates

**Total RN Migration Effort**: ~8-10 weeks

**Key Advantage**: JSI is already in C++. Migration involves:
1. Moving TypeScript orchestration to C++
2. Adding new Nitrogen specs
3. Simplifying TypeScript layer

**Key Challenge**: Need to update Nitrogen specs and regenerate bindings.

---

## Recommendations

1. **Extend HybridRunAnywhere** with component APIs before creating separate HybridObjects
2. **Batch streaming callbacks** to reduce FFI crossings
3. **Generate Nitrogen specs** from shared C header for consistency
4. **Keep platform HybridObjects** (FileSystem, DeviceInfo) separate

---

*Document generated: December 2025*
*Note: React Native SDK uses Nitrogen/JSI (already C++)*
