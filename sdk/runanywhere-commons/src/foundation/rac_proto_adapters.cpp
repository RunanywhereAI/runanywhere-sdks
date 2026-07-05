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

// helpers

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

// STT language enum mapping
//
// Drift reconciliation: C ABI uses BCP-47 strings ("en", "en-US", "es-MX"),
// proto uses the STTLanguage enum. We strip the region tag and look up the
// base language code.

::runanywhere::v1::STTLanguage stt_language_from_string(const char* lang) {
    if (!lang || *lang == '\0')
        return ::runanywhere::v1::STT_LANGUAGE_UNSPECIFIED;
    // Take the first 2 chars, lowercase, ignore region after '-' / '_'.
    char base[3] = {0, 0, 0};
    base[0] = static_cast<char>(::tolower(static_cast<unsigned char>(lang[0])));
    if (lang[1] != '\0' && lang[1] != '-' && lang[1] != '_') {
        base[1] = static_cast<char>(::tolower(static_cast<unsigned char>(lang[1])));
    }
    static const std::unordered_map<std::string, ::runanywhere::v1::STTLanguage> table = {
        {"en", ::runanywhere::v1::STT_LANGUAGE_EN}, {"es", ::runanywhere::v1::STT_LANGUAGE_ES},
        {"fr", ::runanywhere::v1::STT_LANGUAGE_FR}, {"de", ::runanywhere::v1::STT_LANGUAGE_DE},
        {"zh", ::runanywhere::v1::STT_LANGUAGE_ZH}, {"ja", ::runanywhere::v1::STT_LANGUAGE_JA},
        {"ko", ::runanywhere::v1::STT_LANGUAGE_KO}, {"it", ::runanywhere::v1::STT_LANGUAGE_IT},
        {"pt", ::runanywhere::v1::STT_LANGUAGE_PT}, {"ar", ::runanywhere::v1::STT_LANGUAGE_AR},
        {"ru", ::runanywhere::v1::STT_LANGUAGE_RU}, {"hi", ::runanywhere::v1::STT_LANGUAGE_HI},
    };
    // Special case: literal "auto" -> AUTO.
    if (std::strncmp(lang, "auto", 4) == 0)
        return ::runanywhere::v1::STT_LANGUAGE_AUTO;
    auto it = table.find(base);
    return (it != table.end()) ? it->second : ::runanywhere::v1::STT_LANGUAGE_UNSPECIFIED;
}

const char* stt_language_to_string(::runanywhere::v1::STTLanguage e) {
    switch (e) {
        case ::runanywhere::v1::STT_LANGUAGE_AUTO:
            return "auto";
        case ::runanywhere::v1::STT_LANGUAGE_EN:
            return "en";
        case ::runanywhere::v1::STT_LANGUAGE_ES:
            return "es";
        case ::runanywhere::v1::STT_LANGUAGE_FR:
            return "fr";
        case ::runanywhere::v1::STT_LANGUAGE_DE:
            return "de";
        case ::runanywhere::v1::STT_LANGUAGE_ZH:
            return "zh";
        case ::runanywhere::v1::STT_LANGUAGE_JA:
            return "ja";
        case ::runanywhere::v1::STT_LANGUAGE_KO:
            return "ko";
        case ::runanywhere::v1::STT_LANGUAGE_IT:
            return "it";
        case ::runanywhere::v1::STT_LANGUAGE_PT:
            return "pt";
        case ::runanywhere::v1::STT_LANGUAGE_AR:
            return "ar";
        case ::runanywhere::v1::STT_LANGUAGE_RU:
            return "ru";
        case ::runanywhere::v1::STT_LANGUAGE_HI:
            return "hi";
        case ::runanywhere::v1::STT_LANGUAGE_UNSPECIFIED:
        default:
            return "";
    }
}

// Audio format enum mapping
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

// STT

