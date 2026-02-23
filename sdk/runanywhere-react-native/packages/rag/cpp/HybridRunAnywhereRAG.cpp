/**
 * HybridRunAnywhereRAG.cpp
 *
 * Implementation using stable C API (rac_rag_pipeline_*) for ABI stability.
 * Providers (ONNX, LlamaCPP) are encapsulated within the C API implementation.
 * Supports both ONNX-based and LlamaCPP-based text generation.
 */

#include "HybridRunAnywhereRAG.hpp"
#include <stdexcept>
#include <cstdlib>
#include <nlohmann/json.hpp>

namespace margelo::nitro::runanywhere::rag {

using namespace margelo::nitro;

HybridRunAnywhereRAG::HybridRunAnywhereRAG() : HybridObject(TAG), _pipeline(nullptr) {
  // Register RAG backend module
  rac_backend_rag_register();
}

HybridRunAnywhereRAG::~HybridRunAnywhereRAG() noexcept {
  try {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_pipeline != nullptr) {
      rac_rag_pipeline_destroy(_pipeline);
      _pipeline = nullptr;
    }
  } catch (...) {
    // Destructor must not throw
  }
}

void HybridRunAnywhereRAG::loadHybridMethods() {
  // Register hybrid methods with Nitrogen runtime
  registerHybrids(this, [](Prototype& prototype) {
    prototype.registerHybridMethod("createPipeline", &HybridRunAnywhereRAG::createPipeline);
    prototype.registerHybridMethod("destroyPipeline", &HybridRunAnywhereRAG::destroyPipeline);
    prototype.registerHybridMethod("addDocument", &HybridRunAnywhereRAG::addDocument);
    prototype.registerHybridMethod("addDocumentsBatch", &HybridRunAnywhereRAG::addDocumentsBatch);
    prototype.registerHybridMethod("clearDocuments", &HybridRunAnywhereRAG::clearDocuments);
    prototype.registerHybridMethod("getDocumentCount", &HybridRunAnywhereRAG::getDocumentCount);
    prototype.registerHybridMethod("query", &HybridRunAnywhereRAG::query);
    prototype.registerHybridMethod("getStatistics", &HybridRunAnywhereRAG::getStatistics);
  });
}

rac_rag_config_t HybridRunAnywhereRAG::convertConfig(const RAGConfig& config) const {
  rac_rag_config_t c_config = rac_rag_config_default();
  
  c_config.embedding_model_path = config.embeddingModelPath.c_str();
  c_config.llm_model_path = config.llmModelPath.c_str();
  c_config.embedding_dimension = config.embeddingDimension.value_or(384);
  c_config.top_k = config.topK.value_or(3);
  c_config.similarity_threshold = config.similarityThreshold.value_or(0.7f);
  c_config.max_context_tokens = config.maxContextTokens.value_or(2048);
  c_config.chunk_size = config.chunkSize.value_or(512);
  c_config.chunk_overlap = config.chunkOverlap.value_or(50);
  
  if (config.promptTemplate.has_value()) {
    c_config.prompt_template = config.promptTemplate->c_str();
  }
  
  if (config.embeddingConfigJson.has_value()) {
    c_config.embedding_config_json = config.embeddingConfigJson->c_str();
  }
  
  if (config.llmConfigJson.has_value()) {
    c_config.llm_config_json = config.llmConfigJson->c_str();
  }
  
  return c_config;
}

