#include "rac_runtime_onnxrt.h"

#include <onnxruntime_c_api.h>

#if defined(RAC_ONNXRT_EP_COREML_ENABLED)
#include <coreml_provider_factory.h>
#endif

#include <algorithm>
#include <cstring>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#include "core/internal/platform_compat.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_model_format_ids.h"
#include "rac/plugin/rac_onnxrt_runtime_ep.h"
#include "rac/plugin/rac_runtime_registry.h"

namespace runanywhere {
namespace runtime {
namespace onnxrt {
namespace {

/* `SharedOrt` carries no mutex. Initialization of the
 * singleton is already thread-safe via C++11 magic statics (`shared_ort()`
 * below), and `OrtApi::CreateSession` is documented to be callable concurrently
 * from multiple threads against the same `OrtEnv` (each call gets its own
 * `OrtSession*` out-parameter and a locally-constructed `OrtSessionOptions`).
 * Previously we held a global mutex around `CreateSession`, which forced every
 * model load in the process to serialize — e.g. Whisper + embedding warm-up at
 * engine bring-up could not overlap even though the two loads share no state.
 */
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

/* --------------------------------------------------------------------------
 * Execution-provider (EP) state.
 *
 * A single "active EP" is tracked process-wide. The initial skeleton only
 * wires CoreML end-to-end (the vendored ORT build ships `coreml_provider_
 * factory.h` + `OrtSessionOptionsAppendExecutionProvider_CoreML`); CUDA,
 * DirectML, NNAPI, QNN, and WebGPU accept activation only when their
 * corresponding `RAC_ONNXRT_EP_*` compile-time flag is set, otherwise we
 * return `RAC_ERROR_CAPABILITY_UNSUPPORTED` up front.
 *
 * Lock strategy: a plain mutex guards the active-EP snapshot. `Session::
 * create` takes a short copy under the lock, then appends the EP outside.
 * -------------------------------------------------------------------------- */

struct EpState {
    std::mutex mu;
    rac_onnxrt_ep_type_t active = RAC_ONNXRT_EP_CPU;
    std::string config_json;  // Copy of caller's config, if any.

    rac_onnxrt_ep_type_t snapshot(std::string* out_config) {
        std::lock_guard<std::mutex> lock(mu);
        if (out_config)
            *out_config = config_json;
        return active;
    }

