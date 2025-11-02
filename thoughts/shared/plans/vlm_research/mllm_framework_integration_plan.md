# MLLM Framework Integration Plan for RunAnywhere SDK

**Date**: October 26, 2025
**Status**: Research Complete - Ready for Implementation Planning
**Framework**: MLLM (Multimodal LLM) - https://github.com/UbiquitousLearning/mllm

---

## Executive Summary

MLLM is a **lightweight, fast, and easy-to-use on-device LLM inference engine optimized for mobile and edge devices**. It's specifically engineered for multimodal models like Qwen2-VL and LLaVA, with support for multiple hardware accelerators (ARM CPU, x86 CPU, Qualcomm NPU via QNN, XNNPACK). The framework is written in **plain C/C++17 with zero external dependencies**, making it highly portable and suitable for Android integration into the RunAnywhere Kotlin SDK.

**Key Findings**:
- ✅ **Native VLM support** with 9+ model architectures (Qwen2-VL, LLaVA, Fuyu, Phi-3-Vision, MiniCPM)
- ✅ **Excellent Android integration** with existing JNI patterns and build scripts
- ✅ **NPU acceleration ready** for Qualcomm Snapdragon 8 Gen3+
- ✅ **Zero external dependencies** - pure C/C++17 implementation
- ✅ **Active development** with V2 planned for 2025

---

## 1. Framework Overview

### 1.1 What is MLLM?

MLLM is a research-driven project initiated by BUPT (Beijing University of Posts and Telecommunications) and PKU (Peking University) that focuses on:

- **On-device inference**: Designed to run LLMs and VLMs directly on mobile/edge devices
- **Multimodal support**: Handles both text and image inputs simultaneously
- **Lightweight architecture**: Plain C/C++ implementation with zero external dependencies
- **Cross-platform**: Supports Android, Linux, x86, ARM, and NPU acceleration
- **Graph-based computation**: Explicit tensor flow graphs similar to TensorFlow/PyTorch

### 1.2 Architecture Overview

```
┌─────────────────────────────────────────────┐
│        Application Layer (Java/Kotlin)      │
├─────────────────────────────────────────────┤
│    JNI Bridge (LibHelper.hpp/cpp)          │
├─────────────────────────────────────────────┤
│   Model Layer (Module/Forward API)         │
│   - Tensor operations                      │
│   - Layer abstractions (Linear, Conv, etc) │
├─────────────────────────────────────────────┤
│      Backend Abstraction Layer              │
│   - CPU, QNN, XNNPACK interfaces           │
├─────────────────────────────────────────────┤
│   Hardware Kernels                          │
│   - ARM NEON (GEMM, Quantized ops)         │
│   - x86 AVX2                                │
│   - Qualcomm Hexagon (via QNN)             │
└─────────────────────────────────────────────┘
```

### 1.3 Key Design Principles

1. **Minimal dependencies**: Pure C/C++17, no external libraries
2. **Graph-based computation**: Computation graphs similar to TensorFlow/PyTorch
3. **Multi-backend architecture**: CPU, NPU, XNNPACK backends with unified Op interface
4. **Lazy loading**: Models loaded on-demand to minimize memory footprint
5. **Quantization-first**: Native support for Q4_0, Q4_K, Q6_K, Q8_0 quantization schemes

---

## 2. Supported VLM Models

### 2.1 Model Support Matrix

| Model | CPU FP32 | CPU INT4 | Hexagon NPU | Size (Q4_K) | Status |
|-------|----------|----------|------------|-------------|--------|
| **Qwen2-VL 2B** | ✅ | ✅ | 🔄 WIP | ~4-6GB | **Recommended** |
| **LLaVA 1.5 7B** | ✅ | ✅ | - | ~5GB | Stable |
| **Fuyu-8B** | ✅ | ✅ | - | ~12GB | Stable |
| **Phi-3-Vision** | ✅ | ✅ | - | ~3GB | Stable |
| **MiniCPM-2B** | ✅ | ✅ | - | ~3GB | **Mobile Optimized** |
| **MiniCPM3-4B** | ✅ | ✅ | - | ~4GB | Stable |
| **MiniCPM-MoE 8x2B** | ✅ | ✅ | - | ~6GB | Stable |

### 2.2 Vision Encoders Supported

- **CLIP** (OpenAI) - Used in LLaVA models
- **Vision Transformer (ViT)** - Pure attention-based vision
- **Custom encoders** - Qwen2-VL uses proprietary vision encoder
- **ImageBind** (Meta) - Multi-modal encoder (research)

### 2.3 Model Format

- **Native format**: `.mllm` - custom binary format optimized for mobile
- **Conversion tools**: Support from PyTorch (.pth), SafeTensors (.safetensors), GGUF
- **Quantization schemes**: Q4_0, Q4_K, Q6_K, Q8_0, FP32, FP16
- **Model repository**: HuggingFace mllm team - https://huggingface.co/mllmTeam

---

## 3. End-to-End VLM Processing Flow

### 3.1 Qwen2-VL Processing Pipeline

