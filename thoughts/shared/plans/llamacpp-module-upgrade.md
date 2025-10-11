# Llama.cpp Module Upgrade Plan

**Objective**: Upgrade `runanywhere-llm-llamacpp` module to production-grade implementation by adopting SmolChat-Android's proven Llama.cpp integration patterns while maintaining KMP architecture and SDK design principles.

**Status**: Planning
**Estimated Duration**: 12-15 days (2.5-3 weeks)
**Priority**: High

---

## Executive Summary

The current implementation has solid architecture but critical gaps in:
1. **Performance**: Missing multi-ABI optimizations (30-60% speedup potential)
2. **Quality**: Greedy-only sampling produces robotic output
3. **Compatibility**: Hardcoded chat templates break non-Qwen2 models
4. **Usability**: No metadata reader, fixed context size, no cancellation

**Strategy**: Adopt SmolChat's battle-tested JNI/C++ layer and build system while preserving RunAnywhere's superior plugin architecture and KMP design.

---

## Phase 0: Pre-Implementation Analysis ✅ COMPLETE

### Completed Tasks:
- ✅ Full analysis of SmolChat-Android implementation
- ✅ Full analysis of RunAnywhere implementation
- ✅ Comprehensive comparison identifying all gaps
- ✅ Root cause analysis and recommendations

### Key Documents:
- `thoughts/shared/smolchat-llamacpp-analysis.md`
- `thoughts/shared/runanywhere-llamacpp-analysis.md`
- `thoughts/shared/llamacpp-implementation-comparison.md`

---

## Phase 1: Build System & Multi-ABI Support (3-4 days)

### 1.1 Update CMake Configuration (1-2 days)

**Current State**: Single ARM64-v8a baseline build
**Target State**: 8 ARM64 variants with runtime CPU detection

#### Tasks:

**1.1.1 Update native/llama-jni/CMakeLists.txt**
- [ ] Copy SmolChat's multi-ABI CMake strategy
- [ ] Define 8 library variants: `llama-jni`, `llama-jni-fp16`, `llama-jni-dotprod`, etc.
- [ ] Add compiler flags for each variant:
  - Baseline: standard ARM64
  - FP16: `-march=armv8.2-a+fp16`
  - DotProd: `-march=armv8.2-a+fp16+dotprod`
  - I8MM: `-march=armv8.2-a+fp16+dotprod+i8mm`
  - SVE: `-march=armv8.2-a+fp16+dotprod+i8mm+sve`
- [ ] Configure optimization flags:
  ```cmake
  -O3 -DNDEBUG -ffast-math -funroll-loops
  -fvisibility=hidden -flto
  -ffunction-sections -fdata-sections
  -Wl,--gc-sections -Wl,--strip-all
  ```
- [ ] Update llama.cpp source file list if needed

**Files to Modify**:
- `sdk/runanywhere-kotlin/native/llama-jni/CMakeLists.txt`

**Reference**:
- SmolChat: `EXTERNAL/SmolChat-Android/smollm/src/main/cpp/CMakeLists.txt`

---

**1.1.2 Add CPU Feature Detection for Runtime Library Selection**
- [ ] Create `CPUFeatures.cpp` for reading `/proc/cpuinfo`
- [ ] Implement detection for: fp16, dotprod, i8mm, sve
- [ ] Add JNI method: `Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_detectCPUFeatures`
- [ ] Return optimal library suffix based on detected features

**New Files**:
- `sdk/runanywhere-kotlin/native/llama-jni/src/cpu_features.cpp`
- `sdk/runanywhere-kotlin/native/llama-jni/src/cpu_features.h`

**Reference**:
- SmolChat: Uses runtime library selection in Java/Kotlin layer

---

**1.1.3 Update Gradle Build Configuration**
- [ ] Update `modules/runanywhere-llm-llamacpp/build.gradle.kts`
- [ ] Add all 8 ABI targets to `ndk.abiFilters`
- [ ] Configure CMake arguments for each variant
- [ ] Add build tasks for parallel compilation
- [ ] Update .gitignore for new build artifacts

