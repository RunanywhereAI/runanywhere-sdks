/**
 * @file flutter_rag_bridge.cpp
 * @brief Flutter RAG Bridge implementation
 *
 * Ported from React Native's RAGBridge.cpp with these changes:
 * - Removed Nitrogen/Promise dependencies
 * - Exposes plain C functions for Dart FFI
 * - Keeps model path resolution logic (GGUF scanning, vocab discovery)
 * - Keeps thread safety (std::mutex)
 * - Keeps nlohmann::json for parsing/serialization
 */

#include "flutter_rag_bridge.h"

#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <string>
#include <mutex>
#include <sys/stat.h>
#include <dirent.h>

#include "third_party/nlohmann/json.hpp"

// =============================================================================
// Forward declarations of RACommons C API (resolved from prebuilt library)
// =============================================================================

extern "C" {

typedef int32_t rac_result_t;
#define RAC_SUCCESS ((rac_result_t)0)

typedef struct rac_rag_pipeline rac_rag_pipeline_t;

typedef struct rac_search_result {
    char* chunk_id;
    char* text;
    float similarity_score;
    char* metadata_json;
} rac_search_result_t;

typedef struct rac_rag_config {
    const char* embedding_model_path;
    const char* llm_model_path;
    size_t embedding_dimension;
    size_t top_k;
    float similarity_threshold;
    size_t max_context_tokens;
    size_t chunk_size;
    size_t chunk_overlap;
    const char* prompt_template;
    const char* embedding_config_json;
    const char* llm_config_json;
} rac_rag_config_t;

typedef struct rac_rag_query {
    const char* question;
    const char* system_prompt;
    int max_tokens;
    float temperature;
    float top_p;
    int top_k;
} rac_rag_query_t;

typedef struct rac_rag_result {
    char* answer;
    rac_search_result_t* retrieved_chunks;
    size_t num_chunks;
    char* context_used;
    double retrieval_time_ms;
    double generation_time_ms;
    double total_time_ms;
} rac_rag_result_t;

// RACommons function declarations (linked from prebuilt library)
rac_result_t rac_backend_rag_register(void);
rac_result_t rac_rag_pipeline_create_standalone(
    const rac_rag_config_t* config,
    rac_rag_pipeline_t** out_pipeline);
void rac_rag_pipeline_destroy(rac_rag_pipeline_t* pipeline);

// Error detail API (rac_error.h) — returns thread-local detail string
const char* rac_error_get_details(void);
const char* rac_error_message(rac_result_t error_code);
rac_result_t rac_rag_add_document(
    rac_rag_pipeline_t* pipeline,
    const char* document_text,
    const char* metadata_json);
rac_result_t rac_rag_add_documents_batch(
    rac_rag_pipeline_t* pipeline,
    const char** documents,
    const char** metadata_array,
    size_t count);
rac_result_t rac_rag_query(
    rac_rag_pipeline_t* pipeline,
    const rac_rag_query_t* query,
    rac_rag_result_t* out_result);
rac_result_t rac_rag_clear_documents(rac_rag_pipeline_t* pipeline);
size_t rac_rag_get_document_count(rac_rag_pipeline_t* pipeline);
rac_result_t rac_rag_get_statistics(
    rac_rag_pipeline_t* pipeline,
    char** out_stats_json);
void rac_rag_result_free(rac_rag_result_t* result);

} // extern "C"

// =============================================================================
// Logging macros
// =============================================================================

#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "FlutterRAGBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define LOGI(...) do { printf("[FlutterRAGBridge] " __VA_ARGS__); printf("\n"); } while(0)
#define LOGE(...) do { fprintf(stderr, "[FlutterRAGBridge ERROR] " __VA_ARGS__); fprintf(stderr, "\n"); } while(0)
#endif

// =============================================================================
// Bridge state (singleton, thread-safe)
// =============================================================================

static rac_rag_pipeline_t* g_pipeline = nullptr;
static std::mutex g_mutex;
static bool g_registered = false;

// =============================================================================
// Helper: duplicate a string (caller must free with flutter_rag_free_string)
// =============================================================================

