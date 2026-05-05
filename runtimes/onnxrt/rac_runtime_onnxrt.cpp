#include "rac_runtime_onnxrt.h"

#include <onnxruntime_c_api.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <new>

#include "core/internal/platform_compat.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_model_format_ids.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/runtime/rac_runtime_helpers.h"

namespace runanywhere {
namespace runtime {
namespace onnxrt {
namespace {

/* RT-ONNX-07: `SharedOrt` no longer carries a mutex. Initialization of the
 * singleton is already thread-safe via C++11 magic statics (`shared_ort()`
 * below), and `OrtApi::CreateSession` is documented to be callable concurrently
 * from multiple threads against the same `OrtEnv` (each call gets its own
 * `OrtSession*` out-parameter and a locally-constructed `OrtSessionOptions`).
 * Previously we held a global mutex around `CreateSession`, which forced every
 * model load in the process to serialize — e.g. Whisper + embedding warm-up at
 * engine bring-up could not overlap even though the two loads share no state. */
struct SharedOrt {
    const OrtApiBase* api_base = nullptr;
    const OrtApi* api = nullptr;
    OrtEnv* env = nullptr;
    std::string init_error;

    SharedOrt() {
        api_base = OrtGetApiBase();
        api = api_base ? api_base->GetApi(ORT_API_VERSION) : nullptr;
        if (!api) {
            init_error = "failed to resolve ONNX Runtime C API";
            return;
        }
        OrtStatus* status = api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "RunAnywhereONNXRT", &env);
        if (status != nullptr) {
            init_error = api->GetErrorMessage(status);
            api->ReleaseStatus(status);
        }
    }

    ~SharedOrt() {
        if (env && api) {
            api->ReleaseEnv(env);
        }
    }

    bool ready() const { return api != nullptr && env != nullptr; }
};

SharedOrt& shared_ort() {
    static SharedOrt ort;  // Thread-safe one-time init (C++11 magic static).
    return ort;
}

std::string status_message(const OrtApi* api, OrtStatus* status) {
    if (!status || !api) return {};
    std::string message = api->GetErrorMessage(status);
    api->ReleaseStatus(status);
    return message;
}

ONNXTensorElementDataType to_ort_type(ElementType type) {
    switch (type) {
        case ElementType::Float32:  return ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
        case ElementType::Uint8:    return ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8;
        case ElementType::Int8:     return ONNX_TENSOR_ELEMENT_DATA_TYPE_INT8;
        case ElementType::Uint16:   return ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16;
        case ElementType::Int16:    return ONNX_TENSOR_ELEMENT_DATA_TYPE_INT16;
        case ElementType::Int32:    return ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32;
        case ElementType::Int64:    return ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64;
        case ElementType::Float16:  return ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16;
        case ElementType::Float64:  return ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE;
        case ElementType::Uint32:   return ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT32;
        case ElementType::Uint64:   return ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT64;
        case ElementType::BFloat16: return ONNX_TENSOR_ELEMENT_DATA_TYPE_BFLOAT16;
        case ElementType::Undefined:
        default:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
    }
}

/** Map ORT tensor element type back to our public `ElementType` enum.
 *  Returns `Undefined` for types we cannot currently marshal (strings,
 *  complex, packed 4-bit, FP8 variants) so the caller can fail-fast instead
 *  of silently copying garbage. */
ElementType from_ort_type(ONNXTensorElementDataType type) {
    switch (type) {
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT:    return ElementType::Float32;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8:    return ElementType::Uint8;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_INT8:     return ElementType::Int8;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16:   return ElementType::Uint16;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_INT16:    return ElementType::Int16;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32:    return ElementType::Int32;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64:    return ElementType::Int64;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16:  return ElementType::Float16;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE:   return ElementType::Float64;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT32:   return ElementType::Uint32;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT64:   return ElementType::Uint64;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_BFLOAT16: return ElementType::BFloat16;
        default:
            return ElementType::Undefined;
    }
}

size_t element_count(const std::vector<int64_t>& shape) {
    if (shape.empty()) return 0;
    size_t count = 1;
    for (int64_t dim : shape) {
        count *= static_cast<size_t>(std::max<int64_t>(1, dim));
    }
    return count;
}

const rac_device_class_t k_supported_devices[] = {RAC_DEVICE_CLASS_CPU};
const uint32_t k_supported_formats[] = {
    RAC_MODEL_FORMAT_ID_ONNX,
    RAC_MODEL_FORMAT_ID_ORT,
};
/* RT-ONNX-05: the onnxrt adapter is a generic ORT tensor runner —
 * `onnxrt_run_session` dispatches `OrtSession::Run` without primitive-aware
 * pre/post processing. The only wired consumer today is the onnx embedding
 * provider (engines/onnx, manifest at rac_plugin_entry_onnx.cpp). STT / TTS /
 * VAD primitives advertised here previously were aspirational: a router that
 * picked onnxrt for TRANSCRIBE would still need engine-side feature extraction
 * and token decoding, which this adapter does not provide.
 *
 * RT-ONNX-06 will introduce an `rac_onnxrt_runtime_register_provider` surface
 * parallel to CPU's; once that lands, this list should be rebuilt dynamically
 * from the registered providers (mirroring `cpu_capabilities`). Until then,
 * advertise only the primitive actually serviced end-to-end. */
const rac_primitive_t k_supported_primitives[] = {
    RAC_PRIMITIVE_EMBED,
};

}  // namespace

struct Session::Impl {
    const OrtApi* api = nullptr;
    OrtSession* session = nullptr;

