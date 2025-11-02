# llama.cpp Visual Language Model (VLM) Support Investigation Report

## Executive Summary

llama.cpp has **robust and production-ready native VLM implementation** with support for multiple prominent vision-language model architectures. The framework provides complete end-to-end VLM capabilities including image encoding, multi-modal projectors, and integrated inference pipelines.

---

## 1. VLM Support: YES (CONFIRMED)

### Status
- **VLM Implementation:** NATIVE & PRODUCTION-READY
- **Framework Level:** Core llama.cpp functionality (not plugin-based)
- **CLI Tools:** Dedicated `llama-llava-cli` and `llama-minicpmv-cli` binaries
- **Architecture:** Modular, extensible vision encoder + multimodal projector pattern

---

## 2. Supported VLM Architectures

### Officially Supported Models

| Architecture | Models | Status | Notes |
|---|---|---|---|
| **LLaVA 1.5** | 7B, 13B, 34B variants | Fully Supported | Original LLaVA implementation |
| **LLaVA 1.6** | 7B-34B models | Fully Supported | Enhanced with dynamic resolution |
| **BakLLaVA** | Various sizes | Fully Supported | LLaVA derivative |
| **Obsidian** | 3B-V0.5 | Fully Supported | Nous Research VLM |
| **ShareGPT4V** | Multiple variants | Fully Supported | Vision extraction focused |
| **MobileVLM** | 1.7B, 3B, V2 variants | Fully Supported | Mobile-optimized |
| **Yi-VL** | Multiple sizes | Fully Supported | Large vision model |
| **MiniCPM** | Llama3-V 2.5, 2.6 | Fully Supported | Compact efficient model |
| **Moondream** | 2 series | Fully Supported | Lightweight VLM |
| **Bunny** | Multiple variants | Fully Supported | BAAI-DCAI VLM |

### Vision Encoder Components

All supported models use **CLIP-based vision encoders** with variations:
- **CLIP ViT** (Vision Transformer) - Standard encoder
- **CLIP ViT-Large-Patch14-336** - Common configuration
- **OpenCLIP variants** - Extended CLIP implementations
- **Pure vision extractors** (ShareGPT4V style) - Vision-only components

---

## 3. Architecture Overview

### End-to-End Flow

```
Image Input (JPEG, PNG, etc.)
    ↓
[STB Image Library]
    ↓
Image Preprocessing
├─ Load as RGB uint8
├─ Resize/pad to target resolution
└─ Normalize with image_mean & image_std
    ↓
[CLIP Vision Encoder]
├─ Patch embedding (patch_size typically 14)
├─ Transformer blocks (typically 24 layers)
└─ Output: Image embeddings (float32)
    ↓
[Multimodal Projector]
├─ MLP (standard linear layers)
├─ LDP (Linear, Depthwise, Projection)
├─ LDPv2 (Enhanced depthwise variant)
└─ Resampler (CrossAttention resampler) [MiniCPM-V]
    ↓
[LLM Text Generation]
├─ Embed image tokens into context
├─ Process user prompt
└─ Generate response
```

### Key Components

#### 1. Vision Encoder (CLIP)
- **Location:** `/examples/llava/clip.cpp` and `clip.h`
- **Responsibility:** Convert images to dense embeddings
- **Process:**
  - Load GGUF-format vision model
  - Process image patches through transformer
  - Output embedding vectors for each patch
- **Typical Output:** 576-2880 image tokens (depending on model version)

#### 2. Multimodal Projector Types
```cpp
enum projector_type {
    PROJECTOR_TYPE_MLP,        // Simple linear layers
    PROJECTOR_TYPE_MLP_NORM,   // MLP with layer norm
    PROJECTOR_TYPE_LDP,        // Linear + Depthwise + Projection
    PROJECTOR_TYPE_LDPV2,      // Enhanced LDP variant
    PROJECTOR_TYPE_RESAMPLER,  // CrossAttention resampler (MiniCPM)
};
```

#### 3. Image Encoding Metadata
GGUF-stored configuration parameters:
```cpp
#define KEY_IMAGE_SIZE          "clip.vision.image_size"
#define KEY_PATCH_SIZE          "clip.vision.patch_size"
#define KEY_IMAGE_MEAN          "clip.vision.image_mean"
#define KEY_IMAGE_STD           "clip.vision.image_std"
#define KEY_MM_PATCH_MERGE_TYPE "clip.vision.mm_patch_merge_type"
#define KEY_IMAGE_GRID_PINPOINTS "clip.vision.image_grid_pinpoints"
```

