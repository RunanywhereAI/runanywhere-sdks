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
 * REPL turns are independent generations (no cross-turn memory yet — that
 * needs a commons chat-session API; tracked in the rcli plan doc).
 */

#include "commands/commands.h"

#include <csignal>
#include <chrono>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "llm_service.pb.h"
#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_stream.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "vlm_options.pb.h"

#include "catalog/model_ref.h"
#include "commands/engine_options.h"
#include "config/cli_paths.h"
#include "io/output.h"
#include "io/proto.h"
#include "progress/progress_bar.h"
#include "repl/repl.h"
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
    std::string system_prompt;
    std::string engine;
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
    int64_t seed = -1;  // vlm only; LLMGenerationOptions has no seed field
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
        gen->set_repetition_penalty(params.repetition_penalty);
    }
    if (params.frequency_penalty != 0.0f) {
        gen->set_frequency_penalty(params.frequency_penalty);
    }
    if (params.presence_penalty != 0.0f) {
        gen->set_presence_penalty(params.presence_penalty);
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
        if (event.kind() == v1::TOKEN_KIND_THOUGHT) {
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

    if (event.is_final()) {
        std::lock_guard<std::mutex> lock(state->mutex);
        if (state->in_thought_block) {
            std::fprintf(stderr, "%s\n", term::color_enabled() ? "\033[0m" : "");
            state->in_thought_block = false;
        }
        state->finish_reason = event.finish_reason();
        if (!event.error_message().empty()) {
            state->error = event.error_message();
        }
        state->done = true;
        state->cv.notify_all();
    }
}

// One blocking streaming generation; returns 0 ok, 1 error, 130 user-cancel.
int stream_once(const GlobalOptions& options, const std::string& model_id,
                const std::string& prompt, const RunParams& params) {
    v1::LLMGenerateRequest request;
    request.set_prompt(prompt);
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
    }

    std::signal(SIGINT, previous_handler);
    g_gen = nullptr;
    return exit_code;
}

// One unary generation (`llm generate`): the whole result lands at once.
int generate_once(const GlobalOptions& options, const std::string& model_id,
                  const std::string& prompt, const RunParams& params) {
    v1::LLMGenerateRequest request;
    request.set_prompt(prompt);
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
            .field("finish_reason", result.finish_reason())
            .field("input_tokens", static_cast<int64_t>(result.input_tokens()))
            .field("output_tokens", static_cast<int64_t>(result.output_tokens()))
            .field("tokens_per_second", result.tokens_per_second())
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
                         " ms, " + std::to_string(result.tokens_per_second()) + " tok/s)");
    }
    return 0;
}

bool load_model(const GlobalOptions& options, const std::string& model_id,
                v1::InferenceFramework framework, bool is_vlm) {
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
    if (!result.success()) {
        out::error_line("model load failed: " + (result.error_message().empty()
                                                     ? "unknown error"
                                                     : result.error_message()));
        return false;
    }
    if (options.verbose) {
        out::status_line("loaded " + result.resolved_path());
    }
    return true;
}

int run_vlm(const GlobalOptions& options, const std::string& model_id,
            const std::string& image_path, const std::string& prompt, const RunParams& params) {
    v1::VLMGenerationRequest request;
    request.set_model_id(model_id);
    v1::VLMImage* image = request.add_images();
    image->set_file_path(image_path);
    v1::VLMGenerationOptions* gen = request.mutable_options();
    gen->set_prompt(prompt.empty() ? "Describe this image." : prompt);
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
        gen->set_repetition_penalty(params.repetition_penalty);
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
    // VLMGenerationOptions has no frequency/presence penalty; say so rather
    // than dropping the flags silently.
    if (params.frequency_penalty != 0.0f || params.presence_penalty != 0.0f) {
        out::status_line(
            "note: --frequency-penalty / --presence-penalty are not applied to VLM models");
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
    if (!result.error_message().empty()) {
        out::error_line("vlm generation failed: " + result.error_message());
        return 1;
    }

    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("model", model_id)
            .field("response", result.text())
            .field("total_ms", static_cast<int64_t>(result.processing_time_ms()))
            .field("tokens_per_second", static_cast<double>(result.tokens_per_second()))
            .end_object();
        out::result_line(json.str());
    } else {
        out::result_line(result.text());
        if (options.verbose) {
            out::status_line("(" + std::to_string(result.processing_time_ms()) + " ms, " +
                             std::to_string(result.tokens_per_second()) + " tok/s)");
        }
    }
    return 0;
}

void print_repl_help() {
    out::status_line("commands:");
    out::status_line("  /set system <text>          set the system prompt");
    out::status_line("  /set temperature <float>    set sampling temperature");
    out::status_line("  /set max-output-tokens <n>  set the generation budget");
    out::status_line("  /show                       show current settings");
    out::status_line("  /bye                        exit (also Ctrl-D)");
    out::status_line("note: turns are independent — no conversation memory yet");
}

int run_repl(const GlobalOptions& options, const std::string& model_id, RunParams params) {
    out::status_line("loaded " + model_id + " — type a prompt, /? for help, /bye to exit");
    repl::LineEditor editor(std::getenv("RUNANYWHERE_NOHISTORY")
                                ? std::string()
                                : paths::state_dir() + "/history");

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

        const int code = stream_once(options, model_id, line, params);
        if (code == 1) {
            return 1;  // hard error; cancel (130) just returns to the prompt
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

    const v1::InferenceFramework load_framework =
        resolved.from_catalog ? v1::INFERENCE_FRAMEWORK_UNSPECIFIED : engine_hint.framework;
    if (!load_model(options, resolved.model_id, load_framework, is_vlm)) {
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
// The two option sets differ only where the protos do: LLMGenerationOptions has
// the frequency/presence penalties, VLMGenerationOptions has the seed.
void add_generation_options(CLI::App* cmd, const std::shared_ptr<RunParams>& params,
                           ModelArg model_arg, bool vlm) {
    if (model_arg == ModelArg::Option) {
        cmd->add_option("--model,-m", params->model,
                        "Model to generate with; downloads and loads it when absent");
    } else {
        cmd->add_option("model", params->model, "Model id, alias, hf.co/... ref or URL")
            ->required();
    }
    cmd->add_option("--system-prompt,--system", params->system_prompt,
                    "Steer the model with a system instruction");
    cmd->add_option("--engine", params->engine,
                    "Pin the inference engine for URL or HF refs (mlx, llamacpp, onnx, sherpa)");
    cmd->add_option("--temperature,--temp", params->temperature,
                    "Raise for more random sampling (0 = engine default)");
    cmd->add_option("--top-p", params->top_p, "Keep the smallest token set above this probability");
    cmd->add_option("--top-k", params->top_k, "Sample from this many highest-probability tokens");
    cmd->add_option("--min-p", params->min_p, "Drop tokens below this share of the top token");
    cmd->add_option("--repetition-penalty", params->repetition_penalty,
                    "Penalize tokens already present in the context");
    if (vlm) {
        cmd->add_option("--seed", params->seed, "Fix the RNG for a repeatable answer");
    } else {
        cmd->add_option("--frequency-penalty", params->frequency_penalty,
                        "Penalize tokens by how often they have appeared");
        cmd->add_option("--presence-penalty", params->presence_penalty,
                        "Penalize tokens that appeared at all");
    }
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
