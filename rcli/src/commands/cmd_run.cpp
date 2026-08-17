/**
 * @file cmd_run.cpp
 * @brief `rcli llm generate|stream`, `rcli vlm generate`, and the terminal
 *        aliases `rcli run` / `rcli chat`.
 *
 * Canonical SDK flow, all heavy lifting in commons:
 *   rac_model_lifecycle_load_proto(validate_availability=true)  → auto-pulls
 *   missing models through the download orchestrator (progress rendered via
 *   DownloadProgressScope), resolves artifact paths (incl. VLM mmproj) and
 *   loads the engine once.
 *   llm generate: rac_llm_generate_proto returns one LLMGenerationResult.
 *   llm stream:   rac_llm_generate_stream_proto streams LLMStreamEvent protos;
 *   ANSWER tokens go to stdout, THOUGHT tokens to stderr (dimmed, hidden with
 *   -q or --hide-thinking).
 *   VLM: rac_vlm_generate_proto (unary) returns a VLMResult.
 *   Ctrl-C: rac_llm_cancel_proto from the token callback thread.
 *
 * The REPL remembers the conversation: each turn sends the whole transcript as
 * LLMGenerateRequest.messages, which is what that field is for. Commons
 * flattens it to the engine's history array.
 */

#include "commands/commands.h"

#include <csignal>
#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <fstream>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "chat.pb.h"
#include "llm_service.pb.h"
#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_stream.h"
#include "rac/features/lora/rac_lora_service.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "lora_options.pb.h"
#include "vlm_options.pb.h"

#include "catalog/model_ref.h"
#include "commands/engine_options.h"
#include "config/cli_paths.h"
#include "io/output.h"
#include "io/proto.h"
#include "progress/progress_bar.h"
#include "repl/repl.h"
#include "repl/transcript.h"
#include "util/term.h"