    void set(rac_onnxrt_ep_type_t type, const char* config) {
        std::lock_guard<std::mutex> lock(mu);
        active = type;
        config_json = config ? config : std::string();
    }
};

EpState& ep_state() {
    static EpState state;
    return state;
}

bool ep_is_compiled_in(rac_onnxrt_ep_type_t type) {
    switch (type) {
        case RAC_ONNXRT_EP_CPU:
            return true;
#if defined(RAC_ONNXRT_EP_COREML_ENABLED)
        case RAC_ONNXRT_EP_COREML:
            return true;
#endif
#if defined(RAC_ONNXRT_EP_CUDA)
        case RAC_ONNXRT_EP_CUDA:
            return true;
#endif
#if defined(RAC_ONNXRT_EP_DIRECTML)
        case RAC_ONNXRT_EP_DIRECTML:
            return true;
#endif
#if defined(RAC_ONNXRT_EP_NNAPI)
        case RAC_ONNXRT_EP_NNAPI:
            return true;
#endif
#if defined(RAC_ONNXRT_EP_QNN)
        case RAC_ONNXRT_EP_QNN:
            return true;
#endif
#if defined(RAC_ONNXRT_EP_WEBGPU)
        case RAC_ONNXRT_EP_WEBGPU:
            return true;
#endif
        default:
            return false;
    }
}

/* Per-EP metadata: short name, stable device_id, and device class. One row per
 * EP so the name / device_id / class lookups can never drift apart. The string
 * literals have static storage duration, so callers may hold the returned
 * `short_name` / `device_id` pointers across calls (e.g. onnxrt_device_info). */
struct EpInfo {
    rac_onnxrt_ep_type_t type;
    const char* short_name;
    const char* device_id;
    rac_device_class_t device_class;
};

constexpr EpInfo k_ep_info[] = {
    {RAC_ONNXRT_EP_CPU, "cpu", "onnxrt-cpu", RAC_DEVICE_CLASS_CPU},
    {RAC_ONNXRT_EP_COREML, "coreml", "onnxrt-coreml", RAC_DEVICE_CLASS_NPU /* ANE */},
    {RAC_ONNXRT_EP_CUDA, "cuda", "onnxrt-cuda", RAC_DEVICE_CLASS_GPU},
    {RAC_ONNXRT_EP_DIRECTML, "directml", "onnxrt-directml", RAC_DEVICE_CLASS_GPU},
    {RAC_ONNXRT_EP_NNAPI, "nnapi", "onnxrt-nnapi", RAC_DEVICE_CLASS_NPU},
    {RAC_ONNXRT_EP_QNN, "qnn", "onnxrt-qnn", RAC_DEVICE_CLASS_NPU},
    {RAC_ONNXRT_EP_WEBGPU, "webgpu", "onnxrt-webgpu", RAC_DEVICE_CLASS_WEB_GPU},
};

// Look up an EP's row; unknown/out-of-range values fall back to CPU (row 0).
const EpInfo& ep_info(rac_onnxrt_ep_type_t type) {
    for (const auto& e : k_ep_info) {
        if (e.type == type)
            return e;
    }
    return k_ep_info[0];
}

const char* ep_short_name(rac_onnxrt_ep_type_t type) {
    return ep_info(type).short_name;
}

/* Apply the active EP to the supplied session options. Returns RAC_SUCCESS
 * on success or when no non-CPU EP is active. On append failure the caller
 * logs and falls back to CPU-only execution — EPs are advisory. */
rac_result_t apply_active_ep(const OrtApi* api, OrtSessionOptions* session_options) {
    if (!api || !session_options)
        return RAC_ERROR_NULL_POINTER;

    std::string config;
    rac_onnxrt_ep_type_t active = ep_state().snapshot(&config);
    if (active == RAC_ONNXRT_EP_CPU)
        return RAC_SUCCESS;

    (void)config;  // Reserved for MVP — structured EP options parsed per-EP below.
    switch (active) {
#if defined(RAC_ONNXRT_EP_COREML_ENABLED)
        case RAC_ONNXRT_EP_COREML: {
            /* MVP wiring: the default-behavior call. Real config parsing
             * (COREML_FLAG_* + MLComputeUnits) is a follow-up row. Passing
             * 0 asks CoreML EP to use its own defaults (ANE+GPU+CPU). */
            OrtStatus* status = OrtSessionOptionsAppendExecutionProvider_CoreML(session_options,
                                                                                /*coreml_flags=*/0);
            if (status != nullptr) {
                std::string msg = api->GetErrorMessage(status);
                api->ReleaseStatus(status);
                RAC_LOG_WARNING("Runtime.ONNXRT",
                                "CoreML EP append failed: %s — falling back to CPU", msg.c_str());
                return RAC_ERROR_CAPABILITY_UNSUPPORTED;
            }
            return RAC_SUCCESS;
        }
#endif
        /* CUDA / DirectML / NNAPI / QNN / WebGPU are SKELETON stubs for now.
         * Activation is accepted (see `rac_onnxrt_runtime_enable_execution_
         * provider` below which gates on `ep_is_compiled_in`), but the ORT
         * append path isn't wired yet — fall through to CPU and warn. A
         * follow-up gap row per EP will bring real linkage. */
        default:
            RAC_LOG_WARNING("Runtime.ONNXRT", "EP '%s' stub — running on CPU until linkage lands",
                            ep_short_name(active));
            return RAC_SUCCESS;
    }
}

std::string status_message(const OrtApi* api, OrtStatus* status) {
    if (!status || !api)
        return {};
    std::string message = api->GetErrorMessage(status);
    api->ReleaseStatus(status);
    return message;
}

ONNXTensorElementDataType to_ort_type(ElementType type) {
    switch (type) {
        case ElementType::Float32:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
        case ElementType::Uint8:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8;
        case ElementType::Int8:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_INT8;
        case ElementType::Uint16:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16;
        case ElementType::Int16:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_INT16;
        case ElementType::Int32:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32;
        case ElementType::Int64:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64;
        case ElementType::Float16:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16;
        case ElementType::Float64:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE;
        case ElementType::Uint32:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT32;
        case ElementType::Uint64:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT64;
        case ElementType::BFloat16:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_BFLOAT16;
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
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT:
            return ElementType::Float32;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8:
            return ElementType::Uint8;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_INT8:
            return ElementType::Int8;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16:
            return ElementType::Uint16;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_INT16:
            return ElementType::Int16;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32:
            return ElementType::Int32;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64:
            return ElementType::Int64;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16:
            return ElementType::Float16;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE:
            return ElementType::Float64;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT32:
            return ElementType::Uint32;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT64:
            return ElementType::Uint64;
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_BFLOAT16:
            return ElementType::BFloat16;
        default:
            return ElementType::Undefined;
    }
}

size_t element_count(const std::vector<int64_t>& shape) {
    if (shape.empty())
        return 0;
    size_t count = 1;
    for (int64_t dim : shape) {
        count *= static_cast<size_t>(std::max<int64_t>(1, dim));
    }
    return count;
}

/* The device-class manifest is widened at compile time to reflect
 * which Execution Providers are linked into this build. CPU is always present;
 * CoreML / CUDA / DirectML / NNAPI / QNN / WebGPU add NPU, GPU, or WEB_GPU
 * capability. The router uses this array to decide whether onnxrt can be
 * scored for a given device-class request, so it has to be a superset of
 * everything the adapter can route to at runtime. Activation at runtime is
 * what actually selects one.
 *
 * Each device class is gated by a *union* of the EPs that map
 * to it so the entry appears at most once. Earlier per-EP gates could emit
 * duplicate entries (e.g. GPU twice when CoreML + CUDA are both compiled in,
 * NPU twice on CoreML + NNAPI). De-duplicating here keeps the router's
 * scoring stable regardless of which subset of EPs is linked. */
const rac_device_class_t k_supported_devices[] = {
    RAC_DEVICE_CLASS_CPU,
#if defined(RAC_ONNXRT_EP_COREML_ENABLED) || defined(RAC_ONNXRT_EP_NNAPI) || \
    defined(RAC_ONNXRT_EP_QNN)
    RAC_DEVICE_CLASS_NPU,
#endif
#if defined(RAC_ONNXRT_EP_COREML_ENABLED) || defined(RAC_ONNXRT_EP_CUDA) || \
    defined(RAC_ONNXRT_EP_DIRECTML)
    /* CoreML fuses ANE + GPU + CPU; advertising GPU alongside NPU lets the
     * router pick onnxrt for either class. The active EP is still a
     * process-wide single-slot — activation decides what the session actually
     * runs on. */
    RAC_DEVICE_CLASS_GPU,
#endif
#if defined(RAC_ONNXRT_EP_WEBGPU)
    RAC_DEVICE_CLASS_WEB_GPU,
#endif
};
const uint32_t k_supported_formats[] = {
    RAC_MODEL_FORMAT_ID_ONNX,
    RAC_MODEL_FORMAT_ID_ORT,
};
/* ONNXRT is capability-only: it advertises the primitives it can describe for
 * the router, but hosts no session through the C vtable. The onnx engine
 * reaches ONNX Runtime exclusively through the C++ `Session` class below (see
 * engines/onnx/onnx_embedding_provider.cpp). EMBED is the primitive the live
 * `Session` path serves. */
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

namespace {

/* Build an OrtSessionOptions configured per SessionOptions, with the active
 * EP applied. On failure returns nullptr and writes the message into
 * out_error; on success the caller owns the returned options and must
 * ReleaseSessionOptions when done. */
OrtSessionOptions* prepare_session_options(const SharedOrt& ort, const SessionOptions& options,
                                           std::string* out_error) {
    OrtSessionOptions* session_options = nullptr;
    OrtStatus* status = ort.api->CreateSessionOptions(&session_options);
    if (status != nullptr) {
        if (out_error)
            *out_error = status_message(ort.api, status);
        return nullptr;
    }

    status = ort.api->SetIntraOpNumThreads(session_options, options.intra_op_threads);
    if (status != nullptr) {
        if (out_error)
            *out_error = status_message(ort.api, status);
        ort.api->ReleaseSessionOptions(session_options);
        return nullptr;
    }

    if (options.enable_all_optimizations) {
        status = ort.api->SetSessionGraphOptimizationLevel(session_options, ORT_ENABLE_ALL);
        if (status != nullptr) {
            if (out_error)
                *out_error = status_message(ort.api, status);
            ort.api->ReleaseSessionOptions(session_options);
            return nullptr;
        }
    }

    /* Append the currently-active execution provider, if any.
     * `apply_active_ep` is advisory -- CoreML is the only real wiring today;
     * CUDA / DirectML / NNAPI / QNN / WebGPU accept activation but degrade
     * gracefully to CPU-only execution until their linker paths land. */
    (void)apply_active_ep(ort.api, session_options);
    return session_options;
}

}  // namespace

std::unique_ptr<Session> Session::create(const std::string& model_path,
                                         const SessionOptions& options, std::string* out_error) {
    SharedOrt& ort = shared_ort();
    if (!ort.ready()) {
        if (out_error)
            *out_error = ort.init_error;
        return nullptr;
    }

    OrtSessionOptions* session_options = prepare_session_options(ort, options, out_error);
    if (!session_options)
        return nullptr;

    /* `CreateSession` is called without any global lock. ORT's
     * contract is that `CreateSession` may run concurrently from multiple
     * threads against a single `OrtEnv` as long as each call supplies a
     * distinct `OrtSessionOptions` + `OrtSession**`, which is the case here
     * (both are created on the stack of this call). The `shared_ort()` magic
     * static takes care of one-time `OrtEnv` creation. */
    OrtSession* raw_session = nullptr;
#ifdef _WIN32
    std::wstring wpath = rac_to_wstring(model_path);
    OrtStatus* status =
        ort.api->CreateSession(ort.env, wpath.c_str(), session_options, &raw_session);
#else
    OrtStatus* status =
        ort.api->CreateSession(ort.env, model_path.c_str(), session_options, &raw_session);
#endif
    ort.api->ReleaseSessionOptions(session_options);

    if (status != nullptr) {
        if (out_error)
            *out_error = status_message(ort.api, status);
        return nullptr;
    }

    auto impl = std::unique_ptr<Impl>(new (std::nothrow) Impl());
    if (!impl) {
        ort.api->ReleaseSession(raw_session);
        if (out_error)
            *out_error = "out of memory";
        return nullptr;
    }
    impl->api = ort.api;
    impl->session = raw_session;
    (void)options.log_id;
    return std::unique_ptr<Session>(new (std::nothrow) Session(std::move(impl)));
}

std::unique_ptr<Session> Session::create_from_blob(const void* model_data, size_t model_data_bytes,
                                                   const SessionOptions& options,
                                                   std::string* out_error) {
    if (!model_data || model_data_bytes == 0) {
        if (out_error)
            *out_error = "onnxrt: empty model_blob";
        return nullptr;
    }

    SharedOrt& ort = shared_ort();
    if (!ort.ready()) {
        if (out_error)
            *out_error = ort.init_error;
        return nullptr;
    }

    OrtSessionOptions* session_options = prepare_session_options(ort, options, out_error);
    if (!session_options)
        return nullptr;

    OrtSession* raw_session = nullptr;
    OrtStatus* status = ort.api->CreateSessionFromArray(ort.env, model_data, model_data_bytes,
                                                        session_options, &raw_session);
    ort.api->ReleaseSessionOptions(session_options);

    if (status != nullptr) {
        if (out_error)
            *out_error = status_message(ort.api, status);
        return nullptr;
    }

    auto impl = std::unique_ptr<Impl>(new (std::nothrow) Impl());
    if (!impl) {
        ort.api->ReleaseSession(raw_session);
        if (out_error)
            *out_error = "out of memory";
        return nullptr;
    }
    impl->api = ort.api;
    impl->session = raw_session;
    (void)options.log_id;
    return std::unique_ptr<Session>(new (std::nothrow) Session(std::move(impl)));
}

rac_result_t Session::run(const TensorInput* inputs, size_t input_count,
                          const char* const* output_names, size_t output_count,
                          std::vector<TensorOutput>& outputs, std::string* out_error) {
    if (!impl_ || !impl_->api || !impl_->session)
        return RAC_ERROR_BACKEND_NOT_READY;
    if (!inputs || input_count == 0 || !output_names || output_count == 0) {
        return RAC_ERROR_NULL_POINTER;
    }

    const OrtApi* api = impl_->api;
    OrtMemoryInfo* memory_info = nullptr;
    OrtStatus* status =
        api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory_info);
    if (status != nullptr) {
        if (out_error)
            *out_error = status_message(api, status);
        return RAC_ERROR_INFERENCE_FAILED;
    }

