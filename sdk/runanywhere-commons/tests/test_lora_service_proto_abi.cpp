/**
 * @file test_lora_service_proto_abi.cpp
 * @brief Descriptor coverage for the generated logical LoRA service contract.
 */

#include <cstdio>
#include <string>
#include <vector>

#if defined(RAC_HAVE_PROTOBUF)
#include "lora_options.pb.h"
#include "model_types.pb.h"

#include <algorithm>
#include <google/protobuf/descriptor.h>
#include <ranges>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/lora/rac_lora_service.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_plugin_entry.h"
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

struct DummyLlm {
    int load_lora_count{0};
    int remove_lora_count{0};
    int clear_lora_count{0};
    std::vector<std::string> loaded_paths;
    std::vector<float> loaded_scales;
};

bool serialize(const google::protobuf::MessageLite& message, std::vector<uint8_t>* out) {
    out->resize(message.ByteSizeLong());
    return out->empty() || message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

template <typename T>
bool parse_buffer(const rac_proto_buffer_t& buffer, T* out) {
    return buffer.status == RAC_SUCCESS &&
           out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

rac_result_t dummy_llm_create(const char*, const char*, void** out_impl) {
    if (!out_impl)
        return RAC_ERROR_NULL_POINTER;
    *out_impl = new DummyLlm();
    return *out_impl ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

rac_result_t dummy_llm_initialize(void*, const char*) {
    return RAC_SUCCESS;
}

rac_result_t dummy_llm_generate(void*, const char*, const rac_llm_options_t*, rac_llm_result_t*) {
    return RAC_SUCCESS;
}

rac_result_t dummy_llm_stream(void*, const char*, const rac_llm_options_t*,
                              rac_llm_stream_callback_fn, void*) {
    return RAC_SUCCESS;
}

rac_result_t dummy_lora_load(void* impl, const char* adapter_path, float scale) {
    if (!adapter_path || adapter_path[0] == '\0')
        return RAC_ERROR_INVALID_ARGUMENT;
    auto* dummy = static_cast<DummyLlm*>(impl);
    dummy->load_lora_count += 1;
    auto existing = std::ranges::find(dummy->loaded_paths, adapter_path);
    if (existing != dummy->loaded_paths.end()) {
        const size_t index = static_cast<size_t>(existing - dummy->loaded_paths.begin());
        dummy->loaded_scales[index] = scale;
    } else {
        dummy->loaded_paths.emplace_back(adapter_path);
        dummy->loaded_scales.push_back(scale);
    }
    return RAC_SUCCESS;
}

rac_result_t dummy_lora_remove(void* impl, const char* adapter_path) {
    if (!adapter_path || adapter_path[0] == '\0')
        return RAC_ERROR_INVALID_ARGUMENT;
    auto* dummy = static_cast<DummyLlm*>(impl);
    auto existing = std::ranges::find(dummy->loaded_paths, adapter_path);
    if (existing == dummy->loaded_paths.end())
        return RAC_ERROR_NOT_FOUND;
    const auto index = existing - dummy->loaded_paths.begin();
    dummy->loaded_paths.erase(existing);
    dummy->loaded_scales.erase(dummy->loaded_scales.begin() + index);
    dummy->remove_lora_count += 1;
    return RAC_SUCCESS;
}

rac_result_t dummy_lora_clear(void* impl) {
    auto* dummy = static_cast<DummyLlm*>(impl);
    dummy->clear_lora_count += 1;
    dummy->loaded_paths.clear();
    dummy->loaded_scales.clear();
    return RAC_SUCCESS;
}

void dummy_llm_destroy(void* impl) {
    delete static_cast<DummyLlm*>(impl);
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

// GGUF metadata format markers — lifecycle routing inspects the registered
// ModelInfo.format to pick a compatible plugin, so every dummy vtable that
// participates in a lifecycle load must advertise the GGUF format.
const uint32_t g_lora_test_formats[] = {static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_GGUF)};

rac_engine_vtable_t make_vtable(const char* name, const rac_llm_service_ops_t* llm_ops) {
    rac_engine_vtable_t v{};
    v.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    v.metadata.name = name;
    v.metadata.display_name = name;
    v.metadata.engine_version = "0.0.0";
    v.metadata.priority = 10000;
    v.metadata.formats = g_lora_test_formats;
    v.metadata.formats_count = sizeof(g_lora_test_formats) / sizeof(g_lora_test_formats[0]);
    v.llm_ops = llm_ops;
    return v;
}

runanywhere::v1::ModelInfo build_lora_test_model(const std::string& id, const std::string& name) {
    runanywhere::v1::ModelInfo model;
    model.set_id(id);
    model.set_name(name);
    model.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    model.set_format(runanywhere::v1::MODEL_FORMAT_GGUF);
    model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    model.set_local_path("/tmp/" + id + ".gguf");
    model.set_supports_lora(true);
    model.set_is_downloaded(true);
    model.set_is_available(true);
    return model;
}

bool register_lora_test_model(rac_model_registry_handle_t registry,
                              const runanywhere::v1::ModelInfo& model) {
    std::vector<uint8_t> bytes;
    bytes.resize(model.ByteSizeLong());
    if (!bytes.empty() && !model.SerializeToArray(bytes.data(), static_cast<int>(bytes.size())))
        return false;
    return rac_model_registry_register_proto(registry, bytes.empty() ? nullptr : bytes.data(),
                                             bytes.size()) == RAC_SUCCESS;
}

bool register_lora_test_adapter(const std::string& adapter_id, const std::string& model_id) {
    const char* compatible_models[] = {model_id.c_str()};
    rac_lora_entry_t entry{};
    entry.id = const_cast<char*>(adapter_id.c_str());
    entry.name = const_cast<char*>(adapter_id.c_str());
    entry.compatible_model_ids = const_cast<char**>(compatible_models);
    entry.compatible_model_count = 1;
    return rac_lora_registry_register(rac_get_lora_registry(), &entry) == RAC_SUCCESS;
}

bool load_lora_test_model(rac_model_registry_handle_t registry, const std::string& model_id) {
    runanywhere::v1::ModelLoadRequest request;
    request.set_model_id(model_id);
    std::vector<uint8_t> bytes;
    bytes.resize(request.ByteSizeLong());
    if (!bytes.empty() && !request.SerializeToArray(bytes.data(), static_cast<int>(bytes.size())))
        return false;

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc =
        rac_model_lifecycle_load_proto(registry, bytes.data(), bytes.size(), &out);
    runanywhere::v1::ModelLoadResult result;
    const bool ok = rc == RAC_SUCCESS && out.status == RAC_SUCCESS &&
                    result.ParseFromArray(out.data, static_cast<int>(out.size)) && result.success();
    rac_proto_buffer_free(&out);
    return ok;
}

void lora_test_environment_reset() {
    rac_model_lifecycle_reset();
    rac_sdk_event_clear_queue();
    (void)rac_plugin_unregister("llamacpp");
}

void check_unary_rpc(const google::protobuf::ServiceDescriptor* service, const char* method_name,
                     const char* input_type, const char* output_type) {
    const google::protobuf::MethodDescriptor* method = service->FindMethodByName(method_name);
    CHECK(method != nullptr, method_name);
    if (!method)
        return;

    CHECK(method->input_type()->full_name() == input_type, "LoRA unary RPC input type");
    CHECK(method->output_type()->full_name() == output_type, "LoRA unary RPC output type");
    CHECK(!method->client_streaming() && !method->server_streaming(), "LoRA RPC is unary");
}

bool state_has_adapter(const runanywhere::v1::LoRAState& state, const std::string& adapter_id,
                       const std::string& adapter_path) {
    for (const auto& adapter : state.loaded_adapters()) {
        if (adapter.adapter_id() == adapter_id && adapter.adapter_path() == adapter_path &&
            adapter.applied()) {
            return true;
        }
    }
    return false;
}

runanywhere::v1::LoraAdapterCatalogEntry make_catalog_entry(const std::string& id,
                                                            const std::string& name,
                                                            const std::string& model_id,
                                                            const std::string& tag) {
    runanywhere::v1::LoraAdapterCatalogEntry entry;
    entry.set_id(id);
    entry.set_name(name);
    entry.set_description(name + " adapter");
    entry.set_url("https://example.test/" + id + ".gguf");
    entry.set_filename(id + ".gguf");
    entry.add_compatible_models(model_id);
    entry.set_size_bytes(100);
    entry.set_author("RunAnywhere");
    entry.set_default_scale(0.7f);
    entry.set_checksum_sha256("sha256:" + id);
    entry.add_tags(tag);
    (*entry.mutable_metadata())["source"] = "unit-test";
    return entry;
}

int test_lora_generated_service_contract() {
    const google::protobuf::FileDescriptor* file =
        runanywhere::v1::LoRAApplyRequest::descriptor()->file();
    const google::protobuf::ServiceDescriptor* service = file->FindServiceByName("LoRA");
    CHECK(service != nullptr, "generated LoRA service descriptor exists");
    if (!service)
        return 0;

    CHECK(service->method_count() == 10, "generated LoRA service exposes ten RPCs");

    check_unary_rpc(service, "RegisterCatalogEntry", "runanywhere.v1.LoraAdapterCatalogEntry",
                    "runanywhere.v1.LoraAdapterCatalogEntry");
    check_unary_rpc(service, "ListCatalog", "runanywhere.v1.LoraAdapterCatalogListRequest",
                    "runanywhere.v1.LoraAdapterCatalogListResult");
    check_unary_rpc(service, "QueryCatalog", "runanywhere.v1.LoraAdapterCatalogQuery",
                    "runanywhere.v1.LoraAdapterCatalogListResult");
    check_unary_rpc(service, "GetCatalogEntry", "runanywhere.v1.LoraAdapterCatalogGetRequest",
                    "runanywhere.v1.LoraAdapterCatalogGetResult");
    check_unary_rpc(service, "MarkDownloadCompleted",
                    "runanywhere.v1.LoraAdapterDownloadCompletedRequest",
                    "runanywhere.v1.LoraAdapterDownloadCompletedResult");
    check_unary_rpc(service, "Apply", "runanywhere.v1.LoRAApplyRequest",
                    "runanywhere.v1.LoRAApplyResult");
    check_unary_rpc(service, "Remove", "runanywhere.v1.LoRARemoveRequest",
                    "runanywhere.v1.LoRAState");
    check_unary_rpc(service, "CheckCompatibility", "runanywhere.v1.LoRAAdapterConfig",
                    "runanywhere.v1.LoraCompatibilityResult");
    check_unary_rpc(service, "List", "runanywhere.v1.LoRAState", "runanywhere.v1.LoRAState");
    check_unary_rpc(service, "State", "runanywhere.v1.LoRAState", "runanywhere.v1.LoRAState");

    const google::protobuf::Descriptor* apply = runanywhere::v1::LoRAApplyRequest::descriptor();
    const google::protobuf::FieldDescriptor* adapters = apply->FindFieldByName("adapters");
    CHECK(adapters != nullptr, "LoRAApplyRequest carries adapters");
    if (adapters) {
        CHECK(adapters->is_repeated(), "LoRAApplyRequest adapters are repeated");
        CHECK(adapters->message_type()->full_name() == "runanywhere.v1.LoRAAdapterConfig",
              "LoRAApplyRequest adapters use LoRAAdapterConfig");
    }

    const google::protobuf::Descriptor* remove = runanywhere::v1::LoRARemoveRequest::descriptor();
    const google::protobuf::FieldDescriptor* adapter_ids = remove->FindFieldByName("adapter_ids");
    CHECK(adapter_ids != nullptr, "LoRARemoveRequest carries adapter ids");
    if (adapter_ids) {
        CHECK(adapter_ids->is_repeated(), "LoRARemoveRequest adapter ids are repeated");
        CHECK(adapter_ids->type() == google::protobuf::FieldDescriptor::TYPE_STRING,
              "LoRARemoveRequest adapter ids are strings");
    }

    const google::protobuf::Descriptor* state = runanywhere::v1::LoRAState::descriptor();
    const google::protobuf::FieldDescriptor* loaded = state->FindFieldByName("loaded_adapters");
    CHECK(loaded != nullptr, "LoRAState carries loaded adapters");
    if (loaded) {
        CHECK(loaded->is_repeated(), "LoRAState loaded adapters are repeated");
        CHECK(loaded->message_type()->full_name() == "runanywhere.v1.LoRAAdapterInfo",
              "LoRAState loaded adapters use LoRAAdapterInfo");
    }

    const google::protobuf::FieldDescriptor* base_model = state->FindFieldByName("base_model_id");
    CHECK(base_model != nullptr, "LoRAState carries base model id");
    if (base_model) {
        CHECK(base_model->has_presence(), "LoRAState base model id has presence");
    }

    const google::protobuf::Descriptor* compat =
        runanywhere::v1::LoraCompatibilityResult::descriptor();
    const google::protobuf::FieldDescriptor* warnings = compat->FindFieldByName("warnings");
    CHECK(warnings != nullptr, "LoraCompatibilityResult carries warnings");
    if (warnings) {
        CHECK(warnings->is_repeated(), "LoraCompatibilityResult warnings are repeated");
        CHECK(warnings->type() == google::protobuf::FieldDescriptor::TYPE_STRING,
              "LoraCompatibilityResult warnings are strings");
    }

    const google::protobuf::Descriptor* catalog_entry =
        runanywhere::v1::LoraAdapterCatalogEntry::descriptor();
    const google::protobuf::FieldDescriptor* local_path =
        catalog_entry->FindFieldByName("local_path");
    CHECK(local_path != nullptr, "LoraAdapterCatalogEntry carries local path");
    if (local_path) {
        CHECK(local_path->has_presence(), "LoraAdapterCatalogEntry local path has presence");
    }
    const google::protobuf::FieldDescriptor* is_downloaded =
        catalog_entry->FindFieldByName("is_downloaded");
    CHECK(is_downloaded != nullptr, "LoraAdapterCatalogEntry carries downloaded state");
    if (is_downloaded) {
        CHECK(is_downloaded->has_presence(),
              "LoraAdapterCatalogEntry downloaded state has presence");
    }

    const google::protobuf::Descriptor* catalog_result =
        runanywhere::v1::LoraAdapterCatalogListResult::descriptor();
    const google::protobuf::FieldDescriptor* entries = catalog_result->FindFieldByName("entries");
    CHECK(entries != nullptr, "LoraAdapterCatalogListResult carries entries");
    if (entries) {
        CHECK(entries->is_repeated(), "LoraAdapterCatalogListResult entries are repeated");
        CHECK(entries->message_type()->full_name() == "runanywhere.v1.LoraAdapterCatalogEntry",
              "LoraAdapterCatalogListResult entries use catalog entry");
    }

    return 0;
}

int test_generated_lora_catalog_register_list_query_get_and_completion() {
    rac_lora_registry_handle_t registry = nullptr;
    CHECK(rac_lora_registry_create(&registry) == RAC_SUCCESS && registry != nullptr,
          "LoRA catalog registry creates");

    runanywhere::v1::LoraAdapterCatalogEntry style =
        make_catalog_entry("style", "Style", "model-a", "style");
    style.add_compatible_models("model-b");
    style.set_local_path("/tmp/should-not-persist.gguf");
    style.set_is_downloaded(true);
    style.set_downloaded_at_unix_ms(100);
    std::vector<uint8_t> style_bytes;
    CHECK(serialize(style, &style_bytes), "LoRA catalog style entry serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc =
        rac_lora_register_proto(registry, style_bytes.data(), style_bytes.size(), &out);
    runanywhere::v1::LoraAdapterCatalogEntry registered_style;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &registered_style),
          "LoRA catalog register returns canonical entry");
    CHECK(registered_style.id() == "style", "LoRA catalog register preserves id");
    CHECK(registered_style.default_scale() > 0.69f && registered_style.default_scale() < 0.71f,
          "LoRA catalog register preserves default scale");
    CHECK(!registered_style.has_local_path(), "LoRA catalog register scrubs incoming local path");
    CHECK(!registered_style.has_is_downloaded(),
          "LoRA catalog register scrubs incoming downloaded state");
    rac_proto_buffer_free(&out);

    runanywhere::v1::LoraAdapterCatalogEntry tone =
        make_catalog_entry("tone", "Tone", "model-b", "voice");
    std::vector<uint8_t> tone_bytes;
    CHECK(serialize(tone, &tone_bytes), "LoRA catalog tone entry serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_register_proto(registry, tone_bytes.data(), tone_bytes.size(), &out);
    runanywhere::v1::LoraAdapterCatalogEntry registered_tone;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &registered_tone),
          "LoRA catalog second register returns canonical entry");
    rac_proto_buffer_free(&out);

    runanywhere::v1::LoraAdapterCatalogListRequest list_request;
    list_request.set_include_counts(true);
    std::vector<uint8_t> list_bytes;
    CHECK(serialize(list_request, &list_bytes), "LoRA catalog list request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_catalog_list_proto(registry, list_bytes.data(), list_bytes.size(), &out);
    runanywhere::v1::LoraAdapterCatalogListResult list_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &list_result),
          "LoRA catalog list returns list result");
    CHECK(list_result.success(), "LoRA catalog list succeeds");
    CHECK(list_result.entries_size() == 2, "LoRA catalog list returns all entries");
    CHECK(list_result.total_count() == 2, "LoRA catalog list reports total count");
    CHECK(list_result.downloaded_count() == 0,
          "LoRA catalog list reports no downloaded entries before completion");
    rac_proto_buffer_free(&out);

    runanywhere::v1::LoraAdapterCatalogQuery query;
    query.set_model_id("model-a");
    std::vector<uint8_t> query_bytes;
    CHECK(serialize(query, &query_bytes), "LoRA catalog query request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_catalog_query_proto(registry, query_bytes.data(), query_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &list_result),
          "LoRA catalog query by model returns list result");
    CHECK(list_result.entries_size() == 1 && list_result.entries(0).id() == "style",
          "LoRA catalog query by model filters compatible adapters");
    rac_proto_buffer_free(&out);

    runanywhere::v1::LoraAdapterCatalogGetRequest get_request;
    get_request.set_adapter_id("tone");
    std::vector<uint8_t> get_bytes;
    CHECK(serialize(get_request, &get_bytes), "LoRA catalog get request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_catalog_get_proto(registry, get_bytes.data(), get_bytes.size(), &out);
    runanywhere::v1::LoraAdapterCatalogGetResult get_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &get_result),
          "LoRA catalog get returns get result");
    CHECK(get_result.found() && get_result.entry().id() == "tone",
          "LoRA catalog get returns entry by id");
    rac_proto_buffer_free(&out);

    runanywhere::v1::LoraAdapterDownloadCompletedRequest completed;
    completed.set_adapter_id("style");
    completed.set_local_path("/models/lora/style.gguf");
    completed.set_size_bytes(1234);
    completed.set_checksum_sha256("sha256:downloaded-style");
    completed.set_completed_at_unix_ms(9999);
    completed.set_status_message("ready");
    std::vector<uint8_t> completed_bytes;
    CHECK(serialize(completed, &completed_bytes), "LoRA catalog completion request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_catalog_mark_download_completed_proto(registry, completed_bytes.data(),
                                                        completed_bytes.size(), &out);
    runanywhere::v1::LoraAdapterDownloadCompletedResult completed_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &completed_result),
          "LoRA catalog completion returns result");
    CHECK(completed_result.success() && completed_result.persisted(),
          "LoRA catalog completion persists state");
    CHECK(completed_result.entry().local_path() == "/models/lora/style.gguf",
          "LoRA catalog completion stores local path");
    CHECK(completed_result.entry().is_downloaded(), "LoRA catalog completion marks downloaded");
    CHECK(completed_result.entry().downloaded_at_unix_ms() == 9999,
          "LoRA catalog completion stores completion time");
    CHECK(completed_result.entry().size_bytes() == 1234, "LoRA catalog completion updates size");
    CHECK(completed_result.entry().checksum_sha256() == "sha256:downloaded-style",
          "LoRA catalog completion updates checksum");
    rac_proto_buffer_free(&out);

    query.Clear();
    query.set_downloaded_only(true);
    CHECK(serialize(query, &query_bytes), "LoRA catalog downloaded query serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_catalog_query_proto(registry, query_bytes.data(), query_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &list_result),
          "LoRA catalog downloaded query returns list result");
    CHECK(list_result.entries_size() == 1 && list_result.entries(0).id() == "style",
          "LoRA catalog downloaded query sees completed adapter");
    CHECK(list_result.entries(0).local_path() == "/models/lora/style.gguf",
          "LoRA catalog downloaded query returns persisted path");
    rac_proto_buffer_free(&out);

    style.set_name("Style Updated");
    style.set_local_path("/tmp/should-still-not-persist.gguf");
    style.set_is_downloaded(false);
    CHECK(serialize(style, &style_bytes), "LoRA catalog updated style serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_register_proto(registry, style_bytes.data(), style_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &registered_style),
          "LoRA catalog metadata update returns entry");
    CHECK(registered_style.name() == "Style Updated",
          "LoRA catalog metadata update persists metadata");
    CHECK(registered_style.local_path() == "/models/lora/style.gguf",
          "LoRA catalog metadata update preserves completion path");
    CHECK(registered_style.is_downloaded(),
          "LoRA catalog metadata update preserves downloaded state");
    rac_proto_buffer_free(&out);

    rac_lora_registry_destroy(registry);
    return 0;
}