**Files to Modify**:
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/build.gradle.kts`

---

**1.1.4 Update Library Loading Logic**
- [ ] Modify `LLamaAndroid.kt` to detect CPU features first
- [ ] Implement fallback chain: SVE → I8MM → DotProd → FP16 → Baseline
- [ ] Add proper error handling for library loading failures
- [ ] Log selected library variant for debugging

**Files to Modify**:
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/androidMain/kotlin/com/runanywhere/sdk/llm/llamacpp/LLamaAndroid.kt`

**Expected Outcome**:
- 8 optimized `.so` files: `libllama-jni.so`, `libllama-jni-fp16.so`, etc.
- Runtime detection selects best variant
- 30-60% performance improvement on modern devices

---

### 1.2 Build System Testing (1 day)

**Tasks**:
- [ ] Clean build: `./gradlew clean`
- [ ] Build all variants: `./gradlew :modules:runanywhere-llm-llamacpp:build`
- [ ] Verify all 8 `.so` files generated in `jniLibs/arm64-v8a/`
- [ ] Test on devices with different CPUs:
  - [ ] Older device (no FP16/DotProd)
  - [ ] Modern device (with FP16/DotProd)
  - [ ] Latest device (with I8MM/SVE if available)
- [ ] Benchmark inference speed before/after
- [ ] Document performance improvements

**Success Criteria**:
- All 8 libraries build successfully
- Runtime selection works correctly
- Performance improvement: 30-60% on modern devices

---

## Phase 2: C++ Wrapper Layer Improvements (2-3 days)

### 2.1 Enhance C++ LLMInference Wrapper (1-2 days)

**Current State**: Basic llama.cpp wrapper with fixed parameters
**Target State**: Flexible, configurable inference engine matching SmolChat

#### Tasks:

**2.1.1 Create Comprehensive LLMInference Class**
- [ ] Copy SmolChat's `LLMInference.h` and `LLMInference.cpp` structure
- [ ] Adapt to RunAnywhere naming conventions
- [ ] Key methods to implement:
  - `loadModel(modelPath, params)` - with configurable backend, context, threads
  - `updateChatHistory(messages)` - apply chat template
  - `createPrompt(history, template)` - format with template
  - `completionLoop(prompt, callback)` - token-by-token generation
  - `stopCompletion()` - cancellation support
  - `cleanup()` - proper resource cleanup

**New Files**:
- `sdk/runanywhere-kotlin/native/llama-jni/src/llm_inference.h`
- `sdk/runanywhere-kotlin/native/llama-jni/src/llm_inference.cpp`

**Reference**:
- SmolChat: `EXTERNAL/SmolChat-Android/smollm/src/main/cpp/LLMInference.h`
- SmolChat: `EXTERNAL/SmolChat-Android/smollm/src/main/cpp/LLMInference.cpp`

---

**2.1.2 Implement Chat Template System**
- [ ] Add `ChatTemplate` class/enum for template types
- [ ] Support templates:
  - Llama3: `<|begin_of_text|><|start_header_id|>...<|end_header_id|>`
  - Qwen2: `<|im_start|>...<|im_end|>`
  - Mistral: `[INST]...[/INST]`
  - Phi: `<|user|>...<|assistant|>`
  - ChatML: `<|im_start|>...<|im_end|>`
- [ ] Implement `applyTemplate(messages, templateType)` function
- [ ] Add template auto-detection from GGUF metadata

**New Files**:
- `sdk/runanywhere-kotlin/native/llama-jni/src/chat_template.h`
- `sdk/runanywhere-kotlin/native/llama-jni/src/chat_template.cpp`

**Reference**:
- SmolChat: Template logic in `LLMInference.cpp::createPrompt()`

---