    std::vector<OrtValue*> input_values(input_count, nullptr);
    std::vector<const char*> input_names(input_count, nullptr);
    auto cleanup_inputs = [&]() {
        for (OrtValue* value : input_values) {
            if (value)
                api->ReleaseValue(value);
        }
        if (memory_info)
            api->ReleaseMemoryInfo(memory_info);
    };

    for (size_t i = 0; i < input_count; ++i) {
        if (!inputs[i].name || !inputs[i].data || !inputs[i].shape || inputs[i].rank == 0) {
            cleanup_inputs();
            return RAC_ERROR_NULL_POINTER;
        }
        input_names[i] = inputs[i].name;
        status = api->CreateTensorWithDataAsOrtValue(
            memory_info, const_cast<void*>(inputs[i].data), inputs[i].data_bytes, inputs[i].shape,
            inputs[i].rank, to_ort_type(inputs[i].type), &input_values[i]);
        if (status != nullptr) {
            if (out_error)
                *out_error = status_message(api, status);
            cleanup_inputs();
            return RAC_ERROR_INFERENCE_FAILED;
        }
    }

    std::vector<const OrtValue*> const_input_values(input_values.begin(), input_values.end());
    std::vector<OrtValue*> output_values(output_count, nullptr);
    status = api->Run(impl_->session, nullptr, input_names.data(), const_input_values.data(),
                      input_count, output_names, output_count, output_values.data());
    if (status != nullptr) {
        if (out_error)
            *out_error = status_message(api, status);
        for (OrtValue* value : output_values) {
            if (value)
                api->ReleaseValue(value);
        }
        cleanup_inputs();
        return RAC_ERROR_INFERENCE_FAILED;
    }

