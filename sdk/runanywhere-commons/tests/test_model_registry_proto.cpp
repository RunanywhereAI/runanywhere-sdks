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
    model.mutable_metadata()->set_description("test chat model");
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
    // ModelInfo.artifact_type (top-level, tag 25) was reserved -- the
    // artifact oneof below is the only declaration of bundle shape now.
    model.set_acceleration_preference(runanywhere::v1::ACCELERATION_PREFERENCE_GPU);
    model.set_routing_policy(runanywhere::v1::ROUTING_POLICY_PREFER_LOCAL);
    model.mutable_compatibility()->add_compatible_frameworks(
        runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    model.mutable_compatibility()->add_compatible_formats(runanywhere::v1::MODEL_FORMAT_GGUF);
    model.set_preferred_framework(runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    model.set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED);
    // is_downloaded (tag 32) was reserved -- registry_status above is the
    // single downloaded-ness signal now.
    model.set_is_available(!local_path.empty());
    model.set_last_used_at_unix_ms(3000);
    // usage_count / sync_pending / status_message (tags 35-37) were reserved.

    // ModelInfo.expected_files (top-level) was deleted; the manifest now
    // lives solely on SingleFileArtifact/ArchiveArtifact.expected_files. The
    // multi_file artifact carries its own descriptor list instead, so this
    // model uses multi_file with a single descriptor (mirroring the original
    // intent: one primary weights file plus a tokenizer companion) rather
    // than a parallel top-level manifest.
    auto* file = model.mutable_multi_file()->add_files();
    file->set_url("weights/part-0001.gguf");
    file->set_filename("part-0001.gguf");
    file->set_is_optional(false);  // required (is_required polarity inverted to is_optional)
    file->set_size_bytes(42);
    file->set_checksum_sha256("sha256:part");
    file->set_relative_path("weights/part-0001.gguf");
    file->set_destination_path("part-0001.gguf");
    file->set_local_path(local_path + "/part-0001.gguf");
    file->set_role(runanywhere::v1::MODEL_FILE_ROLE_PRIMARY_MODEL);

    auto* tokenizer_file = model.mutable_multi_file()->add_files();
    tokenizer_file->set_filename("tokenizer.json");
    tokenizer_file->set_relative_path("tokenizer.json");
    tokenizer_file->set_destination_path("tokenizer.json");
    tokenizer_file->set_is_optional(true);  // optional (is_required=false polarity inverted)
    tokenizer_file->set_role(runanywhere::v1::MODEL_FILE_ROLE_TOKENIZER);

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
    model.mutable_metadata()->set_description("updated model");
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
    model.mutable_metadata()->set_description(name + " searchable description");
    model.mutable_metadata()->add_tags(name);
    model.set_source(source);
    model.set_registry_status(downloaded ? runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED
                                         : runanywhere::v1::MODEL_REGISTRY_STATUS_REGISTERED);
    // is_downloaded (tag 32) was reserved -- registry_status above is the
    // single downloaded-ness signal now.
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
    model.mutable_metadata()->set_description("expanded enum preservation");
    model.set_source(runanywhere::v1::MODEL_SOURCE_BUILT_IN);
    model.set_created_at_unix_ms(10);
    model.set_updated_at_unix_ms(20);
    // artifact_type (top-level, tag 25) was reserved -- built_in below (the
    // artifact oneof) is the only declaration of bundle shape now.
    model.set_built_in(true);
    model.set_registry_status(runanywhere::v1::MODEL_REGISTRY_STATUS_LOADED);
    // is_downloaded (tag 32) and status_message (tag 37) were reserved.
    model.set_is_available(true);
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
    // is_downloaded (tag 32) was reserved -- registry_status above is the
    // single downloaded-ness signal now.
    ASSERT_TRUE(decoded.has_is_available());
    ASSERT_TRUE(decoded.is_available());
    // ModelInfo.expected_files (top-level) was deleted; build_full_model_proto
    // now encodes both files (primary weights + tokenizer companion) directly
    // on the multi_file artifact.
    ASSERT_TRUE(decoded.has_multi_file());
    ASSERT_EQ(decoded.multi_file().files_size(), 2);
    ASSERT_EQ(decoded.multi_file().files(0).checksum_sha256(), "sha256:part");
    ASSERT_EQ(decoded.multi_file().files(0).role(), runanywhere::v1::MODEL_FILE_ROLE_PRIMARY_MODEL);
    ASSERT_EQ(decoded.multi_file().files(1).role(), runanywhere::v1::MODEL_FILE_ROLE_TOKENIZER);
    ASSERT_EQ(decoded.acceleration_preference(), runanywhere::v1::ACCELERATION_PREFERENCE_GPU);
    ASSERT_EQ(decoded.routing_policy(), runanywhere::v1::ROUTING_POLICY_PREFER_LOCAL);

    runanywhere::v1::ModelInfoList list;
    ASSERT_TRUE(list_model_proto(registry, &list));
    ASSERT_EQ(list.models_size(), 1);
    ASSERT_EQ(list.models(0).id(), "llama.test");
    ASSERT_TRUE(list.models(0).has_multi_file());
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
    // artifact_type (top-level, tag 25) was reserved -- built_in below (the
    // artifact oneof) is the only declaration of bundle shape now.
    ASSERT_TRUE(decoded.has_built_in());
    ASSERT_TRUE(decoded.built_in());
    ASSERT_TRUE(decoded.has_metadata());
    ASSERT_EQ(decoded.metadata().tags_size(), 1);
    ASSERT_TRUE(decoded.has_compatibility());
    ASSERT_EQ(decoded.compatibility().compatible_formats(0), runanywhere::v1::MODEL_FORMAT_TFLITE);
    ASSERT_TRUE(decoded.has_registry_status());
    ASSERT_EQ(decoded.registry_status(), runanywhere::v1::MODEL_REGISTRY_STATUS_LOADED);
    ASSERT_TRUE(decoded.has_last_used_at_unix_ms());
    // usage_count (tag 35) was reserved off the wire type -- rac_model_registry
    // still tracks it on the C struct, but it no longer round-trips on
    // ModelInfo proto.

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
    // build_minimal_update_proto sets no artifact oneof (ARTIFACT_NOT_SET), so
    // preserve_absent_proto_fields() copies the whole existing multi_file
    // artifact over verbatim -- both descriptors survive the update.
    ASSERT_TRUE(decoded.has_multi_file());
    ASSERT_EQ(decoded.multi_file().files_size(), 2);
    ASSERT_EQ(decoded.multi_file().files(0).checksum_sha256(), "sha256:part");
    ASSERT_EQ(decoded.multi_file().files(1).role(), runanywhere::v1::MODEL_FILE_ROLE_TOKENIZER);
    // is_downloaded (tag 32) was reserved -- registry_status is the single
    // downloaded-ness signal now, and it is preserved the same way.
    ASSERT_TRUE(decoded.has_registry_status());
    ASSERT_EQ(decoded.registry_status(), runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED);

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

    // ModelQuery.available_only (former tag 5) was reserved: no remaining
    // filter consumer (see model_matches_query in model_registry_proto.cpp).

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

// test_query_source_filter_and_sorting_proto deleted: it exclusively
// exercised ModelQuery.source / sort_field / descending and the
// ModelQuerySortField enum, all of which were reserved/deleted from
// idl/model_types.proto (see the "reserved 5, 8, 9, 10" comment on
// ModelQuery -- "ordering is the client's job now (a local catalog is tens
// of rows)"). model_matches_query()/sort_query_results() in
// model_registry_proto.cpp confirm there is no remaining filter/sort
// consumer for these fields.

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
    imported_file->set_is_optional(false);  // required (is_required polarity inverted to is_optional)

    std::vector<uint8_t> import_bytes;
    ASSERT_TRUE(serialize_message(import_request, &import_bytes));
    rac_proto_buffer_t import_buffer;
    rac_proto_buffer_init(&import_buffer);
    ASSERT_EQ(rac_model_registry_import_proto(registry, import_bytes.data(), import_bytes.size(),
                                              &import_buffer),
              RAC_SUCCESS);
    runanywhere::v1::ModelImportResult import_result;
    ASSERT_TRUE(parse_and_free_buffer(&import_buffer, &import_result));
    ASSERT_TRUE(import_result.has_error() == false);
    ASSERT_TRUE(import_result.registered());
    ASSERT_EQ(import_result.local_path(), "/imports/import.test");
    ASSERT_EQ(import_result.imported_bytes(), 55);
    ASSERT_TRUE(import_result.model().has_metadata());
    // ModelInfo.expected_files (top-level) was deleted; build_full_model_proto's
    // multi_file artifact (already set on the request model) carries the file
    // descriptors instead, so import_proto's "seed multi_file from
    // request.files when unset" branch never fires here.
    ASSERT_TRUE(import_result.model().has_multi_file());
    ASSERT_EQ(import_result.model().multi_file().files_size(), 2);
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

    // ModelListRequest.include_counts (former tag 2) and the
    // total/downloaded/available/filtered_count fields on ModelListResult
    // (former tags 4-7) were reserved: no facade ever SET include_counts, so
    // the gated counts were never populated in practice.
    runanywhere::v1::ModelListRequest list_request;
    list_request.mutable_query()->set_downloaded_only(true);
    runanywhere::v1::ModelListResult list_result;
    ASSERT_TRUE(call_list_models_result(registry, list_request, &list_result));
    ASSERT_TRUE(list_result.has_error() == false);
    ASSERT_EQ(list_result.models().models_size(), 1);
    ASSERT_EQ(list_result.models().models(0).id(), "import.test");

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
    ASSERT_TRUE(discovery_result.has_error() == false);
    ASSERT_EQ(discovery_result.discovered_models_size(), 1);
    ASSERT_EQ(discovery_result.discovered_models(0).model_id(), "import.test");
    ASSERT_TRUE(discovery_result.discovered_models(0).matched_registry());
    // ModelDiscoveryResult.linked_count (a count over discovered_models,
    // former tags 3/4/7/8) was reserved.

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
    ASSERT_TRUE(refresh_result.has_error() == false);
    ASSERT_EQ(refresh_result.models().models_size(), 1);
    // ModelRegistryRefreshResult.downloaded_count / available_count (counts
    // over `models`, former tags 3-6/10-12) were reserved.

    rac_proto_buffer_t delete_buffer;
    rac_proto_buffer_init(&delete_buffer);
    ASSERT_EQ(rac_model_registry_remove_proto_buffer(registry, "import.test", &delete_buffer),
              RAC_SUCCESS);
    runanywhere::v1::ModelDeleteResult delete_result;
    ASSERT_TRUE(parse_and_free_buffer(&delete_buffer, &delete_result));
    // files_deleted/registry_updated/was_loaded/warnings were reserved off
    // ModelDeleteResult -- success is now the absence of `error`.
    ASSERT_TRUE(delete_result.has_error() == false);

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
