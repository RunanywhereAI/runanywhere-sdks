// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_tool.h"

#include <cstdlib>
#include <cstring>
#include <sstream>
#include <string>
#include <string_view>

#include "../util/tool_calling.h"

namespace {

char* dup_cstr(std::string_view s) {
    char* out = static_cast<char*>(std::malloc(s.size() + 1));
    if (!out) return nullptr;
    if (!s.empty()) std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

ra::core::util::ToolCallFormat to_cpp(ra_tool_call_format_t f) {
    return f == RA_TOOL_CALL_FORMAT_LFM2 ? ra::core::util::ToolCallFormat::kLFM2
                                          : ra::core::util::ToolCallFormat::kDefault;
}

ra_tool_call_format_t from_cpp(ra::core::util::ToolCallFormat f) {
    return f == ra::core::util::ToolCallFormat::kLFM2 ? RA_TOOL_CALL_FORMAT_LFM2
                                                       : RA_TOOL_CALL_FORMAT_DEFAULT;
}

// Build the default-format system prompt: lists each tool with its JSON
// schema and instructs the model to wrap calls in <tool_call>...</tool_call>.
std::string build_default_prompt(const ra_tool_definition_t* tools, int32_t count) {
    std::ostringstream os;
    os << "You have access to the following tools. To call one, emit "
          "exactly:\n<tool_call>{\"tool\":\"name\",\"arguments\":{...}}"
          "</tool_call>\n\nTools:\n";
    for (int32_t i = 0; i < count; ++i) {
        const auto& t = tools[i];
        if (!t.name) continue;
        os << "- " << t.name;
        if (t.description) os << ": " << t.description;
        os << "\n  parameters: {";
        for (int32_t p = 0; p < t.parameter_count; ++p) {
            const auto& pp = t.parameters[p];
            if (p) os << ", ";
            os << "\"" << (pp.name ? pp.name : "") << "\": {"
               << "\"type\":\"" << (pp.type ? pp.type : "string") << "\""
               << (pp.description ? std::string{",\"description\":\""} + pp.description + "\"" : "")
               << ",\"required\":" << (pp.required ? "true" : "false") << "}";
        }
        os << "}\n";
    }
    return os.str();
}

// LFM2-style: terser, uses bracket syntax.
std::string build_lfm2_prompt(const ra_tool_definition_t* tools, int32_t count) {
    std::ostringstream os;
    os << "Available functions (call as "
          "<|tool_call_start|>[func(arg=val)]<|tool_call_end|>):\n";
    for (int32_t i = 0; i < count; ++i) {
        const auto& t = tools[i];
        if (!t.name) continue;
        os << "- " << t.name << "(";
        for (int32_t p = 0; p < t.parameter_count; ++p) {
            if (p) os << ", ";
            os << (t.parameters[p].name ? t.parameters[p].name : "")
               << ":" << (t.parameters[p].type ? t.parameters[p].type : "string");
        }
        os << ")";
        if (t.description) os << " — " << t.description;
        os << "\n";
    }
    return os.str();
}

}  // namespace

extern "C" {

ra_tool_call_format_t ra_tool_call_detect_format(const char* llm_output) {
    if (!llm_output) return RA_TOOL_CALL_FORMAT_DEFAULT;
    return from_cpp(ra::core::util::detect_tool_call_format(llm_output));
}

static ra_status_t parse_into(std::string_view text,
                              ra::core::util::ToolCallFormat fmt,
                              ra_tool_call_t* out_call) {
    if (!out_call) return RA_ERR_INVALID_ARGUMENT;
    auto parsed = ra::core::util::parse_tool_call(text, fmt);
    *out_call = ra_tool_call_t{};
    out_call->has_call       = parsed.has_call ? 1 : 0;
    out_call->format         = from_cpp(parsed.format);
    out_call->tool_name      = dup_cstr(parsed.tool_name);
    out_call->arguments_json = dup_cstr(parsed.arguments_json);
    out_call->clean_text     = dup_cstr(parsed.clean_text);
    return RA_OK;
}

ra_status_t ra_tool_call_parse(const char* llm_output, ra_tool_call_t* out_call) {
    if (!llm_output || !out_call) return RA_ERR_INVALID_ARGUMENT;
    return parse_into(llm_output, ra::core::util::detect_tool_call_format(llm_output),
                      out_call);
}

ra_status_t ra_tool_call_parse_with_format(const char*           llm_output,
                                            ra_tool_call_format_t format,
                                            ra_tool_call_t*       out_call) {
    if (!llm_output || !out_call) return RA_ERR_INVALID_ARGUMENT;
    return parse_into(llm_output, to_cpp(format), out_call);
}

void ra_tool_call_free(ra_tool_call_t* call) {
    if (!call) return;
    if (call->tool_name)      { std::free(call->tool_name);      call->tool_name = nullptr; }
    if (call->arguments_json) { std::free(call->arguments_json); call->arguments_json = nullptr; }
    if (call->clean_text)     { std::free(call->clean_text);     call->clean_text = nullptr; }
    call->has_call = 0;
}

const char* ra_tool_call_format_name(ra_tool_call_format_t format) {
    auto sv = ra::core::util::tool_call_format_name(to_cpp(format));
    return sv == "lfm2" ? "lfm2" : "default";
}

ra_tool_call_format_t ra_tool_call_format_from_name(const char* name) {
    if (!name) return RA_TOOL_CALL_FORMAT_DEFAULT;
    return from_cpp(ra::core::util::tool_call_format_from_name(name));
}

ra_status_t ra_tool_call_format_prompt(const ra_tool_definition_t* tools,
                                        int32_t                     tool_count,
                                        ra_tool_call_format_t       format,
                                        char**                      out_prompt) {
    if (!tools || tool_count < 0 || !out_prompt) return RA_ERR_INVALID_ARGUMENT;
    std::string prompt = (format == RA_TOOL_CALL_FORMAT_LFM2)
                             ? build_lfm2_prompt(tools, tool_count)
                             : build_default_prompt(tools, tool_count);
    *out_prompt = dup_cstr(prompt);
    return *out_prompt ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_tool_call_format_prompt_json(const char*           tools_json,
                                             ra_tool_call_format_t format,
                                             char**                out_prompt) {
    if (!tools_json || !out_prompt) return RA_ERR_INVALID_ARGUMENT;
    // For brevity we wrap the raw JSON in the format-specific preamble; the
    // frontend already serialised tool defs to JSON. Native JSON parsing is
    // intentionally avoided here — frontends pass canonical JSON.
    std::ostringstream os;
    if (format == RA_TOOL_CALL_FORMAT_LFM2) {
        os << "Available functions (LFM2 format). Definitions JSON:\n"
           << tools_json
           << "\nCall as: <|tool_call_start|>[func(arg=val)]<|tool_call_end|>\n";
    } else {
        os << "You have access to the following tools (JSON):\n"
           << tools_json
           << "\nTo call: <tool_call>{\"tool\":\"name\",\"arguments\":{...}}"
              "</tool_call>\n";
    }
    *out_prompt = dup_cstr(os.str());
    return *out_prompt ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_tool_call_build_initial_prompt(const ra_tool_definition_t* tools,
                                                int32_t                    tool_count,
                                                const char*                user_query,
                                                ra_tool_call_format_t      format,
                                                char**                     out_prompt) {
    if (!tools || tool_count < 0 || !user_query || !out_prompt)
        return RA_ERR_INVALID_ARGUMENT;
    std::string preamble = (format == RA_TOOL_CALL_FORMAT_LFM2)
                                ? build_lfm2_prompt(tools, tool_count)
                                : build_default_prompt(tools, tool_count);
    std::ostringstream os;
    os << preamble << "\nUser: " << user_query;
    *out_prompt = dup_cstr(os.str());
    return *out_prompt ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_tool_call_build_followup_prompt(const char*           tool_name,
                                                 const char*           result_json,
                                                 ra_tool_call_format_t format,
                                                 char**                out_prompt) {
    if (!tool_name || !result_json || !out_prompt) return RA_ERR_INVALID_ARGUMENT;
    std::ostringstream os;
    if (format == RA_TOOL_CALL_FORMAT_LFM2) {
        os << "<|tool_response_start|>{\"tool\":\"" << tool_name
           << "\",\"result\":" << result_json << "}<|tool_response_end|>";
    } else {
        os << "<tool_response>{\"tool\":\"" << tool_name
           << "\",\"result\":" << result_json << "}</tool_response>";
    }
    *out_prompt = dup_cstr(os.str());
    return *out_prompt ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_tool_call_normalize_json(const char* arguments_json,
                                         char**      out_normalized) {
    if (!arguments_json || !out_normalized) return RA_ERR_INVALID_ARGUMENT;
    // Minimal normaliser: strip whitespace outside string literals. Frontends
    // that need full canonicalisation should use their language's JSON lib.
    std::string out;
    out.reserve(std::strlen(arguments_json));
    bool in_str = false;
    bool escape = false;
    for (const char* p = arguments_json; *p; ++p) {
        const char c = *p;
        if (in_str) {
            out.push_back(c);
            if (escape) escape = false;
            else if (c == '\\') escape = true;
            else if (c == '"') in_str = false;
        } else if (c == '"') {
            in_str = true;
            out.push_back(c);
        } else if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            // skip whitespace
        } else {
            out.push_back(c);
        }
    }
    *out_normalized = dup_cstr(out);
    return *out_normalized ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_tool_call_to_json(const ra_tool_call_t* call, char** out_json) {
    if (!call || !out_json) return RA_ERR_INVALID_ARGUMENT;
    std::ostringstream os;
    os << "{\"has_call\":" << (call->has_call ? "true" : "false")
       << ",\"format\":\"" << ra_tool_call_format_name(call->format) << "\""
       << ",\"tool_name\":\"" << (call->tool_name ? call->tool_name : "") << "\""
       << ",\"arguments\":"
       << (call->arguments_json && call->arguments_json[0] ? call->arguments_json : "null")
       << "}";
    *out_json = dup_cstr(os.str());
    return *out_json ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_status_t ra_tool_definitions_to_json(const ra_tool_definition_t* tools,
                                         int32_t                     tool_count,
                                         char**                      out_json) {
    if (!tools || tool_count < 0 || !out_json) return RA_ERR_INVALID_ARGUMENT;
    std::ostringstream os;
    os << "[";
    for (int32_t i = 0; i < tool_count; ++i) {
        const auto& t = tools[i];
        if (i) os << ",";
        os << "{\"name\":\"" << (t.name ? t.name : "") << "\","
           << "\"description\":\"" << (t.description ? t.description : "") << "\","
           << "\"parameters\":{";
        for (int32_t p = 0; p < t.parameter_count; ++p) {
            const auto& pp = t.parameters[p];
            if (p) os << ",";
            os << "\"" << (pp.name ? pp.name : "") << "\":{"
               << "\"type\":\"" << (pp.type ? pp.type : "string") << "\","
               << "\"description\":\"" << (pp.description ? pp.description : "") << "\","
               << "\"required\":" << (pp.required ? "true" : "false")
               << "}";
        }
        os << "}}";
    }
    os << "]";
    *out_json = dup_cstr(os.str());
    return *out_json ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

void ra_tool_string_free(char* str) {
    if (str) std::free(str);
}

}  // extern "C"
