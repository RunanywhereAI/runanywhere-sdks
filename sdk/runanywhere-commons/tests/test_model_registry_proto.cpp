/**
 * @file test_model_registry_proto.cpp
 * @brief Tests for the model registry proto-byte C ABI.
 */

#include <cstdio>
#include <cstring>
#include <exception>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#ifdef RAC_HAVE_PROTOBUF
#include "model_types.pb.h"
#endif

namespace {

#define ASSERT_TRUE(cond)                                                                   \
    do {                                                                                    \
        if (!(cond)) {                                                                      \
            std::fprintf(stderr, "ASSERT FAILED: %s @ %s:%d\n", #cond, __FILE__, __LINE__); \
            return 1;                                                                       \
        }                                                                                   \
    } while (0)

#define ASSERT_EQ(a, b)                                                                            \
    do {                                                                                           \
        if (!((a) == (b))) {                                                                       \
            std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d\n", #a, #b, __FILE__, __LINE__); \
            return 1;                                                                              \
        }                                                                                          \
    } while (0)

rac_model_registry_handle_t create_registry() {
    rac_model_registry_handle_t registry = nullptr;
    if (rac_model_registry_create(&registry) != RAC_SUCCESS) {
        return nullptr;
    }
    return registry;
}

#ifdef RAC_HAVE_PROTOBUF

runanywhere::v1::ModelInfo build_full_model_proto(const std::string& id, const std::string& name,
                                                  const std::string& local_path) {
    runanywhere::v1::ModelInfo model;
    model.set_id(id);
    model.set_name(name);
    model.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    model.set_format(runanywhere::v1::MODEL_FORMAT_GGUF);
    model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    model.set_download_url("https://example.test/" + id + ".gguf");
    model.set_local_path(local_path);
    model.set_download_size_bytes(42);
    model.set_context_length(4096);
    model.set_supports_thinking(true);
    model.set_supports_lora(true);
    model.set_description("test chat model");
    model.set_source(runanywhere::v1::MODEL_SOURCE_REMOTE);
    model.set_created_at_unix_ms(1000);
    model.set_updated_at_unix_ms(2000);
    model.set_memory_required_bytes(123456);
    model.set_checksum_sha256("sha256:root");
    model.mutable_thinking_pattern()->set_open_tag("<think>");
    model.mutable_thinking_pattern()->set_close_tag("</think>");
    model.mutable_metadata()->set_description("metadata description");
    model.mutable_metadata()->set_author("RunAnywhere");
    model.mutable_metadata()->set_license("Apache-2.0");
    model.mutable_metadata()->add_tags("chat");
    model.mutable_metadata()->add_tags("reasoning");
    model.mutable_metadata()->set_version("v1");
    model.set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_DIRECTORY);
    model.set_acceleration_preference(runanywhere::v1::ACCELERATION_PREFERENCE_GPU);
    model.set_routing_policy(runanywhere::v1::ROUTING_POLICY_PREFER_LOCAL);
    model.mutable_compatibility()->add_compatible_frameworks(
        runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    model.mutable_compatibility()->add_compatible_formats(runanywhere::v1::MODEL_FORMAT_GGUF);
    model.set_preferred_framework(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    model.set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED);
    model.set_is_downloaded(!local_path.empty());
    model.set_is_available(!local_path.empty());
    model.set_last_used_at_unix_ms(3000);
    model.set_usage_count(7);
    model.set_sync_pending(true);
    model.set_status_message("ready");

    auto* file = model.mutable_multi_file()->add_files();
    file->set_url("weights/part-0001.gguf");
    file->set_filename("part-0001.gguf");
    file->set_is_required(true);
    file->set_size_bytes(42);
    file->set_checksum_sha256("sha256:part");
    file->set_relative_path("weights/part-0001.gguf");
    file->set_destination_path("part-0001.gguf");
    file->set_local_path(local_path + "/part-0001.gguf");
    file->set_role(runanywhere::v1::MODEL_FILE_ROLE_PRIMARY_MODEL);

    auto* expected = model.mutable_expected_files();
    expected->set_root_directory("model-root");
    expected->set_description("expected file set");
    expected->add_required_patterns("*.gguf");
    expected->add_optional_patterns("tokenizer.json");
    auto* expected_file = expected->add_files();
    expected_file->set_filename("tokenizer.json");
    expected_file->set_relative_path("tokenizer.json");
    expected_file->set_destination_path("tokenizer.json");
    expected_file->set_is_required(false);
    expected_file->set_role(runanywhere::v1::MODEL_FILE_ROLE_TOKENIZER);

    return model;
}

runanywhere::v1::ModelInfo build_minimal_update_proto(const std::string& id,
                                                      const std::string& name) {
    runanywhere::v1::ModelInfo model;
    model.set_id(id);
    model.set_name(name);
    model.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    model.set_format(runanywhere::v1::MODEL_FORMAT_GGUF);
    model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    model.set_download_url("https://example.test/" + id + "-updated.gguf");
    model.set_download_size_bytes(41);
    model.set_context_length(2048);
    model.set_supports_thinking(true);
    model.set_supports_lora(false);
    model.set_description("updated model");
    model.set_source(runanywhere::v1::MODEL_SOURCE_REMOTE);
    model.set_created_at_unix_ms(1000);
    model.set_updated_at_unix_ms(4000);
    return model;
}

runanywhere::v1::ModelInfo
build_query_model(const std::string& id, const std::string& name,
                  runanywhere::v1::ModelCategory category, runanywhere::v1::ModelFormat format,
                  runanywhere::v1::InferenceFramework framework, bool downloaded, bool available,
                  int64_t size_bytes,
                  runanywhere::v1::ModelSource source = runanywhere::v1::MODEL_SOURCE_REMOTE) {
    runanywhere::v1::ModelInfo model;
    model.set_id(id);
    model.set_name(name);
    model.set_category(category);
    model.set_format(format);
    model.set_framework(framework);
    model.set_download_url("https://example.test/" + id);
    if (downloaded) {
        model.set_local_path("/models/" + id);
    }
    model.set_download_size_bytes(size_bytes);
    model.set_description(name + " searchable description");
    model.mutable_metadata()->add_tags(name);
    model.set_source(source);
    model.set_registry_status(downloaded ? runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED
                                         : runanywhere::v1::MODEL_REGISTRY_STATUS_REGISTERED);
    model.set_is_downloaded(downloaded);
    model.set_is_available(available);
    return model;
}

bool serialize(const runanywhere::v1::ModelInfo& model, std::vector<uint8_t>* out) {
    std::string bytes;
    if (!out || !model.SerializeToString(&bytes)) {
        return false;
    }
    out->assign(bytes.begin(), bytes.end());
    return true;
}

bool serialize_message(const google::protobuf::MessageLite& message, std::vector<uint8_t>* out) {
    std::string bytes;
    if (!out || !message.SerializeToString(&bytes)) {
        return false;
    }
    out->assign(bytes.begin(), bytes.end());
    return true;
}

bool serialize_query(const runanywhere::v1::ModelQuery& query, std::vector<uint8_t>* out) {
    std::string bytes;
    if (!out || !query.SerializeToString(&bytes)) {
        return false;
    }
    out->assign(bytes.begin(), bytes.end());
    return true;
}

bool register_model_proto(rac_model_registry_handle_t registry,
                          const runanywhere::v1::ModelInfo& model) {
    std::vector<uint8_t> bytes;
    return serialize(model, &bytes) &&
           rac_model_registry_register_proto(registry, bytes.data(), bytes.size()) == RAC_SUCCESS;
}

bool get_model_proto(rac_model_registry_handle_t registry, const char* model_id,
                     runanywhere::v1::ModelInfo* out) {
    uint8_t* bytes = nullptr;
    size_t size = 0;
    if (rac_model_registry_get_proto(registry, model_id, &bytes, &size) != RAC_SUCCESS ||
        bytes == nullptr || !out) {
        return false;
    }
    bool parsed = out->ParseFromArray(bytes, static_cast<int>(size));
    rac_model_registry_proto_free(bytes);
    return parsed;
}

bool list_model_proto(rac_model_registry_handle_t registry, runanywhere::v1::ModelInfoList* out) {
    uint8_t* bytes = nullptr;
    size_t size = 0;
    if (rac_model_registry_list_proto(registry, &bytes, &size) != RAC_SUCCESS || bytes == nullptr ||
        !out) {
        return false;
    }
    bool parsed = out->ParseFromArray(bytes, static_cast<int>(size));
    rac_model_registry_proto_free(bytes);
    return parsed;
}

bool query_model_proto(rac_model_registry_handle_t registry,
                       const runanywhere::v1::ModelQuery& query,
                       runanywhere::v1::ModelInfoList* out) {
    std::vector<uint8_t> query_bytes;
    if (!serialize_query(query, &query_bytes)) {
        return false;
    }

    uint8_t* bytes = nullptr;
    size_t size = 0;
    if (rac_model_registry_query_proto(registry, query_bytes.data(), query_bytes.size(), &bytes,
                                       &size) != RAC_SUCCESS ||
        bytes == nullptr || !out) {
        return false;
    }
    bool parsed = out->ParseFromArray(bytes, static_cast<int>(size));
    rac_model_registry_proto_free(bytes);
    return parsed;
}

template <typename T>
bool parse_and_free_buffer(rac_proto_buffer_t* buffer, T* out) {
    if (!buffer || !out || buffer->status != RAC_SUCCESS || !buffer->data) {
        if (buffer) {
            rac_proto_buffer_free(buffer);
        }
        return false;
    }
    bool parsed = out->ParseFromArray(buffer->data, static_cast<int>(buffer->size));
    rac_proto_buffer_free(buffer);
    return parsed;
}

bool list_downloaded_model_proto(rac_model_registry_handle_t registry,
                                 runanywhere::v1::ModelInfoList* out) {
    uint8_t* bytes = nullptr;
    size_t size = 0;
    if (rac_model_registry_list_downloaded_proto(registry, &bytes, &size) != RAC_SUCCESS ||
        bytes == nullptr || !out) {
        return false;
    }
    bool parsed = out->ParseFromArray(bytes, static_cast<int>(size));
    rac_model_registry_proto_free(bytes);
    return parsed;
}

bool call_get_model_result(rac_model_registry_handle_t registry,
                           const runanywhere::v1::ModelGetRequest& request,
                           runanywhere::v1::ModelGetResult* out) {
    std::vector<uint8_t> bytes;
    if (!serialize_message(request, &bytes)) {
        return false;
    }
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    if (rac_model_registry_get_model_proto(registry, bytes.data(), bytes.size(), &buffer) !=
        RAC_SUCCESS) {
        rac_proto_buffer_free(&buffer);
        return false;
    }
    return parse_and_free_buffer(&buffer, out);
}

bool call_list_models_result(rac_model_registry_handle_t registry,
                             const runanywhere::v1::ModelListRequest& request,
                             runanywhere::v1::ModelListResult* out) {
    std::vector<uint8_t> bytes;
    if (!serialize_message(request, &bytes)) {
        return false;
    }
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    if (rac_model_registry_list_models_proto(registry, bytes.data(), bytes.size(), &buffer) !=
        RAC_SUCCESS) {
        rac_proto_buffer_free(&buffer);
        return false;
    }
    return parse_and_free_buffer(&buffer, out);
}

runanywhere::v1::ModelInfo build_expanded_enum_model() {
    runanywhere::v1::ModelInfo model;
    model.set_id("expanded.tflite");
    model.set_name("Expanded TFLite");
    model.set_category(runanywhere::v1::MODEL_CATEGORY_VISION);
    model.set_format(runanywhere::v1::MODEL_FORMAT_TFLITE);
    model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_TFLITE);
    model.set_download_url("builtin://expanded.tflite");
    model.set_download_size_bytes(9);
    model.set_description("expanded enum preservation");
    model.set_source(runanywhere::v1::MODEL_SOURCE_BUILT_IN);
    model.set_created_at_unix_ms(10);
    model.set_updated_at_unix_ms(20);
    model.set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_BUILT_IN);
    model.set_built_in(true);
    model.set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_LOADED);
    model.set_is_downloaded(true);
    model.set_is_available(true);
    model.set_status_message("loaded");
    model.mutable_metadata()->add_tags("expanded");
    model.mutable_compatibility()->add_compatible_frameworks(
        runanywhere::v1::INFERENCE_FRAMEWORK_TFLITE);
    model.mutable_compatibility()->add_compatible_formats(runanywhere::v1::MODEL_FORMAT_TFLITE);
    model.set_preferred_framework(runanywhere::v1::INFERENCE_FRAMEWORK_TFLITE);
    return model;
}

int test_full_field_round_trip_proto() {
    rac_model_registry_handle_t registry = create_registry();
    ASSERT_TRUE(registry != nullptr);

    runanywhere::v1::ModelInfo original =
        build_full_model_proto("llama.test", "Original", "/models/llama.test");
    std::vector<uint8_t> original_bytes;
    ASSERT_TRUE(serialize(original, &original_bytes));
    ASSERT_EQ(
        rac_model_registry_register_proto(registry, original_bytes.data(), original_bytes.size()),
        RAC_SUCCESS);

    rac_model_info_t* struct_model = nullptr;
    ASSERT_EQ(rac_model_registry_get(registry, "llama.test", &struct_model), RAC_SUCCESS);
    ASSERT_TRUE(struct_model != nullptr);
    ASSERT_EQ(struct_model->category, RAC_MODEL_CATEGORY_LANGUAGE);
    ASSERT_EQ(struct_model->format, RAC_MODEL_FORMAT_GGUF);
    ASSERT_EQ(struct_model->framework, RAC_FRAMEWORK_LLAMACPP);
    ASSERT_TRUE(struct_model->local_path != nullptr);
    ASSERT_TRUE(std::strcmp(struct_model->local_path, "/models/llama.test") == 0);
    rac_model_info_free(struct_model);

    runanywhere::v1::ModelInfo decoded;
    ASSERT_TRUE(get_model_proto(registry, "llama.test", &decoded));
    ASSERT_EQ(decoded.id(), "llama.test");
    ASSERT_EQ(decoded.name(), "Original");
    ASSERT_EQ(decoded.local_path(), "/models/llama.test");
    ASSERT_TRUE(decoded.has_memory_required_bytes());
    ASSERT_EQ(decoded.memory_required_bytes(), 123456);
    ASSERT_TRUE(decoded.has_checksum_sha256());
    ASSERT_EQ(decoded.checksum_sha256(), "sha256:root");
    ASSERT_TRUE(decoded.has_thinking_pattern());
    ASSERT_EQ(decoded.thinking_pattern().open_tag(), "<think>");
    ASSERT_TRUE(decoded.has_metadata());
    ASSERT_EQ(decoded.metadata().tags_size(), 2);
    ASSERT_EQ(decoded.metadata().author(), "RunAnywhere");
    ASSERT_TRUE(decoded.has_compatibility());
    ASSERT_EQ(decoded.compatibility().compatible_frameworks_size(), 1);
    ASSERT_TRUE(decoded.has_registry_status());
    ASSERT_EQ(decoded.registry_status(), runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED);
    ASSERT_TRUE(decoded.has_is_downloaded());
    ASSERT_TRUE(decoded.is_downloaded());
    ASSERT_TRUE(decoded.has_is_available());
    ASSERT_TRUE(decoded.is_available());
    ASSERT_TRUE(decoded.has_expected_files());
    ASSERT_EQ(decoded.expected_files().required_patterns_size(), 1);
    ASSERT_EQ(decoded.expected_files().files_size(), 1);
    ASSERT_TRUE(decoded.has_multi_file());
    ASSERT_EQ(decoded.multi_file().files_size(), 1);
    ASSERT_EQ(decoded.multi_file().files(0).checksum_sha256(), "sha256:part");
    ASSERT_EQ(decoded.multi_file().files(0).role(), runanywhere::v1::MODEL_FILE_ROLE_PRIMARY_MODEL);
    ASSERT_EQ(decoded.acceleration_preference(), runanywhere::v1::ACCELERATION_PREFERENCE_GPU);
    ASSERT_EQ(decoded.routing_policy(), runanywhere::v1::ROUTING_POLICY_PREFER_LOCAL);

    runanywhere::v1::ModelInfoList list;
    ASSERT_TRUE(list_model_proto(registry, &list));
    ASSERT_EQ(list.models_size(), 1);
    ASSERT_EQ(list.models(0).id(), "llama.test");
    ASSERT_TRUE(list.models(0).has_multi_file());
    ASSERT_TRUE(list.models(0).has_expected_files());
    ASSERT_TRUE(list.models(0).has_metadata());

    rac_model_registry_destroy(registry);
    return 0;
}

int test_expanded_proto_fields_survive_struct_state_updates() {
    rac_model_registry_handle_t registry = create_registry();
    ASSERT_TRUE(registry != nullptr);

    runanywhere::v1::ModelInfo original = build_expanded_enum_model();
    std::vector<uint8_t> bytes;
    ASSERT_TRUE(serialize(original, &bytes));

    rac_proto_buffer_t registered;
    rac_proto_buffer_init(&registered);
    ASSERT_EQ(
        rac_model_registry_register_proto_buffer(registry, bytes.data(), bytes.size(), &registered),
        RAC_SUCCESS);
    runanywhere::v1::ModelInfo registered_model;
    ASSERT_TRUE(parse_and_free_buffer(&registered, &registered_model));
    ASSERT_EQ(registered_model.format(), runanywhere::v1::MODEL_FORMAT_TFLITE);
    ASSERT_EQ(registered_model.framework(), runanywhere::v1::INFERENCE_FRAMEWORK_TFLITE);
    ASSERT_EQ(registered_model.source(), runanywhere::v1::MODEL_SOURCE_BUILT_IN);
    ASSERT_TRUE(registered_model.has_built_in());
    ASSERT_TRUE(registered_model.built_in());

    rac_model_info_t* struct_model = nullptr;
    ASSERT_EQ(rac_model_registry_get(registry, "expanded.tflite", &struct_model), RAC_SUCCESS);
    ASSERT_TRUE(struct_model != nullptr);
    ASSERT_EQ(struct_model->format, RAC_MODEL_FORMAT_TFLITE);
    rac_model_info_free(struct_model);

    ASSERT_EQ(rac_model_registry_update_last_used(registry, "expanded.tflite"), RAC_SUCCESS);

    runanywhere::v1::ModelInfo decoded;
    ASSERT_TRUE(get_model_proto(registry, "expanded.tflite", &decoded));
    ASSERT_EQ(decoded.format(), runanywhere::v1::MODEL_FORMAT_TFLITE);
    ASSERT_EQ(decoded.framework(), runanywhere::v1::INFERENCE_FRAMEWORK_TFLITE);
    ASSERT_EQ(decoded.source(), runanywhere::v1::MODEL_SOURCE_BUILT_IN);
    ASSERT_EQ(decoded.artifact_type(), runanywhere::v1::MODEL_ARTIFACT_TYPE_BUILT_IN);
    ASSERT_TRUE(decoded.has_built_in());
    ASSERT_TRUE(decoded.built_in());
    ASSERT_TRUE(decoded.has_metadata());
    ASSERT_EQ(decoded.metadata().tags_size(), 1);
    ASSERT_TRUE(decoded.has_compatibility());
    ASSERT_EQ(decoded.compatibility().compatible_formats(0), runanywhere::v1::MODEL_FORMAT_TFLITE);
    ASSERT_TRUE(decoded.has_registry_status());
    ASSERT_EQ(decoded.registry_status(), runanywhere::v1::MODEL_REGISTRY_STATUS_LOADED);
    ASSERT_TRUE(decoded.has_last_used_at_unix_ms());
    ASSERT_TRUE(decoded.has_usage_count());
    ASSERT_EQ(decoded.usage_count(), 1);

    runanywhere::v1::ModelInfoList list;
    ASSERT_TRUE(list_model_proto(registry, &list));
    ASSERT_EQ(list.models_size(), 1);
    ASSERT_EQ(list.models(0).framework(), runanywhere::v1::INFERENCE_FRAMEWORK_TFLITE);
    ASSERT_EQ(list.models(0).source(), runanywhere::v1::MODEL_SOURCE_BUILT_IN);

    rac_model_registry_destroy(registry);
    return 0;
}

int test_update_preserves_proto_only_fields() {
    rac_model_registry_handle_t registry = create_registry();
    ASSERT_TRUE(registry != nullptr);

    runanywhere::v1::ModelInfo original =
        build_full_model_proto("llama.test", "Original", "/models/llama.test");
    ASSERT_TRUE(register_model_proto(registry, original));

    runanywhere::v1::ModelInfo update = build_minimal_update_proto("llama.test", "Updated");
    std::vector<uint8_t> update_bytes;
    ASSERT_TRUE(serialize(update, &update_bytes));
    ASSERT_EQ(rac_model_registry_update_proto(registry, update_bytes.data(), update_bytes.size()),
              RAC_SUCCESS);
    runanywhere::v1::ModelInfo decoded;
    ASSERT_TRUE(get_model_proto(registry, "llama.test", &decoded));
    ASSERT_EQ(decoded.name(), "Updated");
    ASSERT_EQ(decoded.local_path(), "/models/llama.test");
    ASSERT_TRUE(decoded.has_memory_required_bytes());
    ASSERT_EQ(decoded.memory_required_bytes(), 123456);
    ASSERT_TRUE(decoded.has_metadata());
    ASSERT_EQ(decoded.metadata().tags_size(), 2);
    ASSERT_TRUE(decoded.has_expected_files());
    ASSERT_EQ(decoded.expected_files().files(0).role(), runanywhere::v1::MODEL_FILE_ROLE_TOKENIZER);
    ASSERT_TRUE(decoded.has_multi_file());
    ASSERT_EQ(decoded.multi_file().files(0).checksum_sha256(), "sha256:part");
    ASSERT_TRUE(decoded.has_is_downloaded());
    ASSERT_TRUE(decoded.is_downloaded());

    rac_model_registry_destroy(registry);
    return 0;
}

// commons-053 regression: re-registering a model with a minimal payload must
// merge into (not replace) the existing snapshot. Down-stream services depend
// on checksum_sha256 (download verification), preferred_framework (engine
// routing) and routing_policy (compatibility filter) surviving the catalog
// re-seed call apps perform on startup.
int test_register_proto_preserves_proto_only_fields_on_resave() {
    rac_model_registry_handle_t registry = create_registry();
    ASSERT_TRUE(registry != nullptr);

    runanywhere::v1::ModelInfo original =
        build_full_model_proto("llama.test", "Original", "/models/llama.test");
    ASSERT_TRUE(register_model_proto(registry, original));

    // Catalog re-seed: same id, minimal fields, no checksum/routing/preferred.
    runanywhere::v1::ModelInfo reseed = build_minimal_update_proto("llama.test", "Reseed");
    ASSERT_TRUE(register_model_proto(registry, reseed));

    runanywhere::v1::ModelInfo decoded;
    ASSERT_TRUE(get_model_proto(registry, "llama.test", &decoded));
    ASSERT_EQ(decoded.name(), "Reseed");
    ASSERT_TRUE(decoded.has_checksum_sha256());
    ASSERT_EQ(decoded.checksum_sha256(), "sha256:root");
    ASSERT_TRUE(decoded.has_preferred_framework());
    ASSERT_EQ(decoded.preferred_framework(), runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    ASSERT_TRUE(decoded.has_routing_policy());
    ASSERT_EQ(decoded.routing_policy(), runanywhere::v1::ROUTING_POLICY_PREFER_LOCAL);
    ASSERT_EQ(decoded.acceleration_preference(), runanywhere::v1::ACCELERATION_PREFERENCE_GPU);
    ASSERT_TRUE(decoded.has_compatibility());
    ASSERT_EQ(decoded.compatibility().compatible_frameworks_size(), 1);

    rac_model_registry_destroy(registry);
    return 0;
}

int test_query_filters_and_downloaded_list_proto() {
    rac_model_registry_handle_t registry = create_registry();
    ASSERT_TRUE(registry != nullptr);

    ASSERT_TRUE(register_model_proto(
        registry,
        build_query_model("alpha.chat", "Alpha Chat", runanywhere::v1::MODEL_CATEGORY_LANGUAGE,
                          runanywhere::v1::MODEL_FORMAT_GGUF,
                          runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP, true, true, 100)));
    ASSERT_TRUE(register_model_proto(
        registry,
        build_query_model("beta.speech", "Beta Speech",
                          runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION,
                          runanywhere::v1::MODEL_FORMAT_ONNX,
                          runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA, false, false, 200)));
    ASSERT_TRUE(register_model_proto(
        registry,
        build_query_model("gamma.embed", "Gamma Embed", runanywhere::v1::MODEL_CATEGORY_LANGUAGE,
                          runanywhere::v1::MODEL_FORMAT_ONNX,
                          runanywhere::v1::INFERENCE_FRAMEWORK_ONNX, false, true, 50)));

    runanywhere::v1::ModelInfoList list;
    runanywhere::v1::ModelQuery query;
    query.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    ASSERT_TRUE(query_model_proto(registry, query, &list));
    ASSERT_EQ(list.models_size(), 2);
    ASSERT_EQ(list.models(0).id(), "alpha.chat");
    ASSERT_EQ(list.models(1).id(), "gamma.embed");

    query.Clear();
    query.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    ASSERT_TRUE(query_model_proto(registry, query, &list));
    ASSERT_EQ(list.models_size(), 1);
    ASSERT_EQ(list.models(0).id(), "alpha.chat");

    query.Clear();
    query.set_format(runanywhere::v1::MODEL_FORMAT_ONNX);
    ASSERT_TRUE(query_model_proto(registry, query, &list));
    ASSERT_EQ(list.models_size(), 2);
    ASSERT_EQ(list.models(0).id(), "beta.speech");
    ASSERT_EQ(list.models(1).id(), "gamma.embed");

    query.Clear();
    query.set_downloaded_only(true);
    ASSERT_TRUE(query_model_proto(registry, query, &list));
    ASSERT_EQ(list.models_size(), 1);
    ASSERT_EQ(list.models(0).id(), "alpha.chat");

    query.Clear();
    query.set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_REGISTERED);
    ASSERT_TRUE(query_model_proto(registry, query, &list));
    ASSERT_EQ(list.models_size(), 2);
    ASSERT_EQ(list.models(0).id(), "beta.speech");
    ASSERT_EQ(list.models(1).id(), "gamma.embed");

    query.Clear();
    query.set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED);
    ASSERT_TRUE(query_model_proto(registry, query, &list));
    ASSERT_EQ(list.models_size(), 1);
    ASSERT_EQ(list.models(0).id(), "alpha.chat");

