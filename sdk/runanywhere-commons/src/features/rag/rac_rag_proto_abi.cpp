/**
 * @file rac_rag_proto_abi.cpp
 * @brief Proto-byte C ABI for RAG sessions.
 *
 * Constructs RAGBackend (internal C++ class) directly from
 * runanywhere.v1.RAGConfiguration bytes, without going through the
 * deleted legacy struct API (`rac_rag_pipeline_*` / `rac_rag_config_t`).
 * Model ids are resolved to filesystem paths via the global model
 * registry, then passed through the internal embeddings service factory and
 * rac_llm_create() before handing the service handles to RAGBackend
 * (which owns them and destroys on session destroy).
 */

#include "rag_backend.h"

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <nlohmann/json.hpp>
#include <string>
#include <unordered_map>
#include <vector>

#include "../embeddings/embeddings_service_internal.h"
#include "features/llm/llm_thinking_tags_internal.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_thinking.h"
#include "rac/features/rag/rac_rag.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "rag.pb.h"
#include "sdk_events.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#include "infrastructure/events/sdk_event_publish.h"
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
    return rac::proto::copy_message(message, out, "failed to serialize proto result");
}

void publish_event(const runanywhere::v1::SDKEvent& event) {
    // Route through the destination router (sdk_event_publish) so the envelope's
    // TELEMETRY destination bit reaches the telemetry manager. A direct
    // rac_sdk_event_publish_proto call feeds only the PUBLIC stream, so these
    // capability events would never be recorded as telemetry.
    (void)rac::events::publish_prebuilt(event);
}

void publish_capability(runanywhere::v1::CapabilityOperationEventKind kind, const char* operation,
                        float progress, int64_t input_count, int64_t output_count,
                        const char* error, double duration_ms = 0.0, const char* model_id = nullptr,
                        int64_t top_k = 0, double retrieval_time_ms = 0.0,
                        const char* embedding_model = nullptr,
                        rac_result_t error_code = RAC_SUCCESS, int reranker_used = -1) {
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
    if (model_id != nullptr && model_id[0] != '\0') {
        cap->set_model_id(model_id);
    }
    if (operation) {
        event.set_operation_id(operation);
        cap->set_operation(operation);
    }
    cap->set_progress(progress);
    cap->set_input_count(input_count);
    cap->set_output_count(output_count);
    if (error)
        cap->set_error(error);
    // Populate the envelope SDKError so the telemetry manager records error_code on
    // the row (the kCapability extractor reads ev.error().c_abi_code(); without this
    // a failed RAG op landed with error_message set but error_code null).
    if (error && error[0] && error_code != RAC_SUCCESS) {
        auto* err = event.mutable_error();
        err->set_message(error);
        err->set_c_abi_code(static_cast<int32_t>(error_code));
    }
    // CapabilityOperationEvent has no duration field; telemetry reads it from
    // the envelope properties map (see telemetry_manager kCapability extraction).
    if (duration_ms > 0.0) {
        (*event.mutable_properties())["duration_ms"] = std::to_string(duration_ms);
    }
    if (top_k > 0) {
        (*event.mutable_properties())["top_k"] = std::to_string(top_k);
    }
    if (retrieval_time_ms > 0.0) {
        (*event.mutable_properties())["retrieval_time_ms"] = std::to_string(retrieval_time_ms);
    }
    if (embedding_model != nullptr && embedding_model[0] != '\0') {
        (*event.mutable_properties())["embedding_model"] = embedding_model;
    }
    if (reranker_used >= 0) {
        (*event.mutable_properties())["reranker_used"] = reranker_used != 0 ? "1" : "0";
    }
    publish_event(event);
}

