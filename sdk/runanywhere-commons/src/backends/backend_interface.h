/**
 * @file src/backends/backend_interface.h
 * @brief Abstract C++ interface for concrete inference backends.
 *
 * INTERNAL ONLY. Not exposed to SDK consumers via include/.
 *
 * Today, each of the five backends (LlamaCPP, ONNX, WhisperCPP, MetalRT,
 * WhisperKit CoreML) defines its own top-level C++ class and registers a
 * capability-specific vtable (rac_llm_service_ops_t,
 * rac_stt_service_ops_t, ...) with the service registry. That works, but
 * it produces duplicated registration boilerplate and makes it awkward
 * to express "run this model on the first backend that can handle it on
 * the current hardware."
 *
 * IInferenceBackend gathers the cross-capability lifecycle contract
 * (load_model, health_check, cancel, unload, primary_capability,
 * supports_hardware) into a single abstract class so that:
 *
 *   1. New backends can `class MyBackend : public IInferenceBackend` and
 *      get the core contract for free.
 *   2. Registration helpers (`register_backend(...)`) can be written
 *      once in terms of the abstract interface, instead of duplicated
 *      per-capability.
 *   3. Runtime backend selection can consult
 *      `backend->supports_hardware(hardware_report)` to filter out
 *      backends whose required hardware is absent (e.g. MetalRT on
 *      x86 Linux) without each backend's can_handle() having to
 *      rediscover that on its own.
 *
 * This header intentionally stays small. Capability-specific operations
 * (generate_text, transcribe_audio, synthesize_speech, etc.) still live
 * in the per-capability service vtables; the abstract backend is about
 * lifecycle + hardware dispatch, not a god-class.
 *
 * Existing backends don't need to be rewritten to inherit from this
 * interface. Phase 8 introduces the interface and new backends are
 * expected to use it; retrofit of the five legacy backends is
 * incremental and is documented in CPP_LAYER_AUDIT.md as follow-up.
 */

#ifndef RAC_BACKEND_INTERFACE_H
#define RAC_BACKEND_INTERFACE_H

#include <string>
#include <string_view>

#include "rac/core/rac_error.h"
#include "rac/core/rac_hardware.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

namespace rac {
namespace backends {

// Small result struct returned by health_check(). A plain bool would
// conflate "not ready" with "failing"; this is explicit.
struct BackendHealth {
    rac_bool_t is_ready = RAC_FALSE;
    rac_bool_t is_degraded = RAC_FALSE;
    rac_result_t last_error = RAC_SUCCESS;
    std::string diagnostic;  // Free-form, for logs only.
};

// Lightweight capability advertisement. Each backend declares what it
// can serve and what hardware it expects to have. The service registry
// uses these to prune backends before dispatching.
struct BackendAdvertisement {
    rac_capability_t         primary_capability = RAC_CAPABILITY_UNKNOWN;
    rac_inference_framework_t framework = RAC_FRAMEWORK_UNKNOWN;
    int32_t                  priority = 100;  // Higher = preferred on tie-break.
    std::string              name;
    std::string              version;
};

// Abstract inference backend. Concrete backend classes inherit from this
// to opt into the shared lifecycle + hardware dispatch machinery.
class IInferenceBackend {
public:
    virtual ~IInferenceBackend() = default;

    // Deleted because backends own heavyweight state (model memory,
    // worker threads, ORT sessions). Copies are never what the caller
    // wanted.
    IInferenceBackend(const IInferenceBackend&) = delete;
    IInferenceBackend& operator=(const IInferenceBackend&) = delete;

    // ---- Identification / discovery --------------------------------------

    virtual BackendAdvertisement advertise() const noexcept = 0;

    // Return true if this backend can run on the current hardware. Called
    // once at registration so backends can refuse to load on the wrong
    // device (e.g. MetalRT on non-Apple-Silicon). Default implementation
    // accepts any hardware - CPU-only backends can rely on it.
    virtual rac_bool_t supports_hardware(
        const rac_hardware_report_t& /*report*/) const noexcept {
        return RAC_TRUE;
    }

    // ---- Lifecycle -------------------------------------------------------

    // Load a model given an on-disk path plus a JSON-ish config string.
    // Backends that need richer config can parse `config_json` themselves
    // (see e.g. llamacpp_backend.cpp initialize()).
    virtual rac_result_t load_model(std::string_view model_path,
                                    std::string_view config_json) noexcept = 0;

    // Release all resources associated with the currently loaded model.
    virtual rac_result_t unload_model() noexcept = 0;

    // Cooperatively cancel any in-flight inference. Idempotent.
    virtual rac_result_t cancel() noexcept { return RAC_SUCCESS; }

    // Query backend health. Always safe to call, even pre-load.
    virtual BackendHealth health_check() const noexcept = 0;

protected:
    IInferenceBackend() = default;
};

}  // namespace backends
}  // namespace rac

#endif  // RAC_BACKEND_INTERFACE_H
