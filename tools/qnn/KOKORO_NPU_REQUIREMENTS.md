# Kokoro TTS - Qualcomm NPU Acceleration Requirements

**Document Version:** 1.0
**Target Platform:** Qualcomm Snapdragon 8 Gen 3 (SM8650) and newer
**Target Hardware:** Hexagon Tensor Processor (HTP) NPU

---

## Executive Summary

To achieve NPU-accelerated inference for Kokoro TTS on Qualcomm devices, the model requires architectural modifications. The current ONNX export contains control flow operators (`Loop`, `If`, `SplitToSequence`) that are fundamentally incompatible with Qualcomm's HTP NPU.

**Expected Performance Improvement:** 6-10x faster inference vs CPU-only execution

---

## Problem: Incompatible ONNX Operators

### Current Kokoro Model Analysis

```
Total operators: 4,383
NPU-compatible:  4,377 (99.9%)
NPU-blocking:        6 (0.1%)
```

### Blocking Operators

| Operator | Count | Location | Why It Blocks NPU |
|----------|-------|----------|-------------------|
| `Loop` | 1 | Duration expansion | HTP requires static compute graphs |
| `If` | 2 | Conditional paths | No branching on NPU |
| `SplitToSequence` | 2 | Sequence handling | Dynamic sequence ops unsupported |
| `ConcatFromSequence` | 1 | Sequence merging | Dynamic sequence ops unsupported |

**Root Cause:** The duration expansion loop iterates a variable number of times based on predicted durations. NPU requires all tensor shapes and iteration counts known at compile time.

---

## Solution: Two-Stage Model Architecture

Split Kokoro into two separate ONNX models:

### Stage 1: Duration Predictor (CPU)
- **Runs on:** CPU (acceptable - only ~5-10% of compute)
- **Input:** Text tokens, voice embedding
- **Output:** Per-phoneme durations, encoded features

### Stage 2: Decoder (NPU)
- **Runs on:** Qualcomm HTP NPU (90%+ of compute)
- **Input:** Pre-aligned features (fixed shape)
- **Output:** Audio waveform (fixed shape)

```
┌─────────────────────────────────────────────────────────────────┐
│                        CURRENT MODEL                            │
│  Text → [Encoder] → [Duration Loop] → [Decoder] → Audio        │
│                         ↑ BLOCKED                               │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                     PROPOSED SPLIT                              │
│                                                                 │
│  ┌──────────────────────┐     ┌────────────────────────────┐   │
│  │ Stage 1 (CPU)        │     │ Stage 2 (NPU)              │   │
│  │ • Text encoding      │     │ • Feature decoding         │   │
│  │ • Duration predict   │ ──► │ • Waveform generation      │   │
│  │ • Voice embedding    │     │ • All Conv/MatMul ops      │   │
│  └──────────────────────┘     └────────────────────────────┘   │
│           5-10%                        90-95%                   │
│         of compute                   of compute                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Technical Requirements

### Stage 1: Duration Predictor Model

**File:** `kokoro_duration.onnx`

**Inputs:**
| Name | Shape | Type | Description |
|------|-------|------|-------------|
| `tokens` | `[1, max_tokens]` | INT64 | Phoneme token IDs |
| `token_length` | `[1]` | INT64 | Actual token count |
| `voice_embedding` | `[1, embed_dim]` | FLOAT32 | Speaker embedding |

**Outputs:**
| Name | Shape | Type | Description |
|------|-------|------|-------------|
| `durations` | `[1, max_tokens]` | INT32 | Per-phoneme frame counts |
| `encoded_text` | `[1, max_tokens, hidden_dim]` | FLOAT32 | Encoded text features |
| `ref_style` | `[1, style_dim]` | FLOAT32 | Reference style vector |

**Constraints:**
- Can contain `Loop`, `If`, LSTM, attention - these run on CPU
- Dynamic shapes are acceptable
- No modifications needed from current architecture

### Stage 2: Decoder Model

**File:** `kokoro_decoder.onnx`

**Inputs:**
| Name | Shape | Type | Description |
|------|-------|------|-------------|
| `aligned_features` | `[1, hidden_dim, max_frames]` | FLOAT32 | Aligned encoder output |
| `f0_contour` | `[1, 1, max_frames]` | FLOAT32 | Pitch contour |
| `noise` | `[1, noise_dim, max_frames]` | FLOAT32 | Noise input for flow |
| `ref_style` | `[1, style_dim]` | FLOAT32 | Reference style |

**Outputs:**
| Name | Shape | Type | Description |
|------|-------|------|-------------|
| `audio` | `[1, max_samples]` | FLOAT32 | Raw audio waveform |

**CRITICAL CONSTRAINTS:**
1. **NO control flow operators:** Remove all `Loop`, `If`, `SplitToSequence`, `SequenceAt`, `ConcatFromSequence`
2. **Static shapes:** All dimensions must be fixed integers
3. **Export method:** Use `torch.jit.trace()` NOT `torch.jit.script()`
4. **Supported ops only:** Stick to Conv, MatMul, Add, Mul, Reshape, Transpose, Softmax, LayerNorm, GELU

---

## Recommended Fixed Dimensions

### Option A: Single Fixed-Size Model
```python
MAX_TOKENS = 256      # ~50 words
MAX_FRAMES = 2048     # ~8.5 seconds at 24kHz / 256 hop
MAX_SAMPLES = 192000  # 8 seconds at 24kHz
```

### Option B: Multiple Bucket Models (Recommended)
Create 3 decoder variants for different audio lengths:

| Bucket | Max Frames | Max Audio | Use Case |
|--------|------------|-----------|----------|
| `kokoro_decoder_3s.onnx` | 512 | 3 sec | Short responses |
| `kokoro_decoder_10s.onnx` | 1536 | 10 sec | Medium sentences |
| `kokoro_decoder_45s.onnx` | 6144 | 45 sec | Long paragraphs |

**SDK selects appropriate bucket based on predicted total duration.**

---

## PyTorch Export Guide

### Step 1: Separate the Models

```python
class KokoroDurationPredictor(nn.Module):
    """Stage 1: Runs on CPU - can have dynamic ops"""
    def __init__(self, full_model):
        super().__init__()
        self.text_encoder = full_model.text_encoder
        self.duration_predictor = full_model.duration_predictor
        self.style_encoder = full_model.style_encoder

    def forward(self, tokens, token_length, voice_embedding):
        # Text encoding
        encoded = self.text_encoder(tokens, token_length)

        # Duration prediction (can use LSTM, attention, etc.)
        durations = self.duration_predictor(encoded, voice_embedding)

        # Style extraction
        ref_style = self.style_encoder(voice_embedding)

        return durations, encoded, ref_style