void publish_failure(rac_result_t code, const char* operation, const char* message) {
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_FAILED, operation, 0.0f,
                       0, 0, message && message[0] ? message : rac_error_message(code),
                       /*duration_ms=*/0.0, /*model_id=*/nullptr, /*top_k=*/0,
                       /*retrieval_time_ms=*/0.0, /*embedding_model=*/nullptr, /*error_code=*/code);
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
// The RAG proto ABI hands out opaque, monotonically increasing rac_handle_t
// tokens. A mutex-protected registry owns each Session through shared_ptr so
// an operation can retain its backend while destroy concurrently removes the
// handle from admission. Destroy requests query cancellation after removal;
// the Session and its LLM/Embeddings services are released only after every
// already-admitted operation drops its shared owner.
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
    std::atomic<bool> closing{false};
    // Registry ids captured at create — telemetry attribution only (ingestion
    // events report the embedding model, query events the LLM).
    std::string embedding_model_id;
    std::string llm_model_id;
    // Resolved retrieval top_k for this session (config default). Telemetry emits
    // the effective retrieval top_k so the query row is never null when a caller
    // omits a per-query override.
    size_t retrieval_top_k = 5;
    // Whether LLM-pointwise reranking is enabled for this session (config).
    // Stamped onto query telemetry (rag_telemetry.reranker_used).
    bool rerank = false;
};

struct SessionRegistry {
    std::mutex mutex;
    std::uintptr_t next_handle{1};
    std::unordered_map<std::uintptr_t, std::shared_ptr<Session>> sessions;
};

SessionRegistry& session_registry() {
    static SessionRegistry registry;
    return registry;
}

std::uintptr_t handle_key(rac_handle_t handle) {
    return reinterpret_cast<std::uintptr_t>(handle);
}

rac_handle_t register_session(const std::shared_ptr<Session>& session) {
    auto& registry = session_registry();
    std::lock_guard<std::mutex> lock(registry.mutex);
    for (;;) {
        const std::uintptr_t candidate = registry.next_handle++;
        if (candidate == 0 || registry.sessions.find(candidate) != registry.sessions.end()) {
            continue;
        }
        registry.sessions.emplace(candidate, session);
        return reinterpret_cast<rac_handle_t>(candidate);
    }
}

std::shared_ptr<Session> acquire_session(rac_handle_t handle) {
    if (!handle) {
        return {};
    }
    auto& registry = session_registry();
    std::lock_guard<std::mutex> lock(registry.mutex);
    const auto it = registry.sessions.find(handle_key(handle));
    if (it == registry.sessions.end() || it->second->closing.load(std::memory_order_acquire)) {
        return {};
    }
    return it->second;
}

std::shared_ptr<Session> close_session(rac_handle_t handle) {
    if (!handle) {
        return {};
    }
    auto& registry = session_registry();
    std::lock_guard<std::mutex> lock(registry.mutex);
    const auto it = registry.sessions.find(handle_key(handle));
    if (it == registry.sessions.end()) {
        return {};
    }
    std::shared_ptr<Session> session = it->second;
    session->closing.store(true, std::memory_order_release);
    registry.sessions.erase(it);
    return session;
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
    bc.rerank = proto.rerank_results();
    bc.embedding_model_id = proto.embedding_model_id();
    return bc;
}

bool validate_rag_configuration(const runanywhere::v1::RAGConfiguration& proto,
                                std::string* out_message) {
    const RAGBackendConfig defaults;

    if (proto.has_embedding_dimension() && proto.embedding_dimension() < 1) {
        if (out_message)
            *out_message = "RAGConfiguration.embedding_dimension must be >= 1 when set";
        return false;
    }

    const int64_t top_k = proto.has_top_k() ? static_cast<int64_t>(proto.top_k())
                                            : static_cast<int64_t>(defaults.top_k);
    if (top_k < 1) {
        if (out_message)
            *out_message = "RAGConfiguration.top_k must be >= 1";
        return false;
    }

    const float similarity_threshold = proto.has_similarity_threshold()
                                           ? proto.similarity_threshold()
                                           : defaults.similarity_threshold;
    if (!std::isfinite(similarity_threshold) || similarity_threshold < 0.0f ||
        similarity_threshold > 1.0f) {
        if (out_message)
            *out_message = "RAGConfiguration.similarity_threshold must be in 0.0...1.0";
        return false;
    }

    const int64_t chunk_size = proto.has_chunk_size() ? static_cast<int64_t>(proto.chunk_size())
                                                      : static_cast<int64_t>(defaults.chunk_size);
    if (chunk_size < 1) {
        if (out_message)
            *out_message = "RAGConfiguration.chunk_size must be >= 1";
        return false;
    }

    const int64_t chunk_overlap = proto.has_chunk_overlap()
                                      ? static_cast<int64_t>(proto.chunk_overlap())
                                      : static_cast<int64_t>(defaults.chunk_overlap);
    if (chunk_overlap < 0) {
        if (out_message)
            *out_message = "RAGConfiguration.chunk_overlap must be >= 0";
        return false;
    }
    if (chunk_overlap >= chunk_size) {
        if (out_message) {
            *out_message = "RAGConfiguration.chunk_overlap must be < chunk_size";
        }
        return false;
    }

    return true;
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
    } catch (...) {
        // Keep the structural counters gathered above.
    }
    return out;
}

