#include "rac_runtime_onnxrt.h"

#include <onnxruntime_c_api.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <new>
#include <vector>

#include "core/internal/platform_compat.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_model_format_ids.h"
#include "rac/plugin/rac_onnxrt_runtime_provider.h"
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
/* RT-ONNX-05: the onnxrt adapter ships with a generic ORT tensor runner —
 * `onnxrt_run_session` dispatches `OrtSession::Run` without primitive-aware
 * pre/post processing. The always-on wired consumer is the onnx embedding
 * provider (engines/onnx, manifest at rac_plugin_entry_onnx.cpp). Engines
 * that want primitive-aware handling (feature extraction, token decoding,
 * etc.) can register providers via `rac_onnxrt_runtime_register_provider`
 * (RT-ONNX-06) — `onnxrt_capabilities` then rebuilds the primitive list
 * dynamically from the static seed below plus the live provider set,
 * mirroring `cpu_capabilities`. */
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

/* RT-ONNX-06: session handle now supports two shapes. Sessions created by the
 * built-in generic tensor runner own a `runanywhere::runtime::onnxrt::Session`
 * directly. Sessions created via a registered provider carry a provider-owned
 * session handle plus a copy of the provider vtable so dispatch / destroy can
 * round-trip without re-consulting the provider registry. Exactly one of the
 * two shapes is populated per session. */
struct rac_runtime_session {
    std::unique_ptr<runanywhere::runtime::onnxrt::Session> session;

    /* Provider path — NULL when this session was created by the generic path. */
    rac_onnxrt_runtime_provider_t provider{};
    rac_runtime_session_t* provider_session = nullptr;
    bool is_provider_session = false;
};

struct rac_runtime_buffer {
    void* data = nullptr;
    size_t bytes = 0;
};

namespace {

/* --------------------------------------------------------------------------
 * Provider registry (RT-ONNX-06). Mirrors the CPU provider surface so engines
 * can plug in per-primitive handlers (embedding, STT, TTS, VAD) rather than
 * rediscovering the onnxrt singleton. Keyed by provider `name`; lookup matches
 * on `(primitive, model_format)`.
 * -------------------------------------------------------------------------- */

std::mutex& onnxrt_provider_mutex() {
    static std::mutex mutex;
    return mutex;
}

std::vector<rac_onnxrt_runtime_provider_t>& onnxrt_providers() {
    static std::vector<rac_onnxrt_runtime_provider_t> entries;
    return entries;
}

bool onnxrt_primitive_is_in_range(rac_primitive_t primitive) {
    return primitive > RAC_PRIMITIVE_UNSPECIFIED &&
           primitive <  RAC_PRIMITIVE_COUNT;
}

bool onnxrt_provider_supports_format(const rac_onnxrt_runtime_provider_t& provider,
                                     uint32_t model_format) {
    if (provider.formats == nullptr || provider.formats_count == 0 || model_format == 0) {
        return true;
    }
    for (size_t i = 0; i < provider.formats_count; ++i) {
        if (provider.formats[i] == model_format) return true;
    }
    return false;
}

bool onnxrt_find_provider(const rac_runtime_session_desc_t* desc,
                          rac_onnxrt_runtime_provider_t* out_provider) {
    std::lock_guard<std::mutex> lock(onnxrt_provider_mutex());
    for (const auto& provider : onnxrt_providers()) {
        if (provider.primitive == desc->primitive &&
            onnxrt_provider_supports_format(provider, desc->model_format)) {
            *out_provider = provider;
            return true;
        }
    }
    return false;
}

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

