/**
 * @file cmd_stt.cpp
 * @brief `rcli stt --input a.wav [model]` — file transcription via the STT
 *        component (same call sequence as the commons real-inference tests).
 */

#include "commands/commands.h"

#include <chrono>
#include <memory>
#include <string>

#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_service.h"

#include "commands/model_setup.h"
#include "io/output.h"
#include "io/wav_io.h"

namespace rcli::commands {

namespace {

constexpr const char* kDefaultSttModel = "sherpa-onnx-whisper-tiny.en";
constexpr int kSttSampleRate = 16000;

int run_stt(const GlobalOptions& options, const std::string& ref, const std::string& input) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    ResolvedModelPaths model;
    const int setup = ensure_model_ready(options, ref.empty() ? kDefaultSttModel : ref, &model);
    if (setup != 0) {
        return setup;
    }

    wav::WavData audio;
    std::string error;
    if (!wav::read_wav(input, &audio, &error)) {
        out::error_line(error);
        return 1;
    }
    const std::vector<int16_t> pcm16 = wav::resample(audio.samples, audio.sample_rate,
                                                     kSttSampleRate);

    rac_handle_t stt = nullptr;
    if (rac_stt_component_create(&stt) != RAC_SUCCESS) {
        out::error_line("failed to create STT component");
        return 1;
    }
    rac_result_t rc = rac_stt_component_load_model(stt, model.primary_path.c_str(),
                                                   model.model_id.c_str(),
                                                   model.display_name.c_str());
    if (rc != RAC_SUCCESS) {
        out::error_line("failed to load STT model: " + out::describe_result(rc));
        rac_stt_component_destroy(stt);
        return 1;
    }

    const auto started = std::chrono::steady_clock::now();
    rac_stt_result_t result = {};
    rc = rac_stt_component_transcribe(stt, pcm16.data(), pcm16.size() * sizeof(int16_t), nullptr,
                                      &result);
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                             std::chrono::steady_clock::now() - started)
                             .count();

    int exit_code = 0;
    if (rc != RAC_SUCCESS) {
        out::error_line("transcription failed: " + out::describe_result(rc));
        exit_code = 1;
    } else {
        const std::string text = result.text ? result.text : "";
        if (options.json) {
            out::JsonWriter json;
            json.begin_object()
                .field("model", model.model_id)
                .field("text", text)
                .field("confidence", static_cast<double>(result.confidence))
                .field("total_ms", static_cast<int64_t>(elapsed))
                .end_object();
            out::result_line(json.str());
        } else {
            out::result_line(text);
            if (options.verbose) {
                out::status_line("(" + std::to_string(elapsed) + " ms)");
            }
        }
        rac_stt_result_free(&result);
    }

    rac_stt_component_destroy(stt);
    return exit_code;
}

}  // namespace

void register_stt(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("stt", "Transcribe a WAV file (speech-to-text)");
    auto ref = std::make_shared<std::string>();
    auto input = std::make_shared<std::string>();
    cmd->add_option("model", *ref, "STT model (default: " + std::string(kDefaultSttModel) + ")");
    cmd->add_option("--input,-i", *input, "16-bit PCM WAV file")
        ->required()
        ->check(CLI::ExistingFile);
    cmd->callback([&options, ref, input]() {
        const int exit_code = run_stt(options, *ref, *input);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