static char* dup_string(const std::string& s) {
    char* result = static_cast<char*>(malloc(s.size() + 1));
    if (result) {
        memcpy(result, s.c_str(), s.size() + 1);
    }
    return result;
}

/// Last error detail from createPipeline — readable via flutter_rag_get_last_error().
static std::string g_last_error;

// =============================================================================
// Bridge implementation
// =============================================================================

extern "C" {

int32_t flutter_rag_create_pipeline_json(const char* config_json) {
    std::lock_guard<std::mutex> lock(g_mutex);

    if (g_pipeline) {
        rac_rag_pipeline_destroy(g_pipeline);
        g_pipeline = nullptr;
    }

    // Auto-register RAG module (idempotent)
    if (!g_registered) {
        rac_backend_rag_register();
        g_registered = true;
    }

    try {
        auto json = nlohmann::json::parse(config_json);

        rac_rag_config_t config = {};
        config.embedding_dimension = 384;
        config.top_k = 10;
        config.similarity_threshold = 0.15f;
        config.max_context_tokens = 2048;
        config.chunk_size = 180;
        config.chunk_overlap = 30;

        std::string embPath = json.value("embeddingModelPath", "");
        std::string llmPath = json.value("llmModelPath", "");

        // Resolve LLM directory to .gguf file
        struct stat llmStat;
        if (!llmPath.empty() && stat(llmPath.c_str(), &llmStat) == 0 && S_ISDIR(llmStat.st_mode)) {
            DIR* dir = opendir(llmPath.c_str());
            if (dir) {
                struct dirent* entry;
                while ((entry = readdir(dir)) != nullptr) {
                    std::string name(entry->d_name);
                    if (name.size() > 5 && name.substr(name.size() - 5) == ".gguf") {
                        llmPath = llmPath + "/" + name;
                        LOGI("Resolved LLM directory to: %s", llmPath.c_str());
                        break;
                    }
                }
                closedir(dir);
            }
        }

        // Build embeddingConfigJSON with vocab_path if not already provided
        std::string embConfigJson = json.value("embeddingConfigJSON", "");
        if (embConfigJson.empty() && !embPath.empty()) {
            std::string vocabDir = embPath;
            struct stat embStat;
            if (stat(embPath.c_str(), &embStat) == 0) {
                if (!S_ISDIR(embStat.st_mode)) {
                    size_t lastSlash = embPath.rfind('/');
                    if (lastSlash != std::string::npos) {
                        vocabDir = embPath.substr(0, lastSlash);
                    }
                }
            } else {
                LOGE("Embedding model path does not exist: %s", embPath.c_str());
            }

            std::string vocabPath = vocabDir + "/vocab.txt";
            struct stat vocabStat;
            if (stat(vocabPath.c_str(), &vocabStat) == 0 && S_ISREG(vocabStat.st_mode)) {
                embConfigJson = "{\"vocab_path\":\"" + vocabPath + "\"}";
                LOGI("Resolved vocab.txt: %s", vocabPath.c_str());
            } else {
                LOGI("vocab.txt not at %s, scanning subdirectories...", vocabPath.c_str());
                DIR* dp = opendir(vocabDir.c_str());
                if (dp) {
                    struct dirent* entry;
                    while ((entry = readdir(dp)) != nullptr) {
                        if (entry->d_type != DT_DIR || entry->d_name[0] == '.') continue;
                        std::string subVocab = vocabDir + "/" + entry->d_name + "/vocab.txt";
                        if (stat(subVocab.c_str(), &vocabStat) == 0 && S_ISREG(vocabStat.st_mode)) {
                            vocabPath = subVocab;
                            embConfigJson = "{\"vocab_path\":\"" + vocabPath + "\"}";
                            LOGI("Found vocab.txt in subdirectory: %s", vocabPath.c_str());
                            break;
                        }
                    }
                    closedir(dp);
                }
                if (embConfigJson.empty()) {
                    LOGE("vocab.txt NOT found for embedding model at: %s", vocabDir.c_str());
                }
            }
        }

        config.embedding_model_path = embPath.c_str();
        config.llm_model_path = llmPath.empty() ? nullptr : llmPath.c_str();
        config.embedding_dimension = json.value("embeddingDimension", 384);
        config.top_k = json.value("topK", 10);
        config.similarity_threshold = json.value("similarityThreshold", 0.15f);
        config.max_context_tokens = json.value("maxContextTokens", 2048);
        config.chunk_size = json.value("chunkSize", 180);
        config.chunk_overlap = json.value("chunkOverlap", 30);

        std::string tmpl = json.value("promptTemplate", "");
        if (!tmpl.empty()) config.prompt_template = tmpl.c_str();

        if (!embConfigJson.empty()) config.embedding_config_json = embConfigJson.c_str();

        std::string llmConfigJson = json.value("llmConfigJSON", "");
        if (!llmConfigJson.empty()) config.llm_config_json = llmConfigJson.c_str();

        // Validate paths before calling C API
        struct stat pathStat;
        if (!embPath.empty() && stat(embPath.c_str(), &pathStat) != 0) {
            std::string msg = "Embedding model path does not exist: " + embPath;
            LOGE("%s", msg.c_str());
            g_last_error = msg;
            return -183; // RAC_ERROR_FILE_NOT_FOUND
        }
        if (!llmPath.empty() && stat(llmPath.c_str(), &pathStat) != 0) {
            std::string msg = "LLM model path does not exist: " + llmPath;
            LOGE("%s", msg.c_str());
            g_last_error = msg;
            return -183; // RAC_ERROR_FILE_NOT_FOUND
        }
        if (!embConfigJson.empty()) {
            // Extract vocab_path from config and validate it exists
            try {
                auto embCfg = nlohmann::json::parse(embConfigJson);
                std::string vocabPath = embCfg.value("vocab_path", "");
                if (!vocabPath.empty() && stat(vocabPath.c_str(), &pathStat) != 0) {
                    std::string msg = "vocab.txt not found at: " + vocabPath;
                    LOGE("%s", msg.c_str());
                    g_last_error = msg;
                    return -183; // RAC_ERROR_FILE_NOT_FOUND
                }
            } catch (...) {
                // embeddingConfigJSON isn't valid JSON — let C API handle it
            }
        }

        rac_rag_pipeline_t* newPipeline = nullptr;
        rac_result_t result = rac_rag_pipeline_create_standalone(&config, &newPipeline);

        if (result != RAC_SUCCESS || !newPipeline) {
            // Capture detailed error from RACommons
            const char* details = rac_error_get_details();
            const char* msg = rac_error_message(result);
            std::string errorStr = "createPipeline failed: code=" + std::to_string(result);
            if (msg) errorStr += " msg=" + std::string(msg);
            if (details) errorStr += " details=" + std::string(details);
            LOGE("%s", errorStr.c_str());
            g_last_error = errorStr;
            return result != RAC_SUCCESS ? result : -1;
        }

        g_pipeline = newPipeline;
        g_last_error.clear();
        LOGI("RAG pipeline created");
        return 0;

    } catch (const std::exception& e) {
        std::string msg = std::string("createPipeline exception: ") + e.what();
        LOGE("%s", msg.c_str());
        g_last_error = msg;
        return -1;
    }
}

int32_t flutter_rag_destroy_pipeline(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_pipeline) {
        rac_rag_pipeline_destroy(g_pipeline);
        g_pipeline = nullptr;
        return 0;
    }
    return -1;
}

