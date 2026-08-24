/**
 * @file rac_agent_workflow.h
 * @brief RunAnywhere Commons — agent workflow runner public C ABI.
 *
 * A workflow is a user-drawn DAG of nodes that commons validates, orders, and
 * executes on-device. Documents, run state, and host callbacks are all
 * runanywhere.v1 messages from idl/agent_workflow.proto.
 *
 * This is deliberately separate from the Solutions runtime (rac_solution.h).
 * Solutions compiles a PipelineSpec into a GraphScheduler for continuous
 * streaming; the agent runner walks a DAG once per run, emits a state change
 * per node, and persists an inspectable record. Neither one calls the other.
 *
 * Two node types cannot execute inside commons: Tool Call needs the host's
 * tool registry, and Code needs a JavaScript engine. Both are supplied through
 * rac_agent_host_callbacks_t, the same inversion of control
 * rac_platform_adapter_t uses for file and network access. A workflow that
 * references either without callbacks registered fails the run rather than
 * failing to load.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md): every entry point below is
 * `SDK-facing default` over runanywhere.v1.WorkflowDocument / WorkflowList /
 * WorkflowValidationResult / WorkflowRunRequest / WorkflowRunRecord /
 * WorkflowRunEvent / ToolInvocation / CodeInvocation / NodePack / NodePackList
 * / WorkflowBundle / WorkflowBundleExportRequest / WorkflowBundleImportResult
 * bytes. Run handles are carried as `rac_handle_t` for uniform frontend FFI.
 */

#ifndef RAC_AGENT_WORKFLOW_H
#define RAC_AGENT_WORKFLOW_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

/** ABI version of rac_agent_host_callbacks_t. Bump on any layout change. */
#define RAC_AGENT_HOST_CALLBACKS_ABI_VERSION 1u

/**
 * @brief Execute one registered tool on behalf of a Tool Call node.
 *
 * Receives serialized runanywhere.v1.ToolInvocation bytes and must write
 * serialized ToolInvocationResult bytes into @p out_result.
 *
 * Called synchronously on the run's worker thread. The implementation must not
 * re-enter any rac_agent_* API.
 *
 * Returning non-success fails the node; reporting the failure inside
 * ToolInvocationResult.error is preferred because it carries a message the
 * canvas can show.
 */
typedef rac_result_t (*rac_agent_invoke_tool_fn)(const uint8_t* invocation_proto_bytes,
                                                 size_t invocation_proto_size,
                                                 rac_proto_buffer_t* out_result, void* user_data);

/**
 * @brief Evaluate a Code node's JavaScript in the host's engine.
 *
 * Receives serialized runanywhere.v1.CodeInvocation bytes and must write
 * serialized CodeInvocationResult bytes into @p out_result. Same threading and
 * re-entrancy contract as rac_agent_invoke_tool_fn.
 */
typedef rac_result_t (*rac_agent_evaluate_code_fn)(const uint8_t* invocation_proto_bytes,
                                                   size_t invocation_proto_size,
                                                   rac_proto_buffer_t* out_result, void* user_data);

/**
 * @brief Host-supplied implementations for the node types commons cannot run.
 *
 * Either slot may be NULL, which fails only the nodes that need it. Populate
 * @c abi_version and @c struct_size before calling
 * rac_agent_set_host_callbacks(); a mismatch is rejected with
 * RAC_ERROR_ABI_VERSION_MISMATCH.
 */
typedef struct {
    uint32_t abi_version;
    size_t struct_size;

    rac_agent_invoke_tool_fn invoke_tool;
    rac_agent_evaluate_code_fn evaluate_code;

    void* user_data;
} rac_agent_host_callbacks_t;

/**
 * @brief Install the host callback table. Replaces any previous registration.
 *
 * Passing NULL clears it. Callbacks are read at node-execution time, so a run
 * already in flight observes the change.
 *
 * @return RAC_SUCCESS, or RAC_ERROR_ABI_VERSION_MISMATCH when abi_version or
 *         struct_size does not match this build.
 */
RAC_API rac_result_t rac_agent_set_host_callbacks(const rac_agent_host_callbacks_t* callbacks);

