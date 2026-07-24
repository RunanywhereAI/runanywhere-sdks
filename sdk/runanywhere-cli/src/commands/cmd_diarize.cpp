/**
 * @file cmd_diarize.cpp
 * @brief `rcli diarize <audio.wav> --model <id-or-path>` — offline speaker
 *        diarization via the commons diarization service (audio-in → typed
 *        speaker segments out).
 *
 * Audio loading mirrors cmd_stt (16-bit PCM WAV → mono 16 kHz float). The model
 * lifecycle is the standard service handle sequence the C ABI exposes:
 *   rac_diarization_create(model)   → route to the ONNX Sortformer provider
 *     → rac_diarization_initialize(model_path)  → load the ONNX graph
 *     → rac_diarization_diarize(samples, …, &result)  → typed segments
 *     → rac_diarization_result_free / rac_diarization_destroy
 * A `--model` naming an on-disk path is used verbatim (the provider resolves
 * the .onnx inside a directory); otherwise it is treated as a catalog id and
 * pulled with the shared ensure-downloaded flow. All heavy lifting (mel
 * frontend, streaming state, segmentation) lives in commons/the engine, per
 * repo layering.
 */

#include <filesystem>
#include <memory>
#include <string>
#include <system_error>
#include <vector>

#include "commands/commands.h"
#include "commands/model_setup.h"
#include "io/output.h"
#include "io/wav_io.h"
#include "rac/features/diarization/rac_diarization_service.h"
#include "rac/features/diarization/rac_diarization_types.h"

namespace rcli::commands {

namespace {

constexpr int kDiarizationSampleRate = 16000;

// Resolve `ref` to a local model path: an existing on-disk path is used as-is;
// otherwise it is a catalog/registry id resolved + auto-pulled through commons
// (same flow as the speech commands). Returns 0 on success, else an exit code.
int resolve_model_path(const GlobalOptions& options, const std::string& ref,
                       std::string* out_path) {
    std::error_code ec;
    if (std::filesystem::exists(ref, ec)) {
        *out_path = ref;
        return 0;
    }
    ResolvedModelPaths model;
    const int setup = ensure_model_ready(options, ref, &model);
    if (setup != 0) {
        return setup;
    }
    *out_path = model.primary_path;
    return 0;
}

void print_result(const GlobalOptions& options, const std::string& model_ref,
                  const rac_diarization_result_t& result) {
    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("model", result.model_id ? result.model_id : model_ref)
            .field("speaker_count", static_cast<int64_t>(result.speaker_count))
            .field("segment_count", static_cast<int64_t>(result.segment_count))
            .field("audio_duration_ms", static_cast<int64_t>(result.audio_duration_ms))
            .field("processing_time_ms", static_cast<int64_t>(result.processing_time_ms));
        json.begin_array("segments");
        for (size_t i = 0; i < result.segment_count; ++i) {
            const rac_diarization_segment_t& seg = result.segments[i];
            json.begin_array_object()
                .field("speaker", seg.speaker_id ? seg.speaker_id : "")
                .field("speaker_index", static_cast<int64_t>(seg.speaker_index))
                .field("start_ms", static_cast<int64_t>(seg.start_ms))
                .field("end_ms", static_cast<int64_t>(seg.end_ms))
                .end_object();
        }
        json.end_array().end_object();
        out::result_line(json.str());
        return;
    }

    if (result.segment_count == 0) {
        out::result_line("(no speech segments detected)");
    } else {
        std::vector<std::vector<std::string>> rows;
        rows.reserve(result.segment_count);
        for (size_t i = 0; i < result.segment_count; ++i) {
            const rac_diarization_segment_t& seg = result.segments[i];
            rows.push_back({seg.speaker_id ? seg.speaker_id : std::to_string(seg.speaker_index),
                            std::to_string(seg.start_ms) + " ms",
                            std::to_string(seg.end_ms) + " ms",
                            std::to_string(seg.end_ms - seg.start_ms) + " ms"});
        }
        out::table({"speaker", "start", "end", "duration"}, rows);
    }
    if (options.verbose) {
        out::status_line("(" + std::to_string(result.speaker_count) + " speakers, " +
                         std::to_string(result.processing_time_ms) + " ms)");
    }
}

int run_diarize(const GlobalOptions& options, const std::string& audio_path,
                const std::string& model_ref, const rac_diarization_options_t& diar_options) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    if (model_ref.empty()) {
        out::error_line("--model is required (a diarization model id or on-disk path)");
        return 2;
    }

    std::string model_path;
    const int resolve = resolve_model_path(options, model_ref, &model_path);
    if (resolve != 0) {
        return resolve;
    }

    // Load audio → mono 16 kHz float, mirroring cmd_stt.
    wav::WavData audio;
    std::string error;
    if (!wav::read_wav(audio_path, &audio, &error)) {
        out::error_line(error);
        return 1;
    }
    const std::vector<int16_t> pcm16 =
        wav::resample(audio.samples, audio.sample_rate, kDiarizationSampleRate);
    const std::vector<float> pcm = wav::to_float(pcm16);
    if (pcm.empty()) {
        out::error_line("no audio samples in " + audio_path);
        return 1;
    }

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_diarization_create(model_path.c_str(), &handle);
    if (rc != RAC_SUCCESS || handle == nullptr) {
        out::error_line("failed to create diarization service: " + out::describe_result(rc));
        return 1;
    }

    rc = rac_diarization_initialize(handle, model_path.c_str());
    if (rc != RAC_SUCCESS) {
        out::error_line("failed to load diarization model: " + out::describe_result(rc));
        rac_diarization_destroy(handle);
        return 1;
    }

    rac_diarization_result_t result = {};
    rc = rac_diarization_diarize(handle, pcm.data(), pcm.size(), &diar_options, &result);
    if (rc != RAC_SUCCESS) {
        out::error_line("diarization failed: " + out::describe_result(rc));
        rac_diarization_result_free(&result);
        rac_diarization_cleanup(handle);
        rac_diarization_destroy(handle);
        return 1;
    }

    print_result(options, model_ref, result);

    rac_diarization_result_free(&result);
    rac_diarization_cleanup(handle);
    rac_diarization_destroy(handle);
    return 0;
}

}  // namespace

void register_diarize(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd =
        app.add_subcommand("diarize", "Speaker diarization of a WAV file (who spoke when)");
    auto audio = std::make_shared<std::string>();
    auto model = std::make_shared<std::string>();
    auto diar = std::make_shared<rac_diarization_options_t>(RAC_DIARIZATION_OPTIONS_DEFAULT);
    cmd->add_option("audio", *audio, "16-bit PCM WAV file")->required()->check(CLI::ExistingFile);
    cmd->add_option("--model,-m", *model, "Diarization model id or on-disk path")->required();
    cmd->add_option("--threshold", diar->threshold,
                    "Speaker-activity threshold in [0,1] (default 0.5)");
    cmd->add_option("--min-duration", diar->minimum_duration_ms,
                    "Drop segments shorter than this many ms (default 0)");
    cmd->add_option("--merge-gap", diar->merge_gap_ms,
                    "Merge same-speaker segments closer than this many ms (default 0)");
    cmd->callback([&options, audio, model, diar]() {
        const int exit_code = run_diarize(options, *audio, *model, *diar);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
