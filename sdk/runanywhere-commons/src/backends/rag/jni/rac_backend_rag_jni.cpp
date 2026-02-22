/**
 * @file rac_backend_rag_jni.cpp
 * @brief RunAnywhere Core - RAG Backend JNI Bridge
 *
 * Self-contained JNI layer for the RAG backend.
 *
 * Package: com.runanywhere.sdk.rag
 * Class: RAGBridge
 */

#include <jni.h>
#include <string>
#include <cstring>
#include <cstdio>

#ifdef __ANDROID__
#include <android/log.h>
#define TAG "RACRagJNI"
#define LOGi(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGe(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)
#define LOGw(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)
#else
#define LOGi(...) fprintf(stdout, "[INFO] " __VA_ARGS__); fprintf(stdout, "\n")
#define LOGe(...) fprintf(stderr, "[ERROR] " __VA_ARGS__); fprintf(stderr, "\n")
#define LOGw(...) fprintf(stdout, "[WARN] " __VA_ARGS__); fprintf(stdout, "\n")
#endif

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/features/rag/rac_rag_pipeline.h"

// Forward declarations
extern "C" rac_result_t rac_backend_rag_register(void);
extern "C" rac_result_t rac_backend_rag_unregister(void);

// =============================================================================
// Helpers
// =============================================================================

static std::string json_escape(const char* s) {
    if (!s) return "";
    std::string out;
    out.reserve(strlen(s) + 8);
    for (const char* p = s; *p; ++p) {
        switch (*p) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\r': out += "\\r";  break;
            case '\t': out += "\\t";  break;
            default:   out += *p;     break;
        }
    }
    return out;
}

static const char* get_string(JNIEnv* env, jstring jstr) {
    if (!jstr) return nullptr;
    return env->GetStringUTFChars(jstr, nullptr);
}

static void release_string(JNIEnv* env, jstring jstr, const char* str) {
    if (jstr && str) env->ReleaseStringUTFChars(jstr, str);
}

extern "C" {

// =============================================================================
// JNI_OnLoad
// =============================================================================

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    (void)vm;
    (void)reserved;
    LOGi("JNI_OnLoad: rac_backend_rag_jni loaded");
    return JNI_VERSION_1_6;
}