namespace rcli::commands {

namespace {

namespace v1 = runanywhere::v1;

// ---------------------------------------------------------------------------
// Generation parameters shared by one-shot, streaming and REPL turns. Field
// names follow LlmOptions in the public API spec.
// ---------------------------------------------------------------------------
struct RunParams {
    std::string model;
    std::string image;
    // Models the chat slash commands reach for. Empty means the built-in
    // default for that modality, the same one `rcli vlm` / `rcli stt` use.
    std::string vlm_model;
    std::string stt_model;
    std::string tts_voice;
    std::string accelerator;       // auto | cpu | gpu | npu ("" = engine decides)
    int32_t context_length = 0;    // 0 = engine default
    std::string system_prompt;
    std::string engine;
    std::string lora;            // optional LoRA adapter (.gguf) to attach before generating
    float lora_scale = 1.0f;     // how strongly the adapter applies
    std::string reasoning = "on";  // on | off
    bool show_thinking = true;     // reasoning.include_in_output
    float temperature = 0.0f;      // 0 = engine default
    float top_p = 0.0f;
    float min_p = 0.0f;
    float repetition_penalty = 0.0f;
    float frequency_penalty = 0.0f;
    float presence_penalty = 0.0f;
    int32_t top_k = 0;
    int32_t max_output_tokens = 1024;
    int64_t seed = -1;  // -1 = unset; LLMGenerationOptions.seed default is 0
    std::vector<std::string> stop_sequences;
};

volatile std::sig_atomic_t g_interrupted = 0;

void on_sigint(int /*signum*/) {
    g_interrupted = 1;
}

bool reasoning_off(const RunParams& params) {
    return params.reasoning == "off";
}

// Fill LLMGenerationOptions from the parsed flags. Zero means "leave it to the
// engine default" for every sampling knob the proto declares as non-optional.
void apply_options(const RunParams& params, v1::LLMGenerationOptions* gen) {
    gen->set_max_output_tokens(params.max_output_tokens);
    if (params.temperature > 0.0f) {
        gen->set_temperature(params.temperature);
    }
    if (params.top_p > 0.0f) {
        gen->set_top_p(params.top_p);
    }
    if (params.top_k > 0) {
        gen->set_top_k(params.top_k);
    }
    if (params.min_p > 0.0f) {
        gen->set_min_p(params.min_p);
    }
    if (params.repetition_penalty > 0.0f) {
        gen->set_repeat_penalty(params.repetition_penalty);
    }
    if (params.frequency_penalty != 0.0f) {
        gen->set_frequency_penalty(params.frequency_penalty);
    }
    if (params.presence_penalty != 0.0f) {
        gen->set_presence_penalty(params.presence_penalty);
    }
    if (params.seed >= 0) {
        gen->set_seed(params.seed);
    }
    for (const std::string& stop : params.stop_sequences) {
        gen->add_stop_sequences(stop);
    }
    if (!params.system_prompt.empty()) {
        gen->set_system_prompt(params.system_prompt);
    }
    v1::ReasoningOptions* reasoning = gen->mutable_reasoning();
    if (reasoning_off(params)) {
        reasoning->set_mode(v1::REASONING_MODE_OFF);
    } else {
        reasoning->set_include_in_output(params.show_thinking);
    }
}

// Streaming state shared with the LLM proto callback.
struct GenState {
    std::mutex mutex;
    std::condition_variable cv;
    bool done = false;
    bool cancelled = false;
    std::string answer;
    std::string finish_reason;
    std::string error;
    bool show_thoughts = false;
    bool in_thought_block = false;
    bool stream_to_stdout = true;  // false in --json mode (accumulate only)
};

GenState* g_gen = nullptr;

void llm_stream_callback(const uint8_t* event_bytes, size_t event_size, void* /*user_data*/) {
    GenState* state = g_gen;
    if (!state) {
        return;
    }
    v1::LLMStreamEvent event;
    if (!event.ParseFromArray(event_bytes, static_cast<int>(event_size))) {
        return;
    }

    // Ctrl-C: cancel from this (normal) thread — signal handlers must not.
    if (g_interrupted) {
        std::lock_guard<std::mutex> lock(state->mutex);
        if (!state->cancelled) {
            state->cancelled = true;
            rac_proto_buffer_t cancel_event;
            rac_proto_buffer_init(&cancel_event);
            rac_llm_cancel_proto(&cancel_event);
            rac_proto_buffer_free(&cancel_event);
        }
    }

    if (!event.token().empty()) {
        std::lock_guard<std::mutex> lock(state->mutex);
        if (event.event_kind() == v1::LLM_STREAM_EVENT_KIND_THINKING) {
            if (state->show_thoughts) {
                if (!state->in_thought_block) {
                    std::fprintf(stderr, "%s", term::color_enabled() ? "\033[2m" : "");
                    state->in_thought_block = true;
                }
                std::fprintf(stderr, "%s", event.token().c_str());
                std::fflush(stderr);
            }
        } else {
            if (state->in_thought_block) {
                std::fprintf(stderr, "%s\n", term::color_enabled() ? "\033[0m" : "");
                state->in_thought_block = false;
            }
            // Swallow the leading-whitespace artifact left by think-tag
            // stripping (qwen3 emits "\n\n" before the first answer token).
            std::string token = event.token();
            if (state->answer.empty()) {
                const size_t first = token.find_first_not_of(" \t\r\n");
                if (first == std::string::npos) {
                    token.clear();
                } else {
                    token.erase(0, first);
                }
            }
            if (!token.empty()) {
                if (state->stream_to_stdout) {
                    std::fprintf(stdout, "%s", token.c_str());
                    std::fflush(stdout);
                }
                state->answer += token;
            }
        }
    }

    if (event.event_kind() == v1::LLM_STREAM_EVENT_KIND_COMPLETED ||
        event.event_kind() == v1::LLM_STREAM_EVENT_KIND_ERROR) {
        std::lock_guard<std::mutex> lock(state->mutex);
        if (state->in_thought_block) {
            std::fprintf(stderr, "%s\n", term::color_enabled() ? "\033[0m" : "");
            state->in_thought_block = false;
        }
        state->finish_reason = v1::FinishReason_Name(event.finish_reason());
        if (!event.error().message().empty()) {
            state->error = event.error().message();
        }
        state->done = true;
        state->cv.notify_all();
    }
}

// One blocking streaming generation; returns 0 ok, 1 error, 130 user-cancel.
// `history` carries the prior conversation (null = single turn); `out_answer`
// receives the assistant text so a caller can append it to the transcript.
int stream_once(const GlobalOptions& options, const std::string& model_id,
                const std::string& prompt, const RunParams& params,
                const repl::Transcript* history = nullptr, std::string* out_answer = nullptr) {
    v1::LLMGenerateRequest request;
    fill_messages(&request, history, prompt);
    apply_options(params, request.mutable_options());
    (void)model_id;  // lifecycle-owned state knows the loaded model

    GenState state;
    state.show_thoughts = params.show_thinking && !reasoning_off(params) && !options.quiet &&
                          !options.json;
    state.stream_to_stdout = !options.json;
    g_gen = &state;
    g_interrupted = 0;
    auto* previous_handler = std::signal(SIGINT, on_sigint);

    const auto started = std::chrono::steady_clock::now();
    const std::string bytes = proto::serialize(request);
    const rac_result_t rc = rac_llm_generate_stream_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), llm_stream_callback,
        nullptr);

    int exit_code = 0;
    if (rc != RAC_SUCCESS) {
        out::error_line("generation failed: " + out::describe_result(rc));
        exit_code = 1;
    } else {
        std::unique_lock<std::mutex> lock(state.mutex);
        state.cv.wait(lock, [&state] { return state.done; });
        if (!state.answer.empty() && state.answer.back() != '\n' && !options.json) {
            std::fprintf(stdout, "\n");
        }
        const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                                 std::chrono::steady_clock::now() - started)
                                 .count();
        if (!state.error.empty()) {
            out::error_line("generation failed: " + state.error);
            exit_code = 1;
        } else if (state.cancelled) {
            out::status_line("(cancelled)");
            exit_code = 130;
        } else if (options.json) {
            out::JsonWriter json;
            json.begin_object()
                .field("model", model_id)
                .field("response", state.answer)
                .field("finish_reason", state.finish_reason)
                .field("total_ms", static_cast<int64_t>(elapsed))
                .end_object();
            out::result_line(json.str());
        } else if (options.verbose) {
            out::status_line("(" + std::to_string(elapsed) + " ms)");
        }
        if (exit_code == 0 && out_answer != nullptr) {
            *out_answer = state.answer;
        }
    }

    std::signal(SIGINT, previous_handler);
    g_gen = nullptr;
    return exit_code;
}

