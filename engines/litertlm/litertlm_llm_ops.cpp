/**
 * @file litertlm_llm_ops.cpp
 * @brief LLM (RAC_PRIMITIVE_GENERATE_TEXT) vtable over the LiteRT-LM C API.
 *
 * Compiled only when the prebuilt library is present (see CMakeLists.txt).
 *
 * Threads. LiteRT-LM delivers stream chunks on its own threads, while commons
 * requires generate_stream() to block and to call back on the calling thread
 * (its final-signal side channel is thread-local and the SDK callbacks are bound
 * to it). So the chunk callback only queues, and the calling thread drains.
 *
 * Handles. A LiteRT-LM handle must not see overlapping calls, so active_mutex
 * serializes the calls cancel() can overlap with.
 *
 * Chats. Commons sends the whole history with every request. Rendering it again
 * would prefill it again, turn after turn, so the engine keeps the conversation
 * of the last request and, when the next history is what that conversation
 * already holds, sends only the new message. Anything else starts a new one, and
 * so does a cancel, since a cancelled conversation can only be deleted. The kept
 * conversation only saves time: if it fails before any text went out, the request
 * runs again from the full history.
 *
 * No C++ exception may cross into the registry, JNI or the library: every op
 * body and the chunk callback coerce failures to rac_result_t.
 */

#include "litertlm_stream_helpers.h"

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <fstream>
#include <functional>
#include <memory>
#include <mutex>
#include <new>
#include <nlohmann/json.hpp>
#include <random>
#include <string>
#include <system_error>
#include <vector>

#include "c/conversation.h"
#include "c/engine.h"
#include "c/error_reporter.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"

namespace {

using litertlm_engine::ChunkText;
using litertlm_engine::StreamAssembler;

const char* LOG_CAT = "LiteRTLM";

// Keep in step with ACCELERATOR_POLICY_CPU / _GPU. config_json carries integers
// and this engine does not link protobuf, as in engines/llamacpp.
constexpr int kAcceleratorPolicyCpu = 2;
constexpr int kAcceleratorPolicyGpu = 3;

// top_k 0 means "no limit" in rac_llm_options_t. LiteRT-LM needs k >= 1 and caps
// it at the vocabulary size.
constexpr int32_t kNoTopKLimit = 1 << 24;

template <typename T, void (*Delete)(T*)>
struct HandleDeleter {
    void operator()(T* handle) const { Delete(handle); }
};
using EngineSettingsPtr =
    std::unique_ptr<LiteRtLmEngineSettings,
                    HandleDeleter<LiteRtLmEngineSettings, litert_lm_engine_settings_delete>>;
using ConversationConfigPtr = std::unique_ptr<
    LiteRtLmConversationConfig,
    HandleDeleter<LiteRtLmConversationConfig, litert_lm_conversation_config_delete>>;
using ConversationPtr =
    std::unique_ptr<LiteRtLmConversation,
                    HandleDeleter<LiteRtLmConversation, litert_lm_conversation_delete>>;
using OptionalArgsPtr = std::unique_ptr<
    LiteRtLmConversationOptionalArgs,
    HandleDeleter<LiteRtLmConversationOptionalArgs, litert_lm_conversation_optional_args_delete>>;
using SessionConfigPtr =
    std::unique_ptr<LiteRtLmSessionConfig,
                    HandleDeleter<LiteRtLmSessionConfig, litert_lm_session_config_delete>>;
using SamplerParamsPtr =
    std::unique_ptr<LiteRtLmSamplerParams,
                    HandleDeleter<LiteRtLmSamplerParams, litert_lm_sampler_params_delete>>;
using ThinkingConfigPtr =
    std::unique_ptr<LiteRtLmThinkingConfig,
                    HandleDeleter<LiteRtLmThinkingConfig, litert_lm_thinking_config_delete>>;
using RepetitionPenaltyPtr = std::unique_ptr<
    LiteRtLmRepetitionPenaltyConfig,
    HandleDeleter<LiteRtLmRepetitionPenaltyConfig, litert_lm_repetition_penalty_config_delete>>;
using BenchmarkInfoPtr =
    std::unique_ptr<LiteRtLmBenchmarkInfo,
                    HandleDeleter<LiteRtLmBenchmarkInfo, litert_lm_benchmark_info_delete>>;

struct StreamQueue {
    std::mutex mutex;
    std::condition_variable ready;
    std::deque<std::string> chunks;
    std::string error;
    bool out_of_memory = false;
    bool finished = false;
};

// What a conversation's KV cache was rendered and sampled with: a different value needs a
// new one. Thinking is here because a template can render the flag into the first turn.
struct ConversationKey {
    std::string system_prompt;
    bool thinking_disabled = false;
    int32_t top_k = 0;
    float top_p = 0.0f;
    float temperature = 0.0f;
    int64_t seed = 0;

    bool operator==(const ConversationKey& other) const {
        return system_prompt == other.system_prompt &&
               thinking_disabled == other.thinking_disabled && top_k == other.top_k &&
               top_p == other.top_p && temperature == other.temperature && seed == other.seed;
    }
};

// The conversation of the last request and the turns its KV cache holds.
struct KeptChat {
    // Declared first, so destroyed last: deleting the conversation waits for its tasks,
    // and a chunk callback may still be returning from the last queue of a request.
    std::vector<std::unique_ptr<StreamQueue>> queues;
    ConversationPtr conversation;
    ConversationKey key;
    std::vector<std::string> turns;

