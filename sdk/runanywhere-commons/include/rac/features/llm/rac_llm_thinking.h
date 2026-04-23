/**
 * @file rac_llm_thinking.h
 * @brief C ABI for splitting `<think>...</think>` content from LLM output.
 *
 * v2 close-out Phase 5 — moves the Swift `ThinkingContentParser` block out
 * of every frontend (currently duplicated in Swift, with stubs queued for
 * Kotlin / Dart / RN / Web). The behavior must be byte-for-byte identical
 * across SDKs so streaming UIs that distinguish thinking vs answer
 * content render the same way everywhere.
 *
 * Three operations cover every consumer:
 *   - rac_llm_extract_thinking()  : split full text into (response, thinking)
 *   - rac_llm_strip_thinking()    : drop ALL <think> blocks (incl. unclosed)
 *   - rac_llm_split_thinking_tokens(): apportion total token count between
 *                                       segments by character ratio
 *
 * The strings are NOT retained — callers copy the output before the next call
 * (the implementation uses a thread_local arena that's reused).
 */

#ifndef RAC_FEATURES_LLM_RAC_LLM_THINKING_H
#define RAC_FEATURES_LLM_RAC_LLM_THINKING_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Extracts the FIRST `<think>...</think>` block from @p text. The remaining
 * text (before + after the block, joined by '\n') is returned via @p
 * out_response; the inside-think content via @p out_thinking. Either may be
 * NULL on output if absent.
 *
 * Outputs point into a thread_local buffer owned by the implementation;
 * caller must copy before the next call on the same thread.
 *
 * @param text             Input text. NULL → RAC_ERROR_NULL_POINTER.
 * @param out_response     Receives a pointer to the response text (NEVER NULL
 *                         on success — empty string at minimum).
 * @param out_response_len Length of response text in bytes (excluding NUL).
 * @param out_thinking     Receives a pointer to thinking text, or NULL when
 *                         no <think>...</think> block was found.
 * @param out_thinking_len Length of thinking text, or 0 when out_thinking
 *                         is NULL.
 * @return RAC_SUCCESS, RAC_ERROR_NULL_POINTER.
 */
RAC_API rac_result_t rac_llm_extract_thinking(const char*  text,
                                               const char** out_response,
                                               size_t*      out_response_len,
                                               const char** out_thinking,
                                               size_t*      out_thinking_len);

/**
 * Removes ALL `<think>...</think>` blocks (multiple per text + trailing
 * unclosed `<think>`) from @p text. Returns the trimmed remainder via
 * @p out_stripped (thread_local; copy before next call).
 *
 * @return RAC_SUCCESS, RAC_ERROR_NULL_POINTER.
 */
RAC_API rac_result_t rac_llm_strip_thinking(const char*  text,
                                             const char** out_stripped,
                                             size_t*      out_stripped_len);

/**
 * Splits @p total_completion_tokens between thinking and response by the
 * character-length ratio. Mirrors the Swift `ThinkingContentParser.splitTokens`
 * heuristic so cross-SDK token accounting agrees.
 *
 * If @p thinking_text is NULL or empty: thinking = 0, response = total.
 * Else: proportional split, clamped, and `thinking + response == total`.
 *
 * @param total_completion_tokens >= 0
 * @param response_text           NULL treated as empty.
 * @param thinking_text           NULL or empty → no split.
 * @param out_thinking_tokens     Receives thinking-segment count.
 * @param out_response_tokens     Receives response-segment count.
 * @return RAC_SUCCESS or RAC_ERROR_NULL_POINTER.
 */
RAC_API rac_result_t rac_llm_split_thinking_tokens(int32_t     total_completion_tokens,
                                                    const char* response_text,
                                                    const char* thinking_text,
                                                    int32_t*    out_thinking_tokens,
                                                    int32_t*    out_response_tokens);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif /* RAC_FEATURES_LLM_RAC_LLM_THINKING_H */
