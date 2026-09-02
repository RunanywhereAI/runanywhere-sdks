/**
 * @file model_lifecycle_accessors.cpp
 * @brief Per-modality lifecycle accessor namespaces for model lifecycle.
 *
 * Extracted from the original `model_lifecycle.cpp`
 * SRP split. Owns the `rac::llm`, `rac::vlm`, and `rac::lifecycle`
 * namespace functions used by feature TUs to pin the currently-loaded
 * component implementation across the lifecycle of an inference.
 */

#include "model_lifecycle_internal.h"

#include <map>
#include <memory>
#include <mutex>

#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "features/rac_nonllm_lifecycle_bridge.h"
#include "features/vlm/rac_vlm_lifecycle_bridge.h"
#include "rac/core/rac_model_lifecycle.h"

namespace rac::llm {

#if defined(RAC_HAVE_PROTOBUF)
using rac::core::model_lifecycle::detail::c_framework_from_proto;
using rac::core::model_lifecycle::detail::g_lifecycle_cv;
using rac::core::model_lifecycle::detail::g_lifecycle_mutex;
using rac::core::model_lifecycle::detail::g_loaded;
using rac::core::model_lifecycle::detail::LoadedModel;
#endif

rac_result_t acquire_lifecycle_llm(LifecycleLlmRef* out_ref) {
    if (!out_ref) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_ref = {};
#if !defined(RAC_HAVE_PROTOBUF)
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    auto token = std::make_unique<std::shared_ptr<LoadedModel>>();
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        auto it = g_loaded.find(runanywhere::v1::SDK_COMPONENT_LLM);
        if (it == g_loaded.end() ||
            it->second->state != runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
            return RAC_ERROR_NOT_INITIALIZED;
        }
        if (!it->second->impl || !it->second->llm_ops) {
            return RAC_ERROR_NOT_SUPPORTED;
        }
        *token = it->second;
        (*token)->active_refs += 1;
        out_ref->ops = (*token)->llm_ops;
        out_ref->impl = (*token)->impl;
        out_ref->model_id = (*token)->model_id.c_str();
        out_ref->framework_name = (*token)->framework_name.c_str();
        out_ref->framework = c_framework_from_proto((*token)->framework);
        // LoRA support is a backend capability: any engine whose vtable exposes
        // load_lora (llama.cpp) can attach adapters, regardless of whether the
        // registry entry declared it — dynamically registered hf/URL models
        // default the flag false. Trust the real capability, falling back to the
        // declared flag for backends that gate it some other way.
        out_ref->supports_lora =
            ((*token)->llm_ops && (*token)->llm_ops->load_lora != nullptr) ||
            (*token)->model.supports_lora();
        // Backend capability, gated on the framework enum: only QHexRT currently
        // consumes rac_llm_options_t.grammar (on-device grammar-constrained
        // decoding). Every other engine leaves this false, so the grammar attach
        // in the tool-calling loop is a no-op for llama.cpp/onnx/cloud.
        out_ref->supports_grammar =
            (*token)->framework == runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT;
        // Declared capability, normalized at the registry boundary
        // (normalize_thinking_capability, model_registry.cpp): a row that says
        // it reasons also carries the tag pair the splitter uses.
        out_ref->supports_thinking = (*token)->model.supports_thinking();
        // Optional prefill signal stamped at QHexRT load from the bundle
        // manifest (gen_prefill) or the DeepSeek-R1-Distill name heuristic.
        // Unset ≠ false: only has_template_prefills_open_tag() && value arms
        // start_inside_reasoning() in the stream gate.
        out_ref->template_prefills_open_tag =
            (*token)->model.has_thinking_pattern() &&
            (*token)->model.thinking_pattern().has_template_prefills_open_tag() &&
            (*token)->model.thinking_pattern().template_prefills_open_tag();
    }
    out_ref->opaque = token.release();
    return RAC_SUCCESS;
#endif
}

bool lifecycle_llm_supports_grammar() {
    LifecycleLlmRef ref;
    if (acquire_lifecycle_llm(&ref) != RAC_SUCCESS) {
        return false;
    }
    const bool supported = ref.supports_grammar;
    release_lifecycle_llm(&ref);
    return supported;
}

std::string lifecycle_llm_model_id() {
    LifecycleLlmRef ref;
    if (acquire_lifecycle_llm(&ref) != RAC_SUCCESS) {
        return std::string();
    }
    std::string id = ref.model_id ? ref.model_id : "";
    release_lifecycle_llm(&ref);
    return id;
}

