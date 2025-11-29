/**
 * CLIP JNI Bindings for RunAnywhere SDK
 *
 * This file provides JNI wrappers for llama.cpp's CLIP vision encoder,
 * enabling image understanding capabilities in the Kotlin SDK.
 *
 * Based on llama.cpp's clip.h API
 *
 * @author RunAnywhere Team
 * @date 2025-10-26
 */

#include <jni.h>
#include <android/log.h>
#include <string>
#include <vector>
#include <cstring>

// llama.cpp CLIP headers
#include "tools/mtmd/clip.h"
#include "ggml.h"

#define LOG_TAG "clip-jni"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Convert Java byte array to C unsigned char array
 * Caller must free the returned pointer using freeUnsignedChar()
 */
static unsigned char* jbyteArrayToUnsignedChar(JNIEnv* env, jbyteArray array, jsize* out_len) {
    if (array == nullptr) {
        return nullptr;
    }

    jsize len = env->GetArrayLength(array);
    if (out_len != nullptr) {
        *out_len = len;
    }

    unsigned char* data = new unsigned char[len];
    jbyte* java_bytes = env->GetByteArrayElements(array, nullptr);

    // Copy bytes
    for (jsize i = 0; i < len; i++) {
        data[i] = static_cast<unsigned char>(java_bytes[i]);
    }

    env->ReleaseByteArrayElements(array, java_bytes, JNI_ABORT);
    return data;
}

/**
 * Free unsigned char array allocated by jbyteArrayToUnsignedChar()
 */
static void freeUnsignedChar(unsigned char* ptr) {
    if (ptr != nullptr) {
        delete[] ptr;
    }
}

/**
 * Throw a Java exception from JNI
 */
static void throwJavaException(JNIEnv* env, const char* exception_class, const char* message) {
    jclass clazz = env->FindClass(exception_class);
    if (clazz != nullptr) {
        env->ThrowNew(clazz, message);
        env->DeleteLocalRef(clazz);
    } else {
        LOGE("Failed to find exception class: %s", exception_class);
    }
}

// ============================================================================
// CLIP Context Management
// ============================================================================

/**
 * Initialize CLIP vision model
 *
 * @param model_path Path to mmproj GGUF file
 * @param use_gpu Whether to use GPU acceleration
 * @return Pointer to clip_ctx (as jlong), or 0 on failure
 *
 * Java signature:
 * private external fun clip_model_init(path: String, useGpu: Boolean): Long
 */
extern "C" JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_clip_1model_1init(
    JNIEnv* env,
    jobject /* this */,
    jstring model_path,
    jboolean use_gpu
) {
    if (model_path == nullptr) {
        throwJavaException(env,
            "com/runanywhere/sdk/data/models/VLMServiceError$ModelNotFound",
            "Model path cannot be null");
        return 0;
    }

    const char* path_cstr = env->GetStringUTFChars(model_path, nullptr);
    LOGI("Loading CLIP model from: %s", path_cstr);

    // Configure CLIP context parameters
    struct clip_context_params params;
    params.use_gpu = static_cast<bool>(use_gpu);
    params.verbosity = GGML_LOG_LEVEL_ERROR;  // Only show errors

    // Initialize CLIP model
    struct clip_init_result result = clip_init(path_cstr, params);

    env->ReleaseStringUTFChars(model_path, path_cstr);

    if (result.ctx_v == nullptr) {
        throwJavaException(env,
            "com/runanywhere/sdk/data/models/VLMServiceError$ModelLoadFailed",
            "Failed to load CLIP vision model");
        return 0;
    }

    LOGI("CLIP model loaded successfully");
    return reinterpret_cast<jlong>(result.ctx_v);
}

/**
 * Free CLIP vision model context
 *
 * @param clip_ctx Pointer to clip_ctx
 *
 * Java signature:
 * private external fun clip_model_free(ctx: Long)
 */
extern "C" JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_clip_1model_1free(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong clip_ctx
) {
    if (clip_ctx == 0) {
        LOGW("Attempted to free null CLIP context");
        return;
    }

    struct clip_ctx* ctx = reinterpret_cast<struct clip_ctx*>(clip_ctx);
    clip_free(ctx);
    LOGI("CLIP model freed");
}

