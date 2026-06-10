/**
 * @file cmd_vad.cpp
 * @brief `rcli vad --input a.wav [model]` — speech segment detection.
 *
 * Feeds 16 kHz float frames through the VAD component (Silero when the model
 * is loaded, energy-based otherwise) and derives segments from
 * is_speech_active transitions.
 */

#include "commands/commands.h"

#include <memory>
#include <string>
#include <vector>

#include "rac/features/vad/rac_vad_component.h"

#include "commands/model_setup.h"
#include "io/output.h"
#include "io/wav_io.h"

namespace rcli::commands {

namespace {

constexpr const char* kDefaultVadModel = "silero-vad";
constexpr int kVadSampleRate = 16000;
constexpr size_t kVadFrameSamples = 512;  // Silero's native frame size @16 kHz

struct Segment {
    double start_s;
    double end_s;
};

int run_vad(const GlobalOptions& options, const std::string& ref, const std::string& input) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    ResolvedModelPaths model;
    const int setup = ensure_model_ready(options, ref.empty() ? kDefaultVadModel : ref, &model);
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
                                                     kVadSampleRate);
    const std::vector<float> samples = wav::to_float(pcm16);

    rac_handle_t vad = nullptr;
    if (rac_vad_component_create(&vad) != RAC_SUCCESS) {
        out::error_line("failed to create VAD component");
        return 1;
    }
    rac_result_t rc = rac_vad_component_load_model(vad, model.primary_path.c_str(),
                                                   model.model_id.c_str(),
                                                   model.display_name.c_str());
    if (rc != RAC_SUCCESS) {
        out::error_line("failed to load VAD model: " + out::describe_result(rc));
        rac_vad_component_destroy(vad);
        return 1;
    }
    if (rac_vad_component_initialize(vad) != RAC_SUCCESS ||
        rac_vad_component_start(vad) != RAC_SUCCESS) {
        out::error_line("failed to start VAD");
        rac_vad_component_destroy(vad);
        return 1;
    }

    std::vector<Segment> segments;
    bool in_speech = false;
    double segment_start = 0.0;
    for (size_t offset = 0; offset + kVadFrameSamples <= samples.size();
         offset += kVadFrameSamples) {
        rac_bool_t frame_is_speech = RAC_FALSE;
        rac_vad_component_process(vad, samples.data() + offset, kVadFrameSamples,
                                  &frame_is_speech);
        const bool active = frame_is_speech == RAC_TRUE;
        const double t = static_cast<double>(offset + kVadFrameSamples) / kVadSampleRate;
        if (active && !in_speech) {
            in_speech = true;
            segment_start = static_cast<double>(offset) / kVadSampleRate;
        } else if (!active && in_speech) {
            in_speech = false;
            segments.push_back({segment_start, t});
        }
    }
    if (in_speech) {
        segments.push_back(
            {segment_start, static_cast<double>(samples.size()) / kVadSampleRate});
    }
    rac_vad_component_stop(vad);
    rac_vad_component_destroy(vad);

    if (options.json) {
        out::JsonWriter json;
        json.begin_object().field("model", model.model_id).begin_array("segments");
        for (const Segment& segment : segments) {
            json.begin_array_object()
                .field("start_s", segment.start_s)
                .field("end_s", segment.end_s)
                .end_object();
        }
        json.end_array().end_object();
        out::result_line(json.str());
        return 0;
    }

    if (segments.empty()) {
        out::result_line("no speech detected");
        return 0;
    }
    std::vector<std::vector<std::string>> rows;
    char buffer[64];
    for (const Segment& segment : segments) {
        std::snprintf(buffer, sizeof(buffer), "%.2fs", segment.start_s);
        std::string start = buffer;
        std::snprintf(buffer, sizeof(buffer), "%.2fs", segment.end_s);
        std::string end = buffer;
        std::snprintf(buffer, sizeof(buffer), "%.2fs", segment.end_s - segment.start_s);
        rows.push_back({start, end, buffer});
    }
    out::table({"START", "END", "DURATION"}, rows);
    return 0;
}

}  // namespace

void register_vad(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("vad", "Detect speech segments in a WAV file");
    auto ref = std::make_shared<std::string>();
    auto input = std::make_shared<std::string>();
    cmd->add_option("model", *ref, "VAD model (default: " + std::string(kDefaultVadModel) + ")");
    cmd->add_option("--input,-i", *input, "16-bit PCM WAV file")
        ->required()
        ->check(CLI::ExistingFile);
    cmd->callback([&options, ref, input]() {
        const int exit_code = run_vad(options, *ref, *input);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