    /* RT-ONNX-06: if a provider is registered for this primitive + format,
     * delegate session construction to it. Providers own their native session
     * state (e.g. tokenizer + ORT session pair for embeddings) and return a
     * handle we wrap in a provider-flavored `rac_runtime_session`. Generic
     * "bare tensor runner" callers fall through to the default path below. */
    rac_onnxrt_runtime_provider_t provider{};
    if (onnxrt_find_provider(desc, &provider) && provider.create_session != nullptr) {
        rac_runtime_session_t* provider_session = nullptr;
        rac_result_t rc = provider.create_session(desc, &provider_session);
        if (rc != RAC_SUCCESS) return rc;
        if (provider_session == nullptr) return RAC_ERROR_INVALID_HANDLE;

        auto* handle = new (std::nothrow) rac_runtime_session();
        if (!handle) {
            if (provider.destroy_session != nullptr) {
                provider.destroy_session(provider_session);
            }
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        handle->provider = provider;
        handle->provider_session = provider_session;
        handle->is_provider_session = true;
        *out = handle;
        return RAC_SUCCESS;
    }

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

    /* RT-ONNX-06: route through the registered provider when this session was
     * created by one. Generic-path sessions fall through to the inline tensor
     * runner below. */
    if (session->is_provider_session) {
        if (session->provider.run_session == nullptr) return RAC_ERROR_NOT_IMPLEMENTED;
        return session->provider.run_session(
            session->provider_session, inputs, input_count, outputs, output_count);
    }

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
    if (!session) return;
    /* RT-ONNX-06: forward destroy to the provider for provider-owned sessions.
     * Generic-path sessions carry a `Session` unique_ptr that cleans up via
     * the defaulted struct destructor. */
    if (session->is_provider_session) {
        if (session->provider.destroy_session != nullptr &&
            session->provider_session != nullptr) {
            session->provider.destroy_session(session->provider_session);
        }
    }
    delete session;
}

void onnxrt_free_buffer(rac_runtime_buffer_t* buffer) {
    if (!buffer) return;
    std::free(buffer->data);
    delete buffer;
}

/* RT-ONNX-01: V2-native `run_session_v2` path. Shares the same `Session::run`
 * tensor execution as V1 but honors V2 buffer-ownership + capacity semantics
 * on the output side:
 *   - Inputs borrow from the caller. If a `buffer` handle is supplied the
 *     runtime reads through it; otherwise `data` + `data_bytes` are used
 *     directly. Dtype mapping reuses `to_ort_type` via `ElementType`.
 *   - Outputs: if the caller pre-allocated `data` with a non-zero
 *     `data_capacity_bytes`, the output is copied in-place and ownership is
 *     left at `NONE`. If the capacity is smaller than the actual tensor bytes,
 *     every affected output's `data_bytes` is set to the required size and
 *     `RAC_ERROR_OUTPUT_TRUNCATED` is returned (no partial copies). If the
 *     caller did not supply a buffer (`data == NULL` and `data_capacity_bytes
 *     == 0`), the runtime allocates a new data block via `malloc` and marks
 *     `data_ownership = RAC_RUNTIME_OWNERSHIP_RUNTIME` so the caller can free
 *     it through `release_tensor`. Shape is handled the same way, using
 *     `shape_capacity` for caller-supplied storage. Dtype + rank are written
 *     back unconditionally. */
rac_result_t onnxrt_run_session_v2(rac_runtime_session_t* session,
                                   const rac_runtime_tensor_t* inputs,
                                   size_t n_in,
                                   rac_runtime_tensor_t* outputs,
                                   size_t n_out) {
    if (!session) return RAC_ERROR_INVALID_HANDLE;
    if (n_in > 0 && !inputs) return RAC_ERROR_NULL_POINTER;
    if (n_out > 0 && !outputs) return RAC_ERROR_NULL_POINTER;

    /* RT-ONNX-06: provider-owned sessions forward V2 directly when the
     * provider implements `run_session_v2`; otherwise return NOT_IMPLEMENTED
     * so callers can fall back to legacy `run_session`. V2 cannot shim
     * through V1 for provider sessions because the generic-path marshalling
     * below only knows how to drive `Session::run` of the built-in
     * `runanywhere::runtime::onnxrt::Session`. */
    if (session->is_provider_session) {
        if (session->provider.run_session_v2 == nullptr) {
            return RAC_ERROR_NOT_IMPLEMENTED;
        }
        return session->provider.run_session_v2(
            session->provider_session, inputs, n_in, outputs, n_out);
    }

    using runanywhere::runtime::onnxrt::ElementType;
    using runanywhere::runtime::onnxrt::TensorInput;
    using runanywhere::runtime::onnxrt::TensorOutput;

    /* Marshal V2 inputs into the internal `TensorInput` used by `Session::run`.
     * If a caller supplies a runtime buffer, resolve its host pointer + byte
     * count; otherwise use the raw `data`/`data_bytes` fields. */
    std::vector<TensorInput> runtime_inputs;
    std::vector<const char*> output_names;
    runtime_inputs.reserve(n_in);
    output_names.reserve(n_out);

    for (size_t i = 0; i < n_in; ++i) {
        const void* data = inputs[i].data;
        size_t data_bytes = inputs[i].data_bytes;
        if (inputs[i].buffer != nullptr) {
            data = inputs[i].buffer->data;
            data_bytes = inputs[i].buffer->bytes;
        }
        if (!inputs[i].name || !data || !inputs[i].shape || inputs[i].rank == 0) {
            return RAC_ERROR_NULL_POINTER;
        }
        runtime_inputs.push_back({
            inputs[i].name,
            data,
            data_bytes,
            inputs[i].shape,
            inputs[i].rank,
            static_cast<ElementType>(inputs[i].dtype),
        });
    }

    for (size_t i = 0; i < n_out; ++i) {
        if (!outputs[i].name) return RAC_ERROR_NULL_POINTER;
        output_names.push_back(outputs[i].name);
    }

    std::vector<TensorOutput> runtime_outputs;
    std::string error;
    rac_result_t rc = session->session->run(runtime_inputs.data(),
                                            runtime_inputs.size(),
                                            output_names.data(),
                                            output_names.size(),
                                            runtime_outputs,
                                            &error);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_ERROR("Runtime.ONNXRT", "run_session_v2 failed: %s", error.c_str());
        return rc;
    }