void release_lifecycle_llm(LifecycleLlmRef* ref) {
    if (!ref || !ref->opaque) {
        return;
    }
#if defined(RAC_HAVE_PROTOBUF)
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        if (*token && (*token)->active_refs > 0) {
            (*token)->active_refs -= 1;
        }
    }
    g_lifecycle_cv.notify_all();
    delete token;
#endif
    *ref = {};
}

void clear_lifecycle_llm_cancel(LifecycleLlmRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    if (!ref || !ref->opaque) {
        return;
    }
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    if (*token) {
        (*token)->cancel_requested.store(false, std::memory_order_relaxed);
    }
#else
    (void)ref;
#endif
}

void request_lifecycle_llm_cancel(LifecycleLlmRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    if (!ref || !ref->opaque) {
        return;
    }
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    if (*token) {
        (*token)->cancel_requested.store(true, std::memory_order_relaxed);
    }
#else
    (void)ref;
#endif
}

bool lifecycle_llm_cancel_requested(const LifecycleLlmRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    if (!ref || !ref->opaque) {
        return false;
    }
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    return *token && (*token)->cancel_requested.load(std::memory_order_relaxed);
#else
    (void)ref;
    return false;
#endif
}

}  // namespace rac::llm

namespace rac::vlm {

#if defined(RAC_HAVE_PROTOBUF)
using rac::core::model_lifecycle::detail::g_lifecycle_cv;
using rac::core::model_lifecycle::detail::g_lifecycle_mutex;
using rac::core::model_lifecycle::detail::g_loaded;
using rac::core::model_lifecycle::detail::LoadedModel;
#endif

rac_result_t acquire_lifecycle_vlm(LifecycleVlmRef* out_ref) {
    if (!out_ref) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_ref = {};
#if !defined(RAC_HAVE_PROTOBUF)
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    auto token = std::make_unique<std::shared_ptr<LoadedModel>>();
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        auto it = g_loaded.find(runanywhere::v1::SDK_COMPONENT_VLM);
        if (it == g_loaded.end() ||
            it->second->state != runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
            return RAC_ERROR_NOT_INITIALIZED;
        }
        if (!it->second->impl || !it->second->vlm_ops) {
            return RAC_ERROR_NOT_SUPPORTED;
        }
        *token = it->second;
        (*token)->active_refs += 1;
        out_ref->ops = (*token)->vlm_ops;
        out_ref->impl = (*token)->impl;
        out_ref->model_id = (*token)->model_id.c_str();
        out_ref->framework_name = (*token)->framework_name.c_str();
    }
    out_ref->opaque = token.release();
    return RAC_SUCCESS;
#endif
}

void release_lifecycle_vlm(LifecycleVlmRef* ref) {
    if (!ref || !ref->opaque) {
        return;
    }
#if defined(RAC_HAVE_PROTOBUF)
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        if (*token && (*token)->active_refs > 0) {
            (*token)->active_refs -= 1;
        }
    }
    g_lifecycle_cv.notify_all();
    delete token;
#endif
    *ref = {};
}

void clear_lifecycle_vlm_cancel(LifecycleVlmRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    if (!ref || !ref->opaque) {
        return;
    }
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    if (*token) {
        (*token)->cancel_requested.store(false, std::memory_order_relaxed);
    }
#else
    (void)ref;
#endif
}

void request_lifecycle_vlm_cancel(LifecycleVlmRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    if (!ref || !ref->opaque) {
        return;
    }
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    if (*token) {
        (*token)->cancel_requested.store(true, std::memory_order_relaxed);
    }
#else
    (void)ref;
#endif
}

bool lifecycle_vlm_cancel_requested(const LifecycleVlmRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    if (!ref || !ref->opaque) {
        return false;
    }
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    return *token && (*token)->cancel_requested.load(std::memory_order_relaxed);
#else
    (void)ref;
    return false;
#endif
}

}  // namespace rac::vlm

