/**
 * @file test_advanced_modality_proto_abi.cpp
 * @brief Focused proto-byte ABI tests for advanced modality service boundaries.
 */

#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/lora/rac_lora_service.h"
#include "rac/features/rag/rac_rag_pipeline.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_lora_registry.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "diffusion_options.pb.h"
#include "embeddings_options.pb.h"
#include "lora_options.pb.h"
#include "rag.pb.h"
#include "sdk_events.pb.h"
#include "vlm_options.pb.h"
#endif

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                                    \
    do {                                                                                      \
        ++test_count;                                                                         \
        if (!(cond)) {                                                                        \
            ++fail_count;                                                                     \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) - %s\n", label, __FILE__, __LINE__,      \
                         #cond);                                                             \
        } else {                                                                              \
            std::fprintf(stdout, "  ok:   %s\n", label);                                     \
        }                                                                                     \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

struct DummyVlm {
    int cancel_count{0};
};

struct DummyEmbeddings {
    int embed_count{0};
};

struct DummyDiffusion {
    int cancel_count{0};
};

struct DummyLlm {
    int load_lora_count{0};
    int remove_lora_count{0};
    int clear_lora_count{0};
};

std::string g_last_vlm_create_model;
std::string g_last_vlm_create_config;

bool serialize(const google::protobuf::MessageLite& message, std::vector<uint8_t>* out) {
    out->resize(message.ByteSizeLong());
    return out->empty() ||
           message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

template <typename T>
bool parse_buffer(const rac_proto_buffer_t& buffer, T* out) {
    return buffer.status == RAC_SUCCESS &&
           out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

bool poll_event(runanywhere::v1::SDKEvent* out) {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    const rac_result_t rc = rac_sdk_event_poll(&buffer);
    if (rc != RAC_SUCCESS) return false;
    const bool ok = out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
    rac_proto_buffer_free(&buffer);
    return ok;
}

bool poll_capability(runanywhere::v1::CapabilityOperationEventKind kind) {
    for (int i = 0; i < 32; ++i) {
        runanywhere::v1::SDKEvent event;
        if (!poll_event(&event)) return false;
        if (event.has_capability() && event.capability().kind() == kind) return true;
    }
    return false;
}

std::filesystem::path temp_root(const char* name) {
    auto root = std::filesystem::temp_directory_path() /
                ("rac-advanced-modality-" + std::string(name));
    std::filesystem::remove_all(root);
    std::filesystem::create_directories(root);
    return root;
}

void write_file(const std::filesystem::path& path, const std::string& contents) {
    std::ofstream out(path, std::ios::binary);
    out.write(contents.data(), static_cast<std::streamsize>(contents.size()));
}

rac_result_t dummy_vlm_create(const char* model_id, const char* config_json, void** out_impl) {
    if (!out_impl) return RAC_ERROR_NULL_POINTER;
    auto* impl = new DummyVlm();
    g_last_vlm_create_model = model_id ? model_id : "";
    g_last_vlm_create_config = config_json ? config_json : "";
    *out_impl = impl;
    return RAC_SUCCESS;
}

rac_result_t dummy_vlm_initialize(void*, const char*, const char*) {
    return RAC_SUCCESS;
}

rac_result_t dummy_vlm_process(void*, const rac_vlm_image_t* image, const char* prompt,
                               const rac_vlm_options_t*, rac_vlm_result_t* out_result) {
    if (!image || !prompt || !out_result) return RAC_ERROR_NULL_POINTER;
    std::string text = std::string("vlm:") + prompt;
    out_result->text = rac_strdup(text.c_str());
    out_result->prompt_tokens = 2;
    out_result->completion_tokens = 3;
    out_result->total_tokens = 5;
    out_result->total_time_ms = 7;
    out_result->tokens_per_second = 42.0f;
    return out_result->text ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

rac_result_t dummy_vlm_stream(void*, const rac_vlm_image_t*, const char*,
                              const rac_vlm_options_t*, rac_vlm_stream_callback_fn callback,
                              void* user_data) {
    if (!callback) return RAC_ERROR_NULL_POINTER;
    if (callback("hello", user_data) != RAC_TRUE) return RAC_ERROR_CANCELLED;
    if (callback(" vision", user_data) != RAC_TRUE) return RAC_ERROR_CANCELLED;
    return RAC_SUCCESS;
}

rac_result_t dummy_vlm_cancel(void* impl) {
    static_cast<DummyVlm*>(impl)->cancel_count += 1;
    return RAC_SUCCESS;
}

void dummy_vlm_destroy(void* impl) {
    delete static_cast<DummyVlm*>(impl);
}

rac_result_t fill_embeddings(const char* const* texts, size_t count,
                             rac_embeddings_result_t* out_result) {
    if (!texts || !out_result) return RAC_ERROR_NULL_POINTER;
    constexpr size_t kDim = 3;
    out_result->embeddings = static_cast<rac_embedding_vector_t*>(
        rac_alloc(sizeof(rac_embedding_vector_t) * count));
    if (!out_result->embeddings) return RAC_ERROR_OUT_OF_MEMORY;
    std::memset(out_result->embeddings, 0, sizeof(rac_embedding_vector_t) * count);
    out_result->num_embeddings = count;
    out_result->dimension = kDim;
    out_result->processing_time_ms = 4;
    out_result->total_tokens = static_cast<int32_t>(count);
    for (size_t i = 0; i < count; ++i) {
        out_result->embeddings[i].dimension = kDim;
        out_result->embeddings[i].data = static_cast<float*>(rac_alloc(sizeof(float) * kDim));
        if (!out_result->embeddings[i].data) return RAC_ERROR_OUT_OF_MEMORY;
        out_result->embeddings[i].data[0] = 1.0f;
        out_result->embeddings[i].data[1] = 0.0f;
        out_result->embeddings[i].data[2] = 0.0f;
    }
    return RAC_SUCCESS;
}

rac_result_t dummy_embeddings_create(const char*, const char*, void** out_impl) {
    if (!out_impl) return RAC_ERROR_NULL_POINTER;
    *out_impl = new DummyEmbeddings();
    return RAC_SUCCESS;
}

rac_result_t dummy_embeddings_initialize(void*, const char*) {
    return RAC_SUCCESS;
}

rac_result_t dummy_embeddings_embed(void* impl, const char* text,
                                    const rac_embeddings_options_t*,
                                    rac_embeddings_result_t* out_result) {
    static_cast<DummyEmbeddings*>(impl)->embed_count += 1;
    const char* texts[] = {text};
    return fill_embeddings(texts, 1, out_result);
}

rac_result_t dummy_embeddings_embed_batch(void* impl, const char* const* texts,
                                          size_t count, const rac_embeddings_options_t*,
                                          rac_embeddings_result_t* out_result) {
    static_cast<DummyEmbeddings*>(impl)->embed_count += static_cast<int>(count);
    return fill_embeddings(texts, count, out_result);
}

void dummy_embeddings_destroy(void* impl) {
    delete static_cast<DummyEmbeddings*>(impl);
}

rac_result_t dummy_diffusion_generate(void*, const rac_diffusion_options_t* options,
                                      rac_diffusion_result_t* out_result) {
    if (!options || !out_result) return RAC_ERROR_NULL_POINTER;
    out_result->image_size = 4;
    out_result->image_data = static_cast<uint8_t*>(rac_alloc(out_result->image_size));
    if (!out_result->image_data) return RAC_ERROR_OUT_OF_MEMORY;
    out_result->image_data[0] = 1;
    out_result->image_data[1] = 2;
    out_result->image_data[2] = 3;
    out_result->image_data[3] = 4;
    out_result->width = options->width;
    out_result->height = options->height;
    out_result->seed_used = options->seed;
    out_result->generation_time_ms = 9;
    out_result->safety_flagged = RAC_FALSE;
    return RAC_SUCCESS;
}

rac_result_t dummy_diffusion_progress(void* impl, const rac_diffusion_options_t* options,
                                      rac_diffusion_progress_callback_fn callback,
                                      void* user_data,
                                      rac_diffusion_result_t* out_result) {
    if (callback) {
        rac_diffusion_progress_t progress = {};
        progress.progress = 0.5f;
        progress.current_step = 1;
        progress.total_steps = 2;
        progress.stage = "Denoising";
        if (callback(&progress, user_data) != RAC_TRUE) return RAC_ERROR_CANCELLED;
    }
    return dummy_diffusion_generate(impl, options, out_result);
}

rac_result_t dummy_diffusion_cancel(void* impl) {
    static_cast<DummyDiffusion*>(impl)->cancel_count += 1;
    return RAC_SUCCESS;
}

rac_result_t dummy_llm_create(const char*, const char*, void** out_impl) {
    if (!out_impl) return RAC_ERROR_NULL_POINTER;
    *out_impl = new DummyLlm();
    return RAC_SUCCESS;
}

rac_result_t dummy_llm_initialize(void*, const char*) {
    return RAC_SUCCESS;
}

rac_result_t dummy_llm_generate(void*, const char*, const rac_llm_options_t*,
                                rac_llm_result_t* out_result) {
    out_result->text = rac_strdup("mock answer");
    out_result->completion_tokens = 2;
    out_result->total_tokens = 2;
    return out_result->text ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

rac_result_t dummy_llm_stream(void*, const char*, const rac_llm_options_t*,
                              rac_llm_stream_callback_fn callback, void* user_data) {
    if (!callback) return RAC_ERROR_NULL_POINTER;
    if (callback("mock ", user_data) != RAC_TRUE) return RAC_ERROR_CANCELLED;
    if (callback("answer", user_data) != RAC_TRUE) return RAC_ERROR_CANCELLED;
    return RAC_SUCCESS;
}

rac_result_t dummy_lora_load(void* impl, const char*, float) {
    static_cast<DummyLlm*>(impl)->load_lora_count += 1;
    return RAC_SUCCESS;
}

rac_result_t dummy_lora_remove(void* impl, const char*) {
    static_cast<DummyLlm*>(impl)->remove_lora_count += 1;
    return RAC_SUCCESS;
}

rac_result_t dummy_lora_clear(void* impl) {
    static_cast<DummyLlm*>(impl)->clear_lora_count += 1;
    return RAC_SUCCESS;
}

void dummy_llm_destroy(void* impl) {
    delete static_cast<DummyLlm*>(impl);
}

rac_vlm_service_ops_t make_vlm_ops() {
    rac_vlm_service_ops_t ops{};
    ops.initialize = dummy_vlm_initialize;
    ops.process = dummy_vlm_process;
    ops.process_stream = dummy_vlm_stream;
    ops.cancel = dummy_vlm_cancel;
    ops.destroy = dummy_vlm_destroy;
    ops.create = dummy_vlm_create;
    return ops;
}

rac_embeddings_service_ops_t make_embedding_ops() {
    rac_embeddings_service_ops_t ops{};
    ops.initialize = dummy_embeddings_initialize;
    ops.embed = dummy_embeddings_embed;
    ops.embed_batch = dummy_embeddings_embed_batch;
    ops.destroy = dummy_embeddings_destroy;
    ops.create = dummy_embeddings_create;
    return ops;
}

rac_llm_service_ops_t make_llm_ops(bool supports_lora) {
    rac_llm_service_ops_t ops{};
    ops.initialize = dummy_llm_initialize;
    ops.generate = dummy_llm_generate;
    ops.generate_stream = dummy_llm_stream;
    ops.destroy = dummy_llm_destroy;
    ops.create = dummy_llm_create;
    if (supports_lora) {
        ops.load_lora = dummy_lora_load;
        ops.remove_lora = dummy_lora_remove;
        ops.clear_lora = dummy_lora_clear;
    }
    return ops;
}

rac_engine_vtable_t make_vtable(const char* name, const rac_llm_service_ops_t* llm_ops,
                                const rac_embeddings_service_ops_t* embedding_ops,
                                const rac_vlm_service_ops_t* vlm_ops) {
    rac_engine_vtable_t v{};
    v.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    v.metadata.name = name;
    v.metadata.display_name = name;
    v.metadata.engine_version = "0.0.0";
    v.metadata.priority = 10000;
    v.llm_ops = llm_ops;
    v.embedding_ops = embedding_ops;
    v.vlm_ops = vlm_ops;
    return v;
}

int test_missing_component_and_parse_error() {
    runanywhere::v1::EmbeddingsRequest request;
    request.add_texts("hello");
    std::vector<uint8_t> request_bytes;
    CHECK(serialize(request, &request_bytes), "embeddings request serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_embeddings_embed_batch_proto(
        nullptr, request_bytes.data(), request_bytes.size(), &out);
    CHECK(rc == RAC_ERROR_COMPONENT_NOT_READY,
          "missing embeddings component returns component-not-ready");
    CHECK(out.status == RAC_ERROR_COMPONENT_NOT_READY,
          "missing embeddings component marks buffer error");
    rac_proto_buffer_free(&out);

    DummyVlm impl;
    rac_vlm_service_ops_t vlm_ops = make_vlm_ops();
    rac_vlm_service_t service{&vlm_ops, &impl, "mock-vlm"};
    const uint8_t bad[] = {0xff, 0xff, 0xff};
    rac_proto_buffer_init(&out);
    rc = rac_vlm_process_proto(&service, bad, sizeof(bad), bad, sizeof(bad), &out);
    CHECK(rc == RAC_ERROR_DECODING_ERROR, "invalid VLM request returns decoding error");
    CHECK(out.status == RAC_ERROR_DECODING_ERROR, "invalid VLM request marks buffer error");
    rac_proto_buffer_free(&out);
    return 0;
}

struct StreamCapture {
    std::vector<std::vector<uint8_t>> events;
};

rac_bool_t vlm_stream_capture(const uint8_t* bytes, size_t size, void* user_data) {
    auto* capture = static_cast<StreamCapture*>(user_data);
    capture->events.emplace_back(bytes, bytes + size);
    return RAC_TRUE;
}

int test_vlm_process_stream_events() {
    rac_sdk_event_clear_queue();
    DummyVlm impl;
    rac_vlm_service_ops_t ops = make_vlm_ops();
    rac_vlm_service_t service{&ops, &impl, "mock-vlm"};

    runanywhere::v1::VLMImage image;
    image.set_file_path("/tmp/test-image.png");
    image.set_format(runanywhere::v1::VLM_IMAGE_FORMAT_FILE_PATH);
    runanywhere::v1::VLMGenerationOptions options;
    options.set_prompt("describe");
    options.set_max_tokens(16);
    std::vector<uint8_t> image_bytes;
    std::vector<uint8_t> options_bytes;
    CHECK(serialize(image, &image_bytes), "VLMImage serializes");
    CHECK(serialize(options, &options_bytes), "VLMGenerationOptions serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_vlm_process_proto(&service, image_bytes.data(), image_bytes.size(),
                                            options_bytes.data(), options_bytes.size(), &out);
    runanywhere::v1::VLMResult result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &result), "VLM process returns VLMResult");
    CHECK(result.text() == "vlm:describe", "VLM process preserves prompt path");
    CHECK(poll_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED),
          "VLM process emits started capability event");
    CHECK(poll_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED),
          "VLM process emits completed capability event");
    rac_proto_buffer_free(&out);

    rac_sdk_event_clear_queue();
    StreamCapture capture;
    rac_proto_buffer_init(&out);
    rc = rac_vlm_process_stream_proto(&service, image_bytes.data(), image_bytes.size(),
                                      options_bytes.data(), options_bytes.size(),
                                      vlm_stream_capture, &capture, &out);
    runanywhere::v1::VLMResult stream_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &stream_result),
          "VLM stream returns aggregate VLMResult");
    CHECK(stream_result.text() == "hello vision", "VLM stream aggregates tokens");
    CHECK(capture.events.size() == 2, "VLM stream callback receives token events");
    runanywhere::v1::SDKEvent token_event;
    CHECK(token_event.ParseFromArray(capture.events[0].data(),
                                     static_cast<int>(capture.events[0].size())) &&
              token_event.has_generation(),
          "VLM stream callback receives SDKEvent generation payload");
    rac_proto_buffer_free(&out);

    CHECK(rac_vlm_cancel_proto(&service) == RAC_SUCCESS, "VLM cancel proto succeeds");
    CHECK(impl.cancel_count == 1, "VLM cancel dispatches backend cancel");
    return 0;
}

