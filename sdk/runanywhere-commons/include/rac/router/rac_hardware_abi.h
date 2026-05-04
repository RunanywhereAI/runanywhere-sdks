/**
 * @file rac_hardware_abi.h
 * @brief C ABI for hardware profile queries — proto-serialised results.
 *
 * All 5 SDK frontends need a cross-platform way to query the host hardware
 * profile and accelerator list.  The C ABI here returns proto-serialised
 * HardwareProfileResult bytes (idl/hardware_profile.proto) so that each
 * frontend can decode the payload with its own generated proto classes.
 *
 * Blocking item: CPP-blocked G-C6 (round 1 reports).
 */

#ifndef RAC_ROUTER_HARDWARE_ABI_H
#define RAC_ROUTER_HARDWARE_ABI_H

#include <cstddef>
#include <cstdint>

#include "rac/core/rac_types.h"
#include "rac/core/rac_error.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Query the hardware profile and return it as serialised proto bytes.
 *
 * Internally calls HardwareProfile::cached() (from rac_hardware_profile.h)
 * and serialises to HardwareProfileResult proto.  The caller MUST free the
 * returned buffer with rac_hardware_profile_free().
 *
 * Thread-safe (the underlying HardwareProfile::cached() is mutex-protected).
 *
 * @param proto_bytes_out  Output: allocated proto bytes.  Never NULL on success.
 * @param proto_size_out   Output: byte count.
 * @return RAC_SUCCESS or RAC_ERROR_OUT_OF_MEMORY / RAC_ERROR_GENERAL.
 */
RAC_API rac_result_t rac_hardware_profile_get(uint8_t** proto_bytes_out, size_t* proto_size_out);

/**
 * @brief Free the buffer returned by rac_hardware_profile_get().
 *
 * @param proto_bytes  Buffer to free (may be NULL — no-op).
 */
RAC_API void rac_hardware_profile_free(uint8_t* proto_bytes);

/**
 * @brief Query available accelerators as serialised HardwareProfileResult
 *        (only the accelerators field is populated; profile field is empty).
 *
 * Useful when callers only need the accelerator list without the full profile.
 *
 * @param proto_bytes_out  Output: allocated proto bytes.
 * @param proto_size_out   Output: byte count.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_hardware_get_accelerators(uint8_t** proto_bytes_out,
                                                   size_t* proto_size_out);

/**
 * @brief Set the accelerator preference for subsequent inference calls.
 *
 * @param preference_enum  AcceleratorPreference enum value (0=AUTO, 1=ANE,
 *                         2=GPU, 3=CPU — matches hardware_profile.proto).
 * @return RAC_SUCCESS or RAC_ERROR_INVALID_ARGUMENT.
 */
RAC_API rac_result_t rac_hardware_set_accelerator_preference(int preference_enum);

#ifdef __cplusplus
}
#endif

#endif /* RAC_ROUTER_HARDWARE_ABI_H */
