/**
 * @file rac_rag_pipeline.cpp
 * @brief RAG Pipeline C API Implementation
 */

#include "rac/features/rag/rac_rag_pipeline.h"
#include "rag_backend.h"
#include "inference_provider.h"

#ifdef RAG_HAS_ONNX_PROVIDER
#include "onnx_embedding_provider.h"
#endif

#ifdef RAG_HAS_LLAMACPP_PROVIDER  
#include "llamacpp_generator.h"
#endif

#include <memory>
#include <cstring>
#include <chrono>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/core/rac_error.h"

static const char* LOG_TAG = "RAG.Pipeline";

using namespace runanywhere::rag;

// =============================================================================
// PIPELINE HANDLE
// =============================================================================

struct rac_rag_pipeline {
    std::unique_ptr<RAGBackend> backend;
    rac_rag_config_t config;
};

// =============================================================================
// PUBLIC API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_rag_pipeline_create(
    const rac_rag_config_t* config,
    rac_rag_pipeline_t** out_pipeline
) {
    if (config == nullptr || out_pipeline == nullptr) {
        RAC_LOG_ERROR(LOG_TAG,"Null pointer in rac_rag_pipeline_create");
        return RAC_ERROR_NULL_POINTER;
    }

    if (config->embedding_model_path == nullptr || config->llm_model_path == nullptr) {
        RAC_LOG_ERROR(LOG_TAG,"Model paths required");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    *out_pipeline = nullptr;  // Initialize output to nullptr

    try {
        auto pipeline = std::make_unique<rac_rag_pipeline>();
        pipeline->config = *config;

        // Create backend
        RAGBackendConfig backend_config;
        backend_config.embedding_dimension = config->embedding_dimension > 0 
            ? config->embedding_dimension : 384;
        backend_config.top_k = config->top_k > 0 ? config->top_k : 3;
        backend_config.similarity_threshold = config->similarity_threshold;
        backend_config.max_context_tokens = config->max_context_tokens > 0 
            ? config->max_context_tokens : 2048;
        backend_config.chunk_size = config->chunk_size > 0 ? config->chunk_size : 512;
        backend_config.chunk_overlap = config->chunk_overlap;
        
        if (config->prompt_template != nullptr) {
            backend_config.prompt_template = config->prompt_template;
        }

        // Create embedding provider
        std::unique_ptr<IEmbeddingProvider> embedding_provider;
#ifdef RAG_HAS_ONNX_PROVIDER
        std::string embedding_config = config->embedding_config_json != nullptr 
            ? config->embedding_config_json : "";
        embedding_provider = create_onnx_embedding_provider(
            config->embedding_model_path,
            embedding_config
        );
        
        if (!embedding_provider || !embedding_provider->is_ready()) {
            RAC_LOG_ERROR(LOG_TAG,"Failed to initialize embedding provider");
            return RAC_ERROR_INITIALIZATION_FAILED;
        }
#else
        RAC_LOG_ERROR(LOG_TAG,"No embedding provider available - ONNX backend not built");
        return RAC_ERROR_NOT_SUPPORTED;
#endif
        
        // Create text generator using LlamaCPP (supports .gguf format)
        std::string llm_config = config->llm_config_json != nullptr 
            ? config->llm_config_json : "";
        std::unique_ptr<ITextGenerator> text_generator;
        
#ifdef RAG_HAS_LLAMACPP_PROVIDER
        try {
            text_generator = create_llamacpp_generator(
                config->llm_model_path,
                llm_config
            );
            
            if (!text_generator || !text_generator->is_ready()) {
                RAC_LOG_ERROR(LOG_TAG,"Failed to initialize LlamaCPP text generator");
                return RAC_ERROR_INITIALIZATION_FAILED;
            }
            
            RAC_LOG_INFO(LOG_TAG,"Successfully created LlamaCPP text generator: %s", text_generator->name());
        } catch (const std::exception& e) {
            RAC_LOG_ERROR(LOG_TAG,"LlamaCPP generator creation failed: %s", e.what());
            return RAC_ERROR_INITIALIZATION_FAILED;
        } catch (...) {
            RAC_LOG_ERROR(LOG_TAG,"LlamaCPP generator creation failed with unknown error");
            return RAC_ERROR_INITIALIZATION_FAILED;
        }
#else
        RAC_LOG_ERROR(LOG_TAG,"LlamaCPP backend not available");
        return RAC_ERROR_NOT_SUPPORTED;
#endif
            
            RAC_LOG_INFO(LOG_TAG,"Providers initialized: %s, %s", 
                 embedding_provider->name(), text_generator->name());

        // Create RAG backend with providers
        pipeline->backend = std::make_unique<RAGBackend>(
            backend_config,
            std::move(embedding_provider),
            std::move(text_generator)
        );

        if (!pipeline->backend->is_initialized()) {
            RAC_LOG_ERROR(LOG_TAG,"Failed to initialize RAG backend");
            return RAC_ERROR_INITIALIZATION_FAILED;
        }

        *out_pipeline = pipeline.release();
        RAC_LOG_INFO(LOG_TAG,"RAG pipeline created");
        return RAC_SUCCESS;

    } catch (const std::bad_alloc& e) {
        RAC_LOG_ERROR(LOG_TAG,"Memory allocation failed: %s", e.what());
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_TAG,"Exception creating pipeline: %s", e.what());
        return RAC_ERROR_INITIALIZATION_FAILED;
    } catch (...) {
        RAC_LOG_ERROR(LOG_TAG,"Unknown exception creating pipeline");
        return RAC_ERROR_INITIALIZATION_FAILED;
    }
}