/**
 * @brief Streamed run progress: one serialized runanywhere.v1.WorkflowRunEvent
 *        per call.
 *
 * Fires on the run's worker thread for every node state transition and for run
 * start and finish. The callback must not re-enter any rac_agent_* API.
 */
typedef void (*rac_agent_run_event_callback_fn)(const uint8_t* event_proto_bytes,
                                                size_t event_proto_size, void* user_data);

/**
 * @brief Persist a workflow from serialized runanywhere.v1.WorkflowDocument bytes.
 *
 * Writes through the platform adapter's file operations, so the document lands
 * wherever that adapter puts application data. Overwrites an existing document
 * with the same id and refreshes its updated_at_ms.
 *
 * The document is validated first; an invalid one is rejected with
 * RAC_ERROR_INVALID_CONFIGURATION and nothing is written.
 */
RAC_API rac_result_t rac_agent_workflow_save_proto(const uint8_t* document_proto_bytes,
                                                   size_t document_proto_size);

/**
 * @brief Load one workflow as serialized runanywhere.v1.WorkflowDocument bytes.
 *
 * @return RAC_SUCCESS, RAC_ERROR_NOT_FOUND when no such id is stored, or
 *         RAC_ERROR_DECODING_ERROR when the stored document is unreadable or
 *         carries a newer schema_version than this build understands.
 */
RAC_API rac_result_t rac_agent_workflow_load_proto(const char* workflow_id,
                                                   rac_proto_buffer_t* out_document);

/**
 * @brief List stored workflows as serialized runanywhere.v1.WorkflowList bytes.
 *
 * Unreadable documents are skipped rather than failing the whole listing, so a
 * single corrupt file cannot make the workflow list unopenable.
 */
RAC_API rac_result_t rac_agent_workflow_list_proto(rac_proto_buffer_t* out_list);

/**
 * @brief Delete a stored workflow and its run records.
 *
 * Deleting an id that is not stored is a success, so callers do not have to
 * check first.
 */
RAC_API rac_result_t rac_agent_workflow_delete(const char* workflow_id);

/**
 * @brief Validate a document without storing or running it.
 *
 * Writes serialized runanywhere.v1.WorkflowValidationResult bytes. Checks
 * duplicate node ids, edges naming unknown nodes or undeclared ports, cycles,
 * loop bodies referencing nodes outside the document, and expressions
 * referencing a node that does not precede the reader.
 *
 * A document that fails validation still returns RAC_SUCCESS: the verdict is
 * in the payload. A non-success return means validation could not run.
 */
RAC_API rac_result_t rac_agent_workflow_validate_proto(const uint8_t* document_proto_bytes,
                                                       size_t document_proto_size,
                                                       rac_proto_buffer_t* out_result);

/**
 * @brief Create a run from serialized runanywhere.v1.WorkflowRunRequest bytes.
 *
 * Loads and validates the referenced workflow, then returns a handle in the
 * created state. Nothing executes until rac_agent_run_start(). Destroy the
 * handle with rac_agent_run_destroy().
 *
 * @param event_callback Receives WorkflowRunEvent bytes; may be NULL to run
 *                       without progress reporting.
 */
RAC_API rac_result_t rac_agent_run_create_proto(const uint8_t* request_proto_bytes,
                                                size_t request_proto_size,
                                                rac_agent_run_event_callback_fn event_callback,
                                                void* user_data, rac_handle_t* out_run);

/**
 * @brief Begin executing the graph. Non-blocking.
 *
 * Nodes run in topological order; a node becomes runnable once every parent has
 * succeeded. The untaken branch of a Condition is marked skipped, which is not
 * a failure and does not stop the run.
 *
 * @return RAC_SUCCESS, RAC_ERROR_INVALID_HANDLE, or
 *         RAC_ERROR_ALREADY_INITIALIZED when the run already started.
 */
RAC_API rac_result_t rac_agent_run_start(rac_handle_t run);

/**
 * @brief Request cancellation. Non-blocking.
 *
 * The running node finishes or aborts at its next cancellation point, no
 * further nodes are scheduled, and the record closes as cancelled. Node outputs
 * already recorded are kept.
 */
RAC_API rac_result_t rac_agent_run_cancel(rac_handle_t run);

