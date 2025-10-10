#include <jni.h>
#include <string>
#include <vector>
#include <memory>
#include <unordered_map>
#include <mutex>

#include "llama.h"
#include "common.h"

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
    llama_batch batch;
    llama_sampler* sampler = nullptr;
    std::string last_error;
    bool is_generating = false;
    std::mutex mutex;

    // Simple context parameters
    int n_ctx = 2048;
    int n_batch = 512;
    int n_threads = 4;
    int n_gpu_layers = 0;
    bool use_mmap = true;
    bool use_mlock = false;

    ~LlamaContext() {
        if (sampler) {
            llama_sampler_free(sampler);
        }
        if (batch.token) {
            llama_batch_free(batch);
        }
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

        // Set parameters
        context->n_gpu_layers = env->GetIntField(paramsObj, n_gpu_layers_field);
        context->n_ctx = env->GetIntField(paramsObj, n_ctx_field);
        context->n_batch = env->GetIntField(paramsObj, n_batch_field);
        context->n_threads = env->GetIntField(paramsObj, n_threads_field);
        context->use_mmap = env->GetBooleanField(paramsObj, use_mmap_field);
        context->use_mlock = env->GetBooleanField(paramsObj, use_mlock_field);

        LOGI("Parameters: n_ctx=%d, n_batch=%d, n_threads=%d, n_gpu_layers=%d",
             context->n_ctx, context->n_batch, context->n_threads, context->n_gpu_layers);

        // Load model with default parameters
        llama_model_params model_params = llama_model_default_params();
        model_params.n_gpu_layers = context->n_gpu_layers;
        model_params.use_mmap = context->use_mmap;
        model_params.use_mlock = context->use_mlock;

        context->model = llama_load_model_from_file(model_path.c_str(), model_params);
        if (!context->model) {
            LOGE("Failed to load model from: %s", model_path.c_str());
            return 0;
        }

        // Create context
        llama_context_params ctx_params = llama_context_default_params();
        ctx_params.n_ctx = context->n_ctx;
        ctx_params.n_batch = context->n_batch;
        ctx_params.n_threads = context->n_threads;
        ctx_params.n_threads_batch = context->n_threads;

        context->ctx = llama_new_context_with_model(context->model, ctx_params);
        if (!context->ctx) {
            LOGE("Failed to create context");
            return 0;
        }

        // Initialize batch
        context->batch = llama_batch_init(context->n_batch, 0, 1);

        // Initialize sampler (greedy by default)
        auto sparams = llama_sampler_chain_default_params();
        sparams.no_perf = true;
        context->sampler = llama_sampler_chain_init(sparams);
        llama_sampler_chain_add(context->sampler, llama_sampler_init_greedy());

        // Store in global map
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
    JNIEnv* /* env */, jobject /* this */, jlong contextHandle) {

    std::lock_guard<std::mutex> lock(g_contexts_mutex);
    auto it = g_contexts.find(contextHandle);
    if (it != g_contexts.end()) {
        LOGI("Freeing context: %ld", contextHandle);
        g_contexts.erase(it);
    }
}

