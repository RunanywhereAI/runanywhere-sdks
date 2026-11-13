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

/** Mirrors `runanywhere.v1.DecisionGrouping`. */
typedef enum rac_decision_grouping {
    RAC_DECISION_GROUPING_UNSPECIFIED = 0,
    /** Every question shares one sequence (split only when over length). */
    RAC_DECISION_GROUPING_JOINT = 1,
    /** Each question runs in its own sequence with the full state and images. */
    RAC_DECISION_GROUPING_PER_QUESTION = 2,
} rac_decision_grouping_t;

/** One encoded image (PNG, JPEG, WebP or HEIC). Borrowed, never owned. */
typedef struct rac_decision_image {
    const uint8_t* data;
    size_t size;
    /** MIME type such as "image/png"; NULL or empty = sniffed from the bytes. */
    const char* mime_type;
} rac_decision_image_t;

typedef struct rac_decision_options {
    /** Per-request temperature override; 0 = the model's own per-type value. */
    float temperature;
    /**
     * Prompt-wording version the caller requires; 0 = the model's own served
     * version. A model that serves a different version refuses the request
     * (RAC_ERROR_NOT_SUPPORTED) rather than scoring with unknown wording.
     */
    uint32_t prompt_format_version;
    /**
     * How the questions share forward passes; UNSPECIFIED = the model's
     * default. A model with one fixed layout refuses any other value
     * (RAC_ERROR_NOT_SUPPORTED).
     */
    rac_decision_grouping_t grouping;
    /** Token cap per sequence; 0 = the model's limit. Unsupported non-zero is refused. */
    uint32_t max_length;
    /** Image pixel budget per image; 0 = the model's own. Unsupported non-zero is refused. */
    uint32_t max_pixels;
    /** Lower image pixel bound; 0 = the model's own. Unsupported non-zero is refused. */
    uint32_t min_pixels;
    /**
     * Images shared by every question, borrowed for the duration of the call.
     * A model without image input refuses a non-empty list.
     */
    const rac_decision_image_t* images;
    size_t image_count;
} rac_decision_options_t;

static const rac_decision_options_t RAC_DECISION_OPTIONS_DEFAULT = {
    .temperature = 0.0f,
    .prompt_format_version = 0u,
    .grouping = RAC_DECISION_GROUPING_UNSPECIFIED,
    .max_length = 0u,
    .max_pixels = 0u,
    .min_pixels = 0u,
    .images = NULL,
    .image_count = 0u,
};

/**
 * Whether `options` asks for anything beyond temperature and prompt version.
 * Engines that only honour those two refuse such a request.
 */
static inline rac_bool_t rac_decision_options_has_extended(const rac_decision_options_t* options) {
    return (options != NULL &&
            (options->grouping != RAC_DECISION_GROUPING_UNSPECIFIED || options->max_length != 0u ||
             options->max_pixels != 0u || options->min_pixels != 0u || options->image_count != 0u))
               ? RAC_TRUE
               : RAC_FALSE;
}

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