/**
 * @file test_storage_analyzer_proto.cpp
 * @brief Tests for storage analyzer proto-byte C ABI and delete planning.
 */

#include <cstdio>
#include <cstring>
#include <exception>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/storage/rac_storage_analyzer.h"

#ifdef RAC_HAVE_PROTOBUF
#include "sdk_events.pb.h"
#include "storage_types.pb.h"
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

#define ASSERT_STREQ(a, b)                                                                         \
    do {                                                                                           \
        if (std::strcmp((a), (b)) != 0) {                                                          \
            std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d\n", #a, #b, __FILE__, __LINE__); \
            return 1;                                                                              \
        }                                                                                          \
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
    return storage->existing_paths.count(path ? path : "") != 0 ? RAC_TRUE : RAC_FALSE;
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
    storage->deleted_paths.emplace_back(path ? path : "");
    storage->existing_paths.erase(path ? path : "");
    return RAC_SUCCESS;
}

rac_result_t mock_is_model_loaded(const char* model_id, rac_bool_t* out_is_loaded,
                                  void* user_data) {
    auto* storage = static_cast<MockStorage*>(user_data);
    *out_is_loaded =
        storage->loaded_models.count(model_id ? model_id : "") != 0 ? RAC_TRUE : RAC_FALSE;
    return RAC_SUCCESS;
}

rac_result_t mock_unload_model(const char* model_id, void* user_data) {
    auto* storage = static_cast<MockStorage*>(user_data);
    storage->unloaded_models.emplace_back(model_id ? model_id : "");
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

rac_model_info_t model(const char* id, const char* name, const char* local_path,
                       int64_t download_size, int64_t last_used) {
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

int save_model(rac_model_registry_handle_t registry, const char* id, const char* name,
               const char* local_path, int64_t download_size, int64_t last_used) {
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

bool poll_sdk_event(runanywhere::v1::SDKEvent* out) {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    if (rac_sdk_event_poll(&buffer) != RAC_SUCCESS) {
        return false;
    }
    bool parsed = parse_buffer(buffer, out);
    rac_proto_buffer_free(&buffer);
    return parsed;
}

bool storage_event_has_kind(const runanywhere::v1::SDKEvent& event,
                            runanywhere::v1::StorageLifecycleEventKind kind) {
    return event.category() == runanywhere::v1::EVENT_CATEGORY_STORAGE &&
           event.has_storage_lifecycle() && event.storage_lifecycle().kind() == kind;
}

int test_info_aggregation_and_model_breakdown() {
    ASSERT_EQ(rac_model_paths_set_base_dir("/base"), RAC_SUCCESS);
    rac_sdk_event_clear_queue();

    MockStorage storage;
    storage.total_space = 1000;
    storage.free_space = 400;
    storage.path_sizes["/base/RunAnywhere"] = 175;
    storage.path_sizes["/base/RunAnywhere/Cache"] = 25;
    storage.path_sizes["/base/RunAnywhere/Temp"] = 10;
    storage.path_sizes["/models/m1"] = 100;
    storage.path_sizes["/models/m2"] = 50;
    storage.existing_paths = {"/base/RunAnywhere", "/base/RunAnywhere/Cache",
                              "/base/RunAnywhere/Temp", "/models/m1", "/models/m2"};

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
    request.set_include_cache(true);
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
    ASSERT_EQ(result.info().app().documents_bytes(), 175);
    ASSERT_EQ(result.info().app().cache_bytes(), 25);
    ASSERT_EQ(result.info().app().app_support_bytes(), 10);
    ASSERT_EQ(result.info().app().total_bytes(), 210);
    ASSERT_EQ(result.info().total_models(), 2);
    ASSERT_EQ(result.info().total_models_bytes(), 150);
    ASSERT_EQ(result.info().models_size(), 2);
    bool found_last_used = false;
    for (const auto& metrics : result.info().models()) {
        if (metrics.model_id() == "m2" && metrics.has_last_used_ms() &&
            metrics.last_used_ms() == 20) {
            found_last_used = true;
        }
    }
    ASSERT_TRUE(found_last_used);

    runanywhere::v1::SDKEvent event;
    ASSERT_TRUE(poll_sdk_event(&event));
    ASSERT_TRUE(storage_event_has_kind(
        event, runanywhere::v1::STORAGE_LIFECYCLE_EVENT_KIND_INFO_COMPLETED));
    ASSERT_TRUE(event.storage_lifecycle().has_info_result());

    rac_proto_buffer_free(&buffer);
    rac_model_registry_destroy(registry);
    rac_storage_analyzer_destroy(analyzer);
    return 0;
}

int test_availability_offsets_existing_model_bytes() {
    rac_sdk_event_clear_queue();

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
    ASSERT_EQ(result.availability().shortfall_bytes(), 0);
    ASSERT_TRUE(result.availability().required_to_available_ratio() > 0.89f);

    runanywhere::v1::SDKEvent event;
    ASSERT_TRUE(poll_sdk_event(&event));
    ASSERT_TRUE(storage_event_has_kind(
        event, runanywhere::v1::STORAGE_LIFECYCLE_EVENT_KIND_AVAILABILITY_CHECKED));

    rac_proto_buffer_free(&buffer);
    rac_model_registry_destroy(registry);
    rac_storage_analyzer_destroy(analyzer);
    return 0;
}

int test_availability_includes_cache_delete_plan() {
    ASSERT_EQ(rac_model_paths_set_base_dir("/base"), RAC_SUCCESS);
    rac_sdk_event_clear_queue();

    MockStorage storage;
    storage.total_space = 2000;
    storage.free_space = 500;
    storage.path_sizes["/base/RunAnywhere/Cache"] = 125;
    storage.path_sizes["/base/RunAnywhere/Temp"] = 50;
    storage.path_sizes["/base/RunAnywhere/Downloads"] = 100;
    storage.existing_paths = {"/base/RunAnywhere/Cache", "/base/RunAnywhere/Temp",
                              "/base/RunAnywhere/Downloads"};

    rac_storage_callbacks_t callbacks = callbacks_for(&storage);
    rac_storage_analyzer_handle_t analyzer = nullptr;
    rac_model_registry_handle_t registry = nullptr;
    ASSERT_EQ(rac_storage_analyzer_create(&callbacks, &analyzer), RAC_SUCCESS);
    ASSERT_EQ(rac_model_registry_create(&registry), RAC_SUCCESS);

    runanywhere::v1::StorageAvailabilityRequest request;
    request.set_required_bytes(700);
    request.set_include_delete_plan(true);
    request.set_allow_cache_reclamation(true);
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
    ASSERT_TRUE(!result.availability().is_available());
    ASSERT_EQ(result.availability().shortfall_bytes(), 200);
    ASSERT_TRUE(result.has_delete_plan());
    ASSERT_TRUE(result.delete_plan().can_reclaim_required_bytes());
    ASSERT_EQ(result.delete_plan().required_bytes(), 200);
    ASSERT_EQ(result.delete_plan().reclaimable_bytes(), 275);
    ASSERT_EQ(result.delete_plan().candidate_count(), 3);
    ASSERT_TRUE(result.delete_plan().requires_platform_delete());
    ASSERT_EQ(result.delete_plan().candidates(0).storage_key(), "cache");

    rac_proto_buffer_free(&buffer);
    rac_model_registry_destroy(registry);
    rac_storage_analyzer_destroy(analyzer);
    return 0;
}

int test_delete_plan_blocks_loaded_missing_and_missing_path() {
    rac_sdk_event_clear_queue();

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
    ASSERT_EQ(plan.candidates(0).storage_key(), "model:m1");
    ASSERT_TRUE(plan.candidates(0).requires_platform_delete());
    ASSERT_EQ(plan.reclaimable_bytes(), 100);
    ASSERT_EQ(plan.candidate_count(), 1);
    ASSERT_TRUE(plan.requires_platform_delete());
    ASSERT_TRUE(!plan.requires_unload());
    ASSERT_TRUE(!plan.can_reclaim_required_bytes());
    ASSERT_TRUE(plan.warnings_size() >= 3);
    ASSERT_TRUE(!plan.error_message().empty());

    runanywhere::v1::SDKEvent event;
    ASSERT_TRUE(poll_sdk_event(&event));
    ASSERT_TRUE(storage_event_has_kind(
        event, runanywhere::v1::STORAGE_LIFECYCLE_EVENT_KIND_DELETE_PLAN_FAILED));
    ASSERT_TRUE(event.has_error());
    ASSERT_EQ(event.error().c_abi_code(), RAC_ERROR_INSUFFICIENT_STORAGE);

    rac_proto_buffer_free(&buffer);

    request.set_allow_loaded_models(true);
    request.clear_model_ids();
    request.add_model_ids("m2");
    request.set_required_bytes(75);
    request_bytes = serialize(request);
    rac_proto_buffer_init(&buffer);
    ASSERT_EQ(rac_storage_analyzer_delete_plan_proto(
                  analyzer, registry, reinterpret_cast<const uint8_t*>(request_bytes.data()),
                  request_bytes.size(), &buffer),
              RAC_SUCCESS);

    runanywhere::v1::StorageDeletePlan loaded_plan;
    ASSERT_TRUE(parse_buffer(buffer, &loaded_plan));
    ASSERT_EQ(loaded_plan.candidates_size(), 1);
    ASSERT_EQ(loaded_plan.candidates(0).model_id(), "m2");
    ASSERT_TRUE(loaded_plan.candidates(0).is_loaded());
    ASSERT_TRUE(loaded_plan.candidates(0).requires_unload());
    ASSERT_TRUE(loaded_plan.requires_unload());

    rac_proto_buffer_free(&buffer);
    rac_model_registry_destroy(registry);
    rac_storage_analyzer_destroy(analyzer);
    return 0;
}

int test_delete_dry_run_vs_execute() {
    rac_sdk_event_clear_queue();

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
    ASSERT_TRUE(dry_run.dry_run());
    ASSERT_TRUE(!dry_run.files_deleted());
    ASSERT_TRUE(!dry_run.registry_updated());
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
    ASSERT_TRUE(!executed.success());
    ASSERT_EQ(executed.skipped_model_ids_size(), 1);
    ASSERT_EQ(executed.skipped_model_ids(0), "m1");
    ASSERT_TRUE(storage.deleted_paths.empty());
    rac_proto_buffer_free(&buffer);

    request.set_allow_platform_delete(true);
    request_bytes = serialize(request);
    rac_proto_buffer_init(&buffer);
    ASSERT_EQ(rac_storage_analyzer_delete_proto(
                  analyzer, registry, reinterpret_cast<const uint8_t*>(request_bytes.data()),
                  request_bytes.size(), &buffer),
              RAC_SUCCESS);
    ASSERT_TRUE(parse_buffer(buffer, &executed));
    ASSERT_TRUE(executed.success());
    ASSERT_EQ(executed.deleted_bytes(), 100);
    ASSERT_TRUE(executed.files_deleted());
    ASSERT_TRUE(executed.registry_updated());
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
    rac_sdk_event_clear_queue();

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

int test_invalid_request_publishes_typed_storage_error() {
    rac_sdk_event_clear_queue();

    MockStorage storage;
    rac_storage_callbacks_t callbacks = callbacks_for(&storage);
    rac_storage_analyzer_handle_t analyzer = nullptr;
    rac_model_registry_handle_t registry = nullptr;
    ASSERT_EQ(rac_storage_analyzer_create(&callbacks, &analyzer), RAC_SUCCESS);
    ASSERT_EQ(rac_model_registry_create(&registry), RAC_SUCCESS);

    const uint8_t invalid_bytes[] = {0xff, 0xff, 0xff};
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    ASSERT_EQ(rac_storage_analyzer_delete_plan_proto(analyzer, registry, invalid_bytes,
                                                     sizeof(invalid_bytes), &buffer),
              RAC_SUCCESS);

    runanywhere::v1::StorageDeletePlan plan;
    ASSERT_TRUE(parse_buffer(buffer, &plan));
    ASSERT_TRUE(!plan.error_message().empty());

    runanywhere::v1::SDKEvent event;
    ASSERT_TRUE(poll_sdk_event(&event));
    ASSERT_TRUE(storage_event_has_kind(
        event, runanywhere::v1::STORAGE_LIFECYCLE_EVENT_KIND_DELETE_PLAN_FAILED));
    ASSERT_TRUE(event.has_error());
    ASSERT_EQ(event.error().c_abi_code(), RAC_ERROR_DECODING_ERROR);
    ASSERT_EQ(event.error().category(), runanywhere::v1::ERROR_CATEGORY_VALIDATION);

    rac_proto_buffer_free(&buffer);
    rac_model_registry_destroy(registry);
    rac_storage_analyzer_destroy(analyzer);
    return 0;
}

#endif

}  // namespace

int main() {
    try {
#ifndef RAC_HAVE_PROTOBUF
        std::printf("skip: storage analyzer proto tests require protobuf\n");
        return 0;
#else
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

        RUN(test_info_aggregation_and_model_breakdown);
        RUN(test_availability_offsets_existing_model_bytes);
        RUN(test_availability_includes_cache_delete_plan);
        RUN(test_delete_plan_blocks_loaded_missing_and_missing_path);
        RUN(test_delete_dry_run_vs_execute);
        RUN(test_empty_storage_info);
        RUN(test_invalid_request_publishes_typed_storage_error);

        std::printf("\n%d test(s) failed\n", failures);
        return failures == 0 ? 0 : 1;
#endif
    } catch (const std::exception& e) {
        std::fprintf(stderr, "FATAL: %s\n", e.what());
        return 1;
    } catch (...) {
        return 1;
    }
}
