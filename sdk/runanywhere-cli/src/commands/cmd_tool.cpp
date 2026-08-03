/**
 * @file cmd_tool.cpp
 * @brief `rcli llm tool-call` — exercise the tool-calling loop end to end.
 *
 * Thin wrapper over rac_tool_calling_run_loop_proto: load an LLM, hand commons
 * a prompt plus two built-in demo tools (get_weather, calculate), and let
 * commons drive the whole decide → call → execute → synthesize loop. The host
 * executor here returns canned JSON so the loop can complete offline; the point
 * is to see whether a given model actually emits a well-formed tool call and
 * whether commons parses it and produces a grounded final answer.
 */

#include "commands/commands.h"

#include <cstdint>
#include <memory>
#include <string>

#include "model_types.pb.h"
#include "tool_calling.pb.h"

#include "rac/core/rac_core.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"

#include "bootstrap.h"
#include "catalog/model_ref.h"
#include "commands/engine_options.h"
#include "io/output.h"
#include "io/proto.h"
#include "progress/progress_bar.h"

namespace rcli::commands {
namespace {

namespace v1 = runanywhere::v1;

// Small instruct GGUF that ships in the built-in catalog. Override with --model
// (e.g. `lfm2-350m-q8_0` to exercise the LFM2 tool-call format path).
constexpr const char* kDefaultToolModel = "qwen3-0.6b";

struct ToolCallParams {
    std::string prompt;
    std::string model;
    std::string engine;
    std::string tool_choice;  // auto | required | none | specific (default auto)
    std::string force_tool;   // name for tool_choice=specific
    int max_tool_calls = 3;
};

bool parse_tool_choice(const std::string& mode, v1::ToolChoiceMode* out) {
    if (mode.empty() || mode == "auto") {
        *out = v1::TOOL_CHOICE_MODE_AUTO;
    } else if (mode == "required") {
        *out = v1::TOOL_CHOICE_MODE_REQUIRED;
    } else if (mode == "none") {
        *out = v1::TOOL_CHOICE_MODE_NONE;
    } else if (mode == "specific") {
        *out = v1::TOOL_CHOICE_MODE_SPECIFIC;
    } else {
        return false;
    }
    return true;
}

// rac_tool_calling_run_loop_proto invokes this synchronously and unconditionally
// (it is not null-checked), so a real no-op is required even when the CLI has no
// use for the cancellable handle.
void ignore_published_handle(uint64_t /*handle*/, void* /*user_data*/) {}

void add_string_param(v1::ToolDefinition* tool, const char* name, const char* description) {
    v1::ToolParameter* param = tool->add_parameters();
    param->set_name(name);
    param->set_type(v1::TOOL_PARAMETER_TYPE_STRING);
    param->set_description(description);
    param->set_required(true);
}

// Synchronous host executor: commons hands us a serialized ToolCall and expects
// an owned serialized ToolResult back. We echo the call to stderr and return a
// canned result per tool so the loop can synthesize a final answer offline.
rac_result_t demo_executor(const uint8_t* in_bytes, size_t in_size, rac_proto_buffer_t* out_result,
                           void* user_data) {
    (void)user_data;
    v1::ToolCall call;
    if (in_size > 0) {
        (void)call.ParseFromArray(in_bytes, static_cast<int>(in_size));
    }
    out::status_line("  executing " + call.name() + "(" + call.arguments_json() + ")");

    v1::ToolResult result;
    result.set_tool_call_id(call.id());
    result.set_name(call.name());
    result.set_success(true);
    if (call.name() == "get_weather") {
        result.set_result_json(R"({"temperature_c":18,"condition":"cloudy"})");
    } else if (call.name() == "calculate") {
        result.set_result_json(R"({"note":"demo executor does not evaluate expressions"})");
    } else {
        result.set_result_json(R"({"ok":true})");
    }

    const std::string bytes = proto::serialize(result);
    rac_proto_buffer_init(out_result);
    return rac_proto_buffer_copy(
        bytes.empty() ? nullptr : reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
        out_result);
}

bool load_model(const GlobalOptions& options, const std::string& model_id,
                v1::InferenceFramework framework) {
    progress::DownloadProgressScope progress_scope(model_id, !options.no_progress && !options.json);
    v1::ModelLoadRequest request;
    request.set_model_id(model_id);
    request.set_validate_availability(true);
    if (framework != v1::INFERENCE_FRAMEWORK_UNSPECIFIED) {
        request.set_framework(framework);
    }
    const std::string bytes = proto::serialize(request);

    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    std::string error;
    v1::ModelLoadResult result;
    if (rac_model_lifecycle_load_proto(rac_get_model_registry(),
                                       reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                                       &out_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&out_buffer, &result, &error)) {
        out::error_line("model load failed: " + error);
        return false;
    }
    if (result.has_error()) {
        out::error_line("model load failed: " + (result.error().message().empty()
                                                     ? "unknown error"
                                                     : result.error().message()));
        return false;
    }
    return true;
}

int run_tool_call(const GlobalOptions& options, const ToolCallParams& params) {
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
    engine_hint.resolve_options.has_category = true;
    engine_hint.resolve_options.category = v1::MODEL_CATEGORY_LANGUAGE;

    model_ref::Resolved resolved;
    std::string error;
    if (model_ref::resolve(params.model, &resolved, &error, &engine_hint.resolve_options) !=
        RAC_SUCCESS) {
        out::error_line(error);
        return 1;
    }

    const v1::InferenceFramework load_framework =
        resolved.from_catalog ? v1::INFERENCE_FRAMEWORK_UNSPECIFIED : engine_hint.framework;
    if (!load_model(options, resolved.model_id, load_framework)) {
        return 1;
    }

    v1::ToolCallingSessionCreateRequest request;
    request.set_prompt(params.prompt);
    request.set_max_tokens(256);
    request.set_auto_execute(true);
    if (params.max_tool_calls > 0) {
        request.set_max_tool_calls(params.max_tool_calls);
    }

    v1::ToolDefinition* weather = request.add_tools();
    weather->set_name("get_weather");
    weather->set_description("Get the current weather for a city");
    add_string_param(weather, "location", "City name, e.g. Tokyo");

    v1::ToolDefinition* calc = request.add_tools();
    calc->set_name("calculate");
    calc->set_description("Evaluate an arithmetic expression");
    add_string_param(calc, "expression", "Expression such as 45 * 12");

    v1::ToolChoiceMode choice = v1::TOOL_CHOICE_MODE_AUTO;
    if (!parse_tool_choice(params.tool_choice, &choice)) {
        out::error_line("--tool-choice expects auto|required|none|specific");
        return 2;
    }
    if (!params.force_tool.empty()) {
        request.set_tool_choice(v1::TOOL_CHOICE_MODE_SPECIFIC);
        request.set_forced_tool_name(params.force_tool);
    } else if (choice != v1::TOOL_CHOICE_MODE_AUTO) {
        request.set_tool_choice(choice);
    }

    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    const rac_result_t rc = rac_tool_calling_run_loop_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), demo_executor, nullptr,
        ignore_published_handle, nullptr, &out_buffer);

