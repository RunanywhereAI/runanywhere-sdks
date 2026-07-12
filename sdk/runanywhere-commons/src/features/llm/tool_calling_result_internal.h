#ifndef RAC_FEATURES_LLM_TOOL_CALLING_RESULT_INTERNAL_H
#define RAC_FEATURES_LLM_TOOL_CALLING_RESULT_INTERNAL_H

#include <cctype>
#include <string>
#include <utility>

#include <nlohmann/json.hpp>

#include "tool_calling.pb.h"

namespace rac::llm::tool_calling {

struct WebSearchAttribution {
    std::string summary;
    std::string source_url;
};

inline WebSearchAttribution web_search_attribution(
    const runanywhere::v1::ToolCallingResult& result) {
    for (int index = result.tool_results_size() - 1; index >= 0; --index) {
        const auto& tool_result = result.tool_results(index);
        if (tool_result.name() != "search_web" || tool_result.result_json().empty()) {
            continue;
        }
        const nlohmann::json payload =
            nlohmann::json::parse(tool_result.result_json(), nullptr, false);
        if (payload.is_discarded() || !payload.is_object()) {
            return {};
        }
        WebSearchAttribution attribution;
        const auto summary = payload.find("summary");
        if (summary != payload.end() && summary->is_string()) {
            attribution.summary = summary->get<std::string>();
        }
        const auto source = payload.find("source_url");
        if (source != payload.end() && source->is_string()) {
            attribution.source_url = source->get<std::string>();
        }
        return attribution;
    }
    return {};
}

inline bool is_safe_http_source_url(const std::string& value) {
    if (value.rfind("https://", 0) != 0 && value.rfind("http://", 0) != 0) {
        return false;
    }
    for (const unsigned char c : value) {
        if (std::isspace(c) || std::iscntrl(c)) {
            return false;
        }
    }
    return true;
}

inline void ensure_web_search_attribution(runanywhere::v1::ToolCallingResult* result) {
    if (!result) {
        return;
    }
    const WebSearchAttribution attribution = web_search_attribution(*result);
    if (result->text().empty() && !attribution.summary.empty()) {
        result->set_text(attribution.summary);
    }
    if (!is_safe_http_source_url(attribution.source_url) ||
        result->text().find(attribution.source_url) != std::string::npos) {
        return;
    }
    std::string attributed = result->text();
    if (!attributed.empty()) {
        attributed += "\n";
    }
    attributed += "Source: ";
    attributed += attribution.source_url;
    result->set_text(std::move(attributed));
}

}  // namespace rac::llm::tool_calling

#endif  // RAC_FEATURES_LLM_TOOL_CALLING_RESULT_INTERNAL_H
