/*
 * RESERVED / EXPERIMENTAL — capability-only Metal runtime.
 *
 * This runtime is a pure presence gate: it fills only the MANDATORY capability
 * role (init/destroy + device_info + capabilities) and leaves every
 * session-execution slot NULL (no RAC_RUNTIME_CAP_SESSION_EXECUTION). The NULL
 * session slots are BY DESIGN, not unfinished work — the real Metal compute
 * path lives inside llama.cpp/ggml, never here. Its only consumer is the
 * `metalrt` engine (Apple-only, RAC_BACKEND_METALRT defaults OFF — dormant),
 * which calls `rac_metal_runtime_require_available()` to assert the device is
 * registered before routing. Reserved for future first-class Metal runtimes.
 * See runtimes/AGENTS.md ("Reserved / experimental: metal").
 */
#include "rac_runtime_metal.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <mutex>

#include "rac/plugin/rac_model_format_ids.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"

namespace {

/* Serialize all access to the g_device / g_queue file-scope
 * globals. The registry calls vtable->init() and vtable->destroy() outside
 * the registry lock (see sdk/runanywhere-commons/src/plugin/
 * rac_runtime_registry.cpp:264), so two concurrent
 * rac_runtime_register/_unregister calls -- or a device_info query arriving
 * during tear-down -- could read/write these without ordering. One mutex
 * is enough to make init/destroy idempotent and to keep the
 * consult-and-use sequence in device_info atomic. */
std::mutex& metal_globals_mutex() {
    static std::mutex m;
    return m;
}

id<MTLDevice> g_device = nil;
id<MTLCommandQueue> g_queue = nil;

const rac_device_class_t k_supported_devices[] = {RAC_DEVICE_CLASS_GPU};
const uint32_t k_supported_formats[] = {
    RAC_MODEL_FORMAT_ID_GGUF,
    RAC_MODEL_FORMAT_ID_COREML,
    RAC_MODEL_FORMAT_ID_MLMODEL,
    RAC_MODEL_FORMAT_ID_MLPACKAGE,
};

rac_result_t metal_init(void) {
    std::lock_guard<std::mutex> lock(metal_globals_mutex());
    if (g_device != nil)
        return RAC_SUCCESS;
    g_device = MTLCreateSystemDefaultDevice();
    if (g_device == nil) {
        return RAC_ERROR_CAPABILITY_UNSUPPORTED;
    }
    g_queue = [g_device newCommandQueue];
    if (g_queue == nil) {
        [g_device release];
        g_device = nil;
        return RAC_ERROR_CAPABILITY_UNSUPPORTED;
    }
    return RAC_SUCCESS;
}

void metal_destroy(void) {
    std::lock_guard<std::mutex> lock(metal_globals_mutex());
    if (g_queue != nil) {
        [g_queue release];
        g_queue = nil;
    }
    if (g_device != nil) {
        [g_device release];
        g_device = nil;
    }
}

rac_result_t metal_device_info(rac_runtime_device_info_t* out) {
    if (!out)
        return RAC_ERROR_NULL_POINTER;
    /* Lock across the device read + property query so a
     * concurrent destroy() cannot release g_device between the nil check
     * and the recommendedMaxWorkingSetSize call. */
    std::lock_guard<std::mutex> lock(metal_globals_mutex());
    if (g_device == nil)
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    *out = rac_runtime_device_info_t{};
    out->device_class = RAC_DEVICE_CLASS_GPU;
    out->device_id = "apple-metal";
    out->display_name = "Apple Metal";
    out->memory_bytes = [g_device recommendedMaxWorkingSetSize];
    return RAC_SUCCESS;
}

rac_result_t metal_capabilities(rac_runtime_capabilities_t* out) {
    if (!out)
        return RAC_ERROR_NULL_POINTER;
    *out = rac_runtime_capabilities_t{};
    /* Metal is a capability-only runtime: it reports the Metal device's
     * presence + info for the engine router's hardware-aware selection but
     * provides no session execution and no buffer allocation (real Metal
     * compute lives inside llama.cpp/ggml). So advertise only descriptive
     * capabilities (FP16 + supported_formats) -- no ZERO_COPY / BUFFER_* /
     * DEVICE_ALLOC / OWNED_OUTPUTS, and never RAC_RUNTIME_CAP_SESSION_EXECUTION
     * since the session slots are NULL. */
    out->capability_flags = RAC_RUNTIME_CAP_FP16;
    out->supported_formats = k_supported_formats;
    out->supported_formats_count = sizeof(k_supported_formats) / sizeof(k_supported_formats[0]);
    out->supported_primitives = nullptr;
    out->supported_primitives_count = 0;
    return RAC_SUCCESS;
}

// Capability-only: no session, no device buffers — all v2 op slots NULL.
const rac_runtime_vtable_v2_t k_metal_vtable_v2 = RAC_RUNTIME_VTABLE_V2_CAPABILITY_ONLY;

const rac_runtime_vtable_t k_metal_vtable = {
    /* .metadata = */ {
        /* .abi_version             = */ RAC_RUNTIME_ABI_VERSION,
        /* .id                      = */ RAC_RUNTIME_METAL,
        /* .name                    = */ "metal",
        /* .display_name            = */ "Apple Metal",
        /* .version                 = */ nullptr,
        /* .priority                = */ 100,
        /* .supported_formats       = */ k_supported_formats,
        /* .supported_formats_count = */ sizeof(k_supported_formats) /
            sizeof(k_supported_formats[0]),
        /* .supported_devices       = */ k_supported_devices,
        /* .supported_devices_count = */ sizeof(k_supported_devices) /
            sizeof(k_supported_devices[0]),
        /* .reserved_0              = */ 0,
        /* .reserved_1              = */ 0,
    },
    /* .init            = */ metal_init,
    /* .destroy         = */ metal_destroy,
    /* .create_session  = */ nullptr,
    /* .run_session     = */ nullptr,
    /* .destroy_session = */ nullptr,
    /* .alloc_buffer    = */ nullptr,
    /* .free_buffer     = */ nullptr,
    /* .device_info     = */ metal_device_info,
    /* .capabilities    = */ metal_capabilities,
    /* .reserved_slot_0 = */ &k_metal_vtable_v2,
    /* .reserved_slot_1 = */ nullptr,
    /* .reserved_slot_2 = */ nullptr,
    /* .reserved_slot_3 = */ nullptr,
    /* .reserved_slot_4 = */ nullptr,
    /* .reserved_slot_5 = */ nullptr,
};

}  // namespace

extern "C" rac_result_t rac_metal_runtime_require_available(void) {
    return rac_runtime_get_by_id(RAC_RUNTIME_METAL) != nullptr ? RAC_SUCCESS
                                                               : RAC_ERROR_BACKEND_UNAVAILABLE;
}

extern "C" RAC_API const rac_runtime_vtable_t* rac_runtime_entry_metal(void) {
    return &k_metal_vtable;
}

RAC_STATIC_RUNTIME_REGISTER(metal);
