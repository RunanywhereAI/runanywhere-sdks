/**
 * @file test_vocoder_onnx.cpp
 * @brief Real-ORT tiny vocoder contract, proto ABI, and lifecycle tests.
 */

#include "model_types.pb.h"
#include "vocoder.pb.h"

#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <future>
#include <limits>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/vocoder/rac_vocoder.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

#ifndef RAC_VOCODER_FIXTURE_DIR
#error "RAC_VOCODER_FIXTURE_DIR must name the real ONNX fixture bundle"
#endif

extern "C" const rac_vocoder_service_ops_t g_onnx_vocoder_ops;

namespace {

using namespace std::chrono_literals;

int g_checks = 0;
int g_failures = 0;
int g_competing_create_calls = 0;

struct OperationGate {
    std::mutex mutex;
    std::condition_variable cv;
    bool entered = false;
    bool release = false;
};

std::atomic<OperationGate*> g_operation_gate{nullptr};
std::atomic<bool> g_throw_vocode{false};

rac_result_t fixture_vocode(void* impl, const rac_vocoder_input_t* input,
                            rac_vocoder_result_t* out_result) {
    if (g_throw_vocode.exchange(false, std::memory_order_acq_rel)) {
        throw std::bad_alloc();
    }
    if (auto* gate = g_operation_gate.load(std::memory_order_acquire)) {
        std::unique_lock<std::mutex> lock(gate->mutex);
        gate->entered = true;
        gate->cv.notify_all();
        gate->cv.wait(lock, [&] { return gate->release; });
    }
    return g_onnx_vocoder_ops.vocode(impl, input, out_result);
}

const rac_vocoder_service_ops_t* fixture_ops() {
    static const rac_vocoder_service_ops_t kOps = {
        .initialize = g_onnx_vocoder_ops.initialize,
        .vocode = fixture_vocode,
        .cleanup = g_onnx_vocoder_ops.cleanup,
        .destroy = g_onnx_vocoder_ops.destroy,
        .create = g_onnx_vocoder_ops.create,
    };
    return &kOps;
}

bool wait_for_gate(OperationGate* gate) {
    std::unique_lock<std::mutex> lock(gate->mutex);
    return gate->cv.wait_for(lock, 2s, [&] { return gate->entered; });
}

void release_gate(OperationGate* gate) {
    {
        std::lock_guard<std::mutex> lock(gate->mutex);
        gate->release = true;
    }
    gate->cv.notify_all();
}

#define CHECK(condition, label)                                                      \
    do {                                                                             \
        ++g_checks;                                                                  \
        if (condition) {                                                             \
            std::fprintf(stdout, "  ok:   %s\n", label);                             \
        } else {                                                                     \
            ++g_failures;                                                            \
            std::fprintf(stderr, "  FAIL: %s (%s:%d)\n", label, __FILE__, __LINE__); \
        }                                                                            \
    } while (0)

rac_result_t competing_create(const char* model_id, const char* config_json, void** out_impl) {
    ++g_competing_create_calls;
    return g_onnx_vocoder_ops.create(model_id, config_json, out_impl);
}

const rac_vocoder_service_ops_t* competing_ops() {
    static const rac_vocoder_service_ops_t kOps = {
        .initialize = g_onnx_vocoder_ops.initialize,
        .vocode = g_onnx_vocoder_ops.vocode,
        .cleanup = g_onnx_vocoder_ops.cleanup,
        .destroy = g_onnx_vocoder_ops.destroy,
        .create = competing_create,
    };
    return &kOps;
}

rac_engine_vtable_t make_fixture_vtable() {
    static const uint32_t kFormats[] = {static_cast<uint32_t>(runanywhere::v1::MODEL_FORMAT_ONNX)};
    rac_engine_vtable_t vtable{};
    vtable.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    vtable.metadata.name = "onnx";
    vtable.metadata.display_name = "ONNX Vocoder Fixture";
    vtable.metadata.engine_version = "1";
    vtable.metadata.priority = 1000;
    vtable.metadata.formats = kFormats;
    vtable.metadata.formats_count = 1;
    vtable.vocoder_ops = fixture_ops();
    return vtable;
}

rac_engine_vtable_t make_competing_vtable() {
    rac_engine_vtable_t vtable{};
    vtable.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    vtable.metadata.name = "vocoder-hijacker";
    vtable.metadata.display_name = "Higher-Priority Vocoder";
    vtable.metadata.engine_version = "1";
    vtable.metadata.priority = 2000;
    vtable.vocoder_ops = competing_ops();
    return vtable;
}

bool decode_base64(const std::string& encoded, std::vector<uint8_t>* output) {
    if (!output) {
        return false;
    }
    output->clear();
    const std::string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    uint32_t accumulator = 0;
    int bits = 0;
    for (const unsigned char character : encoded) {
        if (character == '=') {
            break;
        }
        const auto position = alphabet.find(static_cast<char>(character));
        if (position == std::string::npos) {
            if (character == ' ' || character == '\n' || character == '\r' || character == '\t') {
                continue;
            }
            return false;
        }
        accumulator = (accumulator << 6U) | static_cast<uint32_t>(position);
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            output->push_back(static_cast<uint8_t>((accumulator >> bits) & 0xffU));
        }
    }
    return !output->empty();
}