int test_vlm_companion_resolution() {
    auto root = temp_root("vlm");
    auto model_path = root / "model.gguf";
    auto mmproj_path = root / "mmproj-model.gguf";
    write_file(model_path, "GGUFmodel");
    write_file(mmproj_path, "GGUFmmproj");

    rac_vlm_service_ops_t vlm_ops = make_vlm_ops();
    rac_engine_vtable_t vlm_vtable = make_vtable("llamacpp_vlm", nullptr, nullptr, &vlm_ops);
    (void)rac_plugin_unregister("llamacpp_vlm");
    CHECK(rac_plugin_register(&vlm_vtable) == RAC_SUCCESS, "VLM companion test plugin registers");

    rac_model_info_t model{};
    model.id = const_cast<char*>("advanced.vlm");
    model.name = const_cast<char*>("Advanced VLM");
    model.category = RAC_MODEL_CATEGORY_MULTIMODAL;
    model.format = RAC_MODEL_FORMAT_GGUF;
    model.framework = RAC_FRAMEWORK_LLAMACPP;
    std::string root_string = root.string();
    model.local_path = const_cast<char*>(root_string.c_str());
    CHECK(rac_register_model(&model) == RAC_SUCCESS, "VLM model registers globally");

    rac_handle_t handle = nullptr;
    g_last_vlm_create_model.clear();
    g_last_vlm_create_config.clear();
    CHECK(rac_vlm_create("advanced.vlm", &handle) == RAC_SUCCESS && handle != nullptr,
          "VLM create succeeds through plugin route");
    CHECK(g_last_vlm_create_model == model_path.string(),
          "VLM create passes resolved primary model path");
    CHECK(g_last_vlm_create_config.find(mmproj_path.string()) != std::string::npos,
          "VLM create passes resolved mmproj_path in config_json");
    rac_vlm_destroy(handle);
    (void)rac_plugin_unregister("llamacpp_vlm");
    return 0;
}

