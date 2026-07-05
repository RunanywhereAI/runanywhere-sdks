/**
 * @file lifecycle_manager.cpp
 * @brief RunAnywhere Commons - Lifecycle Manager (per-handle facade)
 *
 * The `rac_lifecycle_*` C API is a thin, per-handle FACADE over the canonical
 * global model-lifecycle store (`g_loaded`, keyed by `SDKComponent`) that lives
 * in `model_lifecycle.cpp`. A `LifecycleManager` no longer owns any model
 * state: it carries only its configuration, per-handle metrics, and a pin
 * bookkeeping token. Loading a model through this facade calls the feature
 * module's own create callback (path-based, no registry/download) and stores
 * the resulting service into `g_loaded` so the voice-agent lifecycle path and
 * `rac_model_lifecycle_current_model_proto` see component-loaded models too.
 *
 * Semantics preserved from the previous standalone implementation:
 *   - latest-load-wins per modality (auto-unload previous) with a refcount
 *     drain fence (now `LoadedModel::active_refs` + `g_lifecycle_cv`),
 *   - duplicate-load short-circuit on the same path,
 *   - acquire/release pinning prevents unload while a service is in use,
 *   - per-handle load/unload/failure metrics.
 *
 * Owner-scoping rule: unload/reset/destroy and all queries only ever touch the
 * `g_loaded[component]` slot when its `owner_lifecycle == this manager`, so
 * destroying a never-loaded component handle (e.g. a fresh voice agent) never
 * evicts a user's registry-loaded model.
 *
 * When protobuf is unavailable (`g_loaded`/`LoadedModel` do not exist), the
 * original self-contained per-handle implementation is used verbatim under the
 * `#else` branch below.
 */

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <new>
#include <string>

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"

#if defined(RAC_HAVE_PROTOBUF)
#include <map>
#include <memory>

#include "../model_lifecycle_internal.h"
#endif

#if defined(RAC_HAVE_PROTOBUF)

// FACADE IMPLEMENTATION (canonical: backed by g_loaded)

namespace {

namespace detail = rac::core::model_lifecycle::detail;
using runanywhere::v1::ComponentLifecycleState;
using runanywhere::v1::ModelCategory;
using runanywhere::v1::SDKComponent;

/**
 * Per-handle facade state. Owns NO model storage — that lives in `g_loaded`.
 */
struct LifecycleManager {
    rac_resource_type_t resource_type{RAC_RESOURCE_TYPE_LLM_MODEL};
    SDKComponent component{runanywhere::v1::SDK_COMPONENT_UNSPECIFIED};
    std::string logger_category{};
    void* user_data{nullptr};

    rac_lifecycle_create_service_fn create_fn{nullptr};
    rac_lifecycle_destroy_service_fn destroy_fn{nullptr};

    // Per-handle metrics (exact parity with the previous implementation).
    int32_t load_count{0};
    double total_load_time_ms{0.0};
    int32_t failed_loads{0};
    int32_t total_unloads{0};
    int64_t start_time_ms{0};
    int64_t last_event_time_ms{0};

    // Serializes load/unload/reset on THIS handle. Lock ordering is always
    // mgr->mutex (outer) -> g_lifecycle_mutex (inner); never the reverse.
    std::mutex mutex{};

    // Pin bookkeeping. `pinned` holds the exact entry this handle acquire()d so
    // release() never re-looks-up the map (the entry may already be erased and
    // draining). Guarded by g_lifecycle_mutex.
    std::shared_ptr<detail::LoadedModel> pinned{};
    int pin_depth{0};

