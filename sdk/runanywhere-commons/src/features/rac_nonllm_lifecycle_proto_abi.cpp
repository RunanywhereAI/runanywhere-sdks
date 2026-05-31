/**
 * @file rac_nonllm_lifecycle_proto_abi.cpp
 * @brief Lifecycle-owned generated-proto C ABI for non-LLM operations.
 */

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <string>
#include <utility>
#include <vector>

#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_types.h"
#include "rac/features/diffusion/rac_diffusion_proto_adapters.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/embeddings/rac_embeddings_proto_adapters.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/stt/rac_stt_proto_adapters.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_proto_adapters.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_proto_adapters.h"
#include "rac/features/vad/rac_vad_service.h"
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

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    if (!out) {
        return RAC_ERROR_NULL_POINTER;
    }
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
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

int64_t estimate_audio_length_ms(size_t byte_count, int32_t sample_rate, size_t bytes_per_sample) {
    const int32_t rate = sample_rate > 0 ? sample_rate : RAC_STT_DEFAULT_SAMPLE_RATE;
    const size_t width = bytes_per_sample > 0 ? bytes_per_sample : RAC_STT_BYTES_PER_SAMPLE;
    return static_cast<int64_t>(
        (static_cast<double>(byte_count) / static_cast<double>(width) / static_cast<double>(rate)) *
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
    if (!options)
        return;
    rac_free(const_cast<char*>(options->voice));
    if (options->language != RAC_TTS_OPTIONS_DEFAULT.language) {
        rac_free(const_cast<char*>(options->language));
    }
    *options = RAC_TTS_OPTIONS_DEFAULT;
}

void free_diffusion_options(rac_diffusion_options_t* options) {
    if (!options)
        return;
    rac_free(const_cast<char*>(options->prompt));
    rac_free(const_cast<char*>(options->negative_prompt));
    *options = RAC_DIFFUSION_OPTIONS_DEFAULT;
}

rac_result_t check_model_id(const std::string& requested, const char* loaded, const char* message,
                            rac_proto_buffer_t* out) {
    if (!requested.empty() && loaded && requested != loaded) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_INVALID_ARGUMENT, message);
    }
    return RAC_SUCCESS;
}

