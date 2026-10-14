/** @file decision_module.cpp @brief Lifecycle and proto ABI for decision models. */

#include "decision_internal.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "features/common/rac_component_lifecycle_internal.h"
#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_logger.h"
#include "rac/features/decision/rac_decision_component.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "decision.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#endif

namespace {

constexpr const char* kLogCategory = "Decision.Component";
// Guards against pathological requests; the proto boundary should never hand us
// more questions or options than this in a single decide call. The option cap
// matches the cloud contract (labels A to Z).
constexpr size_t kMaxQuestions = 128;
constexpr size_t kMaxOptionsPerQuestion = 26;

struct rac_decision_component {
    rac_handle_t lifecycle = nullptr;
    std::mutex mutex;
};

std::mutex& lifetime_mutex() {
    static std::mutex value;
    return value;
}

std::condition_variable& lifetime_cv() {
    static std::condition_variable value;
    return value;
}

std::unordered_map<rac_handle_t, std::shared_ptr<rac::decision::ComponentLifetimeEntry>>&
lifetime_registry() {
    static std::unordered_map<rac_handle_t, std::shared_ptr<rac::decision::ComponentLifetimeEntry>>
        value;
    return value;
}

rac::decision::ComponentOperationAdmittedTestHook& admitted_hook() {
    static rac::decision::ComponentOperationAdmittedTestHook value = nullptr;
    return value;
}

void*& admitted_hook_user_data() {
    static void* value = nullptr;
    return value;
}

thread_local rac::decision::ComponentOperationFrame* g_operation_frame = nullptr;

bool current_thread_has_operation(rac_handle_t handle) {
    for (auto* frame = g_operation_frame; frame; frame = frame->previous) {
        if (frame->handle == handle) {
            return true;
        }
    }
    return false;
}

bool register_lifetime(rac_handle_t component, rac_handle_t lifecycle) {
    try {
        auto entry = std::make_shared<rac::decision::ComponentLifetimeEntry>();
        entry->component = component;
        entry->lifecycle = lifecycle;
        std::lock_guard<std::mutex> lock(lifetime_mutex());
        return lifetime_registry().emplace(component, std::move(entry)).second;
    } catch (...) {
        return false;
    }
}

std::shared_ptr<rac::decision::ComponentLifetimeEntry> close_admission(rac_handle_t handle) {
    std::lock_guard<std::mutex> lock(lifetime_mutex());
    const auto it = lifetime_registry().find(handle);
    if (it == lifetime_registry().end() || !it->second->accepting_operations) {
        return nullptr;
    }
    it->second->accepting_operations = false;
    return it->second;
}

void wait_for_operations(const std::shared_ptr<rac::decision::ComponentLifetimeEntry>& entry) {
    std::unique_lock<std::mutex> lock(lifetime_mutex());
    lifetime_cv().wait(lock, [&] { return entry->active_operations == 0; });
}

rac_handle_t remove_lifetime(rac_handle_t handle,
                             const std::shared_ptr<rac::decision::ComponentLifetimeEntry>& entry) {
    std::lock_guard<std::mutex> lock(lifetime_mutex());
    const auto it = lifetime_registry().find(handle);
    if (it == lifetime_registry().end() || it->second != entry || entry->active_operations != 0) {
        return nullptr;
    }
    const rac_handle_t component = entry->component;
    lifetime_registry().erase(it);
    return component;
}

// The lifecycle passes the resolved model PATH as the first argument (see
// rac_lifecycle_load → mgr->create_fn(model_path, ...)); the backend uses it both
// as its create id and as the file to load. The logical model id is tracked
// separately by the lifecycle and reported via rac_lifecycle_get_model_id.
rac_result_t create_component_service(const char* model_path, void*, rac_handle_t* out_service) {
    rac_result_t rc = rac_decision_create(model_path, out_service);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    rc = rac_decision_initialize(*out_service, model_path);
    if (rc != RAC_SUCCESS) {
        rac_decision_destroy(*out_service);
        *out_service = nullptr;
    }
    return rc;
}

void destroy_component_service(rac_handle_t service, void*) {
    if (service) {
        (void)rac_decision_cleanup(service);
        rac_decision_destroy(service);
    }
}

rac_result_t protobuf_unavailable(rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
}

#if defined(RAC_HAVE_PROTOBUF)

using runanywhere::v1::DecisionQuestionType;

rac_decision_question_type_t question_type_from_proto(DecisionQuestionType type) {
    switch (type) {
        case runanywhere::v1::DECISION_QUESTION_TYPE_CHOICE:
            return RAC_DECISION_QUESTION_CHOICE;
        case runanywhere::v1::DECISION_QUESTION_TYPE_NOUL:
            return RAC_DECISION_QUESTION_NOUL;
        case runanywhere::v1::DECISION_QUESTION_TYPE_SCORE:
            return RAC_DECISION_QUESTION_SCORE;
        default:
            return RAC_DECISION_QUESTION_UNSPECIFIED;
    }
}

DecisionQuestionType question_type_to_proto(rac_decision_question_type_t type) {
    switch (type) {
        case RAC_DECISION_QUESTION_CHOICE:
            return runanywhere::v1::DECISION_QUESTION_TYPE_CHOICE;
        case RAC_DECISION_QUESTION_NOUL:
            return runanywhere::v1::DECISION_QUESTION_TYPE_NOUL;
        case RAC_DECISION_QUESTION_SCORE:
            return runanywhere::v1::DECISION_QUESTION_TYPE_SCORE;
        default:
            return runanywhere::v1::DECISION_QUESTION_TYPE_UNSPECIFIED;
    }
}

// Releases the per-question option arrays a successful (or partial)
// validate_request allocated. Declared before validate_request so its failure
// paths can clean up after themselves.
void free_question_views(std::vector<rac_decision_question_t>* questions);

bool is_blank(const std::string& text);

// Trims ASCII whitespace and lowercases, for the "distinct ignoring case and
// surrounding space" option-key rule the cloud contract states.
std::string normalize_option_key(const std::string& key);

// Option keys must be non-blank, unique within their question, and free of the
// control/line-break characters the contract forbids.
bool key_is_valid(const std::string& key);

// Flatten the parsed request into C structs. The option views borrow from the
// still-alive parsed request's strings; the question views borrow from
// `out_questions`, which the caller owns for the duration of the decide call.
rac_result_t validate_request(const runanywhere::v1::DecisionRequest& request,
                              std::vector<rac_decision_question_t>* out_questions,
                              rac_decision_options_t* out_options) {
    if (!out_questions || !out_options) {
        return RAC_ERROR_NULL_POINTER;
    }
    out_questions->clear();
    *out_options = RAC_DECISION_OPTIONS_DEFAULT;
    if (static_cast<size_t>(request.questions_size()) == 0 ||
        static_cast<size_t>(request.questions_size()) > kMaxQuestions) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (request.state().empty() || is_blank(request.state())) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    // Option storage is freed by free_question_views; on any failure past a
    // calloc, release what was already built so the caller's cleanup is a no-op.
    auto fail = [&](rac_result_t rc) {
        free_question_views(out_questions);
        out_questions->clear();
        return rc;
    };

    try {
        out_questions->reserve(static_cast<size_t>(request.questions_size()));
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    for (int i = 0; i < request.questions_size(); ++i) {
        const auto& question = request.questions(i);
        if (static_cast<size_t>(question.options_size()) > kMaxOptionsPerQuestion) {
            return fail(RAC_ERROR_INVALID_PARAMETER);
        }
        const rac_decision_question_type_t type = question_type_from_proto(question.type());
        if (type == RAC_DECISION_QUESTION_UNSPECIFIED) {
            return fail(RAC_ERROR_INVALID_PARAMETER);
        }

        // Late-bound key storage: NOUL options are re-keyed to the reserved
        // true/false pair, so the buffers must outlive the input strings. Kept
        // in a side vector for the duration of the call (freed by the views'
        // owners), and referenced by `options[j].key` below.
        size_t option_count = static_cast<size_t>(question.options_size());

        rac_decision_question_t view = {};
        view.id = question.id().c_str();
        view.type = type;
        view.instructions = question.instructions().empty() ? nullptr : question.instructions().c_str();
        view.option_count = option_count;
        view.options = nullptr;

        if (type == RAC_DECISION_QUESTION_NOUL) {
            // The wire reserves "true"/"false" for yes/no; callers may phrase
            // the options any way (yes/no, no/yes, true/false). Normalize to
            // the reserved pair here so every engine reads the same shape and
            // the answer's p(true) is unambiguous.
            if (option_count != 2) {
                return fail(RAC_ERROR_INVALID_PARAMETER);
            }
            auto* options = static_cast<rac_decision_option_t*>(
                std::calloc(2, sizeof(rac_decision_option_t)));
            if (!options) {
                return fail(RAC_ERROR_OUT_OF_MEMORY);
            }
            // "true" is the affirmative option: the one whose key is literally
            // true/yes, else the first option (the fallback the docs describe).
            size_t true_index = 0;
            for (size_t j = 0; j < option_count; ++j) {
                const std::string key = normalize_option_key(question.options(j).key());
                if (key == "true" || key == "yes") {
                    true_index = j;
                    break;
                }
            }
            static const char* kKeys[2] = {"true", "false"};
            for (size_t slot = 0; slot < 2; ++slot) {
                const size_t source = slot == 0 ? true_index : (1 - true_index);
                options[slot].key = kKeys[slot];
                options[slot].description = question.options(source).description().empty()
                                                ? nullptr
                                                : question.options(source).description().c_str();
            }
            view.options = options;
        } else if (option_count > 0) {
            auto* options = static_cast<rac_decision_option_t*>(
                std::calloc(option_count, sizeof(rac_decision_option_t)));
            if (!options) {
                return fail(RAC_ERROR_OUT_OF_MEMORY);
            }
            // Duplicate or invalid keys are rejected: the proto probability map
            // is keyed by them, so duplicates would silently drop an option.
            std::unordered_map<std::string, bool> seen;
            for (size_t j = 0; j < option_count; ++j) {
                const std::string& key = question.options(j).key();
                if (!key_is_valid(key)) {
                    std::free(options);
                    return fail(RAC_ERROR_INVALID_PARAMETER);
                }
                if (!seen.emplace(normalize_option_key(key), true).second) {
                    std::free(options);
                    return fail(RAC_ERROR_INVALID_PARAMETER);
                }
                options[j].key = key.c_str();
                options[j].description = question.options(j).description().empty()
                                             ? nullptr
                                             : question.options(j).description().c_str();
            }
            view.options = options;
        }

        // CHOICE/SCORE need at least two options for a meaningful distribution
        // (confidence is pinned to 1.0 below two, and the map min is 2).
        if ((type == RAC_DECISION_QUESTION_CHOICE || type == RAC_DECISION_QUESTION_SCORE) &&
            option_count < 2) {
            std::free(const_cast<rac_decision_option_t*>(view.options));
            return fail(RAC_ERROR_INVALID_PARAMETER);
        }

        out_questions->push_back(view);
    }
    if (request.has_options()) {
        out_options->temperature = request.options().temperature();
        out_options->prompt_format_version = request.options().prompt_format_version();
    }
    return RAC_SUCCESS;
}

void free_question_views(std::vector<rac_decision_question_t>* questions) {
    if (!questions) {
        return;
    }
    for (auto& question : *questions) {
        std::free(const_cast<rac_decision_option_t*>(question.options));
    }
}

bool is_blank(const std::string& text) {
    return std::all_of(text.begin(), text.end(), [](unsigned char c) { return std::isspace(c); });
}

std::string normalize_option_key(const std::string& key) {
    size_t begin = 0;
    size_t end = key.size();
    while (begin < end && std::isspace(static_cast<unsigned char>(key[begin]))) {
        ++begin;
    }
    while (end > begin && std::isspace(static_cast<unsigned char>(key[end - 1]))) {
        --end;
    }
    std::string normalized = key.substr(begin, end - begin);
    std::transform(normalized.begin(), normalized.end(), normalized.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return normalized;
}

bool key_is_valid(const std::string& key) {
    if (is_blank(key)) {
        return false;
    }
    for (const unsigned char c : key) {
        if (c <= 0x1F || c == 0x7F) {
            return false;
        }
    }
    // U+2028 / U+2029 in UTF-8.
    return key.find("\xe2\x80\xa8") == std::string::npos &&
           key.find("\xe2\x80\xa9") == std::string::npos;
}

rac_result_t result_to_proto(const rac_decision_result_t& source,
                             const std::vector<rac_decision_question_t>& question_views,
                             const char* fallback_model_id,
                             runanywhere::v1::DecisionResult* out) {
    if (!out) {
        return RAC_ERROR_NULL_POINTER;
    }
    out->Clear();
    if (source.processing_time_ms < 0 || (source.answer_count > 0 && !source.answers)) {
        return RAC_ERROR_ENCODING_ERROR;
    }
    if (source.answer_count != question_views.size()) {
        return RAC_ERROR_ENCODING_ERROR;
    }
    for (size_t i = 0; i < source.answer_count; ++i) {
        const auto& answer = source.answers[i];
        auto* destination = out->add_answers();
        destination->set_id(answer.id ? answer.id : "");
        destination->set_type(question_type_to_proto(answer.type));
        switch (answer.type) {
            case RAC_DECISION_QUESTION_CHOICE:
                destination->set_choice(answer.choice ? answer.choice : "");
                break;
            case RAC_DECISION_QUESTION_NOUL:
                destination->set_noul(answer.noul);
                break;
            case RAC_DECISION_QUESTION_SCORE:
                destination->set_score(answer.score);
                break;
            default:
                break;
        }
        // The answer's probabilities are parallel to the request question's
        // options, so the proto map is keyed by the question's option keys
        // (the request is still alive here — question_views live in the caller).
        const auto& question = question_views[i];
        for (size_t j = 0; j < answer.probability_count; ++j) {
            const char* key = (j < question.option_count && question.options[j].key)
                                  ? question.options[j].key
                                  : nullptr;
            char index_key[16];
            if (key == nullptr) {
                std::snprintf(index_key, sizeof(index_key), "%zu", j);
                key = index_key;
            }
            (*destination->mutable_probabilities())[key] = answer.probabilities[j];
            if (answer.type == RAC_DECISION_QUESTION_SCORE) {
                (*destination->mutable_legend())[key] =
                    (j < question.option_count && question.options[j].description)
                        ? question.options[j].description
                        : "";
            }
        }
        destination->set_confidence(answer.confidence);
    }
    out->set_processing_time_ms(source.processing_time_ms);
    // Prefer the commons-known logical model id (the lifecycle-resolved id passed
    // as fallback_model_id) over the backend-reported value: some backends set
    // rac_decision_result_t.model_id to the resolved on-device path, and the
    // proto model_id field must carry the logical id, never a filesystem path.
    out->set_model_id((fallback_model_id != nullptr && fallback_model_id[0] != '\0')
                          ? fallback_model_id
                          : (source.model_id ? source.model_id : ""));
    out->mutable_usage()->set_input_tokens(source.input_tokens);
    out->mutable_usage()->set_output_tokens(0);
    out->mutable_usage()->set_total_tokens(source.input_tokens);
    out->set_prompt_format_version(source.prompt_format_version);
    return RAC_SUCCESS;
}

rac_result_t decide_with_service(rac_handle_t service, const char* model_id,
                                 const uint8_t* request_bytes, size_t request_size,
                                 rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (!rac::proto::bytes_valid(request_bytes, request_size)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "DecisionRequest bytes are invalid");
    }
    runanywhere::v1::DecisionRequest request;
    if (!request.ParseFromArray(rac::proto::parse_bytes(request_bytes, request_size),
                                static_cast<int>(request_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse DecisionRequest");
    }

    std::vector<rac_decision_question_t> questions;
    rac_decision_options_t options = RAC_DECISION_OPTIONS_DEFAULT;
    rac_result_t rc = validate_request(request, &questions, &options);
    if (rc != RAC_SUCCESS) {
        free_question_views(&questions);
        return rac_proto_buffer_set_error(out_result, rc, "invalid decision request");
    }

    rac_decision_result_t raw = {};
    rc = rac_decision_decide(service, request.state().c_str(),
                             questions.empty() ? nullptr : questions.data(), questions.size(),
                             &options, &raw);
    if (rc != RAC_SUCCESS) {
        free_question_views(&questions);
        rac_decision_result_free(&raw);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    // The question views own the option arrays that result_to_proto reads the
    // probability keys from, so they stay alive until serialization completes.
    runanywhere::v1::DecisionResult result;
    rc = result_to_proto(raw, questions, model_id, &result);
    free_question_views(&questions);
    if (rc == RAC_SUCCESS) {
        rc = rac::proto::copy_message(result, out_result, "failed to serialize DecisionResult");
    } else {
        (void)rac_proto_buffer_set_error(out_result, rc,
                                         "backend returned an invalid decision result");
    }
    rac_decision_result_free(&raw);
    return rc;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

namespace rac::decision {

ComponentOperationLease::ComponentOperationLease(rac_handle_t handle) : handle_(handle) {
    if (!handle) {
        return;
    }
    ComponentOperationAdmittedTestHook hook = nullptr;
    void* hook_user_data = nullptr;
    {
        std::lock_guard<std::mutex> lock(lifetime_mutex());
        const auto it = lifetime_registry().find(handle);
        if (it == lifetime_registry().end() ||
            (!it->second->accepting_operations && !current_thread_has_operation(handle))) {
            return;
        }
        entry_ = it->second;
        ++entry_->active_operations;
        frame_.handle = handle_;
        frame_.previous = g_operation_frame;
        g_operation_frame = &frame_;
        hook = admitted_hook();
        hook_user_data = admitted_hook_user_data();
    }
    if (hook) {
        hook(handle, hook_user_data);
    }
}

ComponentOperationLease::~ComponentOperationLease() {
    if (!entry_) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(lifetime_mutex());
        if (entry_->active_operations > 0) {
            --entry_->active_operations;
        }
        g_operation_frame = frame_.previous;
    }
    lifetime_cv().notify_all();
}

void set_component_operation_admitted_test_hook(ComponentOperationAdmittedTestHook hook,
                                                void* user_data) {
    std::lock_guard<std::mutex> lock(lifetime_mutex());
    admitted_hook() = hook;
    admitted_hook_user_data() = user_data;
}

}  // namespace rac::decision

extern "C" {

rac_result_t rac_decision_component_create(rac_handle_t* out_handle) {
    const rac_result_t rc = rac::features::create_lifecycle_component<rac_decision_component>(
        out_handle, RAC_RESOURCE_TYPE_DECISION_MODEL, "Decision.Lifecycle", create_component_service,
        destroy_component_service, kLogCategory, "Decision component created");
    if (rc == RAC_SUCCESS) {
        auto* component = static_cast<rac_decision_component*>(*out_handle);
        if (!register_lifetime(*out_handle, component->lifecycle)) {
            rac_lifecycle_destroy(component->lifecycle);
            delete component;
            *out_handle = nullptr;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }
    return rc;
}

rac_bool_t rac_decision_component_is_loaded(rac_handle_t handle) {
    rac::decision::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_FALSE;
    }
    auto* component = static_cast<rac_decision_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_is_loaded(component->lifecycle);
}

const char* rac_decision_component_get_model_id(rac_handle_t handle) {
    rac::decision::ComponentOperationLease lease(handle);
    if (!lease) {
        return nullptr;
    }
    auto* component = static_cast<rac_decision_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_model_id(component->lifecycle);
}

rac_result_t rac_decision_component_load_model(rac_handle_t handle, const char* model_path,
                                               const char* model_id, const char* model_name) {
    rac::decision::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (!model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* component = static_cast<rac_decision_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    rac_handle_t service = nullptr;
    return rac_lifecycle_load(component->lifecycle, model_path, model_id, model_name, &service);
}

rac_result_t rac_decision_component_unload(rac_handle_t handle) {
    rac::decision::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    auto* component = static_cast<rac_decision_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_unload(component->lifecycle);
}

rac_lifecycle_state_t rac_decision_component_get_state(rac_handle_t handle) {
    rac::decision::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_LIFECYCLE_STATE_IDLE;
    }
    auto* component = static_cast<rac_decision_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_state(component->lifecycle);
}

rac_result_t rac_decision_component_get_metrics(rac_handle_t handle,
                                                rac_lifecycle_metrics_t* out_metrics) {
    rac::decision::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    auto* component = static_cast<rac_decision_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_metrics(component->lifecycle, out_metrics);
}

void rac_decision_component_destroy(rac_handle_t handle) {
    if (!handle || current_thread_has_operation(handle)) {
        if (handle) {
            RAC_LOG_WARNING(kLogCategory,
                            "Decision component destroy refused from re-entrant operation");
        }
        return;
    }
    const auto entry = close_admission(handle);
    if (!entry) {
        return;
    }
    wait_for_operations(entry);
    auto* component = static_cast<rac_decision_component*>(remove_lifetime(handle, entry));
    if (!component) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(component->mutex);
        rac_lifecycle_destroy(component->lifecycle);
        component->lifecycle = nullptr;
    }
    delete component;
}

rac_result_t rac_decision_component_decide_proto(rac_handle_t handle,
                                                 const uint8_t* request_proto_bytes,
                                                 size_t request_proto_size,
                                                 rac_proto_buffer_t* out_result) {
    rac::decision::ComponentOperationLease lease(handle);
    if (!lease) {
        return out_result ? rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_HANDLE,
                                                       "invalid decision component handle")
                          : RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return protobuf_unavailable(out_result);
#else
    auto* component = static_cast<rac_decision_component*>(lease.component());
    rac_handle_t service = nullptr;
    rac_result_t rc = rac_lifecycle_acquire_service(component->lifecycle, &service);
    if (rc != RAC_SUCCESS) {
        return out_result
                   ? rac_proto_buffer_set_error(out_result, rc, "Decision model is not loaded")
                   : RAC_ERROR_NULL_POINTER;
    }
    const char* model_id = rac_lifecycle_get_model_id(component->lifecycle);
    rc = decide_with_service(service, model_id, request_proto_bytes, request_proto_size, out_result);
    rac_lifecycle_release_service(component->lifecycle);
    return rc;
#endif
}

}  // extern "C"