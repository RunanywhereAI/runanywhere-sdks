/**
 * @file rac_nonllm_lifecycle_proto_abi.cpp
 * @brief Lifecycle-owned generated-proto C ABI for non-LLM operations.
 */

#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_adapters.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "diffusion_options.pb.h"
#include "embeddings_options.pb.h"
#include "stt_options.pb.h"
#include "tts_options.pb.h"
#include "vad_options.pb.h"
#endif

namespace {

#if defined(RAC_HAVE_PROTOBUF)

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return (size == 0 || bytes != nullptr) &&
           size <= static_cast<size_t>(std::numeric_limits<int>::max());
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message,
                        rac_proto_buffer_t* out) {
    if (!out) {
        return RAC_ERROR_NULL_POINTER;
    }
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 &&
        !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize proto result");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
}

rac_result_t parse_error(rac_proto_buffer_t* out, const char* message) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_DECODING_ERROR, message);
}

rac_audio_format_enum_t c_audio_format(runanywhere::v1::AudioFormat format) {
    switch (format) {
        case runanywhere::v1::AUDIO_FORMAT_WAV:
            return RAC_AUDIO_FORMAT_WAV;
        case runanywhere::v1::AUDIO_FORMAT_MP3:
            return RAC_AUDIO_FORMAT_MP3;
        case runanywhere::v1::AUDIO_FORMAT_OPUS:
            return RAC_AUDIO_FORMAT_OPUS;
        case runanywhere::v1::AUDIO_FORMAT_AAC:
            return RAC_AUDIO_FORMAT_AAC;
        case runanywhere::v1::AUDIO_FORMAT_FLAC:
            return RAC_AUDIO_FORMAT_FLAC;
        case runanywhere::v1::AUDIO_FORMAT_PCM:
        case runanywhere::v1::AUDIO_FORMAT_PCM_S16LE:
        default:
            return RAC_AUDIO_FORMAT_PCM;
    }
}

int64_t estimate_audio_length_ms(size_t byte_count,
                                 int32_t sample_rate,
                                 size_t bytes_per_sample) {
    const int32_t rate = sample_rate > 0 ? sample_rate : RAC_STT_DEFAULT_SAMPLE_RATE;
    const size_t width = bytes_per_sample > 0 ? bytes_per_sample : RAC_STT_BYTES_PER_SAMPLE;
    return static_cast<int64_t>((static_cast<double>(byte_count) /
                                 static_cast<double>(width) /
                                 static_cast<double>(rate)) *
                                1000.0);
}

float compute_rms_energy(const float* samples, size_t count) {
    if (!samples || count == 0) {
        return 0.0f;
    }
    double sum = 0.0;
    for (size_t i = 0; i < count; ++i) {
        sum += static_cast<double>(samples[i]) * static_cast<double>(samples[i]);
    }
    return static_cast<float>(std::sqrt(sum / static_cast<double>(count)));
}

void free_tts_options(rac_tts_options_t* options) {
    if (!options) return;
    rac_free(const_cast<char*>(options->voice));
    if (options->language != RAC_TTS_OPTIONS_DEFAULT.language) {
        rac_free(const_cast<char*>(options->language));
    }
    *options = RAC_TTS_OPTIONS_DEFAULT;
}

void free_diffusion_options(rac_diffusion_options_t* options) {
    if (!options) return;
    rac_free(const_cast<char*>(options->prompt));
    rac_free(const_cast<char*>(options->negative_prompt));
    *options = RAC_DIFFUSION_OPTIONS_DEFAULT;
}

rac_result_t check_model_id(const std::string& requested,
                            const char* loaded,
                            const char* message,
                            rac_proto_buffer_t* out) {
    if (!requested.empty() && loaded && requested != loaded) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_INVALID_ARGUMENT, message);
    }
    return RAC_SUCCESS;
}