int test_embeddings_mocked_result() {
    rac_sdk_event_clear_queue();
    DummyEmbeddings impl;
    rac_embeddings_service_ops_t ops = make_embedding_ops();
    rac_embeddings_service_t service{&ops, &impl, "mock-embeddings"};

    runanywhere::v1::EmbeddingsRequest request;
    request.add_texts("alpha");
    request.add_texts("beta");
    request.mutable_options()->set_normalize(true);
    std::vector<uint8_t> bytes;
    CHECK(serialize(request, &bytes), "EmbeddingsRequest serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc =
        rac_embeddings_embed_batch_proto(&service, bytes.data(), bytes.size(), &out);
    runanywhere::v1::EmbeddingsResult result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &result),
          "embeddings proto returns EmbeddingsResult");
    CHECK(result.vectors_size() == 2, "embeddings result has one vector per text");
    CHECK(result.dimension() == 3, "embeddings result carries dimension");
    CHECK(result.vectors(0).text() == "alpha", "embeddings result preserves text ordering");
    CHECK(result.vectors(0).values_size() == 3 && result.vectors(0).values(0) == 1.0f,
          "embeddings result carries mocked values");
    CHECK(poll_capability(
              runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_STARTED),
          "embeddings emits started capability event");
    CHECK(poll_capability(
              runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_COMPLETED),
          "embeddings emits completed capability event");
    rac_proto_buffer_free(&out);
    return 0;
}