    ~Impl() {
        if (session && api) {
            api->ReleaseSession(session);
        }
    }
};

Session::Session(std::unique_ptr<Impl> impl) : impl_(std::move(impl)) {}
Session::~Session() = default;

std::unique_ptr<Session> Session::create(const std::string& model_path,
                                         const SessionOptions& options,
                                         std::string* out_error) {
    SharedOrt& ort = shared_ort();
    if (!ort.ready()) {
        if (out_error) *out_error = ort.init_error;
        return nullptr;
    }

    OrtSessionOptions* session_options = nullptr;
    OrtStatus* status = ort.api->CreateSessionOptions(&session_options);
    if (status != nullptr) {
        if (out_error) *out_error = status_message(ort.api, status);
        return nullptr;
    }

    auto release_options = [&]() {
        if (session_options) {
            ort.api->ReleaseSessionOptions(session_options);
            session_options = nullptr;
        }
    };

    status = ort.api->SetIntraOpNumThreads(session_options, options.intra_op_threads);
    if (status != nullptr) {
        if (out_error) *out_error = status_message(ort.api, status);
        release_options();
        return nullptr;
    }

    if (options.enable_all_optimizations) {
        status = ort.api->SetSessionGraphOptimizationLevel(session_options, ORT_ENABLE_ALL);
        if (status != nullptr) {
            if (out_error) *out_error = status_message(ort.api, status);
            release_options();
            return nullptr;
        }
    }

    /* RT-ONNX-07: `CreateSession` is called without any global lock. ORT's
     * contract is that `CreateSession` may run concurrently from multiple
     * threads against a single `OrtEnv` as long as each call supplies a
     * distinct `OrtSessionOptions` + `OrtSession**`, which is the case here
     * (both are created on the stack of this call). The `shared_ort()` magic
     * static takes care of one-time `OrtEnv` creation. */
    OrtSession* raw_session = nullptr;
#ifdef _WIN32
    std::wstring wpath = rac_to_wstring(model_path);
    status = ort.api->CreateSession(ort.env, wpath.c_str(), session_options, &raw_session);
#else
    status = ort.api->CreateSession(ort.env, model_path.c_str(), session_options, &raw_session);
#endif
    release_options();

    if (status != nullptr) {
        if (out_error) *out_error = status_message(ort.api, status);
        return nullptr;
    }

    auto impl = std::unique_ptr<Impl>(new (std::nothrow) Impl());
    if (!impl) {
        ort.api->ReleaseSession(raw_session);
        if (out_error) *out_error = "out of memory";
        return nullptr;
    }
    impl->api = ort.api;
    impl->session = raw_session;
    (void)options.log_id;
    return std::unique_ptr<Session>(new (std::nothrow) Session(std::move(impl)));
}

rac_result_t Session::run(const TensorInput* inputs,
                          size_t input_count,
                          const char* const* output_names,
                          size_t output_count,
                          std::vector<TensorOutput>& outputs,
                          std::string* out_error) {
    if (!impl_ || !impl_->api || !impl_->session) return RAC_ERROR_BACKEND_NOT_READY;
    if (!inputs || input_count == 0 || !output_names || output_count == 0) {
        return RAC_ERROR_NULL_POINTER;
    }

    const OrtApi* api = impl_->api;
    OrtMemoryInfo* memory_info = nullptr;
    OrtStatus* status = api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory_info);
    if (status != nullptr) {
        if (out_error) *out_error = status_message(api, status);
        return RAC_ERROR_INFERENCE_FAILED;
    }

