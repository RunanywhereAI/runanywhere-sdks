#include "rac_runtime_metal.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstdlib>
#include <cstring>
#include <mutex>
#include <new>

#include "rac/plugin/rac_model_format_ids.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"

namespace {

/* runtimes-003: serialize all access to the g_device / g_queue file-scope
 * globals. The registry calls vtable->init() and vtable->destroy() outside
 * the registry lock (see sdk/runanywhere-commons/src/plugin/
 * rac_runtime_registry.cpp:264), so two concurrent
 * rac_runtime_register/_unregister calls -- or an alloc_buffer arriving
 * during tear-down -- could read/write these without ordering. One mutex
 * is enough to make init/destroy idempotent and to keep the
 * consult-and-use sequence in alloc_buffer / device_info atomic. */
std::mutex &metal_globals_mutex() {
    static std::mutex m;
    return m;
}

id<MTLDevice> g_device = nil;
id<MTLCommandQueue> g_queue = nil;

struct MetalRuntimeBuffer {
    id<MTLBuffer> metal_buffer = nil;
    void* data = nullptr;
    size_t bytes = 0;
};

const rac_device_class_t k_supported_devices[] = {RAC_DEVICE_CLASS_GPU};
const uint32_t k_supported_formats[] = {
    RAC_MODEL_FORMAT_ID_GGUF,
    RAC_MODEL_FORMAT_ID_COREML,
    RAC_MODEL_FORMAT_ID_MLMODEL,
    RAC_MODEL_FORMAT_ID_MLPACKAGE,
};

rac_result_t metal_init(void) {
    std::lock_guard<std::mutex> lock(metal_globals_mutex());
    if (g_device != nil) return RAC_SUCCESS;
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

rac_result_t metal_alloc_buffer(size_t bytes, rac_runtime_buffer_t** out) {
    if (!out) return RAC_ERROR_NULL_POINTER;
    *out = nullptr;
    /* runtimes-003: hold the globals mutex across the device read and the
     * newBufferWithLength: call so destroy() cannot run between the nil
     * check and the buffer allocation. */
    std::lock_guard<std::mutex> lock(metal_globals_mutex());
    if (g_device == nil) return RAC_ERROR_BACKEND_UNAVAILABLE;
    auto* buffer = new (std::nothrow) MetalRuntimeBuffer();
    if (!buffer) return RAC_ERROR_OUT_OF_MEMORY;
    buffer->metal_buffer = [g_device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    if (buffer->metal_buffer == nil) {
        delete buffer;
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    buffer->data = [buffer->metal_buffer contents];
    buffer->bytes = bytes;
    *out = reinterpret_cast<rac_runtime_buffer_t*>(buffer);
    return RAC_SUCCESS;
}

void metal_free_buffer(rac_runtime_buffer_t* buffer) {
    if (!buffer) return;
    auto* typed = reinterpret_cast<MetalRuntimeBuffer*>(buffer);
    if (typed->metal_buffer != nil) {
        [typed->metal_buffer release];
    }
    delete typed;
}

rac_result_t metal_alloc_buffer_v2(const rac_runtime_buffer_desc_t* desc,
                                   rac_runtime_buffer_t** out) {
    if (!desc || !out) return RAC_ERROR_NULL_POINTER;
    if (desc->device_class != RAC_DEVICE_CLASS_UNSPECIFIED &&
        desc->device_class != RAC_DEVICE_CLASS_GPU) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    if (desc->memory_space != RAC_RUNTIME_MEMORY_SPACE_UNSPECIFIED &&
        desc->memory_space != RAC_RUNTIME_MEMORY_SPACE_SHARED &&
        desc->memory_space != RAC_RUNTIME_MEMORY_SPACE_MANAGED) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    /* Reject descriptor fields we cannot currently honor rather than silently
     * dropping them. `newBufferWithLength:` returns at least 16-byte aligned
     * memory on Apple silicon (256-byte on AMD/Intel); we do not currently
     * route a posix_memalign'd pointer through `newBufferWithBytesNoCopy:` to
     * satisfy stricter requests. device_index != 0 has no meaning while we
     * always allocate from the default `MTLCreateSystemDefaultDevice()`. usage
     * flags are advisory in this runtime (the backing MTLBuffer is always
     * StorageModeShared with map-read/map-write), so any flags outside that
     * set would be a silent contract violation. Mirror the shape of
     * cpu_alloc_buffer_v2 at runtimes/cpu/rac_runtime_cpu.cpp:415-417. */
    const uint32_t k_metal_natural_alignment = 16u;
    if (desc->alignment > k_metal_natural_alignment) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    if (desc->device_index != 0) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    const uint64_t k_supported_usage_flags =
        RAC_RUNTIME_BUFFER_USAGE_INPUT |
        RAC_RUNTIME_BUFFER_USAGE_OUTPUT |
        RAC_RUNTIME_BUFFER_USAGE_TEMPORARY |
        RAC_RUNTIME_BUFFER_USAGE_CONSTANT |
        RAC_RUNTIME_BUFFER_USAGE_MAP_READ |
        RAC_RUNTIME_BUFFER_USAGE_MAP_WRITE;
    if (desc->usage_flags & ~k_supported_usage_flags) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return metal_alloc_buffer(desc->bytes, out);
}

rac_result_t metal_buffer_info(rac_runtime_buffer_t* buffer,
                               rac_runtime_buffer_info_t* out) {
    if (!buffer || !out) return RAC_ERROR_NULL_POINTER;
    auto* typed = reinterpret_cast<MetalRuntimeBuffer*>(buffer);
    *out = rac_runtime_buffer_info_t{};
    out->bytes = typed->bytes;
    out->memory_space = RAC_RUNTIME_MEMORY_SPACE_SHARED;
    out->device_class = RAC_DEVICE_CLASS_GPU;
    out->device_id = "apple-metal";
    out->native_handle = reinterpret_cast<void*>(typed->metal_buffer);
    return RAC_SUCCESS;
}

rac_result_t metal_map_buffer(rac_runtime_buffer_t* buffer,
                              size_t offset,
                              size_t bytes,
                              uint32_t map_flags,
                              rac_runtime_buffer_mapping_t* out) {
    if (!buffer || !out) return RAC_ERROR_NULL_POINTER;
    auto* typed = reinterpret_cast<MetalRuntimeBuffer*>(buffer);
    if (offset > typed->bytes) return RAC_ERROR_INVALID_PARAMETER;
    const size_t available = typed->bytes - offset;
    const size_t mapped_bytes = bytes == 0 ? available : bytes;
    if (mapped_bytes > available) return RAC_ERROR_INVALID_PARAMETER;
    *out = rac_runtime_buffer_mapping_t{};
    out->data = static_cast<unsigned char*>(typed->data) + offset;
    out->bytes = mapped_bytes;
    out->memory_space = RAC_RUNTIME_MEMORY_SPACE_SHARED;
    out->map_flags = map_flags;
    return RAC_SUCCESS;
}

rac_result_t metal_unmap_buffer(rac_runtime_buffer_t* buffer,
                                rac_runtime_buffer_mapping_t* mapping) {
    if (!buffer || !mapping) return RAC_ERROR_NULL_POINTER;
    *mapping = rac_runtime_buffer_mapping_t{};
    return RAC_SUCCESS;
}

rac_result_t metal_copy_buffer(rac_runtime_buffer_t* dst,
                               size_t dst_offset,
                               const rac_runtime_buffer_t* src,
                               size_t src_offset,
                               size_t bytes) {
    if (!dst || !src) return RAC_ERROR_NULL_POINTER;
    auto* dst_typed = reinterpret_cast<MetalRuntimeBuffer*>(dst);
    auto* src_typed = reinterpret_cast<const MetalRuntimeBuffer*>(src);
    if (dst_offset > dst_typed->bytes || src_offset > src_typed->bytes) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (bytes > dst_typed->bytes - dst_offset ||
        bytes > src_typed->bytes - src_offset) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    std::memmove(static_cast<unsigned char*>(dst_typed->data) + dst_offset,
                 static_cast<const unsigned char*>(src_typed->data) + src_offset,
                 bytes);
    return RAC_SUCCESS;
}

void metal_release_tensor(rac_runtime_tensor_t* tensor) {
    if (!tensor) return;
    if (tensor->data_ownership == RAC_RUNTIME_OWNERSHIP_RUNTIME && tensor->data) {
        std::free(tensor->data);
    }
    if (tensor->shape_ownership == RAC_RUNTIME_OWNERSHIP_RUNTIME && tensor->shape) {
        std::free(tensor->shape);
    }
    if (tensor->buffer_ownership == RAC_RUNTIME_OWNERSHIP_RUNTIME && tensor->buffer) {
        metal_free_buffer(tensor->buffer);
    }
    *tensor = rac_runtime_tensor_t{};
}

rac_result_t metal_device_info(rac_runtime_device_info_t* out) {
    if (!out) return RAC_ERROR_NULL_POINTER;
    /* runtimes-003: lock across the device read + property query so a
     * concurrent destroy() cannot release g_device between the nil check
     * and the recommendedMaxWorkingSetSize call. */
    std::lock_guard<std::mutex> lock(metal_globals_mutex());
    if (g_device == nil) return RAC_ERROR_BACKEND_UNAVAILABLE;
    *out = rac_runtime_device_info_t{};
    out->device_class = RAC_DEVICE_CLASS_GPU;
    out->device_id = "apple-metal";
    out->display_name = "Apple Metal";
    out->memory_bytes = [g_device recommendedMaxWorkingSetSize];
    return RAC_SUCCESS;
}

// Forward declarations so metal_capabilities can inspect session-op pointers
// before the vtable aggregates are defined below.
extern const rac_runtime_vtable_v2_t k_metal_vtable_v2;
extern const rac_runtime_vtable_t k_metal_vtable;

rac_result_t metal_capabilities(rac_runtime_capabilities_t* out) {
    if (!out) return RAC_ERROR_NULL_POINTER;
    *out = rac_runtime_capabilities_t{};
    /* Buffer-related capabilities are unconditional: the runtime itself
     * implements alloc/map/copy regardless of session-op presence. */
    uint64_t flags =
        RAC_RUNTIME_CAP_FP16           |
        RAC_RUNTIME_CAP_ZERO_COPY      |
        RAC_RUNTIME_CAP_BUFFER_MAPPING |
        RAC_RUNTIME_CAP_BUFFER_COPY    |
        RAC_RUNTIME_CAP_DEVICE_ALLOC;
    /* Only advertise OWNED_OUTPUTS when an execution path can actually return
     * runtime-owned outputs. Today the Metal adapter is buffer-allocator +
     * device probe only (V1 create/run/destroy session and V2 run_session_v2
     * are all nullptr). Mirrors cpu_capabilities's `any_v2` condition at
     * runtimes/cpu/rac_runtime_cpu.cpp:214. */
    const bool has_session_ops =
        k_metal_vtable_v2.run_session_v2 != nullptr ||
        k_metal_vtable.run_session != nullptr;
    if (has_session_ops) {
        flags |= RAC_RUNTIME_CAP_OWNED_OUTPUTS;
    }
    out->capability_flags = flags;
    out->supported_formats = k_supported_formats;
    out->supported_formats_count = sizeof(k_supported_formats) / sizeof(k_supported_formats[0]);
    // Capability shrunk: Metal runtime is buffer-allocator + device probe only; no session ops.
    out->supported_primitives = nullptr;
    out->supported_primitives_count = 0;
    return RAC_SUCCESS;
}

const rac_runtime_vtable_v2_t k_metal_vtable_v2 = {
    /* .abi_version    = */ RAC_RUNTIME_ABI_VERSION_V2,
    /* .struct_size    = */ sizeof(rac_runtime_vtable_v2_t),
    /* .run_session_v2 = */ nullptr,
    /* .alloc_buffer   = */ metal_alloc_buffer_v2,
    /* .buffer_info    = */ metal_buffer_info,
    /* .map_buffer     = */ metal_map_buffer,
    /* .unmap_buffer   = */ metal_unmap_buffer,
    /* .copy_buffer    = */ metal_copy_buffer,
    /* .release_tensor = */ metal_release_tensor,
    /* .reserved_0     = */ nullptr,
    /* .reserved_1     = */ nullptr,
    /* .reserved_2     = */ nullptr,
    /* .reserved_3     = */ nullptr,
    /* .reserved_4     = */ nullptr,
    /* .reserved_5     = */ nullptr,
    /* .reserved_6     = */ nullptr,
    /* .reserved_7     = */ nullptr,
};

const rac_runtime_vtable_t k_metal_vtable = {
    /* .metadata = */ {
        /* .abi_version             = */ RAC_RUNTIME_ABI_VERSION,
        /* .id                      = */ RAC_RUNTIME_METAL,
        /* .name                    = */ "metal",
        /* .display_name            = */ "Apple Metal",
        /* .version                 = */ nullptr,
        /* .priority                = */ 100,
        /* .supported_formats       = */ k_supported_formats,
        /* .supported_formats_count = */ sizeof(k_supported_formats) / sizeof(k_supported_formats[0]),
        /* .supported_devices       = */ k_supported_devices,
        /* .supported_devices_count = */ sizeof(k_supported_devices) / sizeof(k_supported_devices[0]),
        /* .reserved_0              = */ 0,
        /* .reserved_1              = */ 0,
    },
    /* .init            = */ metal_init,
    /* .destroy         = */ metal_destroy,
    /* .create_session  = */ nullptr,
    /* .run_session     = */ nullptr,
    /* .destroy_session = */ nullptr,
    /* .alloc_buffer    = */ metal_alloc_buffer,
    /* .free_buffer     = */ metal_free_buffer,
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
    return rac_runtime_get_by_id(RAC_RUNTIME_METAL) != nullptr
               ? RAC_SUCCESS
               : RAC_ERROR_BACKEND_UNAVAILABLE;
}

extern "C" rac_result_t rac_metal_runtime_alloc_host_buffer(size_t bytes, void** out_data) {
    if (!out_data) return RAC_ERROR_NULL_POINTER;
    *out_data = nullptr;
    *out_data = std::malloc(bytes);
    if (!*out_data) return RAC_ERROR_OUT_OF_MEMORY;
    return RAC_SUCCESS;
}

extern "C" void rac_metal_runtime_free_host_buffer(void* data) {
    std::free(data);
}

extern "C" RAC_API const rac_runtime_vtable_t* rac_runtime_entry_metal(void) {
    return &k_metal_vtable;
}

RAC_STATIC_RUNTIME_REGISTER(metal);