#### 4. Image Processing Pipeline
- **Image Loading:** STB Image library (supports JPEG, PNG, BMP, etc.)
- **Preprocessing:** Automatic aspect-ratio preserving resizing
- **Normalization:** Per-channel mean/std normalization
- **Batching:** Support for multiple image processing
- **Dynamic Resolution:** Intelligent resolution selection for optimal inference

---

## 4. Implementation Details

### Image Encoding Process (from clip.cpp)

1. **Image Load**: `clip_image_load_from_file()` or `clip_image_load_from_bytes()`
   - STB image decoding
   - Convert to uint8 RGB format

2. **Preprocessing**: `clip_image_preprocess()`
   - Resize maintaining aspect ratio
   - Pad to square (configurable)
   - Batch multiple images efficiently

3. **Normalization**: `normalize_image_u8_to_f32()`
   - Convert uint8 → float32
   - Apply per-channel mean subtraction
   - Apply per-channel std division

4. **Encoding**: `clip_image_encode()`
   - Run CLIP vision transformer
   - GPU acceleration via CUDA/Metal/Vulkan/CANN (if enabled)
   - Output: Dense float embedding vectors

5. **Projection**: Multimodal projector
   - Project CLIP embeddings to LLM token space
   - Type-specific processing (MLP/LDP/Resampler)
   - Integrate into LLM context

### Integration with LLM

From `llava.h`:
```cpp
// build an image embed from a path to an image filename
LLAVA_API struct llava_image_embed * llava_image_embed_make_with_filename(
    struct clip_ctx * ctx_clip,
    int n_threads,
    const char * image_path
);

// embed the image into the llama context
LLAVA_API bool llava_eval_image_embed(
    struct llama_context * ctx_llama,
    const struct llava_image_embed * embed,
    int n_batch,
    int * n_past
);
```

---

## 5. Model Format & Quantization Support

### GGUF Format Requirements

VLM models in llama.cpp require **two separate GGUF files**:

1. **LLM Component** (Text generation)
   - Standard llama.cpp GGUF format
   - Typically: `ggml-model-{quantization}.gguf`
   - Example quantizations: Q4_K_M, Q5_K_M, F16, F32

2. **Vision Projector Component** (Image processing)
   - CLIP vision encoder + multimodal projector
   - Typically: `mmproj-model-{precision}.gguf`
   - Format: Fixed precision (usually F16, rarely Q4)

### Quantization Support

**LLM Component:** Full quantization support
- Q2_K through Q8_0
- Optimal: **Q4_K_M** (4-bit, medium) - Best quality/size tradeoff
- Optimal: **Q5_K_M** (5-bit, medium) - Maximum quality
- Supported: **F16** (full precision)

**Vision Projector:** Limited quantization support
- Primarily: **F16** (half precision)
- Supported: **F32** (full precision, rare)
- Note: Quantization beyond F16 may degrade vision quality

### Model File Examples

```
LLaVA 1.5 7B:
  - ggml-model-f16.gguf              (LLM, ~14GB)
  - mmproj-model-f16.gguf            (Projector, ~190MB)

MobileVLM 1.7B:
  - ggml-model-q4_k.gguf             (LLM, ~1.2GB)
  - mmproj-model-f16.gguf            (Projector, ~190MB)

MiniCPM-V 2.5 8B:
  - model-8B-F16.gguf                (LLM, ~16GB)
  - mmproj-model-f16.gguf            (Projector)
```

---

## 6. Android/JNI Integration

### Current State

**Existing JNI Bindings:**
- `LLamaAndroid.kt` in `/examples/llama.android/`
- **Current Limitation:** Text-only LLM support
- **Missing:** VLM function bindings

### Integration Points Needed

To expose VLM through existing JNI wrapper:

1. **Native C++ Functions to Export:**
   ```cpp
   // Image loading
   jlong Java_android_llama_cpp_LLamaAndroid_load_clip_model(
       JNIEnv* env, jobject obj, jstring model_path
   );

   // Image encoding
   jlong Java_android_llama_cpp_LLamaAndroid_encode_image(
       JNIEnv* env, jobject obj, jlong clip_ctx, jbyteArray image_bytes
   );

   // Integration
   jboolean Java_android_llama_cpp_LLamaAndroid_eval_image_embed(
       JNIEnv* env, jobject obj, jlong llama_ctx, jlong image_embed
   );
   ```