// One unary generation (`llm generate`): the whole result lands at once.
int generate_once(const GlobalOptions& options, const std::string& model_id,
                  const std::string& prompt, const RunParams& params) {
    v1::LLMGenerateRequest request;
    v1::ChatMessage* message = request.add_messages();
    message->set_role(v1::MESSAGE_ROLE_USER);
    message->set_content(prompt);
    apply_options(params, request.mutable_options());

    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    std::string error;
    v1::LLMGenerationResult result;
    if (rac_llm_generate_proto(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                               &out_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&out_buffer, &result, &error)) {
        out::error_line("generation failed: " + error);
        return 1;
    }

    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("model", result.model_used().empty() ? model_id : result.model_used())
            .field("response", result.text())
            .field("thinking", result.thinking_content())
            .field("finish_reason", v1::FinishReason_Name(result.finish_reason()))
            .field("input_tokens", static_cast<int64_t>(result.usage().input_tokens()))
            .field("output_tokens", static_cast<int64_t>(result.usage().output_tokens()))
            .field("tokens_per_second", result.usage().decode_tokens_per_second())
            .field("total_ms", static_cast<int64_t>(result.generation_time_ms()))
            .end_object();
        out::result_line(json.str());
        return 0;
    }
    if (params.show_thinking && !reasoning_off(params) && !options.quiet &&
        !result.thinking_content().empty()) {
        std::fprintf(stderr, "%s%s%s\n", term::color_enabled() ? "\033[2m" : "",
                     result.thinking_content().c_str(), term::color_enabled() ? "\033[0m" : "");
    }
    out::result_line(result.text());
    if (options.verbose) {
        out::status_line("(" + std::to_string(static_cast<int64_t>(result.generation_time_ms())) +
                         " ms, " + std::to_string(result.usage().decode_tokens_per_second()) +
                         " tok/s)");
    }
    return 0;
}

// Placement and sizing knobs ModelLoadRequest has always carried. Before these
// were wired the CLI sent neither, so every load went out as
// ACCELERATOR_POLICY_UNSPECIFIED and the engine chose alone.
struct LoadTuning {
    v1::AcceleratorPolicy accelerator = v1::ACCELERATOR_POLICY_UNSPECIFIED;
    int32_t context_length = 0;  // 0 = engine default
};

LoadTuning tuning_from(const RunParams& params) {
    LoadTuning tuning;
    tuning.context_length = params.context_length;
    std::string error;
    if (!parse_accelerator(params.accelerator, &tuning.accelerator, &error)) {
        out::error_line(error);
    }
    return tuning;
}

bool load_model(const GlobalOptions& options, const std::string& model_id,
                v1::InferenceFramework framework, bool is_vlm,
                const LoadTuning& tuning = LoadTuning{}) {
    // Auto-pull (validate_availability) + resolve + engine load, one call.
    progress::DownloadProgressScope progress_scope(model_id,
                                                   !options.no_progress && !options.json);
    v1::ModelLoadRequest request;
    request.set_model_id(model_id);
    request.set_validate_availability(true);
    if (framework != v1::INFERENCE_FRAMEWORK_UNSPECIFIED) {
        request.set_framework(framework);
    }
    if (is_vlm) {
        request.set_category(v1::MODEL_CATEGORY_MULTIMODAL);
    }
    if (tuning.accelerator != v1::ACCELERATOR_POLICY_UNSPECIFIED) {
        request.set_accelerator_policy(tuning.accelerator);
    }
    if (tuning.context_length > 0) {
        request.set_context_length(tuning.context_length);
    }
    const std::string bytes = proto::serialize(request);

    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    std::string error;
    v1::ModelLoadResult result;
    if (rac_model_lifecycle_load_proto(rac_get_model_registry(),
                                       reinterpret_cast<const uint8_t*>(bytes.data()),
                                       bytes.size(), &out_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&out_buffer, &result, &error)) {
        out::error_line("model load failed: " + error);
        return false;
    }
    if (!result.has_error() == false) {
        out::error_line("model load failed: " + (result.error().message().empty()
                                                     ? "unknown error"
                                                     : result.error().message()));
        return false;
    }
    // Commons reports here when a load knob was forwarded to an engine that may
    // not honour it (accelerator_policy and friends travel as advisory
    // config_json). Dropping these made `--accelerator gpu` look like it worked
    // on llama.cpp when nothing had changed.
    for (const std::string& warning : result.warnings()) {
        out::status_line("note: " + warning);
    }
    if (options.verbose) {
        out::status_line("loaded " + result.resolved_path());
    }
    return true;
}

