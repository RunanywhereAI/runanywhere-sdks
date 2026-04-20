// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_structured.h"

#include <cstdlib>
#include <cstring>
#include <sstream>
#include <string>
#include <string_view>

#include "structured_output.h"

namespace {

char* dup_cstr(std::string_view s) {
    char* out = static_cast<char*>(std::malloc(s.size() + 1));
    if (!out) return nullptr;
    if (!s.empty()) std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

int32_t find_matching(const char* text, int32_t open_offset, char open_ch, char close_ch) {
    if (!text || open_offset < 0) return -1;
    const std::size_t len = std::strlen(text);
    if (static_cast<std::size_t>(open_offset) >= len) return -1;
    if (text[open_offset] != open_ch) return -1;
    int depth = 0;
    bool in_str = false;
    bool escape = false;
    for (std::size_t i = open_offset; i < len; ++i) {
        const char c = text[i];
        if (in_str) {
            if (escape) escape = false;
            else if (c == '\\') escape = true;
            else if (c == '"') in_str = false;
        } else if (c == '"') {
            in_str = true;
        } else if (c == open_ch) {
            ++depth;
        } else if (c == close_ch) {
            if (--depth == 0) return static_cast<int32_t>(i);
        }
    }
    return -1;
}

}  // namespace

extern "C" {

ra_status_t ra_structured_output_extract_json(const char* text, char** out_json) {
    if (!text || !out_json) return RA_ERR_INVALID_ARGUMENT;
    auto extracted = ra::core::util::extract_json(text);
    if (!extracted) return RA_ERR_INVALID_ARGUMENT;
    *out_json = dup_cstr(*extracted);
    return *out_json ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

int32_t ra_structured_output_find_complete_json(const char* text, int32_t offset) {
    if (!text || offset < 0) return -1;
    const std::size_t len = std::strlen(text);
    if (static_cast<std::size_t>(offset) >= len) return -1;
    auto extracted = ra::core::util::extract_json(std::string_view{text + offset, len - offset});
    if (!extracted) return -1;
    // Locate the substring back in the source for the offset.
    const auto pos = std::string_view{text + offset, len - offset}.find(*extracted);
    if (pos == std::string_view::npos) return -1;
    return offset + static_cast<int32_t>(pos);
}

int32_t ra_structured_output_find_matching_brace(const char* text, int32_t open_offset) {
    return find_matching(text, open_offset, '{', '}');
}

int32_t ra_structured_output_find_matching_bracket(const char* text, int32_t open_offset) {
    return find_matching(text, open_offset, '[', ']');
}

ra_status_t ra_structured_output_get_system_prompt(
    const ra_structured_output_config_t* cfg, char** out_prompt) {
    if (!cfg || !out_prompt) return RA_ERR_INVALID_ARGUMENT;
    std::ostringstream os;
    os << "Respond with valid JSON";
    if (cfg->json_schema && *cfg->json_schema) {
        os << " conforming to this JSON Schema:\n" << cfg->json_schema << "\n";
    } else {
        os << ".\n";
    }
    if (cfg->wrap_in_code_block) os << "Wrap the JSON in a ```json code block.\n";
    if (cfg->strict)            os << "Do not include any prose outside the JSON.\n";
    *out_prompt = dup_cstr(os.str());
    return *out_prompt ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_structured_output_prepare_prompt(
    const char*                          user_query,
    const ra_structured_output_config_t* cfg,
    char**                                out_prompt) {
    if (!user_query || !cfg || !out_prompt) return RA_ERR_INVALID_ARGUMENT;
    char* sys = nullptr;
    auto rc = ra_structured_output_get_system_prompt(cfg, &sys);
    if (rc != RA_OK) return rc;
    std::ostringstream os;
    os << sys << "\n\nUser request:\n" << user_query;
    std::free(sys);
    *out_prompt = dup_cstr(os.str());
    return *out_prompt ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_structured_output_validate(const char* json_text,
                                           const char* /*json_schema*/,
                                           ra_structured_output_validation_t* out_validation) {
    if (!json_text || !out_validation) return RA_ERR_INVALID_ARGUMENT;
    *out_validation = ra_structured_output_validation_t{};
    auto extracted = ra::core::util::extract_json(json_text);
    if (extracted && *extracted == json_text) {
        out_validation->is_valid = 1;
        return RA_OK;
    }
    out_validation->is_valid      = 0;
    out_validation->error_message = dup_cstr("Input is not a single well-formed JSON value");
    return RA_OK;
}

void ra_structured_output_validation_free(ra_structured_output_validation_t* v) {
    if (!v) return;
    if (v->error_message) { std::free(v->error_message); v->error_message = nullptr; }
    v->is_valid = 0;
}

void ra_structured_output_string_free(char* str) {
    if (str) std::free(str);
}

}  // extern "C"