bool rac_stt_options_from_proto(const ::runanywhere::v1::STTOptions& in, rac_stt_options_t* out) {
    if (!out)
        return false;
    *out = RAC_STT_OPTIONS_DEFAULT;
    if (in.language() == ::runanywhere::v1::STT_LANGUAGE_AUTO) {
        out->detect_language = RAC_TRUE;
        out->language = "auto";
    } else if (in.language() != ::runanywhere::v1::STT_LANGUAGE_UNSPECIFIED) {
        out->detect_language = RAC_FALSE;
        out->language = stt_language_to_string(in.language());
    }
    out->enable_punctuation = in.enable_punctuation() ? RAC_TRUE : RAC_FALSE;
    out->enable_diarization = in.enable_diarization() ? RAC_TRUE : RAC_FALSE;
    out->max_speakers = in.max_speakers();
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
    out->set_audio_length_ms(in->audio_length_ms);
    out->set_real_time_factor(in->real_time_factor);
    return true;
}

bool rac_transcription_metadata_from_proto(const ::runanywhere::v1::TranscriptionMetadata& in,
                                           rac_transcription_metadata_t* out) {
    if (!out)
        return false;
    out->model_id = copy_string(in.model_id());
    out->processing_time_ms = in.processing_time_ms();
    out->audio_length_ms = in.audio_length_ms();
    out->real_time_factor = in.real_time_factor();
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
    out->set_language(stt_language_from_string(in->detected_language));
    out->set_confidence(in->confidence);
    for (size_t i = 0; i < in->num_words; ++i) {
        rac_stt_word_to_proto(&in->words[i], out->add_words());
    }
    auto* meta = out->mutable_metadata();
    meta->set_processing_time_ms(in->processing_time_ms);
    return true;
}

// TTS

bool rac_tts_options_from_proto(const ::runanywhere::v1::TTSOptions& in, rac_tts_options_t* out) {
    if (!out)
        return false;
    *out = RAC_TTS_OPTIONS_DEFAULT;
    out->voice = copy_string(in.voice());
    if (!in.language_code().empty())
        out->language = copy_string(in.language_code());
    if (in.speaking_rate() > 0.0f)
        out->rate = in.speaking_rate();
    if (in.pitch() > 0.0f)
        out->pitch = in.pitch();
    if (in.volume() > 0.0f)
        out->volume = in.volume();
    out->audio_format = audio_format_from_proto(in.audio_format());
    out->use_ssml = in.enable_ssml() ? RAC_TRUE : RAC_FALSE;
    // sample_rate has no proto field on TTSOptions; keep default.
    return true;
}

bool rac_tts_phoneme_timestamp_to_proto(const rac_tts_phoneme_timestamp_t* in,
                                        ::runanywhere::v1::TTSPhonemeTimestamp* out) {
    if (!in || !out)
        return false;
    out->Clear();
    if (in->phoneme)
        out->set_phoneme(in->phoneme);
    out->set_start_ms(in->start_time_ms);
    out->set_end_ms(in->end_time_ms);
    return true;
}

bool rac_tts_phoneme_timestamp_from_proto(const ::runanywhere::v1::TTSPhonemeTimestamp& in,
                                          rac_tts_phoneme_timestamp_t* out) {
    if (!out)
        return false;
    out->phoneme = copy_string_required(in.phoneme());
    out->start_time_ms = in.start_ms();
    out->end_time_ms = in.end_ms();
    return true;
}

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
    out->set_character_count(in->character_count);
    // proto has audio_duration_ms; the C metadata struct has no such field
    // (it's on the parent rac_tts_output_t::duration_ms). Caller must set this
    // separately when emitting metadata-only TTSSpeakResult.
    return true;
}

bool rac_tts_synthesis_metadata_from_proto(const ::runanywhere::v1::TTSSynthesisMetadata& in,
                                           rac_tts_synthesis_metadata_t* out) {
    if (!out)
        return false;
    out->voice = copy_string(in.voice_id());
    out->language = copy_string(in.language_code());
    out->processing_time_ms = in.processing_time_ms();
    out->character_count = in.character_count();
    // Compute characters_per_second from processing_time_ms.
    out->characters_per_second = (in.processing_time_ms() > 0)
                                     ? static_cast<float>(in.character_count()) /
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
    meta->set_audio_duration_ms(in->duration_ms);
    return true;
}

// VAD

// VLM

