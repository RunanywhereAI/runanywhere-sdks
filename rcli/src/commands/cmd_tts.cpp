/**
 * @file cmd_tts.cpp
 * @brief `rcli tts synthesize "text" --output o.wav` — speech synthesis.
 *
 * `rcli tts --text "…" --output o.wav` is the same command: the options live on
 * the `tts` namespace and `synthesize` is a CLI11 fallthrough alias.
 *
 * The sherpa TTS engine returns float PCM at the voice's native sample rate
 * (see tests/test_voice_agent.cpp fixture synthesis); converted to int16 WAV.
 */

#include <chrono>
#include <memory>
#include <string>

#include "commands/commands.h"
#include "commands/model_setup.h"
#include "io/output.h"
#include "io/wav_io.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_types.h"

namespace rcli::commands {

namespace {

constexpr const char* kDefaultVoice = "vits-piper-en_US-lessac-medium";

struct TtsParams {
    std::string model;
    std::string voice;
    std::string positional_text;
    std::string text;  // --text/-t spelling of the same string
    std::string output;
    std::string language;
    float speed = 1.0f;
    float pitch = 1.0f;
    int32_t sample_rate = 0;  // 0 = the voice's native rate
};

int run_tts(const GlobalOptions& options, const TtsParams& params) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    const std::string& text = params.positional_text.empty() ? params.text : params.positional_text;
    if (text.empty()) {
        out::error_line("text to speak is required (positional or --text)");
        return 2;
    }
    if (params.output.empty()) {
        out::error_line("--output is required");
        return 2;
    }

    const std::string& ref = !params.model.empty() ? params.model : params.voice;
    ResolvedModelPaths voice;
    const int setup = ensure_model_ready(options, ref.empty() ? kDefaultVoice : ref, &voice);
    if (setup != 0) {
        return setup;
    }

    rac_handle_t tts = nullptr;
    if (rac_tts_component_create(&tts) != RAC_SUCCESS) {
        out::error_line("failed to create TTS component");
        return 1;
    }
    rac_result_t rc = rac_tts_component_load_voice(
        tts, voice.primary_path.c_str(), voice.model_id.c_str(), voice.display_name.c_str());
    if (rc != RAC_SUCCESS) {
        out::error_line("failed to load voice: " + out::describe_result(rc));
        rac_tts_component_destroy(tts);
        return 1;
    }

    rac_tts_options_t tts_options = RAC_TTS_OPTIONS_DEFAULT;
    tts_options.voice = params.voice.empty() ? nullptr : params.voice.c_str();
    if (!params.language.empty()) {
        tts_options.language = params.language.c_str();
    }
    tts_options.rate = params.speed;
    tts_options.pitch = params.pitch;
    if (params.sample_rate > 0) {
        tts_options.sample_rate = params.sample_rate;
    }

    const auto started = std::chrono::steady_clock::now();
    rac_tts_result_t result = {};
    rc = rac_tts_component_synthesize(tts, text.c_str(), &tts_options, &result);
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                             std::chrono::steady_clock::now() - started)
                             .count();

    int exit_code = 0;
    if (rc != RAC_SUCCESS || !result.audio_data || result.audio_size == 0) {
        out::error_line("synthesis failed: " + out::describe_result(rc));
        exit_code = 1;
    } else {
        // Engine emits float PCM at the voice's native rate; commons builds the WAV.
        const auto* float_samples = static_cast<const float*>(result.audio_data);
        const size_t sample_count = result.audio_size / sizeof(float);

        std::string error;
        if (!wav::write_wav_f32(params.output, float_samples, sample_count, result.sample_rate,
                                &error)) {
            out::error_line(error);
            exit_code = 1;
        } else if (options.json) {
            out::JsonWriter json;
            json.begin_object()
                .field("voice", voice.model_id)
                .field("path", params.output)
                .field("sample_rate", static_cast<int64_t>(result.sample_rate))
                .field("duration_ms", static_cast<int64_t>(result.duration_ms))
                .field("total_ms", static_cast<int64_t>(elapsed))
                .end_object();
            out::result_line(json.str());
        } else {
            out::result_line(params.output);
            if (options.verbose) {
                out::status_line("(" + std::to_string(elapsed) + " ms, " +
                                 std::to_string(result.sample_rate) + " Hz)");
            }
        }
        rac_tts_result_free(&result);
    }

    rac_tts_component_destroy(tts);
    return exit_code;
}

}  // namespace

int synthesize_to_file(const GlobalOptions& options, const std::string& voice_ref,
                       const std::string& text, const std::string& output_path) {
    ResolvedModelPaths voice;
    const int setup =
        ensure_model_ready(options, voice_ref.empty() ? kDefaultVoice : voice_ref, &voice);
    if (setup != 0) {
        return setup;
    }

    rac_handle_t tts = nullptr;
    if (rac_tts_component_create(&tts) != RAC_SUCCESS) {
        out::error_line("failed to create TTS component");
        return 1;
    }
    rac_result_t rc = rac_tts_component_load_voice(
        tts, voice.primary_path.c_str(), voice.model_id.c_str(), voice.display_name.c_str());
    if (rc != RAC_SUCCESS) {
        out::error_line("failed to load voice: " + out::describe_result(rc));
        rac_tts_component_destroy(tts);
        return 1;
    }

    rac_tts_options_t tts_options = RAC_TTS_OPTIONS_DEFAULT;
    rac_tts_result_t result = {};
    rc = rac_tts_component_synthesize(tts, text.c_str(), &tts_options, &result);

    int exit_code = 0;
    if (rc != RAC_SUCCESS || !result.audio_data || result.audio_size == 0) {
        out::error_line("synthesis failed: " + out::describe_result(rc));
        exit_code = 1;
    } else {
        const auto* float_samples = static_cast<const float*>(result.audio_data);
        const size_t sample_count = result.audio_size / sizeof(float);
        std::string error;
        if (!wav::write_wav_f32(output_path, float_samples, sample_count, result.sample_rate,
                                &error)) {
            out::error_line(error);
            exit_code = 1;
        }
        rac_tts_result_free(&result);
    }
    rac_tts_component_destroy(tts);
    return exit_code;
}

void register_tts(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("tts", "Speak text with an on-device voice");
    cmd->require_subcommand(0, 1);
    add_verb_alias(cmd, "synthesize", "Write spoken audio to a WAV file");

    auto params = std::make_shared<TtsParams>();
    // CLI11 matches option names without their dashes, so the positional
    // cannot also be called "text" while `--text` exists.
    cmd->add_option("TEXT", params->positional_text, "Text to speak");
    cmd->add_option("--text,-t", params->text, "Text to speak");
    cmd->add_option("--output,-o", params->output, "WAV file to write");
    cmd->add_option("--model,-m", params->model,
                    "Voice model to load (default: " + std::string(kDefaultVoice) + ")");
    cmd->add_option("--voice", params->voice, "Voice inside the model to speak with");
    cmd->add_option("--language", params->language, "BCP-47 language to speak (default en-US)");
    cmd->add_option("--speed", params->speed, "Speak faster or slower than 1.0");
    cmd->add_option("--pitch", params->pitch, "Raise or lower the pitch from 1.0");
    cmd->add_option("--sample-rate", params->sample_rate,
                    "Output sample rate in Hz (0 = the voice's own)");
    cmd->callback([&options, params]() {
        const int exit_code = run_tts(options, *params);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
