#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <new>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_cpu_runtime_provider.h"
#include "rac/plugin/rac_model_format_ids.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"

#define CHECK(cond, msg)                                                                          \
    do {                                                                                          \
        if (!(cond)) {                                                                            \
            std::cerr << "FAIL: " << (msg) << " at " << __FILE__ << ":" << __LINE__ << std::endl; \
            return 1;                                                                             \
        }                                                                                         \
    } while (0)

namespace {

struct FakeProviderSession {
    int runs = 0;
};

int g_created = 0;
int g_destroyed = 0;
int g_v2_runs = 0;

rac_result_t fake_create_session(const rac_runtime_session_desc_t* desc,
                                 rac_runtime_session_t** out) {
    if (desc == nullptr || out == nullptr)
        return RAC_ERROR_NULL_POINTER;
    *out = nullptr;
    auto* session = new (std::nothrow) FakeProviderSession();
    if (session == nullptr)
        return RAC_ERROR_OUT_OF_MEMORY;
    ++g_created;
    *out = reinterpret_cast<rac_runtime_session_t*>(session);
    return RAC_SUCCESS;
}

const rac_runtime_io_t* find_io(const rac_runtime_io_t* ios, size_t count, const char* name) {
    for (size_t i = 0; i < count; ++i) {
        if (ios[i].name != nullptr && std::string(ios[i].name) == name) {
            return &ios[i];
        }
    }
    return nullptr;
}

rac_result_t fake_run_session(rac_runtime_session_t* session, const rac_runtime_io_t* inputs,
                              size_t n_in, rac_runtime_io_t* outputs, size_t n_out) {
    if (session == nullptr)
        return RAC_ERROR_NULL_POINTER;
    if (inputs == nullptr || outputs == nullptr)
        return RAC_ERROR_NULL_POINTER;
    auto* fake = reinterpret_cast<FakeProviderSession*>(session);
    const auto* value = find_io(inputs, n_in, "value");
    auto* result = const_cast<rac_runtime_io_t*>(find_io(outputs, n_out, "result"));
    if (value == nullptr || result == nullptr || value->data_bytes < sizeof(int) ||
        result->data_bytes < sizeof(int)) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    ++fake->runs;
    *static_cast<int*>(result->data) = *static_cast<int*>(value->data) * 2;
    return RAC_SUCCESS;
}

void fake_destroy_session(rac_runtime_session_t* session) {
    delete reinterpret_cast<FakeProviderSession*>(session);
    ++g_destroyed;
}

/* V2-native provider: uses the tensor ABI directly and returns a
 * runtime-owned output buffer so we can exercise ownership transfer. */
rac_result_t fake_run_session_v2(rac_runtime_session_t* session, const rac_runtime_tensor_t* inputs,
                                 size_t n_in, rac_runtime_tensor_t* outputs, size_t n_out) {
    if (session == nullptr || inputs == nullptr || outputs == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (n_in != 1 || n_out != 1)
        return RAC_ERROR_INVALID_PARAMETER;
    if (inputs[0].dtype != RAC_RUNTIME_DTYPE_I32 || inputs[0].data == nullptr ||
        inputs[0].data_bytes < sizeof(int32_t) ||
        inputs[0].memory_space != RAC_RUNTIME_MEMORY_SPACE_HOST) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    ++g_v2_runs;
    const int32_t in_val = *static_cast<const int32_t*>(inputs[0].data);
    auto* owned_data = static_cast<int32_t*>(std::malloc(sizeof(int32_t)));
    if (owned_data == nullptr)
        return RAC_ERROR_OUT_OF_MEMORY;
    *owned_data = in_val * 3;
    outputs[0].data = owned_data;
    outputs[0].data_bytes = sizeof(int32_t);
    outputs[0].dtype = RAC_RUNTIME_DTYPE_I32;
    outputs[0].memory_space = RAC_RUNTIME_MEMORY_SPACE_HOST;
    outputs[0].data_ownership = RAC_RUNTIME_OWNERSHIP_RUNTIME;
    return RAC_SUCCESS;
}

}  // namespace

int main() {
    rac_cpu_runtime_unregister_provider("fake_cpu");

    const uint32_t formats[] = {RAC_MODEL_FORMAT_ID_GGUF};
    rac_cpu_runtime_provider_t provider = {};
    provider.name = "fake_cpu";
    provider.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
    provider.formats = formats;
    provider.formats_count = 1;
    provider.create_session = fake_create_session;
    provider.run_session = fake_run_session;
    provider.destroy_session = fake_destroy_session;

    CHECK(rac_cpu_runtime_register_provider(&provider) == RAC_SUCCESS,
          "register fake CPU provider");

    const rac_runtime_vtable_t* cpu = rac_runtime_get_by_id(RAC_RUNTIME_CPU);
    CHECK(cpu != nullptr, "CPU runtime present");
    CHECK(cpu->create_session != nullptr, "CPU create_session populated");
    CHECK(cpu->run_session != nullptr, "CPU run_session populated");
    CHECK(cpu->destroy_session != nullptr, "CPU destroy_session populated");
    CHECK(cpu->alloc_buffer != nullptr, "CPU v1 buffer allocation wrapper populated");
    CHECK(cpu->free_buffer != nullptr, "CPU v1 buffer free wrapper populated");

    const rac_runtime_vtable_v2_t* cpu_v2 = rac_runtime_vtable_get_v2(cpu);
    CHECK(cpu_v2 != nullptr, "CPU runtime exposes ABI v2 extension");
    CHECK(cpu_v2->alloc_buffer != nullptr, "CPU v2 alloc_buffer populated");
    CHECK(cpu_v2->run_session_v2 != nullptr, "CPU v2 run_session_v2 populated");
    CHECK(cpu_v2->buffer_info != nullptr, "CPU v2 buffer_info populated");
    CHECK(cpu_v2->map_buffer != nullptr, "CPU v2 map_buffer populated");
    CHECK(cpu_v2->unmap_buffer != nullptr, "CPU v2 unmap_buffer populated");
    CHECK(cpu_v2->copy_buffer != nullptr, "CPU v2 copy_buffer populated");
    CHECK(cpu_v2->release_tensor != nullptr, "CPU v2 release_tensor populated");

    rac_runtime_buffer_desc_t buffer_desc = {};
    buffer_desc.bytes = 16;
    buffer_desc.memory_space = RAC_RUNTIME_MEMORY_SPACE_HOST;
    buffer_desc.device_class = RAC_DEVICE_CLASS_CPU;
    buffer_desc.usage_flags =
        RAC_RUNTIME_BUFFER_USAGE_MAP_READ | RAC_RUNTIME_BUFFER_USAGE_MAP_WRITE;

    rac_runtime_buffer_t* src_buffer = nullptr;
    rac_runtime_buffer_t* dst_buffer = nullptr;
    CHECK(cpu_v2->alloc_buffer(&buffer_desc, &src_buffer) == RAC_SUCCESS,
          "CPU v2 allocates source buffer");
    CHECK(cpu_v2->alloc_buffer(&buffer_desc, &dst_buffer) == RAC_SUCCESS,
          "CPU v2 allocates destination buffer");

    rac_runtime_buffer_mapping_t mapping = {};
    CHECK(cpu_v2->map_buffer(src_buffer, 0, 0, RAC_RUNTIME_MAP_WRITE, &mapping) == RAC_SUCCESS,
          "CPU v2 maps source buffer");
    CHECK(mapping.data != nullptr, "CPU v2 map returns full buffer");
    CHECK(mapping.bytes == 16, "CPU v2 map returns full buffer");
    const unsigned char pattern[16] = {
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    };
    std::memcpy(mapping.data, pattern, sizeof(pattern));
    CHECK(cpu_v2->unmap_buffer(src_buffer, &mapping) == RAC_SUCCESS, "CPU v2 unmaps source buffer");

    CHECK(cpu_v2->copy_buffer(dst_buffer, 0, src_buffer, 0, sizeof(pattern)) == RAC_SUCCESS,
          "CPU v2 copies between buffers");
    CHECK(cpu_v2->map_buffer(dst_buffer, 0, sizeof(pattern), RAC_RUNTIME_MAP_READ, &mapping) ==
              RAC_SUCCESS,
          "CPU v2 maps copied destination");
    CHECK(std::memcmp(mapping.data, pattern, sizeof(pattern)) == 0, "CPU v2 copied bytes match");
    CHECK(cpu_v2->unmap_buffer(dst_buffer, &mapping) == RAC_SUCCESS,
          "CPU v2 unmaps destination buffer");

    rac_runtime_buffer_info_t buffer_info = {};
    CHECK(cpu_v2->buffer_info(dst_buffer, &buffer_info) == RAC_SUCCESS,
          "CPU v2 returns buffer info");
    CHECK(buffer_info.bytes == 16, "CPU v2 buffer info reports size");
    CHECK(buffer_info.memory_space == RAC_RUNTIME_MEMORY_SPACE_HOST,
          "CPU v2 buffer info reports host memory");

    rac_runtime_buffer_desc_t bad_device_desc = buffer_desc;
    bad_device_desc.device_class = RAC_DEVICE_CLASS_NPU;
    rac_runtime_buffer_t* bad_buffer = nullptr;
    CHECK(cpu_v2->alloc_buffer(&bad_device_desc, &bad_buffer) == RAC_ERROR_NOT_SUPPORTED,
          "CPU v2 rejects non-CPU allocation");
    CHECK(bad_buffer == nullptr, "CPU v2 rejected allocation leaves output null");

    rac_runtime_tensor_t owned_tensor = {};
    owned_tensor.data = std::malloc(sizeof(int));
    owned_tensor.shape = static_cast<int64_t*>(std::malloc(sizeof(int64_t)));
    if (owned_tensor.data == nullptr || owned_tensor.shape == nullptr) {
        std::free(owned_tensor.data);
        std::free(owned_tensor.shape);
        std::cerr << "FAIL: test allocated owned tensor fields at " << __FILE__ << ":" << __LINE__
                  << std::endl;
        return 1;
    }
    owned_tensor.data_ownership = RAC_RUNTIME_OWNERSHIP_RUNTIME;
    owned_tensor.shape_ownership = RAC_RUNTIME_OWNERSHIP_RUNTIME;
    cpu_v2->release_tensor(&owned_tensor);
    CHECK(owned_tensor.data == nullptr, "CPU v2 release_tensor clears runtime-owned fields");
    CHECK(owned_tensor.shape == nullptr, "CPU v2 release_tensor clears runtime-owned fields");
    CHECK(owned_tensor.data_ownership == RAC_RUNTIME_OWNERSHIP_NONE,
          "CPU v2 release_tensor clears runtime-owned fields");
    CHECK(owned_tensor.shape_ownership == RAC_RUNTIME_OWNERSHIP_NONE,
          "CPU v2 release_tensor clears runtime-owned fields");

    cpu->free_buffer(src_buffer);
    cpu->free_buffer(dst_buffer);

    CHECK(cpu->create_session(nullptr, nullptr) == RAC_ERROR_NULL_POINTER,
          "create_session null guard");

    rac_runtime_session_desc_t desc = {};
    desc.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
    desc.model_format = RAC_MODEL_FORMAT_ID_GGUF;
    desc.model_path = "/tmp/fake.gguf";

    rac_runtime_session_t* session = nullptr;
    CHECK(cpu->create_session(&desc, &session) == RAC_SUCCESS, "create CPU provider session");
    CHECK(session != nullptr, "CPU provider session non-null");
    CHECK(g_created == 1, "provider create called");

    const char* provider_name = nullptr;
    rac_runtime_session_t* provider_session = nullptr;
    CHECK(rac_cpu_runtime_get_provider_session(session, &provider_name, &provider_session) ==
              RAC_SUCCESS,
          "unwrap provider session");
    CHECK(provider_name != nullptr, "provider name preserved");
    CHECK(std::string(provider_name) == "fake_cpu", "provider name preserved");
    CHECK(provider_session != nullptr, "provider session preserved");

    int input = 21;
    int output = 0;
    rac_runtime_io_t inputs[1] = {};
    inputs[0].name = "value";
    inputs[0].data = &input;
    inputs[0].data_bytes = sizeof(input);

    rac_runtime_io_t outputs[1] = {};
    outputs[0].name = "result";
    outputs[0].data = &output;
    outputs[0].data_bytes = sizeof(output);

    CHECK(cpu->run_session(session, inputs, 1, outputs, 1) == RAC_SUCCESS,
          "run CPU provider session");
    CHECK(output == 42, "provider run result");

    input = 11;
    output = 0;
    int64_t scalar_shape[1] = {1};
    rac_runtime_tensor_t tensor_inputs[1] = {};
    tensor_inputs[0].name = "value";
    tensor_inputs[0].data = &input;
    tensor_inputs[0].data_bytes = sizeof(input);
    tensor_inputs[0].dtype = RAC_RUNTIME_DTYPE_I32;
    tensor_inputs[0].memory_space = RAC_RUNTIME_MEMORY_SPACE_HOST;
    tensor_inputs[0].shape = scalar_shape;
    tensor_inputs[0].rank = 1;

    rac_runtime_tensor_t tensor_outputs[1] = {};
    tensor_outputs[0].name = "result";
    tensor_outputs[0].data = &output;
    tensor_outputs[0].data_capacity_bytes = sizeof(output);
    tensor_outputs[0].dtype = RAC_RUNTIME_DTYPE_I32;
    tensor_outputs[0].memory_space = RAC_RUNTIME_MEMORY_SPACE_HOST;
    tensor_outputs[0].shape = scalar_shape;
    tensor_outputs[0].rank = 1;
    tensor_outputs[0].shape_capacity = 1;

    CHECK(cpu_v2->run_session_v2(session, tensor_inputs, 1, tensor_outputs, 1) == RAC_SUCCESS,
          "run CPU provider session through v2 tensors");
    CHECK(output == 22, "provider v2 run result");

    cpu->destroy_session(session);
    CHECK(g_destroyed == 1, "provider destroy called");

    /* V1-only provider means CAP_OWNED_OUTPUTS must NOT be advertised because
     * owned outputs cannot round-trip through the shim. */
    rac_runtime_capabilities_t caps_v1 = {};
    CHECK(cpu->capabilities(&caps_v1) == RAC_SUCCESS,
          "capabilities() callback with only V1 provider");
    CHECK((caps_v1.capability_flags & RAC_RUNTIME_CAP_OWNED_OUTPUTS) == 0,
          "CAP_OWNED_OUTPUTS hidden when no provider implements V2");

    rac_cpu_runtime_unregister_provider("fake_cpu");
    session = nullptr;
    CHECK(cpu->create_session(&desc, &session) == RAC_ERROR_NOT_IMPLEMENTED,
          "unregistered provider is not implemented");
    CHECK(session == nullptr, "failed create leaves session null");

    /* V2-native path: register a provider that implements `run_session_v2`
     * and confirm the CPU runtime dispatches through it directly, returning
     * a runtime-owned output tensor that `release_tensor` can free. */
    rac_cpu_runtime_provider_t v2_provider = {};
    v2_provider.name = "fake_cpu_v2";
    v2_provider.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
    v2_provider.formats = formats;
    v2_provider.formats_count = 1;
    v2_provider.create_session = fake_create_session;
    v2_provider.run_session = fake_run_session; /* fallback still present */
    v2_provider.destroy_session = fake_destroy_session;
    v2_provider.run_session_v2 = fake_run_session_v2;
    CHECK(rac_cpu_runtime_register_provider(&v2_provider) == RAC_SUCCESS,
          "register V2-capable fake provider");

    /* Owned-outputs capability must now be advertised. */
    rac_runtime_capabilities_t caps_v2 = {};
    CHECK(cpu->capabilities(&caps_v2) == RAC_SUCCESS, "capabilities() callback with V2 provider");
    CHECK((caps_v2.capability_flags & RAC_RUNTIME_CAP_OWNED_OUTPUTS) != 0,
          "CAP_OWNED_OUTPUTS advertised once a V2 provider registers");

    rac_runtime_session_t* v2_session = nullptr;
    CHECK(cpu->create_session(&desc, &v2_session) == RAC_SUCCESS, "create V2 CPU provider session");
    CHECK(v2_session != nullptr, "V2 provider session non-null");

    const int32_t v2_input = 5;
    int64_t v2_shape[1] = {1};
    rac_runtime_tensor_t v2_inputs[1] = {};
    v2_inputs[0].name = "value";
    v2_inputs[0].data = const_cast<int32_t*>(&v2_input);
    v2_inputs[0].data_bytes = sizeof(int32_t);
    v2_inputs[0].dtype = RAC_RUNTIME_DTYPE_I32;
    v2_inputs[0].memory_space = RAC_RUNTIME_MEMORY_SPACE_HOST;
    v2_inputs[0].shape = v2_shape;
    v2_inputs[0].rank = 1;

    /* Output tensor: no caller-supplied data; provider returns runtime-owned data. */
    rac_runtime_tensor_t v2_outputs[1] = {};
    v2_outputs[0].name = "result";
    v2_outputs[0].dtype = RAC_RUNTIME_DTYPE_I32;
    v2_outputs[0].memory_space = RAC_RUNTIME_MEMORY_SPACE_HOST;

    const int v2_runs_before = g_v2_runs;
    CHECK(cpu_v2->run_session_v2(v2_session, v2_inputs, 1, v2_outputs, 1) == RAC_SUCCESS,
          "run V2 provider through native path");
    CHECK(g_v2_runs == v2_runs_before + 1, "V2 provider callback invoked (not shimmed to V1)");
    CHECK(v2_outputs[0].data != nullptr, "V2 output tensor carries data");
    CHECK(v2_outputs[0].data_bytes == sizeof(int32_t), "V2 output tensor reports bytes");
    CHECK(v2_outputs[0].data_ownership == RAC_RUNTIME_OWNERSHIP_RUNTIME,
          "V2 output preserves runtime ownership through CPU runtime");
    CHECK(*static_cast<const int32_t*>(v2_outputs[0].data) == v2_input * 3,
          "V2 provider produced expected result");

    /* `release_tensor` must free the runtime-owned data. */
    cpu_v2->release_tensor(&v2_outputs[0]);
    CHECK(v2_outputs[0].data == nullptr, "release_tensor frees runtime-owned output");
    CHECK(v2_outputs[0].data_ownership == RAC_RUNTIME_OWNERSHIP_NONE,
          "release_tensor frees runtime-owned output");

    cpu->destroy_session(v2_session);
    rac_cpu_runtime_unregister_provider("fake_cpu_v2");

    std::cout << "runtime_cpu_session_tests passed" << std::endl;
    return 0;
}
