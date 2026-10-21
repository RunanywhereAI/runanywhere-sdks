/**
 * @file cua.cpp
 * @brief Computer-Use Agent scaffold — profile registry, prompt rendering,
 *        and model-agnostic action parsing. See include/rac/features/cua/rac_cua.h.
 *
 * Ships one built-in profile ("fara"). Adding another CUA model = add a profile
 * entry here (or, later, a declarative proto), not new public API.
 */

#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>
#include <mutex>
#include <string>
#include <vector>

#include "rac/features/cua/rac_cua.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "cua.pb.h"
#endif

namespace {

// The Fara1.5 (Qwen3.5-VL computer_use) system prompt, verbatim from
// microsoft/fara `_prompts.py` (identity + critical points + the computer_use
// tool schema in <tools>). Coordinate space is a fixed 1000x1000; the agent
// scales emitted coordinates to the real viewport (see rac_cua_parse_action).
constexpr const char* kFaraSystemPrompt =
    R"FARA(You are Fara, a computer use agent (CUA) specialized for web browsers. You are developed by Microsoft AI Frontiers. You assist users with completing and automating tasks that require the use of a web browser.

The model was trained in the timeframe of January - April 2026. You can effectively perform tasks even beyond this range by accessing the web browser and using the latest information on the live web. But your knowledge cutoff is limited to early 2026, so you may not be aware of events or developments that occurred after that time, without explicitly browsing and searching for latest information on the web.

This edition of the model was trained using SFT on top of Qwen3.5-4B, using a synthetic data mixture generated and developed by Microsoft AI Frontiers.

A critical point is a situation where we must pause and request information or confirmation from the user before proceeding. There are three types:

Case 1: Missing User Information — The task requires personal information that the user has not provided (e.g., email, phone number, address, payment details). Never fabricate or assume personal information. Fill in only what the user has explicitly provided, then pause and ask for any missing required fields.

Case 2: Underspecified Task — The task description is ambiguous or missing details needed to make a decision at the current step. Pause and ask for clarification.

Case 3: Irreversible Action — We are about to perform an action that cannot be undone (e.g., submitting a form, completing a purchase, sending a message, deleting data). If the user explicitly authorized the action, proceed. Otherwise, stop and ask for confirmation.

Only stop at a critical point if (1) required information is missing, (2) the task is ambiguous, OR (3) an irreversible action lacks explicit user authorization.

You are provided with function signatures within <tools></tools> XML tags:
<tools>
{"type": "function", "function": {"name": "computer_use", "description": "Use a mouse and keyboard to interact with a computer, and take screenshots.\n* This is an interface to a desktop GUI. You do not have access to a terminal or applications menu. You must click on desktop icons to start applications.\n* Some applications may take time to start or process actions, so you may need to wait and take successive screenshots to see the results of your actions. E.g. if you click on Firefox and a window doesn't open, try wait and taking another screenshot.\n* The screen's resolution is 1000x1000.\n* Whenever you intend to move the cursor to click on an element like an icon, you should consult a screenshot to determine the coordinates of the element before moving the cursor.\n* If you tried clicking on a program or link but it failed to load, even after waiting, try adjusting your cursor position so that the tip of the cursor visually falls on the element that you want to click.\n* Make sure to click any buttons, links, icons, etc with the cursor tip in the center of the element. Don't click boxes on their edges.", "parameters": {"properties": {"action": {"description": "The action to perform. The available actions are:\n* `key`: Performs key down presses on the arguments passed in order, then performs key releases in reverse order.\n* `type`: Type a string of text on the keyboard.\n* `mouse_move`: Move the cursor to a specified (x, y) pixel coordinate on the screen.\n* `left_click`: Click the left mouse button.\n* `double_click`: Double-click the left mouse button.\n* `right_click`: Click the right mouse button.\n* `triple_click`: Triple-click the left mouse button.\n* `left_click_drag`: Click and drag the cursor to a specified (x, y) pixel coordinate on the screen.\n* `scroll`: Performs a scroll of the mouse scroll wheel.\n* `hscroll`: Performs a horizontal scroll (mapped to regular scroll).\n* `visit_url`: Visit a specified URL.\n* `history_back`: Go back to the previous page in the browser history.\n* `web_search`: Perform a web search with a specified query.\n* `read_page_answer_question`: Read the current page content and answer a question about it.\n* `pause_and_memorize_fact`: Pause and memorize a fact for future reference.\n* `ask_user_question`: Ask the user a clarifying question and wait for a response.\n* `wait`: Wait specified seconds for the change to happen.\n* `terminate`: Terminate the current task and provide the final answer.", "enum": ["key", "type", "mouse_move", "left_click", "left_click_drag", "right_click", "double_click", "triple_click", "scroll", "hscroll", "visit_url", "history_back", "web_search", "read_page_answer_question", "pause_and_memorize_fact", "ask_user_question", "wait", "terminate"], "type": "string"}, "keys": {"description": "Required only by `action=key`.", "type": "array"}, "text": {"description": "Required only by `action=type`.", "type": "string"}, "coordinate": {"description": "(x, y): The x (pixels from the left edge) and y (pixels from the top edge) coordinates to move the mouse to. Required by `action=left_click`, `action=double_click`, `action=right_click`, `action=triple_click`, `action=left_click_drag`, and `action=mouse_move`.", "type": "array"}, "pixels": {"description": "The amount of scrolling to perform. Required only by `action=scroll` and `action=hscroll`.", "type": "number"}, "url": {"description": "The URL to visit. Required only by `action=visit_url`.", "type": "string"}, "query": {"description": "The query to search for. Required only by `action=web_search`.", "type": "string"}, "fact": {"description": "The fact to remember. Required only by `action=pause_and_memorize_fact`.", "type": "string"}, "question": {"description": "The question to ask. Required by `action=read_page_answer_question` and `action=ask_user_question`.", "type": "string"}, "time": {"description": "The seconds to wait. Required only by `action=wait`.", "type": "number"}, "answer": {"description": "The final answer. Required only by `action=terminate`.", "type": "string"}}, "required": ["action"], "type": "object"}}}
</tools>

For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
<tool_call>
{"name": <function-name>, "arguments": <args-json-object>}
</tool_call>)FARA";