    void reset() {
        conversation.reset();
        queues.clear();
        turns.clear();
    }
};

struct Service {
    std::string model_path;
    int32_t context_length = 0;
    int32_t num_threads = 0;
    int accelerator_policy = 0;

    // Serializes load, generate and unload.
    std::mutex operation_mutex;
    LiteRtLmEngine* engine = nullptr;
    std::string chat_template;  // empty = the bundle's own
    KeptChat chat;
    bool keep_chats = true;  // false once the library has refused a kept turn of this model

    // Guards the members below. Held for short library calls only, never across a
    // caller callback.
    std::mutex active_mutex;
    bool request_active = false;
    bool cancel_requested = false;
    LiteRtLmConversation* conversation = nullptr;
    bool stream_counts_known = false;
    rac_llm_token_counts_t stream_counts{};
};

Service* as_service(void* impl) {
    return static_cast<Service*>(impl);
}

void report_failure(const char* what, const char* message) {
    const std::string text = std::string(what) + ": " + litertlm_engine::printable_ascii(message);
    RAC_LOG_ERROR(LOG_CAT, "%s", text.c_str());
    rac_error_set_details(text.c_str());
}

const char* last_error_message() {
    const char* message = litert_lm_get_last_error_message();
    return message != nullptr ? message : "no details";
}

// ─────────────────────────────── load ───────────────────────────────────────

void parse_load_options(const char* config_json, Service* service) {
    if (config_json == nullptr || config_json[0] == '\0') {
        return;
    }
    const nlohmann::json parsed =
        nlohmann::json::parse(config_json, nullptr, /*allow_exceptions=*/false);
    if (!parsed.is_object()) {
        RAC_LOG_WARNING(LOG_CAT, "ignoring unparseable load options");
        return;
    }
    if (parsed.contains("context_length") && parsed["context_length"].is_number_integer()) {
        service->context_length = parsed["context_length"].get<int32_t>();
    }
    if (parsed.contains("num_threads") && parsed["num_threads"].is_number_integer()) {
        service->num_threads = parsed["num_threads"].get<int32_t>();
    }
    // accelerator_policy wins over the deprecated use_gpu, as in engines/llamacpp.
    if (parsed.contains("accelerator_policy") && parsed["accelerator_policy"].is_number_integer()) {
        service->accelerator_policy = parsed["accelerator_policy"].get<int>();
    } else if (parsed.contains("use_gpu") && parsed["use_gpu"].is_boolean()) {
        service->accelerator_policy =
            parsed["use_gpu"].get<bool>() ? kAcceleratorPolicyGpu : kAcceleratorPolicyCpu;
    }
}

rac_result_t load_failure_code(LiteRtLmStatusCode status) {
    switch (status) {
        // A bad magic number or flatbuffer. NotFound stays generic: a section that failed
        // to map for lack of memory is reported as missing from the model.
        case kLiteRtLmStatusInvalidArgument:
            return RAC_ERROR_INVALID_MODEL_FORMAT;
        case kLiteRtLmStatusResourceExhausted:
            return RAC_ERROR_INSUFFICIENT_MEMORY;
        default:
            return RAC_ERROR_MODEL_LOAD_FAILED;
    }
}

rac_result_t open_engine(Service* service, const char* backend, LiteRtLmEngine** out_engine) {
    LiteRtLmEngineSettings* raw_settings = nullptr;
    LiteRtLmStatusCode status = litert_lm_engine_settings_create(
        service->model_path.c_str(), backend, nullptr, nullptr, &raw_settings);
    if (status != kLiteRtLmStatusOk) {
        report_failure("LiteRT-LM settings", last_error_message());
        return load_failure_code(status);
    }
    const EngineSettingsPtr settings(raw_settings);
    if (service->context_length > 0) {
        (void)litert_lm_engine_settings_set_max_num_tokens(settings.get(), service->context_length);
    }
    if (service->num_threads > 0) {
        (void)litert_lm_engine_settings_set_num_threads(settings.get(), service->num_threads);
    }
    // The only source of exact token counts: chunks are not tokens, since a
    // multi-byte character can take several tokens.
    (void)litert_lm_engine_settings_enable_benchmark(settings.get());

    status = litert_lm_engine_create(settings.get(), out_engine);
    if (status != kLiteRtLmStatusOk) {
        report_failure("LiteRT-LM load", last_error_message());
        return load_failure_code(status);
    }
    return RAC_SUCCESS;
}

// True when a conversation on this chat template (empty = the bundle's own) renders a user's
// text. A conversation that cannot be made says nothing about the template, and the first
// request reports what is wrong.
bool renders_user_text(LiteRtLmEngine* engine, const std::string& chat_template) {
    constexpr char kMarker[] = "litertlm template check";
    LiteRtLmConversationConfig* raw_config = nullptr;
    if (litert_lm_conversation_config_create(&raw_config) != kLiteRtLmStatusOk) {
        return true;
    }
    const ConversationConfigPtr config(raw_config);
    if (!chat_template.empty()) {
        (void)litert_lm_conversation_config_set_prompt_template(config.get(),
                                                                chat_template.c_str());
    }
    LiteRtLmConversation* raw_conversation = nullptr;
    if (litert_lm_conversation_create(engine, config.get(), &raw_conversation) !=
        kLiteRtLmStatusOk) {
        return true;
    }
    const ConversationPtr conversation(raw_conversation);
    const std::string message =
        litertlm_engine::to_json_string(litertlm_engine::text_message("user", kMarker));
    const char* rendered = nullptr;
    return litert_lm_conversation_render_message_to_string(conversation.get(), message.c_str(),
                                                           &rendered) == kLiteRtLmStatusOk &&
           rendered != nullptr && std::string(rendered).find(kMarker) != std::string::npos;
}

// LiteRT-LM 0.18 and newer always hand a chat template a message's content as a list of parts
// (LiteRT-LM issue 3688). A template written for a string then renders the user's text as
// nothing, and the model answers something else with no error, or it fails on adding a list
// to a string. Such a bundle gets its template back with this in front, which puts the text
// of each message back as a string. The engine sends text parts only.
constexpr char kContentAsString[] =
    "{%- set flattened = namespace(messages=[]) -%}"
    "{%- for message in messages -%}"
    "{%- set text = namespace(value='') -%}"
    "{%- if message.content is string -%}"
    "{%- set text.value = message.content -%}"
    "{%- else -%}"
    "{%- for part in message.content -%}"
    "{%- if part.type == 'text' -%}{%- set text.value = text.value + part.text -%}{%- endif -%}"
    "{%- endfor -%}"
    "{%- endif -%}"
    "{%- set flattened.messages = flattened.messages + "
    "[{'role': message.role, 'content': text.value}] -%}"
    "{%- endfor -%}"
    "{%- set messages = flattened.messages -%}";

rac_result_t prepare_chat_template(Service* service) {
    service->chat_template.clear();
    if (renders_user_text(service->engine, service->chat_template)) {
        return RAC_SUCCESS;
    }
    std::ifstream file(service->model_path, std::ios::binary);
    const std::string own = litertlm_engine::bundle_chat_template(file);
    if (!own.empty()) {
        std::string repaired = kContentAsString + own;
        if (renders_user_text(service->engine, repaired)) {
            RAC_LOG_WARNING(LOG_CAT, "%s: the chat template reads content as a string; adapted",
                            service->model_path.c_str());
            service->chat_template = std::move(repaired);
            return RAC_SUCCESS;
        }
    }
    report_failure("LiteRT-LM chat template", "it does not render the user's message");
    return RAC_ERROR_INVALID_MODEL_FORMAT;
}

// After a restart the registry links a single-file model to its directory, so a directory
// is searched for the bundle, as engines/llamacpp does for .gguf.
std::string bundle_path(const std::string& path) {
    namespace fs = std::filesystem;
    std::error_code error;
    if (!fs::is_directory(path, error)) {
        return path;
    }
    for (fs::directory_iterator it(path, error), end; !error && it != end; it.increment(error)) {
        if (it->path().extension() == ".litertlm") {
            return it->path().string();
        }
    }
    return path;
}

rac_result_t load_model(Service* service) {
    service->model_path = bundle_path(service->model_path);
    std::error_code error;
    const auto size = std::filesystem::file_size(service->model_path, error);
    if (error) {
        report_failure("LiteRT-LM model not found", service->model_path.c_str());
        return RAC_ERROR_MODEL_NOT_FOUND;
    }
    if (size == 0) {
        report_failure("LiteRT-LM model is empty", service->model_path.c_str());
        return RAC_ERROR_INVALID_MODEL_FORMAT;
    }
    std::ifstream file(service->model_path, std::ios::binary);
    const std::uint64_t declared = litertlm_engine::bundle_declared_size(file);
    if (declared > size) {
        const std::string details = service->model_path + " has " + std::to_string(size) + " of " +
                                    std::to_string(declared) + " bytes";
        report_failure("LiteRT-LM model is cut short", details.c_str());
        return RAC_ERROR_INVALID_MODEL_FORMAT;
    }
    (void)litert_lm_set_min_log_level(kLiteRtLmLogSeverityWarning);

    std::vector<const char*> backends;
    if (service->accelerator_policy == kAcceleratorPolicyCpu) {
        backends = {"cpu"};
    } else if (service->accelerator_policy == kAcceleratorPolicyGpu) {
        backends = {"gpu"};
    } else {
        backends = {"gpu", "cpu"};
    }
    rac_result_t rc = RAC_ERROR_MODEL_LOAD_FAILED;
    for (const char* backend : backends) {
        rc = open_engine(service, backend, &service->engine);
        if (rc == RAC_SUCCESS) {
            const rac_result_t template_rc = prepare_chat_template(service);
            if (template_rc != RAC_SUCCESS) {
                litert_lm_engine_delete(service->engine);
                service->engine = nullptr;
                return template_rc;
            }
            RAC_LOG_INFO(LOG_CAT, "loaded %s on %s (context_length=%d)",
                         service->model_path.c_str(), backend, service->context_length);
            return RAC_SUCCESS;
        }
        RAC_LOG_WARNING(LOG_CAT, "backend %s failed to load the model: %d", backend, rc);
    }
    return rc;
}

// ──────────────────────────── stream plumbing ───────────────────────────────

void on_stream_chunk(void* data, const LiteRtLmStreamChunk* chunk) {
    auto* queue = static_cast<StreamQueue*>(data);
    const char* text = nullptr;
    const char* error = nullptr;
    bool is_final = false;
    (void)litert_lm_stream_chunk_get_text(chunk, &text);
    (void)litert_lm_stream_chunk_get_error(chunk, &error);
    (void)litert_lm_stream_chunk_is_final(chunk, &is_final);

    std::lock_guard<std::mutex> lock(queue->mutex);
    try {
        if (text != nullptr) {
            queue->chunks.emplace_back(text);
        }
        if (error != nullptr) {
            queue->error = error;
        }
    } catch (const std::bad_alloc&) {
        queue->out_of_memory = true;
    }
    if (is_final) {
        queue->finished = true;
    }
    queue->ready.notify_one();
}

rac_result_t generation_failure_code(const char* message) {
    const std::string text = message != nullptr ? message : "";
    // The library words a full context by the path the prefill took.
    for (const char* full :
         {"too long", "space left in the context window", "exceeds available state entries"}) {
        if (text.find(full) != std::string::npos) {
            return RAC_ERROR_CONTEXT_TOO_LONG;
        }
    }
    if (text.rfind("RESOURCE_EXHAUSTED", 0) == 0) {
        return RAC_ERROR_INSUFFICIENT_MEMORY;
    }
    return RAC_ERROR_GENERATION_FAILED;
}

// Marks one request active so that a cancel racing the setup below is kept, while
// a cancel from before this request cannot reach it.
class RequestScope {
   public:
    explicit RequestScope(Service* service) : service_(service) {
        std::lock_guard<std::mutex> lock(service_->active_mutex);
        service_->request_active = true;
        service_->cancel_requested = false;
        service_->stream_counts_known = false;
    }
    ~RequestScope() {
        std::lock_guard<std::mutex> lock(service_->active_mutex);
        service_->request_active = false;
        service_->conversation = nullptr;
    }
    RequestScope(const RequestScope&) = delete;
    RequestScope& operator=(const RequestScope&) = delete;

