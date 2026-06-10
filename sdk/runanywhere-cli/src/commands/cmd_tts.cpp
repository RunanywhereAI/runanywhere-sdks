/**
 * @file cmd_tts.cpp
 * @brief `rcli tts --text "..." --output o.wav [voice]` — synthesize speech.
 *
 * The sherpa TTS engine returns float PCM at the voice's native sample rate
 * (see tests/test_voice_agent.cpp fixture synthesis); converted to int16 WAV.
 */

#include "commands/commands.h"

#include <chrono>
#include <memory>
#include <string>

#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_types.h"

#include "commands/model_setup.h"
#include "io/output.h"
#include "io/wav_io.h"

namespace rcli::commands {

namespace {

constexpr const char* kDefaultVoice = "vits-piper-en_US-lessac-medium";

int run_tts(const GlobalOptions& options, const std::string& ref, const std::string& text,
            const std::string& output) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

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
    rac_result_t rc = rac_tts_component_load_voice(tts, voice.primary_path.c_str(),
                                                   voice.model_id.c_str(),
                                                   voice.display_name.c_str());
    if (rc != RAC_SUCCESS) {
        out::error_line("failed to load voice: " + out::describe_result(rc));
        rac_tts_component_destroy(tts);
        return 1;
    }

    const auto started = std::chrono::steady_clock::now();
    rac_tts_result_t result = {};
    rc = rac_tts_component_synthesize(tts, text.c_str(), nullptr, &result);
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                             std::chrono::steady_clock::now() - started)
                             .count();

    int exit_code = 0;
    if (rc != RAC_SUCCESS || !result.audio_data || result.audio_size == 0) {
        out::error_line("synthesis failed: " + out::describe_result(rc));
        exit_code = 1;
    } else {
        // Engine emits float PCM at the voice's native rate.
        const auto* float_samples = static_cast<const float*>(result.audio_data);
        const size_t sample_count = result.audio_size / sizeof(float);
        const std::vector<int16_t> pcm16 = wav::to_int16(float_samples, sample_count);

        std::string error;
        if (!wav::write_wav(output, pcm16.data(), pcm16.size(), result.sample_rate, &error)) {
            out::error_line(error);
            exit_code = 1;
        } else if (options.json) {
            out::JsonWriter json;
            json.begin_object()
                .field("voice", voice.model_id)
                .field("path", output)
                .field("sample_rate", static_cast<int64_t>(result.sample_rate))
                .field("duration_ms",
                       static_cast<int64_t>(sample_count * 1000 /
                                            static_cast<size_t>(result.sample_rate)))
                .field("total_ms", static_cast<int64_t>(elapsed))
                .end_object();
            out::result_line(json.str());
        } else {
            out::result_line(output);
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

void register_tts(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("tts", "Synthesize speech to a WAV file");
    auto ref = std::make_shared<std::string>();
    auto text = std::make_shared<std::string>();
    auto output = std::make_shared<std::string>();
    cmd->add_option("voice", *ref, "TTS voice (default: " + std::string(kDefaultVoice) + ")");
    cmd->add_option("--text,-t", *text, "Text to speak")->required();
    cmd->add_option("--output,-o", *output, "Output WAV path")->required();
    cmd->callback([&options, ref, text, output]() {
        const int exit_code = run_tts(options, *ref, *text, *output);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
