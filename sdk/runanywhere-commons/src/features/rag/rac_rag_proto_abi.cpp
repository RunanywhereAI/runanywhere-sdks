/**
 * @file rac_rag_proto_abi.cpp
 * @brief Proto-byte C ABI for RAG sessions.
 *
 * Constructs RAGBackend (internal C++ class) directly from
 * runanywhere.v1.RAGConfiguration bytes, without going through the
 * deleted legacy struct API (`rac_rag_pipeline_*` / `rac_rag_config_t`).
 * Model ids are resolved to filesystem paths via the global model
 * registry, then passed through rac_embeddings_create_with_config() /
 * rac_llm_create() before handing the service handles to RAGBackend
 * (which owns them and destroys on session destroy).
 */

#include "rag_backend.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/rag/rac_rag.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "rag.pb.h"
#include "sdk_events.pb.h"
#endif

#define LOG_TAG "RAG.ProtoABI"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)

using runanywhere::rag::RAGBackend;
using runanywhere::rag::RAGBackendConfig;

namespace {

#if defined(RAC_HAVE_PROTOBUF)

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

std::string event_id() {
    static std::atomic<uint64_t> counter{0};
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%lld-%llu", static_cast<long long>(now_ms()),
                  static_cast<unsigned long long>(counter.fetch_add(1)));
    return buffer;
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return size == 0 || bytes != nullptr;
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    if (!out)
        return RAC_ERROR_NULL_POINTER;
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize proto result");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
}

void publish_event(const runanywhere::v1::SDKEvent& event) {
    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        (void)rac_sdk_event_publish_proto(bytes.empty() ? nullptr : bytes.data(), bytes.size());
    }
}

void publish_capability(runanywhere::v1::CapabilityOperationEventKind kind, const char* operation,
                        float progress, int64_t input_count, int64_t output_count,
                        const char* error) {
    runanywhere::v1::SDKEvent event;
    event.set_id(event_id());
    event.set_timestamp_ms(now_ms());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_RAG);
    event.set_severity(error && error[0] ? runanywhere::v1::ERROR_SEVERITY_ERROR
                                         : runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::SDK_COMPONENT_RAG);
    event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event.set_source("cpp");
    auto* cap = event.mutable_capability();
    cap->set_kind(kind);
    cap->set_component(runanywhere::v1::SDK_COMPONENT_RAG);
    if (operation) {
        event.set_operation_id(operation);
        cap->set_operation(operation);
    }
    cap->set_progress(progress);
    cap->set_input_count(input_count);
    cap->set_output_count(output_count);
    if (error)
        cap->set_error(error);
    publish_event(event);
}

void publish_failure(rac_result_t code, const char* operation, const char* message) {
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_FAILED, operation, 0.0f,
                       0, 0, message && message[0] ? message : rac_error_message(code));
    (void)rac_sdk_event_publish_failure(code, message, "rag", operation, RAC_TRUE);
}

// ---------------------------------------------------------------------------
// D-6: model-id -> filesystem-path resolution for the RAG proto ABI.
//
// Given a registered model id, looks up the model in the global registry and
// returns the canonical on-disk path (rac_model_info_t.local_path) as a
// std::string. If the model isn't registered or has no local_path set (never
// downloaded), *out_err_message is populated and the function returns an
// empty string.
// ---------------------------------------------------------------------------
std::string resolve_rag_model_id_to_path(const std::string& model_id,
                                         std::string* out_err_message) {
    if (model_id.empty()) {
        if (out_err_message)
            *out_err_message = "model id is required";
        return {};
    }
    rac_model_info_t* info = nullptr;
    rac_result_t rc = rac_get_model(model_id.c_str(), &info);
    if (rc != RAC_SUCCESS || !info) {
        if (out_err_message) {
            *out_err_message = "RAG model id '" + model_id + "' is not registered";
        }
        if (info)
            rac_model_info_free(info);
        return {};
    }
    if (!info->local_path || info->local_path[0] == '\0') {
        if (out_err_message) {
            *out_err_message =
                "RAG model '" + model_id + "' is registered but has no local_path (not downloaded)";
        }
        rac_model_info_free(info);
        return {};
    }
    std::string path(info->local_path);
    rac_model_info_free(info);
    return path;
}