rac_result_t parse_stt_request(const uint8_t* request_proto_bytes, size_t request_proto_size,
                               runanywhere::v1::STTTranscriptionRequest* out_request,
                               rac_proto_buffer_t* out_error) {
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_error, "STTTranscriptionRequest bytes are invalid");
    }
    if (!out_request->ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                     static_cast<int>(request_proto_size))) {
        return parse_error(out_error, "failed to parse STTTranscriptionRequest");
    }
    if (out_request->has_audio() && (!out_request->audio().file_uri().empty() ||
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

rac_result_t parse_tts_request(const uint8_t* request_proto_bytes, size_t request_proto_size,
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

rac_result_t parse_vad_request(const uint8_t* request_proto_bytes, size_t request_proto_size,
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
                                std::vector<float>* out, rac_proto_buffer_t* out_error) {
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

rac_result_t rac_stt_transcribe_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                size_t request_proto_size,
                                                rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    runanywhere::v1::STTTranscriptionRequest request;
    rac_result_t rc =
        parse_stt_request(request_proto_bytes, request_proto_size, &request, out_result);
    if (rc != RAC_SUCCESS)
        return rc;

    rac::lifecycle::LifecycleSttRef ref;
    rc = rac::lifecycle::acquire_lifecycle_stt(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "STT lifecycle model is not loaded");
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

rac_result_t rac_stt_transcribe_stream_lifecycle_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_stt_lifecycle_stream_event_callback_fn callback, void* user_data) {
    if (!callback) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    (void)user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return RAC_ERROR_DECODING_ERROR;
    }

    runanywhere::v1::STTTranscriptionRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    if (request.has_audio() &&
        (!request.audio().file_uri().empty() || !request.audio().adapter_handle().empty())) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    if (!request.has_audio() || request.audio().audio_data().empty()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac::lifecycle::LifecycleSttRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_stt(&ref);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!ref.ops || !ref.ops->transcribe_stream) {
        rac::lifecycle::release_lifecycle_stt(&ref);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
    if (request.has_options() &&
        !rac::foundation::rac_stt_options_from_proto(request.options(), &options)) {
        rac::lifecycle::release_lifecycle_stt(&ref);
        return RAC_ERROR_DECODING_ERROR;
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

    // Bridge context: forwards backend partial/final callbacks into
    // serialized STTStreamEvent envelopes via the caller's proto callback.
    struct StreamCtx {
        rac_stt_lifecycle_stream_event_callback_fn fn;
        void* user_data;
        std::string request_id;
        uint64_t next_seq;
        runanywhere::v1::STTLanguage language;
        size_t audio_size;
        int32_t sample_rate;
        size_t sample_width;
    };

    const std::string request_id =
        request.request_id().empty()
            ? std::string("stt-lifecycle-") + std::to_string(rac_get_current_time_ms())
            : request.request_id();

    const size_t sample_width =
        request.audio().encoding() == runanywhere::v1::STT_AUDIO_ENCODING_PCM_F32_LE
            ? sizeof(float)
            : RAC_STT_BYTES_PER_SAMPLE;

    const int32_t effective_sample_rate =
        options.sample_rate > 0 ? options.sample_rate : RAC_STT_DEFAULT_SAMPLE_RATE;

    runanywhere::v1::STTLanguage language_enum = runanywhere::v1::STT_LANGUAGE_UNSPECIFIED;
    if (request.has_options()) {
        language_enum = request.options().language();
    }

    StreamCtx ctx{.fn = callback,
                  .user_data = user_data,
                  .request_id = request_id,
                  .next_seq = 1,
                  .language = language_enum,
                  .audio_size = request.audio().audio_data().size(),
                  .sample_rate = effective_sample_rate,
                  .sample_width = sample_width};

    auto emit_event = [](const runanywhere::v1::STTStreamEvent& event,
                         rac_stt_lifecycle_stream_event_callback_fn fn, void* user_ctx) {
        const size_t size = event.ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size > 0 && !event.SerializeToArray(bytes.data(), static_cast<int>(size))) {
            return;
        }
        fn(bytes.empty() ? nullptr : bytes.data(), bytes.size(), user_ctx);
    };

    // Emit STARTED envelope before the backend call so SDK consumers can wire
    // their state machine (kind = STARTED, seq = 1).
    {
        runanywhere::v1::STTStreamEvent started;
        started.set_seq(ctx.next_seq++);
        started.set_timestamp_us(rac_get_current_time_ms() * 1000);
        started.set_request_id(ctx.request_id);
        started.set_kind(runanywhere::v1::STT_STREAM_EVENT_KIND_STARTED);
        emit_event(started, ctx.fn, ctx.user_data);
    }

    auto bridge = [](const char* partial_text, rac_bool_t is_final, void* opaque) {
        auto* c = static_cast<StreamCtx*>(opaque);
        runanywhere::v1::STTStreamEvent event;
        event.set_seq(c->next_seq++);
        event.set_timestamp_us(rac_get_current_time_ms() * 1000);
        event.set_request_id(c->request_id);
        event.set_kind(is_final == RAC_TRUE ? runanywhere::v1::STT_STREAM_EVENT_KIND_FINAL
                                            : runanywhere::v1::STT_STREAM_EVENT_KIND_PARTIAL);
        auto* partial = event.mutable_partial();
        if (partial_text) {
            partial->set_text(partial_text);
        }
        partial->set_is_final(is_final == RAC_TRUE);
        partial->set_stability(is_final == RAC_TRUE ? 1.0f : 0.0f);
        partial->set_request_id(c->request_id);
        partial->set_language(c->language);
        if (is_final == RAC_TRUE) {
            auto* final_output = event.mutable_final_output();
            if (partial_text) {
                final_output->set_text(partial_text);
            }
            final_output->set_language(c->language);
            const int64_t audio_length_ms =
                estimate_audio_length_ms(c->audio_size, c->sample_rate, c->sample_width);
            final_output->set_duration_ms(audio_length_ms);
            final_output->mutable_metadata()->set_audio_length_ms(audio_length_ms);
        }
        const size_t size = event.ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size > 0 && !event.SerializeToArray(bytes.data(), static_cast<int>(size))) {
            return;
        }
        c->fn(bytes.empty() ? nullptr : bytes.data(), bytes.size(), c->user_data);
    };

    const std::string& audio = request.audio().audio_data();
    rc = ref.ops->transcribe_stream(ref.impl, audio.data(), audio.size(), &options, bridge, &ctx);
    if (rc != RAC_SUCCESS) {
        runanywhere::v1::STTStreamEvent error_event;
        error_event.set_seq(ctx.next_seq++);
        error_event.set_timestamp_us(rac_get_current_time_ms() * 1000);
        error_event.set_request_id(ctx.request_id);
        error_event.set_kind(runanywhere::v1::STT_STREAM_EVENT_KIND_ERROR);
        error_event.set_error_code(rc);
        error_event.set_error_message(rac_error_message(rc));
        emit_event(error_event, ctx.fn, ctx.user_data);
    }
    rac::lifecycle::release_lifecycle_stt(&ref);
    return rc;
#endif
}

rac_result_t rac_tts_synthesize_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                size_t request_proto_size,
                                                rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    runanywhere::v1::TTSSynthesisRequest request;
    rac_result_t rc =
        parse_tts_request(request_proto_bytes, request_proto_size, &request, out_result);
    if (rc != RAC_SUCCESS)
        return rc;

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

rac_result_t rac_vad_process_lifecycle_proto(const uint8_t* request_proto_bytes,
                                             size_t request_proto_size,
                                             rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    runanywhere::v1::VADProcessRequest request;
    rac_result_t rc =
        parse_vad_request(request_proto_bytes, request_proto_size, &request, out_result);
    if (rc != RAC_SUCCESS)
        return rc;

    std::vector<float> samples;
    rc = decode_vad_samples(request.audio(), &samples, out_result);
    if (rc != RAC_SUCCESS)
        return rc;
    if (samples.empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "VADProcessRequest decoded no samples");
    }

    rac::lifecycle::LifecycleVadRef ref;
    rc = rac::lifecycle::acquire_lifecycle_vad(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "VAD lifecycle model is not loaded");
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

    const int32_t sample_rate = request.audio().sample_rate() > 0 ? request.audio().sample_rate()
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

rac_result_t rac_diffusion_generate_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                    size_t request_proto_size,
                                                    rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
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
    rc = check_model_id(
        request.model_id(), ref.model_id,
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

rac_result_t rac_embeddings_embed_batch_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                        size_t request_proto_size,
                                                        rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
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
        if (!text.empty())
            texts.push_back(text);
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
    for (int i = 0; i < result.vectors_size() && std::cmp_less(i, texts.size()); ++i) {
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

// ---------------------------------------------------------------------------
// TTS lifecycle stream / stop ABIs (FLT-12)
// ---------------------------------------------------------------------------

rac_result_t rac_tts_synthesize_stream_lifecycle_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_tts_lifecycle_stream_event_callback_fn callback, void* user_data) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    (void)callback;
    (void)user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!callback)
        return RAC_ERROR_INVALID_ARGUMENT;
    rac_proto_buffer_t error_buf;
    rac_proto_buffer_init(&error_buf);

    runanywhere::v1::TTSSynthesisRequest request;
    rac_result_t rc =
        parse_tts_request(request_proto_bytes, request_proto_size, &request, &error_buf);
    if (rc != RAC_SUCCESS) {
        rac_proto_buffer_free(&error_buf);
        return rc;
    }

    rac::lifecycle::LifecycleTtsRef ref;
    rc = rac::lifecycle::acquire_lifecycle_tts(&ref);
    if (rc != RAC_SUCCESS) {
        rac_proto_buffer_free(&error_buf);
        return rc;
    }

    if (!ref.ops || !ref.ops->synthesize_stream) {
        rac::lifecycle::release_lifecycle_tts(&ref);
        rac_proto_buffer_free(&error_buf);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    rac_tts_options_t options = RAC_TTS_OPTIONS_DEFAULT;
    if (request.has_options() &&
        !rac::foundation::rac_tts_options_from_proto(request.options(), &options)) {
        rac::lifecycle::release_lifecycle_tts(&ref);
        rac_proto_buffer_free(&error_buf);
        return RAC_ERROR_DECODING_ERROR;
    }
    if (request.has_options() && request.options().sample_rate() > 0) {
        options.sample_rate = request.options().sample_rate();
    }

    const bool use_ssml = request.has_ssml() && !request.ssml().empty();
    if (use_ssml) {
        options.use_ssml = RAC_TRUE;
    }
    const std::string& text = use_ssml ? request.ssml() : request.text();

    const std::string request_id =
        request.request_id().empty()
            ? std::string("tts-lifecycle-") + std::to_string(rac_get_current_time_ms())
            : request.request_id();

    struct StreamCtx {
        rac_tts_lifecycle_stream_event_callback_fn fn;
        void* user_data;
        std::string request_id;
        uint64_t next_seq;
        std::string voice_id;
        std::string language_code;
        int32_t sample_rate;
        rac_audio_format_enum_t audio_format;
        int32_t character_count;
    };
    StreamCtx ctx{.fn = callback,
                  .user_data = user_data,
                  .request_id = request_id,
                  .next_seq = 1,
                  .voice_id = options.voice ? options.voice : (ref.model_id ? ref.model_id : ""),
                  .language_code = options.language ? options.language : "",
                  .sample_rate =
                      options.sample_rate > 0 ? options.sample_rate : RAC_TTS_DEFAULT_SAMPLE_RATE,
                  .audio_format = options.audio_format,
                  .character_count = static_cast<int32_t>(text.size())};

    auto emit_event = [](const runanywhere::v1::TTSStreamEvent& event,
                         rac_tts_lifecycle_stream_event_callback_fn fn, void* user_ctx) {
        const size_t size = event.ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size > 0 && !event.SerializeToArray(bytes.data(), static_cast<int>(size))) {
            return;
        }
        fn(bytes.empty() ? nullptr : bytes.data(), bytes.size(), user_ctx);
    };

    // STARTED envelope.
    {
        runanywhere::v1::TTSStreamEvent started;
        started.set_seq(ctx.next_seq++);
        started.set_timestamp_us(rac_get_current_time_ms() * 1000);
        started.set_request_id(ctx.request_id);
        started.set_kind(runanywhere::v1::TTS_STREAM_EVENT_KIND_STARTED);
        emit_event(started, ctx.fn, ctx.user_data);
    }

    auto chunk_bridge = [](const void* audio_data, size_t audio_size, void* opaque) {
        auto* c = static_cast<StreamCtx*>(opaque);
        runanywhere::v1::TTSStreamEvent event;
        event.set_seq(c->next_seq++);
        event.set_timestamp_us(rac_get_current_time_ms() * 1000);
        event.set_request_id(c->request_id);
        event.set_kind(runanywhere::v1::TTS_STREAM_EVENT_KIND_AUDIO_CHUNK);
        auto* output = event.mutable_output();
        if (audio_data && audio_size > 0) {
            output->set_audio_data(audio_data, audio_size);
        }
        const auto audio_format_proto = [c]() {
            switch (c->audio_format) {
                case RAC_AUDIO_FORMAT_WAV:
                    return runanywhere::v1::AUDIO_FORMAT_WAV;
                case RAC_AUDIO_FORMAT_MP3:
                    return runanywhere::v1::AUDIO_FORMAT_MP3;
                case RAC_AUDIO_FORMAT_OPUS:
                    return runanywhere::v1::AUDIO_FORMAT_OPUS;
                case RAC_AUDIO_FORMAT_AAC:
                    return runanywhere::v1::AUDIO_FORMAT_AAC;
                case RAC_AUDIO_FORMAT_FLAC:
                    return runanywhere::v1::AUDIO_FORMAT_FLAC;
                case RAC_AUDIO_FORMAT_PCM:
                default:
                    return runanywhere::v1::AUDIO_FORMAT_PCM;
            }
        }();
        output->set_audio_format(audio_format_proto);
        output->set_sample_rate(c->sample_rate);
        output->set_timestamp_ms(rac_get_current_time_ms());
        output->set_audio_size_bytes(static_cast<int64_t>(audio_size));
        auto* metadata = output->mutable_metadata();
        metadata->set_voice_id(c->voice_id);
        metadata->set_language_code(c->language_code);
        metadata->set_character_count(c->character_count);
        const size_t size = event.ByteSizeLong();
        std::vector<uint8_t> bytes(size);
        if (size > 0 && !event.SerializeToArray(bytes.data(), static_cast<int>(size))) {
            return;
        }
        c->fn(bytes.empty() ? nullptr : bytes.data(), bytes.size(), c->user_data);
    };

    rc = ref.ops->synthesize_stream(ref.impl, text.c_str(), &options, chunk_bridge, &ctx);

    if (rc != RAC_SUCCESS) {
        runanywhere::v1::TTSStreamEvent error_event;
        error_event.set_seq(ctx.next_seq++);
        error_event.set_timestamp_us(rac_get_current_time_ms() * 1000);
        error_event.set_request_id(ctx.request_id);
        error_event.set_kind(runanywhere::v1::TTS_STREAM_EVENT_KIND_ERROR);
        error_event.set_error_code(rc);
        error_event.set_error_message(rac_error_message(rc));
        emit_event(error_event, ctx.fn, ctx.user_data);
    } else {
        runanywhere::v1::TTSStreamEvent completed;
        completed.set_seq(ctx.next_seq++);
        completed.set_timestamp_us(rac_get_current_time_ms() * 1000);
        completed.set_request_id(ctx.request_id);
        completed.set_kind(runanywhere::v1::TTS_STREAM_EVENT_KIND_COMPLETED);
        emit_event(completed, ctx.fn, ctx.user_data);
    }

    free_tts_options(&options);
    rac::lifecycle::release_lifecycle_tts(&ref);
    rac_proto_buffer_free(&error_buf);
    return rc;
#endif
}

rac_result_t rac_tts_stop_lifecycle_proto(rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    return feature_unavailable(out_result);
#else
    rac::lifecycle::LifecycleTtsRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_tts(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc,
                                          "TTS lifecycle voice/model is not loaded");
    }

    rac_result_t stop_rc = RAC_SUCCESS;
    if (ref.ops && ref.ops->stop) {
        stop_rc = ref.ops->stop(ref.impl);
    }

    runanywhere::v1::TTSServiceState state;
    state.set_is_ready(stop_rc == RAC_SUCCESS);
    if (ref.model_id) {
        state.set_current_voice(ref.model_id);
    }
    if (stop_rc != RAC_SUCCESS) {
        state.set_error_code(stop_rc);
        state.set_error_message(rac_error_message(stop_rc));
    }
    rc = copy_proto(state, out_result);
    rac::lifecycle::release_lifecycle_tts(&ref);
    return rc == RAC_SUCCESS ? stop_rc : rc;
#endif
}