namespace rac::lifecycle {

#if defined(RAC_HAVE_PROTOBUF)
using rac::core::model_lifecycle::detail::g_lifecycle_cv;
using rac::core::model_lifecycle::detail::g_lifecycle_mutex;
using rac::core::model_lifecycle::detail::g_loaded;
using rac::core::model_lifecycle::detail::LoadedModel;

namespace {

template <typename Ref, typename OpsPtr>
rac_result_t acquire_component(runanywhere::v1::SDKComponent component, Ref* out_ref,
                               OpsPtr LoadedModel::* ops_field) {
    if (!out_ref) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_ref = {};

    auto token = std::make_unique<std::shared_ptr<LoadedModel>>();
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        auto it = g_loaded.find(component);
        if (it == g_loaded.end() ||
            it->second->state != runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY) {
            return RAC_ERROR_NOT_INITIALIZED;
        }
        const auto* ops = it->second.get()->*ops_field;
        if (!it->second->impl || !ops) {
            return RAC_ERROR_NOT_SUPPORTED;
        }
        *token = it->second;
        (*token)->active_refs += 1;
        out_ref->ops = ops;
        out_ref->impl = (*token)->impl;
        out_ref->model_id = (*token)->model_id.c_str();
        out_ref->framework_name = (*token)->framework_name.c_str();
    }
    out_ref->opaque = token.release();
    return RAC_SUCCESS;
}

template <typename Ref>
void release_component(Ref* ref) {
    if (!ref || !ref->opaque) {
        return;
    }
    auto* token = static_cast<std::shared_ptr<LoadedModel>*>(ref->opaque);
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_mutex);
        if (*token && (*token)->active_refs > 0) {
            (*token)->active_refs -= 1;
        }
    }
    g_lifecycle_cv.notify_all();
    delete token;
    *ref = {};
}

}  // namespace
#endif

rac_result_t acquire_lifecycle_stt(LifecycleSttRef* out_ref) {
#if !defined(RAC_HAVE_PROTOBUF)
    if (out_ref)
        *out_ref = {};
    return out_ref ? RAC_ERROR_FEATURE_NOT_AVAILABLE : RAC_ERROR_NULL_POINTER;
#else
    return acquire_component(runanywhere::v1::SDK_COMPONENT_STT, out_ref, &LoadedModel::stt_ops);
#endif
}

void release_lifecycle_stt(LifecycleSttRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    release_component(ref);
#else
    if (ref)
        *ref = {};
#endif
}

rac_result_t acquire_lifecycle_tts(LifecycleTtsRef* out_ref) {
#if !defined(RAC_HAVE_PROTOBUF)
    if (out_ref)
        *out_ref = {};
    return out_ref ? RAC_ERROR_FEATURE_NOT_AVAILABLE : RAC_ERROR_NULL_POINTER;
#else
    return acquire_component(runanywhere::v1::SDK_COMPONENT_TTS, out_ref, &LoadedModel::tts_ops);
#endif
}

void release_lifecycle_tts(LifecycleTtsRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    release_component(ref);
#else
    if (ref)
        *ref = {};
#endif
}

rac_result_t acquire_lifecycle_vad(LifecycleVadRef* out_ref) {
#if !defined(RAC_HAVE_PROTOBUF)
    if (out_ref)
        *out_ref = {};
    return out_ref ? RAC_ERROR_FEATURE_NOT_AVAILABLE : RAC_ERROR_NULL_POINTER;
#else
    return acquire_component(runanywhere::v1::SDK_COMPONENT_VAD, out_ref, &LoadedModel::vad_ops);
#endif
}

void release_lifecycle_vad(LifecycleVadRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    release_component(ref);
#else
    if (ref)
        *ref = {};
#endif
}

rac_result_t acquire_lifecycle_embeddings(LifecycleEmbeddingsRef* out_ref) {
#if !defined(RAC_HAVE_PROTOBUF)
    if (out_ref)
        *out_ref = {};
    return out_ref ? RAC_ERROR_FEATURE_NOT_AVAILABLE : RAC_ERROR_NULL_POINTER;
#else
    return acquire_component(runanywhere::v1::SDK_COMPONENT_EMBEDDINGS, out_ref,
                             &LoadedModel::embeddings_ops);
#endif
}

void release_lifecycle_embeddings(LifecycleEmbeddingsRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    release_component(ref);
#else
    if (ref)
        *ref = {};
#endif
}

rac_result_t acquire_lifecycle_diffusion(LifecycleDiffusionRef* out_ref) {
#if !defined(RAC_HAVE_PROTOBUF)
    if (out_ref)
        *out_ref = {};
    return out_ref ? RAC_ERROR_FEATURE_NOT_AVAILABLE : RAC_ERROR_NULL_POINTER;
#else
    return acquire_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION, out_ref,
                             &LoadedModel::diffusion_ops);
#endif
}

void release_lifecycle_diffusion(LifecycleDiffusionRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    release_component(ref);
#else
    if (ref)
        *ref = {};
#endif
}

rac_result_t acquire_lifecycle_diarization(LifecycleDiarizationRef* out_ref) {
#if !defined(RAC_HAVE_PROTOBUF)
    if (out_ref)
        *out_ref = {};
    return out_ref ? RAC_ERROR_FEATURE_NOT_AVAILABLE : RAC_ERROR_NULL_POINTER;
#else
    return acquire_component(runanywhere::v1::SDK_COMPONENT_SPEAKER_DIARIZATION, out_ref,
                             &LoadedModel::diarization_ops);
#endif
}

