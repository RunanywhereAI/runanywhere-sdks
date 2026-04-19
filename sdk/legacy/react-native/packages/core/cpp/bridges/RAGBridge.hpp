/**
 * @file RAGBridge.hpp
 * @brief RAG pipeline bridge for React Native - THIN WRAPPER
 *
 * Wraps rac_rag_pipeline_* C APIs for JSI access.
 * RAG is a pipeline (like Voice Agent), not a backend.
 *
 * NOTE: Stub implementation — rac_rag_* functions not yet in librac_commons.so.
 * Returns safe defaults until the library is updated.
 */

#pragma once

#include <string>
#include <mutex>

namespace runanywhere {
namespace bridges {

class RAGBridge {
public:
    static RAGBridge& shared() {
        static RAGBridge instance;
        return instance;
    }

    bool createPipeline(const std::string& /*configJson*/) { return false; }
    bool destroyPipeline() { return false; }
    bool addDocument(const std::string& /*text*/, const std::string& /*metadataJson*/) { return false; }
    bool addDocumentsBatch(const std::string& /*documentsJson*/) { return false; }
    std::string query(const std::string& /*queryJson*/) { return "{}"; }
    bool clearDocuments() { return false; }
    double getDocumentCount() { return 0.0; }
    std::string getStatistics() { return "{}"; }

private:
    RAGBridge() = default;
    std::mutex mutex_;
};

} // namespace bridges
} // namespace runanywhere