struct CuaProfile {
    const char* id;
    const char* system_prompt;
    uint32_t model_space_w;
    uint32_t model_space_h;
};

// Built-in profiles. This list is a convenience, not the extension point:
// `rac_cua_register_profile` lets an application add a model family at runtime,
// so a new model needs no edit here, no rebuild, and no republish of the
// language bindings.
//
// Built-ins are kept deliberately few. A profile is only useful if its prompt
// and coordinate space match what the model was actually trained to emit;
// shipping a plausible-looking guess would produce confidently wrong clicks,
// which is worse than having no profile at all.
constexpr CuaProfile kProfiles[] = {
    {RAC_CUA_PROFILE_FARA, kFaraSystemPrompt, 1000, 1000},
};

// A profile registered at runtime. Owns its strings: callers are told they may
// free theirs on return, and a dangling prompt pointer would be a use-after-free
// on every subsequent prompt build.
struct OwnedProfile {
    std::string id;
    std::string system_prompt;
    uint32_t model_space_w;
    uint32_t model_space_h;
};

// Function-local statics: initialised on first use, in a defined order, with no
// static-initialisation-order hazard against other translation units.
std::mutex& registry_mutex() {
    static std::mutex m;
    return m;
}

std::vector<OwnedProfile>& runtime_profiles() {
    static std::vector<OwnedProfile> v;
    return v;
}

// Resolved by VALUE rather than by pointer. A pointer into `runtime_profiles()`
// would dangle the moment another thread registered a profile and the vector
// reallocated; copying two small strings per call is not worth that risk.
struct ResolvedProfile {
    std::string system_prompt;
    uint32_t model_space_w;
    uint32_t model_space_h;
};

// Runtime registrations are searched first, so registering an existing id
// overrides it — including a built-in, which lets an application correct a
// shipped prompt without waiting for a release.
bool resolve_profile(const char* id, ResolvedProfile* out) {
    if (id == nullptr || out == nullptr) {
        return false;
    }
    {
        std::lock_guard<std::mutex> lock(registry_mutex());
        for (const auto& p : runtime_profiles()) {
            if (p.id == id) {
                out->system_prompt = p.system_prompt;
                out->model_space_w = p.model_space_w;
                out->model_space_h = p.model_space_h;
                return true;
            }
        }
    }
    for (const auto& p : kProfiles) {
        if (std::strcmp(p.id, id) == 0) {
            out->system_prompt = p.system_prompt;
            out->model_space_w = p.model_space_w;
            out->model_space_h = p.model_space_h;
            return true;
        }
    }
    return false;
}

