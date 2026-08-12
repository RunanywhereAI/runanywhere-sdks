/**
 * @file rac_solution.h
 * @brief RunAnywhere Commons — public C ABI for L5 solution runtime (T4.7).
 *
 * A "solution" is a prepackaged pipeline config (PipelineSpec or
 * SolutionConfig) that the core compiles into a GraphScheduler DAG and
 * runs. Front-ends interact with a solution through an opaque handle
 * and this ABI's start / stop / cancel / destroy verbs.
 *
 * The ABI is additive — existing voice-agent / RAG / LLM ABIs are
 * untouched. Two entry points are provided:
 *
 *   rac_solution_create_from_proto(bytes, len, &handle)
 *     Consumes a serialized SolutionConfig protobuf. Mandatory path —
 *     always available when the build has Protobuf support.
 *
 *   rac_solution_create_from_yaml(text, &handle)
 *     Consumes the YAML sugar shipped inside solution packages. The
 *     parser accepts a narrow YAML subset (block mappings, block
 *     sequences, scalars) sufficient for every field in
 *     pipeline.proto / solutions.proto; no external yaml-cpp dep.
 *
 * Both entry points produce the same `rac_solution_handle_t` type, so
 * callers that acquire a handle via one path can freely pass it to the
 * lifecycle verbs defined here.
 */

#ifndef RAC_SOLUTION_H
#define RAC_SOLUTION_H

#include <stddef.h>

#include "rac_error.h"
#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Opaque solution handle (owns a SolutionRunner internally). */
typedef void* rac_solution_handle_t;

/**
 * Construct a solution from a binary-encoded SolutionConfig.
 *
 * @param proto_bytes  Pointer to a serialized SolutionConfig message.
 * @param len          Byte length of the buffer.
 * @param out_handle   Receives the new solution handle on success.
 *
 * @return RAC_SUCCESS, RAC_ERROR_INVALID_ARGUMENT,
 *         RAC_ERROR_FEATURE_NOT_AVAILABLE (when Protobuf is disabled
 *         at build time), RAC_ERROR_DECODING_ERROR, or
 *         RAC_ERROR_INVALID_CONFIGURATION.
 */
RAC_API rac_result_t rac_solution_create_from_proto(const void*            proto_bytes,
                                                    size_t                 len,
                                                    rac_solution_handle_t* out_handle);

/**
 * Construct a solution from a YAML document. Accepts either a
 * SolutionConfig shape (oneof key at the top level) or a PipelineSpec
 * shape (top-level `name`/`operators`/`edges`) — the loader
 * disambiguates on the presence of `operators:`.
 *
 * @param yaml_text    NUL-terminated YAML document.
 * @param out_handle   Receives the new solution handle on success.
 *
 * @return RAC_SUCCESS or the same error codes as the proto entry
 *         point, plus RAC_ERROR_INVALID_FORMAT on a YAML parse error.
 */
RAC_API rac_result_t rac_solution_create_from_yaml(const char*            yaml_text,
                                                   rac_solution_handle_t* out_handle);

/**
 * Start the underlying scheduler. Non-blocking; worker threads run in
 * the background until `rac_solution_stop` / `rac_solution_cancel` is
 * called.
 *
 * @return RAC_SUCCESS, RAC_ERROR_INVALID_HANDLE, or
 *         RAC_ERROR_ALREADY_INITIALIZED.
 */
RAC_API rac_result_t rac_solution_start(rac_solution_handle_t handle);

/**
 * Request a graceful shutdown. Input edges are closed, workers drain
 * in-flight items, then exit. Non-blocking; follow with
 * `rac_solution_destroy` (which joins) to observe completion.
 */
RAC_API rac_result_t rac_solution_stop(rac_solution_handle_t handle);

/**
 * Force-cancel the graph. Every blocked push/pop returns within the
 * scheduler's cancellation deadline (~50 ms).
 */
RAC_API rac_result_t rac_solution_cancel(rac_solution_handle_t handle);

/**
 * Feed one item into the root input edge. Intended for pipelines with
 * an externally-driven source (e.g. microphone captures, file feeders,
 * tests). Payload is a NUL-terminated UTF-8 string.
 *
 * @return RAC_SUCCESS or RAC_ERROR_COMPONENT_NOT_READY if the solution
 *         has not been started.
 */
RAC_API rac_result_t rac_solution_feed(rac_solution_handle_t handle, const char* item);

/**
 * Close the root input edge. Signals end-of-stream so downstream
 * workers observe EOF and the scheduler drains naturally.
 */
RAC_API rac_result_t rac_solution_close_input(rac_solution_handle_t handle);

/**
 * Cancel, join, and destroy the solution. Always safe; a null handle
 * is a no-op.
 */
RAC_API void rac_solution_destroy(rac_solution_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_SOLUTION_H */