    // Cancels only if a stream is running. After this, the conversation can only be
    // deleted. The final chunk still arrives and ends the drain.
    void stop_stream() {
        std::lock_guard<std::mutex> lock(service_->active_mutex);
        if (service_->conversation != nullptr) {
            (void)litert_lm_conversation_cancel_process(service_->conversation);
        }
    }

    bool cancel_requested() const {
        std::lock_guard<std::mutex> lock(service_->active_mutex);
        return service_->cancel_requested;
    }

    // Publishes the conversation to cancel() and starts the stream without a gap in
    // which a cancel could be lost or overlap the start.
    rac_result_t start(LiteRtLmConversation* conversation, const std::string& message,
                       const LiteRtLmConversationOptionalArgs* args, StreamQueue* queue) {
        std::lock_guard<std::mutex> lock(service_->active_mutex);
        if (service_->cancel_requested) {
            return RAC_ERROR_CANCELLED;
        }
        const LiteRtLmStatusCode status = litert_lm_conversation_send_message_stream(
            conversation, message.c_str(), nullptr, args, on_stream_chunk, queue);
        if (status != kLiteRtLmStatusOk) {
            const char* failure = last_error_message();
            report_failure("LiteRT-LM send", failure);
            return generation_failure_code(failure);
        }
        service_->conversation = conversation;
        return RAC_SUCCESS;
    }

