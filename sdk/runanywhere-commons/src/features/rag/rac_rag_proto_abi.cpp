/**
 * @file rac_rag_proto_abi.cpp
 * @brief Proto-byte C ABI for RAG sessions.
 */

#include "rac/features/rag/rac_rag_pipeline.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_adapters.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "rag.pb.h"
#include "sdk_events.pb.h"
#endif

namespace {

#if defined(RAC_HAVE_PROTOBUF)

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

std::string event_id() {
    static std::atomic<uint64_t> counter{0};
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%lld-%llu",
                  static_cast<long long>(now_ms()),
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

rac_result_t copy_proto(const google::protobuf::MessageLite& message,
                        rac_proto_buffer_t* out) {
    if (!out) return RAC_ERROR_NULL_POINTER;
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 &&
        !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize proto result");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
}

void publish_event(const runanywhere::v1::SDKEvent& event) {
    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 &&
        event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        (void)rac_sdk_event_publish_proto(bytes.empty() ? nullptr : bytes.data(), bytes.size());
    }
}

void publish_capability(runanywhere::v1::CapabilityOperationEventKind kind,
                        const char* operation, float progress, int64_t input_count,
                        int64_t output_count, const char* error) {
    runanywhere::v1::SDKEvent event;
    event.set_id(event_id());
    event.set_timestamp_ms(now_ms());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_RAG);
    event.set_severity(error && error[0] ? runanywhere::v1::EVENT_SEVERITY_ERROR
                                         : runanywhere::v1::EVENT_SEVERITY_INFO);
    event.set_component(runanywhere::v1::SDK_COMPONENT_RAG);
    event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    auto* cap = event.mutable_capability();
    cap->set_kind(kind);
    cap->set_component(runanywhere::v1::SDK_COMPONENT_RAG);
    if (operation) cap->set_operation(operation);
    cap->set_progress(progress);
    cap->set_input_count(input_count);
    cap->set_output_count(output_count);
    if (error) cap->set_error(error);
    publish_event(event);
}

void publish_failure(rac_result_t code, const char* operation, const char* message) {
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_FAILED,
                       operation, 0.0f, 0, 0,
                       message && message[0] ? message : rac_error_message(code));
    (void)rac_sdk_event_publish_failure(code, message, "rag", operation, RAC_TRUE);
}

void free_rag_config(rac_rag_config_t* config) {
    if (!config) return;
    rac_free(const_cast<char*>(config->embedding_model_path));
    rac_free(const_cast<char*>(config->llm_model_path));
    rac_free(const_cast<char*>(config->prompt_template));
    rac_free(const_cast<char*>(config->embedding_config_json));
    rac_free(const_cast<char*>(config->llm_config_json));
    *config = rac_rag_config_default();
}

void free_rag_query(rac_rag_query_t* query) {
    if (!query) return;
    rac_free(const_cast<char*>(query->question));
    rac_free(const_cast<char*>(query->system_prompt));
    std::memset(query, 0, sizeof(*query));
}

runanywhere::v1::RAGStatistics make_stats(rac_rag_pipeline_t* pipeline) {
    runanywhere::v1::RAGStatistics out;
    const int64_t chunks = static_cast<int64_t>(rac_rag_get_document_count(pipeline));
    out.set_indexed_documents(chunks);
    out.set_indexed_chunks(chunks);
    out.set_last_updated_ms(now_ms());

    char* stats_json = nullptr;
    if (rac_rag_get_statistics(pipeline, &stats_json) == RAC_SUCCESS && stats_json) {
        try {
            auto stats = nlohmann::json::parse(stats_json);
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
    }
    rac_free(stats_json);
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
                                          size_t config_proto_size,
                                          rac_handle_t* out_session) {
    if (!out_session) return RAC_ERROR_NULL_POINTER;
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

    rac_rag_config_t config = rac_rag_config_default();
    if (!rac::foundation::rac_rag_config_from_proto(proto, &config) ||
        !config.embedding_model_path ||
        config.embedding_model_path[0] == '\0') {
        free_rag_config(&config);
        publish_failure(RAC_ERROR_INVALID_ARGUMENT, "rag.sessionCreate",
                        "RAGConfiguration.embedding_model_path is required");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_rag_pipeline_t* pipeline = nullptr;
    rac_result_t rc = rac_rag_pipeline_create_standalone(&config, &pipeline);
    free_rag_config(&config);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "rag.sessionCreate", rac_error_message(rc));
        return rc;
    }
    *out_session = reinterpret_cast<rac_handle_t>(pipeline);
    return RAC_SUCCESS;
#endif
}