int run_vlm(const GlobalOptions& options, const std::string& model_id,
            const std::string& image_path, const std::string& prompt, const RunParams& params,
            std::string* out_answer = nullptr) {
    v1::VLMGenerationRequest request;
    request.set_model_id(model_id);
    v1::VLMImage* image = request.add_images();
    image->set_file_path(image_path);
    request.set_prompt(prompt.empty() ? "Describe this image." : prompt);
    v1::LLMGenerationOptions* gen = request.mutable_options();
    gen->set_max_output_tokens(params.max_output_tokens);
    if (params.temperature > 0.0f) {
        gen->set_temperature(params.temperature);
    }
    if (params.top_p > 0.0f) {
        gen->set_top_p(params.top_p);
    }
    if (params.top_k > 0) {
        gen->set_top_k(params.top_k);
    }
    if (params.min_p > 0.0f) {
        gen->set_min_p(params.min_p);
    }
    if (params.repetition_penalty > 0.0f) {
        gen->set_repeat_penalty(params.repetition_penalty);
    }
    if (params.seed >= 0) {
        gen->set_seed(params.seed);
    }
    for (const std::string& stop : params.stop_sequences) {
        gen->add_stop_sequences(stop);
    }
    if (!params.system_prompt.empty()) {
        gen->set_system_prompt(params.system_prompt);
    }
    v1::ReasoningOptions* reasoning = gen->mutable_reasoning();
    if (reasoning_off(params)) {
        reasoning->set_mode(v1::REASONING_MODE_OFF);
    } else {
        reasoning->set_include_in_output(params.show_thinking);
    }
    // VLMGenerationRequest.options is now the shared LLMGenerationOptions, so
    // frequency/presence penalty apply to VLM generation too.
    if (params.frequency_penalty != 0.0f) {
        gen->set_frequency_penalty(params.frequency_penalty);
    }
    if (params.presence_penalty != 0.0f) {
        gen->set_presence_penalty(params.presence_penalty);
    }

    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    std::string error;
    v1::VLMResult result;
    if (rac_vlm_generate_proto(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                               &out_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&out_buffer, &result, &error)) {
        out::error_line("vlm generation failed: " + error);
        return 1;
    }
    if (!result.error().message().empty()) {
        out::error_line("vlm generation failed: " + result.error().message());
        return 1;
    }

    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("model", model_id)
            .field("response", result.text())
            .field("total_ms", static_cast<int64_t>(result.total_time_ms()))
            .field("tokens_per_second",
                   static_cast<double>(result.usage().decode_tokens_per_second()))
            .end_object();
        out::result_line(json.str());
    } else {
        out::result_line(result.text());
        if (options.verbose) {
            out::status_line("(" + std::to_string(result.total_time_ms()) + " ms, " +
                             std::to_string(result.usage().decode_tokens_per_second()) +
                             " tok/s)");
        }
    }
    if (out_answer != nullptr) {
        *out_answer = result.text();
    }
    return 0;
}

// `/image` inside a chat: resolve and load a vision model, then ask it.
int run_vlm_turn(const GlobalOptions& options, const RunParams& params,
                 const std::string& image_path, const std::string& question,
                 std::string* out_answer) {
    model_ref::Resolved resolved;
    std::string error;
    if (model_ref::resolve(params.model, &resolved, &error) != RAC_SUCCESS) {
        out::error_line(error);
        return 1;
    }
    if (!load_model(options, resolved.model_id, v1::INFERENCE_FRAMEWORK_UNSPECIFIED,
                    /*is_vlm=*/true, tuning_from(params))) {
        return 1;
    }
    return run_vlm(options, resolved.model_id, image_path, question, params, out_answer);
}

void print_repl_help() {
    out::status_line("commands:");
    out::status_line("  /set system <text>          set the system prompt");
    out::status_line("  /set temperature <float>    set sampling temperature");
    out::status_line("  /set max-output-tokens <n>  set the generation budget");
    out::status_line("  /show                       show current settings");
    out::status_line("  /image <path> [question]    ask a vision model about a picture");
    out::status_line("  /audio <file.wav>           transcribe speech and answer it");
    out::status_line("  /engine <name>              reload on another engine, keeping the chat");
    out::status_line("      llamacpp  GGUF on CPU, and GPU when built with Metal");
    out::status_line("      mlx       Apple Silicon; needs the Swift-hosted rcli");
    out::status_line("      neurt     Apple Neural Engine (aliases: coreml, ane)");
    out::status_line("      onnx      embeddings and segmentation");
    out::status_line("      sherpa    speech models");
    out::status_line("  /accelerator <policy>       auto | cpu | gpu | npu, keeping the chat");
    out::status_line("      advisory: an engine may ignore it and will say so");
    out::status_line("  /say [text]                 speak the last reply, or given text, to a WAV");
    out::status_line("  /model <name>               switch model, keeping the chat");
    out::status_line("  /save <file.md>             write the conversation to a file");
    out::status_line("  /context                    show how much conversation is remembered");
    out::status_line("  /clear                      forget the conversation, keep settings");
    out::status_line("  /bye                        exit (also Ctrl-D)");
}

