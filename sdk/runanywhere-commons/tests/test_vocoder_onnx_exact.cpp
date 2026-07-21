/**
 * @file test_vocoder_onnx_exact.cpp
 * @brief Opt-in oracle gate for the pinned NVIDIA BigVGAN ONNX bundle.
 */

#include "vocoder.pb.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <string>

#include "rac/features/vocoder/rac_vocoder.h"
#include "rac/foundation/rac_sha256.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_onnx.h"

namespace {

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

bool near(double actual, double expected, double tolerance) {
    return std::isfinite(actual) && std::fabs(actual - expected) <= tolerance;
}

}  // namespace

int main() {
    const char* model_dir = std::getenv("RA_BIGVGAN_BUNDLE_DIR");
    if (!model_dir || model_dir[0] == '\0') {
        std::fprintf(stdout,
                     "SKIP: set RA_BIGVGAN_BUNDLE_DIR to the pinned BigVGAN export bundle\n");
        return 77;
    }

    const rac_engine_vtable_t* vtable = rac_plugin_entry_onnx();
    if (!vtable || !vtable->vocoder_ops || rac_plugin_register(vtable) != RAC_SUCCESS) {
        std::fprintf(stderr, "FAIL: production ONNX vocoder plugin registration\n");
        return 1;
    }

    rac_handle_t component = nullptr;
    if (rac_vocoder_component_create(&component) != RAC_SUCCESS || !component) {
        std::fprintf(stderr, "FAIL: vocoder component creation\n");
        (void)rac_plugin_unregister("onnx");
        return 1;
    }
    const char* model_id = "nvidia-bigvgan-v2-22khz-80band-256x";
    const rac_result_t load_rc = rac_vocoder_component_load_model(
        component, model_dir, model_id, "NVIDIA BigVGAN v2 22 kHz 80-band 256x");
    if (load_rc != RAC_SUCCESS) {
        std::fprintf(stderr, "FAIL: exact BigVGAN bundle load returned %d\n", load_rc);
        rac_vocoder_component_destroy(component);
        (void)rac_plugin_unregister("onnx");
        return 1;
    }

    runanywhere::v1::VocoderRequest request;
    request.set_batch_size(1);
    request.set_mel_bin_count(80);
    request.set_frame_count(3);
    std::string samples;
    samples.reserve(240 * sizeof(float));
    for (size_t index = 0; index < 240; ++index) {
        append_float_le(-2.0F + 3.0F * static_cast<float>(index) / 239.0F, &samples);
    }
    request.set_mel_spectrogram_f32_le(std::move(samples));
    std::string request_bytes;
    const bool serialized = request.SerializeToString(&request_bytes);

    rac_proto_buffer_t response{};
    const rac_result_t vocode_rc =
        serialized ? rac_vocoder_component_vocode_proto(
                         component, reinterpret_cast<const uint8_t*>(request_bytes.data()),
                         request_bytes.size(), &response)
                   : RAC_ERROR_ENCODING_ERROR;
    runanywhere::v1::VocoderResult result;
    const bool parsed = vocode_rc == RAC_SUCCESS &&
                        result.ParseFromArray(response.data, static_cast<int>(response.size));
    rac_proto_buffer_free(&response);

    bool valid = parsed && result.batch_size() == 1 && result.channel_count() == 1 &&
                 result.sample_count() == 768 && result.sample_rate_hz() == 22050 &&
                 result.hop_length() == 256 &&
                 result.samples_f32_le().size() == 768 * sizeof(float) &&
                 result.model_id() == model_id && result.processing_time_ms() >= 0;

    double minimum = std::numeric_limits<double>::infinity();
    double maximum = -std::numeric_limits<double>::infinity();
    double sum = 0.0;
    double sum_squares = 0.0;
    double first = std::numeric_limits<double>::quiet_NaN();
    double last = std::numeric_limits<double>::quiet_NaN();
    if (valid) {
        for (size_t index = 0; index < 768; ++index) {
            const double value = read_float_le(result.samples_f32_le(), index);
            valid = valid && std::isfinite(value);
            minimum = std::min(minimum, value);
            maximum = std::max(maximum, value);
            sum += value;
            sum_squares += value * value;
            if (index == 0) {
                first = value;
            }
            last = value;
        }
    }
    const double mean = sum / 768.0;
    const double rms = std::sqrt(sum_squares / 768.0);
    valid = valid && near(minimum, -1.0, 1.0e-4) && near(maximum, 1.0, 1.0e-4) &&
            near(mean, 0.0008340172816474478, 5.0e-4) && near(rms, 0.3346755089442641, 5.0e-4) &&
            near(first, -0.0050332979299128056, 2.0e-4) && near(last, 0.005958514753729105, 2.0e-4);
    const std::string output_sha =
        parsed ? runanywhere::sha256_hex(result.samples_f32_le()) : std::string("-");

    (void)rac_vocoder_component_unload(component);
    rac_vocoder_component_destroy(component);
    (void)rac_plugin_unregister("onnx");

    if (!valid) {
        std::fprintf(stderr,
                     "FAIL: exact BigVGAN parity rc=%d parsed=%d sha=%s "
                     "min=%.9g max=%.9g mean=%.9g rms=%.9g first=%.9g last=%.9g\n",
                     vocode_rc, parsed ? 1 : 0, output_sha.c_str(), minimum, maximum, mean, rms,
                     first, last);
        return 1;
    }
    std::fprintf(stdout,
                 "PASS: pinned BigVGAN output matches independent ORT anchors "
                 "(diagnostic raw SHA %s)\n",
                 output_sha.c_str());
    return 0;
}