// --- minimal, dependency-free JSON-ish extractors (Fara's tool_call is fixed) ---
//
// Every extractor is ANCHORED to the matched key's own value: it locates
// `"key"` used as a key (quoted name, optional space, ':') and then requires
// the value to have the expected shape. They fail closed — a present-but-wrong
// value (null, wrong type, malformed) reports absent rather than latching onto
// an unrelated token later in the payload. This matters because the input is
// untrusted model output.

bool is_json_space(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

// Index of the first non-space character of `"key"`'s value, or npos.
size_t json_value_start(const std::string& s, const char* key) {
    const std::string needle = std::string("\"") + key + "\"";
    size_t from = 0;
    while (true) {
        size_t k = s.find(needle, from);
        if (k == std::string::npos) {
            return std::string::npos;
        }
        size_t i = k + needle.size();
        while (i < s.size() && is_json_space(s[i])) {
            ++i;
        }
        // Only a name followed by ':' is a key; otherwise this was a value that
        // merely looks like the key name, so keep searching.
        if (i < s.size() && s[i] == ':') {
            ++i;
            while (i < s.size() && is_json_space(s[i])) {
                ++i;
            }
            return i < s.size() ? i : std::string::npos;
        }
        from = k + needle.size();
    }
}

void append_utf8(std::string* out, uint32_t cp) {
    if (cp < 0x80) {
        out->push_back(static_cast<char>(cp));
    } else if (cp < 0x800) {
        out->push_back(static_cast<char>(0xC0 | (cp >> 6)));
        out->push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp < 0x10000) {
        out->push_back(static_cast<char>(0xE0 | (cp >> 12)));
        out->push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out->push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else {
        out->push_back(static_cast<char>(0xF0 | (cp >> 18)));
        out->push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
        out->push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out->push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
}

// Read 4 hex digits at `at`. Returns false when they are not all hex.
bool read_hex4(const std::string& s, size_t at, uint32_t* out) {
    if (at + 3 >= s.size()) {
        return false;
    }
    uint32_t cp = 0;
    for (size_t h = 0; h < 4; ++h) {
        char d = s[at + h];
        cp <<= 4;
        if (d >= '0' && d <= '9') {
            cp |= static_cast<uint32_t>(d - '0');
        } else if (d >= 'a' && d <= 'f') {
            cp |= static_cast<uint32_t>(d - 'a' + 10);
        } else if (d >= 'A' && d <= 'F') {
            cp |= static_cast<uint32_t>(d - 'A' + 10);
        } else {
            return false;
        }
    }
    *out = cp;
    return true;
}

// Scan the JSON string literal at s[start] (must be '"'). Writes the decoded
// value and the index just past the closing quote. False when unterminated.
bool scan_json_string(const std::string& s, size_t start, std::string* out, size_t* next) {
    if (start >= s.size() || s[start] != '"') {
        return false;
    }
    std::string value;
    for (size_t i = start + 1; i < s.size(); ++i) {
        char c = s[i];
        if (c == '\\') {
            if (i + 1 >= s.size()) {
                return false;  // dangling escape
            }
            char n = s[++i];
            switch (n) {
                case 'n':
                    value.push_back('\n');
                    break;
                case 't':
                    value.push_back('\t');
                    break;
                case 'r':
                    value.push_back('\r');
                    break;
                case 'b':
                    value.push_back('\b');
                    break;
                case 'f':
                    value.push_back('\f');
                    break;
                case '"':
                    value.push_back('"');
                    break;
                case '\\':
                    value.push_back('\\');
                    break;
                case '/':
                    value.push_back('/');
                    break;
                case 'u': {
                    // Decode to UTF-8. These land in proto3 `string` fields, so
                    // an unpaired surrogate becomes U+FFFD rather than invalid
                    // UTF-8 on the wire.
                    uint32_t cp = 0;
                    if (!read_hex4(s, i + 1, &cp)) {
                        value.push_back('\\');
                        value.push_back('u');
                        break;
                    }
                    i += 4;
                    if (cp >= 0xD800 && cp <= 0xDBFF) {
                        uint32_t low = 0;
                        if (i + 6 < s.size() && s[i + 1] == '\\' && s[i + 2] == 'u' &&
                            read_hex4(s, i + 3, &low) && low >= 0xDC00 && low <= 0xDFFF) {
                            cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                            i += 6;
                        } else {
                            cp = 0xFFFD;
                        }
                    } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
                        cp = 0xFFFD;  // lone trailing surrogate
                    }
                    append_utf8(&value, cp);
                    break;
                }
                default:
                    value.push_back(n);
                    break;
            }
        } else if (c == '"') {
            *out = value;
            if (next != nullptr) {
                *next = i + 1;
            }
            return true;
        } else {
            value.push_back(c);
        }
    }
    return false;  // unterminated
}

// Value of "key": "...". False when absent, null, a non-string, or unterminated.
bool json_string(const std::string& s, const char* key, std::string* out) {
    size_t i = json_value_start(s, key);
    if (i == std::string::npos || s[i] != '"') {
        return false;
    }
    return scan_json_string(s, i, out, nullptr);
}

// Value of "key": ["a","b"] joined with single spaces. False when absent or not
// an array of strings. Used for `keys` (the KEY action's chord).
bool json_string_array(const std::string& s, const char* key, std::string* out) {
    size_t i = json_value_start(s, key);
    if (i == std::string::npos || s[i] != '[') {
        return false;
    }
    std::string joined;
    size_t j = i + 1;
    while (true) {
        while (j < s.size() && is_json_space(s[j])) {
            ++j;
        }
        if (j >= s.size()) {
            return false;  // unterminated array
        }
        if (s[j] == ']') {
            *out = joined;
            return true;
        }
        std::string item;
        size_t next = 0;
        if (!scan_json_string(s, j, &item, &next)) {
            return false;  // non-string element
        }
        if (!joined.empty()) {
            joined.push_back(' ');
        }
        joined += item;
        j = next;
        while (j < s.size() && is_json_space(s[j])) {
            ++j;
        }
        if (j < s.size() && s[j] == ',') {
            ++j;
            continue;
        }
        if (j < s.size() && s[j] == ']') {
            *out = joined;
            return true;
        }
        return false;  // junk between elements
    }
}

// Value of "key": [a, b]. Requires EXACTLY two integers inside this key's own
// array — a scalar, a 1- or 3-element array, or a non-array all report absent.
bool json_int_pair(const std::string& s, const char* key, long* a, long* b) {
    size_t i = json_value_start(s, key);
    if (i == std::string::npos || s[i] != '[') {
        return false;
    }
    size_t close = s.find(']', i + 1);
    if (close == std::string::npos) {
        return false;
    }
    // Parse strictly inside the brackets so nothing after ']' can be consumed.
    const std::string span = s.substr(i + 1, close - (i + 1));
    const char* p = span.c_str();
    char* end = nullptr;
    long first = std::strtol(p, &end, 10);
    if (end == p) {
        return false;  // no leading integer
    }
    while (*end != '\0' && is_json_space(*end)) {
        ++end;
    }
    if (*end != ',') {
        return false;  // single element
    }
    const char* second = end + 1;
    char* end2 = nullptr;
    long value = std::strtol(second, &end2, 10);
    if (end2 == second) {
        return false;
    }
    while (*end2 != '\0' && is_json_space(*end2)) {
        ++end2;
    }
    if (*end2 != '\0') {
        return false;  // a third element: not a coordinate
    }
    *a = first;
    *b = value;
    return true;
}

// Value of "key": <number>. False when absent or the value is not numeric.
bool json_number(const std::string& s, const char* key, double* out) {
    size_t i = json_value_start(s, key);
    if (i == std::string::npos) {
        return false;
    }
    const char* p = s.c_str() + i;
    char* end = nullptr;
    double value = std::strtod(p, &end);
    if (end == p) {
        return false;  // null, string, or anything non-numeric
    }
    *out = value;
    return true;
}

rac_cua_action_type_t action_from_string(const std::string& a) {
    struct Map {
        const char* s;
        rac_cua_action_type_t t;
    };
    static const Map kMap[] = {
        {"left_click", RAC_CUA_LEFT_CLICK},
        {"right_click", RAC_CUA_RIGHT_CLICK},
        {"double_click", RAC_CUA_DOUBLE_CLICK},
        {"triple_click", RAC_CUA_TRIPLE_CLICK},
        {"mouse_move", RAC_CUA_MOUSE_MOVE},
        {"left_click_drag", RAC_CUA_LEFT_CLICK_DRAG},
        {"type", RAC_CUA_TYPE},
        {"key", RAC_CUA_KEY},
        {"scroll", RAC_CUA_SCROLL},
        {"hscroll", RAC_CUA_HSCROLL},
        {"visit_url", RAC_CUA_VISIT_URL},
        {"history_back", RAC_CUA_HISTORY_BACK},
        {"web_search", RAC_CUA_WEB_SEARCH},
        {"read_page_answer_question", RAC_CUA_READ_PAGE_ANSWER},
        {"pause_and_memorize_fact", RAC_CUA_PAUSE_MEMORIZE},
        {"ask_user_question", RAC_CUA_ASK_USER},
        {"wait", RAC_CUA_WAIT},
        {"terminate", RAC_CUA_TERMINATE},
    };
    for (const auto& m : kMap) {
        if (a == m.s) {
            return m.t;
        }
    }
    return RAC_CUA_ACTION_UNKNOWN;
}

// Copy into a fixed char[cap], NUL-terminated. Truncation backs off to a UTF-8
// character boundary: these buffers feed proto3 `string` fields, and a severed
// multi-byte sequence would be invalid UTF-8 on the wire (SwiftProtobuf and
// dart-protobuf reject it outright, so the whole action would be lost).
void copy_bounded(char* dst, size_t cap, const std::string& src) {
    if (cap == 0) {
        return;
    }
    size_t n = src.size() < cap - 1 ? src.size() : cap - 1;
    if (n < src.size()) {
        while (n > 0 && (static_cast<unsigned char>(src[n]) & 0xC0) == 0x80) {
            --n;  // sitting on a continuation byte: rewind to the lead byte
        }
    }
    std::memcpy(dst, src.data(), n);
    dst[n] = '\0';
}

// Upper bound on a caller-declared coordinate space. Far past any real display,
// yet small enough that scaling a model coordinate stays well inside int32_t.
// This is also what catches a signed value a platform SDK handed to a uint32_t
// parameter: a JNI `jint` of -1 arrives as 4294967295 and is rejected here,
// rather than becoming a scale factor that mis-places every click.
constexpr uint32_t kMaxDimension = 1u << 16;

bool dimension_in_range(uint32_t value) {
    return value != 0 && value <= kMaxDimension;
}

// Scale one model-space coordinate into the viewport, saturating at int32_t.
// The bound above constrains the viewport, but `value` comes from the model's
// own output — a garbled `"coordinate": [999999999, 1]` must not overflow the
// cast even when the viewport is sane.
int32_t scale_coordinate(long value, uint32_t viewport, uint32_t model_space) {
    const double scaled = static_cast<double>(value) *
                          (static_cast<double>(viewport) / static_cast<double>(model_space));
    constexpr double kMin = static_cast<double>(std::numeric_limits<int32_t>::min());
    constexpr double kMax = static_cast<double>(std::numeric_limits<int32_t>::max());
    // Written as `!(scaled >= kMin)` so a NaN also lands here.
    if (!(scaled >= kMin)) {
        return std::numeric_limits<int32_t>::min();
    }
    if (scaled > kMax) {
        return std::numeric_limits<int32_t>::max();
    }
    return static_cast<int32_t>(std::lround(scaled));
}

}  // namespace

extern "C" int rac_cua_system_prompt(const char* profile_id, uint32_t display_w, uint32_t display_h,
                                     char* out, size_t out_size) {
    ResolvedProfile profile;
    if (!resolve_profile(profile_id, &profile)) {
        return -1;
    }
    // (0, 0) means "use the profile's native space". Anything else must be a
    // usable resolution on both axes — a half-specified space (1000 x 0) is a
    // caller bug, not a request for the default.
    if ((display_w != 0 || display_h != 0) &&
        (!dimension_in_range(display_w) || !dimension_in_range(display_h))) {
        return -1;
    }
    // The coordinate space is a property of the MODEL, not of the caller: Fara
    // emits in a fixed 1000x1000 space because that is what it was trained on,
    // and saying otherwise in the prompt does not change what it emits. Worse,
    // `rac_cua_parse_action` always rescales from the profile's own space, so a
    // declared space that disagreed produced a prompt and a rescale that
    // contradicted each other — every click confidently wrong, silently. Refuse
    // it. The parameter stays for a future profile whose space is negotiable.
    if (display_w != 0 && (display_w != profile.model_space_w || display_h != profile.model_space_h)) {
        return -1;
    }
    const std::string& prompt = profile.system_prompt;
    if (out != nullptr && out_size > 0) {
        copy_bounded(out, out_size, prompt);
    }
    return static_cast<int>(prompt.size());
}

extern "C" int rac_cua_parse_action(const char* profile_id, const char* model_output,
                                    uint32_t viewport_w, uint32_t viewport_h,
                                    rac_cua_action_t* out) {
    ResolvedProfile profile;
    if (!resolve_profile(profile_id, &profile) || model_output == nullptr || out == nullptr) {
        return -1;
    }
    // Unlike the prompt's display space, a viewport has no "use the default"
    // form — every coordinate this returns is scaled into it, so a zero or
    // out-of-range viewport can only yield confidently wrong pixels.
    if (!dimension_in_range(viewport_w) || !dimension_in_range(viewport_h)) {
        return -1;
    }
    std::memset(out, 0, sizeof(*out));
    std::string s = model_output;

    // Chain-of-thought precedes the tool_call.
    size_t open = s.find("<tool_call>");
    if (open != std::string::npos) {
        std::string reasoning = s.substr(0, open);
        // trim trailing whitespace
        while (!reasoning.empty() &&
               (reasoning.back() == '\n' || reasoning.back() == ' ' || reasoning.back() == '\t')) {
            reasoning.pop_back();
        }
        copy_bounded(out->reasoning, sizeof(out->reasoning), reasoning);
    }

    // Isolate the tool_call body (best-effort: between <tool_call> and </tool_call>,
    // else from <tool_call> to end).
    std::string body = s;
    if (open != std::string::npos) {
        size_t start = open + std::strlen("<tool_call>");
        size_t close = s.find("</tool_call>", start);
        body = s.substr(start, close == std::string::npos ? std::string::npos : close - start);
    }

    std::string action;
    if (!json_string(body, "action", &action) || action.empty()) {
        out->parse_ok = 0;
        return 0;
    }
    out->type = action_from_string(action);
    if (out->type == RAC_CUA_ACTION_UNKNOWN) {
        out->parse_ok = 0;
        return 0;
    }
    out->parse_ok = 1;

    long mx = 0;
    long my = 0;
    if (json_int_pair(body, "coordinate", &mx, &my)) {
        out->has_coordinate = 1;
        out->x = scale_coordinate(mx, viewport_w, profile.model_space_w);
        out->y = scale_coordinate(my, viewport_h, profile.model_space_h);
    }

    double num = 0.0;
    if (json_number(body, "pixels", &num)) {
        out->scroll_pixels = static_cast<int32_t>(std::lround(num));
    }
    if (json_number(body, "time", &num)) {
        out->wait_seconds = num;
    }

    // Primary string argument, keyed by action. KEY is the odd one out: its
    // argument is `keys`, an ARRAY, which the documented contract (rac_cua.h,
    // cua.proto, every SDK facade) says arrives space-joined.
    if (out->type == RAC_CUA_KEY) {
        std::string keys;
        if (json_string_array(body, "keys", &keys)) {
            copy_bounded(out->text, sizeof(out->text), keys);
        }
        return 0;
    }

    const char* text_key = nullptr;
    switch (out->type) {
        case RAC_CUA_TYPE:
            text_key = "text";
            break;
        case RAC_CUA_VISIT_URL:
            text_key = "url";
            break;
        case RAC_CUA_WEB_SEARCH:
            text_key = "query";
            break;
        case RAC_CUA_TERMINATE:
            text_key = "answer";
            break;
        case RAC_CUA_ASK_USER:
        case RAC_CUA_READ_PAGE_ANSWER:
            text_key = "question";
            break;
        case RAC_CUA_PAUSE_MEMORIZE:
            text_key = "fact";
            break;
        default:
            break;
    }
    if (text_key != nullptr) {
        std::string text;
        if (json_string(body, text_key, &text)) {
            copy_bounded(out->text, sizeof(out->text), text);
        }
    }
    return 0;
}

extern "C" rac_result_t rac_cua_parse_action_proto(const char* profile_id, const char* model_output,
                                                   uint32_t viewport_w, uint32_t viewport_h,
                                                   rac_proto_buffer_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)profile_id;
    (void)model_output;
    (void)viewport_w;
    (void)viewport_h;
    return rac_proto_buffer_set_error(out, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    // Reuse the struct parser so parse/scale logic lives in exactly one place;
    // the proto is a faithful projection of rac_cua_action_t. The C enum values
    // match runanywhere.v1.CuaActionType one-for-one (see rac_cua.h / cua.proto).
    rac_cua_action_t action;
    if (rac_cua_parse_action(profile_id, model_output, viewport_w, viewport_h, &action) != 0) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_INVALID_ARGUMENT, "unknown CUA profile");
    }

    runanywhere::v1::CuaAction proto;
    proto.set_type(static_cast<runanywhere::v1::CuaActionType>(action.type));
    if (action.has_coordinate != 0) {
        proto.set_x(action.x);
        proto.set_y(action.y);
    }
    // The C struct keeps one scroll_pixels field (the axis is implied by
    // action.type); the proto splits it into scroll_x (HSCROLL)/scroll_y
    // (SCROLL) per axis.
    if (action.type == RAC_CUA_HSCROLL) {
        proto.set_scroll_x(action.scroll_pixels);
    } else if (action.type == RAC_CUA_SCROLL) {
        proto.set_scroll_y(action.scroll_pixels);
    }
    proto.set_wait_seconds(action.wait_seconds);
    proto.set_text(action.text);
    proto.set_reasoning(action.reasoning);
    proto.set_is_valid(action.parse_ok != 0);

    std::string bytes;
    if (!proto.SerializeToString(&bytes)) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize CuaAction");
    }
    return rac_proto_buffer_copy(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), out);