// Shared core for the unary + streaming RAG query entry points. Runs setup →
// retrieval + generation (per-token via on_token when non-null) → telemetry →
// builds the RAGResult proto. On success fills *out_proto and returns
// RAC_SUCCESS; on failure returns the status and sets *out_error for the
// caller's error surface. Telemetry (started/completed/failed) is emitted here
// so both entry points behave identically.
rac_result_t execute_rag_query(const std::shared_ptr<Session>& s,
                               const runanywhere::v1::RAGQueryOptions& query_proto,
                               std::function<bool(const std::string&)> on_token,
                               runanywhere::v1::RAGResult* out_proto, std::string* out_error) {
    const std::string question = query_proto.question();
    const std::string system_prompt =
        query_proto.has_system_prompt() ? query_proto.system_prompt() : std::string();

    // Base off RAC_LLM_OPTIONS_DEFAULT so the sampling fields RAGQueryOptions
    // does not expose carry the proto-documented defaults instead of zero-init.
    rac_llm_options_t opts = RAC_LLM_OPTIONS_DEFAULT;
    opts.max_tokens = query_proto.max_tokens() > 0 ? query_proto.max_tokens() : 512;
    opts.temperature = query_proto.temperature();
    opts.top_p = query_proto.top_p() > 0.0f ? query_proto.top_p() : 0.9f;
    opts.top_k = query_proto.top_k();
    opts.disable_thinking = query_proto.disable_thinking() ? RAC_TRUE : RAC_FALSE;
    opts.system_prompt = system_prompt.empty() ? nullptr : system_prompt.c_str();

    RAGBackend::QueryOverrides overrides;
    overrides.retrieval_top_k = query_proto.retrieval_top_k();
    overrides.has_similarity_threshold = query_proto.has_similarity_threshold();
    overrides.similarity_threshold = query_proto.similarity_threshold();
    overrides.enable_multi_query = query_proto.enable_multi_query();
    constexpr int32_t kMaxMultiQueryCount = 8;
    if (query_proto.has_multi_query_count()) {
        const int32_t n = query_proto.multi_query_count();
        overrides.multi_query_count = n > kMaxMultiQueryCount ? kMaxMultiQueryCount : n;
    } else {
        overrides.multi_query_count = 0;
    }
    if (query_proto.has_scope_prefix())
        overrides.scope_prefix = query_proto.scope_prefix();

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_STARTED,
                       "rag.query", 0.0f, 1, 0, nullptr, 0.0,
                       s->llm_model_id.empty() ? s->embedding_model_id.c_str()
                                               : s->llm_model_id.c_str());

    const auto t_start = std::chrono::high_resolution_clock::now();
    rac_llm_result_t llm_result = {};
    nlohmann::json metadata;
    rac_result_t status = RAC_SUCCESS;
    try {
        status = s->backend->query(question, &opts, &llm_result, metadata, std::move(on_token),
                                   &overrides);
    } catch (const std::exception& e) {
        LOGE("rag.query exception: %s", e.what());
        rac_llm_result_free(&llm_result);
        if (out_error)
            *out_error = e.what();
        publish_failure(RAC_ERROR_PROCESSING_FAILED, "rag.query", e.what());
        return RAC_ERROR_PROCESSING_FAILED;
    }
    const auto t_end = std::chrono::high_resolution_clock::now();
    const double total_ms = std::chrono::duration<double, std::milli>(t_end - t_start).count();

    if (status != RAC_SUCCESS) {
        rac_llm_result_free(&llm_result);
        if (out_error)
            *out_error = rac_error_message(status);
        publish_failure(status, "rag.query", rac_error_message(status));
        return status;
    }

    runanywhere::v1::RAGResult& proto = *out_proto;
    const char* raw_answer = llm_result.text ? llm_result.text : "";
    const char* answer = nullptr;
    size_t answer_len = 0;
    const char* thinking = nullptr;
    size_t thinking_len = 0;
    std::string thinking_open_tag;
    std::string thinking_close_tag;
    (void)rac::llm::model_thinking_tags_from_registry(s->llm_model_id.c_str(), &thinking_open_tag,
                                                      &thinking_close_tag);
    if (rac_llm_extract_thinking_with_tags(
            raw_answer, thinking_open_tag.empty() ? nullptr : thinking_open_tag.c_str(),
            thinking_close_tag.empty() ? nullptr : thinking_close_tag.c_str(), &answer, &answer_len,
            &thinking, &thinking_len) == RAC_SUCCESS) {
        proto.set_answer(answer ? std::string(answer, answer_len) : std::string());
        if (thinking && thinking_len > 0) {
            proto.set_thinking_content(std::string(thinking, thinking_len));
        }
    } else if (llm_result.text) {
        proto.set_answer(llm_result.text);
    }

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
            if (s_item.contains("source_document") && s_item["source_document"].is_string()) {
                chunk->set_source_document(s_item["source_document"].get<std::string>());
            } else if (s_item.contains("source") && s_item["source"].is_string()) {
                chunk->set_source_document(s_item["source"].get<std::string>());
            }
        }
    }

    const double generation_ms = llm_result.total_time_ms;
    const double retrieval_ms = std::max(0.0, total_ms - generation_ms);
    proto.set_retrieval_time_ms(static_cast<int64_t>(retrieval_ms));
    proto.set_generation_time_ms(static_cast<int64_t>(generation_ms));
    proto.set_total_time_ms(static_cast<int64_t>(total_ms));

    // Emit the EFFECTIVE retrieval top_k (per-query override, else the session
    // config default) — not query_proto.top_k(), which is the LLM sampling top_k.
    const int64_t effective_top_k =
        overrides.retrieval_top_k > 0 ? static_cast<int64_t>(overrides.retrieval_top_k)
                                      : static_cast<int64_t>(s->retrieval_top_k);
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_COMPLETED,
                       "rag.query", 1.0f, 1, proto.retrieved_chunks_size(), nullptr, total_ms,
                       s->llm_model_id.empty() ? s->embedding_model_id.c_str()
                                               : s->llm_model_id.c_str(),
                       effective_top_k, retrieval_ms, s->embedding_model_id.c_str(),
                       /*error_code=*/RAC_SUCCESS, /*reranker_used=*/s->rerank ? 1 : 0);
    rac_llm_result_free(&llm_result);
    return RAC_SUCCESS;
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
    // handing them to the internal embeddings factory / rac_llm_create.
    const std::string embedding_model_id = proto.embedding_model_id();
    const std::string llm_model_id = proto.llm_model_id();

    if (embedding_model_id.empty()) {
        publish_failure(RAC_ERROR_INVALID_ARGUMENT, "rag.sessionCreate",
                        "RAGConfiguration.embedding_model_id is required");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::string validation_message;
    if (!validate_rag_configuration(proto, &validation_message)) {
        publish_failure(RAC_ERROR_INVALID_ARGUMENT, "rag.sessionCreate",
                        validation_message.c_str());
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // rerank_results enables LLM-pointwise reranking of fused candidates, run
    // by rag_pipeline_graph using the session's LLM handle. reranker_model_id
    // (a dedicated cross-encoder) is not yet supported — reject only that.
    if (proto.has_reranker_model_id() && !proto.reranker_model_id().empty()) {
        const char* msg =
            "reranker_model_id (dedicated cross-encoder) is not yet supported; use rerank_results "
            "to enable LLM-pointwise reranking with the session LLM";
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

    rac_result_t rc = rac::embeddings::create_service(embedding_path.c_str(), embedding_config_json,
                                                      &embed_handle);
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
        auto session = std::make_shared<Session>();
        session->embedding_model_id = embedding_model_id;
        session->llm_model_id = llm_model_id;
        RAGBackendConfig backend_config = build_backend_config(proto);
        session->retrieval_top_k = backend_config.top_k;
        session->rerank = backend_config.rerank;
        // Resolve the dimension without assuming 384. Some providers know it
        // at create time; providers such as QHexRT only know after inference,
        // in which case zero remains the auto sentinel and RAGBackend binds the
        // vector store to the first actual embedding output.
        rac_embeddings_info_t info = {};
        const rac_result_t info_rc = rac_embeddings_get_info(embed_handle, &info);
        if (info_rc == RAC_SUCCESS && info.dimension > 0) {
            if (proto.has_embedding_dimension() &&
                static_cast<size_t>(proto.embedding_dimension()) != info.dimension) {
                const std::string message =
                    "RAGConfiguration.embedding_dimension does not match loaded model: "
                    "configured " +
                    std::to_string(proto.embedding_dimension()) + ", model " +
                    std::to_string(info.dimension);
                if (llm_handle)
                    rac_llm_destroy(llm_handle);
                rac_embeddings_destroy(embed_handle);
                publish_failure(RAC_ERROR_INVALID_ARGUMENT, "rag.sessionCreate", message.c_str());
                return RAC_ERROR_INVALID_ARGUMENT;
            }
            if (!proto.has_embedding_dimension()) {
                backend_config.embedding_dimension = info.dimension;
                LOGI("Derived embedding_dimension=%zu from embedding model '%s'", info.dimension,
                     embedding_model_id.c_str());
            }
        } else if (!proto.has_embedding_dimension()) {
            LOGI(
                "Embedding model '%s' reports dimension at inference; deferring vector-store "
                "initialization",
                embedding_model_id.c_str());
        }
        session->backend = std::make_unique<RAGBackend>(backend_config, llm_handle, embed_handle,
                                                        /*owns_services=*/true);
        // Ownership transferred successfully. Any later exception (including
        // registry allocation failure) is handled by Session/RAGBackend.
        llm_handle = nullptr;
        embed_handle = nullptr;
        if (!session->backend->is_initialized()) {
            publish_failure(RAC_ERROR_INITIALIZATION_FAILED, "rag.sessionCreate",
                            "RAG pipeline failed to initialize");
            // session destructor clears owned services.
            return RAC_ERROR_INITIALIZATION_FAILED;
        }
        *out_session = register_session(session);
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
    auto owned_session = close_session(session);
    if (owned_session && owned_session->backend) {
        // Do not wait for in-flight callers while holding the registry lock.
        // The shared owner keeps all backend resources alive until both this
        // cancellation pulse and every already-admitted operation return.
        (void)owned_session->backend->cancel_query();
    }
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
    const auto s = acquire_session(session);
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
                       "rag.ingest", 0.0f, 1, 0, nullptr, 0.0, s->embedding_model_id.c_str());

    const auto ingest_start = std::chrono::steady_clock::now();
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
    const double ingest_ms = std::chrono::duration_cast<std::chrono::duration<double, std::milli>>(
                                 std::chrono::steady_clock::now() - ingest_start)
                                 .count();
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_COMPLETED,
                       "rag.ingest", 1.0f, 1, stats.indexed_chunks(), nullptr, ingest_ms,
                       s->embedding_model_id.c_str(), /*top_k=*/0, /*retrieval_time_ms=*/0.0,
                       s->embedding_model_id.c_str());
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
    const auto s = acquire_session(session);
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

    runanywhere::v1::RAGResult proto;
    std::string err_msg;
    const rac_result_t status = execute_rag_query(s, query_proto, nullptr, &proto, &err_msg);
    if (status != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(
            out_result, status, err_msg.empty() ? rac_error_message(status) : err_msg.c_str());
    }
    return copy_proto(proto, out_result);
#endif
}