rac_result_t rac_tts_list_voices_lifecycle_proto(rac_proto_buffer_t* out) {
    if (!out)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    return feature_unavailable(out);
#else
    rac::lifecycle::LifecycleTtsRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_tts(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out, rc, "TTS lifecycle voice/model is not loaded");
    }

    runanywhere::v1::TTSVoiceList list;
    if (ref.ops && ref.ops->get_info) {
        rac_tts_info_t info = {};
        rac_result_t info_rc = ref.ops->get_info(ref.impl, &info);
        if (info_rc == RAC_SUCCESS) {
            for (size_t i = 0; i < info.num_voices; ++i) {
                const char* id = info.available_voices ? info.available_voices[i] : nullptr;
                if (!id)
                    continue;
                runanywhere::v1::TTSVoiceInfo* voice = list.add_voices();
                voice->set_id(id);
                voice->set_display_name(id);
            }
        }
    }

    if (list.voices_size() == 0 && ref.model_id) {
        runanywhere::v1::TTSVoiceInfo* voice = list.add_voices();
        voice->set_id(ref.model_id);
        voice->set_display_name(ref.model_id);
    }

    rc = copy_proto(list, out);
    rac::lifecycle::release_lifecycle_tts(&ref);
    return rc;
#endif
}

// ---------------------------------------------------------------------------
// VAD lifecycle configure / start / stop / reset ABIs (FLT-12)
// ---------------------------------------------------------------------------