int run_repl(const GlobalOptions& options, std::string model_id, RunParams params) {
    out::status_line("loaded " + model_id + " — type a prompt, /? for help, /bye to exit");
    repl::LineEditor editor(std::getenv("RUNANYWHERE_NOHISTORY")
                                ? std::string()
                                : paths::state_dir() + "/history");
    repl::Transcript transcript;

    std::string line;
    while (editor.read_line("» ", &line)) {
        if (line.empty()) {
            continue;
        }
        editor.add_history(line);

        if (line == "/bye" || line == "/exit" || line == "/quit") {
            break;
        }
        if (line == "/?" || line == "/help") {
            print_repl_help();
            continue;
        }
        if (line == "/show") {
            out::status_line("model              " + model_id);
            out::status_line("system-prompt      " +
                             (params.system_prompt.empty() ? "(none)" : params.system_prompt));
            out::status_line("temperature        " + (params.temperature > 0
                                                         ? std::to_string(params.temperature)
                                                         : "(engine default)"));
            out::status_line("max-output-tokens  " + std::to_string(params.max_output_tokens));
            out::status_line("reasoning          " + params.reasoning);
            out::status_line("engine             " +
                             (params.engine.empty() ? "(model default)" : params.engine));
            out::status_line("accelerator        " +
                             (params.accelerator.empty() ? "(engine decides)" : params.accelerator));
            continue;
        }
        if (line == "/context") {
            out::status_line("turns remembered   " + std::to_string(transcript.size()) + " of " +
                             std::to_string(transcript.max_turns()));
            if (transcript.trimmed()) {
                out::status_line("note: oldest turns were dropped to stay under the cap");
            }
            continue;
        }
        if (line == "/clear" || line == "/reset") {
            transcript.clear();
            out::status_line("conversation cleared");
            continue;
        }
        if (line.starts_with("/say")) {
            const auto [first, rest] = repl::split_first_word(line.substr(4));
            std::string spoken = first.empty() ? std::string() : first + (rest.empty() ? "" : " " + rest);
            if (spoken.empty()) {
                // No text given: voice the model's last reply, which is what
                // "say that back to me" means in a conversation.
                for (auto it = transcript.turns().rbegin(); it != transcript.turns().rend(); ++it) {
                    if (it->role == repl::Role::Assistant) {
                        spoken = it->content;
                        break;
                    }
                }
            }
            if (spoken.empty()) {
                out::status_line("nothing to say yet — usage: /say [text]");
                continue;
            }
            const std::string wav = paths::state_dir() + "/say.wav";
            if (synthesize_to_file(options, params.tts_voice, spoken, wav) == 0) {
                out::status_line("wrote " + wav);
            }
            continue;
        }
        if (line.starts_with("/save")) {
            const auto [path, ignored] = repl::split_first_word(line.substr(5));
            (void)ignored;
            if (path.empty()) {
                out::status_line("usage: /save <file.md>");
                continue;
            }
            std::ofstream file(path);
            if (!file) {
                out::status_line("cannot write " + path);
                continue;
            }
            for (const repl::Turn& turn : transcript.turns()) {
                file << (turn.role == repl::Role::User ? "## you\n\n" : "## " + model_id + "\n\n")
                     << turn.content << "\n\n";
            }
            if (!file) {
                out::status_line("failed while writing " + path);
                continue;
            }
            out::status_line("saved " + std::to_string(transcript.size()) + " turns to " + path);
            continue;
        }
        if (line.starts_with("/model ")) {
            const auto [name, ignored] = repl::split_first_word(line.substr(7));
            (void)ignored;
            if (name.empty()) {
                out::status_line("usage: /model <name>");
                continue;
            }
            model_ref::Resolved resolved;
            std::string resolve_error;
            if (model_ref::resolve(name, &resolved, &resolve_error) != RAC_SUCCESS) {
                out::status_line(resolve_error);
                continue;
            }
            v1::InferenceFramework framework = v1::INFERENCE_FRAMEWORK_UNSPECIFIED;
            std::string hint_error;
            if (!parse_engine_hint(params.engine, &framework, &hint_error)) {
                out::status_line(hint_error);
                continue;
            }
            if (!load_model(options, resolved.model_id, framework, /*is_vlm=*/false,
                            tuning_from(params))) {
                out::status_line("keeping " + model_id + "; the conversation is intact");
                continue;
            }
            // The transcript deliberately survives: comparing two models on the
            // same conversation is the reason to switch mid-session.
            model_id = resolved.model_id;
            params.model = resolved.model_id;
            out::status_line("now " + model_id + "; " + std::to_string(transcript.size()) +
                             " turns still remembered");
            continue;
        }
        if (line.starts_with("/engine ") || line.starts_with("/accelerator ")) {
            const bool is_engine = line.starts_with("/engine ");
            const auto [value, ignored_rest] =
                repl::split_first_word(line.substr(is_engine ? 7 : 13));
            (void)ignored_rest;
            if (value.empty()) {
                out::status_line(is_engine ? "usage: /engine <mlx|llamacpp|neurt|onnx|sherpa>"
                                           : "usage: /accelerator <auto|cpu|gpu|npu>");
                continue;
            }
            // Validate before touching the loaded model, so a typo cannot leave
            // the session with nothing loaded.
            RunParams next = params;
            (is_engine ? next.engine : next.accelerator) = value;
            v1::InferenceFramework framework = v1::INFERENCE_FRAMEWORK_UNSPECIFIED;
            v1::AcceleratorPolicy policy = v1::ACCELERATOR_POLICY_UNSPECIFIED;
            std::string parse_error;
            if (!parse_engine_hint(next.engine, &framework, &parse_error) ||
                !parse_accelerator(next.accelerator, &policy, &parse_error)) {
                out::status_line(parse_error);
                continue;
            }
            LoadTuning tuning;
            tuning.accelerator = policy;
            tuning.context_length = next.context_length;
            if (!load_model(options, model_id, framework, /*is_vlm=*/false, tuning)) {
                out::status_line("keeping the previous placement; the conversation is intact");
                continue;
            }
            params = next;  // only after the reload actually succeeded
            out::status_line(std::string(is_engine ? "engine" : "accelerator") + " set to " +
                             value + "; " + std::to_string(transcript.size()) +
                             " turns still remembered");
            continue;
        }
        if (line.starts_with("/image")) {
            const auto [path, question] = repl::split_first_word(line.substr(6));
            if (path.empty()) {
                out::status_line("usage: /image <path> [question]");
                continue;
            }
            if (!std::filesystem::exists(path)) {
                out::status_line("no such file: " + path);
                continue;
            }
            RunParams vlm_params = params;
            vlm_params.model = params.vlm_model;
            std::string answer;
            if (run_vlm_turn(options, vlm_params, path, question, &answer) == 0 &&
                !answer.empty()) {
                // The VLM call itself is single-turn: commons does not read
                // VLMGenerationRequest.messages. Recording the exchange here is
                // what lets the following TEXT turns refer back to the picture.
                transcript.add(repl::Role::User,
                               (question.empty() ? std::string("Describe this image.") : question) +
                                   "\n[image: " + path + "]");
                transcript.add(repl::Role::Assistant, answer);
            }
            continue;
        }
        if (line.starts_with("/audio")) {
            const auto [path, ignored] = repl::split_first_word(line.substr(6));
            (void)ignored;
            if (path.empty()) {
                out::status_line("usage: /audio <file.wav>");
                continue;
            }
            if (!std::filesystem::exists(path)) {
                out::status_line("no such file: " + path);
                continue;
            }
            std::string spoken;
            if (transcribe_to_text(options, params.stt_model, path, &spoken) != 0) {
                continue;
            }
            if (spoken.empty()) {
                out::status_line("nothing was transcribed from " + path);
                continue;
            }
            // Speaking is typing: the transcript becomes an ordinary user turn.
            out::status_line("heard: " + spoken);
            std::string answer;
            if (stream_once(options, model_id, spoken, params, &transcript, &answer) == 0 &&
                !answer.empty()) {
                transcript.add(repl::Role::User, spoken);
                transcript.add(repl::Role::Assistant, answer);
            }
            continue;
        }
        if (line.starts_with("/set ")) {
            const std::string rest = line.substr(5);
            if (rest.starts_with("system ")) {
                params.system_prompt = rest.substr(7);
                out::status_line("system prompt set");
            } else if (rest.starts_with("temperature ")) {
                params.temperature = std::strtof(rest.substr(12).c_str(), nullptr);
                out::status_line("temperature set");
            } else if (rest.starts_with("temp ")) {
                params.temperature = std::strtof(rest.substr(5).c_str(), nullptr);
                out::status_line("temperature set");
            } else if (rest.starts_with("max-output-tokens ")) {
                params.max_output_tokens =
                    static_cast<int32_t>(std::strtol(rest.substr(18).c_str(), nullptr, 10));
                out::status_line("max-output-tokens set");
            } else if (rest.starts_with("max-tokens ")) {
                params.max_output_tokens =
                    static_cast<int32_t>(std::strtol(rest.substr(11).c_str(), nullptr, 10));
                out::status_line("max-output-tokens set");
            } else {
                out::status_line(
                    "unknown /set option (system | temperature | max-output-tokens)");
            }
            continue;
        }
        if (line.starts_with("/")) {
            out::status_line("unknown command — /? for help");
            continue;
        }

        std::string answer;
        const int code = stream_once(options, model_id, line, params, &transcript, &answer);
        if (code == 1) {
            return 1;  // hard error; cancel (130) just returns to the prompt
        }
        // A cancelled turn is deliberately not remembered: the answer is a
        // fragment, and feeding half a reply back as context makes the next
        // turn worse in a way the user cannot see.
        if (code == 0 && !answer.empty()) {
            transcript.add(repl::Role::User, line);
            transcript.add(repl::Role::Assistant, answer);
        }
    }
    return 0;
}