**2.1.3 Implement Advanced Sampling Chain**
- [ ] Replace greedy sampling with configurable sampler
- [ ] Implement sampler chain:
  1. Top-K sampling (optional)
  2. Temperature scaling
  3. Min-P sampling
  4. Repetition penalty (optional)
- [ ] Add `SamplerParams` struct with fields:
  - `temperature` (default: 0.8)
  - `min_p` (default: 0.05)
  - `top_k` (default: 40, 0 = disabled)
  - `repeat_penalty` (default: 1.1)
  - `seed` (default: -1 for random)
- [ ] Use `llama_sampler_chain_*` APIs from llama.cpp

**Files to Modify**:
- `sdk/runanywhere-kotlin/native/llama-jni/src/llm_inference.cpp`

**Reference**:
- SmolChat: `LLMInference.cpp::completionLoop()` sampler setup

---

**2.1.4 Add Cancellation Support**
- [ ] Add `stopRequested` atomic flag to `LLMInference`
- [ ] Check flag in token generation loop
- [ ] Implement `stopCompletion()` JNI method
- [ ] Handle partial completion cleanup

**Files to Modify**:
- `sdk/runanywhere-kotlin/native/llama-jni/src/llm_inference.h`
- `sdk/runanywhere-kotlin/native/llama-jni/src/llm_inference.cpp`

---

**2.1.5 Improve Memory Management**
- [ ] Ensure proper RAII patterns (smart pointers, destructors)
- [ ] Add memory usage tracking (model size, KV cache, buffers)
- [ ] Implement context size overflow detection
- [ ] Add logging for memory allocations

**Files to Modify**:
- `sdk/runanywhere-kotlin/native/llama-jni/src/llm_inference.cpp`

---

### 2.2 Update JNI Bindings (1 day)

**Tasks**:

**2.2.1 Refactor llama-jni.cpp**
- [ ] Update JNI method signatures to match new C++ API
- [ ] Add methods:
  - `detectCPUFeatures()` → String (comma-separated features)
  - `loadModel(path, nThreads, contextSize, useGPU)` → long (handle)
  - `setChatTemplate(handle, template)` → void
  - `setSamplerParams(handle, temp, minP, topK, repeatPen)` → void
  - `generateStream(handle, prompt, callback)` → void
  - `stopGeneration(handle)` → void
  - `getTokenCount(handle)` → int
  - `unloadModel(handle)` → void
- [ ] Improve error handling: translate C++ exceptions to Java exceptions
- [ ] Add JNI callbacks for streaming tokens

**Files to Modify**:
- `sdk/runanywhere-kotlin/native/llama-jni/src/llama-jni.cpp`

**Reference**:
- SmolChat: `EXTERNAL/SmolChat-Android/smollm/src/main/cpp/smollm.cpp`

---

**2.2.2 Add UTF-8 Validation**
- [ ] Implement UTF-8 validation for token text
- [ ] Buffer incomplete sequences for next token
- [ ] Only emit valid UTF-8 strings to UI
- [ ] Handle multi-byte character boundaries

**New Files**:
- `sdk/runanywhere-kotlin/native/llama-jni/src/utf8_utils.h`
- `sdk/runanywhere-kotlin/native/llama-jni/src/utf8_utils.cpp`

**Reference**:
- SmolChat: UTF-8 handling in token callback

---

## Phase 3: Kotlin API Layer (3-4 days)

### 3.1 Create GGUF Metadata Reader (1.5 days)

**Current State**: No metadata reading capability
**Target State**: Automatic model configuration from GGUF files

**Tasks**:

**3.1.1 Implement GGUF Parser in C++**
- [ ] Create `GGUFReader` C++ class
- [ ] Parse GGUF header and metadata tensors
- [ ] Extract key fields:
  - `general.architecture` (model type)
  - `llama.context_length` (max context)
  - `llama.vocab_size`
  - `tokenizer.chat_template` (if present)
  - Model size estimation