```
1. Image Input (jpg/png/bitmap)
        ↓
2. STB Image Resize (1024x1024 target)
        ↓
3. Patch Embedding (Qwen2PatchEmbed)
   - 3D Conv: (3, embed_dim, {2, 16, 16})
   - Outputs: (seq_len, embed_dim)
        ↓
4. Vision Attention Layers
   - VisionAttention with RoPE
   - VisionMLP feed-forward
   - 24 layers stacked
        ↓
5. Vision Token Embeddings
   (576-2880 image tokens)
        ↓
6. Text Token Embedding
        ↓
7. Merge Tokens (position-aware)
        ↓
8. Qwen2 Transformer LLM
   - Self-attention with KV-cache
   - Feed-forward
   - 28 layers
        ↓
9. Output Token Generation
   - Iterative decoding
   - Streaming callbacks
        ↓
10. Final Text Response
```

### 3.2 LLaVA Processing Pipeline

```
1. Image Input
        ↓
2. CLIP ViT Encoder
   - Patch extraction
   - Vision transformer (12 layers)
   - Output: 576 image embeddings
        ↓
3. Linear Projection
   - Map CLIP space → LLaMA space
        ↓
4. Text Tokenization
        ↓
5. Concatenate Image + Text Tokens
        ↓
6. LLaMA LLM Processing
   - Standard transformer with KV-cache
        ↓
7. Output Generation
```

### 3.3 Fuyu-8B Processing Pipeline

```
1. Image Input
        ↓
2. Rasterize to Patches
   - Unique approach: image as sequence
   - No separate vision encoder
        ↓
3. Patch Embedding
   - Linear: patch_data → hidden_dim
        ↓
4. Position-aware Token Gathering
        ↓
5. Persimmon LLM Processing
        ↓
6. Output Generation
```

---

## 4. Android Integration Details

### 4.1 Existing Android Support

**Build System**:
- CMake-based with Android NDK support
- Build scripts: `build_android.sh`, `build_android_qnn.sh`, `build_android_xp.sh`
- Target: `arm64-v8a` (primary), `armeabi-v7a` (optional)
- Minimum Android API: 24 (Android 7.0)
- Produces: Static library `libmllm_lib.a`

**CMake Configuration Example**:
```bash
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI="arm64-v8a" \
  -DANDROID_PLATFORM=android-34 \
  -DCMAKE_CXX_FLAGS="-march=armv8.6-a+dotprod+i8mm" \
  -DARM=ON \
  -DAPK=OFF
```

### 4.2 JNI Interface (LibHelper)

**Core API** (tools/jni/LibHelper.hpp):

```cpp
class LibHelper {
public:
    // Model types
    enum PreDefinedModel {
        QWEN25,      // Qwen 2.5 text-only
        FUYU,        // Fuyu-8B VLM
        Bert,        // BERT embeddings
        PhoneLM,     // Phone task-specific
        QWEN15,      // Qwen 1.5
        QWEN2VL      // Qwen2-VL multimodal
    };

    // Backend types
    enum MLLMBackendType {
        CPU = 0,
        QNN         // Qualcomm NPU
    };

    // Setup model
    bool setUp(
        std::string basePath,
        std::string weightsPath,
        std::string qnnWeightsPath,  // For NPU
        std::string vocabPath,
        std::string mergePath,
        PreDefinedModel model,
        MLLMBackendType backendType
    );

    // Set callback for streaming output
    typedef std::function<void(std::string, bool, std::vector<double>)> callback_t;
    void setCallback(callback_t callback);

    // Run inference
    void run(
        std::string inputStr,
        uint8_t* image,
        int maxSteps,
        int imageLength,
        std::string chatTemplate = ""
    );

    // Get embeddings
    std::vector<float> runForResult(std::string inputStr);
};
```

**Callback Signature**:
```cpp
callback_t = std::function<void(
    std::string tokenString,    // Generated token text
    bool isFinal,               // Is this the last token?
    std::vector<double> metrics // [tokenTime, prefillTime, decodeTime]
)>;
```

### 4.3 Android Example App

**Features Demonstrated**:
- Chat interface with CPU inference
- Chat with NPU acceleration (Snapdragon 8 Gen3)
- Image understanding (VLM mode)
- Real-time token streaming
- Performance metrics display
- Android Intent invocation

**Repository**: Separate example app at https://github.com/lx200916/ChatBotApp

---

## 5. RunAnywhere SDK Integration Plan

### 5.1 Proposed Module Structure

```
sdk/runanywhere-kotlin/modules/runanywhere-llm-mllm/
├── build.gradle.kts
├── CMakeLists.txt
├── README.md
├── src/
│   ├── androidMain/
│   │   ├── kotlin/com/runanywhere/sdk/llm/mllm/
│   │   │   ├── MLLMVisionComponent.kt
│   │   │   ├── MLLMConfiguration.kt
│   │   │   ├── AndroidMLLMEngine.kt
│   │   │   └── MLLMModelManager.kt
│   │   ├── cpp/
│   │   │   ├── mllm_jni.cpp
│   │   │   ├── mllm_jni.hpp
│   │   │   └── CMakeLists.txt
│   │   └── jniLibs/
│   │       └── arm64-v8a/
│   │           └── libmllm_jni.so
│   ├── jvmMain/
│   │   └── kotlin/com/runanywhere/sdk/llm/mllm/
│   │       ├── JvmMLLMEngine.kt
│   │       └── JvmMLLMStub.kt
│   ├── commonMain/
│   │   └── kotlin/com/runanywhere/sdk/llm/mllm/
│   │       ├── MLLMVisionModel.kt (interface)
│   │       ├── MLLMInferenceResult.kt
│   │       ├── VLMProcessor.kt
│   │       ├── ImageProcessingPipeline.kt
│   │       └── models/
│   │           ├── VLMModelType.kt
│   │           ├── QuantizationType.kt
│   │           └── InferenceOptions.kt
│   └── nativeMain/
│       └── kotlin/com/runanywhere/sdk/llm/mllm/
│           └── NativeMLLMEngine.kt
└── external/
    └── mllm/ (git submodule)
```

