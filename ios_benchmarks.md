# iOS In-App Benchmarking Suite — Implementation Plan

## Status: COMPLETE ✅ (Build verified)

## Files Created

### Phase 1: Data Models & Utilities ✅
- [x] `Benchmarks/Models/BenchmarkTypes.swift` — Enums, structs, data models (BenchmarkCategory, BenchmarkRunStatus, BenchmarkScenario, ComponentModelInfo, BenchmarkDeviceInfo, BenchmarkMetrics, BenchmarkResult, BenchmarkRun, BenchmarkProgressUpdate)
- [x] `Benchmarks/Utilities/SyntheticInputGenerator.swift` — silentAudio, sineWaveAudio, solidColorImage, gradientImage, availableMemoryBytes

### Phase 2: Services ✅
- [x] `Benchmarks/Services/BenchmarkRunner.swift` — BenchmarkScenarioProvider protocol + BenchmarkRunner class
- [x] `Benchmarks/Services/LLMBenchmarkProvider.swift` — Short/Medium/Long scenarios (50/256/512 tokens)
- [x] `Benchmarks/Services/STTBenchmarkProvider.swift` — Silent 2s, Sine Tone 3s
- [x] `Benchmarks/Services/TTSBenchmarkProvider.swift` — Short Text, Medium Text
- [x] `Benchmarks/Services/VLMBenchmarkProvider.swift` — Solid Red Image, Gradient Image (224×224)
- [x] `Benchmarks/Services/DiffusionBenchmarkProvider.swift` — Simple Prompt (10 steps, seed 42)

### Phase 3: Persistence ✅
- [x] `Benchmarks/Models/BenchmarkStore.swift` — JSON persistence to Documents/benchmarks.json, max 50 runs

### Phase 4: ViewModel & Report Formatter ✅
- [x] `Benchmarks/ViewModels/BenchmarkViewModel.swift` — @MainActor @Observable, orchestrates runs, exports
- [x] `Benchmarks/Utilities/BenchmarkReportFormatter.swift` — Markdown, JSON, CSV export

### Phase 5: Views ✅
- [x] `Benchmarks/Views/BenchmarkProgressView.swift` — Progress overlay during execution
- [x] `Benchmarks/Views/BenchmarkDetailView.swift` — Single run detail + export actions
- [x] `Benchmarks/Views/BenchmarkDashboardView.swift` — Main screen with device info, filters, controls, history

### Phase 6: Integration ✅
- [x] Modified `CombinedSettingsView.swift` — Added Performance section (iOS) and BenchmarksCard (macOS)

## SDK API Details Used

| Component | Load | Execute | Unload |
|---|---|---|---|
| LLM | `RunAnywhere.loadModel(model.id)` | `RunAnywhere.generateStream(prompt, options:)` | `RunAnywhere.unloadModel()` |
| STT | `RunAnywhere.loadSTTModel(model.id)` | `RunAnywhere.transcribeWithOptions(data, options:)` | `RunAnywhere.unloadSTTModel()` |
| TTS | `RunAnywhere.loadTTSModel(model.id)` | `RunAnywhere.synthesize(text, options:)` | `RunAnywhere.unloadTTSVoice()` |
| VLM | `RunAnywhere.loadVLMModel(model)` (ModelInfo) | `RunAnywhere.processImage(image, prompt:, maxTokens:, temperature:)` | `RunAnywhere.unloadVLMModel()` (no try) |
| Diffusion | `RunAnywhere.loadDiffusionModel(modelPath:, modelId:, modelName:, configuration:)` | `RunAnywhere.generateImage(prompt:, options:)` | `RunAnywhere.unloadDiffusionModel()` |