#endif
}

extern "C" rac_result_t rac_cua_register_profile(const char* profile_id, const char* system_prompt,
                                                 uint32_t model_space_w, uint32_t model_space_h) {
    if (profile_id == nullptr || *profile_id == '\0' || system_prompt == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    // Same bound the built-in path enforces: a zero or absurd coordinate space
    // would make every rescale meaningless rather than merely wrong.
    if (!dimension_in_range(model_space_w) || !dimension_in_range(model_space_h)) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(registry_mutex());
    auto& profiles = runtime_profiles();
    for (auto& existing : profiles) {
        if (existing.id == profile_id) {
            existing.system_prompt = system_prompt;
            existing.model_space_w = model_space_w;
            existing.model_space_h = model_space_h;
            return RAC_SUCCESS;
        }
    }
    profiles.push_back(OwnedProfile{profile_id, system_prompt, model_space_w, model_space_h});
    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_cua_unregister_profile(const char* profile_id) {
    if (profile_id == nullptr || *profile_id == '\0') {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::lock_guard<std::mutex> lock(registry_mutex());
    auto& profiles = runtime_profiles();
    for (auto it = profiles.begin(); it != profiles.end(); ++it) {
        if (it->id == profile_id) {
            profiles.erase(it);
            return RAC_SUCCESS;
        }
    }
    // Built-ins are not removable; reporting success here would imply the
    // profile is gone when the next lookup would still resolve it.
    return RAC_ERROR_INVALID_ARGUMENT;
}

extern "C" size_t rac_cua_profile_count(void) {
    std::lock_guard<std::mutex> lock(registry_mutex());
    size_t count = runtime_profiles().size();
    // A runtime profile that overrides a built-in must be counted once, not
    // twice, or an index walk would report the same id from both lists.
    for (const auto& builtin : kProfiles) {
        bool overridden = false;
        for (const auto& runtime : runtime_profiles()) {
            if (runtime.id == builtin.id) {
                overridden = true;
                break;
            }
        }
        if (!overridden) {
            ++count;
        }
    }
    return count;
}

extern "C" int rac_cua_profile_id_at(size_t index, char* out, size_t out_size) {
    std::lock_guard<std::mutex> lock(registry_mutex());
    const auto& profiles = runtime_profiles();
    if (index < profiles.size()) {
        const std::string& id = profiles[index].id;
        if (out != nullptr && out_size > 0) {
            copy_bounded(out, out_size, id);
        }
        return static_cast<int>(id.size());
    }

    size_t remaining = index - profiles.size();
    for (const auto& builtin : kProfiles) {
        bool overridden = false;
        for (const auto& runtime : profiles) {
            if (runtime.id == builtin.id) {
                overridden = true;
                break;
            }
        }
        if (overridden) {
            continue;
        }
        if (remaining == 0) {
            const std::string id = builtin.id;
            if (out != nullptr && out_size > 0) {
                copy_bounded(out, out_size, id);
            }
            return static_cast<int>(id.size());
        }
        --remaining;
    }
    return -1;
}
