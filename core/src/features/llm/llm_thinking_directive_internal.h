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
#include "rac/infrastructure/model_management/rac_model_types.h"

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
 * ALLOWLIST semantics: only the frameworks named here skip the directive on
 * engine grounds; every other engine relies on the Qwen "/no_think" control
 * token, so for them the decision falls to the MODEL gate below.
 */
inline bool engine_handles_disable_thinking_natively(rac_inference_framework_t framework) {
    return framework == RAC_FRAMEWORK_QHEXRT;
}

/**
 * Returns @p prompt with the model no-think directive prepended when
 * @p disable_thinking is set AND the model actually speaks the directive AND the
 * engine does not suppress thinking natively; otherwise returns @p prompt
 * unchanged.
 *
 * "/no_think\n" is the Qwen-family control token and matches the prior per-SDK
 * app behavior (e.g. iOS RAGViewModel). Both gates are mandatory parameters on
 * purpose: an overload that defaulted @p model_supports_thinking to true is what
 * let a non-reasoning model receive the token in the first place, so a caller
 * that cannot name the model's capability must resolve it (see
 * [model_thinking_profile_from_registry] in llm_thinking_tags_internal.h) rather
 * than assume it.
 */
inline std::string apply_no_think_directive(const std::string& prompt,
                                            rac_bool_t disable_thinking,
                                            rac_inference_framework_t framework,
                                            bool model_supports_thinking) {
    if (disable_thinking == RAC_FALSE) {
        return prompt;
    }
    // A model that does not reason has nothing to suppress, and "/no_think" is
    // a Qwen control token rather than a universal one: a model outside that
    // family reads it as prompt text. Measured on LFM2.5-230M, which answers
    // the injected directive with "\n\n" and stops, so a caller that merely
    // asked not to see reasoning got a one-token empty reply. Swift never had
    // this problem because its MLX runtime passes enable_thinking=false as
    // chat-template context (MLX.swift:1371) instead of editing the prompt.
    if (!model_supports_thinking) {
        return prompt;
    }
    if (engine_handles_disable_thinking_natively(framework)) {
        return prompt;
    }
    return "/no_think\n" + prompt;
}

}  // namespace rac::llm

#endif  // RAC_LLM_THINKING_DIRECTIVE_INTERNAL_H
