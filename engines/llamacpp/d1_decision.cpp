#include "d1_decision.h"

#include "chat.h"
#include "common.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#include "rac/features/decision/rac_decision_service.h"

namespace {

std::string meta_str(const llama_model* model, const std::string& key) {
    char buf[256];
    const int32_t n = llama_model_meta_val_str(model, key.c_str(), buf, sizeof(buf));
    return n < 0 ? std::string() : std::string(buf);
}

const char* type_name(rac_decision_question_type_t type) {
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

float temperature_for(const llama_model* model, rac_decision_question_type_t type, size_t option_count,
                      const rac_decision_options_t* options) {
    if (options != nullptr && options->temperature > 0.0f) {
        return options->temperature;
    }
    const char* bucket = option_count <= 2 ? "2" : option_count <= 5 ? "3_5" : option_count <= 10 ? "6_10" : "11";
    const std::string prefix = meta_str(model, "general.architecture") + ".decision.temperature.";
    const std::string names[] = {std::string(type_name(type)) + "." + bucket, type_name(type)};
    for (const std::string& name : names) {
        const std::string value = meta_str(model, prefix + name);
        if (!value.empty()) {
            return std::strtof(value.c_str(), nullptr);
        }
    }
    return 1.0f;
}

std::vector<float> softmax(const std::vector<float>& scores, float temperature) {
    const float temp = temperature > 0.0f ? temperature : 1.0f;
    const float max_score = *std::max_element(scores.begin(), scores.end());
    std::vector<float> probs(scores.size());
    double sum = 0.0;
    for (size_t i = 0; i < scores.size(); ++i) {
        probs[i] = std::exp((scores[i] - max_score) / temp);
        sum += probs[i];
    }
    for (float& p : probs) {
        p = static_cast<float>(p / sum);
    }
    return probs;
}

float choice_confidence(const std::vector<float>& probs) {
    if (probs.size() < 2) {
        return 1.0f;
    }
    const float uniform = 1.0f / static_cast<float>(probs.size());
    const float p_max = *std::max_element(probs.begin(), probs.end());
    return std::max(0.0f, (p_max - uniform) / (1.0f - uniform));
}

float score_confidence(const std::vector<float>& probs) {
    if (probs.size() < 2) {
        return 1.0f;
    }
    const size_t n = probs.size();
    const size_t mode =
        static_cast<size_t>(std::max_element(probs.begin(), probs.end()) - probs.begin());
    double dist = 0.0;
    double dist_uniform = 0.0;
    for (size_t i = 0; i < n; ++i) {
        dist += probs[i] * std::fabs(static_cast<double>(i) - static_cast<double>(mode));
        dist_uniform += std::fabs(static_cast<double>(i) - (n - 1) / 2.0) / n;
    }
    if (dist_uniform <= 0.0) {
        return 1.0f;
    }
    return std::max(0.0f, static_cast<float>(1.0 - dist / dist_uniform));
}

std::vector<llama_token> one_token_forms(const llama_vocab* vocab, const std::vector<std::string>& forms) {
    std::vector<llama_token> out;
    for (const std::string& form : forms) {
        const std::vector<llama_token> toks = common_tokenize(vocab, form, false, false);
        if (toks.size() == 1 && std::find(out.begin(), out.end(), toks[0]) == out.end()) {
            out.push_back(toks[0]);
        }
    }
    return out;
}

std::string ascii_lower(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return text;
}

// 1 is the yes side, 0 the no side, -1 is not a yes/no key.
int noul_polarity(const char* key) {
    if (key == nullptr) {
        return -1;
    }
    const std::string lower = ascii_lower(key);
    if (lower == "true" || lower == "yes") {
        return 1;
    }
    if (lower == "false" || lower == "no") {
        return 0;
    }
    return -1;
}

std::string choice_label(const std::string& key, size_t index, size_t count) {
    if (key.size() == 1 && std::isalpha(static_cast<unsigned char>(key[0]))) {
        return key;
    }
    if (count <= 26) {
        return std::string(1, static_cast<char>('A' + index));
    }
    char buf[8];
    std::snprintf(buf, sizeof(buf), "%02zu", index);
    return buf;
}

std::vector<llama_token> label_group(const llama_vocab* vocab, rac_decision_question_type_t type,
                                     const std::string& key, const std::string& code) {
    if (type == RAC_DECISION_QUESTION_CHOICE || type == RAC_DECISION_QUESTION_SCORE) {
        const std::string text = type == RAC_DECISION_QUESTION_CHOICE ? code : key;
        const std::vector<llama_token> toks = common_tokenize(vocab, text, false, false);
        if (toks.size() != 1) {
            throw std::runtime_error("decision label is not one token: " + text);
        }
        std::vector<llama_token> group = {toks[0]};
        for (const llama_token extra : one_token_forms(vocab, {" " + text})) {
            if (extra != toks[0]) {
                group.push_back(extra);
            }
        }
        return group;
    }
    const int polarity = noul_polarity(key.c_str());
    if (polarity == 1) {
        return one_token_forms(vocab, {"yes", "Yes", "YES"});
    }
    if (polarity == 0) {
        return one_token_forms(vocab, {"no", "No", "NO"});
    }
    throw std::runtime_error("yes/no options must be true/false or yes/no");
}

std::string render_template(const llama_model* model, const common_json& input) {
    const char* src = llama_model_chat_template(model, "systemone");
    if (src == nullptr) {
        throw std::runtime_error("model has no systemone template");
    }
    const common_chat_template tmpl(src, "", "");
    jinja::context ctx(tmpl.source());
    jinja::global_from_json(ctx, input, false);
    jinja::runtime runtime(ctx);
    return jinja::runtime::gather_string_parts(runtime.execute(tmpl.prog))->as_string().str();
}

void decode_all(llama_context* ctx, const std::vector<llama_token>& tokens) {
    llama_batch batch =
        llama_batch_get_one(const_cast<llama_token*>(tokens.data()), static_cast<int32_t>(tokens.size()));
    if (llama_decode(ctx, batch) != 0) {
        throw std::runtime_error("llama_decode failed");
    }
}

std::vector<float> score_lfm2(llama_model* model, llama_context* ctx, const llama_vocab* vocab,
                              const char* state, const rac_decision_question_t& question, float temperature,
                              int32_t* token_count) {
    const bool true_first = question.type == RAC_DECISION_QUESTION_NOUL;
    std::vector<size_t> order(question.option_count);
    for (size_t i = 0; i < order.size(); ++i) {
        order[i] = i;
    }
    if (true_first) {
        std::stable_partition(order.begin(), order.end(), [&](size_t index) {
            const char* key = question.options[index].key;
            return noul_polarity(key) == 1;
        });
    }

    common_json options = common_json::array();
    std::vector<std::vector<llama_token>> groups;
    for (size_t slot = 0; slot < order.size(); ++slot) {
        const rac_decision_option_t& option = question.options[order[slot]];
        const std::string key = option.key != nullptr ? option.key : "";
        const std::string code = choice_label(key, slot, question.option_count);
        common_json row = common_json::object();
        row["key"] = key;
        row["description"] = option.description != nullptr ? option.description : nullptr;
        if (question.type == RAC_DECISION_QUESTION_CHOICE) {
            row["label"] = code;
        }
        options.push_back(row);
        groups.push_back(label_group(vocab, question.type, key, code));
    }

    common_json input = common_json::object();
    input["id"] = question.id != nullptr ? question.id : "";
    input["type"] = type_name(question.type);
    input["instructions"] = question.instructions != nullptr ? question.instructions : "";
    input["state"] = state != nullptr ? state : "";
    input["options"] = std::move(options);

    const std::vector<llama_token> tokens =
        common_tokenize(vocab, render_template(model, input), false, true);
    *token_count += static_cast<int32_t>(tokens.size());
    llama_memory_clear(llama_get_memory(ctx), true);
    decode_all(ctx, tokens);
    const float* logits = llama_get_logits_ith(ctx, -1);
    if (logits == nullptr) {
        throw std::runtime_error("no logits");
    }
    const int32_t n_vocab = llama_vocab_n_tokens(vocab);
    std::vector<float> prompt_scores;
    for (const auto& group : groups) {
        if (group.empty()) {
            throw std::runtime_error("empty label group");
        }
        float best = -1e30f;
        for (const llama_token id : group) {
            if (id < 0 || id >= n_vocab) {
                throw std::runtime_error("label token out of range");
            }
            best = std::max(best, logits[id]);
        }
        prompt_scores.push_back(best);
    }
    const std::vector<float> prompt_probs = softmax(prompt_scores, temperature);
    std::vector<float> probs(question.option_count);
    for (size_t slot = 0; slot < order.size(); ++slot) {
        probs[order[slot]] = prompt_probs[slot];
    }
    return probs;
}

std::vector<float> score_omni(llama_model* model, llama_context* ctx, const llama_vocab* vocab,
                              const char* state, const rac_decision_question_t& question, float temperature,
                              int32_t* token_count) {
    const llama_token mask = llama_vocab_mask(vocab);
    if (mask == LLAMA_TOKEN_NULL) {
        throw std::runtime_error("model has no mask token");
    }
    common_json options = common_json::array();
    for (size_t i = 0; i < question.option_count; ++i) {
        const rac_decision_option_t& option = question.options[i];
        common_json row = common_json::object();
        row["key"] = option.key != nullptr ? option.key : "";
        row["description"] = option.description != nullptr ? option.description : nullptr;
        options.push_back(row);
    }
    common_json input = common_json::object();
    input["id"] = question.id != nullptr ? question.id : "";
    input["type"] = type_name(question.type);
    input["instructions"] = question.instructions != nullptr ? question.instructions : "";
    input["state"] = state != nullptr ? state : "";
    input["options"] = std::move(options);
    input["audio"] = false;
    input["sep"] = "<<d1omni:sep>>";
    input["mark_state"] = "<<d1omni:state>>";
    input["mark_question"] = "<<d1omni:question>>";
    input["mark_option"] = "<<d1omni:option>>";

    const std::string prompt = render_template(model, input);
    const std::string sep = "<<d1omni:sep>>";
    std::vector<llama_token> tokens;
    size_t at = 0;
    bool first = true;
    while (at <= prompt.size()) {
        const size_t next = prompt.find(sep, at);
        std::string piece = prompt.substr(at, next == std::string::npos ? std::string::npos : next - at);
        if (!first) {
            const char* marks[] = {"<<d1omni:state>>", "<<d1omni:question>>", "<<d1omni:option>>"};
            for (const char* mark : marks) {
                const size_t n = std::strlen(mark);
                if (piece.compare(0, n, mark) == 0) {
                    piece = piece.substr(n);
                    break;
                }
            }
        }
        first = false;
        const std::vector<llama_token> piece_tokens = common_tokenize(vocab, piece, false, true);
        tokens.insert(tokens.end(), piece_tokens.begin(), piece_tokens.end());
        if (next == std::string::npos) {
            break;
        }
        at = next + sep.size();
    }
    *token_count += static_cast<int32_t>(tokens.size());
    std::vector<int32_t> markers;
    for (size_t i = 0; i < tokens.size(); ++i) {
        if (tokens[i] == mask) {
            markers.push_back(static_cast<int32_t>(i));
        }
    }
    if (markers.size() != question.option_count) {
        throw std::runtime_error("option markers do not match the question");
    }
    llama_memory_clear(llama_get_memory(ctx), true);
    decode_all(ctx, tokens);
    const int column = question.type == RAC_DECISION_QUESTION_CHOICE ? 0
                       : question.type == RAC_DECISION_QUESTION_SCORE ? 1
                                                                      : 2;
    std::vector<float> scores;
    for (const int32_t marker : markers) {
        const float* embedding = llama_get_embeddings_ith(ctx, marker);
        if (embedding == nullptr) {
            throw std::runtime_error("no embedding at mask token");
        }
        scores.push_back(embedding[column]);
    }
    return softmax(scores, temperature);
}

std::vector<float> score_gliner(llama_model* model, llama_context* ctx, const llama_vocab* vocab,
                                const char* state, const rac_decision_question_t& question,
                                float temperature, int32_t* token_count) {
    const std::vector<llama_token> marker = common_tokenize(vocab, "[L]", false, true);
    if (marker.size() != 1) {
        throw std::runtime_error("decision model has no [L] token");
    }
    common_json options = common_json::array();
    for (size_t i = 0; i < question.option_count; ++i) {
        const rac_decision_option_t& option = question.options[i];
        common_json row = common_json::object();
        row["key"] = option.key != nullptr ? option.key : "";
        row["description"] = option.description != nullptr ? option.description : nullptr;
        options.push_back(row);
    }
    common_json input = common_json::object();
    input["id"] = question.id != nullptr ? question.id : "";
    input["type"] = type_name(question.type);
    input["instructions"] = question.instructions != nullptr ? question.instructions : "";
    input["state"] = state != nullptr ? state : "";
    input["options"] = std::move(options);

    const std::vector<llama_token> tokens =
        common_tokenize(vocab, render_template(model, input), false, true);
    *token_count += static_cast<int32_t>(tokens.size());
    std::vector<int32_t> marks;
    for (size_t i = 0; i < tokens.size(); ++i) {
        if (tokens[i] == marker[0]) {
            marks.push_back(static_cast<int32_t>(i));
        }
    }
    if (marks.size() != question.option_count) {
        throw std::runtime_error("option markers do not match the question");
    }
    if (llama_memory_t mem = llama_get_memory(ctx)) {
        llama_memory_clear(mem, true);
    }
    decode_all(ctx, tokens);
    std::vector<float> scores;
    for (const int32_t at : marks) {
        const float* embedding = llama_get_embeddings_ith(ctx, at);
        if (embedding == nullptr) {
            throw std::runtime_error("no score at [L]");
        }
        scores.push_back(embedding[0]);
    }
    return softmax(scores, temperature);
}

}  // namespace

rac_llamacpp_d1_kind rac_llamacpp_d1_kind_of(const llama_model* model) {
    const std::string key = meta_str(model, "general.architecture") + ".decision.type";
    const std::string type = meta_str(model, key);
    if (type == "lfm2-d1") {
        return rac_llamacpp_d1_kind::lfm2;
    }
    if (type == "lfm2-d1-omni") {
        return rac_llamacpp_d1_kind::omni;
    }
    if (type == "gliner") {
        return rac_llamacpp_d1_kind::gliner;
    }
    return rac_llamacpp_d1_kind::none;
}

rac_result_t rac_llamacpp_d1_decide(llama_model* model, llama_context* ctx, rac_llamacpp_d1_kind kind,
                                    const char* state, const rac_decision_question_t* questions,
                                    size_t question_count, const rac_decision_options_t* options,
                                    rac_decision_result_t* output, const char* model_id) {
    const auto started = std::chrono::steady_clock::now();
    output->answers =
        static_cast<rac_decision_answer_t*>(std::calloc(question_count, sizeof(rac_decision_answer_t)));
    if (output->answers == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    output->answer_count = question_count;
    const llama_vocab* vocab = llama_model_get_vocab(model);
    int32_t n_tokens = 0;
    try {
        for (size_t i = 0; i < question_count; ++i) {
            const rac_decision_question_t& question = questions[i];
            auto& answer = output->answers[i];
            answer.id = question.id != nullptr ? strdup(question.id) : strdup("");
            answer.type = question.type;
            answer.probability_count = question.option_count;
            answer.probabilities = static_cast<float*>(
                std::calloc(question.option_count > 0 ? question.option_count : 1, sizeof(float)));
            if (answer.id == nullptr || answer.probabilities == nullptr) {
                rac_decision_result_free(output);
                return RAC_ERROR_OUT_OF_MEMORY;
            }
            if (question.option_count == 0) {
                continue;
            }
            if (question.type == RAC_DECISION_QUESTION_NOUL) {
                if (question.option_count != 2) {
                    throw std::runtime_error("a yes/no decision needs two options");
                }
                int yes = 0;
                int no = 0;
                for (size_t j = 0; j < question.option_count; ++j) {
                    const int polarity = noul_polarity(question.options[j].key);
                    if (polarity == 1) {
                        ++yes;
                    } else if (polarity == 0) {
                        ++no;
                    } else {
                        throw std::runtime_error("yes/no options must be true/false or yes/no");
                    }
                }
                if (yes != 1 || no != 1) {
                    throw std::runtime_error("yes/no options must name both sides once");
                }
            }
            const float temperature = temperature_for(model, question.type, question.option_count, options);
            std::vector<float> probs;
            if (kind == rac_llamacpp_d1_kind::omni) {
                probs = score_omni(model, ctx, vocab, state, question, temperature, &n_tokens);
            } else if (kind == rac_llamacpp_d1_kind::gliner) {
                probs = score_gliner(model, ctx, vocab, state, question, temperature, &n_tokens);
            } else {
                probs = score_lfm2(model, ctx, vocab, state, question, temperature, &n_tokens);
            }
            std::memcpy(answer.probabilities, probs.data(), probs.size() * sizeof(float));
            switch (question.type) {
                case RAC_DECISION_QUESTION_CHOICE: {
                    const size_t best = static_cast<size_t>(
                        std::max_element(probs.begin(), probs.end()) - probs.begin());
                    answer.choice = strdup(question.options[best].key != nullptr ? question.options[best].key : "");
                    if (answer.choice == nullptr) {
                        rac_decision_result_free(output);
                        return RAC_ERROR_OUT_OF_MEMORY;
                    }
                    answer.confidence = choice_confidence(probs);
                    break;
                }
                case RAC_DECISION_QUESTION_NOUL: {
                    size_t true_index = probs.size();
                    for (size_t j = 0; j < probs.size(); ++j) {
                        if (noul_polarity(question.options[j].key) == 1) {
                            true_index = j;
                            break;
                        }
                    }
                    if (true_index >= probs.size()) {
                        throw std::runtime_error("yes/no options must be true/false or yes/no");
                    }
                    answer.noul = probs[true_index];
                    answer.confidence = choice_confidence(probs);
                    break;
                }
                case RAC_DECISION_QUESTION_SCORE: {
                    double expected = 0.0;
                    for (size_t j = 0; j < probs.size(); ++j) {
                        expected += static_cast<double>(j) * probs[j];
                    }
                    answer.score = static_cast<float>(expected);
                    answer.confidence = score_confidence(probs);
                    break;
                }
                default:
                    break;
            }
        }
    } catch (const std::exception&) {
        rac_decision_result_free(output);
        return RAC_ERROR_INFERENCE_FAILED;
    }
    output->processing_time_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started)
            .count();
    output->model_id = model_id != nullptr ? strdup(model_id) : strdup("");
    output->input_tokens = n_tokens;
    if (output->model_id == nullptr) {
        rac_decision_result_free(output);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    return RAC_SUCCESS;
}
