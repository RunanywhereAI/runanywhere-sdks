/**
 * @file cua.cpp
 * @brief Computer-Use Agent scaffold — profile registry, prompt rendering,
 *        and model-agnostic action parsing. See include/rac/features/cua/rac_cua.h.
 *
 * Ships one built-in profile ("fara"). Adding another CUA model = add a profile
 * entry here (or, later, a declarative proto), not new public API.
 */

#include "rac/features/cua/rac_cua.h"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>

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

// Built-in profile registry. Extend here to add a CUA model family.
constexpr CuaProfile kProfiles[] = {
    {RAC_CUA_PROFILE_FARA, kFaraSystemPrompt, 1000, 1000},
};

const CuaProfile* find_profile(const char* id) {
    if (id == nullptr) {
        return nullptr;
    }
    for (const auto& p : kProfiles) {
        if (std::strcmp(p.id, id) == 0) {
            return &p;
        }
    }
    return nullptr;
}

// --- minimal, dependency-free JSON-ish extractors (Fara's tool_call is fixed) ---

// Value of "key": "...". Returns "" if absent. Handles \" and \\ escapes.
std::string json_string(const std::string& s, const char* key) {
    std::string needle = std::string("\"") + key + "\"";
    size_t k = s.find(needle);
    if (k == std::string::npos) {
        return "";
    }
    size_t colon = s.find(':', k + needle.size());
    if (colon == std::string::npos) {
        return "";
    }
    size_t q = s.find('"', colon);
    if (q == std::string::npos) {
        return "";
    }
    std::string out;
    for (size_t i = q + 1; i < s.size(); ++i) {
        char c = s[i];
        if (c == '\\' && i + 1 < s.size()) {
            char n = s[++i];
            switch (n) {
                case 'n': out.push_back('\n'); break;
                case 't': out.push_back('\t'); break;
                case '"': out.push_back('"'); break;
                case '\\': out.push_back('\\'); break;
                default: out.push_back(n); break;
            }
        } else if (c == '"') {
            break;
        } else {
            out.push_back(c);
        }
    }
    return out;
}

// Value of "key": [a, b]. Returns false if absent/malformed.
bool json_int_pair(const std::string& s, const char* key, long* a, long* b) {
    std::string needle = std::string("\"") + key + "\"";
    size_t k = s.find(needle);
    if (k == std::string::npos) {
        return false;
    }
    size_t lb = s.find('[', k + needle.size());
    if (lb == std::string::npos) {
        return false;
    }
    char* end = nullptr;
    *a = std::strtol(s.c_str() + lb + 1, &end, 10);
    if (end == nullptr) {
        return false;
    }
    const char* comma = std::strchr(end, ',');
    if (comma == nullptr) {
        return false;
    }
    *b = std::strtol(comma + 1, nullptr, 10);
    return true;
}

// Value of "key": <number>. Returns false if absent.
bool json_number(const std::string& s, const char* key, double* out) {
    std::string needle = std::string("\"") + key + "\"";
    size_t k = s.find(needle);
    if (k == std::string::npos) {
        return false;
    }
    size_t colon = s.find(':', k + needle.size());
    if (colon == std::string::npos) {
        return false;
    }
    *out = std::strtod(s.c_str() + colon + 1, nullptr);
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

void copy_bounded(char* dst, size_t cap, const std::string& src) {
    if (cap == 0) {
        return;
    }
    size_t n = src.size() < cap - 1 ? src.size() : cap - 1;
    std::memcpy(dst, src.data(), n);
    dst[n] = '\0';
}

}  // namespace

extern "C" int rac_cua_system_prompt(const char* profile_id, uint32_t display_w,
                                     uint32_t display_h, char* out, size_t out_size) {
    const CuaProfile* p = find_profile(profile_id);
    if (p == nullptr) {
        return -1;
    }
    std::string prompt = p->system_prompt;
    // Substitute the declared resolution when the caller wants a space other
    // than the profile's native one.
    if (display_w != 0 && display_h != 0 &&
        (display_w != p->model_space_w || display_h != p->model_space_h)) {
        char from[32];
        char to[48];
        std::snprintf(from, sizeof(from), "%ux%u", p->model_space_w, p->model_space_h);
        std::snprintf(to, sizeof(to), "%ux%u", display_w, display_h);
        size_t pos = prompt.find(from);
        if (pos != std::string::npos) {
            prompt.replace(pos, std::strlen(from), to);
        }
    }
    if (out != nullptr && out_size > 0) {
        copy_bounded(out, out_size, prompt);
    }
    return static_cast<int>(prompt.size());
}

extern "C" int rac_cua_parse_action(const char* profile_id, const char* model_output,
                                    uint32_t viewport_w, uint32_t viewport_h,
                                    rac_cua_action_t* out) {
    const CuaProfile* p = find_profile(profile_id);
    if (p == nullptr || model_output == nullptr || out == nullptr) {
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

    std::string action = json_string(body, "action");
    if (action.empty()) {
        out->parse_ok = 0;
        return 0;
    }
    out->type = action_from_string(action);
    out->parse_ok = 1;

    long mx = 0;
    long my = 0;
    if (json_int_pair(body, "coordinate", &mx, &my)) {
        out->has_coordinate = 1;
        double sx = static_cast<double>(viewport_w) / static_cast<double>(p->model_space_w);
        double sy = static_cast<double>(viewport_h) / static_cast<double>(p->model_space_h);
        out->x = static_cast<int32_t>(std::lround(static_cast<double>(mx) * sx));
        out->y = static_cast<int32_t>(std::lround(static_cast<double>(my) * sy));
    }

    double num = 0.0;
    if (json_number(body, "pixels", &num)) {
        out->scroll_pixels = static_cast<int32_t>(std::lround(num));
    }
    if (json_number(body, "time", &num)) {
        out->wait_seconds = num;
    }

    // Primary string argument, keyed by action.
    const char* text_key = nullptr;
    switch (out->type) {
        case RAC_CUA_TYPE: text_key = "text"; break;
        case RAC_CUA_VISIT_URL: text_key = "url"; break;
        case RAC_CUA_WEB_SEARCH: text_key = "query"; break;
        case RAC_CUA_TERMINATE: text_key = "answer"; break;
        case RAC_CUA_ASK_USER:
        case RAC_CUA_READ_PAGE_ANSWER: text_key = "question"; break;
        case RAC_CUA_PAUSE_MEMORIZE: text_key = "fact"; break;
        default: break;
    }
    if (text_key != nullptr) {
        copy_bounded(out->text, sizeof(out->text), json_string(body, text_key));
    }
    return 0;
}
