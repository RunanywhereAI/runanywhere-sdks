/**
 * @file rac_device_identity.h
 * @brief Persistent device-identity resolution.
 *
 * Centralizes the chain that every platform SDK previously reimplemented:
 *   Keychain / Android Keystore-backed storage / localStorage cache
 *     -> platform vendor ID (e.g. UIDevice.identifierForVendor on iOS)
 *     -> freshly synthesized RFC-4122 v4 UUID
 *
 * The resolved value is written back into secure storage via the platform
 * adapter's secure_set callback so subsequent boots short-circuit on the
 * cache hit. This mirrors Swift's DeviceIdentity.persistentUUID semantics.
 */

#ifndef RAC_DEVICE_IDENTITY_H
#define RAC_DEVICE_IDENTITY_H

#include <stddef.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Minimum buffer size (incl. NUL terminator) accepted by
 * rac_device_get_or_create_persistent_id(). Mirrors the canonical 36-char
 * RFC-4122 form ("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx") plus a trailing NUL.
 */
#define RAC_DEVICE_ID_BUFFER_MIN_SIZE 37u

/**
 * Resolves the persistent device identifier, walking a fixed chain:
 *
 *   1. adapter.secure_get("device_id")
 *      -> if found and non-empty, return it (no other path is consulted).
 *   2. adapter.get_vendor_id (if non-NULL)
 *      -> use the returned UUID, write it back via secure_set, return it.
 *   3. Synthesize a fresh RFC-4122 v4 UUID, write it back via secure_set,
 *      return it.
 *
 * The resolved value is written into @p out as a NUL-terminated UTF-8 string.
 * @p out_size MUST be >= RAC_DEVICE_ID_BUFFER_MIN_SIZE; smaller buffers are
 * rejected before any platform-adapter callbacks are invoked.
 *
 * Concurrent calls are serialized internally. Every call revalidates durable
 * storage so a Keychain/Keystore failure or adapter reconfiguration cannot be
 * hidden by process-local state.
 *
 * @param out      Caller-provided output buffer.
 * @param out_size Capacity of @p out, must be >= RAC_DEVICE_ID_BUFFER_MIN_SIZE.
 * @return RAC_SUCCESS on success, RAC_ERROR_NULL_POINTER if @p out is NULL,
 *         RAC_ERROR_BUFFER_TOO_SMALL if @p out_size is below the minimum,
 *         RAC_ERROR_ADAPTER_NOT_SET if no platform adapter has been registered,
 *         or another error code propagated from the platform adapter.
 */
RAC_API rac_result_t rac_device_get_or_create_persistent_id(char* out, size_t out_size);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DEVICE_IDENTITY_H */
