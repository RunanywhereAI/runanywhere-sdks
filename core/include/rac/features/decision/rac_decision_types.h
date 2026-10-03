/** @file rac_decision_types.h @brief Backend-facing decision-model types. */

#ifndef RAC_FEATURES_DECISION_RAC_DECISION_TYPES_H
#define RAC_FEATURES_DECISION_RAC_DECISION_TYPES_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * The kind of answer a question expects. Selects both the shape of the answer
 * and the calibration formula used for its confidence.
 */
typedef enum rac_decision_question_type {
    RAC_DECISION_QUESTION_UNSPECIFIED = 0,
    /** Pick one of the listed options; the answer carries per-option probabilities. */
    RAC_DECISION_QUESTION_CHOICE = 1,
    /** Yes / no / unknown; the answer carries the probability of the "true" option. */
    RAC_DECISION_QUESTION_NOUL = 2,
    /** A level on an ordered scale; the answer carries the expected level index. */
    RAC_DECISION_QUESTION_SCORE = 3,
} rac_decision_question_type_t;

/** One candidate answer for a question. Both pointers stay caller-owned for the
 * duration of the decide call. */
typedef struct rac_decision_option {
    /** Stable identifier echoed back in the answer. */
    const char* key;
    /** Human-readable text for this option. MAY be NULL. */
    const char* description;
} rac_decision_option_t;

typedef struct rac_decision_question {
    /** Identifier echoed back on the matching answer. */
    const char* id;
    rac_decision_question_type_t type;
    /** Instructions read by the model. MAY be NULL. */
    const char* instructions;
    const rac_decision_option_t* options;
    size_t option_count;
} rac_decision_question_t;

typedef struct rac_decision_options {
    /** Per-request temperature override; 0 = the model's own per-type value. */
    float temperature;
    /**
     * Prompt-wording version the caller requires; 0 = the model's own served
     * version. A model that serves a different version refuses the request
     * (RAC_ERROR_NOT_SUPPORTED) rather than scoring with unknown wording.
     */
    uint32_t prompt_format_version;
} rac_decision_options_t;

static const rac_decision_options_t RAC_DECISION_OPTIONS_DEFAULT = {
    .temperature = 0.0f,
    .prompt_format_version = 0u,
};

typedef struct rac_decision_answer {
    /** malloc-owned copy of the question id. */
    char* id;
    rac_decision_question_type_t type;
    /** CHOICE: malloc-owned copy of the winning option key (NULL otherwise). */
    char* choice;
    /** NOUL: probability of the "true" option in [0, 1]. */
    float noul;
    /** SCORE: expected level index over the ordered options. */
    float score;
    /** Probability of each option, parallel to the request question's options. */
    float* probabilities;
    size_t probability_count;
    /** Calibrated confidence in [0, 1]. */
    float confidence;
    /**
     * SCORE only: descriptions parallel to `probabilities` (entries may be
     * NULL). NULL when the request carried no descriptions. The array is
     * malloc-owned and released by rac_decision_result_free; the entries
     * point into the caller's request (which must outlive the result), so a
     * backend must NOT allocate them and MUST NOT free them.
     */
    char** legend;
} rac_decision_answer_t;

typedef struct rac_decision_result {
    /** One answer per request question, in request order. */
    rac_decision_answer_t* answers;
    size_t answer_count;
    int64_t processing_time_ms;
    char* model_id;
    /** Tokens of the jointly-evaluated prompt. */
    int32_t input_tokens;
    /** Prompt-wording version the model served; 0 when it reports none. */
    uint32_t prompt_format_version;
} rac_decision_result_t;

/** Free every malloc-owned result field and zero the struct. */
RAC_API void rac_decision_result_free(rac_decision_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_FEATURES_DECISION_RAC_DECISION_TYPES_H */