bool rac_vlm_options_from_proto(const ::runanywhere::v1::VLMGenerationOptions& in,
                                rac_vlm_options_t* out, const char** out_prompt) {
    if (!out)
        return false;
    rac_vlm_options_t defaults = RAC_VLM_OPTIONS_DEFAULT;
    *out = defaults;
    if (in.max_tokens() > 0)
        out->max_tokens = in.max_tokens();
    if (in.temperature() > 0.0f)
        out->temperature = in.temperature();
    if (in.top_p() > 0.0f)
        out->top_p = in.top_p();
    out->streaming_enabled = in.streaming_enabled() ? RAC_TRUE : RAC_FALSE;
    if (in.max_image_size() > 0)
        out->max_image_size = in.max_image_size();
    if (in.n_threads() > 0)
        out->n_threads = in.n_threads();
    out->use_gpu = in.use_gpu() ? RAC_TRUE : RAC_FALSE;
    switch (in.model_family()) {
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

    // Carry request-owned strings into
    // rac_vlm_options_t so the llama.cpp VLM engine can actually apply
    // them. The engine reads options->system_prompt directly when building
    // the VLM prompt; stop_sequences is in the C ABI struct for future
    // enforcement parity with LLM.
    if (in.has_system_prompt() && !in.system_prompt().empty()) {
        out->system_prompt = rac_strdup(in.system_prompt().c_str());
    }
    const int stop_count = in.stop_sequences_size();
    if (stop_count > 0) {
        auto** arr =
            static_cast<const char**>(std::malloc(static_cast<size_t>(stop_count) * sizeof(char*)));
        if (arr) {
            size_t written = 0;
            for (int i = 0; i < stop_count; ++i) {
                const auto& seq = in.stop_sequences(i);
                if (seq.empty()) {
                    continue;
                }
                arr[written] = rac_strdup(seq.c_str());
                if (arr[written] != nullptr) {
                    ++written;
                }
            }
            if (written > 0) {
                out->stop_sequences = arr;
                out->num_stop_sequences = written;
            } else {
                std::free(static_cast<void*>(arr));
            }
        }
    }

    // Allocate a heap rac_vlm_chat_template_t and its owned
    // strings when the proto carries a custom_chat_template, and rac_strdup
    // image_marker_override. rac_vlm_options_free_owned releases both.
    if (in.has_custom_chat_template()) {
        const auto& proto_tpl = in.custom_chat_template();
        auto* tpl =
            static_cast<rac_vlm_chat_template_t*>(rac_alloc(sizeof(rac_vlm_chat_template_t)));
        if (tpl) {
            tpl->template_str = proto_tpl.template_text().empty()
                                    ? nullptr
                                    : rac_strdup(proto_tpl.template_text().c_str());
            tpl->image_marker = proto_tpl.has_image_marker()
                                    ? rac_strdup(proto_tpl.image_marker().c_str())
                                    : nullptr;
            tpl->default_system_prompt = proto_tpl.has_default_system_prompt()
                                             ? rac_strdup(proto_tpl.default_system_prompt().c_str())
                                             : nullptr;
            out->custom_chat_template = tpl;
        }
    }
    if (in.has_image_marker_override() && !in.image_marker_override().empty()) {
        out->image_marker_override = rac_strdup(in.image_marker_override().c_str());
    }

    // Extended sampling knobs round-trip into the C struct so
    // the llama.cpp VLM engine can honor them in configure_sampler(). All
    // scalars — no allocation needed; rac_vlm_options_free_owned is unaffected.
    if (in.top_k() > 0) {
        out->top_k = in.top_k();
    }
    if (in.seed() != 0) {
        out->seed = in.seed();
    }
    if (in.repetition_penalty() > 0.0f) {
        out->repetition_penalty = in.repetition_penalty();
    }
    if (in.min_p() > 0.0f) {
        out->min_p = in.min_p();
    }
    out->emit_image_embeddings = in.emit_image_embeddings() ? RAC_TRUE : RAC_FALSE;

    if (out_prompt) {
        *out_prompt = in.prompt().empty() ? nullptr : rac_strdup(in.prompt().c_str());
    }
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
    out->set_prompt_tokens(in->prompt_tokens);
    out->set_completion_tokens(in->completion_tokens);
    out->set_total_tokens(in->total_tokens);
    out->set_processing_time_ms(in->total_time_ms);
    out->set_tokens_per_second(in->tokens_per_second);
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
        // The `raw_rgb` oneof slot carries either RAW_RGB (3 B/px) or
        // RAW_RGBA (4 B/px); only `in.format()` distinguishes them. The
        // C ABI / mtmd backend speak RGB only, so downsample RGBA → RGB at
        // the proto boundary — mirrors RAVLMImage.fromUIImage's CGContext
        // path. Without this, a 4 B/px buffer reaches mtmd_bitmap_init,
        // which reads it as 3 B/px, overshoots the heap by 33%, and either
        // hallucinates or EXC_BAD_ACCESSes.
        out->format = RAC_VLM_IMAGE_FORMAT_RGB_PIXELS;
        const ::std::string& src = in.raw_rgb();
        if (in.format() == ::runanywhere::v1::VLM_IMAGE_FORMAT_RAW_RGBA) {
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
        } else {
            out->data_size = src.size();
            if (out->data_size > 0) {
                uint8_t* buf = static_cast<uint8_t*>(rac_alloc(out->data_size));
                std::memcpy(buf, src.data(), out->data_size);
                out->pixel_data = buf;
            }
        }
    } else if (in.has_base64()) {
        out->format = RAC_VLM_IMAGE_FORMAT_BASE64;
        out->base64_data = copy_string_required(in.base64());
        out->data_size = in.base64().size();
    } else if (in.has_encoded()) {
        // The C ABI has no carrier for encoded JPEG/PNG/WEBP containers.
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

// DIFFUSION

namespace {

rac_diffusion_scheduler_t diffusion_scheduler_from_proto(::runanywhere::v1::DiffusionScheduler p) {
    switch (p) {
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS:
            return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS;
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_DPMPP_2M:
            return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M;
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_DDIM:
            return RAC_DIFFUSION_SCHEDULER_DDIM;
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_DDPM:
            // No C carrier. Fold to the recommended default per drift notes.
            return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS;
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_EULER:
            return RAC_DIFFUSION_SCHEDULER_EULER;
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_EULER_A:
            return RAC_DIFFUSION_SCHEDULER_EULER_ANCESTRAL;
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_PNDM:
            return RAC_DIFFUSION_SCHEDULER_PNDM;
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_LMS:
            return RAC_DIFFUSION_SCHEDULER_LMS;
        case ::runanywhere::v1::DIFFUSION_SCHEDULER_LCM:
            // No C carrier. Fold to recommended default.
            return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS;
        default:
            return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS;
    }
}

rac_diffusion_mode_t diffusion_mode_from_proto(::runanywhere::v1::DiffusionMode p) {
    switch (p) {
        case ::runanywhere::v1::DIFFUSION_MODE_TEXT_TO_IMAGE:
            return RAC_DIFFUSION_MODE_TEXT_TO_IMAGE;
        case ::runanywhere::v1::DIFFUSION_MODE_IMAGE_TO_IMAGE:
            return RAC_DIFFUSION_MODE_IMAGE_TO_IMAGE;
        case ::runanywhere::v1::DIFFUSION_MODE_INPAINTING:
            return RAC_DIFFUSION_MODE_INPAINTING;
        default:
            return RAC_DIFFUSION_MODE_TEXT_TO_IMAGE;
    }
}

}  // namespace

bool rac_diffusion_options_from_proto(const ::runanywhere::v1::DiffusionGenerationOptions& in,
                                      rac_diffusion_options_t* out) {
    if (!out)
        return false;
    *out = RAC_DIFFUSION_OPTIONS_DEFAULT;
    out->prompt = copy_string(in.prompt());
    out->negative_prompt = copy_string(in.negative_prompt());
    if (in.width() > 0)
        out->width = in.width();
    if (in.height() > 0)
        out->height = in.height();
    if (in.num_inference_steps() > 0)
        out->steps = in.num_inference_steps();
    if (in.guidance_scale() > 0.0f)
        out->guidance_scale = in.guidance_scale();
    out->seed = in.seed();
    out->scheduler = diffusion_scheduler_from_proto(in.scheduler());
    out->mode = diffusion_mode_from_proto(in.mode());
    return true;
}

bool rac_diffusion_progress_to_proto(const rac_diffusion_progress_t* in,
                                     ::runanywhere::v1::DiffusionProgress* out) {
    if (!in || !out)
        return false;
    out->Clear();
    out->set_progress_percent(in->progress);
    out->set_current_step(in->current_step);
    out->set_total_steps(in->total_steps);
    if (in->stage)
        out->set_stage(in->stage);
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
    if (in->image_data && in->image_size > 0) {
        out->set_image_data(
            ::std::string(reinterpret_cast<const char*>(in->image_data), in->image_size));
        // Every shipped C-ABI diffusion engine (rac_diffusion_coreml,
        // rac_diffusion_platform) emits raw RGBA bytes — surface the media
        // type so SDKs can route through CGContext/Canvas instead of
        // Image(data:). A future backend that returns a PNG container must
        // override this on a parallel C-side carrier.
        out->set_image_media_type("image/raw-rgba");
    }
    out->set_width(in->width);
    out->set_height(in->height);
    out->set_seed_used(in->seed_used);
    out->set_total_time_ms(in->generation_time_ms);
    out->set_safety_flag(in->safety_flagged == RAC_TRUE);
    // No used_scheduler available on rac_diffusion_result_t — leave UNSPECIFIED.
    return true;
}

// LoRA

bool rac_lora_entry_to_proto(const rac_lora_entry_t* in,
                             ::runanywhere::v1::LoraAdapterCatalogEntry* out) {
    if (!in || !out)
        return false;
    out->Clear();
    if (in->id)
        out->set_id(in->id);
    if (in->name)
        out->set_name(in->name);
    if (in->description)
        out->set_description(in->description);
    if (in->download_url)
        out->set_url(in->download_url);
    if (in->filename)
        out->set_filename(in->filename);
    for (size_t i = 0; i < in->compatible_model_count; ++i) {
        if (in->compatible_model_ids[i]) {
            out->add_compatible_models(in->compatible_model_ids[i]);
        }
    }
    out->set_size_bytes(in->file_size);
    out->set_default_scale(in->default_scale > 0.0f ? in->default_scale : 1.0f);
    return true;
}

bool rac_lora_entry_from_proto(const ::runanywhere::v1::LoraAdapterCatalogEntry& in,
                               rac_lora_entry_t* out) {
    if (!out)
        return false;
    std::memset(out, 0, sizeof(*out));
    out->id = copy_string(in.id());
    out->name = copy_string(in.name());
    out->description = copy_string(in.description());
    out->download_url = copy_string(in.url());
    out->filename = copy_string(in.filename());
    out->file_size = in.size_bytes();
    out->default_scale = in.default_scale() > 0.0f ? in.default_scale() : 1.0f;
    if (in.compatible_models_size() > 0) {
        out->compatible_model_count = static_cast<size_t>(in.compatible_models_size());
        out->compatible_model_ids =
            static_cast<char**>(rac_alloc(sizeof(char*) * out->compatible_model_count));
        for (int i = 0; i < in.compatible_models_size(); ++i) {
            out->compatible_model_ids[i] = rac_strdup(in.compatible_models(i).c_str());
        }
    }
    return true;
}

// EMBEDDINGS

bool rac_embeddings_options_from_proto(const ::runanywhere::v1::EmbeddingsOptions& in,
                                       rac_embeddings_options_t* out) {
    if (!out)
        return false;
    *out = RAC_EMBEDDINGS_OPTIONS_DEFAULT;
    out->normalize = in.normalize() ? RAC_EMBEDDINGS_NORMALIZE_L2 : RAC_EMBEDDINGS_NORMALIZE_NONE;
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

// STORAGE

bool rac_device_storage_to_proto(const rac_device_storage_t* in,
                                 ::runanywhere::v1::DeviceStorageInfo* out) {
    if (!in || !out)
        return false;
    out->Clear();
    out->set_total_bytes(in->total_space);
    out->set_free_bytes(in->free_space);
    out->set_used_bytes(in->used_space);
    if (in->total_space > 0) {
        out->set_used_percent(static_cast<float>(in->used_space) /
                              static_cast<float>(in->total_space) * 100.0f);
    } else {
        out->set_used_percent(0.0f);
    }
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

// ERRORS

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