int test_generated_lora_catalog_negative_errors() {
    runanywhere::v1::LoraAdapterCatalogListRequest list_request;
    std::vector<uint8_t> list_bytes;
    CHECK(serialize(list_request, &list_bytes), "LoRA negative list request serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc =
        rac_lora_catalog_list_proto(nullptr, list_bytes.data(), list_bytes.size(), &out);
    CHECK(rc == RAC_ERROR_NULL_POINTER && out.status == RAC_ERROR_NULL_POINTER,
          "LoRA catalog list requires registry");
    rac_proto_buffer_free(&out);

    rac_lora_registry_handle_t registry = nullptr;
    CHECK(rac_lora_registry_create(&registry) == RAC_SUCCESS && registry != nullptr,
          "LoRA negative registry creates");

    const uint8_t invalid[] = {0xff, 0xff, 0xff};
    rac_proto_buffer_init(&out);
    rc = rac_lora_catalog_query_proto(registry, invalid, sizeof(invalid), &out);
    CHECK(rc == RAC_ERROR_DECODING_ERROR && out.status == RAC_ERROR_DECODING_ERROR,
          "LoRA catalog query rejects malformed proto");
    rac_proto_buffer_free(&out);

    runanywhere::v1::LoraAdapterCatalogGetRequest get_request;
    get_request.set_adapter_id("missing");
    std::vector<uint8_t> get_bytes;
    CHECK(serialize(get_request, &get_bytes), "LoRA negative get request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_catalog_get_proto(registry, get_bytes.data(), get_bytes.size(), &out);
    runanywhere::v1::LoraAdapterCatalogGetResult get_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &get_result),
          "LoRA catalog get missing returns typed result");
    CHECK(!get_result.found() && get_result.error_message().find("not found") != std::string::npos,
          "LoRA catalog get missing reports not found");
    rac_proto_buffer_free(&out);

    runanywhere::v1::LoraAdapterDownloadCompletedRequest completed;
    completed.set_adapter_id("missing");
    completed.set_local_path("/models/lora/missing.gguf");
    std::vector<uint8_t> completed_bytes;
    CHECK(serialize(completed, &completed_bytes), "LoRA negative completion request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_catalog_mark_download_completed_proto(registry, completed_bytes.data(),
                                                        completed_bytes.size(), &out);
    runanywhere::v1::LoraAdapterDownloadCompletedResult completed_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &completed_result),
          "LoRA catalog completion missing returns typed result");
    CHECK(!completed_result.success() && !completed_result.persisted(),
          "LoRA catalog completion missing is not persisted");
    CHECK(completed_result.error_message().find("not found") != std::string::npos,
          "LoRA catalog completion missing reports not found");
    rac_proto_buffer_free(&out);

    completed.clear_adapter_id();
    CHECK(serialize(completed, &completed_bytes), "LoRA invalid completion request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_catalog_mark_download_completed_proto(registry, completed_bytes.data(),
                                                        completed_bytes.size(), &out);
    CHECK(rc == RAC_ERROR_INVALID_ARGUMENT && out.status == RAC_ERROR_INVALID_ARGUMENT,
          "LoRA catalog completion requires adapter id");
    rac_proto_buffer_free(&out);

    rac_lora_registry_destroy(registry);
    return 0;
}

