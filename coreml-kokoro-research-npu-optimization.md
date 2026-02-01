# CoreML Kokoro TTS Model Research & NPU Optimization Insights

**Status**: RESEARCH COMPLETE
**Created**: 2026-01-31
**Purpose**: Analyze FluidInference CoreML Kokoro TTS model to extract insights for NNAPI optimization

---

## Executive Summary

FluidInference has successfully converted the Kokoro-82M TTS model to CoreML format for Apple Neural Engine (ANE) execution. This research documents their approach and extracts actionable insights for Android NNAPI optimization.

**Key Findings:**
1. **Fixed sequence lengths** are critical for NPU acceleration (5s, 10s, 15s model variants)
2. **Memory efficiency** improved from 4.85GB (PyTorch) to 1.5GB (CoreML)
3. **Real-time factor** of 23-28x achieved on Apple Neural Engine
4. **Trade-off**: Longer initial compilation (~15s) for faster inference
5. **No explicit quantization** - CoreML uses FP16 by default on ANE

---

## Part 1: CoreML Kokoro Model Architecture

### 1.1 Model Details

| Attribute | Value |
|-----------|-------|
| **Base Model** | hexgrad/Kokoro-82M (StyleTTS2 architecture) |
| **Parameters** | 82 million |
| **Architecture** | StyleTTS 2 + ISTFTNet vocoder |
| **Output** | 24 kHz mono audio |
| **Input** | Phoneme token IDs + voice style embedding |

### 1.2 Model Variants on HuggingFace

FluidInference publishes multiple fixed-shape variants:

```
FluidInference/kokoro-82m-coreml/
├── kokoro_21_5s.mlmodelc/    # 5 seconds max output
├── kokoro_21_10s.mlmodelc/   # 10 seconds max output
├── kokoro_21_15s.mlmodelc/   # 15 seconds max output
├── kokoro_24_10s.mlmodelc/   # v24 - 10 seconds
├── kokoro_24_15s.mlmodelc/   # v24 - 15 seconds
├── voices/                    # Voice embeddings
├── us_lexicon_cache.json     # Phoneme dictionary
└── vocab_index.json          # Token vocabulary
```

**Key Insight**: They create MULTIPLE models for different audio durations instead of using dynamic shapes. This is crucial for NPU optimization.

### 1.3 CoreML Conversion Process (via möbius)

