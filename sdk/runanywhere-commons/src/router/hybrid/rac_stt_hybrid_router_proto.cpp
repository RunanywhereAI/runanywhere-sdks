/**
 * @file rac_stt_hybrid_router_proto.cpp
 * @brief Proto-byte wrappers for the STT hybrid router. All proto type
 *        usage stays inside rac_commons.so so the hidden-visibility default
 *        doesn't strand symbols at the .so boundary.
 *
 * Each wrapper:
 *   1. Decodes the runanywhere.v1.* proto bytes into a transient message.
 *   2. Translates that message into the native C struct surface the
 *      router consumes.
 *   3. Calls the existing rac_stt_hybrid_router_* C ABI.
 *   4. For transcribe_proto, builds and serialises a
 *      runanywhere.v1.HybridSttTranscribeResponse and returns it as a heap
 *      allocation the binding frees via
 *      rac_stt_hybrid_router_proto_buffer_free.
 */

#include "rac/router/hybrid/rac_stt_hybrid_router_proto.h"

#if !defined(RAC_HAVE_PROTOBUF)
// Protobuf-less builds (e.g. the wasm preset) keep the exported proto ABI
// surface as unavailable stubs, matching the repo-wide
// RAC_ENABLE_PROTOBUF=OFF contract ("exported proto ABI functions use
// unavailable stubs").

#include <cstdlib>