- [ ] Return metadata as JSON string or structured object

**New Files**:
- `sdk/runanywhere-kotlin/native/llama-jni/src/gguf_reader.h`
- `sdk/runanywhere-kotlin/native/llama-jni/src/gguf_reader.cpp`

**Reference**:
- SmolChat: `EXTERNAL/SmolChat-Android/smollm/src/main/cpp/GGUFReader.h`
- SmolChat: `EXTERNAL/SmolChat-Android/smollm/src/main/cpp/GGUFReader.cpp`

---

**3.1.2 Add JNI Method for Metadata Reading**
- [ ] Add `readGGUFMetadata(path)` JNI method
- [ ] Return JSON string with all metadata
- [ ] Handle file access errors

**Files to Modify**:
- `sdk/runanywhere-kotlin/native/llama-jni/src/llama-jni.cpp`

---

**3.1.3 Create Kotlin GGUFMetadata Data Class**
- [ ] Define `GGUFMetadata` data class in commonMain
- [ ] Fields:
  ```kotlin
  data class GGUFMetadata(
      val architecture: String,
      val contextLength: Int,
      val vocabSize: Int,
      val chatTemplate: String?,
      val fileSizeBytes: Long,
      val quantizationType: String?
  )
  ```
- [ ] Add parsing from JSON string
- [ ] Add validation methods

**New Files**:
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/commonMain/kotlin/com/runanywhere/sdk/llm/llamacpp/GGUFMetadata.kt`

---

**3.1.4 Integrate Metadata Reader into Android Wrapper**
- [ ] Add `readMetadata(modelPath)` to `LLamaAndroid`
- [ ] Call JNI method and parse result
- [ ] Use metadata to auto-configure model loading

**Files to Modify**:
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/androidMain/kotlin/com/runanywhere/sdk/llm/llamacpp/LLamaAndroid.kt`

---

### 3.2 Enhance LLamaAndroid Wrapper (1 day)

**Tasks**:

**3.2.1 Add Configuration Data Classes**
- [ ] Create `LlamaModelConfig` in commonMain:
  ```kotlin
  data class LlamaModelConfig(
      val modelPath: String,
      val nThreads: Int = Runtime.getRuntime().availableProcessors(),
      val contextSize: Int = 2048,
      val useGPU: Boolean = false,
      val chatTemplate: ChatTemplate = ChatTemplate.AUTO
  )
  ```
- [ ] Create `LlamaSamplerConfig`:
  ```kotlin
  data class LlamaSamplerConfig(
      val temperature: Float = 0.8f,
      val minP: Float = 0.05f,
      val topK: Int = 40,
      val repeatPenalty: Float = 1.1f,
      val seed: Int = -1
  )
  ```
- [ ] Create `ChatTemplate` enum

**New Files**:
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/commonMain/kotlin/com/runanywhere/sdk/llm/llamacpp/LlamaModelConfig.kt`
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/commonMain/kotlin/com/runanywhere/sdk/llm/llamacpp/LlamaSamplerConfig.kt`
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/commonMain/kotlin/com/runanywhere/sdk/llm/chiamacpp/ChatTemplate.kt`

---

**3.2.2 Refactor LLamaAndroid for Configuration**
- [ ] Replace hardcoded values with config parameters
- [ ] Add `loadModel(config: LlamaModelConfig)` method
- [ ] Add `setSamplerConfig(config: LlamaSamplerConfig)` method
- [ ] Store model handle and config as instance variables
- [ ] Implement proper lifecycle: load → configure → generate → unload

**Files to Modify**:
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/androidMain/kotlin/com/runanywhere/sdk/llm/llamacpp/LLamaAndroid.kt`

---

**3.2.3 Implement Cancellation Support**
- [ ] Add `cancelGeneration()` method to `LLamaAndroid`
- [ ] Call native `stopGeneration(handle)` method
- [ ] Cancel coroutine Job if applicable
- [ ] Emit cancellation event to Flow

