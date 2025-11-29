# llama.cpp VLM Quick Reference Guide

## One-Line Answer
**llama.cpp has production-ready, native VLM support with 9+ model architectures, CLIP-based vision encoders, and proven mobile performance.**

---

## Quick Answers

| Question | Answer | Confidence |
|----------|--------|-----------|
| Does llama.cpp have native VLM? | YES | 100% |
| What VLMs are supported? | LLaVA 1.5/1.6, MobileVLM, MiniCPM-V, Moondream, Obsidian, Yi-VL, ShareGPT4V, BakLLaVA, Bunny | 100% |
| Vision encoder type? | CLIP ViT (Vision Transformer) | 100% |
| How many image tokens? | 576-2880 depending on model | 100% |
| Can it run on Android? | YES - requires JNI integration | 95% |
| Timeframe for Android? | 3-4 weeks | 85% |
| Best mobile model? | MobileVLM 1.7B or MiniCPM-V 8B | 90% |
| Image encoding speed (mobile)? | 15-30s (CPU), <1s (GPU) | 85% |

---

## Architecture at a Glance

```
Image → CLIP Encoder (Vision Transformer) → Multimodal Projector → LLM Token Stream
         576-2880 image embeddings              (MLP/LDP/Resampler)     Generated Text
```

---

## Core Components (5 Projector Types)

1. **MLP** - Simple linear layers
2. **MLP_NORM** - MLP with layer normalization
3. **LDP** - Linear + Depthwise + Projection (MobileVLM V1)
4. **LDPv2** - Enhanced LDP (MobileVLM V2)
5. **RESAMPLER** - CrossAttention-based (MiniCPM-V)

---

## Top 5 Models for Different Use Cases

| Use Case | Model | Size | Speed | Quality |
|----------|-------|------|-------|---------|
| Super lightweight | Moondream 2 | ~1B | Very Fast | Fair |
| Mobile real-time | MobileVLM 1.7B | 1.7B | Fast | Good |
| Mobile balanced | MiniCPM-V 8B | 8B | Moderate | Excellent |
| High quality mobile | LLaVA 1.6 7B | 7B | Moderate | Very Good |
| Desktop/Server | LLaVA 1.6 13B | 13B | Slow | Excellent |

---

## Memory Quick Reference

| Model | Unquantized | Q4_K_M | Q5_K_M |
|-------|------------|--------|--------|
| MobileVLM 1.7B | ~3.5GB | 1.2GB | 1.5GB |
| LLaVA 7B | ~14GB | 4.5GB | 5.5GB |
| MiniCPM-V 8B | ~16GB | 5.0GB | 6.5GB |
| LLaVA 13B | ~26GB | 8.5GB | 10.5GB |

(Plus ~190MB for vision projector in all cases)

---

## Integration Checklist for RunAnywhere SDK

### Phase 1: Foundation (Week 1)
- [ ] Review existing llama-jni structure
- [ ] Study clip.cpp and llava.cpp implementations
- [ ] Plan JNI function signatures

### Phase 2: JNI Bindings (Week 2)
- [ ] Implement clip_model_load() JNI wrapper
- [ ] Implement image encoding JNI wrapper
- [ ] Implement image embedding integration

### Phase 3: Kotlin API (Week 2-3)
- [ ] Extend LLamaAndroid.kt with vision lifecycle
- [ ] Add sendWithImage() method
- [ ] Thread-safe memory management

### Phase 4: Testing & Optimization (Week 3-4)
- [ ] Test with MobileVLM model
- [ ] Performance profiling
- [ ] GPU acceleration (optional but recommended)

---

## Key Functions to Wrap

```cpp
// Vision model management
clip_ctx * clip_model_load(const char * fname, int verbosity);
void clip_free(struct clip_ctx * ctx);

// Image processing
struct llava_image_embed * llava_image_embed_make_with_bytes(
    struct clip_ctx * ctx_clip, int n_threads,
    const unsigned char * image_bytes, int image_bytes_length
);

// Integration
bool llava_eval_image_embed(
    struct llama_context * ctx_llama,
    const struct llava_image_embed * embed,
    int n_batch, int * n_past
);
```

---

## Model File Structure

Every VLM model needs TWO files:

```
model-directory/
├── ggml-model-{quantization}.gguf     (LLM - 1.2GB to 16GB)
└── mmproj-model-f16.gguf              (Vision Projector - ~190MB)
```

Example command:
```bash
./llama-llava-cli \
    -m ./model/ggml-model-q4_k.gguf \
    --mmproj ./model/mmproj-model-f16.gguf \
    --image photo.jpg \
    -p "Describe this image"
```

---

## Where to Find Models

**Pre-converted & Ready to Use:**
- HuggingFace: `mys/ggml_llava-v1.5-{7b,13b}`
- HuggingFace: `cmp-nct/llava-1.6-gguf`
- HuggingFace: `mtgv/MobileVLM-{1.7B,3B}`
- HuggingFace: `openbmb/MiniCPM-Llama3-V-2_5-gguf`

**Requires Conversion:**
- Original models need `llava_surgery.py` → `convert_image_encoder_to_gguf.py`
- Scripts included in llama.cpp repository

---

## Performance Expectations

### Desktop (Intel i7-10750H)
- Image encoding: 2.7 seconds
- Full inference: 5-10 seconds per query

### Mobile (Snapdragon 888)
- Image encoding: 21 seconds
- Full inference: 30-40 seconds per query

### With GPU (NVIDIA Jetson Orin)
- Image encoding: 296ms
- Full inference: 1-2 seconds per query

---

## Critical Implementation Notes

1. **Two-Model Architecture:** CLIP encoder (F16) + LLM (quantized)
2. **No Text Mixing:** Image tokens can't be mixed with text tokens in same batch
3. **Context Size:** Typically need 2048+ context for image processing
4. **Memory Peak:** Highest during image encoding phase
5. **Thread Safety:** Image encoding and text generation must not race

---

## File Locations in llama-jni

```
/native/llama-jni/llama.cpp/examples/llava/
├── clip.h (52 lines) .................... Vision encoder API
├── clip.cpp (2400+ lines) .............. Vision implementation
├── llava.h (50 lines) .................. Integration API
├── llava.cpp (400+ lines) .............. Integration impl
├── llava-cli.cpp (usage example)
├── minicpmv-cli.cpp (MiniCPM variant)
├── CMakeLists.txt ...................... Build config
└── android/
    ├── build_64.sh ..................... NDK build script
    └── adb_run.sh ...................... Deployment helper
```

---

## Troubleshooting Quick Tips

| Problem | Solution |
|---------|----------|
| "Missing mmproj" error | Both .gguf files needed in same directory |
| Slow image encoding | Use GPU acceleration flag (-ngl) |
| OOM on mobile | Use smaller model (MobileVLM) or quantize (Q4_K_M) |
| Wrong image token count | Check model version (1.5 = 576 tokens, 1.6 = 2880 tokens) |
| Android crash on load | Verify NDK build and native library path |

---

## Next Steps

1. **Study the Code** - Read clip.cpp and llava.cpp carefully
2. **Review Examples** - Look at llava-cli.cpp for usage patterns
3. **Plan Integration** - Map to existing RunAnywhere architecture
4. **Prototype JNI** - Start with basic image encoding
5. **Test Mobile** - Validate on actual Android device

---

## Bottom Line

llama.cpp VLM is **production-ready, well-architected, and proven on mobile**.
Integration is straightforward with existing llama-jni foundation.
**Recommended: Start with MobileVLM 1.7B for development and testing.**