    // The final chunk arrived. From here cancel() cannot reach the conversation, so
    // reading from it cannot overlap a cancel. Returns whether a cancel got in first.
    bool end_stream() {
        std::lock_guard<std::mutex> lock(service_->active_mutex);
        service_->conversation = nullptr;
        return service_->cancel_requested;
    }

    void publish_counts(bool counts_known, const rac_llm_token_counts_t& counts) {
        std::lock_guard<std::mutex> lock(service_->active_mutex);
        service_->stream_counts_known = counts_known;
        service_->stream_counts = counts;
    }

   private:
    Service* service_;
};

// ────────────────────────────── options ─────────────────────────────────────

ConversationKey conversation_key(const rac_llm_options_t& options) {
    // TopP is the only sampler type the CPU path implements in v0.19.0; GREEDY
    // returns UNIMPLEMENTED. k=1 is greedy under it, as in the library's own
    // GreedySamplerParams().
    const bool greedy = options.temperature <= 0.0f;
    ConversationKey key;
    key.system_prompt = options.system_prompt != nullptr ? options.system_prompt : "";
    key.thinking_disabled = options.disable_thinking != RAC_FALSE;
    key.top_k = greedy ? 1 : (options.top_k > 0 ? options.top_k : kNoTopKLimit);
    key.top_p = greedy ? 0.0f : (options.top_p > 0.0f ? options.top_p : 1.0f);
    key.temperature = greedy ? 1.0f : options.temperature;
    key.seed = options.seed > 0 ? options.seed : 0;
    return key;
}

rac_result_t apply_sampler(LiteRtLmConversationConfig* config, const ConversationKey& key) {
    // The library seeds a fresh sampler per conversation, so a fixed default would
    // repeat the same reply. seed 0 means "backend default" in rac_llm_options_t.
    const int32_t seed = key.seed > 0 ? static_cast<int32_t>(key.seed & 0x7FFFFFFF)
                                      : static_cast<int32_t>(std::random_device{}() >> 1);

    LiteRtLmSamplerParams* raw_params = nullptr;
    if (litert_lm_sampler_params_create(kLiteRtLmSamplerTypeTopP, &raw_params) !=
        kLiteRtLmStatusOk) {
        return RAC_ERROR_GENERATION_FAILED;
    }
    const SamplerParamsPtr params(raw_params);
    (void)litert_lm_sampler_params_set_top_k(params.get(), key.top_k);
    (void)litert_lm_sampler_params_set_top_p(params.get(), key.top_p);
    (void)litert_lm_sampler_params_set_temperature(params.get(), key.temperature);
    (void)litert_lm_sampler_params_set_seed(params.get(), seed);

    LiteRtLmSessionConfig* raw_session = nullptr;
    if (litert_lm_session_config_create(&raw_session) != kLiteRtLmStatusOk) {
        return RAC_ERROR_GENERATION_FAILED;
    }
    const SessionConfigPtr session(raw_session);
    (void)litert_lm_session_config_set_sampler_params(session.get(), params.get());
    (void)litert_lm_conversation_config_set_session_config(config, session.get());
    return RAC_SUCCESS;
}

// Holds what the optional args point at until the stream has started.
struct RequestArgs {
    OptionalArgsPtr args;
    ThinkingConfigPtr thinking;
    RepetitionPenaltyPtr penalty;
};

rac_result_t build_request_args(const rac_llm_options_t& options, RequestArgs* out) {
    LiteRtLmConversationOptionalArgs* raw_args = nullptr;
    if (litert_lm_conversation_optional_args_create(&raw_args) != kLiteRtLmStatusOk) {
        return RAC_ERROR_GENERATION_FAILED;
    }
    out->args.reset(raw_args);
    if (options.max_tokens > 0) {
        (void)litert_lm_conversation_optional_args_set_max_output_tokens(out->args.get(),
                                                                         options.max_tokens);
    }
    if (options.disable_thinking != RAC_FALSE) {
        LiteRtLmThinkingConfig* raw_thinking = nullptr;
        if (litert_lm_thinking_config_create(&raw_thinking) != kLiteRtLmStatusOk) {
            return RAC_ERROR_GENERATION_FAILED;
        }
        out->thinking.reset(raw_thinking);
        (void)litert_lm_thinking_config_set_enable_thinking(out->thinking.get(), false);
        (void)litert_lm_conversation_optional_args_set_thinking_config(out->args.get(),
                                                                       out->thinking.get());
    }
    const bool has_penalty = options.repetition_penalty > 1.0f ||
                             options.presence_penalty != 0.0f || options.frequency_penalty != 0.0f;
    if (has_penalty) {
        LiteRtLmRepetitionPenaltyConfig* raw_penalty = nullptr;
        if (litert_lm_repetition_penalty_config_create(&raw_penalty) != kLiteRtLmStatusOk) {
            return RAC_ERROR_GENERATION_FAILED;
        }
        out->penalty.reset(raw_penalty);
        if (options.repetition_penalty > 1.0f) {
            (void)litert_lm_repetition_penalty_config_set_repetition_penalty(
                out->penalty.get(), options.repetition_penalty);
        }
        (void)litert_lm_repetition_penalty_config_set_presence_penalty(out->penalty.get(),
                                                                       options.presence_penalty);
        (void)litert_lm_repetition_penalty_config_set_frequency_penalty(out->penalty.get(),
                                                                        options.frequency_penalty);
        (void)litert_lm_conversation_optional_args_set_repetition_penalty_config(
            out->args.get(), out->penalty.get());
    }
    return RAC_SUCCESS;
}

// ───────────────────────────── generation ───────────────────────────────────

struct GenerationSummary {
    const char* finish_reason = "stop";
    int32_t prompt_tokens = 0;
    int32_t completion_tokens = 0;
    bool counts_known = false;
    int32_t context_limit = 0;
    int64_t time_to_first_chunk_ms = 0;
    int64_t total_time_ms = 0;
};

// The prefill and decode turns a conversation has done so far. The counts of one
// request are what it adds to them.
struct BenchmarkTurns {
    std::size_t prefill = 0;
    std::size_t decode = 0;
};

BenchmarkInfoPtr benchmark_info(LiteRtLmConversation* conversation) {
    LiteRtLmBenchmarkInfo* raw_info = nullptr;
    if (litert_lm_conversation_get_benchmark_info(conversation, &raw_info) != kLiteRtLmStatusOk) {
        return nullptr;
    }
    return BenchmarkInfoPtr(raw_info);
}

bool read_benchmark_turns(const LiteRtLmBenchmarkInfo* info, BenchmarkTurns* out) {
    return litert_lm_benchmark_info_get_num_prefill_turns(info, &out->prefill) ==
               kLiteRtLmStatusOk &&
           litert_lm_benchmark_info_get_num_decode_turns(info, &out->decode) == kLiteRtLmStatusOk;
}

// Sums the decode turns of this request. Only its first prefill turn is prompt: later
// turns replay the answer into the KV cache once reasoning is filtered out of it.
bool read_token_counts(LiteRtLmConversation* conversation, const BenchmarkTurns& before,
                       GenerationSummary* summary) {
    const BenchmarkInfoPtr info = benchmark_info(conversation);
    BenchmarkTurns after;
    if (!info || !read_benchmark_turns(info.get(), &after) || after.prefill <= before.prefill) {
        return false;
    }
    std::size_t prompt = 0;
    if (litert_lm_benchmark_info_get_prefill_token_count_at(info.get(), before.prefill, &prompt) !=
        kLiteRtLmStatusOk) {
        return false;
    }
    std::size_t completion = 0;
    for (std::size_t i = before.decode; i < after.decode; ++i) {
        std::size_t turn = 0;
        if (litert_lm_benchmark_info_get_decode_token_count_at(info.get(), i, &turn) !=
            kLiteRtLmStatusOk) {
            return false;
        }
        completion += turn;
    }
    summary->prompt_tokens = static_cast<int32_t>(prompt);
    summary->completion_tokens = static_cast<int32_t>(completion);
    (void)litert_lm_benchmark_info_get_max_num_tokens(info.get(), &summary->context_limit);
    return true;
}

// Commons trims what it sends back, so a kept turn is compared without the outer blanks.
std::string trimmed(const std::string& text) {
    const auto first = text.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) {
        return "";
    }
    return text.substr(first, text.find_last_not_of(" \t\r\n") - first + 1);
}