    query.Clear();
    query.set_available_only(true);
    ASSERT_TRUE(query_model_proto(registry, query, &list));
    ASSERT_EQ(list.models_size(), 2);
    ASSERT_EQ(list.models(0).id(), "alpha.chat");
    ASSERT_EQ(list.models(1).id(), "gamma.embed");

    query.Clear();
    query.set_search_query("speech");
    ASSERT_TRUE(query_model_proto(registry, query, &list));
    ASSERT_EQ(list.models_size(), 1);
    ASSERT_EQ(list.models(0).id(), "beta.speech");

    query.Clear();
    query.set_max_size_bytes(100);
    ASSERT_TRUE(query_model_proto(registry, query, &list));
    ASSERT_EQ(list.models_size(), 2);
    ASSERT_EQ(list.models(0).id(), "alpha.chat");
    ASSERT_EQ(list.models(1).id(), "gamma.embed");

    ASSERT_TRUE(list_downloaded_model_proto(registry, &list));
    ASSERT_EQ(list.models_size(), 1);
    ASSERT_EQ(list.models(0).id(), "alpha.chat");

    rac_model_registry_destroy(registry);
    return 0;
}

int test_query_source_filter_and_sorting_proto() {
    rac_model_registry_handle_t registry = create_registry();
    ASSERT_TRUE(registry != nullptr);

    ASSERT_TRUE(register_model_proto(
        registry,
        build_query_model("alpha.remote", "Zulu Remote", runanywhere::v1::MODEL_CATEGORY_LANGUAGE,
                          runanywhere::v1::MODEL_FORMAT_GGUF,
                          runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP, false, true, 300,
                          runanywhere::v1::MODEL_SOURCE_REMOTE)));
    ASSERT_TRUE(register_model_proto(
        registry, build_query_model(
                      "beta.local", "Mango Local", runanywhere::v1::MODEL_CATEGORY_LANGUAGE,
                      runanywhere::v1::MODEL_FORMAT_ONNX, runanywhere::v1::INFERENCE_FRAMEWORK_ONNX,
                      true, true, 100, runanywhere::v1::MODEL_SOURCE_LOCAL)));
    ASSERT_TRUE(register_model_proto(
        registry, build_query_model("zeta.local", "Aardvark Local",
                                    runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION,
                                    runanywhere::v1::MODEL_FORMAT_ONNX,
                                    runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA, true, true, 200,
                                    runanywhere::v1::MODEL_SOURCE_LOCAL)));

    runanywhere::v1::ModelInfoList list;
    runanywhere::v1::ModelQuery query;
    query.set_source(runanywhere::v1::MODEL_SOURCE_LOCAL);
    ASSERT_TRUE(query_model_proto(registry, query, &list));
    ASSERT_EQ(list.models_size(), 2);
    ASSERT_EQ(list.models(0).id(), "beta.local");
    ASSERT_EQ(list.models(1).id(), "zeta.local");

    query.Clear();
    query.set_sort_field(runanywhere::v1::MODEL_QUERY_SORT_FIELD_NAME);
    query.set_sort_order(runanywhere::v1::MODEL_QUERY_SORT_ORDER_ASCENDING);
    ASSERT_TRUE(query_model_proto(registry, query, &list));
    ASSERT_EQ(list.models_size(), 3);
    ASSERT_EQ(list.models(0).id(), "zeta.local");
    ASSERT_EQ(list.models(1).id(), "beta.local");
    ASSERT_EQ(list.models(2).id(), "alpha.remote");

    query.set_sort_order(runanywhere::v1::MODEL_QUERY_SORT_ORDER_DESCENDING);
    ASSERT_TRUE(query_model_proto(registry, query, &list));
    ASSERT_EQ(list.models_size(), 3);
    ASSERT_EQ(list.models(0).id(), "alpha.remote");
    ASSERT_EQ(list.models(1).id(), "beta.local");
    ASSERT_EQ(list.models(2).id(), "zeta.local");

    query.Clear();
    query.set_sort_field(runanywhere::v1::MODEL_QUERY_SORT_FIELD_DOWNLOAD_SIZE_BYTES);
    query.set_sort_order(runanywhere::v1::MODEL_QUERY_SORT_ORDER_DESCENDING);
    ASSERT_TRUE(query_model_proto(registry, query, &list));
    ASSERT_EQ(list.models_size(), 3);
    ASSERT_EQ(list.models(0).id(), "alpha.remote");
    ASSERT_EQ(list.models(1).id(), "zeta.local");
    ASSERT_EQ(list.models(2).id(), "beta.local");

    rac_model_registry_destroy(registry);
    return 0;
}