### 5.2 Common Interface Design (commonMain)

```kotlin
// MLLMVisionModel.kt
interface MLLMVisionModel {
    /**
     * Load VLM model from file system
     */
    suspend fun loadModel(
        modelPath: String,
        modelType: VLMModelType,
        options: ModelLoadOptions = ModelLoadOptions()
    ): Result<Unit>

    /**
     * Process image and text together
     */
    suspend fun processImageAndText(
        imageData: ByteArray,
        text: String,
        options: VLMInferenceOptions = VLMInferenceOptions()
    ): Result<VLMInferenceResult>

    /**
     * Stream text generation token by token
     */
    fun generateTextStream(
        prompt: String,
        imageData: ByteArray? = null,
        options: VLMInferenceOptions = VLMInferenceOptions()
    ): Flow<GeneratedToken>

    /**
     * Text-only generation (no image)
     */
    suspend fun generateText(
        prompt: String,
        maxTokens: Int = 100
    ): Result<String>

    /**
     * Get image embeddings only
     */
    suspend fun encodeImage(
        imageData: ByteArray
    ): Result<FloatArray>

    /**
     * Cleanup resources
     */
    suspend fun cleanup()

    /**
     * Current component state
     */
    val state: ComponentState

    /**
     * Model information
     */
    val modelInfo: ModelInfo?
}

// VLMModelType.kt
enum class VLMModelType(
    val modelId: String,
    val vocabFile: String,
    val mergeFile: String?,
    val recommendedQuantization: QuantizationType,
    val minMemoryMB: Int
) {
    QWEN2_VL_2B(
        modelId = "qwen2-vl-2b",
        vocabFile = "qwen2vl_vocab.mllm",
        mergeFile = null,
        recommendedQuantization = QuantizationType.Q4_K,
        minMemoryMB = 4096
    ),

    LLAVA_1_5_7B(
        modelId = "llava-1.5-7b",
        vocabFile = "llava_vocab.mllm",
        mergeFile = "llava_merge.mllm",
        recommendedQuantization = QuantizationType.Q4_K,
        minMemoryMB = 5120
    ),

    FUYU_8B(
        modelId = "fuyu-8b",
        vocabFile = "fuyu_vocab.mllm",
        mergeFile = null,
        recommendedQuantization = QuantizationType.Q4_K,
        minMemoryMB = 12288
    ),

    PHI3_VISION(
        modelId = "phi3-vision",
        vocabFile = "phi3_vocab.mllm",
        mergeFile = null,
        recommendedQuantization = QuantizationType.Q4_K,
        minMemoryMB = 3072
    ),

    MINICPM_2B(
        modelId = "minicpm-2b",
        vocabFile = "minicpm_vocab.mllm",
        mergeFile = null,
        recommendedQuantization = QuantizationType.Q4_K,
        minMemoryMB = 3072
    )
}

// QuantizationType.kt
enum class QuantizationType(val mllmName: String) {
    FP32("fp32"),
    FP16("fp16"),
    Q4_0("q4_0"),
    Q4_K("q4_k"),
    Q6_K("q6_k"),
    Q8_0("q8_0")
}

// MLLMConfiguration.kt
data class MLLMConfiguration(
    val modelType: VLMModelType,
    val basePath: String,
    val quantizationType: QuantizationType = modelType.recommendedQuantization,
    val maxTokens: Int = 2000,
    val cpuThreads: Int = 4,
    val enableNPU: Boolean = false,
    val backendType: BackendType = BackendType.CPU
) : ComponentConfiguration {
    override fun validate() {
        require(maxTokens > 0) { "maxTokens must be positive" }
        require(cpuThreads in 1..16) { "cpuThreads must be between 1 and 16" }
        require(File(basePath).exists()) { "Base path does not exist: $basePath" }
    }
}

enum class BackendType {
    CPU,
    QNN,      // Qualcomm NPU
    XNNPACK   // Google XNNPACK
}

// VLMInferenceOptions.kt
data class VLMInferenceOptions(
    val temperature: Float = 0.7f,
    val topK: Int = 5,
    val topP: Float = 0.92f,
    val maxNewTokens: Int = 100,
    val doSample: Boolean = true,
    val repeatPenalty: Float = 1.1f,
    val chatTemplate: String = ""  // For conversation mode
) {
    init {
        require(temperature > 0) { "Temperature must be positive" }
        require(topK > 0) { "topK must be positive" }
        require(topP in 0.0f..1.0f) { "topP must be between 0 and 1" }
        require(maxNewTokens > 0) { "maxNewTokens must be positive" }
    }
}

// VLMInferenceResult.kt
data class VLMInferenceResult(
    val text: String,
    val tokens: List<Int>,
    val confidence: Float,
    val prefillTimeMs: Long,
    val decodeTimeMs: Long,
    val totalTimeMs: Long,
    val tokensPerSecond: Float,
    val modelName: String,
    val metadata: Map<String, Any> = emptyMap()
)

data class GeneratedToken(
    val text: String,
    val tokenId: Int,
    val isFinal: Boolean,
    val generationTimeMs: Long
)

data class ModelInfo(
    val modelType: VLMModelType,
    val quantization: QuantizationType,
    val fileSizeMB: Long,
    val loadedTimeMs: Long,
    val backend: BackendType
)

// MLLMError.kt
sealed class MLLMError(message: String) : Exception(message) {
    data class ModelNotFound(val modelPath: String) :
        MLLMError("Model not found at: $modelPath")

    data class InsufficientMemory(val required: Long, val available: Long) :
        MLLMError("Insufficient memory: need ${required}MB, have ${available}MB")

    data class InvalidImageFormat(val reason: String) :
        MLLMError("Invalid image format: $reason")

    data class InferenceFailure(val step: Int, val reason: String) :
        MLLMError("Inference failed at step $step: $reason")

    data class ModelLoadFailure(val reason: String) :
        MLLMError("Failed to load model: $reason")

    object BackendNotSupported :
        MLLMError("Selected backend not supported on this platform")
}
```

