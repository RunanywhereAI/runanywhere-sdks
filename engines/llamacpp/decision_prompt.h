/**
 * @file decision_prompt.h
 * @brief Joint decision-prompt construction for the llamacpp decision engine.
 *
 * A decision model consumes one prompt that carries the whole request: a state,
 * and for every question its instructions plus its options. The model's own
 * bundled template (shipped in the GGUF metadata under a named template) does
 * the actual layout; this builder:
 *
 *   1. hands the template the request as raw JSON with sorted keys,
 *   2. splits the rendered text at the separator markers the template emits,
 *   3. tokenizes each piece and tags its tokens with a llama_decision_order
 *      value (question span typed by the answer kind, option span, or NONE for
 *      glue text the head ignores).
 *
 * The span array is what the joint head reads: one run of TOKENS per question,
 * one run per option, everything else NONE. Without it the head scores nothing.
 */

#ifndef RAC_ENGINE_LLAMACPP_DECISION_PROMPT_H
#define RAC_ENGINE_LLAMACPP_DECISION_PROMPT_H

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>

#include "chat.h"
#include "common.h"
#include "llama.h"
#include "nlohmann/json.hpp"

#include "rac/features/decision/rac_decision_types.h"

#if !defined(RAC_LLAMACPP_HAS_CLEF_SPAN)
enum {
    LLAMA_DECISION_ORDER_NONE = 0,
    LLAMA_DECISION_ORDER_QUESTION_NOUL = 1,
    LLAMA_DECISION_ORDER_QUESTION_CHOICE = 2,
    LLAMA_DECISION_ORDER_QUESTION_SCORE = 3,
    LLAMA_DECISION_ORDER_OPTION = 4,
};
#endif

