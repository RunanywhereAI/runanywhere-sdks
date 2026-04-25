/**
 * @file rac_runtime_cpu.cpp
 * @brief Built-in CPU runtime plugin.
 *
 * Task T4.1 — see `sdk/runanywhere-commons/docs/RUNTIME_VTABLE_DESIGN.md`.
 *
 * The CPU runtime is always available on every supported host. It guarantees
 * the runtime registry is non-empty and exposes a canonical `RAC_RUNTIME_CPU`
 * descriptor (device info + capabilities). Session execution is delegated to
 * CPU providers registered by engine plugins, which keeps rac_commons from
 * linking directly against engine implementations such as llama.cpp.
 *
 * Lifecycle:
 *   init    — no-op, reports success.
 *   destroy — no-op.
 *   device_info — synthesizes a descriptor from `HardwareProfile::cached()`
 *                 so the `device_id` reflects the actual host CPU.
 *   capabilities — static, advertises FP16 + quantised paths which every
 *                  modern CPU backend supports via NEON / AVX / VNNI.
 *   sessions — delegated to registered rac_cpu_runtime_provider_t entries.
 */

#include "rac_runtime_entry_cpu.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <new>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_cpu_runtime_provider.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"
#include "rac/router/rac_hardware_profile.h"

namespace {

constexpr uint64_t kCpuSessionMagic = 0x5241434350555345ull; /* "RACCPUSE" */

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

struct CpuRuntimeSession {
    uint64_t magic = kCpuSessionMagic;
    rac_cpu_runtime_provider_t provider{};
    rac_runtime_session_t* provider_session = nullptr;
};

std::mutex& provider_mutex() {
    static std::mutex mutex;
    return mutex;
}

std::vector<rac_cpu_runtime_provider_t>& providers() {
    static std::vector<rac_cpu_runtime_provider_t> entries;
    return entries;
}

bool primitive_is_supported(rac_primitive_t primitive) {
    for (rac_primitive_t supported : k_supported_primitives) {
        if (supported == primitive) return true;
    }
    return false;
}

bool provider_supports_format(const rac_cpu_runtime_provider_t& provider,
                              uint32_t model_format) {
    if (provider.formats == nullptr || provider.formats_count == 0 || model_format == 0) {
        return true;
    }
    for (size_t i = 0; i < provider.formats_count; ++i) {
        if (provider.formats[i] == model_format) return true;
    }
    return false;
}

bool find_provider(const rac_runtime_session_desc_t* desc,
                   rac_cpu_runtime_provider_t* out_provider) {
    std::lock_guard<std::mutex> lock(provider_mutex());
    for (const auto& provider : providers()) {
        if (provider.primitive == desc->primitive &&
            provider_supports_format(provider, desc->model_format)) {
            *out_provider = provider;
            return true;
        }
    }
    return false;
}

CpuRuntimeSession* as_cpu_session(rac_runtime_session_t* session) {
    auto* cpu_session = reinterpret_cast<CpuRuntimeSession*>(session);
    if (cpu_session == nullptr || cpu_session->magic != kCpuSessionMagic) {
        return nullptr;
    }
    return cpu_session;
}

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

rac_result_t cpu_create_session(const rac_runtime_session_desc_t* desc,
                                rac_runtime_session_t** out) {
    if (out == nullptr || desc == nullptr) return RAC_ERROR_NULL_POINTER;
    *out = nullptr;

    if (!primitive_is_supported(desc->primitive)) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    if ((desc->model_path == nullptr || desc->model_path[0] == '\0') &&
        (desc->model_blob == nullptr || desc->model_blob_bytes == 0)) {
        return RAC_ERROR_INVALID_PATH;
    }

    rac_cpu_runtime_provider_t provider{};
    if (!find_provider(desc, &provider)) {
        return RAC_ERROR_NOT_IMPLEMENTED;
    }

    rac_runtime_session_t* provider_session = nullptr;
    rac_result_t rc = provider.create_session(desc, &provider_session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (provider_session == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }

    auto* session = new (std::nothrow) CpuRuntimeSession();
    if (session == nullptr) {
        provider.destroy_session(provider_session);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    session->provider = provider;
    session->provider_session = provider_session;
    *out = reinterpret_cast<rac_runtime_session_t*>(session);
    return RAC_SUCCESS;
}

rac_result_t cpu_run_session(rac_runtime_session_t* session,
                             const rac_runtime_io_t* inputs, size_t n_in,
                             rac_runtime_io_t* outputs, size_t n_out) {
    auto* cpu_session = as_cpu_session(session);
    if (cpu_session == nullptr) return RAC_ERROR_INVALID_HANDLE;
    if (n_in > 0 && inputs == nullptr) return RAC_ERROR_NULL_POINTER;
    if (n_out > 0 && outputs == nullptr) return RAC_ERROR_NULL_POINTER;
    return cpu_session->provider.run_session(
        cpu_session->provider_session, inputs, n_in, outputs, n_out);
}

void cpu_destroy_session(rac_runtime_session_t* session) {
    auto* cpu_session = as_cpu_session(session);
    if (cpu_session == nullptr) return;
    cpu_session->magic = 0;
    if (cpu_session->provider.destroy_session != nullptr &&
        cpu_session->provider_session != nullptr) {
        cpu_session->provider.destroy_session(cpu_session->provider_session);
    }
    delete cpu_session;
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
    /* .create_session  = */ cpu_create_session,
    /* .run_session     = */ cpu_run_session,
    /* .destroy_session = */ cpu_destroy_session,
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

extern "C" RAC_API rac_result_t rac_cpu_runtime_register_provider(
    const rac_cpu_runtime_provider_t* provider) {
    if (provider == nullptr || provider->name == nullptr ||
        provider->create_session == nullptr || provider->run_session == nullptr ||
        provider->destroy_session == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (!primitive_is_supported(provider->primitive)) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    std::lock_guard<std::mutex> lock(provider_mutex());
    auto& entries = providers();
    auto it = std::find_if(entries.begin(), entries.end(), [&](const auto& entry) {
        return entry.name != nullptr && std::strcmp(entry.name, provider->name) == 0;
    });
    try {
        if (it != entries.end()) {
            *it = *provider;
        } else {
            entries.push_back(*provider);
        }
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    return RAC_SUCCESS;
}

extern "C" RAC_API void rac_cpu_runtime_unregister_provider(const char* name) {
    if (name == nullptr) return;
    std::lock_guard<std::mutex> lock(provider_mutex());
    auto& entries = providers();
    entries.erase(std::remove_if(entries.begin(), entries.end(), [&](const auto& entry) {
        return entry.name != nullptr && std::strcmp(entry.name, name) == 0;
    }), entries.end());
}

extern "C" RAC_API rac_result_t rac_cpu_runtime_get_provider_session(
    rac_runtime_session_t* session,
    const char** out_provider_name,
    rac_runtime_session_t** out_provider_session) {
    if (out_provider_session == nullptr) return RAC_ERROR_NULL_POINTER;
    *out_provider_session = nullptr;
    if (out_provider_name) *out_provider_name = nullptr;

    auto* cpu_session = as_cpu_session(session);
    if (cpu_session == nullptr) return RAC_ERROR_INVALID_HANDLE;

    if (out_provider_name) *out_provider_name = cpu_session->provider.name;
    *out_provider_session = cpu_session->provider_session;
    return RAC_SUCCESS;
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