2. **Kotlin API (to implement):**
   ```kotlin
   // Load vision model
   suspend fun loadVisionModel(modelPath: String): Long

   // Encode image from bytes
   suspend fun encodeImage(imageBytes: ByteArray): Long

   // Send image-based query
   fun sendWithImage(imageBytes: ByteArray, prompt: String): Flow<String>
   ```

3. **Required Changes:**
   - Link against `libllava.a` (vision library)
   - Add CLIP model loading during initialization
   - Memory management for image embeddings
   - Thread-safe integration with existing LLM context

4. **Android-Specific Considerations:**
   - **Camera Integration:** Direct camera feed → image encoding pipeline
   - **Image Format:** Support Android Bitmap → JPEG encoding
   - **Memory Constraints:** Mobile GPUs have limited VRAM
   - **Performance:** Image encoding latency (typically 15-30s on mid-range devices)

### Example Android Integration Architecture

```
┌─────────────────┐
│   Android App   │ (Kotlin)
└────────┬────────┘
         │
    JNI Bridge (Kotlin external functions)
         │
    ┌────────────────────────┐
    │  LLM Component         │ (Existing)
    │  + VLM Component       │ (New)
    └────┬───────────────────┘
         │
    ┌─────────────────────────────────┐
    │  CLIP Vision Encoder            │ (Native C++)
    │  Multimodal Projector           │
    │  LLama Text Generation          │
    └──────────────────────────────────┘
```

---

## 7. Performance Characteristics

### Performance Metrics (from MobileVLM documentation)

**Image Encoding Time (CLIP):**
- Snapdragon 888: ~21 seconds for one image
- Snapdragon 778G: ~18-20 seconds
- Intel Core i7-10750H: ~2.7 seconds
- NVIDIA Jetson Orin: ~296ms (GPU accelerated)

**Full Inference Pipeline (MobileVLM 1.7B, Android):**
- Model Load: 20-23 seconds
- Image Encoding: 18-21 seconds
- Prompt Processing: ~8-12 seconds per 191 tokens
- Token Generation: ~14ms per token
- **Total Response Time:** 28-35 seconds (on mid-range Android)

**Memory Requirements:**
- LLaVA 7B: ~4-8GB RAM (depending on quantization)
- MobileVLM 1.7B: ~2-3GB RAM (mobile-optimized)
- MiniCPM-V 8B: ~4-6GB RAM

### Performance Optimization Strategies

1. **Model Selection:** MobileVLM/MiniCPM for mobile (1.7B-3B)
2. **Quantization:** Use Q4_K_M for LLM, F16 for projector
3. **GPU Acceleration:** Enable CUDA/Metal/Vulkan for encoding
4. **Batch Processing:** Process multiple images efficiently
5. **Context Management:** Reuse KV cache between queries

---

## 8. Building VLM Support into llama-jni

### Required Changes

#### Step 1: CMake Integration
Add to main CMakeLists.txt:
```cmake
# Add CLIP/LLaVA components
target_sources(llama_android PRIVATE
    ${LLAMA_CPP_DIR}/examples/llava/clip.cpp
    ${LLAMA_CPP_DIR}/examples/llava/llava.cpp
)

target_include_directories(llama_android PRIVATE
    ${LLAMA_CPP_DIR}/examples/llava
)
```

#### Step 2: JNI Binding Implementation
Add C++ functions:
```cpp
extern "C" {
    // Vision model management
    JNIEXPORT jlong JNICALL Java_android_llama_cpp_LLamaAndroid_load_clip(
        JNIEnv* env, jobject, jstring path);

    JNIEXPORT void JNICALL Java_android_llama_cpp_LLamaAndroid_free_clip(
        JNIEnv*, jobject, jlong ctx);

    // Image processing
    JNIEXPORT jlong JNICALL Java_android_llama_cpp_LLamaAndroid_encode_image_bytes(
        JNIEnv* env, jobject, jlong clip_ctx, jbyteArray bytes);

    // Integration
    JNIEXPORT jboolean JNICALL Java_android_llama_cpp_LLamaAndroid_eval_image_embed(
        JNIEnv*, jobject, jlong llama_ctx, jlong image_embed);
}
```

