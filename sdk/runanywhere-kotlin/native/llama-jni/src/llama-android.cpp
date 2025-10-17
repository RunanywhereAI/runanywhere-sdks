#include <android/log.h>
#include <jni.h>
#include <string>
#include "llama.h"
#include "common.h"

#define TAG "llama-android"
#define LOGi(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGe(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// Global variables for JNI method caching
jclass la_int_var;
jmethodID la_int_var_value;
jmethodID la_int_var_inc;

std::string cached_token_chars;

// UTF-8 validation helper
bool is_valid_utf8(const char * string) {
    if (!string) return true;

    const unsigned char * bytes = (const unsigned char *)string;
    int num;

    while (*bytes != 0x00) {
        if ((*bytes & 0x80) == 0x00) {
            num = 1;
        } else if ((*bytes & 0xE0) == 0xC0) {
            num = 2;
        } else if ((*bytes & 0xF0) == 0xE0) {
            num = 3;
        } else if ((*bytes & 0xF8) == 0xF0) {
            num = 4;
        } else {
            return false;
        }

        bytes += 1;
        for (int i = 1; i < num; ++i) {
            if ((*bytes & 0xC0) != 0x80) return false;
            bytes += 1;
        }
    }
    return true;
}

// Log callback for llama.cpp
static void log_callback(ggml_log_level level, const char * fmt, void * data) {
    if (level == GGML_LOG_LEVEL_ERROR)     __android_log_print(ANDROID_LOG_ERROR, TAG, fmt, data);
    else if (level == GGML_LOG_LEVEL_INFO) __android_log_print(ANDROID_LOG_INFO, TAG, fmt, data);
    else if (level == GGML_LOG_LEVEL_WARN) __android_log_print(ANDROID_LOG_WARN, TAG, fmt, data);
    else __android_log_print(ANDROID_LOG_DEFAULT, TAG, fmt, data);
}

// JNI: Load model from file
extern "C"
JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_load_1model(JNIEnv *env, jobject, jstring filename) {
    llama_model_params model_params = llama_model_default_params();

    auto path_to_model = env->GetStringUTFChars(filename, 0);
    LOGi("Loading model from %s", path_to_model);

    auto model = llama_model_load_from_file(path_to_model, model_params);
    env->ReleaseStringUTFChars(filename, path_to_model);

    if (!model) {
        LOGe("load_model() failed");
        env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "load_model() failed");
        return 0;
    }

    return reinterpret_cast<jlong>(model);
}

// JNI: Free model
extern "C"
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_free_1model(JNIEnv *, jobject, jlong model) {
    llama_model_free(reinterpret_cast<llama_model *>(model));
}

// JNI: Create context with configurable parameters
extern "C"
JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_new_1context(
    JNIEnv *env, jobject, jlong jmodel, jint n_ctx, jint n_threads_hint) {
    auto model = reinterpret_cast<llama_model *>(jmodel);

    if (!model) {
        LOGe("new_context(): model cannot be null");
        env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Model cannot be null");
        return 0;
    }

    // Use provided n_threads or auto-detect
    int n_threads;
    if (n_threads_hint <= 0) {
        n_threads = std::max(1, std::min(8, (int) sysconf(_SC_NPROCESSORS_ONLN) - 2));
    } else {
        n_threads = n_threads_hint;
    }
    LOGi("Using %d threads (context size: %d)", n_threads, n_ctx);

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx           = n_ctx;
    ctx_params.n_batch         = n_ctx;  // Fix: Match batch size to context size (like SmolChat)
    ctx_params.n_threads       = n_threads;
    ctx_params.n_threads_batch = n_threads;
    ctx_params.no_perf         = true;   // Fix: Disable perf tracking for lower overhead (like SmolChat)

    llama_context * context = llama_init_from_model(model, ctx_params);

    if (!context) {
        LOGe("llama_init_from_model() returned null");
        env->ThrowNew(env->FindClass("java/lang/IllegalStateException"),
                      "llama_init_from_model() returned null");
        return 0;
    }

    return reinterpret_cast<jlong>(context);
}

