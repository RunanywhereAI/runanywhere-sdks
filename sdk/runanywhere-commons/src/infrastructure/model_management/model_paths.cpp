/**
 * @file model_paths.cpp
 * @brief Model Path Utilities Implementation
 *
 * C port of Swift's ModelPathUtils from:
 * Sources/RunAnywhere/Infrastructure/ModelManagement/Utilities/ModelPathUtils.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 */

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <initializer_list>
#include <mutex>
#include <ranges>
#include <string>
#include <vector>

#include "infrastructure/rac_path_safety_internal.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"

// =============================================================================
// STATIC STATE
// =============================================================================

static std::mutex g_paths_mutex{};
static std::string g_base_dir{};

namespace fs = std::filesystem;

// Mirrors download_orchestrator.cpp::is_safe_path_segment.
// model_id is concatenated into the per-model folder root (and used as a
// fallback filename), so any path-separator or traversal token in the
// untrusted id could pivot the storage root before any descriptor path is
// applied (security-privacy-storage-network-001-followup-model-id).
namespace {
bool is_safe_model_id_segment(const char* model_id) {
    return model_id != nullptr && rac::path::is_safe_path_segment(model_id);
}
}  // namespace

// =============================================================================
// CONFIGURATION
// =============================================================================

rac_result_t rac_model_paths_set_base_dir(const char* base_dir) {
    if (!base_dir) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(g_paths_mutex);
    g_base_dir = base_dir;

    // Remove trailing slash if present
    while (!g_base_dir.empty() && (g_base_dir.back() == '/' || g_base_dir.back() == '\\')) {
        g_base_dir.pop_back();
    }

    return RAC_SUCCESS;
}