#if defined(RAC_HAVE_PROTOBUF)
namespace {

rac_result_t emit_vad_service_state(const rac::lifecycle::LifecycleVadRef& ref, rac_result_t op_rc,
                                    float threshold, int32_t sample_rate, int32_t frame_length_ms,
                                    rac_proto_buffer_t* out_result) {
    runanywhere::v1::VADServiceState state;
    state.set_is_ready(op_rc == RAC_SUCCESS);
    const bool active = (ref.ops != nullptr && ref.ops->is_speech_active != nullptr &&
                         ref.ops->is_speech_active(ref.impl) == RAC_TRUE);
    state.set_is_speech_active(active);
    state.set_energy_threshold(threshold);
    state.set_sample_rate(sample_rate);
    state.set_frame_length_ms(frame_length_ms);
    if (ref.model_id) {
        state.set_current_model(ref.model_id);
    }
    if (op_rc != RAC_SUCCESS) {
        state.set_error_code(op_rc);
        state.set_error_message(rac_error_message(op_rc));
    }
    return copy_proto(state, out_result);
}

}  // namespace
#endif

rac_result_t rac_vad_configure_lifecycle_proto(const uint8_t* request_proto_bytes,
                                               size_t request_proto_size,
                                               rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_result, "VADConfiguration bytes are invalid");
    }
    runanywhere::v1::VADConfiguration proto;
    if (!proto.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                              static_cast<int>(request_proto_size))) {
        return parse_error(out_result, "failed to parse VADConfiguration");
    }

    rac::lifecycle::LifecycleVadRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_vad(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "VAD lifecycle model is not loaded");
    }

    const int32_t sample_rate =
        proto.sample_rate() > 0 ? proto.sample_rate() : RAC_VAD_DEFAULT_SAMPLE_RATE;
    const int32_t frame_length_ms =
        proto.frame_length_ms() > 0 ? proto.frame_length_ms()
                                    : static_cast<int32_t>(RAC_VAD_DEFAULT_FRAME_LENGTH * 1000.0f);
    const float threshold =
        proto.threshold() > 0.0f ? proto.threshold() : RAC_VAD_DEFAULT_ENERGY_THRESHOLD;

    rac_result_t op_rc = RAC_SUCCESS;
    if (ref.ops && ref.ops->set_threshold) {
        op_rc = ref.ops->set_threshold(ref.impl, threshold);
    }

    rc = emit_vad_service_state(ref, op_rc, threshold, sample_rate, frame_length_ms, out_result);
    rac::lifecycle::release_lifecycle_vad(&ref);
    return rc == RAC_SUCCESS ? op_rc : rc;