bool holds_history(const KeptChat& chat, const char* const* history, int32_t count) {
    if (chat.turns.size() != static_cast<std::size_t>(count)) {
        return false;
    }
    for (int32_t i = 0; i < count; ++i) {
        if (chat.turns[static_cast<std::size_t>(i)] != trimmed(history[i])) {
            return false;
        }
    }
    return true;
}

// Replaces the kept conversation with one that holds the given history.
rac_result_t start_chat(Service* service, const ConversationKey& key, const char* const* history,
                        int32_t history_count) {
    KeptChat& chat = service->chat;
    chat.reset();

    LiteRtLmConversationConfig* raw_config = nullptr;
    if (litert_lm_conversation_config_create(&raw_config) != kLiteRtLmStatusOk) {
        return RAC_ERROR_GENERATION_FAILED;
    }
    const ConversationConfigPtr config(raw_config);
    const rac_result_t sampler_rc = apply_sampler(config.get(), key);
    if (sampler_rc != RAC_SUCCESS) {
        return sampler_rc;
    }
    if (!service->chat_template.empty()) {
        (void)litert_lm_conversation_config_set_prompt_template(config.get(),
                                                                service->chat_template.c_str());
    }
    if (!key.system_prompt.empty()) {
        (void)litert_lm_conversation_config_set_system_message(
            config.get(), litertlm_engine::system_content_json(key.system_prompt.c_str()).c_str());
    }
    if (history_count > 0) {
        (void)litert_lm_conversation_config_set_messages(
            config.get(), litertlm_engine::history_messages_json(history, history_count).c_str());
    }
    LiteRtLmConversation* raw_conversation = nullptr;
    const LiteRtLmStatusCode status =
        litert_lm_conversation_create(service->engine, config.get(), &raw_conversation);
    if (status != kLiteRtLmStatusOk) {
        const char* message = last_error_message();
        report_failure("LiteRT-LM conversation", message);
        return generation_failure_code(message);
    }
    chat.conversation.reset(raw_conversation);
    chat.key = key;
    for (int32_t i = 0; i < history_count; ++i) {
        chat.turns.push_back(trimmed(history[i]));
    }
    return RAC_SUCCESS;
}