class KokoroDecoder(nn.Module):
    """Stage 2: Must be NPU-compatible - NO control flow"""
    def __init__(self, full_model):
        super().__init__()
        self.decoder = full_model.decoder
        self.flow = full_model.flow  # If using flow-matching

    def forward(self, aligned_features, f0, noise, ref_style):
        # IMPORTANT: No loops, no conditionals
        # All operations must be static tensor ops

        # Decode features to audio
        audio = self.decoder(aligned_features, f0, noise, ref_style)

        return audio
```

### Step 2: Export with Tracing (NOT Scripting)

```python
# Duration predictor - script is OK (runs on CPU)
duration_model = KokoroDurationPredictor(full_model)
torch.onnx.export(
    duration_model,
    (dummy_tokens, dummy_length, dummy_voice),
    "kokoro_duration.onnx",
    input_names=["tokens", "token_length", "voice_embedding"],
    output_names=["durations", "encoded_text", "ref_style"],
    dynamic_axes={
        "tokens": {1: "seq_len"},
        "encoded_text": {1: "seq_len"},
        "durations": {1: "seq_len"}
    },
    opset_version=17
)

# Decoder - MUST use trace to unroll any loops
decoder_model = KokoroDecoder(full_model)
decoder_model.eval()

# Create fixed-size dummy inputs
MAX_FRAMES = 2048
dummy_aligned = torch.randn(1, 512, MAX_FRAMES)
dummy_f0 = torch.randn(1, 1, MAX_FRAMES)
dummy_noise = torch.randn(1, 256, MAX_FRAMES)
dummy_style = torch.randn(1, 256)

# CRITICAL: Use trace, not script
traced_decoder = torch.jit.trace(
    decoder_model,
    (dummy_aligned, dummy_f0, dummy_noise, dummy_style)
)

torch.onnx.export(
    traced_decoder,
    (dummy_aligned, dummy_f0, dummy_noise, dummy_style),
    "kokoro_decoder.onnx",
    input_names=["aligned_features", "f0_contour", "noise", "ref_style"],
    output_names=["audio"],
    # NO dynamic_axes - all shapes must be fixed
    opset_version=17
)
```

### Step 3: Verify No Blocking Ops

```python
import onnx

def check_for_blocking_ops(model_path):
    model = onnx.load(model_path)
    blocking = ["Loop", "If", "SplitToSequence", "SequenceAt",
                "ConcatFromSequence", "Scan", "SequenceConstruct"]

    found = []
    for node in model.graph.node:
        if node.op_type in blocking:
            found.append(node.op_type)

    if found:
        print(f"❌ BLOCKING OPS FOUND: {found}")
        return False
    else:
        print("✅ No blocking ops - NPU compatible!")
        return True