struct ProgressCapture {
    std::vector<std::vector<uint8_t>> progress;
};

rac_bool_t diffusion_progress_capture(const uint8_t* bytes, size_t size, void* user_data) {
    auto* capture = static_cast<ProgressCapture*>(user_data);
    capture->progress.emplace_back(bytes, bytes + size);
    return RAC_TRUE;
}

int test_diffusion_progress_cancel_and_unsupported() {
    DummyDiffusion impl;
    rac_diffusion_service_ops_t ops{};
    ops.generate = dummy_diffusion_generate;
    ops.generate_with_progress = dummy_diffusion_progress;
    ops.cancel = dummy_diffusion_cancel;
    rac_diffusion_service_t service{&ops, &impl, "mock-diffusion"};

    runanywhere::v1::DiffusionGenerationOptions options;
    options.set_prompt("a test image");
    options.set_width(32);
    options.set_height(32);
    options.set_num_inference_steps(2);
    options.set_seed(123);
    std::vector<uint8_t> bytes;
    CHECK(serialize(options, &bytes), "DiffusionGenerationOptions serializes");

    ProgressCapture capture;
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_diffusion_generate_with_progress_proto(
        &service, bytes.data(), bytes.size(), diffusion_progress_capture, &capture, &out);
    runanywhere::v1::DiffusionResult result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &result),
          "diffusion progress proto returns DiffusionResult");
    CHECK(result.image_data().size() == 4, "diffusion result carries image bytes");
    CHECK(capture.progress.size() == 1, "diffusion progress callback receives event");
    runanywhere::v1::DiffusionProgress progress;
    CHECK(progress.ParseFromArray(capture.progress[0].data(),
                                  static_cast<int>(capture.progress[0].size())) &&
              progress.current_step() == 1,
          "diffusion progress bytes decode");
    rac_proto_buffer_free(&out);

    CHECK(rac_diffusion_cancel_proto(&service) == RAC_SUCCESS,
          "diffusion cancel proto succeeds");
    CHECK(impl.cancel_count == 1, "diffusion cancel dispatches backend cancel");

    rac_diffusion_service_ops_t unsupported_ops{};
    rac_diffusion_service_t unsupported_service{&unsupported_ops, &impl, "unsupported"};
    rac_proto_buffer_init(&out);
    rc = rac_diffusion_generate_proto(&unsupported_service, bytes.data(), bytes.size(), &out);
    CHECK(rc == RAC_ERROR_NOT_SUPPORTED,
          "unsupported diffusion backend returns typed C ABI error");
    CHECK(out.status == RAC_ERROR_NOT_SUPPORTED,
          "unsupported diffusion backend marks proto buffer error");
    rac_proto_buffer_free(&out);
    return 0;
}