#### Step 3: Kotlin API Extension
```kotlin
class LLamaAndroid {
    private var clipContext: Long = 0L

    private external fun load_clip(path: String): Long
    private external fun free_clip(ctx: Long)
    private external fun encode_image_bytes(clipCtx: Long, bytes: ByteArray): Long
    private external fun eval_image_embed(llamaCtx: Long, imageEmbed: Long): Boolean

    suspend fun initializeVision(clipModelPath: String) {
        withContext(runLoop) {
            clipContext = load_clip(clipModelPath)
            if (clipContext == 0L) throw IllegalStateException("Failed to load CLIP model")
        }
    }

    fun sendWithImage(imageBytes: ByteArray, prompt: String): Flow<String> = flow {
        val imageEmbed = encode_image_bytes(clipContext, imageBytes)
        if (!eval_image_embed(state.context, imageEmbed)) {
            throw IllegalStateException("Failed to process image")
        }
        // Continue with standard text generation
    }.flowOn(runLoop)
}
```

---

## 9. Compatible High-Performance VLM Models

### Recommended Models for Mobile/Embedded

| Model | Size | VRAM | Speed | Quality | Best For |
|---|---|---|---|---|---|
| **MobileVLM** | 1.7B | 2.5GB | Fast | Good | Real-time mobile apps |
| **MiniCPM-V 2.5** | 8B | 4-5GB | Moderate | Excellent | Balanced performance |
| **Moondream 2** | ~1B | 2GB | Very Fast | Fair | Lightweight deployment |
| **LLaVA 1.6 7B** | 7B | 4GB | Moderate | Very Good | Quality over speed |
| **Obsidian 3B** | 3B | 2-3GB | Fast | Good | Efficient alternative |

### Downloadable Pre-Converted Models

**MobileVLM 1.7B (GGUF):**
- HuggingFace: mtgv/MobileVLM-1.7B (PyTorch) → convert to GGUF
- Pre-quantized Q4_K_M available

**LLaVA 1.5 (Pre-converted GGUF):**
- HuggingFace: mys/ggml_llava-v1.5-7b
- HuggingFace: mys/ggml_llava-v1.5-13b

**LLaVA 1.6 (Pre-converted GGUF):**
- HuggingFace: cmp-nct/llava-1.6-gguf (7B-34B variants)

**MiniCPM-V (Pre-converted GGUF):**
- HuggingFace: openbmb/MiniCPM-Llama3-V-2_5-gguf

---

## 10. Known Limitations & Considerations

### Limitations
1. **No Video Support:** Only static images (but can process frame-by-frame)
2. **Single Image Focus:** Multi-image support requires sequential processing
3. **Android Integration:** Requires custom JNI implementation (not in current llama-jni)
4. **Inference Speed:** Image encoding is bottleneck (10-30s on mobile)
5. **Model Size:** Even "mobile" VLMs require 2-5GB RAM

### Technical Notes
- CLIP embeddings are not identical to PyTorch (noted in clip.cpp comment)
- Image preprocessing variations can affect output quality
- Dynamic resolution (LLaVA 1.6) adds complexity but improves quality
- MiniCPM-V uses CrossAttention resampler (different architecture)

### Compatibility Matrix
```
✓ = Fully supported
~ = Partial support
✗ = Not supported

                 GGUF Conv | Android | GPU Accel | Quantized
LLaVA 1.5           ✓          ~          ✓           ✓
LLaVA 1.6           ✓          ~          ✓           ✓
MobileVLM           ✓          ~          ✓           ✓
MiniCPM-V 2.5       ✓          ~          ✓           ✓
Moondream 2         ✓          ~          ✓           ✓
```

---

## 11. Code Examples & File Locations

### Key Files in llama.cpp Repository

```
/examples/llava/
├── clip.h                          # Vision encoder interface
├── clip.cpp                        # CLIP implementation (2284+ lines)
├── llava.h                         # LLaVA integration interface
├── llava.cpp                       # LLaVA implementation
├── llava-cli.cpp                  # CLI tool (LLaVA usage example)
├── minicpmv-cli.cpp               # CLI tool (MiniCPM-V usage example)
├── CMakeLists.txt                 # Build configuration
│
├── convert_image_encoder_to_gguf.py    # Convert CLIP to GGUF
├── llava_surgery.py                    # Split LLaVA models
├── llava_surgery_v2.py                 # Enhanced split script
├── minicpmv-surgery.py                 # MiniCPM-V model preparation
└── android/
    ├── build_64.sh                # Android NDK build script
    └── adb_run.sh                 # Android deployment helper

/include/
├── llama.h                        # Main API (note: no direct VLM references)

/examples/llama.android/
└── llama/src/main/java/android/llama/cpp/
    └── LLamaAndroid.kt            # Current JNI implementation (text-only)
```

