/**
 * @file rac_proto_adapters.cpp
 * @brief Implementation of the C ABI <-> proto adapters declared
 *        in include/rac/foundation/rac_proto_adapters.h.
 *
 * Each adapter is a straightforward field-by-field copy. Drift between the
 * C struct and the proto message is reconciled inline (see the header for
 * the full table).
 *
 * Memory ownership rules (recap):
 *   - `_to_proto` writes into a caller-owned proto message; proto strings /
 *     bytes / repeated fields are populated via the standard `set_X` and
 *     `add_X` methods so proto's own arena/allocator owns those bytes.
 *   - `_from_proto` writes into a caller-owned C struct. Where the C side
 *     owns memory (char `*`, uint8_t `*` with size, T `*` with count), the
 *     adapter uses rac_alloc / rac_strdup so the caller can release with the
 *     matching `_free` helper (or rac_free + rac_free per element).
 *   - NULL inputs return false. We do NOT clear the destination on failure.
 */

// Pull in <cstddef> (and friends) BEFORE the protobuf-bearing header so newer
// libc++ on macOS finds ::ptrdiff_t before any protobuf header references it
// without a `std::` qualifier.
#include "rac/foundation/rac_proto_adapters.h"

// Per-modality adapter declarations now live in features/ headers.
// The .cpp pulls them in alongside the
// foundation header so it can define all adapter bodies.
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unordered_map>
#include <utility>

#include "rac/features/diffusion/rac_diffusion_proto_adapters.h"
#include "rac/features/embeddings/rac_embeddings_proto_adapters.h"
#include "rac/features/stt/rac_stt_proto_adapters.h"
#include "rac/features/tts/rac_tts_proto_adapters.h"
#include "rac/features/vad/rac_vad_proto_adapters.h"
#include "rac/features/vlm/rac_vlm_proto_adapters.h"

#ifdef RAC_HAVE_PROTOBUF

// The generated .pb.h files live here, NOT in the public
// header. The header forward-declares every proto class; the full message
// definitions are only needed inside the adapter implementation TU. Anyone
// editing this file should add new proto includes here, not in the header.
#include "diffusion_options.pb.h"
#include "embeddings_options.pb.h"
#include "errors.pb.h"
#include "llm_options.pb.h"
#include "lora_options.pb.h"
#include "rag.pb.h"
#include "storage_types.pb.h"
#include "stt_options.pb.h"
#include "tts_options.pb.h"
#include "vad_options.pb.h"
#include "vlm_options.pb.h"

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