// JNI: Free context
extern "C"
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_free_1context(JNIEnv *, jobject, jlong context) {
    llama_free(reinterpret_cast<llama_context *>(context));
}

// JNI: Backend initialization
extern "C"
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_backend_1init(JNIEnv *, jobject, jboolean numa) {
    llama_backend_init();
}

// JNI: Backend cleanup
extern "C"
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_backend_1free(JNIEnv *, jobject) {
    llama_backend_free();
}

// JNI: Set Android logger
extern "C"
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_log_1to_1android(JNIEnv *, jobject) {
    llama_log_set(log_callback, NULL);
}

// JNI: System info
extern "C"
JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_system_1info(JNIEnv *env, jobject) {
    return env->NewStringUTF(llama_print_system_info());
}

// JNI: Create batch
extern "C"
JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_new_1batch(JNIEnv *, jobject, jint n_tokens, jint embd, jint n_seq_max) {
    llama_batch *batch = new llama_batch {
        0, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr,
    };

    if (embd) {
        batch->embd = (float *) malloc(sizeof(float) * n_tokens * embd);
    } else {
        batch->token = (llama_token *) malloc(sizeof(llama_token) * n_tokens);
    }

    batch->pos      = (llama_pos *)     malloc(sizeof(llama_pos)      * n_tokens);
    batch->n_seq_id = (int32_t *)       malloc(sizeof(int32_t)        * n_tokens);
    batch->seq_id   = (llama_seq_id **) malloc(sizeof(llama_seq_id *) * n_tokens);
    for (int i = 0; i < n_tokens; ++i) {
        batch->seq_id[i] = (llama_seq_id *) malloc(sizeof(llama_seq_id) * n_seq_max);
    }
    batch->logits   = (int8_t *)        malloc(sizeof(int8_t)         * n_tokens);

    return reinterpret_cast<jlong>(batch);
}

// JNI: Free batch
extern "C"
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_free_1batch(JNIEnv *, jobject, jlong batch_pointer) {
    const auto batch = reinterpret_cast<llama_batch *>(batch_pointer);
    free(batch->pos);
    free(batch->n_seq_id);
    for (int i = 0; i < 512; ++i) {  // Match batch size
        free(batch->seq_id[i]);
    }
    free(batch->seq_id);
    free(batch->logits);
    if (batch->token) free(batch->token);
    if (batch->embd) free(batch->embd);
    delete batch;
}

