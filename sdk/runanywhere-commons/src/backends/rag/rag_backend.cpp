/**
 * @file rag_backend.cpp
 * @brief RAG Backend Implementation
 */

#include "rag_backend.h"

#include <algorithm>
#include <cmath>

#include "rac/core/rac_logger.h"

#define LOG_TAG "RAG.Backend"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)

// Contrastive ICL system prompt injected at the start of every query
static const std::string kICLSystemPrompt =
    "You are a question-answering assistant. Given context passages and a question, "
    "determine if the passages contain enough information to answer the question.\n\n"
    "Example 1 (Sufficient context):\n"
    "Context: \"The Eiffel Tower was completed in 1889 for the World's Fair in Paris.\"\n"
    "Question: \"When was the Eiffel Tower built?\"\n"
    "Assessment: Yes - the context directly states the completion year.\n\n"
    "Example 2 (Insufficient context):\n"
    "Context: \"Paris is the capital of France and known for its cuisine.\"\n"
    "Question: \"When was the Eiffel Tower built?\"\n"
    "Assessment: No - the context discusses Paris but not the Eiffel Tower's construction date.\n";

namespace runanywhere {
namespace rag {

RAGBackend::RAGBackend(
    const RAGBackendConfig& config,
    std::unique_ptr<IEmbeddingProvider> embedding_provider,
    std::unique_ptr<ITextGenerator> text_generator
) : config_(config),
    embedding_provider_(std::shared_ptr<IEmbeddingProvider>(std::move(embedding_provider))),
    text_generator_(std::shared_ptr<ITextGenerator>(std::move(text_generator))) {
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
    embedding_provider_ = std::shared_ptr<IEmbeddingProvider>(std::move(provider));
    
    // Update embedding dimension if provider is ready
    if (embedding_provider_ && embedding_provider_->is_ready()) {
        config_.embedding_dimension = embedding_provider_->dimension();
        LOGI("Set embedding provider: %s, dim=%zu", 
             embedding_provider_->name(), config_.embedding_dimension);
    }
}

void RAGBackend::set_text_generator(std::unique_ptr<ITextGenerator> generator) {
    std::lock_guard<std::mutex> lock(mutex_);
    text_generator_ = std::shared_ptr<ITextGenerator>(std::move(generator));
    
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
    std::shared_ptr<IEmbeddingProvider> embedding_provider;
    size_t embedding_dimension = 0;
    float similarity_threshold = 0.0f;
    bool initialized = false;
    const DocumentChunker* chunker = nullptr;

    {
        std::lock_guard<std::mutex> lock(mutex_);
        embedding_provider = embedding_provider_;
        embedding_dimension = config_.embedding_dimension;
        similarity_threshold = config_.similarity_threshold;
        initialized = initialized_;
        chunker = chunker_.get();
    }

    return search_with_provider(
        query_text,
        top_k,
        embedding_provider,
        embedding_dimension,
        similarity_threshold,
        initialized,
        chunker
    );
}

std::vector<SearchResult> RAGBackend::search_with_provider(
    const std::string& query_text,
    size_t top_k,
    const std::shared_ptr<IEmbeddingProvider>& embedding_provider,
    size_t embedding_dimension,
    float similarity_threshold,
    bool initialized,
    const DocumentChunker* chunker
) const {
    if (!initialized) {
        return {};
    }

    if (!embedding_provider || !embedding_provider->is_ready()) {
        LOGE("Embedding provider not available for search");
        return {};
    }

    if (!chunker) {
        LOGE("Chunker not available for sentence splitting");
        return {};
    }

    auto cosine_similarity = [](const std::vector<float>& a, const std::vector<float>& b) -> float {
        if (a.size() != b.size() || a.empty()) return 0.0f;
        float dot = 0.0f, norm_a = 0.0f, norm_b = 0.0f;
        for (size_t i = 0; i < a.size(); ++i) {
            dot += a[i] * b[i];
            norm_a += a[i] * a[i];
            norm_b += b[i] * b[i];
        }
        float denom = std::sqrt(norm_a) * std::sqrt(norm_b);
        return denom > 0.0f ? dot / denom : 0.0f;
    };

    try {
        static constexpr size_t kParentChunkCount = 5;
        auto query_embedding = embedding_provider->embed(query_text);

        if (query_embedding.size() != embedding_dimension) {
            LOGE("Query embedding dimension mismatch");
            return {};
        }

        auto parent_chunks = vector_store_->search(query_embedding, kParentChunkCount, similarity_threshold);
        LOGI("Retrieved %zu parent chunks for focused sentence search", parent_chunks.size());

        if (parent_chunks.empty()) {
            return {};
        }

        struct ScoredSentence {
            std::string text;
            float similarity;
            std::string parent_chunk_id;
            nlohmann::json parent_metadata;
        };

        std::vector<ScoredSentence> scored_sentences;

        for (const auto& parent : parent_chunks) {
            auto sentences = chunker->split_into_sentences(parent.text);
            LOGI("Parent chunk '%s' split into %zu sentences", parent.chunk_id.c_str(), sentences.size());

            for (const auto& sentence : sentences) {
                if (sentence.size() < 3) {
                    continue;
                }

                try {
                    auto sentence_embedding = embedding_provider->embed(sentence);
                    float sim = cosine_similarity(query_embedding, sentence_embedding);

                    scored_sentences.push_back({
                        sentence,
                        sim,
                        parent.chunk_id,
                        parent.metadata
                    });
                } catch (const std::exception& e) {
                    LOGE("Failed to embed sentence, skipping: %s", e.what());
                }
            }
        }

        LOGI("Scored %zu sentences total across all parent chunks", scored_sentences.size());

        if (scored_sentences.empty()) {
            return {};
        }

        static constexpr size_t kTopSentences = 10;
        size_t result_count = std::min(kTopSentences, scored_sentences.size());

        std::partial_sort(
            scored_sentences.begin(),
            scored_sentences.begin() + static_cast<std::ptrdiff_t>(result_count),
            scored_sentences.end(),
            [](const ScoredSentence& a, const ScoredSentence& b) {
                return a.similarity > b.similarity;
            }
        );

        std::vector<SearchResult> results;
        results.reserve(result_count);

        for (size_t i = 0; i < result_count; ++i) {
            SearchResult r;
            r.id = scored_sentences[i].parent_chunk_id + "_s" + std::to_string(i);
            r.chunk_id = scored_sentences[i].parent_chunk_id;
            r.text = scored_sentences[i].text;
            r.similarity = scored_sentences[i].similarity;
            r.score = scored_sentences[i].similarity;
            r.metadata = scored_sentences[i].parent_metadata;
            results.push_back(std::move(r));
        }

        return results;

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
    std::shared_ptr<IEmbeddingProvider> embedding_provider;
    std::shared_ptr<ITextGenerator> text_generator;
    size_t embedding_dimension = 0;
    float similarity_threshold = 0.0f;
    size_t top_k = 0;
    bool initialized = false;

    {
        std::lock_guard<std::mutex> lock(mutex_);
        embedding_provider = embedding_provider_;
        text_generator = text_generator_;
        embedding_dimension = config_.embedding_dimension;
        similarity_threshold = config_.similarity_threshold;
        top_k = config_.top_k;
        initialized = initialized_;
    }

    // Validate providers are available
    if (!embedding_provider || !embedding_provider->is_ready()) {
        LOGE("Embedding provider not available for query");
        GenerationResult error_result;
        error_result.text = "Error: Embedding provider not available";
        error_result.success = false;
        return error_result;
    }

    if (!text_generator || !text_generator->is_ready()) {
        LOGE("Text generator not available for query");
        GenerationResult error_result;
        error_result.text = "Error: Text generator not available";
        error_result.success = false;
        return error_result;
    }

    try {
        text_generator->clear_context();

        bool icl_injected = text_generator->inject_system_prompt(kICLSystemPrompt);
        if (!icl_injected) {
            LOGI("inject_system_prompt returned false — generator may not support KV cache injection, continuing");
        }

        auto search_results = search_with_provider(
            query,
            top_k,
            embedding_provider,
            embedding_dimension,
            similarity_threshold,
            initialized,
            chunker_.get()
        );

        if (search_results.empty()) {
            LOGI("No relevant documents found for query");
            GenerationResult result;
            result.text = "I don't have enough information to answer that question.";
            result.success = true;
            result.metadata["reason"] = "no_context";
            return result;
        }

        std::string accumulated_context;
        float confidence = 0.0f;
        size_t sentences_used = 0;

        for (const auto& sentence_result : search_results) {
            const std::string& sentence_text = sentence_result.text;
            std::string append_text = (sentences_used == 0) ? sentence_text : ("\n" + sentence_text);
            text_generator->append_context(append_text);

            if (sentences_used == 0) {
                accumulated_context = sentence_text;
            } else {
                accumulated_context += "\n" + sentence_text;
            }

            sentences_used++;

            confidence = text_generator->probe_confidence("", query);

            LOGI("Adaptive loop: sentence %zu/%zu, confidence=%.4f, threshold=%.4f",
                 sentences_used, search_results.size(), confidence, kConfidenceThreshold);

            if (confidence > kConfidenceThreshold) {
                LOGI("Confidence threshold reached at sentence %zu (confidence=%.4f)",
                     sentences_used, confidence);
                break;
            }
        }

        bool threshold_reached = confidence > kConfidenceThreshold;
        LOGI("Adaptive loop complete: sentences_used=%zu, final_confidence=%.4f, threshold_reached=%s",
             sentences_used, confidence, threshold_reached ? "true" : "false");

        if (!kKeepPartialContext && !threshold_reached) {
            text_generator->clear_context();
            text_generator->inject_system_prompt(kICLSystemPrompt);
            accumulated_context.clear();
            sentences_used = 0;
            LOGI("Strict filtering: cleared all sentences (confidence never reached threshold)");
        } else if (!kKeepPartialContext && threshold_reached && sentences_used < search_results.size()) {

            LOGI("Strict filtering: keeping %zu sentences that reached confidence threshold", sentences_used);
        }
 
        std::string query_suffix = "\n\nQuestion: " + query + "\n\nAnswer:";
        auto result = text_generator->generate_from_context(query_suffix, options);


        result.metadata["sentences_used"] = sentences_used;
        result.metadata["final_confidence"] = confidence;
        result.metadata["threshold_reached"] = threshold_reached;
        result.metadata["total_sentences"] = search_results.size();
        result.metadata["keep_partial_context"] = kKeepPartialContext;

        nlohmann::json sources = nlohmann::json::array();
        for (size_t i = 0; i < sentences_used && i < search_results.size(); ++i) {
            const auto& res = search_results[i];
            nlohmann::json source;
            source["id"] = res.id;
            source["score"] = res.score;
            if (res.metadata.contains("source_text")) {
                source["source"] = res.metadata["source_text"];
            }
            sources.push_back(source);
        }
        result.metadata["sources"] = sources;

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
    std::lock_guard<std::mutex> lock(mutex_);
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