// =============================================================================
// Backend Registration
// =============================================================================

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_rag_RAGBridge_nativeRegister(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    LOGi("RAG nativeRegister called");

    rac_result_t result = rac_backend_rag_register();

    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        LOGe("Failed to register RAG backend: %d", result);
        return static_cast<jint>(result);
    }

    LOGi("RAG backend registered successfully");
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_rag_RAGBridge_nativeUnregister(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    LOGi("RAG nativeUnregister called");

    rac_result_t result = rac_backend_rag_unregister();

    if (result != RAC_SUCCESS) {
        LOGe("Failed to unregister RAG backend: %d", result);
    } else {
        LOGi("RAG backend unregistered");
    }

    return static_cast<jint>(result);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_rag_RAGBridge_nativeIsRegistered(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;

    const rac_module_info_t* info = nullptr;
    rac_result_t result = rac_module_get_info("rag", &info);
    return (result == RAC_SUCCESS && info != nullptr) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_rag_RAGBridge_nativeGetVersion(JNIEnv* env, jclass clazz) {
    (void)clazz;
    return env->NewStringUTF("1.0.0");
}

// =============================================================================
// Pipeline Operations
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_rag_RAGBridge_nativeCreatePipeline(
    JNIEnv* env, jclass clazz,
    jstring embeddingModelPath,
    jstring llmModelPath,
    jint embeddingDimension,
    jint topK,
    jfloat similarityThreshold,
    jint maxContextTokens,
    jint chunkSize,
    jint chunkOverlap,
    jstring promptTemplate,
    jstring embeddingConfigJson,
    jstring llmConfigJson)
{
    (void)clazz;

    const char* embPath  = get_string(env, embeddingModelPath);
    const char* llmPath  = get_string(env, llmModelPath);
    const char* tmpl     = get_string(env, promptTemplate);
    const char* embCfg   = get_string(env, embeddingConfigJson);
    const char* llmCfg   = get_string(env, llmConfigJson);

    if (!embPath) {
        LOGe("nativeCreatePipeline: embedding model path is required");
        release_string(env, llmModelPath, llmPath);
        release_string(env, promptTemplate, tmpl);
        release_string(env, embeddingConfigJson, embCfg);
        release_string(env, llmConfigJson, llmCfg);
        return 0;
    }

    LOGi("nativeCreatePipeline: emb=%s, llm=%s, dim=%d, topK=%d",
         embPath, llmPath ? llmPath : "(none)", embeddingDimension, topK);

    rac_rag_config_t config = rac_rag_config_default();
    config.embedding_model_path  = embPath;
    config.llm_model_path        = llmPath;
    config.embedding_dimension   = static_cast<size_t>(embeddingDimension);
    config.top_k                 = static_cast<size_t>(topK);
    config.similarity_threshold  = similarityThreshold;
    config.max_context_tokens    = static_cast<size_t>(maxContextTokens);
    config.chunk_size            = static_cast<size_t>(chunkSize);
    config.chunk_overlap         = static_cast<size_t>(chunkOverlap);
    if (tmpl)   config.prompt_template       = tmpl;
    if (embCfg) config.embedding_config_json = embCfg;
    if (llmCfg) config.llm_config_json       = llmCfg;

    rac_rag_pipeline_t* pipeline = nullptr;
    rac_result_t result = rac_rag_pipeline_create(&config, &pipeline);

    release_string(env, embeddingModelPath, embPath);
    release_string(env, llmModelPath, llmPath);
    release_string(env, promptTemplate, tmpl);
    release_string(env, embeddingConfigJson, embCfg);
    release_string(env, llmConfigJson, llmCfg);

    if (result != RAC_SUCCESS || !pipeline) {
        LOGe("nativeCreatePipeline: failed with result %d", result);
        return 0;
    }

    LOGi("nativeCreatePipeline: success, handle=%p", static_cast<void*>(pipeline));
    return reinterpret_cast<jlong>(pipeline);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_rag_RAGBridge_nativeDestroyPipeline(
    JNIEnv* env, jclass clazz, jlong pipelineHandle)
{
    (void)env;
    (void)clazz;

    if (pipelineHandle == 0) return;

    auto* pipeline = reinterpret_cast<rac_rag_pipeline_t*>(pipelineHandle);
    LOGi("nativeDestroyPipeline: handle=%p", static_cast<void*>(pipeline));
    rac_rag_pipeline_destroy(pipeline);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_rag_RAGBridge_nativeAddDocument(
    JNIEnv* env, jclass clazz,
    jlong pipelineHandle,
    jstring text,
    jstring metadataJson)
{
    (void)clazz;

    if (pipelineHandle == 0) {
        LOGe("nativeAddDocument: invalid handle");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* pipeline = reinterpret_cast<rac_rag_pipeline_t*>(pipelineHandle);

    const char* docText  = get_string(env, text);
    const char* metadata = get_string(env, metadataJson);

    if (!docText) {
        LOGe("nativeAddDocument: text is required");
        release_string(env, metadataJson, metadata);
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    LOGi("nativeAddDocument: text_len=%zu", strlen(docText));

    rac_result_t result = rac_rag_add_document(pipeline, docText, metadata);

    release_string(env, text, docText);
    release_string(env, metadataJson, metadata);

    if (result != RAC_SUCCESS) {
        LOGe("nativeAddDocument: failed with result %d", result);
    }

    return static_cast<jint>(result);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_rag_RAGBridge_nativeQuery(
    JNIEnv* env, jclass clazz,
    jlong pipelineHandle,
    jstring question,
    jstring systemPrompt,
    jint maxTokens,
    jfloat temperature,
    jfloat topP,
    jint topK)
{
    (void)clazz;

    if (pipelineHandle == 0) {
        LOGe("nativeQuery: invalid handle");
        return env->NewStringUTF("");
    }

    auto* pipeline = reinterpret_cast<rac_rag_pipeline_t*>(pipelineHandle);

    const char* questionStr = get_string(env, question);
    const char* sysPrompt   = get_string(env, systemPrompt);

    if (!questionStr) {
        LOGe("nativeQuery: question is required");
        release_string(env, systemPrompt, sysPrompt);
        return env->NewStringUTF("");
    }

    LOGi("nativeQuery: question_len=%zu, maxTokens=%d, temp=%.2f",
         strlen(questionStr), maxTokens, temperature);

    rac_rag_query_t query = {};
    query.question    = questionStr;
    query.system_prompt = sysPrompt;
    query.max_tokens  = maxTokens;
    query.temperature = temperature;
    query.top_p       = topP;
    query.top_k       = topK;

    rac_rag_result_t result = {};
    rac_result_t status = rac_rag_query(pipeline, &query, &result);

    release_string(env, question, questionStr);
    release_string(env, systemPrompt, sysPrompt);

    if (status != RAC_SUCCESS) {
        LOGe("nativeQuery: failed with status %d", status);
        return env->NewStringUTF("");
    }

    // Serialize result to JSON
    std::string json;
    json.reserve(1024);
    json += "{";
    json += "\"answer\":\"" + json_escape(result.answer) + "\"";
    json += ",\"context_used\":\"" + json_escape(result.context_used) + "\"";
    json += ",\"retrieval_time_ms\":" + std::to_string(result.retrieval_time_ms);
    json += ",\"generation_time_ms\":" + std::to_string(result.generation_time_ms);
    json += ",\"total_time_ms\":" + std::to_string(result.total_time_ms);
    json += ",\"retrieved_chunks\":[";
    for (size_t i = 0; i < result.num_chunks; ++i) {
        if (i > 0) json += ",";
        const auto& chunk = result.retrieved_chunks[i];
        json += "{";
        json += "\"chunk_id\":\"" + json_escape(chunk.chunk_id) + "\"";
        json += ",\"text\":\"" + json_escape(chunk.text) + "\"";
        char scoreStr[32];
        snprintf(scoreStr, sizeof(scoreStr), "%.6f", chunk.similarity_score);
        json += ",\"similarity_score\":" + std::string(scoreStr);
        json += ",\"metadata_json\":\"" + json_escape(chunk.metadata_json) + "\"";
        json += "}";
    }
    json += "]}";

    LOGi("nativeQuery: success, answer_len=%zu, chunks=%zu",
         result.answer ? strlen(result.answer) : 0, result.num_chunks);

    rac_rag_result_free(&result);

    return env->NewStringUTF(json.c_str());
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_rag_RAGBridge_nativeClearDocuments(
    JNIEnv* env, jclass clazz, jlong pipelineHandle)
{
    (void)env;
    (void)clazz;

    if (pipelineHandle == 0) {
        LOGe("nativeClearDocuments: invalid handle");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* pipeline = reinterpret_cast<rac_rag_pipeline_t*>(pipelineHandle);
    LOGi("nativeClearDocuments: handle=%p", static_cast<void*>(pipeline));

    rac_result_t result = rac_rag_clear_documents(pipeline);

    if (result != RAC_SUCCESS) {
        LOGe("nativeClearDocuments: failed with result %d", result);
    }

    return static_cast<jint>(result);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_rag_RAGBridge_nativeGetDocumentCount(
    JNIEnv* env, jclass clazz, jlong pipelineHandle)
{
    (void)env;
    (void)clazz;

    if (pipelineHandle == 0) {
        LOGe("nativeGetDocumentCount: invalid handle");
        return -1;
    }

    auto* pipeline = reinterpret_cast<rac_rag_pipeline_t*>(pipelineHandle);
    size_t count = rac_rag_get_document_count(pipeline);

    LOGi("nativeGetDocumentCount: count=%zu", count);
    return static_cast<jint>(count);
}

}  // extern "C"