// JNI: Create sampler with configurable parameters
extern "C"
JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_new_1sampler(
    JNIEnv *, jobject, jfloat temperature, jfloat min_p, jint top_k) {

    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    llama_sampler * smpl = llama_sampler_chain_init(sparams);

    // Add sampling strategies based on parameters
    if (temperature > 0.0f) {
        // Temperature-based sampling
        llama_sampler_chain_add(smpl, llama_sampler_init_temp(temperature));

        // Add min-P sampling if specified
        if (min_p > 0.0f && min_p < 1.0f) {
            llama_sampler_chain_add(smpl, llama_sampler_init_min_p(min_p, 1));
        }

        // Add top-K sampling if specified
        if (top_k > 0) {
            llama_sampler_chain_add(smpl, llama_sampler_init_top_k(top_k));
        }

        // Distribution sampler for probabilistic selection
        llama_sampler_chain_add(smpl, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

        LOGi("Created sampler: temp=%.2f, min_p=%.2f, top_k=%d", temperature, min_p, top_k);
    } else {
        // Greedy sampling (deterministic)
        llama_sampler_chain_add(smpl, llama_sampler_init_greedy());
        LOGi("Created greedy sampler");
    }

    return reinterpret_cast<jlong>(smpl);
}

// JNI: Free sampler
extern "C"
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_free_1sampler(JNIEnv *, jobject, jlong sampler_pointer) {
    llama_sampler_free(reinterpret_cast<llama_sampler *>(sampler_pointer));
}

// JNI: Initialize completion
extern "C"
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_completion_1init(
    JNIEnv *env, jobject,
    jlong context_pointer,
    jlong batch_pointer,
    jstring jtext,
    jboolean parse_special_tokens,  // Changed parameter name for clarity
    jint n_len
) {
    cached_token_chars.clear();

    const auto text = env->GetStringUTFChars(jtext, 0);
    const auto context = reinterpret_cast<llama_context *>(context_pointer);
    const auto batch = reinterpret_cast<llama_batch *>(batch_pointer);

    // Use the parse_special_tokens parameter (defaults to true in Kotlin)
    // This ensures special tokens like <|im_start|>, <|im_end|> are properly recognized
    // for chat-formatted models like Qwen2, while allowing flexibility for other models
    bool parse_special = (parse_special_tokens == JNI_TRUE);
    const auto tokens_list = common_tokenize(context, text, true, parse_special);

    auto n_ctx = llama_n_ctx(context);
    auto n_kv_req = tokens_list.size() + n_len;

    LOGi("n_len = %d, n_ctx = %d, n_kv_req = %zu", n_len, n_ctx, n_kv_req);

    if (n_kv_req > n_ctx) {
        LOGe("error: n_kv_req (%zu) > n_ctx (%d), the required KV cache size is not big enough", n_kv_req, n_ctx);
        env->ReleaseStringUTFChars(jtext, text);
        env->ThrowNew(env->FindClass("java/lang/IllegalStateException"),
            "Context size exceeded: increase context_length in configuration");
        return -1;
    }

    common_batch_clear(*batch);

    // Evaluate the initial prompt
    for (auto i = 0; i < tokens_list.size(); i++) {
        common_batch_add(*batch, tokens_list[i], i, { 0 }, false);
    }

    batch->logits[batch->n_tokens - 1] = true;

    if (llama_decode(context, *batch) != 0) {
        LOGe("llama_decode() failed");
    }

    env->ReleaseStringUTFChars(jtext, text);

    return batch->n_tokens;
}

// JNI: Completion loop (generates one token)
extern "C"
JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_completion_1loop(
    JNIEnv * env, jobject,
    jlong context_pointer,
    jlong batch_pointer,
    jlong sampler_pointer,
    jint n_len,
    jobject intvar_ncur
) {
    const auto context = reinterpret_cast<llama_context *>(context_pointer);
    const auto batch   = reinterpret_cast<llama_batch   *>(batch_pointer);
    const auto sampler = reinterpret_cast<llama_sampler *>(sampler_pointer);
    const auto model = llama_get_model(context);
    const auto vocab = llama_model_get_vocab(model);

    if (!la_int_var) la_int_var = env->GetObjectClass(intvar_ncur);
    if (!la_int_var_value) la_int_var_value = env->GetMethodID(la_int_var, "getValue", "()I");
    if (!la_int_var_inc) la_int_var_inc = env->GetMethodID(la_int_var, "inc", "()V");

    // Sample the most likely token
    const auto new_token_id = llama_sampler_sample(sampler, context, -1);

    const auto n_cur = env->CallIntMethod(intvar_ncur, la_int_var_value);
    if (llama_vocab_is_eog(vocab, new_token_id) || n_cur == n_len) {
        return nullptr;
    }

    auto new_token_chars = common_token_to_piece(context, new_token_id);
    cached_token_chars += new_token_chars;

    jstring new_token = nullptr;
    if (is_valid_utf8(cached_token_chars.c_str())) {
        new_token = env->NewStringUTF(cached_token_chars.c_str());
        cached_token_chars.clear();
    } else {
        new_token = env->NewStringUTF("");
    }

    common_batch_clear(*batch);
    common_batch_add(*batch, new_token_id, n_cur, { 0 }, true);

    env->CallVoidMethod(intvar_ncur, la_int_var_inc);

    if (llama_decode(context, *batch) != 0) {
        LOGe("llama_decode() returned null");
    }

    return new_token;
}

// JNI: Clear KV cache
extern "C"
JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_llm_llamacpp_LLamaAndroid_kv_1cache_1clear(JNIEnv *, jobject, jlong context) {
    llama_memory_clear(llama_get_memory(reinterpret_cast<llama_context *>(context)), true);
}
