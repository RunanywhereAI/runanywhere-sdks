// SPDX-License-Identifier: Apache-2.0
//
// config_loader.cpp — T4.7 proto-bytes + minimal YAML loaders.
//
// YAML subset supported
// ---------------------
// The parser deliberately implements a small subset of YAML that is
// nonetheless sufficient for every field in pipeline.proto and
// solutions.proto. Supported features:
//
//   * Block mappings — `key: value` per line, deeper indent implies a
//     nested mapping.
//   * Block sequences — `- item` per line, deeper indent implies a
//     nested mapping as the sequence element.
//   * Scalar values — bare or single/double-quoted strings, integers,
//     floats, booleans (`true` / `false`).
//   * Comments — from `#` to end of line.
//
// Unsupported (and intentionally so, to keep the parser ~250 LoC):
//   * Flow style (`{a: 1, b: 2}`, `[1, 2]`)
//   * Anchors/aliases, folded/literal block scalars, tags.
//   * Multi-document streams.
//
// The parser emits a generic YamlNode tree (scalar / sequence /
// mapping) which the translation layer below maps into the proto
// fields we care about. Unknown keys are ignored with a warning-style
// detail message so frontends can evolve without breaking the loader.

#include "rac/solutions/config_loader.hpp"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <memory>
#include <sstream>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <variant>
#include <vector>

#include "pipeline.pb.h"
#include "rac/core/rac_error.h"
#include "solutions.pb.h"

namespace rac::solutions {

namespace {

// ===========================================================================
// YAML NODE MODEL
// ===========================================================================

struct YamlNode;
using YamlNodePtr = std::shared_ptr<YamlNode>;

struct YamlNode {
    enum class Kind { Scalar, Sequence, Mapping };
    Kind kind = Kind::Scalar;

    std::string                                     scalar;
    std::vector<YamlNodePtr>                        sequence;
    std::vector<std::pair<std::string, YamlNodePtr>> mapping;

    static YamlNodePtr make_scalar(std::string v) {
        auto n = std::make_shared<YamlNode>();
        n->kind = Kind::Scalar;
        n->scalar = std::move(v);
        return n;
    }
    static YamlNodePtr make_sequence() {
        auto n = std::make_shared<YamlNode>();
        n->kind = Kind::Sequence;
        return n;
    }
    static YamlNodePtr make_mapping() {
        auto n = std::make_shared<YamlNode>();
        n->kind = Kind::Mapping;
        return n;
    }

    YamlNodePtr find(std::string_view key) const {
        if (kind != Kind::Mapping) return nullptr;
        for (const auto& [k, v] : mapping) {
            if (k == key) return v;
        }
        return nullptr;
    }
};

// ===========================================================================
// YAML PARSER
// ===========================================================================

class YamlParser {
public:
    explicit YamlParser(const std::string& text) {
        // Split into raw lines, stripping comments and trailing WS.
        std::istringstream in(text);
        std::string        line;
        while (std::getline(in, line)) {
            // Strip comments (outside of quotes). Tracking quote state
            // keeps us honest for strings containing '#'.
            std::string clean;
            bool in_sq = false, in_dq = false;
            for (size_t i = 0; i < line.size(); ++i) {
                char c = line[i];
                if (!in_dq && c == '\'') { in_sq = !in_sq; clean.push_back(c); continue; }
                if (!in_sq && c == '"')  { in_dq = !in_dq; clean.push_back(c); continue; }
                if (!in_sq && !in_dq && c == '#') break;
                clean.push_back(c);
            }
            // Trim trailing WS.
            while (!clean.empty() && (clean.back() == ' ' || clean.back() == '\t'
                                     || clean.back() == '\r')) {
                clean.pop_back();
            }
            lines_.push_back(std::move(clean));
        }
    }

    YamlNodePtr parse(std::string* err) {
        size_t idx = 0;
        // Skip leading blanks.
        while (idx < lines_.size() && is_blank(lines_[idx])) ++idx;
        if (idx >= lines_.size()) return YamlNode::make_mapping();
        const int base_indent = leading_spaces(lines_[idx]);
        return parse_block(idx, base_indent, err);
    }

private:
    std::vector<std::string> lines_;