void rac_rag_session_destroy_proto(rac_handle_t session) {
    rac_rag_pipeline_destroy(reinterpret_cast<rac_rag_pipeline_t*>(session));
}

rac_result_t rac_rag_ingest_proto(rac_handle_t session,
                                  const uint8_t* document_proto_bytes,
                                  size_t document_proto_size,
                                  rac_proto_buffer_t* out_stats) {
    if (!out_stats) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session;
    (void)document_proto_bytes;
    (void)document_proto_size;
    return feature_unavailable(out_stats);
#else
    auto* pipeline = reinterpret_cast<rac_rag_pipeline_t*>(session);
    if (!pipeline) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "rag.ingest",
                        "RAG session is not loaded");
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
    if (document.has_metadata_json() && !document.metadata_json().empty()) {
        try {
            auto legacy = nlohmann::json::parse(document.metadata_json());
            if (legacy.is_object()) {
                metadata.update(legacy);
            } else {
                metadata["metadata_json"] = document.metadata_json();
            }
        } catch (...) {
            metadata["metadata_json"] = document.metadata_json();
        }
    }
    for (const auto& item : document.metadata()) {
        metadata[item.first] = item.second;
    }
    const std::string metadata_json = metadata.dump();

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_STARTED,
                       "rag.ingest", 0.0f, 1, 0, nullptr);
    rac_result_t rc = rac_rag_add_document(pipeline, document.text().c_str(),
                                           metadata_json.c_str());
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "rag.ingest", rac_error_message(rc));
        return rac_proto_buffer_set_error(out_stats, rc, rac_error_message(rc));
    }

    auto stats = make_stats(pipeline);
    rc = copy_proto(stats, out_stats);
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_COMPLETED,
                       "rag.ingest", 1.0f, 1, stats.indexed_chunks(), nullptr);
    return rc;
#endif
}

rac_result_t rac_rag_query_proto(rac_handle_t session,
                                 const uint8_t* query_proto_bytes,
                                 size_t query_proto_size,
                                 rac_proto_buffer_t* out_result) {
    if (!out_result) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session;
    (void)query_proto_bytes;
    (void)query_proto_size;
    return feature_unavailable(out_result);
#else
    auto* pipeline = reinterpret_cast<rac_rag_pipeline_t*>(session);
    if (!pipeline) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "rag.query",
                        "RAG session is not loaded");
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

    rac_rag_query_t query = {};
    if (!rac::foundation::rac_rag_query_from_proto(query_proto, &query) || !query.question ||
        query.question[0] == '\0') {
        free_rag_query(&query);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "RAGQueryOptions.question is required");
    }

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_STARTED,
                       "rag.query", 0.0f, 1, 0, nullptr);
    rac_rag_result_t result = {};
    rac_result_t rc = rac_rag_query(pipeline, &query, &result);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "rag.query", rac_error_message(rc));
        free_rag_query(&query);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::RAGResult proto;
    if (!rac::foundation::rac_rag_result_to_proto(&result, &proto)) {
        rc = rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                        "failed to encode RAGResult");
    } else {
        rc = copy_proto(proto, out_result);
    }
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_COMPLETED,
                       "rag.query", 1.0f, 1, proto.retrieved_chunks_size(), nullptr);
    rac_rag_result_free(&result);
    free_rag_query(&query);
    return rc;
#endif
}

rac_result_t rac_rag_stats_proto(rac_handle_t session, rac_proto_buffer_t* out_stats) {
    if (!out_stats) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session;
    return feature_unavailable(out_stats);
#else
    auto* pipeline = reinterpret_cast<rac_rag_pipeline_t*>(session);
    if (!pipeline) {
        return rac_proto_buffer_set_error(out_stats, RAC_ERROR_COMPONENT_NOT_READY,
                                          "RAG session is not loaded");
    }
    return copy_proto(make_stats(pipeline), out_stats);
#endif
}

rac_result_t rac_rag_clear_proto(rac_handle_t session, rac_proto_buffer_t* out_stats) {
    if (!out_stats) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session;
    return feature_unavailable(out_stats);
#else
    auto* pipeline = reinterpret_cast<rac_rag_pipeline_t*>(session);
    if (!pipeline) {
        return rac_proto_buffer_set_error(out_stats, RAC_ERROR_COMPONENT_NOT_READY,
                                          "RAG session is not loaded");
    }
    rac_result_t rc = rac_rag_clear_documents(pipeline);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "rag.clear", rac_error_message(rc));
        return rac_proto_buffer_set_error(out_stats, rc, rac_error_message(rc));
    }
    return copy_proto(make_stats(pipeline), out_stats);
#endif
}

}  // extern "C"