    std::vector<OrtValue*> input_values(input_count, nullptr);
    std::vector<const char*> input_names(input_count, nullptr);
    auto cleanup_inputs = [&]() {
        for (OrtValue* value : input_values) {
            if (value) api->ReleaseValue(value);
        }
        if (memory_info) api->ReleaseMemoryInfo(memory_info);
    };

    for (size_t i = 0; i < input_count; ++i) {
        if (!inputs[i].name || !inputs[i].data || !inputs[i].shape || inputs[i].rank == 0) {
            cleanup_inputs();
            return RAC_ERROR_NULL_POINTER;
        }
        input_names[i] = inputs[i].name;
        status = api->CreateTensorWithDataAsOrtValue(
            memory_info,
            const_cast<void*>(inputs[i].data),
            inputs[i].data_bytes,
            inputs[i].shape,
            inputs[i].rank,
            to_ort_type(inputs[i].type),
            &input_values[i]);
        if (status != nullptr) {
            if (out_error) *out_error = status_message(api, status);
            cleanup_inputs();
            return RAC_ERROR_INFERENCE_FAILED;
        }
    }

    std::vector<const OrtValue*> const_input_values(input_values.begin(), input_values.end());
    std::vector<OrtValue*> output_values(output_count, nullptr);
    status = api->Run(impl_->session,
                      nullptr,
                      input_names.data(),
                      const_input_values.data(),
                      input_count,
                      output_names,
                      output_count,
                      output_values.data());
    if (status != nullptr) {
        if (out_error) *out_error = status_message(api, status);
        for (OrtValue* value : output_values) {
            if (value) api->ReleaseValue(value);
        }
        cleanup_inputs();
        return RAC_ERROR_INFERENCE_FAILED;
    }

