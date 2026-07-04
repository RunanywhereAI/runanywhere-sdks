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

namespace {

constexpr size_t kMaxChunkChars = 360;

std::string flatten_and_truncate(const std::string& text, size_t max_chars) {
    std::string out;
    out.reserve(std::min(text.size(), max_chars));
    for (char c : text) {
        if (out.size() >= max_chars)
            break;
        out.push_back((c == '\n' || c == '\r' || c == '\t') ? ' ' : c);
    }
    return out;
}

}  // namespace

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
