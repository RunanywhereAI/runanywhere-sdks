/**
 * @file rac_directory_probe.h
 * @brief Error-aware classification of an ambiguous platform directory probe.
 *
 * Platform adapters that enumerate directories through APIs which hide stat
 * errors (Java's File.exists()/isDirectory()/listFiles() all return false or
 * null on permission and I/O failures) cannot tell "missing" from "unreadable"
 * on their own. After such a probe comes back empty-handed, call this to decide
 * which result code `rac_platform_adapter_t::file_list_directory` should return.
 *
 * Shared by the Kotlin SDK's JNI layer and the React Native Android bridge so
 * both apply the same rule. Getting it wrong lets orphan pruning clear the
 * registry state of a model folder that still exists.
 */

#ifndef RAC_DIRECTORY_PROBE_H
#define RAC_DIRECTORY_PROBE_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Classify a directory listing that the platform could not produce.
 *
 * Re-probes @p path with a stat that keeps its error:
 * - `RAC_ERROR_FILE_NOT_FOUND`: absence is confirmed (no such file or
 *   directory, a path component is not a directory, or the path exists but is
 *   not a directory).
 * - `RAC_ERROR_FILE_READ_FAILED`: inconclusive. Permission or I/O errors, and an
 *   existing directory (it may have become readable since the platform probe),
 *   so callers keep any registered path until a later refresh.
 * - `RAC_ERROR_INVALID_ARGUMENT`: @p path is NULL.
 *
 * @p path is UTF-8. On Windows it is strictly converted to UTF-16 before
 * probing, and malformed UTF-8 is inconclusive (READ_FAILED). On POSIX the
 * bytes are passed through unchanged, since file names there are byte strings.
 *
 * Never throws; safe to call across a JNI boundary.
 *
 * @param path Directory path the platform failed to list (UTF-8).
 * @return One of the codes above.
 */
RAC_API rac_result_t rac_classify_null_directory_listing(const char* path);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DIRECTORY_PROBE_H */