### 5.3 Android Implementation (androidMain)

```kotlin
// AndroidMLLMEngine.kt
class AndroidMLLMEngine(
    private val configuration: MLLMConfiguration
) : MLLMVisionModel {

    private var _state: ComponentState = ComponentState.NotInitialized
    override val state: ComponentState get() = _state

    override var modelInfo: ModelInfo? = null
        private set

    private val _tokenFlow = MutableSharedFlow<GeneratedToken>()

    // Native methods
    private external fun nativeSetup(
        basePath: String,
        modelPath: String,
        qnnModelPath: String,
        vocabPath: String,
        mergePath: String,
        modelType: Int,
        backendType: Int
    ): Boolean

    private external fun nativeRunInference(
        input: String,
        imageData: ByteArray?,
        imageLength: Int,
        maxSteps: Int,
        chatTemplate: String
    )

    private external fun nativeGetEmbeddings(input: String): FloatArray

    private external fun nativeCleanup()

    companion object {
        init {
            System.loadLibrary("mllm_jni")
        }
    }

    override suspend fun loadModel(
        modelPath: String,
        modelType: VLMModelType,
        options: ModelLoadOptions
    ): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            _state = ComponentState.Initializing
            val startTime = System.currentTimeMillis()

            val vocabPath = "${configuration.basePath}/${modelType.vocabFile}"
            val mergePath = modelType.mergeFile?.let {
                "${configuration.basePath}/$it"
            } ?: ""

            val qnnPath = if (configuration.enableNPU) {
                "$modelPath.qnn"
            } else ""

            val success = nativeSetup(
                basePath = configuration.basePath,
                modelPath = modelPath,
                qnnModelPath = qnnPath,
                vocabPath = vocabPath,
                mergePath = mergePath,
                modelType = modelType.ordinal,
                backendType = configuration.backendType.ordinal
            )

            if (success) {
                val loadTime = System.currentTimeMillis() - startTime
                val fileSize = File(modelPath).length() / (1024 * 1024)

                modelInfo = ModelInfo(
                    modelType = modelType,
                    quantization = configuration.quantizationType,
                    fileSizeMB = fileSize,
                    loadedTimeMs = loadTime,
                    backend = configuration.backendType
                )

                _state = ComponentState.Ready
                EventBus.publish(ComponentInitializationEvent.ComponentReady(
                    component = "MLLMVisionComponent",
                    modelId = modelType.modelId
                ))
                Result.success(Unit)
            } else {
                _state = ComponentState.Error("Model load failed")
                Result.failure(MLLMError.ModelLoadFailure("Native setup returned false"))
            }
        } catch (e: Exception) {
            _state = ComponentState.Error(e.message ?: "Unknown error")
            Result.failure(e)
        }
    }

    override suspend fun processImageAndText(
        imageData: ByteArray,
        text: String,
        options: VLMInferenceOptions
    ): Result<VLMInferenceResult> = withContext(Dispatchers.IO) {
        if (_state != ComponentState.Ready) {
            return@withContext Result.failure(
                MLLMError.InferenceFailure(0, "Model not ready")
            )
        }

        try {
            val startTime = System.currentTimeMillis()
            val resultBuilder = StringBuilder()
            var prefillTime = 0L
            var decodeTime = 0L

            // Setup callback
            setupNativeCallback { token, isFinal, metrics ->
                resultBuilder.append(token)
                if (metrics.size >= 3) {
                    prefillTime = metrics[1].toLong()
                    decodeTime = metrics[2].toLong()
                }
            }

            nativeRunInference(
                input = text,
                imageData = imageData,
                imageLength = imageData.size,
                maxSteps = options.maxNewTokens,
                chatTemplate = options.chatTemplate
            )

            val totalTime = System.currentTimeMillis() - startTime
            val tokensPerSec = if (decodeTime > 0) {
                (options.maxNewTokens.toFloat() / decodeTime) * 1000
            } else 0f

            Result.success(VLMInferenceResult(
                text = resultBuilder.toString(),
                tokens = emptyList(), // Not exposed by MLLM
                confidence = 1.0f,
                prefillTimeMs = prefillTime,
                decodeTimeMs = decodeTime,
                totalTimeMs = totalTime,
                tokensPerSecond = tokensPerSec,
                modelName = modelInfo?.modelType?.modelId ?: "unknown"
            ))
        } catch (e: Exception) {
            Result.failure(MLLMError.InferenceFailure(0, e.message ?: "Unknown"))
        }
    }

    override fun generateTextStream(
        prompt: String,
        imageData: ByteArray?,
        options: VLMInferenceOptions
    ): Flow<GeneratedToken> = flow {
        if (_state != ComponentState.Ready) {
            throw MLLMError.InferenceFailure(0, "Model not ready")
        }

        setupNativeCallback { token, isFinal, metrics ->
            val generatedToken = GeneratedToken(
                text = token,
                tokenId = 0, // Not exposed
                isFinal = isFinal,
                generationTimeMs = metrics.getOrNull(0)?.toLong() ?: 0
            )
            _tokenFlow.tryEmit(generatedToken)
        }

        // Launch inference in background
        withContext(Dispatchers.IO) {
            nativeRunInference(
                input = prompt,
                imageData = imageData,
                imageLength = imageData?.size ?: 0,
                maxSteps = options.maxNewTokens,
                chatTemplate = options.chatTemplate
            )
        }
    }.flatMapConcat { _tokenFlow }

    override suspend fun encodeImage(
        imageData: ByteArray
    ): Result<FloatArray> = withContext(Dispatchers.IO) {
        // MLLM doesn't expose separate image encoding
        Result.failure(UnsupportedOperationException("Not supported by MLLM"))
    }

    override suspend fun cleanup() {
        nativeCleanup()
        _state = ComponentState.NotInitialized
        modelInfo = null
    }

    private fun setupNativeCallback(
        callback: (String, Boolean, List<Double>) -> Unit
    ) {
        // JNI callback registration
        nativeSetCallback(callback)
    }

    private external fun nativeSetCallback(
        callback: (String, Boolean, List<Double>) -> Unit
    )
}
```