// ---------------------------------------------------------------------------
// Session handle
//
// The RAG proto ABI hands out rac_handle_t values that are in fact pointers
// to a Session struct which owns the underlying RAGBackend (which owns the
// LLM + Embeddings service handles). The Session is created by
// rac_rag_session_create_proto and freed by rac_rag_session_destroy_proto.
//
// Multi-session is the deliberate contract here: each handle is a fully
// independent Session with its own RAGBackend (its own vector store + BM25
// index + service handles) and no shared global state, so an app can keep
// several RAG indexes live at once. Mobile SDK bridges currently expose only
// one session for convenience, but that is a frontend choice, not an ABI
// limitation -- the commons layer imposes no single-session restriction.
// ---------------------------------------------------------------------------
struct Session {
    std::unique_ptr<RAGBackend> backend;
};

Session* as_session(rac_handle_t handle) {
    return reinterpret_cast<Session*>(handle);
}

RAGBackendConfig build_backend_config(const runanywhere::v1::RAGConfiguration& proto) {
    RAGBackendConfig bc;
    // Numeric fields are proto3 `optional`, so presence == "caller-supplied
    // override". This preserves explicit-zero values (e.g. chunk_overlap=0
    // = no overlap) instead of silently re-applying the struct's defaults.
    if (proto.has_embedding_dimension())
        bc.embedding_dimension = static_cast<size_t>(proto.embedding_dimension());
    if (proto.has_top_k())
        bc.top_k = static_cast<size_t>(proto.top_k());
    if (proto.has_similarity_threshold())
        bc.similarity_threshold = proto.similarity_threshold();
    if (proto.has_max_context_tokens())
        bc.max_context_tokens = static_cast<size_t>(proto.max_context_tokens());
    if (proto.has_chunk_size())
        bc.chunk_size = static_cast<size_t>(proto.chunk_size());
    if (proto.has_chunk_overlap())
        bc.chunk_overlap = static_cast<size_t>(proto.chunk_overlap());
    if (proto.has_prompt_template() && !proto.prompt_template().empty())
        bc.prompt_template = proto.prompt_template();
    return bc;
}

runanywhere::v1::RAGStatistics make_stats(RAGBackend& backend) {
    runanywhere::v1::RAGStatistics out;
    const int64_t chunks = static_cast<int64_t>(backend.document_count());
    out.set_indexed_documents(chunks);
    out.set_indexed_chunks(chunks);
    out.set_last_updated_ms(now_ms());

    try {
        const auto stats = backend.get_statistics();
        if (stats.contains("num_chunks") && stats["num_chunks"].is_number_integer()) {
            out.set_indexed_chunks(stats["num_chunks"].get<int64_t>());
            out.set_indexed_documents(stats["num_chunks"].get<int64_t>());
        }
        if (stats.contains("total_tokens_indexed") &&
            stats["total_tokens_indexed"].is_number_integer()) {
            out.set_total_tokens_indexed(stats["total_tokens_indexed"].get<int64_t>());
        }
        if (stats.contains("index_path") && stats["index_path"].is_string()) {
            out.set_index_path(stats["index_path"].get<std::string>());
        }
    } catch (...) {
        // Keep the structural counters gathered above.
    }
    return out;
}

#endif  // RAC_HAVE_PROTOBUF

#if !defined(RAC_HAVE_PROTOBUF)
rac_result_t feature_unavailable(rac_proto_buffer_t* out) {
    if (out) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                          "protobuf support is not available");
    }
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}
#endif

}  // namespace

