/**
 * @file rac_proto_adapters.cpp
 * @brief Phase C6 — implementation of the C ABI <-> proto adapters declared
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
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <string>
#include <unordered_map>
#include <utility>

#include "rac/foundation/rac_proto_adapters.h"

#ifdef RAC_HAVE_PROTOBUF

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

namespace rac::foundation {

namespace {

// ---- helpers ---------------------------------------------------------------

// Copy a std::string into a freshly allocated C string. Empty std::string maps
// to nullptr so the C consumer can use the conventional "absent" sentinel.
char* copy_string(const ::std::string& s) {
    if (s.empty()) return nullptr;
    return rac_strdup(s.c_str());
}

// Always returns a freshly allocated C string (even for empty std::string).
// Used when the C struct field is documented as "owned, never NULL".
char* copy_string_required(const ::std::string& s) {
    return rac_strdup(s.c_str());
}

// Set proto string from possibly-NULL C string. Empty / NULL -> empty proto.
template <class Setter>
void set_proto_string_or_empty(Setter setter, const char* src) {
    setter(src ? src : "");
}

// ---- STT language enum mapping --------------------------------------------
//
// Drift reconciliation: C ABI uses BCP-47 strings ("en", "en-US", "es-MX"),
// proto uses the STTLanguage enum. We strip the region tag and look up the
// base language code.

::runanywhere::v1::STTLanguage stt_language_from_string(const char* lang) {
    if (!lang || !*lang) return ::runanywhere::v1::STT_LANGUAGE_UNSPECIFIED;
    // Take the first 2 chars, lowercase, ignore region after '-' / '_'.
    char base[3] = {0, 0, 0};
    base[0] = static_cast<char>(::tolower(static_cast<unsigned char>(lang[0])));
    if (lang[1] && lang[1] != '-' && lang[1] != '_') {
        base[1] = static_cast<char>(::tolower(static_cast<unsigned char>(lang[1])));
    }
    static const std::unordered_map<std::string, ::runanywhere::v1::STTLanguage> table = {
        {"en", ::runanywhere::v1::STT_LANGUAGE_EN},
        {"es", ::runanywhere::v1::STT_LANGUAGE_ES},
        {"fr", ::runanywhere::v1::STT_LANGUAGE_FR},
        {"de", ::runanywhere::v1::STT_LANGUAGE_DE},
        {"zh", ::runanywhere::v1::STT_LANGUAGE_ZH},
        {"ja", ::runanywhere::v1::STT_LANGUAGE_JA},
        {"ko", ::runanywhere::v1::STT_LANGUAGE_KO},
        {"it", ::runanywhere::v1::STT_LANGUAGE_IT},
        {"pt", ::runanywhere::v1::STT_LANGUAGE_PT},
        {"ar", ::runanywhere::v1::STT_LANGUAGE_AR},
        {"ru", ::runanywhere::v1::STT_LANGUAGE_RU},
        {"hi", ::runanywhere::v1::STT_LANGUAGE_HI},
    };
    // Special case: literal "auto" -> AUTO.
    if (std::strncmp(lang, "auto", 4) == 0)
        return ::runanywhere::v1::STT_LANGUAGE_AUTO;
    auto it = table.find(base);
    return (it != table.end()) ? it->second : ::runanywhere::v1::STT_LANGUAGE_UNSPECIFIED;
}

const char* stt_language_to_string(::runanywhere::v1::STTLanguage e) {
    switch (e) {
        case ::runanywhere::v1::STT_LANGUAGE_AUTO: return "auto";
        case ::runanywhere::v1::STT_LANGUAGE_EN:   return "en";
        case ::runanywhere::v1::STT_LANGUAGE_ES:   return "es";
        case ::runanywhere::v1::STT_LANGUAGE_FR:   return "fr";
        case ::runanywhere::v1::STT_LANGUAGE_DE:   return "de";
        case ::runanywhere::v1::STT_LANGUAGE_ZH:   return "zh";
        case ::runanywhere::v1::STT_LANGUAGE_JA:   return "ja";
        case ::runanywhere::v1::STT_LANGUAGE_KO:   return "ko";
        case ::runanywhere::v1::STT_LANGUAGE_IT:   return "it";
        case ::runanywhere::v1::STT_LANGUAGE_PT:   return "pt";
        case ::runanywhere::v1::STT_LANGUAGE_AR:   return "ar";
        case ::runanywhere::v1::STT_LANGUAGE_RU:   return "ru";
        case ::runanywhere::v1::STT_LANGUAGE_HI:   return "hi";
        case ::runanywhere::v1::STT_LANGUAGE_UNSPECIFIED:
        default:                                   return "";
    }
}

// ---- Audio format enum mapping --------------------------------------------
// Both enums share the same ordering for the formats they overlap on. The C
// enum starts at PCM=0; proto starts at UNSPECIFIED=0 with PCM=1. Apply +1 / -1
// shift, with bounds checks.

::runanywhere::v1::AudioFormat audio_format_to_proto(rac_audio_format_enum_t c) {
    switch (c) {
        case RAC_AUDIO_FORMAT_PCM:  return ::runanywhere::v1::AUDIO_FORMAT_PCM;
        case RAC_AUDIO_FORMAT_WAV:  return ::runanywhere::v1::AUDIO_FORMAT_WAV;
        case RAC_AUDIO_FORMAT_MP3:  return ::runanywhere::v1::AUDIO_FORMAT_MP3;
        case RAC_AUDIO_FORMAT_OPUS: return ::runanywhere::v1::AUDIO_FORMAT_OPUS;
        case RAC_AUDIO_FORMAT_AAC:  return ::runanywhere::v1::AUDIO_FORMAT_AAC;
        case RAC_AUDIO_FORMAT_FLAC: return ::runanywhere::v1::AUDIO_FORMAT_FLAC;
    }
    return ::runanywhere::v1::AUDIO_FORMAT_UNSPECIFIED;
}

rac_audio_format_enum_t audio_format_from_proto(::runanywhere::v1::AudioFormat p) {
    switch (p) {
        case ::runanywhere::v1::AUDIO_FORMAT_PCM:       return RAC_AUDIO_FORMAT_PCM;
        case ::runanywhere::v1::AUDIO_FORMAT_WAV:       return RAC_AUDIO_FORMAT_WAV;
        case ::runanywhere::v1::AUDIO_FORMAT_MP3:       return RAC_AUDIO_FORMAT_MP3;
        case ::runanywhere::v1::AUDIO_FORMAT_OPUS:      return RAC_AUDIO_FORMAT_OPUS;
        case ::runanywhere::v1::AUDIO_FORMAT_AAC:       return RAC_AUDIO_FORMAT_AAC;
        case ::runanywhere::v1::AUDIO_FORMAT_FLAC:      return RAC_AUDIO_FORMAT_FLAC;
        case ::runanywhere::v1::AUDIO_FORMAT_PCM_S16LE: return RAC_AUDIO_FORMAT_PCM;
        // Container formats with no C enum equivalent fall through to PCM.
        default:                                        return RAC_AUDIO_FORMAT_PCM;
    }
}

// ---- VAD frame_length seconds <-> ms --------------------------------------
int32_t frame_seconds_to_ms(float seconds) {
    if (seconds <= 0.0f) return 0;
    long ms = static_cast<long>(std::lround(seconds * 1000.0));
    if (ms < 0) ms = 0;
    if (ms > 100000) ms = 100000;
    return static_cast<int32_t>(ms);
}

float frame_ms_to_seconds(int32_t ms) {
    if (ms <= 0) return RAC_VAD_DEFAULT_FRAME_LENGTH;
    return static_cast<float>(ms) / 1000.0f;
}

}  // namespace

// ===========================================================================
// STT
// ===========================================================================

bool rac_stt_config_to_proto(const rac_stt_config_t* in,
                             ::runanywhere::v1::STTConfiguration* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->model_id) out->set_model_id(in->model_id);
    out->set_language(stt_language_from_string(in->language));
    out->set_sample_rate(in->sample_rate);
    // C ABI has no enable_vad — leave proto default (false).
    out->set_enable_vad(false);
    // C ABI has no audio_format on STTConfig — keep PCM as the canonical default.
    out->set_audio_format(::runanywhere::v1::AUDIO_FORMAT_PCM);
    return true;
}

bool rac_stt_config_from_proto(const ::runanywhere::v1::STTConfiguration& in,
                               rac_stt_config_t* out) {
    if (!out) return false;
    *out = RAC_STT_CONFIG_DEFAULT;
    out->model_id = copy_string(in.model_id());
    out->language = rac_strdup(stt_language_to_string(in.language()));
    if (in.sample_rate() > 0) out->sample_rate = in.sample_rate();
    // enable_vad and audio_format on the proto have no C ABI counterparts in
    // rac_stt_config_t — drop them silently.
    return true;
}

bool rac_stt_options_to_proto(const rac_stt_options_t* in,
                              ::runanywhere::v1::STTOptions* out) {
    if (!in || !out) return false;
    out->Clear();
    // detect_language collapses to STT_LANGUAGE_AUTO.
    if (in->detect_language) {
        out->set_language(::runanywhere::v1::STT_LANGUAGE_AUTO);
    } else {
        out->set_language(stt_language_from_string(in->language));
    }
    out->set_enable_punctuation(in->enable_punctuation == RAC_TRUE);
    out->set_enable_diarization(in->enable_diarization == RAC_TRUE);
    out->set_max_speakers(in->max_speakers);
    out->set_enable_word_timestamps(in->enable_timestamps == RAC_TRUE);
    out->set_beam_size(0);  // C ABI has no beam_size — leave at backend default.
    return true;
}

bool rac_stt_options_from_proto(const ::runanywhere::v1::STTOptions& in,
                                rac_stt_options_t* out) {
    if (!out) return false;
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

bool rac_stt_word_to_proto(const rac_stt_word_t* in,
                           ::runanywhere::v1::WordTimestamp* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->text) out->set_word(in->text);
    out->set_start_ms(in->start_ms);
    out->set_end_ms(in->end_ms);
    out->set_confidence(in->confidence);
    return true;
}

bool rac_stt_word_from_proto(const ::runanywhere::v1::WordTimestamp& in,
                             rac_stt_word_t* out) {
    if (!out) return false;
    out->text = copy_string_required(in.word());
    out->start_ms = in.start_ms();
    out->end_ms = in.end_ms();
    out->confidence = in.confidence();
    return true;
}

bool rac_transcription_metadata_to_proto(const rac_transcription_metadata_t* in,
                                         ::runanywhere::v1::TranscriptionMetadata* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->model_id) out->set_model_id(in->model_id);
    out->set_processing_time_ms(in->processing_time_ms);
    out->set_audio_length_ms(in->audio_length_ms);
    out->set_real_time_factor(in->real_time_factor);
    return true;
}

bool rac_transcription_metadata_from_proto(
    const ::runanywhere::v1::TranscriptionMetadata& in,
    rac_transcription_metadata_t* out) {
    if (!out) return false;
    out->model_id = copy_string(in.model_id());
    out->processing_time_ms = in.processing_time_ms();
    out->audio_length_ms = in.audio_length_ms();
    out->real_time_factor = in.real_time_factor();
    return true;
}

bool rac_transcription_alternative_to_proto(
    const rac_transcription_alternative_t* in,
    ::runanywhere::v1::TranscriptionAlternative* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->text) out->set_text(in->text);
    out->set_confidence(in->confidence);
    // C ABI has no per-word breakdown for alternatives; leave proto words empty.
    return true;
}

bool rac_transcription_alternative_from_proto(
    const ::runanywhere::v1::TranscriptionAlternative& in,
    rac_transcription_alternative_t* out) {
    if (!out) return false;
    out->text = copy_string_required(in.text());
    out->confidence = in.confidence();
    return true;
}

bool rac_stt_output_to_proto(const rac_stt_output_t* in,
                             ::runanywhere::v1::STTOutput* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->text) out->set_text(in->text);
    out->set_language(stt_language_from_string(in->detected_language));
    out->set_confidence(in->confidence);
    for (size_t i = 0; i < in->num_word_timestamps; ++i) {
        rac_stt_word_to_proto(&in->word_timestamps[i], out->add_words());
    }
    for (size_t i = 0; i < in->num_alternatives; ++i) {
        rac_transcription_alternative_to_proto(&in->alternatives[i],
                                               out->add_alternatives());
    }
    rac_transcription_metadata_to_proto(&in->metadata, out->mutable_metadata());
    // proto STTOutput has no timestamp_ms — drop in->timestamp_ms.
    return true;
}

bool rac_stt_output_from_proto(const ::runanywhere::v1::STTOutput& in,
                               rac_stt_output_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    out->text = copy_string_required(in.text());
    out->confidence = in.confidence();
    if (in.language() != ::runanywhere::v1::STT_LANGUAGE_UNSPECIFIED) {
        out->detected_language = rac_strdup(stt_language_to_string(in.language()));
    }
    if (in.words_size() > 0) {
        out->num_word_timestamps = static_cast<size_t>(in.words_size());
        out->word_timestamps = static_cast<rac_stt_word_t*>(
            rac_alloc(sizeof(rac_stt_word_t) * out->num_word_timestamps));
        for (int i = 0; i < in.words_size(); ++i) {
            rac_stt_word_from_proto(in.words(i), &out->word_timestamps[i]);
        }
    }
    if (in.alternatives_size() > 0) {
        out->num_alternatives = static_cast<size_t>(in.alternatives_size());
        out->alternatives = static_cast<rac_transcription_alternative_t*>(
            rac_alloc(sizeof(rac_transcription_alternative_t) * out->num_alternatives));
        for (int i = 0; i < in.alternatives_size(); ++i) {
            rac_transcription_alternative_from_proto(in.alternatives(i),
                                                      &out->alternatives[i]);
        }
    }
    if (in.has_metadata()) {
        rac_transcription_metadata_from_proto(in.metadata(), &out->metadata);
    }
    out->timestamp_ms = 0;  // proto carries no wall-clock timestamp.
    return true;
}

bool rac_stt_result_to_proto(const rac_stt_result_t* in,
                             ::runanywhere::v1::STTOutput* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->text) out->set_text(in->text);
    out->set_language(stt_language_from_string(in->detected_language));
    out->set_confidence(in->confidence);
    for (size_t i = 0; i < in->num_words; ++i) {
        rac_stt_word_to_proto(&in->words[i], out->add_words());
    }
    auto* meta = out->mutable_metadata();
    meta->set_processing_time_ms(in->processing_time_ms);
    return true;
}

bool rac_stt_result_from_proto(const ::runanywhere::v1::STTOutput& in,
                               rac_stt_result_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    out->text = copy_string_required(in.text());
    if (in.language() != ::runanywhere::v1::STT_LANGUAGE_UNSPECIFIED) {
        out->detected_language = rac_strdup(stt_language_to_string(in.language()));
    }
    out->confidence = in.confidence();
    if (in.words_size() > 0) {
        out->num_words = static_cast<size_t>(in.words_size());
        out->words = static_cast<rac_stt_word_t*>(
            rac_alloc(sizeof(rac_stt_word_t) * out->num_words));
        for (int i = 0; i < in.words_size(); ++i) {
            rac_stt_word_from_proto(in.words(i), &out->words[i]);
        }
    }
    out->processing_time_ms = in.has_metadata() ? in.metadata().processing_time_ms() : 0;
    return true;
}

// ===========================================================================
// TTS
// ===========================================================================

bool rac_tts_config_to_proto(const rac_tts_config_t* in,
                             ::runanywhere::v1::TTSConfiguration* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->model_id) out->set_model_id(in->model_id);
    set_proto_string_or_empty([&](const char* v) { out->set_voice(v); }, in->voice);
    set_proto_string_or_empty([&](const char* v) { out->set_language_code(v); },
                              in->language);
    out->set_speaking_rate(in->speaking_rate);
    out->set_pitch(in->pitch);
    out->set_volume(in->volume);
    out->set_audio_format(audio_format_to_proto(in->audio_format));
    out->set_sample_rate(0);  // C config has no sample_rate; rely on engine default.
    out->set_enable_neural_voice(in->use_neural_voice == RAC_TRUE);
    out->set_enable_ssml(in->enable_ssml == RAC_TRUE);
    return true;
}

bool rac_tts_config_from_proto(const ::runanywhere::v1::TTSConfiguration& in,
                               rac_tts_config_t* out) {
    if (!out) return false;
    *out = RAC_TTS_CONFIG_DEFAULT;
    out->model_id = copy_string(in.model_id());
    out->voice = copy_string(in.voice());
    if (!in.language_code().empty()) out->language = copy_string(in.language_code());
    if (in.speaking_rate() > 0.0f) out->speaking_rate = in.speaking_rate();
    if (in.pitch() > 0.0f) out->pitch = in.pitch();
    if (in.volume() > 0.0f) out->volume = in.volume();
    out->audio_format = audio_format_from_proto(in.audio_format());
    out->use_neural_voice = in.enable_neural_voice() ? RAC_TRUE : RAC_FALSE;
    out->enable_ssml = in.enable_ssml() ? RAC_TRUE : RAC_FALSE;
    return true;
}

bool rac_tts_options_to_proto(const rac_tts_options_t* in,
                              ::runanywhere::v1::TTSOptions* out) {
    if (!in || !out) return false;
    out->Clear();
    set_proto_string_or_empty([&](const char* v) { out->set_voice(v); }, in->voice);
    set_proto_string_or_empty([&](const char* v) { out->set_language_code(v); },
                              in->language);
    out->set_speaking_rate(in->rate);  // rename: rate -> speaking_rate.
    out->set_pitch(in->pitch);
    out->set_volume(in->volume);
    out->set_enable_ssml(in->use_ssml == RAC_TRUE);
    out->set_audio_format(audio_format_to_proto(in->audio_format));
    return true;
}

bool rac_tts_options_from_proto(const ::runanywhere::v1::TTSOptions& in,
                                rac_tts_options_t* out) {
    if (!out) return false;
    *out = RAC_TTS_OPTIONS_DEFAULT;
    out->voice = copy_string(in.voice());
    if (!in.language_code().empty()) out->language = copy_string(in.language_code());
    if (in.speaking_rate() > 0.0f) out->rate = in.speaking_rate();
    if (in.pitch() > 0.0f) out->pitch = in.pitch();
    if (in.volume() > 0.0f) out->volume = in.volume();
    out->audio_format = audio_format_from_proto(in.audio_format());
    out->use_ssml = in.enable_ssml() ? RAC_TRUE : RAC_FALSE;
    // sample_rate has no proto field on TTSOptions; keep default.
    return true;
}

bool rac_tts_phoneme_timestamp_to_proto(const rac_tts_phoneme_timestamp_t* in,
                                        ::runanywhere::v1::TTSPhonemeTimestamp* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->phoneme) out->set_phoneme(in->phoneme);
    out->set_start_ms(in->start_time_ms);
    out->set_end_ms(in->end_time_ms);
    return true;
}

bool rac_tts_phoneme_timestamp_from_proto(
    const ::runanywhere::v1::TTSPhonemeTimestamp& in,
    rac_tts_phoneme_timestamp_t* out) {
    if (!out) return false;
    out->phoneme = copy_string_required(in.phoneme());
    out->start_time_ms = in.start_ms();
    out->end_time_ms = in.end_ms();
    return true;
}

bool rac_tts_synthesis_metadata_to_proto(
    const rac_tts_synthesis_metadata_t* in,
    ::runanywhere::v1::TTSSynthesisMetadata* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->voice) out->set_voice_id(in->voice);
    if (in->language) out->set_language_code(in->language);
    out->set_processing_time_ms(in->processing_time_ms);
    out->set_character_count(in->character_count);
    // proto has audio_duration_ms; the C metadata struct has no such field
    // (it's on the parent rac_tts_output_t::duration_ms). Caller must set this
    // separately when emitting metadata-only TTSSpeakResult.
    return true;
}

bool rac_tts_synthesis_metadata_from_proto(
    const ::runanywhere::v1::TTSSynthesisMetadata& in,
    rac_tts_synthesis_metadata_t* out) {
    if (!out) return false;
    out->voice = copy_string(in.voice_id());
    out->language = copy_string(in.language_code());
    out->processing_time_ms = in.processing_time_ms();
    out->character_count = in.character_count();
    // Compute characters_per_second from processing_time_ms.
    out->characters_per_second =
        (in.processing_time_ms() > 0)
            ? static_cast<float>(in.character_count()) /
                  (static_cast<float>(in.processing_time_ms()) / 1000.0f)
            : 0.0f;
    return true;
}

bool rac_tts_output_to_proto(const rac_tts_output_t* in,
                             ::runanywhere::v1::TTSOutput* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->audio_data && in->audio_size > 0) {
        out->set_audio_data(::std::string(static_cast<const char*>(in->audio_data),
                                          in->audio_size));
    }
    out->set_audio_format(audio_format_to_proto(in->format));
    out->set_sample_rate(0);  // C struct has no sample_rate at the output level.
    out->set_duration_ms(in->duration_ms);
    for (size_t i = 0; i < in->num_phoneme_timestamps; ++i) {
        rac_tts_phoneme_timestamp_to_proto(&in->phoneme_timestamps[i],
                                            out->add_phoneme_timestamps());
    }
    auto* meta = out->mutable_metadata();
    rac_tts_synthesis_metadata_to_proto(&in->metadata, meta);
    meta->set_audio_duration_ms(in->duration_ms);
    out->set_timestamp_ms(in->timestamp_ms);
    return true;
}

bool rac_tts_output_from_proto(const ::runanywhere::v1::TTSOutput& in,
                               rac_tts_output_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    if (!in.audio_data().empty()) {
        out->audio_size = in.audio_data().size();
        out->audio_data = rac_alloc(out->audio_size);
        std::memcpy(out->audio_data, in.audio_data().data(), out->audio_size);
    }
    out->format = audio_format_from_proto(in.audio_format());
    out->duration_ms = in.duration_ms();
    if (in.phoneme_timestamps_size() > 0) {
        out->num_phoneme_timestamps = static_cast<size_t>(in.phoneme_timestamps_size());
        out->phoneme_timestamps = static_cast<rac_tts_phoneme_timestamp_t*>(
            rac_alloc(sizeof(rac_tts_phoneme_timestamp_t) * out->num_phoneme_timestamps));
        for (int i = 0; i < in.phoneme_timestamps_size(); ++i) {
            rac_tts_phoneme_timestamp_from_proto(in.phoneme_timestamps(i),
                                                 &out->phoneme_timestamps[i]);
        }
    }
    if (in.has_metadata()) {
        rac_tts_synthesis_metadata_from_proto(in.metadata(), &out->metadata);
    }
    out->timestamp_ms = in.timestamp_ms();
    return true;
}

bool rac_tts_result_to_proto(const rac_tts_result_t* in,
                             ::runanywhere::v1::TTSOutput* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->audio_data && in->audio_size > 0) {
        out->set_audio_data(::std::string(static_cast<const char*>(in->audio_data),
                                          in->audio_size));
    }
    out->set_audio_format(audio_format_to_proto(in->audio_format));
    out->set_sample_rate(in->sample_rate);
    out->set_duration_ms(in->duration_ms);
    auto* meta = out->mutable_metadata();
    meta->set_processing_time_ms(in->processing_time_ms);
    meta->set_audio_duration_ms(in->duration_ms);
    return true;
}

bool rac_tts_result_from_proto(const ::runanywhere::v1::TTSOutput& in,
                               rac_tts_result_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    if (!in.audio_data().empty()) {
        out->audio_size = in.audio_data().size();
        out->audio_data = rac_alloc(out->audio_size);
        std::memcpy(out->audio_data, in.audio_data().data(), out->audio_size);
    }
    out->audio_format = audio_format_from_proto(in.audio_format());
    out->sample_rate = in.sample_rate();
    out->duration_ms = in.duration_ms();
    out->processing_time_ms = in.has_metadata() ? in.metadata().processing_time_ms() : 0;
    return true;
}

bool rac_tts_speak_result_to_proto(const rac_tts_speak_result_t* in,
                                   ::runanywhere::v1::TTSSpeakResult* out) {
    if (!in || !out) return false;
    out->Clear();
    out->set_audio_format(audio_format_to_proto(in->format));
    out->set_sample_rate(0);  // C struct has no sample_rate field.
    out->set_duration_ms(in->duration_ms);
    out->set_audio_size_bytes(static_cast<int64_t>(in->audio_size_bytes));
    rac_tts_synthesis_metadata_to_proto(&in->metadata, out->mutable_metadata());
    out->mutable_metadata()->set_audio_duration_ms(in->duration_ms);
    out->set_timestamp_ms(in->timestamp_ms);
    return true;
}

bool rac_tts_speak_result_from_proto(const ::runanywhere::v1::TTSSpeakResult& in,
                                     rac_tts_speak_result_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    out->format = audio_format_from_proto(in.audio_format());
    out->duration_ms = in.duration_ms();
    out->audio_size_bytes = static_cast<size_t>(in.audio_size_bytes());
    if (in.has_metadata()) {
        rac_tts_synthesis_metadata_from_proto(in.metadata(), &out->metadata);
    }
    out->timestamp_ms = in.timestamp_ms();
    return true;
}

// ===========================================================================
// VAD
// ===========================================================================

bool rac_vad_config_to_proto(const rac_vad_config_t* in,
                             ::runanywhere::v1::VADConfiguration* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->model_id) out->set_model_id(in->model_id);
    out->set_sample_rate(in->sample_rate);
    out->set_frame_length_ms(frame_seconds_to_ms(in->frame_length));
    out->set_threshold(in->energy_threshold);
    out->set_enable_auto_calibration(in->enable_auto_calibration == RAC_TRUE);
    return true;
}

bool rac_vad_config_from_proto(const ::runanywhere::v1::VADConfiguration& in,
                               rac_vad_config_t* out) {
    if (!out) return false;
    *out = RAC_VAD_CONFIG_DEFAULT;
    out->model_id = copy_string(in.model_id());
    if (in.sample_rate() > 0) out->sample_rate = in.sample_rate();
    out->frame_length = frame_ms_to_seconds(in.frame_length_ms());
    if (in.threshold() > 0.0f) out->energy_threshold = in.threshold();
    out->enable_auto_calibration = in.enable_auto_calibration() ? RAC_TRUE : RAC_FALSE;
    return true;
}

bool rac_vad_input_to_proto_options(const rac_vad_input_t* in,
                                    ::runanywhere::v1::VADOptions* out) {
    if (!in || !out) return false;
    out->Clear();
    // -1.0f sentinel ("no override") collapses to proto unset (0.0).
    if (in->energy_threshold_override > 0.0f) {
        out->set_threshold(in->energy_threshold_override);
    } else {
        out->set_threshold(0.0f);
    }
    out->set_min_speech_duration_ms(RAC_VAD_MIN_SPEECH_DURATION_MS);
    out->set_min_silence_duration_ms(RAC_VAD_MIN_SILENCE_DURATION_MS);
    return true;
}

bool rac_vad_input_from_proto_options(const ::runanywhere::v1::VADOptions& in,
                                      rac_vad_input_t* out) {
    if (!out) return false;
    *out = RAC_VAD_INPUT_DEFAULT;
    if (in.threshold() > 0.0f) {
        out->energy_threshold_override = in.threshold();
    } else {
        out->energy_threshold_override = -1.0f;
    }
    // min_speech / min_silence cannot be carried on rac_vad_input_t; they are
    // global #defines. The caller must apply them externally if needed.
    return true;
}

bool rac_vad_output_to_proto(const rac_vad_output_t* in,
                             ::runanywhere::v1::VADResult* out) {
    if (!in || !out) return false;
    out->Clear();
    out->set_is_speech(in->is_speech_detected == RAC_TRUE);
    out->set_energy(in->energy_level);
    out->set_confidence(0.0f);  // C ABI has no confidence on rac_vad_output_t.
    out->set_duration_ms(0);    // analysed-frame length not carried on C struct.
    return true;
}

bool rac_vad_output_from_proto(const ::runanywhere::v1::VADResult& in,
                               rac_vad_output_t* out) {
    if (!out) return false;
    out->is_speech_detected = in.is_speech() ? RAC_TRUE : RAC_FALSE;
    out->energy_level = in.energy();
    out->timestamp_ms = 0;  // proto carries no wall-clock timestamp; caller fills.
    return true;
}

bool rac_vad_statistics_to_proto(const rac_vad_statistics_t* in,
                                 ::runanywhere::v1::VADStatistics* out) {
    if (!in || !out) return false;
    out->Clear();
    out->set_current_threshold(in->current_threshold);
    out->set_ambient_level(in->ambient_noise_level);
    // C ABI carries average_energy / peak_energy — map to recent_avg / recent_max.
    out->set_recent_avg(in->average_energy);
    out->set_recent_max(in->peak_energy);
    // current_energy has no exact C counterpart; default to peak as a best guess.
    out->set_current_energy(in->peak_energy);
    return true;
}

bool rac_vad_statistics_from_proto(const ::runanywhere::v1::VADStatistics& in,
                                   rac_vad_statistics_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    out->current_threshold = in.current_threshold();
    out->ambient_noise_level = in.ambient_level();
    out->average_energy = in.recent_avg();
    out->peak_energy = in.recent_max();
    // total_speech_segments / total_speech_duration_ms have no proto carriers.
    return true;
}

bool rac_speech_activity_to_proto(rac_speech_activity_t in_kind,
                                  int64_t in_timestamp_ms,
                                  int32_t in_duration_ms,
                                  ::runanywhere::v1::SpeechActivityEvent* out) {
    if (!out) return false;
    out->Clear();
    switch (in_kind) {
        case RAC_SPEECH_STARTED:
            out->set_event_type(::runanywhere::v1::SPEECH_ACTIVITY_KIND_SPEECH_STARTED);
            break;
        case RAC_SPEECH_ENDED:
            out->set_event_type(::runanywhere::v1::SPEECH_ACTIVITY_KIND_SPEECH_ENDED);
            break;
        case RAC_SPEECH_ONGOING:
            out->set_event_type(::runanywhere::v1::SPEECH_ACTIVITY_KIND_ONGOING);
            break;
        default:
            out->set_event_type(::runanywhere::v1::SPEECH_ACTIVITY_KIND_UNSPECIFIED);
            break;
    }
    out->set_timestamp_ms(in_timestamp_ms);
    out->set_duration_ms(in_duration_ms);
    return true;
}

bool rac_speech_activity_from_proto(const ::runanywhere::v1::SpeechActivityEvent& in,
                                    rac_speech_activity_t* out_kind,
                                    int64_t* out_timestamp_ms,
                                    int32_t* out_duration_ms) {
    if (!out_kind) return false;
    switch (in.event_type()) {
        case ::runanywhere::v1::SPEECH_ACTIVITY_KIND_SPEECH_STARTED:
            *out_kind = RAC_SPEECH_STARTED;
            break;
        case ::runanywhere::v1::SPEECH_ACTIVITY_KIND_SPEECH_ENDED:
            *out_kind = RAC_SPEECH_ENDED;
            break;
        case ::runanywhere::v1::SPEECH_ACTIVITY_KIND_ONGOING:
            *out_kind = RAC_SPEECH_ONGOING;
            break;
        default:
            *out_kind = RAC_SPEECH_ONGOING;  // safest fallback; nothing to drop.
            break;
    }
    if (out_timestamp_ms) *out_timestamp_ms = in.timestamp_ms();
    if (out_duration_ms) *out_duration_ms = in.duration_ms();
    return true;
}

// ===========================================================================
// VLM
// ===========================================================================

bool rac_vlm_config_to_proto(const rac_vlm_config_t* in,
                             ::runanywhere::v1::VLMConfiguration* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->model_id) out->set_model_id(in->model_id);
    out->set_max_image_size_px(0);  // C struct has no max_image_size on config.
    out->set_max_tokens(in->max_tokens);
    return true;
}

bool rac_vlm_config_from_proto(const ::runanywhere::v1::VLMConfiguration& in,
                               rac_vlm_config_t* out) {
    if (!out) return false;
    *out = RAC_VLM_CONFIG_DEFAULT;
    out->model_id = copy_string(in.model_id());
    if (in.max_tokens() > 0) out->max_tokens = in.max_tokens();
    return true;
}

bool rac_vlm_options_to_proto(const rac_vlm_options_t* in,
                              const char* prompt,
                              ::runanywhere::v1::VLMGenerationOptions* out) {
    if (!in || !out) return false;
    out->Clear();
    if (prompt) out->set_prompt(prompt);
    out->set_max_tokens(in->max_tokens);
    out->set_temperature(in->temperature);
    out->set_top_p(in->top_p);
    out->set_top_k(0);  // C ABI has no top_k on rac_vlm_options_t.
    return true;
}

bool rac_vlm_options_from_proto(const ::runanywhere::v1::VLMGenerationOptions& in,
                                rac_vlm_options_t* out,
                                const char** out_prompt) {
    if (!out) return false;
    rac_vlm_options_t defaults = RAC_VLM_OPTIONS_DEFAULT;
    *out = defaults;
    if (in.max_tokens() > 0) out->max_tokens = in.max_tokens();
    if (in.temperature() > 0.0f) out->temperature = in.temperature();
    if (in.top_p() > 0.0f) out->top_p = in.top_p();
    if (out_prompt) {
        *out_prompt = in.prompt().empty() ? nullptr : rac_strdup(in.prompt().c_str());
    }
    return true;
}

bool rac_vlm_result_to_proto(const rac_vlm_result_t* in,
                             ::runanywhere::v1::VLMResult* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->text) out->set_text(in->text);
    out->set_prompt_tokens(in->prompt_tokens);
    out->set_completion_tokens(in->completion_tokens);
    out->set_total_tokens(in->total_tokens);
    out->set_processing_time_ms(in->total_time_ms);
    out->set_tokens_per_second(in->tokens_per_second);
    return true;
}

bool rac_vlm_result_from_proto(const ::runanywhere::v1::VLMResult& in,
                               rac_vlm_result_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    out->text = copy_string_required(in.text());
    out->prompt_tokens = in.prompt_tokens();
    out->completion_tokens = in.completion_tokens();
    out->total_tokens = static_cast<int32_t>(in.total_tokens());
    out->total_time_ms = in.processing_time_ms();
    out->tokens_per_second = in.tokens_per_second();
    return true;
}

bool rac_vlm_image_to_proto(const rac_vlm_image_t* in,
                            ::runanywhere::v1::VLMImage* out) {
    if (!in || !out) return false;
    out->Clear();
    out->set_width(static_cast<int32_t>(in->width));
    out->set_height(static_cast<int32_t>(in->height));
    switch (in->format) {
        case RAC_VLM_IMAGE_FORMAT_FILE_PATH:
            if (in->file_path) out->set_file_path(in->file_path);
            out->set_format(::runanywhere::v1::VLM_IMAGE_FORMAT_FILE_PATH);
            break;
        case RAC_VLM_IMAGE_FORMAT_RGB_PIXELS:
            if (in->pixel_data && in->data_size > 0) {
                out->set_raw_rgb(::std::string(
                    reinterpret_cast<const char*>(in->pixel_data), in->data_size));
            }
            out->set_format(::runanywhere::v1::VLM_IMAGE_FORMAT_RAW_RGB);
            break;
        case RAC_VLM_IMAGE_FORMAT_BASE64:
            if (in->base64_data) out->set_base64(in->base64_data);
            out->set_format(::runanywhere::v1::VLM_IMAGE_FORMAT_BASE64);
            break;
    }
    return true;
}

bool rac_vlm_image_from_proto(const ::runanywhere::v1::VLMImage& in,
                              rac_vlm_image_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    out->width = static_cast<uint32_t>(in.width());
    out->height = static_cast<uint32_t>(in.height());
    if (in.has_file_path()) {
        out->format = RAC_VLM_IMAGE_FORMAT_FILE_PATH;
        out->file_path = copy_string_required(in.file_path());
    } else if (in.has_raw_rgb()) {
        out->format = RAC_VLM_IMAGE_FORMAT_RGB_PIXELS;
        out->data_size = in.raw_rgb().size();
        if (out->data_size > 0) {
            uint8_t* buf = static_cast<uint8_t*>(rac_alloc(out->data_size));
            std::memcpy(buf, in.raw_rgb().data(), out->data_size);
            out->pixel_data = buf;
        }
    } else if (in.has_base64()) {
        out->format = RAC_VLM_IMAGE_FORMAT_BASE64;
        out->base64_data = copy_string_required(in.base64());
        out->data_size = in.base64().size();
    } else if (in.has_encoded()) {
        // No exact C ABI carrier — surface as RGB_PIXELS bytes (encoded
        // payload). Caller must inspect the (proto-side) format hint
        // separately. This is a best-effort path; pixel data will not be
        // raw RGB but the caller can still treat it as opaque bytes.
        out->format = RAC_VLM_IMAGE_FORMAT_RGB_PIXELS;
        out->data_size = in.encoded().size();
        if (out->data_size > 0) {
            uint8_t* buf = static_cast<uint8_t*>(rac_alloc(out->data_size));
            std::memcpy(buf, in.encoded().data(), out->data_size);
            out->pixel_data = buf;
        }
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

::runanywhere::v1::DiffusionScheduler diffusion_scheduler_to_proto(
    rac_diffusion_scheduler_t s) {
    switch (s) {
        case RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS:
            return ::runanywhere::v1::DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS;
        case RAC_DIFFUSION_SCHEDULER_DPM_PP_2M:
            return ::runanywhere::v1::DIFFUSION_SCHEDULER_DPMPP_2M;
        case RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_SDE:
            // Drift: proto folds SDE into DPMPP_2M.
            return ::runanywhere::v1::DIFFUSION_SCHEDULER_DPMPP_2M;
        case RAC_DIFFUSION_SCHEDULER_DDIM:
            return ::runanywhere::v1::DIFFUSION_SCHEDULER_DDIM;
        case RAC_DIFFUSION_SCHEDULER_EULER:
            return ::runanywhere::v1::DIFFUSION_SCHEDULER_EULER;
        case RAC_DIFFUSION_SCHEDULER_EULER_ANCESTRAL:
            return ::runanywhere::v1::DIFFUSION_SCHEDULER_EULER_A;
        case RAC_DIFFUSION_SCHEDULER_PNDM:
            return ::runanywhere::v1::DIFFUSION_SCHEDULER_PNDM;
        case RAC_DIFFUSION_SCHEDULER_LMS:
            return ::runanywhere::v1::DIFFUSION_SCHEDULER_LMS;
    }
    return ::runanywhere::v1::DIFFUSION_SCHEDULER_UNSPECIFIED;
}

rac_diffusion_scheduler_t diffusion_scheduler_from_proto(
    ::runanywhere::v1::DiffusionScheduler p) {
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

::runanywhere::v1::DiffusionMode diffusion_mode_to_proto(rac_diffusion_mode_t m) {
    switch (m) {
        case RAC_DIFFUSION_MODE_TEXT_TO_IMAGE:
            return ::runanywhere::v1::DIFFUSION_MODE_TEXT_TO_IMAGE;
        case RAC_DIFFUSION_MODE_IMAGE_TO_IMAGE:
            return ::runanywhere::v1::DIFFUSION_MODE_IMAGE_TO_IMAGE;
        case RAC_DIFFUSION_MODE_INPAINTING:
            return ::runanywhere::v1::DIFFUSION_MODE_INPAINTING;
    }
    return ::runanywhere::v1::DIFFUSION_MODE_UNSPECIFIED;
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

::runanywhere::v1::DiffusionModelVariant diffusion_variant_to_proto(
    rac_diffusion_model_variant_t v) {
    switch (v) {
        case RAC_DIFFUSION_MODEL_SD_1_5:
            return ::runanywhere::v1::DIFFUSION_MODEL_VARIANT_SD_1_5;
        case RAC_DIFFUSION_MODEL_SD_2_1:
            return ::runanywhere::v1::DIFFUSION_MODEL_VARIANT_SD_2_1;
        case RAC_DIFFUSION_MODEL_SDXL:
            return ::runanywhere::v1::DIFFUSION_MODEL_VARIANT_SDXL;
        case RAC_DIFFUSION_MODEL_SDXL_TURBO:
            return ::runanywhere::v1::DIFFUSION_MODEL_VARIANT_SDXL_TURBO;
        case RAC_DIFFUSION_MODEL_SDXS:
            return ::runanywhere::v1::DIFFUSION_MODEL_VARIANT_SDXS;
        case RAC_DIFFUSION_MODEL_LCM:
            return ::runanywhere::v1::DIFFUSION_MODEL_VARIANT_LCM;
    }
    return ::runanywhere::v1::DIFFUSION_MODEL_VARIANT_UNSPECIFIED;
}

rac_diffusion_model_variant_t diffusion_variant_from_proto(
    ::runanywhere::v1::DiffusionModelVariant p) {
    switch (p) {
        case ::runanywhere::v1::DIFFUSION_MODEL_VARIANT_SD_1_5:
            return RAC_DIFFUSION_MODEL_SD_1_5;
        case ::runanywhere::v1::DIFFUSION_MODEL_VARIANT_SD_2_1:
            return RAC_DIFFUSION_MODEL_SD_2_1;
        case ::runanywhere::v1::DIFFUSION_MODEL_VARIANT_SDXL:
            return RAC_DIFFUSION_MODEL_SDXL;
        case ::runanywhere::v1::DIFFUSION_MODEL_VARIANT_SDXL_TURBO:
            return RAC_DIFFUSION_MODEL_SDXL_TURBO;
        case ::runanywhere::v1::DIFFUSION_MODEL_VARIANT_SDXS:
            return RAC_DIFFUSION_MODEL_SDXS;
        case ::runanywhere::v1::DIFFUSION_MODEL_VARIANT_LCM:
            return RAC_DIFFUSION_MODEL_LCM;
        default:
            return RAC_DIFFUSION_MODEL_SD_1_5;
    }
}

::runanywhere::v1::DiffusionTokenizerSourceKind diffusion_tokenizer_to_proto(
    rac_diffusion_tokenizer_source_t s) {
    switch (s) {
        case RAC_DIFFUSION_TOKENIZER_SD_1_5:
            return ::runanywhere::v1::DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15;
        case RAC_DIFFUSION_TOKENIZER_SD_2_X:
            return ::runanywhere::v1::DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2;
        case RAC_DIFFUSION_TOKENIZER_SDXL:
            return ::runanywhere::v1::DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL;
        case RAC_DIFFUSION_TOKENIZER_CUSTOM:
            return ::runanywhere::v1::DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM;
    }
    return ::runanywhere::v1::DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED;
}

rac_diffusion_tokenizer_source_t diffusion_tokenizer_from_proto(
    ::runanywhere::v1::DiffusionTokenizerSourceKind p) {
    switch (p) {
        case ::runanywhere::v1::DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15:
            return RAC_DIFFUSION_TOKENIZER_SD_1_5;
        case ::runanywhere::v1::DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2:
            return RAC_DIFFUSION_TOKENIZER_SD_2_X;
        case ::runanywhere::v1::DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL:
            return RAC_DIFFUSION_TOKENIZER_SDXL;
        case ::runanywhere::v1::DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM:
            return RAC_DIFFUSION_TOKENIZER_CUSTOM;
        default:
            return RAC_DIFFUSION_TOKENIZER_SD_1_5;
    }
}

}  // namespace

bool rac_diffusion_config_to_proto(const rac_diffusion_config_t* in,
                                   ::runanywhere::v1::DiffusionConfiguration* out) {
    if (!in || !out) return false;
    out->Clear();
    out->set_model_variant(diffusion_variant_to_proto(in->model_variant));
    auto* tok = out->mutable_tokenizer_source();
    tok->set_kind(diffusion_tokenizer_to_proto(in->tokenizer.source));
    if (in->tokenizer.source == RAC_DIFFUSION_TOKENIZER_CUSTOM &&
        in->tokenizer.custom_base_url) {
        tok->set_custom_path(in->tokenizer.custom_base_url);
    }
    out->set_enable_safety_checker(in->enable_safety_checker == RAC_TRUE);
    // reduce_memory bool maps to a small max_memory_mb when set; 0 otherwise.
    out->set_max_memory_mb(in->reduce_memory == RAC_TRUE ? 1024 : 0);
    return true;
}

bool rac_diffusion_config_from_proto(const ::runanywhere::v1::DiffusionConfiguration& in,
                                     rac_diffusion_config_t* out) {
    if (!out) return false;
    *out = RAC_DIFFUSION_CONFIG_DEFAULT;
    out->model_variant = diffusion_variant_from_proto(in.model_variant());
    if (in.has_tokenizer_source()) {
        out->tokenizer.source = diffusion_tokenizer_from_proto(in.tokenizer_source().kind());
        if (in.tokenizer_source().has_custom_path()) {
            out->tokenizer.custom_base_url =
                copy_string(in.tokenizer_source().custom_path());
        }
    }
    out->enable_safety_checker = in.enable_safety_checker() ? RAC_TRUE : RAC_FALSE;
    out->reduce_memory = (in.max_memory_mb() > 0) ? RAC_TRUE : RAC_FALSE;
    return true;
}

bool rac_diffusion_options_to_proto(const rac_diffusion_options_t* in,
                                    ::runanywhere::v1::DiffusionGenerationOptions* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->prompt) out->set_prompt(in->prompt);
    if (in->negative_prompt) out->set_negative_prompt(in->negative_prompt);
    out->set_width(in->width);
    out->set_height(in->height);
    out->set_num_inference_steps(in->steps);
    out->set_guidance_scale(in->guidance_scale);
    out->set_seed(in->seed);
    out->set_scheduler(diffusion_scheduler_to_proto(in->scheduler));
    out->set_mode(diffusion_mode_to_proto(in->mode));
    return true;
}

bool rac_diffusion_options_from_proto(
    const ::runanywhere::v1::DiffusionGenerationOptions& in,
    rac_diffusion_options_t* out) {
    if (!out) return false;
    *out = RAC_DIFFUSION_OPTIONS_DEFAULT;
    out->prompt = copy_string(in.prompt());
    out->negative_prompt = copy_string(in.negative_prompt());
    if (in.width() > 0) out->width = in.width();
    if (in.height() > 0) out->height = in.height();
    if (in.num_inference_steps() > 0) out->steps = in.num_inference_steps();
    if (in.guidance_scale() > 0.0f) out->guidance_scale = in.guidance_scale();
    out->seed = in.seed();
    out->scheduler = diffusion_scheduler_from_proto(in.scheduler());
    out->mode = diffusion_mode_from_proto(in.mode());
    return true;
}

bool rac_diffusion_progress_to_proto(const rac_diffusion_progress_t* in,
                                     ::runanywhere::v1::DiffusionProgress* out) {
    if (!in || !out) return false;
    out->Clear();
    out->set_progress_percent(in->progress);
    out->set_current_step(in->current_step);
    out->set_total_steps(in->total_steps);
    if (in->stage) out->set_stage(in->stage);
    if (in->intermediate_image_data && in->intermediate_image_size > 0) {
        out->set_intermediate_image_data(::std::string(
            reinterpret_cast<const char*>(in->intermediate_image_data),
            in->intermediate_image_size));
    }
    return true;
}

bool rac_diffusion_progress_from_proto(
    const ::runanywhere::v1::DiffusionProgress& in,
    rac_diffusion_progress_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    out->progress = in.progress_percent();
    out->current_step = in.current_step();
    out->total_steps = in.total_steps();
    out->stage = copy_string(in.stage());
    if (in.has_intermediate_image_data()) {
        out->intermediate_image_size = in.intermediate_image_data().size();
        if (out->intermediate_image_size > 0) {
            uint8_t* buf =
                static_cast<uint8_t*>(rac_alloc(out->intermediate_image_size));
            std::memcpy(buf, in.intermediate_image_data().data(),
                        out->intermediate_image_size);
            out->intermediate_image_data = buf;
        }
    }
    return true;
}

bool rac_diffusion_result_to_proto(const rac_diffusion_result_t* in,
                                   ::runanywhere::v1::DiffusionResult* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->image_data && in->image_size > 0) {
        out->set_image_data(::std::string(reinterpret_cast<const char*>(in->image_data),
                                          in->image_size));
    }
    out->set_width(in->width);
    out->set_height(in->height);
    out->set_seed_used(in->seed_used);
    out->set_total_time_ms(in->generation_time_ms);
    out->set_safety_flag(in->safety_flagged == RAC_TRUE);
    // No used_scheduler available on rac_diffusion_result_t — leave UNSPECIFIED.
    return true;
}

bool rac_diffusion_result_from_proto(const ::runanywhere::v1::DiffusionResult& in,
                                     rac_diffusion_result_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    if (!in.image_data().empty()) {
        out->image_size = in.image_data().size();
        out->image_data = static_cast<uint8_t*>(rac_alloc(out->image_size));
        std::memcpy(out->image_data, in.image_data().data(), out->image_size);
    }
    out->width = in.width();
    out->height = in.height();
    out->seed_used = in.seed_used();
    out->generation_time_ms = in.total_time_ms();
    out->safety_flagged = in.safety_flag() ? RAC_TRUE : RAC_FALSE;
    out->error_code = RAC_SUCCESS;
    return true;
}

// ===========================================================================
// LoRA
// ===========================================================================

bool rac_lora_entry_to_proto(const rac_lora_entry_t* in,
                             ::runanywhere::v1::LoraAdapterCatalogEntry* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->id) out->set_id(in->id);
    if (in->name) out->set_name(in->name);
    if (in->description) out->set_description(in->description);
    if (in->download_url) out->set_url(in->download_url);
    if (in->filename) out->set_filename(in->filename);
    for (size_t i = 0; i < in->compatible_model_count; ++i) {
        if (in->compatible_model_ids[i]) {
            out->add_compatible_models(in->compatible_model_ids[i]);
        }
    }
    out->set_size_bytes(in->file_size);
    // proto LoraAdapterCatalogEntry has no default_scale field — drop in->default_scale
    // (drift documented).
    return true;
}

bool rac_lora_entry_from_proto(const ::runanywhere::v1::LoraAdapterCatalogEntry& in,
                               rac_lora_entry_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    out->id = copy_string(in.id());
    out->name = copy_string(in.name());
    out->description = copy_string(in.description());
    out->download_url = copy_string(in.url());
    out->filename = copy_string(in.filename());
    out->file_size = in.size_bytes();
    out->default_scale = 1.0f;  // proto has no carrier; use the documented default.
    if (in.compatible_models_size() > 0) {
        out->compatible_model_count = static_cast<size_t>(in.compatible_models_size());
        out->compatible_model_ids = static_cast<char**>(
            rac_alloc(sizeof(char*) * out->compatible_model_count));
        for (int i = 0; i < in.compatible_models_size(); ++i) {
            out->compatible_model_ids[i] = rac_strdup(in.compatible_models(i).c_str());
        }
    }
    return true;
}

bool rac_lora_info_to_proto(const char* adapter_id, const char* adapter_path,
                            float scale, bool applied, const char* error_message,
                            ::runanywhere::v1::LoRAAdapterInfo* out) {
    if (!out) return false;
    out->Clear();
    if (adapter_id) out->set_adapter_id(adapter_id);
    if (adapter_path) out->set_adapter_path(adapter_path);
    out->set_scale(scale);
    out->set_applied(applied);
    if (error_message) out->set_error_message(error_message);
    return true;
}

bool rac_lora_info_from_proto(const ::runanywhere::v1::LoRAAdapterInfo& in,
                              char** out_adapter_id, char** out_adapter_path,
                              float* out_scale, bool* out_applied,
                              char** out_error_message) {
    if (out_adapter_id) *out_adapter_id = copy_string(in.adapter_id());
    if (out_adapter_path) *out_adapter_path = copy_string(in.adapter_path());
    if (out_scale) *out_scale = in.scale();
    if (out_applied) *out_applied = in.applied();
    if (out_error_message) {
        *out_error_message = in.has_error_message() ? copy_string(in.error_message())
                                                    : nullptr;
    }
    return true;
}

// ===========================================================================
// RAG
// ===========================================================================

bool rac_rag_config_to_proto(const rac_rag_config_t* in,
                             ::runanywhere::v1::RAGConfiguration* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->embedding_model_path) out->set_embedding_model_path(in->embedding_model_path);
    if (in->llm_model_path) out->set_llm_model_path(in->llm_model_path);
    out->set_embedding_dimension(static_cast<int32_t>(in->embedding_dimension));
    out->set_top_k(static_cast<int32_t>(in->top_k));
    out->set_similarity_threshold(in->similarity_threshold);
    out->set_chunk_size(static_cast<int32_t>(in->chunk_size));
    out->set_chunk_overlap(static_cast<int32_t>(in->chunk_overlap));
    return true;
}

bool rac_rag_config_from_proto(const ::runanywhere::v1::RAGConfiguration& in,
                               rac_rag_config_t* out) {
    if (!out) return false;
    *out = rac_rag_config_default();
    out->embedding_model_path = copy_string(in.embedding_model_path());
    out->llm_model_path = copy_string(in.llm_model_path());
    if (in.embedding_dimension() > 0)
        out->embedding_dimension = static_cast<size_t>(in.embedding_dimension());
    if (in.top_k() > 0) out->top_k = static_cast<size_t>(in.top_k());
    if (in.similarity_threshold() > 0.0f)
        out->similarity_threshold = in.similarity_threshold();
    if (in.chunk_size() > 0) out->chunk_size = static_cast<size_t>(in.chunk_size());
    if (in.chunk_overlap() >= 0)
        out->chunk_overlap = static_cast<size_t>(in.chunk_overlap());
    return true;
}

bool rac_rag_query_to_proto(const rac_rag_query_t* in,
                            ::runanywhere::v1::RAGQueryOptions* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->question) out->set_question(in->question);
    if (in->system_prompt) out->set_system_prompt(in->system_prompt);
    out->set_max_tokens(in->max_tokens);
    out->set_temperature(in->temperature);
    out->set_top_p(in->top_p);
    out->set_top_k(in->top_k);
    return true;
}

bool rac_rag_query_from_proto(const ::runanywhere::v1::RAGQueryOptions& in,
                              rac_rag_query_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    out->question = copy_string(in.question());
    out->system_prompt = in.has_system_prompt() ? copy_string(in.system_prompt())
                                                : nullptr;
    out->max_tokens = in.max_tokens() > 0 ? in.max_tokens() : 512;
    out->temperature = in.temperature() > 0.0f ? in.temperature() : 0.7f;
    out->top_p = in.top_p() > 0.0f ? in.top_p() : 0.9f;
    out->top_k = in.top_k() > 0 ? in.top_k() : 40;
    return true;
}

bool rac_search_result_to_proto(const rac_search_result_t* in,
                                ::runanywhere::v1::RAGSearchResult* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->chunk_id) out->set_chunk_id(in->chunk_id);
    if (in->text) out->set_text(in->text);
    out->set_similarity_score(in->similarity_score);
    // C ABI ships metadata as an opaque JSON string. Since the proto canonical
    // form is map<string,string>, we don't attempt JSON parsing here — leave
    // metadata empty. Consumers that need structured metadata MUST parse the
    // legacy JSON blob themselves before calling this adapter.
    return true;
}

bool rac_search_result_from_proto(const ::runanywhere::v1::RAGSearchResult& in,
                                  rac_search_result_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    out->chunk_id = copy_string_required(in.chunk_id());
    out->text = copy_string_required(in.text());
    out->similarity_score = in.similarity_score();
    // metadata: we don't generate JSON here; leave NULL (caller-friendly).
    out->metadata_json = nullptr;
    return true;
}

bool rac_rag_result_to_proto(const rac_rag_result_t* in,
                             ::runanywhere::v1::RAGResult* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->answer) out->set_answer(in->answer);
    for (size_t i = 0; i < in->num_chunks; ++i) {
        rac_search_result_to_proto(&in->retrieved_chunks[i],
                                   out->add_retrieved_chunks());
    }
    if (in->context_used) out->set_context_used(in->context_used);
    out->set_retrieval_time_ms(static_cast<int64_t>(in->retrieval_time_ms));
    out->set_generation_time_ms(static_cast<int64_t>(in->generation_time_ms));
    out->set_total_time_ms(static_cast<int64_t>(in->total_time_ms));
    return true;
}

bool rac_rag_result_from_proto(const ::runanywhere::v1::RAGResult& in,
                               rac_rag_result_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    out->answer = copy_string_required(in.answer());
    out->context_used = copy_string_required(in.context_used());
    if (in.retrieved_chunks_size() > 0) {
        out->num_chunks = static_cast<size_t>(in.retrieved_chunks_size());
        out->retrieved_chunks = static_cast<rac_search_result_t*>(
            rac_alloc(sizeof(rac_search_result_t) * out->num_chunks));
        for (int i = 0; i < in.retrieved_chunks_size(); ++i) {
            rac_search_result_from_proto(in.retrieved_chunks(i),
                                         &out->retrieved_chunks[i]);
        }
    }
    out->retrieval_time_ms = static_cast<double>(in.retrieval_time_ms());
    out->generation_time_ms = static_cast<double>(in.generation_time_ms());
    out->total_time_ms = static_cast<double>(in.total_time_ms());
    return true;
}

// ===========================================================================
// EMBEDDINGS
// ===========================================================================

bool rac_embeddings_config_to_proto(const rac_embeddings_config_t* in,
                                    ::runanywhere::v1::EmbeddingsConfiguration* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->model_id) out->set_model_id(in->model_id);
    out->set_embedding_dimension(0);  // C ABI does not carry a dimension on config.
    out->set_max_sequence_length(in->max_tokens);
    out->set_normalize(in->normalize == RAC_EMBEDDINGS_NORMALIZE_L2);
    return true;
}

bool rac_embeddings_config_from_proto(
    const ::runanywhere::v1::EmbeddingsConfiguration& in,
    rac_embeddings_config_t* out) {
    if (!out) return false;
    *out = RAC_EMBEDDINGS_CONFIG_DEFAULT;
    out->model_id = copy_string(in.model_id());
    if (in.max_sequence_length() > 0) out->max_tokens = in.max_sequence_length();
    if (in.has_normalize()) {
        out->normalize = in.normalize() ? RAC_EMBEDDINGS_NORMALIZE_L2
                                        : RAC_EMBEDDINGS_NORMALIZE_NONE;
    }
    // pooling and preferred_framework are not on the wire — keep defaults.
    return true;
}

bool rac_embeddings_options_to_proto(const rac_embeddings_options_t* in,
                                     ::runanywhere::v1::EmbeddingsOptions* out) {
    if (!in || !out) return false;
    out->Clear();
    // C `normalize` uses -1 sentinel for "use config default"; on the wire,
    // proto `normalize` is non-optional bool (defaults to false). Treat -1
    // as false on the way out.
    out->set_normalize(in->normalize == RAC_EMBEDDINGS_NORMALIZE_L2);
    return true;
}

bool rac_embeddings_options_from_proto(
    const ::runanywhere::v1::EmbeddingsOptions& in,
    rac_embeddings_options_t* out) {
    if (!out) return false;
    *out = RAC_EMBEDDINGS_OPTIONS_DEFAULT;
    out->normalize = in.normalize() ? RAC_EMBEDDINGS_NORMALIZE_L2
                                    : RAC_EMBEDDINGS_NORMALIZE_NONE;
    return true;
}

bool rac_embedding_vector_to_proto(const rac_embedding_vector_t* in,
                                   ::runanywhere::v1::EmbeddingVector* out) {
    if (!in || !out) return false;
    out->Clear();
    for (size_t i = 0; i < in->dimension; ++i) {
        out->add_values(in->data[i]);
    }
    return true;
}

bool rac_embedding_vector_from_proto(const ::runanywhere::v1::EmbeddingVector& in,
                                     rac_embedding_vector_t* out) {
    if (!out) return false;
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
    if (!in || !out) return false;
    out->Clear();
    for (size_t i = 0; i < in->num_embeddings; ++i) {
        rac_embedding_vector_to_proto(&in->embeddings[i], out->add_vectors());
    }
    out->set_dimension(static_cast<int32_t>(in->dimension));
    out->set_processing_time_ms(in->processing_time_ms);
    out->set_tokens_used(in->total_tokens);
    return true;
}

bool rac_embeddings_result_from_proto(const ::runanywhere::v1::EmbeddingsResult& in,
                                      rac_embeddings_result_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    out->dimension = static_cast<size_t>(in.dimension());
    out->processing_time_ms = in.processing_time_ms();
    out->total_tokens = in.tokens_used();
    if (in.vectors_size() > 0) {
        out->num_embeddings = static_cast<size_t>(in.vectors_size());
        out->embeddings = static_cast<rac_embedding_vector_t*>(
            rac_alloc(sizeof(rac_embedding_vector_t) * out->num_embeddings));
        for (int i = 0; i < in.vectors_size(); ++i) {
            rac_embedding_vector_from_proto(in.vectors(i), &out->embeddings[i]);
        }
    }
    return true;
}

// ===========================================================================
// STORAGE
// ===========================================================================

bool rac_device_storage_to_proto(const rac_device_storage_t* in,
                                 ::runanywhere::v1::DeviceStorageInfo* out) {
    if (!in || !out) return false;
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
    if (!out) return false;
    out->total_space = in.total_bytes();
    out->free_space = in.free_bytes();
    out->used_space = in.used_bytes();
    return true;
}

bool rac_app_storage_to_proto(const rac_app_storage_t* in,
                              ::runanywhere::v1::AppStorageInfo* out) {
    if (!in || !out) return false;
    out->Clear();
    out->set_documents_bytes(in->documents_size);
    out->set_cache_bytes(in->cache_size);
    out->set_app_support_bytes(in->app_support_size);
    out->set_total_bytes(in->total_size);
    return true;
}

bool rac_app_storage_from_proto(const ::runanywhere::v1::AppStorageInfo& in,
                                rac_app_storage_t* out) {
    if (!out) return false;
    out->documents_size = in.documents_bytes();
    out->cache_size = in.cache_bytes();
    out->app_support_size = in.app_support_bytes();
    out->total_size = in.total_bytes();
    return true;
}

bool rac_model_storage_metrics_to_proto(
    const rac_model_storage_metrics_t* in,
    ::runanywhere::v1::ModelStorageMetrics* out) {
    if (!in || !out) return false;
    out->Clear();
    if (in->model_id) out->set_model_id(in->model_id);
    out->set_size_on_disk_bytes(in->size_on_disk);
    return true;
}

bool rac_model_storage_metrics_from_proto(
    const ::runanywhere::v1::ModelStorageMetrics& in,
    rac_model_storage_metrics_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    out->model_id = copy_string(in.model_id());
    out->size_on_disk = in.size_on_disk_bytes();
    return true;
}

bool rac_storage_info_to_proto(const rac_storage_info_t* in,
                               ::runanywhere::v1::StorageInfo* out) {
    if (!in || !out) return false;
    out->Clear();
    rac_app_storage_to_proto(&in->app_storage, out->mutable_app());
    rac_device_storage_to_proto(&in->device_storage, out->mutable_device());
    for (size_t i = 0; i < in->model_count; ++i) {
        rac_model_storage_metrics_to_proto(&in->models[i], out->add_models());
    }
    out->set_total_models(static_cast<int32_t>(in->model_count));
    out->set_total_models_bytes(in->total_models_size);
    return true;
}

bool rac_storage_info_from_proto(const ::runanywhere::v1::StorageInfo& in,
                                 rac_storage_info_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    if (in.has_app()) rac_app_storage_from_proto(in.app(), &out->app_storage);
    if (in.has_device()) rac_device_storage_from_proto(in.device(), &out->device_storage);
    if (in.models_size() > 0) {
        out->model_count = static_cast<size_t>(in.models_size());
        out->models = static_cast<rac_model_storage_metrics_t*>(
            rac_alloc(sizeof(rac_model_storage_metrics_t) * out->model_count));
        for (int i = 0; i < in.models_size(); ++i) {
            rac_model_storage_metrics_from_proto(in.models(i), &out->models[i]);
        }
    }
    out->total_models_size = in.total_models_bytes();
    return true;
}

bool rac_storage_availability_to_proto(
    const rac_storage_availability_t* in,
    ::runanywhere::v1::StorageAvailability* out) {
    if (!in || !out) return false;
    out->Clear();
    out->set_is_available(in->is_available == RAC_TRUE);
    out->set_required_bytes(in->required_space);
    out->set_available_bytes(in->available_space);
    if (in->has_warning == RAC_TRUE) {
        out->set_warning_message("low storage");
    }
    if (in->recommendation) {
        out->set_recommendation(in->recommendation);
    }
    return true;
}

bool rac_storage_availability_from_proto(
    const ::runanywhere::v1::StorageAvailability& in,
    rac_storage_availability_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    out->is_available = in.is_available() ? RAC_TRUE : RAC_FALSE;
    out->required_space = in.required_bytes();
    out->available_space = in.available_bytes();
    out->has_warning = in.has_warning_message() ? RAC_TRUE : RAC_FALSE;
    out->recommendation = in.has_recommendation() ? copy_string(in.recommendation())
                                                  : nullptr;
    return true;
}

// ===========================================================================
// ERRORS
// ===========================================================================

::runanywhere::v1::ErrorCode rac_result_to_proto_error_code(rac_result_t code) {
    if (code == RAC_SUCCESS) return ::runanywhere::v1::ERROR_CODE_UNSPECIFIED;
    int32_t magnitude = (code < 0) ? -code : code;
    // The proto enum mirrors abs() of the C codes for the well-known ranges.
    // Use a switch on the magnitude to avoid runtime errors on out-of-bounds
    // values; unknown codes fall through to ERROR_CODE_UNKNOWN.
    switch (magnitude) {
        case 100: return ::runanywhere::v1::ERROR_CODE_NOT_INITIALIZED;
        case 101: return ::runanywhere::v1::ERROR_CODE_ALREADY_INITIALIZED;
        case 102: return ::runanywhere::v1::ERROR_CODE_INITIALIZATION_FAILED;
        case 103: return ::runanywhere::v1::ERROR_CODE_INVALID_CONFIGURATION;
        case 104: return ::runanywhere::v1::ERROR_CODE_INVALID_API_KEY;
        case 105: return ::runanywhere::v1::ERROR_CODE_ENVIRONMENT_MISMATCH;
        case 106: return ::runanywhere::v1::ERROR_CODE_INVALID_PARAMETER;
        case 110: return ::runanywhere::v1::ERROR_CODE_MODEL_NOT_FOUND;
        case 111: return ::runanywhere::v1::ERROR_CODE_MODEL_LOAD_FAILED;
        case 112: return ::runanywhere::v1::ERROR_CODE_MODEL_VALIDATION_FAILED;
        case 113: return ::runanywhere::v1::ERROR_CODE_MODEL_INCOMPATIBLE;
        case 114: return ::runanywhere::v1::ERROR_CODE_INVALID_MODEL_FORMAT;
        case 115: return ::runanywhere::v1::ERROR_CODE_MODEL_STORAGE_CORRUPTED;
        case 116: return ::runanywhere::v1::ERROR_CODE_MODEL_NOT_LOADED;
        case 130: return ::runanywhere::v1::ERROR_CODE_GENERATION_FAILED;
        case 131: return ::runanywhere::v1::ERROR_CODE_GENERATION_TIMEOUT;
        case 132: return ::runanywhere::v1::ERROR_CODE_CONTEXT_TOO_LONG;
        case 133: return ::runanywhere::v1::ERROR_CODE_TOKEN_LIMIT_EXCEEDED;
        case 150: return ::runanywhere::v1::ERROR_CODE_NETWORK_UNAVAILABLE;
        case 151: return ::runanywhere::v1::ERROR_CODE_NETWORK_ERROR;
        case 153: return ::runanywhere::v1::ERROR_CODE_DOWNLOAD_FAILED;
        case 155: return ::runanywhere::v1::ERROR_CODE_TIMEOUT;
        case 180: return ::runanywhere::v1::ERROR_CODE_INSUFFICIENT_STORAGE;
        case 183: return ::runanywhere::v1::ERROR_CODE_FILE_NOT_FOUND;
        case 220: return ::runanywhere::v1::ERROR_CODE_HARDWARE_UNSUPPORTED;
        case 221: return ::runanywhere::v1::ERROR_CODE_INSUFFICIENT_MEMORY;
        case 230: return ::runanywhere::v1::ERROR_CODE_COMPONENT_NOT_READY;
        case 231: return ::runanywhere::v1::ERROR_CODE_INVALID_STATE;
        case 232: return ::runanywhere::v1::ERROR_CODE_SERVICE_NOT_AVAILABLE;
        case 250: return ::runanywhere::v1::ERROR_CODE_VALIDATION_FAILED;
        case 251: return ::runanywhere::v1::ERROR_CODE_INVALID_INPUT;
        case 259: return ::runanywhere::v1::ERROR_CODE_INVALID_ARGUMENT;
        case 260: return ::runanywhere::v1::ERROR_CODE_NULL_POINTER;
        case 320: return ::runanywhere::v1::ERROR_CODE_AUTHENTICATION_FAILED;
        case 380: return ::runanywhere::v1::ERROR_CODE_CANCELLED;
        case 800: return ::runanywhere::v1::ERROR_CODE_NOT_IMPLEMENTED;
        case 801: return ::runanywhere::v1::ERROR_CODE_FEATURE_NOT_AVAILABLE;
        case 804: return ::runanywhere::v1::ERROR_CODE_UNKNOWN;
        case 805: return ::runanywhere::v1::ERROR_CODE_INTERNAL;
        default:  return ::runanywhere::v1::ERROR_CODE_UNKNOWN;
    }
}

rac_result_t rac_proto_error_code_to_result(::runanywhere::v1::ErrorCode code) {
    if (code == ::runanywhere::v1::ERROR_CODE_UNSPECIFIED) return RAC_SUCCESS;
    int32_t magnitude = static_cast<int32_t>(code);
    return -magnitude;
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

bool rac_error_to_proto(const rac_error_t* in,
                        ::runanywhere::v1::SDKError* out) {
    if (!in || !out) return false;
    out->Clear();
    out->set_code(rac_result_to_proto_error_code(in->code));
    out->set_category(rac_category_to_proto(in->category));
    out->set_message(in->message);
    out->set_c_abi_code(in->code);
    if (in->underlying_message[0] != '\0') {
        out->set_nested_message(in->underlying_message);
    }
    auto* ctx = out->mutable_context();
    if (in->source_file[0] != '\0') ctx->set_source_file(in->source_file);
    if (in->source_line > 0) ctx->set_source_line(in->source_line);
    if (in->source_function[0] != '\0') ctx->set_operation(in->source_function);
    auto* metadata = ctx->mutable_metadata();
    if (in->model_id[0] != '\0') (*metadata)["model_id"] = in->model_id;
    if (in->framework[0] != '\0') (*metadata)["framework"] = in->framework;
    if (in->session_id[0] != '\0') (*metadata)["session_id"] = in->session_id;
    if (in->custom_key1[0] != '\0' && in->custom_value1[0] != '\0')
        (*metadata)[in->custom_key1] = in->custom_value1;
    if (in->custom_key2[0] != '\0' && in->custom_value2[0] != '\0')
        (*metadata)[in->custom_key2] = in->custom_value2;
    if (in->custom_key3[0] != '\0' && in->custom_value3[0] != '\0')
        (*metadata)[in->custom_key3] = in->custom_value3;
    return true;
}

bool rac_error_from_proto(const ::runanywhere::v1::SDKError& in,
                          rac_error_t* out) {
    if (!out) return false;
    std::memset(out, 0, sizeof(*out));
    if (in.has_c_abi_code()) {
        out->code = in.c_abi_code();
    } else {
        out->code = rac_proto_error_code_to_result(in.code());
    }
    out->category = rac_proto_to_category(in.category());
    std::strncpy(out->message, in.message().c_str(), RAC_MAX_ERROR_MESSAGE - 1);
    if (in.has_nested_message()) {
        std::strncpy(out->underlying_message, in.nested_message().c_str(),
                     RAC_MAX_ERROR_MESSAGE - 1);
    }
    if (in.has_context()) {
        const auto& ctx = in.context();
        if (ctx.has_source_file()) {
            std::strncpy(out->source_file, ctx.source_file().c_str(),
                         RAC_MAX_METADATA_STRING - 1);
        }
        if (ctx.has_source_line()) {
            out->source_line = ctx.source_line();
        }
        if (ctx.has_operation()) {
            std::strncpy(out->source_function, ctx.operation().c_str(),
                         RAC_MAX_METADATA_STRING - 1);
        }
        const auto& metadata = ctx.metadata();
        auto it = metadata.find("model_id");
        if (it != metadata.end()) {
            std::strncpy(out->model_id, it->second.c_str(),
                         RAC_MAX_METADATA_STRING - 1);
        }
        it = metadata.find("framework");
        if (it != metadata.end()) {
            std::strncpy(out->framework, it->second.c_str(),
                         RAC_MAX_METADATA_STRING - 1);
        }
        it = metadata.find("session_id");
        if (it != metadata.end()) {
            std::strncpy(out->session_id, it->second.c_str(),
                         RAC_MAX_METADATA_STRING - 1);
        }
        // Populate custom_key1..3 with any remaining unique entries.
        int slot = 1;
        for (const auto& kv : metadata) {
            if (kv.first == "model_id" || kv.first == "framework" ||
                kv.first == "session_id")
                continue;
            if (slot == 1) {
                std::strncpy(out->custom_key1, kv.first.c_str(), 63);
                std::strncpy(out->custom_value1, kv.second.c_str(),
                             RAC_MAX_METADATA_STRING - 1);
            } else if (slot == 2) {
                std::strncpy(out->custom_key2, kv.first.c_str(), 63);
                std::strncpy(out->custom_value2, kv.second.c_str(),
                             RAC_MAX_METADATA_STRING - 1);
            } else if (slot == 3) {
                std::strncpy(out->custom_key3, kv.first.c_str(), 63);
                std::strncpy(out->custom_value3, kv.second.c_str(),
                             RAC_MAX_METADATA_STRING - 1);
            } else {
                break;
            }
            ++slot;
        }
    }
    return true;
}

}  // namespace rac::foundation

#endif  // RAC_HAVE_PROTOBUF