void release_lifecycle_diarization(LifecycleDiarizationRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    release_component(ref);
#else
    if (ref)
        *ref = {};
#endif
}

rac_result_t acquire_lifecycle_segmentation(LifecycleSegmentationRef* out_ref) {
#if !defined(RAC_HAVE_PROTOBUF)
    if (out_ref)
        *out_ref = {};
    return out_ref ? RAC_ERROR_FEATURE_NOT_AVAILABLE : RAC_ERROR_NULL_POINTER;
#else
    return acquire_component(runanywhere::v1::SDK_COMPONENT_SEMANTIC_SEGMENTATION, out_ref,
                             &LoadedModel::segmentation_ops);
#endif
}

void release_lifecycle_segmentation(LifecycleSegmentationRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    release_component(ref);
#else
    if (ref)
        *ref = {};
#endif
}

rac_result_t acquire_lifecycle_ocr(LifecycleOcrRef* out_ref) {
#if !defined(RAC_HAVE_PROTOBUF)
    if (out_ref)
        *out_ref = {};
    return out_ref ? RAC_ERROR_FEATURE_NOT_AVAILABLE : RAC_ERROR_NULL_POINTER;
#else
    return acquire_component(runanywhere::v1::SDK_COMPONENT_OCR, out_ref, &LoadedModel::ocr_ops);
#endif
}

void release_lifecycle_ocr(LifecycleOcrRef* ref) {
#if defined(RAC_HAVE_PROTOBUF)
    release_component(ref);
#else
    if (ref)
        *ref = {};
#endif
}

}  // namespace rac::lifecycle

// ---------------------------------------------------------------------------
// Loaded-state query and unload
//
// The storage delete path needs to know whether a model is open before it
// removes files underneath it, and needs to close it when it is. Hosts answer
// both through rac_storage_callbacks_t, but commons is the component that
// performed the load and already tracks it in g_loaded, so it can answer and
// act without asking anyone. Internal on purpose: the only caller is inside
// commons, so this stays off the public C ABI.
// ---------------------------------------------------------------------------

namespace rac::lifecycle {

bool is_model_loaded(const char* model_id) {
#if defined(RAC_HAVE_PROTOBUF)
    if (model_id == nullptr || *model_id == '\0') {
        return false;
    }
    std::lock_guard<std::mutex> lock(rac::core::model_lifecycle::detail::g_lifecycle_mutex);
    for (const auto& entry : rac::core::model_lifecycle::detail::g_loaded) {
        const auto& loaded = entry.second;
        // READY is the discriminator, not mere presence in g_loaded. A load that
        // failed leaves an ERROR sentinel carrying the failed request's model_id
        // (install_failed_entry_preserving), and that model has no backend at
        // all, so reporting it loaded made it undeletable, which is the opposite
        // of what a user wants after a failed load. READY and ERROR are the only
        // states ever installed, so this is exact, and it matches what
        // acquire_lifecycle_llm / acquire_component already require.
        if (loaded && loaded->state == runanywhere::v1::COMPONENT_LIFECYCLE_STATE_READY &&
            loaded->model_id == model_id) {
            return true;
        }
    }
    return false;
#else
    (void)model_id;
    return false;
#endif
}

rac_result_t unload_model(const char* model_id) {
#if defined(RAC_HAVE_PROTOBUF)
    if (model_id == nullptr || *model_id == '\0') {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    // Delegate to the one unload implementation rather than re-walking g_loaded
    // here: it already erases under the lifecycle mutex, destroys the backends
    // outside it, and publishes UNLOADING->NOT_LOADED for each entry. A second
    // hand-rolled copy of that sequence is exactly how the two paths drift.
    runanywhere::v1::ModelUnloadRequest request;
    request.set_model_id(model_id);
    std::string bytes;
    if (!request.SerializeToString(&bytes)) {
        return RAC_ERROR_INTERNAL;
    }
    rac_proto_buffer_t out{};
    rac_result_t rc = rac_model_lifecycle_unload_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &out);
    if (rc == RAC_SUCCESS) {
        // The C entry point reports "nothing matched" inside the result, not in
        // its return code, so an unmatched id would otherwise read as success.
        runanywhere::v1::ModelUnloadResult result;
        if (out.data != nullptr && out.size > 0 &&
            result.ParseFromArray(out.data, static_cast<int>(out.size))) {
            if (result.unloaded_model_ids_size() == 0) {
                rc = RAC_ERROR_MODEL_NOT_LOADED;
            }
        } else {
            rc = RAC_ERROR_MODEL_NOT_LOADED;
        }
    }
    rac_proto_buffer_free(&out);
    return rc;
#else
    (void)model_id;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

}  // namespace rac::lifecycle
