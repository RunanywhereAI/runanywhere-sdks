#include <jni.h>
#include <string>
#include <vector>
#include <memory>
#include <unordered_map>
#include <mutex>
#include <functional>

#include "llama.h"
#include "common.h"
#include "sampling.h"

// JNI utility functions
#include "llama_jni_utils.h"

#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "LlamaJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <iostream>
#define LOGI(...) fprintf(stdout, __VA_ARGS__); fprintf(stdout, "\n")
#define LOGE(...) fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n")
#endif

// Context management
struct LlamaContext {
    llama_model* model = nullptr;
    llama_context* ctx = nullptr;
    gpt_params params;
    std::vector<llama_token> tokens;
    std::string last_error;
    bool is_generating = false;
    std::mutex mutex;
    
    ~LlamaContext() {
        if (ctx) {
            llama_free(ctx);
        }
        if (model) {
            llama_free_model(model);
        }
    }
};

// Global context management
static std::unordered_map<jlong, std::unique_ptr<LlamaContext>> g_contexts;
static std::mutex g_contexts_mutex;
static bool g_backend_initialized = false;

// Initialize backend
static void init_backend() {
    if (!g_backend_initialized) {
        llama_backend_init();
        llama_numa_init(GGML_NUMA_STRATEGY_DISTRIBUTE);
        g_backend_initialized = true;
        LOGI("Llama backend initialized");
    }
}

