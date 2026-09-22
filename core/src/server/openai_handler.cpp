/** @file openai_handler.cpp OpenAI protocol translation for local LLMs. */
#include "openai_handler.h"

#include "json_utils.h"
#include "llm_service.pb.h"
#include "openai_translation.h"
#include "tool_calling.pb.h"

#include <chrono>
#include <condition_variable>
#include <functional>
#include <limits>
#include <set>
#include <stdexcept>
#include <thread>
#include <vector>

#include "features/llm/llm_thinking_stream_internal.h"
#include "features/llm/llm_thinking_tags_internal.h"
#include "rac/features/llm/rac_tool_calling.h"

namespace rac::server {
namespace {
using Json = nlohmann::json;

int64_t timestamp() {
    return std::chrono::duration_cast<std::chrono::seconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

void require(bool valid, const std::string& message) {
    if (!valid)
        throw std::invalid_argument(message);
}

void validateRequest(const Json& request) {
    require(request.is_object(), "Request must be a JSON object");
    require(request.contains("messages") && request["messages"].is_array() &&
                !request["messages"].empty(),
            "messages must be a nonempty array");
    for (const auto& message : request["messages"]) {
        require(message.is_object() && message.contains("role") && message["role"].is_string(),
                "Every message must have a string role");
        const auto role = message["role"].get<std::string>();
        require(role == "system" || role == "developer" || role == "user" || role == "assistant" ||
                    role == "tool",
                "Unsupported message role: " + role);
        if (message.contains("content") && !message["content"].is_null()) {
            const auto& content = message["content"];
            require(content.is_string() || content.is_array(),
                    "content must be text or text parts");
            if (content.is_array()) {
                for (const auto& part : content) {
                    require(part.is_object() && part.value("type", Json()) == "text" &&
                                part.contains("text") && part["text"].is_string(),
                            "Only text content parts are supported by this server");
                }
            }
        } else {
            require(role == "assistant" && message.contains("tool_calls"),
                    "Only assistant tool-call messages may have null or missing content");
        }
        if (message.contains("name"))
            require(message["name"].is_string(), "name must be text");
        if (role == "tool") {
            require(message.contains("tool_call_id") && message["tool_call_id"].is_string(),
                    "Tool results require a string tool_call_id");
        }
        if (message.contains("tool_calls")) {
            require(role == "assistant" && message["tool_calls"].is_array() &&
                        !message["tool_calls"].empty(),
                    "tool_calls must be a nonempty assistant array");
            for (const auto& call : message["tool_calls"]) {
                require(call.is_object() && call.contains("id") && call["id"].is_string() &&
                            call.value("type", Json()) == "function" && call.contains("function") &&
                            call["function"].is_object(),
                        "Malformed assistant tool call");
                const auto& function = call["function"];
                require(function.contains("name") && function["name"].is_string() &&
                            function.contains("arguments") && function["arguments"].is_string(),
                        "Tool calls require string function name and arguments");
            }
        }
    }
    if (request.contains("stream"))
        require(request["stream"].is_boolean(), "stream must be boolean");
    if (request.contains("model"))
        require(request["model"].is_string(), "model must be a string");
    for (const char* key : {"max_tokens", "max_completion_tokens"}) {
        if (request.contains(key) && !request[key].is_null()) {
            require(request[key].is_number_integer() && request[key] > 0 &&
                        request[key] <= std::numeric_limits<int32_t>::max(),
                    std::string(key) + " must be a positive 32-bit integer");
        }
    }
    for (const char* key : {"temperature", "top_p", "frequency_penalty", "presence_penalty"}) {
        if (!request.contains(key) || request[key].is_null())
            continue;
        const double minimum = std::string(key).find("penalty") != std::string::npos ? -2 : 0;
        const double maximum = std::string(key) == "top_p" ? 1 : 2;
        require(request[key].is_number() && request[key] >= minimum && request[key] <= maximum,
                std::string("Invalid ") + key);
    }
    if (request.contains("n"))
        require(request["n"] == 1, "Only n=1 is supported");
    if (request.contains("seed"))
        require(request["seed"].is_number_integer(), "seed must be integer");
    if (request.contains("stop") && !request["stop"].is_null()) {
        const auto& stop = request["stop"];
        require(stop.is_string() || stop.is_array(), "stop must be a string or array of strings");
        if (stop.is_array()) {
            for (const auto& value : stop)
                require(value.is_string(), "stop entries must be strings");
        }
    }
    if (request.contains("stream_options")) {
        require(request["stream_options"].is_object(), "stream_options must be an object");
        const auto& streamOptions = request["stream_options"];
        if (streamOptions.contains("include_usage"))
            require(streamOptions["include_usage"].is_boolean(), "include_usage must be boolean");
    }
    std::set<std::string> names;
    if (request.contains("tools")) {
        require(request["tools"].is_array(), "tools must be an array");
        for (const auto& tool : request["tools"]) {
            require(tool.is_object() && tool.value("type", Json()) == "function" &&
                        tool.contains("function") && tool["function"].is_object(),
                    "Only function tools are supported");
            const auto& function = tool["function"];
            require(function.contains("name") && function["name"].is_string() &&
                        !function["name"].get<std::string>().empty(),
                    "Tool name must be nonempty");
            require(names.insert(function["name"].get<std::string>()).second,
                    "Duplicate tool name");
            if (function.contains("description"))
                require(function["description"].is_string(), "Tool description must be a string");
            if (function.contains("parameters"))
                require(function["parameters"].is_object(),
                        "Tool parameters must be a JSON schema object");
        }
    }
    if (request.contains("parallel_tool_calls"))
        require(request["parallel_tool_calls"].is_boolean(), "parallel_tool_calls must be boolean");
    const auto choice = request.value("tool_choice", Json("auto"));
    if (choice.is_object()) {
        require(choice.value("type", Json()) == "function" && choice.contains("function") &&
                    choice["function"].is_object() && choice["function"].contains("name") &&
                    choice["function"]["name"].is_string(),
                "Invalid named tool_choice");
        require(names.count(choice["function"]["name"].get<std::string>()) > 0,
                "tool_choice refers to an unknown tool");
    } else {
        require(choice == "auto" || choice == "none" || choice == "required",
                "Invalid tool_choice");
        require(choice != "required" || !names.empty(), "tool_choice required needs tools");
    }
}

// Own all pointer-backed options through generation (including delayed SSE providers).
struct GenerationOptions {
    rac_llm_options_t value = RAC_LLM_OPTIONS_DEFAULT;
    std::vector<std::string> stops;
    std::vector<const char*> stopPointers;
    GenerationOptions(const Json& request, int32_t threads) {
        value.max_tokens = 4096;
        value.n_threads = threads;
        value.streaming_enabled = RAC_TRUE;
        for (const char* key : {"max_tokens", "max_completion_tokens"}) {
            if (request.contains(key) && !request[key].is_null())
                value.max_tokens = request[key];
        }
        if (request.contains("temperature") && !request["temperature"].is_null())
            value.temperature = request["temperature"];
        if (request.contains("top_p") && !request["top_p"].is_null())
            value.top_p = request["top_p"];
        if (request.contains("frequency_penalty") && !request["frequency_penalty"].is_null())
            value.frequency_penalty = request["frequency_penalty"];
        if (request.contains("presence_penalty") && !request["presence_penalty"].is_null())
            value.presence_penalty = request["presence_penalty"];
        if (request.contains("seed"))
            value.seed = request["seed"];
        if (request.contains("stop") && !request["stop"].is_null()) {
            if (request["stop"].is_string())
                stops.push_back(request["stop"]);
            else
                stops = request["stop"].get<std::vector<std::string>>();
        }
        for (const auto& stop : stops)
            stopPointers.push_back(stop.c_str());
        value.stop_sequences = stopPointers.data();
        value.num_stop_sequences = stopPointers.size();
    }
};

Json responseMessage(const std::string& raw, const Json& request) {
    // The same SDK splitter is used for buffered SSE tool responses and unary
    // output, so tags, split delimiters, and prefilled reasoning have one policy.
    rac::llm::ThinkingStreamSplitter splitter;
    splitter.set_hold_ambiguous_prefix(true);
    std::vector<rac::llm::ThinkingStreamSegment> parts;
    splitter.push(raw, &parts);
    splitter.flush(&parts);
    std::string content, reasoning;
    for (const auto& part : parts) {
        (part.channel == rac::llm::ThinkingChannel::kReasoning ? reasoning : content) += part.text;
    }
    Json message = {{"role", "assistant"}, {"content", content}};
    if (!reasoning.empty())
        message["reasoning_content"] = reasoning;
    const auto tools = request.value("tools", Json::array());
    const auto choice = request.value("tool_choice", Json("auto"));
    if (tools.empty() || choice == "none")
        return message;

    runanywhere::v1::ToolParseRequest parseRequest;
    // Some models omit the advertised wrapper but still return exactly its JSON
    // payload. Normalize that envelope before reusing the SDK parser.
    const auto bareCall = Json::parse(content, nullptr, false);
    if (bareCall.is_object() && bareCall.contains("tool") && bareCall.contains("arguments")) {
        parseRequest.set_text("<tool_call>" + content + "</tool_call>");
    } else {
        parseRequest.set_text(content);
    }
    parseRequest.mutable_options()->set_format(runanywhere::v1::TOOL_CALL_FORMAT_NAME_JSON);
    parseRequest.mutable_options()->set_parallel_tool_calls(true);
    const std::string bytes = parseRequest.SerializeAsString();
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_tool_call_parse_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &out);
    runanywhere::v1::ToolParseResult parsed;
    const bool valid = rc == RAC_SUCCESS && out.status == RAC_SUCCESS && out.data &&
                       parsed.ParseFromArray(out.data, static_cast<int>(out.size));
    rac_proto_buffer_free(&out);
    if (!valid)
        throw std::runtime_error("Failed to parse generated tool response");
    if (parsed.error_code() != RAC_SUCCESS ||
        (!parsed.has_tool_call() && content.find("<tool_call>") != std::string::npos))
        throw std::runtime_error("Model generated an incomplete or invalid tool call");
    if (parsed.has_tool_call() && parsed.tool_calls_size() > 0) {
        Json calls = Json::array();
        for (const auto& call : parsed.tool_calls()) {
            bool known = false;
            for (const auto& tool : tools)
                known |= tool["function"]["name"] == call.name();
            if (!known)
                throw std::runtime_error("Model generated an unknown tool: " + call.name());
            if (choice.is_object() && choice["function"]["name"] != call.name())
                throw std::runtime_error("Model did not follow the requested tool_choice");
            const std::string arguments =
                call.arguments_json().empty() ? "{}" : call.arguments_json();
            const auto parsedArgs = Json::parse(arguments, nullptr, false);
            if (!parsedArgs.is_object())
                throw std::runtime_error("Model generated invalid tool arguments");
            calls.push_back({{"id", translation::generateToolCallId()},
                             {"type", "function"},
                             {"function", {{"name", call.name()}, {"arguments", arguments}}}});
        }
        if (!request.value("parallel_tool_calls", true) && calls.size() > 1)
            throw std::runtime_error("Model generated parallel calls when they were disabled");
        message["tool_calls"] = calls;
        message["content"] =
            parsed.remaining_text().empty() ? Json(nullptr) : Json(parsed.remaining_text());
    } else if (choice == "required" || choice.is_object()) {
        throw std::runtime_error("Model did not produce the required tool call");
    }
    return message;
}

struct Generation {
    std::string raw;
    std::string finish = "stop";
    int32_t tokens = 0;
    int32_t promptTokens = 0;
    int32_t cachedPromptTokens = 0;
    bool disconnected = false;
    bool timedOut = false;
    rac_result_t result = RAC_SUCCESS;
};

Generation generate(rac_handle_t handle, const runanywhere::v1::LLMGenerateRequest& request,
                    const std::string& fallbackPrompt, GenerationOptions& options,
                    int32_t timeoutSeconds, const std::function<bool(const char*)>& onToken,
                    const std::function<bool()>& connected) {
    Generation generation;
    // Cancellation must also work while prefill has not produced its first token.
    std::mutex mutex;
    std::condition_variable completed;
    bool done = false;
    std::atomic<bool> timedOut{false}, disconnected{false};
    std::thread watchdog([&] {
        const auto deadline =
            std::chrono::steady_clock::now() + std::chrono::seconds(timeoutSeconds);
        std::unique_lock lock(mutex);
        while (!completed.wait_for(lock, std::chrono::milliseconds(100), [&] { return done; })) {
            if (!connected()) {
                disconnected = true;
                rac_llm_cancel(handle);
                break;
            }
            if (std::chrono::steady_clock::now() >= deadline) {
                timedOut = true;
                rac_llm_cancel(handle);
                break;
            }
        }
    });
    struct Callback {
        Generation* generation;
        const std::function<bool(const char*)>* onToken;
    } callback{&generation, &onToken};
    try {
        const auto streamCallback = [](const char* token, rac_bool_t final, const char* reason,
                                       int32_t count, void* user) -> rac_bool_t {
            auto& state = *static_cast<Callback*>(user);
            if (final && reason && reason[0])
                state.generation->finish = reason;
            if (!token || !token[0])
                return RAC_TRUE;
            state.generation->raw += token;
            state.generation->tokens += count > 0 ? count : 1;
            if (!(*state.onToken)(token)) {
                state.generation->disconnected = true;
                return RAC_FALSE;
            }
            return RAC_TRUE;
        };
        const auto* service = static_cast<const rac_llm_service_t*>(handle);
        if (service->ops && service->ops->generate_chat_stream) {
            const std::string bytes = request.SerializeAsString();
            generation.result = service->ops->generate_chat_stream(
                service->impl, reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                streamCallback, &callback);
        } else {
            generation.result = rac_llm_generate_stream(handle, fallbackPrompt.c_str(),
                                                        &options.value, streamCallback, &callback);
        }
    } catch (...) {
        generation.result = RAC_ERROR_INTERNAL;
    }
    {
        std::lock_guard lock(mutex);
        done = true;
    }
    completed.notify_all();
    watchdog.join();
    generation.timedOut = timedOut;
    generation.disconnected |= disconnected;
    const auto* service = static_cast<const rac_llm_service_t*>(handle);
    if (service->ops && service->ops->get_stream_token_counts) {
        rac_llm_token_counts_t counts{};
        if (service->ops->get_stream_token_counts(service->impl, &counts) == RAC_SUCCESS) {
            generation.tokens = counts.completion_tokens;
            generation.promptTokens = counts.prompt_tokens;
            generation.cachedPromptTokens = counts.cached_prompt_tokens;
        }
    }
    return generation;
}

bool failed(const Generation& generation) {
    return RAC_FAILED(generation.result) || generation.timedOut || generation.disconnected ||
           generation.finish == "error" || generation.finish == "cancelled";
}

Json chunk(const std::string& id, int64_t created, const std::string& model, const Json& delta,
           const Json& finish = nullptr) {
    return {
        {"id", id},
        {"object", "chat.completion.chunk"},
        {"created", created},
        {"model", model},
        {"choices", Json::array({{{"index", 0}, {"delta", delta}, {"finish_reason", finish}}})}};
}

Json usageObject(const Generation& generation) {
    return {{"prompt_tokens", generation.promptTokens},
            {"completion_tokens", generation.tokens},
            {"total_tokens", generation.promptTokens + generation.tokens},
            {"prompt_tokens_details", {{"cached_tokens", generation.cachedPromptTokens}}}};
}

struct ActiveRequest {
    std::atomic<int32_t>& count;
    explicit ActiveRequest(std::atomic<int32_t>& count) : count(count) { ++count; }
    ~ActiveRequest() { --count; }
};
}  // namespace

OpenAIHandler::OpenAIHandler(rac_handle_t handle, const std::string& model, int32_t threads,
                             int32_t timeoutSeconds)
    : llmHandle_(handle), modelId_(model), threads_(threads), timeoutSeconds_(timeoutSeconds) {
    rac_llm_info_t info{};
    ready_ = handle && rac_llm_get_info(handle, &info) == RAC_SUCCESS && info.is_ready;
}

void OpenAIHandler::requestStop() {
    stopping_ = true;
    rac_llm_cancel(llmHandle_);
}

void OpenAIHandler::handleModels(const httplib::Request&, httplib::Response& res) {
    res.set_content(Json({{"object", "list"},
                          {"data", Json::array({{{"id", modelId_},
                                                 {"object", "model"},
                                                 {"created", timestamp()},
                                                 {"owned_by", "runanywhere"}}})}})
                        .dump(),
                    "application/json");
}

void OpenAIHandler::handleHealth(const httplib::Request&, httplib::Response& res) {
    const bool ready = ready_ && !stopping_;
    res.status = ready ? 200 : 503;
    res.set_content(Json({{"status", ready ? "ok" : "unavailable"},
                          {"model", modelId_},
                          {"model_loaded", ready}})
                        .dump(),
                    "application/json");
}

void OpenAIHandler::handleChatCompletions(const httplib::Request& req, httplib::Response& res) {
    try {
        const auto request = Json::parse(req.body);
        validateRequest(request);
        if (request.contains("model") && request["model"] != modelId_) {
            sendError(res, 404,
                      "Requested model is not loaded: " + request["model"].get<std::string>(),
                      "model_not_found");
            return;
        }
        if (stopping_ || !ready_) {
            sendError(res, 503, "Local model is unavailable", "server_error");
            return;
        }
        if (request.value("stream", false))
            processStreaming(req, res, request);
        else
            processNonStreaming(req, res, request);
    } catch (const Json::exception& error) {
        sendError(res, 400, std::string("Invalid request: ") + error.what(),
                  "invalid_request_error");
    } catch (const std::invalid_argument& error) {
        sendError(res, 400, error.what(), "invalid_request_error");
    } catch (const std::exception& error) {
        sendError(res, 500, error.what(), "server_error");
    }
}

void OpenAIHandler::processNonStreaming(const httplib::Request& req, httplib::Response& res,
                                        const Json& request) {
    ActiveRequest active(activeRequests_);
    std::unique_lock lock(generationMutex_);
    if (stopping_) {
        sendError(res, 503, "Server is stopping", "server_error");
        return;
    }
    const auto* service = static_cast<const rac_llm_service_t*>(llmHandle_);
    const auto prompt = service->ops && service->ops->generate_chat_stream
                            ? std::string()
                            : translation::buildPromptFromOpenAI(
                                  request["messages"], request.value("tools", Json::array()),
                                  request.value("tool_choice", Json("auto")));
    const auto structuredRequest = translation::buildGenerateRequest(request, modelId_);
    GenerationOptions options(request, threads_);
    const auto generation = generate(
        llmHandle_, structuredRequest, prompt, options, timeoutSeconds_,
        [](const char*) { return true; }, [&req] { return !req.is_connection_closed(); });
    totalTokensGenerated_ += generation.tokens;
    if (failed(generation)) {
        sendError(res, generation.timedOut ? 504 : 500,
                  generation.timedOut ? "Local generation timed out"
                                      : "Local generation failed or was cancelled",
                  "server_error");
        return;
    }
    const auto message = responseMessage(generation.raw, request);
    const auto finish = message.contains("tool_calls") ? "tool_calls" : generation.finish;
    const Json response = {
        {"id", "chatcmpl-" + translation::generateToolCallId()},
        {"object", "chat.completion"},
        {"created", timestamp()},
        {"model", modelId_},
        {"choices", Json::array({{{"index", 0}, {"message", message}, {"finish_reason", finish}}})},
        {"usage", usageObject(generation)}};
    res.set_content(response.dump(), "application/json");
}

void OpenAIHandler::processStreaming(const httplib::Request&, httplib::Response& res,
                                     const Json& request) {
    const auto* service = static_cast<const rac_llm_service_t*>(llmHandle_);
    const auto prompt = service->ops && service->ops->generate_chat_stream
                            ? std::string()
                            : translation::buildPromptFromOpenAI(
                                  request["messages"], request.value("tools", Json::array()),
                                  request.value("tool_choice", Json("auto")));
    const auto structuredRequest = translation::buildGenerateRequest(request, modelId_);
    const std::string id = "chatcmpl-" + translation::generateToolCallId();
    const int64_t created = timestamp();
    res.set_header("Cache-Control", "no-cache");
    res.set_chunked_content_provider("text/event-stream", [this, request, structuredRequest, prompt,
                                                           id, created](size_t,
                                                                        httplib::DataSink& sink) {
        ActiveRequest active(activeRequests_);
        std::unique_lock lock(generationMutex_);
        const auto send = [&](const Json& value) {
            const std::string data = json::formatSSE(value);
            return sink.write(data.data(), data.size());
        };
        const auto sendDelta = [&](const Json& delta) {
            return send(chunk(id, created, modelId_, delta));
        };
        try {
            if (stopping_)
                throw std::runtime_error("Server is stopping");
            if (!sendDelta({{"role", "assistant"}}))
                return false;
            const bool tools = request.contains("tools") && !request["tools"].empty() &&
                               request.value("tool_choice", Json("auto")) != "none";
            rac::llm::ThinkingStreamSplitter splitter;
            const auto* service = static_cast<const rac_llm_service_t*>(llmHandle_);
            splitter.set_hold_ambiguous_prefix(
                rac::llm::model_thinking_profile_from_registry(service->model_id)
                    .supports_thinking);
            const auto emitParts = [&](const std::vector<rac::llm::ThinkingStreamSegment>& parts) {
                for (const auto& part : parts) {
                    if (!sendDelta({{part.channel == rac::llm::ThinkingChannel::kReasoning
                                         ? "reasoning_content"
                                         : "content",
                                     part.text}}))
                        return false;
                }
                return true;
            };
            GenerationOptions options(request, threads_);
            const auto generation = generate(
                llmHandle_, structuredRequest, prompt, options, timeoutSeconds_,
                [&](const char* token) {
                    if (tools)
                        return !sink.is_writable || sink.is_writable();
                    std::vector<rac::llm::ThinkingStreamSegment> parts;
                    splitter.push(token, &parts);
                    return emitParts(parts);
                },
                [&sink] { return !sink.is_writable || sink.is_writable(); });
            totalTokensGenerated_ += generation.tokens;
            if (generation.disconnected)
                return false;
            if (failed(generation))
                throw std::runtime_error(generation.timedOut
                                             ? "Local generation timed out"
                                             : "Local generation failed or was cancelled");
            std::string finish = generation.finish;
            if (tools) {
                // Buffer tool-enabled output until the SDK can distinguish a
                // complete tool envelope from ordinary text. Never leak JSON as content.
                auto message = responseMessage(generation.raw, request);
                message.erase("role");
                if (message.contains("tool_calls")) {
                    finish = "tool_calls";
                    for (size_t index = 0; index < message["tool_calls"].size(); ++index)
                        message["tool_calls"][index]["index"] = index;
                }
                if (message["content"].is_null())
                    message.erase("content");
                if (!sendDelta(message))
                    return false;
            } else {
                std::vector<rac::llm::ThinkingStreamSegment> parts;
                splitter.flush(&parts);
                if (!emitParts(parts))
                    return false;
            }
            if (!send(chunk(id, created, modelId_, Json::object(), finish)))
                return false;
            if (request.contains("stream_options") && request["stream_options"].is_object() &&
                request["stream_options"].value("include_usage", false)) {
                auto usageChunk = chunk(id, created, modelId_, Json::object());
                usageChunk["choices"] = Json::array();
                usageChunk["usage"] = usageObject(generation);
                if (!send(usageChunk))
                    return false;
            }
        } catch (const std::exception& error) {
            if (!send(json::createErrorResponse(error.what(), "server_error", 500)))
                return false;
        }
        const std::string done = json::formatSSEDone();
        if (!sink.write(done.data(), done.size()))
            return false;
        sink.done();
        return true;
    });
}

void OpenAIHandler::sendError(httplib::Response& res, int status, const std::string& message,
                              const std::string& type) {
    res.status = status;
    res.set_content(json::createErrorResponse(message, type, status).dump(), "application/json");
}
}  // namespace rac::server
