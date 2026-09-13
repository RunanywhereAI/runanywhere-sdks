#ifndef RAC_INFRASTRUCTURE_RAC_PATH_SAFETY_INTERNAL_H
#define RAC_INFRASTRUCTURE_RAC_PATH_SAFETY_INTERNAL_H

// Internal (not installed): shared path-segment safety check. An untrusted
// model id or descriptor filename is concatenated into the per-model storage
// root and used as a fallback filename, so a separator or traversal token in
// it could pivot the storage root before any containment check runs. Both the
// download orchestrator and model_paths gate untrusted segments through this.

#include <cstring>
#include <string_view>

namespace rac::path {

// True if `component` is a single safe path segment: non-empty, not "." or
// "..", and free of '/' and '\\' separators.
inline bool is_safe_path_segment(std::string_view component) {
    return !component.empty() && component != "." && component != ".." &&
           component.find('/') == std::string_view::npos &&
           component.find('\\') == std::string_view::npos;
}

/**
 * @brief Finds the last occurrence of a path separator ('/' or '\\') in a C string.
 *
 * Safely compares separator pointers without risking undefined behavior from comparing
 * unrelated pointers when one is null.
 *
 * @param path Null-terminated path string.
 * @return Pointer to the last separator character in path, or nullptr if none found.
 */
inline const char* find_last_path_separator(const char* path) {
    if (!path) {
        return nullptr;
    }
    const char* last_slash = std::strrchr(path, '/');
    const char* last_backslash = std::strrchr(path, '\\');
    if (last_slash && last_backslash) {
        return last_slash > last_backslash ? last_slash : last_backslash;
    }
    return last_slash ? last_slash : last_backslash;
}

/**
 * @brief Finds the last occurrence of a path separator ('/' or '\\') in a mutable C string.
 *
 * @param path Mutable null-terminated path string.
 * @return Pointer to the last separator character in path, or nullptr if none found.
 */
inline char* find_last_path_separator(char* path) {
    if (!path) {
        return nullptr;
    }
    char* last_slash = std::strrchr(path, '/');
    char* last_backslash = std::strrchr(path, '\\');
    if (last_slash && last_backslash) {
        return last_slash > last_backslash ? last_slash : last_backslash;
    }
    return last_slash ? last_slash : last_backslash;
}

/**
 * @brief Extracts the trailing filename or last component from a path string.
 *
 * @param path Null-terminated path string.
 * @return Pointer to the first character after the last separator, or `path` if no separator.
 */
inline const char* filename_from_path(const char* path) {
    if (!path) {
        return nullptr;
    }
    const char* sep = find_last_path_separator(path);
    return sep ? sep + 1 : path;
}

}  // namespace rac::path

#endif  // RAC_INFRASTRUCTURE_RAC_PATH_SAFETY_INTERNAL_H
