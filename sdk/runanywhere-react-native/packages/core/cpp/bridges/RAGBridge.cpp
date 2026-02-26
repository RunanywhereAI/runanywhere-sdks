/**
 * @file RAGBridge.cpp
 * @brief RAG pipeline bridge implementation
 */

#include "RAGBridge.hpp"

#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <stdexcept>

#include <nlohmann/json.hpp>

#include <rac/features/rag/rac_rag.h>
#include <rac/features/rag/rac_rag_pipeline.h>
#include <rac/core/rac_error.h>

#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "RAGBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define LOGI(...) printf("[RAGBridge] " __VA_ARGS__); printf("\n")
#define LOGE(...) fprintf(stderr, "[RAGBridge ERROR] " __VA_ARGS__); fprintf(stderr, "\n")
#endif

namespace runanywhere {
namespace bridges {

RAGBridge& RAGBridge::shared() {
    static RAGBridge instance;
    return instance;
}

bool RAGBridge::createPipeline(const std::string& configJson) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (pipeline_) {
        rac_rag_pipeline_destroy(pipeline_);
        pipeline_ = nullptr;
    }

    // Register RAG module (idempotent)
    rac_backend_rag_register();

    try {
        auto json = nlohmann::json::parse(configJson);

        rac_rag_config_t config = rac_rag_config_default();

        std::string embPath = json.value("embeddingModelPath", "");
        std::string llmPath = json.value("llmModelPath", "");
        config.embedding_model_path = embPath.c_str();
        config.llm_model_path = llmPath.empty() ? nullptr : llmPath.c_str();
        config.embedding_dimension = json.value("embeddingDimension", 384);
        config.top_k = json.value("topK", 10);
        config.similarity_threshold = json.value("similarityThreshold", 0.15f);
        config.max_context_tokens = json.value("maxContextTokens", 2048);
        config.chunk_size = json.value("chunkSize", 512);
        config.chunk_overlap = json.value("chunkOverlap", 50);

        std::string tmpl = json.value("promptTemplate", "");
        if (!tmpl.empty()) config.prompt_template = tmpl.c_str();

        rac_rag_pipeline_t* newPipeline = nullptr;
        rac_result_t result = rac_rag_pipeline_create_standalone(&config, &newPipeline);

        if (result != RAC_SUCCESS || !newPipeline) {
            LOGE("createPipeline failed: %d", result);
            return false;
        }

        pipeline_ = newPipeline;
        LOGI("RAG pipeline created");
        return true;

    } catch (const std::exception& e) {
        LOGE("createPipeline exception: %s", e.what());
        return false;
    }
}

bool RAGBridge::destroyPipeline() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (pipeline_) {
        rac_rag_pipeline_destroy(pipeline_);
        pipeline_ = nullptr;
        return true;
    }
    return false;
}

bool RAGBridge::addDocument(const std::string& text, const std::string& metadataJson) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!pipeline_) throw std::runtime_error("RAG pipeline not created");

    const char* meta = metadataJson.empty() ? nullptr : metadataJson.c_str();
    rac_result_t result = rac_rag_add_document(pipeline_, text.c_str(), meta);
    if (result != RAC_SUCCESS) {
        LOGE("addDocument failed: %d", result);
        return false;
    }
    return true;
}

bool RAGBridge::addDocumentsBatch(const std::string& documentsJson) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!pipeline_) throw std::runtime_error("RAG pipeline not created");

    try {
        auto docs = nlohmann::json::parse(documentsJson);
        if (!docs.is_array()) return false;

        for (const auto& doc : docs) {
            std::string text = doc.value("text", "");
            std::string meta = doc.contains("metadataJson") ? doc["metadataJson"].dump() : "";
            const char* metaPtr = meta.empty() ? nullptr : meta.c_str();
            rac_rag_add_document(pipeline_, text.c_str(), metaPtr);
        }
        return true;
    } catch (...) {
        return false;
    }
}

std::string RAGBridge::query(const std::string& queryJson) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!pipeline_) throw std::runtime_error("RAG pipeline not created");

    try {
        auto json = nlohmann::json::parse(queryJson);

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
        rac_result_t status = rac_rag_query(pipeline_, &q, &result);

        if (status != RAC_SUCCESS) {
            LOGE("query failed: %d", status);
            return "{}";
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
            c["chunkId"] = result.retrieved_chunks[i].chunk_id ? result.retrieved_chunks[i].chunk_id : "";
            c["text"] = result.retrieved_chunks[i].text ? result.retrieved_chunks[i].text : "";
            c["similarityScore"] = result.retrieved_chunks[i].similarity_score;
            c["metadataJson"] = result.retrieved_chunks[i].metadata_json ? result.retrieved_chunks[i].metadata_json : "";
            chunks.push_back(c);
        }
        out["retrievedChunks"] = chunks;

        rac_rag_result_free(&result);
        return out.dump();

    } catch (const std::exception& e) {
        LOGE("query exception: %s", e.what());
        return "{}";
    }
}

bool RAGBridge::clearDocuments() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!pipeline_) throw std::runtime_error("RAG pipeline not created");
    return rac_rag_clear_documents(pipeline_) == RAC_SUCCESS;
}

double RAGBridge::getDocumentCount() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!pipeline_) return 0;
    return static_cast<double>(rac_rag_get_document_count(pipeline_));
}

std::string RAGBridge::getStatistics() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!pipeline_) return "{}";

    char* statsJson = nullptr;
    rac_result_t result = rac_rag_get_statistics(pipeline_, &statsJson);
    if (result != RAC_SUCCESS || !statsJson) return "{}";

    std::string out(statsJson);
    free(statsJson);
    return out;
}

} // namespace bridges
} // namespace runanywhere