int test_rag_ingest_query_mocked_path() {
    rac_embeddings_service_ops_t embedding_ops = make_embedding_ops();
    rac_llm_service_ops_t llm_ops = make_llm_ops(/*supports_lora=*/true);
    rac_engine_vtable_t onnx = make_vtable("onnx", nullptr, &embedding_ops, nullptr);
    rac_engine_vtable_t llamacpp = make_vtable("llamacpp", &llm_ops, nullptr, nullptr);
    (void)rac_plugin_unregister("onnx");
    (void)rac_plugin_unregister("llamacpp");
    CHECK(rac_plugin_register(&onnx) == RAC_SUCCESS, "RAG embeddings plugin registers");
    CHECK(rac_plugin_register(&llamacpp) == RAC_SUCCESS, "RAG LLM plugin registers");

    runanywhere::v1::RAGConfiguration config;
    config.set_embedding_model_path("/tmp/mock-embeddings.onnx");
    config.set_llm_model_path("/tmp/mock-llm.gguf");
    config.set_embedding_dimension(3);
    config.set_top_k(1);
    config.set_similarity_threshold(0.0f);
    config.set_chunk_size(256);
    config.set_chunk_overlap(0);
    std::vector<uint8_t> config_bytes;
    CHECK(serialize(config, &config_bytes), "RAGConfiguration serializes");

    rac_handle_t session = nullptr;
    CHECK(rac_rag_session_create_proto(config_bytes.data(), config_bytes.size(), &session) ==
              RAC_SUCCESS &&
              session != nullptr,
          "RAG session creates from proto");

    runanywhere::v1::RAGDocument document;
    document.set_id("doc-1");
    document.set_text("RunAnywhere centralizes RAG ingestion and querying in C++.");
    (*document.mutable_metadata())["section"] = "unit-test";
    std::vector<uint8_t> document_bytes;
    CHECK(serialize(document, &document_bytes), "RAGDocument serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc =
        rac_rag_ingest_proto(session, document_bytes.data(), document_bytes.size(), &out);
    runanywhere::v1::RAGStatistics stats;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &stats), "RAG ingest returns statistics");
    CHECK(stats.indexed_chunks() >= 1, "RAG ingest indexes chunks");
    rac_proto_buffer_free(&out);

    runanywhere::v1::RAGQueryOptions query;
    query.set_question("Where does RAG live?");
    query.set_max_tokens(32);
    std::vector<uint8_t> query_bytes;
    CHECK(serialize(query, &query_bytes), "RAGQueryOptions serializes");
    rac_proto_buffer_init(&out);
    rc = rac_rag_query_proto(session, query_bytes.data(), query_bytes.size(), &out);
    runanywhere::v1::RAGResult result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &result), "RAG query returns RAGResult");
    CHECK(result.answer() == "mock answer", "RAG query uses mocked LLM path");
    CHECK(result.retrieved_chunks_size() >= 1, "RAG query returns retrieved chunks");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    CHECK(rac_rag_clear_proto(session, &out) == RAC_SUCCESS, "RAG clear succeeds");
    rac_proto_buffer_free(&out);
    rac_rag_session_destroy_proto(session);
    (void)rac_plugin_unregister("onnx");
    (void)rac_plugin_unregister("llamacpp");
    return 0;
}