int32_t flutter_rag_add_document(const char* text, const char* metadata_json) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_pipeline) return -1;

    rac_result_t result = rac_rag_add_document(g_pipeline, text, metadata_json);
    if (result != RAC_SUCCESS) {
        LOGE("addDocument failed: %d", result);
        return result;
    }
    return 0;
}

int32_t flutter_rag_add_documents_batch_json(const char* documents_json) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_pipeline) return -1;

    try {
        auto docs = nlohmann::json::parse(documents_json);
        if (!docs.is_array()) return -1;

        size_t count = docs.size();
        if (count == 0) return 0;

        // Build arrays for batch API
        std::vector<std::string> texts;
        std::vector<std::string> metas;
        std::vector<const char*> textPtrs;
        std::vector<const char*> metaPtrs;

        texts.reserve(count);
        metas.reserve(count);
        textPtrs.reserve(count);
        metaPtrs.reserve(count);

        for (const auto& doc : docs) {
            texts.push_back(doc.value("text", ""));
            std::string meta = doc.contains("metadataJson") ? doc["metadataJson"].dump() : "";
            metas.push_back(meta);
        }

        for (size_t i = 0; i < count; ++i) {
            textPtrs.push_back(texts[i].c_str());
            metaPtrs.push_back(metas[i].empty() ? nullptr : metas[i].c_str());
        }

        rac_result_t result = rac_rag_add_documents_batch(
            g_pipeline, textPtrs.data(), metaPtrs.data(), count);

        if (result != RAC_SUCCESS) {
            LOGE("addDocumentsBatch failed: %d", result);
            return result;
        }
        return 0;

    } catch (const std::exception& e) {
        LOGE("addDocumentsBatch exception: %s", e.what());
        return -1;
    }
}