std::filesystem::path materialize_fixture(const char* suffix) {
    const auto unique = std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
    const auto destination =
        std::filesystem::temp_directory_path() / (std::string("rac-vocoder-") + suffix + unique);
    try {
        std::filesystem::copy(RAC_VOCODER_FIXTURE_DIR, destination,
                              std::filesystem::copy_options::recursive);
        std::ifstream source(destination / "model.onnx.base64", std::ios::binary);
        if (!source) {
            std::filesystem::remove_all(destination);
            return {};
        }
        const std::string encoded((std::istreambuf_iterator<char>(source)),
                                  std::istreambuf_iterator<char>());
        std::vector<uint8_t> model;
        if (source.bad() || !decode_base64(encoded, &model)) {
            std::filesystem::remove_all(destination);
            return {};
        }
        std::ofstream output(destination / "model.onnx", std::ios::binary | std::ios::trunc);
        output.write(reinterpret_cast<const char*>(model.data()),
                     static_cast<std::streamsize>(model.size()));
        output.close();
        if (!output || model.size() != 409) {
            std::filesystem::remove_all(destination);
            return {};
        }
        return destination;
    } catch (...) {
        std::filesystem::remove_all(destination);
        return {};
    }
}

void append_float_le(float value, std::string* bytes) {
    uint32_t bits = 0;
    std::memcpy(&bits, &value, sizeof(bits));
    bytes->push_back(static_cast<char>(bits & 0xffU));
    bytes->push_back(static_cast<char>((bits >> 8U) & 0xffU));
    bytes->push_back(static_cast<char>((bits >> 16U) & 0xffU));
    bytes->push_back(static_cast<char>((bits >> 24U) & 0xffU));
}

float read_float_le(const std::string& bytes, size_t index) {
    const auto* source = reinterpret_cast<const uint8_t*>(bytes.data()) + index * sizeof(float);
    const uint32_t bits =
        static_cast<uint32_t>(source[0]) | (static_cast<uint32_t>(source[1]) << 8U) |
        (static_cast<uint32_t>(source[2]) << 16U) | (static_cast<uint32_t>(source[3]) << 24U);
    float value = 0.0F;
    std::memcpy(&value, &bits, sizeof(value));
    return value;
}

runanywhere::v1::VocoderRequest make_ramp_request() {
    runanywhere::v1::VocoderRequest request;
    request.set_batch_size(1);
    request.set_mel_bin_count(80);
    request.set_frame_count(3);
    std::string bytes;
    bytes.reserve(240 * sizeof(float));
    for (size_t index = 0; index < 240; ++index) {
        append_float_le(-2.0F + 3.0F * static_cast<float>(index) / 239.0F, &bytes);
    }
    request.set_mel_spectrogram_f32_le(std::move(bytes));
    return request;
}

bool vocode_component(rac_handle_t component, const runanywhere::v1::VocoderRequest& request,
                      runanywhere::v1::VocoderResult* output, rac_result_t* out_rc = nullptr) {
    std::string request_bytes;
    if (!request.SerializeToString(&request_bytes)) {
        return false;
    }
    rac_proto_buffer_t response{};
    const rac_result_t rc = rac_vocoder_component_vocode_proto(
        component, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
        &response);
    if (out_rc) {
        *out_rc = rc;
    }
    const bool parsed = rc == RAC_SUCCESS && output &&
                        output->ParseFromArray(response.data, static_cast<int>(response.size));
    rac_proto_buffer_free(&response);
    return parsed;
}