    /* First pass: detect capacity shortfalls without copying so the caller can
     * cleanly reallocate and retry. Mirrors the V1 semantics in
     * `onnxrt_run_session` — we publish the required byte count on each
     * truncated output and also flag shape-capacity shortfalls. */
    bool truncated = false;
    for (size_t i = 0; i < n_out && i < runtime_outputs.size(); ++i) {
        const size_t required_bytes = runtime_outputs[i].bytes.size();
        const size_t required_rank = runtime_outputs[i].shape.size();
        /* Data capacity check — only applies when the caller supplied storage. */
        if (outputs[i].data != nullptr && outputs[i].data_capacity_bytes > 0 &&
            outputs[i].data_capacity_bytes < required_bytes) {
            outputs[i].data_bytes = required_bytes;
            truncated = true;
        }
        /* Shape capacity check — only applies when the caller supplied storage. */
        if (outputs[i].shape != nullptr && outputs[i].shape_capacity > 0 &&
            outputs[i].shape_capacity < required_rank) {
            outputs[i].rank = required_rank;
            truncated = true;
        }
    }
    if (truncated) {
        return RAC_ERROR_OUTPUT_TRUNCATED;
    }

    /* Second pass: commit outputs. If the caller supplied backing storage,
     * copy in place and keep `*_ownership == NONE`. Otherwise allocate
     * runtime-owned storage and mark ownership as RUNTIME so the caller can
     * release through `onnxrt_release_tensor`. */
    for (size_t i = 0; i < n_out && i < runtime_outputs.size(); ++i) {
        const auto& src = runtime_outputs[i];
        const size_t bytes = src.bytes.size();
        const size_t rank = src.shape.size();

        /* Data. */
        if (outputs[i].data != nullptr && outputs[i].data_capacity_bytes > 0) {
            /* Caller-supplied storage; copy in place. */
            if (bytes > 0) {
                std::memcpy(outputs[i].data, src.bytes.data(), bytes);
            }
            outputs[i].data_bytes = bytes;
            /* Leave data_ownership untouched — caller owns their own buffer. */
        } else if (bytes > 0) {
            /* No caller storage → allocate runtime-owned data. */
            void* owned = std::malloc(bytes);
            if (!owned) return RAC_ERROR_OUT_OF_MEMORY;
            std::memcpy(owned, src.bytes.data(), bytes);
            outputs[i].data = owned;
            outputs[i].data_bytes = bytes;
            outputs[i].data_ownership = RAC_RUNTIME_OWNERSHIP_RUNTIME;
        } else {
            outputs[i].data = nullptr;
            outputs[i].data_bytes = 0;
        }

        /* Shape. */
        if (outputs[i].shape != nullptr && outputs[i].shape_capacity > 0) {
            if (rank > 0) {
                std::memcpy(outputs[i].shape, src.shape.data(), rank * sizeof(int64_t));
            }
            outputs[i].rank = rank;
        } else if (rank > 0) {
            auto* owned_shape = static_cast<int64_t*>(std::malloc(rank * sizeof(int64_t)));
            if (!owned_shape) {
                /* Roll back data allocation on this output if we just made one
                 * so the caller doesn't leak on the error path. */
                if (outputs[i].data_ownership == RAC_RUNTIME_OWNERSHIP_RUNTIME &&
                    outputs[i].data != nullptr) {
                    std::free(outputs[i].data);
                    outputs[i].data = nullptr;
                    outputs[i].data_bytes = 0;
                    outputs[i].data_ownership = RAC_RUNTIME_OWNERSHIP_NONE;
                }
                return RAC_ERROR_OUT_OF_MEMORY;
            }
            std::memcpy(owned_shape, src.shape.data(), rank * sizeof(int64_t));
            outputs[i].shape = owned_shape;
            outputs[i].rank = rank;
            outputs[i].shape_ownership = RAC_RUNTIME_OWNERSHIP_RUNTIME;
        } else {
            outputs[i].rank = 0;
        }

        /* Dtype + memory space are always reported from the runtime. */
        outputs[i].dtype = static_cast<rac_runtime_dtype_t>(src.dtype);
        outputs[i].memory_space = RAC_RUNTIME_MEMORY_SPACE_HOST;
    }
    return RAC_SUCCESS;
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

/* Snapshot storage for the dynamic primitive list published by
 * `onnxrt_capabilities`. Thread-local so concurrent callers from different
 * threads each get a stable snapshot whose lifetime extends until the next
 * `onnxrt_capabilities` call on the same thread. Fixed-size array sized to
 * the full primitive enum — no allocation on the capability hot path. */
thread_local rac_primitive_t tl_onnxrt_primitive_snapshot[RAC_PRIMITIVE_COUNT];
thread_local size_t          tl_onnxrt_primitive_snapshot_count = 0;

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