### 5.4 JNI Implementation (androidMain/cpp)

```cpp
// mllm_jni.cpp
#include <jni.h>
#include <string>
#include <vector>
#include <android/log.h>
#include "tools/jni/LibHelper.hpp"

#define TAG "MLLM-JNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

using namespace mllm;

// Global state
static LibHelper* gLibHelper = nullptr;
static JavaVM* gJavaVM = nullptr;
static jobject gCallbackObject = nullptr;
static jmethodID gCallbackMethodID = nullptr;

// JNI_OnLoad
JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    gJavaVM = vm;
    LOGI("MLLM JNI loaded successfully");
    return JNI_VERSION_1_6;
}

// Callback wrapper
static void nativeCallback(
    std::string token,
    bool isFinal,
    std::vector<double> metrics
) {
    if (!gCallbackObject || !gCallbackMethodID) return;

    JNIEnv* env;
    bool attached = false;

    if (gJavaVM->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) {
        if (gJavaVM->AttachCurrentThread(&env, nullptr) == JNI_OK) {
            attached = true;
        } else {
            LOGE("Failed to attach thread for callback");
            return;
        }
    }

    // Convert token to jstring
    jstring jToken = env->NewStringUTF(token.c_str());

    // Convert metrics to List<Double>
    jclass doubleClass = env->FindClass("java/lang/Double");
    jmethodID doubleConstructor = env->GetMethodID(doubleClass, "<init>", "(D)V");

    jclass arrayListClass = env->FindClass("java/util/ArrayList");
    jmethodID arrayListConstructor = env->GetMethodID(arrayListClass, "<init>", "()V");
    jmethodID arrayListAdd = env->GetMethodID(arrayListClass, "add",
                                              "(Ljava/lang/Object;)Z");

    jobject metricsList = env->NewObject(arrayListClass, arrayListConstructor);
    for (double metric : metrics) {
        jobject doubleObj = env->NewObject(doubleClass, doubleConstructor, metric);
        env->CallBooleanMethod(metricsList, arrayListAdd, doubleObj);
        env->DeleteLocalRef(doubleObj);
    }

    // Call Kotlin callback
    env->CallVoidMethod(gCallbackObject, gCallbackMethodID,
                       jToken, isFinal, metricsList);

    // Cleanup
    env->DeleteLocalRef(jToken);
    env->DeleteLocalRef(metricsList);
    env->DeleteLocalRef(doubleClass);
    env->DeleteLocalRef(arrayListClass);

    if (attached) {
        gJavaVM->DetachCurrentThread();
    }
}

extern "C" {

// Setup model
JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_llm_mllm_AndroidMLLMEngine_nativeSetup(
    JNIEnv* env, jobject obj,
    jstring basePath,
    jstring modelPath,
    jstring qnnModelPath,
    jstring vocabPath,
    jstring mergePath,
    jint modelType,
    jint backendType
) {
    const char* base_path = env->GetStringUTFChars(basePath, nullptr);
    const char* model_path = env->GetStringUTFChars(modelPath, nullptr);
    const char* qnn_model_path = env->GetStringUTFChars(qnnModelPath, nullptr);
    const char* vocab_path = env->GetStringUTFChars(vocabPath, nullptr);
    const char* merge_path = env->GetStringUTFChars(mergePath, nullptr);

    LOGI("Setting up MLLM with model: %s", model_path);

    // Clean up previous instance
    if (gLibHelper) {
        delete gLibHelper;
    }

    gLibHelper = new LibHelper();

    // Map model type
    LibHelper::PreDefinedModel model;
    switch(modelType) {
        case 0: model = LibHelper::PreDefinedModel::QWEN2VL; break;
        case 1: model = LibHelper::PreDefinedModel::FUYU; break;
        case 2: model = LibHelper::PreDefinedModel::Bert; break;
        case 3: model = LibHelper::PreDefinedModel::PhoneLM; break;
        case 4: model = LibHelper::PreDefinedModel::QWEN15; break;
        default:
            LOGE("Unknown model type: %d", modelType);
            return JNI_FALSE;
    }

    // Map backend type
    LibHelper::MLLMBackendType backend = (backendType == 1) ?
        LibHelper::MLLMBackendType::QNN :
        LibHelper::MLLMBackendType::CPU;

    // Setup
    bool success = gLibHelper->setUp(
        std::string(base_path),
        std::string(model_path),
        std::string(qnn_model_path),
        std::string(vocab_path),
        std::string(merge_path),
        model,
        backend
    );

    // Release strings
    env->ReleaseStringUTFChars(basePath, base_path);
    env->ReleaseStringUTFChars(modelPath, model_path);
    env->ReleaseStringUTFChars(qnnModelPath, qnn_model_path);
    env->ReleaseStringUTFChars(vocabPath, vocab_path);
    env->ReleaseStringUTFChars(mergePath, merge_path);

    LOGI("MLLM setup %s", success ? "succeeded" : "failed");
    return success ? JNI_TRUE : JNI_FALSE;
}

// Set callback
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_mllm_AndroidMLLMEngine_nativeSetCallback(
    JNIEnv* env, jobject obj,
    jobject callback
) {
    // Clear previous callback
    if (gCallbackObject) {
        env->DeleteGlobalRef(gCallbackObject);
    }

    // Store callback
    gCallbackObject = env->NewGlobalRef(callback);

    // Find callback method
    jclass callbackClass = env->GetObjectClass(callback);
    gCallbackMethodID = env->GetMethodID(
        callbackClass,
        "invoke",
        "(Ljava/lang/String;ZLjava/util/List;)V"
    );

    // Set callback in LibHelper
    if (gLibHelper) {
        gLibHelper->setCallback(nativeCallback);
    }
}

// Run inference
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_mllm_AndroidMLLMEngine_nativeRunInference(
    JNIEnv* env, jobject obj,
    jstring input,
    jbyteArray imageData,
    jint imageLength,
    jint maxSteps,
    jstring chatTemplate
) {
    if (!gLibHelper) {
        LOGE("LibHelper not initialized");
        return;
    }

    const char* input_str = env->GetStringUTFChars(input, nullptr);
    const char* chat_template = env->GetStringUTFChars(chatTemplate, nullptr);

    uint8_t* img_data = nullptr;
    if (imageData) {
        img_data = (uint8_t*)env->GetByteArrayElements(imageData, nullptr);
    }

    LOGI("Running inference: input='%s', maxSteps=%d, imageLen=%d",
         input_str, maxSteps, imageLength);

    // Run inference
    gLibHelper->run(
        std::string(input_str),
        img_data,
        maxSteps,
        imageLength,
        std::string(chat_template)
    );

    // Cleanup
    env->ReleaseStringUTFChars(input, input_str);
    env->ReleaseStringUTFChars(chatTemplate, chat_template);
    if (imageData && img_data) {
        env->ReleaseByteArrayElements(imageData, (jbyte*)img_data, JNI_ABORT);
    }
}

// Get embeddings
JNIEXPORT jfloatArray JNICALL
Java_com_runanywhere_sdk_llm_mllm_AndroidMLLMEngine_nativeGetEmbeddings(
    JNIEnv* env, jobject obj,
    jstring input
) {
    if (!gLibHelper) {
        LOGE("LibHelper not initialized");
        return nullptr;
    }

    const char* input_str = env->GetStringUTFChars(input, nullptr);

    std::vector<float> embeddings = gLibHelper->runForResult(std::string(input_str));

    env->ReleaseStringUTFChars(input, input_str);

    // Convert to jfloatArray
    jfloatArray result = env->NewFloatArray(embeddings.size());
    env->SetFloatArrayRegion(result, 0, embeddings.size(), embeddings.data());

    return result;
}

// Cleanup
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_mllm_AndroidMLLMEngine_nativeCleanup(
    JNIEnv* env, jobject obj
) {
    if (gLibHelper) {
        delete gLibHelper;
        gLibHelper = nullptr;
    }

    if (gCallbackObject) {
        env->DeleteGlobalRef(gCallbackObject);
        gCallbackObject = nullptr;
        gCallbackMethodID = nullptr;
    }

    LOGI("MLLM cleaned up");
}

} // extern "C"
```