const char* flutter_rag_query_json(const char* query_json) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_pipeline) return dup_string("{}");

    try {
        auto json = nlohmann::json::parse(query_json);

        rac_rag_query_t q = {};
        std::string question = json.value("question", "");
        std::string sysPrompt = json.value("systemPrompt", "");
        q.question = question.c_str();
        q.system_prompt = sysPrompt.empty() ? nullptr : sysPrompt.c_str();
        q.max_tokens = json.value("maxTokens", 512);
        q.temperature = json.value("temperature", 0.7f);
        q.top_p = json.value("topP", 0.9f);
        q.top_k = json.value("topK", 40);

        rac_rag_result_t result = {};
        rac_result_t status = rac_rag_query(g_pipeline, &q, &result);

        if (status != RAC_SUCCESS) {
            LOGE("query failed: %d", status);
            return dup_string("{}");
        }

        nlohmann::json out;
        out["answer"] = result.answer ? result.answer : "";
        out["contextUsed"] = result.context_used ? result.context_used : "";
        out["retrievalTimeMs"] = result.retrieval_time_ms;
        out["generationTimeMs"] = result.generation_time_ms;
        out["totalTimeMs"] = result.total_time_ms;

        nlohmann::json chunks = nlohmann::json::array();
        for (size_t i = 0; i < result.num_chunks; ++i) {
            nlohmann::json c;
            c["chunkId"] = result.retrieved_chunks[i].chunk_id
                ? result.retrieved_chunks[i].chunk_id : "";
            c["text"] = result.retrieved_chunks[i].text
                ? result.retrieved_chunks[i].text : "";
            c["similarityScore"] = result.retrieved_chunks[i].similarity_score;
            c["metadataJson"] = result.retrieved_chunks[i].metadata_json
                ? result.retrieved_chunks[i].metadata_json : "";
            chunks.push_back(c);
        }
        out["retrievedChunks"] = chunks;

        rac_rag_result_free(&result);

        return dup_string(out.dump());

    } catch (const std::exception& e) {
        LOGE("query exception: %s", e.what());
        return dup_string("{}");
    }
}

int32_t flutter_rag_clear_documents(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_pipeline) return -1;
    return rac_rag_clear_documents(g_pipeline) == RAC_SUCCESS ? 0 : -1;
}

int32_t flutter_rag_get_document_count(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_pipeline) return 0;
    return static_cast<int32_t>(rac_rag_get_document_count(g_pipeline));
}

const char* flutter_rag_get_statistics_json(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_pipeline) return dup_string("{}");

    char* statsJson = nullptr;
    rac_result_t result = rac_rag_get_statistics(g_pipeline, &statsJson);
    if (result != RAC_SUCCESS || !statsJson) return dup_string("{}");

    char* out = dup_string(std::string(statsJson));
    free(statsJson);
    return out;
}

void flutter_rag_free_string(const char* str) {
    free(const_cast<char*>(str));
}

const char* flutter_rag_get_last_error(void) {
    if (g_last_error.empty()) return nullptr;
    return dup_string(g_last_error);
}

} // extern "C"