bool vocode_lifecycle(const runanywhere::v1::VocoderRequest& request,
                      runanywhere::v1::VocoderResult* output, rac_result_t* out_rc = nullptr) {
    std::string request_bytes;
    if (!request.SerializeToString(&request_bytes)) {
        return false;
    }
    rac_proto_buffer_t response{};
    const rac_result_t rc = rac_vocoder_vocode_lifecycle_proto(
        reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(), &response);
    if (out_rc) {
        *out_rc = rc;
    }
    const bool parsed = rc == RAC_SUCCESS && output &&
                        output->ParseFromArray(response.data, static_cast<int>(response.size));
    rac_proto_buffer_free(&response);
    return parsed;
}

bool valid_fixture_result(const runanywhere::v1::VocoderRequest& request,
                          const runanywhere::v1::VocoderResult& result,
                          const std::string& model_id) {
    if (result.batch_size() != 1 || result.channel_count() != 1 || result.sample_count() != 768 ||
        result.sample_rate_hz() != 22050 || result.hop_length() != 256 ||
        result.samples_f32_le().size() != 768 * sizeof(float) || result.model_id() != model_id ||
        result.processing_time_ms() < 0) {
        return false;
    }
    for (size_t frame = 0; frame < 3; ++frame) {
        double expected = 0.0;
        for (size_t mel = 0; mel < 80; ++mel) {
            expected += read_float_le(request.mel_spectrogram_f32_le(), mel * 3 + frame);
        }
        expected /= 80.0;
        for (size_t sample = 0; sample < 256; ++sample) {
            const float actual = read_float_le(result.samples_f32_le(), frame * 256 + sample);
            if (!std::isfinite(actual) || std::fabs(actual - expected) > 1.0e-5) {
                return false;
            }
        }
    }
    return true;
}

rac_result_t initialize_bundle_direct(const std::filesystem::path& path) {
    void* implementation = nullptr;
    const rac_result_t create_rc =
        g_onnx_vocoder_ops.create(path.string().c_str(), nullptr, &implementation);
    if (create_rc != RAC_SUCCESS || !implementation) {
        return create_rc == RAC_SUCCESS ? RAC_ERROR_BACKEND_NOT_READY : create_rc;
    }
    const rac_result_t rc = g_onnx_vocoder_ops.initialize(implementation, path.string().c_str());
    if (g_onnx_vocoder_ops.cleanup) {
        (void)g_onnx_vocoder_ops.cleanup(implementation);
    }
    g_onnx_vocoder_ops.destroy(implementation);
    return rc;
}