**Files to Modify**:
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/androidMain/kotlin/com/runanywhere/sdk/llm/llamacpp/LLamaAndroid.kt`

---

**3.2.4 Improve Error Handling**
- [ ] Define `LlamaException` sealed class hierarchy:
  - `ModelLoadException`
  - `GenerationException`
  - `ConfigurationException`
  - `OutOfMemoryException`
- [ ] Catch native exceptions and wrap in typed Kotlin exceptions
- [ ] Add error recovery strategies

**New Files**:
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/commonMain/kotlin/com/runanywhere/sdk/llm/llamacpp/LlamaException.kt`

---

### 3.3 Update LlamaCppService (0.5 days)

**Tasks**:

**3.3.1 Integrate New Configuration**
- [ ] Update `LlamaCppService` to use new config classes
- [ ] Pass configuration from `TextToTextInput` to `LLamaAndroid`
- [ ] Map SDK-level options to Llama-specific config
- [ ] Add metadata reading before model loading

**Files to Modify**:
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/commonMain/kotlin/com/runanywhere/sdk/llm/llamacpp/LlamaCppService.kt`

---

**3.3.2 Add Cancellation to Service**
- [ ] Implement cancellation in `textToTextStream` Flow
- [ ] Call `LLamaAndroid.cancelGeneration()` on Flow cancellation
- [ ] Test cancellation behavior

**Files to Modify**:
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/commonMain/kotlin/com/runanywhere/sdk/llm/llamacpp/LlamaCppService.kt`

---

### 3.4 Update SDK Integration (1 day)

**Tasks**:

**3.4.1 Update Module Registration**
- [ ] Update `LlamaCppProvider` to register new capabilities
- [ ] Add supported model types and architectures
- [ ] Update capability flags (streaming, cancellation, configurable sampling)

**Files to Modify**:
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/commonMain/kotlin/com/runanywhere/sdk/llm/llamacpp/LlamaCppProvider.kt`

---

**3.4.2 Add Configuration to SDK-Level APIs**
- [ ] Extend `TextToTextInput` to include sampling parameters
- [ ] Add chat template selection option
- [ ] Add context size configuration
- [ ] Update example code in documentation

**Files to Modify** (if needed):
- `sdk/runanywhere-kotlin/modules/runanywhere-core/src/commonMain/kotlin/com/runanywhere/sdk/services/llm/TextToTextInput.kt`

---

## Phase 4: Testing & Validation (2-3 days)

### 4.1 Unit Testing (1 day)

**Tasks**:
- [ ] Test GGUF metadata reader with various model formats
- [ ] Test CPU feature detection on different devices
- [ ] Test library loading fallback chain
- [ ] Test configuration validation
- [ ] Test error handling paths
- [ ] Test memory cleanup and resource management

**New Files**:
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/androidUnitTest/kotlin/com/runanywhere/sdk/llm/llamacpp/GGUFMetadataTest.kt`
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/src/androidUnitTest/kotlin/com/runanywhere/sdk/llm/llamacpp/LlamaConfigTest.kt`

---

### 4.2 Integration Testing (1 day)

**Tasks**:
- [ ] Test with Llama3 model (8B, Q4_K_M)
- [ ] Test with Qwen2 model
- [ ] Test with Mistral model
- [ ] Test with Phi-3 model
- [ ] Verify chat template auto-detection
- [ ] Verify correct prompt formatting for each template
- [ ] Test different sampling configurations
- [ ] Test cancellation during generation
- [ ] Test context window limits
- [ ] Measure inference speed improvements

**Test Devices**:
- [ ] Old device (no advanced CPU features)
- [ ] Modern device (FP16, DotProd)
- [ ] Latest flagship (all optimizations)

---

### 4.3 Example App Updates (0.5 days)

**Tasks**:
- [ ] Update Android example app to showcase new features
- [ ] Add UI for sampling configuration
- [ ] Add model metadata display
- [ ] Add cancellation button
- [ ] Add performance metrics display
- [ ] Update documentation

**Files to Modify**:
- `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/ai/MainActivity.kt`

---

### 4.4 Performance Benchmarking (0.5 days)

**Tasks**:
- [ ] Benchmark tokens/second on various devices
- [ ] Compare before/after upgrade
- [ ] Compare against SmolChat performance
- [ ] Document results with device specs
- [ ] Create performance comparison table

**Expected Results**:
- 30-60% speedup from multi-ABI optimizations
- Similar or better performance than SmolChat
- Better generation quality from advanced sampling

---

## Phase 5: Documentation & Cleanup (1 day)

### 5.1 Code Documentation (0.5 days)

**Tasks**:
- [ ] Add KDoc comments to all public APIs
- [ ] Document configuration options and defaults
- [ ] Add code examples for common use cases
- [ ] Document chat template usage
- [ ] Document sampling parameters and their effects

---

### 5.2 Integration Documentation (0.5 days)

**Tasks**:
- [ ] Update module README
- [ ] Add migration guide from old API
- [ ] Add troubleshooting section
- [ ] Update main SDK documentation
- [ ] Add performance tuning guide

**Files to Modify**:
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/README.md`
- `sdk/runanywhere-kotlin/README.md`

