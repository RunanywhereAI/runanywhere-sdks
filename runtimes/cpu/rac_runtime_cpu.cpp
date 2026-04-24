/**
 * @file rac_runtime_cpu.cpp
 * @brief Built-in CPU runtime plugin.
 *
 * Task T4.1 — see `sdk/runanywhere-commons/docs/RUNTIME_VTABLE_DESIGN.md`.
 *
 * The CPU runtime is always available on every supported host. Its role in
 * the MVP is to guarantee the runtime registry is non-empty and to expose a
 * canonical `RAC_RUNTIME_CPU` descriptor (device info + capabilities) that
 * engines can consult as a fallback. It intentionally does NOT implement
 * `create_session` / `run_session`: compute-capable engines
 * (llama.cpp-CPU, ONNX Runtime CPU EP) keep their own dispatch paths in
 * this phase. When the engine→runtime migration (§7 of the design doc)
 * lands, those engines will move their session code into dedicated runtime
 * plugins that populate these slots.
 *
 * Lifecycle:
 *   init    — no-op, reports success.
 *   destroy — no-op.
 *   device_info — synthesizes a descriptor from `HardwareProfile::cached()`
 *                 so the `device_id` reflects the actual host CPU.
 *   capabilities — static, advertises FP16 + quantised paths which every
 *                  modern CPU backend supports via NEON / AVX / VNNI.
 */

#include "rac_runtime_entry_cpu.h"

#include <cstddef>
#include <cstdint>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"
#include "rac/router/rac_hardware_profile.h"

namespace {

/* --------------------------------------------------------------------------
 * Metadata (lives in .rodata; registry does NOT copy).
 * -------------------------------------------------------------------------- */

const rac_device_class_t k_supported_devices[] = {RAC_DEVICE_CLASS_CPU};

/* Supported primitives — the CPU runtime is format-agnostic, so it declares
 * the service primitives that have a credible CPU path today. Kept static
 * to avoid a separate data-segment allocation at register time. */
const rac_primitive_t k_supported_primitives[] = {
    RAC_PRIMITIVE_GENERATE_TEXT,
    RAC_PRIMITIVE_TRANSCRIBE,
    RAC_PRIMITIVE_SYNTHESIZE,
    RAC_PRIMITIVE_DETECT_VOICE,
    RAC_PRIMITIVE_EMBED,
    RAC_PRIMITIVE_RERANK,
};

/* --------------------------------------------------------------------------
 * Vtable op implementations.
 * -------------------------------------------------------------------------- */

rac_result_t cpu_init(void) {
    return RAC_SUCCESS;
}

void cpu_destroy(void) {
    /* Nothing to tear down — the CPU runtime is stateless. */
}

/** Mapping from detected CpuVendor / GpuVendor to a stable device id string.
 *  The string is returned as a pointer into process-constant storage; the
 *  registry stores only the pointer. */
const char* cpu_device_id_from_profile() {
    using rac::router::CpuVendor;
    using rac::router::HardwareProfile;
    const HardwareProfile& hp = HardwareProfile::cached();
    switch (hp.cpu_vendor) {
        case CpuVendor::Apple:    return "cpu-apple";
        case CpuVendor::Intel:    return "cpu-intel";
        case CpuVendor::Amd:      return "cpu-amd";
        case CpuVendor::Arm:      return "cpu-arm";
        case CpuVendor::Qualcomm: return "cpu-qualcomm";
        case CpuVendor::Other:    return "cpu-other";
        case CpuVendor::Unknown:
        default:                  return "cpu-generic";
    }
}

rac_result_t cpu_device_info(rac_runtime_device_info_t* out) {
    if (out == nullptr) return RAC_ERROR_NULL_POINTER;
    const rac::router::HardwareProfile& hp = rac::router::HardwareProfile::cached();
    *out = rac_runtime_device_info_t{};
    out->device_class = RAC_DEVICE_CLASS_CPU;
    out->device_id    = cpu_device_id_from_profile();
    out->display_name = "CPU (generic)";
    out->memory_bytes = static_cast<uint64_t>(hp.total_ram_bytes);
    return RAC_SUCCESS;
}

rac_result_t cpu_capabilities(rac_runtime_capabilities_t* out) {
    if (out == nullptr) return RAC_ERROR_NULL_POINTER;
    *out = rac_runtime_capabilities_t{};
    out->capability_flags =
        RAC_RUNTIME_CAP_QUANTIZED_INT8 |
        RAC_RUNTIME_CAP_QUANTIZED_INT4 |
        RAC_RUNTIME_CAP_FP16           |
        RAC_RUNTIME_CAP_DYNAMIC_SHAPES;
    out->supported_formats       = nullptr;     /* format-agnostic */
    out->supported_formats_count = 0;
    out->supported_primitives    = k_supported_primitives;
    out->supported_primitives_count =
        sizeof(k_supported_primitives) / sizeof(k_supported_primitives[0]);
    return RAC_SUCCESS;
}

/* --------------------------------------------------------------------------
 * Vtable singleton. Every op slot is filled explicitly (including the
 * intentionally-NULL session ops) so layout matches the header exactly and
 * a future reserved-slot promotion is a compile-time error.
 * -------------------------------------------------------------------------- */

const rac_runtime_vtable_t k_cpu_vtable = {
    /* .metadata = */ {
        /* .abi_version             = */ RAC_RUNTIME_ABI_VERSION,
        /* .id                      = */ RAC_RUNTIME_CPU,
        /* .name                    = */ "cpu",
        /* .display_name            = */ "Built-in CPU",
        /* .version                 = */ "1.0.0",
        /* .priority                = */ 0,
        /* .supported_formats       = */ nullptr,
        /* .supported_formats_count = */ 0,
        /* .supported_devices       = */ k_supported_devices,
        /* .supported_devices_count = */
            sizeof(k_supported_devices) / sizeof(k_supported_devices[0]),
        /* .reserved_0              = */ 0,
        /* .reserved_1              = */ 0,
    },
    /* .init            = */ cpu_init,
    /* .destroy         = */ cpu_destroy,
    /* .create_session  = */ nullptr,
    /* .run_session     = */ nullptr,
    /* .destroy_session = */ nullptr,
    /* .alloc_buffer    = */ nullptr,
    /* .free_buffer     = */ nullptr,
    /* .device_info     = */ cpu_device_info,
    /* .capabilities    = */ cpu_capabilities,
    /* .reserved_slot_0 = */ nullptr,
    /* .reserved_slot_1 = */ nullptr,
    /* .reserved_slot_2 = */ nullptr,
    /* .reserved_slot_3 = */ nullptr,
    /* .reserved_slot_4 = */ nullptr,
    /* .reserved_slot_5 = */ nullptr,
};

}  // namespace

extern "C" RAC_API const rac_runtime_vtable_t* rac_runtime_entry_cpu(void) {
    return &k_cpu_vtable;
}

/* Registration:
 *   The CPU runtime is bootstrapped explicitly by rac_commons' registry TU
 *   (see `rac_runtime_registry.cpp::BuiltinBootstrap`) so it does NOT rely
 *   on RAC_STATIC_RUNTIME_REGISTER's linker-keep-alive dance. This makes the
 *   CPU runtime work out-of-the-box on every build configuration (iOS
 *   static-linked xcframework, Android .so, plain unit test, …) without
 *   needing a per-host `-force_load` invocation.
 *
 *   The RAC_STATIC_RUNTIME_REGISTER path is still exercised by the
 *   loader-fixture in tests/test_runtime_loader.cpp — we don't need a second
 *   copy here. */ 