    outputs.clear();
    outputs.reserve(output_count);
    for (OrtValue* value : output_values) {
        TensorOutput out;

        /* RT-ONNX-02: consult the actual ORT tensor dtype and element count
         * rather than force-casting to `float*`. We read shape, dtype, and
         * element count via GetTensorTypeAndShapeInfo (the ORT-recommended
         * single-call path) so the copy is `element_size × count` bytes of the
         * tensor's real type. */
        OrtTensorTypeAndShapeInfo* shape_info = nullptr;
        status = api->GetTensorTypeAndShape(value, &shape_info);
        if (status != nullptr || shape_info == nullptr) {
            if (status != nullptr && out_error) *out_error = status_message(api, status);
            api->ReleaseValue(value);
            cleanup_inputs();
            return RAC_ERROR_INFERENCE_FAILED;
        }

        size_t dims = 0;
        (void)api->GetDimensionsCount(shape_info, &dims);
        out.shape.resize(dims);
        if (dims > 0) {
            (void)api->GetDimensions(shape_info, out.shape.data(), dims);
        }

        ONNXTensorElementDataType onnx_type = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED;
        (void)api->GetTensorElementType(shape_info, &onnx_type);
        out.dtype = from_ort_type(onnx_type);

        size_t element_count_actual = 0;
        (void)api->GetTensorShapeElementCount(shape_info, &element_count_actual);

        api->ReleaseTensorTypeAndShapeInfo(shape_info);

        const size_t elem_size = element_size_bytes(out.dtype);
        if (elem_size == 0) {
            if (out_error) *out_error = "onnxrt: unsupported output tensor dtype";
            api->ReleaseValue(value);
            cleanup_inputs();
            return RAC_ERROR_INFERENCE_FAILED;
        }

        void* data = nullptr;
        status = api->GetTensorMutableData(value, &data);
        if (status != nullptr || data == nullptr) {
            if (status != nullptr && out_error) *out_error = status_message(api, status);
            api->ReleaseValue(value);
            cleanup_inputs();
            return RAC_ERROR_INFERENCE_FAILED;
        }

        const size_t byte_count = element_count_actual * elem_size;
        out.bytes.resize(byte_count);
        if (byte_count > 0) {
            std::memcpy(out.bytes.data(), data, byte_count);
        }
        outputs.push_back(std::move(out));
        api->ReleaseValue(value);
    }

    cleanup_inputs();
    return RAC_SUCCESS;
}

size_t element_size_bytes(ElementType type) {
    switch (type) {
        case ElementType::Uint8:
        case ElementType::Int8:
            return 1;
        case ElementType::Uint16:
        case ElementType::Int16:
        case ElementType::Float16:
        case ElementType::BFloat16:
            return 2;
        case ElementType::Float32:
        case ElementType::Int32:
        case ElementType::Uint32:
            return 4;
        case ElementType::Int64:
        case ElementType::Uint64:
        case ElementType::Float64:
            return 8;
        case ElementType::Undefined:
        default:
            return 0;
    }
}

const char* runtime_version() {
    SharedOrt& ort = shared_ort();
    return ort.api_base ? ort.api_base->GetVersionString() : "unknown";
}

}  // namespace onnxrt
}  // namespace runtime
}  // namespace runanywhere

using runanywhere::runtime::onnxrt::k_supported_devices;
using runanywhere::runtime::onnxrt::k_supported_formats;
using runanywhere::runtime::onnxrt::k_supported_primitives;

struct rac_runtime_session {
    std::unique_ptr<runanywhere::runtime::onnxrt::Session> session;
};

struct rac_runtime_buffer {
    void* data = nullptr;
    size_t bytes = 0;
};