int test_remove_proto() {
    rac_model_registry_handle_t registry = create_registry();
    ASSERT_TRUE(registry != nullptr);

    ASSERT_TRUE(register_model_proto(
        registry, build_full_model_proto("llama.test", "Original", "/models/llama.test")));

    ASSERT_EQ(rac_model_registry_remove_proto(registry, "llama.test"), RAC_SUCCESS);
    uint8_t* missing_bytes = nullptr;
    size_t missing_size = 0;
    ASSERT_EQ(rac_model_registry_get_proto(registry, "llama.test", &missing_bytes, &missing_size),
              RAC_ERROR_NOT_FOUND);
    ASSERT_TRUE(missing_bytes == nullptr);
    ASSERT_EQ(missing_size, 0U);

    rac_model_registry_destroy(registry);
    return 0;
}

int test_canonical_result_shapes_and_typed_errors() {
    rac_model_registry_handle_t registry = create_registry();
    ASSERT_TRUE(registry != nullptr);

    runanywhere::v1::ModelImportRequest import_request;
    import_request.mutable_model()->CopyFrom(
        build_full_model_proto("import.test", "Import Test", ""));
    import_request.set_source_path("/imports/import.test");
    import_request.set_overwrite_existing(true);
    import_request.set_copy_into_managed_storage(true);
    import_request.set_validate_before_register(true);
    auto* imported_file = import_request.add_files();
    imported_file->set_filename("weights.gguf");
    imported_file->set_size_bytes(55);
    imported_file->set_is_required(true);

    std::vector<uint8_t> import_bytes;
    ASSERT_TRUE(serialize_message(import_request, &import_bytes));
    rac_proto_buffer_t import_buffer;
    rac_proto_buffer_init(&import_buffer);
    ASSERT_EQ(rac_model_registry_import_proto(registry, import_bytes.data(), import_bytes.size(),
                                              &import_buffer),
              RAC_SUCCESS);
    runanywhere::v1::ModelImportResult import_result;
    ASSERT_TRUE(parse_and_free_buffer(&import_buffer, &import_result));
    ASSERT_TRUE(import_result.success());
    ASSERT_TRUE(import_result.registered());
    ASSERT_EQ(import_result.local_path(), "/imports/import.test");
    ASSERT_EQ(import_result.imported_bytes(), 55);
    ASSERT_TRUE(import_result.model().has_metadata());
    ASSERT_TRUE(import_result.model().has_expected_files());
    ASSERT_TRUE(import_result.model().has_multi_file());
    ASSERT_EQ(import_result.model().registry_status(),
              runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED);
    ASSERT_EQ(import_result.warnings_size(), 2);

    runanywhere::v1::ModelGetRequest get_request;
    get_request.set_model_id("import.test");
    runanywhere::v1::ModelGetResult get_result;
    ASSERT_TRUE(call_get_model_result(registry, get_request, &get_result));
    ASSERT_TRUE(get_result.found());
    ASSERT_EQ(get_result.model().id(), "import.test");
    ASSERT_EQ(get_result.model().local_path(), "/imports/import.test");
    ASSERT_TRUE(get_result.model().has_metadata());

    runanywhere::v1::ModelListRequest list_request;
    list_request.set_include_counts(true);
    list_request.mutable_query()->set_downloaded_only(true);
    runanywhere::v1::ModelListResult list_result;
    ASSERT_TRUE(call_list_models_result(registry, list_request, &list_result));
    ASSERT_TRUE(list_result.success());
    ASSERT_EQ(list_result.models().models_size(), 1);
    ASSERT_EQ(list_result.models().models(0).id(), "import.test");
    ASSERT_EQ(list_result.total_count(), 1);
    ASSERT_EQ(list_result.downloaded_count(), 1);
    ASSERT_EQ(list_result.available_count(), 1);
    ASSERT_EQ(list_result.filtered_count(), 1);

    runanywhere::v1::ModelDiscoveryRequest discovery_request;
    discovery_request.add_search_roots("/imports");
    discovery_request.set_link_downloaded(true);
    std::vector<uint8_t> discovery_bytes;
    ASSERT_TRUE(serialize_message(discovery_request, &discovery_bytes));
    rac_proto_buffer_t discovery_buffer;
    rac_proto_buffer_init(&discovery_buffer);
    ASSERT_EQ(rac_model_registry_discover_proto(registry, discovery_bytes.data(),
                                                discovery_bytes.size(), &discovery_buffer),
              RAC_SUCCESS);
    runanywhere::v1::ModelDiscoveryResult discovery_result;
    ASSERT_TRUE(parse_and_free_buffer(&discovery_buffer, &discovery_result));
    ASSERT_TRUE(discovery_result.success());
    ASSERT_EQ(discovery_result.discovered_models_size(), 1);
    ASSERT_EQ(discovery_result.discovered_models(0).model_id(), "import.test");
    ASSERT_TRUE(discovery_result.discovered_models(0).matched_registry());
    ASSERT_EQ(discovery_result.linked_count(), 1);

    runanywhere::v1::ModelRegistryRefreshRequest refresh_request;
    refresh_request.mutable_query()->set_registry_status(
        runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED);
    std::vector<uint8_t> refresh_bytes;
    ASSERT_TRUE(serialize_message(refresh_request, &refresh_bytes));
    rac_proto_buffer_t refresh_buffer;
    rac_proto_buffer_init(&refresh_buffer);
    ASSERT_EQ(rac_model_registry_refresh_proto(registry, refresh_bytes.data(), refresh_bytes.size(),
                                               &refresh_buffer),
              RAC_SUCCESS);
    runanywhere::v1::ModelRegistryRefreshResult refresh_result;
    ASSERT_TRUE(parse_and_free_buffer(&refresh_buffer, &refresh_result));
    ASSERT_TRUE(refresh_result.success());
    ASSERT_EQ(refresh_result.models().models_size(), 1);
    ASSERT_EQ(refresh_result.downloaded_count(), 1);
    ASSERT_EQ(refresh_result.available_count(), 1);

    rac_proto_buffer_t delete_buffer;
    rac_proto_buffer_init(&delete_buffer);
    ASSERT_EQ(rac_model_registry_remove_proto_buffer(registry, "import.test", &delete_buffer),
              RAC_SUCCESS);
    runanywhere::v1::ModelDeleteResult delete_result;
    ASSERT_TRUE(parse_and_free_buffer(&delete_buffer, &delete_result));
    ASSERT_TRUE(delete_result.success());
    ASSERT_TRUE(delete_result.registry_updated());
    ASSERT_TRUE(!delete_result.files_deleted());

    const uint8_t invalid[] = {0xff, 0xff, 0xff};
    rac_proto_buffer_t error_buffer;
    rac_proto_buffer_init(&error_buffer);
    ASSERT_EQ(
        rac_model_registry_list_models_proto(registry, invalid, sizeof(invalid), &error_buffer),
        RAC_ERROR_INVALID_FORMAT);
    ASSERT_EQ(error_buffer.status, RAC_ERROR_INVALID_FORMAT);
    ASSERT_TRUE(error_buffer.data == nullptr);
    ASSERT_TRUE(error_buffer.error_message != nullptr);
    rac_proto_buffer_free(&error_buffer);

    runanywhere::v1::ModelInfo missing_update =
        build_minimal_update_proto("missing.buffer", "Missing");
    std::vector<uint8_t> missing_update_bytes;
    ASSERT_TRUE(serialize(missing_update, &missing_update_bytes));
    rac_proto_buffer_init(&error_buffer);
    ASSERT_EQ(rac_model_registry_update_proto_buffer(registry, missing_update_bytes.data(),
                                                     missing_update_bytes.size(), &error_buffer),
              RAC_ERROR_NOT_FOUND);
    ASSERT_EQ(error_buffer.status, RAC_ERROR_NOT_FOUND);
    ASSERT_TRUE(error_buffer.data == nullptr);
    rac_proto_buffer_free(&error_buffer);

    rac_model_registry_destroy(registry);
    return 0;
}