rac_result_t parse_stt_request(const uint8_t* request_proto_bytes,
                               size_t request_proto_size,
                               runanywhere::v1::STTTranscriptionRequest* out_request,
                               rac_proto_buffer_t* out_error) {
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_error, "STTTranscriptionRequest bytes are invalid");
    }
    if (!out_request->ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                     static_cast<int>(request_proto_size))) {
        return parse_error(out_error, "failed to parse STTTranscriptionRequest");
    }
    if (out_request->has_audio() &&
        (!out_request->audio().file_uri().empty() ||
         !out_request->audio().adapter_handle().empty())) {
        return rac_proto_buffer_set_error(
            out_error, RAC_ERROR_NOT_SUPPORTED,
            "STTTranscriptionRequest audio file_uri/adapter_handle requires a platform adapter");
    }
    if (!out_request->has_audio() || out_request->audio().audio_data().empty()) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                          "STTTranscriptionRequest.audio.audio_data is required");
    }
    return RAC_SUCCESS;
}

rac_result_t parse_tts_request(const uint8_t* request_proto_bytes,
                               size_t request_proto_size,
                               runanywhere::v1::TTSSynthesisRequest* out_request,
                               rac_proto_buffer_t* out_error) {
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_error, "TTSSynthesisRequest bytes are invalid");
    }
    if (!out_request->ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                     static_cast<int>(request_proto_size))) {
        return parse_error(out_error, "failed to parse TTSSynthesisRequest");
    }
    if (out_request->text().empty() && !out_request->has_ssml()) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                          "TTSSynthesisRequest.text or ssml is required");
    }
    return RAC_SUCCESS;
}

rac_result_t parse_vad_request(const uint8_t* request_proto_bytes,
                               size_t request_proto_size,
                               runanywhere::v1::VADProcessRequest* out_request,
                               rac_proto_buffer_t* out_error) {
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_error, "VADProcessRequest bytes are invalid");
    }
    if (!out_request->ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                     static_cast<int>(request_proto_size))) {
        return parse_error(out_error, "failed to parse VADProcessRequest");
    }
    if (out_request->has_audio() && !out_request->audio().adapter_handle().empty()) {
        return rac_proto_buffer_set_error(
            out_error, RAC_ERROR_NOT_SUPPORTED,
            "VADProcessRequest audio adapter_handle requires a platform adapter");
    }
    if (!out_request->has_audio() || out_request->audio().audio_data().empty()) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                          "VADProcessRequest.audio.audio_data is required");
    }
    if (out_request->audio().channels() > 1) {
        return rac_proto_buffer_set_error(
            out_error, RAC_ERROR_NOT_SUPPORTED,
            "VADProcessRequest multi-channel audio is not supported by the portable lifecycle ABI");
    }
    return RAC_SUCCESS;
}

rac_result_t decode_vad_samples(const runanywhere::v1::VADAudioSource& audio,
                                std::vector<float>* out,
                                rac_proto_buffer_t* out_error) {
    const std::string& bytes = audio.audio_data();
    out->clear();
    switch (audio.encoding()) {
        case runanywhere::v1::VAD_AUDIO_ENCODING_PCM_S16_LE: {
            if (bytes.size() % sizeof(int16_t) != 0) {
                return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                                  "VAD PCM_S16_LE audio byte length is invalid");
            }
            const size_t count = bytes.size() / sizeof(int16_t);
            out->resize(count);
            const auto* raw = reinterpret_cast<const uint8_t*>(bytes.data());
            for (size_t i = 0; i < count; ++i) {
                const int16_t sample =
                    static_cast<int16_t>(static_cast<uint16_t>(raw[i * 2]) |
                                         (static_cast<uint16_t>(raw[i * 2 + 1]) << 8));
                (*out)[i] = static_cast<float>(sample) / 32768.0f;
            }
            return RAC_SUCCESS;
        }
        case runanywhere::v1::VAD_AUDIO_ENCODING_UNSPECIFIED:
        case runanywhere::v1::VAD_AUDIO_ENCODING_PCM_F32_LE: {
            if (bytes.size() % sizeof(float) != 0) {
                return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                                  "VAD PCM_F32_LE audio byte length is invalid");
            }
            const size_t count = bytes.size() / sizeof(float);
            out->resize(count);
            if (count > 0) {
                std::memcpy(out->data(), bytes.data(), bytes.size());
            }
            return RAC_SUCCESS;
        }
        default:
            return rac_proto_buffer_set_error(out_error, RAC_ERROR_NOT_SUPPORTED,
                                              "VAD audio encoding is not supported");
    }
}

#endif  // RAC_HAVE_PROTOBUF

[[maybe_unused]] rac_result_t feature_unavailable(rac_proto_buffer_t* out) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
}

}  // namespace