namespace {

rac_result_t onnxrt_init(void) {
    const OrtApiBase* base = OrtGetApiBase();
    const OrtApi* api = base ? base->GetApi(ORT_API_VERSION) : nullptr;
    return api != nullptr
               ? RAC_SUCCESS
               : RAC_ERROR_CAPABILITY_UNSUPPORTED;
}

void onnxrt_destroy(void) {}

rac_result_t onnxrt_create_session(const rac_runtime_session_desc_t* desc,
                                   rac_runtime_session_t** out) {
    if (!desc || !out) return RAC_ERROR_NULL_POINTER;
    if (!desc->model_path) return RAC_ERROR_INVALID_PARAMETER;
    *out = nullptr;
    std::string error;
    runanywhere::runtime::onnxrt::SessionOptions options{};
    auto session = runanywhere::runtime::onnxrt::Session::create(desc->model_path, options, &error);
    if (!session) {
        RAC_LOG_ERROR("Runtime.ONNXRT", "create_session failed: %s", error.c_str());
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }
    auto* handle = new (std::nothrow) rac_runtime_session();
    if (!handle) return RAC_ERROR_OUT_OF_MEMORY;
    handle->session = std::move(session);
    *out = handle;
    return RAC_SUCCESS;
}

rac_result_t onnxrt_run_session(rac_runtime_session_t* session,
                                const rac_runtime_io_t* inputs,
                                size_t input_count,
                                rac_runtime_io_t* outputs,
                                size_t output_count) {
    if (!session || !inputs || !outputs) return RAC_ERROR_NULL_POINTER;
    std::vector<runanywhere::runtime::onnxrt::TensorInput> runtime_inputs;
    std::vector<const char*> output_names;
    runtime_inputs.reserve(input_count);
    output_names.reserve(output_count);
    for (size_t i = 0; i < input_count; ++i) {
        runtime_inputs.push_back({
            inputs[i].name,
            inputs[i].data,
            inputs[i].data_bytes,
            inputs[i].shape,
            inputs[i].rank,
            static_cast<runanywhere::runtime::onnxrt::ElementType>(inputs[i].dtype),
        });
    }
    for (size_t i = 0; i < output_count; ++i) {
        if (!outputs[i].name) return RAC_ERROR_NULL_POINTER;
        output_names.push_back(outputs[i].name);
    }

    std::vector<runanywhere::runtime::onnxrt::TensorOutput> runtime_outputs;
    std::string error;
    rac_result_t rc = session->session->run(runtime_inputs.data(),
                                            runtime_inputs.size(),
                                            output_names.data(),
                                            output_names.size(),
                                            runtime_outputs,
                                            &error);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_ERROR("Runtime.ONNXRT", "run_session failed: %s", error.c_str());
        return rc;
    }
    /* First pass: detect any capacity shortfall and publish the required byte
     * count on every affected output so the caller can reallocate and retry.
     * We report truncation without copying any partial data, so the caller can
     * cleanly distinguish "legitimate zero-byte output" from "buffer too small,
     * output dropped" (RT-ONNX-03). RT-ONNX-02: `bytes` is now the real
     * element-size × count payload from the tensor's actual dtype, not a
     * `sizeof(float)` multiple. */
    bool truncated = false;
    for (size_t i = 0; i < output_count && i < runtime_outputs.size(); ++i) {
        const size_t required = runtime_outputs[i].bytes.size();
        if (outputs[i].data != nullptr && outputs[i].data_bytes < required) {
            outputs[i].data_bytes = required;
            truncated = true;
        }
    }
    if (truncated) {
        return RAC_ERROR_OUTPUT_TRUNCATED;
    }
    /* Second pass: all outputs fit — commit the copies and record actual sizes
     * plus the observed dtype so the caller can interpret the bytes correctly. */
    for (size_t i = 0; i < output_count && i < runtime_outputs.size(); ++i) {
        const size_t bytes = runtime_outputs[i].bytes.size();
        if (outputs[i].data != nullptr) {
            if (bytes > 0) {
                std::memcpy(outputs[i].data, runtime_outputs[i].bytes.data(), bytes);
            }
            outputs[i].data_bytes = bytes;
        }
        outputs[i].dtype = static_cast<uint32_t>(runtime_outputs[i].dtype);
    }
    return RAC_SUCCESS;
}

void onnxrt_destroy_session(rac_runtime_session_t* session) {
    delete session;
}

void onnxrt_free_buffer(rac_runtime_buffer_t* buffer) {
    if (!buffer) return;
    std::free(buffer->data);
    delete buffer;
}