---

## Implementation Strategy

### Code Reuse from SmolChat

**Direct Ports** (copy and adapt):
1. ✅ CMake multi-ABI configuration
2. ✅ LLMInference C++ wrapper class
3. ✅ GGUFReader implementation
4. ✅ Chat template formatting logic
5. ✅ Sampler chain setup
6. ✅ UTF-8 validation utilities
7. ✅ CPU feature detection

**Preserve RunAnywhere Design** (don't port):
1. ❌ SmolChat's Manager pattern → Use `LlamaCppService`
2. ❌ SmolChat's Room database → Use SDK's `ModelManager`
3. ❌ SmolChat's ViewModel → Use SDK's Component pattern
4. ❌ SmolChat's singleton → Allow multiple instances via SDK

**Hybrid Approach**:
- Port SmolChat's **low-level** C++/JNI layer (proven, battle-tested)
- Keep RunAnywhere's **high-level** Kotlin/KMP architecture (cleaner, more flexible)
- Best of both worlds: performance + architecture

---

## Risk Mitigation

### High-Risk Areas:

1. **CMake Build Complexity**
   - Risk: Build failures, missing libraries
   - Mitigation: Test incrementally, start with baseline, add variants one-by-one

2. **JNI Crashes**
   - Risk: Native crashes are hard to debug
   - Mitigation: Extensive logging, crash reporting, defensive checks

3. **Memory Leaks**
   - Risk: C++ resources not properly cleaned up
   - Mitigation: RAII patterns, automated testing with memory profilers

4. **API Breaking Changes**
   - Risk: Existing users' code breaks
   - Mitigation: Deprecate old APIs, provide migration guide, version bump

### Testing Strategy:

- **Incremental Testing**: Test each phase before moving to next
- **Device Coverage**: Test on 3+ devices with different CPU capabilities
- **Model Coverage**: Test with 4+ model architectures
- **Regression Testing**: Ensure existing functionality still works
- **Performance Testing**: Benchmark before/after for all changes

---

## Success Metrics

### Performance:
- ✅ 30-60% faster inference on modern devices (FP16/DotProd)
- ✅ Tokens/second matches or exceeds SmolChat

### Quality:
- ✅ Non-deterministic, natural-sounding responses
- ✅ Configurable creativity (temperature control)
- ✅ No repetitive loops (repeat penalty)

### Compatibility:
- ✅ Works with Llama3, Qwen2, Mistral, Phi-3 models
- ✅ Automatic chat template detection
- ✅ Supports context sizes: 2048, 4096, 8192+

### Usability:
- ✅ No manual configuration needed (metadata reader)
- ✅ Cancellation works reliably
- ✅ Clear error messages

### Architecture:
- ✅ Maintains KMP compatibility (commonMain interfaces)
- ✅ Preserves plugin architecture (ModuleRegistry)
- ✅ No breaking changes to SDK-level APIs (if possible)

---

## Timeline Estimate

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| **Phase 0**: Analysis | ✅ Complete | None |
| **Phase 1**: Build System | 3-4 days | Phase 0 |
| **Phase 2**: C++ Layer | 2-3 days | Phase 1 |
| **Phase 3**: Kotlin API | 3-4 days | Phase 2 |
| **Phase 4**: Testing | 2-3 days | Phase 3 |
| **Phase 5**: Documentation | 1 day | Phase 4 |
| **Total** | **12-15 days** | - |

**Note**: Assumes full-time focus. Add buffer for:
- Learning curve (first time with llama.cpp internals)
- Debugging native issues (crashes, memory issues)
- Integration issues with existing SDK

---

## Next Steps

1. **Review & Approve Plan**: Get stakeholder sign-off
2. **Setup Development Branch**: `feature/llamacpp-upgrade`
3. **Phase 1 Kickoff**: Start with CMake multi-ABI build
4. **Daily Check-ins**: Review progress, adjust plan as needed
5. **Phase-by-Phase Reviews**: Validate each phase before proceeding

---

## Open Questions

1. **API Versioning**: Should this be a breaking change (2.0) or backward-compatible (1.1)?
2. **GPU Support**: Should we add Vulkan/GPU support in this phase or defer?
3. **iOS Parity**: Should we upgrade iOS SDK's Llama.cpp integration too?
4. **Model Management**: Should GGUF reader integrate with existing ModelManager?
5. **Configuration Defaults**: What defaults balance quality vs. performance?

---

## Appendix: File Checklist

### Files to Create:
- [ ] `native/llama-jni/src/cpu_features.h`
- [ ] `native/llama-jni/src/cpu_features.cpp`
- [ ] `native/llama-jni/src/llm_inference.h`
- [ ] `native/llama-jni/src/llm_inference.cpp`
- [ ] `native/llama-jni/src/chat_template.h`
- [ ] `native/llama-jni/src/chat_template.cpp`
- [ ] `native/llama-jni/src/gguf_reader.h`
- [ ] `native/llama-jni/src/gguf_reader.cpp`
- [ ] `native/llama-jni/src/utf8_utils.h`
- [ ] `native/llama-jni/src/utf8_utils.cpp`
- [ ] `modules/.../commonMain/.../GGUFMetadata.kt`
- [ ] `modules/.../commonMain/.../LlamaModelConfig.kt`
- [ ] `modules/.../commonMain/.../LlamaSamplerConfig.kt`
- [ ] `modules/.../commonMain/.../ChatTemplate.kt`
- [ ] `modules/.../commonMain/.../LlamaException.kt`
- [ ] `modules/.../androidUnitTest/.../GGUFMetadataTest.kt`
- [ ] `modules/.../androidUnitTest/.../LlamaConfigTest.kt`

### Files to Modify:
- [ ] `native/llama-jni/CMakeLists.txt`
- [ ] `native/llama-jni/src/llama-jni.cpp`
- [ ] `modules/.../build.gradle.kts`
- [ ] `modules/.../androidMain/.../LLamaAndroid.kt`
- [ ] `modules/.../commonMain/.../LlamaCppService.kt`
- [ ] `modules/.../commonMain/.../LlamaCppProvider.kt`
- [ ] `examples/android/RunAnywhereAI/app/.../MainActivity.kt`
- [ ] `sdk/runanywhere-kotlin/modules/runanywhere-llm-llamacpp/README.md`

---

**Plan Created**: 2025-10-11
**Last Updated**: 2025-10-11
**Author**: Claude Code
**Status**: Ready for Implementation