    // The run loop writes a structured ToolCallingResult even when it returns a
    // non-success rc (e.g. a generation failure lands in error_code/error_message),
    // so parse the envelope first and report from it rather than the bare rc.
    std::string parse_error;
    v1::ToolCallingResult result;
    if (!proto::parse_proto_buffer(&out_buffer, &result, &parse_error)) {
        out::error_line("tool-calling failed: " +
                        (parse_error.empty() ? std::to_string(rc) : parse_error));
        return 1;
    }

    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("text", result.text())
            .field("is_complete", result.is_complete())
            .field("iterations", static_cast<int64_t>(result.iterations_used()))
            .field("tool_calls", static_cast<int64_t>(result.tool_calls_size()))
            .end_object();
        out::result_line(json.str());
        return result.is_complete() ? 0 : 1;
    }

    for (int i = 0; i < result.tool_calls_size(); ++i) {
        const v1::ToolCall& call = result.tool_calls(i);
        out::status_line("tool call " + std::to_string(i + 1) + ": " + call.name() + "(" +
                         call.arguments_json() + ")");
    }
    if (result.error_code() != 0) {
        out::error_line("tool-calling error: " + result.error_message());
    }
    out::status_line("iterations: " + std::to_string(result.iterations_used()) +
                     ", tool calls: " + std::to_string(result.tool_calls_size()));
    out::result_line(result.text());
    return result.is_complete() ? 0 : 1;
}

void configure_tool_call(CLI::App* cmd, GlobalOptions& options) {
    auto params = std::make_shared<ToolCallParams>();
    cmd->add_option("prompt", params->prompt, "What to ask the model")->required();
    cmd->add_option("--model,-m", params->model, "Model to use for the tool-calling loop")
        ->default_val(kDefaultToolModel);
    cmd->add_option("--engine", params->engine, "Pin a specific inference engine");
    cmd->add_option("--tool-choice", params->tool_choice,
                    "How the model may call tools: auto|required|none|specific");
    cmd->add_option("--force-tool", params->force_tool,
                    "Force one tool by name (implies --tool-choice specific)");
    cmd->add_option("--max-tool-calls", params->max_tool_calls,
                    "Maximum host tool executions per turn");
    cmd->callback([&options, params]() {
        const int exit_code = run_tool_call(options, *params);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace

void register_tool(CLI::App& app, GlobalOptions& options) {
    // Tool calling is an LLM capability, so it lives under the `llm` namespace
    // that register_llm() already created (app.cpp registers llm first).
    CLI::App* ns = app.get_subcommand("llm");
    configure_tool_call(
        ns->add_subcommand("tool-call",
                           "Run the tool-calling loop with built-in demo tools (get_weather, "
                           "calculate)"),
        options);
}

}  // namespace rcli::commands