rac_result_t onnxrt_alloc_buffer_v2(const rac_runtime_buffer_desc_t* desc,
                                    rac_runtime_buffer_t** out) {
    if (!desc || !out) return RAC_ERROR_NULL_POINTER;
    *out = nullptr;
    if (desc->device_class != RAC_DEVICE_CLASS_UNSPECIFIED &&
        desc->device_class != RAC_DEVICE_CLASS_CPU) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    if (desc->memory_space != RAC_RUNTIME_MEMORY_SPACE_UNSPECIFIED &&
        desc->memory_space != RAC_RUNTIME_MEMORY_SPACE_HOST) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    if (desc->alignment > static_cast<uint32_t>(alignof(std::max_align_t))) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    auto* buffer = new (std::nothrow) rac_runtime_buffer();
    if (!buffer) return RAC_ERROR_OUT_OF_MEMORY;
    buffer->data = std::malloc(desc->bytes);
    if (!buffer->data) {
        delete buffer;
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    buffer->bytes = desc->bytes;
    *out = buffer;
    return RAC_SUCCESS;
}

rac_result_t onnxrt_buffer_info(rac_runtime_buffer_t* buffer,
                                rac_runtime_buffer_info_t* out) {
    if (!buffer || !out) return RAC_ERROR_NULL_POINTER;
    *out = rac_runtime_buffer_info_t{};
    out->bytes = buffer->bytes;
    out->memory_space = RAC_RUNTIME_MEMORY_SPACE_HOST;
    out->device_class = RAC_DEVICE_CLASS_CPU;
    out->alignment = static_cast<uint32_t>(alignof(std::max_align_t));
    out->device_id = "onnxrt-cpu";
    out->native_handle = buffer->data;
    return RAC_SUCCESS;
}

rac_result_t onnxrt_map_buffer(rac_runtime_buffer_t* buffer,
                               size_t offset,
                               size_t bytes,
                               uint32_t map_flags,
                               rac_runtime_buffer_mapping_t* out) {
    if (!buffer || !out) return RAC_ERROR_NULL_POINTER;
    if (offset > buffer->bytes) return RAC_ERROR_INVALID_PARAMETER;
    const size_t available = buffer->bytes - offset;
    const size_t mapped_bytes = bytes == 0 ? available : bytes;
    if (mapped_bytes > available) return RAC_ERROR_INVALID_PARAMETER;
    *out = rac_runtime_buffer_mapping_t{};
    out->data = static_cast<unsigned char*>(buffer->data) + offset;
    out->bytes = mapped_bytes;
    out->memory_space = RAC_RUNTIME_MEMORY_SPACE_HOST;
    out->map_flags = map_flags;
    return RAC_SUCCESS;
}

rac_result_t onnxrt_unmap_buffer(rac_runtime_buffer_t* buffer,
                                 rac_runtime_buffer_mapping_t* mapping) {
    if (!buffer || !mapping) return RAC_ERROR_NULL_POINTER;
    *mapping = rac_runtime_buffer_mapping_t{};
    return RAC_SUCCESS;
}

rac_result_t onnxrt_copy_buffer(rac_runtime_buffer_t* dst,
                                size_t dst_offset,
                                const rac_runtime_buffer_t* src,
                                size_t src_offset,
                                size_t bytes) {
    if (!dst || !src) return RAC_ERROR_NULL_POINTER;
    return rac::runtime::rac_runtime_copy_buffer(dst->data, dst->bytes, dst_offset,
                                                 src->data, src->bytes, src_offset,
                                                 bytes);
}

void onnxrt_release_tensor(rac_runtime_tensor_t* tensor) {
    rac::runtime::rac_runtime_release_tensor(tensor, onnxrt_free_buffer);
}

rac_result_t onnxrt_device_info(rac_runtime_device_info_t* out) {
    if (!out) return RAC_ERROR_NULL_POINTER;
    *out = rac_runtime_device_info_t{};
    out->device_class = RAC_DEVICE_CLASS_CPU;
    out->device_id = "onnxrt-cpu";
    out->display_name = "ONNX Runtime";
    return RAC_SUCCESS;
}

rac_result_t onnxrt_capabilities(rac_runtime_capabilities_t* out) {
    if (!out) return RAC_ERROR_NULL_POINTER;
    *out = rac_runtime_capabilities_t{};
    out->capability_flags =
        RAC_RUNTIME_CAP_FP16           |
        RAC_RUNTIME_CAP_DYNAMIC_SHAPES |
        RAC_RUNTIME_CAP_BUFFER_MAPPING |
        RAC_RUNTIME_CAP_BUFFER_COPY    |
        RAC_RUNTIME_CAP_DEVICE_ALLOC   |
        RAC_RUNTIME_CAP_OWNED_OUTPUTS;
    out->supported_formats = k_supported_formats;
    out->supported_formats_count = sizeof(k_supported_formats) / sizeof(k_supported_formats[0]);
    out->supported_primitives = k_supported_primitives;
    out->supported_primitives_count =
        sizeof(k_supported_primitives) / sizeof(k_supported_primitives[0]);
    return RAC_SUCCESS;
}

const rac_runtime_vtable_v2_t k_onnxrt_vtable_v2 = {
    /* .abi_version    = */ RAC_RUNTIME_ABI_VERSION_V2,
    /* .struct_size    = */ sizeof(rac_runtime_vtable_v2_t),
    /* .run_session_v2 = */ nullptr,
    /* .alloc_buffer   = */ onnxrt_alloc_buffer_v2,
    /* .buffer_info    = */ onnxrt_buffer_info,
    /* .map_buffer     = */ onnxrt_map_buffer,
    /* .unmap_buffer   = */ onnxrt_unmap_buffer,
    /* .copy_buffer    = */ onnxrt_copy_buffer,
    /* .release_tensor = */ onnxrt_release_tensor,
    /* .reserved_0     = */ nullptr,
    /* .reserved_1     = */ nullptr,
    /* .reserved_2     = */ nullptr,
    /* .reserved_3     = */ nullptr,
    /* .reserved_4     = */ nullptr,
    /* .reserved_5     = */ nullptr,
    /* .reserved_6     = */ nullptr,
    /* .reserved_7     = */ nullptr,
};

const rac_runtime_vtable_t k_onnxrt_vtable = {
    /* .metadata = */ {
        /* .abi_version             = */ RAC_RUNTIME_ABI_VERSION,
        /* .id                      = */ RAC_RUNTIME_ONNXRT,
        /* .name                    = */ "onnxrt",
        /* .display_name            = */ "ONNX Runtime",
        /* .version                 = */ nullptr,
        /* .priority                = */ 80,
        /* .supported_formats       = */ k_supported_formats,
        /* .supported_formats_count = */ sizeof(k_supported_formats) / sizeof(k_supported_formats[0]),
        /* .supported_devices       = */ k_supported_devices,
        /* .supported_devices_count = */ sizeof(k_supported_devices) / sizeof(k_supported_devices[0]),
        /* .reserved_0              = */ 0,
        /* .reserved_1              = */ 0,
    },
    /* .init            = */ onnxrt_init,
    /* .destroy         = */ onnxrt_destroy,
    /* .create_session  = */ onnxrt_create_session,
    /* .run_session     = */ onnxrt_run_session,
    /* .destroy_session = */ onnxrt_destroy_session,
    /* .alloc_buffer    = */ nullptr,
    /* .free_buffer     = */ nullptr,
    /* .device_info     = */ onnxrt_device_info,
    /* .capabilities    = */ onnxrt_capabilities,
    /* .reserved_slot_0 = */ &k_onnxrt_vtable_v2,
    /* .reserved_slot_1 = */ nullptr,
    /* .reserved_slot_2 = */ nullptr,
    /* .reserved_slot_3 = */ nullptr,
    /* .reserved_slot_4 = */ nullptr,
    /* .reserved_slot_5 = */ nullptr,
};

}  // namespace

namespace runanywhere {
namespace runtime {
namespace onnxrt {

const rac_runtime_vtable_t* runtime_vtable() {
    return &k_onnxrt_vtable;
}

}  // namespace onnxrt
}  // namespace runtime
}  // namespace runanywhere

extern "C" RAC_API const rac_runtime_vtable_t* rac_runtime_entry_onnxrt(void) {
    return &k_onnxrt_vtable;
}

RAC_STATIC_RUNTIME_REGISTER(onnxrt);