int test_update_missing_and_invalid_bytes() {
    rac_model_registry_handle_t registry = create_registry();
    ASSERT_TRUE(registry != nullptr);

    runanywhere::v1::ModelInfo missing = build_minimal_update_proto("missing.test", "Missing");
    std::vector<uint8_t> missing_bytes;
    ASSERT_TRUE(serialize(missing, &missing_bytes));
    ASSERT_EQ(rac_model_registry_update_proto(registry, missing_bytes.data(), missing_bytes.size()),
              RAC_ERROR_NOT_FOUND);

    const uint8_t invalid[] = {0xff, 0xff, 0xff};
    ASSERT_EQ(rac_model_registry_register_proto(registry, invalid, sizeof(invalid)),
              RAC_ERROR_INVALID_FORMAT);

    uint8_t* out_bytes = reinterpret_cast<uint8_t*>(0x1);
    size_t out_size = 99;
    ASSERT_EQ(rac_model_registry_register_proto(registry, nullptr, 0), RAC_ERROR_INVALID_ARGUMENT);
    ASSERT_EQ(rac_model_registry_get_proto(registry, nullptr, &out_bytes, &out_size),
              RAC_ERROR_INVALID_ARGUMENT);
    ASSERT_EQ(rac_model_registry_list_proto(registry, nullptr, &out_size),
              RAC_ERROR_INVALID_ARGUMENT);

    runanywhere::v1::ModelQuery query;
    std::vector<uint8_t> query_bytes;
    ASSERT_TRUE(serialize_query(query, &query_bytes));
    ASSERT_EQ(rac_model_registry_query_proto(registry, nullptr, 0, &out_bytes, &out_size),
              RAC_SUCCESS);
    ASSERT_TRUE(out_bytes != nullptr);
    rac_model_registry_proto_free(out_bytes);
    out_bytes = reinterpret_cast<uint8_t*>(0x1);
    out_size = 99;
    ASSERT_EQ(
        rac_model_registry_query_proto(registry, invalid, sizeof(invalid), &out_bytes, &out_size),
        RAC_ERROR_INVALID_FORMAT);
    ASSERT_EQ(rac_model_registry_query_proto(registry, query_bytes.data(), query_bytes.size(),
                                             nullptr, &out_size),
              RAC_ERROR_INVALID_ARGUMENT);
    ASSERT_EQ(rac_model_registry_list_downloaded_proto(registry, nullptr, &out_size),
              RAC_ERROR_INVALID_ARGUMENT);

    rac_model_registry_destroy(registry);
    return 0;
}