    LifecycleManager() { start_time_ms = detail::now_ms(); }
};

SDKComponent component_for_resource_type(rac_resource_type_t type) {
    switch (type) {
        case RAC_RESOURCE_TYPE_LLM_MODEL:
            return runanywhere::v1::SDK_COMPONENT_LLM;
        case RAC_RESOURCE_TYPE_STT_MODEL:
            return runanywhere::v1::SDK_COMPONENT_STT;
        case RAC_RESOURCE_TYPE_TTS_VOICE:
            return runanywhere::v1::SDK_COMPONENT_TTS;
        case RAC_RESOURCE_TYPE_VAD_MODEL:
            return runanywhere::v1::SDK_COMPONENT_VAD;
        case RAC_RESOURCE_TYPE_VLM_MODEL:
            return runanywhere::v1::SDK_COMPONENT_VLM;
        case RAC_RESOURCE_TYPE_DIFFUSION_MODEL:
            return runanywhere::v1::SDK_COMPONENT_DIFFUSION;
        case RAC_RESOURCE_TYPE_EMBEDDINGS_MODEL:
            return runanywhere::v1::SDK_COMPONENT_EMBEDDINGS;
        case RAC_RESOURCE_TYPE_DIARIZATION_MODEL:
        default:
            return runanywhere::v1::SDK_COMPONENT_UNSPECIFIED;
    }
}

// Inverse of detail::component_for_category. Lets component-loaded entries
// participate in the category filters of rac_model_lifecycle_current_model_proto.
ModelCategory category_for_component(SDKComponent component) {
    switch (component) {
        case runanywhere::v1::SDK_COMPONENT_LLM:
            return runanywhere::v1::MODEL_CATEGORY_LANGUAGE;
        case runanywhere::v1::SDK_COMPONENT_STT:
            return runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION;
        case runanywhere::v1::SDK_COMPONENT_TTS:
            return runanywhere::v1::MODEL_CATEGORY_SPEECH_SYNTHESIS;
        case runanywhere::v1::SDK_COMPONENT_VAD:
            return runanywhere::v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;
        case runanywhere::v1::SDK_COMPONENT_EMBEDDINGS:
            return runanywhere::v1::MODEL_CATEGORY_EMBEDDING;
        case runanywhere::v1::SDK_COMPONENT_VLM:
            return runanywhere::v1::MODEL_CATEGORY_MULTIMODAL;
        case runanywhere::v1::SDK_COMPONENT_DIFFUSION:
            return runanywhere::v1::MODEL_CATEGORY_IMAGE_GENERATION;
        default:
            return runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED;
    }
}

// Decompose the per-modality service wrapper into the engine-level
// (ops, impl) pair stored in the LoadedModel. Every rac_<mod>_service_t shares
// the layout { const <mod>_service_ops_t* ops; void* impl; const char* model_id; }.
void decompose_service(SDKComponent component, rac_handle_t service, detail::LoadedModel* entry) {
    if (!service || !entry) {
        return;
    }
    switch (component) {
        case runanywhere::v1::SDK_COMPONENT_LLM: {
            auto* s = static_cast<rac_llm_service_t*>(service);
            entry->llm_ops = s->ops;
            entry->impl = s->impl;
            break;
        }
        case runanywhere::v1::SDK_COMPONENT_STT: {
            auto* s = static_cast<rac_stt_service_t*>(service);
            entry->stt_ops = s->ops;
            entry->impl = s->impl;
            break;
        }
        case runanywhere::v1::SDK_COMPONENT_TTS: {
            auto* s = static_cast<rac_tts_service_t*>(service);
            entry->tts_ops = s->ops;
            entry->impl = s->impl;
            break;
        }
        case runanywhere::v1::SDK_COMPONENT_VAD: {
            auto* s = static_cast<rac_vad_service_t*>(service);
            entry->vad_ops = s->ops;
            entry->impl = s->impl;
            break;
        }
        case runanywhere::v1::SDK_COMPONENT_EMBEDDINGS: {
            auto* s = static_cast<rac_embeddings_service_t*>(service);
            entry->embeddings_ops = s->ops;
            entry->impl = s->impl;
            break;
        }
        case runanywhere::v1::SDK_COMPONENT_VLM: {
            auto* s = static_cast<rac_vlm_service_t*>(service);
            entry->vlm_ops = s->ops;
            entry->impl = s->impl;
            break;
        }
        case runanywhere::v1::SDK_COMPONENT_DIFFUSION: {
            auto* s = static_cast<rac_diffusion_service_t*>(service);
            entry->diffusion_ops = s->ops;
            entry->impl = s->impl;
            break;
        }
        default:
            break;
    }
}

// Erase the current occupant of g_loaded[component] (if any) and install
// `entry`. Returns the displaced occupant (if any) so the caller can drain +
// destroy it OUTSIDE g_lifecycle_mutex.
std::shared_ptr<detail::LoadedModel> install_entry(SDKComponent component,
                                                   std::shared_ptr<detail::LoadedModel> entry) {
    std::shared_ptr<detail::LoadedModel> displaced;
    std::lock_guard<std::mutex> lock(detail::g_lifecycle_mutex);
    auto it = detail::g_loaded.find(component);
    if (it != detail::g_loaded.end()) {
        displaced = it->second;
        detail::g_loaded.erase(it);
    }
    detail::g_loaded[component] = std::move(entry);
    return displaced;
}

}  // namespace

