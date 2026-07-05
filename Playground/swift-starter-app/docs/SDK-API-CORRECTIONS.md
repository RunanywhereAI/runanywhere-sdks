# RunAnywhere SDK API Corrections

**SDK Version:** 0.16.0-test.39
**Date:** January 2026
**Based on:** LocalAI Playground implementation

---

## Overview

This document catalogs discrepancies found between the RunAnywhere SDK documentation/examples and the actual API behavior as observed during implementation of the LocalAI Playground app.

---

## 1. Model State Checking

### `isModelLoaded`

**Documentation/examples suggest:**
```swift
let isLoaded = await RunAnywhere.isModelLoaded(id: "model-id")
```

**Actual API:**
```swift
let isLoaded = await RunAnywhere.isModelLoaded
```

**Notes:**
- `isModelLoaded` is a **property**, not a function
- No model ID parameter - checks if ANY LLM model is loaded
- Similar properties exist: `isSTTModelLoaded`, `isTTSVoiceLoaded`

**Evidence:** `Services/ModelService.swift`, lines 218-222
```swift
func refreshLoadedStates() async {
    isLLMLoaded = await RunAnywhere.isModelLoaded
    isSTTLoaded = await RunAnywhere.isSTTModelLoaded
    isTTSLoaded = await RunAnywhere.isTTSVoiceLoaded
}
```

---

## 2. Model Download

### `downloadModel`

**Documentation suggests:**
```swift
let stream = try await RunAnywhere.downloadModel(id: "model-id")
```

**Actual API:**
```swift
let stream = try await RunAnywhere.downloadModel("model-id")
```

**Notes:**
- The `id:` parameter label should be **omitted**
- Uses positional parameter only

**Evidence:** `Services/ModelService.swift`, lines 268, 334, 400
```swift
let progressStream = try await RunAnywhere.downloadModel(Self.llmModelId)
```

---

## 3. Model Unloading

### `unloadModel`

**Documentation suggests:**
```swift
try await RunAnywhere.unloadModel(id: "model-id")
```

**Actual API:**
```swift
try await RunAnywhere.unloadModel()
```

**Notes:**
- **No ID parameter**
- Unloads the currently loaded model (single-model-at-a-time paradigm)

**Evidence:** `Services/ModelService.swift`, line 299
```swift
try await RunAnywhere.unloadModel()
```

### `unloadSTTModel`

**Documentation suggests:**
```swift
try await RunAnywhere.unloadSTTModel(id: "model-id")
```

**Actual API:**
```swift
try await RunAnywhere.unloadSTTModel()
```

**Notes:**
- No ID parameter

**Evidence:** `Services/ModelService.swift`, line 365

### `unloadTTSVoice`

**Documentation suggests:**
```swift
try await RunAnywhere.unloadTTSVoice(id: "voice-id")
```

**Actual API:**
```swift
try await RunAnywhere.unloadTTSVoice()
```

**Notes:**
- No ID parameter

**Evidence:** `Services/ModelService.swift`, line 431

---

## 4. LLM Generation Options

### `LLMGenerationOptions`

**Documentation suggests:**
```swift
let options = LLMGenerationOptions(
    maxTokens: 256,
    temperature: 0.7,
    modelId: "model-id"
)
```

**Actual API:**
```swift
let options = LLMGenerationOptions(
    maxTokens: 256,
    temperature: 0.7
)
```

**Notes:**
- `modelId` parameter **does not exist**
- Model selection happens at load time, not generation time
- Only `maxTokens` and `temperature` are confirmed parameters

**Evidence:** `Views/ChatView.swift`, lines 297-300
```swift
let options = LLMGenerationOptions(
    maxTokens: 256,
    temperature: 0.8
)
```

---

## 5. Verified API Reference

Based on actual implementation, here is the verified API surface:

### Initialization
```swift
// Initialize SDK
try RunAnywhere.initialize(environment: .development | .production)

// Register backends
LlamaCPP.register()
ONNX.register()

// Get version
RunAnywhere.version -> String
```

