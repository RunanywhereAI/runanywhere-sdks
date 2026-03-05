/**
 * @file RAGBridge.hpp
 * @brief RAG pipeline bridge for React Native - THIN WRAPPER
 *
 * Wraps rac_rag_pipeline_* C APIs for JSI access.
 * RAG is a pipeline (like Voice Agent), not a backend.
 */

#pragma once

#include <string>
#include <mutex>

// Forward declare opaque pipeline handle
struct rac_rag_pipeline;
typedef struct rac_rag_pipeline rac_rag_pipeline_t;

namespace runanywhere {
namespace bridges {

class RAGBridge {
public:
    static RAGBridge& shared();

    bool createPipeline(const std::string& configJson);
    bool destroyPipeline();
    bool addDocument(const std::string& text, const std::string& metadataJson);
    bool addDocumentsBatch(const std::string& documentsJson);
    std::string query(const std::string& queryJson);
    bool clearDocuments();
    double getDocumentCount();
    std::string getStatistics();

private:
    RAGBridge() = default;
    rac_rag_pipeline_t* pipeline_ = nullptr;
    std::mutex mutex_;
};

} // namespace bridges
} // namespace runanywhere
