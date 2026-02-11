/**
 * HybridRunAnywhereRAG.hpp
 *
 * C++ implementation of the RunAnywhereRAG Nitrogen spec.
 * Uses C++ RAGBackend API directly (no C API layer).
 */

#pragma once

#include "HybridRunAnywhereRAGSpec.hpp"
#include <NitroModules/Promise.hpp>
#include <memory>

// Import Nitrogen-generated types
#include "RAGConfig.hpp"
#include "RAGResult.hpp"
#include "RAGQuery.hpp"
#include "RAGStatistics.hpp"
#include "RAGChunk.hpp"

// RAG C API - stable ABI, proper encapsulation
#include "rac/features/rag/rac_rag_pipeline.h"
#include "rac/backends/rac_rag.h"
#include "rac/core/rac_error.h"

namespace margelo::nitro::runanywhere::rag {

using namespace margelo::nitro;

/**
 * C++ implementation of RunAnywhereRAG HybridObject
 */
class HybridRunAnywhereRAG : public HybridRunAnywhereRAGSpec {
public:
  explicit HybridRunAnywhereRAG();
  ~HybridRunAnywhereRAG() noexcept override;

  // Lifecycle
  std::shared_ptr<Promise<bool>> createPipeline(const RAGConfig& config) override;
  std::shared_ptr<Promise<bool>> destroyPipeline() override;

  // Document management
  std::shared_ptr<Promise<bool>> addDocument(const std::string& documentText,
                                const std::optional<std::string>& metadataJson) override;
  std::shared_ptr<Promise<bool>> addDocumentsBatch(const std::vector<std::string>& documents,
                                      const std::optional<std::vector<std::string>>& metadataArray) override;
  std::shared_ptr<Promise<bool>> clearDocuments() override;
  std::shared_ptr<Promise<double>> getDocumentCount() override;

  // Query
  std::shared_ptr<Promise<RAGResult>> query(const RAGQuery& query) override;

  // Statistics
  std::shared_ptr<Promise<RAGStatistics>> getStatistics() override;

  // HybridObject
  void loadHybridMethods() override;

private:
  // Disable copy and move (HybridObject is not copyable)
  HybridRunAnywhereRAG(const HybridRunAnywhereRAG&) = delete;
  HybridRunAnywhereRAG& operator=(const HybridRunAnywhereRAG&) = delete;
  HybridRunAnywhereRAG(HybridRunAnywhereRAG&&) = delete;
  HybridRunAnywhereRAG& operator=(HybridRunAnywhereRAG&&) = delete;

  /**
   * C API RAG pipeline handle (opaque pointer)
   */
  rac_rag_pipeline_t* _pipeline;

  /**
   * Thread-safe access
   */
  mutable std::mutex _mutex;

  /**
   * Helper to check if pipeline is created
   */
  void ensurePipelineCreated() const;

  /**
   * Convert config to C API config
   */
  rac_rag_config_t convertConfig(const RAGConfig& config) const;
};

} // namespace margelo::nitro::runanywhere::rag