int test_generated_lora_apply_no_service_typed_error() {
    lora_test_environment_reset();

    runanywhere::v1::LoRAApplyRequest request;
    request.set_request_id("apply-no-service");
    auto* adapter = request.add_adapters();
    adapter->set_adapter_path("/tmp/adapter.gguf");
    adapter->set_adapter_id("adapter.one");
    adapter->set_scale(0.5f);

    std::vector<uint8_t> bytes;
    CHECK(serialize(request, &bytes), "LoRAApplyRequest serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_lora_apply_proto(bytes.data(), bytes.size(), &out);
    runanywhere::v1::LoRAApplyResult result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &result),
          "LoRA apply no-service returns typed result");
    CHECK(!result.success(), "LoRA apply no-service result is unsuccessful");
    CHECK(result.request_id() == "apply-no-service", "LoRA apply no-service preserves request id");
    CHECK(result.error_code() == RAC_ERROR_COMPONENT_NOT_READY,
          "LoRA apply no-service carries component-not-ready code");
    CHECK(result.error_message().find("LoRA service is not loaded") != std::string::npos,
          "LoRA apply no-service explains missing service");
    rac_proto_buffer_free(&out);
    return 0;
}

int test_generated_lora_apply_list_state_remove_and_clear(rac_model_registry_handle_t registry) {
    lora_test_environment_reset();

    rac_llm_service_ops_t llm_ops = make_llm_ops(/*supports_lora=*/true);
    rac_engine_vtable_t vtable = make_vtable("llamacpp", &llm_ops);
    CHECK(rac_plugin_register(&vtable) == RAC_SUCCESS, "LoRA service test plugin registers");
    CHECK(register_lora_test_model(registry, build_lora_test_model("mock-llm", "Mock LLM")),
          "mock-llm registers for generated LoRA apply");
    CHECK(register_lora_test_adapter("style", "mock-llm"),
          "style adapter registers for mock-llm");
    CHECK(register_lora_test_adapter("tone", "mock-llm"), "tone adapter registers for mock-llm");
    CHECK(load_lora_test_model(registry, "mock-llm"),
          "lifecycle loads mock model for generated LoRA apply");

    runanywhere::v1::LoRAApplyRequest apply;
    apply.set_request_id("apply-generated");
    apply.set_replace_existing(true);
    auto* adapter = apply.add_adapters();
    adapter->set_adapter_path("/tmp/style.gguf");
    adapter->set_adapter_id("style");
    adapter->set_scale(0.25f);
    auto* second = apply.add_adapters();
    second->set_adapter_path("/tmp/tone.gguf");
    second->set_adapter_id("tone");
    second->set_scale(0.75f);
    std::vector<uint8_t> apply_bytes;
    CHECK(serialize(apply, &apply_bytes), "generated LoRA apply request serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_lora_apply_proto(apply_bytes.data(), apply_bytes.size(), &out);
    runanywhere::v1::LoRAApplyResult apply_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &apply_result),
          "generated LoRA apply returns LoRAApplyResult");
    CHECK(apply_result.success(), "generated LoRA apply succeeds");
    CHECK(apply_result.adapters_size() == 2, "generated LoRA apply returns adapter info");
    CHECK(apply_result.adapters(0).applied() &&
              apply_result.adapters(0).adapter_path() == "/tmp/style.gguf",
          "generated LoRA apply reports applied adapter");
    rac_proto_buffer_free(&out);

    runanywhere::v1::LoRAState state_request;
    std::vector<uint8_t> state_bytes;
    CHECK(serialize(state_request, &state_bytes), "generated LoRA state request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_list_proto(state_bytes.data(), state_bytes.size(), &out);
    runanywhere::v1::LoRAState state;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &state), "generated LoRA list returns LoRAState");
    CHECK(state.error_code() == RAC_SUCCESS, "generated LoRA list has no error");
    CHECK(state.has_active_adapters() && state.loaded_adapters_size() == 2,
          "generated LoRA list returns active adapters");
    CHECK(state.base_model_id() == "mock-llm", "generated LoRA list keeps base model id");
    CHECK(state_has_adapter(state, "style", "/tmp/style.gguf"),
          "generated LoRA list includes style adapter");
    CHECK(state_has_adapter(state, "tone", "/tmp/tone.gguf"),
          "generated LoRA list includes tone adapter");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    rc = rac_lora_state_proto(state_bytes.data(), state_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &state), "generated LoRA state returns LoRAState");
    CHECK(state.has_active_adapters() && state.loaded_adapters_size() == 2,
          "generated LoRA state mirrors tracked adapters");
    rac_proto_buffer_free(&out);

    runanywhere::v1::LoRARemoveRequest remove_one;
    remove_one.set_request_id("remove-style");
    remove_one.add_adapter_ids("style");
    std::vector<uint8_t> remove_one_bytes;
    CHECK(serialize(remove_one, &remove_one_bytes),
          "generated LoRA remove-by-id request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_remove_proto(remove_one_bytes.data(), remove_one_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &state),
          "generated LoRA remove-by-id returns LoRAState");
    CHECK(state.error_code() == RAC_SUCCESS, "generated LoRA remove-by-id has no error");
    CHECK(state.has_active_adapters() && state.loaded_adapters_size() == 1,
          "generated LoRA remove-by-id leaves remaining adapter");
    CHECK(!state_has_adapter(state, "style", "/tmp/style.gguf"),
          "generated LoRA remove-by-id removes style adapter");
    CHECK(state_has_adapter(state, "tone", "/tmp/tone.gguf"),
          "generated LoRA remove-by-id keeps tone adapter");
    rac_proto_buffer_free(&out);

    runanywhere::v1::LoRARemoveRequest remove_path;
    remove_path.set_request_id("remove-tone");
    remove_path.add_adapter_paths("/tmp/tone.gguf");
    std::vector<uint8_t> remove_path_bytes;
    CHECK(serialize(remove_path, &remove_path_bytes),
          "generated LoRA remove-by-path request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_remove_proto(remove_path_bytes.data(), remove_path_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &state),
          "generated LoRA remove-by-path returns LoRAState");
    CHECK(state.error_code() == RAC_SUCCESS, "generated LoRA remove-by-path has no error");
    CHECK(!state.has_active_adapters() && state.loaded_adapters_size() == 0,
          "generated LoRA remove-by-path returns empty state");
    rac_proto_buffer_free(&out);

    CHECK(serialize(apply, &apply_bytes), "generated LoRA reapply request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_apply_proto(apply_bytes.data(), apply_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &apply_result),
          "generated LoRA reapply returns LoRAApplyResult");
    CHECK(apply_result.success(), "generated LoRA reapply succeeds");
    rac_proto_buffer_free(&out);

    runanywhere::v1::LoRARemoveRequest remove;
    remove.set_request_id("clear-generated");
    remove.set_clear_all(true);
    std::vector<uint8_t> remove_bytes;
    CHECK(serialize(remove, &remove_bytes), "generated LoRA clear request serializes");
    rac_proto_buffer_init(&out);
    rc = rac_lora_remove_proto(remove_bytes.data(), remove_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &state), "generated LoRA clear returns LoRAState");
    CHECK(state.error_code() == RAC_SUCCESS, "generated LoRA clear has no error");
    CHECK(!state.has_active_adapters() && state.loaded_adapters_size() == 0,
          "generated LoRA clear returns empty state");
    CHECK(state.base_model_id() == "mock-llm", "generated LoRA clear keeps base model id");
    rac_proto_buffer_free(&out);

    lora_test_environment_reset();
    return 0;
}