// Takes one turn on the kept conversation: drains the stream on the calling thread and
// hands each piece of text to sink. A false from sink cancels.
using TextSink = std::function<bool(const std::string&)>;

rac_result_t stream_turn(Service* service, RequestScope& request,
                         const rac_llm_options_t& effective, const std::string& turn,
                         const TextSink& sink, GenerationSummary* summary, bool* text_delivered) {
    // Whatever does not reach the end below leaves a conversation that cannot go on.
    KeptChat& chat = service->chat;
    struct DropUnlessKept {
        RequestScope& request;
        KeptChat& chat;
        bool keep = false;
        ~DropUnlessKept() {
            if (!keep) {
                (void)request.end_stream();
                chat.reset();
            }
        }
    } drop{request, chat};
    LiteRtLmConversation* const conversation = chat.conversation.get();

    BenchmarkTurns turns_before;
    if (const BenchmarkInfoPtr info = benchmark_info(conversation)) {
        (void)read_benchmark_turns(info.get(), &turns_before);
    }
    // Nothing yet for a new conversation, whose prefill below carries all of the prompt.
    std::size_t tokens_before = 0;
    (void)litert_lm_conversation_get_token_count(conversation, &tokens_before);
    chat.queues.push_back(std::make_unique<StreamQueue>());
    StreamQueue& queue = *chat.queues.back();

    RequestArgs args;
    const rac_result_t args_rc = build_request_args(effective, &args);
    if (args_rc != RAC_SUCCESS) {
        return args_rc;
    }

    std::vector<std::string> stops;
    for (size_t i = 0; effective.stop_sequences != nullptr && i < effective.num_stop_sequences;
         ++i) {
        if (effective.stop_sequences[i] != nullptr) {
            stops.emplace_back(effective.stop_sequences[i]);
        }
    }
    StreamAssembler assembler(std::move(stops));

    const auto started = std::chrono::steady_clock::now();
    const std::string message =
        litertlm_engine::to_json_string(litertlm_engine::text_message("user", turn.c_str()));
    const rac_result_t start_rc = request.start(conversation, message, args.args.get(), &queue);
    if (start_rc != RAC_SUCCESS) {
        return start_rc;
    }

    bool accepting = true;
    bool sink_refused = false;
    bool first_chunk_seen = false;
    int32_t chunk_count = 0;
    std::string answer;
    std::deque<std::string> batch;
    std::string stream_error;
    bool out_of_memory = false;
    for (bool finished = false; !finished;) {
        {
            std::unique_lock<std::mutex> lock(queue.mutex);
            queue.ready.wait(lock, [&] { return queue.finished || !queue.chunks.empty(); });
            batch.swap(queue.chunks);
            finished = queue.finished;
            if (finished) {
                stream_error = queue.error;
                out_of_memory = queue.out_of_memory;
            }
        }
        for (const std::string& chunk : batch) {
            if (!first_chunk_seen) {
                first_chunk_seen = true;
                summary->time_to_first_chunk_ms =
                    std::chrono::duration_cast<std::chrono::milliseconds>(
                        std::chrono::steady_clock::now() - started)
                        .count();
            }
            if (!accepting || request.cancel_requested()) {
                continue;
            }
            ++chunk_count;
            const ChunkText parsed = litertlm_engine::parse_chunk(chunk);
            answer += parsed.answer;
            const std::string text = assembler.feed(parsed);
            *text_delivered = *text_delivered || !text.empty();
            if (!text.empty() && !sink(text)) {
                accepting = false;
                sink_refused = true;
                request.stop_stream();
            } else if (assembler.stop_matched()) {
                accepting = false;
                request.stop_stream();
            }
        }
        batch.clear();
    }
    summary->total_time_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                                 std::chrono::steady_clock::now() - started)
                                 .count();

    const bool cancelled = request.end_stream();
    const bool stopped_early = cancelled || sink_refused || assembler.stop_matched();
    // After a cancel the conversation may only be deleted, so counts come from it
    // only when the stream ended on its own.
    summary->counts_known = !stopped_early && stream_error.empty() &&
                            read_token_counts(conversation, turns_before, summary);
    if (!summary->counts_known) {
        summary->completion_tokens = chunk_count;
    }
    // The prompt is all the model has in front of it, not only what this request prefilled.
    summary->prompt_tokens += static_cast<int32_t>(tokens_before);
    rac_llm_token_counts_t counts{};
    counts.prompt_tokens = summary->prompt_tokens;
    counts.completion_tokens = summary->completion_tokens;
    request.publish_counts(summary->counts_known, counts);

    if (cancelled || sink_refused) {
        return RAC_ERROR_CANCELLED;
    }
    if (out_of_memory) {
        report_failure("LiteRT-LM stream", "out of memory while queueing a chunk");
        return RAC_ERROR_INSUFFICIENT_MEMORY;
    }
    if (!assembler.stop_matched() && !stream_error.empty()) {
        report_failure("LiteRT-LM generation", stream_error.c_str());
        return generation_failure_code(stream_error.c_str());
    }
    if (!assembler.stop_matched()) {
        const std::string tail = assembler.finish();
        if (!tail.empty() && !sink(tail)) {
            return RAC_ERROR_CANCELLED;
        }
        // A full context ends the reply without an error from the library, as max_tokens would.
        const bool context_filled =
            summary->context_limit > 0 &&
            summary->prompt_tokens + summary->completion_tokens >= summary->context_limit;
        if (context_filled ||
            (effective.max_tokens > 0 && summary->completion_tokens >= effective.max_tokens)) {
            summary->finish_reason = "length";
        }
        chat.turns.push_back(trimmed(turn));
        chat.turns.push_back(trimmed(answer));
        // Only the last queue can still be in use, by the callback that just returned.
        chat.queues.erase(chat.queues.begin(), chat.queues.end() - 1);
        drop.keep = true;
    }
    return RAC_SUCCESS;
}