rac_result_t rac_rag_add_document(
    rac_rag_pipeline_t* pipeline,
    const char* document_text,
    const char* metadata_json
) {
    if (pipeline == nullptr || document_text == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    try {
        nlohmann::json metadata;
        if (metadata_json != nullptr) {
            metadata = nlohmann::json::parse(metadata_json);
        }

        bool success = pipeline->backend->add_document(document_text, metadata);
        return success ? RAC_SUCCESS : RAC_ERROR_PROCESSING_FAILED;

    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_TAG,"Exception adding document: %s", e.what());
        return RAC_ERROR_PROCESSING_FAILED;
    }
}

rac_result_t rac_rag_add_documents_batch(
    rac_rag_pipeline_t* pipeline,
    const char** documents,
    const char** metadata_array,
    size_t count
) {
    if (pipeline == nullptr || documents == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    for (size_t i = 0; i < count; ++i) {
        const char* metadata = (metadata_array != nullptr) ? metadata_array[i] : nullptr;
        rac_result_t result = rac_rag_add_document(pipeline, documents[i], metadata);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR(LOG_TAG,"Failed to add document %zu", i);
            // Continue with other documents
        }
    }

    return RAC_SUCCESS;
}

rac_result_t rac_rag_query(
    rac_rag_pipeline_t* pipeline,
    const rac_rag_query_t* query,
    rac_rag_result_t* out_result
) {
    if (pipeline == nullptr || query == nullptr || out_result == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    if (query->question == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    try {
        // Prepare generation options
        GenerationOptions gen_options;
        gen_options.max_tokens = query->max_tokens > 0 ? query->max_tokens : 512;
        gen_options.temperature = query->temperature > 0.0f ? query->temperature : 0.7f;
        gen_options.top_p = query->top_p > 0.0f ? query->top_p : 0.9f;
        gen_options.top_k = query->top_k > 0 ? query->top_k : 40;
        
        // Measure total time
        auto start_time = std::chrono::high_resolution_clock::now();
        
        // Execute RAG query
        auto result = pipeline->backend->query(query->question, gen_options);
        
        auto end_time = std::chrono::high_resolution_clock::now();
        double total_ms = std::chrono::duration<double, std::milli>(end_time - start_time).count();
        
        // Check if generation was successful
        if (!result.success) {
            RAC_LOG_ERROR(LOG_TAG,"RAG query failed: %s", result.text.c_str());
            return RAC_ERROR_PROCESSING_FAILED;
        }
        
        // Allocate answer string
        out_result->answer = rac_strdup(result.text.c_str());
        if (out_result->answer == nullptr) {
            RAC_LOG_ERROR(LOG_TAG,"Failed to allocate memory for answer");
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        
        // Extract retrieved chunks from metadata
        out_result->num_chunks = 0;
        out_result->retrieved_chunks = nullptr;
        
        if (result.metadata.contains("sources") && result.metadata["sources"].is_array()) {
            auto sources = result.metadata["sources"];
            size_t num_chunks = sources.size();
            
            if (num_chunks > 0) {
                out_result->retrieved_chunks = static_cast<rac_search_result_t*>(
                    rac_alloc(sizeof(rac_search_result_t) * num_chunks)
                );
                
                if (out_result->retrieved_chunks != nullptr) {
                    out_result->num_chunks = num_chunks;
                    
                    for (size_t i = 0; i < num_chunks; ++i) {
                        auto& source = sources[i];
                        auto& chunk = out_result->retrieved_chunks[i];
                        
                        chunk.chunk_id = rac_strdup(source["id"].get<std::string>().c_str());
                        chunk.similarity_score = source["score"].get<float>();
                        chunk.text = nullptr;  // Not included in metadata
                        chunk.metadata_json = nullptr;
                        
                        if (source.contains("source")) {
                            chunk.metadata_json = rac_strdup(
                                source["source"].get<std::string>().c_str()
                            );
                        }
                    }
                }
            }
        }
        
        // Build context placeholder (actual context not returned by backend)
        out_result->context_used = nullptr;
        if (result.metadata.contains("context_length")) {
            std::string ctx_info = "Context length: " + 
                std::to_string(result.metadata["context_length"].get<size_t>());
            out_result->context_used = rac_strdup(ctx_info.c_str());
        }
        
        // Set timing information
        out_result->generation_time_ms = result.inference_time_ms;
        out_result->retrieval_time_ms = total_ms - result.inference_time_ms;
        out_result->total_time_ms = total_ms;
        
        RAC_LOG_INFO(LOG_TAG,"RAG query completed: %zu chunks, %.2fms total", 
             out_result->num_chunks, total_ms);
        
        return RAC_SUCCESS;

    } catch (const std::bad_alloc& e) {
        RAC_LOG_ERROR(LOG_TAG,"Memory allocation failed: %s", e.what());
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_TAG,"Exception in RAG query: %s", e.what());
        return RAC_ERROR_PROCESSING_FAILED;
    }
}

rac_result_t rac_rag_clear_documents(rac_rag_pipeline_t* pipeline) {
    if (pipeline == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    try {
        pipeline->backend->clear();
        return RAC_SUCCESS;
    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_TAG,"Exception clearing documents: %s", e.what());
        return RAC_ERROR_PROCESSING_FAILED;
    }
}

size_t rac_rag_get_document_count(rac_rag_pipeline_t* pipeline) {
    if (pipeline == nullptr) {
        return 0;
    }

    return pipeline->backend->document_count();
}

rac_result_t rac_rag_get_statistics(
    rac_rag_pipeline_t* pipeline,
    char** out_stats_json
) {
    if (pipeline == nullptr || out_stats_json == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    try {
        auto stats = pipeline->backend->get_statistics();
        std::string json_str = stats.dump();
        
        char* json_copy = rac_strdup(json_str.c_str());
        if (json_copy == nullptr) {
            RAC_LOG_ERROR(LOG_TAG,"Failed to allocate memory for statistics JSON");
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        *out_stats_json = json_copy;
        return RAC_SUCCESS;

    } catch (const std::exception& e) {
        RAC_LOG_ERROR(LOG_TAG,"Exception getting statistics: %s", e.what());
        return RAC_ERROR_PROCESSING_FAILED;
    }
}

void rac_rag_result_free(rac_rag_result_t* result) {
    if (result == nullptr) {
        return;
    }

    rac_free(result->answer);
    rac_free(result->context_used);

    if (result->retrieved_chunks != nullptr) {
        for (size_t i = 0; i < result->num_chunks; ++i) {
            rac_free(result->retrieved_chunks[i].chunk_id);
            rac_free(result->retrieved_chunks[i].text);
            rac_free(result->retrieved_chunks[i].metadata_json);
        }
        rac_free(result->retrieved_chunks);
    }

    // Zero out the struct but DON'T free the struct itself
    // Caller is responsible for the result struct memory
    memset(result, 0, sizeof(rac_rag_result_t));
}

void rac_rag_pipeline_destroy(rac_rag_pipeline_t* pipeline) {
    if (pipeline == nullptr) {
        return;
    }

    RAC_LOG_INFO(LOG_TAG,"Destroying RAG pipeline");
    delete pipeline;
}

} // extern "C"