namespace runanywhere::decision_prompt {

// Tokens and their span roles for one decision prompt.
struct TaggedPrompt {
    std::vector<llama_token> tokens;
    // Parallel to `tokens`; values are llama_decision_order.
    std::vector<int32_t> order;
    size_t option_count = 0;
    // The k-th option in the model's canonical render order came from request
    // option `option_request_index[k]` of its question. Parallel to the score
    // rows the joint head returns, so callers can place each score back onto
    // the option index the request used.
    std::vector<int32_t> option_request_index;
};

// Markers the template inserts; keep in sync with the template contract.
inline const std::string kSep = "<<clef:sep>>";
inline const std::string kMarkQuestion = "<<clef:question>>";
inline const std::string kMarkOption = "<<clef:option>>";
inline const std::string kMarker = "<<clef:";

inline const char* question_type_name(rac_decision_question_type_t type) {
    switch (type) {
        case RAC_DECISION_QUESTION_CHOICE:
            return "choice";
        case RAC_DECISION_QUESTION_NOUL:
            return "noul";
        case RAC_DECISION_QUESTION_SCORE:
            return "score";
        default:
            return "";
    }
}

inline int32_t question_order(rac_decision_question_type_t type) {
    switch (type) {
        case RAC_DECISION_QUESTION_NOUL:
            return LLAMA_DECISION_ORDER_QUESTION_NOUL;
        case RAC_DECISION_QUESTION_CHOICE:
            return LLAMA_DECISION_ORDER_QUESTION_CHOICE;
        case RAC_DECISION_QUESTION_SCORE:
            return LLAMA_DECISION_ORDER_QUESTION_SCORE;
        default:
            return LLAMA_DECISION_ORDER_NONE;
    }
}

namespace detail {

// The canonical option order the model was trained on: CHOICE options sorted
// by key, NOUL options with "true" first, SCORE options already in level
// order. The upstream server and the reference encoder apply the same rules;
// rendering request order instead shifts every score in the joint pass.
inline std::vector<size_t> canonical_option_order(const rac_decision_question_t& question) {
    std::vector<size_t> order(question.option_count);
    for (size_t i = 0; i < question.option_count; ++i) {
        order[i] = i;
    }
    if (question.type == RAC_DECISION_QUESTION_CHOICE) {
        std::stable_sort(order.begin(), order.end(), [&](size_t a, size_t b) {
            const char* ka = question.options[a].key != nullptr ? question.options[a].key : "";
            const char* kb = question.options[b].key != nullptr ? question.options[b].key : "";
            return std::strcmp(ka, kb) < 0;
        });
    } else if (question.type == RAC_DECISION_QUESTION_NOUL) {
        std::stable_sort(order.begin(), order.end(), [&](size_t a, size_t b) {
            auto rank = [&](size_t index) {
                const char* key = question.options[index].key;
                if (key != nullptr && std::strcmp(key, "true") == 0) {
                    return 0;
                }
                if (key != nullptr && std::strcmp(key, "false") == 0) {
                    return 1;
                }
                return 2;
            };
            return rank(a) < rank(b);
        });
    }
    return order;
}

inline nlohmann::ordered_json replace_text(const nlohmann::ordered_json& val,
                                           const std::string& search,
                                           const std::string& replace) {
    if (val.is_string()) {
        std::string str = val.get<std::string>();
        string_replace_all(str, search, replace);
        return str;
    }
    if (val.is_array()) {
        auto out = nlohmann::ordered_json::array();
        for (const auto& item : val) {
            out.push_back(replace_text(item, search, replace));
        }
        return out;
    }
    if (val.is_object()) {
        auto out = nlohmann::ordered_json::object();
        for (const auto& [key, item] : val.items()) {
            out[key] = replace_text(item, search, replace);
        }
        return out;
    }
    return val;
}

inline nlohmann::ordered_json sort_keys(const nlohmann::ordered_json& val) {
    if (val.is_array()) {
        auto out = nlohmann::ordered_json::array();
        for (const auto& item : val) {
            out.push_back(sort_keys(item));
        }
        return out;
    }
    if (val.is_object()) {
        std::map<std::string, nlohmann::ordered_json> sorted;
        for (const auto& [key, item] : val.items()) {
            sorted[key] = sort_keys(item);
        }
        auto out = nlohmann::ordered_json::object();
        for (const auto& [key, item] : sorted) {
            out[key] = item;
        }
        return out;
    }
    return val;
}

}  // namespace detail

/**
 * Render the model's bundled decision template for one request and tag the
 * resulting tokens. The template source is passed in (callers read it from the
 * GGUF metadata); this function never invents a layout of its own.
 *
 * Throws std::invalid_argument when the rendered prompt does not match the
 * request (missing question/option spans, empty instruction or option text).
 */
inline TaggedPrompt build(const std::string& template_src, const llama_vocab* vocab,
                          const char* state,
                          const rac_decision_question_t* questions, size_t question_count) {
    if (!vocab || !state || (question_count > 0 && !questions)) {
        throw std::invalid_argument("decision prompt: null argument");
    }

    auto inp_questions = nlohmann::ordered_json::array();
    std::vector<int32_t> option_request_index;
    for (size_t i = 0; i < question_count; ++i) {
        const auto& question = questions[i];
        const std::vector<size_t> render_order = detail::canonical_option_order(question);
        auto options = nlohmann::ordered_json::array();
        for (size_t position = 0; position < render_order.size(); ++position) {
            const size_t request_index = render_order[position];
            const rac_decision_option_t& option = question.options[request_index];
            // SCORE renders its level index as the option id, matching the
            // reference encoder.
            std::string key;
            if (question.type == RAC_DECISION_QUESTION_SCORE) {
                key = std::to_string(position);
            } else {
                key = option.key != nullptr ? option.key : "";
            }
            options.push_back(nlohmann::ordered_json{
                {"key", key},
                {"description", option.description
                                    ? nlohmann::ordered_json(option.description)
                                    : nlohmann::ordered_json(nullptr)},
            });
            option_request_index.push_back(static_cast<int32_t>(request_index));
        }
        inp_questions.push_back(nlohmann::ordered_json{
            {"id", question.id ? question.id : ""},
            {"type", question_type_name(question.type)},
            {"instructions", question.instructions
                                 ? nlohmann::ordered_json(question.instructions)
                                 : nlohmann::ordered_json(nullptr)},
            {"options", options},
        });
    }

    // The template is given raw values with sorted keys, and no template marker
    // may survive inside the input.
    auto inp = nlohmann::ordered_json{
        {"state", state},
        {"questions", inp_questions},
    };
    inp = detail::replace_text(detail::sort_keys(inp), kMarker, "<<clef ");
    inp["sep"] = kSep;
    inp["mark_question"] = kMarkQuestion;
    inp["mark_option"] = kMarkOption;

    common_chat_template tmpl(template_src, "", "");
    jinja::context ctx(tmpl.source());
    jinja::global_from_json(ctx, inp, false);
    jinja::runtime runtime(ctx);
    const jinja::value results = runtime.execute(tmpl.prog);
    const std::string prompt = jinja::runtime::gather_string_parts(results)->as_string().str();

    // The model was trained with the pieces tokenized one by one, never as one
    // blob, so split at the separator and tokenize each piece independently.
    TaggedPrompt out;
    size_t i_question = 0;
    for (std::string piece : string_split(prompt, kSep)) {
        int32_t order = LLAMA_DECISION_ORDER_NONE;
        if (string_starts_with(piece, kMarkQuestion)) {
            piece = piece.substr(kMarkQuestion.size());
            if (i_question >= question_count) {
                throw std::invalid_argument("unexpected layout of the decision prompt");
            }
            order = question_order(questions[i_question++].type);
        } else if (string_starts_with(piece, kMarkOption)) {
            piece = piece.substr(kMarkOption.size());
            order = LLAMA_DECISION_ORDER_OPTION;
            out.option_count++;
        }

        std::vector<llama_token> piece_tokens(piece.size() + 8);
        int32_t n = llama_tokenize(vocab, piece.c_str(), static_cast<int32_t>(piece.size()),
                                   piece_tokens.data(), static_cast<int32_t>(piece_tokens.size()),
                                   false, true);
        if (n < 0) {
            piece_tokens.resize(-n);
            n = llama_tokenize(vocab, piece.c_str(), static_cast<int32_t>(piece.size()),
                               piece_tokens.data(), static_cast<int32_t>(piece_tokens.size()),
                               false, true);
        }
        if (n < 0) {
            throw std::runtime_error("decision prompt: tokenization failed");
        }
        piece_tokens.resize(n);
        if (order != LLAMA_DECISION_ORDER_NONE && piece_tokens.empty()) {
            throw std::invalid_argument(
                "the instructions and the options of a question must not be empty");
        }
        out.tokens.insert(out.tokens.end(), piece_tokens.begin(), piece_tokens.end());
        out.order.insert(out.order.end(), piece_tokens.size(), order);
    }

    size_t expected_options = 0;
    for (size_t i = 0; i < question_count; ++i) {
        expected_options += questions[i].option_count;
    }
    if (i_question != question_count || out.option_count != expected_options ||
        option_request_index.size() != expected_options) {
        throw std::invalid_argument("unexpected layout of the decision prompt");
    }
    out.option_request_index = std::move(option_request_index);
    return out;
}

}  // namespace runanywhere::decision_prompt

#endif  // RAC_ENGINE_LLAMACPP_DECISION_PROMPT_H