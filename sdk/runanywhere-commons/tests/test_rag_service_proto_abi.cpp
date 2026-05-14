/**
 * @file test_rag_service_proto_abi.cpp
 * @brief Descriptor coverage for the generated logical RAG service contract.
 */

#include <cstdio>

#if defined(RAC_HAVE_PROTOBUF)
#include "rag.pb.h"

#include <google/protobuf/descriptor.h>
#endif

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                                       \
    do {                                                                                         \
        ++test_count;                                                                            \
        if (cond) {                                                                              \
            std::fprintf(stdout, "  ok:   %s\n", label);                                         \
        } else {                                                                                 \
            ++fail_count;                                                                        \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) - %s\n", label, __FILE__, __LINE__, #cond); \
        }                                                                                        \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

void check_unary_rpc(const google::protobuf::ServiceDescriptor* service, const char* method_name,
                     const char* input_type, const char* output_type) {
    const google::protobuf::MethodDescriptor* method = service->FindMethodByName(method_name);
    CHECK(method != nullptr, method_name);
    if (!method)
        return;

    CHECK(method->input_type()->full_name() == input_type, "RAG unary RPC input type");
    CHECK(method->output_type()->full_name() == output_type, "RAG unary RPC output type");
    CHECK(!(method->client_streaming() || method->server_streaming()), "RAG RPC is unary");
}

int test_rag_generated_service_contract() {
    const google::protobuf::FileDescriptor* file =
        runanywhere::v1::RAGConfiguration::descriptor()->file();
    const google::protobuf::ServiceDescriptor* service = file->FindServiceByName("RAG");
    CHECK(service != nullptr, "generated RAG service descriptor exists");
    if (!service)
        return 0;

    CHECK(service->method_count() == 7, "generated RAG service exposes seven RPCs");

    check_unary_rpc(service, "Create", "runanywhere.v1.RAGConfiguration",
                    "runanywhere.v1.RAGServiceState");
    check_unary_rpc(service, "Ingest", "runanywhere.v1.RAGIngestRequest",
                    "runanywhere.v1.RAGIngestResult");
    check_unary_rpc(service, "Query", "runanywhere.v1.RAGQueryRequest", "runanywhere.v1.RAGResult");
    check_unary_rpc(service, "Search", "runanywhere.v1.RAGQueryRequest",
                    "runanywhere.v1.RAGResult");
    check_unary_rpc(service, "Stats", "runanywhere.v1.RAGServiceState",
                    "runanywhere.v1.RAGStatistics");
    check_unary_rpc(service, "Clear", "runanywhere.v1.RAGServiceState",
                    "runanywhere.v1.RAGServiceState");

    const google::protobuf::MethodDescriptor* stream = service->FindMethodByName("Stream");
    CHECK(stream != nullptr, "RAG Stream RPC exists");
    if (stream) {
        CHECK(stream->input_type()->full_name() == "runanywhere.v1.RAGQueryRequest",
              "Stream accepts RAGQueryRequest");
        CHECK(stream->output_type()->full_name() == "runanywhere.v1.RAGStreamEvent",
              "Stream returns RAGStreamEvent");
        CHECK(!stream->client_streaming(), "Stream is not client-streaming");
        CHECK(stream->server_streaming(), "Stream is server-streaming");
    }

    // D-6: RAGConfiguration carries *model ids*, not filesystem paths. Guard
    // against an accidental schema regression by asserting the id fields
    // exist and the old path fields are gone.
    const google::protobuf::Descriptor* rag_config =
        runanywhere::v1::RAGConfiguration::descriptor();
    CHECK(rag_config->FindFieldByName("embedding_model_id") != nullptr,
          "RAGConfiguration has embedding_model_id");
    CHECK(rag_config->FindFieldByName("llm_model_id") != nullptr,
          "RAGConfiguration has llm_model_id");
    CHECK(rag_config->FindFieldByName("reranker_model_id") != nullptr,
          "RAGConfiguration has reranker_model_id");
    CHECK(rag_config->FindFieldByName("embedding_model_path") == nullptr,
          "RAGConfiguration no longer carries embedding_model_path");
    CHECK(rag_config->FindFieldByName("llm_model_path") == nullptr,
          "RAGConfiguration no longer carries llm_model_path");
    CHECK(rag_config->FindFieldByName("reranker_model_path") == nullptr,
          "RAGConfiguration no longer carries reranker_model_path");

    const google::protobuf::Descriptor* result = runanywhere::v1::RAGResult::descriptor();
    const google::protobuf::FieldDescriptor* retrieved_chunks =
        result->FindFieldByName("retrieved_chunks");
    CHECK(retrieved_chunks != nullptr, "RAGResult carries retrieved chunks");
    if (retrieved_chunks) {
        CHECK(retrieved_chunks->is_repeated(), "RAGResult retrieved_chunks are repeated");
        CHECK(retrieved_chunks->message_type()->full_name() == "runanywhere.v1.RAGSearchResult",
              "RAGResult retrieved_chunks use RAGSearchResult");
    }

    const google::protobuf::Descriptor* ingest = runanywhere::v1::RAGIngestRequest::descriptor();
    const google::protobuf::FieldDescriptor* documents = ingest->FindFieldByName("documents");
    CHECK(documents != nullptr, "RAGIngestRequest carries documents");
    if (documents) {
        CHECK(documents->is_repeated(), "RAGIngestRequest documents are repeated");
        CHECK(documents->message_type()->full_name() == "runanywhere.v1.RAGDocument",
              "RAGIngestRequest documents use RAGDocument");
    }

    const google::protobuf::Descriptor* event = runanywhere::v1::RAGStreamEvent::descriptor();
    const google::protobuf::FieldDescriptor* chunk = event->FindFieldByName("chunk");
    CHECK(chunk != nullptr, "RAG stream event has chunk field");
    if (chunk) {
        CHECK(chunk->message_type()->full_name() == "runanywhere.v1.RAGSearchResult",
              "RAG stream chunk field uses RAGSearchResult");
        CHECK(chunk->has_presence(), "RAG stream chunk field has presence");
    }

    const google::protobuf::FieldDescriptor* terminal_result = event->FindFieldByName("result");
    CHECK(terminal_result != nullptr, "RAG stream event has terminal result field");
    if (terminal_result) {
        CHECK(terminal_result->message_type()->full_name() == "runanywhere.v1.RAGResult",
              "RAG stream result field uses RAGResult");
        CHECK(terminal_result->has_presence(), "RAG stream result field has presence");
    }

    const google::protobuf::EnumDescriptor* kind = file->FindEnumTypeByName("RAGStreamEventKind");
    CHECK(kind != nullptr, "RAG stream event kind enum exists");
    if (kind) {
        CHECK(kind->FindValueByName("RAG_STREAM_EVENT_KIND_RETRIEVAL_STARTED") != nullptr,
              "RAG stream supports retrieval-started events");
        CHECK(kind->FindValueByName("RAG_STREAM_EVENT_KIND_CHUNK_RETRIEVED") != nullptr,
              "RAG stream supports chunk-retrieved events");
        CHECK(kind->FindValueByName("RAG_STREAM_EVENT_KIND_CONTEXT_READY") != nullptr,
              "RAG stream supports context-ready events");
        CHECK(kind->FindValueByName("RAG_STREAM_EVENT_KIND_TOKEN") != nullptr,
              "RAG stream supports token events");
        CHECK(kind->FindValueByName("RAG_STREAM_EVENT_KIND_COMPLETED") != nullptr,
              "RAG stream supports completion events");
        CHECK(kind->FindValueByName("RAG_STREAM_EVENT_KIND_ERROR") != nullptr,
              "RAG stream supports error events");
    }

    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_rag_service_proto_abi\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: RAG service proto ABI tests (no protobuf)\n");
    return 0;
#else
    test_rag_generated_service_contract();
    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
