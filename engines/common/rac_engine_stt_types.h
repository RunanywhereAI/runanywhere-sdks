#ifndef RUNANYWHERE_ENGINES_COMMON_STT_TYPES_H
#define RUNANYWHERE_ENGINES_COMMON_STT_TYPES_H

/**
 * Shared internal STT request/result types for engine backends.
 *
 * Backends (sherpa, whispercpp) previously each redefined these structs in
 * their own headers, producing an ODR landmine the moment any TU pulled in
 * both backend headers (cross-backend orchestrator, JNI bridge, test fixture).
 * Defining them once here in engines/common/ — the same place DeviceType
 * already lives — collapses the duplication to a single source of truth.
 *
 * The fields are the SUPERSET across backends: sherpa ignores
 * `translate_to_english` and `word_timings`; whispercpp ignores the
 * NEMO_CTC enumerator. Defaulted members mean each backend pays no
 * runtime cost for the fields it does not use.
 *
 * Internal to the engines/ tree. Not part of the stable rac_* C ABI; that
 * surface uses the POD `rac_stt_*` structs.
 */

#include <string>
#include <vector>

namespace runanywhere {

// Recognized STT model architectures. NEMO_CTC is sherpa-only; whispercpp
// only ever loads WHISPER. Kept in a single enum so cross-backend code can
// pass values around without bouncing through string conversions.
enum class STTModelType {
    WHISPER = 0,
    ZIPFORMER = 1,
    TRANSDUCER = 2,
    PARAFORMER = 3,
    NEMO_CTC = 4,
    CUSTOM = 5,
};

struct WordTiming {
    std::string word;
    double start_time_ms = 0.0;
    double end_time_ms = 0.0;
    float confidence = 0.0f;
};

struct AudioSegment {
    std::string text;
    double start_time_ms = 0.0;
    double end_time_ms = 0.0;
    float confidence = 0.0f;
    std::string language;
};

struct STTRequest {
    std::vector<float> audio_samples;
    int sample_rate = 16000;
    std::string language;
    bool detect_language = false;
    bool word_timestamps = false;
    // whispercpp-only: ask the model to translate non-English speech into
    // English. Ignored by sherpa, which has no equivalent path.
    bool translate_to_english = false;
};

struct STTResult {
    std::string text;
    std::string detected_language;
    std::vector<AudioSegment> segments;
    // whispercpp-only: populated when STTRequest::word_timestamps is true.
    // Always empty for sherpa results.
    std::vector<WordTiming> word_timings;
    double audio_duration_ms = 0.0;
    double inference_time_ms = 0.0;
    float confidence = 0.0f;
    bool is_final = true;
};

}  // namespace runanywhere

#endif  // RUNANYWHERE_ENGINES_COMMON_STT_TYPES_H