### 5.5 Component Integration

```kotlin
// MLLMVisionComponent.kt
class MLLMVisionComponent(
    configuration: MLLMConfiguration,
    serviceContainer: ServiceContainer? = null
) : BaseComponent<MLLMVisionModel>(configuration, serviceContainer) {

    override suspend fun createService(): MLLMVisionModel {
        return when (Platform.current()) {
            Platform.ANDROID -> AndroidMLLMEngine(configuration as MLLMConfiguration)
            Platform.JVM -> JvmMLLMEngine(configuration as MLLMConfiguration)
            Platform.NATIVE -> NativeMLLMEngine(configuration as MLLMConfiguration)
            else -> throw MLLMError.BackendNotSupported
        }
    }

    override suspend fun initialize() {
        state = ComponentState.Initializing

        try {
            val service = createService()

            // Load model
            val modelPath = "${(configuration as MLLMConfiguration).basePath}/${configuration.modelType.modelId}.mllm"

            service.loadModel(
                modelPath = modelPath,
                modelType = configuration.modelType
            ).getOrThrow()

            state = ComponentState.Ready

            EventBus.publish(ComponentInitializationEvent.ComponentReady(
                component = SDKComponent.VISION_MODEL.name,
                modelId = configuration.modelType.modelId
            ))
        } catch (e: Exception) {
            state = ComponentState.Error(e.message ?: "Unknown error")
            throw e
        }
    }

    override suspend fun cleanup() {
        service?.cleanup()
        state = ComponentState.NotInitialized
        super.cleanup()
    }

    override suspend fun healthCheck(): ComponentHealth {
        return ComponentHealth(
            isHealthy = state == ComponentState.Ready,
            lastCheck = System.currentTimeMillis(),
            diagnostics = mapOf(
                "state" to state.toString(),
                "modelInfo" to (service?.modelInfo?.toString() ?: "N/A")
            )
        )
    }
}
```