namespace rac::foundation {

namespace {

// ---- helpers ---------------------------------------------------------------

// Copy a std::string into a freshly allocated C string. Empty std::string maps
// to nullptr so the C consumer can use the conventional "absent" sentinel.
char* copy_string(const ::std::string& s) {
    if (s.empty())
        return nullptr;
    return rac_strdup(s.c_str());
}

// Always returns a freshly allocated C string (even for empty std::string).
// Used when the C struct field is documented as "owned, never NULL".
char* copy_string_required(const ::std::string& s) {
    return rac_strdup(s.c_str());
}

uint8_t* copy_bytes(const ::std::string& bytes) {
    if (bytes.empty())
        return nullptr;
    auto* out = static_cast<uint8_t*>(rac_alloc(bytes.size()));
    if (out)
        std::memcpy(out, bytes.data(), bytes.size());
    return out;
}

// ---- Audio format enum mapping --------------------------------------------
// Both enums share the same ordering for the formats they overlap on. The C
// enum starts at PCM=0; proto starts at UNSPECIFIED=0 with PCM=1. Apply +1 / -1
// shift, with bounds checks.

::runanywhere::v1::AudioFormat audio_format_to_proto(rac_audio_format_enum_t c) {
    switch (c) {
        case RAC_AUDIO_FORMAT_PCM:
            return ::runanywhere::v1::AUDIO_FORMAT_PCM;
        case RAC_AUDIO_FORMAT_WAV:
            return ::runanywhere::v1::AUDIO_FORMAT_WAV;
        case RAC_AUDIO_FORMAT_MP3:
            return ::runanywhere::v1::AUDIO_FORMAT_MP3;
        case RAC_AUDIO_FORMAT_OPUS:
            return ::runanywhere::v1::AUDIO_FORMAT_OPUS;
        case RAC_AUDIO_FORMAT_AAC:
            return ::runanywhere::v1::AUDIO_FORMAT_AAC;
        case RAC_AUDIO_FORMAT_FLAC:
            return ::runanywhere::v1::AUDIO_FORMAT_FLAC;
    }
    return ::runanywhere::v1::AUDIO_FORMAT_UNSPECIFIED;
}

rac_audio_format_enum_t audio_format_from_proto(::runanywhere::v1::AudioFormat p) {
    switch (p) {
        case ::runanywhere::v1::AUDIO_FORMAT_PCM:
            return RAC_AUDIO_FORMAT_PCM;
        case ::runanywhere::v1::AUDIO_FORMAT_WAV:
            return RAC_AUDIO_FORMAT_WAV;
        case ::runanywhere::v1::AUDIO_FORMAT_MP3:
            return RAC_AUDIO_FORMAT_MP3;
        case ::runanywhere::v1::AUDIO_FORMAT_OPUS:
            return RAC_AUDIO_FORMAT_OPUS;
        case ::runanywhere::v1::AUDIO_FORMAT_AAC:
            return RAC_AUDIO_FORMAT_AAC;
        case ::runanywhere::v1::AUDIO_FORMAT_FLAC:
            return RAC_AUDIO_FORMAT_FLAC;
        case ::runanywhere::v1::AUDIO_FORMAT_PCM_S16LE:
            return RAC_AUDIO_FORMAT_PCM;
        // Container formats with no C enum equivalent fall through to PCM.
        default:
            return RAC_AUDIO_FORMAT_PCM;
    }
}

}  // namespace

// ===========================================================================
// STT
// ===========================================================================

bool rac_stt_options_from_proto(const ::runanywhere::v1::STTOptions& in, rac_stt_options_t* out) {
    if (!out)
        return false;
    *out = RAC_STT_OPTIONS_DEFAULT;
    // Borrows the proto's string storage; `in` must outlive `out` (adapter
    // contract — callers hold the request across the call).
    if (in.has_language() && !in.language().empty() && in.language() != "auto") {
        out->detect_language = RAC_FALSE;
        out->language = in.language().c_str();
    } else {
        out->detect_language = RAC_TRUE;
        out->language = nullptr;
    }
    out->enable_punctuation = in.enable_punctuation() ? RAC_TRUE : RAC_FALSE;
    out->enable_diarization = in.diarize() ? RAC_TRUE : RAC_FALSE;
    out->max_speakers = in.has_speakers_expected() ? in.speakers_expected() : 0;
    out->enable_timestamps = in.enable_word_timestamps() ? RAC_TRUE : RAC_FALSE;
    return true;
}

bool rac_stt_word_to_proto(const rac_stt_word_t* in, ::runanywhere::v1::WordTimestamp* out) {
    if (!in || !out)
        return false;
    out->Clear();
    if (in->text)
        out->set_word(in->text);
    out->set_start_ms(in->start_ms);
    out->set_end_ms(in->end_ms);
    out->set_confidence(in->confidence);
    return true;
}

bool rac_stt_word_from_proto(const ::runanywhere::v1::WordTimestamp& in, rac_stt_word_t* out) {
    if (!out)
        return false;
    out->text = copy_string_required(in.word());
    out->start_ms = in.start_ms();
    out->end_ms = in.end_ms();
    out->confidence = in.confidence();
    return true;
}

bool rac_transcription_metadata_to_proto(const rac_transcription_metadata_t* in,
                                         ::runanywhere::v1::TranscriptionMetadata* out) {
    if (!in || !out)
        return false;
    out->Clear();
    if (in->model_id)
        out->set_model_id(in->model_id);
    out->set_processing_time_ms(in->processing_time_ms);
    // audio_length_ms deleted from TranscriptionMetadata: STTOutput.duration_ms
    // is the one home for that value now (STTOutput is the message that
    // embeds this TranscriptionMetadata).
    return true;
}

bool rac_transcription_metadata_from_proto(const ::runanywhere::v1::TranscriptionMetadata& in,
                                           rac_transcription_metadata_t* out) {
    if (!out)
        return false;
    out->model_id = copy_string(in.model_id());
    out->processing_time_ms = in.processing_time_ms();
    out->audio_length_ms = 0;  // field deleted from the proto; no source left
    return true;
}

bool rac_transcription_alternative_to_proto(const rac_transcription_alternative_t* in,
                                            ::runanywhere::v1::TranscriptionAlternative* out) {
    if (!in || !out)
        return false;
    out->Clear();
    if (in->text)
        out->set_text(in->text);
    out->set_confidence(in->confidence);
    // C ABI has no per-word breakdown for alternatives; leave proto words empty.
    return true;
}

bool rac_transcription_alternative_from_proto(const ::runanywhere::v1::TranscriptionAlternative& in,
                                              rac_transcription_alternative_t* out) {
    if (!out)
        return false;
    out->text = copy_string_required(in.text());
    out->confidence = in.confidence();
    return true;
}

bool rac_stt_result_to_proto(const rac_stt_result_t* in, ::runanywhere::v1::STTOutput* out) {
    if (!in || !out)
        return false;
    out->Clear();
    if (in->text)
        out->set_text(in->text);
    if (in->detected_language && in->detected_language[0] != '\0') {
        out->set_language(in->detected_language);
    }
    out->set_confidence(in->confidence);
    for (size_t i = 0; i < in->num_words; ++i) {
        rac_stt_word_to_proto(&in->words[i], out->add_words());
    }
    auto* meta = out->mutable_metadata();
    meta->set_processing_time_ms(in->processing_time_ms);
    return true;
}

// ===========================================================================
// TTS
// ===========================================================================

bool rac_tts_options_from_proto(const ::runanywhere::v1::TTSOptions& in, rac_tts_options_t* out) {
    if (!out)
        return false;
    *out = RAC_TTS_OPTIONS_DEFAULT;
    out->voice = copy_string(in.voice());
    if (!in.language_code().empty())
        out->language = copy_string(in.language_code());
    if (in.speed() > 0.0f)
        out->rate = in.speed();
    if (in.pitch() > 0.0f)
        out->pitch = in.pitch();
    if (in.volume() > 0.0f)
        out->volume = in.volume();
    out->audio_format = audio_format_from_proto(in.audio_format());
    // enable_ssml deleted from TTSOptions -- no backend parses SSML. use_ssml
    // stays at RAC_TTS_OPTIONS_DEFAULT's value (false).
    // sample_rate has no proto field on TTSOptions; keep default.
    return true;
}

// rac_tts_phoneme_timestamp_to_proto / _from_proto deleted: TTSPhonemeTimestamp
// was deleted from tts_options.proto outright ("never produced, and the wrong
// granularity" -- see idl/tts_options.proto). No wire type remains to adapt.

bool rac_tts_synthesis_metadata_to_proto(const rac_tts_synthesis_metadata_t* in,
                                         ::runanywhere::v1::TTSSynthesisMetadata* out) {
    if (!in || !out)
        return false;
    out->Clear();
    if (in->voice)
        out->set_voice_id(in->voice);
    if (in->language)
        out->set_language_code(in->language);
    out->set_processing_time_ms(in->processing_time_ms);
    // character_count renamed to input_bytes (UTF-8 byte length, not codepoint
    // count -- see idl/tts_options.proto). audio_duration_ms was deleted
    // (reserved 5): it duplicated the parent rac_tts_output_t::duration_ms.
    out->set_input_bytes(in->character_count);
    return true;
}

bool rac_tts_synthesis_metadata_from_proto(const ::runanywhere::v1::TTSSynthesisMetadata& in,
                                           rac_tts_synthesis_metadata_t* out) {
    if (!out)
        return false;
    out->voice = copy_string(in.voice_id());
    out->language = copy_string(in.language_code());
    out->processing_time_ms = in.processing_time_ms();
    out->character_count = in.input_bytes();
    // Compute characters_per_second from processing_time_ms.
    out->characters_per_second = (in.processing_time_ms() > 0)
                                     ? static_cast<float>(in.input_bytes()) /
                                           (static_cast<float>(in.processing_time_ms()) / 1000.0f)
                                     : 0.0f;
    return true;
}

bool rac_tts_result_to_proto(const rac_tts_result_t* in, ::runanywhere::v1::TTSOutput* out) {
    if (!in || !out)
        return false;
    out->Clear();
    if (in->audio_data && in->audio_size > 0) {
        out->set_audio_data(
            ::std::string(static_cast<const char*>(in->audio_data), in->audio_size));
    }
    out->set_audio_format(audio_format_to_proto(in->audio_format));
    out->set_sample_rate(in->sample_rate);
    out->set_duration_ms(in->duration_ms);
    auto* meta = out->mutable_metadata();
    meta->set_processing_time_ms(in->processing_time_ms);
    // audio_duration_ms deleted from TTSSynthesisMetadata: it duplicated this
    // same TTSOutput.duration_ms set above.
    return true;
}

// ===========================================================================
// VAD
// ===========================================================================

// ===========================================================================
// VLM
// ===========================================================================

bool rac_vlm_options_from_proto(const ::runanywhere::v1::LLMGenerationOptions& in,
                                const ::runanywhere::v1::VLMVisionOptions* vision,
                                rac_vlm_options_t* out) {
    if (!out)
        return false;
    rac_vlm_options_t defaults = RAC_VLM_OPTIONS_DEFAULT;
    *out = defaults;
    auto fail = [&]() {
        rac_vlm_options_free_owned(out);
        return false;
    };
    // LLMGenerationOptions has explicit presence on every knob: ABSENT means
    // the annotated default applies (already loaded via RAC_VLM_OPTIONS_DEFAULT
    // above), and any value the caller sets -- including 0 -- is honoured
    // verbatim (idl/llm_options.proto).
    if (in.has_max_output_tokens())
        out->max_tokens = in.max_output_tokens();
    if (in.has_temperature())
        out->temperature = in.temperature();
    if (in.has_top_p())
        out->top_p = in.top_p();
    if (in.has_top_k())
        out->top_k = in.top_k();
    if (in.has_repeat_penalty())
        out->repetition_penalty = in.repeat_penalty();
    if (in.has_min_p())
        out->min_p = in.min_p();
    if (in.has_seed())
        out->seed = in.seed();

    // max_image_size, n_threads, use_gpu, and emit_image_embeddings had no
    // LLMGenerationOptions or VLMVisionOptions equivalent (max_image_size /
    // use_gpu were converted at the C boundary and read by no engine per
    // idl/vlm_options.proto's deletion note); leave them at the C default.

    if (vision != nullptr) {
        switch (vision->model_family()) {
            case ::runanywhere::v1::VLM_MODEL_FAMILY_QWEN2_VL:
                out->model_family = RAC_VLM_MODEL_FAMILY_QWEN2_VL;
                break;
            case ::runanywhere::v1::VLM_MODEL_FAMILY_SMOLVLM:
                out->model_family = RAC_VLM_MODEL_FAMILY_SMOLVLM;
                break;
            case ::runanywhere::v1::VLM_MODEL_FAMILY_LLAVA:
                out->model_family = RAC_VLM_MODEL_FAMILY_LLAVA;
                break;
            case ::runanywhere::v1::VLM_MODEL_FAMILY_CUSTOM:
                out->model_family = RAC_VLM_MODEL_FAMILY_CUSTOM;
                break;
            case ::runanywhere::v1::VLM_MODEL_FAMILY_AUTO:
            case ::runanywhere::v1::VLM_MODEL_FAMILY_UNSPECIFIED:
            default:
                out->model_family = RAC_VLM_MODEL_FAMILY_AUTO;
                break;
        }

        // Allocate a heap rac_vlm_chat_template_t and its owned
        // strings when the proto carries a custom_chat_template, and rac_strdup
        // image_marker_override. rac_vlm_options_free_owned releases both.
        if (vision->has_custom_chat_template()) {
            const auto& proto_tpl = vision->custom_chat_template();
            auto* tpl =
                static_cast<rac_vlm_chat_template_t*>(rac_alloc(sizeof(rac_vlm_chat_template_t)));
            if (!tpl) {
                return fail();
            }
            *tpl = {};
            out->custom_chat_template = tpl;
            if (!proto_tpl.template_text().empty()) {
                tpl->template_str = rac_strdup(proto_tpl.template_text().c_str());
                if (!tpl->template_str) {
                    return fail();
                }
            }
            if (proto_tpl.has_image_marker()) {
                tpl->image_marker = rac_strdup(proto_tpl.image_marker().c_str());
                if (!tpl->image_marker) {
                    return fail();
                }
            }
            if (proto_tpl.has_default_system_prompt()) {
                tpl->default_system_prompt = rac_strdup(proto_tpl.default_system_prompt().c_str());
                if (!tpl->default_system_prompt) {
                    return fail();
                }
            }
        }
        if (vision->has_image_marker_override() && !vision->image_marker_override().empty()) {
            out->image_marker_override = rac_strdup(vision->image_marker_override().c_str());
            if (!out->image_marker_override) {
                return fail();
            }
        }
    } else {
        out->model_family = RAC_VLM_MODEL_FAMILY_AUTO;
    }

    // Carry request-owned strings into
    // rac_vlm_options_t so the llama.cpp VLM engine can actually apply
    // them. The engine reads options->system_prompt directly when building
    // the VLM prompt; stop_sequences is in the C ABI struct for future
    // enforcement parity with LLM.
    if (in.has_system_prompt() && !in.system_prompt().empty()) {
        out->system_prompt = rac_strdup(in.system_prompt().c_str());
        if (!out->system_prompt) {
            return fail();
        }
    }
    const int stop_count = in.stop_sequences_size();
    if (stop_count > 0) {
        auto** arr =
            static_cast<const char**>(std::calloc(static_cast<size_t>(stop_count), sizeof(char*)));
        if (!arr) {
            return fail();
        }
        out->stop_sequences = arr;
        out->num_stop_sequences = static_cast<size_t>(stop_count);
        size_t written = 0;
        for (int i = 0; i < stop_count; ++i) {
            const auto& seq = in.stop_sequences(i);
            if (seq.empty()) {
                continue;
            }
            arr[written] = rac_strdup(seq.c_str());
            if (!arr[written]) {
                return fail();
            }
            ++written;
        }
        if (written > 0) {
            out->num_stop_sequences = written;
        } else {
            std::free(static_cast<void*>(arr));
            out->stop_sequences = nullptr;
            out->num_stop_sequences = 0;
        }
    }

    // emit_image_embeddings had no LLMGenerationOptions/VLMVisionOptions
    // equivalent after the merge; leave it at the C default (false, per
    // RAC_VLM_OPTIONS_DEFAULT).
    return true;
}

void rac_vlm_options_free_owned(rac_vlm_options_t* options) {
    if (!options) {
        return;
    }
    if (options->system_prompt) {
        rac_free(const_cast<char*>(options->system_prompt));
        options->system_prompt = nullptr;
    }
    if (options->stop_sequences && options->num_stop_sequences > 0) {
        for (size_t i = 0; i < options->num_stop_sequences; ++i) {
            if (options->stop_sequences[i]) {
                rac_free(const_cast<char*>(options->stop_sequences[i]));
            }
        }
        std::free(static_cast<void*>(const_cast<const char**>(options->stop_sequences)));
    }
    options->stop_sequences = nullptr;
    options->num_stop_sequences = 0;

    // Free adapter-owned chat-template + marker override
    // allocations produced by rac_vlm_options_from_proto.
    if (options->custom_chat_template) {
        auto* tpl = const_cast<rac_vlm_chat_template_t*>(options->custom_chat_template);
        if (tpl->template_str) {
            rac_free(const_cast<char*>(tpl->template_str));
            tpl->template_str = nullptr;
        }
        if (tpl->image_marker) {
            rac_free(const_cast<char*>(tpl->image_marker));
            tpl->image_marker = nullptr;
        }
        if (tpl->default_system_prompt) {
            rac_free(const_cast<char*>(tpl->default_system_prompt));
            tpl->default_system_prompt = nullptr;
        }
        rac_free(tpl);
        options->custom_chat_template = nullptr;
    }
    if (options->image_marker_override) {
        rac_free(const_cast<char*>(options->image_marker_override));
        options->image_marker_override = nullptr;
    }
}

bool rac_vlm_result_to_proto(const rac_vlm_result_t* in, ::runanywhere::v1::VLMResult* out) {
    if (!in || !out)
        return false;
    out->Clear();
    if (in->text)
        out->set_text(in->text);
    out->mutable_usage()->set_input_tokens(in->prompt_tokens);
    out->set_image_tokens(in->image_tokens);
    out->mutable_usage()->set_output_tokens(in->completion_tokens);
    out->mutable_usage()->set_total_tokens(in->total_tokens);
    // time_to_first_token_ms deleted from VLMResult: TokenUsage.ttft_ms is the
    // one canonical spelling now.
    out->mutable_usage()->set_ttft_ms(in->time_to_first_token_ms);
    out->set_image_encode_time_ms(in->image_encode_time_ms);
    // processing_time_ms renamed to total_time_ms.
    out->set_total_time_ms(in->total_time_ms);
    // TokenUsage has no tokens_per_second field; decode_tokens_per_second is
    // the decode-phase-only throughput this maps onto.
    out->mutable_usage()->set_decode_tokens_per_second(in->tokens_per_second);
    return true;
}

bool rac_vlm_image_from_proto(const ::runanywhere::v1::VLMImage& in, rac_vlm_image_t* out) {
    if (!out)
        return false;
    std::memset(out, 0, sizeof(*out));
    out->width = static_cast<uint32_t>(in.width());
    out->height = static_cast<uint32_t>(in.height());
    if (in.has_file_path()) {
        out->format = RAC_VLM_IMAGE_FORMAT_FILE_PATH;
        out->file_path = copy_string_required(in.file_path());
    } else if (in.has_raw_rgb()) {
        // 3 bytes/px, tightly packed -- no alpha to drop.
        out->format = RAC_VLM_IMAGE_FORMAT_RGB_PIXELS;
        const ::std::string& src = in.raw_rgb();
        out->data_size = src.size();
        if (out->data_size > 0) {
            uint8_t* buf = static_cast<uint8_t*>(rac_alloc(out->data_size));
            std::memcpy(buf, src.data(), out->data_size);
            out->pixel_data = buf;
        }
    } else if (in.has_raw_rgba()) {
        // raw_rgba is now its own oneof arm (4 B/px) instead of being
        // disambiguated out of raw_rgb via a deleted `format` field. The
        // C ABI / mtmd backend speak RGB only, so downsample RGBA → RGB at
        // the proto boundary — mirrors RAVLMImage.fromUIImage's CGContext
        // path. Without this, a 4 B/px buffer reaches mtmd_bitmap_init,
        // which reads it as 3 B/px, overshoots the heap by 33%, and either
        // hallucinates or EXC_BAD_ACCESSes.
        out->format = RAC_VLM_IMAGE_FORMAT_RGB_PIXELS;
        const ::std::string& src = in.raw_rgba();
        const size_t pixels = static_cast<size_t>(out->width) * out->height;
        if (pixels == 0 || src.size() < pixels * 4) {
            // Dimensions inconsistent with RGBA payload — refuse rather
            // than read past the buffer.
            return false;
        }
        out->data_size = pixels * 3;
        uint8_t* buf = static_cast<uint8_t*>(rac_alloc(out->data_size));
        const uint8_t* in_px = reinterpret_cast<const uint8_t*>(src.data());
        for (size_t i = 0; i < pixels; ++i) {
            buf[i * 3 + 0] = in_px[i * 4 + 0];
            buf[i * 3 + 1] = in_px[i * 4 + 1];
            buf[i * 3 + 2] = in_px[i * 4 + 2];
        }
        out->pixel_data = buf;
    } else if (in.has_base64()) {
        out->format = RAC_VLM_IMAGE_FORMAT_BASE64;
        out->base64_data = copy_string_required(in.base64());
        out->data_size = in.base64().size();
    } else if (in.has_data()) {
        // `data` (renamed from `encoded`) carries compressed JPEG/PNG/WEBP
        // container bytes. The C ABI has no carrier for those containers.
        // Coercing them into RGB_PIXELS would silently feed container bytes
        // into mtmd_bitmap_init (which expects width*height*3 raw pixels)
        // and crash the engine. Mirror the BASE64 hotspot fix — refuse at
        // the proto boundary so the caller sees a clean decoding error
        // instead of a backend crash. SDKs must decode containers to
        // RAW_RGB or supply a file path before calling C.
        return false;
    } else {
        // No source set — leave pointers NULL and pick FILE_PATH as the
        // safest default (matches RAC_VLM_IMAGE_FORMAT_FILE_PATH = 0).
        out->format = RAC_VLM_IMAGE_FORMAT_FILE_PATH;
    }
    return true;
}

// ===========================================================================
// DIFFUSION
// ===========================================================================

namespace {

rac_diffusion_scheduler_t diffusion_scheduler_from_proto(::runanywhere::v1::DiffusionScheduler p) {
    switch (p) {
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS:
            return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS;
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_DPMPP_2M:
            return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M;
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_DDIM:
            return RAC_DIFFUSION_SCHEDULER_DDIM;
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_EULER:
            return RAC_DIFFUSION_SCHEDULER_EULER;
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_EULER_A:
            return RAC_DIFFUSION_SCHEDULER_EULER_ANCESTRAL;
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_PNDM:
            return RAC_DIFFUSION_SCHEDULER_PNDM;
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_LMS:
            return RAC_DIFFUSION_SCHEDULER_LMS;
        // DDPM and LCM were deleted from the proto enum outright (no C
        // carrier existed for either); DPMPP_2M_SDE has no C carrier either
        // and falls through to the default below, same as UNSPECIFIED.
        default:
            return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS;
    }
}

// DiffusionMode enum was deleted: mode is now inferred from which of
// image/mask_image are present (see idl/diffusion_options.proto), never
// declared on the wire. Mirrors the proto's own inference rule: no image =
// text-to-image, image = image-to-image, image + mask_image = inpainting.
rac_diffusion_mode_t diffusion_mode_from_presence(bool has_image, bool has_mask) {
    if (has_image && has_mask)
        return RAC_DIFFUSION_MODE_INPAINTING;
    if (has_image)
        return RAC_DIFFUSION_MODE_IMAGE_TO_IMAGE;
    return RAC_DIFFUSION_MODE_TEXT_TO_IMAGE;
}

}  // namespace

namespace {

bool is_png_bytes(const std::string& bytes) {
    return bytes.size() >= 8 && static_cast<uint8_t>(bytes[0]) == 0x89 && bytes[1] == 'P' &&
           bytes[2] == 'N' && bytes[3] == 'G';
}

bool is_jpeg_bytes(const std::string& bytes) {
    return bytes.size() >= 3 && static_cast<uint8_t>(bytes[0]) == 0xFF &&
           static_cast<uint8_t>(bytes[1]) == 0xD8 && static_cast<uint8_t>(bytes[2]) == 0xFF;
}

bool encoded_image_media_type_matches(const std::string& bytes, const std::string& media_type) {
    if (media_type.empty()) {
        return is_png_bytes(bytes) || is_jpeg_bytes(bytes);
    }
    if (media_type == "image/png")
        return is_png_bytes(bytes);
    if (media_type == "image/jpeg" || media_type == "image/jpg")
        return is_jpeg_bytes(bytes);
    return false;
}

}  // namespace

bool rac_diffusion_options_from_proto(const ::runanywhere::v1::DiffusionGenerationOptions& in,
                                      rac_diffusion_options_t* out) {
    if (!out)
        return false;
    *out = RAC_DIFFUSION_OPTIONS_DEFAULT;
    out->prompt = copy_string(in.prompt());
    out->negative_prompt = copy_string(in.negative_prompt());
    auto fail = [&]() {
        rac_free(const_cast<char*>(out->prompt));
        rac_free(const_cast<char*>(out->negative_prompt));
        rac_free(const_cast<uint8_t*>(out->input_image_data));
        rac_free(const_cast<uint8_t*>(out->mask_data));
        *out = RAC_DIFFUSION_OPTIONS_DEFAULT;
        return false;
    };
    if ((!in.prompt().empty() && !out->prompt) ||
        (!in.negative_prompt().empty() && !out->negative_prompt))
        return fail();
    if (in.width() > 0)
        out->width = in.width();
    if (in.height() > 0)
        out->height = in.height();
    if (in.steps() > 0)
        out->steps = in.steps();
    if (in.guidance_scale() > 0.0f)
        out->guidance_scale = in.guidance_scale();
    // seed is now `optional int64`: absent means "pick a fresh random seed".
    // The C struct has no presence bit of its own (-1 is its documented
    // random sentinel); map absent -> -1, present -> the literal value
    // including 0.
    out->seed = in.has_seed() ? in.seed() : -1;
    out->scheduler = diffusion_scheduler_from_proto(in.scheduler());
    // image/mask_image (renamed from input_image/mask_image) are `optional
    // bytes`; mode is inferred from presence, not read off a deleted
    // DiffusionMode field.
    out->mode = diffusion_mode_from_presence(in.has_image(), in.has_mask_image());
    if (in.has_image() && !in.image().empty()) {
        // Shared across SDKs: reject non-PNG/JPEG payloads before engine dispatch
        // so Kotlin/Swift/Web inpaint helpers do not re-implement sniffing.
        if (!encoded_image_media_type_matches(in.image(), in.image_media_type()))
            return fail();
        out->input_image_data = copy_bytes(in.image());
        if (!out->input_image_data)
            return fail();
        out->input_image_size = in.image().size();
    }
    if (in.has_mask_image() && !in.mask_image().empty()) {
        if (!encoded_image_media_type_matches(in.mask_image(), in.mask_image_media_type()))
            return fail();
        out->mask_data = copy_bytes(in.mask_image());
        if (!out->mask_data)
            return fail();
        out->mask_size = in.mask_image().size();
    }
    if (out->mode == RAC_DIFFUSION_MODE_INPAINTING) {
        if (!out->input_image_data || out->input_image_size == 0 || !out->mask_data ||
            out->mask_size == 0) {
            return fail();
        }
    }
    if (out->mode == RAC_DIFFUSION_MODE_IMAGE_TO_IMAGE) {
        if (!out->input_image_data || out->input_image_size == 0) {
            return fail();
        }
    }
    // input_image_width/input_image_height were deleted from the proto
    // outright (dead fields, never read by any backend); leave the C
    // defaults (0). denoise_strength renamed to strength.
    if (in.strength() > 0.0f)
        out->denoise_strength = in.strength();
    // report_intermediate_images / progress_stride were deleted from the
    // proto outright; leave the C struct at RAC_DIFFUSION_OPTIONS_DEFAULT's
    // values (no per-request override exists on the wire anymore).
    return true;
}

bool rac_diffusion_progress_to_proto(const rac_diffusion_progress_t* in,
                                     ::runanywhere::v1::DiffusionProgress* out) {
    if (!in || !out)
        return false;
    out->Clear();
    // progress_percent and stage were deleted from DiffusionProgress outright
    // (current_step/total_steps already carry the same information).
    out->set_current_step(in->current_step);
    out->set_total_steps(in->total_steps);
    if (in->intermediate_image_data && in->intermediate_image_size > 0) {
        out->set_intermediate_image_data(
            ::std::string(reinterpret_cast<const char*>(in->intermediate_image_data),
                          in->intermediate_image_size));
    }
    return true;
}

bool rac_diffusion_result_to_proto(const rac_diffusion_result_t* in,
                                   ::runanywhere::v1::DiffusionResult* out) {
    if (!in || !out)
        return false;
    out->Clear();
    // DiffusionResult is now `repeated DiffusionImage images` + total_time_ms.
    // rac_diffusion_result_t is a single-image C struct, so commons emits
    // exactly one DiffusionImage entry until the C ABI grows a list.
    if (in->image_data && in->image_size > 0) {
        auto* image = out->add_images();
        image->set_data(
            ::std::string(reinterpret_cast<const char*>(in->image_data), in->image_size));
        image->set_width(in->width);
        image->set_height(in->height);
        image->set_seed_used(in->seed_used);
        image->set_safety_flag(in->safety_flagged == RAC_TRUE);
        // Every shipped C-ABI diffusion engine (rac_diffusion_coreml,
        // rac_diffusion_platform) emits raw RGBA bytes — surface the media
        // type so SDKs can route through CGContext/Canvas instead of
        // Image(data:). A future backend that returns a PNG container must
        // override this on a parallel C-side carrier.
        image->set_media_type("image/raw-rgba");
    }
    out->set_total_time_ms(in->generation_time_ms);
    return true;
}

// ===========================================================================
// LoRA
// ===========================================================================

bool rac_lora_entry_to_proto(const rac_lora_entry_t* in,
                             ::runanywhere::v1::LoraAdapterCatalogEntry* out) {
    if (!in || !out)
        return false;
    out->Clear();
    if (in->id)
        out->set_id(in->id);
    if (in->name)
        out->set_name(in->name);
    for (size_t i = 0; i < in->compatible_model_count; ++i) {
        if (in->compatible_model_ids[i]) {
            out->add_compatible_models(in->compatible_model_ids[i]);
        }
    }
    out->set_default_scale(in->default_scale);
    // description/url/filename/size_bytes were deleted from
    // LoraAdapterCatalogEntry outright (idl/lora_options.proto -- adapter
    // files are now acquired through the models domain's download/import
    // verbs, not tracked here). download_url/filename/file_size stay on the
    // C struct for that layer but have no proto counterpart to write into.
    // local_path (non-empty = downloaded) has no rac_lora_entry_t equivalent
    // either; it is populated by the registry directly, not this adapter.
    return true;
}

bool rac_lora_entry_from_proto(const ::runanywhere::v1::LoraAdapterCatalogEntry& in,
                               rac_lora_entry_t* out) {
    if (!out)
        return false;
    std::memset(out, 0, sizeof(*out));
    out->id = copy_string(in.id());
    if (!in.id().empty() && !out->id) {
        return false;
    }
    out->name = copy_string(in.name());
    if (!in.name().empty() && !out->name) {
        return false;
    }
    // Preserve an explicit catalog 0.0; only absent default_scale falls back.
    out->default_scale = in.has_default_scale() ? in.default_scale() : 1.0f;
    if (in.compatible_models_size() > 0) {
        out->compatible_model_count = static_cast<size_t>(in.compatible_models_size());
        out->compatible_model_ids =
            static_cast<char**>(std::calloc(out->compatible_model_count, sizeof(char*)));
        if (!out->compatible_model_ids) {
            // Keep the count consistent with the null pointer so the entry never
            // advertises elements that were never allocated.
            out->compatible_model_count = 0;
            return false;
        }
        for (int i = 0; i < in.compatible_models_size(); ++i) {
            out->compatible_model_ids[i] = rac_strdup(in.compatible_models(i).c_str());
            if (!out->compatible_model_ids[i]) {
                return false;
            }
        }
    }
    return true;
}

// ===========================================================================
// EMBEDDINGS
// ===========================================================================

bool rac_embeddings_options_from_proto(const ::runanywhere::v1::EmbeddingsOptions& in,
                                       rac_embeddings_options_t* out) {
    if (!out)
        return false;
    *out = RAC_EMBEDDINGS_OPTIONS_DEFAULT;

    // EmbeddingsOptions.normalize is a plain proto3 bool with no unset sentinel;
    // the backends default to L2 unit vectors (EmbeddingsConfiguration.normalize
    // rac_default = true), so an explicit true and the proto default both resolve
    // to L2 here. Disabling normalization is a component-configuration concern.
    out->normalize = RAC_EMBEDDINGS_NORMALIZE_L2;

    switch (in.pooling()) {
        case ::runanywhere::v1::EMBEDDINGS_POOLING_STRATEGY_UNSPECIFIED:
            out->pooling = -1;
            break;
        case ::runanywhere::v1::EMBEDDINGS_POOLING_STRATEGY_MEAN:
            out->pooling = RAC_EMBEDDINGS_POOLING_MEAN;
            break;
        case ::runanywhere::v1::EMBEDDINGS_POOLING_STRATEGY_CLS:
            out->pooling = RAC_EMBEDDINGS_POOLING_CLS;
            break;
        case ::runanywhere::v1::EMBEDDINGS_POOLING_STRATEGY_LAST:
            out->pooling = RAC_EMBEDDINGS_POOLING_LAST;
            break;
        default:
            return false;
    }

    if (in.n_threads() < 0) {
        return false;
    }
    out->n_threads = in.n_threads();
    out->truncate = in.has_truncate() ? (in.truncate() ? 1 : 0) : -1;
    if (in.has_batch_size()) {
        if (in.batch_size() <= 0 || in.batch_size() > RAC_EMBEDDINGS_MAX_BATCH_SIZE) {
            return false;
        }
        out->batch_size = in.batch_size();
    }
    return true;
}

bool rac_embedding_vector_to_proto(const rac_embedding_vector_t* in,
                                   ::runanywhere::v1::EmbeddingVector* out) {
    if (!in || !out)
        return false;
    out->Clear();
    for (size_t i = 0; i < in->dimension; ++i) {
        out->add_values(in->data[i]);
    }
    return true;
}

bool rac_embedding_vector_from_proto(const ::runanywhere::v1::EmbeddingVector& in,
                                     rac_embedding_vector_t* out) {
    if (!out)
        return false;
    std::memset(out, 0, sizeof(*out));
    out->dimension = static_cast<size_t>(in.values_size());
    if (out->dimension > 0) {
        out->data = static_cast<float*>(rac_alloc(sizeof(float) * out->dimension));
        for (int i = 0; i < in.values_size(); ++i) {
            out->data[i] = in.values(i);
        }
    }
    return true;
}

bool rac_embeddings_result_to_proto(const rac_embeddings_result_t* in,
                                    ::runanywhere::v1::EmbeddingsResult* out) {
    if (!in || !out)
        return false;
    out->Clear();
    for (size_t i = 0; i < in->num_embeddings; ++i) {
        rac_embedding_vector_to_proto(&in->embeddings[i], out->add_vectors());
    }
    out->set_dimension(static_cast<int32_t>(in->dimension));
    out->set_processing_time_ms(in->processing_time_ms);
    out->set_tokens_used(in->total_tokens);
    return true;
}

// ===========================================================================
// STORAGE
// ===========================================================================

bool rac_device_storage_to_proto(const rac_device_storage_t* in,
                                 ::runanywhere::v1::DeviceStorageInfo* out) {
    if (!in || !out)
        return false;
    out->Clear();
    out->set_total_bytes(in->total_space);
    out->set_free_bytes(in->free_space);
    out->set_used_bytes(in->used_space);
    // used_percent deleted from DeviceStorageInfo: derivable from
    // used_bytes/total_bytes, so callers compute it rather than reading a
    // second copy off the wire.
    return true;
}

bool rac_device_storage_from_proto(const ::runanywhere::v1::DeviceStorageInfo& in,
                                   rac_device_storage_t* out) {
    if (!out)
        return false;
    out->total_space = in.total_bytes();
    out->free_space = in.free_bytes();
    out->used_space = in.used_bytes();
    return true;
}

bool rac_app_storage_to_proto(const rac_app_storage_t* in, ::runanywhere::v1::AppStorageInfo* out) {
    if (!in || !out)
        return false;
    out->Clear();
    out->set_documents_bytes(in->documents_size);
    out->set_cache_bytes(in->cache_size);
    out->set_app_support_bytes(in->app_support_size);
    out->set_total_bytes(in->total_size);
    return true;
}

bool rac_app_storage_from_proto(const ::runanywhere::v1::AppStorageInfo& in,
                                rac_app_storage_t* out) {
    if (!out)
        return false;
    out->documents_size = in.documents_bytes();
    out->cache_size = in.cache_bytes();
    out->app_support_size = in.app_support_bytes();
    out->total_size = in.total_bytes();
    return true;
}

bool rac_model_storage_metrics_to_proto(const rac_model_storage_metrics_t* in,
                                        ::runanywhere::v1::ModelStorageMetrics* out) {
    if (!in || !out)
        return false;
    out->Clear();
    if (in->model_id)
        out->set_model_id(in->model_id);
    out->set_size_on_disk_bytes(in->size_on_disk);
    return true;
}

bool rac_model_storage_metrics_from_proto(const ::runanywhere::v1::ModelStorageMetrics& in,
                                          rac_model_storage_metrics_t* out) {
    if (!out)
        return false;
    std::memset(out, 0, sizeof(*out));
    out->model_id = copy_string(in.model_id());
    out->size_on_disk = in.size_on_disk_bytes();
    return true;
}

// ===========================================================================
// ERRORS
// ===========================================================================

::runanywhere::v1::ErrorCategory rac_result_to_proto_category(rac_result_t code) {
    // Non-negative codes (success / invalid) carry no error category.
    if (code >= 0)
        return ::runanywhere::v1::ERROR_CATEGORY_UNSPECIFIED;
    if (code <= -150 && code >= -179)
        return ::runanywhere::v1::ERROR_CATEGORY_NETWORK;
    if (code <= -250 && code >= -279)
        return ::runanywhere::v1::ERROR_CATEGORY_VALIDATION;
    if (code <= -110 && code >= -129)
        return ::runanywhere::v1::ERROR_CATEGORY_MODEL;
    if ((code <= -180 && code >= -219) || (code <= -280 && code >= -299))
        return ::runanywhere::v1::ERROR_CATEGORY_IO;
    if (code <= -320 && code >= -329)
        return ::runanywhere::v1::ERROR_CATEGORY_AUTH;
    if (code <= -100 && code >= -109)
        return ::runanywhere::v1::ERROR_CATEGORY_CONFIGURATION;
    if ((code <= -230 && code >= -249) || (code <= -300 && code >= -319))
        return ::runanywhere::v1::ERROR_CATEGORY_COMPONENT;
    // Any other negative code is an unmapped error -> INTERNAL (canonical
    // fallback; rac_error_proto.cpp previously returned UNSPECIFIED here, the
    // drift this consolidation fixes).
    return ::runanywhere::v1::ERROR_CATEGORY_INTERNAL;
}

::runanywhere::v1::ErrorCategory rac_category_to_proto(rac_error_category_t category) {
    switch (category) {
        case RAC_CATEGORY_GENERAL:
            return ::runanywhere::v1::ERROR_CATEGORY_INTERNAL;
        case RAC_CATEGORY_STT:
        case RAC_CATEGORY_TTS:
        case RAC_CATEGORY_LLM:
        case RAC_CATEGORY_VAD:
        case RAC_CATEGORY_VLM:
        case RAC_CATEGORY_SPEAKER_DIARIZATION:
        case RAC_CATEGORY_WAKE_WORD:
        case RAC_CATEGORY_VOICE_AGENT:
        case RAC_CATEGORY_RUNTIME:
            return ::runanywhere::v1::ERROR_CATEGORY_COMPONENT;
        case RAC_CATEGORY_DOWNLOAD:
        case RAC_CATEGORY_NETWORK:
            return ::runanywhere::v1::ERROR_CATEGORY_NETWORK;
        case RAC_CATEGORY_FILE_MANAGEMENT:
            return ::runanywhere::v1::ERROR_CATEGORY_IO;
        case RAC_CATEGORY_AUTHENTICATION:
        case RAC_CATEGORY_SECURITY:
            return ::runanywhere::v1::ERROR_CATEGORY_AUTH;
    }
    return ::runanywhere::v1::ERROR_CATEGORY_UNSPECIFIED;
}

rac_error_category_t rac_proto_to_category(::runanywhere::v1::ErrorCategory category) {
    switch (category) {
        case ::runanywhere::v1::ERROR_CATEGORY_NETWORK:
            return RAC_CATEGORY_NETWORK;
        case ::runanywhere::v1::ERROR_CATEGORY_VALIDATION:
            return RAC_CATEGORY_GENERAL;
        case ::runanywhere::v1::ERROR_CATEGORY_MODEL:
            return RAC_CATEGORY_GENERAL;
        case ::runanywhere::v1::ERROR_CATEGORY_COMPONENT:
            return RAC_CATEGORY_RUNTIME;
        case ::runanywhere::v1::ERROR_CATEGORY_IO:
            return RAC_CATEGORY_FILE_MANAGEMENT;
        case ::runanywhere::v1::ERROR_CATEGORY_AUTH:
            return RAC_CATEGORY_AUTHENTICATION;
        case ::runanywhere::v1::ERROR_CATEGORY_INTERNAL:
        case ::runanywhere::v1::ERROR_CATEGORY_CONFIGURATION:
        case ::runanywhere::v1::ERROR_CATEGORY_UNSPECIFIED:
        default:
            return RAC_CATEGORY_GENERAL;
    }
}

}  // namespace rac::foundation

#endif  // RAC_HAVE_PROTOBUF
