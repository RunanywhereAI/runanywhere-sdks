#ifndef RAC_ENGINE_LLAMACPP_D1_DECISION_H
#define RAC_ENGINE_LLAMACPP_D1_DECISION_H

#include "llama.h"

#include "rac/features/decision/rac_decision_types.h"

// lfm2-d1 reads vocab logits. lfm2-d1-omni reads an embedding column at a mask
// token. GLiNER reads one score at each [L] marker. None of them use Clef spans.
enum class rac_llamacpp_d1_kind { none, lfm2, omni, gliner };

#if defined(RAC_LLAMACPP_HAS_D1)

rac_llamacpp_d1_kind rac_llamacpp_d1_kind_of(const llama_model* model);

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
