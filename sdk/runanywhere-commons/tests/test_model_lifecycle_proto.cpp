/**
 * @file test_model_lifecycle_proto.cpp
 * @brief Proto-byte model lifecycle ABI tests.
 */

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"
#include "sdk_events.pb.h"
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

int g_create_count = 0;
int g_initialize_count = 0;
int g_cleanup_count = 0;
int g_destroy_count = 0;

struct DummyLlm {
    std::string model_path;
    bool initialized{false};
};

rac_result_t dummy_llm_create(const char* model_id, const char*, void** out_impl) {
    if (!model_id || !out_impl) return RAC_ERROR_NULL_POINTER;
    auto* impl = new DummyLlm();
    impl->model_path = model_id;
    *out_impl = impl;
    ++g_create_count;
    return RAC_SUCCESS;
}

rac_result_t dummy_llm_initialize(void* impl, const char* model_path) {
    if (!impl || !model_path) return RAC_ERROR_NULL_POINTER;
    auto* dummy = static_cast<DummyLlm*>(impl);
    dummy->initialized = true;
    dummy->model_path = model_path;
    ++g_initialize_count;
    return RAC_SUCCESS;
}

rac_result_t dummy_llm_cleanup(void*) {
    ++g_cleanup_count;
    return RAC_SUCCESS;
}

void dummy_llm_destroy(void* impl) {
    ++g_destroy_count;
    delete static_cast<DummyLlm*>(impl);
}

bool serialize(const google::protobuf::MessageLite& message, std::vector<uint8_t>* out) {
    out->resize(message.ByteSizeLong());
    if (out->empty()) return true;
    return message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

template <typename T>
bool parse_buffer(const rac_proto_buffer_t& buffer, T* out) {
    return buffer.status == RAC_SUCCESS &&
           out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

bool poll_sdk_event(runanywhere::v1::SDKEvent* out) {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    const rac_result_t rc = rac_sdk_event_poll(&buffer);
    if (rc != RAC_SUCCESS) {
        return false;
    }
    const bool ok = out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
    rac_proto_buffer_free(&buffer);
    return ok;
}

bool poll_component_event(runanywhere::v1::ComponentLifecycleState expected_state) {
    for (int i = 0; i < 16; ++i) {
        runanywhere::v1::SDKEvent event;
        if (!poll_sdk_event(&event)) return false;
        if (event.has_component_lifecycle() &&
            event.component_lifecycle().current_state() == expected_state) {
            return true;
        }
    }
    return false;
}

runanywhere::v1::ModelInfo build_llm_model() {
    runanywhere::v1::ModelInfo model;
    model.set_id("lifecycle.llm");
    model.set_name("Lifecycle LLM");
    model.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    model.set_format(runanywhere::v1::MODEL_FORMAT_GGUF);
    model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    model.set_local_path("/tmp/lifecycle-test.gguf");
    model.set_is_downloaded(true);
    model.set_is_available(true);
    return model;
}

bool register_model(rac_model_registry_handle_t registry,
                    const runanywhere::v1::ModelInfo& model) {
    std::vector<uint8_t> bytes;
    return serialize(model, &bytes) &&
           rac_model_registry_register_proto(
               registry, bytes.empty() ? nullptr : bytes.data(), bytes.size()) == RAC_SUCCESS;
}

rac_engine_vtable_t make_dummy_llm_vtable(rac_llm_service_ops_t* ops,
                                          const uint32_t* formats) {
    rac_engine_vtable_t v{};
    v.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    v.metadata.name = "llamacpp";
    v.metadata.display_name = "dummy llama.cpp";
    v.metadata.engine_version = "0.0.0";
    v.metadata.priority = 100;
    v.metadata.formats = formats;
    v.metadata.formats_count = 1;
    v.llm_ops = ops;
    return v;
}

int test_parse_error(rac_model_registry_handle_t registry) {
    const uint8_t invalid[] = {0xff, 0xff, 0xff};
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc =
        rac_model_lifecycle_load_proto(registry, invalid, sizeof(invalid), &out);
    CHECK(rc == RAC_ERROR_DECODING_ERROR, "invalid load request returns decoding error");
    CHECK(out.status == RAC_ERROR_DECODING_ERROR, "invalid load request marks buffer error");
    rac_proto_buffer_free(&out);
    return 0;
}

int test_model_missing(rac_model_registry_handle_t registry) {
    runanywhere::v1::ModelLoadRequest request;
    request.set_model_id("missing.model");
    std::vector<uint8_t> bytes;
    CHECK(serialize(request, &bytes), "missing-model request serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc =
        rac_model_lifecycle_load_proto(registry, bytes.data(), bytes.size(), &out);
    runanywhere::v1::ModelLoadResult result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &result),
          "missing model returns parsable ModelLoadResult");
    CHECK(!result.success(), "missing model reports success=false");
    CHECK(result.error_message().find("not found") != std::string::npos,
          "missing model carries error message");
    rac_proto_buffer_free(&out);
    return 0;
}

int test_unsupported_route(rac_model_registry_handle_t registry) {
    CHECK(register_model(registry, build_llm_model()), "unsupported-route model registers");

    runanywhere::v1::ModelLoadRequest request;
    request.set_model_id("lifecycle.llm");
    request.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_ONNX);
    std::vector<uint8_t> bytes;
    CHECK(serialize(request, &bytes), "unsupported-route request serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc =
        rac_model_lifecycle_load_proto(registry, bytes.data(), bytes.size(), &out);
    runanywhere::v1::ModelLoadResult result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &result),
          "unsupported route returns parsable ModelLoadResult");
    CHECK(!result.success(), "unsupported route reports success=false");
    CHECK(result.error_message().find("route") != std::string::npos,
          "unsupported route carries route error");
    rac_proto_buffer_free(&out);
    rac_model_lifecycle_reset();
    return 0;
}

