/**
 * @file rag_backend.cpp
 * @brief RAG Backend Implementation
 */

#include "rag_backend.h"

#include "rac/core/rac_logger.h"

#define LOG_TAG "RAG.Backend"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)

namespace runanywhere {
namespace rag {

RAGBackend::RAGBackend(
    const RAGBackendConfig& config,
    std::unique_ptr<IEmbeddingProvider> embedding_provider,
    std::unique_ptr<ITextGenerator> text_generator
) : config_(config),
    embedding_provider_(std::move(embedding_provider)),
    text_generator_(std::move(text_generator)) {
    // Create vector store
    VectorStoreConfig store_config;
    store_config.dimension = config.embedding_dimension;
    vector_store_ = std::make_unique<VectorStoreUSearch>(store_config);

    // Create chunker
    ChunkerConfig chunker_config;
    chunker_config.chunk_size = config.chunk_size;
    chunker_config.chunk_overlap = config.chunk_overlap;
    chunker_ = std::make_unique<DocumentChunker>(chunker_config);

    initialized_ = true;
    LOGI("RAG backend initialized: dim=%zu, chunk_size=%zu",
         config.embedding_dimension, config.chunk_size);
}

RAGBackend::~RAGBackend() {
    clear();
}

void RAGBackend::set_embedding_provider(std::unique_ptr<IEmbeddingProvider> provider) {
    std::lock_guard<std::mutex> lock(mutex_);
    embedding_provider_ = std::move(provider);
    
    // Update embedding dimension if provider is ready
    if (embedding_provider_ && embedding_provider_->is_ready()) {
        config_.embedding_dimension = embedding_provider_->dimension();
        LOGI("Set embedding provider: %s, dim=%zu", 
             embedding_provider_->name(), config_.embedding_dimension);
    }
}

void RAGBackend::set_text_generator(std::unique_ptr<ITextGenerator> generator) {
    std::lock_guard<std::mutex> lock(mutex_);
    text_generator_ = std::move(generator);
    
    if (text_generator_ && text_generator_->is_ready()) {
        LOGI("Set text generator: %s", text_generator_->name());
    }
}

bool RAGBackend::add_document(
    const std::string& text,
    const nlohmann::json& metadata
) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!initialized_) {
        LOGE("Backend not initialized");
        return false;
    }

    if (!embedding_provider_ || !embedding_provider_->is_ready()) {
        LOGE("Embedding provider not available");
        return false;
    }

    // Split into chunks
    auto chunks = chunker_->chunk_document(text);
    LOGI("Split document into %zu chunks", chunks.size());

    // Embed and add each chunk
    for (const auto& chunk_obj : chunks) {
        try {
            // Generate embedding
            auto embedding = embedding_provider_->embed(chunk_obj.text);
            
            if (embedding.size() != config_.embedding_dimension) {
                LOGE("Embedding dimension mismatch: got %zu, expected %zu",
                     embedding.size(), config_.embedding_dimension);
                continue;
            }

            // Create document chunk
            DocumentChunk chunk;
            chunk.id = "chunk_" + std::to_string(next_chunk_id_++);
            chunk.text = chunk_obj.text;
            chunk.embedding = std::move(embedding);
            chunk.metadata = metadata;
            chunk.metadata["source_text"] = text.substr(0, 100);  // First 100 chars

            // Add to vector store
            if (!vector_store_->add_chunk(chunk)) {
                LOGE("Failed to add chunk to vector store");
                return false;
            }
            
            LOGI("Added chunk %s to vector store (text: %.50s...)", 
                 chunk.id.c_str(), chunk.text.c_str());
            
        } catch (const std::exception& e) {
            LOGE("Failed to embed chunk: %s", e.what());
            return false;
        }
    }

    LOGI("Successfully added %zu chunks from document", chunks.size());
    return true;
}

