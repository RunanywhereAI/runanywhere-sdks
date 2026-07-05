#ifndef RUNANYWHERE_LLAMACPP_STOP_HELPERS_H
#define RUNANYWHERE_LLAMACPP_STOP_HELPERS_H

/**
 * Shared caller-stop-sequence helpers for the llama.cpp engine.
 *
 * The inner generation loops (engines/llamacpp/llamacpp_backend.cpp) only honour
 * a built-in static stop list, so caller-supplied stops (passed via
 * rac_llm_options_t / rac_vlm_options_t) are enforced at the C-API boundary in
 * rac_llm_llamacpp.cpp and rac_vlm_llamacpp.cpp. These two window-scanning
 * helpers were byte-for-byte identical in both translation units; they are
 * lifted here so the LLM and VLM stop-enforcement paths share one definition.
 *
 * Collecting the stops out of the (differently-typed) option structs stays in
 * each TU — only these option-struct-agnostic string helpers are shared.
 */

#include <cstddef>
#include <string>
#include <vector>

namespace runanywhere {
namespace llamacpp_internal {

/**
 * Find the earliest occurrence of any caller-supplied stop sequence in the
 * decode window. Returns std::string::npos when no stop sequence is matched.
 */
inline std::size_t find_first_stop_sequence(const std::string& window,
                                            const std::vector<std::string>& stops) {
    std::size_t earliest = std::string::npos;
    for (const auto& stop_seq : stops) {
        const std::size_t pos = window.find(stop_seq);
        if (pos != std::string::npos && (earliest == std::string::npos || pos < earliest)) {
            earliest = pos;
        }
    }
    return earliest;
}

/**
 * Compute the longest length across all caller-supplied stop sequences so the
 * scan window can be trimmed to that horizon without losing potential matches.
 */
inline std::size_t max_stop_length(const std::vector<std::string>& stops) {
    std::size_t m = 0;
    for (const auto& s : stops) {
        if (s.size() > m) {
            m = s.size();
        }
    }
    return m;
}

}  // namespace llamacpp_internal
}  // namespace runanywhere

#endif  // RUNANYWHERE_LLAMACPP_STOP_HELPERS_H