extern "C" {

rac_result_t rac_stt_transcribe_lifecycle_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_proto_buffer_t* out_result) {
    if (!out_result) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    runanywhere::v1::STTTranscriptionRequest request;
    rac_result_t rc = parse_stt_request(request_proto_bytes, request_proto_size,
                                        &request, out_result);
    if (rc != RAC_SUCCESS) return rc;

    rac::lifecycle::LifecycleSttRef ref;
    rc = rac::lifecycle::acquire_lifecycle_stt(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc,
                                          "STT lifecycle model is not loaded");
    }

    rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
    if (request.has_options() &&
        !rac::foundation::rac_stt_options_from_proto(request.options(), &options)) {
        rac::lifecycle::release_lifecycle_stt(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert STTOptions");
    }
    if (request.has_options() && request.options().has_language_code() &&
        !request.options().language_code().empty()) {
        options.language = request.options().language_code().c_str();
        options.detect_language = RAC_FALSE;
    }
    if (request.audio().sample_rate() > 0) {
        options.sample_rate = request.audio().sample_rate();
    }
    if (request.audio().audio_format() != runanywhere::v1::AUDIO_FORMAT_UNSPECIFIED) {
        options.audio_format = c_audio_format(request.audio().audio_format());
    }

    const std::string& audio = request.audio().audio_data();
    rac_stt_service_t service{ref.ops, ref.impl, ref.model_id};
    rac_stt_result_t raw = {};
    rc = rac_stt_transcribe(&service, audio.data(), audio.size(), &options, &raw);
    if (rc != RAC_SUCCESS) {
        rac::lifecycle::release_lifecycle_stt(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::STTOutput output;
    if (!rac::foundation::rac_stt_result_to_proto(&raw, &output)) {
        rac_stt_result_free(&raw);
        rac::lifecycle::release_lifecycle_stt(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                          "failed to encode STTOutput");
    }
    output.set_timestamp_ms(rac_get_current_time_ms());
    const size_t sample_width =
        request.audio().encoding() == runanywhere::v1::STT_AUDIO_ENCODING_PCM_F32_LE
            ? sizeof(float)
            : RAC_STT_BYTES_PER_SAMPLE;
    const int64_t duration_ms =
        request.audio().duration_ms() > 0
            ? request.audio().duration_ms()
            : estimate_audio_length_ms(audio.size(), options.sample_rate, sample_width);
    output.set_duration_ms(duration_ms);
    auto* metadata = output.mutable_metadata();
    metadata->set_model_id(ref.model_id ? ref.model_id : "");
    metadata->set_audio_length_ms(duration_ms);
    if (duration_ms > 0 && metadata->processing_time_ms() > 0) {
        metadata->set_real_time_factor(
            static_cast<float>(static_cast<double>(metadata->processing_time_ms()) /
                               static_cast<double>(duration_ms)));
    }

    rc = copy_proto(output, out_result);
    rac_stt_result_free(&raw);
    rac::lifecycle::release_lifecycle_stt(&ref);
    return rc;
#endif
}

rac_result_t rac_tts_synthesize_lifecycle_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_proto_buffer_t* out_result) {
    if (!out_result) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    runanywhere::v1::TTSSynthesisRequest request;
    rac_result_t rc = parse_tts_request(request_proto_bytes, request_proto_size,
                                        &request, out_result);
    if (rc != RAC_SUCCESS) return rc;

    rac::lifecycle::LifecycleTtsRef ref;
    rc = rac::lifecycle::acquire_lifecycle_tts(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc,
                                          "TTS lifecycle voice/model is not loaded");
    }

    rac_tts_options_t options = RAC_TTS_OPTIONS_DEFAULT;
    if (request.has_options() &&
        !rac::foundation::rac_tts_options_from_proto(request.options(), &options)) {
        rac::lifecycle::release_lifecycle_tts(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert TTSOptions");
    }
    if (request.has_options() && request.options().sample_rate() > 0) {
        options.sample_rate = request.options().sample_rate();
    }

    const bool use_ssml = request.has_ssml() && !request.ssml().empty();
    if (use_ssml) {
        options.use_ssml = RAC_TRUE;
    }
    const std::string& text = use_ssml ? request.ssml() : request.text();
    rac_tts_service_t service{ref.ops, ref.impl, ref.model_id};
    rac_tts_result_t raw = {};
    rc = rac_tts_synthesize(&service, text.c_str(), &options, &raw);
    if (rc != RAC_SUCCESS) {
        free_tts_options(&options);
        rac::lifecycle::release_lifecycle_tts(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::TTSOutput output;
    if (!rac::foundation::rac_tts_result_to_proto(&raw, &output)) {
        rac_tts_result_free(&raw);
        free_tts_options(&options);
        rac::lifecycle::release_lifecycle_tts(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                          "failed to encode TTSOutput");
    }
    output.set_timestamp_ms(rac_get_current_time_ms());
    output.set_is_final(true);
    output.set_error_code(RAC_SUCCESS);
    output.set_audio_size_bytes(static_cast<int64_t>(raw.audio_size));
    auto* metadata = output.mutable_metadata();
    metadata->set_voice_id(options.voice ? options.voice : (ref.model_id ? ref.model_id : ""));
    if (options.language) {
        metadata->set_language_code(options.language);
    }
    metadata->set_character_count(static_cast<int32_t>(text.size()));

    rc = copy_proto(output, out_result);
    rac_tts_result_free(&raw);
    free_tts_options(&options);
    rac::lifecycle::release_lifecycle_tts(&ref);
    return rc;
#endif
}

rac_result_t rac_vad_process_lifecycle_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_proto_buffer_t* out_result) {
    if (!out_result) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    runanywhere::v1::VADProcessRequest request;
    rac_result_t rc = parse_vad_request(request_proto_bytes, request_proto_size,
                                        &request, out_result);
    if (rc != RAC_SUCCESS) return rc;

    std::vector<float> samples;
    rc = decode_vad_samples(request.audio(), &samples, out_result);
    if (rc != RAC_SUCCESS) return rc;
    if (samples.empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "VADProcessRequest decoded no samples");
    }

    rac::lifecycle::LifecycleVadRef ref;
    rc = rac::lifecycle::acquire_lifecycle_vad(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc,
                                          "VAD lifecycle model is not loaded");
    }

    float threshold = RAC_VAD_DEFAULT_ENERGY_THRESHOLD;
    if (request.has_options() && request.options().threshold() > 0.0f) {
        threshold = request.options().threshold();
        if (ref.ops->set_threshold) {
            (void)ref.ops->set_threshold(ref.impl, threshold);
        }
    }

    rac_bool_t is_speech = RAC_FALSE;
    if (!ref.ops->process) {
        rac::lifecycle::release_lifecycle_vad(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NOT_SUPPORTED,
                                          "VAD backend does not implement process");
    }
    rc = ref.ops->process(ref.impl, samples.data(), samples.size(), &is_speech);
    if (rc != RAC_SUCCESS) {
        rac::lifecycle::release_lifecycle_vad(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    const int32_t sample_rate =
        request.audio().sample_rate() > 0 ? request.audio().sample_rate()
                                          : RAC_VAD_DEFAULT_SAMPLE_RATE;
    const float energy = compute_rms_energy(samples.data(), samples.size());
    runanywhere::v1::VADResult result;
    result.set_is_speech(is_speech == RAC_TRUE);
    result.set_energy(energy);
    result.set_confidence(threshold > 0.0f ? std::min(1.0f, energy / threshold)
                                           : (is_speech == RAC_TRUE ? 1.0f : 0.0f));
    int32_t duration_ms = static_cast<int32_t>(
        (static_cast<double>(samples.size()) / static_cast<double>(sample_rate)) * 1000.0);
    if (!samples.empty() && duration_ms == 0) {
        duration_ms = 1;
    }
    result.set_duration_ms(duration_ms);
    result.set_timestamp_ms(rac_get_current_time_ms());
    rc = copy_proto(result, out_result);
    rac::lifecycle::release_lifecycle_vad(&ref);
    return rc;
#endif
}

rac_result_t rac_diffusion_generate_lifecycle_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_proto_buffer_t* out_result) {
    if (!out_result) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_result, "DiffusionGenerationRequest bytes are invalid");
    }
    runanywhere::v1::DiffusionGenerationRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return parse_error(out_result, "failed to parse DiffusionGenerationRequest");
    }
    if (!request.has_options()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "DiffusionGenerationRequest.options is required");
    }

    rac::lifecycle::LifecycleDiffusionRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_diffusion(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc,
                                          "Diffusion lifecycle model is not loaded");
    }
    rc = check_model_id(request.model_id(), ref.model_id,
                        "DiffusionGenerationRequest.model_id does not match the lifecycle-loaded model",
                        out_result);
    if (rc != RAC_SUCCESS) {
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rc;
    }

    rac_diffusion_options_t options = RAC_DIFFUSION_OPTIONS_DEFAULT;
    if (!rac::foundation::rac_diffusion_options_from_proto(request.options(), &options)) {
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert DiffusionGenerationOptions");
    }
    if (!options.prompt || options.prompt[0] == '\0') {
        free_diffusion_options(&options);
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "DiffusionGenerationOptions.prompt is required");
    }

    rac_diffusion_service_t service{ref.ops, ref.impl, ref.model_id};
    rac_diffusion_result_t raw = {};
    rc = rac_diffusion_generate(&service, &options, &raw);
    if (rc != RAC_SUCCESS) {
        free_diffusion_options(&options);
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::DiffusionResult result;
    if (!rac::foundation::rac_diffusion_result_to_proto(&raw, &result)) {
        rac_diffusion_result_free(&raw);
        free_diffusion_options(&options);
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                          "failed to encode DiffusionResult");
    }
    rc = copy_proto(result, out_result);
    rac_diffusion_result_free(&raw);
    free_diffusion_options(&options);
    rac::lifecycle::release_lifecycle_diffusion(&ref);
    return rc;
