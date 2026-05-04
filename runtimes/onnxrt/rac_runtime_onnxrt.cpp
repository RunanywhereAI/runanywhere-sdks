#include "rac_runtime_onnxrt.h"

#include <onnxruntime_c_api.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <new>

#include "core/internal/platform_compat.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_runtime_registry.h"

namespace runanywhere {
namespace runtime {
namespace onnxrt {
namespace {

struct SharedOrt {
    const OrtApiBase* api_base = nullptr;
    const OrtApi* api = nullptr;
    OrtEnv* env = nullptr;
    std::mutex mutex;
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
    static SharedOrt ort;
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
        case ElementType::Int64:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64;
        case ElementType::Float32:
        default:
            return ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT;
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
    3,  // MODEL_FORMAT_ONNX
    4,  // MODEL_FORMAT_ORT
};
const rac_primitive_t k_supported_primitives[] = {
    RAC_PRIMITIVE_EMBED,
    RAC_PRIMITIVE_DETECT_VOICE,
    RAC_PRIMITIVE_TRANSCRIBE,
    RAC_PRIMITIVE_SYNTHESIZE,
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

    OrtSession* raw_session = nullptr;
    {
        std::lock_guard<std::mutex> lock(ort.mutex);
#ifdef _WIN32
        std::wstring wpath = rac_to_wstring(model_path);
        status = ort.api->CreateSession(ort.env, wpath.c_str(), session_options, &raw_session);
#else
        status = ort.api->CreateSession(ort.env, model_path.c_str(), session_options, &raw_session);
#endif
    }
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
                          std::vector<FloatTensorOutput>& outputs,
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
        FloatTensorOutput out;
        OrtTensorTypeAndShapeInfo* shape_info = nullptr;
        status = api->GetTensorTypeAndShape(value, &shape_info);
        if (status == nullptr && shape_info != nullptr) {
            size_t dims = 0;
            (void)api->GetDimensionsCount(shape_info, &dims);
            out.shape.resize(dims);
            if (dims > 0) {
                (void)api->GetDimensions(shape_info, out.shape.data(), dims);
            }
            api->ReleaseTensorTypeAndShapeInfo(shape_info);
        } else if (status != nullptr) {
            if (out_error) *out_error = status_message(api, status);
            api->ReleaseValue(value);
            cleanup_inputs();
            return RAC_ERROR_INFERENCE_FAILED;
        }

        float* data = nullptr;
        status = api->GetTensorMutableData(value, reinterpret_cast<void**>(&data));
        if (status != nullptr || data == nullptr) {
            if (status != nullptr && out_error) *out_error = status_message(api, status);
            api->ReleaseValue(value);
            cleanup_inputs();
            return RAC_ERROR_INFERENCE_FAILED;
        }
        const size_t count = element_count(out.shape);
        out.data.assign(data, data + count);
        outputs.push_back(std::move(out));
        api->ReleaseValue(value);
    }

    cleanup_inputs();
    return RAC_SUCCESS;
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

    std::vector<runanywhere::runtime::onnxrt::FloatTensorOutput> runtime_outputs;
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
    for (size_t i = 0; i < output_count && i < runtime_outputs.size(); ++i) {
        const size_t bytes = runtime_outputs[i].data.size() * sizeof(float);
        if (outputs[i].data && outputs[i].data_bytes >= bytes) {
            std::memcpy(outputs[i].data, runtime_outputs[i].data.data(), bytes);
            outputs[i].data_bytes = bytes;
        }
    }
    return RAC_SUCCESS;
}

void onnxrt_destroy_session(rac_runtime_session_t* session) {
    delete session;
}

rac_result_t onnxrt_alloc_buffer(size_t bytes, rac_runtime_buffer_t** out) {
    if (!out) return RAC_ERROR_NULL_POINTER;
    *out = nullptr;
    auto* buffer = new (std::nothrow) rac_runtime_buffer();
    if (!buffer) return RAC_ERROR_OUT_OF_MEMORY;
    buffer->data = std::malloc(bytes);
    if (!buffer->data) {
        delete buffer;
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    buffer->bytes = bytes;
    *out = buffer;
    return RAC_SUCCESS;
}

void onnxrt_free_buffer(rac_runtime_buffer_t* buffer) {
    if (!buffer) return;
    std::free(buffer->data);
    delete buffer;
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
    out->capability_flags = RAC_RUNTIME_CAP_FP16 | RAC_RUNTIME_CAP_DYNAMIC_SHAPES;
    out->supported_formats = k_supported_formats;
    out->supported_formats_count = sizeof(k_supported_formats) / sizeof(k_supported_formats[0]);
    out->supported_primitives = k_supported_primitives;
    out->supported_primitives_count =
        sizeof(k_supported_primitives) / sizeof(k_supported_primitives[0]);
    return RAC_SUCCESS;
}

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
    /* .alloc_buffer    = */ onnxrt_alloc_buffer,
    /* .free_buffer     = */ onnxrt_free_buffer,
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

extern "C" RAC_API const rac_runtime_vtable_t* rac_runtime_entry_onnxrt(void) {
    return &k_onnxrt_vtable;
}

RAC_STATIC_RUNTIME_REGISTER(onnxrt);
