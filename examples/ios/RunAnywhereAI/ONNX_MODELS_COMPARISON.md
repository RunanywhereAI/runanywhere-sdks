# ONNX Models Comparison

## Why Wav2Vec2 Instead of Whisper?

To properly test the ONNX Runtime integration, we're using **Wav2Vec2 Base** instead of Whisper Tiny. Here's why:

### ✅ Benefits of Using Different Models

| Aspect | WhisperKit (CoreML) | Wav2Vec2 (ONNX) | Benefit |
|--------|---------------------|-----------------|---------|
| **Architecture** | Whisper | Wav2Vec2 | Tests ONNX with different model type |
| **Framework** | CoreML | ONNX Runtime | Clear comparison of backends |
| **Vendor** | OpenAI | Facebook/Meta | Different model families |
| **Use Case** | Multi-language ASR | English ASR (optimized) | Complementary capabilities |

### 🎯 Testing Strategy

**Side-by-Side Comparison**:
- **Whisper Tiny (WhisperKit)** → Tests CoreML backend
- **Wav2Vec2 Base (ONNX)** → Tests ONNX backend

This lets you:
1. ✅ Compare performance between CoreML and ONNX
2. ✅ Test different model architectures
3. ✅ Verify ONNX works with non-Whisper models
4. ✅ See which is faster/more accurate for English

---

## Available ONNX ASR Models

### 1. Wav2Vec2 Base (Currently Used) ⭐

**Model**: `facebook/wav2vec2-base-960h`
**URL**: https://huggingface.co/darjusul/wav2vec2-ONNX-collection/resolve/main/facebook-wav2vec2-base-960h/model.onnx
**Size**: ~360 MB
**Language**: English
**Speed**: 2.2x faster than PyTorch on CPU

**Pros**:
- ✅ Single ONNX file (easy to test)
- ✅ Well-tested and proven
- ✅ Different from Whisper
- ✅ Facebook's ASR architecture

**Cons**:
- ⚠️ English only (but has multi-language variants)
- ⚠️ Larger than Whisper Tiny

---

### 2. Wav2Vec2 (Other Languages)

Available in the same collection:

**French**:
```
https://huggingface.co/darjusul/wav2vec2-ONNX-collection/resolve/main/facebook-wav2vec2-base-10k-voxpopuli-ft-fr/model.onnx
```

**German**:
```
https://huggingface.co/darjusul/wav2vec2-ONNX-collection/resolve/main/facebook-wav2vec2-base-10k-voxpopuli-ft-de/model.onnx
```

**Spanish**:
```
https://huggingface.co/darjusul/wav2vec2-ONNX-collection/resolve/main/facebook-wav2vec2-base-10k-voxpopuli-ft-es/model.onnx
```

**Italian**:
```
https://huggingface.co/darjusul/wav2vec2-ONNX-collection/resolve/main/facebook-wav2vec2-base-10k-voxpopuli-ft-it/model.onnx
```

---

### 3. Moonshine Tiny (Advanced)

**Model**: Moonshine by Useful Sensors
**Size**: 284 MB (4 ONNX files)
**Language**: English
**Year**: 2024 (Brand New!)

**Why It's Interesting**:
- ✅ Specifically designed for edge/mobile devices
- ✅ Optimized for Raspberry Pi
- ✅ State-of-the-art 2024 architecture
- ✅ MIT License

**Why Not Using Now**:
- ⚠️ Multiple ONNX files (preprocess, encode, cached_decode, uncached_decode)
- ⚠️ More complex integration
- ⚠️ Better suited for advanced testing

**Files**:
```
https://huggingface.co/UsefulSensors/moonshine/resolve/main/onnx/tiny/preprocess.onnx (6.8 MB)
https://huggingface.co/UsefulSensors/moonshine/resolve/main/onnx/tiny/encode.onnx (30.1 MB)
https://huggingface.co/UsefulSensors/moonshine/resolve/main/onnx/tiny/cached_decode.onnx (120 MB)
https://huggingface.co/UsefulSensors/moonshine/resolve/main/onnx/tiny/uncached_decode.onnx (128 MB)
```

---

### 4. Whisper ONNX (If You Want It)

**Model**: `whisper-tiny`
**URL**: https://huggingface.co/onnx-community/whisper-tiny/resolve/main/model.onnx
**Size**: ~39 MB
**Languages**: 99

**Why We're NOT Using It**:
- You already have Whisper Tiny via WhisperKit (CoreML)
- Testing the same model with different backends is less interesting
- Wav2Vec2 provides better comparison

**If You Want to Add It**:
Just uncomment or add another model to the registration list!

---

## Current App Configuration

### Registered Models:

1. **LLM Models** (LLMSwift - llama.cpp):
   - SmolLM2 360M
   - Qwen 2.5 0.5B
   - Llama 3.2 1B
   - SmolLM2 1.7B
   - Qwen 2.5 1.5B
   - LiquidAI LFM2 350M (Q4_K_M & Q8_0)

2. **STT Models**:
   - **WhisperKit (CoreML)**:
     - Whisper Tiny ← CoreML backend
     - Whisper Base ← CoreML backend
   - **ONNX Runtime**:
     - Wav2Vec2 Base ← ONNX backend

3. **Audio Diarization**:
   - FluidAudioDiarization

---

## Performance Comparison (Expected)

| Model | Backend | Size | Speed (estimated) | Quality |
|-------|---------|------|-------------------|---------|
| Whisper Tiny | CoreML | 39 MB | Very Fast | Good |
| Whisper Base | CoreML | 74 MB | Fast | Better |
| Wav2Vec2 Base | ONNX | 360 MB | Fast (2.2x vs PyTorch) | Good |

**Note**: Actual performance will vary based on:
- Device (iPhone 15 Pro vs iPhone 13)
- Implementation (once C++ backend is complete)
- Hardware acceleration used

---

## Adding More Models Later

Want to add more ONNX models? Just update the registration in `RunAnywhereAIApp.swift`:

```swift
try await RunAnywhere.registerFrameworkAdapter(
    ONNXAdapter.shared,
    models: [
        // Existing Wav2Vec2
        try! ModelRegistration(...),

        // Add more here!
        try! ModelRegistration(
            url: "https://huggingface.co/.../model.onnx",
            framework: .onnx,
            id: "model-id",
            name: "Model Name",
            format: .onnx,
            category: .speechRecognition,
            memoryRequirement: 100_000_000
        )
    ],
    options: lazyOptions
)
```

---

## Summary

**Current Setup**:
- WhisperKit provides Whisper models via CoreML
- ONNX Runtime provides Wav2Vec2 via ONNX
- Two different ASR architectures for comparison
- Clear differentiation between backends

**Ready to test!** 🚀
