/**
 * @file cmd_voice.cpp
 * @brief `rcli voice --input a.wav` — one-shot voice turn (STT → LLM → TTS)
 *        via the commons voice agent, mirroring tests/test_voice_agent.cpp.
 */

#include "commands/commands.h"

#include <fstream>
#include <memory>
#include <string>
#include <vector>

#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "voice_agent_service.pb.h"
#endif

#include "commands/model_setup.h"
#include "io/output.h"
#include "io/proto.h"
#include "io/wav_io.h"

namespace rcli::commands {

namespace {

constexpr const char* kDefaultStt = "sherpa-onnx-whisper-tiny.en";
constexpr const char* kDefaultLlm = "qwen3-0.6b";
constexpr const char* kDefaultTts = "vits-piper-en_US-lessac-medium";
constexpr int kTurnSampleRate = 16000;

int run_voice(const GlobalOptions& options, const std::string& input, const std::string& stt_ref,
              const std::string& llm_ref, const std::string& tts_ref,
              const std::string& output) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }
    if (input.empty()) {
        out::error_line("an audio file is required (positional or --input)");
        return 2;
    }

    ResolvedModelPaths stt;
    ResolvedModelPaths llm;
    ResolvedModelPaths tts;
    for (const auto& [ref, paths] :
         {std::pair{stt_ref.empty() ? kDefaultStt : stt_ref.c_str(), &stt},
          std::pair{llm_ref.empty() ? kDefaultLlm : llm_ref.c_str(), &llm},
          std::pair{tts_ref.empty() ? kDefaultTts : tts_ref.c_str(), &tts}}) {
        const int setup = ensure_model_ready(options, ref, paths);
        if (setup != 0) {
            return setup;
        }
    }

    wav::WavData audio;
    std::string error;
    if (!wav::read_wav(input, &audio, &error)) {
        out::error_line(error);
        return 1;
    }
    const std::vector<int16_t> pcm16 = wav::resample(audio.samples, audio.sample_rate,
                                                     kTurnSampleRate);

    rac_voice_agent_handle_t agent = nullptr;
    rac_result_t rc = rac_voice_agent_create_standalone(&agent);
    if (rc != RAC_SUCCESS || !agent) {
        out::error_line("failed to create voice agent: " + out::describe_result(rc));
        return 1;
    }

    rac_voice_agent_config_t config = RAC_VOICE_AGENT_CONFIG_DEFAULT;
    config.stt_config.model_path = stt.primary_path.c_str();
    config.stt_config.model_id = stt.model_id.c_str();
    config.stt_config.model_name = stt.display_name.c_str();
    config.llm_config.model_path = llm.primary_path.c_str();
    config.llm_config.model_id = llm.model_id.c_str();
    config.llm_config.model_name = llm.display_name.c_str();
    config.tts_config.voice_path = tts.primary_path.c_str();
    config.tts_config.voice_id = tts.model_id.c_str();
    config.tts_config.voice_name = tts.display_name.c_str();

    rc = rac_voice_agent_initialize(agent, &config);
    if (rc != RAC_SUCCESS) {
        out::error_line("voice agent init failed: " + out::describe_result(rc));
        rac_voice_agent_destroy(agent);
        return 1;
    }

    out::status_line("processing voice turn (stt=" + stt.model_id + ", llm=" + llm.model_id +
                     ", tts=" + tts.model_id + ")");
    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    rc = rac_voice_agent_process_voice_turn_proto(
        agent, pcm16.data(), pcm16.size() * sizeof(int16_t), &out_buffer);

    int exit_code = 0;
    runanywhere::v1::VoiceAgentResult result;
    if (rc != RAC_SUCCESS || !proto::parse_proto_buffer(&out_buffer, &result, &error)) {
        out::error_line("voice turn failed: " +
                        (rc != RAC_SUCCESS ? out::describe_result(rc) : error));
        exit_code = 1;
    } else {
        std::string reply_path;
        // synthesized_audio_sample_rate_hz/channels/encoding were deleted from
        // VoiceAgentResult outright: commons (voice_agent_proto_abi.cpp) already
        // wraps the TTS float32 PCM into a complete WAV container via
        // rac_audio_float32_to_wav before setting synthesized_audio, so this is
        // a ready-to-write WAV file, not raw PCM -- no reinterpret/resample here.
        if (!output.empty() && !result.synthesized_audio().empty()) {
            std::ofstream file(output, std::ios::binary);
            file.write(result.synthesized_audio().data(),
                      static_cast<std::streamsize>(result.synthesized_audio().size()));
            if (file.good()) {
                reply_path = output;
            } else {
                out::status_line("warning: cannot write " + output);
            }
        }

        if (options.json) {
            out::JsonWriter json;
            json.begin_object()
                .field("transcription", result.transcription())
                .field("response", result.assistant_response())
                .field("reply_audio", reply_path)
                .end_object();
            out::result_line(json.str());
        } else {
            out::result_line("you   " + result.transcription());
            out::result_line("agent " + result.assistant_response());
            if (!reply_path.empty()) {
                out::result_line("audio " + reply_path);
            }
        }
    }

    rac_voice_agent_destroy(agent);
    return exit_code;
}

}  // namespace

void register_voice(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand("voice", "Hold one spoken turn: listen, answer, speak");
    auto input = std::make_shared<std::string>();
    auto stt = std::make_shared<std::string>();
    auto llm = std::make_shared<std::string>();
    auto tts = std::make_shared<std::string>();
    auto output = std::make_shared<std::string>();
    cmd->add_option("audio", *input, "16-bit PCM WAV file with the user's speech")
        ->check(CLI::ExistingFile);
    cmd->add_option("--input,-i", *input, "16-bit PCM WAV file with the user's speech")
        ->check(CLI::ExistingFile);
    cmd->add_option("--stt", *stt,
                    "Transcription model (default: " + std::string(kDefaultStt) + ")");
    cmd->add_option("--llm", *llm, "Answering model (default: " + std::string(kDefaultLlm) + ")");
    cmd->add_option("--tts", *tts, "Voice that speaks the reply (default: " +
                                       std::string(kDefaultTts) + ")");
    cmd->add_option("--output,-o", *output, "WAV file for the spoken reply");
    cmd->callback([&options, input, stt, llm, tts, output]() {
        const int exit_code = run_voice(options, *input, *stt, *llm, *tts, *output);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