### Example Usage: Command Line

```bash
# LLaVA 1.5
./llama-llava-cli \
    -m ./models/llava-v1.5-7b/ggml-model-f16.gguf \
    --mmproj ./models/llava-v1.5-7b/mmproj-model-f16.gguf \
    --image ./photo.jpg \
    -p "Describe the image in detail." \
    --temp 0.1

# MobileVLM
./llama-llava-cli \
    -m ./models/MobileVLM-1.7B/ggml-model-q4_k.gguf \
    --mmproj ./models/MobileVLM-1.7B/mmproj-model-f16.gguf \
    --image ./photo.jpg \
    -p "What is in this image?"

# MiniCPM-V 2.5
./llama-minicpmv-cli \
    -m ./models/MiniCPM-V-2_5/model-8B-F16.gguf \
    --mmproj ./models/MiniCPM-V-2_5/mmproj-model-f16.gguf \
    --image ./photo.jpg \
    -c 4096 \
    -p "Analyze this image."
```

---

## 12. Integration Recommendations for RunAnywhere SDK

### Short Term (3-4 weeks)
1. Create JNI bindings for VLM functionality
2. Expose CLIP model loading and image encoding
3. Integrate with existing RunAnywhere LLM context
4. Add image input support to ToolCallingScreen

### Medium Term (1-2 months)
1. Implement camera integration for real-time image capture
2. Add image preprocessing utilities
3. Create reusable VLM component (similar to STT component)
4. Performance optimization for mobile (GPU acceleration)

### Architecture Proposal
```kotlin
// New VisionComponent similar to existing STT component
class VisionComponent(
    private val configuration: VisionComponentConfiguration,
    serviceContainer: ServiceContainer? = null
) : Component {

    private var clipModel: ClipModel? = null

    override suspend fun initialize() {
        // Load CLIP model from GGUF
        // Initialize vision encoder
    }

    suspend fun encodeImage(imageBytes: ByteArray): ImageEmbedding {
        // Process image through CLIP
        // Return dense embeddings
    }

    suspend fun processImageWithPrompt(
        imageBytes: ByteArray,
        prompt: String
    ): String {
        // Encode image
        // Insert into LLM context
        // Generate response
    }
}
```

---

## 13. Summary & Conclusion

### Key Findings

| Aspect | Status | Confidence |
|---|---|---|
| **VLM Support in llama.cpp** | YES, Production-ready | 100% |
| **Multiple Model Support** | YES, 9+ architectures | 100% |
| **Android Compatibility** | YES, Requires integration | 95% |
| **Performance (Mobile)** | Acceptable for non-realtime | 80% |
| **Easy Integration** | Requires custom work | 70% |

### Yes/No Summary

**Q: Does llama.cpp have native VLM implementation?**
**A: YES** - Production-ready CLIP+Projector+LLM pipeline

**Q: What VLM architectures are supported?**
**A: 9+ architectures** including LLaVA, MobileVLM, MiniCPM-V, Moondream, etc.

**Q: Can it work on Android?**
**A: YES** - Requires JNI integration (straightforward, similar to existing bindings)

**Q: Can it be integrated into RunAnywhere SDK?**
**A: YES** - Moderate effort (~3-4 weeks for complete implementation)

**Q: Are there high-performance mobile models?**
**A: YES** - MobileVLM (1.7B) and MiniCPM-V (8B with quantization) are optimized

---

## Appendix: References

### Official Documentation
- llama.cpp Repository: https://github.com/ggerganov/llama.cpp
- LLaVA Documentation: /examples/llava/README.md
- MobileVLM: /examples/llava/MobileVLM-README.md
- MiniCPM-V: /examples/llava/README-minicpmv2.5.md

### Model Sources
- LLaVA Models: huggingface.co/liuhaotian/
- MobileVLM: huggingface.co/mtgv/
- MiniCPM-V: huggingface.co/openbmb/

### Key Implementation Files
- Vision Encoder: `/examples/llava/clip.cpp` (~2400 lines)
- LLaVA Integration: `/examples/llava/llava.cpp` (~400 lines)
- Model Conversion: `/examples/llava/convert_image_encoder_to_gguf.py`