extern "C" {

rac_result_t rac_rag_session_create_proto(const uint8_t* config_proto_bytes,
                                          size_t config_proto_size, rac_handle_t* out_session) {
    if (!out_session)
        return RAC_ERROR_NULL_POINTER;
    *out_session = nullptr;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)config_proto_bytes;
    (void)config_proto_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!valid_bytes(config_proto_bytes, config_proto_size)) {
        publish_failure(RAC_ERROR_DECODING_ERROR, "rag.sessionCreate",
                        "RAGConfiguration bytes are invalid");
        return RAC_ERROR_DECODING_ERROR;
    }
    runanywhere::v1::RAGConfiguration proto;
    if (!proto.ParseFromArray(parse_data(config_proto_bytes, config_proto_size),
                              static_cast<int>(config_proto_size))) {
        publish_failure(RAC_ERROR_DECODING_ERROR, "rag.sessionCreate",
                        "failed to parse RAGConfiguration");
        return RAC_ERROR_DECODING_ERROR;
    }

    // D-6: RAGConfiguration carries model ids. embedding_model_id is required;
    // llm_model_id is optional (embed-only pipelines are legal). Commons
    // resolves each id to a filesystem path via rac_get_model() before
    // handing them to rac_embeddings_create_with_config / rac_llm_create.
    const std::string embedding_model_id = proto.embedding_model_id();
    const std::string llm_model_id = proto.llm_model_id();

    if (embedding_model_id.empty()) {
        publish_failure(RAC_ERROR_INVALID_ARGUMENT, "rag.sessionCreate",
                        "RAGConfiguration.embedding_model_id is required");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Reranking is part of the public RAGConfiguration surface (rag.proto:128,
    // rag.proto:130) but no rerank backend is wired up: rag_pipeline_graph
    // skips the rerank step (rag_pipeline_graph.h:20-25) and every engine sets
    // rac_engine_vtable_t::rerank_ops = nullptr. Silently honoring the request
    // would let callers ship "reranked" RAG that is plain RRF fusion. Fail
    // fast until the rerank vtable lands so misconfiguration surfaces at
    // session-create instead of looking exactly like a working baseline.
    const bool rerank_requested =
        proto.rerank_results() ||
        (proto.has_reranker_model_id() && !proto.reranker_model_id().empty());
    if (rerank_requested) {
        const char* msg =
            "reranking is not yet implemented; unset rerank_results and reranker_model_id";
        publish_failure(RAC_ERROR_FEATURE_NOT_AVAILABLE, "rag.sessionCreate", msg);
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }

    std::string err_message;
    std::string embedding_path = resolve_rag_model_id_to_path(embedding_model_id, &err_message);
    if (embedding_path.empty()) {
        publish_failure(RAC_ERROR_MODEL_NOT_FOUND, "rag.sessionCreate", err_message.c_str());
        return RAC_ERROR_MODEL_NOT_FOUND;
    }

    std::string llm_path;
    if (!llm_model_id.empty()) {
        llm_path = resolve_rag_model_id_to_path(llm_model_id, &err_message);
        if (llm_path.empty()) {
            publish_failure(RAC_ERROR_MODEL_NOT_FOUND, "rag.sessionCreate", err_message.c_str());
            return RAC_ERROR_MODEL_NOT_FOUND;
        }
    }

    // Spin up the embeddings + (optional) LLM service handles. Ownership is
    // transferred into the RAGBackend (owns_services=true) so the Session
    // destructor will clean them up via RAGBackend::~RAGBackend().
    rac_handle_t embed_handle = nullptr;
    rac_handle_t llm_handle = nullptr;

    const char* embedding_config_json =
        proto.has_embedding_config_json() && !proto.embedding_config_json().empty()
            ? proto.embedding_config_json().c_str()
            : nullptr;

    LOGI("sessionCreate: embed_path=%s, llm_path=%s", embedding_path.c_str(),
         llm_path.empty() ? "(none)" : llm_path.c_str());

    rac_result_t rc = rac_embeddings_create_with_config(embedding_path.c_str(),
                                                        embedding_config_json, &embed_handle);
    if (rc != RAC_SUCCESS || !embed_handle) {
        rc = rc != RAC_SUCCESS ? rc : RAC_ERROR_INITIALIZATION_FAILED;
        publish_failure(rc, "rag.sessionCreate", rac_error_message(rc));
        return rc;
    }

    if (!llm_path.empty()) {
        rc = rac_llm_create(llm_path.c_str(), &llm_handle);
        if (rc != RAC_SUCCESS || !llm_handle) {
            rc = rc != RAC_SUCCESS ? rc : RAC_ERROR_INITIALIZATION_FAILED;
            rac_embeddings_destroy(embed_handle);
            publish_failure(rc, "rag.sessionCreate", rac_error_message(rc));
            return rc;
        }
    }

    try {
        auto session = std::make_unique<Session>();
        session->backend =
            std::make_unique<RAGBackend>(build_backend_config(proto), llm_handle, embed_handle,
                                         /*owns_services=*/true);
        if (!session->backend->is_initialized()) {
            publish_failure(RAC_ERROR_INITIALIZATION_FAILED, "rag.sessionCreate",
                            "RAG pipeline failed to initialize");
            // session destructor clears owned services.
            return RAC_ERROR_INITIALIZATION_FAILED;
        }
        *out_session = reinterpret_cast<rac_handle_t>(session.release());
        LOGI("RAG session created");
        return RAC_SUCCESS;
    } catch (const std::exception& e) {
        LOGE("Exception creating RAG session: %s", e.what());
        if (llm_handle)
            rac_llm_destroy(llm_handle);
        if (embed_handle)
            rac_embeddings_destroy(embed_handle);
        publish_failure(RAC_ERROR_INITIALIZATION_FAILED, "rag.sessionCreate", e.what());
        return RAC_ERROR_INITIALIZATION_FAILED;
    }
#endif
}

void rac_rag_session_destroy_proto(rac_handle_t session) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session;
#else
    delete as_session(session);
#endif
}