extern "C" {

// Native method implementations
JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaInit(
    JNIEnv* env, jobject /* this */, jstring modelPath, jobject paramsObj) {
    
    init_backend();
    
    // Convert Java string to C++ string
    const char* model_path_cstr = env->GetStringUTFChars(modelPath, nullptr);
    std::string model_path(model_path_cstr);
    env->ReleaseStringUTFChars(modelPath, model_path_cstr);
    
    LOGI("Loading model from: %s", model_path.c_str());
    
    try {
        auto context = std::make_unique<LlamaContext>();
        
        // Extract parameters from Java object
        jclass params_class = env->GetObjectClass(paramsObj);
        
        jfieldID n_gpu_layers_field = env->GetFieldID(params_class, "nGpuLayers", "I");
        jfieldID n_ctx_field = env->GetFieldID(params_class, "nCtx", "I");
        jfieldID n_batch_field = env->GetFieldID(params_class, "nBatch", "I");
        jfieldID n_threads_field = env->GetFieldID(params_class, "nThreads", "I");
        jfieldID use_mmap_field = env->GetFieldID(params_class, "useMmap", "Z");
        jfieldID use_mlock_field = env->GetFieldID(params_class, "useMlock", "Z");
        jfieldID f16_kv_field = env->GetFieldID(params_class, "f16Kv", "Z");
        
        // Set parameters
        context->params.n_gpu_layers = env->GetIntField(paramsObj, n_gpu_layers_field);
        context->params.n_ctx = env->GetIntField(paramsObj, n_ctx_field);
        context->params.n_batch = env->GetIntField(paramsObj, n_batch_field);
        context->params.n_threads = env->GetIntField(paramsObj, n_threads_field);
        context->params.use_mmap = env->GetBooleanField(paramsObj, use_mmap_field);
        context->params.use_mlock = env->GetBooleanField(paramsObj, use_mlock_field);
        context->params.flash_attn = true; // Enable flash attention
        
        // Load model
        llama_model_params model_params = llama_model_default_params();
        model_params.n_gpu_layers = context->params.n_gpu_layers;
        model_params.use_mmap = context->params.use_mmap;
        model_params.use_mlock = context->params.use_mlock;
        
        context->model = llama_load_model_from_file(model_path.c_str(), model_params);
        if (!context->model) {
            LOGE("Failed to load model from: %s", model_path.c_str());
            return 0;
        }
        
        // Create context
        llama_context_params ctx_params = llama_context_default_params();
        ctx_params.n_ctx = context->params.n_ctx;
        ctx_params.n_batch = context->params.n_batch;
        ctx_params.n_threads = context->params.n_threads;
        ctx_params.flash_attn = true;
        
        context->ctx = llama_new_context_with_model(context->model, ctx_params);
        if (!context->ctx) {
            LOGE("Failed to create llama context");
            return 0;
        }
        
        // Store context and return handle
        jlong handle = reinterpret_cast<jlong>(context.get());
        {
            std::lock_guard<std::mutex> lock(g_contexts_mutex);
            g_contexts[handle] = std::move(context);
        }
        
        LOGI("Model loaded successfully, handle: %ld", handle);
        return handle;
        
    } catch (const std::exception& e) {
        LOGE("Exception in llamaInit: %s", e.what());
        return 0;
    }
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaFree(
    JNIEnv* env, jobject /* this */, jlong handle) {
    
    std::lock_guard<std::mutex> lock(g_contexts_mutex);
    auto it = g_contexts.find(handle);
    if (it != g_contexts.end()) {
        LOGI("Freeing context handle: %ld", handle);
        g_contexts.erase(it);
    }
}

JNIEXPORT jobject JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaGenerate(
    JNIEnv* env, jobject /* this */, jlong handle, jstring promptStr, jobject paramsObj) {
    
    std::lock_guard<std::mutex> contexts_lock(g_contexts_mutex);
    auto it = g_contexts.find(handle);
    if (it == g_contexts.end()) {
        LOGE("Invalid context handle: %ld", handle);
        return nullptr;
    }
    
    auto& context = it->second;
    std::lock_guard<std::mutex> context_lock(context->mutex);
    
    if (context->is_generating) {
        LOGE("Generation already in progress");
        return nullptr;
    }
    
    context->is_generating = true;
    
    try {
        // Convert prompt to string
        const char* prompt_cstr = env->GetStringUTFChars(promptStr, nullptr);
        std::string prompt(prompt_cstr);
        env->ReleaseStringUTFChars(promptStr, prompt_cstr);
        
        // Extract generation parameters
        jclass params_class = env->GetObjectClass(paramsObj);
        jfieldID max_tokens_field = env->GetFieldID(params_class, "maxTokens", "I");
        jfieldID temperature_field = env->GetFieldID(params_class, "temperature", "F");
        jfieldID top_k_field = env->GetFieldID(params_class, "topK", "I");
        jfieldID top_p_field = env->GetFieldID(params_class, "topP", "F");
        
        int max_tokens = env->GetIntField(paramsObj, max_tokens_field);
        float temperature = env->GetFloatField(paramsObj, temperature_field);
        int top_k = env->GetIntField(paramsObj, top_k_field);
        float top_p = env->GetFloatField(paramsObj, top_p_field);
        
        LOGI("Generating with: maxTokens=%d, temp=%.2f, topK=%d, topP=%.2f", 
             max_tokens, temperature, top_k, top_p);
        
        // Tokenize prompt
        context->tokens.clear();
        context->tokens = llama_tokenize(context->ctx, prompt, true, true);
        
        if (context->tokens.empty()) {
            LOGE("Failed to tokenize prompt");
            context->is_generating = false;
            return nullptr;
        }
        
        // Evaluate prompt
        llama_batch batch = llama_batch_init(context->params.n_batch, 0, 1);
        for (size_t i = 0; i < context->tokens.size(); ++i) {
            llama_batch_add(batch, context->tokens[i], i, {0}, false);
        }
        batch.logits[batch.n_tokens - 1] = true;
        
        if (llama_decode(context->ctx, batch) != 0) {
            LOGE("Failed to decode prompt");
            llama_batch_free(batch);
            context->is_generating = false;
            return nullptr;
        }
        
        // Generate tokens
        std::string generated_text;
        auto start_time = std::chrono::steady_clock::now();
        
        struct llama_sampling_context* smpl_ctx = llama_sampling_init({});
        smpl_ctx->params.temp = temperature;
        smpl_ctx->params.top_k = top_k;
        smpl_ctx->params.top_p = top_p;
        smpl_ctx->params.min_p = 0.05f;
        smpl_ctx->params.typ_p = 1.0f;
        smpl_ctx->params.penalty_repeat = 1.1f;
        smpl_ctx->params.penalty_last_n = 64;
        
        int tokens_generated = 0;
        for (int i = 0; i < max_tokens; ++i) {
            // Sample next token
            llama_token next_token = llama_sampling_sample(smpl_ctx, context->ctx, nullptr);
            
            if (llama_token_is_eog(context->model, next_token)) {
                break;
            }
            
            // Convert token to text
            char token_str[256];
            int n = llama_token_to_piece(context->model, next_token, token_str, sizeof(token_str), 0, true);
            if (n > 0) {
                generated_text.append(token_str, n);
                tokens_generated++;
            }
            
            // Add token for next iteration
            context->tokens.push_back(next_token);
            llama_batch_clear(batch);
            llama_batch_add(batch, next_token, context->tokens.size() - 1, {0}, true);
            
            if (llama_decode(context->ctx, batch) != 0) {
                LOGE("Failed to decode token");
                break;
            }
            
            llama_sampling_accept(smpl_ctx, context->ctx, next_token, true);
        }
        
        auto end_time = std::chrono::steady_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
        
        llama_sampling_free(smpl_ctx);
        llama_batch_free(batch);
        context->is_generating = false;
        
        LOGI("Generated %d tokens in %ld ms", tokens_generated, duration.count());
        
        // Create result object
        jclass result_class = env->FindClass("com/runanywhere/sdk/llm/llamacpp/GenerationNativeResult");
        jmethodID constructor = env->GetMethodID(result_class, "<init>", 
            "(Ljava/lang/String;IIJJJFZLjava/lang/String;)V");
        
        jstring j_text = env->NewStringUTF(generated_text.c_str());
        jstring j_stop_sequence = nullptr; // No stop sequence detected
        
        return env->NewObject(result_class, constructor,
            j_text,                         // text
            tokens_generated,               // tokensGenerated
            (jint)context->tokens.size(),   // tokensEvaluated
            (jlong)0,                       // timePromptMs (not tracked separately)
            (jlong)duration.count(),        // timeGenerationMs
            (jlong)duration.count(),        // timeTotalMs
            (jfloat)(tokens_generated * 1000.0f / duration.count()), // tokensPerSecond
            false,                          // stoppedByLimit
            j_stop_sequence                 // stoppedBySequence
        );
        
    } catch (const std::exception& e) {
        LOGE("Exception in llamaGenerate: %s", e.what());
        context->is_generating = false;
        return nullptr;
    }
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaGenerateStream(
    JNIEnv* env, jobject /* this */, jlong handle, jstring promptStr, 
    jobject paramsObj, jobject callback) {
    
    std::lock_guard<std::mutex> contexts_lock(g_contexts_mutex);
    auto it = g_contexts.find(handle);
    if (it == g_contexts.end()) {
        LOGE("Invalid context handle: %ld", handle);
        return;
    }
    
    auto& context = it->second;
    std::lock_guard<std::mutex> context_lock(context->mutex);
    
    if (context->is_generating) {
        LOGE("Generation already in progress");
        return;
    }
    
    context->is_generating = true;
    
    try {
        // Get callback method
        jclass callback_class = env->GetObjectClass(callback);
        jmethodID callback_method = env->GetMethodID(callback_class, "invoke", "(Ljava/lang/String;)V");
        
        // Convert prompt and extract parameters (similar to generate method)
        const char* prompt_cstr = env->GetStringUTFChars(promptStr, nullptr);
        std::string prompt(prompt_cstr);
        env->ReleaseStringUTFChars(promptStr, prompt_cstr);
        
        // Extract generation parameters
        jclass params_class = env->GetObjectClass(paramsObj);
        jfieldID max_tokens_field = env->GetFieldID(params_class, "maxTokens", "I");
        jfieldID temperature_field = env->GetFieldID(params_class, "temperature", "F");
        jfieldID top_k_field = env->GetFieldID(params_class, "topK", "I");
        jfieldID top_p_field = env->GetFieldID(params_class, "topP", "F");
        
        int max_tokens = env->GetIntField(paramsObj, max_tokens_field);
        float temperature = env->GetFloatField(paramsObj, temperature_field);
        int top_k = env->GetIntField(paramsObj, top_k_field);
        float top_p = env->GetFloatField(paramsObj, top_p_field);
        
        // Tokenize and setup (similar to generate method)
        context->tokens.clear();
        context->tokens = llama_tokenize(context->ctx, prompt, true, true);
        
        llama_batch batch = llama_batch_init(context->params.n_batch, 0, 1);
        for (size_t i = 0; i < context->tokens.size(); ++i) {
            llama_batch_add(batch, context->tokens[i], i, {0}, false);
        }
        batch.logits[batch.n_tokens - 1] = true;
        
        if (llama_decode(context->ctx, batch) != 0) {
            LOGE("Failed to decode prompt");
            llama_batch_free(batch);
            context->is_generating = false;
            return;
        }
        
        // Stream generation
        struct llama_sampling_context* smpl_ctx = llama_sampling_init({});
        smpl_ctx->params.temp = temperature;
        smpl_ctx->params.top_k = top_k;
        smpl_ctx->params.top_p = top_p;
        
        for (int i = 0; i < max_tokens; ++i) {
            llama_token next_token = llama_sampling_sample(smpl_ctx, context->ctx, nullptr);
            
            if (llama_token_is_eog(context->model, next_token)) {
                break;
            }
            
            // Convert token to text and call callback
            char token_str[256];
            int n = llama_token_to_piece(context->model, next_token, token_str, sizeof(token_str), 0, true);
            if (n > 0) {
                jstring j_token = env->NewStringUTF(std::string(token_str, n).c_str());
                env->CallVoidMethod(callback, callback_method, j_token);
                env->DeleteLocalRef(j_token);
            }
            
            // Continue generation
            context->tokens.push_back(next_token);
            llama_batch_clear(batch);
            llama_batch_add(batch, next_token, context->tokens.size() - 1, {0}, true);
            
            if (llama_decode(context->ctx, batch) != 0) {
                LOGE("Failed to decode token");
                break;
            }
            
            llama_sampling_accept(smpl_ctx, context->ctx, next_token, true);
        }
        
        llama_sampling_free(smpl_ctx);
        llama_batch_free(batch);
        context->is_generating = false;
        
    } catch (const std::exception& e) {
        LOGE("Exception in llamaGenerateStream: %s", e.what());
        context->is_generating = false;
    }
}

JNIEXPORT jintArray JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaTokenize(
    JNIEnv* env, jobject /* this */, jlong handle, jstring textStr) {
    
    std::lock_guard<std::mutex> contexts_lock(g_contexts_mutex);
    auto it = g_contexts.find(handle);
    if (it == g_contexts.end()) {
        return nullptr;
    }
    
    auto& context = it->second;
    
    const char* text_cstr = env->GetStringUTFChars(textStr, nullptr);
    std::string text(text_cstr);
    env->ReleaseStringUTFChars(textStr, text_cstr);
    
    std::vector<llama_token> tokens = llama_tokenize(context->ctx, text, false, true);
    
    jintArray result = env->NewIntArray(tokens.size());
    env->SetIntArrayRegion(result, 0, tokens.size(), reinterpret_cast<const jint*>(tokens.data()));
    
    return result;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaGetTokenCount(
    JNIEnv* env, jobject /* this */, jlong handle, jstring textStr) {
    
    std::lock_guard<std::mutex> contexts_lock(g_contexts_mutex);
    auto it = g_contexts.find(handle);
    if (it == g_contexts.end()) {
        return -1;
    }
    
    auto& context = it->second;
    
    const char* text_cstr = env->GetStringUTFChars(textStr, nullptr);
    std::string text(text_cstr);
    env->ReleaseStringUTFChars(textStr, text_cstr);
    
    std::vector<llama_token> tokens = llama_tokenize(context->ctx, text, false, true);
    return static_cast<jint>(tokens.size());
}

// Additional utility methods would be implemented here...
// For brevity, I'll include placeholders for the remaining methods

JNIEXPORT jobject JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaGetModelInfo(
    JNIEnv* env, jobject /* this */, jlong handle) {
    // Implementation would extract model metadata
    return nullptr;
}

JNIEXPORT jobject JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaGetGpuInfo(
    JNIEnv* env, jobject /* this */) {
    // Implementation would check GPU capabilities
    return nullptr;
}

JNIEXPORT jobject JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaGetMemoryUsage(
    JNIEnv* env, jobject /* this */, jlong handle) {
    // Implementation would return memory usage statistics
    return nullptr;
}

} // extern "C"