JNIEXPORT jobject JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaGenerate(
    JNIEnv* env, jobject /* this */, jlong contextHandle, jstring jPrompt, jobject genParamsObj) {

    // Get context
    LlamaContext* context = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_contexts_mutex);
        auto it = g_contexts.find(contextHandle);
        if (it == g_contexts.end()) {
            LOGE("Invalid context handle: %ld", contextHandle);
            return nullptr;
        }
        context = it->second.get();
    }

    if (context->is_generating) {
        LOGE("Generation already in progress");
        return nullptr;
    }

    std::lock_guard<std::mutex> context_lock(context->mutex);
    context->is_generating = true;

    try {
        // Extract generation parameters
        jclass gen_params_class = env->GetObjectClass(genParamsObj);
        jfieldID max_tokens_field = env->GetFieldID(gen_params_class, "maxTokens", "I");
        jfieldID temperature_field = env->GetFieldID(gen_params_class, "temperature", "F");

        int max_tokens = env->GetIntField(genParamsObj, max_tokens_field);
        float temperature = env->GetFloatField(genParamsObj, temperature_field);

        // Convert prompt
        const char* prompt_cstr = env->GetStringUTFChars(jPrompt, nullptr);
        std::string prompt(prompt_cstr);
        env->ReleaseStringUTFChars(jPrompt, prompt_cstr);

        LOGI("Generating with prompt: %s (max_tokens=%d, temp=%f)",
             prompt.substr(0, 50).c_str(), max_tokens, temperature);

        // Tokenize prompt
        std::vector<llama_token> tokens_list = common_tokenize(context->ctx, prompt, true);

        if (tokens_list.empty()) {
            LOGE("Failed to tokenize prompt");
            context->is_generating = false;
            return nullptr;
        }

        // Clear KV cache and batch
        llama_kv_cache_clear(context->ctx);
        common_batch_clear(context->batch);

        // Add prompt tokens to batch
        for (size_t i = 0; i < tokens_list.size(); ++i) {
            common_batch_add(context->batch, tokens_list[i], i, {0}, false);
        }
        context->batch.logits[context->batch.n_tokens - 1] = true;

        // Evaluate prompt
        if (llama_decode(context->ctx, context->batch) != 0) {
            LOGE("Failed to decode prompt");
            context->is_generating = false;
            return nullptr;
        }

        // Generate tokens
        std::string generated_text;
        auto start_time = std::chrono::steady_clock::now();
        int tokens_generated = 0;
        int n_cur = tokens_list.size();

        for (int i = 0; i < max_tokens; ++i) {
            // Sample next token
            llama_token next_token = llama_sampler_sample(context->sampler, context->ctx, -1);

            // Check for end of generation
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

            // Prepare for next iteration
            common_batch_clear(context->batch);
            common_batch_add(context->batch, next_token, n_cur, {0}, true);
            n_cur++;

            if (llama_decode(context->ctx, context->batch) != 0) {
                LOGE("Failed to decode token");
                break;
            }

            // Accept the token
            llama_sampler_accept(context->sampler, next_token);
        }

        auto end_time = std::chrono::steady_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);

        context->is_generating = false;

        LOGI("Generated %d tokens in %ld ms", tokens_generated, duration.count());

        // Create result object
        jclass result_class = env->FindClass("com/runanywhere/sdk/llm/llamacpp/GenerationNativeResult");
        jmethodID constructor = env->GetMethodID(result_class, "<init>",
            "(Ljava/lang/String;IIJJJFZLjava/lang/String;)V");

        jstring j_text = env->NewStringUTF(generated_text.c_str());
        jstring j_stop_sequence = nullptr;

        return env->NewObject(result_class, constructor,
            j_text,                         // text
            tokens_generated,               // tokensGenerated
            (jint)tokens_list.size(),       // tokensEvaluated
            (jlong)0,                       // timePromptMs
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
    JNIEnv* env, jobject /* this */, jlong contextHandle, jstring jPrompt,
    jobject genParamsObj, jobject callback) {
    LOGI("Streaming generation not fully implemented yet");
}

// Stub implementations for remaining functions
JNIEXPORT jobject JNICALL Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaGetModelInfo(JNIEnv* env, jobject, jlong contextHandle) { return nullptr; }
JNIEXPORT jobject JNICALL Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaGetGpuInfo(JNIEnv* env, jobject) { return nullptr; }
JNIEXPORT jobject JNICALL Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaGetMemoryUsage(JNIEnv* env, jobject, jlong contextHandle) { return nullptr; }
JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaGetTokenCount(JNIEnv* env, jobject, jlong contextHandle, jstring jText) { return 0; }
JNIEXPORT jintArray JNICALL Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaTokenize(JNIEnv* env, jobject, jlong contextHandle, jstring jText) { return nullptr; }
JNIEXPORT jstring JNICALL Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaDetokenize(JNIEnv* env, jobject, jlong contextHandle, jintArray tokens) { return env->NewStringUTF(""); }
JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaGetVocabSize(JNIEnv*, jobject, jlong contextHandle) { return 0; }
JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaGetContextLength(JNIEnv*, jobject, jlong contextHandle) { return 0; }
JNIEXPORT void JNICALL Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaResetContext(JNIEnv*, jobject, jlong contextHandle) { }
JNIEXPORT jboolean JNICALL Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaSaveState(JNIEnv*, jobject, jlong contextHandle, jstring path) { return false; }
JNIEXPORT jboolean JNICALL Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaLoadState(JNIEnv*, jobject, jlong contextHandle, jstring path) { return false; }
JNIEXPORT void JNICALL Java_com_runanywhere_sdk_llm_llamacpp_LlamaCppNative_llamaSetMemoryLimit(JNIEnv*, jobject, jlong maxBytes) { }

} // extern "C"