/**
 * @brief Read the current record as serialized runanywhere.v1.WorkflowRunRecord
 *        bytes.
 *
 * Valid at any point in the lifecycle. Mid-run it reflects progress so far,
 * which is what makes a run inspectable while it is still going.
 */
RAC_API rac_result_t rac_agent_run_record_proto(rac_handle_t run, rac_proto_buffer_t* out_record);

/**
 * @brief Cancel, join, and destroy the run. A null handle is a no-op.
 *
 * The record is persisted before the handle is released, so a destroyed run
 * stays readable through rac_agent_run_record_load_proto().
 */
RAC_API void rac_agent_run_destroy(rac_handle_t run);

/**
 * @brief Load a persisted record as serialized runanywhere.v1.WorkflowRunRecord
 *        bytes.
 *
 * @return RAC_SUCCESS, or RAC_ERROR_NOT_FOUND when that run id was never
 *         recorded for that workflow.
 */
RAC_API rac_result_t rac_agent_run_record_load_proto(const char* workflow_id, const char* run_id,
                                                     rac_proto_buffer_t* out_record);

/**
 * @brief Persist a node pack from serialized runanywhere.v1.NodePack bytes.
 *
 * Writes through the platform adapter's file operations, the same as
 * rac_agent_workflow_save_proto. Overwrites an existing pack with the same id.
 */
RAC_API rac_result_t rac_agent_pack_save_proto(const uint8_t* pack_proto_bytes,
                                               size_t pack_proto_size);

/**
 * @brief Load one node pack as serialized runanywhere.v1.NodePack bytes.
 *
 * @return RAC_SUCCESS, RAC_ERROR_NOT_FOUND when no such id is stored, or
 *         RAC_ERROR_DECODING_ERROR when the stored pack is unreadable.
 */
RAC_API rac_result_t rac_agent_pack_load_proto(const char* pack_id, rac_proto_buffer_t* out_pack);

/**
 * @brief List stored node packs as serialized runanywhere.v1.NodePackList bytes.
 *
 * Unreadable packs are skipped rather than failing the whole listing, same as
 * rac_agent_workflow_list_proto.
 */
RAC_API rac_result_t rac_agent_pack_list_proto(rac_proto_buffer_t* out_list);

/**
 * @brief Delete a stored node pack.
 *
 * Deleting an id that is not stored is a success, so callers do not have to
 * check first.
 */
RAC_API rac_result_t rac_agent_pack_delete(const char* pack_id);

/**
 * @brief Export workflows and the packs they reference as a serialized
 *        runanywhere.v1.WorkflowBundle.
 *
 * @p request_proto_bytes carries a serialized
 * runanywhere.v1.WorkflowBundleExportRequest naming which workflows to
 * export. Every node pack any of them references — transitively, through a
 * composite pack's own subgraph — is resolved and included automatically.
 *
 * @return RAC_SUCCESS, RAC_ERROR_NOT_FOUND when a named workflow id is not
 *         stored, or RAC_ERROR_INVALID_CONFIGURATION when the referenced
 *         packs contain a cycle.
 */
RAC_API rac_result_t rac_agent_bundle_export_proto(const uint8_t* request_proto_bytes,
                                                   size_t request_proto_size,
                                                   rac_proto_buffer_t* out_bundle);

/**
 * @brief Import a serialized runanywhere.v1.WorkflowBundle, saving every
 *        workflow and pack it carries.
 *
 * Writes serialized runanywhere.v1.WorkflowBundleImportResult bytes reporting
 * which items were imported and which were skipped and why. One invalid or
 * unsaveable item is dropped from the report rather than aborting the rest of
 * the import.
 *
 * @return RAC_SUCCESS once the bundle has been processed — even when every
 *         item was skipped — or RAC_ERROR_DECODING_ERROR when the bundle's
 *         format_version is newer than this build writes, refused before any
 *         item is touched.
 */
RAC_API rac_result_t rac_agent_bundle_import_proto(const uint8_t* bundle_proto_bytes,
                                                   size_t bundle_proto_size,
                                                   rac_proto_buffer_t* out_result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_AGENT_WORKFLOW_H */