#else

int test_proto_abi_reports_unavailable_without_protobuf() {
    rac_model_registry_handle_t registry = create_registry();
    ASSERT_TRUE(registry != nullptr);
    const uint8_t bytes[] = {0x00};
    ASSERT_EQ(rac_model_registry_register_proto(registry, bytes, sizeof(bytes)),
              RAC_ERROR_FEATURE_NOT_AVAILABLE);
    uint8_t* out = nullptr;
    size_t out_size = 0;
    ASSERT_EQ(rac_model_registry_query_proto(registry, bytes, sizeof(bytes), &out, &out_size),
              RAC_ERROR_FEATURE_NOT_AVAILABLE);
    ASSERT_EQ(rac_model_registry_list_downloaded_proto(registry, &out, &out_size),
              RAC_ERROR_FEATURE_NOT_AVAILABLE);
    rac_model_registry_destroy(registry);
    return 0;
}

#endif

}  // namespace

int main() {
    try {
        int failures = 0;

#define RUN(name)                                \
    do {                                         \
        std::printf("[ RUN  ] %s\n", #name);     \
        int rc = name();                         \
        if (rc == 0)                             \
            std::printf("[  OK  ] %s\n", #name); \
        else {                                   \
            std::printf("[ FAIL ] %s\n", #name); \
            ++failures;                          \
        }                                        \
    } while (0)

#ifdef RAC_HAVE_PROTOBUF
        RUN(test_full_field_round_trip_proto);
        RUN(test_expanded_proto_fields_survive_struct_state_updates);
        RUN(test_update_preserves_proto_only_fields);
        RUN(test_register_proto_preserves_proto_only_fields_on_resave);
        RUN(test_query_filters_and_downloaded_list_proto);
        RUN(test_query_source_filter_and_sorting_proto);
        RUN(test_remove_proto);
        RUN(test_canonical_result_shapes_and_typed_errors);
        RUN(test_update_missing_and_invalid_bytes);
#else
        RUN(test_proto_abi_reports_unavailable_without_protobuf);
#endif

        std::printf("\n%d test(s) failed\n", failures);
        return failures == 0 ? 0 : 1;
    } catch (const std::exception& e) {
        std::fprintf(stderr, "FATAL: %s\n", e.what());
        return 1;
    } catch (...) {
        return 1;
    }
}