// ============================================================================
// Image Encoding
// ============================================================================

/**
 * Encode image to embeddings
 *
 * @param clip_ctx Pointer to clip_ctx
 * @param image_bytes Raw RGB image bytes
 * @param width Image width in pixels
 * @param height Image height in pixels
 * @param n_threads Number of threads for encoding
 * @return Pointer to float array containing embeddings, or 0 on failure
 *
 * Java signature:
 * private external fun clip_image_encode(
 *     clipCtx: Long,
 *     imageBytes: ByteArray,
 *     width: Int,
 *     height: Int,
 *     nThreads: Int
 * ): Long
 */
extern "C" JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_clip_1image_1encode(
    JNIEnv* env,
    jobject /* this */,
    jlong clip_ctx,
    jbyteArray image_bytes,
    jint width,
    jint height,
    jint n_threads
) {
    if (clip_ctx == 0) {
        throwJavaException(env,
            "com/runanywhere/sdk/data/models/VLMServiceError$NotInitialized",
            "CLIP context not initialized");
        return 0;
    }

    if (image_bytes == nullptr) {
        throwJavaException(env,
            "com/runanywhere/sdk/data/models/VLMServiceError$InvalidInput",
            "Image bytes cannot be null");
        return 0;
    }

    struct clip_ctx* ctx = reinterpret_cast<struct clip_ctx*>(clip_ctx);

    // Convert Java byte array to C array
    jsize len;
    unsigned char* rgb_pixels = jbyteArrayToUnsignedChar(env, image_bytes, &len);

    // Verify expected size (RGB = 3 bytes per pixel)
    jsize expected_size = width * height * 3;
    if (len != expected_size) {
        freeUnsignedChar(rgb_pixels);
        char error_msg[256];
        snprintf(error_msg, sizeof(error_msg),
            "Invalid image size: expected %d bytes (width=%d, height=%d), got %d bytes",
            expected_size, width, height, len);
        throwJavaException(env,
            "com/runanywhere/sdk/data/models/VLMServiceError$InvalidImageDimensions",
            error_msg);
        return 0;
    }

    LOGI("Encoding image: %dx%d, %d bytes", width, height, len);

    // Create CLIP image structure (u8 = unsigned 8-bit)
    struct clip_image_u8* img_u8 = clip_image_u8_init();
    if (img_u8 == nullptr) {
        freeUnsignedChar(rgb_pixels);
        throwJavaException(env,
            "com/runanywhere/sdk/data/models/VLMServiceError$InferenceError",
            "Failed to initialize image structure");
        return 0;
    }

    // Build image from raw pixels
    clip_build_img_from_pixels(rgb_pixels, width, height, img_u8);

    // Preprocess image (resize, normalize, etc.)
    struct clip_image_f32_batch* img_batch = clip_image_f32_batch_init();
    if (img_batch == nullptr) {
        clip_image_u8_free(img_u8);
        freeUnsignedChar(rgb_pixels);
        throwJavaException(env,
            "com/runanywhere/sdk/data/models/VLMServiceError$InferenceError",
            "Failed to initialize batch structure");
        return 0;
    }

    bool preprocess_success = clip_image_preprocess(ctx, img_u8, img_batch);
    if (!preprocess_success) {
        clip_image_f32_batch_free(img_batch);
        clip_image_u8_free(img_u8);
        freeUnsignedChar(rgb_pixels);
        throwJavaException(env,
            "com/runanywhere/sdk/data/models/VLMServiceError$ImageEncodingFailed",
            "Image preprocessing failed");
        return 0;
    }

    // Get embedding dimension
    int embd_dim = clip_n_mmproj_embd(ctx);
    if (embd_dim <= 0) {
        clip_image_f32_batch_free(img_batch);
        clip_image_u8_free(img_u8);
        freeUnsignedChar(rgb_pixels);
        throwJavaException(env,
            "com/runanywhere/sdk/data/models/VLMServiceError$InferenceError",
            "Invalid embedding dimension");
        return 0;
    }

    LOGI("Embedding dimension: %d", embd_dim);

    // Allocate embedding vector
    float* embeddings = new float[embd_dim];

    // Encode preprocessed image to embeddings
    bool encode_success = clip_image_batch_encode(ctx, n_threads, img_batch, embeddings);

    // Cleanup temporary structures
    clip_image_f32_batch_free(img_batch);
    clip_image_u8_free(img_u8);
    freeUnsignedChar(rgb_pixels);

    if (!encode_success) {
        delete[] embeddings;
        throwJavaException(env,
            "com/runanywhere/sdk/data/models/VLMServiceError$ImageEncodingFailed",
            "Image encoding failed");
        return 0;
    }

    LOGI("Image encoded successfully");
    return reinterpret_cast<jlong>(embeddings);
}