int test_success_current_snapshot_unload_events(rac_model_registry_handle_t registry) {
    g_create_count = g_initialize_count = g_cleanup_count = g_destroy_count = 0;
    rac_model_lifecycle_reset();
    rac_sdk_event_clear_queue();

    rac_llm_service_ops_t ops{};
    ops.create = dummy_llm_create;
    ops.initialize = dummy_llm_initialize;
    ops.cleanup = dummy_llm_cleanup;
    ops.destroy = dummy_llm_destroy;

    const uint32_t formats[] = {
        static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_GGUF)};
    auto vtable = make_dummy_llm_vtable(&ops, formats);
    CHECK(rac_plugin_register(&vtable) == RAC_SUCCESS, "dummy lifecycle plugin registers");
    CHECK(register_model(registry, build_llm_model()), "load-success model registers");

    runanywhere::v1::ModelLoadRequest load;
    load.set_model_id("lifecycle.llm");
    std::vector<uint8_t> load_bytes;
    CHECK(serialize(load, &load_bytes), "load request serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc =
        rac_model_lifecycle_load_proto(registry, load_bytes.data(), load_bytes.size(), &out);
    runanywhere::v1::ModelLoadResult load_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &load_result),
          "successful load returns parsable ModelLoadResult");
    CHECK(load_result.success(), "successful load reports success=true");
    CHECK(load_result.model_id() == "lifecycle.llm", "successful load preserves model id");
    CHECK(load_result.resolved_path() == "/tmp/lifecycle-test.gguf",
          "successful load resolves registry local path");
    CHECK(g_create_count == 1 && g_initialize_count == 1,
          "successful load calls backend create and initialize");
    rac_proto_buffer_free(&out);
    CHECK(poll_component_event(runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY),
          "successful load emits ready lifecycle event");

    runanywhere::v1::CurrentModelRequest current;
    std::vector<uint8_t> current_bytes;
    CHECK(serialize(current, &current_bytes), "empty current request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_model_lifecycle_current_model_proto(
        current_bytes.empty() ? nullptr : current_bytes.data(), current_bytes.size(), &out);
    runanywhere::v1::CurrentModelResult current_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &current_result),
          "current model returns parsable CurrentModelResult");
    CHECK(current_result.model_id() == "lifecycle.llm", "current model reports loaded id");
    CHECK(current_result.has_model(), "current model embeds ModelInfo");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    rc = rac_component_lifecycle_snapshot_proto(
        static_cast<uint32_t>(runanywhere::v1::SDK_COMPONENT_LLM), &out);
    runanywhere::v1::ComponentLifecycleSnapshot snapshot;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &snapshot),
          "snapshot returns parsable ComponentLifecycleSnapshot");
    CHECK(snapshot.state() == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY,
          "snapshot reports ready state");
    CHECK(snapshot.model_id() == "lifecycle.llm", "snapshot reports loaded model id");
    rac_proto_buffer_free(&out);

    runanywhere::v1::ModelUnloadRequest unload;
    unload.set_model_id("lifecycle.llm");
    std::vector<uint8_t> unload_bytes;
    CHECK(serialize(unload, &unload_bytes), "unload request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_model_lifecycle_unload_proto(unload_bytes.data(), unload_bytes.size(), &out);
    runanywhere::v1::ModelUnloadResult unload_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &unload_result),
          "unload returns parsable ModelUnloadResult");
    CHECK(unload_result.success(), "unload reports success=true");
    CHECK(unload_result.unloaded_model_ids_size() == 1 &&
              unload_result.unloaded_model_ids(0) == "lifecycle.llm",
          "unload reports unloaded id");
    CHECK(g_cleanup_count == 1 && g_destroy_count == 1,
          "unload calls backend cleanup and destroy");
    rac_proto_buffer_free(&out);
    CHECK(poll_component_event(runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED),
          "unload emits not-loaded lifecycle event");

    rac_proto_buffer_init(&out);
    rc = rac_component_lifecycle_snapshot_proto(
        static_cast<uint32_t>(runanywhere::v1::SDK_COMPONENT_LLM), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &snapshot),
          "post-unload snapshot parses");
    CHECK(snapshot.state() == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
          "post-unload snapshot reports not loaded");
    rac_proto_buffer_free(&out);

    rac_plugin_unregister("llamacpp");
    rac_model_lifecycle_reset();
    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_model_lifecycle_proto\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: model lifecycle proto tests (no protobuf)\n");
    return 0;
#else
    rac_model_registry_handle_t registry = nullptr;
    CHECK(rac_model_registry_create(&registry) == RAC_SUCCESS && registry != nullptr,
          "model registry creates");

    test_parse_error(registry);
    test_model_missing(registry);
    test_unsupported_route(registry);
    test_success_current_snapshot_unload_events(registry);

    rac_model_registry_destroy(registry);
    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