extern "C" {

rac_result_t rac_lifecycle_create(const rac_lifecycle_config_t* config,
                                  rac_lifecycle_create_service_fn create_fn,
                                  rac_lifecycle_destroy_service_fn destroy_fn,
                                  rac_handle_t* out_handle) {
    if (config == nullptr || create_fn == nullptr || out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = new (std::nothrow) LifecycleManager();
    if (!mgr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    mgr->resource_type = config->resource_type;
    mgr->component = component_for_resource_type(config->resource_type);
    mgr->logger_category = config->logger_category ? config->logger_category : "Lifecycle";
    mgr->user_data = config->user_data;
    mgr->create_fn = create_fn;
    mgr->destroy_fn = destroy_fn;

    *out_handle = static_cast<rac_handle_t>(mgr);
    return RAC_SUCCESS;
}

rac_result_t rac_lifecycle_load(rac_handle_t handle, const char* model_path, const char* model_id,
                                const char* model_name, rac_handle_t* out_service) {
    if (handle == nullptr || model_path == nullptr || out_service == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (model_id == nullptr) {
        model_id = model_path;
    }
    if (model_name == nullptr) {
        model_name = model_id;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> mgr_lock(mgr->mutex);

    if (mgr->component == runanywhere::v1::SDK_COMPONENT_UNSPECIFIED) {
        // No SDKComponent maps to this resource type (e.g. diarization); the
        // facade has nowhere to store the model.
        RAC_LOG_ERROR(mgr->logger_category.c_str(),
                      "Lifecycle load unsupported for resource type %d",
                      static_cast<int>(mgr->resource_type));
        return RAC_ERROR_NOT_SUPPORTED;
    }

    const int64_t start_time = detail::now_ms();

    // 1. Duplicate-load short-circuit: same handle, same path, still READY.
    {
        std::lock_guard<std::mutex> g(detail::g_lifecycle_mutex);
        auto it = detail::g_loaded.find(mgr->component);
        if (it != detail::g_loaded.end() && it->second->owner_lifecycle == mgr &&
            it->second->resolved_path == model_path &&
            it->second->state == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY &&
            it->second->service_handle != nullptr) {
            RAC_LOG_INFO(mgr->logger_category.c_str(),
                         "Model already loaded, skipping duplicate load");
            *out_service = it->second->service_handle;
            return RAC_SUCCESS;
        }
    }

    // 2. Evict whatever occupies this modality's slot (latest-load-wins). The
    //    drain fence inside destroy_loaded_model replaces the old service_cv
    //    wait. Only count/log an auto-unload when the evicted entry was a model
    //    this handle had successfully loaded.
    std::shared_ptr<detail::LoadedModel> previous;
    bool evicted_mine_loaded = false;
    {
        std::lock_guard<std::mutex> g(detail::g_lifecycle_mutex);
        auto it = detail::g_loaded.find(mgr->component);
        if (it != detail::g_loaded.end()) {
            evicted_mine_loaded =
                it->second->owner_lifecycle == mgr &&
                it->second->state == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY;
            previous = it->second;
            detail::g_loaded.erase(it);
        }
    }
    if (previous) {
        if (evicted_mine_loaded) {
            RAC_LOG_INFO(mgr->logger_category.c_str(),
                         "Auto-unloading previous model '%s' before loading '%s'",
                         previous->model_id.c_str(), model_id);
        }
        detail::destroy_loaded_model(previous);
        if (evicted_mine_loaded) {
            mgr->total_unloads++;
            mgr->last_event_time_ms = detail::now_ms();
        }
    }

    // 3. Create the backend service via the feature module's own callback.
    //    NOT holding g_lifecycle_mutex — model creation can take seconds.
    RAC_LOG_INFO(mgr->logger_category.c_str(), "Loading model: %s (path: %s)", model_id,
                 model_path);
    rac_handle_t service = nullptr;
    const rac_result_t result = mgr->create_fn(model_path, mgr->user_data, &service);
    const auto load_time_ms = static_cast<double>(detail::now_ms() - start_time);

    if (result == RAC_SUCCESS && service != nullptr) {
        auto entry = std::make_shared<detail::LoadedModel>();
        entry->component = mgr->component;
        entry->state = runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY;
        entry->model_id = model_id;
        entry->model_name = model_name;
        entry->resolved_path = model_path;
        entry->category = category_for_component(mgr->component);
        entry->primitive = detail::primitive_for_component(mgr->component);
        entry->owner_lifecycle = mgr;
        entry->service_handle = service;
        decompose_service(mgr->component, service, entry.get());
        entry->loaded_at_ms = detail::now_ms();
        entry->updated_at_ms = entry->loaded_at_ms;
        auto destroy_fn = mgr->destroy_fn;
        void* user_data = mgr->user_data;
        entry->destroy = [destroy_fn, service, user_data]() {
            if (destroy_fn) {
                destroy_fn(service, user_data);
            }
        };

        std::shared_ptr<detail::LoadedModel> displaced = install_entry(mgr->component, entry);
        detail::destroy_loaded_model(displaced);

        mgr->load_count++;
        mgr->total_load_time_ms += load_time_ms;
        mgr->last_event_time_ms = detail::now_ms();
        RAC_LOG_INFO(mgr->logger_category.c_str(), "Loaded model in %dms",
                     static_cast<int>(load_time_ms));

        *out_service = service;
        return RAC_SUCCESS;
    }

    // 4. Failure: record an owner-tagged ERROR entry so get_state() -> FAILED,
    //    mirroring System A's own ERROR-entry pattern.
    mgr->failed_loads++;
    mgr->last_event_time_ms = detail::now_ms();
    {
        auto failed = std::make_shared<detail::LoadedModel>();
        failed->component = mgr->component;
        failed->state = runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR;
        failed->model_id = model_id;
        failed->model_name = model_name;
        failed->resolved_path = model_path;
        failed->category = category_for_component(mgr->component);
        failed->primitive = detail::primitive_for_component(mgr->component);
        failed->owner_lifecycle = mgr;
        failed->error_message = rac_error_message(result);
        failed->updated_at_ms = detail::now_ms();

        std::shared_ptr<detail::LoadedModel> displaced = install_entry(mgr->component, failed);
        detail::destroy_loaded_model(displaced);
    }
    RAC_LOG_ERROR(mgr->logger_category.c_str(), "Failed to load model");
    return result;
}

rac_result_t rac_lifecycle_acquire_service(rac_handle_t handle, rac_handle_t* out_service) {
    if (handle == nullptr || out_service == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> g(detail::g_lifecycle_mutex);
    auto it = detail::g_loaded.find(mgr->component);
    if (it == detail::g_loaded.end() || it->second->owner_lifecycle != mgr ||
        it->second->state != runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY ||
        it->second->service_handle == nullptr) {
        return RAC_ERROR_NOT_INITIALIZED;
    }
    it->second->active_refs += 1;
    mgr->pinned = it->second;
    mgr->pin_depth++;
    *out_service = it->second->service_handle;
    return RAC_SUCCESS;
}

void rac_lifecycle_release_service(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    {
        std::lock_guard<std::mutex> g(detail::g_lifecycle_mutex);
        if (mgr->pinned && mgr->pin_depth > 0) {
            if (mgr->pinned->active_refs > 0) {
                mgr->pinned->active_refs -= 1;
            }
            mgr->pin_depth--;
            if (mgr->pin_depth == 0) {
                mgr->pinned.reset();
            }
        }
    }
    detail::g_lifecycle_cv.notify_all();
}

namespace {

rac_result_t lifecycle_unload_impl(LifecycleManager* mgr, bool count_unload) {
    std::lock_guard<std::mutex> mgr_lock(mgr->mutex);

    std::shared_ptr<detail::LoadedModel> previous;
    bool was_loaded = false;
    {
        std::lock_guard<std::mutex> g(detail::g_lifecycle_mutex);
        auto it = detail::g_loaded.find(mgr->component);
        if (it != detail::g_loaded.end() && it->second->owner_lifecycle == mgr) {
            was_loaded = it->second->state == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY;
            previous = it->second;
            detail::g_loaded.erase(it);
        }
    }

    if (previous) {
        if (was_loaded) {
            RAC_LOG_INFO(mgr->logger_category.c_str(), "Unloading model: %s",
                         previous->model_id.c_str());
        }
        detail::destroy_loaded_model(previous);
        if (count_unload && was_loaded) {
            mgr->total_unloads++;
        }
        mgr->last_event_time_ms = detail::now_ms();
    }
    return RAC_SUCCESS;
}

}  // namespace

rac_result_t rac_lifecycle_unload(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    return lifecycle_unload_impl(static_cast<LifecycleManager*>(handle), /*count_unload=*/true);
}

rac_result_t rac_lifecycle_reset(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    return lifecycle_unload_impl(static_cast<LifecycleManager*>(handle), /*count_unload=*/false);
}

rac_lifecycle_state_t rac_lifecycle_get_state(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_LIFECYCLE_STATE_IDLE;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> g(detail::g_lifecycle_mutex);
    auto it = detail::g_loaded.find(mgr->component);
    if (it == detail::g_loaded.end() || it->second->owner_lifecycle != mgr) {
        return RAC_LIFECYCLE_STATE_IDLE;
    }
    switch (it->second->state) {
        case runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY:
            return RAC_LIFECYCLE_STATE_LOADED;
        case runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR:
            return RAC_LIFECYCLE_STATE_FAILED;
        default:
            return RAC_LIFECYCLE_STATE_IDLE;
    }
}

rac_bool_t rac_lifecycle_is_loaded(rac_handle_t handle) {
    return rac_lifecycle_get_state(handle) == RAC_LIFECYCLE_STATE_LOADED ? RAC_TRUE : RAC_FALSE;
}

const char* rac_lifecycle_get_model_id(rac_handle_t handle) {
    if (handle == nullptr) {
        return nullptr;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> g(detail::g_lifecycle_mutex);
    auto it = detail::g_loaded.find(mgr->component);
    if (it == detail::g_loaded.end() || it->second->owner_lifecycle != mgr ||
        it->second->model_id.empty()) {
        return nullptr;
    }
    return it->second->model_id.c_str();
}

const char* rac_lifecycle_get_model_name(rac_handle_t handle) {
    if (handle == nullptr) {
        return nullptr;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> g(detail::g_lifecycle_mutex);
    auto it = detail::g_loaded.find(mgr->component);
    if (it == detail::g_loaded.end() || it->second->owner_lifecycle != mgr ||
        it->second->model_name.empty()) {
        return nullptr;
    }
    return it->second->model_name.c_str();
}

rac_handle_t rac_lifecycle_get_service(rac_handle_t handle) {
    if (handle == nullptr) {
        return nullptr;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> g(detail::g_lifecycle_mutex);
    auto it = detail::g_loaded.find(mgr->component);
    if (it == detail::g_loaded.end() || it->second->owner_lifecycle != mgr ||
        it->second->state != runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
        return nullptr;
    }
    return it->second->service_handle;
}

rac_result_t rac_lifecycle_require_service(rac_handle_t handle, rac_handle_t* out_service) {
    if (handle == nullptr || out_service == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> g(detail::g_lifecycle_mutex);
    auto it = detail::g_loaded.find(mgr->component);
    if (it == detail::g_loaded.end() || it->second->owner_lifecycle != mgr ||
        it->second->state != runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY ||
        it->second->service_handle == nullptr) {
        rac_error_set_details("Service not loaded - call load() first");
        return RAC_ERROR_NOT_INITIALIZED;
    }
    *out_service = it->second->service_handle;
    return RAC_SUCCESS;
}

void rac_lifecycle_track_error(rac_handle_t handle, rac_result_t error_code,
                               const char* operation) {
    // Errors surface via the proto SDKError path at the feature-module layer;
    // nothing to emit here.
    (void)handle;
    (void)error_code;
    (void)operation;
}

rac_result_t rac_lifecycle_get_metrics(rac_handle_t handle, rac_lifecycle_metrics_t* out_metrics) {
    if (handle == nullptr || out_metrics == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> lock(mgr->mutex);

    out_metrics->total_events = mgr->load_count + mgr->total_unloads + mgr->failed_loads;
    out_metrics->start_time_ms = mgr->start_time_ms;
    out_metrics->last_event_time_ms = mgr->last_event_time_ms;
    out_metrics->total_loads = mgr->load_count + mgr->failed_loads;
    out_metrics->successful_loads = mgr->load_count;
    out_metrics->failed_loads = mgr->failed_loads;
    out_metrics->average_load_time_ms =
        mgr->load_count > 0 ? mgr->total_load_time_ms / static_cast<double>(mgr->load_count) : 0.0;
    out_metrics->total_unloads = mgr->total_unloads;

    return RAC_SUCCESS;
}

void rac_lifecycle_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    rac_lifecycle_unload(handle);
    delete mgr;
}

}  // extern "C"

#else  // !RAC_HAVE_PROTOBUF

// STANDALONE IMPLEMENTATION (no protobuf: g_loaded does not exist)
//
// Self-contained per-handle lifecycle, kept verbatim for builds without the
// proto-backed canonical store.

namespace {

struct LifecycleManager {
    rac_resource_type_t resource_type{RAC_RESOURCE_TYPE_LLM_MODEL};
    std::string logger_category{};
    void* user_data{nullptr};

    rac_lifecycle_create_service_fn create_fn{nullptr};
    rac_lifecycle_destroy_service_fn destroy_fn{nullptr};

    std::atomic<rac_lifecycle_state_t> state{RAC_LIFECYCLE_STATE_IDLE};
    std::string current_model_path{};
    std::string current_model_id{};
    std::string current_model_name{};
    std::atomic<rac_handle_t> current_service{nullptr};

    int32_t load_count{0};
    double total_load_time_ms{0.0};
    int32_t failed_loads{0};
    int32_t total_unloads{0};
    int64_t start_time_ms{0};
    int64_t last_event_time_ms{0};

    std::mutex mutex{};

    std::atomic<int> service_refcount{0};
    std::condition_variable service_cv{};

    LifecycleManager() {
        auto now = std::chrono::system_clock::now();
        auto duration = now.time_since_epoch();
        start_time_ms = std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
    }
};

int64_t current_time_ms() {
    auto now = std::chrono::system_clock::now();
    auto duration = now.time_since_epoch();
    return std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
}

void track_lifecycle_event(LifecycleManager* mgr, const char* event_type, const char* model_id,
                           double duration_ms, rac_result_t error_code) {
    (void)event_type;
    (void)model_id;
    (void)duration_ms;
    (void)error_code;
    mgr->last_event_time_ms = current_time_ms();
}

}  // namespace

extern "C" {

rac_result_t rac_lifecycle_create(const rac_lifecycle_config_t* config,
                                  rac_lifecycle_create_service_fn create_fn,
                                  rac_lifecycle_destroy_service_fn destroy_fn,
                                  rac_handle_t* out_handle) {
    if (config == nullptr || create_fn == nullptr || out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = new (std::nothrow) LifecycleManager();
    if (!mgr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    mgr->resource_type = config->resource_type;
    mgr->logger_category = config->logger_category ? config->logger_category : "Lifecycle";
    mgr->user_data = config->user_data;
    mgr->create_fn = create_fn;
    mgr->destroy_fn = destroy_fn;

    *out_handle = static_cast<rac_handle_t>(mgr);
    return RAC_SUCCESS;
}

rac_result_t rac_lifecycle_load(rac_handle_t handle, const char* model_path, const char* model_id,
                                const char* model_name, rac_handle_t* out_service) {
    if (handle == nullptr || model_path == nullptr || out_service == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    if (model_id == nullptr) {
        model_id = model_path;
    }
    if (model_name == nullptr) {
        model_name = model_id;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::unique_lock<std::mutex> lock(mgr->mutex);

    if (mgr->state.load() == RAC_LIFECYCLE_STATE_LOADED && mgr->current_model_path == model_path &&
        mgr->current_service.load() != nullptr) {
        RAC_LOG_INFO(mgr->logger_category.c_str(), "Model already loaded, skipping duplicate load");
        *out_service = mgr->current_service.load();
        return RAC_SUCCESS;
    }

    if (mgr->state.load() == RAC_LIFECYCLE_STATE_LOADED && mgr->current_service.load() != nullptr) {
        mgr->service_cv.wait(lock, [mgr] { return mgr->service_refcount.load() == 0; });

        RAC_LOG_INFO(mgr->logger_category.c_str(),
                     "Auto-unloading previous model '%s' before loading '%s'",
                     mgr->current_model_id.c_str(), model_id);

        rac_handle_t old_service = mgr->current_service.load();
        mgr->current_service.store(nullptr);
        if (mgr->destroy_fn != nullptr && old_service != nullptr) {
            mgr->destroy_fn(old_service, mgr->user_data);
        }
        track_lifecycle_event(mgr, "unloaded", mgr->current_model_id.c_str(), 0.0, RAC_SUCCESS);

        mgr->current_model_path.clear();
        mgr->current_model_id.clear();
        mgr->current_model_name.clear();
        mgr->total_unloads++;
        mgr->state.store(RAC_LIFECYCLE_STATE_IDLE);
    }

    int64_t start_time = current_time_ms();
    mgr->state.store(RAC_LIFECYCLE_STATE_LOADING);
    track_lifecycle_event(mgr, "load.started", model_id, 0.0, RAC_SUCCESS);

    RAC_LOG_INFO(mgr->logger_category.c_str(), "Loading model: %s (path: %s)", model_id,
                 model_path);

    rac_handle_t service = nullptr;
    rac_result_t result = mgr->create_fn(model_path, mgr->user_data, &service);

    auto load_time_ms = static_cast<double>(current_time_ms() - start_time);

    if (result == RAC_SUCCESS && service != nullptr) {
        mgr->current_model_path = model_path;
        mgr->current_model_id = model_id;
        mgr->current_model_name = model_name;
        mgr->current_service.store(service);
        mgr->state.store(RAC_LIFECYCLE_STATE_LOADED);

        track_lifecycle_event(mgr, "load.completed", model_id, load_time_ms, RAC_SUCCESS);

        mgr->load_count++;
        mgr->total_load_time_ms += load_time_ms;

        RAC_LOG_INFO(mgr->logger_category.c_str(), "Loaded model in %dms",
                     static_cast<int>(load_time_ms));

        *out_service = service;
        return RAC_SUCCESS;
    }

    mgr->state.store(RAC_LIFECYCLE_STATE_FAILED);
    mgr->failed_loads++;

    track_lifecycle_event(mgr, "load.failed", model_id, load_time_ms, result);

    RAC_LOG_ERROR(mgr->logger_category.c_str(), "Failed to load model");

    return result;
}

rac_result_t rac_lifecycle_acquire_service(rac_handle_t handle, rac_handle_t* out_service) {
    if (handle == nullptr || out_service == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> lock(mgr->mutex);

    if (mgr->state.load() != RAC_LIFECYCLE_STATE_LOADED || mgr->current_service.load() == nullptr) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    mgr->service_refcount.fetch_add(1);
    *out_service = mgr->current_service.load();
    return RAC_SUCCESS;
}

void rac_lifecycle_release_service(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    int prev = mgr->service_refcount.fetch_sub(1);
    if (prev <= 1) {
        mgr->service_cv.notify_all();
    }
}

rac_result_t rac_lifecycle_unload(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::unique_lock<std::mutex> lock(mgr->mutex);

    mgr->service_cv.wait(lock, [mgr] { return mgr->service_refcount.load() == 0; });

    if (!mgr->current_model_id.empty()) {
        RAC_LOG_INFO(mgr->logger_category.c_str(), "Unloading model: %s",
                     mgr->current_model_id.c_str());

        rac_handle_t svc = mgr->current_service.load();
        mgr->current_service.store(nullptr);
        if (mgr->destroy_fn != nullptr && svc != nullptr) {
            mgr->destroy_fn(svc, mgr->user_data);
        }

        track_lifecycle_event(mgr, "unloaded", mgr->current_model_id.c_str(), 0.0, RAC_SUCCESS);

        mgr->total_unloads++;
    }

    mgr->current_model_path.clear();
    mgr->current_model_id.clear();
    mgr->current_model_name.clear();
    mgr->current_service.store(nullptr);
    mgr->state.store(RAC_LIFECYCLE_STATE_IDLE);

    return RAC_SUCCESS;
}

rac_result_t rac_lifecycle_reset(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::unique_lock<std::mutex> lock(mgr->mutex);

    mgr->service_cv.wait(lock, [mgr] { return mgr->service_refcount.load() == 0; });

    if (!mgr->current_model_id.empty()) {
        track_lifecycle_event(mgr, "unloaded", mgr->current_model_id.c_str(), 0.0, RAC_SUCCESS);

        rac_handle_t svc = mgr->current_service.load();
        mgr->current_service.store(nullptr);
        if (mgr->destroy_fn != nullptr && svc != nullptr) {
            mgr->destroy_fn(svc, mgr->user_data);
        }
    }

    mgr->current_model_path.clear();
    mgr->current_model_id.clear();
    mgr->current_model_name.clear();
    mgr->current_service.store(nullptr);
    mgr->state.store(RAC_LIFECYCLE_STATE_IDLE);

    return RAC_SUCCESS;
}

rac_lifecycle_state_t rac_lifecycle_get_state(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_LIFECYCLE_STATE_IDLE;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    return mgr->state.load();
}

rac_bool_t rac_lifecycle_is_loaded(rac_handle_t handle) {
    if (handle == nullptr) {
        return RAC_FALSE;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    return mgr->state.load() == RAC_LIFECYCLE_STATE_LOADED ? RAC_TRUE : RAC_FALSE;
}

const char* rac_lifecycle_get_model_id(rac_handle_t handle) {
    if (handle == nullptr) {
        return nullptr;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> lock(mgr->mutex);

    if (mgr->current_model_id.empty()) {
        return nullptr;
    }
    return mgr->current_model_id.c_str();
}

const char* rac_lifecycle_get_model_name(rac_handle_t handle) {
    if (handle == nullptr) {
        return nullptr;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> lock(mgr->mutex);

    if (mgr->current_model_name.empty()) {
        return nullptr;
    }
    return mgr->current_model_name.c_str();
}

rac_handle_t rac_lifecycle_get_service(rac_handle_t handle) {
    if (handle == nullptr) {
        return nullptr;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    return mgr->current_service.load(std::memory_order_acquire);
}

rac_result_t rac_lifecycle_require_service(rac_handle_t handle, rac_handle_t* out_service) {
    if (handle == nullptr || out_service == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> lock(mgr->mutex);

    if (mgr->state.load() != RAC_LIFECYCLE_STATE_LOADED) {
        rac_error_set_details("Service not loaded - call load() first");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_handle_t svc = mgr->current_service.load();
    if (svc == nullptr) {
        rac_error_set_details("Service not loaded - call load() first");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    *out_service = svc;
    return RAC_SUCCESS;
}

void rac_lifecycle_track_error(rac_handle_t handle, rac_result_t error_code,
                               const char* operation) {
    (void)handle;
    (void)error_code;
    (void)operation;
}

rac_result_t rac_lifecycle_get_metrics(rac_handle_t handle, rac_lifecycle_metrics_t* out_metrics) {
    if (handle == nullptr || out_metrics == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    std::lock_guard<std::mutex> lock(mgr->mutex);

    out_metrics->total_events = mgr->load_count + mgr->total_unloads + mgr->failed_loads;
    out_metrics->start_time_ms = mgr->start_time_ms;
    out_metrics->last_event_time_ms = mgr->last_event_time_ms;
    out_metrics->total_loads = mgr->load_count + mgr->failed_loads;
    out_metrics->successful_loads = mgr->load_count;
    out_metrics->failed_loads = mgr->failed_loads;
    out_metrics->average_load_time_ms =
        mgr->load_count > 0 ? mgr->total_load_time_ms / static_cast<double>(mgr->load_count) : 0.0;
    out_metrics->total_unloads = mgr->total_unloads;

    return RAC_SUCCESS;
}

void rac_lifecycle_destroy(rac_handle_t handle) {
    if (handle == nullptr) {
        return;
    }

    auto* mgr = static_cast<LifecycleManager*>(handle);
    rac_lifecycle_unload(handle);
    delete mgr;
}

}  // extern "C"

#endif  // RAC_HAVE_PROTOBUF

// SHARED PURE HELPERS (independent of LifecycleManager storage)

extern "C" {

const char* rac_lifecycle_state_name(rac_lifecycle_state_t state) {
    switch (state) {
        case RAC_LIFECYCLE_STATE_IDLE:
            return "idle";
        case RAC_LIFECYCLE_STATE_LOADING:
            return "loading";
        case RAC_LIFECYCLE_STATE_LOADED:
            return "loaded";
        case RAC_LIFECYCLE_STATE_FAILED:
            return "failed";
        default:
            return "unknown";
    }
}

const char* rac_resource_type_name(rac_resource_type_t type) {
    switch (type) {
        case RAC_RESOURCE_TYPE_LLM_MODEL:
            return "llmModel";
        case RAC_RESOURCE_TYPE_STT_MODEL:
            return "sttModel";
        case RAC_RESOURCE_TYPE_TTS_VOICE:
            return "ttsVoice";
        case RAC_RESOURCE_TYPE_VAD_MODEL:
            return "vadModel";
        case RAC_RESOURCE_TYPE_DIARIZATION_MODEL:
            return "diarizationModel";
        case RAC_RESOURCE_TYPE_VLM_MODEL:
            return "vlmModel";
        case RAC_RESOURCE_TYPE_DIFFUSION_MODEL:
            return "diffusionModel";
        case RAC_RESOURCE_TYPE_EMBEDDINGS_MODEL:
            return "embeddingsModel";
        default:
            return "unknown";
    }
}

}  // extern "C"
