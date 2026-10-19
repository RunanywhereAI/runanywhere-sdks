#ifndef RAC_ENGINE_LLAMACPP_D1_DECISION_H
#define RAC_ENGINE_LLAMACPP_D1_DECISION_H

#include "llama.h"

#include "rac/features/decision/rac_decision_types.h"

// lfm2-d1 reads vocab logits. lfm2-d1-omni reads an embedding column at a mask
// token. GLiNER reads one score at each [L] marker. pplx-decider-joint reads
// the answer-code logits at a marker after each question, one question per
// sequence unless joint grouping is asked for. None of them use Clef spans.
enum class rac_llamacpp_d1_kind { none, lfm2, omni, gliner, pplx_joint };

#if defined(RAC_LLAMACPP_HAS_D1)

#include <string>
#include <vector>

rac_llamacpp_d1_kind rac_llamacpp_d1_kind_of(const llama_model* model);

// pplx-decider-joint: rewrites each escape token in user text with fullwidth
// angle brackets, longest first as listed, so it cannot forge a marker or a
// chat-template boundary.
std::string rac_llamacpp_pplx_escape(const std::string& text, const std::vector<std::string>& escapes);

// Parses a JSON list of strings; empty when it is not one.
std::vector<std::string> rac_llamacpp_pplx_parse_string_list(const std::string& json);

rac_result_t rac_llamacpp_d1_decide(llama_model* model, llama_context* ctx,
                                    rac_llamacpp_d1_kind kind, const char* state,
                                    const rac_decision_question_t* questions, size_t question_count,
                                    const rac_decision_options_t* options,
                                    rac_decision_result_t* output, const char* model_id);

#else

inline rac_llamacpp_d1_kind rac_llamacpp_d1_kind_of(const llama_model*) {
    return rac_llamacpp_d1_kind::none;
}

#endif

#endif