From the [möbius](https://github.com/FluidInference/mobius) repository:

```python
# Conversion guidelines from möbius:
# 1. Trace with .CpuOnly compute unit first
# 2. Target iOS17+ / macOS 14+ for ANE features
# 3. Use fixed shapes - dynamic shapes fall back to CPU
# 4. Use uv for dependency management
```

The conversion flow:
1. **PyTorch → TorchScript** (via `torch.jit.trace`)
2. **TorchScript → CoreML** (via `coremltools`)
3. **CoreML → mlmodelc** (compiled format)

---

## Part 2: Performance Benchmarks

### 2.1 CoreML vs Other Runtimes (M4 Pro, 48GB)

| Runtime | Total Inference | RTF | Peak Memory | Notes |
|---------|----------------|-----|-------------|-------|
| **CoreML (Swift)** | 17.4s | 23.2x | 1.5 GB | **Lowest memory** |
| MLX Pipeline | 19.4s | 23.8x | 3.37 GB | Similar speed, 2x memory |
| PyTorch CPU | 27.2s | 17.0x | 4.85 GB | Highest memory |
| PyTorch MPS | Crashed | - | - | Unstable for long inputs |

### 2.2 Key Performance Observations

1. **Initial Compilation**: ~15s on first run (cached after)
2. **Warm-up**: ~2.3s for subsequent loads
3. **RTF Scaling**: Better RTF for longer audio (6x for 0.8s → 28x for 67s)
4. **Memory**: CoreML uses ~3x less memory than PyTorch

### 2.3 Per-Test Breakdown (CoreML)

| Test | Chars | Output Duration | Inference Time | RTF |
|------|-------|-----------------|----------------|-----|
| 1 | 42 | 2.8s | 440ms | 6.4x |
| 2 | 129 | 7.7s | 594ms | 13.0x |
| 9 | 1228 | 67.6s | 2362ms | 28.6x |
| 11 | 4269 | 247.6s | 9087ms | 27.2x |

**Insight**: NPU acceleration benefits scale with output length. Short utterances have high overhead.

---

## Part 3: ONNX Kokoro Model Analysis

### 3.1 Available ONNX Quantizations

The [onnx-community/Kokoro-82M-v1.0-ONNX](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX) repository provides:

| Model | Size | Precision | NNAPI Compatibility |
|-------|------|-----------|---------------------|
| model.onnx | 326 MB | FP32 | Partial (fallback to CPU) |
| model_fp16.onnx | 163 MB | FP16 | Partial (GPU on some devices) |
| model_quantized.onnx | 92.4 MB | INT8 | **Best for NNAPI NPU** |
| model_q8f16.onnx | 86 MB | Mixed INT8/FP16 | Good |
| model_uint8.onnx | 177 MB | UINT8 | Good |
| model_q4.onnx | 305 MB | INT4 matmul | Limited support |
| model_q4f16.onnx | 154 MB | INT4+FP16 | Limited support |

### 3.2 ONNX Conversion Challenges

From [adrianlyjak's conversion experience](https://www.adrianlyjak.com/p/onnx/):

**Issues Encountered:**
1. **LSTM layers not supported** in TorchDynamo export
2. **STFT with complex numbers** not supported in old-style export
3. **InstanceNorm1d export bug** requires `affine=True`
4. **Numerical discrepancies** in custom STFT layer

**Solutions Applied:**
1. Custom STFT rewrite without complex numbers
2. Fallback to torch.jit.trace instead of Dynamo
3. InstanceNorm fix with affine parameter

### 3.3 ONNX Quantization Best Practices

```python
# From ONNX conversion documentation:
# 1. Use QDQ format for NNAPI compatibility
# 2. Block-list sensitive layers from quantization
# 3. Use calibration data for accurate quantization

# Sensitive layers that should remain FP32:
# - First/last conv layers
# - Decoder output layers
# - STFT-related operations
```

---

## Part 4: CoreML vs ONNX/NNAPI Comparison

### 4.1 Optimization Approach Differences

| Aspect | CoreML (Apple ANE) | ONNX + NNAPI (Android) |
|--------|-------------------|----------------------|
| **Primary Optimization** | Fixed shapes, FP16 | INT8/UINT8 quantization |
| **Dynamic Shapes** | ❌ Falls back to CPU | ❌ Falls back to CPU |
| **Compilation** | Ahead-of-time (.mlmodelc) | Runtime or cached |
| **Quantization** | FP16 default, optional INT8 | INT8 for NPU, FP16 for GPU |
| **Memory Mapping** | Native support | Requires explicit setup |
| **Graph Optimization** | Automatic fusion | Manual or ORT optimizer |

### 4.2 Operator Support Comparison

**CoreML on ANE:**
- Excellent: Conv, MatMul, LayerNorm, GELU
- Good: Attention, Softmax
- Falls back: Custom ops, complex STFT

**NNAPI on Android NPUs:**
- Excellent: Conv2D, DepthwiseConv, MatMul
- Good: ReLU, Sigmoid, Tanh, Pooling
- Limited: Attention, LayerNorm (device-specific)
- Falls back: STFT, GroupNorm, complex control flow

### 4.3 Common Principles

Both CoreML and NNAPI benefit from:

1. **Fixed/static shapes** - No dynamic dimensions
2. **Standard ops** - Avoid custom operators
3. **Quantization** - INT8 for best NPU utilization
4. **Batch size 1** - Typical for on-device inference
5. **Memory-mapped weights** - Reduce loading time
6. **Caching** - Store compiled graphs

---

## Part 5: NNAPI Optimization Recommendations

### 5.1 Model Preparation

```python
# 1. Create fixed-shape variants (like CoreML approach)
FIXED_DURATIONS = [5, 10, 15]  # seconds

for duration in FIXED_DURATIONS:
    max_tokens = duration * tokens_per_second
    model = create_fixed_shape_model(max_tokens)
    onnx.save(model, f"kokoro_{duration}s.onnx")

# 2. Apply INT8 quantization with calibration
from onnxruntime.quantization import quantize_dynamic, QuantType

quantize_dynamic(
    "kokoro_10s.onnx",
    "kokoro_10s_int8.onnx",
    weight_type=QuantType.QInt8,
    optimize_model=True
)
```

### 5.2 NNAPI Session Configuration

Based on current SDK implementation and research:

```cpp
// Optimal NNAPI configuration for Kokoro TTS
NNAPIConfig config;
config.enabled = true;
config.use_fp16 = false;       // INT8 preferred for NPU
config.cpu_disabled = false;   // Allow fallback initially
config.use_nchw = true;        // NCHW format for NPU ops

// For verification (all ops on NPU):
config.cpu_disabled = true;    // Will fail if any op unsupported
```

### 5.3 QNN vs NNAPI Decision Matrix

| Scenario | Recommendation | Reason |
|----------|---------------|--------|
| Broad device support | NNAPI | Works on Qualcomm, Samsung, MediaTek |
| Qualcomm-only, max perf | QNN | Direct HTP access, context caching |
| INT8 quantized model | NNAPI preferred | Better coverage |
| FP32 model | QNN or CPU | NNAPI NPU needs quantization |
| App sandbox restricted | NNAPI | QNN needs DSP access |

### 5.4 Model Architecture Optimizations

**Remove/Replace problematic operators:**

| Problematic Op | Replacement | NNAPI Support |
|----------------|-------------|---------------|
| STFT (complex) | ISTFTNet vocoder | Better |
| GroupNorm | LayerNorm or BatchNorm | Good |
| Dynamic shapes | Fixed shapes | Required |
| Control flow | Unroll loops | Required |
| Einsum | Explicit MatMul | Better |

---

## Part 6: Implementation Checklist for RunAnywhere SDK

### 6.1 Already Implemented ✅

Based on current `kokoro_tts_loader.cpp`:

- [x] NNAPI session options creation
- [x] INT8 model detection by filename/size
- [x] NPU status tracking and logging
- [x] CPU fallback when NNAPI unavailable
- [x] NPU vs CPU benchmark function
- [x] Unified and split model support

### 6.2 Recommended Improvements

1. **Fixed-Shape Model Variants**
   ```
   models/kokoro_tts_5s_int8.onnx   # Short utterances
   models/kokoro_tts_10s_int8.onnx  # Medium
   models/kokoro_tts_15s_int8.onnx  # Long
   ```

2. **Smart Model Selection**
   ```cpp
   // Select model based on estimated output duration
   std::string select_model(size_t num_tokens) {
       float estimated_seconds = num_tokens / TOKENS_PER_SECOND;
       if (estimated_seconds <= 5) return "kokoro_5s_int8.onnx";
       if (estimated_seconds <= 10) return "kokoro_10s_int8.onnx";
       return "kokoro_15s_int8.onnx";
   }
   ```

3. **NNAPI Compilation Caching**
   ```cpp
   // Enable compilation caching for faster subsequent loads
   config.model_cache_dir = get_cache_dir();  // Already supported
   ```

4. **Operator Compatibility Verification**
   ```cpp
   // Run with cpu_disabled=true to verify 100% NPU execution
   config.cpu_disabled = true;
   bool fully_npu_compatible = load_and_verify(model_path);
   ```

### 6.3 Model Conversion Pipeline

```bash
# Recommended pipeline for Kokoro ONNX → NNAPI-optimized
1. Export from PyTorch with fixed shapes
2. Simplify with onnx-simplifier
3. Quantize to INT8 with calibration data
4. Verify with ONNX Runtime + NNAPI EP
5. Test on target devices (Samsung, Qualcomm, MediaTek)
```

---

## Part 7: Key Takeaways

### 7.1 From CoreML Success

1. **Fixed shapes are mandatory** for NPU acceleration
2. **Multiple model variants** handle different use cases
3. **FP16 is sufficient** for good quality audio
4. **Memory efficiency** is achievable (3x less than CPU)
5. **Initial compilation overhead** is acceptable with caching

### 7.2 For NNAPI Implementation

1. **INT8 quantization** is the path to NPU execution
2. **Static shapes** are just as important as on CoreML
3. **Model architecture matters** - avoid unsupported ops
4. **Hybrid execution** (NPU+CPU) is realistic
5. **Device-specific testing** is essential

### 7.3 Performance Expectations

| Metric | CoreML (ANE) | NNAPI (Expected) |
|--------|--------------|------------------|
| RTF | 23-28x | 15-25x (estimated) |
| Memory | 1.5 GB | 1.5-2.0 GB |
| Load time | 2-15s | 2-10s |
| INT8 quality | Excellent | Excellent |

---

## References

1. [FluidInference/kokoro-82m-coreml](https://huggingface.co/FluidInference/kokoro-82m-coreml)
2. [FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio)
3. [FluidInference/mobius](https://github.com/FluidInference/mobius)
4. [onnx-community/Kokoro-82M-v1.0-ONNX](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX)
5. [Apple CoreML Optimization Guide](https://apple.github.io/coremltools/docs-guides/source/opt-overview.html)
6. [ONNX Runtime NNAPI EP](https://onnxruntime.ai/docs/execution-providers/NNAPI-ExecutionProvider.html)
7. [ONNX Runtime QNN EP](https://onnxruntime.ai/docs/execution-providers/QNN-ExecutionProvider.html)
8. [Kokoro ONNX Export Blog](https://www.adrianlyjak.com/p/onnx/)
