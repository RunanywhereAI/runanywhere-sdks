/**
 * @file rac_tool_provider.h
 * @brief Provider hook for tool-calling tools.
 *
 * Tools are currently written once per binding: Swift, Kotlin and Web each
 * ship their own `search_web`, each with its own HTTP call and its own result
 * shape. Commons already assumes otherwise, hardcoding the `"search_web"` name
 * in the run loop and reading two keys out of a payload it does not own.
 *
 * This is the engine arrangement applied to tools. Commons owns the tool
 * registry and the run loop; a provider attaches one tool through a vtable,
 * exactly as `rac_cpu_runtime_provider` attaches a session handler without the
 * CPU runtime linking any engine. A provider that needs the network calls
 * `rac_http_request_send`, so transport stays platform-supplied through the
 * client adapter the platform already implements.
 */
#ifndef RAC_PLUGIN_TOOL_PROVIDER_H
#define RAC_PLUGIN_TOOL_PROVIDER_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

// NOLINTBEGIN(modernize-redundant-void-arg,modernize-use-nullptr)
#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Status of one stage of a tool's work.
 *
 * Mirrors `runanywhere.v1.ToolProgressStatus`. Stated in C so a provider
 * never has to link protobuf.
 */
typedef enum rac_tool_progress_status {
    RAC_TOOL_PROGRESS_UNSPECIFIED = 0,
    RAC_TOOL_PROGRESS_STARTED = 1,
    RAC_TOOL_PROGRESS_COMPLETED = 2,
    RAC_TOOL_PROGRESS_FAILED = 3
} rac_tool_progress_status_t;

typedef struct rac_tool_context rac_tool_context_t;

/**
 * @brief What a running tool is given to talk back through.
 *
 * Commons owns and fills this; a provider only reads it. It exists because
 * `execute(args) -> result` returns once, at the end, which is no use to a UI
 * that wants to show the stages of a multi-step tool as they happen.
 */
struct rac_tool_context {
    /**
     * Report that a stage started, finished or failed.
     *
     * `stage_id` is a provider-defined key such as "generating_questions",
     * stable across runs so a UI can key off it; `label` is what a person
     * reads; `detail` is optional free text and may be NULL. Commons fills in
     * tool name, sequence, run-loop handle and timestamp, so a provider
     * cannot get correlation wrong and does not serialize anything itself.
     *
     * Returns false when nobody is listening any more or the run was
     * cancelled. A provider that gets false should stop and return.
     */
    rac_bool_t (*emit)(const rac_tool_context_t* ctx, const char* stage_id, const char* label,
                       rac_tool_progress_status_t status, const char* detail);

    /** Cancellation check for a provider between stages, without emitting. */
    rac_bool_t (*is_cancelled)(const rac_tool_context_t* ctx);

    /**
     * Prior conversation turns, alternating user/assistant, excluding the
     * current one. NULL / 0 when the tool runs outside a conversation.
     *
     * A tool that has to interpret the user's words needs them: "what does
     * that news say?" is unanswerable without the turn before it. Borrowed for
     * the duration of `execute` and not owned by the provider.
     *
     * Deliberately NOT something to feed into a summarising step. A tool that
     * reasons over fetched material should do that on a clean context, or the
     * conversation leaks into the summary and the model starts answering from
     * what it said earlier instead of from what it fetched.
     */
    const char* const* history;
    int32_t n_history;

    /** Commons-owned. Opaque to providers. */
    void* state;
};

/**
 * @brief One tool a model may call.
 *
 * Every field except `user_data` is read-only and must outlive registration.
 * Providers are expected to keep these in .rodata, as engine vtables do, so
 * the registry never owns provider storage.
 */
typedef struct rac_tool_provider {
    /** Stable tool name as the model sees it, e.g. "search_web". MUST NOT be NULL. */
    const char* name;

    /**
     * What the tool does, in the wording the model reads.
     *
     * Under AUTO tool choice this text is the only channel that decides
     * whether the tool is called at all, so it belongs with the provider
     * rather than being restated by each binding.
     */
    const char* description;

    /** Optional grouping label, e.g. "Web". May be NULL. */
    const char* category;

    /**
     * Parameters as a JSON Schema object:
     * `{"type":"object","properties":{...},"required":[...]}`.
     * A tool taking no arguments passes `"{}"`. MUST NOT be NULL.
     */
    const char* parameters_json;

    /**
     * Run the tool.
     *
     * `args_json` is a JSON object matching `parameters_json`. `ctx` is never
     * NULL and carries the progress emitter and cancel check; a tool that
     * finishes in one step may ignore it. On success the
     * provider allocates `out_result_json` with `rac_alloc` and the caller
     * frees it. A tool that fails should still return RAC_SUCCESS with an
     * `error` key in the payload when the model can usefully see the failure;
     * reserve a non-success result for a tool that could not run at all.
     */
    rac_result_t (*execute)(const char* args_json, const rac_tool_context_t* ctx,
                            char** out_result_json, void* user_data);

    /**
     * Keys the run loop may read out of a successful result, NULL-terminated.
     *
     * This exists so commons stops hardcoding `summary` and `source_url` for
     * one known tool. A provider declares what it publishes and attribution
     * reads that instead. May be NULL when nothing is published.
     */
    const char* const* published_keys;

    /** Drop this tool from the offered set after one successful call. */
    uint8_t single_use;

    /**
     * Whether the final turn after this tool ran should be grounded in the
     * tool's result: answer only from it, and cite it.
     *
     * This is what `tool_calling.cpp` currently derives from the literal name
     * `"search_web"`. A tool that returns evidence declares it here instead of
     * commons knowing one tool by name.
     */
    uint8_t grounds_answer;

    /** Passed back to `execute`. May be NULL. */
    void* user_data;

    /** Reserved; must be zero. */
    uint8_t reserved[6];
} rac_tool_provider_t;

/**
 * @brief Register a tool provider.
 *
 * Idempotent by `name`: registering the same name twice replaces the earlier
 * provider, so a binding can override a commons tool without unregistering.
 */
RAC_API rac_result_t rac_tool_provider_register(const rac_tool_provider_t* provider);

/** @brief Remove a provider by name. Returns RAC_ERROR_NOT_FOUND when absent. */
RAC_API rac_result_t rac_tool_provider_unregister(const char* name);

/** @brief Look up a provider by name, or NULL. */
RAC_API const rac_tool_provider_t* rac_tool_provider_find(const char* name);

/**
 * @brief Number of registered providers.
 *
 * With `rac_tool_provider_at`, lets the run loop offer every commons tool
 * without the host enumerating them.
 */
RAC_API size_t rac_tool_provider_count(void);

/** @brief Provider at `index`, or NULL when out of range. */
RAC_API const rac_tool_provider_t* rac_tool_provider_at(size_t index);

#ifdef __cplusplus
}  // extern "C"
#endif
// NOLINTEND(modernize-redundant-void-arg,modernize-use-nullptr)

#endif  // RAC_PLUGIN_TOOL_PROVIDER_H