    static bool is_blank(const std::string& s) {
        for (char c : s) {
            if (c != ' ' && c != '\t') return false;
        }
        return true;
    }

    static int leading_spaces(const std::string& s) {
        int n = 0;
        for (char c : s) {
            if (c == ' ') ++n;
            else if (c == '\t') n += 2;  // tolerate tabs as 2 spaces
            else break;
        }
        return n;
    }

    static std::string strip(const std::string& s) {
        size_t a = 0;
        while (a < s.size() && (s[a] == ' ' || s[a] == '\t')) ++a;
        size_t b = s.size();
        while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\t')) --b;
        return s.substr(a, b - a);
    }

    static std::string unquote(const std::string& s) {
        if (s.size() >= 2 &&
            ((s.front() == '"' && s.back() == '"') ||
             (s.front() == '\'' && s.back() == '\''))) {
            return s.substr(1, s.size() - 2);
        }
        return s;
    }

    /// Parse the block starting at `idx` whose first line has indent
    /// >= base_indent. Advances idx past the consumed region.
    YamlNodePtr parse_block(size_t& idx, int base_indent, std::string* err) {
        // Skip blank lines.
        while (idx < lines_.size() && is_blank(lines_[idx])) ++idx;
        if (idx >= lines_.size()) return YamlNode::make_mapping();

        const std::string& first = lines_[idx];
        const int          indent = leading_spaces(first);
        if (indent < base_indent) return YamlNode::make_mapping();

        const std::string trimmed = strip(first);
        if (trimmed.rfind("- ", 0) == 0 || trimmed == "-") {
            return parse_sequence(idx, indent, err);
        }
        return parse_mapping(idx, indent, err);
    }

    YamlNodePtr parse_sequence(size_t& idx, int indent, std::string* err) {
        auto node = YamlNode::make_sequence();
        while (idx < lines_.size()) {
            if (is_blank(lines_[idx])) { ++idx; continue; }
            const int line_indent = leading_spaces(lines_[idx]);
            if (line_indent < indent) break;
            if (line_indent > indent) break;  // shouldn't happen at this level

            const std::string trimmed = strip(lines_[idx]);
            if (trimmed.rfind("- ", 0) != 0 && trimmed != "-") break;

            std::string after = trimmed.size() > 1 ? strip(trimmed.substr(1))
                                                  : std::string();
            ++idx;

            // Three flavours: "- scalar", "- key: value" (inline map
            // starting element), or "-" followed by indented block.
            if (!after.empty()) {
                auto colon = after.find(':');
                if (colon != std::string::npos) {
                    // Element is a mapping. Re-emit the current key/value
                    // pair and let parse_mapping handle the remainder.
                    auto map = YamlNode::make_mapping();
                    std::string key = strip(after.substr(0, colon));
                    std::string val = strip(after.substr(colon + 1));
                    if (val.empty()) {
                        // Nested block: child lines belong to this key.
                        YamlNodePtr child;
                        if (idx < lines_.size()
                            && !is_blank(lines_[idx])
                            && leading_spaces(lines_[idx]) > indent) {
                            child = parse_block(idx,
                                                leading_spaces(lines_[idx]),
                                                err);
                        } else {
                            child = YamlNode::make_mapping();
                        }
                        map->mapping.emplace_back(std::move(key),
                                                  std::move(child));
                    } else {
                        map->mapping.emplace_back(
                            std::move(key),
                            YamlNode::make_scalar(unquote(std::move(val))));
                    }
                    // Continue parsing additional keys that belong to
                    // the same sequence element (indent > list indent).
                    while (idx < lines_.size()) {
                        if (is_blank(lines_[idx])) { ++idx; continue; }
                        const int ii = leading_spaces(lines_[idx]);
                        const std::string tt = strip(lines_[idx]);
                        if (ii <= indent || tt.rfind("- ", 0) == 0
                                          || tt == "-") {
                            break;
                        }
                        // Sub-key of the same element.
                        auto cc = tt.find(':');
                        if (cc == std::string::npos) { ++idx; continue; }
                        std::string k2 = strip(tt.substr(0, cc));
                        std::string v2 = strip(tt.substr(cc + 1));
                        ++idx;
                        if (v2.empty()) {
                            YamlNodePtr child;
                            if (idx < lines_.size()
                                && !is_blank(lines_[idx])
                                && leading_spaces(lines_[idx]) > ii) {
                                child = parse_block(idx,
                                                    leading_spaces(lines_[idx]),
                                                    err);
                            } else {
                                child = YamlNode::make_mapping();
                            }
                            map->mapping.emplace_back(std::move(k2),
                                                      std::move(child));
                        } else {
                            map->mapping.emplace_back(
                                std::move(k2),
                                YamlNode::make_scalar(unquote(std::move(v2))));
                        }
                    }
                    node->sequence.push_back(std::move(map));
                } else {
                    node->sequence.push_back(
                        YamlNode::make_scalar(unquote(std::move(after))));
                }
            } else {
                // Bare "-"; child block below.
                if (idx < lines_.size()
                    && !is_blank(lines_[idx])
                    && leading_spaces(lines_[idx]) > indent) {
                    node->sequence.push_back(
                        parse_block(idx, leading_spaces(lines_[idx]), err));
                } else {
                    node->sequence.push_back(YamlNode::make_scalar(""));
                }
            }
        }
        return node;
    }