### 5.6 ServiceContainer Integration

```kotlin
// In ServiceContainer.kt
class ServiceContainer {
    companion object {
        val shared = ServiceContainer()
    }

    // ... existing services

    // MLLM Vision Component
    private var _mllmComponent: MLLMVisionComponent? = null

    val mllmVisionService: MLLMVisionModel by lazy {
        _mllmComponent?.service ?: throw IllegalStateException("MLLM not initialized")
    }

    /**
     * Initialize MLLM with configuration
     */
    suspend fun initializeMLLM(configuration: MLLMConfiguration) {
        _mllmComponent = MLLMVisionComponent(configuration, this)
        _mllmComponent?.initialize()
    }

    /**
     * Cleanup all components including MLLM
     */
    suspend fun cleanup() {
        _mllmComponent?.cleanup()
        // ... cleanup other components
    }
}
```

---

## 6. Implementation Timeline

### Phase 1: Foundation (Weeks 1-2)

**Goals**: Establish MLLM as a separate module with basic JNI bindings

**Tasks**:
1. Create module structure in `modules/runanywhere-llm-mllm/`
2. Configure `build.gradle.kts` with CMake integration
3. Add MLLM as git submodule in `external/mllm/`
4. Create basic JNI bindings (setup, inference, cleanup)
5. Test basic model loading

**Deliverables**:
- Module structure created
- CMake builds successfully
- Basic JNI wrapper functional
- Can load Qwen2-VL model

### Phase 2: Component Integration (Weeks 3-4)

**Goals**: Integrate with RunAnywhere architecture

**Tasks**:
1. Define common interfaces (`MLLMVisionModel`, etc.)
2. Create `MLLMVisionComponent` extending `BaseComponent`
3. Implement lifecycle management
4. Add EventBus integration
5. Register in ServiceContainer

**Deliverables**:
- Common interfaces defined
- Component lifecycle working
- Events published correctly
- ServiceContainer integration complete

### Phase 3: Feature Implementation (Weeks 5-8)

**Goals**: Core VLM functionality

**Tasks**:
1. Image processing pipeline
2. Text-only inference
3. Image + text inference
4. Streaming output with Flow
5. Callback handling
6. Model management (download, cache)

**Deliverables**:
- Full inference pipeline working
- Streaming output functional
- Image processing robust
- Model downloading automated

### Phase 4: Optimization & NPU (Weeks 9-10)

**Goals**: Performance optimization and NPU support

**Tasks**:
1. Integrate QNN backend
2. Memory optimization
3. Performance profiling
4. Device compatibility testing
5. Quantization optimization

**Deliverables**:
- NPU acceleration working (Snapdragon 8 Gen3+)
- Memory usage optimized
- Performance benchmarks documented
- Device compatibility matrix

### Phase 5: Testing & Documentation (Weeks 11-12)

**Goals**: Comprehensive testing and docs

**Tasks**:
1. Unit tests for all components
2. Integration tests
3. Example Android app
4. API documentation
5. Integration guide
6. Performance guidelines

**Deliverables**:
- 80%+ test coverage
- Working example app
- Complete API docs
- Integration guide published

---

## 7. Comparison: MLLM vs llama.cpp for VLM

### 7.1 Feature Comparison

| Feature | MLLM | llama.cpp |
|---------|------|-----------|
| **VLM Support** | ✅ Native (9+ models) | ⚠️ Limited (requires plugins) |
| **Primary Focus** | Multimodal (images + text) | Text-only LLMs |
| **Mobile Optimization** | ✅ Primary target | ⚠️ Secondary |
| **NPU Support** | ✅ Native (Qualcomm QNN) | ❌ Minimal |
| **Dependencies** | ✅ Zero external | ✅ Minimal |
| **Model Format** | Custom MLLM format | GGUF (larger ecosystem) |
| **Vision Encoders** | ✅ Built-in | ❌ Not included |
| **Android JNI** | ✅ Existing patterns | ⚠️ Custom work needed |
| **Model Ecosystem** | ⚠️ Smaller | ✅ Larger (HuggingFace) |
| **Quantization** | Q4_0, Q4_K, Q6_K, Q8_K | Same + IQ2_XXS variants |
| **KV-Cache** | ✅ Advanced (position-aware) | ✅ Standard |

### 7.2 Performance Comparison

**Text-Only LLM**:
- llama.cpp: **Faster** (optimized for text)
- MLLM: Comparable, but not primary focus

**Vision + Language (VLM)**:
- MLLM: **Significantly faster** (built-in vision encoder)
- llama.cpp: Requires external CLIP, slower integration

**Mobile Deployment**:
- MLLM: **Better** (mobile-first design)
- llama.cpp: Good, but desktop-focused