std::string read_piped_prompt() {
    std::string piped;
    char buffer[4096];
    size_t n = 0;
    while ((n = fread(buffer, 1, sizeof(buffer), stdin)) > 0) {
        piped.append(buffer, n);
    }
    while (!piped.empty() && (piped.back() == '\n' || piped.back() == '\r')) {
        piped.pop_back();
    }
    return piped;
}

// Attach a LoRA adapter to the already-loaded LLM in this same process, so the
// following generation actually uses it (adapter state is session-scoped).
bool apply_lora_adapter(const std::string& adapter_path, float scale) {
    // keep_existing left unset (false): SET semantics, which is what the
    // former explicit replace_existing(true) meant. LoraApplyRequest has no
    // replace_existing field to set.
    v1::LoraApplyRequest request;
    v1::LoraAdapterConfig* adapter = request.add_adapters();
    adapter->set_adapter_path(adapter_path);
    adapter->set_scale(scale);

    const std::string request_bytes = proto::serialize(request);
    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    const rac_result_t rc = rac_lora_apply_proto(
        reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(), &out_buffer);
    v1::LoraApplyResult result;
    std::string error;
    const bool parsed = proto::parse_proto_buffer(&out_buffer, &result, &error);
    if (!parsed || rc != RAC_SUCCESS || result.has_error()) {
        out::error_line("lora apply failed: " +
                        (result.has_error() && !result.error().message().empty()
                             ? result.error().message()
                             : (error.empty() ? std::to_string(rc) : error)));
        return false;
    }
    return true;
}

