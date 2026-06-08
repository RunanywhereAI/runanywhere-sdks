/**
 * @file rac_tts_stream.cpp
 * @brief Implementation of the lifecycle-owned proto-byte TTS stream ABI
 *        declared in `rac_tts_stream.h`.
 *
 * Mirrors `rac_llm_stream.cpp` exactly:
 *   - Per-handle CallbackSlot registry guarded by a mutex.
 *   - Session map indexed by monotonically-increasing 64-bit ids.
 */

#include "rac/features/tts/rac_tts_stream.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <limits>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include "features/common/rac_stream_registry_internal.h"
#include "rac/core/rac_logger.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_proto_adapters.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "tts_options.pb.h"
#endif

namespace {

std::atomic<int> g_in_flight{0};

using CallbackSlot = rac::stream::CallbackSlot<rac_tts_stream_proto_callback_fn>;

struct StreamSession {
    rac_handle_t handle = nullptr;
    std::string request_id;
    std::atomic<bool> is_cancelled{false};
};

std::mutex& g_mu() {
    static std::mutex m;
    return m;
}

std::unordered_map<rac_handle_t, CallbackSlot>& g_slots() {
    static std::unordered_map<rac_handle_t, CallbackSlot> m;
    return m;
}

std::unordered_map<uint64_t, StreamSession>& g_sessions() {
    static std::unordered_map<uint64_t, StreamSession> m;
    return m;
}

rac::stream::SessionIdAllocator g_session_ids;

#if defined(RAC_HAVE_PROTOBUF)
int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

bool valid_proto_bytes(const uint8_t* bytes, size_t size) {
    return (size == 0 || bytes != nullptr) &&
           size <= static_cast<size_t>(std::numeric_limits<int>::max());
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

runanywhere::v1::AudioFormat proto_audio_format(rac_audio_format_enum_t format) {
    switch (format) {
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
}

void free_tts_options(rac_tts_options_t* options) {
    if (!options) {
        return;
    }
    rac_free(const_cast<char*>(options->voice));
    if (options->language != RAC_TTS_OPTIONS_DEFAULT.language) {
        rac_free(const_cast<char*>(options->language));
    }
    *options = RAC_TTS_OPTIONS_DEFAULT;
}

bool session_is_active(uint64_t session_id) {
    std::lock_guard<std::mutex> lock(g_mu());
    auto it = g_sessions().find(session_id);
    return it != g_sessions().end() && !it->second.is_cancelled.load(std::memory_order_relaxed);
}

void erase_session(uint64_t session_id) {
    std::lock_guard<std::mutex> lock(g_mu());
    g_sessions().erase(session_id);
}
#endif

}  // namespace

#if defined(RAC_HAVE_PROTOBUF)
namespace rac::tts {
void dispatch_tts_stream_event(rac_handle_t handle, runanywhere::v1::TTSStreamEventKind kind,
                               const runanywhere::v1::TTSOutput* output,
                               const runanywhere::v1::TTSPhonemeTimestamp* phoneme,
                               const runanywhere::v1::TTSSpeakResult* speak_result,
                               const char* error_message, int error_code, uint64_t session_id = 0);
}  // namespace rac::tts
#endif

extern "C" {

rac_result_t rac_tts_set_stream_proto_callback(rac_handle_t handle,
                                               rac_tts_stream_proto_callback_fn callback,
                                               void* user_data) {
    if (handle == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    std::lock_guard<std::mutex> lock(g_mu());
    if (callback == nullptr) {
        g_slots().erase(handle);
    } else {
        g_slots()[handle] = CallbackSlot{.fn = callback, .user_data = user_data, .seq = 0};
    }
    return RAC_SUCCESS;
}

rac_result_t rac_tts_unset_stream_proto_callback(rac_handle_t handle) {
    if (handle == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    std::lock_guard<std::mutex> lock(g_mu());
    g_slots().erase(handle);
    return RAC_SUCCESS;
}

void rac_tts_proto_quiesce(void) {
    while (g_in_flight.load(std::memory_order_acquire) > 0) {
        std::this_thread::yield();
    }
}

rac_result_t rac_tts_stream_start_proto(rac_handle_t handle, const uint8_t* request_proto_bytes,
                                        size_t request_proto_size, uint64_t* out_session_id) {
    if (handle == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    if (out_session_id == nullptr)
        return RAC_ERROR_NULL_POINTER;
    if (request_proto_size > 0 && request_proto_bytes == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out_session_id = 0;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!valid_proto_bytes(request_proto_bytes, request_proto_size)) {
        return RAC_ERROR_DECODING_ERROR;
    }

    runanywhere::v1::TTSSynthesisRequest parsed;
    if (!parsed.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                               static_cast<int>(request_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    const bool use_ssml = parsed.has_ssml() && !parsed.ssml().empty();
    if (parsed.text().empty() && !use_ssml) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_tts_options_t options = RAC_TTS_OPTIONS_DEFAULT;
    if (parsed.has_options() &&
        !rac::foundation::rac_tts_options_from_proto(parsed.options(), &options)) {
        free_tts_options(&options);
        return RAC_ERROR_DECODING_ERROR;
    }
    if (parsed.has_options() && parsed.options().sample_rate() > 0) {
        options.sample_rate = parsed.options().sample_rate();
    }
    if (use_ssml) {
        options.use_ssml = RAC_TRUE;
    }

    const uint64_t session_id = g_session_ids.next();
    const std::string request_id = parsed.request_id().empty()
                                       ? std::string("tts-") + std::to_string(session_id)
                                       : parsed.request_id();
    {
        std::lock_guard<std::mutex> lock(g_mu());
        StreamSession& session = g_sessions()[session_id];
        session.handle = handle;
        session.request_id = request_id;
        session.is_cancelled.store(false, std::memory_order_relaxed);
    }
    *out_session_id = session_id;

    const std::string& text = use_ssml ? parsed.ssml() : parsed.text();
    const char* voice_id = options.voice ? options.voice : rac_tts_component_get_voice_id(handle);
    struct StreamContext {
        rac_handle_t handle;
        uint64_t session_id;
        std::string voice_id;
        std::string language_code;
        int32_t sample_rate;
        rac_audio_format_enum_t audio_format;
        int32_t character_count;
        int32_t chunk_index;
    } context{.handle = handle,
              .session_id = session_id,
              .voice_id = voice_id ? voice_id : "",
              .language_code = options.language ? options.language : "",
              .sample_rate =
                  options.sample_rate > 0 ? options.sample_rate : RAC_TTS_DEFAULT_SAMPLE_RATE,
              .audio_format = options.audio_format,
              .character_count = static_cast<int32_t>(text.size()),
              .chunk_index = 0};

    rac::tts::dispatch_tts_stream_event(handle, runanywhere::v1::TTS_STREAM_EVENT_KIND_STARTED,
                                        nullptr, nullptr, nullptr, nullptr, 0, session_id);

    auto bridge = [](const void* audio_data, size_t audio_size, void* opaque) {
        auto* ctx = static_cast<StreamContext*>(opaque);
        if (!session_is_active(ctx->session_id)) {
            return;
        }
        runanywhere::v1::TTSOutput output;
        if (audio_data && audio_size > 0) {
            output.set_audio_data(audio_data, audio_size);
        }
        output.set_audio_format(proto_audio_format(ctx->audio_format));
        output.set_sample_rate(ctx->sample_rate);
        output.set_timestamp_ms(now_us() / 1000);
        output.set_audio_size_bytes(static_cast<int64_t>(audio_size));
        output.set_chunk_index(ctx->chunk_index++);
        auto* metadata = output.mutable_metadata();
        metadata->set_voice_id(ctx->voice_id);
        metadata->set_language_code(ctx->language_code);
        metadata->set_character_count(ctx->character_count);
        rac::tts::dispatch_tts_stream_event(ctx->handle,
                                            runanywhere::v1::TTS_STREAM_EVENT_KIND_AUDIO_CHUNK,
                                            &output, nullptr, nullptr, nullptr, 0, ctx->session_id);
    };

    rac_result_t rc =
        rac_tts_component_synthesize_stream(handle, text.c_str(), &options, bridge, &context);
    const bool active = session_is_active(session_id);
    if (active) {
        if (rc == RAC_SUCCESS) {
            rac::tts::dispatch_tts_stream_event(handle,
                                                runanywhere::v1::TTS_STREAM_EVENT_KIND_COMPLETED,
                                                nullptr, nullptr, nullptr, nullptr, 0, session_id);
        } else {
            rac::tts::dispatch_tts_stream_event(
                handle, runanywhere::v1::TTS_STREAM_EVENT_KIND_ERROR, nullptr, nullptr, nullptr,
                rac_error_message(rc), rc, session_id);
        }
    }
    erase_session(session_id);
    free_tts_options(&options);
    return active ? rc : RAC_ERROR_CANCELLED;
#endif
}

rac_result_t rac_tts_stream_stop_proto(uint64_t session_id) {
    if (session_id == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(g_mu());
    auto it = g_sessions().find(session_id);
    if (it == g_sessions().end())
        return RAC_ERROR_INVALID_ARGUMENT;
    g_sessions().erase(it);
    return RAC_SUCCESS;
}

rac_result_t rac_tts_stream_cancel_proto(uint64_t session_id) {
    if (session_id == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(g_mu());
    auto it = g_sessions().find(session_id);
    if (it == g_sessions().end())
        return RAC_ERROR_INVALID_ARGUMENT;
    it->second.is_cancelled.store(true, std::memory_order_relaxed);
    g_sessions().erase(it);
    return RAC_SUCCESS;
}

}  // extern "C"

#if defined(RAC_HAVE_PROTOBUF)
namespace rac::tts {

void dispatch_tts_stream_event(rac_handle_t handle, runanywhere::v1::TTSStreamEventKind kind,
                               const runanywhere::v1::TTSOutput* output,
                               const runanywhere::v1::TTSPhonemeTimestamp* phoneme,
                               const runanywhere::v1::TTSSpeakResult* speak_result,
                               const char* error_message, int error_code, uint64_t session_id) {
    rac::stream::InFlightGuard guard(g_in_flight);
    CallbackSlot slot;
    uint64_t seq = 0;
    std::string request_id;
    {
        std::lock_guard<std::mutex> lock(g_mu());
        auto it = g_slots().find(handle);
        if (it == g_slots().end() || it->second.fn == nullptr)
            return;
        slot = it->second;
        seq = ++(it->second.seq);
        if (session_id != 0) {
            auto sit = g_sessions().find(session_id);
            if (sit == g_sessions().end() || sit->second.handle != handle ||
                sit->second.is_cancelled.load(std::memory_order_relaxed)) {
                return;
            }
            request_id = sit->second.request_id;
        }
        if (request_id.empty()) {
            for (const auto& [_, session] : g_sessions()) {
                if (session.handle == handle &&
                    !session.is_cancelled.load(std::memory_order_relaxed)) {
                    request_id = session.request_id;
                    break;
                }
            }
        }
    }

    thread_local runanywhere::v1::TTSStreamEvent proto_event;
    thread_local std::vector<uint8_t> scratch;

    proto_event.Clear();
    proto_event.set_seq(seq);
    proto_event.set_timestamp_us(now_us());
    if (!request_id.empty()) {
        proto_event.set_request_id(request_id);
    }
    proto_event.set_kind(kind);
    if (output) {
        *proto_event.mutable_output() = *output;
    }
    if (phoneme) {
        *proto_event.mutable_phoneme() = *phoneme;
    }
    if (speak_result) {
        *proto_event.mutable_speak_result() = *speak_result;
    }
    if (error_message && error_message[0] != '\0') {
        proto_event.set_error_message(error_message);
    }
    if (error_code != 0) {
        proto_event.set_error_code(error_code);
    }

    const size_t needed = static_cast<size_t>(proto_event.ByteSizeLong());
    if (scratch.size() < needed)
        scratch.resize(needed);
    if (!proto_event.SerializeToArray(scratch.data(), static_cast<int>(needed))) {
        RAC_LOG_WARNING("tts", "dispatch_tts_stream_event: SerializeToArray failed");
        return;
    }
    slot.fn(scratch.data(), needed, slot.user_data);
}

}  // namespace rac::tts
#endif  // RAC_HAVE_PROTOBUF