bool unload_lifecycle_model(const std::string& model_id) {
    runanywhere::v1::ModelUnloadRequest request;
    request.set_model_id(model_id);
    std::string request_bytes;
    if (!request.SerializeToString(&request_bytes)) {
        return false;
    }
    rac_proto_buffer_t response{};
    const rac_result_t rc = rac_model_lifecycle_unload_proto(
        reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(), &response);
    runanywhere::v1::ModelUnloadResult result;
    const bool unloaded = rc == RAC_SUCCESS &&
                          result.ParseFromArray(response.data, static_cast<int>(response.size)) &&
                          result.success() && result.unloaded_model_ids_size() == 1 &&
                          result.unloaded_model_ids(0) == model_id;
    rac_proto_buffer_free(&response);
    return unloaded;
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_vocoder_onnx (real tiny ONNX graph)\n");
    const auto fixture = materialize_fixture("fixture-");
    CHECK(!fixture.empty() && std::filesystem::file_size(fixture / "model.onnx") == 409,
          "text fixture materializes a real 409-byte ONNX graph");
    if (fixture.empty()) {
        return 1;
    }
    const auto reload_fixture = materialize_fixture("reload-");
    CHECK(!reload_fixture.empty(), "second pinned fixture path materializes for reload testing");
    if (reload_fixture.empty()) {
        std::filesystem::remove_all(fixture);
        return 1;
    }

    const rac_engine_vtable_t vtable = make_fixture_vtable();
    const rac_engine_vtable_t competing_vtable = make_competing_vtable();
    CHECK(rac_plugin_register(&vtable) == RAC_SUCCESS, "fixture vocoder plugin registers");
    CHECK(rac_plugin_register(&competing_vtable) == RAC_SUCCESS,
          "higher-priority competing vocoder plugin registers");
    CHECK(rac_plugin_find(RAC_PRIMITIVE_VOCODE) == &competing_vtable,
          "unhinted primitive lookup selects the higher-priority competitor");

    rac_handle_t component = nullptr;
    CHECK(rac_vocoder_component_create(&component) == RAC_SUCCESS && component,
          "vocoder component creates");
    const auto request = make_ramp_request();
    runanywhere::v1::VocoderResult result;
    rac_result_t rc = RAC_SUCCESS;
    CHECK(!vocode_component(component, request, &result, &rc) && rc == RAC_ERROR_NOT_INITIALIZED,
          "component proto ABI rejects inference before model load");
    CHECK(rac_vocoder_component_load_model(component, fixture.string().c_str(), "fixture-bigvgan",
                                           "Fixture BigVGAN") == RAC_SUCCESS,
          "real tiny ONNX fixture loads through Commons lifecycle");
    CHECK(g_competing_create_calls == 0,
          "ONNX framework hint prevents a higher-priority vocoder from hijacking routing");
    CHECK(rac_vocoder_component_is_loaded(component) == RAC_TRUE, "component reports loaded state");
    CHECK(vocode_component(component, request, &result),
          "compact little-endian mel proto dispatches through real ORT");
    CHECK(valid_fixture_result(request, result, "fixture-bigvgan"),
          "fixture waveform shape, metadata, model ID, and samples are exact");

    OperationGate reload_gate;
    g_operation_gate.store(&reload_gate, std::memory_order_release);
    runanywhere::v1::VocoderResult in_flight_result;
    auto in_flight = std::async(std::launch::async, [&] {
        return vocode_component(component, request, &in_flight_result);
    });
    CHECK(wait_for_gate(&reload_gate), "component inference pauses inside the pinned provider");
    g_operation_gate.store(nullptr, std::memory_order_release);
    auto reload = std::async(std::launch::async, [&] {
        return rac_vocoder_component_load_model(component, reload_fixture.string().c_str(),
                                                "fixture-bigvgan-reloaded",
                                                "Fixture BigVGAN reloaded");
    });
    CHECK(reload.wait_for(50ms) == std::future_status::timeout,
          "component reload waits while inference owns provider and model identity");
    release_gate(&reload_gate);
    CHECK(in_flight.wait_for(2s) == std::future_status::ready && in_flight.get() &&
              valid_fixture_result(request, in_flight_result, "fixture-bigvgan"),
          "in-flight inference returns the old provider's matching model ID");
    CHECK(reload.wait_for(2s) == std::future_status::ready && reload.get() == RAC_SUCCESS,
          "component reload completes after inference releases its identity lease");
    runanywhere::v1::VocoderResult reloaded_result;
    CHECK(vocode_component(component, request, &reloaded_result) &&
              valid_fixture_result(request, reloaded_result, "fixture-bigvgan-reloaded"),
          "subsequent inference returns the reloaded provider's model ID");
    g_throw_vocode.store(true, std::memory_order_release);
    CHECK(!vocode_component(component, request, &result, &rc) && rc == RAC_ERROR_OUT_OF_MEMORY,
          "component proto exception barrier maps bad_alloc to an owned error result");

    auto malformed = request;
    malformed.mutable_mel_spectrogram_f32_le()->pop_back();
    CHECK(!vocode_component(component, malformed, &result, &rc) && rc == RAC_ERROR_INVALID_ARGUMENT,
          "proto ABI rejects malformed little-endian tensor bytes");
    auto wrong_shape = request;
    wrong_shape.set_mel_bin_count(79);
    wrong_shape.mutable_mel_spectrogram_f32_le()->resize(79 * 3 * sizeof(float));
    CHECK(!vocode_component(component, wrong_shape, &result, &rc) &&
              rc == RAC_ERROR_INVALID_ARGUMENT,
          "BigVGAN provider requires exactly 80 mel bins");
    auto nonfinite = request;
    std::string nonfinite_bytes = nonfinite.mel_spectrogram_f32_le();
    nonfinite_bytes.resize(nonfinite_bytes.size() - sizeof(float));
    append_float_le(std::numeric_limits<float>::quiet_NaN(), &nonfinite_bytes);
    nonfinite.set_mel_spectrogram_f32_le(std::move(nonfinite_bytes));
    CHECK(!vocode_component(component, nonfinite, &result, &rc) && rc == RAC_ERROR_INVALID_ARGUMENT,
          "proto ABI rejects non-finite mel values");

    const auto corrupt = materialize_fixture("corrupt-");
    {
        std::fstream config(corrupt / "config.json", std::ios::in | std::ios::out);
        char first = 0;
        config.read(&first, 1);
        config.clear();
        config.seekp(0);
        first = first == '{' ? '[' : '{';
        config.write(&first, 1);
    }
    CHECK(initialize_bundle_direct(corrupt) == RAC_ERROR_MODEL_VALIDATION_FAILED,
          "bundle bytes are verified against exact pinned SHA-256 sidecars");
    std::filesystem::remove_all(corrupt);

    CHECK(rac_vocoder_component_unload(component) == RAC_SUCCESS, "component unload succeeds");
    rac_vocoder_component_destroy(component);

    rac_model_lifecycle_reset();
    rac_model_registry_handle_t registry = nullptr;
    CHECK(rac_model_registry_create(&registry) == RAC_SUCCESS && registry,
          "canonical lifecycle registry creates");
    if (registry) {
        runanywhere::v1::ModelInfo model;
        model.set_id("fixture-bigvgan-lifecycle");
        model.set_name("Fixture BigVGAN lifecycle");
        model.set_category(runanywhere::v1::MODEL_CATEGORY_VOCODER);
        model.set_format(runanywhere::v1::MODEL_FORMAT_ONNX);
        model.set_framework(runanywhere::v1::INFERENCE_FRAMEWORK_ONNX);
        model.set_local_path(fixture.string());
        model.set_is_downloaded(true);
        model.set_is_available(true);
        std::string model_bytes;
        CHECK(model.SerializeToString(&model_bytes) &&
                  rac_model_registry_register_proto(
                      registry, reinterpret_cast<const uint8_t*>(model_bytes.data()),
                      model_bytes.size()) == RAC_SUCCESS,
              "vocoder fixture registers in the canonical model registry");

        runanywhere::v1::ModelLoadRequest load_request;
        load_request.set_model_id(model.id());
        std::string load_bytes;
        (void)load_request.SerializeToString(&load_bytes);
        rac_proto_buffer_t load_response{};
        const rac_result_t load_rc = rac_model_lifecycle_load_proto(
            registry, reinterpret_cast<const uint8_t*>(load_bytes.data()), load_bytes.size(),
            &load_response);
        runanywhere::v1::ModelLoadResult load_result;
        const bool loaded =
            load_rc == RAC_SUCCESS &&
            load_result.ParseFromArray(load_response.data, static_cast<int>(load_response.size)) &&
            load_result.success() && load_result.model_id() == model.id();
        rac_proto_buffer_free(&load_response);
        CHECK(loaded, "canonical model lifecycle loads the real ONNX vocoder fixture");

        runanywhere::v1::VocoderResult lifecycle_result;
        CHECK(loaded && vocode_lifecycle(request, &lifecycle_result),
              "handle-free SDK ABI dispatches vocoding through real ORT");
        CHECK(loaded && valid_fixture_result(request, lifecycle_result, model.id()),
              "handle-free result preserves exact waveform contract and canonical model ID");
        g_throw_vocode.store(true, std::memory_order_release);
        CHECK(!vocode_lifecycle(request, &lifecycle_result, &rc) && rc == RAC_ERROR_OUT_OF_MEMORY,
              "handle-free proto exception barrier maps bad_alloc and releases its lifecycle ref");
        CHECK(loaded && unload_lifecycle_model(model.id()),
              "canonical lifecycle unload releases the vocoder provider");
        CHECK(!vocode_lifecycle(request, &lifecycle_result, &rc) && rc == RAC_ERROR_NOT_INITIALIZED,
              "handle-free vocoder rejects inference after unload");
        rac_model_registry_destroy(registry);
    }
    rac_model_lifecycle_reset();

    CHECK(rac_plugin_unregister("vocoder-hijacker") == RAC_SUCCESS,
          "competing vocoder plugin unregisters");
    CHECK(rac_plugin_unregister("onnx") == RAC_SUCCESS, "fixture vocoder plugin unregisters");
    std::filesystem::remove_all(fixture);
    std::filesystem::remove_all(reload_fixture);
    std::fprintf(stdout, "\n%d checks, %d failed\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
