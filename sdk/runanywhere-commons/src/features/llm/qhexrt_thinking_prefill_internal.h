#ifndef RAC_FEATURES_LLM_QHEXRT_THINKING_PREFILL_INTERNAL_H
#define RAC_FEATURES_LLM_QHEXRT_THINKING_PREFILL_INTERNAL_H

#include <algorithm>
#include <cctype>
#include <fstream>
#include <string>
#include <string_view>
#include <vector>

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"
#endif

#if defined(__cpp_lib_filesystem)
#include <filesystem>
namespace rac::llm::detail {
namespace fs = std::filesystem;
}
#else
#include <experimental/filesystem>
namespace rac::llm::detail {
namespace fs = std::experimental::filesystem;
}
#endif

namespace rac::llm {

#if defined(RAC_HAVE_PROTOBUF)

namespace detail {

inline bool ends_with_ci(std::string_view value, std::string_view suffix) {
    if (value.size() < suffix.size()) {
        return false;
    }
    for (size_t i = 0; i < suffix.size(); ++i) {
        const unsigned char a = static_cast<unsigned char>(value[value.size() - suffix.size() + i]);
        const unsigned char b = static_cast<unsigned char>(suffix[i]);
        if (std::tolower(a) != std::tolower(b)) {
            return false;
        }
    }
    return true;
}

inline bool is_aux_json_name(std::string_view name) {
    return name == "tokenizer.json" || name == "tokenizer_config.json" || name == "config.json" ||
           name == "generation_config.json" || name == "preprocessor_config.json";
}

// Bounded head read — same 8 KiB precedent as engines/qhexrt/qhexrt_diffusion_ops.cpp.
inline bool read_manifest_head(const std::string& path, std::string* out) {
    if (out == nullptr || path.empty()) {
        return false;
    }
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        return false;
    }
    char buf[8192];
    in.read(buf, static_cast<std::streamsize>(sizeof(buf) - 1));
    const std::streamsize n = in.gcount();
    if (n <= 0) {
        return false;
    }
    buf[static_cast<size_t>(n)] = '\0';
    out->assign(buf, static_cast<size_t>(n));
    return true;
}

inline bool looks_like_qhexrt_manifest_head(std::string_view head) {
    return head.find("schema_version") != std::string_view::npos ||
           head.find("\"plan\"") != std::string_view::npos ||
           head.find("dsp_arch") != std::string_view::npos;
}

inline std::string find_manifest_in_dir(const fs::path& dir) {
    std::error_code ec;
    if (!fs::is_directory(dir, ec)) {
        return {};
    }
    std::vector<fs::path> candidates;
    for (fs::directory_iterator it(dir, fs::directory_options::skip_permission_denied, ec), end;
         it != end && !ec; it.increment(ec)) {
        if (!it->is_regular_file(ec)) {
            continue;
        }
        const fs::path& p = it->path();
        const std::string name = p.filename().generic_string();
        if (!ends_with_ci(name, ".json") || is_aux_json_name(name)) {
            continue;
        }
        candidates.push_back(p);
    }
    std::sort(candidates.begin(), candidates.end());
    for (const auto& candidate : candidates) {
        std::string head;
        if (read_manifest_head(candidate.generic_string(), &head) &&
            looks_like_qhexrt_manifest_head(head)) {
            return candidate.generic_string();
        }
    }
    return {};
}

inline std::string resolve_qhexrt_manifest_path(const std::string& resolved_path) {
    if (resolved_path.empty()) {
        return {};
    }
    const fs::path p(resolved_path);
    std::error_code ec;
    if (fs::is_regular_file(p, ec)) {
        const std::string name = p.filename().generic_string();
        if (ends_with_ci(name, ".json") && !is_aux_json_name(name)) {
            std::string head;
            if (read_manifest_head(resolved_path, &head) && looks_like_qhexrt_manifest_head(head)) {
                return resolved_path;
            }
        }
        // Non-manifest file inside a bundle — recover from the parent directory.
        return find_manifest_in_dir(p.parent_path());
    }
    if (fs::is_directory(p, ec)) {
        return find_manifest_in_dir(p);
    }
    return {};
}

// Decode a JSON string literal body (between quotes), handling the \\uXXXX escapes
// we actually see in manifests (`\n`). Returns false on truncated/invalid input.
inline bool decode_json_string_body(std::string_view body, std::string* out) {
    if (out == nullptr) {
        return false;
    }
    out->clear();
    out->reserve(body.size());
    for (size_t i = 0; i < body.size(); ++i) {
        const char c = body[i];
        if (c != '\\') {
            out->push_back(c);
            continue;
        }
        if (i + 1 >= body.size()) {
            return false;
        }
        const char esc = body[++i];
        switch (esc) {
            case '"':
            case '\\':
            case '/':
                out->push_back(esc);
                break;
            case 'b':
                out->push_back('\b');
                break;
            case 'f':
                out->push_back('\f');
                break;
            case 'n':
                out->push_back('\n');
                break;
            case 'r':
                out->push_back('\r');
                break;
            case 't':
                out->push_back('\t');
                break;
            case 'u':
                // Manifests only need ASCII escapes for this field; skip the code unit.
                if (i + 4 >= body.size()) {
                    return false;
                }
                i += 4;
                break;
            default:
                return false;
        }
    }
    return true;
}

// Locate `"gen_prefill": "<value>"` in a bounded JSON head without a full parser.
// Distinguishes from `no_think_prefill` by matching the exact key.
inline bool extract_gen_prefill_value(std::string_view head, std::string* out_value,
                                      bool* out_key_present) {
    if (out_value == nullptr || out_key_present == nullptr) {
        return false;
    }
    out_value->clear();
    *out_key_present = false;
    constexpr std::string_view kKey = "\"gen_prefill\"";
    const size_t key_pos = head.find(kKey);
    if (key_pos == std::string_view::npos) {
        return false;
    }
    *out_key_present = true;
    size_t i = key_pos + kKey.size();
    while (i < head.size() && std::isspace(static_cast<unsigned char>(head[i]))) {
        ++i;
    }
    if (i >= head.size() || head[i] != ':') {
        return false;
    }
    ++i;
    while (i < head.size() && std::isspace(static_cast<unsigned char>(head[i]))) {
        ++i;
    }
    if (i >= head.size() || head[i] != '"') {
        return false;
    }
    ++i;
    const size_t begin = i;
    bool escaped = false;
    for (; i < head.size(); ++i) {
        const char c = head[i];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (c == '\\') {
            escaped = true;
            continue;
        }
        if (c == '"') {
            return decode_json_string_body(head.substr(begin, i - begin), out_value);
        }
    }
    return false;
}

inline bool gen_prefill_is_opening_think_tag(std::string_view value) {
    // Opening-tag prefills are `<think>` / `<thinking>` plus optional trailing
    // whitespace. A value that also closes the block (e.g. no_think shape) is
    // not an "open tag already emitted" signal.
    const bool has_open =
        value.find("<think>") != std::string_view::npos ||
        value.find("<thinking>") != std::string_view::npos;
    if (!has_open) {
        return false;
    }
    const bool has_close =
        value.find("</think>") != std::string_view::npos ||
        value.find("</thinking>") != std::string_view::npos;
    return !has_close;
}

// Mirrors QHexRT src/model.cpp default_chat_json: DeepSeek-R1-Distill gets
// assistant.gen_prefill = "<think>\n" when the shipped manifest omits chat.
inline bool deepseek_r1_distill_name_heuristic(const runanywhere::v1::ModelInfo& model) {
    const auto matches = [](std::string_view s) {
        return s.find("DeepSeek-R1-Distill") != std::string_view::npos ||
               s.find("deepseek_r1_distill") != std::string_view::npos ||
               s.find("deepseek-r1-distill") != std::string_view::npos;
    };
    return matches(model.id()) || matches(model.name());
}

}  // namespace detail

