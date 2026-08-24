/**
 * @file tool_provider_dispatch.h
 * @brief Runs a parsed tool call against the commons tool-provider registry.
 *
 * The run loop has always handed every call to the host's `on_execute`
 * callback, which is why `search_web` is implemented separately in Swift,
 * Kotlin and Web. A provider registered through `rac_tool_provider.h` is
 * resolved here first, so a tool that lives in commons is answered by commons
 * and the host callback is only reached for tools the app itself registered.
 */
#ifndef RAC_FEATURES_LLM_TOOL_PROVIDER_DISPATCH_H
#define RAC_FEATURES_LLM_TOOL_PROVIDER_DISPATCH_H

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

#if defined(RAC_HAVE_PROTOBUF)
#include "tool_calling.pb.h"
#endif

namespace rac::llm::tool_calling {

#if defined(RAC_HAVE_PROTOBUF)

/**
 * @brief Answer `call` from the provider registry when one owns that name.
 *
 * `run_loop_handle` and `is_cancelled` build the `rac_tool_context_t` the
 * provider reports progress through; pass 0 and an empty function for a call
 * made outside a run loop.
 *
 * @return false when no provider is registered for the call's name, leaving
 *         the caller to fall through to the host executor. A provider that
 *         runs and fails still returns true, with `out_result`'s `error` set,
 *         because the model should see the failure rather than the loop
 *         retrying the call against a host that does not implement it.
 */
bool execute_via_provider(const runanywhere::v1::ToolCall& call, uint64_t run_loop_handle,
                          std::function<bool()> is_cancelled,
                          const std::vector<std::string>& history,
                          runanywhere::v1::ToolResult* out_result);

/** @brief Whether a commons provider owns `name`. */
bool provider_owns(const std::string& name);

/** @brief Whether the tool named `name` is withdrawn after one call. */
bool provider_is_single_use(const std::string& name);

/**
 * @brief Whether the follow-up turn should be grounded in this tool's result.
 *
 * What `tool_calling.cpp` currently derives from the literal name
 * `"search_web"`. Falls back to false, so a name the registry does not know
 * behaves exactly as before.
 */
bool provider_grounds_answer(const std::string& name);

#endif  // RAC_HAVE_PROTOBUF

}  // namespace rac::llm::tool_calling

#endif  // RAC_FEATURES_LLM_TOOL_PROVIDER_DISPATCH_H
