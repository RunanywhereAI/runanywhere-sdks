#include <cstdint>
#include <iostream>
#include <new>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_cpu_runtime_provider.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        if (!(cond)) {                                                          \
            std::cerr << "FAIL: " << msg << " at " << __FILE__ << ":"          \
                      << __LINE__ << std::endl;                                 \
            return 1;                                                           \
        }                                                                       \
    } while (0)

namespace {

struct FakeProviderSession {
    int runs = 0;
};

int g_created = 0;
int g_destroyed = 0;

rac_result_t fake_create_session(const rac_runtime_session_desc_t* desc,
                                 rac_runtime_session_t** out) {
    if (desc == nullptr || out == nullptr) return RAC_ERROR_NULL_POINTER;
    *out = nullptr;
    auto* session = new (std::nothrow) FakeProviderSession();
    if (session == nullptr) return RAC_ERROR_OUT_OF_MEMORY;
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

rac_result_t fake_run_session(rac_runtime_session_t* session,
                              const rac_runtime_io_t* inputs, size_t n_in,
                              rac_runtime_io_t* outputs, size_t n_out) {
    if (session == nullptr) return RAC_ERROR_NULL_POINTER;
    if (inputs == nullptr || outputs == nullptr) return RAC_ERROR_NULL_POINTER;
    auto* fake = reinterpret_cast<FakeProviderSession*>(session);
    const auto* value = find_io(inputs, n_in, "value");
    auto* result = const_cast<rac_runtime_io_t*>(find_io(outputs, n_out, "result"));
    if (value == nullptr || result == nullptr ||
        value->data_bytes < sizeof(int) || result->data_bytes < sizeof(int)) {
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

}  // namespace

int main() {
    rac_cpu_runtime_unregister_provider("fake_cpu");

    const uint32_t formats[] = {1};
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

    CHECK(cpu->create_session(nullptr, nullptr) == RAC_ERROR_NULL_POINTER,
          "create_session null guard");

    rac_runtime_session_desc_t desc = {};
    desc.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
    desc.model_format = 1;
    desc.model_path = "/tmp/fake.gguf";

    rac_runtime_session_t* session = nullptr;
    CHECK(cpu->create_session(&desc, &session) == RAC_SUCCESS,
          "create CPU provider session");
    CHECK(session != nullptr, "CPU provider session non-null");
    CHECK(g_created == 1, "provider create called");

    const char* provider_name = nullptr;
    rac_runtime_session_t* provider_session = nullptr;
    CHECK(rac_cpu_runtime_get_provider_session(session, &provider_name, &provider_session) ==
              RAC_SUCCESS,
          "unwrap provider session");
    CHECK(provider_name != nullptr && std::string(provider_name) == "fake_cpu",
          "provider name preserved");
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

    cpu->destroy_session(session);
    CHECK(g_destroyed == 1, "provider destroy called");

    rac_cpu_runtime_unregister_provider("fake_cpu");
    session = nullptr;
    CHECK(cpu->create_session(&desc, &session) == RAC_ERROR_NOT_IMPLEMENTED,
          "unregistered provider is not implemented");
    CHECK(session == nullptr, "failed create leaves session null");

    std::cout << "runtime_cpu_session_tests passed" << std::endl;
    return 0;
}
