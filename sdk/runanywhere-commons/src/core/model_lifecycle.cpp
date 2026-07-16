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
#include "rac/plugin/rac_engine_ids.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

namespace rac::core::model_lifecycle::detail {

#if defined(RAC_HAVE_PROTOBUF)

// Canonical lifecycle state. Declared extern in model_lifecycle_internal.h;
// defined here exactly once.
std::mutex g_lifecycle_mutex;
std::condition_variable g_lifecycle_cv;
std::map<runanywhere::v1::SDKComponent, std::shared_ptr<LoadedModel>> g_loaded;

// Backend creation is intentionally performed outside g_lifecycle_mutex, but
// the complete check/create/install sequence still has to be single-filed.
// Without this admission gate, concurrent cold loads can both miss the READY
// fast path, initialize duplicate backends, and then replace one another in the
// component slot. Keep this mutex separate from g_lifecycle_mutex: lifecycle
// accessors and destroy_loaded_model() must remain able to drain active refs
// while a load is in progress.
std::mutex g_load_admission_mutex;

// Map a model's declared inference framework to the registered plugin engine
// name (the manifest `.name` each engine publishes). Returns nullptr for
// frameworks that have no dedicated engine (UNSPECIFIED), which keeps the
// caller on plain priority selection.
//
// Why this exists: plugin selection is plain priority order, so the moment a
// high-priority specialist backend (e.g. QHexRT, priority 150) registers it
// wins EVERY load for its primitive — even a generic GGUF model that only
// llamacpp can open. Pinning by the model's own framework lets each model land
// on the engine it was built for, regardless of who else is registered.
const char* engine_name_for_framework(runanywhere::v1::InferenceFramework framework) {
    switch (framework) {
        case runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP:
            return RAC_ENGINE_ID_LLAMACPP;
        case runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT:
            return RAC_ENGINE_ID_QHEXRT;
        case runanywhere::v1::INFERENCE_FRAMEWORK_ONNX:
            return RAC_ENGINE_ID_ONNX;
        case runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA:
            return RAC_ENGINE_ID_SHERPA;
        case runanywhere::v1::INFERENCE_FRAMEWORK_MLX:
            return RAC_ENGINE_ID_MLX;
        case runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
        case runanywhere::v1::INFERENCE_FRAMEWORK_SYSTEM_TTS:
            return RAC_ENGINE_ID_PLATFORM;
        case runanywhere::v1::INFERENCE_FRAMEWORK_COREML:
            return RAC_ENGINE_ID_COREML;
        default:
            return nullptr;
    }
}

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

// Cross-modality DSP eviction. A single Hexagon NPU cannot hold an LLM, a VLM,
// and an embedding backend co-resident — each QHexRT context reserves DSP
// memory at create() time, so loading a second QHexRT-framework model into a
// different component slot OOMs the DSP instead of transparently paging. Before
// creating a new QHexRT (NPU) backend we therefore evict every OTHER component's
// QHexRT model, freeing their DSP contexts. Same-component replacement is handled
// separately by the caller's create-then-swap. Only QHexRT entries are touched:
// CPU/cloud backends (llamacpp, ONNX, platform) are memory-independent and stay
// resident. destroy_loaded_model() drains active_refs, so a model mid-generate
// is never yanked out from under an in-flight request.
std::vector<std::shared_ptr<LoadedModel>>
evict_other_qhexrt_models(runanywhere::v1::SDKComponent keep_component) {
    std::vector<std::shared_ptr<LoadedModel>> victims;
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        for (auto it = g_loaded.begin(); it != g_loaded.end();) {
            if (it->first != keep_component && it->second &&
                it->second->framework == runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT) {
                it->second->state = runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED;
                it->second->updated_at_ms = now_ms();
                victims.push_back(it->second);
                it = g_loaded.erase(it);
            } else {
                ++it;
            }
        }
    }
    for (const auto& victim : victims) {
        RAC_LOG_INFO("model_lifecycle",
                     "Evicting co-resident QHexRT model '%s' to free DSP memory for a new NPU load",
                     victim->model_id.c_str());
        destroy_loaded_model(victim);
    }
    return victims;
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

#if defined(RAC_HAVE_PROTOBUF)
// Install `entry` as the slot occupant for `component`, returning whatever a
// concurrent load installed in the meantime (artifact resolve, auto-download,
// and backend create all run outside g_lifecycle_mutex). Overwriting that
// occupant without destroying it would leak the displaced backend impl. The
// caller destroys the returned entry OUTSIDE the lock —
// destroy_loaded_model() re-acquires g_lifecycle_mutex to drain active_refs.
std::shared_ptr<rac::core::model_lifecycle::detail::LoadedModel>
install_loaded_entry(runanywhere::v1::SDKComponent component,
                     std::shared_ptr<rac::core::model_lifecycle::detail::LoadedModel> entry) {
    namespace detail = rac::core::model_lifecycle::detail;
    std::lock_guard<std::mutex> lock(detail::g_lifecycle_mutex);
    std::shared_ptr<detail::LoadedModel> displaced = std::move(detail::g_loaded[component]);
    detail::g_loaded[component] = std::move(entry);
    return displaced;
}

// Failure-path installer for create-then-swap (A12). A new load that fails
// must not strand the caller with an empty slot: if the previous READY model
// (`preserve`) is still the current occupant, leave it in place and drop the
// error sentinel, so the caller keeps a usable backend. Only when the slot no
// longer holds the preserved model (nothing was resident, a force_reload tore
// it down, or a concurrent load replaced it) does the sentinel take the slot,
// returning the displaced occupant for the caller to destroy. Returns true when
// the preserved model was kept (the sentinel was not installed).
bool install_failed_entry_preserving(
    runanywhere::v1::SDKComponent component,
    const std::shared_ptr<rac::core::model_lifecycle::detail::LoadedModel>& preserve,
    std::shared_ptr<rac::core::model_lifecycle::detail::LoadedModel> failed,
    std::shared_ptr<rac::core::model_lifecycle::detail::LoadedModel>* out_displaced) {
    namespace detail = rac::core::model_lifecycle::detail;
    std::lock_guard<std::mutex> lock(detail::g_lifecycle_mutex);
    auto it = detail::g_loaded.find(component);
    if (preserve && it != detail::g_loaded.end() && it->second == preserve &&
        preserve->state == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
        return true;  // keep the resident model; discard the error sentinel
    }
    std::shared_ptr<detail::LoadedModel> displaced;
    if (it != detail::g_loaded.end()) {
        displaced = std::move(it->second);
    }
    detail::g_loaded[component] = std::move(failed);
    if (out_displaced != nullptr) {
        *out_displaced = std::move(displaced);
    }
    return false;
}

constexpr const char* kLoraAdapterModelIDPrefix = "lora-adapter:";
constexpr const char* kLoraAdapterTag = "lora-adapter";
constexpr const char* kLegacyLoraAdapterTag = "lora";

bool is_lora_adapter_artifact(const runanywhere::v1::ModelInfo& model) {
    if (model.id().rfind(kLoraAdapterModelIDPrefix, 0) == 0) {
        return true;
    }
    if (!model.has_metadata()) {
        return false;
    }
    for (const auto& tag : model.metadata().tags()) {
        if (tag == kLoraAdapterTag || tag == kLegacyLoraAdapterTag) {
            return true;
        }
    }
    return false;
}
#endif  // RAC_HAVE_PROTOBUF
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
    if (is_lora_adapter_artifact(model)) {
        const ModelCategory fail_category = detail::preferred_category_for(request, model);
        const InferenceFramework fail_framework = detail::preferred_framework_for(request, model);
        ModelLoadResult result = detail::make_load_result(
            false, request.model_id(), fail_category, fail_framework, "", {}, 0,
            "LoRA adapter artifacts cannot be loaded as base models; load a compatible base "
            "LLM and apply the adapter through the LoRA API");
        detail::publish_component_event(detail::component_for_category(fail_category),
                                        runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
                                        runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR,
                                        request.model_id(), &result, nullptr,
                                        result.error_message().c_str());
        return detail::copy_proto(result, out_result);
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

    // A model with no local artifact cannot be loaded. Without this guard the
    // resolver falls back to the bare model id (resolved_path_for_model) and
    // the backend receives e.g. "silero-vad" as a file path, failing deep in
    // the engine with a confusing message. Built-ins pass
    // (model_artifact_present treats them as always available).
    if (!detail::model_artifact_present(model)) {
        const ModelCategory fail_category = detail::preferred_category_for(request, model);
        const InferenceFramework fail_framework = detail::preferred_framework_for(request, model);
        ModelLoadResult result = detail::make_load_result(
            false, request.model_id(), fail_category, fail_framework, "", {}, 0,
            "model is not downloaded — download it first or set validate_availability");
        detail::publish_component_event(detail::component_for_category(fail_category),
                                        runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
                                        runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR,
                                        request.model_id(), &result, nullptr,
                                        result.error_message().c_str());
        return detail::copy_proto(result, out_result);
    }

    const ModelCategory category = detail::preferred_category_for(request, model);
    const InferenceFramework framework = detail::preferred_framework_for(request, model);
    const SDKComponent component = detail::component_for_category(category);
    const rac_primitive_t primitive = detail::primitive_for_component(component);
    const detail::ModelArtifactResolution artifact_resolution =
        detail::resolve_model_artifacts(model);
    const std::string& resolved_path = artifact_resolution.resolved_path;

    // Self-heal: lazy resolution recovered a real on-disk path for a registry
    // entry whose local_path was empty (cold-launch re-registration gap —
    // SDKs re-register from URL before their persistence layer backfills).
    // Persist it best-effort so downloadedModels()/getModel() observe the
    // path without each SDK scanning the filesystem itself. Mirrors the
    // download orchestrator's completion-time self-heal.
    if (model.local_path().empty() && !resolved_path.empty() &&
        resolved_path != request.model_id()) {
        const rac_result_t heal_rc = rac_model_registry_update_download_status(
            registry, request.model_id().c_str(), resolved_path.c_str());
        if (heal_rc != RAC_SUCCESS) {
            RAC_LOG_WARNING("ModelLifecycle",
                            "local_path self-heal failed for %s (rc=%d); continuing with "
                            "resolved path",
                            request.model_id().c_str(), heal_rc);
        }
    }

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

    // Serialize the mutating load phase across all component slots. This is
    // deliberately broader than a same-model gate: QHexRT contexts share one
    // process-wide DSP, and different-model loads targeting the same component
    // also need deterministic admission order. Registry lookup, auto-download,
    // and artifact resolution stay outside the gate; the download orchestrator
    // already deduplicates active work for a model.
    std::unique_lock<std::mutex> load_admission_lock(detail::g_load_admission_mutex);

    // Same-component slot handling. The READY fast path is re-checked only
    // after admission, so a concurrent non-force follower observes the model
    // installed by the leader and returns without creating another backend.
    // The previous occupant is captured but left installed so a failed new
    // load does not strand the caller with an empty slot (create-then-swap: the
    // old backend is destroyed only after the new one is created successfully,
    // or explicitly for a same-model force_reload). The destroy stays outside
    // g_lifecycle_mutex because destroy_loaded_model() re-acquires it to wait
    // for active_refs to drain.
    // `previous_loaded` is torn down up front (force-reload only). `swap_previous`
    // is the create-then-swap occupant left installed and displaced on success.
    std::shared_ptr<detail::LoadedModel> previous_loaded;
    std::shared_ptr<detail::LoadedModel> swap_previous;
    ComponentLifecycleState previous_state = runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED;
    {
        std::lock_guard<std::mutex> lock(detail::g_lifecycle_mutex);
        auto existing = detail::g_loaded.find(component);
        if (existing != detail::g_loaded.end()) {
            if (!request.force_reload() && existing->second->model_id == request.model_id() &&
                existing->second->state == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
                ModelLoadResult result = detail::make_load_result(
                    true, existing->second->model_id, existing->second->category,
                    existing->second->framework, existing->second->resolved_path,
                    existing->second->resolved_artifacts, existing->second->loaded_at_ms, "");
                return detail::copy_proto(result, out_result);
            }
            previous_state = existing->second->state;
            // A same-model force_reload cannot hold two backends for one context
            // at once (the reload targets the very DSP/context the old one owns),
            // so tear the old one down up front. A DIFFERENT model keeps the old
            // backend resident until the new one is proven, then swaps.
            if (request.force_reload() && existing->second->model_id == request.model_id()) {
                previous_loaded = existing->second;
                detail::g_loaded.erase(existing);
            } else {
                swap_previous = existing->second;
            }
        }
    }
    detail::destroy_loaded_model(previous_loaded);

    // Cross-modality guard (A5): a new QHexRT/NPU backend cannot co-reside with
    // another component's QHexRT context on the DSP. Evict them before create so
    // the new load has DSP memory; done after the same-component teardown above
    // so a same-model force_reload frees its own context first.
    std::vector<std::shared_ptr<detail::LoadedModel>> evicted_qhexrt_models;
    if (framework == runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT) {
        evicted_qhexrt_models = detail::evict_other_qhexrt_models(component);
    }

    // Component event subscribers are external callbacks and may synchronously
    // re-enter lifecycle APIs. Publish only after releasing the admission gate.
    // The load's transitions are collected here and emitted in their original
    // LOADING-then-terminal order after the slot has reached its terminal state.
    const auto publish_deferred_transitions = [&] {
        for (const auto& evicted : evicted_qhexrt_models) {
            detail::publish_component_event(evicted->component,
                                            runanywhere::v1::COMPONENT_LIFECYCLE_STATE_UNLOADING,
                                            runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
                                            evicted->model_id, nullptr, nullptr, nullptr);
        }
        detail::publish_component_event(component, previous_state,
                                        runanywhere::v1::COMPONENT_LIFECYCLE_STATE_LOADING,
                                        request.model_id(), nullptr, nullptr, nullptr);
    };

    // Pin the engine the model was built for when its framework is known
    // (priority order alone cannot tell two backends serving the same primitive
    // apart — e.g. QHexRT at priority 150 would otherwise hijack every GGUF
    // load meant for llamacpp). Fall back to plain priority selection when the
    // framework is unspecified or its engine isn't registered.
    const char* engine_hint = detail::engine_name_for_framework(framework);
    const rac_engine_vtable_t* vt =
        engine_hint ? rac_plugin_find_for_engine(primitive, engine_hint) : nullptr;
    if (vt) {
        RAC_LOG_INFO("model_lifecycle", "Pinned engine '%s' for framework %s", engine_hint,
                     runanywhere::v1::InferenceFramework_Name(framework).c_str());
    } else {
        vt = rac_plugin_find(primitive);
    }
    if (!vt) {
        std::string error = "no registered backend serves the requested primitive";
        ModelLoadResult result =
            detail::make_load_result(false, request.model_id(), category, framework, resolved_path,
                                     artifact_resolution.artifacts, 0, error);
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
        std::shared_ptr<detail::LoadedModel> displaced;
        const bool preserved = install_failed_entry_preserving(component, swap_previous,
                                                               std::move(failed), &displaced);
        detail::destroy_loaded_model(displaced);
        load_admission_lock.unlock();
        publish_deferred_transitions();
        detail::publish_component_event(
            component,
            preserved ? runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY
                      : runanywhere::v1::COMPONENT_LIFECYCLE_STATE_LOADING,
            preserved ? runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY
                      : runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR,
            // A preserved (kept) model is a clean READY->READY outcome, not an error — don't leak
            // the failed-load message onto it (it would surface as an error banner for a working
            // model).
            request.model_id(), &result, nullptr,
            preserved ? nullptr : result.error_message().c_str());
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
        // Create-then-swap (A12): the previous READY backend was never torn down
        // for a different-model load, so a failed create keeps it resident
        // instead of stranding the slot.
        std::shared_ptr<detail::LoadedModel> displaced;
        const bool preserved = install_failed_entry_preserving(component, swap_previous,
                                                               std::move(failed), &displaced);
        detail::destroy_loaded_model(displaced);
        load_admission_lock.unlock();
        publish_deferred_transitions();
        detail::publish_component_event(
            component,
            preserved ? runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY
                      : runanywhere::v1::COMPONENT_LIFECYCLE_STATE_LOADING,
            preserved ? runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY
                      : runanywhere::v1::COMPONENT_LIFECYCLE_STATE_ERROR,
            // A preserved (kept) model is a clean READY->READY outcome, not an error — don't leak
            // the failed-load message onto it (it would surface as an error banner for a working
            // model).
            request.model_id(), &result, nullptr,
            preserved ? nullptr : result.error_message().c_str());
        return detail::copy_proto(result, out_result);
    }

    int64_t loaded_at_ms = detail::now_ms();
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
    detail::destroy_loaded_model(install_loaded_entry(component, std::move(loaded)));

    ModelLoadResult result =
        detail::make_load_result(true, request.model_id(), category, framework, resolved_path,
                                 artifact_resolution.artifacts, loaded_at_ms, "");
    load_admission_lock.unlock();
    publish_deferred_transitions();
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

    if (!detail::valid_bytes(request_proto_bytes, request_proto_size)) {
        return detail::parse_error(out_result, "CurrentModelRequest bytes are empty or too large");
    }
    CurrentModelRequest request;
    if (!request.ParseFromArray(detail::parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return detail::parse_error(out_result, "failed to parse CurrentModelRequest");
    }

    CurrentModelResult result;
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
            break;
        }
    }
    if (result.model_id().empty()) {
        result.set_found(false);
    }
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