### Model Registration
```swift
RunAnywhere.registerModel(
    id: String,
    name: String,
    url: URL,
    framework: ModelFramework,          // .llamaCpp or .onnx
    modality: ModelModality?,           // .speechRecognition, .speechSynthesis
    artifactType: ArtifactType?,        // .archive(.tarGz, structure: .nestedDirectory)
    memoryRequirement: Int
)
```

### Model Download
```swift
// Returns AsyncStream<DownloadProgress>
let progressStream = try await RunAnywhere.downloadModel(String)

// Progress object contains:
// - overallProgress: Double (0.0 to 1.0)
// - stage: DownloadStage (.downloading, .extracting, .completed, etc.)
```

### Model Loading
```swift
try await RunAnywhere.loadModel(String)        // LLM
try await RunAnywhere.loadSTTModel(String)     // Speech-to-Text
try await RunAnywhere.loadTTSVoice(String)     // Text-to-Speech
```

### State Checking (Properties, NOT Functions)
```swift
await RunAnywhere.isModelLoaded      -> Bool
await RunAnywhere.isSTTModelLoaded   -> Bool
await RunAnywhere.isTTSVoiceLoaded   -> Bool
```

### Model Unloading (No Parameters)
```swift
try await RunAnywhere.unloadModel()
try await RunAnywhere.unloadSTTModel()
try await RunAnywhere.unloadTTSVoice()
```

### Text Generation
```swift
let options = LLMGenerationOptions(
    maxTokens: Int,
    temperature: Float
)

// Streaming generation
let result = try await RunAnywhere.generateStream(String, options: LLMGenerationOptions)
// result.stream: AsyncStream<String> (tokens)
// result.result: Task<GenerationResult, Error>

// GenerationResult contains:
// - tokensUsed: Int
// - tokensPerSecond: Double
```

### Speech-to-Text
```swift
let text: String = try await RunAnywhere.transcribe(Data)
// Input: 16kHz mono Int16 PCM audio data
// Output: Transcribed text
```

### Text-to-Speech
```swift
let options = TTSOptions(
    rate: Float,    // Speech rate (1.0 = normal)
    pitch: Float,   // Pitch adjustment
    volume: Float   // Volume level
)

let output = try await RunAnywhere.synthesize(String, options: TTSOptions)
// output.audioData: Data (Float32 PCM @ 22kHz)
// output.duration: TimeInterval
```

---

## 6. Recommendations for SDK Documentation

1. **Consistency in parameter naming:** `downloadModel` uses positional parameter while `loadModel` uses positional. Document this clearly or consider standardizing with labeled parameters.

2. **State checking paradigm:** The property-based state checking (`isModelLoaded` vs `isModelLoaded(id:)`) suggests a single-model-at-a-time design. Document this architectural decision clearly.

3. **Audio format documentation:** Clearly document input/output audio formats in a prominent location:
   - STT input: 16kHz, mono, Int16 PCM
   - TTS output: 22kHz, mono, Float32 PCM

4. **Unload behavior:** Document that unload functions don't take ID parameters and operate on the currently loaded model.

5. **Version-specific API notes:** Consider publishing API changelogs with each release to help developers track breaking changes.

---

## Files Referenced

| File | Line Numbers | API Verified |
|------|--------------|--------------|
| `Services/ModelService.swift` | 218-222 | `isModelLoaded` property |
| `Services/ModelService.swift` | 268, 334, 400 | `downloadModel` positional param |
| `Services/ModelService.swift` | 299 | `unloadModel()` no params |
| `Services/ModelService.swift` | 365 | `unloadSTTModel()` no params |
| `Services/ModelService.swift` | 431 | `unloadTTSVoice()` no params |
| `Views/ChatView.swift` | 297-300 | `LLMGenerationOptions` |
| `Views/VoicePipelineView.swift` | 601, 617, 637 | Full pipeline API usage |
