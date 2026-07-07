/**
 * @file cmd_run.cpp
 * @brief `rcli run <model> [prompt]` — LLM chat (one-shot or REPL) and
 *        `--image` VLM understanding.
 *
 * Canonical SDK flow, all heavy lifting in commons:
 *   rac_model_lifecycle_load_proto(validate_availability=true)  → auto-pulls
 *   missing models through the download orchestrator (progress rendered via
 *   DownloadProgressScope), resolves artifact paths (incl. VLM mmproj) and
 *   loads the engine once.
 *   LLM: rac_llm_generate_stream_proto streams LLMStreamEvent protos; ANSWER
 *   tokens go to stdout, THOUGHT tokens to stderr (dimmed, hidden with -q).
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
// Generation parameters shared by one-shot and REPL turns.
// ---------------------------------------------------------------------------
struct RunParams {
    std::string system_prompt;
    std::string engine;
    float temperature = 0.0f;  // 0 = engine default
    int32_t max_tokens = 1024;
    bool no_think = false;
};

volatile std::sig_atomic_t g_interrupted = 0;

void on_sigint(int /*signum*/) {
    g_interrupted = 1;
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

// One blocking generation; returns 0 ok, 1 error, 130 user-cancel.
int generate_once(const GlobalOptions& options, const std::string& model_id,
                  const std::string& prompt, const RunParams& params) {
    v1::LLMGenerateRequest request;
    request.set_prompt(prompt);
    request.set_emit_thoughts(!params.no_think);
    v1::LLMGenerationOptions* gen = request.mutable_options();
    gen->set_max_tokens(params.max_tokens);
    if (params.temperature > 0.0f) {
        gen->set_temperature(params.temperature);
    }
    if (!params.system_prompt.empty()) {
        gen->set_system_prompt(params.system_prompt);
    }
    if (params.no_think) {
        gen->set_disable_thinking(true);
    }
    (void)model_id;  // lifecycle-owned state knows the loaded model

    GenState state;
    state.show_thoughts = !options.quiet && !options.json;
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
    gen->set_max_tokens(params.max_tokens);
    if (params.temperature > 0.0f) {
        gen->set_temperature(params.temperature);
    }
    if (!params.system_prompt.empty()) {
        gen->set_system_prompt(params.system_prompt);
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
    out::status_line("  /set system <text>   set the system prompt");
    out::status_line("  /set temp <float>    set sampling temperature");
    out::status_line("  /set max-tokens <n>  set the generation budget");
    out::status_line("  /show                show current settings");
    out::status_line("  /bye                 exit (also Ctrl-D)");
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
            out::status_line("model       " + model_id);
            out::status_line("system      " +
                             (params.system_prompt.empty() ? "(none)" : params.system_prompt));
            out::status_line("temperature " + (params.temperature > 0
                                                   ? std::to_string(params.temperature)
                                                   : "(engine default)"));
            out::status_line("max-tokens  " + std::to_string(params.max_tokens));
            out::status_line("thinking    " + std::string(params.no_think ? "off" : "model default"));
            continue;
        }
        if (line.starts_with("/set ")) {
            const std::string rest = line.substr(5);
            if (rest.starts_with("system ")) {
                params.system_prompt = rest.substr(7);
                out::status_line("system prompt set");
            } else if (rest.starts_with("temp ")) {
                params.temperature = std::strtof(rest.substr(5).c_str(), nullptr);
                out::status_line("temperature set");
            } else if (rest.starts_with("max-tokens ")) {
                params.max_tokens = static_cast<int32_t>(std::strtol(rest.substr(11).c_str(),
                                                                     nullptr, 10));
                out::status_line("max-tokens set");
            } else {
                out::status_line("unknown /set option (system | temp | max-tokens)");
            }
            continue;
        }
        if (line.starts_with("/")) {
            out::status_line("unknown command — /? for help");
            continue;
        }

        const int code = generate_once(options, model_id, line, params);
        if (code == 1) {
            return 1;  // hard error; cancel (130) just returns to the prompt
        }
    }
    return 0;
}

int run_run(const GlobalOptions& options, const std::string& ref, const std::string& prompt,
            const std::string& image_path, const RunParams& params) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return 1;
    }

    EngineHintResolution engine_hint;
    std::string engine_error;
    if (!resolve_engine_hint(params.engine, &engine_hint, &engine_error)) {
        out::error_line(engine_error);
        return 2;
    }

    if (!image_path.empty()) {
        engine_hint.resolve_options.has_category = true;
        engine_hint.resolve_options.category = v1::MODEL_CATEGORY_MULTIMODAL;
    }

    model_ref::Resolved resolved;
    std::string error;
    if (model_ref::resolve(ref, &resolved, &error, &engine_hint.resolve_options) != RAC_SUCCESS) {
        out::error_line(error);
        return 1;
    }

    const v1::InferenceFramework load_framework =
        resolved.from_catalog ? v1::INFERENCE_FRAMEWORK_UNSPECIFIED : engine_hint.framework;
    if (!load_model(options, resolved.model_id, load_framework, !image_path.empty())) {
        return 1;
    }

    if (!image_path.empty()) {
        return run_vlm(options, resolved.model_id, image_path, prompt, params);
    }
    if (!prompt.empty()) {
        return generate_once(options, resolved.model_id, prompt, params);
    }
    if (!term::stdin_is_tty()) {
        // Piped stdin: read it all as the prompt (echo "..." | rcli run model).
        std::string piped;
        char buffer[4096];
        size_t n = 0;
        while ((n = fread(buffer, 1, sizeof(buffer), stdin)) > 0) {
            piped.append(buffer, n);
        }
        while (!piped.empty() && (piped.back() == '\n' || piped.back() == '\r')) {
            piped.pop_back();
        }
        if (piped.empty()) {
            out::error_line("no prompt given");
            return 2;
        }
        return generate_once(options, resolved.model_id, piped, params);
    }
    return run_repl(options, resolved.model_id, params);
}

}  // namespace

void register_run(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd =
        app.add_subcommand("run", "Chat with a model (REPL, one-shot, or --image VLM)");
    auto ref = std::make_shared<std::string>();
    auto prompt = std::make_shared<std::string>();
    auto image = std::make_shared<std::string>();
    auto params = std::make_shared<RunParams>();
    cmd->add_option("model", *ref, "Model id, alias, hf.co/... or URL")->required();
    cmd->add_option("prompt", *prompt, "One-shot prompt (omit for interactive REPL)");
    cmd->add_option("--image", *image, "Image file for VLM models")
        ->check(CLI::ExistingFile);
    cmd->add_option("--system", params->system_prompt, "System prompt");
    cmd->add_option("--engine", params->engine,
                    "Engine/framework hint for URL or HF refs (mlx, llamacpp, onnx, sherpa)");
    cmd->add_option("--temp,--temperature", params->temperature, "Sampling temperature");
    cmd->add_option("--max-tokens", params->max_tokens, "Max tokens to generate (default 1024)");
    cmd->add_flag("--no-think", params->no_think, "Disable the model's thinking phase");
    cmd->callback([&options, ref, prompt, image, params]() {
        const int exit_code = run_run(options, *ref, *prompt, *image, *params);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
