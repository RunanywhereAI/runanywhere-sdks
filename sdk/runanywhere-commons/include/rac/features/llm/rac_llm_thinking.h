/**
 * @file rac_llm_thinking.h
 * @brief C ABI for splitting thinking-tag content from LLM output.
 *
 * Moves the Swift `ThinkingContentParser` block out
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
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md): `internal`.
 * SDK-facing thinking/response splits arrive inside
 * runanywhere.v1.LLMGenerationResult / LLMStreamEvent bytes; this header
 * is the portable parser used by commons to compute those splits. Do not
 * expose it as a new public SDK surface.
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
 * Extracts the FIRST built-in thinking block from @p text. The default parser
 * recognizes both `<think>...</think>` and `<thinking>...</thinking>` so
 * existing model behavior stays intact. The remaining text (before + after
 * the block, joined by '\n') is returned via @p out_response; the inside-think
 * content via @p out_thinking. Either may be NULL on output if absent.
 *
 * Outputs point into a thread_local buffer owned by the implementation;
 * caller must copy before the next call on the same thread.
 *
 * @internal Commons-internal helper. SDK-facing thinking/response splits
 * arrive via `runanywhere.v1.LLMGenerationResult.thinking_content` /
 * `LLMStreamEvent` proto bytes already populated by
 * `rac_llm_generate_proto` / `rac_llm_generate_stream_proto`. Do NOT bind
 * this symbol from any SDK.
 *
 * @param text             Input text. NULL → RAC_ERROR_NULL_POINTER.
 * @param out_response     Receives a pointer to the response text (NEVER NULL
 *                         on success — empty string at minimum).
 * @param out_response_len Length of response text in bytes (excluding NUL).
 * @param out_thinking     Receives a pointer to thinking text, or NULL when
 *                         no built-in thinking block was found.
 * @param out_thinking_len Length of thinking text, or 0 when out_thinking
 *                         is NULL.
 * @return RAC_SUCCESS, RAC_ERROR_NULL_POINTER.
 */
rac_result_t rac_llm_extract_thinking(const char* text, const char** out_response,
                                      size_t* out_response_len, const char** out_thinking,
                                      size_t* out_thinking_len);

/**
 * Extracts thinking content with a caller-provided tag pair plus the built-in
 * fallbacks described by `rac_llm_extract_thinking`. A caller-provided pair
 * also recognizes chat-template-prefilled output where the opening tag is in
 * the prompt and generated text begins with the thinking body followed by the
 * closing tag. If either custom tag is empty, commons uses only the built-in
 * recognizer.
 *
 * This is still a commons-internal parser; SDKs should consume the generated
 * proto fields populated by commons.
 */
rac_result_t rac_llm_extract_thinking_with_tags(const char* text, const char* open_tag,
                                                const char* close_tag, const char** out_response,
                                                size_t* out_response_len, const char** out_thinking,
                                                size_t* out_thinking_len);

/**
 * Removes ALL built-in thinking blocks (multiple per text + trailing unclosed
 * tags) from @p text. Returns the trimmed remainder via @p out_stripped
 * (thread_local; copy before next call).
 *
 * @internal Commons-internal helper. See `rac_llm_extract_thinking` above —
 * SDKs should read the trimmed response from the proto-populated
 * `LLMGenerationResult.text` / `LLMStreamEvent.token` fields instead.
 *
 * @return RAC_SUCCESS, RAC_ERROR_NULL_POINTER.
 */
rac_result_t rac_llm_strip_thinking(const char* text, const char** out_stripped,
                                    size_t* out_stripped_len);

/**
 * Splits @p total_completion_tokens between thinking and response by the
 * character-length ratio. Mirrors the legacy Swift `ThinkingContentParser
 * .splitTokens` heuristic so cross-SDK token accounting agrees.
 *
 * If @p thinking_text is NULL or empty: thinking = 0, response = total.
 * Else: proportional split, clamped, and `thinking + response == total`.
 *
 * @internal Commons-internal helper. The split is already exposed to SDKs
 * via `LLMGenerationResult.thinking_tokens` / `response_tokens` proto
 * fields, populated by `rac_llm_generate_proto`. Do NOT bind from SDKs.
 *
 * @param total_completion_tokens >= 0
 * @param response_text           NULL treated as empty.
 * @param thinking_text           NULL or empty → no split.
 * @param out_thinking_tokens     Receives thinking-segment count.
 * @param out_response_tokens     Receives response-segment count.
 * @return RAC_SUCCESS or RAC_ERROR_NULL_POINTER.
 */
rac_result_t rac_llm_split_thinking_tokens(int32_t total_completion_tokens,
                                           const char* response_text, const char* thinking_text,
                                           int32_t* out_thinking_tokens,
                                           int32_t* out_response_tokens);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* RAC_FEATURES_LLM_RAC_LLM_THINKING_H */
