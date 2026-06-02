/**
 * @file rac_runtime_cpu.cpp
 * @brief Built-in CPU runtime plugin.
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
 *   capabilities — dynamic, advertises the union of primitives across all
 *                  currently registered CPU providers. Flags (FP16 + quantised
 *                  paths) are static because every modern CPU backend supports
 *                  them via NEON / AVX / VNNI.
 *   sessions — delegated to registered rac_cpu_runtime_provider_t entries.
 *
 * NOTE: supported primitives are no longer a static, GENERATE_TEXT-
 * only list. `capabilities()` rebuilds a snapshot of primitives from the live
 * provider registry on every call, and `primitive_is_supported` /
 * `rac_cpu_runtime_register_provider` validate against the full primitive-enum
 * range so any engine that speaks a supported format can plug its own CPU
 * provider in (STT, TTS, VAD, EMBED, RERANK, VLM, DIFFUSION) without the
 * runtime rejecting the registration up front.
 */

#include "rac_runtime_entry_cpu.h"

#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <new>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_cpu_runtime_provider.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"
#include "rac/router/rac_hardware_profile.h"
#include "rac/runtime/rac_runtime_helpers.h"
#include "rac/runtime/rac_runtime_provider_registry.h"

namespace {

constexpr uint64_t kCpuSessionMagic = 0x5241434350555345ull; /* "RACCPUSE" */
constexpr uint64_t kCpuBufferMagic = 0x5241434350554255ull;  /* "RACCPUBU" */

/* --------------------------------------------------------------------------
 * Metadata (lives in .rodata; registry does NOT copy).
 * -------------------------------------------------------------------------- */

const rac_device_class_t k_supported_devices[] = {RAC_DEVICE_CLASS_CPU};

/* Supported primitives are no longer a static list — see
 * `capabilities_snapshot` below. The CPU runtime publishes whichever primitives
 * have at least one `rac_cpu_runtime_provider_t` registered at the time
 * `capabilities()` is invoked. This keeps the manifest honest as engines plug
 * in additional providers (STT, TTS, VAD, EMBED, RERANK, VLM, DIFFUSION)
 * without requiring a rebuild of the CPU runtime. */

struct CpuRuntimeSession {
    uint64_t magic = kCpuSessionMagic;
    rac_cpu_runtime_provider_t provider{};
    rac_runtime_session_t* provider_session = nullptr;
};

struct CpuRuntimeBuffer {
    uint64_t magic = kCpuBufferMagic;
    void* data = nullptr;
    size_t bytes = 0;
    rac_runtime_memory_space_t memory_space = RAC_RUNTIME_MEMORY_SPACE_HOST;
    rac_device_class_t device_class = RAC_DEVICE_CLASS_CPU;
    uint32_t device_index = 0;
    uint32_t alignment = 0;
    uint64_t usage_flags = 0;
};

struct FreeDeleter {
    void operator()(void* ptr) const {
        std::free(ptr);
    }
};

/* Provider bookkeeping (mutex + vector + register/unregister/find)
 * lives in `rac::runtime::ProviderRegistry<rac_cpu_runtime_provider_t>`. This
 * TU only has to supply the registry singleton. */
rac::runtime::ProviderRegistry<rac_cpu_runtime_provider_t>& provider_registry() {
    static rac::runtime::ProviderRegistry<rac_cpu_runtime_provider_t> registry;
    return registry;
}

CpuRuntimeSession* as_cpu_session(rac_runtime_session_t* session) {
    auto* cpu_session = reinterpret_cast<CpuRuntimeSession*>(session);
    if (cpu_session == nullptr || cpu_session->magic != kCpuSessionMagic) {
        return nullptr;
    }
    return cpu_session;
}

CpuRuntimeBuffer* as_cpu_buffer(rac_runtime_buffer_t* buffer) {
    auto* cpu_buffer = reinterpret_cast<CpuRuntimeBuffer*>(buffer);
    if (cpu_buffer == nullptr || cpu_buffer->magic != kCpuBufferMagic) {
        return nullptr;
    }
    return cpu_buffer;
}

const CpuRuntimeBuffer* as_cpu_buffer_const(const rac_runtime_buffer_t* buffer) {
    auto* cpu_buffer = reinterpret_cast<const CpuRuntimeBuffer*>(buffer);
    if (cpu_buffer == nullptr || cpu_buffer->magic != kCpuBufferMagic) {
        return nullptr;
    }
    return cpu_buffer;
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
    const HardwareProfile hp = HardwareProfile::cached();
    switch (hp.cpu_vendor) {
        case CpuVendor::Apple:
            return "cpu-apple";
        case CpuVendor::Intel:
            return "cpu-intel";
        case CpuVendor::Amd:
            return "cpu-amd";
        case CpuVendor::Arm:
            return "cpu-arm";
        case CpuVendor::Qualcomm:
            return "cpu-qualcomm";
        case CpuVendor::Other:
            return "cpu-other";
        case CpuVendor::Unknown:
        default:
            return "cpu-generic";
    }
}

rac_result_t cpu_device_info(rac_runtime_device_info_t* out) {
    if (out == nullptr)
        return RAC_ERROR_NULL_POINTER;
    const rac::router::HardwareProfile hp = rac::router::HardwareProfile::cached();
    *out = rac_runtime_device_info_t{};
    out->device_class = RAC_DEVICE_CLASS_CPU;
    out->device_id = cpu_device_id_from_profile();
    out->display_name = "CPU (generic)";
    out->memory_bytes = static_cast<uint64_t>(hp.total_ram_bytes);
    return RAC_SUCCESS;
}

/* Snapshot storage for the dynamic primitive list published by
 * `cpu_capabilities`. Thread-local so concurrent callers from different
 * threads each get a stable snapshot whose lifetime extends until the next
 * `cpu_capabilities` call on the same thread. Fixed-size array sized to the
 * full primitive enum — no allocation on the capability hot path. */
thread_local rac_primitive_t tl_primitive_snapshot[RAC_PRIMITIVE_COUNT];
thread_local size_t tl_primitive_snapshot_count = 0;

rac_result_t cpu_capabilities(rac_runtime_capabilities_t* out) {
    if (out == nullptr)
        return RAC_ERROR_NULL_POINTER;
    *out = rac_runtime_capabilities_t{};

    /* Static, always-on capabilities. The runtime itself (not the providers)
     * implements buffer mapping/copy/alloc, so those flags are unconditional.
     * RAC_RUNTIME_CAP_SESSION_EXECUTION is likewise unconditional: the CPU
     * runtime always fills the create/run/destroy_session slots and serves the
     * OPTIONAL session-execution role by delegating to its provider registry —
     * it is the one runtime that hosts sessions rather than only describing
     * hardware. (Whether any provider is currently registered governs the
     * supported-primitive list below, not this role bit.) */
    uint64_t flags = RAC_RUNTIME_CAP_QUANTIZED_INT8 | RAC_RUNTIME_CAP_QUANTIZED_INT4 |
                     RAC_RUNTIME_CAP_FP16 | RAC_RUNTIME_CAP_DYNAMIC_SHAPES |
                     RAC_RUNTIME_CAP_BUFFER_MAPPING | RAC_RUNTIME_CAP_BUFFER_COPY |
                     RAC_RUNTIME_CAP_DEVICE_ALLOC | RAC_RUNTIME_CAP_SESSION_EXECUTION;
    out->supported_formats = nullptr; /* format-agnostic */
    out->supported_formats_count = 0;

    /* Build a deduplicated snapshot of the primitives currently served by
     * registered providers. Order is stable (primitive enum value ascending)
     * so callers that cache the list see consistent results across calls.
     *
     * While iterating, also detect whether any registered provider implements
     * the optional V2-native `run_session_v2` callback.
     * `RAC_RUNTIME_CAP_OWNED_OUTPUTS` is only advertised when at least one
     * provider can return runtime-owned outputs — the V1-shim fallback flattens
     * tensors and cannot transport ownership back to the caller.
     */
    bool seen[RAC_PRIMITIVE_COUNT] = {false};
    bool any_v2 = false;
    provider_registry().for_each([&](const rac_cpu_runtime_provider_t& provider) {
        const auto p = provider.primitive;
        if (p > RAC_PRIMITIVE_UNSPECIFIED && p < RAC_PRIMITIVE_COUNT) {
            seen[static_cast<size_t>(p)] = true;
        }
        if (provider.run_session_v2 != nullptr) {
            any_v2 = true;
        }
    });
    if (any_v2) {
        flags |= RAC_RUNTIME_CAP_OWNED_OUTPUTS;
    }
    out->capability_flags = flags;

    size_t count = 0;
    for (size_t i = 1; i < RAC_PRIMITIVE_COUNT; ++i) {
        if (seen[i]) {
            tl_primitive_snapshot[count++] = static_cast<rac_primitive_t>(i);
        }
    }
    tl_primitive_snapshot_count = count;
    out->supported_primitives = count > 0 ? tl_primitive_snapshot : nullptr;
    out->supported_primitives_count = count;
    return RAC_SUCCESS;
}

rac_result_t cpu_create_session(const rac_runtime_session_desc_t* desc,
                                rac_runtime_session_t** out) {
    if (out == nullptr || desc == nullptr)
        return RAC_ERROR_NULL_POINTER;
    *out = nullptr;

    if (!rac::runtime::rac_runtime_primitive_in_range(desc->primitive)) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    if ((desc->model_path == nullptr || desc->model_path[0] == '\0') &&
        (desc->model_blob == nullptr || desc->model_blob_bytes == 0)) {
        return RAC_ERROR_INVALID_PATH;
    }

    rac_cpu_runtime_provider_t provider{};
    if (!provider_registry().find_by_desc(desc, &provider)) {
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

rac_result_t cpu_run_session(rac_runtime_session_t* session, const rac_runtime_io_t* inputs,
                             size_t n_in, rac_runtime_io_t* outputs, size_t n_out) {
    auto* cpu_session = as_cpu_session(session);
    if (cpu_session == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    if (n_in > 0 && inputs == nullptr)
        return RAC_ERROR_NULL_POINTER;
    if (n_out > 0 && outputs == nullptr)
        return RAC_ERROR_NULL_POINTER;
    return cpu_session->provider.run_session(cpu_session->provider_session, inputs, n_in, outputs,
                                             n_out);
}

rac_result_t cpu_run_session_v2(rac_runtime_session_t* session, const rac_runtime_tensor_t* inputs,
                                size_t n_in, rac_runtime_tensor_t* outputs, size_t n_out) {
    auto* cpu_session = as_cpu_session(session);
    if (cpu_session == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    if (n_in > 0 && inputs == nullptr)
        return RAC_ERROR_NULL_POINTER;
    if (n_out > 0 && outputs == nullptr)
        return RAC_ERROR_NULL_POINTER;

    /* V2-native fast path: provider handles tensors directly, preserving
     * buffers, ownership flags, capacity fields, memory-space, and dtype.
     * This is the only path through which `RAC_RUNTIME_CAP_OWNED_OUTPUTS` is
     * reachable. */
    if (cpu_session->provider.run_session_v2 != nullptr) {
        /* Validate any caller-supplied CPU buffers up front so the provider
         * only ever sees handles it can safely dereference. Tensors that
         * don't carry a buffer flow through untouched. */
        for (size_t i = 0; i < n_in; ++i) {
            if (inputs[i].buffer != nullptr && as_cpu_buffer_const(inputs[i].buffer) == nullptr) {
                return RAC_ERROR_INVALID_HANDLE;
            }
        }
        for (size_t i = 0; i < n_out; ++i) {
            if (outputs[i].buffer != nullptr && as_cpu_buffer(outputs[i].buffer) == nullptr) {
                return RAC_ERROR_INVALID_HANDLE;
            }
        }
        return cpu_session->provider.run_session_v2(cpu_session->provider_session, inputs, n_in,
                                                    outputs, n_out);
    }

    /* V1-shim fallback: provider only implements the legacy `run_session`.
     * Flatten V2 tensors into `rac_runtime_io_t`, run, then copy shape / dtype
     * / byte count back. Ownership and capacity fields cannot round-trip
     * through this path; V2-only features remain unreachable here. */
    std::vector<rac_runtime_io_t> legacy_inputs(n_in);
    std::vector<rac_runtime_io_t> legacy_outputs(n_out);

    for (size_t i = 0; i < n_in; ++i) {
        const void* data = inputs[i].data;
        size_t data_bytes = inputs[i].data_bytes;
        if (inputs[i].buffer != nullptr) {
            const auto* buffer = as_cpu_buffer_const(inputs[i].buffer);
            if (buffer == nullptr)
                return RAC_ERROR_INVALID_HANDLE;
            data = buffer->data;
            data_bytes = buffer->bytes;
        }
        legacy_inputs[i].name = inputs[i].name;
        legacy_inputs[i].data = const_cast<void*>(data);
        legacy_inputs[i].data_bytes = data_bytes;
        legacy_inputs[i].dtype = static_cast<uint32_t>(inputs[i].dtype);
        legacy_inputs[i].shape = inputs[i].shape;
        legacy_inputs[i].rank = inputs[i].rank;
    }

    for (size_t i = 0; i < n_out; ++i) {
        void* data = outputs[i].data;
        size_t data_bytes = outputs[i].data_capacity_bytes != 0 ? outputs[i].data_capacity_bytes
                                                                : outputs[i].data_bytes;
        if (outputs[i].buffer != nullptr) {
            auto* buffer = as_cpu_buffer(outputs[i].buffer);
            if (buffer == nullptr)
                return RAC_ERROR_INVALID_HANDLE;
            data = buffer->data;
            data_bytes = buffer->bytes;
        }
        legacy_outputs[i].name = outputs[i].name;
        legacy_outputs[i].data = data;
        legacy_outputs[i].data_bytes = data_bytes;
        legacy_outputs[i].dtype = static_cast<uint32_t>(outputs[i].dtype);
        legacy_outputs[i].shape = outputs[i].shape;
        legacy_outputs[i].rank = outputs[i].rank;
    }

    rac_result_t rc = cpu_session->provider.run_session(
        cpu_session->provider_session, legacy_inputs.data(), legacy_inputs.size(),
        legacy_outputs.data(), legacy_outputs.size());
    if (rc != RAC_SUCCESS)
        return rc;

    /* First pass: honor the V2 truncation contract the same way the onnxrt
     * V2-native path does (see runtimes/onnxrt/rac_runtime_onnxrt.cpp). The
     * legacy provider wrote the actual payload size into `data_bytes`; when the
     * caller pre-allocated storage with a smaller `data_capacity_bytes` the
     * write overran it, so publish the required size and report truncation
     * instead of silently returning RAC_SUCCESS with the post-write size. */
    bool truncated = false;
    for (size_t i = 0; i < n_out; ++i) {
        if (outputs[i].data_capacity_bytes > 0 &&
            outputs[i].data_capacity_bytes < legacy_outputs[i].data_bytes) {
            outputs[i].data_bytes = legacy_outputs[i].data_bytes;
            truncated = true;
        }
    }
    if (truncated) {
        return RAC_ERROR_OUTPUT_TRUNCATED;
    }

    for (size_t i = 0; i < n_out; ++i) {
        outputs[i].data_bytes = legacy_outputs[i].data_bytes;
        outputs[i].dtype = static_cast<rac_runtime_dtype_t>(legacy_outputs[i].dtype);
        outputs[i].rank = legacy_outputs[i].rank;
    }
    return RAC_SUCCESS;
}

void cpu_destroy_session(rac_runtime_session_t* session) {
    auto* cpu_session = as_cpu_session(session);
    if (cpu_session == nullptr)
        return;
    cpu_session->magic = 0;
    if (cpu_session->provider.destroy_session != nullptr &&
        cpu_session->provider_session != nullptr) {
        cpu_session->provider.destroy_session(cpu_session->provider_session);
    }
    delete cpu_session;
}

rac_result_t cpu_alloc_buffer_v2(const rac_runtime_buffer_desc_t* desc,
                                 rac_runtime_buffer_t** out) {
    if (desc == nullptr || out == nullptr)
        return RAC_ERROR_NULL_POINTER;
    *out = nullptr;
    if (desc->bytes == 0)
        return RAC_ERROR_INVALID_PARAMETER;

    rac_runtime_memory_space_t space = desc->memory_space;
    if (space == RAC_RUNTIME_MEMORY_SPACE_UNSPECIFIED) {
        space = RAC_RUNTIME_MEMORY_SPACE_HOST;
    }
    if (space != RAC_RUNTIME_MEMORY_SPACE_HOST && space != RAC_RUNTIME_MEMORY_SPACE_SHARED &&
        space != RAC_RUNTIME_MEMORY_SPACE_MANAGED) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    if (desc->device_class != RAC_DEVICE_CLASS_UNSPECIFIED &&
        desc->device_class != RAC_DEVICE_CLASS_CPU) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    const uint32_t default_alignment = static_cast<uint32_t>(alignof(std::max_align_t));
    if (desc->alignment > default_alignment) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    auto buffer = std::unique_ptr<CpuRuntimeBuffer>(new (std::nothrow) CpuRuntimeBuffer());
    if (buffer == nullptr)
        return RAC_ERROR_OUT_OF_MEMORY;

    std::unique_ptr<void, FreeDeleter> data(std::malloc(desc->bytes));
    if (data == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    buffer->data = data.get();
    buffer->bytes = desc->bytes;
    buffer->memory_space = space;
    buffer->device_class = RAC_DEVICE_CLASS_CPU;
    buffer->device_index = desc->device_index;
    buffer->alignment = desc->alignment == 0 ? default_alignment : desc->alignment;
    buffer->usage_flags = desc->usage_flags;
    *out = reinterpret_cast<rac_runtime_buffer_t*>(buffer.release());
    data.release();
    return RAC_SUCCESS;
}

rac_result_t cpu_alloc_buffer(size_t bytes, rac_runtime_buffer_t** out) {
    rac_runtime_buffer_desc_t desc{};
    desc.bytes = bytes;
    desc.memory_space = RAC_RUNTIME_MEMORY_SPACE_HOST;
    desc.device_class = RAC_DEVICE_CLASS_CPU;
    desc.usage_flags = RAC_RUNTIME_BUFFER_USAGE_MAP_READ | RAC_RUNTIME_BUFFER_USAGE_MAP_WRITE;
    return cpu_alloc_buffer_v2(&desc, out);
}

void cpu_free_buffer(rac_runtime_buffer_t* buffer) {
    auto* cpu_buffer = as_cpu_buffer(buffer);
    if (cpu_buffer == nullptr)
        return;
    cpu_buffer->magic = 0;
    std::free(cpu_buffer->data);
    cpu_buffer->data = nullptr;
    delete cpu_buffer;
}

rac_result_t cpu_buffer_info(rac_runtime_buffer_t* buffer, rac_runtime_buffer_info_t* out) {
    if (out == nullptr)
        return RAC_ERROR_NULL_POINTER;
    auto* cpu_buffer = as_cpu_buffer(buffer);
    if (cpu_buffer == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    *out = rac_runtime_buffer_info_t{};
    out->bytes = cpu_buffer->bytes;
    out->memory_space = cpu_buffer->memory_space;
    out->device_class = cpu_buffer->device_class;
    out->device_index = cpu_buffer->device_index;
    out->alignment = cpu_buffer->alignment;
    out->usage_flags = cpu_buffer->usage_flags;
    out->device_id = "cpu-generic";
    out->native_handle = cpu_buffer->data;
    return RAC_SUCCESS;
}

rac_result_t cpu_map_buffer(rac_runtime_buffer_t* buffer, size_t offset, size_t bytes,
                            uint32_t map_flags, rac_runtime_buffer_mapping_t* out) {
    if (out == nullptr)
        return RAC_ERROR_NULL_POINTER;
    auto* cpu_buffer = as_cpu_buffer(buffer);
    if (cpu_buffer == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    if (offset > cpu_buffer->bytes)
        return RAC_ERROR_INVALID_PARAMETER;
    const size_t available = cpu_buffer->bytes - offset;
    const size_t mapped_bytes = bytes == 0 ? available : bytes;
    if (mapped_bytes > available)
        return RAC_ERROR_INVALID_PARAMETER;
    *out = rac_runtime_buffer_mapping_t{};
    out->data = static_cast<unsigned char*>(cpu_buffer->data) + offset;
    out->bytes = mapped_bytes;
    out->memory_space = RAC_RUNTIME_MEMORY_SPACE_HOST;
    out->map_flags = map_flags;
    return RAC_SUCCESS;
}

rac_result_t cpu_unmap_buffer(rac_runtime_buffer_t* buffer, rac_runtime_buffer_mapping_t* mapping) {
    if (mapping == nullptr)
        return RAC_ERROR_NULL_POINTER;
    auto* cpu_buffer = as_cpu_buffer(buffer);
    if (cpu_buffer == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    *mapping = rac_runtime_buffer_mapping_t{};
    return RAC_SUCCESS;
}

rac_result_t cpu_copy_buffer(rac_runtime_buffer_t* dst, size_t dst_offset,
                             const rac_runtime_buffer_t* src, size_t src_offset, size_t bytes) {
    auto* dst_buffer = as_cpu_buffer(dst);
    const auto* src_buffer = as_cpu_buffer_const(src);
    if (dst_buffer == nullptr || src_buffer == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    return rac::runtime::rac_runtime_copy_buffer(dst_buffer->data, dst_buffer->bytes, dst_offset,
                                                 src_buffer->data, src_buffer->bytes, src_offset,
                                                 bytes);
}

void cpu_release_tensor(rac_runtime_tensor_t* tensor) {
    rac::runtime::rac_runtime_release_tensor(tensor, cpu_free_buffer);
}

/* --------------------------------------------------------------------------
 * Vtable singleton. Every op slot is filled explicitly (including the
 * intentionally-NULL session ops) so layout matches the header exactly and
 * a future reserved-slot promotion is a compile-time error.
 * -------------------------------------------------------------------------- */

const rac_runtime_vtable_v2_t k_cpu_vtable_v2 = {
    /* .abi_version    = */ RAC_RUNTIME_ABI_VERSION_V2,
    /* .struct_size    = */ sizeof(rac_runtime_vtable_v2_t),
    /* .run_session_v2 = */ cpu_run_session_v2,
    /* .alloc_buffer   = */ cpu_alloc_buffer_v2,
    /* .buffer_info    = */ cpu_buffer_info,
    /* .map_buffer     = */ cpu_map_buffer,
    /* .unmap_buffer   = */ cpu_unmap_buffer,
    /* .copy_buffer    = */ cpu_copy_buffer,
    /* .release_tensor = */ cpu_release_tensor,
    /* .reserved_0     = */ nullptr,
    /* .reserved_1     = */ nullptr,
    /* .reserved_2     = */ nullptr,
    /* .reserved_3     = */ nullptr,
    /* .reserved_4     = */ nullptr,
    /* .reserved_5     = */ nullptr,
    /* .reserved_6     = */ nullptr,
    /* .reserved_7     = */ nullptr,
};

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
    /* .alloc_buffer    = */ cpu_alloc_buffer,
    /* .free_buffer     = */ cpu_free_buffer,
    /* .device_info     = */ cpu_device_info,
    /* .capabilities    = */ cpu_capabilities,
    /* .reserved_slot_0 = */ &k_cpu_vtable_v2,
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

extern "C" RAC_API rac_result_t
rac_cpu_runtime_register_provider(const rac_cpu_runtime_provider_t* provider) {
    return provider_registry().register_provider(provider);
}

extern "C" RAC_API void rac_cpu_runtime_unregister_provider(const char* name) {
    provider_registry().unregister_provider(name);
}

extern "C" RAC_API rac_result_t
rac_cpu_runtime_get_provider_session(rac_runtime_session_t* session, const char** out_provider_name,
                                     rac_runtime_session_t** out_provider_session) {
    if (out_provider_session == nullptr)
        return RAC_ERROR_NULL_POINTER;
    *out_provider_session = nullptr;
    if (out_provider_name)
        *out_provider_name = nullptr;

    auto* cpu_session = as_cpu_session(session);
    if (cpu_session == nullptr)
        return RAC_ERROR_INVALID_HANDLE;

    if (out_provider_name)
        *out_provider_name = cpu_session->provider.name;
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