# Decoder must pass this check
assert check_for_blocking_ops("kokoro_decoder.onnx")
```

---

## SDK Runtime Responsibilities

The RunAnywhere SDK will handle:

### 1. Alignment Matrix Construction
The SDK replaces the ONNX `Loop` operator with runtime code:

```kotlin
fun buildAlignmentMatrix(
    encodedText: FloatArray,  // [1, seq_len, hidden_dim]
    durations: IntArray,      // [seq_len]
    maxFrames: Int
): FloatArray {
    val seqLen = durations.size
    val hiddenDim = encodedText.size / seqLen
    val totalFrames = durations.sum().coerceAtMost(maxFrames)

    // Output: [1, hidden_dim, totalFrames]
    val aligned = FloatArray(hiddenDim * maxFrames)

    var frameIdx = 0
    for (phonemeIdx in 0 until seqLen) {
        val dur = durations[phonemeIdx]
        for (d in 0 until dur) {
            if (frameIdx >= maxFrames) break
            // Copy hidden features for this phoneme
            for (h in 0 until hiddenDim) {
                aligned[h * maxFrames + frameIdx] =
                    encodedText[phonemeIdx * hiddenDim + h]
            }
            frameIdx++
        }
    }

    return aligned
}
```

### 2. Bucket Selection
```kotlin
fun selectDecoderBucket(totalFrames: Int): DecoderModel {
    return when {
        totalFrames <= 512  -> decoderBuckets["3s"]!!
        totalFrames <= 1536 -> decoderBuckets["10s"]!!
        else                -> decoderBuckets["45s"]!!
    }
}
```

### 3. Audio Trimming
```kotlin
fun trimAudio(audio: FloatArray, actualFrames: Int, hopLength: Int = 256): FloatArray {
    val actualSamples = actualFrames * hopLength
    return audio.copyOf(actualSamples)
}
```

---

## Validation Checklist

Before delivering the split models, verify:

- [ ] `kokoro_duration.onnx` loads and runs on ONNX Runtime CPU
- [ ] `kokoro_decoder.onnx` contains NO blocking operators
- [ ] Decoder has all fixed shapes (no dynamic dimensions)
- [ ] Decoder compiles successfully on Qualcomm AI Hub
- [ ] End-to-end audio quality matches original model
- [ ] Latency improvement observed on target device

### Qualcomm AI Hub Compilation Test

```bash
pip install qai-hub

# This should succeed if decoder is NPU-compatible
python -c "
import qai_hub as hub
hub.submit_compile_job(
    model='kokoro_decoder.onnx',
    device=hub.Device('Samsung Galaxy S24'),
    options='--target_runtime qnn_context_binary'
)
"
```

---

## Reference: kokoro-coreml Implementation

The [kokoro-coreml](https://github.com/nickarls/kokoro-coreml) project successfully uses this two-stage approach for Apple Neural Engine:

- `KokoroTextEncoder.mlpackage` - Text encoding + duration prediction
- `KokoroDecode.mlpackage` - Audio decoding (runs on ANE)

This validates that the architectural split works and maintains audio quality.

---

## Contact & Support

For questions about SDK integration:
- **Repository:** https://github.com/RunanywhereAI/runanywhere-sdks
- **Email:** founders@runanywhere.ai

---

## Appendix: QNN-Compatible ONNX Operators

### Fully Supported (NPU)
`Add`, `BatchNormalization`, `Cast`, `Clip`, `Concat`, `Conv`, `ConvTranspose`, `Div`, `Elu`, `Exp`, `Flatten`, `Gather`, `Gemm`, `GlobalAveragePool`, `GlobalMaxPool`, `HardSigmoid`, `HardSwish`, `InstanceNormalization`, `LayerNormalization`, `LeakyRelu`, `Log`, `LogSoftmax`, `MatMul`, `MaxPool`, `Mul`, `Neg`, `Pad`, `Pow`, `PRelu`, `ReduceMean`, `ReduceSum`, `Relu`, `Reshape`, `Resize`, `Sigmoid`, `Slice`, `Softmax`, `Split`, `Sqrt`, `Squeeze`, `Sub`, `Tanh`, `Tile`, `Transpose`, `Unsqueeze`

### Partially Supported (May fallback to CPU)
`Attention`, `GELU`, `GroupNormalization`, `ScatterND`, `Where`

### NOT Supported (Blocks NPU compilation)
`Loop`, `If`, `Scan`, `SequenceAt`, `SplitToSequence`, `ConcatFromSequence`, `SequenceConstruct`, `SequenceInsert`, `SequenceErase`, `RandomNormalLike`, `RandomUniformLike`, `NonZero`