rac_result_t rac_rag_ingest_proto(rac_handle_t session, const uint8_t* document_proto_bytes,
                                  size_t document_proto_size, rac_proto_buffer_t* out_stats) {
    if (!out_stats)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session;
    (void)document_proto_bytes;
    (void)document_proto_size;
    return feature_unavailable(out_stats);
#else
    auto* s = as_session(session);
    if (!s || !s->backend) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "rag.ingest", "RAG session is not loaded");
        return rac_proto_buffer_set_error(out_stats, RAC_ERROR_COMPONENT_NOT_READY,
                                          "RAG session is not loaded");
    }
    if (!valid_bytes(document_proto_bytes, document_proto_size)) {
        return rac_proto_buffer_set_error(out_stats, RAC_ERROR_DECODING_ERROR,
                                          "RAGDocument bytes are invalid");
    }
    runanywhere::v1::RAGDocument document;
    if (!document.ParseFromArray(parse_data(document_proto_bytes, document_proto_size),
                                 static_cast<int>(document_proto_size))) {
        return rac_proto_buffer_set_error(out_stats, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse RAGDocument ingest request");
    }
    if (document.text().empty()) {
        return rac_proto_buffer_set_error(out_stats, RAC_ERROR_INVALID_ARGUMENT,
                                          "RAGDocument.text is required for ingestion");
    }

    nlohmann::json metadata = nlohmann::json::object();
    if (!document.id().empty()) {
        metadata["document_id"] = document.id();
    }
    for (const auto& item : document.metadata()) {
        metadata[item.first] = item.second;
    }

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_STARTED,
                       "rag.ingest", 0.0f, 1, 0, nullptr);

    bool added = false;
    try {
        added = s->backend->add_document(document.text(), metadata);
    } catch (const std::exception& e) {
        LOGE("rag.ingest exception: %s", e.what());
        publish_failure(RAC_ERROR_PROCESSING_FAILED, "rag.ingest", e.what());
        return rac_proto_buffer_set_error(out_stats, RAC_ERROR_PROCESSING_FAILED, e.what());
    }
    if (!added) {
        publish_failure(RAC_ERROR_PROCESSING_FAILED, "rag.ingest",
                        rac_error_message(RAC_ERROR_PROCESSING_FAILED));
        return rac_proto_buffer_set_error(out_stats, RAC_ERROR_PROCESSING_FAILED,
                                          rac_error_message(RAC_ERROR_PROCESSING_FAILED));
    }

    auto stats = make_stats(*s->backend);
    rac_result_t rc = copy_proto(stats, out_stats);
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_COMPLETED,
                       "rag.ingest", 1.0f, 1, stats.indexed_chunks(), nullptr);
    return rc;
#endif
}