    /* RT-ONNX-06: rebuild the primitive list from the static "generic tensor
     * runner" surface (`k_supported_primitives`, currently just EMBED) plus
     * whichever primitives have at least one registered provider. Order is
     * stable (primitive enum value ascending) so callers that cache the list
     * see consistent results across calls. Mirrors `cpu_capabilities`. */
    bool seen[RAC_PRIMITIVE_COUNT] = {false};
    for (rac_primitive_t p : k_supported_primitives) {
        if (onnxrt_primitive_is_in_range(p)) {
            seen[static_cast<size_t>(p)] = true;
        }
    }
    {
        std::lock_guard<std::mutex> lock(onnxrt_provider_mutex());
        for (const auto& provider : onnxrt_providers()) {
            if (onnxrt_primitive_is_in_range(provider.primitive)) {
                seen[static_cast<size_t>(provider.primitive)] = true;
            }
        }
    }

    size_t count = 0;
    for (size_t i = 1; i < RAC_PRIMITIVE_COUNT; ++i) {
        if (seen[i]) {
            tl_onnxrt_primitive_snapshot[count++] = static_cast<rac_primitive_t>(i);
        }
    }
    tl_onnxrt_primitive_snapshot_count = count;
    out->supported_primitives =
        count > 0 ? tl_onnxrt_primitive_snapshot : nullptr;
    out->supported_primitives_count = count;
    return RAC_SUCCESS;
}

const rac_runtime_vtable_v2_t k_onnxrt_vtable_v2 = {
    /* .abi_version    = */ RAC_RUNTIME_ABI_VERSION_V2,
    /* .struct_size    = */ sizeof(rac_runtime_vtable_v2_t),
    /* .run_session_v2 = */ onnxrt_run_session_v2,
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

/* RT-ONNX-06: provider registration surface, symmetric to CPU's
 * `rac_cpu_runtime_register_provider`. Providers are stored by value and
 * looked up by name for replacement / unregistration. Dispatch happens
 * transparently inside `onnxrt_create_session` so existing consumers of the
 * generic tensor runner keep working unchanged. */
extern "C" RAC_API rac_result_t rac_onnxrt_runtime_register_provider(
    const rac_onnxrt_runtime_provider_t* provider) {
    if (provider == nullptr || provider->name == nullptr ||
        provider->create_session == nullptr || provider->run_session == nullptr ||
        provider->destroy_session == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (!onnxrt_primitive_is_in_range(provider->primitive)) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    std::lock_guard<std::mutex> lock(onnxrt_provider_mutex());
    auto& entries = onnxrt_providers();
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

extern "C" RAC_API void rac_onnxrt_runtime_unregister_provider(const char* name) {
    if (name == nullptr) return;
    std::lock_guard<std::mutex> lock(onnxrt_provider_mutex());
    auto& entries = onnxrt_providers();
    entries.erase(std::remove_if(entries.begin(), entries.end(), [&](const auto& entry) {
        return entry.name != nullptr && std::strcmp(entry.name, name) == 0;
    }), entries.end());
}

extern "C" RAC_API rac_result_t rac_onnxrt_runtime_get_provider_session(
    rac_runtime_session_t* session,
    const char** out_provider_name,
    rac_runtime_session_t** out_provider_session) {
    if (out_provider_session == nullptr) return RAC_ERROR_NULL_POINTER;
    *out_provider_session = nullptr;
    if (out_provider_name) *out_provider_name = nullptr;

    if (session == nullptr) return RAC_ERROR_INVALID_HANDLE;

    if (session->is_provider_session) {
        if (out_provider_name) *out_provider_name = session->provider.name;
        *out_provider_session = session->provider_session;
        return RAC_SUCCESS;
    }

    /* Generic-path session — no provider is involved. Return the same session
     * handle as the "provider session" so callers can treat the path
     * uniformly, with NULL provider_name as the signal. */
    *out_provider_session = session;
    return RAC_SUCCESS;
}

RAC_STATIC_RUNTIME_REGISTER(onnxrt);