int test_generated_lora_remove_unknown_id_is_typed_error(rac_model_registry_handle_t registry) {
    lora_test_environment_reset();

    rac_llm_service_ops_t llm_ops = make_llm_ops(/*supports_lora=*/true);
    rac_engine_vtable_t vtable = make_vtable("llamacpp", &llm_ops);
    CHECK(rac_plugin_register(&vtable) == RAC_SUCCESS, "LoRA unknown-id plugin registers");
    CHECK(register_lora_test_model(registry, build_lora_test_model("mock-llm", "Mock LLM")),
          "mock-llm registers for generated LoRA unknown-id test");
    CHECK(register_lora_test_adapter("style", "mock-llm"),
          "style adapter registers for mock-llm unknown-id test");
    CHECK(load_lora_test_model(registry, "mock-llm"),
          "lifecycle loads mock model for generated LoRA unknown-id test");

    runanywhere::v1::LoRAApplyRequest apply;
    apply.set_request_id("apply-before-unknown-id");
    auto* adapter = apply.add_adapters();
    adapter->set_adapter_path("/tmp/style.gguf");
    adapter->set_adapter_id("style");
    adapter->set_scale(1.0f);
    std::vector<uint8_t> apply_bytes;
    CHECK(serialize(apply, &apply_bytes), "LoRA apply-before-unknown-id serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_lora_apply_proto(apply_bytes.data(), apply_bytes.size(), &out);
    runanywhere::v1::LoRAApplyResult apply_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &apply_result),
          "LoRA apply-before-unknown-id returns result");
    CHECK(apply_result.success(), "LoRA apply-before-unknown-id succeeds");
    rac_proto_buffer_free(&out);

    runanywhere::v1::LoRARemoveRequest remove_by_id;
    remove_by_id.add_adapter_ids("missing");
    std::vector<uint8_t> remove_bytes;
    CHECK(serialize(remove_by_id, &remove_bytes), "LoRA remove unknown-id request serializes");

    rac_proto_buffer_init(&out);
    rc = rac_lora_remove_proto(remove_bytes.data(), remove_bytes.size(), &out);
    runanywhere::v1::LoRAState state;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &state),
          "LoRA remove unknown-id returns typed state error");
    CHECK(state.error_code() == RAC_ERROR_NOT_FOUND,
          "LoRA remove unknown-id carries not-found code");
    CHECK(state.error_message().find("not active") != std::string::npos,
          "LoRA remove unknown-id explains missing active id");
    CHECK(state.has_active_adapters() && state.loaded_adapters_size() == 1,
          "LoRA remove unknown-id preserves tracked active state");
    CHECK(state_has_adapter(state, "style", "/tmp/style.gguf"),
          "LoRA remove unknown-id keeps existing adapter");
    rac_proto_buffer_free(&out);

    lora_test_environment_reset();
    return 0;
}

