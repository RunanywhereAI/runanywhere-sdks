#include "rac_runtime_metal.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstdlib>
#include <new>

#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"

namespace {

id<MTLDevice> g_device = nil;
id<MTLCommandQueue> g_queue = nil;

struct MetalRuntimeBuffer {
    id<MTLBuffer> metal_buffer = nil;
    void* data = nullptr;
    size_t bytes = 0;
};

const rac_device_class_t k_supported_devices[] = {RAC_DEVICE_CLASS_GPU};
const uint32_t k_supported_formats[] = {
    1,  // MODEL_FORMAT_GGUF
    5,  // MODEL_FORMAT_COREML
    6,  // MODEL_FORMAT_COREML
    8,  // MODEL_FORMAT_MLPACKAGE
};
const rac_primitive_t k_supported_primitives[] = {
    RAC_PRIMITIVE_GENERATE_TEXT,
    RAC_PRIMITIVE_TRANSCRIBE,
    RAC_PRIMITIVE_SYNTHESIZE,
    RAC_PRIMITIVE_VLM,
};

rac_result_t metal_init(void) {
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

rac_result_t metal_device_info(rac_runtime_device_info_t* out) {
    if (!out) return RAC_ERROR_NULL_POINTER;
    if (g_device == nil) return RAC_ERROR_BACKEND_UNAVAILABLE;
    *out = rac_runtime_device_info_t{};
    out->device_class = RAC_DEVICE_CLASS_GPU;
    out->device_id = "apple-metal";
    out->display_name = "Apple Metal";
    out->memory_bytes = [g_device recommendedMaxWorkingSetSize];
    return RAC_SUCCESS;
}

rac_result_t metal_capabilities(rac_runtime_capabilities_t* out) {
    if (!out) return RAC_ERROR_NULL_POINTER;
    *out = rac_runtime_capabilities_t{};
    out->capability_flags = RAC_RUNTIME_CAP_FP16 | RAC_RUNTIME_CAP_ZERO_COPY;
    out->supported_formats = k_supported_formats;
    out->supported_formats_count = sizeof(k_supported_formats) / sizeof(k_supported_formats[0]);
    out->supported_primitives = k_supported_primitives;
    out->supported_primitives_count =
        sizeof(k_supported_primitives) / sizeof(k_supported_primitives[0]);
    return RAC_SUCCESS;
}

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
    /* .reserved_slot_0 = */ nullptr,
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