int test_lora_register_compat_load_remove_clear() {
    auto root = temp_root("lora");
    auto adapter_path = root / "adapter.gguf";
    write_file(adapter_path, "GGUFadapter");

    rac_lora_registry_handle_t registry = nullptr;
    CHECK(rac_lora_registry_create(&registry) == RAC_SUCCESS && registry != nullptr,
          "LoRA registry creates");
    runanywhere::v1::LoraAdapterCatalogEntry entry;
    entry.set_id("style.adapter");
    entry.set_name("Style Adapter");
    entry.set_filename("adapter.gguf");
    entry.add_compatible_models("mock-llm");
    std::vector<uint8_t> entry_bytes;
    CHECK(serialize(entry, &entry_bytes), "LoRA catalog entry serializes");
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_lora_register_proto(registry, entry_bytes.data(),
                                              entry_bytes.size(), &out);
    runanywhere::v1::LoraAdapterCatalogEntry registered;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &registered),
          "LoRA register returns catalog entry");
    CHECK(registered.id() == "style.adapter", "LoRA register preserves id");
    rac_proto_buffer_free(&out);
    rac_lora_registry_destroy(registry);

    rac_llm_service_ops_t llm_ops = make_llm_ops(/*supports_lora=*/true);
    rac_engine_vtable_t llamacpp = make_vtable("llamacpp", &llm_ops, nullptr, nullptr);
    (void)rac_plugin_unregister("llamacpp");
    CHECK(rac_plugin_register(&llamacpp) == RAC_SUCCESS, "LoRA-capable plugin registers");

    rac_handle_t component = nullptr;
    CHECK(rac_llm_component_create(&component) == RAC_SUCCESS && component != nullptr,
          "LLM component creates for LoRA");
    CHECK(rac_llm_component_load_model(component, "/tmp/mock-llm.gguf", "mock-llm",
                                       "Mock LLM") == RAC_SUCCESS,
          "LLM component loads mocked model");

    runanywhere::v1::LoRAAdapterConfig config;
    config.set_adapter_path(adapter_path.string());
    config.set_adapter_id("style.adapter");
    config.set_scale(0.5f);
    std::vector<uint8_t> config_bytes;
    CHECK(serialize(config, &config_bytes), "LoRAAdapterConfig serializes");

    rac_proto_buffer_init(&out);
    rc = rac_lora_compatibility_proto(component, config_bytes.data(), config_bytes.size(), &out);
    runanywhere::v1::LoraCompatibilityResult compat;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &compat), "LoRA compatibility returns result");
    CHECK(compat.is_compatible(), "LoRA compatibility succeeds for capable backend");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    rc = rac_lora_load_proto(component, config_bytes.data(), config_bytes.size(), &out);
    runanywhere::v1::LoRAAdapterInfo info;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &info), "LoRA load returns adapter info");
    CHECK(info.applied() && info.adapter_path() == adapter_path.string(),
          "LoRA load marks adapter applied");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    CHECK(rac_lora_remove_proto(component, config_bytes.data(), config_bytes.size(), &out) ==
              RAC_SUCCESS,
          "LoRA remove succeeds");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    CHECK(rac_lora_clear_proto(component, &out) == RAC_SUCCESS, "LoRA clear succeeds");
    rac_proto_buffer_free(&out);
    rac_llm_component_destroy(component);
    (void)rac_plugin_unregister("llamacpp");

    rac_llm_service_ops_t no_lora_ops = make_llm_ops(/*supports_lora=*/false);
    rac_engine_vtable_t no_lora = make_vtable("llamacpp", &no_lora_ops, nullptr, nullptr);
    CHECK(rac_plugin_register(&no_lora) == RAC_SUCCESS, "non-LoRA plugin registers");
    component = nullptr;
    CHECK(rac_llm_component_create(&component) == RAC_SUCCESS && component != nullptr,
          "LLM component creates for unsupported LoRA check");
    CHECK(rac_llm_component_load_model(component, "/tmp/mock-llm.gguf", "mock-llm",
                                       "Mock LLM") == RAC_SUCCESS,
          "LLM component loads non-LoRA model");
    rac_proto_buffer_init(&out);
    rc = rac_lora_compatibility_proto(component, config_bytes.data(), config_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &compat),
          "unsupported LoRA compatibility still returns generated result");
    CHECK(!compat.is_compatible() &&
              compat.error_message().find("Backend does not support") != std::string::npos,
          "unsupported LoRA reports typed incompatibility");
    rac_proto_buffer_free(&out);
    rac_llm_component_destroy(component);
    (void)rac_plugin_unregister("llamacpp");
    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_advanced_modality_proto_abi\n");

#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: advanced modality proto ABI tests (no protobuf)\n");
    return 0;
#else
    test_missing_component_and_parse_error();
    test_vlm_process_stream_events();
    test_vlm_companion_resolution();
    test_embeddings_mocked_result();
    test_diffusion_progress_cancel_and_unsupported();
    test_rag_ingest_query_mocked_path();
    test_lora_register_compat_load_remove_clear();

    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
