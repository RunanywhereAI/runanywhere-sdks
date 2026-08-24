/**
 * @file tool_provider_dispatch.cpp
 * @brief Provider-registry dispatch for the tool-calling run loop.
 */
#include "features/llm/tool_provider_dispatch.h"

#include <chrono>
#include <cstdlib>
#include <utility>

#include "plugin/tool_progress_scope.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_tool_provider.h"

#if defined(RAC_HAVE_PROTOBUF)

namespace rac::llm::tool_calling {

namespace {

constexpr const char* kTag = "ToolDispatch";

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

}  // namespace

bool provider_owns(const std::string& name) {
    return !name.empty() && rac_tool_provider_find(name.c_str()) != nullptr;
}

bool provider_is_single_use(const std::string& name) {
    if (name.empty()) {
        return false;
    }
    const rac_tool_provider_t* provider = rac_tool_provider_find(name.c_str());
    return provider != nullptr && provider->single_use != 0;
}

bool provider_grounds_answer(const std::string& name) {
    if (name.empty()) {
        return false;
    }
    const rac_tool_provider_t* provider = rac_tool_provider_find(name.c_str());
    return provider != nullptr && provider->grounds_answer != 0;
}

bool execute_via_provider(const runanywhere::v1::ToolCall& call, uint64_t run_loop_handle,
                          std::function<bool()> is_cancelled,
                          const std::vector<std::string>& history, const std::string& user_prompt,
                          runanywhere::v1::ToolResult* out_result) {
    if (out_result == nullptr) {
        return false;
    }
    const rac_tool_provider_t* provider = rac_tool_provider_find(call.name().c_str());
    if (provider == nullptr) {
        return false;
    }

    out_result->set_tool_call_id(call.id());
    out_result->set_name(call.name());
    out_result->set_started_at_ms(now_ms());

    // A tool declaring no parameters is still called with an object, so the
    // provider never has to distinguish "no arguments" from "malformed".
    const std::string arguments = call.arguments_json().empty() ? "{}" : call.arguments_json();

    rac::plugin::ToolProgressScope scope(call.name(), run_loop_handle, std::move(is_cancelled),
                                         history);

    char* raw = nullptr;
    const rac_result_t rc =
        provider->execute(arguments.c_str(), scope.context(), &raw, provider->user_data);

    out_result->set_completed_at_ms(now_ms());

    if (rc != RAC_SUCCESS) {
        RAC_LOG_WARNING(kTag, "provider '%s' failed with %d", call.name().c_str(),
                        static_cast<int>(rc));
        out_result->set_error("tool failed to run");
        out_result->set_is_error(true);
        std::free(raw);
        return true;
    }
    if (raw == nullptr) {
        out_result->set_error("tool returned no result");
        out_result->set_is_error(true);
        return true;
    }

    out_result->set_result_json(raw);
    std::free(raw);
    return true;
}

}  // namespace rac::llm::tool_calling

#endif  // RAC_HAVE_PROTOBUF
