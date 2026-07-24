/**
 * @file rac_cua.h
 * @brief RunAnywhere Commons - Computer-Use Agent (CUA) scaffold.
 *
 * Turns a VLM into a drivable computer-use agent WITHOUT baking any single
 * model into the SDK. A CUA "profile" (data) describes how a family of models
 * is driven: its system prompt, its output format, and its coordinate
 * convention. The API is generic — callers pass a `profile_id`; the built-in
 * registry currently ships `RAC_CUA_PROFILE_FARA` (Microsoft Fara1.5 /
 * Qwen3.5-VL computer_use, a fixed 1000x1000 coordinate space). Other CUA
 * models (Qwen2.5-VL-CU, UI-TARS, ...) are added as more profiles, not new API.
 *
 * This layer is stateless and I/O-free (no model handle, no inference): it
 * pairs with the existing `rac_vlm_*` inference APIs. The app does screenshot
 * capture, executes the returned action (tap/type/scroll), and owns the agent
 * loop — none of the prompt/parse/coordinate knowledge leaks into the app.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md): struct API, `internal`
 * today; a proto-byte `CuaAction` variant is a planned follow-up once the IDL
 * toolchain is wired.
 */

#ifndef RAC_CUA_H
#define RAC_CUA_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Built-in profile IDs. */
#define RAC_CUA_PROFILE_FARA "fara"

/** Model-agnostic action type parsed from a CUA model's output. */
typedef enum {
    RAC_CUA_ACTION_UNKNOWN = 0,
    RAC_CUA_LEFT_CLICK,
    RAC_CUA_RIGHT_CLICK,
    RAC_CUA_DOUBLE_CLICK,
    RAC_CUA_TRIPLE_CLICK,
    RAC_CUA_MOUSE_MOVE,
    RAC_CUA_LEFT_CLICK_DRAG,
    RAC_CUA_TYPE,
    RAC_CUA_KEY,
    RAC_CUA_SCROLL,
    RAC_CUA_HSCROLL,
    RAC_CUA_VISIT_URL,
    RAC_CUA_HISTORY_BACK,
    RAC_CUA_WEB_SEARCH,
    RAC_CUA_READ_PAGE_ANSWER,
    RAC_CUA_PAUSE_MEMORIZE,
    RAC_CUA_ASK_USER,
    RAC_CUA_WAIT,
    RAC_CUA_TERMINATE
} rac_cua_action_type_t;

/**
 * A single parsed action. Coordinates are already scaled to the caller's
 * viewport. `text` is the action's primary string argument, interpreted by
 * `type`: TYPE->text, VISIT_URL->url, WEB_SEARCH->query, TERMINATE->answer,
 * ASK_USER/READ_PAGE_ANSWER->question, PAUSE_MEMORIZE->fact, KEY->space-joined
 * keys. `reasoning` holds any chain-of-thought preceding the tool_call.
 */
typedef struct {
    rac_cua_action_type_t type;
    int32_t has_coordinate; /* 1 if x/y are valid */
    int32_t x;              /* viewport-scaled pixels */
    int32_t y;
    int32_t scroll_pixels;  /* SCROLL/HSCROLL: +up / -down */
    double wait_seconds;    /* WAIT */
    char text[2048];        /* primary string arg (see above) */
    char reasoning[2048];   /* CoT before the tool_call, if any */
    int32_t parse_ok;       /* 1 if a valid tool_call was found */
} rac_cua_action_t;

/**
 * Render `profile_id`'s system prompt for a declared coordinate space
 * (`display_w` x `display_h`; pass the profile's native space, e.g. 1000x1000
 * for Fara). Writes a NUL-terminated string into `out` (truncated to
 * `out_size`). Returns the full length excluding NUL (>= out_size means it was
 * truncated), or -1 if `profile_id` is unknown.
 */
int rac_cua_system_prompt(const char* profile_id, uint32_t display_w, uint32_t display_h,
                          char* out, size_t out_size);

/**
 * Parse a CUA model's raw output into `out_action`, rescaling coordinates from
 * the profile's model space to `viewport_w` x `viewport_h`. Returns 0 on a
 * recognized profile (inspect `out_action->parse_ok` for whether a valid
 * tool_call was found), or -1 if `profile_id` is unknown / args are NULL.
 */
int rac_cua_parse_action(const char* profile_id, const char* model_output,
                         uint32_t viewport_w, uint32_t viewport_h,
                         rac_cua_action_t* out_action);

#ifdef __cplusplus
}
#endif

#endif /* RAC_CUA_H */