rac_result_t run_generation(Service* service, const char* prompt, const rac_llm_options_t* options,
                            const TextSink& sink, GenerationSummary* summary) {
    std::lock_guard<std::mutex> operation_lock(service->operation_mutex);
    if (service->engine == nullptr) {
        return RAC_ERROR_NOT_INITIALIZED;
    }
    RequestScope request(service);

    const rac_llm_options_t effective = options != nullptr ? *options : RAC_LLM_OPTIONS_DEFAULT;
    if (effective.grammar != nullptr && effective.grammar[0] != '\0') {
        // Never degrade constrained output to free generation silently.
        report_failure("LiteRT-LM", "grammar-constrained generation is not supported");
        return RAC_ERROR_NOT_SUPPORTED;
    }

    // Commons can leave a user turn last, directly before the prompt. Chat templates
    // expect alternating roles, so it joins the prompt as commons joins same-role turns.
    std::string turn = prompt;
    int32_t history_count =
        effective.history != nullptr && effective.n_history > 0 ? effective.n_history : 0;
    if (history_count % 2 != 0) {
        --history_count;
        turn = std::string(effective.history[history_count]) + "\n\n" + turn;
    }

    // A fixed seed asks for a reply that repeats, which only a new conversation gives.
    KeptChat& chat = service->chat;
    const ConversationKey key = conversation_key(effective);
    bool text_delivered = false;
    if (service->keep_chats && chat.conversation && key.seed == 0 && chat.key == key &&
        holds_history(chat, effective.history, history_count)) {
        const rac_result_t rc =
            stream_turn(service, request, effective, turn, sink, summary, &text_delivered);
        if (rc == RAC_SUCCESS || rc == RAC_ERROR_CANCELLED || text_delivered) {
            return rc;
        }
        // The kept KV cache can be fuller than the history needs, and a new conversation frees
        // memory. Any other failure is taken for a template that renders earlier turns differently
        // once another follows, as the standard Qwen 3 template does: the library refuses every
        // kept turn of such a model.
        RAC_LOG_WARNING(LOG_CAT, "kept conversation failed (%d), rendering the history again", rc);
        service->keep_chats = rc != RAC_ERROR_GENERATION_FAILED;
        *summary = GenerationSummary{};
    }
    const rac_result_t start_rc = start_chat(service, key, effective.history, history_count);
    if (start_rc != RAC_SUCCESS) {
        return start_rc;
    }
    return stream_turn(service, request, effective, turn, sink, summary, &text_delivered);
}

// ───────────────────────────── vtable ops ───────────────────────────────────