/**
 * Stamp ModelInfo.thinking_pattern.template_prefills_open_tag from the on-disk
 * QHexRT bundle manifest's chat.assistant.gen_prefill (or the DeepSeek-R1-Distill
 * name heuristic when the manifest carries no gen_prefill).
 *
 * Caller-declared has_template_prefills_open_tag wins and is never overwritten.
 * No-op when supports_thinking is false (normalize would clear the pattern).
 *
 * @return true when the ModelInfo was mutated.
 */
inline bool enrich_thinking_prefill_from_qhexrt_manifest(runanywhere::v1::ModelInfo* model,
                                                         const std::string& resolved_path) {
    if (model == nullptr || !model->supports_thinking()) {
        return false;
    }
    if (model->has_thinking_pattern() &&
        model->thinking_pattern().has_template_prefills_open_tag()) {
        return false;
    }

    bool set_true = false;
    bool saw_gen_prefill_key = false;
    const std::string manifest_path = detail::resolve_qhexrt_manifest_path(resolved_path);
    if (!manifest_path.empty()) {
        std::string head;
        if (detail::read_manifest_head(manifest_path, &head)) {
            std::string gen_prefill;
            if (detail::extract_gen_prefill_value(head, &gen_prefill, &saw_gen_prefill_key)) {
                set_true = detail::gen_prefill_is_opening_think_tag(gen_prefill);
            }
        }
    }

    if (!saw_gen_prefill_key && !set_true &&
        detail::deepseek_r1_distill_name_heuristic(*model)) {
        set_true = true;
    }

    if (!set_true) {
        return false;
    }

    auto* pattern = model->mutable_thinking_pattern();
    if (pattern->open_tag().empty()) {
        pattern->set_open_tag("<think>");
    }
    if (pattern->close_tag().empty()) {
        pattern->set_close_tag("</think>");
    }
    pattern->set_template_prefills_open_tag(true);
    return true;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace rac::llm

#endif  // RAC_FEATURES_LLM_QHEXRT_THINKING_PREFILL_INTERNAL_H
