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

#include <string>

#include "rac/core/rac_types.h"

namespace rac::llm {

/**
 * Returns @p prompt with the model no-think directive prepended when
 * @p disable_thinking is set; otherwise returns @p prompt unchanged.
 *
 * "/no_think\n" is the Qwen-family control token and matches the prior
 * per-SDK app behavior (e.g. iOS RAGViewModel). Per-model directive mapping
 * can refine this later without touching the call sites.
 */
inline std::string apply_no_think_directive(const std::string& prompt,
                                            rac_bool_t disable_thinking) {
    if (disable_thinking == RAC_FALSE) {
        return prompt;
    }
    return "/no_think\n" + prompt;
}

}  // namespace rac::llm

#endif  // RAC_LLM_THINKING_DIRECTIVE_INTERNAL_H