int run_llm(const GlobalOptions& options, LlmVerb verb, const std::string& prompt,
            const RunParams& params) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }
    if (params.model.empty()) {
        out::error_line("--model is required (a catalog id, alias, hf.co/... ref or URL)");
        return 2;
    }
    // Reject an unusable --accelerator here rather than loading without it. A
    // flag the load call then ignores is worse than no flag at all.
    v1::AcceleratorPolicy unused_policy = v1::ACCELERATOR_POLICY_UNSPECIFIED;
    std::string accelerator_error;
    if (!parse_accelerator(params.accelerator, &unused_policy, &accelerator_error)) {
        out::error_line(accelerator_error);
        return 2;
    }

    EngineHintResolution engine_hint;
    std::string engine_error;
    if (!resolve_engine_hint(params.engine, &engine_hint, &engine_error)) {
        out::error_line(engine_error);
        return 2;
    }

    const bool is_vlm = !params.image.empty();
    if (is_vlm) {
        engine_hint.resolve_options.has_category = true;
        engine_hint.resolve_options.category = v1::MODEL_CATEGORY_MULTIMODAL;
    }

    model_ref::Resolved resolved;
    std::string error;
    if (model_ref::resolve(params.model, &resolved, &error, &engine_hint.resolve_options) !=
        RAC_SUCCESS) {
        out::error_line(error);
        return 1;
    }

    // An explicit --engine is honoured whatever the ref resolved to. This used to
    // read `resolved.from_catalog ? UNSPECIFIED : engine_hint.framework`, which
    // silently DISCARDED the flag for anything that came out of the built-in
    // catalog — `--engine <x>` on a catalog model did nothing at all, with no
    // warning. When the flag is absent engine_hint.framework is UNSPECIFIED, so
    // catalog entries still fall back to their own declared framework exactly as
    // before; the only behaviour that changes is that asking now works. Mirrors
    // cmd_embed.cpp.
    if (!load_model(options, resolved.model_id, engine_hint.framework, is_vlm,
                    tuning_from(params))) {
        return 1;
    }
    if (!params.lora.empty() && !apply_lora_adapter(params.lora, params.lora_scale)) {
        return 1;
    }

    std::string effective_prompt = prompt;
    if (effective_prompt.empty() && !term::stdin_is_tty()) {
        // Piped stdin is the prompt: echo "..." | rcli llm generate -m qwen3
        effective_prompt = read_piped_prompt();
    }

    if (is_vlm) {
        return run_vlm(options, resolved.model_id, params.image, effective_prompt, params);
    }
    if (!effective_prompt.empty()) {
        return verb == LlmVerb::Generate ? generate_once(options, resolved.model_id,
                                                         effective_prompt, params)
                                         : stream_once(options, resolved.model_id,
                                                       effective_prompt, params);
    }
    if (verb == LlmVerb::Chat) {
        return run_repl(options, resolved.model_id, params);
    }
    out::error_line("no prompt given");
    return 2;
}

