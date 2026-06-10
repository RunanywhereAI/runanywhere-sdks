/**
 * @file test_embeddings_service_proto_abi.cpp
 * @brief Descriptor coverage for the generated logical Embeddings service contract.
 */

#include <cstdio>

#if defined(RAC_HAVE_PROTOBUF)
#include "embeddings_options.pb.h"

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

void check_embeddings_rpc(const google::protobuf::ServiceDescriptor* service,
                          const char* method_name) {
    const google::protobuf::MethodDescriptor* method = service->FindMethodByName(method_name);
    CHECK(method != nullptr, method_name);
    if (!method)
        return;

    CHECK(method->input_type()->full_name() == "runanywhere.v1.EmbeddingsRequest",
          "Embeddings RPC accepts EmbeddingsRequest");
    CHECK(method->output_type()->full_name() == "runanywhere.v1.EmbeddingsResult",
          "Embeddings RPC returns EmbeddingsResult");
    CHECK(!(method->client_streaming() || method->server_streaming()), "Embeddings RPC is unary");
}

int test_embeddings_generated_service_contract() {
    const google::protobuf::FileDescriptor* file =
        runanywhere::v1::EmbeddingsRequest::descriptor()->file();
    const google::protobuf::ServiceDescriptor* service = file->FindServiceByName("Embeddings");
    CHECK(service != nullptr, "generated Embeddings service descriptor exists");
    if (!service)
        return 0;

    CHECK(service->method_count() == 2, "generated Embeddings service exposes two RPCs");
    check_embeddings_rpc(service, "Embed");
    check_embeddings_rpc(service, "EmbedBatch");

    const google::protobuf::Descriptor* request = runanywhere::v1::EmbeddingsRequest::descriptor();
    const google::protobuf::FieldDescriptor* texts = request->FindFieldByName("texts");
    CHECK(texts != nullptr, "EmbeddingsRequest carries input texts");
    if (texts) {
        CHECK(texts->is_repeated(), "EmbeddingsRequest texts are repeated");
        CHECK(texts->type() == google::protobuf::FieldDescriptor::TYPE_STRING,
              "EmbeddingsRequest texts are strings");
    }

    const google::protobuf::FieldDescriptor* options = request->FindFieldByName("options");
    CHECK(options != nullptr, "EmbeddingsRequest carries options");
    if (options) {
        CHECK(options->message_type()->full_name() == "runanywhere.v1.EmbeddingsOptions",
              "EmbeddingsRequest options use EmbeddingsOptions");
        CHECK(options->has_presence(), "EmbeddingsRequest options field has presence");
    }

    const google::protobuf::Descriptor* result = runanywhere::v1::EmbeddingsResult::descriptor();
    const google::protobuf::FieldDescriptor* vectors = result->FindFieldByName("vectors");
    CHECK(vectors != nullptr, "EmbeddingsResult carries embedding vectors");
    if (vectors) {
        CHECK(vectors->is_repeated(), "EmbeddingsResult vectors are repeated");
        CHECK(vectors->message_type()->full_name() == "runanywhere.v1.EmbeddingVector",
              "EmbeddingsResult vectors use EmbeddingVector");
    }

    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_embeddings_service_proto_abi\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: Embeddings service proto ABI tests (no protobuf)\n");
    return 0;
#else
    test_embeddings_generated_service_contract();
    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