#endif
}

rac_result_t rac_embeddings_embed_batch_lifecycle_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_proto_buffer_t* out_result) {
    if (!out_result) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_result, "EmbeddingsRequest bytes are invalid");
    }
    runanywhere::v1::EmbeddingsRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return parse_error(out_result, "failed to parse EmbeddingsRequest");
    }

    rac::lifecycle::LifecycleEmbeddingsRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_embeddings(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc,
                                          "Embeddings lifecycle model is not loaded");
    }
    rc = check_model_id(request.model_id(), ref.model_id,
                        "EmbeddingsRequest.model_id does not match the lifecycle-loaded model",
                        out_result);
    if (rc != RAC_SUCCESS) {
        rac::lifecycle::release_lifecycle_embeddings(&ref);
        return rc;
    }

    std::vector<std::string> texts;
    texts.reserve(static_cast<size_t>(request.texts_size()));
    for (const auto& text : request.texts()) {
        if (!text.empty()) texts.push_back(text);
    }
    if (texts.empty()) {
        rac::lifecycle::release_lifecycle_embeddings(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "EmbeddingsRequest.texts is required");
    }

    rac_embeddings_options_t options = RAC_EMBEDDINGS_OPTIONS_DEFAULT;
    if (request.has_options() &&
        !rac::foundation::rac_embeddings_options_from_proto(request.options(), &options)) {
        rac::lifecycle::release_lifecycle_embeddings(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert EmbeddingsOptions");
    }

    std::vector<const char*> c_texts;
    c_texts.reserve(texts.size());
    for (const auto& text : texts) {
        c_texts.push_back(text.c_str());
    }

    rac_embeddings_service_t service{ref.ops, ref.impl, ref.model_id};
    rac_embeddings_result_t raw = {};
    rc = rac_embeddings_embed_batch(&service, c_texts.data(), c_texts.size(), &options, &raw);
    if (rc != RAC_SUCCESS) {
        rac::lifecycle::release_lifecycle_embeddings(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::EmbeddingsResult result;
    if (!rac::foundation::rac_embeddings_result_to_proto(&raw, &result)) {
        rac_embeddings_result_free(&raw);
        rac::lifecycle::release_lifecycle_embeddings(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                          "failed to encode EmbeddingsResult");
    }
    for (int i = 0; i < result.vectors_size() && i < static_cast<int>(texts.size()); ++i) {
        result.mutable_vectors(i)->set_text(texts[static_cast<size_t>(i)]);
        result.mutable_vectors(i)->set_input_index(i);
    }
    result.set_model_id(ref.model_id ? ref.model_id : "");
    result.set_request_id(request.request_id());
    rc = copy_proto(result, out_result);
    rac_embeddings_result_free(&raw);
    rac::lifecycle::release_lifecycle_embeddings(&ref);
    return rc;
#endif
}

}  // extern "C"
