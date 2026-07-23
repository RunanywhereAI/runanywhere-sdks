/**
 * @file llm_thinking_directive_internal.h
 * @brief Commons-internal helper: apply a model "no-think" directive.
 *
 * Centralizes the prompt-level thinking suppression that the platform example
 * apps used to perform by hand (prepending "/no_think" to the user prompt).
 * Driven by rac_llm_options_t.disable_thinking (proto
 * LLMGenerationOptions.disable_thinking / RAGQueryOptions.disable_thinking).
 * Applied at every engine generate call site (component, proto, RAG) so all
 * paths behave identically and no SDK/app injects the token itself.
 */
#ifndef RAC_LLM_THINKING_DIRECTIVE_INTERNAL_H
#define RAC_LLM_THINKING_DIRECTIVE_INTERNAL_H

#include <cstring>
#include <string>

#include "rac/core/rac_types.h"

namespace rac::llm {

/**
 * True when the inference engine applies disable-thinking itself and therefore
 * needs no commons-injected "/no_think" prompt directive (RUN-81).
 *
 * QHexRT suppresses thinking in-runtime via per-family chat-template prefills
 * (hard switch for Qwen3.5, soft directive normalization for Qwen3, gen-prefill
 * for DeepSeek-R1) AND strips a commons-injected "/no_think" from user content,
 * so prepending the token here is redundant double-handling.
 *
 * @p framework_name is the InferenceFramework enum NAME string
 * (e.g. "INFERENCE_FRAMEWORK_QHEXRT"), so we match a stable substring to survive
 * enum renames. ALLOWLIST semantics: only engines named here skip the directive;
 * every other/unknown engine keeps injecting, because llama.cpp/onnx/cloud do
 * NOT self-suppress and rely on the Qwen "/no_think" control token.
 */
inline bool engine_handles_disable_thinking_natively(const char* framework_name) {
    return framework_name != nullptr && std::strstr(framework_name, "QHEXRT") != nullptr;
}

/**
 * Returns @p prompt with the model no-think directive prepended when
 * @p disable_thinking is set AND the engine does not suppress thinking natively;
 * otherwise returns @p prompt unchanged.
 *
 * "/no_think\n" is the Qwen-family control token and matches the prior per-SDK
 * app behavior (e.g. iOS RAGViewModel). @p framework_name gates the injection
 * (see [engine_handles_disable_thinking_natively]).
 */
inline std::string apply_no_think_directive(const std::string& prompt,
                                            rac_bool_t disable_thinking,
                                            const char* framework_name) {
    if (disable_thinking == RAC_FALSE) {
        return prompt;
    }
    if (engine_handles_disable_thinking_natively(framework_name)) {
        return prompt;
    }
    return "/no_think\n" + prompt;
}

/**
 * Backwards-compatible overload for call sites that do not have the framework
 * identity in scope (e.g. the legacy generic C-API path). Framework unknown ⇒
 * inject (the safe default: better a redundant token on a native engine than a
 * missing one on llama.cpp).
 */
inline std::string apply_no_think_directive(const std::string& prompt,
                                            rac_bool_t disable_thinking) {
    return apply_no_think_directive(prompt, disable_thinking, nullptr);
}

}  // namespace rac::llm

#endif  // RAC_LLM_THINKING_DIRECTIVE_INTERNAL_H
