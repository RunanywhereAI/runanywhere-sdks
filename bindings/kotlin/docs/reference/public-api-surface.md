# Kotlin SDK — public API surface map

Full file → capability → signature map for the `RunAnywhere` extension functions.
Entry point: `RunAnywhere` (object singleton, `src/main/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt`).
Every feature API is an extension function on it, organized one-per-file under
`src/main/kotlin/com/runanywhere/sdk/public/extensions/`. See the top-level `AGENTS.md`
for the surrounding architecture (JNI bridge, event system, error handling); this file is
just the index.

| File | Capability |
|------|-----------|
| `LLM/RunAnywhereTextGeneration.kt` | `generate(prompt, RALLMGenerationOptions?) → RALLMGenerationResult`, `generateStream(...) → Flow<RALLMStreamEvent>`, `suspend cancelGeneration()` |
| `STT/RunAnywhereSTT.kt` | `transcribe(audio, RASTTOptions)`, `transcribeStream(Flow<ByteArray>, RASTTOptions?) → Flow<RASTTPartialResult>` |
| `TTS/RunAnywhereTTS.kt` | `synthesize(text, RATTSOptions)`, `speak()`, `synthesizeStream() → Flow<RATTSOutput>`, `stopSpeaking()`, `stopSynthesis()` |
| `VAD/RunAnywhereVAD.kt` | `detectVoiceActivity()`, `streamVAD(Flow<ByteArray>, RAVADOptions?)`, `resetVAD()` |
| `VLM/RunAnywhereVisionLanguage.kt` | `describeImage()`, `processImage()`, `processImageStream()` |
| `VoiceAgent/RunAnywhereVoiceAgent.kt` | Full voice pipeline: `initializeVoiceAgent(VoiceAgentConfig)`, `streamVoiceAgent() → Flow<VoiceEvent>`, `processVoiceTurn()`, `cleanupVoiceAgent()` |
| `Models/RunAnywhereModelLifecycle.kt` | `loadModel(RAModelLoadRequest)`, `unloadModel(ModelUnloadRequest)`, `currentModel(CurrentModelRequest)`, `componentLifecycleSnapshot()` |
| `Models/RunAnywhereModelRegistry.kt` | `registerModel()`, `downloadModel()`, `availableModels()`, `deleteModel()`, model CRUD |
| `RunAnywhere+RAG.kt` | `ragCreatePipeline()`, `ragIngest()`, `ragQuery()` |
| `RunAnywhere+ToolCalling.kt` | `registerTool()`, `generateWithTools()` |
| `RunAnywhere+StructuredOutput.kt` | `generateStructured()`, JSON schema-constrained generation |
| `RunAnywhere+LoRA.kt` | LoRA adapter load/remove/registry |
| `RunAnywhere+Diffusion.kt` | Image generation pipeline |
| `RunAnywhere+Solutions.kt` | Declarative YAML-based pipeline orchestration |
| `RunAnywhere+Storage.kt` | Storage info, cache management, model storage metrics |
| `RunAnywhere+Auth.kt` | `getUserId()`, `isAuthenticated`, device registration status |
| `RunAnywhere+Hardware.kt` | `HardwareProfile`, NPU/accelerator detection |

## Overlap with `docs/Documentation.md`

`docs/Documentation.md` ("Complete API reference") predates this table's bottom nine rows
— it has narrated usage examples for Core/LLM/STT/TTS/VAD/VoiceAgent/Model Management only.
It has not been updated for RAG, ToolCalling, StructuredOutput, LoRA, Diffusion, Solutions,
Storage, Auth, or Hardware. Treat this file as the current, complete index; treat
`Documentation.md` as narrated-examples-for-a-subset, not exhaustive.