void HybridRunAnywhereRAG::ensurePipelineCreated() const {
  if (_pipeline == nullptr) {
    throw std::runtime_error("RAG pipeline not created. Call createPipeline() first.");
  }
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereRAG::createPipeline(const RAGConfig& config) {
  return Promise<bool>::async([this, config]() {
    std::lock_guard<std::mutex> lock(_mutex);
    
    // Destroy existing pipeline if any
    if (_pipeline != nullptr) {
      rac_rag_pipeline_destroy(_pipeline);
      _pipeline = nullptr;
    }
    
    // Convert config to C API format
    rac_rag_config_t c_config = convertConfig(config);
    
    // Create RAG pipeline using C API
    rac_rag_pipeline_t* new_pipeline = nullptr;
    rac_result_t result = rac_rag_pipeline_create(&c_config, &new_pipeline);

    if (result != RAC_SUCCESS || new_pipeline == nullptr) {
      if (new_pipeline != nullptr) {
        rac_rag_pipeline_destroy(new_pipeline);
      }
      throw std::runtime_error(
          std::string("Failed to create RAG pipeline: ") + rac_error_message(result)
      );
    }

    _pipeline = new_pipeline;
    
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereRAG::destroyPipeline() {
  return Promise<bool>::async([this]() {
    std::lock_guard<std::mutex> lock(_mutex);
    
    if (_pipeline != nullptr) {
      rac_rag_pipeline_destroy(_pipeline);
      _pipeline = nullptr;
      return true;
    }
    
    return false;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereRAG::addDocument(const std::string& documentText,
                                                    const std::optional<std::string>& metadataJson) {
  return Promise<bool>::async([this, documentText, metadataJson]() {
    std::lock_guard<std::mutex> lock(_mutex);
    ensurePipelineCreated();
    
    const char* metadata_ptr = metadataJson.has_value() ? metadataJson->c_str() : nullptr;
    
    rac_result_t result = rac_rag_add_document(_pipeline, documentText.c_str(), metadata_ptr);
    
    if (result != RAC_SUCCESS) {
      throw std::runtime_error(
          std::string("Failed to add document: ") + rac_error_message(result)
      );
    }
    
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereRAG::addDocumentsBatch(
    const std::vector<std::string>& documents,
    const std::optional<std::vector<std::string>>& metadataArray) {
  return Promise<bool>::async([this, documents, metadataArray]() {
    std::lock_guard<std::mutex> lock(_mutex);
    ensurePipelineCreated();
    
    // Convert to C-style arrays
    std::vector<const char*> doc_ptrs;
    std::vector<const char*> meta_ptrs;
    
    doc_ptrs.reserve(documents.size());
    for (const auto& doc : documents) {
      doc_ptrs.push_back(doc.c_str());
    }
    
    const char** metadata_array_ptr = nullptr;
    if (metadataArray.has_value()) {
      meta_ptrs.reserve(metadataArray->size());
      for (const auto& meta : *metadataArray) {
        meta_ptrs.push_back(meta.c_str());
      }
      metadata_array_ptr = meta_ptrs.data();
    }
    
    rac_result_t result = rac_rag_add_documents_batch(
        _pipeline,
        doc_ptrs.data(),
        metadata_array_ptr,
        documents.size()
    );
    
    if (result != RAC_SUCCESS) {
      throw std::runtime_error(
          std::string("Failed to add documents batch: ") + rac_error_message(result)
      );
    }
    
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereRAG::clearDocuments() {
  return Promise<bool>::async([this]() {
    std::lock_guard<std::mutex> lock(_mutex);
    ensurePipelineCreated();
    
    rac_result_t result = rac_rag_clear_documents(_pipeline);
    
    if (result != RAC_SUCCESS) {
      throw std::runtime_error(
          std::string("Failed to clear documents: ") + rac_error_message(result)
      );
    }
    
    return true;
  });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereRAG::getDocumentCount() {
  return Promise<double>::async([this]() {
    std::lock_guard<std::mutex> lock(_mutex);
    ensurePipelineCreated();
    
    size_t count = rac_rag_get_document_count(_pipeline);
    return static_cast<double>(count);
  });
}

std::shared_ptr<Promise<RAGResult>> HybridRunAnywhereRAG::query(const RAGQuery& query) {
  return Promise<RAGResult>::async([this, query]() {
    std::lock_guard<std::mutex> lock(_mutex);
    ensurePipelineCreated();
    
    // Build C API query
    rac_rag_query_t c_query;
    c_query.question = query.question.c_str();
    c_query.system_prompt = nullptr; // Could be added to RAGQuery spec if needed
    c_query.max_tokens = query.maxTokens.value_or(512);
    c_query.temperature = query.temperature.value_or(0.7f);
    c_query.top_p = query.topP.value_or(0.9f);
    c_query.top_k = query.topK.value_or(40);
    
    // Execute RAG query
    rac_rag_result_t c_result;
    rac_result_t result = rac_rag_query(_pipeline, &c_query, &c_result);
    
    if (result != RAC_SUCCESS) {
      throw std::runtime_error(
          std::string("Failed to execute RAG query: ") + rac_error_message(result)
      );
    }
    
    // Convert C result to Nitrogen result
    RAGResult js_result;
    js_result.answer = c_result.answer ? c_result.answer : "";
    js_result.contextUsed = c_result.context_used ? c_result.context_used : "";
    
    // Convert retrieved chunks
    std::vector<RAGChunk> chunks;
    for (size_t i = 0; i < c_result.num_chunks; ++i) {
      RAGChunk chunk;
      chunk.text = c_result.retrieved_chunks[i].text ? c_result.retrieved_chunks[i].text : "";
      chunk.similarityScore = c_result.retrieved_chunks[i].similarity_score;
      chunk.metadataJson = c_result.retrieved_chunks[i].metadata_json ? 
                          c_result.retrieved_chunks[i].metadata_json : "";
      chunks.push_back(chunk);
    }
    js_result.retrievedChunks = chunks;
    
    // Timing
    js_result.retrievalTimeMs = c_result.retrieval_time_ms;
    js_result.generationTimeMs = c_result.generation_time_ms;
    js_result.totalTimeMs = c_result.total_time_ms;
    
    // Free C result
    rac_rag_result_free(&c_result);
    
    return js_result;
  });
}

std::shared_ptr<Promise<RAGStatistics>> HybridRunAnywhereRAG::getStatistics() {
  return Promise<RAGStatistics>::async([this]() {
    std::lock_guard<std::mutex> lock(_mutex);
    ensurePipelineCreated();
    
    // Get statistics from pipeline
    char* stats_json_str = nullptr;
    rac_result_t result = rac_rag_get_statistics(_pipeline, &stats_json_str);
    
    if (result != RAC_SUCCESS) {
      throw std::runtime_error(
          std::string("Failed to get statistics: ") + rac_error_message(result)
      );
    }
    
    RAGStatistics stats;
    stats.documentCount = static_cast<double>(rac_rag_get_document_count(_pipeline));
    
    // Parse JSON stats
    if (stats_json_str != nullptr) {
      try {
        nlohmann::json stats_json = nlohmann::json::parse(stats_json_str);
        stats.chunkCount = stats_json.value("chunk_count", 0.0);
        stats.vectorStoreSize = stats_json.value("vector_store_size_mb", 0.0);
        stats.statsJson = stats_json_str;
      } catch (const std::exception& e) {
        stats.chunkCount = 0.0;
        stats.vectorStoreSize = 0.0;
        stats.statsJson = stats_json_str;
      }
      free(stats_json_str);
    } else {
      stats.chunkCount = 0.0;
      stats.vectorStoreSize = 0.0;
      stats.statsJson = "{}";
    }
    
    return stats;
  });
}

} // namespace margelo::nitro::runanywhere::rag