    YamlNodePtr parse_mapping(size_t& idx, int indent, std::string* err) {
        auto node = YamlNode::make_mapping();
        while (idx < lines_.size()) {
            if (is_blank(lines_[idx])) { ++idx; continue; }
            const int         line_indent = leading_spaces(lines_[idx]);
            if (line_indent < indent) break;
            if (line_indent > indent) {
                // Orphan indentation — bail out; caller handles.
                if (err) *err = "unexpected indentation";
                return node;
            }
            const std::string trimmed = strip(lines_[idx]);
            if (trimmed.rfind("- ", 0) == 0 || trimmed == "-") break;
            auto colon = trimmed.find(':');
            if (colon == std::string::npos) {
                ++idx;
                continue;
            }
            std::string key = strip(trimmed.substr(0, colon));
            std::string val = strip(trimmed.substr(colon + 1));
            ++idx;
            if (!val.empty()) {
                node->mapping.emplace_back(
                    std::move(key),
                    YamlNode::make_scalar(unquote(std::move(val))));
            } else {
                // Child block.
                YamlNodePtr child;
                if (idx < lines_.size()
                    && !is_blank(lines_[idx])
                    && leading_spaces(lines_[idx]) > indent) {
                    child = parse_block(idx, leading_spaces(lines_[idx]), err);
                } else {
                    child = YamlNode::make_mapping();
                }
                node->mapping.emplace_back(std::move(key), std::move(child));
            }
        }
        return node;
    }
};

// ===========================================================================
// YAML → PROTO MAPPING
// ===========================================================================

static int to_int(const std::string& s, int fallback = 0) {
    try { return std::stoi(s); } catch (...) { return fallback; }
}
static float to_float(const std::string& s, float fallback = 0.0f) {
    try { return std::stof(s); } catch (...) { return fallback; }
}
static bool to_bool(const std::string& s) {
    std::string lower; lower.reserve(s.size());
    for (char c : s) lower.push_back(static_cast<char>(std::tolower(c)));
    return lower == "true" || lower == "yes" || lower == "1" || lower == "on";
}

runanywhere::v1::DeviceAffinity parse_device(const std::string& s) {
    using runanywhere::v1::DeviceAffinity;
    std::string lower; for (char c : s) lower.push_back(static_cast<char>(std::tolower(c)));
    if (lower == "cpu") return DeviceAffinity::DEVICE_AFFINITY_CPU;
    if (lower == "gpu") return DeviceAffinity::DEVICE_AFFINITY_GPU;
    if (lower == "ane" || lower == "npu")
        return DeviceAffinity::DEVICE_AFFINITY_ANE;
    if (lower == "any") return DeviceAffinity::DEVICE_AFFINITY_ANY;
    return DeviceAffinity::DEVICE_AFFINITY_UNSPECIFIED;
}

runanywhere::v1::EdgePolicy parse_policy(const std::string& s) {
    using runanywhere::v1::EdgePolicy;
    if (s == "block")       return EdgePolicy::EDGE_POLICY_BLOCK;
    if (s == "drop_oldest") return EdgePolicy::EDGE_POLICY_DROP_OLDEST;
    if (s == "drop_newest") return EdgePolicy::EDGE_POLICY_DROP_NEWEST;
    return EdgePolicy::EDGE_POLICY_UNSPECIFIED;
}

void populate_operator(const YamlNode& node,
                       runanywhere::v1::OperatorSpec* op) {
    if (auto n = node.find("name"))          op->set_name(n->scalar);
    if (auto n = node.find("type"))          op->set_type(n->scalar);
    if (auto n = node.find("pinned_engine")) op->set_pinned_engine(n->scalar);
    if (auto n = node.find("model_id"))      op->set_model_id(n->scalar);
    if (auto n = node.find("device"))        op->set_device(parse_device(n->scalar));
    if (auto params = node.find("params");
        params && params->kind == YamlNode::Kind::Mapping) {
        for (const auto& [k, v] : params->mapping) {
            if (v && v->kind == YamlNode::Kind::Scalar) {
                (*op->mutable_params())[k] = v->scalar;
            }
        }
    }
}

void populate_edge(const YamlNode& node, runanywhere::v1::EdgeSpec* edge) {
    if (auto n = node.find("from"))     edge->set_from(n->scalar);
    if (auto n = node.find("to"))       edge->set_to(n->scalar);
    if (auto n = node.find("capacity")) edge->set_capacity(
        static_cast<uint32_t>(std::max(0, to_int(n->scalar))));
    if (auto n = node.find("policy"))   edge->set_policy(parse_policy(n->scalar));
}

void populate_options(const YamlNode& node,
                      runanywhere::v1::PipelineOptions* opts) {
    if (auto n = node.find("latency_budget_ms")) {
        opts->set_latency_budget_ms(to_int(n->scalar));
    }
    if (auto n = node.find("emit_metrics")) {
        opts->set_emit_metrics(to_bool(n->scalar));
    }
    if (auto n = node.find("strict_validation")) {
        opts->set_strict_validation(to_bool(n->scalar));
    }
}

rac_result_t populate_pipeline(const YamlNode& root,
                               runanywhere::v1::PipelineSpec* spec) {
    if (root.kind != YamlNode::Kind::Mapping) {
        rac_error_set_details("YAML root must be a mapping");
        return RAC_ERROR_INVALID_FORMAT;
    }
    if (auto n = root.find("name")) spec->set_name(n->scalar);
    if (auto operators = root.find("operators");
        operators && operators->kind == YamlNode::Kind::Sequence) {
        for (const auto& item : operators->sequence) {
            if (!item || item->kind != YamlNode::Kind::Mapping) continue;
            populate_operator(*item, spec->add_operators());
        }
    }
    if (auto edges = root.find("edges");
        edges && edges->kind == YamlNode::Kind::Sequence) {
        for (const auto& item : edges->sequence) {
            if (!item || item->kind != YamlNode::Kind::Mapping) continue;
            populate_edge(*item, spec->add_edges());
        }
    }
    if (auto opts = root.find("options");
        opts && opts->kind == YamlNode::Kind::Mapping) {
        populate_options(*opts, spec->mutable_options());
    }
    return RAC_SUCCESS;
}

// ---------------------------------------------------------------------------
// Solution-specific populators. Each mirrors the fields declared in
// solutions.proto for the corresponding oneof arm.
// ---------------------------------------------------------------------------

runanywhere::v1::AudioSource parse_audio_source(const std::string& s) {
    using runanywhere::v1::AudioSource;
    if (s == "microphone" || s == "mic") return AudioSource::AUDIO_SOURCE_MICROPHONE;
    if (s == "file")                     return AudioSource::AUDIO_SOURCE_FILE;
    if (s == "callback")                 return AudioSource::AUDIO_SOURCE_CALLBACK;
    return AudioSource::AUDIO_SOURCE_UNSPECIFIED;
}

void populate_voice_agent(const YamlNode& node,
                          runanywhere::v1::VoiceAgentConfig* cfg) {
    if (auto n = node.find("llm_model_id")) cfg->set_llm_model_id(n->scalar);
    if (auto n = node.find("stt_model_id")) cfg->set_stt_model_id(n->scalar);
    if (auto n = node.find("tts_model_id")) cfg->set_tts_model_id(n->scalar);
    if (auto n = node.find("vad_model_id")) cfg->set_vad_model_id(n->scalar);
    if (auto n = node.find("sample_rate_hz"))
        cfg->set_sample_rate_hz(to_int(n->scalar, 16000));
    if (auto n = node.find("chunk_ms"))
        cfg->set_chunk_ms(to_int(n->scalar, 20));
    if (auto n = node.find("audio_source"))
        cfg->set_audio_source(parse_audio_source(n->scalar));
    if (auto n = node.find("audio_file_path"))
        cfg->set_audio_file_path(n->scalar);
    if (auto n = node.find("enable_barge_in"))
        cfg->set_enable_barge_in(to_bool(n->scalar));
    if (auto n = node.find("barge_in_threshold_ms"))
        cfg->set_barge_in_threshold_ms(to_int(n->scalar));
    if (auto n = node.find("system_prompt"))
        cfg->set_system_prompt(n->scalar);
    if (auto n = node.find("max_context_tokens"))
        cfg->set_max_context_tokens(to_int(n->scalar));
    if (auto n = node.find("temperature"))
        cfg->set_temperature(to_float(n->scalar));
    if (auto n = node.find("emit_partials"))
        cfg->set_emit_partials(to_bool(n->scalar));
    if (auto n = node.find("emit_thoughts"))
        cfg->set_emit_thoughts(to_bool(n->scalar));
}

runanywhere::v1::VectorStore parse_vector_store(const std::string& s) {
    using runanywhere::v1::VectorStore;
    if (s == "usearch")  return VectorStore::VECTOR_STORE_USEARCH;
    if (s == "pgvector") return VectorStore::VECTOR_STORE_PGVECTOR;
    return VectorStore::VECTOR_STORE_UNSPECIFIED;
}

void populate_rag(const YamlNode& node, runanywhere::v1::RAGConfig* cfg) {
    if (auto n = node.find("embed_model_id"))  cfg->set_embed_model_id(n->scalar);
    if (auto n = node.find("rerank_model_id")) cfg->set_rerank_model_id(n->scalar);
    if (auto n = node.find("llm_model_id"))    cfg->set_llm_model_id(n->scalar);
    if (auto n = node.find("vector_store"))
        cfg->set_vector_store(parse_vector_store(n->scalar));
    if (auto n = node.find("vector_store_path"))
        cfg->set_vector_store_path(n->scalar);
    if (auto n = node.find("retrieve_k")) cfg->set_retrieve_k(to_int(n->scalar));
    if (auto n = node.find("rerank_top")) cfg->set_rerank_top(to_int(n->scalar));
    if (auto n = node.find("bm25_k1"))    cfg->set_bm25_k1(to_float(n->scalar));
    if (auto n = node.find("bm25_b"))     cfg->set_bm25_b(to_float(n->scalar));
    if (auto n = node.find("rrf_k"))      cfg->set_rrf_k(to_int(n->scalar));
    if (auto n = node.find("prompt_template"))
        cfg->set_prompt_template(n->scalar);
}

void populate_wake_word(const YamlNode& node,
                        runanywhere::v1::WakeWordConfig* cfg) {
    if (auto n = node.find("model_id"))     cfg->set_model_id(n->scalar);
    if (auto n = node.find("keyword"))      cfg->set_keyword(n->scalar);
    if (auto n = node.find("threshold"))    cfg->set_threshold(to_float(n->scalar));
    if (auto n = node.find("pre_roll_ms"))  cfg->set_pre_roll_ms(to_int(n->scalar));
    if (auto n = node.find("sample_rate_hz"))
        cfg->set_sample_rate_hz(to_int(n->scalar, 16000));
}

rac_result_t populate_solution(const YamlNode& root,
                               runanywhere::v1::SolutionConfig* cfg) {
    if (root.kind != YamlNode::Kind::Mapping) {
        rac_error_set_details("YAML root must be a mapping");
        return RAC_ERROR_INVALID_FORMAT;
    }
    if (auto n = root.find("voice_agent");
        n && n->kind == YamlNode::Kind::Mapping) {
        populate_voice_agent(*n, cfg->mutable_voice_agent());
        return RAC_SUCCESS;
    }
    if (auto n = root.find("rag"); n && n->kind == YamlNode::Kind::Mapping) {
        populate_rag(*n, cfg->mutable_rag());
        return RAC_SUCCESS;
    }
    if (auto n = root.find("wake_word"); n && n->kind == YamlNode::Kind::Mapping) {
        populate_wake_word(*n, cfg->mutable_wake_word());
        return RAC_SUCCESS;
    }
    rac_error_set_details(
        "SolutionConfig YAML must declare one of: voice_agent, rag, wake_word");
    return RAC_ERROR_INVALID_FORMAT;
}

}  // namespace

// ===========================================================================
// PUBLIC API
// ===========================================================================

rac_result_t load_pipeline_from_proto_bytes(const void* data, size_t len,
                                            runanywhere::v1::PipelineSpec* out_spec) {
    if (!out_spec)              return RAC_ERROR_INVALID_ARGUMENT;
    if (!data && len > 0)       return RAC_ERROR_INVALID_ARGUMENT;
    out_spec->Clear();
    if (!out_spec->ParseFromArray(data, static_cast<int>(len))) {
        rac_error_set_details("failed to decode PipelineSpec proto bytes");
        return RAC_ERROR_DECODING_ERROR;
    }
    return RAC_SUCCESS;
}

rac_result_t load_solution_from_proto_bytes(const void* data, size_t len,
                                            runanywhere::v1::SolutionConfig* out_config) {
    if (!out_config)            return RAC_ERROR_INVALID_ARGUMENT;
    if (!data && len > 0)       return RAC_ERROR_INVALID_ARGUMENT;
    out_config->Clear();
    if (!out_config->ParseFromArray(data, static_cast<int>(len))) {
        rac_error_set_details("failed to decode SolutionConfig proto bytes");
        return RAC_ERROR_DECODING_ERROR;
    }
    return RAC_SUCCESS;
}

rac_result_t load_pipeline_from_yaml(const std::string& yaml,
                                     runanywhere::v1::PipelineSpec* out_spec) {
    if (!out_spec) return RAC_ERROR_INVALID_ARGUMENT;
    out_spec->Clear();
    YamlParser  parser(yaml);
    std::string err;
    auto        root = parser.parse(&err);
    if (!err.empty()) {
        rac_error_set_details(("YAML parse error: " + err).c_str());
        return RAC_ERROR_INVALID_FORMAT;
    }
    if (!root) {
        rac_error_set_details("YAML parse produced null root");
        return RAC_ERROR_INVALID_FORMAT;
    }
    return populate_pipeline(*root, out_spec);
}

rac_result_t load_solution_from_yaml(const std::string& yaml,
                                     runanywhere::v1::SolutionConfig* out_config) {
    if (!out_config) return RAC_ERROR_INVALID_ARGUMENT;
    out_config->Clear();
    YamlParser  parser(yaml);
    std::string err;
    auto        root = parser.parse(&err);
    if (!err.empty()) {
        rac_error_set_details(("YAML parse error: " + err).c_str());
        return RAC_ERROR_INVALID_FORMAT;
    }
    if (!root) {
        rac_error_set_details("YAML parse produced null root");
        return RAC_ERROR_INVALID_FORMAT;
    }
    return populate_solution(*root, out_config);
}

}  // namespace rac::solutions
