/**
 * @file rag_rerank.cpp
 * @brief LLM-pointwise reranking of fused RAG candidates.
 */

#include "rag_rerank.h"

#include <algorithm>
#include <cctype>
#include <numeric>

#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_llm_service.h"

#define LOG_TAG "RAG.Rerank"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)

namespace runanywhere {
namespace rag {

/**
 * @brief Flatten whitespace and truncate text to at most `max_chars` bytes,
 *        backing off to a valid UTF-8 character boundary.
 *
 * @param text Input text to format and truncate.
 * @param max_chars Maximum byte budget for the output.
 * @return Formatted string guaranteed to end on a complete UTF-8 code point.
 */
std::string flatten_and_truncate(const std::string& text, size_t max_chars) {
    if (max_chars == 0 || text.empty()) {
        return "";
    }
    std::string out;
    out.reserve(std::min(text.size(), max_chars));

    size_t i = 0;
    while (i < text.size()) {
        const unsigned char lead = static_cast<unsigned char>(text[i]);
        size_t cp_len = 1;
        if (lead < 0x80) {
            cp_len = 1;
        } else if ((lead & 0xE0) == 0xC0) {
            cp_len = 2;
        } else if ((lead & 0xF0) == 0xE0) {
            cp_len = 3;
        } else if ((lead & 0xF8) == 0xF0) {
            cp_len = 4;
        } else {
            cp_len = 1;
        }

        if (i + cp_len > text.size()) {
            break;
        }

        bool valid = true;
        for (size_t k = 1; k < cp_len; ++k) {
            if ((static_cast<unsigned char>(text[i + k]) & 0xC0) != 0x80) {
                valid = false;
                break;
            }
        }
        if (!valid) {
            ++i;
            continue;
        }

        if (out.size() + cp_len > max_chars) {
            break;
        }

        if (lead == '\n' || lead == '\r' || lead == '\t') {
            out.push_back(' ');
        } else if (cp_len == 1) {
            out.push_back(text[i]);
        } else {
            out.append(text, i, cp_len);
        }
        i += cp_len;
    }

    return out;
}

/**
 * @brief Parse LLM scorer output into per-candidate scores.
 *
 * @param text The raw output string from the LLM.
 * @param n Number of candidates.
 * @param scores Output vector to populate with scores.
 * @return Number of distinct candidates that received a score.
 */
size_t parse_rerank_scores(const std::string& text, size_t n, std::vector<int>& scores) {
    scores.assign(n, 0);
    size_t parsed = 0;
    size_t pos = 0;
    while (pos < text.size()) {
        size_t eol = text.find('\n', pos);
        if (eol == std::string::npos)
            eol = text.size();
        const std::string line = text.substr(pos, eol - pos);
        pos = eol + 1;

        size_t i = 0;
        while (i < line.size() && !std::isdigit(static_cast<unsigned char>(line[i])))
            ++i;
        if (i >= line.size())
            continue;
        size_t idx = 0;
        bool have_idx = false;
        while (i < line.size() && std::isdigit(static_cast<unsigned char>(line[i]))) {
            idx = idx * 10 + static_cast<size_t>(line[i] - '0');
            have_idx = true;
            ++i;
        }
        if (!have_idx || idx < 1 || idx > n)
            continue;
        // Skip separators to the score digit.
        while (i < line.size() && !std::isdigit(static_cast<unsigned char>(line[i])))
            ++i;
        if (i >= line.size())
            continue;
        int score = line[i] - '0';
        if (score < 1)
            score = 1;
        if (score > 5)
            score = 5;
        if (scores[idx - 1] == 0)
            ++parsed;
        scores[idx - 1] = score;
    }
    return parsed;
}

/**
 * @brief Stable-reorder `results` by descending score.
 *
 * @param results Vector of search results to reorder.
 * @param scores Corresponding score vector matching results in size.
 */
void reorder_by_scores(std::vector<SearchResult>& results, const std::vector<int>& scores) {
    if (scores.size() != results.size())
        return;
    const size_t n = results.size();
    std::vector<size_t> order(n);
    std::iota(order.begin(), order.end(), 0);
    std::stable_sort(order.begin(), order.end(),
                     [&](size_t a, size_t b) { return scores[a] > scores[b]; });

    std::vector<SearchResult> reranked;
    reranked.reserve(n);
    for (size_t i : order)
        reranked.push_back(std::move(results[i]));
    results = std::move(reranked);
}

/**
 * @brief Score `results` with the LLM and reorder in place.
 *
 * @param llm_handle Native handle to the loaded LLM instance.
 * @param question The user question/query string.
 * @param base_options LLM options to use as baseline.
 * @param results Candidates to score and reorder.
 */
void rerank_llm_pointwise(rac_handle_t llm_handle, const std::string& question,
                          const rac_llm_options_t& base_options,
                          std::vector<SearchResult>& results) {
    if (!llm_handle || results.size() < 2)
        return;

    const size_t n = results.size();
    std::string prompt =
        "You are a relevance scorer. Rate how well each passage helps answer the query, "
        "from 1 (irrelevant) to 5 (perfect match).\n"
        "Output exactly " +
        std::to_string(n) +
        " lines, no extra text. Format: '<index>: <score>'.\n\nQuery: " + question +
        "\n\nPassages:\n";
    for (size_t i = 0; i < n; ++i) {
        prompt += "[" + std::to_string(i + 1) + "] " +
                  flatten_and_truncate(results[i].text, kMaxChunkChars) + "\n";
    }

    rac_llm_options_t opts = base_options;
    opts.temperature = 0.0f;
    opts.max_tokens = static_cast<int32_t>(n * 8 + 16);
    opts.system_prompt = nullptr;

    rac_llm_result_t out = {};
    rac_result_t rc = rac_llm_generate(llm_handle, prompt.c_str(), &opts, &out);
    if (rc != RAC_SUCCESS || !out.text) {
        LOGI("LLM scoring unavailable (%d), keeping fused order", rc);
        rac_llm_result_free(&out);
        return;
    }
    const std::string scored_text(out.text);
    rac_llm_result_free(&out);

    std::vector<int> scores;
    if (parse_rerank_scores(scored_text, n, scores) == 0) {
        LOGI("no parseable scores, keeping fused order");
        return;
    }

    reorder_by_scores(results, scores);
    LOGI("reordered %zu candidates by LLM relevance", n);
}

}  // namespace rag
}  // namespace runanywhere
