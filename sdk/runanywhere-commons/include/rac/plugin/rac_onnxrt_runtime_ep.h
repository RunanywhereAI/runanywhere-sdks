/**
 * @file rac_onnxrt_runtime_ep.h
 * @brief Execution-provider (EP) configuration for the ONNX Runtime L1
 *        adapter.
 *
 * RT-ONNX-04: ONNX Runtime supports a pluggable Execution Provider model —
 * CoreML, CUDA, DirectML, NNAPI, QNN, WebGPU, OpenVINO, etc. The onnxrt
 * adapter previously hard-coded CPU-only execution, which meant a router
 * could never pick onnxrt for an NPU/GPU-class primitive even when the
 * underlying ORT build shipped support.
 *
 * This header exposes a tiny enable/disable surface. Each EP is identified
 * by a `rac_onnxrt_ep_type_t` value; at most one EP is "active" at a time.
 * Activation is applied to every subsequent session constructed through the
 * generic ORT tensor runner (`runanywhere::runtime::onnxrt::Session::create`).
 * Existing sessions are unaffected.
 *
 * Provider availability is gated at build time by `RAC_ONNXRT_EP_*`
 * compile definitions. An EP that is not compiled in will return
 * `RAC_ERROR_CAPABILITY_UNSUPPORTED` from `enable_execution_provider`.
 */

#ifndef RAC_PLUGIN_ONNXRT_RUNTIME_EP_H
#define RAC_PLUGIN_ONNXRT_RUNTIME_EP_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/plugin/rac_runtime_vtable.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Execution-provider identifier.
 *
 * Values are stable and cross-platform. An EP whose native headers are not
 * present in the current ORT build, or whose platform is wrong (e.g. CoreML
 * on Linux), will be rejected with `RAC_ERROR_CAPABILITY_UNSUPPORTED`.
 */
typedef enum rac_onnxrt_ep_type {
    RAC_ONNXRT_EP_CPU = 0,      /**< Default CPU EP (no-op — always active). */
    RAC_ONNXRT_EP_COREML = 1,   /**< Apple CoreML (CPU / GPU / ANE fused).  */
    RAC_ONNXRT_EP_CUDA = 2,     /**< NVIDIA CUDA (discrete / integrated).   */
    RAC_ONNXRT_EP_DIRECTML = 3, /**< Windows DirectML (any D3D12 GPU).      */
    RAC_ONNXRT_EP_NNAPI = 4,    /**< Android NNAPI accelerator path.        */
    RAC_ONNXRT_EP_QNN = 5,      /**< Qualcomm QNN HTP / DSP / HMX.          */
    RAC_ONNXRT_EP_WEBGPU = 6,   /**< Emscripten WebGPU EP.                  */
} rac_onnxrt_ep_type_t;

/**
 * @brief Per-EP configuration hook.
 *
 * Keeps the ABI additive — EPs that need knobs (CoreML compute units, CUDA
 * device index, QNN backend path, …) receive them as a JSON blob. The adapter
 * translates known keys into the EP-native struct before calling the ORT
 * append function. Unknown keys are ignored so newer SDKs can light up new
 * EP options against older onnxrt builds without breaking the ABI.
 *
 * Pass `config_json = NULL` for "use EP defaults".
 */
typedef struct rac_onnxrt_ep_config {
    rac_onnxrt_ep_type_t type;
    const char* config_json; /**< Optional. Owned by caller; copied. */
} rac_onnxrt_ep_config_t;

/**
 * Activate an execution provider for subsequent sessions.
 *
 * Calling with `type = RAC_ONNXRT_EP_CPU` clears any prior activation and
 * returns the runtime to pure-CPU execution. Activation is process-wide and
 * idempotent — re-activating the same EP with a different config replaces
 * the stored config.
 *
 * Returns:
 *   - `RAC_SUCCESS` when the EP was compiled in and the config was accepted.
 *   - `RAC_ERROR_CAPABILITY_UNSUPPORTED` when the EP is not available in the
 *     current ORT / platform build (caller should fall back to CPU).
 *   - `RAC_ERROR_INVALID_PARAMETER` on malformed config.
 */
RAC_API rac_result_t
rac_onnxrt_runtime_enable_execution_provider(const rac_onnxrt_ep_config_t* config);

/**
 * Read back the currently active EP.
 *
 * `out` must not be NULL. Returns `RAC_ONNXRT_EP_CPU` when no EP has been
 * activated or activation was cleared.
 */
RAC_API rac_result_t rac_onnxrt_runtime_get_active_ep(rac_onnxrt_ep_type_t* out);

/**
 * Query whether an EP is compiled in for the current build.
 *
 * Returns non-zero when the EP's ORT append path is wired up, zero otherwise.
 * Callers can use this to decide at runtime whether to attempt activation.
 */
RAC_API int rac_onnxrt_runtime_ep_is_available(rac_onnxrt_ep_type_t type);

/**
 * Map an EP type to its matching device class.
 *
 * Used by the router and by `onnxrt_capabilities()` to advertise the correct
 * class when a non-CPU EP is active. Returns `RAC_DEVICE_CLASS_CPU` for
 * `RAC_ONNXRT_EP_CPU` and for any unrecognised value.
 */
RAC_API rac_device_class_t rac_onnxrt_runtime_ep_device_class(rac_onnxrt_ep_type_t type);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_ONNXRT_RUNTIME_EP_H */