// The sampling / reasoning / model flags shared by every llm and vlm command.
// VLMGenerationRequest.options is now the same LLMGenerationOptions the LLM
// path uses (VLMGenerationOptions was deleted), so llm and vlm expose an
// identical sampling surface -- the `vlm` parameter only controls whether
// --seed / --frequency-penalty / --presence-penalty are offered at all
// (kept for CLI-surface stability; both option sets now support them).
void add_generation_options(CLI::App* cmd, const std::shared_ptr<RunParams>& params,
                           ModelArg model_arg, bool vlm) {
    (void)vlm;
    if (model_arg == ModelArg::Option) {
        cmd->add_option("--model,-m", params->model,
                        "Model to generate with; downloads and loads it when absent");
    } else {
        cmd->add_option("model", params->model, "Model id, alias, hf.co/... ref or URL")
            ->required();
    }
    cmd->add_option("--system-prompt,--system", params->system_prompt,
                    "Steer the model with a system instruction");
    cmd->add_option("--lora", params->lora,
                    "Attach a LoRA adapter (.gguf) before generating");
    cmd->add_option("--lora-scale", params->lora_scale,
                    "How strongly the LoRA applies (default 1.0)");
    cmd->add_option("--engine", params->engine,
                    "Engine hint (neurt|coreml|ane, mlx, llamacpp, onnx, sherpa). Honoured for "
                    "catalog models too, not just URL/HF refs.");
    cmd->add_option("--accelerator", params->accelerator,
                    "Where the model runs: auto, cpu, gpu or npu");
    cmd->add_option("--context-length", params->context_length,
                    "Context window to load the model with (0 = engine default)");
    cmd->add_option("--temperature,--temp", params->temperature,
                    "Raise for more random sampling (0 = engine default)");
    cmd->add_option("--top-p", params->top_p, "Keep the smallest token set above this probability");
    cmd->add_option("--top-k", params->top_k, "Sample from this many highest-probability tokens");
    cmd->add_option("--min-p", params->min_p, "Drop tokens below this share of the top token");
    cmd->add_option("--repetition-penalty", params->repetition_penalty,
                    "Penalize tokens already present in the context");
    cmd->add_option("--seed", params->seed, "Fix the RNG for a repeatable answer");
    cmd->add_option("--frequency-penalty", params->frequency_penalty,
                    "Penalize tokens by how often they have appeared");
    cmd->add_option("--presence-penalty", params->presence_penalty,
                    "Penalize tokens that appeared at all");
    cmd->add_option("--stop", params->stop_sequences,
                    "Stop as soon as this text is produced (repeat for several)");
    cmd->add_option("--max-output-tokens,--max-tokens", params->max_output_tokens,
                    "Cap the generated tokens (default 1024)");
    cmd->add_option("--reasoning", params->reasoning,
                    "Turn the model's thinking phase on or off (default on)")
        ->check(CLI::IsMember({"on", "off"}));
    cmd->add_flag("--show-thinking,!--hide-thinking", params->show_thinking,
                  "Stream thought tokens to stderr (default on)");
    cmd->add_flag_callback(
        "--no-think", [params]() { params->reasoning = "off"; },
        "Older spelling of `--reasoning off`");
}

}  // namespace

void configure_llm(CLI::App* cmd, GlobalOptions& options, LlmVerb verb, ModelArg model_arg) {
    auto params = std::make_shared<RunParams>();
    auto prompt = std::make_shared<std::string>();
    add_generation_options(cmd, params, model_arg, false);
    cmd->add_option("prompt", *prompt,
                    verb == LlmVerb::Chat ? "First prompt (omit for the interactive REPL)"
                                          : "Prompt to complete (omit to read stdin)");
    if (verb == LlmVerb::Chat) {
        // The REPL and VLM paths share one implementation; `run --image` stays
        // the documented alias of `vlm generate`.
        cmd->add_option("--image", params->image, "Describe this image instead (VLM models)")
            ->check(CLI::ExistingFile);
        cmd->add_option("--vlm-model", params->vlm_model,
                        "Vision model the chat /image command uses");
        cmd->add_option("--stt-model", params->stt_model,
                        "Speech model the chat /audio command uses");
        cmd->add_option("--tts-voice", params->tts_voice,
                        "Voice the chat /say command speaks with");
    }
    cmd->callback([&options, verb, params, prompt]() {
        const int exit_code = run_llm(options, verb, *prompt, *params);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

void configure_vlm_generate(CLI::App* cmd, GlobalOptions& options) {
    auto params = std::make_shared<RunParams>();
    auto prompt = std::make_shared<std::string>();
    add_generation_options(cmd, params, ModelArg::Option, true);
    cmd->add_option("prompt", *prompt, "Question about the image (default: describe it)");
    cmd->add_option("--image,-i", params->image, "Image to look at")
        ->required()
        ->check(CLI::ExistingFile);
    cmd->callback([&options, params, prompt]() {
        const int exit_code = run_llm(options, LlmVerb::Generate, *prompt, *params);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

void register_llm(CLI::App& app, GlobalOptions& options) {
    CLI::App* ns = app.add_subcommand("llm", "Generate text with a language model");
    ns->require_subcommand(1);
    configure_llm(ns->add_subcommand("generate", "Complete a prompt and print the result"),
                  options, LlmVerb::Generate, ModelArg::Option);
    configure_llm(ns->add_subcommand("stream", "Complete a prompt, printing tokens as they arrive"),
                  options, LlmVerb::Stream, ModelArg::Option);
}

void register_vlm(CLI::App& app, GlobalOptions& options) {
    CLI::App* ns = app.add_subcommand("vlm", "Ask a vision-language model about an image");
    ns->require_subcommand(1);
    configure_vlm_generate(ns->add_subcommand("generate", "Answer a prompt about an image"),
                           options);
}

void register_llm_aliases(CLI::App& app, GlobalOptions& options) {
    configure_llm(app.add_subcommand("run", "Chat with a model (alias of `llm stream`)"), options,
                  LlmVerb::Chat, ModelArg::Positional);
    configure_llm(
        app.add_subcommand("chat", "Start an interactive session (alias of `llm stream`)"),
        options, LlmVerb::Chat, ModelArg::Positional);
}

}  // namespace rcli::commands
