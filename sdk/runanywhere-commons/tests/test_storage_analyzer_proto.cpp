/**
 * @file test_storage_analyzer_proto.cpp
 * @brief Tests for storage analyzer proto-byte C ABI and delete planning.
 */

#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/storage/rac_storage_analyzer.h"

#ifdef RAC_HAVE_PROTOBUF
#include "storage_types.pb.h"
#endif

namespace {

#define ASSERT_TRUE(cond) do { \
    if (!(cond)) { \
        std::fprintf(stderr, "ASSERT FAILED: %s @ %s:%d\n", #cond, __FILE__, __LINE__); \
        return 1; \
    } \
} while (0)

#define ASSERT_EQ(a, b) do { \
    if (!((a) == (b))) { \
        std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d\n", #a, #b, __FILE__, __LINE__); \
        return 1; \
    } \
} while (0)

#define ASSERT_STREQ(a, b) do { \
    if (std::strcmp((a), (b)) != 0) { \
        std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d\n", #a, #b, __FILE__, __LINE__); \
        return 1; \
    } \
} while (0)

struct MockStorage {
    int64_t total_space = 0;
    int64_t free_space = 0;
    std::unordered_map<std::string, int64_t> path_sizes;
    std::unordered_set<std::string> existing_paths;
    std::unordered_set<std::string> loaded_models;
    std::vector<std::string> deleted_paths;
    std::vector<std::string> unloaded_models;
};

int64_t mock_calculate_dir_size(const char* path, void* user_data) {
    auto* storage = static_cast<MockStorage*>(user_data);
    auto it = storage->path_sizes.find(path ? path : "");
    return it == storage->path_sizes.end() ? 0 : it->second;
}

int64_t mock_get_file_size(const char* path, void* user_data) {
    return mock_calculate_dir_size(path, user_data);
}

rac_bool_t mock_path_exists(const char* path, rac_bool_t* is_directory, void* user_data) {
    auto* storage = static_cast<MockStorage*>(user_data);
    if (is_directory) {
        *is_directory = RAC_TRUE;
    }
    return storage->existing_paths.count(path ? path : "") ? RAC_TRUE : RAC_FALSE;
}

int64_t mock_get_available_space(void* user_data) {
    return static_cast<MockStorage*>(user_data)->free_space;
}

int64_t mock_get_total_space(void* user_data) {
    return static_cast<MockStorage*>(user_data)->total_space;
}

rac_result_t mock_delete_path(const char* path, int recursive, void* user_data) {
    (void)recursive;
    auto* storage = static_cast<MockStorage*>(user_data);
    storage->deleted_paths.push_back(path ? path : "");
    storage->existing_paths.erase(path ? path : "");
    return RAC_SUCCESS;
}

rac_result_t mock_is_model_loaded(const char* model_id,
                                  rac_bool_t* out_is_loaded,
                                  void* user_data) {
    auto* storage = static_cast<MockStorage*>(user_data);
    *out_is_loaded = storage->loaded_models.count(model_id ? model_id : "") ? RAC_TRUE : RAC_FALSE;
    return RAC_SUCCESS;
}

rac_result_t mock_unload_model(const char* model_id, void* user_data) {
    auto* storage = static_cast<MockStorage*>(user_data);
    storage->unloaded_models.push_back(model_id ? model_id : "");
    storage->loaded_models.erase(model_id ? model_id : "");
    return RAC_SUCCESS;
}

rac_storage_callbacks_t callbacks_for(MockStorage* storage) {
    rac_storage_callbacks_t callbacks{};
    callbacks.calculate_dir_size = mock_calculate_dir_size;
    callbacks.get_file_size = mock_get_file_size;
    callbacks.path_exists = mock_path_exists;
    callbacks.get_available_space = mock_get_available_space;
    callbacks.get_total_space = mock_get_total_space;
    callbacks.delete_path = mock_delete_path;
    callbacks.is_model_loaded = mock_is_model_loaded;
    callbacks.unload_model = mock_unload_model;
    callbacks.user_data = storage;
    return callbacks;
}

rac_model_info_t model(const char* id,
                       const char* name,
                       const char* local_path,
                       int64_t download_size,
                       int64_t last_used) {
    rac_model_info_t info{};
    info.id = const_cast<char*>(id);
    info.name = const_cast<char*>(name);
    info.framework = RAC_FRAMEWORK_LLAMACPP;
    info.format = RAC_MODEL_FORMAT_GGUF;
    info.local_path = const_cast<char*>(local_path);
    info.download_size = download_size;
    info.last_used = last_used;
    return info;
}

int save_model(rac_model_registry_handle_t registry,
               const char* id,
               const char* name,
               const char* local_path,
               int64_t download_size,
               int64_t last_used) {
    rac_model_info_t info = model(id, name, local_path, download_size, last_used);
    ASSERT_EQ(rac_model_registry_save(registry, &info), RAC_SUCCESS);
    return 0;
}

#ifdef RAC_HAVE_PROTOBUF

std::string serialize(const google::protobuf::Message& message) {
    std::string bytes;
    if (!message.SerializeToString(&bytes)) {
        return {};
    }
    return bytes;
}

template <typename Proto>
bool parse_buffer(const rac_proto_buffer_t& buffer, Proto* out) {
    return out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

int test_info_aggregation_and_model_breakdown() {
    MockStorage storage;
    storage.total_space = 1000;
    storage.free_space = 400;
    storage.path_sizes["/base/RunAnywhere"] = 175;
    storage.path_sizes["/models/m1"] = 100;
    storage.path_sizes["/models/m2"] = 50;
    storage.existing_paths = {"/models/m1", "/models/m2"};

    rac_storage_callbacks_t callbacks = callbacks_for(&storage);
    rac_storage_analyzer_handle_t analyzer = nullptr;
    rac_model_registry_handle_t registry = nullptr;
    ASSERT_EQ(rac_storage_analyzer_create(&callbacks, &analyzer), RAC_SUCCESS);
    ASSERT_EQ(rac_model_registry_create(&registry), RAC_SUCCESS);
    ASSERT_EQ(save_model(registry, "m1", "Model 1", "/models/m1", 100, 10), 0);
    ASSERT_EQ(save_model(registry, "m2", "Model 2", "/models/m2", 50, 20), 0);

    runanywhere::v1::StorageInfoRequest request;
    request.set_include_device(true);
    request.set_include_app(true);
    request.set_include_models(true);
    std::string request_bytes = serialize(request);

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    ASSERT_EQ(rac_storage_analyzer_info_proto(
                  analyzer, registry, reinterpret_cast<const uint8_t*>(request_bytes.data()),
                  request_bytes.size(), &buffer),
              RAC_SUCCESS);

    runanywhere::v1::StorageInfoResult result;
    ASSERT_TRUE(parse_buffer(buffer, &result));
    ASSERT_TRUE(result.success());
    ASSERT_EQ(result.info().device().total_bytes(), 1000);
    ASSERT_EQ(result.info().device().free_bytes(), 400);
    ASSERT_EQ(result.info().device().used_bytes(), 600);
    ASSERT_TRUE(result.info().device().used_percent() > 59.9f);
    ASSERT_EQ(result.info().total_models(), 2);
    ASSERT_EQ(result.info().total_models_bytes(), 150);
    ASSERT_EQ(result.info().models_size(), 2);

    rac_proto_buffer_free(&buffer);
    rac_model_registry_destroy(registry);
    rac_storage_analyzer_destroy(analyzer);
    return 0;
}

int test_availability_offsets_existing_model_bytes() {
    MockStorage storage;
    storage.total_space = 2000;
    storage.free_space = 500;
    storage.path_sizes["/models/m1"] = 100;
    storage.existing_paths = {"/models/m1"};

    rac_storage_callbacks_t callbacks = callbacks_for(&storage);
    rac_storage_analyzer_handle_t analyzer = nullptr;
    rac_model_registry_handle_t registry = nullptr;
    ASSERT_EQ(rac_storage_analyzer_create(&callbacks, &analyzer), RAC_SUCCESS);
    ASSERT_EQ(rac_model_registry_create(&registry), RAC_SUCCESS);
    ASSERT_EQ(save_model(registry, "m1", "Model 1", "/models/m1", 100, 10), 0);

    runanywhere::v1::StorageAvailabilityRequest request;
    request.set_model_id("m1");
    request.set_required_bytes(550);
    request.set_include_existing_model_bytes(true);
    std::string request_bytes = serialize(request);

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    ASSERT_EQ(rac_storage_analyzer_availability_proto(
                  analyzer, registry, reinterpret_cast<const uint8_t*>(request_bytes.data()),
                  request_bytes.size(), &buffer),
              RAC_SUCCESS);

    runanywhere::v1::StorageAvailabilityResult result;
    ASSERT_TRUE(parse_buffer(buffer, &result));
    ASSERT_TRUE(result.success());
    ASSERT_EQ(result.availability().required_bytes(), 450);
    ASSERT_EQ(result.availability().available_bytes(), 500);
    ASSERT_TRUE(result.availability().is_available());

    rac_proto_buffer_free(&buffer);
    rac_model_registry_destroy(registry);
    rac_storage_analyzer_destroy(analyzer);
    return 0;
}

int test_delete_plan_blocks_loaded_missing_and_missing_path() {
    MockStorage storage;
    storage.total_space = 2000;
    storage.free_space = 500;
    storage.path_sizes["/models/m1"] = 100;
    storage.path_sizes["/models/m2"] = 75;
    storage.existing_paths = {"/models/m1", "/models/m2"};
    storage.loaded_models.insert("m2");

    rac_storage_callbacks_t callbacks = callbacks_for(&storage);
    rac_storage_analyzer_handle_t analyzer = nullptr;
    rac_model_registry_handle_t registry = nullptr;
    ASSERT_EQ(rac_storage_analyzer_create(&callbacks, &analyzer), RAC_SUCCESS);
    ASSERT_EQ(rac_model_registry_create(&registry), RAC_SUCCESS);
    ASSERT_EQ(save_model(registry, "m1", "Model 1", "/models/m1", 100, 20), 0);
    ASSERT_EQ(save_model(registry, "m2", "Model 2", "/models/m2", 75, 10), 0);
    ASSERT_EQ(save_model(registry, "no-path", "No Path", "", 40, 5), 0);

    runanywhere::v1::StorageDeletePlanRequest request;
    request.add_model_ids("m1");
    request.add_model_ids("m2");
    request.add_model_ids("missing");
    request.add_model_ids("no-path");
    request.set_required_bytes(120);
    request.set_oldest_first(true);
    std::string request_bytes = serialize(request);

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    ASSERT_EQ(rac_storage_analyzer_delete_plan_proto(
                  analyzer, registry, reinterpret_cast<const uint8_t*>(request_bytes.data()),
                  request_bytes.size(), &buffer),
              RAC_SUCCESS);

    runanywhere::v1::StorageDeletePlan plan;
    ASSERT_TRUE(parse_buffer(buffer, &plan));
    ASSERT_EQ(plan.candidates_size(), 1);
    ASSERT_EQ(plan.candidates(0).model_id(), "m1");
    ASSERT_EQ(plan.reclaimable_bytes(), 100);
    ASSERT_TRUE(!plan.can_reclaim_required_bytes());
    ASSERT_TRUE(plan.warnings_size() >= 3);
    ASSERT_TRUE(!plan.error_message().empty());

    rac_proto_buffer_free(&buffer);
    rac_model_registry_destroy(registry);
    rac_storage_analyzer_destroy(analyzer);
    return 0;
}

int test_delete_dry_run_vs_execute() {
    MockStorage storage;
    storage.total_space = 2000;
    storage.free_space = 500;
    storage.path_sizes["/models/m1"] = 100;
    storage.existing_paths = {"/models/m1"};

    rac_storage_callbacks_t callbacks = callbacks_for(&storage);
    rac_storage_analyzer_handle_t analyzer = nullptr;
    rac_model_registry_handle_t registry = nullptr;
    ASSERT_EQ(rac_storage_analyzer_create(&callbacks, &analyzer), RAC_SUCCESS);
    ASSERT_EQ(rac_model_registry_create(&registry), RAC_SUCCESS);
    ASSERT_EQ(save_model(registry, "m1", "Model 1", "/models/m1", 100, 20), 0);

    runanywhere::v1::StorageDeleteRequest request;
    request.add_model_ids("m1");
    request.set_delete_files(true);
    request.set_clear_registry_paths(true);
    request.set_dry_run(true);
    std::string request_bytes = serialize(request);

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    ASSERT_EQ(rac_storage_analyzer_delete_proto(
                  analyzer, registry, reinterpret_cast<const uint8_t*>(request_bytes.data()),
                  request_bytes.size(), &buffer),
              RAC_SUCCESS);
    runanywhere::v1::StorageDeleteResult dry_run;
    ASSERT_TRUE(parse_buffer(buffer, &dry_run));
    ASSERT_TRUE(dry_run.success());
    ASSERT_EQ(dry_run.deleted_bytes(), 100);
    ASSERT_EQ(dry_run.deleted_model_ids_size(), 1);
    ASSERT_TRUE(storage.deleted_paths.empty());
    rac_proto_buffer_free(&buffer);

    request.set_dry_run(false);
    request_bytes = serialize(request);
    rac_proto_buffer_init(&buffer);
    ASSERT_EQ(rac_storage_analyzer_delete_proto(
                  analyzer, registry, reinterpret_cast<const uint8_t*>(request_bytes.data()),
                  request_bytes.size(), &buffer),
              RAC_SUCCESS);
    runanywhere::v1::StorageDeleteResult executed;
    ASSERT_TRUE(parse_buffer(buffer, &executed));
    ASSERT_TRUE(executed.success());
    ASSERT_EQ(executed.deleted_bytes(), 100);
    ASSERT_EQ(storage.deleted_paths.size(), 1U);
    ASSERT_EQ(storage.deleted_paths[0], "/models/m1");

    rac_model_info_t** downloaded = nullptr;
    size_t downloaded_count = 99;
    ASSERT_EQ(rac_model_registry_get_downloaded(registry, &downloaded, &downloaded_count),
              RAC_SUCCESS);
    ASSERT_EQ(downloaded_count, 0U);
    rac_model_info_array_free(downloaded, downloaded_count);

    rac_proto_buffer_free(&buffer);
    rac_model_registry_destroy(registry);
    rac_storage_analyzer_destroy(analyzer);
    return 0;
}

int test_empty_storage_info() {
    MockStorage storage;
    rac_storage_callbacks_t callbacks = callbacks_for(&storage);
    rac_storage_analyzer_handle_t analyzer = nullptr;
    rac_model_registry_handle_t registry = nullptr;
    ASSERT_EQ(rac_storage_analyzer_create(&callbacks, &analyzer), RAC_SUCCESS);
    ASSERT_EQ(rac_model_registry_create(&registry), RAC_SUCCESS);

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    ASSERT_EQ(rac_storage_analyzer_info_proto(analyzer, registry, nullptr, 0, &buffer),
              RAC_SUCCESS);

    runanywhere::v1::StorageInfoResult result;
    ASSERT_TRUE(parse_buffer(buffer, &result));
    ASSERT_TRUE(result.success());
    ASSERT_EQ(result.info().device().total_bytes(), 0);
    ASSERT_EQ(result.info().device().free_bytes(), 0);
    ASSERT_EQ(result.info().device().used_bytes(), 0);
    ASSERT_EQ(result.info().total_models(), 0);
    ASSERT_EQ(result.info().total_models_bytes(), 0);

    rac_proto_buffer_free(&buffer);
    rac_model_registry_destroy(registry);
    rac_storage_analyzer_destroy(analyzer);
    return 0;
}

#endif

}  // namespace

int main() {
#ifndef RAC_HAVE_PROTOBUF
    std::printf("skip: storage analyzer proto tests require protobuf\n");
    return 0;
#else
    int failures = 0;

#define RUN(name) do { \
    std::printf("[ RUN  ] %s\n", #name); \
    int rc = name(); \
    if (rc == 0) std::printf("[  OK  ] %s\n", #name); \
    else        { std::printf("[ FAIL ] %s\n", #name); ++failures; } \
} while (0)

    RUN(test_info_aggregation_and_model_breakdown);
    RUN(test_availability_offsets_existing_model_bytes);
    RUN(test_delete_plan_blocks_loaded_missing_and_missing_path);
    RUN(test_delete_dry_run_vs_execute);
    RUN(test_empty_storage_info);

    std::printf("\n%d test(s) failed\n", failures);
    return failures == 0 ? 0 : 1;
#endif
}