**NPU Acceleration**:
- MLLM: **Native QNN support**
- llama.cpp: Minimal NPU support

### 7.3 Integration Complexity

| Task | MLLM | llama.cpp |
|------|------|-----------|
| Text-only LLM | Medium | **Easy** |
| VLM Integration | **Easy** | Hard |
| Custom operations | Medium | Hard |
| Android JNI | **Easy** | Custom work |
| NPU acceleration | **Native** | Custom |

### 7.4 Recommendation

**Use MLLM when**:
- ✅ Primary goal is VLM/multimodal
- ✅ Targeting mobile devices
- ✅ Need NPU acceleration
- ✅ Want simpler Android integration

**Use llama.cpp when**:
- ✅ Primary goal is text-only LLM
- ✅ Need larger model ecosystem
- ✅ Desktop/server deployment
- ✅ Require specific GGUF models

**For RunAnywhere SDK**: **MLLM is recommended** for VLM support due to:
1. Native multimodal architecture
2. Excellent Android integration
3. NPU support for Qualcomm devices
4. Cleaner integration path with existing JNI patterns

---

## 8. Critical Files & References

### 8.1 MLLM Source Files (Reference)

**Core JNI Interface**:
- `EXTERNAL/mllm/tools/jni/LibHelper.hpp` - JNI API definition
- `EXTERNAL/mllm/tools/jni/LibHelper.cpp` - JNI implementation

**Vision Models**:
- `EXTERNAL/mllm/src/models/qwen2vl/modeling_qwen2vl.cpp` - Qwen2-VL implementation
- `EXTERNAL/mllm/src/models/llava/modeling_llava.cpp` - LLaVA implementation
- `EXTERNAL/mllm/src/models/fuyu/modeling_fuyu.cpp` - Fuyu implementation

**Build Configuration**:
- `EXTERNAL/mllm/CMakeLists.txt` - Main CMake config
- `EXTERNAL/mllm/build_android.sh` - Android build script
- `EXTERNAL/mllm/build_android_qnn.sh` - QNN backend build

**Documentation**:
- `EXTERNAL/mllm/README.md` - Main documentation
- `EXTERNAL/mllm/docs/` - Additional docs

### 8.2 Integration Files (To Be Created)

**Module Root**:
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-mllm/build.gradle.kts`
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-mllm/CMakeLists.txt`
- `sdk/runanywhere-kotlin/modules/runanywhere-llm-mllm/README.md`

**Common Main**:
- `src/commonMain/kotlin/com/runanywhere/sdk/llm/mllm/MLLMVisionModel.kt`
- `src/commonMain/kotlin/com/runanywhere/sdk/llm/mllm/MLLMConfiguration.kt`
- `src/commonMain/kotlin/com/runanywhere/sdk/llm/mllm/models/VLMModelType.kt`

**Android Main**:
- `src/androidMain/kotlin/com/runanywhere/sdk/llm/mllm/AndroidMLLMEngine.kt`
- `src/androidMain/kotlin/com/runanywhere/sdk/llm/mllm/MLLMVisionComponent.kt`
- `src/androidMain/cpp/mllm_jni.cpp`
- `src/androidMain/cpp/CMakeLists.txt`

---

## 9. Next Steps

### 9.1 Immediate Actions

1. **Review Plan**: Get approval for the integration approach
2. **Setup Submodule**: Add MLLM as git submodule
3. **Create Module**: Set up basic module structure
4. **Test Build**: Verify CMake builds for Android

### 9.2 Research Tasks

1. **Model Selection**: Identify which VLM models to support initially
2. **Memory Profiling**: Test memory requirements on target devices
3. **NPU Testing**: Verify QNN availability on test devices
4. **Performance Baseline**: Establish performance benchmarks

### 9.3 Planning Tasks

1. **Detailed Design**: Expand API design with edge cases
2. **Error Handling**: Define comprehensive error scenarios
3. **Testing Strategy**: Plan unit, integration, and E2E tests
4. **Documentation**: Outline user guides and API references

---

## 10. References

**Official MLLM**:
- GitHub: https://github.com/UbiquitousLearning/mllm
- Website: https://ubiquitouslearning.github.io/mllm_website/
- Research Paper: https://arxiv.org/pdf/2407.05858v1

**Model Repository**:
- HuggingFace: https://huggingface.co/mllmTeam

**Related Technologies**:
- Qualcomm QNN: https://developer.qualcomm.com/qualcomm-ai-engine-direct-sdk
- GGML: https://github.com/ggerganov/ggml
- llama.cpp: https://github.com/ggerganov/llama.cpp

**RunAnywhere SDK**:
- iOS Implementation: `sdk/runanywhere-swift/`
- Kotlin SDK: `sdk/runanywhere-kotlin/`
- Component Architecture: `CLAUDE.md`

---

## Conclusion

MLLM represents an excellent foundation for adding VLM capabilities to the RunAnywhere SDK. Its purpose-built mobile architecture, comprehensive model support, and clean JNI interface make it ideal for on-device multimodal AI. The proposed integration leverages existing RunAnywhere patterns (BaseComponent, ServiceContainer, EventBus) while maintaining cross-platform compatibility through the Kotlin Multiplatform architecture.

**Recommendation**: Proceed with MLLM integration as a separate module (`runanywhere-llm-mllm`) following the 12-week timeline outlined above. Start with Qwen2-VL 2B model for development and expand to additional models based on user demand.
