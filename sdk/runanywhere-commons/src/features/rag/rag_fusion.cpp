/**
 * @file rag_fusion.cpp
 * @brief RRF fusion + multi-query variant parsing.
 */

#include "rag_fusion.h"

#include <algorithm>
#include <cctype>
#include <unordered_map>

namespace runanywhere {
namespace rag {

std::vector<SearchResult> fuse_rankings(const std::vector<std::vector<std::string>>& rankings,
                                        const VectorStoreUSearch* vector_store, size_t top_k) {
    static constexpr float kRRFConstant = 60.0f;

    std::unordered_map<std::string, float> rrf_scores;
    for (const auto& ranking : rankings) {
        for (size_t i = 0; i < ranking.size(); ++i) {
            rrf_scores[ranking[i]] += 1.0f / (kRRFConstant + static_cast<float>(i + 1));
        }
    }

    std::vector<std::pair<std::string, float>> sorted_ids(rrf_scores.begin(), rrf_scores.end());
    std::sort(sorted_ids.begin(), sorted_ids.end(),
              [](const auto& a, const auto& b) { return a.second > b.second; });
    if (sorted_ids.size() > top_k)
        sorted_ids.resize(top_k);

    // Best achievable score: rank-1 in every ranking. Normalizes into [0,1] so
    // the reported similarity is comparable regardless of fan-out.
    const float max_possible =
        rankings.empty() ? 1.0f : static_cast<float>(rankings.size()) / (kRRFConstant + 1.0f);

    std::vector<SearchResult> fused;
    fused.reserve(sorted_ids.size());
    for (const auto& [id, rrf_score] : sorted_ids) {
        float normalized = max_possible > 0.0f ? rrf_score / max_possible : rrf_score;
        normalized = std::min(1.0f, std::max(0.0f, normalized));
        SearchResult result;
        result.id = id;
        result.chunk_id = id;
        result.score = normalized;
        result.similarity = normalized;
        if (vector_store) {
            auto chunk = vector_store->get_chunk(id);
            if (chunk) {
                result.text = chunk->text;
                result.metadata = chunk->metadata;
            }
        }
        fused.push_back(std::move(result));
    }
    return fused;
}

std::vector<std::string> parse_query_variants(const std::string& llm_text,
                                              const std::string& original, size_t count) {
    std::vector<std::string> out;
    if (count == 0)
        return out;

    size_t pos = 0;
    while (pos < llm_text.size() && out.size() < count) {
        size_t eol = llm_text.find('\n', pos);
        if (eol == std::string::npos)
            eol = llm_text.size();
        std::string line = llm_text.substr(pos, eol - pos);
        pos = eol + 1;

        // Strip a leading list marker only: a bullet (-, *) or an explicit
        // numbered prefix (digits followed by '.' or ')'). Bare leading digits
        // are kept so variants like "2024 tax deadlines" survive intact.
        size_t s = 0;
        while (s < line.size() && std::isspace(static_cast<unsigned char>(line[s])))
            ++s;
        if (s < line.size() && (line[s] == '-' || line[s] == '*')) {
            ++s;
        } else {
            size_t d = s;
            while (d < line.size() && std::isdigit(static_cast<unsigned char>(line[d])))
                ++d;
            if (d > s && d < line.size() && (line[d] == '.' || line[d] == ')'))
                s = d + 1;
        }
        while (s < line.size() && std::isspace(static_cast<unsigned char>(line[s])))
            ++s;
        size_t e = line.size();
        while (e > s && std::isspace(static_cast<unsigned char>(line[e - 1])))
            --e;
        const std::string v = line.substr(s, e - s);
        if (v.size() >= 4 && v.size() <= 256 && v != original)
            out.push_back(v);
    }
    return out;
}

}  // namespace rag
}  // namespace runanywhere