extern "C" {

rac_result_t rac_stt_hybrid_router_set_offline_service_proto(rac_handle_t /*handle*/,
                                                             rac_stt_service_t* /*service*/,
                                                             const uint8_t* /*descriptor_bytes*/,
                                                             size_t /*descriptor_size*/) {
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

rac_result_t rac_stt_hybrid_router_set_online_service_proto(rac_handle_t /*handle*/,
                                                            rac_stt_service_t* /*service*/,
                                                            const uint8_t* /*descriptor_bytes*/,
                                                            size_t /*descriptor_size*/) {
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

rac_result_t rac_stt_hybrid_router_set_policy_proto(rac_handle_t /*handle*/,
                                                    const uint8_t* /*policy_bytes*/,
                                                    size_t /*policy_size*/) {
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

rac_result_t rac_stt_hybrid_router_transcribe_proto(rac_handle_t /*handle*/,
                                                    const uint8_t* /*request_bytes*/,
                                                    size_t /*request_size*/,
                                                    uint8_t** out_response_bytes,
                                                    size_t* out_response_size) {
    if (out_response_bytes != nullptr) {
        *out_response_bytes = nullptr;
    }
    if (out_response_size != nullptr) {
        *out_response_size = 0;
    }
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

void rac_stt_hybrid_router_proto_buffer_free(uint8_t* response_bytes) {
    std::free(response_bytes);
}

}  // extern "C"

#else  // RAC_HAVE_PROTOBUF

#include "hybrid_router.pb.h"
#include "sdk_events.pb.h"

#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "infrastructure/events/sdk_event_publish.h"
#include "rac/core/rac_audio_utils.h"
#include "rac/core/rac_error.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/router/hybrid/rac_hybrid_device_state.h"
#include "rac/router/hybrid/rac_hybrid_types.h"
#include "rac/router/hybrid/rac_stt_hybrid_router.h"

namespace v1 = ::runanywhere::v1;

namespace {

// Emit one STT telemetry event for a hybrid transcribe. The router invokes the
// engine vtable directly (no lifecycle-proto path), so without this the hybrid
// STT path produces no telemetry. Routes through the events layer → "stt"
// modality. model_id carries the backend that actually served the request
// (on-device id or cloud id), so cloud-vs-local is visible. The dedicated
// routed_backend/was_fallback columns need a VoiceLifecycleEvent proto field to
// populate end-to-end (deferred — would require regenerating bindings).
void emit_hybrid_stt_telemetry(const rac_stt_result_t& result,
                               const rac_hybrid_routed_metadata_t& meta, rac_result_t rc,
                               const char* language, int32_t sample_rate) {
    const bool ok = (rc == RAC_SUCCESS);
    v1::VoiceLifecycleEvent voice;
    voice.set_kind(ok ? v1::VOICE_EVENT_KIND_STT_COMPLETED : v1::VOICE_EVENT_KIND_STT_FAILED);
    if (meta.chosen_model_id[0] != '\0') {
        voice.set_model_id(meta.chosen_model_id);
    }
    if (ok && result.text != nullptr && result.text[0] != '\0') {
        voice.set_text(result.text);
    }
    if (!std::isnan(meta.confidence) && meta.confidence > 0.0f) {
        voice.set_confidence(meta.confidence);
    }
    if (result.processing_time_ms > 0) {
        voice.set_duration_ms(static_cast<int64_t>(result.processing_time_ms));
    }
    if (language != nullptr && language[0] != '\0') {
        voice.set_language(language);
    }
    if (sample_rate > 0) {
        voice.set_sample_rate(sample_rate);
    }
    if (!ok) {
        voice.set_error(rac_error_message(rc));
    }
    rac::events::publish_with_session(v1::SDK_COMPONENT_STT, v1::EVENT_CATEGORY_STT,
                                      std::move(voice), nullptr);
}

void parse_descriptor(const uint8_t* bytes, size_t size, rac_hybrid_model_descriptor_t& out) {
    std::memset(&out, 0, sizeof(out));
    if (bytes == nullptr || size == 0) {
        return;
    }
    v1::HybridModelDescriptor msg;
    if (!msg.ParseFromArray(bytes, static_cast<int>(size))) {
        return;
    }
    const auto& id = msg.model_id();
    std::strncpy(out.model_id, id.c_str(), sizeof(out.model_id) - 1);
    out.model_type = static_cast<rac_hybrid_model_type_t>(msg.model_type());
    out.backend = static_cast<rac_hybrid_backend_kind_t>(msg.backend());
}

bool parse_filter(const v1::HybridFilter& f, rac_hybrid_filter_t& out) {
    std::memset(&out, 0, sizeof(out));
    switch (f.kind_case()) {
        case v1::HybridFilter::kNetwork:
            out.kind = RAC_HYBRID_FILTER_NETWORK;
            out.data.network_required = f.network();
            return true;
        case v1::HybridFilter::kQualityTier:
            out.kind = RAC_HYBRID_FILTER_QUALITY;
            out.data.quality_tier = f.quality_tier();
            return true;
        case v1::HybridFilter::kBattery:
            out.kind = RAC_HYBRID_FILTER_BATTERY;
            out.data.battery.min_battery_percent = f.battery().min_battery_percent();
            return true;
        case v1::HybridFilter::kCustom: {
            // Carry the custom filter's NAME (and description for logging) into
            // the C filter struct. The predicate itself is NOT marshalled —
            // the router resolves it from the named custom-filter table
            // (rac_hybrid_custom_filter.h) that the host registers separately.
            // A nameless custom filter is meaningless (nothing to look up), so
            // drop it just like an unset oneof.
            const auto& custom = f.custom();
            if (custom.name().empty()) {
                return false;
            }
            out.kind = RAC_HYBRID_FILTER_CUSTOM;
            std::strncpy(out.data.custom.name, custom.name().c_str(),
                         sizeof(out.data.custom.name) - 1);
            out.data.custom.name[sizeof(out.data.custom.name) - 1] = '\0';
            std::strncpy(out.data.custom.description, custom.description().c_str(),
                         sizeof(out.data.custom.description) - 1);
            out.data.custom.description[sizeof(out.data.custom.description) - 1] = '\0';
            out.data.custom.check = nullptr;      // predicate lives in the named table
            out.data.custom.user_data = nullptr;  // not used on the proto path
            return true;
        }
        case v1::HybridFilter::KIND_NOT_SET:
        default:
            return false;
    }
}

void parse_policy(const uint8_t* bytes, size_t size, std::vector<rac_hybrid_filter_t>& filters,
                  rac_hybrid_routing_policy_t& policy) {
    filters.clear();
    std::memset(&policy, 0, sizeof(policy));
    if (bytes != nullptr && size > 0) {
        v1::HybridRoutingPolicy msg;
        if (msg.ParseFromArray(bytes, static_cast<int>(size))) {
            for (const auto& f : msg.hard_filters()) {
                rac_hybrid_filter_t parsed{};
                if (parse_filter(f, parsed)) {
                    filters.push_back(parsed);
                }
            }
            if (msg.has_cascade()) {
                const auto& c = msg.cascade();
                if (c.kind_case() == v1::HybridCascade::kConfidence) {
                    policy.cascade.kind = RAC_HYBRID_CASCADE_CONFIDENCE;
                    policy.cascade.data.confidence.threshold = c.confidence().threshold();
                }
            }
            policy.rank = static_cast<rac_hybrid_rank_t>(msg.rank());
        }
    }
    policy.hard_filters = filters.empty() ? nullptr : filters.data();
    policy.hard_filter_count = static_cast<int32_t>(filters.size());
}

void build_context(const v1::HybridRoutingContext& /*proto_ctx*/,
                   rac_hybrid_routing_context_t& out) {
    std::memset(&out, 0, sizeof(out));
    rac_hybrid_device_state_snapshot_t snap{};
    if (rac_hybrid_get_device_state_snapshot(&snap) == RAC_SUCCESS) {
        out.is_online = snap.is_online;
        out.battery_percent = snap.battery_percent;
    } else {
        out.is_online = true;
        out.battery_percent = 100;
    }
}

bool is_wav_container(const std::string& audio) {
    return audio.size() >= 12 && std::memcmp(audio.data(), "RIFF", 4) == 0 &&
           std::memcmp(audio.data() + 8, "WAVE", 4) == 0;
}

/**
 * Normalise the audio payload for the shared offline+online dispatch. The
 * router hands ONE payload to both services, and only a WAV container
 * satisfies both: sherpa parses WAV inline (and falls back to raw PCM16),
 * but cloud providers upload the bytes verbatim as an `audio/wav` file part
 * and reject headerless PCM. Raw PCM16 is therefore wrapped via
 * rac_audio_int16_to_wav using the request's sample rate (16 kHz when unset,
 * sherpa's own default). Input that is already a container — WAV by
 * RIFF/WAVE magic, or a declared compressed format — passes through
 * unchanged. Owned by commons so every SDK gets the same behaviour.
 *
 * Returns a malloc'd WAV buffer (caller frees with rac_free) and updates
 * options in place, or nullptr when the payload passes through as-is.
 */
void* normalize_audio_payload(const std::string& audio, rac_stt_options_t& options,
                              const uint8_t** out_data, size_t* out_size) {
    *out_data = reinterpret_cast<const uint8_t*>(audio.data());
    *out_size = audio.size();
    const bool is_compressed = options.audio_format > RAC_AUDIO_FORMAT_WAV;
    if (audio.empty() || is_compressed || is_wav_container(audio)) {
        return nullptr;
    }
    const int32_t sample_rate = options.sample_rate > 0 ? options.sample_rate : 16000;
    void* wav_data = nullptr;
    size_t wav_size = 0;
    if (rac_audio_int16_to_wav(audio.data(), audio.size(), sample_rate, &wav_data, &wav_size) !=
            RAC_SUCCESS ||
        wav_data == nullptr) {
        return nullptr;  // fail open: dispatch the raw payload unchanged
    }
    options.sample_rate = sample_rate;
    options.audio_format = RAC_AUDIO_FORMAT_WAV;
    *out_data = static_cast<const uint8_t*>(wav_data);
    *out_size = wav_size;
    return wav_data;
}

rac_result_t build_response_bytes(const rac_stt_result_t& result,
                                  const rac_hybrid_routed_metadata_t& meta,
                                  rac_result_t transcribe_rc, uint8_t** out_bytes,
                                  size_t* out_size) {
    v1::HybridSttTranscribeResponse msg;
    msg.set_rc(static_cast<int32_t>(transcribe_rc));
    msg.set_text(result.text != nullptr ? result.text : "");
    msg.set_detected_language(result.detected_language != nullptr ? result.detected_language : "");
    auto* routing = msg.mutable_routing();
    routing->set_chosen_model_id(meta.chosen_model_id);
    routing->set_was_fallback(meta.was_fallback);
    routing->set_attempt_count(meta.attempt_count);
    routing->set_primary_error_code(meta.primary_error_code);
    routing->set_primary_error_message(meta.primary_error_message);
    routing->set_confidence(meta.confidence);
    routing->set_primary_confidence(meta.primary_confidence);

    const std::string serialised = msg.SerializeAsString();
    auto* buf = static_cast<uint8_t*>(std::malloc(serialised.size()));
    if (buf == nullptr && !serialised.empty()) {
        *out_bytes = nullptr;
        *out_size = 0;
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    if (!serialised.empty()) {
        std::memcpy(buf, serialised.data(), serialised.size());
    }
    *out_bytes = buf;
    *out_size = serialised.size();
    return RAC_SUCCESS;
}

}  // namespace

extern "C" {

rac_result_t rac_stt_hybrid_router_set_offline_service_proto(rac_handle_t handle,
                                                             rac_stt_service_t* service,
                                                             const uint8_t* descriptor_bytes,
                                                             size_t descriptor_size) {
    if (handle == RAC_INVALID_HANDLE) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    rac_hybrid_model_descriptor_t desc{};
    parse_descriptor(descriptor_bytes, descriptor_size, desc);
    return rac_stt_hybrid_router_set_offline_service(handle, service,
                                                     service != nullptr ? &desc : nullptr);
}

rac_result_t rac_stt_hybrid_router_set_online_service_proto(rac_handle_t handle,
                                                            rac_stt_service_t* service,
                                                            const uint8_t* descriptor_bytes,
                                                            size_t descriptor_size) {
    if (handle == RAC_INVALID_HANDLE) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    rac_hybrid_model_descriptor_t desc{};
    parse_descriptor(descriptor_bytes, descriptor_size, desc);
    return rac_stt_hybrid_router_set_online_service(handle, service,
                                                    service != nullptr ? &desc : nullptr);
}

rac_result_t rac_stt_hybrid_router_set_policy_proto(rac_handle_t handle,
                                                    const uint8_t* policy_bytes,
                                                    size_t policy_size) {
    if (handle == RAC_INVALID_HANDLE) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    std::vector<rac_hybrid_filter_t> filters;
    rac_hybrid_routing_policy_t policy{};
    parse_policy(policy_bytes, policy_size, filters, policy);
    return rac_stt_hybrid_router_set_policy(handle, &policy);
}

rac_result_t rac_stt_hybrid_router_transcribe_proto(rac_handle_t handle,
                                                    const uint8_t* request_bytes,
                                                    size_t request_size,
                                                    uint8_t** out_response_bytes,
                                                    size_t* out_response_size) {
    if (out_response_bytes == nullptr || out_response_size == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    *out_response_bytes = nullptr;
    *out_response_size = 0;
    if (handle == RAC_INVALID_HANDLE || request_bytes == nullptr || request_size == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    v1::HybridSttTranscribeRequest req;
    if (!req.ParseFromArray(request_bytes, static_cast<int>(request_size))) {
        return RAC_ERROR_INVALID_RESPONSE;
    }

    rac_hybrid_routing_context_t ctx{};
    build_context(req.context(), ctx);

    rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
    std::string language_storage;
    const auto& opt = req.options();
    language_storage = opt.language();
    // Do NOT inherit RAC_STT_OPTIONS_DEFAULT.language ("en") when the caller
    // didn't pin a language — the cloud provider (sarvam) rejects bare "en";
    // only BCP-47 region forms like "en-IN" or the "unknown" sentinel are
    // accepted. NULL here lets each engine fall back to its own default
    // (cloud/sarvam: "unknown", sherpa: whatever the model header declares).
    options.language = language_storage.empty() ? nullptr : language_storage.c_str();
    if (opt.sample_rate() > 0) {
        options.sample_rate = opt.sample_rate();
    }
    if (opt.audio_format() > 0) {
        options.audio_format = static_cast<rac_audio_format_enum_t>(opt.audio_format());
    }

    const std::string& audio = req.audio_bytes();
    const uint8_t* audio_data = nullptr;
    size_t audio_size = 0;
    void* owned_wav = normalize_audio_payload(audio, options, &audio_data, &audio_size);

    rac_stt_result_t result{};
    rac_hybrid_routed_metadata_t meta{};
    const rac_result_t transcribe_rc = rac_stt_hybrid_router_transcribe(
        handle, &ctx, audio_data, audio_size, &options, &result, &meta);
    rac_free(owned_wav);

    // Hybrid STT bypasses the lifecycle-proto path, so emit telemetry here.
    emit_hybrid_stt_telemetry(result, meta, transcribe_rc, options.language, options.sample_rate);

    const rac_result_t encode_rc =
        build_response_bytes(result, meta, transcribe_rc, out_response_bytes, out_response_size);
    rac_stt_result_free(&result);
    if (encode_rc != RAC_SUCCESS) {
        return encode_rc;
    }
    return RAC_SUCCESS;
}

void rac_stt_hybrid_router_proto_buffer_free(uint8_t* response_bytes) {
    std::free(response_bytes);
}

}  // extern "C"

#endif  // RAC_HAVE_PROTOBUF