rac_result_t rac_rag_query_stream_proto(rac_handle_t session, const uint8_t* query_proto_bytes,
                                        size_t query_proto_size,
                                        rac_rag_stream_proto_callback_fn callback, void* user_data) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session;
    (void)query_proto_bytes;
    (void)query_proto_size;
    (void)callback;
    (void)user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!callback)
        return RAC_ERROR_NULL_POINTER;
    const auto s = acquire_session(session);
    if (!s || !s->backend) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "rag.query", "RAG session is not loaded");
        return RAC_ERROR_COMPONENT_NOT_READY;
    }
    if (!valid_bytes(query_proto_bytes, query_proto_size))
        return RAC_ERROR_DECODING_ERROR;
    runanywhere::v1::RAGQueryOptions query_proto;
    if (!query_proto.ParseFromArray(parse_data(query_proto_bytes, query_proto_size),
                                    static_cast<int>(query_proto_size)))
        return RAC_ERROR_DECODING_ERROR;
    if (query_proto.question().empty())
        return RAC_ERROR_INVALID_ARGUMENT;

    // Serializes one RAGStreamEvent and hands it to the SDK callback. Runs on the
    // calling thread (the pipeline invokes on_token synchronously).
    uint64_t seq = 0;
    auto emit = [&](runanywhere::v1::RAGStreamEventKind kind, const std::string* token,
                    const runanywhere::v1::RAGResult* result, rac_result_t err_code,
                    const char* err_msg) {
        runanywhere::v1::RAGStreamEvent ev;
        ev.set_seq(seq++);
        ev.set_timestamp_us(now_ms() * 1000);
        ev.set_kind(kind);
        if (token != nullptr)
            ev.set_token(*token);
        if (result != nullptr)
            *ev.mutable_result() = *result;
        if (err_msg != nullptr && err_msg[0] != '\0') {
            ev.set_error_message(err_msg);
            ev.set_error_code(static_cast<int32_t>(err_code));
        }
        std::string bytes;
        if (ev.SerializeToString(&bytes)) {
            callback(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), user_data);
        }
    };

    auto on_token = [&](const std::string& tok) -> bool {
        emit(runanywhere::v1::RAG_STREAM_EVENT_KIND_TOKEN, &tok, nullptr, RAC_SUCCESS, nullptr);
        // Cancellation is driven by rac_rag_cancel_proto() latching the pipeline's
        // atomic; the graph stops between phases, so on_token always continues.
        return true;
    };

    runanywhere::v1::RAGResult proto;
    std::string err_msg;
    const rac_result_t status = execute_rag_query(s, query_proto, on_token, &proto, &err_msg);
    if (status != RAC_SUCCESS) {
        emit(runanywhere::v1::RAG_STREAM_EVENT_KIND_ERROR, nullptr, nullptr, status,
             err_msg.empty() ? rac_error_message(status) : err_msg.c_str());
        return status;
    }
    emit(runanywhere::v1::RAG_STREAM_EVENT_KIND_COMPLETED, nullptr, &proto, RAC_SUCCESS, nullptr);
    return RAC_SUCCESS;
#endif
}

rac_result_t rac_rag_cancel_proto(rac_handle_t session) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    const auto s = acquire_session(session);
    if (!s || !s->backend)
        return RAC_ERROR_COMPONENT_NOT_READY;
    return s->backend->cancel_query();
#endif
}

rac_result_t rac_rag_stats_proto(rac_handle_t session, rac_proto_buffer_t* out_stats) {
    if (!out_stats)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session;
    return feature_unavailable(out_stats);
#else
    const auto s = acquire_session(session);
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
    const auto s = acquire_session(session);
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
