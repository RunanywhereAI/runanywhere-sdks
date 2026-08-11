/**
 * @file cmd_stt.cpp
 * @brief `rcli stt transcribe <audio.wav>` — file transcription via the STT
 *        component (same call sequence as the commons real-inference tests).
 *
 * `rcli stt --input a.wav` is the same command: the options live on the `stt`
 * namespace and `transcribe` is a CLI11 fallthrough alias, so both spellings
 * reach one callback.
 */

#include "commands/commands.h"

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

struct SttParams {
    std::string model;
    std::string audio;
    std::string input;  // --input/-i spelling of the same file
    std::string language;
    bool punctuation = true;
    bool word_timestamps = true;
    bool diarization = false;
    int32_t max_speakers = 0;
};

int run_stt(const GlobalOptions& options, const SttParams& params) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    const std::string& audio_path = params.audio.empty() ? params.input : params.audio;
    if (audio_path.empty()) {
        out::error_line("an audio file is required (positional or --input)");
        return 2;
    }

    ResolvedModelPaths model;
    const int setup = ensure_model_ready(
        options, params.model.empty() ? kDefaultSttModel : params.model, &model);
    if (setup != 0) {
        return setup;
    }

    wav::WavData audio;
    std::string error;
    if (!wav::read_wav(audio_path, &audio, &error)) {
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

    rac_stt_options_t stt_options = RAC_STT_OPTIONS_DEFAULT;
    stt_options.language = params.language.empty() ? nullptr : params.language.c_str();
    stt_options.detect_language = params.language.empty() ? RAC_TRUE : RAC_FALSE;
    stt_options.enable_punctuation = params.punctuation ? RAC_TRUE : RAC_FALSE;
    stt_options.enable_timestamps = params.word_timestamps ? RAC_TRUE : RAC_FALSE;
    stt_options.enable_diarization = params.diarization ? RAC_TRUE : RAC_FALSE;
    stt_options.max_speakers = params.max_speakers;
    stt_options.sample_rate = kSttSampleRate;

    rac_stt_result_t result = {};
    rc = rac_stt_component_transcribe(stt, pcm16.data(), pcm16.size() * sizeof(int16_t),
                                      &stt_options, &result);

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
                .field("language", result.detected_language ? result.detected_language : "")
                .field("confidence", static_cast<double>(result.confidence))
                .field("total_ms", result.processing_time_ms);
            json.begin_array("words");
            for (size_t i = 0; i < result.num_words; ++i) {
                const rac_stt_word_t& word = result.words[i];
                json.begin_array_object()
                    .field("text", word.text ? word.text : "")
                    .field("start_ms", static_cast<int64_t>(word.start_ms))
                    .field("end_ms", static_cast<int64_t>(word.end_ms))
                    .field("confidence", static_cast<double>(word.confidence))
                    .end_object();
            }
            json.end_array().end_object();
            out::result_line(json.str());
        } else {
            out::result_line(text);
            if (options.verbose) {
                out::status_line("(" + std::to_string(result.processing_time_ms) + " ms)");
            }
        }
        rac_stt_result_free(&result);
    }

    rac_stt_component_destroy(stt);
    return exit_code;
}

}  // namespace

void register_stt(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("stt", "Turn recorded speech into text");
    cmd->require_subcommand(0, 1);
    add_verb_alias(cmd, "transcribe", "Transcribe an audio file");

    auto params = std::make_shared<SttParams>();
    cmd->add_option("audio", params->audio, "16-bit PCM WAV file")->check(CLI::ExistingFile);
    cmd->add_option("--input,-i", params->input, "16-bit PCM WAV file")->check(CLI::ExistingFile);
    cmd->add_option("--model,-m", params->model,
                    "STT model to use (default: " + std::string(kDefaultSttModel) + ")");
    cmd->add_option("--language", params->language,
                    "BCP-47 language of the speech (omit to auto-detect)");
    cmd->add_flag("--punctuation,!--no-punctuation", params->punctuation,
                  "Punctuate the transcript (default on)");
    cmd->add_flag("--word-timestamps,!--no-word-timestamps", params->word_timestamps,
                  "Report per-word timings (default on)");
    cmd->add_flag("--diarization", params->diarization, "Attribute words to speakers");
    cmd->add_option("--max-speakers", params->max_speakers,
                    "Cap the speakers diarization may find");
    cmd->callback([&options, params]() {
        const int exit_code = run_stt(options, *params);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
