/** @file rerank_module.cpp @brief Lifecycle and proto ABI for cross-encoder reranking. */

#include "rerank_internal.h"

#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "features/common/rac_component_lifecycle_internal.h"
#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_logger.h"
#include "rac/features/rerank/rac_rerank_component.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "rerank.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#endif

namespace {

constexpr const char* kLogCategory = "Rerank.Component";
// Guards against pathological requests; the proto boundary should never hand us
// more candidates than this in a single rerank call.
constexpr size_t kMaxCandidates = 100000;

struct rac_rerank_component {
    rac_handle_t lifecycle = nullptr;
    std::mutex mutex;
};

std::mutex& lifetime_mutex() {
    static std::mutex value;
    return value;
}

std::condition_variable& lifetime_cv() {
    static std::condition_variable value;
    return value;
}

std::unordered_map<rac_handle_t, std::shared_ptr<rac::rerank::ComponentLifetimeEntry>>&
lifetime_registry() {
    static std::unordered_map<rac_handle_t, std::shared_ptr<rac::rerank::ComponentLifetimeEntry>>
        value;
    return value;
}

rac::rerank::ComponentOperationAdmittedTestHook& admitted_hook() {
    static rac::rerank::ComponentOperationAdmittedTestHook value = nullptr;
    return value;
}

void*& admitted_hook_user_data() {
    static void* value = nullptr;
    return value;
}

thread_local rac::rerank::ComponentOperationFrame* g_operation_frame = nullptr;

bool current_thread_has_operation(rac_handle_t handle) {
    for (auto* frame = g_operation_frame; frame; frame = frame->previous) {
        if (frame->handle == handle) {
            return true;
        }
    }
    return false;
}

bool register_lifetime(rac_handle_t component, rac_handle_t lifecycle) {
    try {
        auto entry = std::make_shared<rac::rerank::ComponentLifetimeEntry>();
        entry->component = component;
        entry->lifecycle = lifecycle;
        std::lock_guard<std::mutex> lock(lifetime_mutex());
        return lifetime_registry().emplace(component, std::move(entry)).second;
    } catch (...) {
        return false;
    }
}

std::shared_ptr<rac::rerank::ComponentLifetimeEntry> close_admission(rac_handle_t handle) {
    std::lock_guard<std::mutex> lock(lifetime_mutex());
    const auto it = lifetime_registry().find(handle);
    if (it == lifetime_registry().end() || !it->second->accepting_operations) {
        return nullptr;
    }
    it->second->accepting_operations = false;
    return it->second;
}

void wait_for_operations(const std::shared_ptr<rac::rerank::ComponentLifetimeEntry>& entry) {
    std::unique_lock<std::mutex> lock(lifetime_mutex());
    lifetime_cv().wait(lock, [&] { return entry->active_operations == 0; });
}

rac_handle_t remove_lifetime(rac_handle_t handle,
                             const std::shared_ptr<rac::rerank::ComponentLifetimeEntry>& entry) {
    std::lock_guard<std::mutex> lock(lifetime_mutex());
    const auto it = lifetime_registry().find(handle);
    if (it == lifetime_registry().end() || it->second != entry || entry->active_operations != 0) {
        return nullptr;
    }
    const rac_handle_t component = entry->component;
    lifetime_registry().erase(it);
    return component;
}

// The lifecycle passes the resolved model PATH as the first argument (see
// rac_lifecycle_load → mgr->create_fn(model_path, ...)); the backend uses it both
// as its create id and as the file to load. The logical model id is tracked
// separately by the lifecycle and reported via rac_lifecycle_get_model_id.
rac_result_t create_component_service(const char* model_path, void*, rac_handle_t* out_service) {
    rac_result_t rc = rac_rerank_create(model_path, out_service);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    rc = rac_rerank_initialize(*out_service, model_path);
    if (rc != RAC_SUCCESS) {
        rac_rerank_destroy(*out_service);
        *out_service = nullptr;
    }
    return rc;
}

void destroy_component_service(rac_handle_t service, void*) {
    if (service) {
        (void)rac_rerank_cleanup(service);
        rac_rerank_destroy(service);
    }
}

rac_result_t protobuf_unavailable(rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
}

#if defined(RAC_HAVE_PROTOBUF)

rac_result_t validate_request(const runanywhere::v1::RerankRequest& request,
                              std::vector<rac_rerank_candidate_t>* out_candidates,
                              rac_rerank_options_t* out_options) {
    if (!out_candidates || !out_options) {
        return RAC_ERROR_NULL_POINTER;
    }
    out_candidates->clear();
    *out_options = RAC_RERANK_OPTIONS_DEFAULT;
    if (request.query().empty()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (static_cast<size_t>(request.candidates_size()) > kMaxCandidates) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    try {
        out_candidates->reserve(static_cast<size_t>(request.candidates_size()));
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    for (const auto& candidate : request.candidates()) {
        // Candidate strings are borrowed from the still-alive parsed request.
        out_candidates->push_back(
            rac_rerank_candidate_t{candidate.id().c_str(), candidate.text().c_str()});
    }
    if (request.has_options()) {
        out_options->top_n = request.options().top_n();
    }
    return RAC_SUCCESS;
}

rac_result_t result_to_proto(const rac_rerank_result_t& source, size_t candidate_count,
                             const char* fallback_model_id, runanywhere::v1::RerankResult* out) {
    if (!out) {
        return RAC_ERROR_NULL_POINTER;
    }
    out->Clear();
    if (source.processing_time_ms < 0 || (source.item_count > 0 && !source.items)) {
        return RAC_ERROR_ENCODING_ERROR;
    }
    // A ranked result can never contain more items than were submitted.
    if (source.item_count > candidate_count) {
        return RAC_ERROR_ENCODING_ERROR;
    }
    for (size_t i = 0; i < source.item_count; ++i) {
        const auto& item = source.items[i];
        if (item.original_index >= candidate_count) {
            out->Clear();
            return RAC_ERROR_ENCODING_ERROR;
        }
        auto* destination = out->add_items();
        destination->set_id(item.id ? item.id : "");
        destination->set_score(item.score);
        destination->set_original_index(item.original_index);
        destination->set_rank(item.rank);
    }
    out->set_processing_time_ms(source.processing_time_ms);
    // Prefer the commons-known logical model id (the lifecycle-resolved id passed
    // as fallback_model_id) over the backend-reported value: some backends (e.g.
    // llamacpp) set rac_rerank_result_t.model_id to the resolved on-device GGUF
    // PATH, and the proto model_id field must carry the logical id, never a
    // filesystem path (proto contract + no device-path leakage to the app layer).
    out->set_model_id((fallback_model_id != nullptr && fallback_model_id[0] != '\0')
                          ? fallback_model_id
                          : (source.model_id ? source.model_id : ""));
    return RAC_SUCCESS;
}

rac_result_t rerank_with_service(rac_handle_t service, const char* model_id,
                                 const uint8_t* request_bytes, size_t request_size,
                                 rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (rac_proto_bytes_validate(request_bytes, request_size) != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "RerankRequest bytes are invalid");
    }
    runanywhere::v1::RerankRequest request;
    if (!request.ParseFromArray(rac_proto_bytes_data_or_empty(request_bytes, request_size),
                                static_cast<int>(request_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse RerankRequest");
    }

    std::vector<rac_rerank_candidate_t> candidates;
    rac_rerank_options_t options = RAC_RERANK_OPTIONS_DEFAULT;
    rac_result_t rc = validate_request(request, &candidates, &options);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "invalid rerank request");
    }

    rac_rerank_result_t raw = {};
    rc = rac_rerank_rerank(service, request.query().c_str(),
                           candidates.empty() ? nullptr : candidates.data(), candidates.size(),
                           &options, &raw);
    if (rc != RAC_SUCCESS) {
        rac_rerank_result_free(&raw);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::RerankResult result;
    rc = result_to_proto(raw, candidates.size(), model_id, &result);
    if (rc == RAC_SUCCESS) {
        rc = rac::proto::copy_message(result, out_result, "failed to serialize RerankResult");
    } else {
        (void)rac_proto_buffer_set_error(out_result, rc,
                                         "backend returned an invalid rerank result");
    }
    rac_rerank_result_free(&raw);
    return rc;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

namespace rac::rerank {

ComponentOperationLease::ComponentOperationLease(rac_handle_t handle) : handle_(handle) {
    if (!handle) {
        return;
    }
    ComponentOperationAdmittedTestHook hook = nullptr;
    void* hook_user_data = nullptr;
    {
        std::lock_guard<std::mutex> lock(lifetime_mutex());
        const auto it = lifetime_registry().find(handle);
        if (it == lifetime_registry().end() ||
            (!it->second->accepting_operations && !current_thread_has_operation(handle))) {
            return;
        }
        entry_ = it->second;
        ++entry_->active_operations;
        frame_.handle = handle_;
        frame_.previous = g_operation_frame;
        g_operation_frame = &frame_;
        hook = admitted_hook();
        hook_user_data = admitted_hook_user_data();
    }
    if (hook) {
        hook(handle, hook_user_data);
    }
}

ComponentOperationLease::~ComponentOperationLease() {
    if (!entry_) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(lifetime_mutex());
        if (entry_->active_operations > 0) {
            --entry_->active_operations;
        }
        g_operation_frame = frame_.previous;
    }
    lifetime_cv().notify_all();
}

void set_component_operation_admitted_test_hook(ComponentOperationAdmittedTestHook hook,
                                                void* user_data) {
    std::lock_guard<std::mutex> lock(lifetime_mutex());
    admitted_hook() = hook;
    admitted_hook_user_data() = user_data;
}

}  // namespace rac::rerank

extern "C" {

rac_result_t rac_rerank_component_create(rac_handle_t* out_handle) {
    const rac_result_t rc = rac::features::create_lifecycle_component<rac_rerank_component>(
        out_handle, RAC_RESOURCE_TYPE_RERANK_MODEL, "Rerank.Lifecycle", create_component_service,
        destroy_component_service, kLogCategory, "Rerank component created");
    if (rc == RAC_SUCCESS) {
        auto* component = static_cast<rac_rerank_component*>(*out_handle);
        if (!register_lifetime(*out_handle, component->lifecycle)) {
            rac_lifecycle_destroy(component->lifecycle);
            delete component;
            *out_handle = nullptr;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }
    return rc;
}

rac_bool_t rac_rerank_component_is_loaded(rac_handle_t handle) {
    rac::rerank::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_FALSE;
    }
    auto* component = static_cast<rac_rerank_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_is_loaded(component->lifecycle);
}

const char* rac_rerank_component_get_model_id(rac_handle_t handle) {
    rac::rerank::ComponentOperationLease lease(handle);
    if (!lease) {
        return nullptr;
    }
    auto* component = static_cast<rac_rerank_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_model_id(component->lifecycle);
}

rac_result_t rac_rerank_component_load_model(rac_handle_t handle, const char* model_path,
                                             const char* model_id, const char* model_name) {
    rac::rerank::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (!model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* component = static_cast<rac_rerank_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    rac_handle_t service = nullptr;
    return rac_lifecycle_load(component->lifecycle, model_path, model_id, model_name, &service);
}

rac_result_t rac_rerank_component_unload(rac_handle_t handle) {
    rac::rerank::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    auto* component = static_cast<rac_rerank_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_unload(component->lifecycle);
}

rac_lifecycle_state_t rac_rerank_component_get_state(rac_handle_t handle) {
    rac::rerank::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_LIFECYCLE_STATE_IDLE;
    }
    auto* component = static_cast<rac_rerank_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_state(component->lifecycle);
}

rac_result_t rac_rerank_component_get_metrics(rac_handle_t handle,
                                              rac_lifecycle_metrics_t* out_metrics) {
    rac::rerank::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    auto* component = static_cast<rac_rerank_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_metrics(component->lifecycle, out_metrics);
}

void rac_rerank_component_destroy(rac_handle_t handle) {
    if (!handle || current_thread_has_operation(handle)) {
        if (handle) {
            RAC_LOG_WARNING(kLogCategory,
                            "Rerank component destroy refused from re-entrant operation");
        }
        return;
    }
    const auto entry = close_admission(handle);
    if (!entry) {
        return;
    }
    wait_for_operations(entry);
    auto* component = static_cast<rac_rerank_component*>(remove_lifetime(handle, entry));
    if (!component) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(component->mutex);
        rac_lifecycle_destroy(component->lifecycle);
        component->lifecycle = nullptr;
    }
    delete component;
}

rac_result_t rac_rerank_component_rerank_proto(rac_handle_t handle,
                                               const uint8_t* request_proto_bytes,
                                               size_t request_proto_size,
                                               rac_proto_buffer_t* out_result) {
    rac::rerank::ComponentOperationLease lease(handle);
    if (!lease) {
        return out_result ? rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_HANDLE,
                                                        "invalid rerank component handle")
                          : RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return protobuf_unavailable(out_result);
#else
    auto* component = static_cast<rac_rerank_component*>(lease.component());
    rac_handle_t service = nullptr;
    rac_result_t rc = rac_lifecycle_acquire_service(component->lifecycle, &service);
    if (rc != RAC_SUCCESS) {
        return out_result
                   ? rac_proto_buffer_set_error(out_result, rc, "Rerank model is not loaded")
                   : RAC_ERROR_NULL_POINTER;
    }
    const char* model_id = rac_lifecycle_get_model_id(component->lifecycle);
    rc = rerank_with_service(service, model_id, request_proto_bytes, request_proto_size, out_result);
    rac_lifecycle_release_service(component->lifecycle);
    return rc;
#endif
}

}  // extern "C"
