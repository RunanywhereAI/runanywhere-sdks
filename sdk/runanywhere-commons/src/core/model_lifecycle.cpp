/**
 * @file model_lifecycle.cpp
 * @brief Canonical model lifecycle C ABI over generated proto bytes.
 *
 * SRP split: the load/unload/snapshot ABI entry
 * points plus the shared lifecycle state live here. Translation helpers,
 * artifact resolution, auto-download, and per-modality lifecycle accessors
 * each live in their own TU under the same directory:
 *
 *   - model_lifecycle_translation.cpp  -- proto<->C + event publish helpers
 *   - model_lifecycle_resolve.cpp      -- artifact resolution + result/snapshot builders
 *   - model_lifecycle_download.cpp     -- validate_availability=true auto-download path
 *   - model_lifecycle_accessors.cpp    -- rac::llm / rac::vlm / rac::lifecycle namespaces
 *
 * Public C ABI surface is unchanged; the split is purely internal.
 */

#include "model_lifecycle_internal.h"

#include <condition_variable>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

namespace rac::core::model_lifecycle::detail {

#if defined(RAC_HAVE_PROTOBUF)

// Canonical lifecycle state. Declared extern in model_lifecycle_internal.h;
// defined here exactly once.
std::mutex g_lifecycle_mutex;
std::condition_variable g_lifecycle_cv;
std::map<runanywhere::v1::SDKComponent, std::shared_ptr<LoadedModel>> g_loaded;

void destroy_loaded_model(const std::shared_ptr<LoadedModel>& model) {
    if (!model) {
        return;
    }
    {
        std::unique_lock<std::mutex> lock(g_lifecycle_mutex);
        g_lifecycle_cv.wait(lock, [&model] { return model->active_refs == 0; });
    }
    if (model->destroy) {
        model->destroy();
        model->destroy = {};
    }
    model->impl = nullptr;
    model->llm_ops = nullptr;
    model->stt_ops = nullptr;
    model->tts_ops = nullptr;
    model->vad_ops = nullptr;
    model->embeddings_ops = nullptr;
    model->vlm_ops = nullptr;
    model->diffusion_ops = nullptr;
}

namespace {

rac_result_t create_backend_impl(const rac_engine_vtable_t* vt, rac_primitive_t primitive,
                                 const std::string& resolved_path, const std::string& mmproj_path,
                                 void** out_impl, std::function<void()>* out_destroy) {
    if (!vt || !out_impl || !out_destroy) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;
    *out_destroy = {};

    void* impl = nullptr;
    rac_result_t rc = RAC_ERROR_BACKEND_NOT_FOUND;

    switch (primitive) {
        case RAC_PRIMITIVE_GENERATE_TEXT:
            if (!vt->llm_ops || !vt->llm_ops->create)
                return RAC_ERROR_BACKEND_NOT_FOUND;
            rc = vt->llm_ops->create(resolved_path.c_str(), nullptr, &impl);
            if (rc == RAC_SUCCESS && impl && vt->llm_ops->initialize) {
                rc = vt->llm_ops->initialize(impl, resolved_path.c_str());
            }
            if (rc == RAC_SUCCESS && impl) {
                auto* ops = vt->llm_ops;
                *out_destroy = [ops, impl]() {
                    if (ops->cleanup)
                        (void)ops->cleanup(impl);
                    if (ops->destroy)
                        ops->destroy(impl);
                };
            }
            break;
        case RAC_PRIMITIVE_TRANSCRIBE:
            if (!vt->stt_ops || !vt->stt_ops->create)
                return RAC_ERROR_BACKEND_NOT_FOUND;
            rc = vt->stt_ops->create(resolved_path.c_str(), nullptr, &impl);
            if (rc == RAC_SUCCESS && impl && vt->stt_ops->initialize) {
                rc = vt->stt_ops->initialize(impl, resolved_path.c_str());
            }
            if (rc == RAC_SUCCESS && impl) {
                auto* ops = vt->stt_ops;
                *out_destroy = [ops, impl]() {
                    if (ops->cleanup)
                        (void)ops->cleanup(impl);
                    if (ops->destroy)
                        ops->destroy(impl);
                };
            }
            break;
        case RAC_PRIMITIVE_SYNTHESIZE:
            if (!vt->tts_ops || !vt->tts_ops->create)
                return RAC_ERROR_BACKEND_NOT_FOUND;
            rc = vt->tts_ops->create(resolved_path.c_str(), nullptr, &impl);
            if (rc == RAC_SUCCESS && impl && vt->tts_ops->initialize) {
                rc = vt->tts_ops->initialize(impl);
            }
            if (rc == RAC_SUCCESS && impl) {
                auto* ops = vt->tts_ops;
                *out_destroy = [ops, impl]() {
                    if (ops->cleanup)
                        (void)ops->cleanup(impl);
                    if (ops->destroy)
                        ops->destroy(impl);
                };
            }
            break;
        case RAC_PRIMITIVE_DETECT_VOICE:
            if (!vt->vad_ops || !vt->vad_ops->create)
                return RAC_ERROR_BACKEND_NOT_FOUND;
            rc = vt->vad_ops->create(resolved_path.c_str(), nullptr, &impl);
            if (rc == RAC_SUCCESS && impl && vt->vad_ops->initialize) {
                rc = vt->vad_ops->initialize(impl, resolved_path.c_str());
            }
            if (rc == RAC_SUCCESS && impl) {
                auto* ops = vt->vad_ops;
                *out_destroy = [ops, impl]() {
                    if (ops->destroy)
                        ops->destroy(impl);
                };
            }
            break;
        case RAC_PRIMITIVE_EMBED:
            if (!vt->embedding_ops || !vt->embedding_ops->create) {
                return RAC_ERROR_BACKEND_NOT_FOUND;
            }
            rc = vt->embedding_ops->create(resolved_path.c_str(), nullptr, &impl);
            if (rc == RAC_SUCCESS && impl && vt->embedding_ops->initialize) {
                rc = vt->embedding_ops->initialize(impl, resolved_path.c_str());
            }
            if (rc == RAC_SUCCESS && impl) {
                auto* ops = vt->embedding_ops;
                *out_destroy = [ops, impl]() {
                    if (ops->cleanup)
                        (void)ops->cleanup(impl);
                    if (ops->destroy)
                        ops->destroy(impl);
                };
            }
            break;
        case RAC_PRIMITIVE_VLM:
            if (!vt->vlm_ops || !vt->vlm_ops->create)
                return RAC_ERROR_BACKEND_NOT_FOUND;
            {
                const std::string config_json = vlm_config_json(mmproj_path);
                rc =
                    vt->vlm_ops->create(resolved_path.c_str(),
                                        config_json.empty() ? nullptr : config_json.c_str(), &impl);
            }
            if (rc == RAC_SUCCESS && impl && vt->vlm_ops->initialize) {
                rc = vt->vlm_ops->initialize(impl, resolved_path.c_str(),
                                             mmproj_path.empty() ? nullptr : mmproj_path.c_str());
            }
            if (rc == RAC_SUCCESS && impl) {
                auto* ops = vt->vlm_ops;
                *out_destroy = [ops, impl]() {
                    if (ops->cleanup)
                        (void)ops->cleanup(impl);
                    if (ops->destroy)
                        ops->destroy(impl);
                };
            }
            break;
        case RAC_PRIMITIVE_DIFFUSION:
            if (!vt->diffusion_ops || !vt->diffusion_ops->create) {
                return RAC_ERROR_BACKEND_NOT_FOUND;
            }
            rc = vt->diffusion_ops->create(resolved_path.c_str(), nullptr, &impl);
            if (rc == RAC_SUCCESS && impl && vt->diffusion_ops->initialize) {
                rc = vt->diffusion_ops->initialize(impl, resolved_path.c_str(), nullptr);
            }
            if (rc == RAC_SUCCESS && impl) {
                auto* ops = vt->diffusion_ops;
                *out_destroy = [ops, impl]() {
                    if (ops->cleanup)
                        (void)ops->cleanup(impl);
                    if (ops->destroy)
                        ops->destroy(impl);
                };
            }
            break;
        default:
            return RAC_ERROR_UNSUPPORTED_MODALITY;
    }

    if (rc != RAC_SUCCESS) {
        if (impl) {
            switch (primitive) {
                case RAC_PRIMITIVE_GENERATE_TEXT:
                    if (vt->llm_ops && vt->llm_ops->destroy)
                        vt->llm_ops->destroy(impl);
                    break;
                case RAC_PRIMITIVE_TRANSCRIBE:
                    if (vt->stt_ops && vt->stt_ops->destroy)
                        vt->stt_ops->destroy(impl);
                    break;
                case RAC_PRIMITIVE_SYNTHESIZE:
                    if (vt->tts_ops && vt->tts_ops->destroy)
                        vt->tts_ops->destroy(impl);
                    break;
                case RAC_PRIMITIVE_DETECT_VOICE:
                    if (vt->vad_ops && vt->vad_ops->destroy)
                        vt->vad_ops->destroy(impl);
                    break;
                case RAC_PRIMITIVE_EMBED:
                    if (vt->embedding_ops && vt->embedding_ops->destroy) {
                        vt->embedding_ops->destroy(impl);
                    }
                    break;
                case RAC_PRIMITIVE_VLM:
                    if (vt->vlm_ops && vt->vlm_ops->destroy)
                        vt->vlm_ops->destroy(impl);
                    break;
                case RAC_PRIMITIVE_DIFFUSION:
                    if (vt->diffusion_ops && vt->diffusion_ops->destroy) {
                        vt->diffusion_ops->destroy(impl);
                    }
                    break;
                default:
                    break;
            }
        }
        return rc;
    }

    if (!impl || !*out_destroy) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }

    *out_impl = impl;
    return RAC_SUCCESS;
}

}  // namespace

#endif  // RAC_HAVE_PROTOBUF

}  // namespace rac::core::model_lifecycle::detail

namespace {
using rac::core::model_lifecycle::detail::feature_unavailable;
}  // namespace

extern "C" {

rac_result_t rac_model_lifecycle_load_proto(rac_model_registry_handle_t registry,
                                            const uint8_t* request_proto_bytes,
                                            size_t request_proto_size,
                                            rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)registry;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    namespace detail = rac::core::model_lifecycle::detail;
    using runanywhere::v1::ComponentLifecycleState;
    using runanywhere::v1::InferenceFramework;
    using runanywhere::v1::ModelCategory;
    using runanywhere::v1::ModelInfo;
    using runanywhere::v1::ModelLoadRequest;
    using runanywhere::v1::ModelLoadResult;
    using runanywhere::v1::SDKComponent;

    if (!registry) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NULL_POINTER,
                                          "registry handle is required");
    }
    if (!detail::valid_bytes(request_proto_bytes, request_proto_size)) {
        return detail::parse_error(out_result, "ModelLoadRequest bytes are empty or too large");
    }

    ModelLoadRequest request;
    if (!request.ParseFromArray(detail::parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return detail::parse_error(out_result, "failed to parse ModelLoadRequest");
    }
    if (request.model_id().empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "ModelLoadRequest.model_id is required");
    }

    uint8_t* model_bytes = nullptr;
    size_t model_size = 0;
    rac_result_t rc = rac_model_registry_get_proto(registry, request.model_id().c_str(),
                                                   &model_bytes, &model_size);
    if (rc != RAC_SUCCESS) {
        ModelLoadResult result = detail::make_load_result(
            false, request.model_id(),
            request.has_category() ? request.category()
                                   : runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED,
            request.has_framework() ? request.framework()
                                    : runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED,
            "", {}, 0, "model not found in registry");
        detail::publish_component_event(runanywhere::v1::SDK_COMPONENT_UNSPECIFIED,
                                        runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
                                        runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR,
                                        request.model_id(), &result, nullptr,
                                        result.error_message().c_str());
        return detail::copy_proto(result, out_result);
    }

    ModelInfo model;
    const bool parsed_model = model.ParseFromArray(model_bytes, static_cast<int>(model_size));
    rac_model_registry_proto_free(model_bytes);
    if (!parsed_model) {
        return detail::parse_error(out_result, "failed to parse registered ModelInfo");
    }

    // Collapse the legacy
    // `getModel → downloadModel(asyncIterator) → loadModel` chain into a
    // single `loadModel(id)` call when callers opt in via
    // `validate_availability=true`. If the registry says the model is
    // missing on disk AND the entry advertises a download source, drive
    // the canonical download orchestrator before continuing and re-fetch
    // the ModelInfo so the post-download local_path is observed.
    if (request.validate_availability() && !detail::model_artifact_present(model) &&
        detail::model_has_download_source(model)) {
        std::string dl_error;
        const rac_result_t dl_rc =
            detail::download_and_wait_for_model(request.model_id(), model, &dl_error);
        if (dl_rc != RAC_SUCCESS) {
            const ModelCategory fail_category = detail::preferred_category_for(request, model);
            const InferenceFramework fail_framework =
                detail::preferred_framework_for(request, model);
            ModelLoadResult result = detail::make_load_result(
                false, request.model_id(), fail_category, fail_framework, "", {}, 0,
                dl_error.empty() ? "auto-download failed" : dl_error);
            detail::publish_component_event(detail::component_for_category(fail_category),
                                            runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
                                            runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR,
                                            request.model_id(), &result, nullptr,
                                            result.error_message().c_str());
            return detail::copy_proto(result, out_result);
        }

        // Re-fetch the registry entry — the download worker calls
        // rac_model_registry_update_download_status() on success
        // (update_registry_on_completion=true above), so the refreshed
        // ModelInfo carries the now-populated local_path.
        uint8_t* refreshed_bytes = nullptr;
        size_t refreshed_size = 0;
        const rac_result_t refetch_rc = rac_model_registry_get_proto(
            registry, request.model_id().c_str(), &refreshed_bytes, &refreshed_size);
        if (refetch_rc == RAC_SUCCESS && refreshed_bytes) {
            ModelInfo refreshed;
            if (refreshed.ParseFromArray(refreshed_bytes, static_cast<int>(refreshed_size))) {
                model.Swap(&refreshed);
            }
            rac_model_registry_proto_free(refreshed_bytes);
        }
    }

    const ModelCategory category = detail::preferred_category_for(request, model);
    const InferenceFramework framework = detail::preferred_framework_for(request, model);
    const SDKComponent component = detail::component_for_category(category);
    const rac_primitive_t primitive = detail::primitive_for_component(component);
    const detail::ModelArtifactResolution artifact_resolution =
        detail::resolve_model_artifacts(model);
    const std::string& resolved_path = artifact_resolution.resolved_path;

    if (component == runanywhere::v1::SDK_COMPONENT_UNSPECIFIED ||
        primitive == RAC_PRIMITIVE_UNSPECIFIED) {
        ModelLoadResult result =
            detail::make_load_result(false, request.model_id(), category, framework, resolved_path,
                                     artifact_resolution.artifacts, 0,
                                     "model category is not supported by lifecycle routing");
        detail::publish_component_event(
            component, runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
            runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR, request.model_id(), &result, nullptr,
            result.error_message().c_str());
        return detail::copy_proto(result, out_result);
    }

    {
        std::lock_guard<std::mutex> lock(detail::g_lifecycle_mutex);
        auto existing = detail::g_loaded.find(component);
        if (existing != detail::g_loaded.end() && !request.force_reload() &&
            existing->second->model_id == request.model_id() &&
            existing->second->state == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
            ModelLoadResult result = detail::make_load_result(
                true, existing->second->model_id, existing->second->category,
                existing->second->framework, existing->second->resolved_path,
                existing->second->resolved_artifacts, existing->second->loaded_at_ms, "");
            return detail::copy_proto(result, out_result);
        }
    }

    std::shared_ptr<detail::LoadedModel> previous_loaded;
    ComponentLifecycleState previous_state = runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED;
    {
        std::lock_guard<std::mutex> lock(detail::g_lifecycle_mutex);
        auto existing = detail::g_loaded.find(component);
        if (existing != detail::g_loaded.end()) {
            previous_state = existing->second->state;
            previous_loaded = existing->second;
            detail::g_loaded.erase(existing);
        }
    }
    detail::destroy_loaded_model(previous_loaded);

    detail::publish_component_event(component, previous_state,
                                    runanywhere::v1::COMPONENT_LIFECYCLE_STATE_LOADING,
                                    request.model_id(), nullptr, nullptr, nullptr);

    // Pick the highest-priority registered plugin that serves this primitive
    // (priority assigned at backend registration; no hardware/format scoring).
    const rac_engine_vtable_t* vt = rac_plugin_find(primitive);
    if (!vt) {
        std::string error = "no registered backend serves the requested primitive";
        ModelLoadResult result =
            detail::make_load_result(false, request.model_id(), category, framework, resolved_path,
                                     artifact_resolution.artifacts, 0, error);
        {
            std::lock_guard<std::mutex> lock(detail::g_lifecycle_mutex);
            auto failed = std::make_shared<detail::LoadedModel>();
            failed->component = component;
            failed->state = runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR;
            failed->model_id = request.model_id();
            failed->resolved_path = resolved_path;
            failed->mmproj_path = artifact_resolution.mmproj_path;
            failed->resolved_artifacts = artifact_resolution.artifacts;
            failed->category = category;
            failed->framework = framework;
            failed->framework_name = runanywhere::v1::InferenceFramework_Name(framework);
            failed->updated_at_ms = detail::now_ms();
            failed->error_message = error;
            detail::g_loaded[component] = std::move(failed);
        }
        detail::publish_component_event(
            component, runanywhere::v1::COMPONENT_LIFECYCLE_STATE_LOADING,
            runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR, request.model_id(), &result, nullptr,
            result.error_message().c_str());
        return detail::copy_proto(result, out_result);
    }

    void* impl = nullptr;
    std::function<void()> destroy;
    rc = detail::create_backend_impl(vt, primitive, resolved_path, artifact_resolution.mmproj_path,
                                     &impl, &destroy);
    if (rc != RAC_SUCCESS) {
        ModelLoadResult result =
            detail::make_load_result(false, request.model_id(), category, framework, resolved_path,
                                     artifact_resolution.artifacts, 0, rac_error_message(rc));
        {
            std::lock_guard<std::mutex> lock(detail::g_lifecycle_mutex);
            auto failed = std::make_shared<detail::LoadedModel>();
            failed->component = component;
            failed->state = runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR;
            failed->model_id = request.model_id();
            failed->resolved_path = resolved_path;
            failed->mmproj_path = artifact_resolution.mmproj_path;
            failed->resolved_artifacts = artifact_resolution.artifacts;
            failed->category = category;
            failed->framework = framework;
            failed->framework_name = runanywhere::v1::InferenceFramework_Name(framework);
            failed->updated_at_ms = detail::now_ms();
            failed->error_message = result.error_message();
            detail::g_loaded[component] = std::move(failed);
        }
        detail::publish_component_event(
            component, runanywhere::v1::COMPONENT_LIFECYCLE_STATE_LOADING,
            runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR, request.model_id(), &result, nullptr,
            result.error_message().c_str());
        return detail::copy_proto(result, out_result);
    }

    int64_t loaded_at_ms = detail::now_ms();
    {
        std::lock_guard<std::mutex> lock(detail::g_lifecycle_mutex);
        auto loaded = std::make_shared<detail::LoadedModel>();
        loaded->component = component;
        loaded->state = runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY;
        loaded->model_id = request.model_id();
        loaded->resolved_path = resolved_path;
        loaded->mmproj_path = artifact_resolution.mmproj_path;
        loaded->resolved_artifacts = artifact_resolution.artifacts;
        loaded->framework = framework;
        loaded->framework_name = runanywhere::v1::InferenceFramework_Name(framework);
        loaded->category = category;
        loaded->primitive = primitive;
        if (primitive == RAC_PRIMITIVE_GENERATE_TEXT) {
            loaded->llm_ops = vt->llm_ops;
        } else if (primitive == RAC_PRIMITIVE_TRANSCRIBE) {
            loaded->stt_ops = vt->stt_ops;
        } else if (primitive == RAC_PRIMITIVE_SYNTHESIZE) {
            loaded->tts_ops = vt->tts_ops;
        } else if (primitive == RAC_PRIMITIVE_DETECT_VOICE) {
            loaded->vad_ops = vt->vad_ops;
        } else if (primitive == RAC_PRIMITIVE_EMBED) {
            loaded->embeddings_ops = vt->embedding_ops;
        } else if (primitive == RAC_PRIMITIVE_VLM) {
            loaded->vlm_ops = vt->vlm_ops;
        } else if (primitive == RAC_PRIMITIVE_DIFFUSION) {
            loaded->diffusion_ops = vt->diffusion_ops;
        }
        loaded->impl = impl;
        loaded->model.CopyFrom(model);
        loaded->loaded_at_ms = loaded_at_ms;
        loaded->updated_at_ms = loaded->loaded_at_ms;
        loaded->destroy = std::move(destroy);
        detail::g_loaded[component] = std::move(loaded);
    }

    ModelLoadResult result =
        detail::make_load_result(true, request.model_id(), category, framework, resolved_path,
                                 artifact_resolution.artifacts, loaded_at_ms, "");
    detail::publish_component_event(component, runanywhere::v1::COMPONENT_LIFECYCLE_STATE_LOADING,
                                    runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY,
                                    request.model_id(), &result, nullptr, nullptr);
    RAC_LOG_INFO("ModelLifecycle", "Model load succeeded for %s", request.model_id().c_str());
    return detail::copy_proto(result, out_result);