// Verifies that tracked LoRA state is keyed on the lifecycle backend instance
// and resets when the lifecycle service unloads/reloads a model. With the
// lifecycle service owning a single LLM at a time, "scoped per component"
// becomes "scoped per loaded model" — loading a different model after unload
// must NOT inherit adapters from the previous load.
int test_generated_lora_state_is_scoped_per_lifecycle_load(rac_model_registry_handle_t registry) {
    lora_test_environment_reset();

    rac_llm_service_ops_t llm_ops = make_llm_ops(/*supports_lora=*/true);
    rac_engine_vtable_t vtable = make_vtable("llamacpp", &llm_ops);
    CHECK(rac_plugin_register(&vtable) == RAC_SUCCESS, "LoRA scoped-state plugin registers");
    CHECK(register_lora_test_model(registry, build_lora_test_model("model-a", "Model A")),
          "model-a registers for scoped LoRA state");
    CHECK(register_lora_test_model(registry, build_lora_test_model("model-b", "Model B")),
          "model-b registers for scoped LoRA state");
    CHECK(register_lora_test_adapter("first", "model-a"),
          "first adapter registers for model-a");
    CHECK(register_lora_test_adapter("second", "model-b"),
          "second adapter registers for model-b");

    CHECK(load_lora_test_model(registry, "model-a"),
          "lifecycle loads model-a for scoped LoRA state");

    runanywhere::v1::LoRAApplyRequest apply_first;
    apply_first.set_request_id("apply-first");
    auto* first_adapter = apply_first.add_adapters();
    first_adapter->set_adapter_path("/tmp/first.gguf");
    first_adapter->set_adapter_id("first");
    first_adapter->set_scale(0.4f);
    std::vector<uint8_t> first_apply_bytes;
    CHECK(serialize(apply_first, &first_apply_bytes), "first scoped LoRA apply request serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc =
        rac_lora_apply_proto(first_apply_bytes.data(), first_apply_bytes.size(), &out);
    runanywhere::v1::LoRAApplyResult apply_result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &apply_result),
          "first scoped LoRA apply returns result");
    CHECK(apply_result.success(), "first scoped LoRA apply succeeds");
    rac_proto_buffer_free(&out);

    runanywhere::v1::LoRAState state_request;
    std::vector<uint8_t> state_bytes;
    CHECK(serialize(state_request, &state_bytes), "scoped LoRA state request serializes");

    runanywhere::v1::LoRAState state;
    rac_proto_buffer_init(&out);
    rc = rac_lora_state_proto(state_bytes.data(), state_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &state),
          "model-a scoped LoRA state returns state");
    CHECK(state.base_model_id() == "model-a", "model-a scoped LoRA state keeps model id");
    CHECK(state.loaded_adapters_size() == 1 && state_has_adapter(state, "first", "/tmp/first.gguf"),
          "model-a scoped LoRA state sees only first adapter");
    rac_proto_buffer_free(&out);

    // Unload model-a and load model-b. Tracked state for model-a must NOT
    // leak into model-b because the backend impl pointer is a different
    // allocation and the base model id has changed.
    rac_model_lifecycle_reset();
    CHECK(load_lora_test_model(registry, "model-b"),
          "lifecycle loads model-b for scoped LoRA state");

    runanywhere::v1::LoRAApplyRequest apply_second;
    apply_second.set_request_id("apply-second");
    auto* second_adapter = apply_second.add_adapters();
    second_adapter->set_adapter_path("/tmp/second.gguf");
    second_adapter->set_adapter_id("second");
    second_adapter->set_scale(0.6f);
    std::vector<uint8_t> second_apply_bytes;
    CHECK(serialize(apply_second, &second_apply_bytes),
          "second scoped LoRA apply request serializes");

    rac_proto_buffer_init(&out);
    rc = rac_lora_apply_proto(second_apply_bytes.data(), second_apply_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &apply_result),
          "second scoped LoRA apply returns result");
    CHECK(apply_result.success(), "second scoped LoRA apply succeeds");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    rc = rac_lora_state_proto(state_bytes.data(), state_bytes.size(), &out);
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &state),
          "model-b scoped LoRA state returns state");
    CHECK(state.base_model_id() == "model-b", "model-b scoped LoRA state keeps model id");
    CHECK(state.loaded_adapters_size() == 1 &&
              state_has_adapter(state, "second", "/tmp/second.gguf"),
          "model-b scoped LoRA state sees only second adapter");
    CHECK(!state_has_adapter(state, "first", "/tmp/first.gguf"),
          "model-b scoped LoRA state does not inherit model-a adapter");
    rac_proto_buffer_free(&out);

    lora_test_environment_reset();
    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_lora_service_proto_abi\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: LoRA service proto ABI tests (no protobuf)\n");
    return 0;
#else
    rac_model_registry_handle_t registry = nullptr;
    if (rac_model_registry_create(&registry) != RAC_SUCCESS || registry == nullptr) {
        std::fprintf(stderr, "  FATAL: failed to create model registry\n");
        return 1;
    }

    try {
        test_lora_generated_service_contract();
        test_generated_lora_catalog_register_list_query_get_and_completion();
        test_generated_lora_catalog_negative_errors();
        test_generated_lora_apply_no_service_typed_error();
        test_generated_lora_apply_list_state_remove_and_clear(registry);
        test_generated_lora_remove_unknown_id_is_typed_error(registry);
        test_generated_lora_state_is_scoped_per_lifecycle_load(registry);
    } catch (const std::exception& e) {
        std::fprintf(stderr, "  FATAL: uncaught exception: %s\n", e.what());
        lora_test_environment_reset();
        rac_model_registry_destroy(registry);
        return 1;
    } catch (...) {
        std::fprintf(stderr, "  FATAL: uncaught unknown exception\n");
        lora_test_environment_reset();
        rac_model_registry_destroy(registry);
        return 1;
    }

    lora_test_environment_reset();
    rac_model_registry_destroy(registry);
    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