rac_result_t litertlm_llm_create(const char* model_id, const char* config_json, void** out_impl) {
    if (out_impl == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;
    try {
        auto service = std::make_unique<Service>();
        if (model_id != nullptr) {
            service->model_path = model_id;
        }
        parse_load_options(config_json, service.get());
        *out_impl = service.release();
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t litertlm_llm_initialize(void* impl, const char* model_path) {
    auto* service = as_service(impl);
    if (service == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    try {
        std::lock_guard<std::mutex> operation_lock(service->operation_mutex);
        if (service->engine != nullptr) {
            return RAC_SUCCESS;
        }
        if (model_path != nullptr && model_path[0] != '\0') {
            service->model_path = model_path;
        }
        return load_model(service);
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t litertlm_llm_generate(void* impl, const char* prompt, const rac_llm_options_t* options,
                                   rac_llm_result_t* out_result) {
    auto* service = as_service(impl);
    if (service == nullptr || prompt == nullptr || out_result == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    try {
        std::string text;
        GenerationSummary summary;
        const rac_result_t rc = run_generation(
            service, prompt, options,
            [&text](const std::string& piece) {
                text += piece;
                return true;
            },
            &summary);
        if (rc != RAC_SUCCESS) {
            return rc;
        }
        out_result->text = rac_strdup(text.c_str());
        out_result->prompt_tokens = summary.prompt_tokens;
        out_result->completion_tokens = summary.completion_tokens;
        out_result->total_tokens = summary.prompt_tokens + summary.completion_tokens;
        out_result->time_to_first_token_ms = summary.time_to_first_chunk_ms;
        out_result->prompt_eval_time_ms = summary.time_to_first_chunk_ms;
        out_result->total_time_ms = summary.total_time_ms;
        const int64_t decode_ms = summary.total_time_ms - summary.time_to_first_chunk_ms;
        out_result->tokens_per_second = decode_ms > 0
                                            ? static_cast<float>(summary.completion_tokens) *
                                                  1000.0f / static_cast<float>(decode_ms)
                                            : 0.0f;
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t litertlm_llm_generate_stream(void* impl, const char* prompt,
                                          const rac_llm_options_t* options,
                                          rac_llm_stream_callback_fn callback, void* user_data) {
    auto* service = as_service(impl);
    if (service == nullptr || prompt == nullptr || callback == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    try {
        GenerationSummary summary;
        const rac_result_t rc = run_generation(
            service, prompt, options,
            [callback, user_data](const std::string& piece) {
                return callback(piece.c_str(), RAC_FALSE, nullptr, /*tokens_in_delta=*/1,
                                user_data) != RAC_FALSE;
            },
            &summary);
        if (rc != RAC_SUCCESS) {
            return rc;
        }
        rac_llm_stream_report_final_signal();
        (void)callback("", RAC_TRUE, summary.finish_reason, /*tokens_in_delta=*/0, user_data);
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t litertlm_llm_get_info(void* impl, rac_llm_info_t* out_info) {
    if (out_info == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = as_service(impl);
    if (service == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    std::lock_guard<std::mutex> operation_lock(service->operation_mutex);
    out_info->is_ready = service->engine != nullptr ? RAC_TRUE : RAC_FALSE;
    out_info->current_model = service->model_path.c_str();
    out_info->context_length = service->context_length;
    out_info->supports_streaming = RAC_TRUE;
    return RAC_SUCCESS;
}

rac_result_t litertlm_llm_cancel(void* impl) {
    auto* service = as_service(impl);
    if (service == nullptr) {
        return RAC_SUCCESS;
    }
    std::lock_guard<std::mutex> lock(service->active_mutex);
    if (service->request_active) {
        service->cancel_requested = true;
        if (service->conversation != nullptr) {
            (void)litert_lm_conversation_cancel_process(service->conversation);
        }
    }
    return RAC_SUCCESS;
}

rac_result_t litertlm_llm_cleanup(void* impl) {
    auto* service = as_service(impl);
    if (service == nullptr) {
        return RAC_SUCCESS;
    }
    (void)litertlm_llm_cancel(impl);
    std::lock_guard<std::mutex> operation_lock(service->operation_mutex);
    service->chat.reset();
    service->keep_chats = true;
    if (service->engine != nullptr) {
        litert_lm_engine_delete(service->engine);
        service->engine = nullptr;
    }
    return RAC_SUCCESS;
}

void litertlm_llm_destroy(void* impl) {
    (void)litertlm_llm_cleanup(impl);
    delete as_service(impl);
}

rac_result_t litertlm_llm_get_stream_token_counts(void* impl, rac_llm_token_counts_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = as_service(impl);
    if (service == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    std::lock_guard<std::mutex> lock(service->active_mutex);
    if (!service->stream_counts_known) {
        return RAC_ERROR_NOT_SUPPORTED;  // commons falls back to its own count
    }
    *out = service->stream_counts;
    return RAC_SUCCESS;
}

}  // namespace

// Positional, as in the other engines: MSVC rejects mixing designated initializers.
extern "C" const rac_llm_service_ops_t g_litertlm_llm_ops = {
    /* .initialize              = */ litertlm_llm_initialize,
    /* .generate                = */ litertlm_llm_generate,
    /* .generate_stream         = */ litertlm_llm_generate_stream,
    /* .get_info                = */ litertlm_llm_get_info,
    /* .cancel                  = */ litertlm_llm_cancel,
    /* .cleanup                 = */ litertlm_llm_cleanup,
    /* .destroy                 = */ litertlm_llm_destroy,
    /* .load_lora               = */ nullptr,
    /* .remove_lora             = */ nullptr,
    /* .clear_lora              = */ nullptr,
    /* .get_lora_info           = */ nullptr,
    /* .inject_system_prompt    = */ nullptr,
    /* .append_context          = */ nullptr,
    /* .generate_from_context   = */ nullptr,
    /* .clear_context           = */ nullptr,
    /* .create                  = */ litertlm_llm_create,
    /* .get_stream_token_counts = */ litertlm_llm_get_stream_token_counts,
    /* .generate_chat_stream    = */ nullptr,
};