    /* Every partial-failure path through the per-output marshal
     * loop previously released only the OrtValue at the current index, leaking
     * the remaining N-i-1 ORT-owned outputs (each holds a heap tensor buffer
     * sized to the model's output). Drive all releases through one helper that
     * walks `[i .. output_count)` so a mid-loop bail-out frees every output the
     * `Run` call produced. */
    auto release_outputs_from = [&](size_t start) {
        for (size_t k = start; k < output_values.size(); ++k) {
            if (output_values[k]) {
                api->ReleaseValue(output_values[k]);
                output_values[k] = nullptr;
            }
        }
    };

    outputs.clear();
    outputs.reserve(output_count);
    for (size_t i = 0; i < output_values.size(); ++i) {
        OrtValue* value = output_values[i];
        TensorOutput out;

        /* Consult the actual ORT tensor dtype and element count
         * rather than force-casting to `float*`. We read shape, dtype, and
         * element count via GetTensorTypeAndShapeInfo (the ORT-recommended
         * single-call path) so the copy is `element_size × count` bytes of the
         * tensor's real type. */
        OrtTensorTypeAndShapeInfo* shape_info = nullptr;
        status = api->GetTensorTypeAndShape(value, &shape_info);
        if (status != nullptr || shape_info == nullptr) {
            if (status != nullptr && out_error)
                *out_error = status_message(api, status);
            release_outputs_from(i);
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
            if (out_error)
                *out_error = "onnxrt: unsupported output tensor dtype";
            release_outputs_from(i);
            cleanup_inputs();
            return RAC_ERROR_INFERENCE_FAILED;
        }

        void* data = nullptr;
        status = api->GetTensorMutableData(value, &data);
        if (status != nullptr || data == nullptr) {
            if (status != nullptr && out_error)
                *out_error = status_message(api, status);
            release_outputs_from(i);
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
        output_values[i] = nullptr;
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

namespace {

rac_result_t onnxrt_init(void) {
    const OrtApiBase* base = OrtGetApiBase();
    const OrtApi* api = base ? base->GetApi(ORT_API_VERSION) : nullptr;
    return api != nullptr ? RAC_SUCCESS : RAC_ERROR_CAPABILITY_UNSUPPORTED;
}

void onnxrt_destroy(void) {}

/* Stable per-EP `device_id` strings live in the `EpInfo` table (defined in the
 * onnxrt namespace above); the returned pointers are static-storage literals so
 * callers can hold them across calls rather than rebuilding a heap string. */
const char* active_ep_device_id(rac_onnxrt_ep_type_t type) {
    return runanywhere::runtime::onnxrt::ep_info(type).device_id;
}

rac_result_t onnxrt_device_info(rac_runtime_device_info_t* out) {
    if (!out)
        return RAC_ERROR_NULL_POINTER;
    *out = rac_runtime_device_info_t{};
    /* The active EP determines both the class and the id so the
     * router can pick onnxrt for NPU/GPU-class primitives when an appropriate
     * EP has been activated. Falls back to CPU when no EP is active. */
    rac_onnxrt_ep_type_t active =
        runanywhere::runtime::onnxrt::ep_state().snapshot(/*out_config=*/nullptr);
    out->device_class = rac_onnxrt_runtime_ep_device_class(active);
    out->device_id = active_ep_device_id(active);
    out->display_name = "ONNX Runtime";
    return RAC_SUCCESS;
}

rac_result_t onnxrt_capabilities(rac_runtime_capabilities_t* out) {
    if (!out)
        return RAC_ERROR_NULL_POINTER;
    *out = rac_runtime_capabilities_t{};
    /* ONNXRT is capability-only over the C vtable: it describes the model
     * formats/dtypes ONNX Runtime supports but hosts no session here (no
     * buffer/output ownership through the runtime), so it does NOT set the
     * buffer/owned-output flags or `RAC_RUNTIME_CAP_SESSION_EXECUTION`. FP16 and
     * dynamic shapes reflect what the underlying ORT engine genuinely handles. */
    out->capability_flags = RAC_RUNTIME_CAP_FP16 | RAC_RUNTIME_CAP_DYNAMIC_SHAPES;
    out->supported_formats = k_supported_formats;
    out->supported_formats_count = sizeof(k_supported_formats) / sizeof(k_supported_formats[0]);
    out->supported_primitives = k_supported_primitives;
    out->supported_primitives_count =
        sizeof(k_supported_primitives) / sizeof(k_supported_primitives[0]);
    return RAC_SUCCESS;
}

/* ONNXRT exposes no ABI-v2 session/buffer ops: the v2 run + buffer block is
 * part of the session-execution role, which ONNXRT does not provide over the C
 * vtable (the onnx engine drives ONNX Runtime through the C++ `Session` class).
 * `reserved_slot_0` is therefore left NULL — there is no v2 extension table. */
const rac_runtime_vtable_t k_onnxrt_vtable = {
    /* .metadata = */ {
        /* .abi_version             = */ RAC_RUNTIME_ABI_VERSION,
        /* .id                      = */ RAC_RUNTIME_ONNXRT,
        /* .name                    = */ "onnxrt",
        /* .display_name            = */ "ONNX Runtime",
        /* .version                 = */ nullptr,
        /* .priority                = */ 80,
        /* .supported_formats       = */ k_supported_formats,
        /* .supported_formats_count = */ sizeof(k_supported_formats) /
            sizeof(k_supported_formats[0]),
        /* .supported_devices       = */ k_supported_devices,
        /* .supported_devices_count = */ sizeof(k_supported_devices) /
            sizeof(k_supported_devices[0]),
        /* .reserved_0              = */ 0,
        /* .reserved_1              = */ 0,
    },
    /* .init            = */ onnxrt_init,
    /* .destroy         = */ onnxrt_destroy,
    /* ONNXRT is capability-only: the session-execution slots are NULL. The onnx
     * engine reaches ONNX Runtime through the C++ `Session` class, never the C
     * vtable's session/buffer ops. */
    /* .create_session  = */ nullptr,
    /* .run_session     = */ nullptr,
    /* .destroy_session = */ nullptr,
    /* .alloc_buffer    = */ nullptr,
    /* .free_buffer     = */ nullptr,
    /* .device_info     = */ onnxrt_device_info,
    /* .capabilities    = */ onnxrt_capabilities,
    /* .reserved_slot_0 = */ nullptr,
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

/* Linker-keep-alive anchor, symmetric to
 * `rac_coreml_runtime_require_available` / `rac_metal_runtime_require_available`.
 * Engines that route to onnxrt call this from their plugin entry so a real
 * symbol reference forces the linker to retain THIS translation unit — which
 * also carries the `RAC_STATIC_RUNTIME_REGISTER(onnxrt)` constructor below.
 * Without it the registrar survives only coincidentally (engines/onnx pulls in
 * the C++ `Session::create` symbol, and only under RAC_BACKEND_RAG=ON), so a
 * RAG-off iOS/static build could strip the registrar and leave
 * `rac_runtime_is_registered(RAC_RUNTIME_ONNXRT)` returning 0. */
extern "C" RAC_API rac_result_t rac_onnxrt_runtime_require_available(void) {
    return rac_runtime_get_by_id(RAC_RUNTIME_ONNXRT) != nullptr ? RAC_SUCCESS
                                                                : RAC_ERROR_BACKEND_UNAVAILABLE;
}

extern "C" RAC_API const rac_runtime_vtable_t* rac_runtime_entry_onnxrt(void) {
    return &k_onnxrt_vtable;
}

/* Execution-provider configuration surface. Real linkage is only
 * wired for CoreML today; other EPs accept activation but run on CPU until
 * their follow-up rows bring the ORT append paths online. */
extern "C" RAC_API rac_result_t
rac_onnxrt_runtime_enable_execution_provider(const rac_onnxrt_ep_config_t* config) {
    if (config == nullptr)
        return RAC_ERROR_NULL_POINTER;
    if (!runanywhere::runtime::onnxrt::ep_is_compiled_in(config->type)) {
        return RAC_ERROR_CAPABILITY_UNSUPPORTED;
    }
    runanywhere::runtime::onnxrt::ep_state().set(config->type, config->config_json);
    return RAC_SUCCESS;
}

extern "C" RAC_API rac_result_t rac_onnxrt_runtime_get_active_ep(rac_onnxrt_ep_type_t* out) {
    if (out == nullptr)
        return RAC_ERROR_NULL_POINTER;
    *out = runanywhere::runtime::onnxrt::ep_state().snapshot(nullptr);
    return RAC_SUCCESS;
}

extern "C" RAC_API int rac_onnxrt_runtime_ep_is_available(rac_onnxrt_ep_type_t type) {
    return runanywhere::runtime::onnxrt::ep_is_compiled_in(type) ? 1 : 0;
}

extern "C" RAC_API rac_device_class_t
rac_onnxrt_runtime_ep_device_class(rac_onnxrt_ep_type_t type) {
    return runanywhere::runtime::onnxrt::ep_info(type).device_class;
}

RAC_STATIC_RUNTIME_REGISTER(onnxrt);