#endif
}

rac_result_t rac_vad_start_lifecycle_proto(rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    return feature_unavailable(out_result);
#else
    rac::lifecycle::LifecycleVadRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_vad(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "VAD lifecycle model is not loaded");
    }

    rac_result_t op_rc = RAC_SUCCESS;
    if (ref.ops && ref.ops->start) {
        op_rc = ref.ops->start(ref.impl);
    }

    rc = emit_vad_service_state(
        ref, op_rc, RAC_VAD_DEFAULT_ENERGY_THRESHOLD, RAC_VAD_DEFAULT_SAMPLE_RATE,
        static_cast<int32_t>(RAC_VAD_DEFAULT_FRAME_LENGTH * 1000.0f), out_result);
    rac::lifecycle::release_lifecycle_vad(&ref);
    return rc == RAC_SUCCESS ? op_rc : rc;
#endif
}

rac_result_t rac_vad_stop_lifecycle_proto(rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    return feature_unavailable(out_result);
#else
    rac::lifecycle::LifecycleVadRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_vad(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "VAD lifecycle model is not loaded");
    }

    rac_result_t op_rc = RAC_SUCCESS;
    if (ref.ops && ref.ops->stop) {
        op_rc = ref.ops->stop(ref.impl);
    }

    rc = emit_vad_service_state(
        ref, op_rc, RAC_VAD_DEFAULT_ENERGY_THRESHOLD, RAC_VAD_DEFAULT_SAMPLE_RATE,
        static_cast<int32_t>(RAC_VAD_DEFAULT_FRAME_LENGTH * 1000.0f), out_result);
    rac::lifecycle::release_lifecycle_vad(&ref);
    return rc == RAC_SUCCESS ? op_rc : rc;
#endif
}

rac_result_t rac_vad_reset_lifecycle_proto(rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    return feature_unavailable(out_result);
#else
    rac::lifecycle::LifecycleVadRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_vad(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "VAD lifecycle model is not loaded");
    }

    rac_result_t op_rc = RAC_SUCCESS;
    if (ref.ops && ref.ops->reset) {
        op_rc = ref.ops->reset(ref.impl);
    }

    rc = emit_vad_service_state(
        ref, op_rc, RAC_VAD_DEFAULT_ENERGY_THRESHOLD, RAC_VAD_DEFAULT_SAMPLE_RATE,
        static_cast<int32_t>(RAC_VAD_DEFAULT_FRAME_LENGTH * 1000.0f), out_result);
    rac::lifecycle::release_lifecycle_vad(&ref);
    return rc == RAC_SUCCESS ? op_rc : rc;
#endif
}

}  // extern "C"