rac_result_t rac_rag_query_proto(rac_handle_t session, const uint8_t* query_proto_bytes,
                                 size_t query_proto_size, rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session;
    (void)query_proto_bytes;
    (void)query_proto_size;
    return feature_unavailable(out_result);
#else
    auto* s = as_session(session);
    if (!s || !s->backend) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "rag.query", "RAG session is not loaded");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_COMPONENT_NOT_READY,
                                          "RAG session is not loaded");
    }
    if (!valid_bytes(query_proto_bytes, query_proto_size)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "RAGQueryOptions bytes are invalid");
    }
    runanywhere::v1::RAGQueryOptions query_proto;
    if (!query_proto.ParseFromArray(parse_data(query_proto_bytes, query_proto_size),
                                    static_cast<int>(query_proto_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse RAGQueryOptions");
    }

    const std::string question = query_proto.question();
    if (question.empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "RAGQueryOptions.question is required");
    }

    const std::string system_prompt =
        query_proto.has_system_prompt() ? query_proto.system_prompt() : std::string();

    rac_llm_options_t opts = {};
    opts.max_tokens = query_proto.max_tokens() > 0 ? query_proto.max_tokens() : 512;
    opts.temperature = query_proto.temperature() > 0.0f ? query_proto.temperature() : 0.7f;
    opts.top_p = query_proto.top_p() > 0.0f ? query_proto.top_p() : 0.9f;
    opts.system_prompt = system_prompt.empty() ? nullptr : system_prompt.c_str();

    // Per-query retrieval overrides from RAGQueryOptions (idl/rag.proto:180-183).
    // Zero values fall back to the session-level RAGConfig defaults inside
    // RAGBackend::query so legacy callers behave as before.
    RAGBackend::QueryOverrides overrides;
    overrides.retrieval_top_k = query_proto.retrieval_top_k();
    overrides.similarity_threshold = query_proto.similarity_threshold();

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_STARTED,
                       "rag.query", 0.0f, 1, 0, nullptr);

    const auto t_start = std::chrono::high_resolution_clock::now();
    rac_llm_result_t llm_result = {};
    nlohmann::json metadata;
    rac_result_t status = RAC_SUCCESS;
    try {
        status = s->backend->query(question, &opts, &llm_result, metadata, nullptr, &overrides);
    } catch (const std::exception& e) {
        LOGE("rag.query exception: %s", e.what());
        rac_llm_result_free(&llm_result);
        publish_failure(RAC_ERROR_PROCESSING_FAILED, "rag.query", e.what());
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_PROCESSING_FAILED, e.what());
    }
    const auto t_end = std::chrono::high_resolution_clock::now();
    const double total_ms = std::chrono::duration<double, std::milli>(t_end - t_start).count();

    if (status != RAC_SUCCESS) {
        rac_llm_result_free(&llm_result);
        publish_failure(status, "rag.query", rac_error_message(status));
        return rac_proto_buffer_set_error(out_result, status, rac_error_message(status));
    }

    runanywhere::v1::RAGResult proto;
    if (llm_result.text)
        proto.set_answer(llm_result.text);

    if (metadata.contains("context_used") && metadata["context_used"].is_string()) {
        proto.set_context_used(metadata["context_used"].get<std::string>());
    }

    if (metadata.contains("sources") && metadata["sources"].is_array()) {
        for (const auto& s_item : metadata["sources"]) {
            auto* chunk = proto.add_retrieved_chunks();
            if (s_item.contains("id") && s_item["id"].is_string()) {
                chunk->set_chunk_id(s_item["id"].get<std::string>());
            }
            if (s_item.contains("text") && s_item["text"].is_string()) {
                chunk->set_text(s_item["text"].get<std::string>());
            }
            if (s_item.contains("score") && s_item["score"].is_number()) {
                chunk->set_similarity_score(s_item["score"].get<float>());
            }
        }
    }

    const double generation_ms = llm_result.total_time_ms;
    const double retrieval_ms = std::max(0.0, total_ms - generation_ms);
    proto.set_retrieval_time_ms(static_cast<int64_t>(retrieval_ms));
    proto.set_generation_time_ms(static_cast<int64_t>(generation_ms));
    proto.set_total_time_ms(static_cast<int64_t>(total_ms));

    rac_result_t rc = copy_proto(proto, out_result);
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_COMPLETED,
                       "rag.query", 1.0f, 1, proto.retrieved_chunks_size(), nullptr);
    rac_llm_result_free(&llm_result);
    return rc;
#endif
}

rac_result_t rac_rag_stats_proto(rac_handle_t session, rac_proto_buffer_t* out_stats) {
    if (!out_stats)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session;
    return feature_unavailable(out_stats);
#else
    auto* s = as_session(session);
    if (!s || !s->backend) {
        return rac_proto_buffer_set_error(out_stats, RAC_ERROR_COMPONENT_NOT_READY,
                                          "RAG session is not loaded");
    }
    return copy_proto(make_stats(*s->backend), out_stats);
#endif
}

rac_result_t rac_rag_clear_proto(rac_handle_t session, rac_proto_buffer_t* out_stats) {
    if (!out_stats)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session;
    return feature_unavailable(out_stats);
#else
    auto* s = as_session(session);
    if (!s || !s->backend) {
        return rac_proto_buffer_set_error(out_stats, RAC_ERROR_COMPONENT_NOT_READY,
                                          "RAG session is not loaded");
    }
    try {
        s->backend->clear();
    } catch (const std::exception& e) {
        LOGE("rag.clear exception: %s", e.what());
        publish_failure(RAC_ERROR_PROCESSING_FAILED, "rag.clear", e.what());
        return rac_proto_buffer_set_error(out_stats, RAC_ERROR_PROCESSING_FAILED, e.what());
    }
    return copy_proto(make_stats(*s->backend), out_stats);
#endif
}

}  // extern "C"