const char* rac_model_paths_get_base_dir(void) {
    // Use thread_local copy to avoid returning c_str() that dangles after mutex release.
    // Valid until the next call from the same thread.
    static thread_local std::string tl_base_dir;
    std::lock_guard<std::mutex> lock(g_paths_mutex);
    if (g_base_dir.empty()) {
        return nullptr;
    }
    tl_base_dir = g_base_dir;
    return tl_base_dir.c_str();
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

static rac_result_t copy_string_to_buffer(const std::string& src, char* out_path,
                                          size_t path_size) {
    if (!out_path || path_size == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (src.length() >= path_size) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    strncpy(out_path, src.c_str(), path_size - 1);
    out_path[path_size - 1] = '\0';
    return RAC_SUCCESS;
}

// Storage root under the configured base dir.
//
// Canonical layout is {base_dir}/RunAnywhere/... (Swift parity — every mobile
// SDK passes a sandbox root like the app Documents dir). Desktop consumers
// (rcli, Linux test rig, Playground tooling) standardize on a base dir that is
// ALREADY named "runanywhere" (~/.local/share/runanywhere), so re-appending the
// segment would double it ({...}/runanywhere/RunAnywhere/Models). When the last
// path component of base_dir is already "runanywhere" (case-insensitive), the
// base dir itself is the root. Mobile base dirs never end in "runanywhere", so
// their layout is unchanged. Agreed deviation from the original Swift port —
// see thoughts/shared/plans/rcli_desktop_cli.md.
static std::string runanywhere_root_locked() {
    const size_t sep = g_base_dir.find_last_of("/\\");
    std::string last = (sep == std::string::npos) ? g_base_dir : g_base_dir.substr(sep + 1);
    std::ranges::transform(last, last.begin(),
                           [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (last == "runanywhere") {
        return g_base_dir;
    }
    return g_base_dir + "/RunAnywhere";
}

static std::vector<std::string> split_path(const std::string& path) {
    std::vector<std::string> components;
    size_t start = 0;
    size_t end = 0;

    while ((end = path.find_first_of("/\\", start)) != std::string::npos) {
        if (end > start) {
            components.push_back(path.substr(start, end - start));
        }
        start = end + 1;
    }

    if (start < path.length()) {
        components.push_back(path.substr(start));
    }

    return components;
}

static std::string to_lower(std::string value) {
    std::ranges::transform(value, value.begin(),
                           [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return value;
}

static std::string filename_of(const fs::path& path) {
    return path.filename().generic_string();
}

static bool should_skip_model_entry(const fs::path& path) {
    std::string name = filename_of(path);
    if (name.empty())
        return true;
    if (name == "__MACOSX" || name == ".DS_Store")
        return true;
    if (name == rac_model_folder_manifest_filename())
        return true;  // registry metadata sidecar, never a model artifact
    if (name.size() >= 2 && name[0] == '.' && name[1] == '_')
        return true;
    return false;
}

static std::string normalize_slashes(std::string value) {
    std::ranges::replace(value, '\\', '/');
    return value;
}

static std::string relative_to_root(const fs::path& root, const fs::path& path) {
    std::error_code ec;
    fs::path rel = fs::relative(path, root, ec);
    if (ec) {
        return path.filename().generic_string();
    }
    return rel.generic_string();
}

static bool has_extension(const fs::path& path, const char* extension) {
    if (!extension)
        return false;
    std::string ext = to_lower(path.extension().generic_string());
    if (!ext.empty() && ext[0] == '.') {
        ext.erase(ext.begin());
    }
    return ext == extension;
}

static bool name_equals_any(const std::string& name, std::initializer_list<const char*> values) {
    for (const char* value : values) {
        if (value && name == value) {
            return true;
        }
    }
    return false;
}

static bool matches_model_format(const fs::path& path, rac_model_format_t format) {
    switch (format) {
        case RAC_MODEL_FORMAT_UNSPECIFIED:
        case RAC_MODEL_FORMAT_UNKNOWN:
            return has_extension(path, "gguf") || has_extension(path, "ggml") ||
                   has_extension(path, "onnx") || has_extension(path, "ort") ||
                   has_extension(path, "bin") || has_extension(path, "mlmodel") ||
                   has_extension(path, "mlpackage") || has_extension(path, "mlmodelc") ||
                   has_extension(path, "tflite") || has_extension(path, "safetensors") ||
                   has_extension(path, "zip");
        case RAC_MODEL_FORMAT_GGUF:
            return has_extension(path, "gguf");
        case RAC_MODEL_FORMAT_GGML:
            return has_extension(path, "ggml");
        case RAC_MODEL_FORMAT_ONNX:
            return has_extension(path, "onnx");
        case RAC_MODEL_FORMAT_ORT:
            return has_extension(path, "ort");
        case RAC_MODEL_FORMAT_BIN:
        case RAC_MODEL_FORMAT_QNN_CONTEXT:
            return has_extension(path, "bin");
        case RAC_MODEL_FORMAT_COREML:
            return has_extension(path, "mlmodelc") || has_extension(path, "mlmodel") ||
                   has_extension(path, "mlpackage");
        case RAC_MODEL_FORMAT_MLMODEL:
            return has_extension(path, "mlmodel");
        case RAC_MODEL_FORMAT_MLPACKAGE:
            return has_extension(path, "mlpackage");
        case RAC_MODEL_FORMAT_TFLITE:
            return has_extension(path, "tflite");
        case RAC_MODEL_FORMAT_SAFETENSORS:
            return has_extension(path, "safetensors");
        case RAC_MODEL_FORMAT_ZIP:
            return has_extension(path, "zip");
        case RAC_MODEL_FORMAT_FOLDER: {
            std::error_code ec;
            return fs::is_directory(path, ec);
        }
        case RAC_MODEL_FORMAT_PROPRIETARY:
            return false;
        default:
            return false;
    }
}

static rac_resolved_model_file_role_t infer_file_role(const fs::path& path,
                                                      rac_model_format_t format) {
    std::string name = to_lower(filename_of(path));
    if ((name.find("mmproj") != std::string::npos || name.find("mm-proj") != std::string::npos ||
         name.find("vision-projector") != std::string::npos ||
         name.find("vision_projector") != std::string::npos ||
         name.find("multimodal_projector") != std::string::npos ||
         name.find("multi-modal-projector") != std::string::npos) &&
        has_extension(path, "gguf")) {
        return RAC_RESOLVED_MODEL_FILE_ROLE_VISION_PROJECTOR;
    }
    if (name_equals_any(name, {"tokenizer.json", "tokenizer.model", "tokenizer_config.json",
                               "special_tokens_map.json", "added_tokens.json", "tokens.txt",
                               "sentencepiece.bpe.model", "spm.model"})) {
        return RAC_RESOLVED_MODEL_FILE_ROLE_TOKENIZER;
    }
    if (name_equals_any(name, {"vocab.txt", "vocab.json"})) {
        return RAC_RESOLVED_MODEL_FILE_ROLE_VOCABULARY;
    }
    if (name == "merges.txt") {
        return RAC_RESOLVED_MODEL_FILE_ROLE_MERGES;
    }
    if (name_equals_any(name, {"config.json", "generation_config.json", "preprocessor_config.json",
                               "processor_config.json", "image_processor_config.json",
                               "model_config.json"})) {
        return RAC_RESOLVED_MODEL_FILE_ROLE_CONFIG;
    }
    if (matches_model_format(path, format)) {
        return RAC_RESOLVED_MODEL_FILE_ROLE_PRIMARY;
    }
    return RAC_RESOLVED_MODEL_FILE_ROLE_COMPANION;
}

// Public single-file role inference. Mirrors the Swift reference
// RAModelFileRole+Inference.swift::inferModelFileRole(filename:modality:): a
// modality-keyed filename classifier returning a descriptor-role
// (rac_model_file_role_t / proto RAModelFileRole), distinct from the
// format-keyed scan-time infer_file_role() above which returns the
// resolved-role enum. Keyed on the proto ModelCategory value (so every SDK
// passes its generated ModelCategory raw value directly); the returned int is
// the proto RAModelFileRole value (identical to the rac_model_file_role_t
// ordinal). The vision-projector (mmproj) branch only fires for the
// multimodal category, matching the Swift source.
rac_result_t rac_infer_model_file_role(const char* filename, int32_t modality_proto,
                                       int32_t* out_role_proto) {
    if (!filename || !out_role_proto) {
        return RAC_ERROR_NULL_POINTER;
    }

    const std::string name = to_lower(filename_of(fs::path(filename)));

    rac_model_category_t category = RAC_MODEL_CATEGORY_UNKNOWN;
    (void)rac_model_category_from_proto(modality_proto, &category);

    if (category == RAC_MODEL_CATEGORY_MULTIMODAL &&
        (name.find("mmproj") != std::string::npos || name.find("mm-proj") != std::string::npos ||
         name.find("vision-projector") != std::string::npos ||
         name.find("vision_projector") != std::string::npos ||
         name.find("multimodal_projector") != std::string::npos ||
         name.find("multi-modal-projector") != std::string::npos) &&
        has_extension(fs::path(name), "gguf")) {
        *out_role_proto = RAC_MODEL_FILE_ROLE_VISION_PROJECTOR;
        return RAC_SUCCESS;
    }

    if (name_equals_any(name, {"tokenizer.json", "tokenizer.model", "tokenizer_config.json",
                               "special_tokens_map.json", "added_tokens.json", "tokens.txt",
                               "sentencepiece.bpe.model", "spm.model"})) {
        *out_role_proto = RAC_MODEL_FILE_ROLE_TOKENIZER;
        return RAC_SUCCESS;
    }
    if (name_equals_any(name, {"vocab.txt", "vocab.json"})) {
        *out_role_proto = RAC_MODEL_FILE_ROLE_VOCABULARY;
        return RAC_SUCCESS;
    }
    if (name == "merges.txt") {
        *out_role_proto = RAC_MODEL_FILE_ROLE_MERGES;
        return RAC_SUCCESS;
    }
    if (name_equals_any(name, {"config.json", "generation_config.json", "preprocessor_config.json",
                               "processor_config.json", "image_processor_config.json",
                               "model_config.json"})) {
        *out_role_proto = RAC_MODEL_FILE_ROLE_CONFIG;
        return RAC_SUCCESS;
    }

    *out_role_proto = RAC_MODEL_FILE_ROLE_PRIMARY_MODEL;
    return RAC_SUCCESS;
}

static bool glob_match_ci(const std::string& pattern_raw, const std::string& value_raw) {
    std::string pattern = to_lower(normalize_slashes(pattern_raw));
    std::string value = to_lower(normalize_slashes(value_raw));

    size_t p = 0;
    size_t v = 0;
    size_t star = std::string::npos;
    size_t star_match = 0;
    while (v < value.size()) {
        if (p < pattern.size() && (pattern[p] == '?' || pattern[p] == value[v])) {
            ++p;
            ++v;
        } else if (p < pattern.size() && pattern[p] == '*') {
            star = p++;
            star_match = v;
        } else if (star != std::string::npos) {
            p = star + 1;
            v = ++star_match;
        } else {
            return false;
        }
    }
    while (p < pattern.size() && pattern[p] == '*') {
        ++p;
    }
    return p == pattern.size();
}

struct scanned_file {
    fs::path path;
    std::string relative_path;
    rac_resolved_model_file_role_t role = RAC_RESOLVED_MODEL_FILE_ROLE_UNKNOWN;
};

static rac_resolved_model_file_role_t resolved_role_from_descriptor(rac_model_file_role_t role) {
    switch (role) {
        case RAC_MODEL_FILE_ROLE_PRIMARY_MODEL:
            return RAC_RESOLVED_MODEL_FILE_ROLE_PRIMARY;
        case RAC_MODEL_FILE_ROLE_VISION_PROJECTOR:
            return RAC_RESOLVED_MODEL_FILE_ROLE_VISION_PROJECTOR;
        case RAC_MODEL_FILE_ROLE_TOKENIZER:
            return RAC_RESOLVED_MODEL_FILE_ROLE_TOKENIZER;
        case RAC_MODEL_FILE_ROLE_CONFIG:
            return RAC_RESOLVED_MODEL_FILE_ROLE_CONFIG;
        case RAC_MODEL_FILE_ROLE_VOCABULARY:
            return RAC_RESOLVED_MODEL_FILE_ROLE_VOCABULARY;
        case RAC_MODEL_FILE_ROLE_MERGES:
            return RAC_RESOLVED_MODEL_FILE_ROLE_MERGES;
        case RAC_MODEL_FILE_ROLE_LABELS:
            return RAC_RESOLVED_MODEL_FILE_ROLE_LABELS;
        case RAC_MODEL_FILE_ROLE_COMPANION:
            return RAC_RESOLVED_MODEL_FILE_ROLE_COMPANION;
        case RAC_MODEL_FILE_ROLE_UNSPECIFIED:
        default:
            return RAC_RESOLVED_MODEL_FILE_ROLE_UNKNOWN;
    }
}

static bool file_matches_descriptor(const scanned_file& file,
                                    const rac_model_file_descriptor_t& descriptor) {
    std::string rel = to_lower(normalize_slashes(file.relative_path));
    std::string name = to_lower(filename_of(file.path));
    const char* raw = descriptor.destination_path && descriptor.destination_path[0] != '\0'
                          ? descriptor.destination_path
                          : descriptor.relative_path;
    if (!raw || raw[0] == '\0') {
        return false;
    }
    std::string expected = to_lower(normalize_slashes(raw));
    return rel == expected || name == expected || glob_match_ci(expected, rel) ||
           glob_match_ci(expected, name);
}

static void apply_descriptor_roles(std::vector<scanned_file>* files,
                                   const rac_model_artifact_info_t* artifact) {
    if (!files || !artifact || !artifact->file_descriptors) {
        return;
    }
    for (size_t i = 0; i < artifact->file_descriptor_count; ++i) {
        const rac_model_file_descriptor_t& descriptor = artifact->file_descriptors[i];
        const rac_resolved_model_file_role_t role = resolved_role_from_descriptor(descriptor.role);
        if (role == RAC_RESOLVED_MODEL_FILE_ROLE_UNKNOWN) {
            continue;
        }
        for (auto& file : *files) {
            if (file_matches_descriptor(file, descriptor)) {
                file.role = role;
                break;
            }
        }
    }
}

static std::vector<scanned_file> scan_model_files(const fs::path& root, rac_model_format_t format) {
    std::vector<scanned_file> files;
    std::error_code ec;
    if (fs::is_regular_file(root, ec)) {
        files.push_back({root, filename_of(root), infer_file_role(root, format)});
        return files;
    }
    if (!fs::is_directory(root, ec)) {
        return files;
    }

    fs::recursive_directory_iterator it(root, fs::directory_options::skip_permission_denied, ec);
    fs::recursive_directory_iterator end;
    while (!ec && it != end) {
        const fs::path current = it->path();
        if (should_skip_model_entry(current)) {
            if (it->is_directory(ec)) {
                it.disable_recursion_pending();
            }
            it.increment(ec);
            continue;
        }
        if (it->is_regular_file(ec)) {
            files.push_back(
                {current, relative_to_root(root, current), infer_file_role(current, format)});
        }
        it.increment(ec);
    }
    std::ranges::sort(files, [](const scanned_file& a, const scanned_file& b) {
        return a.relative_path < b.relative_path;
    });
    return files;
}

static fs::path effective_model_root(const fs::path& root, rac_model_format_t format) {
    std::error_code ec;
    if (!fs::is_directory(root, ec)) {
        return root;
    }

    bool has_direct_model_file = false;
    std::vector<fs::path> child_dirs;
    for (fs::directory_iterator it(root, fs::directory_options::skip_permission_denied, ec), end;
         !ec && it != end; it.increment(ec)) {
        fs::path child = it->path();
        if (should_skip_model_entry(child)) {
            continue;
        }
        if (it->is_regular_file(ec) && matches_model_format(child, format)) {
            has_direct_model_file = true;
        } else if (it->is_directory(ec)) {
            child_dirs.push_back(child);
        }
    }
    if (!has_direct_model_file && child_dirs.size() == 1) {
        return child_dirs.front();
    }
    return root;
}

static const scanned_file* find_primary_file(const std::vector<scanned_file>& files,
                                             const char* model_id, rac_model_format_t format) {
    const scanned_file* first_format_match = nullptr;
    std::string wanted_prefix = model_id ? to_lower(model_id) : "";
    const char* ext = rac_model_format_extension(format);

    for (const auto& file : files) {
        if (file.role == RAC_RESOLVED_MODEL_FILE_ROLE_VISION_PROJECTOR) {
            continue;
        }
        if (!matches_model_format(file.path, format)) {
            continue;
        }
        if (!first_format_match) {
            first_format_match = &file;
        }
        if (!wanted_prefix.empty()) {
            std::string name = to_lower(filename_of(file.path));
            std::string stem = to_lower(file.path.stem().generic_string());
            if (stem == wanted_prefix) {
                return &file;
            }
            if (ext) {
                std::string wanted = wanted_prefix + "." + ext;
                if (name == wanted) {
                    return &file;
                }
            }
        }
    }
    return first_format_match;
}

static char* dup_string(const std::string& value) {
    char* out = static_cast<char*>(malloc(value.size() + 1));
    if (!out)
        return nullptr;
    memcpy(out, value.c_str(), value.size() + 1);
    return out;
}

static int role_specificity(rac_resolved_model_file_role_t role) {
    switch (role) {
        case RAC_RESOLVED_MODEL_FILE_ROLE_PRIMARY:
            return 100;
        case RAC_RESOLVED_MODEL_FILE_ROLE_VISION_PROJECTOR:
        case RAC_RESOLVED_MODEL_FILE_ROLE_TOKENIZER:
        case RAC_RESOLVED_MODEL_FILE_ROLE_CONFIG:
        case RAC_RESOLVED_MODEL_FILE_ROLE_VOCABULARY:
        case RAC_RESOLVED_MODEL_FILE_ROLE_MERGES:
        case RAC_RESOLVED_MODEL_FILE_ROLE_LABELS:
            return 75;
        case RAC_RESOLVED_MODEL_FILE_ROLE_COMPANION:
            return 25;
        case RAC_RESOLVED_MODEL_FILE_ROLE_UNKNOWN:
        default:
            return 0;
    }
}

static int tokenizer_path_priority(rac_resolved_model_file_role_t role) {
    switch (role) {
        case RAC_RESOLVED_MODEL_FILE_ROLE_TOKENIZER:
            return 30;
        case RAC_RESOLVED_MODEL_FILE_ROLE_VOCABULARY:
            return 20;
        case RAC_RESOLVED_MODEL_FILE_ROLE_MERGES:
            return 10;
        default:
            return 0;
    }
}

static int tokenizer_path_priority_for_file(const fs::path& path,
                                            rac_resolved_model_file_role_t role) {
    std::string name = to_lower(filename_of(path));
    if (name_equals_any(name, {"tokenizer.json", "tokenizer.model", "sentencepiece.bpe.model",
                               "spm.model", "tokens.txt"})) {
        return 40;
    }
    if (name_equals_any(
            name, {"tokenizer_config.json", "special_tokens_map.json", "added_tokens.json"})) {
        return 30;
    }
    return tokenizer_path_priority(role);
}

static const scanned_file* find_matching_file(const std::vector<scanned_file>& files,
                                              const char* pattern) {
    if (!pattern || pattern[0] == '\0') {
        return nullptr;
    }
    for (const auto& file : files) {
        if (glob_match_ci(pattern, file.relative_path) ||
            glob_match_ci(pattern, filename_of(file.path))) {
            return &file;
        }
    }
    return nullptr;
}

static bool add_missing_required(rac_model_path_resolution_t* out, const std::string& value) {
    size_t next = out->missing_required_file_count + 1;
    char** resized = static_cast<char**>(
        realloc(static_cast<void*>(out->missing_required_files), next * sizeof(char*)));
    if (!resized)
        return false;
    out->missing_required_files = resized;
    out->missing_required_files[out->missing_required_file_count] = dup_string(value);
    if (!out->missing_required_files[out->missing_required_file_count])
        return false;
    out->missing_required_file_count = next;
    return true;
}

static bool append_resolved_file(rac_model_path_resolution_t* out, const std::string& rel,
                                 const std::string& path, rac_resolved_model_file_role_t role,
                                 rac_bool_t required, rac_bool_t exists) {
    size_t next = out->file_count + 1;
    auto* resized = static_cast<rac_resolved_model_file_t*>(
        realloc(out->files, next * sizeof(rac_resolved_model_file_t)));
    if (!resized)
        return false;
    out->files = resized;
    rac_resolved_model_file_t* file = &out->files[out->file_count];
    memset(file, 0, sizeof(*file));
    file->relative_path = dup_string(rel);
    file->path = dup_string(path);
    if (!file->relative_path || !file->path) {
        free(file->relative_path);
        free(file->path);
        memset(file, 0, sizeof(*file));
        return false;
    }
    file->role = role;
    file->is_required = required;
    file->exists = exists;
    out->file_count = next;
    return true;
}

static rac_resolved_model_file_t* find_resolved_file_by_path(rac_model_path_resolution_t* out,
                                                             const std::string& path) {
    if (!out) {
        return nullptr;
    }
    for (size_t i = 0; i < out->file_count; ++i) {
        if (out->files[i].path && path == out->files[i].path) {
            return &out->files[i];
        }
    }
    return nullptr;
}

static const rac_resolved_model_file_t*
find_resolved_file_by_path(const rac_model_path_resolution_t* out, const std::string& path) {
    if (!out) {
        return nullptr;
    }
    for (size_t i = 0; i < out->file_count; ++i) {
        if (out->files[i].path && path == out->files[i].path) {
            return &out->files[i];
        }
    }
    return nullptr;
}

static bool has_resolved_path(const rac_model_path_resolution_t* out, const std::string& path) {
    return find_resolved_file_by_path(out, path) != nullptr;
}

static void mark_resolved_file(rac_model_path_resolution_t* out, const std::string& path,
                               rac_resolved_model_file_role_t role, rac_bool_t required) {
    rac_resolved_model_file_t* file = find_resolved_file_by_path(out, path);
    if (!file) {
        return;
    }
    if (required == RAC_TRUE) {
        file->is_required = RAC_TRUE;
    }
    if (role_specificity(role) > role_specificity(file->role)) {
        file->role = role;
    }
}

static bool assign_owned_path(char** slot, const std::string& value) {
    char* copy = dup_string(value);
    if (!copy) {
        return false;
    }
    free(*slot);
    *slot = copy;
    return true;
}

// Minimal SHA-256 implementation for local primary-file validation.
struct sha256_ctx {
    std::array<uint32_t, 8> state{};
    std::array<uint8_t, 64> buffer{};
    uint64_t bit_len = 0;
    size_t buffer_len = 0;
};

static uint32_t rotr(uint32_t x, uint32_t n) {
    return (x >> n) | (x << (32 - n));
}

static void sha256_transform(sha256_ctx* ctx, const uint8_t data[64]) {
    static constexpr uint32_t k[64] = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2};
    uint32_t w[64];
    for (int i = 0; i < 16; ++i) {
        const size_t base = static_cast<size_t>(i) * 4;
        w[i] = (static_cast<uint32_t>(data[base]) << 24) |
               (static_cast<uint32_t>(data[base + 1]) << 16) |
               (static_cast<uint32_t>(data[base + 2]) << 8) | static_cast<uint32_t>(data[base + 3]);
    }
    for (int i = 16; i < 64; ++i) {
        uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    uint32_t a = ctx->state[0], b = ctx->state[1], c = ctx->state[2], d = ctx->state[3];
    uint32_t e = ctx->state[4], f = ctx->state[5], g = ctx->state[6], h = ctx->state[7];
    for (int i = 0; i < 64; ++i) {
        uint32_t s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t temp1 = h + s1 + ch + k[i] + w[i];
        uint32_t s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t temp2 = s0 + maj;
        h = g;
        g = f;
        f = e;
        e = d + temp1;
        d = c;
        c = b;
        b = a;
        a = temp1 + temp2;
    }
    ctx->state[0] += a;
    ctx->state[1] += b;
    ctx->state[2] += c;
    ctx->state[3] += d;
    ctx->state[4] += e;
    ctx->state[5] += f;
    ctx->state[6] += g;
    ctx->state[7] += h;
}

static void sha256_init(sha256_ctx* ctx) {
    ctx->state = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    ctx->bit_len = 0;
    ctx->buffer_len = 0;
}

static void sha256_update(sha256_ctx* ctx, const uint8_t* data, size_t len) {
    for (size_t i = 0; i < len; ++i) {
        ctx->buffer[ctx->buffer_len++] = data[i];
        if (ctx->buffer_len == 64) {
            sha256_transform(ctx, ctx->buffer.data());
            ctx->bit_len += 512;
            ctx->buffer_len = 0;
        }
    }
}

static std::string sha256_final_hex(sha256_ctx* ctx) {
    uint64_t total_bits = ctx->bit_len + ctx->buffer_len * 8;
    ctx->buffer[ctx->buffer_len++] = 0x80;
    if (ctx->buffer_len > 56) {
        while (ctx->buffer_len < 64) {
            ctx->buffer[ctx->buffer_len++] = 0;
        }
        sha256_transform(ctx, ctx->buffer.data());
        ctx->buffer_len = 0;
    }
    while (ctx->buffer_len < 56) {
        ctx->buffer[ctx->buffer_len++] = 0;
    }
    for (int i = 7; i >= 0; --i) {
        ctx->buffer[ctx->buffer_len++] = static_cast<uint8_t>((total_bits >> (i * 8)) & 0xff);
    }
    sha256_transform(ctx, ctx->buffer.data());

    static constexpr char hex[] = "0123456789abcdef";
    std::string out;
    out.reserve(64);
    for (uint32_t word : ctx->state) {
        for (int shift = 28; shift >= 0; shift -= 4) {
            out.push_back(hex[(word >> shift) & 0x0f]);
        }
    }
    return out;
}

static bool file_sha256_hex(const std::string& path, std::string* out_hex) {
    if (!out_hex)
        return false;
    std::ifstream input(path, std::ios::binary);
    if (!input.is_open())
        return false;
    sha256_ctx ctx;
    sha256_init(&ctx);
    std::array<char, 8192> buffer{};
    while (input.good()) {
        input.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
        std::streamsize n = input.gcount();
        if (n > 0) {
            sha256_update(&ctx, reinterpret_cast<const uint8_t*>(buffer.data()),
                          static_cast<size_t>(n));
        }
    }
    *out_hex = sha256_final_hex(&ctx);
    return true;
}

// =============================================================================
// FORMAT AND FRAMEWORK UTILITIES
// =============================================================================

// NOTE: rac_model_format_extension is defined in model_types.cpp

const char* rac_framework_raw_value(rac_inference_framework_t framework) {
    // Mirrors Swift's InferenceFramework.rawValue
    switch (framework) {
        case RAC_FRAMEWORK_ONNX:
            return "ONNX";
        case RAC_FRAMEWORK_SHERPA:
            return "Sherpa";
        case RAC_FRAMEWORK_LLAMACPP:
            return "LlamaCpp";
        case RAC_FRAMEWORK_COREML:
            return "CoreML";
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            return "FoundationModels";
        case RAC_FRAMEWORK_SYSTEM_TTS:
            return "SystemTTS";
        case RAC_FRAMEWORK_FLUID_AUDIO:
            return "FluidAudio";
        case RAC_FRAMEWORK_METALRT:
            return "MetalRT";
        case RAC_FRAMEWORK_GENIE:
            return "Genie";
        case RAC_FRAMEWORK_BUILTIN:
            return "BuiltIn";
        case RAC_FRAMEWORK_NONE:
            return "None";
        default:
            return "Unknown";
    }
}

const char* rac_model_folder_manifest_filename(void) {
    // Durable per-model registry sidecar written into the canonical model
    // folder on download completion (see model_registry_manifest.cpp). Dotted
    // so casual folder listings de-emphasize it; skipped by artifact scans via
    // should_skip_model_entry above.
    return ".rac-manifest.binpb";
}

// =============================================================================
// BASE DIRECTORIES
// =============================================================================

rac_result_t rac_model_paths_get_base_directory(char* out_path, size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getBaseDirectory()
    // Returns: {base_dir}/RunAnywhere/

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::string path = runanywhere_root_locked();
    return copy_string_to_buffer(path, out_path, path_size);
}

rac_result_t rac_model_paths_get_models_directory(char* out_path, size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getModelsDirectory()
    // Returns: {base_dir}/RunAnywhere/Models/

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::string path = runanywhere_root_locked() + "/Models";
    return copy_string_to_buffer(path, out_path, path_size);
}

// =============================================================================
// FRAMEWORK-SPECIFIC PATHS
// =============================================================================

rac_result_t rac_model_paths_get_framework_directory(rac_inference_framework_t framework,
                                                     char* out_path, size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getFrameworkDirectory(framework:)
    // Returns: {base_dir}/RunAnywhere/Models/{framework.rawValue}/

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::string path = runanywhere_root_locked() + "/Models/" + rac_framework_raw_value(framework);
    return copy_string_to_buffer(path, out_path, path_size);
}

rac_result_t rac_model_paths_get_model_folder(const char* model_id,
                                              rac_inference_framework_t framework, char* out_path,
                                              size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getModelFolder(modelId:framework:)
    // Returns: {base_dir}/RunAnywhere/Models/{framework.rawValue}/{modelId}/

    if (!is_safe_model_id_segment(model_id)) {
        RAC_LOG_WARNING("ModelPaths",
                        "Rejecting unsafe model_id for model folder construction "
                        "(security-privacy-storage-network-001-followup-model-id).");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::string path = runanywhere_root_locked() + "/Models/" + rac_framework_raw_value(framework) +
                       "/" + model_id;
    return copy_string_to_buffer(path, out_path, path_size);
}

// =============================================================================
// MODEL FILE PATHS
// =============================================================================

rac_result_t rac_model_paths_get_model_file_path(const char* model_id,
                                                 rac_inference_framework_t framework,
                                                 rac_model_format_t format, char* out_path,
                                                 size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getModelFilePath(modelId:framework:format:)
    // Returns:
    // {base_dir}/RunAnywhere/Models/{framework.rawValue}/{modelId}/{modelId}.{format.rawValue}

    if (!is_safe_model_id_segment(model_id)) {
        RAC_LOG_WARNING("ModelPaths",
                        "Rejecting unsafe model_id for model file path construction "
                        "(security-privacy-storage-network-001-followup-model-id).");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    const char* extension = rac_model_format_extension(format);
    if (!extension) {
        // Unknown format - return just the model folder path
        // The caller should search for model files in this folder
        RAC_LOG_WARNING("ModelPaths",
                        "Unknown model format (%d) for model '%s', returning folder path",
                        static_cast<int>(format), model_id);
        std::string path = runanywhere_root_locked() + "/Models/" +
                           rac_framework_raw_value(framework) + "/" + model_id;
        return copy_string_to_buffer(path, out_path, path_size);
    }

    std::string path = runanywhere_root_locked() + "/Models/" + rac_framework_raw_value(framework) +
                       "/" + model_id + "/" + model_id + "." + extension;
    return copy_string_to_buffer(path, out_path, path_size);
}

rac_result_t rac_model_paths_get_expected_model_path(const char* model_id,
                                                     rac_inference_framework_t framework,
                                                     rac_model_format_t format, char* out_path,
                                                     size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getExpectedModelPath(modelId:framework:format:)
    // For directory-based frameworks, returns the model folder
    // For single-file frameworks, returns the model file path

    if (!model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Check if framework uses directory-based models
    // (mirrors Swift's InferenceFramework.usesDirectoryBasedModels)
    if (rac_framework_uses_directory_based_models(framework) == RAC_TRUE) {
        return rac_model_paths_get_model_folder(model_id, framework, out_path, path_size);
    }

    return rac_model_paths_get_model_file_path(model_id, framework, format, out_path, path_size);
}

rac_result_t rac_model_paths_get_model_path(const rac_model_info_t* model_info, char* out_path,
                                            size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getModelPath(modelInfo:)

    if (!model_info || !model_info->id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    return rac_model_paths_get_model_file_path(model_info->id, model_info->framework,
                                               model_info->format, out_path, path_size);
}

// =============================================================================
// MODEL ARTIFACT RESOLUTION
// =============================================================================

void rac_model_path_resolution_free(rac_model_path_resolution_t* resolution) {
    if (!resolution)
        return;

    free(resolution->root_path);
    free(resolution->primary_model_path);
    free(resolution->mmproj_path);
    free(resolution->tokenizer_path);
    free(resolution->config_path);

    if (resolution->files) {
        for (size_t i = 0; i < resolution->file_count; ++i) {
            free(resolution->files[i].relative_path);
            free(resolution->files[i].path);
        }
        free(resolution->files);
    }

    if (resolution->missing_required_files) {
        for (size_t i = 0; i < resolution->missing_required_file_count; ++i) {
            free(resolution->missing_required_files[i]);
        }
        free(static_cast<void*>(resolution->missing_required_files));
    }

    memset(resolution, 0, sizeof(*resolution));
}

rac_result_t rac_model_paths_resolve_artifact(const rac_model_info_t* model_info,
                                              const char* artifact_root,
                                              const char* expected_primary_sha256,
                                              rac_model_path_resolution_t* out_resolution) {
    if (!model_info || !artifact_root || !out_resolution) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    memset(out_resolution, 0, sizeof(*out_resolution));

    std::error_code ec;
    fs::path input_root(artifact_root);
    if (!fs::exists(input_root, ec)) {
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    // Self-heal legacy registry entries that stored the mmproj .gguf as
    // local_path instead of the model folder (pre-fix archive extraction).
    if (fs::is_regular_file(input_root, ec)) {
        const std::string leaf = to_lower(filename_of(input_root));
        if (leaf.find("mmproj") != std::string::npos && has_extension(input_root, "gguf")) {
            input_root = input_root.parent_path();
        }
    }

    out_resolution->is_directory_based =
        rac_framework_uses_directory_based_models(model_info->framework);

    fs::path model_root = out_resolution->is_directory_based == RAC_TRUE
                              ? effective_model_root(input_root, model_info->format)
                              : input_root;
    std::vector<scanned_file> files = scan_model_files(model_root, model_info->format);
    apply_descriptor_roles(&files, &model_info->artifact_info);

    const scanned_file* primary_file = nullptr;
    if (fs::is_regular_file(model_root, ec)) {
        primary_file =
            (!files.empty() && matches_model_format(files.front().path, model_info->format))
                ? &files.front()
                : nullptr;
    } else if (out_resolution->is_directory_based != RAC_TRUE) {
        primary_file = find_primary_file(files, model_info->id, model_info->format);
    }

    if (out_resolution->is_directory_based == RAC_TRUE) {
        out_resolution->primary_model_path = dup_string(model_root.generic_string());
    } else if (primary_file) {
        out_resolution->primary_model_path = dup_string(primary_file->path.generic_string());
    } else {
        return RAC_ERROR_NOT_FOUND;
    }
    out_resolution->root_path = dup_string(model_root.generic_string());
    if (!out_resolution->root_path || !out_resolution->primary_model_path) {
        rac_model_path_resolution_free(out_resolution);
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    bool saw_primary_in_list = false;
    int tokenizer_priority = 0;
    for (const auto& file : files) {
        rac_resolved_model_file_role_t role = file.role;
        if (primary_file && file.path == primary_file->path) {
            role = RAC_RESOLVED_MODEL_FILE_ROLE_PRIMARY;
            saw_primary_in_list = true;
        }

        std::string abs = file.path.generic_string();
        if (!append_resolved_file(
                out_resolution, file.relative_path, abs, role,
                role == RAC_RESOLVED_MODEL_FILE_ROLE_PRIMARY ? RAC_TRUE : RAC_FALSE, RAC_TRUE)) {
            rac_model_path_resolution_free(out_resolution);
            return RAC_ERROR_OUT_OF_MEMORY;
        }

        if (role == RAC_RESOLVED_MODEL_FILE_ROLE_VISION_PROJECTOR && !out_resolution->mmproj_path) {
            if (!assign_owned_path(&out_resolution->mmproj_path, abs)) {
                rac_model_path_resolution_free(out_resolution);
                return RAC_ERROR_OUT_OF_MEMORY;
            }
        } else if ((role == RAC_RESOLVED_MODEL_FILE_ROLE_TOKENIZER ||
                    role == RAC_RESOLVED_MODEL_FILE_ROLE_VOCABULARY ||
                    role == RAC_RESOLVED_MODEL_FILE_ROLE_MERGES)) {
            int priority = tokenizer_path_priority_for_file(file.path, role);
            if (priority > tokenizer_priority) {
                if (!assign_owned_path(&out_resolution->tokenizer_path, abs)) {
                    rac_model_path_resolution_free(out_resolution);
                    return RAC_ERROR_OUT_OF_MEMORY;
                }
                tokenizer_priority = priority;
            }
        } else if (role == RAC_RESOLVED_MODEL_FILE_ROLE_CONFIG && !out_resolution->config_path) {
            if (!assign_owned_path(&out_resolution->config_path, abs)) {
                rac_model_path_resolution_free(out_resolution);
                return RAC_ERROR_OUT_OF_MEMORY;
            }
        }
    }

    if (out_resolution->is_directory_based != RAC_TRUE && primary_file && !saw_primary_in_list) {
        if (!append_resolved_file(out_resolution, primary_file->relative_path,
                                  primary_file->path.generic_string(),
                                  RAC_RESOLVED_MODEL_FILE_ROLE_PRIMARY, RAC_TRUE, RAC_TRUE)) {
            rac_model_path_resolution_free(out_resolution);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    const rac_model_artifact_info_t* artifact = &model_info->artifact_info;
    if (artifact->file_descriptors && artifact->file_descriptor_count > 0) {
        for (size_t i = 0; i < artifact->file_descriptor_count; ++i) {
            const rac_model_file_descriptor_t& descriptor = artifact->file_descriptors[i];
            const scanned_file* match = nullptr;
            for (const auto& file : files) {
                if (file_matches_descriptor(file, descriptor)) {
                    match = &file;
                    break;
                }
            }
            std::string expected =
                descriptor.destination_path && descriptor.destination_path[0] != '\0'
                    ? descriptor.destination_path
                    : (descriptor.relative_path ? descriptor.relative_path : "");
            if (!match && descriptor.is_required == RAC_TRUE) {
                if (!add_missing_required(out_resolution, expected)) {
                    rac_model_path_resolution_free(out_resolution);
                    return RAC_ERROR_OUT_OF_MEMORY;
                }
            } else if (match) {
                std::string path = match->path.generic_string();
                const rac_resolved_model_file_role_t descriptor_role =
                    resolved_role_from_descriptor(descriptor.role);
                const rac_resolved_model_file_role_t role =
                    descriptor_role == RAC_RESOLVED_MODEL_FILE_ROLE_UNKNOWN ? match->role
                                                                            : descriptor_role;
                if (has_resolved_path(out_resolution, path)) {
                    mark_resolved_file(out_resolution, path, role, descriptor.is_required);
                } else {
                    if (!append_resolved_file(out_resolution, match->relative_path, path, role,
                                              descriptor.is_required, RAC_TRUE)) {
                        rac_model_path_resolution_free(out_resolution);
                        return RAC_ERROR_OUT_OF_MEMORY;
                    }
                }
            }
        }
    }

    const rac_expected_model_files_t* expected = artifact->expected_files;
    if (expected) {
        for (size_t i = 0; i < expected->required_pattern_count; ++i) {
            const char* pattern =
                expected->required_patterns ? expected->required_patterns[i] : nullptr;
            const scanned_file* match = find_matching_file(files, pattern);
            if (!match) {
                if (!add_missing_required(out_resolution, pattern ? pattern : "")) {
                    rac_model_path_resolution_free(out_resolution);
                    return RAC_ERROR_OUT_OF_MEMORY;
                }
            } else {
                std::string path = match->path.generic_string();
                if (has_resolved_path(out_resolution, path)) {
                    mark_resolved_file(out_resolution, path, match->role, RAC_TRUE);
                } else {
                    if (!append_resolved_file(out_resolution, match->relative_path, path,
                                              match->role, RAC_TRUE, RAC_TRUE)) {
                        rac_model_path_resolution_free(out_resolution);
                        return RAC_ERROR_OUT_OF_MEMORY;
                    }
                }
            }
        }
        for (size_t i = 0; i < expected->optional_pattern_count; ++i) {
            const char* pattern =
                expected->optional_patterns ? expected->optional_patterns[i] : nullptr;
            const scanned_file* match = find_matching_file(files, pattern);
            if (match) {
                std::string path = match->path.generic_string();
                if (has_resolved_path(out_resolution, path)) {
                    mark_resolved_file(out_resolution, path, match->role, RAC_FALSE);
                } else {
                    if (!append_resolved_file(out_resolution, match->relative_path, path,
                                              match->role, RAC_FALSE, RAC_TRUE)) {
                        rac_model_path_resolution_free(out_resolution);
                        return RAC_ERROR_OUT_OF_MEMORY;
                    }
                }
            }
        }
    }

    if (expected_primary_sha256 && expected_primary_sha256[0] != '\0' &&
        out_resolution->is_directory_based != RAC_TRUE) {
        std::string actual;
        out_resolution->checksum_validated = RAC_TRUE;
        if (!file_sha256_hex(out_resolution->primary_model_path, &actual)) {
            out_resolution->checksum_matched = RAC_FALSE;
        } else {
            out_resolution->checksum_matched =
                to_lower(actual) == to_lower(expected_primary_sha256) ? RAC_TRUE : RAC_FALSE;
        }
    }

    out_resolution->is_complete = (out_resolution->missing_required_file_count == 0 &&
                                   (out_resolution->checksum_validated != RAC_TRUE ||
                                    out_resolution->checksum_matched == RAC_TRUE))
                                      ? RAC_TRUE
                                      : RAC_FALSE;

    if (out_resolution->is_complete != RAC_TRUE) {
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    }
    return RAC_SUCCESS;
}

// =============================================================================
// OTHER DIRECTORIES
// =============================================================================

rac_result_t rac_model_paths_get_cache_directory(char* out_path, size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getCacheDirectory()
    // Returns: {base_dir}/RunAnywhere/Cache/

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::string path = runanywhere_root_locked() + "/Cache";
    return copy_string_to_buffer(path, out_path, path_size);
}

rac_result_t rac_model_paths_get_temp_directory(char* out_path, size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getTempDirectory()
    // Returns: {base_dir}/RunAnywhere/Temp/

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::string path = runanywhere_root_locked() + "/Temp";
    return copy_string_to_buffer(path, out_path, path_size);
}

rac_result_t rac_model_paths_get_downloads_directory(char* out_path, size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getDownloadsDirectory()
    // Returns: {base_dir}/RunAnywhere/Downloads/

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::string path = runanywhere_root_locked() + "/Downloads";
    return copy_string_to_buffer(path, out_path, path_size);
}

// =============================================================================
// PATH ANALYSIS
// =============================================================================

rac_result_t rac_model_paths_extract_model_id(const char* path, char* out_model_id,
                                              size_t model_id_size) {
    // Mirrors Swift's ModelPathUtils.extractModelId(from:)

    if (!path) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::vector<std::string> components = split_path(path);

    // Find "Models" component
    auto it = std::ranges::find(components, "Models");
    if (it == components.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    auto modelsIndex = static_cast<size_t>(std::distance(components.begin(), it));

    // Check if there's a component after "Models"
    if (modelsIndex + 1 >= components.size()) {
        return RAC_ERROR_NOT_FOUND;
    }

    std::string nextComponent = components[modelsIndex + 1];

    // Check if next component is a framework name
    bool isFramework = false;
    // Must stay in sync with rac_framework_raw_value() above. Any framework
    // returned by rac_framework_raw_value MUST appear here; otherwise paths
    // under {Models}/{framework}/{id}/ will be parsed as direct
    // {Models}/{id}/ entries and model-id extraction will collapse to the
    // framework name (observed previously for Sherpa which was missing here).
    const char* frameworks[] = {"ONNX",      "Sherpa",     "LlamaCpp", "FoundationModels",
                                "SystemTTS", "FluidAudio", "BuiltIn",  "CoreML",
                                "MetalRT",   "Genie",      "None",     "Unknown"};
    for (const char* fw : frameworks) {
        if (nextComponent == fw) {
            isFramework = true;
            break;
        }
    }

    std::string modelId;
    if (isFramework && modelsIndex + 2 < components.size()) {
        // Framework structure: Models/framework/modelId
        modelId = components[modelsIndex + 2];
    } else {
        // Direct model folder structure: Models/modelId
        modelId = nextComponent;
    }

    if (out_model_id && model_id_size > 0) {
        return copy_string_to_buffer(modelId, out_model_id, model_id_size);
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_paths_extract_framework(const char* path,
                                               rac_inference_framework_t* out_framework) {
    // Mirrors Swift's ModelPathUtils.extractFramework(from:)

    if (!path || !out_framework) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::vector<std::string> components = split_path(path);

    // Find "Models" component
    auto it = std::ranges::find(components, "Models");
    if (it == components.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    auto modelsIndex = static_cast<size_t>(std::distance(components.begin(), it));

    // Check if there's a component after "Models"
    if (modelsIndex + 1 >= components.size()) {
        return RAC_ERROR_NOT_FOUND;
    }

    std::string nextComponent = components[modelsIndex + 1];

    // Map to framework enum. Must stay in sync with rac_framework_raw_value()
    // above. Every raw value it returns must map back here, otherwise the
    // reverse-lookup loses frameworks (e.g. Sherpa/CoreML were previously
    // missing and paths under `Models/Sherpa/<id>/` would not round-trip).
    if (nextComponent == "ONNX") {
        *out_framework = RAC_FRAMEWORK_ONNX;
        return RAC_SUCCESS;
    } else if (nextComponent == "Sherpa") {
        *out_framework = RAC_FRAMEWORK_SHERPA;
        return RAC_SUCCESS;
    } else if (nextComponent == "LlamaCpp") {
        *out_framework = RAC_FRAMEWORK_LLAMACPP;
        return RAC_SUCCESS;
    } else if (nextComponent == "CoreML") {
        *out_framework = RAC_FRAMEWORK_COREML;
        return RAC_SUCCESS;
    } else if (nextComponent == "FoundationModels") {
        *out_framework = RAC_FRAMEWORK_FOUNDATION_MODELS;
        return RAC_SUCCESS;
    } else if (nextComponent == "SystemTTS") {
        *out_framework = RAC_FRAMEWORK_SYSTEM_TTS;
        return RAC_SUCCESS;
    } else if (nextComponent == "FluidAudio") {
        *out_framework = RAC_FRAMEWORK_FLUID_AUDIO;
        return RAC_SUCCESS;
    } else if (nextComponent == "MetalRT") {
        *out_framework = RAC_FRAMEWORK_METALRT;
        return RAC_SUCCESS;
    } else if (nextComponent == "BuiltIn") {
        *out_framework = RAC_FRAMEWORK_BUILTIN;
        return RAC_SUCCESS;
    } else if (nextComponent == "None") {
        *out_framework = RAC_FRAMEWORK_NONE;
        return RAC_SUCCESS;
    } else if (nextComponent == "Genie") {
        *out_framework = RAC_FRAMEWORK_GENIE;
        return RAC_SUCCESS;
    }

    return RAC_ERROR_NOT_FOUND;
}

rac_bool_t rac_model_paths_is_model_path(const char* path) {
    // Mirrors Swift's ModelPathUtils.isModelPath(_:)

    if (!path) {
        return RAC_FALSE;
    }

    // Simply check if "Models" appears in the path
    return (strstr(path, "Models") != nullptr) ? RAC_TRUE : RAC_FALSE;
}