std::vector<SearchResult> RAGBackend::search(
    const std::string& query_text,
    size_t top_k
) const {
    if (!initialized_) {
        return {};
    }

    if (!embedding_provider_ || !embedding_provider_->is_ready()) {
        LOGE("Embedding provider not available for search");
        return {};
    }

    try {
        // Generate embedding for query
        auto query_embedding = embedding_provider_->embed(query_text);
        
        if (query_embedding.size() != config_.embedding_dimension) {
            LOGE("Query embedding dimension mismatch");
            return {};
        }

        return vector_store_->search(
            query_embedding,
            top_k,
            config_.similarity_threshold
        );
        
    } catch (const std::exception& e) {
        LOGE("Search failed: %s", e.what());
        return {};
    }
}

std::string RAGBackend::build_context(const std::vector<SearchResult>& results) const {
    std::string context;
    
    for (size_t i = 0; i < results.size(); ++i) {
        if (i > 0) {
            context += "\n\n";
        }
        context += results[i].text;
    }
    
    return context;
}

std::string RAGBackend::format_prompt(
    const std::string& query,
    const std::string& context
) const {
    std::string prompt = config_.prompt_template;
    
    // Replace {context} placeholder
    size_t pos = prompt.find("{context}");
    if (pos != std::string::npos) {
        prompt.replace(pos, 9, context);
    }
    
    // Replace {query} placeholder
    pos = prompt.find("{query}");
    if (pos != std::string::npos) {
        prompt.replace(pos, 7, query);
    }
    
    return prompt;
}

GenerationResult RAGBackend::query(
    const std::string& query,
    const GenerationOptions& options
) {
    // Validate providers are available
    if (!embedding_provider_ || !embedding_provider_->is_ready()) {
        LOGE("Embedding provider not available for query");
        GenerationResult error_result;
        error_result.text = "Error: Embedding provider not available";
        error_result.success = false;
        return error_result;
    }
    
    if (!text_generator_ || !text_generator_->is_ready()) {
        LOGE("Text generator not available for query");
        GenerationResult error_result;
        error_result.text = "Error: Text generator not available";
        error_result.success = false;
        return error_result;
    }
    
    try {
        // Step 1: Search for relevant context
        auto search_results = search(query, config_.top_k);
        
        if (search_results.empty()) {
            LOGE("No relevant documents found for query");
            GenerationResult result;
            result.text = "I don't have enough information to answer that question.";
            result.success = true;
            result.metadata["reason"] = "no_context";
            return result;
        }
        
        // Step 2: Build context from results
        std::string context = build_context(search_results);
        LOGI("Built context from %zu chunks, %zu chars", 
             search_results.size(), context.size());
        
        // Step 3: Format prompt
        std::string prompt = format_prompt(query, context);
        
        // Step 4: Generate answer
        auto result = text_generator_->generate(prompt, options);
        
        // Add search metadata
        if (result.success) {
            result.metadata["num_chunks"] = search_results.size();
            result.metadata["context_length"] = context.size();
            
            // Add chunk sources
            nlohmann::json sources = nlohmann::json::array();
            for (const auto& res : search_results) {
                nlohmann::json source;
                source["id"] = res.id;
                source["score"] = res.score;
                if (res.metadata.contains("source_text")) {
                    source["source"] = res.metadata["source_text"];
                }
                sources.push_back(source);
            }
            result.metadata["sources"] = sources;
        }
        
        return result;
        
    } catch (const std::exception& e) {
        LOGE("Query failed: %s", e.what());
        GenerationResult error_result;
        error_result.text = std::string("Error: ") + e.what();
        error_result.success = false;
        return error_result;
    }
}

void RAGBackend::clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (vector_store_) {
        vector_store_->clear();
    }
    next_chunk_id_ = 0;
}

nlohmann::json RAGBackend::get_statistics() const {
    nlohmann::json stats;
    
    if (vector_store_) {
        stats = vector_store_->get_statistics();
    }
    
    stats["config"] = {
        {"embedding_dimension", config_.embedding_dimension},
        {"top_k", config_.top_k},
        {"similarity_threshold", config_.similarity_threshold},
        {"chunk_size", config_.chunk_size},
        {"chunk_overlap", config_.chunk_overlap}
    };
    
    return stats;
}

size_t RAGBackend::document_count() const {
    return vector_store_ ? vector_store_->size() : 0;
}

} // namespace rag
} // namespace runanywhere