#endif
}

rac_result_t rac_model_lifecycle_unload_proto(const uint8_t* request_proto_bytes,
                                              size_t request_proto_size,
                                              rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    namespace detail = rac::core::model_lifecycle::detail;
    using runanywhere::v1::ModelUnloadRequest;
    using runanywhere::v1::ModelUnloadResult;

    if (!detail::valid_bytes(request_proto_bytes, request_proto_size)) {
        return detail::parse_error(out_result, "ModelUnloadRequest bytes are empty or too large");
    }
    ModelUnloadRequest request;
    if (!request.ParseFromArray(detail::parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return detail::parse_error(out_result, "failed to parse ModelUnloadRequest");
    }

    std::vector<std::shared_ptr<detail::LoadedModel>> unloaded;
    {
        std::lock_guard<std::mutex> lock(detail::g_lifecycle_mutex);
        for (auto it = detail::g_loaded.begin(); it != detail::g_loaded.end();) {
            const bool model_match =
                !request.model_id().empty() && it->second->model_id == request.model_id();
            const bool category_match =
                request.has_category() && it->second->category == request.category();
            const bool should_unload = request.unload_all() || model_match || category_match;
            if (!should_unload) {
                ++it;
                continue;
            }
            it->second->state = runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED;
            it->second->updated_at_ms = detail::now_ms();
            unloaded.push_back(it->second);
            it = detail::g_loaded.erase(it);
        }
    }

    for (const auto& model : unloaded) {
        detail::destroy_loaded_model(model);
    }

    ModelUnloadResult result;
    result.set_success(!unloaded.empty());
    if (unloaded.empty()) {
        result.set_error_message("no loaded model matched unload request");
    }
    for (const auto& model : unloaded) {
        result.add_unloaded_model_ids(model->model_id);
        detail::publish_component_event(model->component,
                                        runanywhere::v1::COMPONENT_LIFECYCLE_STATE_UNLOADING,
                                        runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
                                        model->model_id, nullptr, &result, nullptr);
    }
    return detail::copy_proto(result, out_result);
#endif
}

rac_result_t rac_model_lifecycle_current_model_proto(const uint8_t* request_proto_bytes,
                                                     size_t request_proto_size,
                                                     rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    namespace detail = rac::core::model_lifecycle::detail;
    using runanywhere::v1::CurrentModelRequest;
    using runanywhere::v1::CurrentModelResult;
    using runanywhere::v1::SDKComponent;

    if (!detail::valid_bytes(request_proto_bytes, request_proto_size)) {
        return detail::parse_error(out_result, "CurrentModelRequest bytes are empty or too large");
    }
    CurrentModelRequest request;
    if (!request.ParseFromArray(detail::parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return detail::parse_error(out_result, "failed to parse CurrentModelRequest");
    }

    CurrentModelResult result;
    SDKComponent component = runanywhere::v1::SDK_COMPONENT_UNSPECIFIED;
    {
        std::lock_guard<std::mutex> lock(detail::g_lifecycle_mutex);
        for (const auto& pair : detail::g_loaded) {
            if (!detail::matches_current_filter(*pair.second, request.has_category(),
                                                request.category(), request.has_framework(),
                                                request.framework())) {
                continue;
            }
            result.set_model_id(pair.second->model_id);
            result.mutable_model()->CopyFrom(pair.second->model);
            result.set_loaded_at_unix_ms(pair.second->loaded_at_ms);
            result.set_found(true);
            result.set_category(pair.second->category);
            result.set_framework(pair.second->framework);
            result.set_resolved_path(pair.second->resolved_path);
            detail::add_artifacts_to_result(pair.second->resolved_artifacts,
                                            result.mutable_resolved_artifacts());
            component = pair.second->component;
            break;
        }
    }
    if (result.model_id().empty()) {
        result.set_found(false);
    }
    detail::publish_current_model_event(result, component);
    detail::publish_component_event(
        component,
        result.model_id().empty() ? runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED
                                  : runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY,
        result.model_id().empty() ? runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED
                                  : runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY,
        result.model_id(), nullptr, nullptr, nullptr);
    return detail::copy_proto(result, out_result);
#endif
}

rac_result_t rac_component_lifecycle_snapshot_proto(uint32_t component,
                                                    rac_proto_buffer_t* out_snapshot) {
    if (!out_snapshot) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)component;
    return feature_unavailable(out_snapshot);
#else
    namespace detail = rac::core::model_lifecycle::detail;
    using runanywhere::v1::ComponentLifecycleSnapshot;
    using runanywhere::v1::SDKComponent;

    ComponentLifecycleSnapshot snapshot;
    const auto sdk_component = static_cast<SDKComponent>(component);
    {
        std::lock_guard<std::mutex> lock(detail::g_lifecycle_mutex);
        auto it = detail::g_loaded.find(sdk_component);
        detail::fill_snapshot(it == detail::g_loaded.end() ? nullptr : it->second.get(),
                              sdk_component, &snapshot);
    }
    return detail::copy_proto(snapshot, out_snapshot);
#endif
}

void rac_model_lifecycle_reset(void) {
#if defined(RAC_HAVE_PROTOBUF)
    namespace detail = rac::core::model_lifecycle::detail;
    std::vector<std::shared_ptr<detail::LoadedModel>> loaded;
    {
        std::lock_guard<std::mutex> lock(detail::g_lifecycle_mutex);
        for (auto& pair : detail::g_loaded) {
            loaded.push_back(pair.second);
        }
        detail::g_loaded.clear();
    }
    for (const auto& model : loaded) {
        detail::destroy_loaded_model(model);
    }
#endif
}

}  // extern "C"