/**
 * Get embeddings as Java float array
 *
 * @param clip_ctx Pointer to clip_ctx
 * @param embeddings_ptr Pointer to embeddings array
 * @return Java float array containing embeddings
 *
 * Java signature:
 * private external fun clip_get_embeddings(clipCtx: Long, embeddingsPtr: Long): FloatArray
 */
extern "C" JNIEXPORT jfloatArray JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_clip_1get_1embeddings(
    JNIEnv* env,
    jobject /* this */,
    jlong clip_ctx,
    jlong embeddings_ptr
) {
    if (clip_ctx == 0 || embeddings_ptr == 0) {
        return nullptr;
    }

    struct clip_ctx* ctx = reinterpret_cast<struct clip_ctx*>(clip_ctx);
    float* embeddings = reinterpret_cast<float*>(embeddings_ptr);

    int embd_dim = clip_n_mmproj_embd(ctx);

    jfloatArray result = env->NewFloatArray(embd_dim);
    if (result == nullptr) {
        return nullptr;
    }

    env->SetFloatArrayRegion(result, 0, embd_dim, embeddings);

    return result;
}

/**
 * Free embeddings array
 *
 * @param embeddings_ptr Pointer to embeddings array
 *
 * Java signature:
 * private external fun clip_free_embeddings(embeddingsPtr: Long)
 */
extern "C" JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_clip_1free_1embeddings(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong embeddings_ptr
) {
    if (embeddings_ptr == 0) {
        LOGW("Attempted to free null embeddings");
        return;
    }

    float* embeddings = reinterpret_cast<float*>(embeddings_ptr);
    delete[] embeddings;
    LOGI("Embeddings freed");
}

// ============================================================================
// Model Information
// ============================================================================

/**
 * Get embedding dimension
 *
 * @param clip_ctx Pointer to clip_ctx
 * @return Embedding dimension
 *
 * Java signature:
 * private external fun clip_get_embed_dim(clipCtx: Long): Int
 */
extern "C" JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_clip_1get_1embed_1dim(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong clip_ctx
) {
    if (clip_ctx == 0) {
        return 0;
    }

    struct clip_ctx* ctx = reinterpret_cast<struct clip_ctx*>(clip_ctx);
    return clip_n_mmproj_embd(ctx);
}

/**
 * Get expected image size
 *
 * @param clip_ctx Pointer to clip_ctx
 * @return Image size (e.g., 336 for 336x336)
 *
 * Java signature:
 * private external fun clip_get_image_size(clipCtx: Long): Int
 */
extern "C" JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_clip_1get_1image_1size(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong clip_ctx
) {
    if (clip_ctx == 0) {
        return 0;
    }

    struct clip_ctx* ctx = reinterpret_cast<struct clip_ctx*>(clip_ctx);
    return clip_get_image_size(ctx);
}

/**
 * Get hidden size
 *
 * @param clip_ctx Pointer to clip_ctx
 * @return Hidden size
 *
 * Java signature:
 * private external fun clip_get_hidden_size(clipCtx: Long): Int
 */
extern "C" JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_clip_1get_1hidden_1size(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong clip_ctx
) {
    if (clip_ctx == 0) {
        return 0;
    }

    struct clip_ctx* ctx = reinterpret_cast<struct clip_ctx*>(clip_ctx);
    return clip_get_hidden_size(ctx);
}
