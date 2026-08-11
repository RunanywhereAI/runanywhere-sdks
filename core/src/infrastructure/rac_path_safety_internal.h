#ifndef RAC_INFRASTRUCTURE_RAC_PATH_SAFETY_INTERNAL_H
#define RAC_INFRASTRUCTURE_RAC_PATH_SAFETY_INTERNAL_H

// Internal (not installed): shared path-segment safety check. An untrusted
// model id or descriptor filename is concatenated into the per-model storage
// root and used as a fallback filename, so a separator or traversal token in
// it could pivot the storage root before any containment check runs. Both the
// download orchestrator and model_paths gate untrusted segments through this.

#include <string_view>

namespace rac::path {

// True if `component` is a single safe path segment: non-empty, not "." or
// "..", and free of '/' and '\\' separators.
inline bool is_safe_path_segment(std::string_view component) {
    return !component.empty() && component != "." && component != ".." &&
           component.find('/') == std::string_view::npos &&
           component.find('\\') == std::string_view::npos;
}

}  // namespace rac::path

#endif  // RAC_INFRASTRUCTURE_RAC_PATH_SAFETY_INTERNAL_H
